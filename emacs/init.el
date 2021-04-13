(setq user-init-file (or load-file-name (buffer-file-name)))
(setq user-emacs-directory (file-name-directory user-init-file))

;; about appearance and general settings

(tool-bar-mode -1)
;; ;; already disable by emacs-mac compile
(scroll-bar-mode -1)

(setq-default abbrev-mode t)
;; (setq mac-use-title-bar t)
;; ;; tocreate
;; (setq ns-pop-up-frames nil)

;; (setq inhibit-startup-screen t)
;; ;; disable default startup infomation screen

;; (setq-default left-margin-width 3 right-margin-width 3)

;; (set-fringe-mode '(6 . 6))
;; (set-face-attribute 'fringe nil
;;       :foreground (face-foreground 'default)
;;       :background (face-background 'default))

  
;; set gui's color theme
(add-to-list 'custom-theme-load-path (concat user-emacs-directory
                                             (convert-standard-filename "themes")))

(global-display-line-numbers-mode)
(setq display-line-numbers-type t)
(setq display-line-numbers-type 'relative)

;; where to backup files.
(setq backup-directory-alist `(("" . ,(concat user-emacs-directory
                                              (convert-standard-filename "emacs-backup")))))
(add-to-list 'load-path
             (concat user-emacs-directory
                     (convert-standard-filename "elisp/")))

(setq-default indent-tabs-mode nil)
(setq-default tab-width 4)
(setq indent-line-function 'insert-tab)
(electric-indent-mode nil)

;; load package for you use
(require 'package)
(add-to-list 'package-archives '("melpa" . "http://melpa.org/packages/"))
(package-initialize)

(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(custom-safe-themes
   '("190a9882bef28d7e944aa610aa68fe1ee34ecea6127239178c7ac848754992df" default))
 '(package-selected-packages
   '(ivy doom-themes use-package org-roam-server org-roam helm projectile dashboard dash-at-point cnfonts vimrc-mode ein multiple-cursors htmlize company ob-async org-preview-html exec-path-from-shell ## relative-line-numbers general expand-region evil-surround markdown-mode markdown-mode+ evil-org neotree evil)))


(require 'evil)
(evil-mode t)
(require 'evil-surround)
(global-evil-surround-mode 1)

;; about org-mode support python
(org-babel-do-load-languages
  'org-babel-load-languages
  '((python . t) (R . t) (shell . t)))
(setq org-src-fontify-natively t)
(setq org-confirm-babel-evaluate nil)
(setq org-startup-folded nil)

(when (memq window-system '(mac ns x))
  (exec-path-from-shell-initialize))
(exec-path-from-shell-copy-env "PYTHONPATH")


;; define org-mode vim-style keymaping.
(add-to-list 'load-path "~/.emacs.d/plugins/evil-org-mode")
(require 'evil-org)


;; (use-package org-roam
;;   :ensure t
;;   :hook
;;   (after-init . org-roam-mode)
;;   :custom
;;   (org-roam-directory "/Users/gfgkmn/Documents/roamwiki/")
;;   :bind (:map org-roam-mode-map
;;               (("C-c n l" . org-roam)
;;                ("C-c n f" . org-roam-find-file)
;;                ("C-c n g" . org-roam-graph))
;;               :map org-mode-map
;;               (("C-c n i" . org-roam-insert))
;;               (("C-c n I" . org-roam-insert-immediate))))

;; (add-hook 'org-mode-hook (lambda () (setq truncate-lines nil)))

(if (display-graphic-p)
    (progn
      ;; (load-theme 'Amelie t)
      (use-package doom-themes
        :config
        ;; Global settings (defaults)
        (setq doom-themes-enable-bold t    ; if nil, bold is universally disabled
              doom-themes-enable-italic t) ; if nil, italics is universally disabled
        (load-theme 'doom-one t)

        ;; Enable flashing mode-line on errors
        (doom-themes-visual-bell-config)
        
        ;; Enable custom neotree theme (all-the-icons must be installed!)
        (doom-themes-neotree-config)
        ;; or for treemacs users
        (setq doom-themes-treemacs-theme "doom-colors") ; use the colorful treemacs theme
        (doom-themes-treemacs-config)
        
        ;; Corrects (and improves) org-mode's native fontification.
        (doom-themes-org-config))
      (menu-bar-mode -1)))

(setq org-roam-server-host "127.0.0.1"
      org-roam-server-port 9090
      org-roam-server-export-inline-images t
      org-roam-server-authenticate nil
      org-roam-server-network-label-truncate t
      org-roam-server-network-label-truncate-length 60
      org-roam-server-network-label-wrap-length 20)
;; (org-roam-server-mode)

(require 'general)
;; bind a key globally in normal state; keymaps must be quoted
(setq general-default-keymaps 'evil-normal-state-map)
;; defind key-binding in evil normal mode.

;; define gcc comment and uncomment line
(defun comment-or-uncomment-regionline()
  "Comments or uncomments the region or the current line if there's no active region."
  (interactive)
  (let (beg end)
    (if (region-active-p)
      (setq beg (region-beginning) end (region-end))
      (setq beg (line-beginning-position) end (line-end-position)))
    (comment-or-uncomment-region beg end)))

(setq leaderg "g")
(general-define-key :prefix leaderg
                    "c" 'comment-or-uncomment-regionline)

(setq leader-next "]")
(setq leader-backslash "\\")

(general-define-key :prefix leader-next
		    "b" 'next-buffer)

(general-define-key :prefix leader-backslash
		    "nt" 'neotree-toggle
            "be" 'ivy-switch-buffer
		    "re" 'eval-last-sexp
		    "ci" 'delete-other-windows
            "dd" 'dash-at-point)



(defun open_emacs ()
    (interactive)
    (find-file user-init-file))

(defun eval_emacs ()
    (interactive)
    (load-file user-init-file))


(general-define-key :prefix leader-backslash
		    "er" 'eval_emacs)

(general-define-key :prefix leader-backslash
		    "oi" 'open_emacs)

;; use recent file
(recentf-mode 1)
(setq recentf-max-menu-items 100)
(general-define-key :prefix leader-backslash
		    "vf" 'recentf-open-files)
;; (global-set-key "\C-x\ \C-r" 'recentf-open-files)

;; (global-visual-line-mode t)
;; (set-display-table-slot standard-display-table 'wrap ?\ )


(require 'yasnippet)
(yas-global-mode 1)

;; ;; tocreate
;; (electric-pair-mode 1)
;; (setq electric-pair-pairs '( (?\` . ?\`) ) )

(require 'ob-async)
;; acculerate org-mode ipython execute
(require 'ein)
;; about ipython notebook
(require 'vimrc-mode)
(require 'company)
(add-hook 'after-init-hook 'global-company-mode)


;; (add-to-list 'auto-mode-alist  '("\\.md\\'" . org-mode))
(add-to-list 'auto-mode-alist '("\\.vim\\(rc\\)?\\'" . vimrc-mode))
(setq x-select-enable-clipboard t)

(require 'cnfonts)
(cnfonts-enable)


(when (executable-find "ipython")
  (setq python-shell-interpreter "ipython"))

(require 'all-the-icons)

(require 'dashboard)
(dashboard-setup-startup-hook)
;; Set the title
(setq dashboard-banner-logo-title "Welcome to Emacs Dashboard")
;; Set the banner
(setq dashboard-startup-banner "/Users/gfgkmn/Configs/Emacs/emacs_red_small.png")
;; Value can be
;; 'official which displays the official emacs logo
;; 'logo which displays an alternative emacs logo
;; 1, 2 or 3 which displays one of the text banners
;; "path/to/your/image.png" which displays whatever image you would prefer

;; ;; Content is not centered by default. To center, set
;; (setq dashboard-center-content t)

;; To disable shortcut "jump" indicators for each section, set
;; (setq dashboard-show-shortcuts nil)
(setq dashboard-items '((recents  . 10)
                        (bookmarks . 5)
                        ; (projects . 5)
                        (agenda . 5)))
                        ; (registers . 5)))
(setq dashboard-set-heading-icons t)
(setq dashboard-set-file-icons t)
(setq initial-buffer-choice (lambda () (get-buffer "*dashboard*")))


(setq visible-bell nil
      ring-bell-function nil)

(setq-default cursor-type 'bar)
;; the different between setq and setq-default only exists when the variable to
;; deal is buffer-local variable, so you should use setq-default
