"""Frames from the Mac's built-in camera only (never Continuity Camera)."""
import select
import subprocess

import cv2
import numpy as np

from . import config


class BuiltinCamera:
    def __init__(self):
        self.proc = None

    def open(self):
        if not config.BUILTIN_CAMERA.exists():
            return False
        try:
            self.proc = subprocess.Popen(
                [str(config.BUILTIN_CAMERA)], stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, bufsize=0,
            )
            return True
        except OSError:
            return False

    def _read_exact(self, size, timeout=1.5):
        data = bytearray()
        while len(data) < size and self.proc and self.proc.poll() is None:
            ready, _, _ = select.select([self.proc.stdout], [], [], timeout)
            if not ready:
                return None
            chunk = self.proc.stdout.read(size - len(data))
            if not chunk:
                return None
            data.extend(chunk)
        return bytes(data) if len(data) == size else None

    def read(self):
        header = self._read_exact(4)
        if header is None:
            return False, None
        size = int.from_bytes(header, "big")
        if size <= 0 or size > 8_000_000:
            return False, None
        payload = self._read_exact(size)
        if payload is None:
            return False, None
        frame = cv2.imdecode(np.frombuffer(payload, dtype=np.uint8), cv2.IMREAD_COLOR)
        return frame is not None, frame

    def release(self):
        if not self.proc:
            return
        self.proc.terminate()
        try:
            self.proc.wait(timeout=1)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait(timeout=1)
        self.proc = None
