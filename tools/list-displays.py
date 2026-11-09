#!/usr/bin/env python3
"""List online displays (ID, vendor) via CoreGraphics. vdisplay uses vendor 0xeeee."""
import ctypes

cg = ctypes.cdll.LoadLibrary("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
cg.CGDisplayVendorNumber.restype = ctypes.c_uint32
cg.CGDisplayPixelsWide.restype = ctypes.c_size_t
cg.CGDisplayPixelsHigh.restype = ctypes.c_size_t
cg.CGDisplayIsMain.restype = ctypes.c_bool

ids = (ctypes.c_uint32 * 32)()
n = ctypes.c_uint32()
cg.CGGetOnlineDisplayList(32, ids, ctypes.byref(n))
for i in range(n.value):
    did = ids[i]
    vendor = cg.CGDisplayVendorNumber(did)
    tag = "  <- vdisplay" if vendor == 0xEEEE else ""
    main = " (main)" if cg.CGDisplayIsMain(did) else ""
    print(f"id={did:<4} vendor=0x{vendor:04x}  {cg.CGDisplayPixelsWide(did)}x{cg.CGDisplayPixelsHigh(did)}{main}{tag}")
