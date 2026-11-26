// cc-bridge.ts — deliver Pi's events to the Emacs bridge.
//
// Pi has no hook files; an extension runs inside Pi and is told of its
// events.  This one turns four of them into the bridge's events:
//
//   before_agent_start (a user prompt)  -> prompt-submit
//   agent_settled                       -> stop
//   tool_call                           -> pretool
//   tool_execution_end                  -> posttool
//
// `agent_settled', not `agent_end': after `agent_end' Pi may still
// retry, compact or go on with queued messages.
//
// It also keeps a record of the running session, as Claude Code does in
// ~/.claude/sessions/: ~/.pi/agent/cc-bridge-sessions/<pid>.json with
// the session's id, file, folder and name, and after a turn how full
// the context is.  The bridge lists Pi's live sessions from these; Pi
// does not keep its session file open, so nothing else says which
// process runs which session.  The record is removed when Pi exits.
//
// The payload is written in the names the bridge reads (session_id,
// transcript_path, cwd, prompt, tool_name, tool_input) plus
// `"agent": "pi"', so the bridge needs no translation for Pi.
//
// Emacs is notified, never consulted: nothing here waits for Emacs,
// blocks a tool or changes what Pi does, and every failure is logged
// and dropped.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execFile } from "node:child_process";
import { randomUUID } from "node:crypto";
import { appendFileSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";

const LOG = "/tmp/cc-bridge-hook.log";
const FUNCTIONS: Record<string, string> = {
  "prompt-submit": "claude-code-bridge--on-prompt-submit-from-file",
  stop: "claude-code-bridge--on-stop-from-file",
  pretool: "claude-code-bridge--notify-pretool-from-file",
  posttool: "claude-code-bridge--on-posttool-from-file",
};

const RECORDS = join(process.env.PI_CODING_AGENT_DIR ?? join(homedir(), ".pi", "agent"),
                     "cc-bridge-sessions");
const RECORD = join(RECORDS, `${process.pid}.json`);

// Write what the bridge reads about this process's session.
function record(ctx: any) {
  try {
    const file = ctx.sessionManager.getSessionFile();
    if (!file) return;                       // an ephemeral session
    const usage = ctx.getContextUsage?.();
    const percent =
      typeof usage?.percent === "number" ? usage.percent
      : usage?.tokens != null && usage?.contextWindow ? (100 * usage.tokens) / usage.contextWindow
      : null;
    mkdirSync(RECORDS, { recursive: true });
    writeFileSync(RECORD, JSON.stringify({
      pid: process.pid,
      session_id: ctx.sessionManager.getSessionId(),
      transcript_path: file,
      cwd: ctx.cwd,
      name: ctx.sessionManager.getSessionName?.() ?? null,
      ctx_pct: percent,
      updated_at: Date.now(),
    }));
  } catch (err) {
    log("record", "error: " + String(err).slice(0, 200));
  }
}

function log(event: string, text: string) {
  try {
    const stamp = new Date().toISOString().replace(/\.\d+Z$/, "Z");
    appendFileSync(LOG, `${stamp} [pi/${event}] ${text}\n`);
  } catch {}
}

// The bridge's own kill switches, so one toggle covers every agent.
function switchedOff(sessionId: string): boolean {
  const dir = join(homedir(), ".claude");
  if (existsSync(join(dir, "cc-bridge-disabled-globally"))) return true;
  try {
    const ids = readFileSync(join(dir, "cc-bridge-disabled-uuids"), "utf8");
    return ids.split("\n").includes(sessionId);
  } catch {
    return false;
  }
}

// A Lisp string literal for TEXT.
function lisp(text: string): string {
  return '"' + text.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
}

function deliver(event: string, ctx: any, extra: Record<string, unknown> = {}) {
  try {
    const sessionId = ctx.sessionManager.getSessionId();
    if (!sessionId) return log(event, "no session id");
    if (switchedOff(sessionId)) return;
    if (process.env.SSH_CONNECTION)
      return log(event, "remote pi session: no transport to the local Emacs yet");
    const payload = {
      agent: "pi",
      hook_event_name: event,
      session_id: sessionId,
      transcript_path: ctx.sessionManager.getSessionFile() ?? null,
      cwd: ctx.cwd,
      ...extra,
    };
    // One file, which Emacs deletes when it has read it.  A directory
    // of its own would stay behind, empty, for every event.
    const file = join(tmpdir(), `cc-bridge-pi-payload.${randomUUID()}.json`);
    const json = JSON.stringify(payload);
    writeFileSync(file, json, { mode: 0o600, flag: "wx" });
    log(event, "fired: " + json.slice(0, 200));
    const fn = FUNCTIONS[event];
    const form =
      `(and (fboundp '${fn}) ` +
      `(${fn} ${lisp(file)} ${lisp(process.env.ITERM_SESSION_ID ?? "")}))`;
    execFile("emacsclient", ["--no-wait", "--eval", form], { timeout: 3000 }, (err) => {
      if (err) {
        log(event, "emacsclient call failed: " + String(err.message).slice(0, 120));
        try { rmSync(file, { force: true }); } catch {}
      }
    });
  } catch (err) {
    log(event, "error: " + String(err).slice(0, 200));
  }
}

export default function (pi: ExtensionAPI) {
  pi.on("session_start", async (_event, ctx) => record(ctx));
  pi.on("session_info_changed", async (_event, ctx) => record(ctx));
  pi.on("session_shutdown", async () => {
    try { rmSync(RECORD, { force: true }); } catch {}
  });
  pi.on("before_agent_start", async (event: any, ctx) => {
    record(ctx);
    if (event.messageType === "user") deliver("prompt-submit", ctx, { prompt: event.prompt });
  });
  pi.on("agent_settled", async (event: any, ctx) => {
    record(ctx);
    deliver("stop", ctx, { aborted: !!event.aborted });
  });
  pi.on("tool_call", async (event: any, ctx) => {
    deliver("pretool", ctx, { tool_name: event.toolName, tool_input: event.input });
  });
  pi.on("tool_execution_end", async (event: any, ctx) => {
    deliver("posttool", ctx, { tool_name: event.toolName, is_error: !!event.isError });
  });
}
