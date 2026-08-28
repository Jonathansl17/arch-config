#!/usr/bin/python3
# -*- coding: utf-8 -*-
"""Single-owner arbitration for the termclip clipboard backends.

X11/Wayland clipboards are owned by a live process, so `c.py`, `cc.py` and
`cpwd.py` must stay resident after setting the clipboard. Only the most
recent one is useful: this module terminates the previous owner (whichever
backend it was) and records the current process as the new one.
"""

import atexit
import os
import signal
import time

CACHE_DIR_ENV = "XDG_CACHE_HOME"
DEFAULT_CACHE_DIR = ".cache"
APP_CACHE_DIR = "termclip"
PIDFILE_NAME = "clipboard-owner.pid"
BACKEND_NAMES = ("c.py", "cc.py", "cpwd.py")
TERM_TIMEOUT_SECONDS = 1.0
POLL_INTERVAL_SECONDS = 0.02
PROC_CMDLINE = "/proc/{pid}/cmdline"
ENCODING = "utf-8"


def _pidfile_path() -> str:
    cache_root = os.environ.get(CACHE_DIR_ENV) or os.path.join(
        os.path.expanduser("~"), DEFAULT_CACHE_DIR
    )
    directory = os.path.join(cache_root, APP_CACHE_DIR)
    os.makedirs(directory, exist_ok=True)
    return os.path.join(directory, PIDFILE_NAME)


def _read_pid(path: str) -> int:
    try:
        with open(path, "r", encoding=ENCODING) as handle:
            return int(handle.read().strip())
    except (OSError, ValueError):
        return 0


def _is_termclip_backend(pid: int) -> bool:
    """Guard against killing an unrelated process that reused the PID."""
    try:
        with open(PROC_CMDLINE.format(pid=pid), "rb") as handle:
            cmdline = handle.read().decode(ENCODING, errors="replace")
    except OSError:
        return False
    return any(name in cmdline for name in BACKEND_NAMES)


def _terminate(pid: int) -> None:
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        return
    deadline = time.monotonic() + TERM_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        try:
            os.kill(pid, 0)
        except OSError:
            return
        time.sleep(POLL_INTERVAL_SECONDS)
    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        pass


def _write_pid(path: str, pid: int) -> None:
    tmp_path = "{path}.{pid}".format(path=path, pid=pid)
    with open(tmp_path, "w", encoding=ENCODING) as handle:
        handle.write(str(pid))
    os.replace(tmp_path, path)


def _release(path: str, pid: int) -> None:
    if _read_pid(path) == pid:
        try:
            os.remove(path)
        except OSError:
            pass


def claim_clipboard_owner() -> None:
    """Kill the previous termclip clipboard owner and become the current one."""
    path = _pidfile_path()
    previous = _read_pid(path)
    own_pid = os.getpid()
    if previous and previous != own_pid and _is_termclip_backend(previous):
        _terminate(previous)
    _write_pid(path, own_pid)
    atexit.register(_release, path, own_pid)
