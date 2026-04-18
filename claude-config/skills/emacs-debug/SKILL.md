---
name: emacs-debug
description: Debug Emacs configuration and behavior via live introspection with `emacsclient --eval` instead of blindly grepping init files. Use when the user reports an Emacs problem (broken keybinding, wrong variable value, package not loading, mode misbehaving, elisp error, which-key/company/LSP misconfiguration) or mentions Emacs/Elisp debugging.
allowed-tools: Bash, Read, Grep, Glob
---

# Emacs Live Introspection

When debugging Emacs, **prefer live state over file source**. The running Emacs is authoritative; init files describe intent, which may differ from actual state due to hooks, advice, `custom-set-variables`, load order, package lazy-loading, or user interactive changes.

## Check that the server is up first

```bash
emacsclient --eval 't' 2>&1
```

If it errors, tell the user to `M-x server-start` (or confirm `(server-start)` is in their init). Do not fall back to file grep silently — ask the user.

## Core introspection commands

All use `emacsclient --eval '<sexp>'`. Use `(quote NAME)` form to avoid shell-quoting hell.

| Question | Command |
|---|---|
| Variable value | `emacsclient --eval '(symbol-value (quote VAR))'` |
| Is variable bound? | `emacsclient --eval '(boundp (quote VAR))'` |
| Function docstring | `emacsclient --eval '(documentation (quote FN))'` |
| Is function defined? | `emacsclient --eval '(fboundp (quote FN))'` |
| Function's actual body (post-advice) | `emacsclient --eval '(symbol-function (quote FN))'` |
| Keybindings for a command | `emacsclient --eval '(where-is-internal (quote FN) nil t)'` |
| Command bound to a key (in current buffer) | `emacsclient --eval '(key-binding (kbd "C-c x"))'` |
| Is package loaded? | `emacsclient --eval '(featurep (quote PKG))'` |
| Package file path | `emacsclient --eval '(find-library-name "LIBNAME")'` |
| Hook contents | `emacsclient --eval '(symbol-value (quote MODE-hook))'` |
| Active minor modes in current buffer | `emacsclient --eval '(with-current-buffer (window-buffer) minor-mode-list)'` |
| Recent `*Messages*` (last 2000 chars) | `emacsclient --eval '(with-current-buffer "*Messages*" (buffer-substring-no-properties (max (point-min) (- (point-max) 2000)) (point-max)))'` |
| Custom-set value | `emacsclient --eval '(get (quote VAR) (quote saved-value))'` |
| All advice on a function | `emacsclient --eval '(advice--p (advice--symbol-function (quote FN)))'` |

## Decision tree

1. **Live Emacs available?** → introspect first. File grep is a fallback, not the default.
2. **Live and file disagree?** → that IS the bug signal. Report both; the divergence usually points to the cause (hook clobbering a var, advice changing a function, wrong load order, `customize` overriding init.el).
3. **No live Emacs / user can't start server?** → offline inspection via:
   ```bash
   emacs --batch -l ~/.emacs.d/init.el --eval '(princ (symbol-value (quote VAR)))'
   ```
   Slower (full init load) but deterministic.

## What NOT to eval without asking

Same reversibility gate as `cooperation.md § Manual Trigger`. Read-only introspection is free; anything that mutates state needs user approval first:

- **Ask first**: `kill-emacs`, `save-buffers-kill-emacs`, `delete-file`, `write-region`, `(setq VAR ...)` for vars the user cares about, `package-delete`, `package-refresh-contents` (slow), `load-file` with arbitrary paths, anything calling shell commands via `shell-command` / `call-process`.
- **No ask needed**: `symbol-value`, `describe-*`, `boundp`, `fboundp`, `featurep`, `where-is-internal`, `documentation`, reading `*Messages*` or any buffer, inspecting keymaps, evaluating pure expressions into fresh temporaries.

## Reporting pattern

When you find the cause, report:
1. What the user saw (symptom).
2. What live introspection revealed (actual state).
3. What the init file says (intended state).
4. Where they diverge and why — name the mechanism (hook / advice / load order / customize override).
5. Minimal fix.

Do not propose an init.el edit before confirming the live state with `emacsclient --eval`. Silent file-only patches are the failure mode this skill exists to prevent.
