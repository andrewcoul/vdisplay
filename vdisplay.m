// vdisplay — create a macOS virtual display via the private CGVirtualDisplay API.
// The display exists only while this process runs. Ctrl-C / SIGTERM removes it.
//
// Build: make   (or: clang -fobjc-arc -framework Foundation -framework CoreGraphics -framework IOKit vdisplay.m -o vdisplay)
// Usage: vdisplay [--width 3440] [--height 1440] [--hz 160] [--name "Virtual Display"] [--serial N] [--hidpi] [--keep-awake]
//
// SPDX-License-Identifier: MIT

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <signal.h>
#import <IOKit/pwr_mgt/IOPMLib.h>

// ---- Private CoreGraphics interfaces (undocumented; may change between macOS releases) ----
@class CGVirtualDisplay;

@interface CGVirtualDisplayDescriptor : NSObject
@property (retain, nonatomic) dispatch_queue_t queue;
@property (retain, nonatomic) NSString *name;
@property (nonatomic) unsigned int maxPixelsWide;
@property (nonatomic) unsigned int maxPixelsHigh;
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic) unsigned int serialNum;
@property (nonatomic) unsigned int productID;
@property (nonatomic) unsigned int vendorID;
@property (copy, nonatomic) void (^terminationHandler)(id, CGVirtualDisplay *);
@end

@interface CGVirtualDisplayMode : NSObject
@property (readonly, nonatomic) unsigned int width;
@property (readonly, nonatomic) unsigned int height;
@property (readonly, nonatomic) double refreshRate;
- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property (retain, nonatomic) NSArray<CGVirtualDisplayMode *> *modes;
@property (nonatomic) unsigned int hiDPI;
@end

@interface CGVirtualDisplay : NSObject
@property (readonly, nonatomic) unsigned int displayID;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end
// ------------------------------------------------------------------------------------------

static CGVirtualDisplay *gDisplay = nil;

static BOOL displayOnline(CGDirectDisplayID did) {
    CGDirectDisplayID ids[32]; uint32_t n = 0;
    if (CGGetOnlineDisplayList(32, ids, &n) != kCGErrorSuccess) return NO;
    for (uint32_t i = 0; i < n; i++) if (ids[i] == did) return YES;
    return NO;
}

static void usage(void) {
    fprintf(stderr,
            "usage: vdisplay [--width N] [--height N] [--hz N] [--name NAME] [--serial N] [--hidpi] [--keep-awake]\n"
            "  defaults: 3440x1440 @ 160Hz, name \"Virtual Display\"\n"
            "  --serial N  display serial number (must differ from any display still online)\n"
            "  --hidpi   offer a Retina mode (backing store is 2x the size)\n"
            "  --keep-awake  prevent display sleep while running (useful for streaming)\n");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {   // drained before the run loop starts, so only gDisplay retains the display
        unsigned int width = 3440, height = 1440;
        double hz = 160.0;
        BOOL hidpi = NO;
        BOOL keepAwake = NO;
        unsigned int serial = 1;
        NSString *name = @"Virtual Display";

        for (int i = 1; i < argc; i++) {
            NSString *a = [NSString stringWithUTF8String:argv[i]];
            BOOL hasNext = (i + 1 < argc);
            if ([a isEqualToString:@"--width"] && hasNext)       width = (unsigned)atoi(argv[++i]);
            else if ([a isEqualToString:@"--height"] && hasNext) height = (unsigned)atoi(argv[++i]);
            else if ([a isEqualToString:@"--hz"] && hasNext)     hz = atof(argv[++i]);
            else if ([a isEqualToString:@"--name"] && hasNext)   name = [NSString stringWithUTF8String:argv[++i]];
            else if ([a isEqualToString:@"--serial"] && hasNext) serial = (unsigned)atoi(argv[++i]);
            else if ([a isEqualToString:@"--hidpi"])             hidpi = YES;
            else if ([a isEqualToString:@"--keep-awake"])        keepAwake = YES;
            else { usage(); return [a isEqualToString:@"-h"] || [a isEqualToString:@"--help"] ? 0 : 2; }
        }
        if (width < 640 || height < 480 || hz < 1) { usage(); return 2; }

        unsigned int scale = hidpi ? 2 : 1;

        CGVirtualDisplayDescriptor *desc = [[CGVirtualDisplayDescriptor alloc] init];
        desc.queue = dispatch_queue_create("vdisplay.cg", DISPATCH_QUEUE_SERIAL);
        desc.name = name;
        desc.maxPixelsWide = width * scale;
        desc.maxPixelsHigh = height * scale;
        // Pretend to be a ~34" panel; macOS uses the physical size for DPI calculations.
        double diagMM = 34.0 * 25.4;
        double aspect = (double)width / (double)height;
        double hMM = diagMM / sqrt(1.0 + aspect * aspect);
        desc.sizeInMillimeters = CGSizeMake(hMM * aspect, hMM);
        desc.vendorID = 0xEEEE;
        desc.productID = 0x3440;
        desc.serialNum = serial;
        // Chromium also sets `serialNumber` (newer macOS reads it); set it if present.
        if ([desc respondsToSelector:NSSelectorFromString(@"setSerialNumber:")]) {
            [desc setValue:@(serial) forKey:@"serialNumber"];
        }
        desc.terminationHandler = nil;   // as Chromium does; the block can fire mid-exit and crash

        gDisplay = [[CGVirtualDisplay alloc] initWithDescriptor:desc];
        if (!gDisplay || gDisplay.displayID == 0) {
            fprintf(stderr, "vdisplay: failed to create virtual display "
                            "(serial %u already in use, API unavailable, or not in a GUI session)\n", serial);
            return 1;
        }

        // Offer the requested refresh plus common fallbacks at the same resolution.
        NSMutableArray<CGVirtualDisplayMode *> *modes = [NSMutableArray array];
        NSMutableOrderedSet<NSNumber *> *rates = [NSMutableOrderedSet orderedSetWithObject:@(hz)];
        for (NSNumber *r in @[@144, @120, @100, @60]) if (r.doubleValue < hz) [rates addObject:r];
        for (NSNumber *r in rates) {
            [modes addObject:[[CGVirtualDisplayMode alloc] initWithWidth:width height:height refreshRate:r.doubleValue]];
        }

        CGVirtualDisplaySettings *settings = [[CGVirtualDisplaySettings alloc] init];
        settings.hiDPI = hidpi ? 1 : 0;
        settings.modes = modes;

        if (![gDisplay applySettings:settings]) {
            fprintf(stderr, "vdisplay: applySettings failed\n");
            return 1;
        }

        printf("vdisplay: created \"%s\" displayID=%u serial=%u  %ux%u @ %.0fHz%s\n",
               name.UTF8String, gDisplay.displayID, serial, width, height, hz, hidpi ? " (HiDPI)" : "");
        fflush(stdout);

        if (keepAwake) {
            IOPMAssertionID noSleep = 0;
            if (IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionLevelOn,
                                            CFSTR("vdisplay keep-awake"), &noSleep) == kIOReturnSuccess)
                printf("vdisplay: preventing display sleep while running\n");
            fflush(stdout);
        }

        // Clean shutdown on SIGINT/SIGTERM: release the object, then wait (up to 5 s)
        // until WindowServer has actually dropped the display before exiting.
        signal(SIGINT, SIG_IGN);
        signal(SIGTERM, SIG_IGN);
        int sigs[] = {SIGINT, SIGTERM};
        for (int k = 0; k < 2; k++) {
            dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, sigs[k], 0, dispatch_get_main_queue());
            dispatch_source_set_event_handler(src, ^{
                static BOOL closing = NO;
                if (closing) return;
                closing = YES;
                CGDirectDisplayID did = gDisplay.displayID;
                // WindowServer defers display reconfiguration while displays are asleep,
                // so a removal during display sleep leaves a ghost until the next wake.
                // Declaring user activity wakes the display system so the removal applies now.
                IOPMAssertionID act = 0;
                IOPMAssertionDeclareUserActivity(CFSTR("vdisplay teardown"), kIOPMUserActiveLocal, &act);
                __weak CGVirtualDisplay *weakDisplay = gDisplay;
                gDisplay = nil;
                printf("vdisplay: removing display %u\n", did);
                if (weakDisplay) fprintf(stderr, "vdisplay: object still retained after release\n");
                fflush(stdout);
                __block int tries = 0;
                dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
                dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                                          100 * NSEC_PER_MSEC, 10 * NSEC_PER_MSEC);
                dispatch_source_set_event_handler(t, ^{
                    BOOL gone = !displayOnline(did);
                    if (!gone && ++tries < 50) {
                        if (tries % 10 == 0) {   // re-poke every second in case it dozed off again
                            IOPMAssertionID a2 = 0;
                            IOPMAssertionDeclareUserActivity(CFSTR("vdisplay teardown"), kIOPMUserActiveLocal, &a2);
                        }
                        return;
                    }
                    if (gone) printf("vdisplay: display %u removed after %d ms\n", did, (tries + 1) * 100);
                    else fprintf(stderr, "vdisplay: display %u still online at exit\n", did);
                    fflush(stdout);
                    exit(gone ? 0 : 3);
                });
                dispatch_resume(t);
                CFBridgingRetain(t);
            });
            dispatch_resume(src);
            CFBridgingRetain(src);   // keep source alive
        }
    }
    CFRunLoopRun();   // real main run loop; also services the main dispatch queue
    return 0;
}
