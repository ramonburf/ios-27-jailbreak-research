#import <mach-o/dyld.h>
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>

int trigger_ane_direct(void);
void run_decmpfs_leak(const char *base_dir);
void log_from_c(const char* msg);
void run_iosurface_notify_probe(void);

// Cross-zone OOL reclaim spray for the socket-UAF harness (SockUafSpray.c).
#include <stddef.h>
int sockuaf_ool_spray(size_t size, int count, uint64_t fill);
void sockuaf_ool_reset(void);
int sockuaf_ool_count(void);

// Container-manager extension probe (see WQProbe.c).
#include <stdint.h>
int64_t wq_grant(const char *target, const char *group, uint64_t flags);
void wq_revoke(int64_t handle);
int wq_group_available(const char *group);
int64_t wq_token(const char *identifier, uint64_t cls, uint64_t part, uint64_t flags, const char *partDomain);

// CoW / external-object fault storm (SockUafSpray.c).
int cow_probe_run(int rounds, int size_kb, int *stages);
