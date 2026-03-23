;;; claude-audit.el --- Minor mode for auditing Claude Code edits -*- lexical-binding: t; -*-

;;; Commentary:
;; Provides keybindings and UI for reviewing Claude Code edits.
;; Supports two transports:
;;   - emacsclient (local): activated via find-file-hook on "claude-audit-*" files
;;   - rmate (remote): activated via advice on rmate-server--open-buffer
;;
;; For Edit: opens original file + after version side by side.
;; For Write: opens the new file content with proper syntax.
;;
;; Two view modes:
;;   Diff view  — split: original (left) + after (right)
;;   Focus view — single window: after only, for editing
;;
;; Actions:
;;   C-c C-c  Approve
;;   C-c C-k  Reject
;;   C-c C-v  Toggle between diff view and focus view
;;   ]c       Next changed region (evil normal state)
;;   [c       Previous changed region (evil normal state)

;;; Code:

(require 'cl-lib)

(defvar-local claude-audit--original-hash nil
  "Hash of original buffer content for change detection.")

(defvar-local claude-audit--decision-file nil
  "Path to the decision file for this audit.")

(defvar-local claude-audit--original-buffer nil
  "Buffer showing the original file (for split view cleanup).")

(defvar-local claude-audit--original-file nil
  "Path to the original file (for restoring split view).")

(defvar-local claude-audit--change-positions nil
  "List of positions of changed regions in after buffer.")

(defvar-local claude-audit--view-mode 'diff
  "Current view mode: `diff' (split) or `focus' (single).")

;; rmate-specific state
(defvar-local claude-audit--is-rmate nil
  "Non-nil when this audit session uses rmate transport.")

(defvar-local claude-audit--rmate-conn nil
  "The rmate connection struct when auditing via rmate.")

(defvar-local claude-audit--remote-host nil
  "SSH host alias for the remote machine (e.g. 'xiyun2').")

(defvar-local claude-audit--remote-original-path nil
  "Absolute path of original file on remote machine.")

;; Sentinel for encoding decision in file content (rmate transport)
(defconst claude-audit--decision-sentinel "# __CLAUDE_AUDIT_DECISION__:"
  "Sentinel line prefix for encoding decision in file content.")

;; Background-only faces that preserve syntax highlighting
(defface claude-audit-added
  '((((background dark))  :background "#1a3a1a")
    (((background light)) :background "#ddffdd"))
  "Face for added/changed lines in after buffer. Background only."
  :group 'claude-audit)

(defface claude-audit-removed
  '((((background dark))  :background "#3a1a1a")
    (((background light)) :background "#ffdddd"))
  "Face for removed/changed lines in original buffer. Background only."
  :group 'claude-audit)

;; Word-level refinement faces (stronger highlight on exact changed words)
(defface claude-audit-added-refined
  '((((background dark))  :background "#2d5a2d")
    (((background light)) :background "#aaffaa"))
  "Face for exact changed words in after buffer."
  :group 'claude-audit)

(defface claude-audit-removed-refined
  '((((background dark))  :background "#5a2d2d")
    (((background light)) :background "#ffaaaa"))
  "Face for exact changed words in original buffer."
  :group 'claude-audit)

;; ── Decision ──────────────────────────────────────────────────────────────

(defun claude-audit--write-decision (decision)
  "Write DECISION string to the decision file (emacsclient transport)."
  (when claude-audit--decision-file
    (with-temp-file claude-audit--decision-file
      (insert decision "\n"))))

(defun claude-audit--rmate-decide (decision)
  "Send DECISION back via rmate protocol and close."
  (let ((rmate-buf (current-buffer))
        (orig-buf claude-audit--original-buffer))
    ;; 1. Prepend sentinel line to buffer content
    (goto-char (point-min))
    (insert (format "%s %s\n" claude-audit--decision-sentinel decision))
    ;; 2. Save via rmate FIRST (sends content including sentinel to remote)
    ;;    Must happen while we're still in the rmate buffer
    (when (fboundp 'rmate-server--save-current)
      (rmate-server--save-current))
    ;; 3. Clean up original buffer (TRAMP)
    (when (and orig-buf (buffer-live-p orig-buf))
      (with-current-buffer orig-buf
        (remove-overlays (point-min) (point-max) 'claude-audit t)
        (when (bound-and-true-p read-only-mode) (read-only-mode -1)))
      (kill-buffer orig-buf))
    ;; 4. Kill rmate buffer (sends close, unblocks rmate --wait on remote)
    (when (buffer-live-p rmate-buf)
      (with-current-buffer rmate-buf
        (set-buffer-modified-p nil)
        (kill-buffer rmate-buf)))
    (message "Audit decision: %s" decision)))

(defun claude-audit--cleanup-and-close ()
  "Clean up buffers and close the frame (emacsclient transport)."
  (when (and claude-audit--original-buffer
             (buffer-live-p claude-audit--original-buffer))
    (with-current-buffer claude-audit--original-buffer
      (remove-overlays (point-min) (point-max) 'claude-audit t)
      (read-only-mode -1))
    (kill-buffer claude-audit--original-buffer))
  (let ((frame (selected-frame)))
    (set-buffer-modified-p nil)
    (kill-buffer)
    (delete-frame frame)))

(defun claude-audit-approve ()
  "Approve the edit."
  (interactive)
  (let ((changed (not (equal (buffer-hash) claude-audit--original-hash))))
    (let ((decision (if changed "change" "approve")))
      (if claude-audit--is-rmate
          (claude-audit--rmate-decide decision)
        (save-buffer)
        (claude-audit--write-decision decision)
        (message (if changed "✅ Approved with changes" "✅ Approved"))
        (claude-audit--cleanup-and-close)))))

(defun claude-audit-reject ()
  "Reject the edit."
  (interactive)
  (if claude-audit--is-rmate
      (claude-audit--rmate-decide "reject")
    (claude-audit--write-decision "reject")
    (message "❌ Rejected")
    (claude-audit--cleanup-and-close)))

;; ── View toggle ──────────────────────────────────────────────────────────

(defun claude-audit-toggle-view ()
  "Toggle between diff view (split) and focus view (single window)."
  (interactive)
  ;; If we're in the original buffer, switch to the after buffer first
  (unless claude-audit-mode
    (let ((after-win (cl-find-if
                      (lambda (w)
                        (buffer-local-value 'claude-audit-mode (window-buffer w)))
                      (window-list))))
      (when after-win (select-window after-win))))
  ;; Simple check: multiple windows = diff view, single = focus view
  (if (> (count-windows) 1)
      (claude-audit--switch-to-focus)
    (claude-audit--switch-to-diff)))

(defun claude-audit--switch-to-focus ()
  "Switch to focus view: hide original, show only after buffer."
  (delete-other-windows)
  (setq claude-audit--view-mode 'focus)
  (claude-audit--update-header)
  (message "Focus view — edit freely"))

(defun claude-audit--switch-to-diff ()
  "Switch to diff view: restore split with original file."
  (unless (and claude-audit--original-file
               (or (not (file-remote-p claude-audit--original-file))
                   t)  ; TRAMP files: trust the path
               (file-exists-p claude-audit--original-file))
    (message "No original file to diff against")
    (cl-return-from claude-audit--switch-to-diff))
  (let ((after-buf (current-buffer))
        (orig-file claude-audit--original-file)
        (pos (point)))
    (delete-other-windows)
    (if (fboundp 'split-window-sensibly-by-orientation)
        (split-window-sensibly-by-orientation)
      (split-window-right))
    (save-selected-window
      (other-window 1)
      (find-file orig-file)
      (read-only-mode 1)
      (setq-local header-line-format
                  (propertize
                   (if (file-remote-p orig-file)
                       "  ORIGINAL (read-only, remote)"
                     "  ORIGINAL (read-only)")
                   'face '(:height 1.1 :weight bold :foreground "gray"))))
    ;; Update references
    (setq-local claude-audit--original-buffer
                (or (get-file-buffer orig-file)
                    (find-buffer-visiting orig-file)))
    ;; Re-highlight
    (let ((changes (claude-audit--compute-changes-auto orig-file after-buf)))
      (setq-local claude-audit--change-positions changes))
    (goto-char pos)
    (claude-audit--sync-scroll))
  (setq claude-audit--view-mode 'diff)
  (claude-audit--update-header)
  (message "Diff view — original | after"))

(defun claude-audit--update-header ()
  "Update header line based on current view mode."
  (let* ((view-label (if (eq claude-audit--view-mode 'diff) "DIFF" "FOCUS"))
         (transport (if claude-audit--is-rmate "rmate" "local")))
    (setq-local header-line-format
                (propertize
                 (format "  AUDIT [%s|%s]: [C-c C-c] ✅ Approve  [C-c C-k] ❌ Reject  [C-c C-v] Toggle  []c/[c] Nav"
                         view-label transport)
                 'face '(:height 1.1 :weight bold :foreground "cyan")))))

;; ── Scroll sync ──────────────────────────────────────────────────────────

(defun claude-audit--sync-scroll (&optional _window _start)
  "Sync scroll position between after and original buffers."
  (when (and (eq claude-audit--view-mode 'diff)
             claude-audit--original-buffer
             (buffer-live-p claude-audit--original-buffer))
    (let ((line (line-number-at-pos (window-start))))
      (save-selected-window
        (let ((win (get-buffer-window claude-audit--original-buffer)))
          (when win
            (with-selected-window win
              (goto-char (point-min))
              (forward-line (1- line))
              (set-window-start win (point)))))))))

(defun claude-audit--enable-scroll-sync ()
  "Enable scroll synchronization for the after buffer."
  (add-hook 'window-scroll-functions #'claude-audit--sync-scroll nil t))

;; ── Hunk navigation ──────────────────────────────────────────────────────

(defun claude-audit-next-change ()
  "Jump to the next changed region. Syncs both windows."
  (interactive)
  (let ((pos (point))
        (found nil))
    (dolist (region claude-audit--change-positions)
      (when (and (not found) (> region pos))
        (setq found region)))
    (if found
        (progn
          (goto-char found)
          (recenter)
          (claude-audit--sync-scroll))
      (message "No more changes below"))))

(defun claude-audit-prev-change ()
  "Jump to the previous changed region. Syncs both windows."
  (interactive)
  (let ((pos (point))
        (found nil))
    (dolist (region (reverse claude-audit--change-positions))
      (when (and (not found) (< region pos))
        (setq found region)))
    (if found
        (progn
          (goto-char found)
          (recenter)
          (claude-audit--sync-scroll))
      (message "No more changes above"))))

;; ── Change highlighting ──────────────────────────────────────────────────

(defun claude-audit--get-diff-hunks (file-a file-b)
  "Get list of changed line ranges using external diff on local files.
Returns list of (orig-start orig-count new-start new-count)."
  (let ((output (shell-command-to-string
                 (format "diff -u0 %s %s 2>/dev/null || true"
                         (shell-quote-argument file-a)
                         (shell-quote-argument file-b))))
        (hunks nil))
    (with-temp-buffer
      (insert output)
      (goto-char (point-min))
      (while (re-search-forward
              "^@@ -\\([0-9]+\\)\\(?:,\\([0-9]+\\)\\)? \\+\\([0-9]+\\)\\(?:,\\([0-9]+\\)\\)? @@"
              nil t)
        (let ((orig-start (string-to-number (match-string 1)))
              (orig-count (if (match-string 2) (string-to-number (match-string 2)) 1))
              (new-start (string-to-number (match-string 3)))
              (new-count (if (match-string 4) (string-to-number (match-string 4)) 1)))
          (push (list orig-start orig-count new-start new-count) hunks))))
    (nreverse hunks)))

(defun claude-audit--line-range-to-overlay (buf start count face)
  "Add overlay in BUF from line START spanning COUNT lines with FACE."
  (when (and (> count 0) (buffer-live-p buf))
    (with-current-buffer buf
      (save-excursion
        (goto-char (point-min))
        (forward-line (1- start))
        (let ((beg (point)))
          (forward-line count)
          (let ((ov (make-overlay beg (point))))
            (overlay-put ov 'face face)
            (overlay-put ov 'claude-audit t))
          beg)))))

(defun claude-audit--get-line-region (buf line-start count)
  "Get (beg . end) positions for COUNT lines starting at LINE-START in BUF."
  (with-current-buffer buf
    (save-excursion
      (goto-char (point-min))
      (forward-line (1- line-start))
      (let ((beg (point)))
        (forward-line count)
        (cons beg (point))))))

(defun claude-audit--refine-hunk (orig-buf orig-start orig-count
                                   after-buf new-start new-count)
  "Add word-level refinement overlays within a hunk."
  (require 'smerge-mode)
  (when (and (> orig-count 0) (> new-count 0)
             (buffer-live-p orig-buf) (buffer-live-p after-buf))
    (let* ((orig-region (claude-audit--get-line-region orig-buf orig-start orig-count))
           (after-region (claude-audit--get-line-region after-buf new-start new-count))
           (orig-text (with-current-buffer orig-buf
                        (buffer-substring-no-properties (car orig-region) (cdr orig-region))))
           (after-text (with-current-buffer after-buf
                         (buffer-substring-no-properties (car after-region) (cdr after-region)))))
      (condition-case nil
          (with-temp-buffer
            (insert orig-text)
            (let ((sep (point)))
              (insert after-text)
              (smerge-refine-regions
               (point-min) sep
               sep (point-max)
               nil nil
               '((face . claude-audit-removed-refined))
               '((face . claude-audit-added-refined)))
              (dolist (ov (overlays-in (point-min) (point-max)))
                (let* ((ov-beg (overlay-start ov))
                       (ov-end (overlay-end ov))
                       (ov-face (overlay-get ov 'face)))
                  (when ov-face
                    (if (< ov-beg sep)
                        (let ((real-beg (+ (car orig-region) (- ov-beg 1)))
                              (real-end (+ (car orig-region) (- ov-end 1))))
                          (let ((real-ov (make-overlay real-beg real-end orig-buf)))
                            (overlay-put real-ov 'face ov-face)
                            (overlay-put real-ov 'claude-audit t)))
                      (let ((real-beg (+ (car after-region) (- ov-beg sep)))
                            (real-end (+ (car after-region) (- ov-end sep))))
                        (let ((real-ov (make-overlay real-beg real-end after-buf)))
                          (overlay-put real-ov 'face ov-face)
                          (overlay-put real-ov 'claude-audit t)))))))))
        (error nil)))))

(defun claude-audit--apply-hunks (hunks orig-buf after-buf)
  "Apply hunk overlays and word-level refinement to both buffers.
Returns list of change positions in after-buf."
  (let ((changes nil))
    ;; Clear old overlays
    (with-current-buffer after-buf
      (remove-overlays (point-min) (point-max) 'claude-audit t))
    (when (and orig-buf (buffer-live-p orig-buf))
      (with-current-buffer orig-buf
        (remove-overlays (point-min) (point-max) 'claude-audit t)))
    ;; Apply per-hunk
    (dolist (hunk hunks)
      (let ((orig-start (nth 0 hunk))
            (orig-count (nth 1 hunk))
            (new-start (nth 2 hunk))
            (new-count (nth 3 hunk)))
        (when (> new-count 0)
          (let ((pos (claude-audit--line-range-to-overlay
                      after-buf new-start new-count 'claude-audit-added)))
            (when pos (push pos changes))))
        (when (and orig-buf (> orig-count 0))
          (claude-audit--line-range-to-overlay
           orig-buf orig-start orig-count 'claude-audit-removed))
        (when orig-buf
          (claude-audit--refine-hunk
           orig-buf orig-start orig-count
           after-buf new-start new-count))))
    (nreverse changes)))

(defun claude-audit--compute-changes-from-buffers (orig-buf after-buf)
  "Compare two buffers by writing to local temp files and running diff.
Works for any buffer (rmate virtual buffers, TRAMP buffers, local files)."
  (let ((orig-tmp (make-temp-file "claude-audit-orig-"))
        (after-tmp (make-temp-file "claude-audit-after-")))
    (unwind-protect
        (progn
          (with-current-buffer orig-buf
            (write-region (point-min) (point-max) orig-tmp nil 'silent))
          (with-current-buffer after-buf
            (write-region (point-min) (point-max) after-tmp nil 'silent))
          (let ((hunks (claude-audit--get-diff-hunks orig-tmp after-tmp)))
            (claude-audit--apply-hunks hunks orig-buf after-buf)))
      (delete-file orig-tmp nil)
      (delete-file after-tmp nil))))

(defun claude-audit--compute-changes-from-files (original-file after-buffer)
  "Compare local files using external diff (emacsclient transport)."
  (let* ((after-file (file-truename (buffer-file-name after-buffer)))
         (original-file (file-truename original-file))
         (hunks (claude-audit--get-diff-hunks original-file after-file))
         (orig-buf (or (get-file-buffer original-file)
                       (cl-find-if (lambda (b)
                                     (when-let ((fn (buffer-file-name b)))
                                       (string= (file-truename fn) original-file)))
                                   (buffer-list)))))
    (claude-audit--apply-hunks hunks orig-buf after-buffer)))

(defun claude-audit--compute-changes-auto (original-file after-buffer)
  "Choose the right diff method based on transport."
  (if (or claude-audit--is-rmate
          (not (buffer-file-name after-buffer))
          (file-remote-p (or original-file "")))
      ;; Buffer-based diff (rmate, TRAMP, or no file-name)
      (let ((orig-buf (or claude-audit--original-buffer
                          (get-file-buffer original-file)
                          (find-buffer-visiting original-file))))
        (if (and orig-buf (buffer-live-p orig-buf))
            (claude-audit--compute-changes-from-buffers orig-buf after-buffer)
          nil))
    ;; File-based diff (local emacsclient)
    (claude-audit--compute-changes-from-files original-file after-buffer)))

(defun claude-audit--refresh-highlights ()
  "Re-compute diff highlights after the after buffer is saved."
  (when (and claude-audit-mode claude-audit--original-file)
    (let ((changes (claude-audit--compute-changes-auto
                    claude-audit--original-file (current-buffer))))
      (setq-local claude-audit--change-positions changes))))

;; ── Keymap & mode ────────────────────────────────────────────────────────

(defvar claude-audit-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'claude-audit-approve)
    (define-key map (kbd "C-c C-k") #'claude-audit-reject)
    (define-key map (kbd "C-c C-v") #'claude-audit-toggle-view)
    map)
  "Keymap for `claude-audit-mode'.")

(define-minor-mode claude-audit-mode
  "Minor mode for auditing Claude Code edits.

\\{claude-audit-mode-map}"
  :lighter " Audit"
  :keymap claude-audit-mode-map
  (when claude-audit-mode
    (setq-local claude-audit--original-hash (buffer-hash))
    ;; Decision file only for emacsclient transport
    (when buffer-file-name
      (setq-local claude-audit--decision-file
                  (concat buffer-file-name ".decision"))
      (when (file-exists-p claude-audit--decision-file)
        (delete-file claude-audit--decision-file)))
    ;; Evil keybindings — override all major mode conflicts
    (when (bound-and-true-p evil-mode)
      (evil-define-key* '(normal motion insert) claude-audit-mode-map
        (kbd "]c") #'claude-audit-next-change
        (kbd "[c") #'claude-audit-prev-change
        (kbd "C-c C-c") #'claude-audit-approve
        (kbd "C-c C-k") #'claude-audit-reject
        (kbd "C-c C-v") #'claude-audit-toggle-view)
      (evil-make-overriding-map claude-audit-mode-map 'normal)
      (evil-make-overriding-map claude-audit-mode-map 'insert)
      (evil-normalize-keymaps))
    ;; Auto-refresh diff highlights after save (local files only)
    (when buffer-file-name
      (add-hook 'after-save-hook #'claude-audit--refresh-highlights nil t))
    (claude-audit--update-header)
    (goto-char (point-min))))

;; ── Activation: emacsclient (find-file-hook) ────────────────────────────

(defun claude-audit--maybe-activate ()
  "Activate `claude-audit-mode' for audit files opened via emacsclient."
  (when (and buffer-file-name
             (string-match-p "claude-audit-"
                             (file-name-nondirectory buffer-file-name)))
    (claude-audit-mode 1)))

(add-hook 'find-file-hook #'claude-audit--maybe-activate)

;; ── Activation: rmate (advice on rmate-server--open-buffer) ─────────────

(defun claude-audit--rmate-maybe-activate (conn)
  "Check if CONN is a claude-audit session and activate audit mode.
Called as :after advice on `rmate-server--open-buffer'."
  (let ((display-name (and (fboundp 'rmate-server--conn-display-name)
                           (rmate-server--conn-display-name conn))))
    (when (and display-name (string-prefix-p "claude-audit||" display-name))
      ;; Parse: claude-audit||hostname||ip||original_path||tool_name
      (let* ((parts (split-string display-name "||"))
             (hostname (nth 1 parts))
             (ip (nth 2 parts))
             (original-path (nth 3 parts))
             (tool-name (nth 4 parts))
             (buf-name (rmate-server--conn-buffer-name conn))
             (buf (get-buffer buf-name)))
        (when buf
          (with-current-buffer buf
            ;; Resolve SSH alias from IP or hostname
            (let ((ssh-alias
                   (or (and (fboundp 'gfgkmn/ssh-get-host-for-hostname)
                            (car (gfgkmn/ssh-get-host-for-hostname ip)))
                       (and (fboundp 'gfgkmn/ssh-get-host-for-hostname)
                            (car (gfgkmn/ssh-get-host-for-hostname hostname)))
                       hostname)))
              (setq-local claude-audit--is-rmate t)
              (setq-local claude-audit--rmate-conn conn)
              (setq-local claude-audit--remote-host ssh-alias)
              (setq-local claude-audit--remote-original-path original-path)
              ;; Activate audit mode
              (claude-audit-mode 1)
              ;; Override C-x C-s to use rmate save + refresh highlights
              (local-set-key (kbd "C-x C-s")
                             (lambda ()
                               (interactive)
                               (when (fboundp 'rmate-server--save-current)
                                 (rmate-server--save-current))
                               (claude-audit--refresh-highlights)))
              ;; For Edit/MultiEdit, open split view with original via TRAMP
              (when (and (member tool-name '("Edit" "MultiEdit"))
                         original-path
                         (not (string-empty-p original-path)))
                (claude-audit--rmate-open-split ssh-alias original-path)))))))))

(with-eval-after-load 'rmate
  (advice-add 'rmate-server--open-buffer :after
              (lambda (conn) (claude-audit--rmate-maybe-activate conn))))

;; ── Split view: rmate (TRAMP original) ──────────────────────────────────

(defun claude-audit--rmate-open-split (ssh-alias remote-path)
  "Open split view with remote original file via TRAMP."
  (let* ((tramp-method (or (bound-and-true-p tramp-default-method) "sshx"))
         (tramp-path (format "/%s:%s:%s" tramp-method ssh-alias remote-path))
         (after-buf (current-buffer)))
    (delete-other-windows)
    ;; Split: after stays in current window
    (if (fboundp 'split-window-sensibly-by-orientation)
        (split-window-sensibly-by-orientation)
      (split-window-right))
    ;; Open original via TRAMP in the other window
    (save-selected-window
      (other-window 1)
      (find-file tramp-path)
      (read-only-mode 1)
      (setq-local header-line-format
                  (propertize
                   "  ORIGINAL (read-only, remote)"
                   'face '(:height 1.1 :weight bold :foreground "gray"))))
    ;; Update references in after buffer
    (setq-local claude-audit--original-buffer (find-buffer-visiting tramp-path))
    (setq-local claude-audit--original-file tramp-path)
    (setq-local claude-audit--view-mode 'diff)
    ;; Enable scroll sync
    (claude-audit--enable-scroll-sync)
    ;; Compute and highlight changes
    (let ((changes (claude-audit--compute-changes-auto tramp-path after-buf)))
      (setq-local claude-audit--change-positions changes)
      (when changes
        (goto-char (car changes))
        (recenter)
        (claude-audit--sync-scroll)))))

;; ── Split view: emacsclient (local files) ───────────────────────────────

(defun claude-audit-open-split (original-file after-file)
  "Open ORIGINAL-FILE and AFTER-FILE side by side for audit.
AFTER-FILE gets `claude-audit-mode'. ORIGINAL-FILE is read-only.
Changed regions are highlighted. Scroll is synced."
  (delete-other-windows)
  ;; Open original on the left
  (find-file original-file)
  (read-only-mode 1)
  (setq-local header-line-format
              (propertize
               "  ORIGINAL (read-only)"
               'face '(:height 1.1 :weight bold :foreground "gray")))
  (let ((orig-buf (current-buffer)))
    ;; Split
    (if (fboundp 'split-window-sensibly-by-orientation)
        (split-window-sensibly-by-orientation)
      (split-window-right))
    (other-window 1)
    (find-file after-file)
    ;; claude-audit-mode auto-activates via find-file-hook
    (setq-local claude-audit--original-buffer orig-buf)
    (setq-local claude-audit--original-file (file-truename original-file))
    (setq-local claude-audit--view-mode 'diff)
    ;; Enable scroll sync
    (claude-audit--enable-scroll-sync)
    ;; Compute and highlight changes
    (let ((changes (claude-audit--compute-changes-auto original-file (current-buffer))))
      (setq-local claude-audit--change-positions changes)
      (when changes
        (goto-char (car changes))
        (recenter)
        (claude-audit--sync-scroll)))))

(provide 'claude-audit)
;;; claude-audit.el ends here
