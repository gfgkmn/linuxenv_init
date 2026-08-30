#!/usr/bin/env python3
"""wolfram-mcp-proxy: lazy seat-holding proxy for the Wolfram MCP server.

The real server is one Wolfram kernel = one license seat, held for the whole
client session even when idle. This proxy answers cheap protocol traffic
(initialize / list / ping) from a cached snapshot and only spawns the kernel
when a request needs it, releasing it after an idle period.

On top of that it exposes three synthetic tools for explicit lease control,
so a model (or the user, in words) can pin the kernel while a stateful
computation session is in progress:

  WolframKernelHold     acquire the seat and suspend idle recycling (TTL lease)
  WolframKernelRelease  end the lease; by default also shut the kernel down
  WolframKernelStatus   report seat / lease / session state

Usage:
  wolfram-mcp-proxy.py             serve (stdio MCP)
  wolfram-mcp-proxy.py --snapshot  run the real server once, cache its lists

Env:
  MCP_SERVER_NAME             which built-in server (default WolframLanguage)
  WOLFRAM_LAZY_IDLE_SECONDS   idle timeout before the kernel is released (300)
"""

import json
import os
import signal
import subprocess
import sys
import threading
import time

BACKEND_CMD = [
    "/Applications/Wolfram.app/Contents/MacOS/wolfram",
    "-run", 'PacletSymbol["Wolfram/AgentTools","Wolfram`AgentTools`StartMCPServer"][]',
    "-noinit", "-noprompt",
]
SERVER_NAME = os.environ.get("MCP_SERVER_NAME", "WolframLanguage")
CACHE = os.path.expanduser(f"~/.claude/cache/wolfram-mcp-cache-{SERVER_NAME}.json")
IDLE = int(os.environ.get("WOLFRAM_LAZY_IDLE_SECONDS", "300"))
HANDSHAKE_TIMEOUT = 180
MAX_HOLD_MINUTES = 480

DEFAULT_INIT_PARAMS = {
    "protocolVersion": "2024-11-05",
    "capabilities": {},
    "clientInfo": {"name": "wolfram-lazy", "version": "1.1"},
}

SYNTH_TOOLS = [
    {
        "name": "WolframKernelHold",
        "description": (
            "Acquire the Wolfram kernel and suspend idle recycling for a while. "
            "Call this BEFORE a multi-step stateful computation (variables, "
            "session=... continuity), so the kernel is not recycled between "
            "your calls. The lease auto-expires; call again to renew."),
        "inputSchema": {"type": "object", "properties": {
            "minutes": {"type": "number",
                        "description": "Lease duration in minutes (default 30, max 480)."}}},
    },
    {
        "name": "WolframKernelRelease",
        "description": (
            "End the hold lease. By default also shuts the kernel down "
            "immediately, freeing the license seat (session state is lost). "
            "Pass shutdown=false to only end the lease and let the normal "
            "idle timeout take over."),
        "inputSchema": {"type": "object", "properties": {
            "shutdown": {"type": "boolean",
                         "description": "Also kill the kernel now (default true)."}}},
    },
    {
        "name": "WolframKernelStatus",
        "description": "Report kernel/seat state: running, held-until, idle policy.",
        "inputSchema": {"type": "object", "properties": {}},
    },
]
SYNTH_NAMES = {t["name"] for t in SYNTH_TOOLS}

log_lock = threading.Lock()
def log(*a):
    with log_lock:
        print(time.strftime("[%H:%M:%S]"), "wolfram-lazy:", *a, file=sys.stderr, flush=True)

def load_cache():
    try:
        return json.load(open(CACHE))
    except Exception:
        return {}

def save_cache(c):
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    json.dump(c, open(CACHE, "w"), indent=1)

def text_result(mid, text):
    return {"jsonrpc": "2.0", "id": mid,
            "result": {"content": [{"type": "text", "text": text}]}}


class Backend:
    """The real kernel: spawned on demand, killed when idle (unless held)."""

    def __init__(self, init_params, to_client):
        self.init_params = init_params
        self.to_client = to_client
        self.proc = None
        self.lock = threading.RLock()
        self.pending = set()
        self.last_used = time.time()
        self.hold_until = 0.0
        self.started_at = None
        self._hs_event = threading.Event()

    def alive(self):
        return self.proc is not None and self.proc.poll() is None

    def ensure(self):
        with self.lock:
            if self.alive():
                return True
            log("spawning kernel (seat acquired)")
            self.proc = subprocess.Popen(
                BACKEND_CMD, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL, env=os.environ.copy(),
                start_new_session=True)
            self.started_at = time.time()
            self._hs_event.clear()
            threading.Thread(target=self._pump, daemon=True).start()
            self._send({"jsonrpc": "2.0", "id": "__proxy_init__",
                        "method": "initialize", "params": self.init_params})
            if not self._hs_event.wait(HANDSHAKE_TIMEOUT):
                log("handshake timeout, killing kernel")
                self.stop()
                return False
            self._send({"jsonrpc": "2.0",
                        "method": "notifications/initialized", "params": {}})
            for rid, method in [("__proxy_tools__", "tools/list"),
                                ("__proxy_prompts__", "prompts/list"),
                                ("__proxy_resources__", "resources/list")]:
                self._send({"jsonrpc": "2.0", "id": rid, "method": method, "params": {}})
            self.last_used = time.time()
            return True

    def _send(self, msg):
        data = (json.dumps(msg) + "\n").encode()
        with self.lock:
            if self.proc and self.proc.stdin:
                try:
                    self.proc.stdin.write(data)
                    self.proc.stdin.flush()
                except BrokenPipeError:
                    log("backend stdin broken")

    def _pump(self):
        proc = self.proc
        for raw in proc.stdout:
            try:
                msg = json.loads(raw.decode("utf-8", "replace"))
            except Exception:
                continue
            mid = msg.get("id")
            if mid == "__proxy_init__":
                res = msg.get("result")
                if res:
                    c = load_cache(); c["initialize"] = res; save_cache(c)
                self._hs_event.set()
                continue
            if mid in ("__proxy_tools__", "__proxy_prompts__", "__proxy_resources__"):
                key = mid.strip("_").replace("proxy", "").strip("_")
                res = msg.get("result")
                if isinstance(res, dict):
                    c = load_cache(); c[key] = res; save_cache(c)
                continue
            if mid is not None:
                self.pending.discard(mid)
                self.last_used = time.time()
            self.to_client(msg)
        log("kernel exited (seat released)")

    def forward(self, msg):
        if not self.ensure():
            if msg.get("id") is not None:
                self.to_client({"jsonrpc": "2.0", "id": msg["id"], "error": {
                    "code": -32000,
                    "message": "Wolfram kernel failed to start (license seat unavailable?)"}})
            return
        if msg.get("id") is not None:
            self.pending.add(msg["id"])
        self.last_used = time.time()
        self._send(msg)

    def stop(self):
        with self.lock:
            if not self.proc:
                return
            pgid = None
            try:
                pgid = os.getpgid(self.proc.pid)
            except Exception:
                pass
            try:
                if pgid: os.killpg(pgid, signal.SIGTERM)
                else: self.proc.terminate()
            except Exception:
                pass
            time.sleep(1.5)
            try:
                if self.proc.poll() is None:
                    if pgid: os.killpg(pgid, signal.SIGKILL)
                    else: self.proc.kill()
            except Exception:
                pass
            self.proc = None
            self.pending.clear()
            self.started_at = None

    def reap_if_idle(self):
        with self.lock:
            if not self.alive() or self.pending:
                return
            if time.time() < self.hold_until:
                return                       # lease active: never recycle
            if time.time() - self.last_used > IDLE:
                log(f"idle {IDLE}s, releasing seat")
                self.stop()

    # ---- lease tools -------------------------------------------------------
    def tool_hold(self, mid, args):
        minutes = float(args.get("minutes") or 30)
        minutes = max(0.1, min(minutes, MAX_HOLD_MINUTES))
        if not self.ensure():
            self.to_client(text_result(mid, "FAILED: kernel could not start "
                                            "(license seat unavailable?)"))
            return
        self.hold_until = time.time() + minutes * 60
        until = time.strftime("%H:%M:%S", time.localtime(self.hold_until))
        log(f"hold: seat pinned for {minutes:g} min (until {until})")
        self.to_client(text_result(mid,
            f"Kernel held. Seat pinned and idle recycling suspended for "
            f"{minutes:g} minutes (until {until}). Session state will be "
            f"preserved across calls. Call WolframKernelHold again to renew, "
            f"or WolframKernelRelease when done."))

    def tool_release(self, mid, args):
        shutdown = args.get("shutdown", True)
        self.hold_until = 0.0
        if shutdown:
            was = self.alive()
            self.stop()
            log("release: lease ended, kernel shut down")
            self.to_client(text_result(mid,
                "Lease ended; kernel shut down and license seat freed."
                if was else "Lease ended; kernel was not running."))
        else:
            log("release: lease ended, idle policy resumes")
            self.to_client(text_result(mid,
                f"Lease ended. Kernel left running; it will be recycled after "
                f"{IDLE}s of inactivity."))

    def tool_status(self, mid):
        now = time.time()
        if self.alive():
            up = int(now - (self.started_at or now))
            if now < self.hold_until:
                lease = f"HELD until {time.strftime('%H:%M:%S', time.localtime(self.hold_until))}"
            else:
                left = max(0, int(IDLE - (now - self.last_used)))
                lease = f"idle policy active, recycle in ~{left}s if unused"
            state = f"kernel RUNNING (up {up}s, seat occupied); {lease}"
        else:
            state = "kernel NOT running (seat free); will spawn on next call"
        self.to_client(text_result(mid, state + f". Idle timeout: {IDLE}s."))


def snapshot():
    log("snapshot: starting real server once")
    be = Backend(DEFAULT_INIT_PARAMS, lambda m: None)
    if not be.ensure():
        log("snapshot FAILED"); return 1
    deadline = time.time() + 60
    while time.time() < deadline:
        c = load_cache()
        if all(k in c for k in ("initialize", "tools", "prompts", "resources")):
            break
        time.sleep(1)
    be.stop()
    log("snapshot done:", list(load_cache().keys()))
    return 0


def serve():
    out_lock = threading.Lock()
    def to_client(msg):
        with out_lock:
            sys.stdout.buffer.write((json.dumps(msg) + "\n").encode())
            sys.stdout.buffer.flush()

    client_init = dict(DEFAULT_INIT_PARAMS)
    be = Backend(client_init, to_client)

    def watchdog():
        while True:
            time.sleep(10)
            be.reap_if_idle()
    threading.Thread(target=watchdog, daemon=True).start()

    LIST_KEYS = {"tools/list": "tools", "prompts/list": "prompts",
                 "resources/list": "resources"}

    def serve_tools_list(mid):
        cache = load_cache()
        if "tools" not in cache:
            # cold path: pull the real list once, then serve it
            if be.ensure():
                deadline = time.time() + 30
                while time.time() < deadline and "tools" not in load_cache():
                    time.sleep(0.5)
                cache = load_cache()
        tools = list(cache.get("tools", {}).get("tools", []))
        to_client({"jsonrpc": "2.0", "id": mid,
                   "result": {"tools": tools + SYNTH_TOOLS}})

    for raw in sys.stdin.buffer:
        try:
            msg = json.loads(raw.decode("utf-8", "replace"))
        except Exception:
            continue
        method, mid = msg.get("method"), msg.get("id")
        cache = load_cache()

        if method == "initialize":
            client_init.clear(); client_init.update(msg.get("params") or DEFAULT_INIT_PARAMS)
            result = cache.get("initialize") or {
                "protocolVersion": client_init.get("protocolVersion", "2024-11-05"),
                "capabilities": {"tools": {}, "prompts": {}, "resources": {}},
                "serverInfo": {"name": "wolfram-lazy", "version": "1.1"}}
            to_client({"jsonrpc": "2.0", "id": mid, "result": result})
        elif method == "notifications/initialized":
            pass
        elif method == "ping":
            to_client({"jsonrpc": "2.0", "id": mid, "result": {}})
        elif method == "tools/list":
            serve_tools_list(mid)
        elif method == "tools/call" and (msg.get("params") or {}).get("name") in SYNTH_NAMES:
            name = msg["params"]["name"]
            args = msg["params"].get("arguments") or {}
            if name == "WolframKernelHold":
                be.tool_hold(mid, args)
            elif name == "WolframKernelRelease":
                be.tool_release(mid, args)
            else:
                be.tool_status(mid)
        elif method in LIST_KEYS and not be.alive():
            key = LIST_KEYS[method]
            if key in cache:
                to_client({"jsonrpc": "2.0", "id": mid, "result": cache[key]})
            else:
                be.forward(msg)
        elif method and method.startswith("notifications/") and not be.alive():
            pass
        else:
            be.forward(msg)

    log("client closed stdin, shutting down")
    be.stop()
    return 0


if __name__ == "__main__":
    sys.exit(snapshot() if "--snapshot" in sys.argv else serve())
