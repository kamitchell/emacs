;;; autorevert.el --- revert buffers when files on disk change

;; Copyright (C) 1997, 1998, 1999, 2001 Free Software Foundation, Inc.

;; Author: Anders Lindgren <andersl@andersl.com>
;; Keywords: convenience
;; Created: 1997-06-01
;; Date: 1999-11-30

;; This file is part of GNU Emacs.

;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;; Introduction:
;;
;; Whenever a file that Emacs is editing has been changed by another
;; program the user normally has to execute the command `revert-buffer'
;; to load the new content of the file into Emacs.
;;
;; This package contains two minor modes: Global Auto-Revert Mode and
;; Auto-Revert Mode.  Both modes automatically revert buffers
;; whenever the corresponding files have been changed on disk.
;;
;; Auto-Revert Mode can be activated for individual buffers.
;; Global Auto-Revert Mode applies to all file buffers.
;;
;; Both modes operate by checking the time stamp of all files at
;; intervals of `auto-revert-interval'.  The default is every five
;; seconds.  The check is aborted whenever the user actually uses
;; Emacs.  You should never even notice that this package is active
;; (except that your buffers will be reverted, of course).

;; Usage:
;;
;; Go to the appropriate buffer and press:
;;   M-x auto-revert-mode RET
;;
;; To activate Global Auto-Revert Mode, press:
;;   M-x global-auto-revert-mode RET
;;
;; To activate Global Auto-Revert Mode every time Emacs is started
;; customise the option `global-auto-revert-mode' or the following
;; line could be added to your ~/.emacs:
;;   (global-auto-revert-mode 1)
;;
;; The function `turn-on-auto-revert-mode' could be added to any major
;; mode hook to activate Auto-Revert Mode for all buffers in that
;; mode.  For example, the following line will activate Auto-Revert
;; Mode in all C mode buffers:
;;
;; (add-hook 'c-mode-hook 'turn-on-auto-revert-mode)

;;; Code:

;; Dependencies:

(require 'timer)
(autoload 'dired-get-filename "dired")
(autoload 'vc-workfile-version "vc-hooks")
(autoload 'vc-mode-line        "vc-hooks")

(eval-when-compile
  (defvar dired-directory)
  (defvar vc-mode)
  (require 'cl))


;; Custom Group:
;;
;; The two modes will be placed next to Auto Save Mode under the
;; Files group under Emacs.

(defgroup auto-revert nil
  "Revert individual buffers when files on disk change.

Auto-Revert Mode can be activated for individual buffer.
Global Auto-Revert Mode applies to all buffers."
  :group 'files
  :group 'convenience)


;; Variables:

;; Autoload for the benefit of `make-mode-line-mouse-sensitive'.
;;;###autoload
(defvar auto-revert-mode nil
  "*Non-nil when Auto-Revert Mode is active.
Never set this variable directly, use the command `auto-revert-mode' instead.")
(put 'auto-revert-mode 'permanent-local t)

(defcustom auto-revert-interval 5
  "Time, in seconds, between Auto-Revert Mode file checks.
Setting this variable has no effect on buffers that are already in
auto-revert-mode; it only affects buffers that are put into
auto-revert-mode afterwards."
  :group 'auto-revert
  :type 'integer)

(defcustom auto-revert-stop-on-user-input t
  "When non-nil Auto-Revert Mode stops checking files on user input."
  :group 'auto-revert
  :type 'boolean)

(defcustom auto-revert-verbose t
  "When nil, Auto-Revert Mode will not generate any messages.

Currently, messages are generated when the mode is activated or
deactivated, and whenever a file is reverted."
  :group 'auto-revert
  :type 'boolean)

(defcustom auto-revert-mode-text " ARev"
  "String to display in the mode line when Auto-Revert Mode is active.

\(When the string is not empty, make sure that it has a leading space.)"
  :tag "Auto Revert Mode Text"		; To separate it from `global-...'
  :group 'auto-revert
  :type 'string)

(defcustom auto-revert-mode-hook nil
  "Functions to run when Auto-Revert Mode is activated."
  :tag "Auto Revert Mode Hook"		; To separate it from `global-...'
  :group 'auto-revert
  :type 'hook)

(defcustom global-auto-revert-mode-text ""
  "String to display when Global Auto-Revert Mode is active.

The default is nothing since when this mode is active this text doesn't
vary over time, or between buffers.  Hence mode line text
would only waste precious space."
  :group 'auto-revert
  :type 'string)

(defcustom global-auto-revert-mode-hook nil
  "Hook called when Global Auto-Revert Mode is activated."
  :group 'auto-revert
  :type 'hook)

(defcustom global-auto-revert-non-file-buffers nil
  "When nil only file buffers are reverted by Global Auto-Revert Mode.

When non-nil, both file buffers and buffers with a custom
`revert-buffer-function' are reverted by Global Auto-Revert Mode.

Use this option with care since it could lead to excessive reverts."
  :group 'auto-revert
  :type 'boolean)

(defcustom global-auto-revert-ignore-modes '()
  "List of major modes Global Auto-Revert Mode should not check."
  :group 'auto-revert
  :type '(repeat sexp))

(defcustom auto-revert-load-hook nil
  "Functions to run when Auto-Revert Mode is first loaded."
  :tag "Load Hook"
  :group 'auto-revert
  :type 'hook)

(defvar global-auto-revert-ignore-buffer nil
  "*When non-nil, Global Auto-Revert Mode will not revert this buffer.

This variable becomes buffer local when set in any fashion.")
(make-variable-buffer-local 'global-auto-revert-ignore-buffer)


;; Internal variables:

(defvar auto-revert-buffer-list '()
  "List of buffers in Auto-Revert Mode.

Note that only Auto-Revert Mode, never Global Auto-Revert Mode, adds
buffers to this list.

The timer function `auto-revert-buffers' is responsible for purging
the list of old buffers.")

(defvar auto-revert-timer nil
  "Timer used by Auto-Revert Mode.")

(defvar auto-revert-remaining-buffers '()
  "Buffers not checked when user input stopped execution.")


;; Functions:

;;;###autoload
(define-minor-mode auto-revert-mode
  "Toggle reverting buffer when file on disk changes.

With arg, turn Auto Revert mode on if and only if arg is positive.
This is a minor mode that affects only the current buffer.
Use `global-auto-revert-mode' to automatically revert all buffers."
  nil auto-revert-mode-text nil
  (if auto-revert-mode
      (if (not (memq (current-buffer) auto-revert-buffer-list))
	  (push (current-buffer) auto-revert-buffer-list))
    (setq auto-revert-buffer-list
	  (delq (current-buffer) auto-revert-buffer-list)))
  (auto-revert-set-timer)
  (when auto-revert-mode
    (auto-revert-buffers)))


;;;###autoload
(defun turn-on-auto-revert-mode ()
  "Turn on Auto-Revert Mode.

This function is designed to be added to hooks, for example:
  (add-hook 'c-mode-hook 'turn-on-auto-revert-mode)"
  (auto-revert-mode 1))


;;;###autoload
(define-minor-mode global-auto-revert-mode
  "Revert any buffer when file on disk change.

With arg, turn Auto Revert mode on globally if and only if arg is positive.
This is a minor mode that affects all buffers.
Use `auto-revert-mode' to revert a particular buffer."
  :global t :group 'auto-revert :lighter global-auto-revert-mode-text
  (auto-revert-set-timer)
  (when global-auto-revert-mode
    (auto-revert-buffers)))


(defun auto-revert-set-timer ()
  "Restart or cancel the timer."
  (if (timerp auto-revert-timer)
      (cancel-timer auto-revert-timer))
  (setq auto-revert-timer
	(if (or global-auto-revert-mode auto-revert-buffer-list)
	    (run-with-timer auto-revert-interval
			    auto-revert-interval
			    'auto-revert-buffers)
	  nil)))

(defun auto-revert-active-p ()
  "Check if auto-revert is active (in current buffer or globally)."
  (or auto-revert-mode
      (and
       global-auto-revert-mode
       (not global-auto-revert-ignore-buffer)
       (not (memq major-mode
		  global-auto-revert-ignore-modes)))))

(defun auto-revert-list-diff (a b)
  "Check if strings in list A differ from list B."
  (when (and a b)
    (setq a (sort a 'string-lessp))
    (setq b (sort b 'string-lessp))
    (let (elt1 elt2)
      (catch 'break
	(while (and (setq elt1 (and a (pop a)))
		    (setq elt2 (and b (pop b))))
	  (if (not (string= elt1 elt2))
	      (throw 'break t)))))))

(defun auto-revert-dired-file-list ()
  "Return list of dired files."
  (let (file list)
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
	(if (setq file (dired-get-filename t t))
	    (push file list))
	(forward-line 1)))
    list))

(defun auto-revert-dired-changed-p ()
  "Check if dired buffer has changed."
  (when (and (stringp dired-directory)
	     ;;	  Exclude remote buffers, would be too slow for user
	     ;;	  modem, timeouts, network lag ... all is possible
	     (not (string-match "@" dired-directory))
	     (file-directory-p dired-directory))
    (let ((files (directory-files dired-directory))
	  (dired (auto-revert-dired-file-list)))
      (or (not (eq (length files) (length dired)))
	  (auto-revert-list-diff files dired)))))

(defun auto-revert-buffer-p ()
  "Check if current buffer should be reverted."
  ;;  - Always include dired buffers to list.  It would be too expensive
  ;;  to test the "revert" status here each time timer launches.
  ;;  - Same for VC buffers.
  (or (and (eq major-mode 'dired-mode)
	   (or (and global-auto-revert-mode
		    global-auto-revert-non-file-buffers)
	       auto-revert-mode))
      (and (not (buffer-modified-p))
	   (auto-revert-vc-buffer-p))
      (and (not (buffer-modified-p))
	   (if (buffer-file-name)
	       (and (file-readable-p (buffer-file-name))
		    (not (verify-visited-file-modtime (current-buffer))))
	     (and revert-buffer-function
		  (or (and global-auto-revert-mode
			   global-auto-revert-non-file-buffers)
		      auto-revert-mode))))))

(defun auto-revert-vc-cvs-file-version (file)
  "Get version of FILE by reading control file on disk."
  (let* ((control "CVS/Entries")
	 (name	  (file-name-nondirectory file))
	 (path	  (format "%s/%s"
			  (file-name-directory file)
			  control)))
    (when (file-exists-p path)
      (with-temp-buffer
	(insert-file-contents-literally path)
	(goto-char (point-min))
	(when (re-search-forward
	       ;; /file.txt/1.3/Mon Sep 15 18:43:20 2003//
	       (format "%s/\\([.0-9]+\\)" (regexp-quote name))
	       nil t)
	  (match-string 1))))))

(defun auto-revert-vc-buffer-p ()
  "Check if buffer is version controlled."
  (and (boundp 'vc-mode)
       (string-match "[0-9]" (or vc-mode ""))))

(defun auto-revert-handler-vc ()
  "Check if version controlled buffer needs revert."
  ;; [Emacs 1]
  ;; 1. File is saved	  (*)
  ;; 2. checkin is done 1.1 -> 1.2
  ;; 3. VC reverts, so that updated version number is shown in mode line
  ;;
  ;; Suppose the same file has been opened in another Emacs and
  ;; autorevert.el is on.
  ;;
  ;; [Emacs 2]
  ;; 1. Step (1) is detected and buffer is reverted.
  ;; 2. But check in does not always change the file in dis, but possibly only
  ;;	control files like CVS/Entries
  ;; 3. The buffer is not reverted to update VC version line.
  ;;	Incorrect version number 1.1 is shown in this Emacs
  ;;
  (when (featurep 'vc)
    (let* ((file	   (buffer-file-name))
	   (backend	   (vc-backend (buffer-file-name)))
	   (version-buffer (vc-workfile-version file)))
      (when (stringp version-buffer)
	(cond
	 ((eq backend 'CVS)
	  (let ((version-file
		 (auto-revert-vc-cvs-file-version (buffer-file-name))))
	    (and (stringp version-file)
		 (not (string-match version-file version-buffer)))))
	 ((eq backend 'RCS)
	  ;; TODO:
	  ))))))

(defun auto-revert-handler ()
  "Revert current buffer."
  (let (revert)
    (cond
     ((eq major-mode 'dired-mode)
      ;;  Dired includes revert-buffer-function
      (when (and revert-buffer-function
		 (auto-revert-dired-changed-p))
	(setq revert t)))
     ((auto-revert-vc-buffer-p)
      (when (auto-revert-handler-vc)
	(setq revert 'vc)))
     ((or (buffer-file-name)
	  revert-buffer-function)
      (setq revert t)))
    (when revert
      (revert-buffer 'ignore-auto 'dont-ask 'preserve-modes)
      (if (eq revert 'vc)
	  (vc-mode-line buffer-file-name))
      (if auto-revert-verbose
	  (message "Reverting buffer `%s'." (buffer-name))))))

(defun auto-revert-buffers ()
  "Revert buffers as specified by Auto-Revert and Global Auto-Revert Mode.

Should `global-auto-revert-mode' be active all file buffers are checked.

Should `auto-revert-mode' be active in some buffers, those buffers
are checked.

Non-file buffers that have a custom `revert-buffer-function' are
reverted either when Auto-Revert Mode is active in that buffer, or
when the variable `global-auto-revert-non-file-buffers' is non-nil
and Global Auto-Revert Mode is active.

This function stops whenever there is user input.  The buffers not
checked are stored in the variable `auto-revert-remaining-buffers'.

To avoid starvation, the buffers in `auto-revert-remaining-buffers'
are checked first the next time this function is called.

This function is also responsible for removing buffers no longer in
Auto-Revert mode from `auto-revert-buffer-list', and for canceling
the timer when no buffers need to be checked."
  (let ((bufs (if global-auto-revert-mode
		  (buffer-list)
		auto-revert-buffer-list))
	(remaining '())
	(new '()))
    ;; Partition `bufs' into two halves depending on whether or not
    ;; the buffers are in `auto-revert-remaining-buffers'.  The two
    ;; halves are then re-joined with the "remaining" buffers at the
    ;; head of the list.
    (dolist (buf auto-revert-remaining-buffers)
      (if (memq buf bufs)
	  (push buf remaining)))
    (dolist (buf bufs)
      (if (not (memq buf remaining))
	  (push buf new)))
    (setq bufs (nreverse (nconc new remaining)))
    (while (and bufs
		(not (and auto-revert-stop-on-user-input
			  (input-pending-p))))
      (let ((buf (car bufs)))
	(if (buffer-name buf)		; Buffer still alive?
	    (with-current-buffer buf
	      ;; Test if someone has turned off Auto-Revert Mode in a
	      ;; non-standard way, for example by changing major mode.
	      (if (and (not auto-revert-mode)
		       (memq buf auto-revert-buffer-list))
		  (setq auto-revert-buffer-list
			(delq buf auto-revert-buffer-list)))
	      (when (and (auto-revert-active-p)
			 (auto-revert-buffer-p))
		(auto-revert-handler)
		;; `preserve-modes' avoids changing the (minor) modes.  But we
		;; do want to reset the mode for VC, so we do it explicitly.
		(vc-find-file-hook)))
	  ;; Remove dead buffer from `auto-revert-buffer-list'.
	  (setq auto-revert-buffer-list
		(delq buf auto-revert-buffer-list))))
      (setq bufs (cdr bufs)))
    (setq auto-revert-remaining-buffers bufs)
    ;; Check if we should cancel the timer.
    (when (and (not global-auto-revert-mode)
	       (null auto-revert-buffer-list))
      (cancel-timer auto-revert-timer)
      (setq auto-revert-timer nil))))


;; The end:
(provide 'autorevert)

(run-hooks 'auto-revert-load-hook)

;;; arch-tag: f6bcb07b-4841-477e-9e44-b18678e58876
;;; autorevert.el ends here
