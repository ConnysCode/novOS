#!/usr/bin/env python3
"""Writes live video frames to shared memory for the panel.

libvtcapture reads along with the picture on screen. libvt must not be used for
this: it turns the HDMI picture black while it runs. The process is separate
from surface-manager, so a failure here cannot touch the TV interface.

The panel starts it and renews the lease file while it is open. Without a fresh
lease the process ends by itself, even if surface-manager crashed.

Usage: vt-feed.py <lease-file>
"""

import ctypes as C
import mmap
import os
import signal
import struct
import sys
import time

FRAME_PATH = "/tmp/novos-video-frame"
WIDTH, HEIGHT = 480, 270
# 50 frames overload the interface: only 43 to 48 reach the panel. 25 hold steady
# and look the same behind this much blur.
FRAMERATE = 25
FRAME_INTERVAL = 1.0 / FRAMERATE
LEASE_SECONDS = 3
MAX_SECONDS = 3600
HANG_SECONDS = 8
DISPLAY_OUTPUT = 2
POLL_SECONDS = 0.006
MAGIC = 0x54564632
HEADER_BYTES = 16


class Properties(C.Structure):
    _fields_ = [("dump", C.c_int32), ("x", C.c_int16), ("y", C.c_int16),
                ("w", C.c_int16), ("h", C.c_int16), ("buffers", C.c_int32),
                ("framerate", C.c_int32)]


class PlaneInfo(C.Structure):
    _fields_ = [("stride", C.c_int32), ("plane", C.c_int16 * 4), ("active", C.c_int16 * 4)]


class BufferInfo(C.Structure):
    _fields_ = [("luma", C.c_void_p), ("chroma", C.c_void_p),
                ("luma_size", C.c_int32), ("chroma_size", C.c_int32)]


def load_library():
    vt = C.CDLL("libvtcapture.so.1")
    vt.vtCapture_create.restype = C.c_void_p
    vt.vtCapture_release.argtypes = [C.c_void_p]
    for name in ("init", "preprocess", "planeInfo"):
        getattr(vt, "vtCapture_" + name).argtypes = [C.c_void_p, C.c_void_p, C.c_void_p]
    for name in ("process", "currentCaptureBuffInfo", "stop", "postprocess", "finalize"):
        getattr(vt, "vtCapture_" + name).argtypes = [C.c_void_p, C.c_void_p]
    return vt


def create_frame_file(stride, height):
    """Replaces the file atomically. surface-manager may have the old one mapped,
    and shrinking a mapped file would crash it with SIGBUS."""
    frame_bytes = stride * height + stride * (height // 2)
    temporary = FRAME_PATH + ".new"
    with open(temporary, "wb") as file:
        file.truncate(HEADER_BYTES + frame_bytes)
    file = open(temporary, "r+b")
    shared = mmap.mmap(file.fileno(), HEADER_BYTES + frame_bytes)
    shared[0:HEADER_BYTES] = struct.pack("<IIII", MAGIC, 0, stride, height)
    os.rename(temporary, FRAME_PATH)
    return shared


def lease_is_fresh(path):
    try:
        return time.time() - os.stat(path).st_mtime < LEASE_SECONDS
    except OSError:
        return False


def main():
    lease = sys.argv[1]
    # The hard stop for a hanging libvtcapture call. Python cannot run a SIGTERM
    # handler while a native call blocks, so only the default SIGALRM action ends it.
    signal.alarm(HANG_SECONDS)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    vt = load_library()
    driver = vt.vtCapture_create()
    client = C.create_string_buffer(b"00", 128)
    if not driver or vt.vtCapture_init(driver, b"novos_video_feed", client):
        sys.exit("capture not available")
    frames = 0
    try:
        props = Properties(DISPLAY_OUTPUT, 0, 0, WIDTH, HEIGHT, 3, FRAMERATE)
        if vt.vtCapture_preprocess(driver, client, C.byref(props)):
            sys.exit("capture setup failed")
        plane = PlaneInfo()
        vt.vtCapture_planeInfo(driver, client, C.byref(plane))
        stride, height = plane.stride, plane.plane[3]
        shared = create_frame_file(stride, height)
        target = C.addressof(C.c_char.from_buffer(shared, HEADER_BYTES))
        luma_bytes = stride * height
        chroma_bytes = stride * (height // 2)
        if vt.vtCapture_process(driver, client):
            sys.exit("capture start failed")

        started = time.time()
        last = None
        next_frame = 0.0
        buffer = BufferInfo()
        while time.time() - started < MAX_SECONDS and lease_is_fresh(lease):
            signal.alarm(HANG_SECONDS)
            status = vt.vtCapture_currentCaptureBuffInfo(driver, C.byref(buffer))
            if status == 0 and buffer.luma and buffer.luma != last and time.time() >= next_frame:
                last = buffer.luma
                next_frame = time.time() + FRAME_INTERVAL - POLL_SECONDS
                C.memmove(target, buffer.luma, luma_bytes)
                C.memmove(target + luma_bytes, buffer.chroma, chroma_bytes)
                frames += 1
                shared[4:8] = struct.pack("<I", frames)
            time.sleep(POLL_SECONDS)
    finally:
        vt.vtCapture_stop(driver, client)
        vt.vtCapture_postprocess(driver, client)
        vt.vtCapture_finalize(driver, client)
        vt.vtCapture_release(driver)


if __name__ == "__main__":
    main()
