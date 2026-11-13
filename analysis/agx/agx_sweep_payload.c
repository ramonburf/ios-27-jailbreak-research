// AGXG18P external-method argument-shape sweep, executed inside the signed
// AGXProbe process via LLDB `expr -l c --`.
//
// Why this exists: the Swift probe's argument-shape matrix hardcoded
// `nil, 0` for the scalar input arguments, so the scalarInputCount axis was
// NEVER exercised -- while the static dispatch table shows most AGX entries
// declare scalarInputCount = 3.  This sweep walks the real space.
//
// Safety: every structure is zero-filled.  The OOB helper reads index from
// input[0] and ORs input[8..15] into object+0x18.  With an all-zero struct
// the index is 0 (in bounds) and the mask is 0 (no write), so even the
// selectors that reach the helper are benign.
//
// Results are written to $HOME/Documents/lldb_sweep.txt so they can be pulled
// with `pymobiledevice3 apps pull` without relying on stdout capture.

{
    extern char *getenv(const char *);
    extern int printf(const char *, ...);
    extern void *fopen(const char *, const char *);
    extern int fprintf(void *, const char *, ...);
    extern int fclose(void *);
    extern int snprintf(char *, unsigned long, const char *, ...);
    extern void *IOServiceMatching(const char *);
    extern int IOServiceGetMatchingService(int, void *, int *);
    extern int IOServiceOpen(int, int, unsigned int, int *);
    extern int IOConnectCallMethod(int, unsigned int, const void *, unsigned int,
                                    const void *, unsigned int, void *, unsigned int *,
                                    void *, unsigned int);
    extern int IOServiceClose(int);
    extern int IOObjectRelease(int);
    extern int mach_task_self_;

    char path[512];
    char *home = getenv("HOME");
    if (!home) { printf("AGXSWEEP: no HOME\n"); }
    snprintf(path, sizeof(path), "%s/Documents/lldb_sweep.txt", home ? home : "/tmp");
    void *f = fopen(path, "w");
    if (!f) { printf("AGXSWEEP: fopen failed for %s\n", path); }

    int svc = 0, conn = 0;
    int kr = IOServiceGetMatchingService(mach_task_self_,
                                         IOServiceMatching("AGXAcceleratorG18P"), &svc);
    if (f) fprintf(f, "# match kr=0x%x svc=%d\n", kr, svc);
    if (kr != 0 || svc == 0) {
        if (f) { fprintf(f, "# FAILED to find service\n"); fclose(f); }
        printf("AGXSWEEP: service lookup failed kr=0x%x\n", kr);
    } else {
        kr = IOServiceOpen(svc, mach_task_self_, 1, &conn);
        IOObjectRelease(svc);
        if (f) fprintf(f, "# open kr=0x%x conn=%d\n", kr, conn);

        if (kr == 0) {
            // stage 1: scalar input count x structure input size,
            // structure output size fixed at 0.
            unsigned char inbuf[1024];
            unsigned char outbuf[1024];
            unsigned long scalars[8];
            unsigned int outCnt;
            int hits = 0;
            for (unsigned sel = 0x100; sel <= 0x1ff; sel++) {
                for (unsigned sc = 0; sc <= 5; sc++) {
                    for (unsigned ss = 0; ss <= 0x100; ss += 4) {
                        for (unsigned i = 0; i < sizeof(inbuf); i++) inbuf[i] = 0;
                        for (unsigned i = 0; i < sizeof(outbuf); i++) outbuf[i] = 0;
                        for (unsigned i = 0; i < 8; i++) scalars[i] = 0;
                        outCnt = 256;
                        int r = IOConnectCallMethod(conn, sel,
                                                   sc ? (void *)scalars : (void *)0, sc,
                                                   (void *)inbuf, ss,
                                                   (void *)outbuf, &outCnt,
                                                   (void *)0, 0);
                        // 0xe00002c2 == kIOReturnBadArgument (wrong shape)
                        if ((unsigned)r != 0xe00002c2u) {
                            if (f) fprintf(f, "sel=0x%03x sc=%u ss=0x%02x kr=0x%08x outCnt=%u\n",
                                           sel, sc, ss, (unsigned)r, outCnt);
                            printf("AGXSWEEP sel=0x%03x sc=%u ss=0x%02x kr=0x%08x outCnt=%u\n",
                                   sel, sc, ss, (unsigned)r, outCnt);
                            hits++;
                        }
                    }
                }
            }
            if (f) fprintf(f, "# stage1 hits=%d\n", hits);
            printf("AGXSWEEP: stage1 done, hits=%d\n", hits);
            IOServiceClose(conn);
        }
        if (f) fclose(f);
    }
    printf("AGXSWEEP: wrote %s\n", path);
    0
}
