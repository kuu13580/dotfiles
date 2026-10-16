#!/usr/bin/env python3
"""claude を PTY 越しに起動し、alt screen 切替を止めて同じバッファに描かせる。

Windows Terminal でスナップ後に Agent View の一覧へ戻ると描画が崩れる件の回避用。
使い方: proxy.py [--log] [--keep-alt] [command ...]  (既定: claude agents)
"""
import argparse
import fcntl
import os
import pty
import re
import select
import signal
import struct
import sys
import termios
import time
import tty

ALT_MODES = {b"47", b"1047", b"1049"}
PRIVATE_MODE = re.compile(rb"\x1b\[\?([0-9;]+)([hl])")
# 末尾で切れた CSI ? ... を次の読み込みまで持ち越すため
PARTIAL_TAIL = re.compile(rb"\x1b(\[(\?[0-9;]*)?)?$")
CLEAR = b"\x1b[H\x1b[2J\x1b[3J"

LOG_PATH = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "claude-agents-proxy.log")


def get_winsize(fd):
    return fcntl.ioctl(fd, termios.TIOCGWINSZ, b"\0" * 8)


def set_winsize(fd, ws):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, ws)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", action="store_true", help="private mode の切替を ~/.cache/claude-agents-proxy.log に記録")
    ap.add_argument("--keep-alt", action="store_true", help="alt screen 切替を止めない(記録だけしたい時)")
    ap.add_argument("command", nargs=argparse.REMAINDER)
    args = ap.parse_args()
    cmd = args.command or ["claude", "agents"]

    if args.log:
        os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
    log = open(LOG_PATH, "a") if args.log else None

    def note(msg):
        if log:
            log.write(f"{time.strftime('%H:%M:%S')}.{int(time.time() * 1000) % 1000:03d} {msg}\n")
            log.flush()

    pid, master = pty.fork()
    if pid == 0:
        os.execvp(cmd[0], cmd)

    stdin = sys.stdin.fileno()
    stdout = sys.stdout.fileno()
    set_winsize(master, get_winsize(stdin))
    note(f"start pid={pid} cmd={cmd}")

    pending_redraw = [0.0]

    def nudge():
        # 切替で消えた画面を描き直させるため、1列縮めて戻す
        ws = get_winsize(stdin)
        rows, cols, x, y = struct.unpack("HHHH", ws)
        set_winsize(master, struct.pack("HHHH", rows, max(cols - 1, 1), x, y))
        os.kill(pid, signal.SIGWINCH)
        time.sleep(0.05)
        set_winsize(master, ws)
        os.kill(pid, signal.SIGWINCH)

    def on_winch(*_):
        ws = get_winsize(stdin)
        set_winsize(master, ws)
        os.kill(pid, signal.SIGWINCH)
        note("winch %dx%d" % struct.unpack("HHHH", ws)[:2])

    signal.signal(signal.SIGWINCH, on_winch)

    def filter_out(data):
        def repl(m):
            modes = m.group(1).split(b";")
            note(f"mode ?{m.group(1).decode()}{m.group(2).decode()}")
            if args.keep_alt or not ALT_MODES.intersection(modes):
                return m.group(0)
            pending_redraw[0] = time.monotonic() + 0.05
            rest = [x for x in modes if x not in ALT_MODES]
            out = CLEAR
            if rest:
                out += b"\x1b[?" + b";".join(rest) + m.group(2)
            return out

        return PRIVATE_MODE.sub(repl, data)

    old = termios.tcgetattr(stdin)
    tty.setraw(stdin)
    carry = b""
    try:
        while True:
            timeout = None
            if pending_redraw[0]:
                timeout = max(pending_redraw[0] - time.monotonic(), 0)
            try:
                r, _, _ = select.select([stdin, master], [], [], timeout)
            except InterruptedError:
                continue
            if pending_redraw[0] and time.monotonic() >= pending_redraw[0]:
                pending_redraw[0] = 0.0
                nudge()
            if stdin in r:
                data = os.read(stdin, 4096)
                if not data:
                    break
                os.write(master, data)
            if master in r:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    break
                if not data:
                    break
                data = carry + data
                m = PARTIAL_TAIL.search(data)
                carry = data[m.start():] if m else b""
                if m:
                    data = data[: m.start()]
                os.write(stdout, filter_out(data))
    finally:
        termios.tcsetattr(stdin, termios.TCSAFLUSH, old)
        note("exit")
    _, status = os.waitpid(pid, 0)
    sys.exit(os.waitstatus_to_exitcode(status))


if __name__ == "__main__":
    main()
