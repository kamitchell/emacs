;;; rmailedit.el --- "RMAIL edit mode"  Edit the current message

;; Copyright (C) 1985, 1994, 2001, 2002, 2003, 2004, 2005,
;;   2006 Free Software Foundation, Inc.

;; Maintainer: FSF
;; Keywords: mail

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
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;;; Code:

(eval-when-compile
  (require 'rmail)
  (require 'rmaildesc)
  (require 'rmailsum))

(defcustom rmail-edit-mode-hook nil
  "List of functions to call when editing an RMAIL message."
  :type 'hook
  :version "21.1"
  :group 'rmail-edit)

(defvar rmail-old-text)

(defvar rmail-edit-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map text-mode-map)
    (define-key map "\C-c\C-c" 'rmail-cease-edit)
    (define-key map "\C-c\C-]" 'rmail-abort-edit)
    map)
  "Keymap for `rmail-edit-mode'.")

;; Rmail Edit mode is suitable only for specially formatted data.
(put 'rmail-edit-mode 'mode-class 'special)

(defun rmail-edit-mode ()
  "Major mode for editing the contents of an RMAIL message.
The editing commands are the same as in Text mode, together with two commands
to return to regular RMAIL:
  *  \\[rmail-abort-edit] cancels the changes
     you have made and returns to RMAIL
  *  \\[rmail-cease-edit] makes them permanent.
This functions runs the normal hook `rmail-edit-mode-hook'.
\\{rmail-edit-map}"
  (delay-mode-hooks (text-mode))
  (use-local-map rmail-edit-map)
  (setq major-mode 'rmail-edit-mode)
  (setq mode-name "RMAIL Edit")
  (if (boundp 'mode-line-modified)
      (setq mode-line-modified (default-value 'mode-line-modified))
    (setq mode-line-format (default-value 'mode-line-format)))
  (if (rmail-summary-exists)
      (save-excursion
	(set-buffer rmail-summary-buffer)
	(rmail-summary-disable)))
  (run-mode-hooks 'rmail-edit-mode-hook))

(defvar rmail-old-pruned nil)
(put 'rmail-old-pruned 'permanent-local t)

(defvar rmail-edit-saved-coding-system nil)
(put 'rmail-edit-saved-coding-system 'permanent-local t)

;;;###autoload
(defun rmail-edit-current-message ()
  "Edit the contents of this message."
  (interactive)
  (if (= rmail-total-messages 0)
      (error "No messages in this file"))
  (make-local-variable 'rmail-old-pruned)
  (setq rmail-old-pruned (rmail-msg-is-pruned))
  (make-local-variable 'rmail-edit-saved-coding-system)
  (setq rmail-edit-saved-coding-system save-buffer-coding-system)
  (rmail-header-show-headers)
  (rmail-edit-mode)
  ;; As the local value of save-buffer-coding-system is deleted by
  ;; rmail-edit-mode, we restore the original value.
  (make-local-variable 'save-buffer-coding-system)
  (setq save-buffer-coding-system rmail-edit-saved-coding-system)
  (make-local-variable 'rmail-old-text)
  (setq rmail-old-text (buffer-substring (point-min) (point-max)))
  (setq buffer-read-only nil)
  (force-mode-line-update)
  (if (and (eq (key-binding "\C-c\C-c") 'rmail-cease-edit)
	   (eq (key-binding "\C-c\C-]") 'rmail-abort-edit))
      (message "Editing: Type C-c C-c to return to Rmail, C-c C-] to abort")
    (message "%s" (substitute-command-keys
		   "Editing: Type \\[rmail-cease-edit] to return to Rmail, \\[rmail-abort-edit] to abort"))))

(defun rmail-cease-edit ()
  "Finish editing message; switch back to Rmail proper."
  (interactive)
  (when (rmail-summary-exists)
    (with-current-buffer rmail-summary-buffer
      (rmail-summary-enable)))
  ;; Make sure buffer ends with a newline.
  (save-excursion
    (goto-char (point-max))
    (when (/= (preceding-char) ?\n)
      (insert "\n"))
    ;; Adjust the marker that points to the end of this message, unless
    ;; we're at the last message.
    (when (< rmail-current-message (length rmail-desc-vector))
	(rmail-desc-set-start (1+ rmail-current-message) (point))))
  (let ((old rmail-old-text))
    (force-mode-line-update)
    (kill-all-local-variables)
    (rmail-mode-1)
    (rmail-variables)
    ;; As the local value of save-buffer-coding-system is changed by
    ;; rmail-variables, we restore the original value.
    (setq save-buffer-coding-system rmail-edit-saved-coding-system)
    (unless (and (= (length old) (- (point-max) (point-min)))
		 (string= old (buffer-substring (point-min) (point-max))))
      (setq old nil)
      (rmail-set-attribute "edited" t))
    (save-excursion
      (rmail-show-message)
      ;; `rmail-show-message' always hides the headers, so we show them
      ;; here if they were visible before starting the edit.
      (when rmail-old-pruned
	(rmail-header-show-headers))))
  (run-hooks 'rmail-mode-hook)
  (setq buffer-read-only t))

(defun rmail-abort-edit ()
  "Abort edit of current message; restore original contents."
  (interactive)
  (delete-region (point-min) (point-max))
  (insert rmail-old-text)
  (rmail-cease-edit))

(provide 'rmailedit)

;;; arch-tag: 93c22709-a14a-46c1-ab91-52c3f5a0ec12
;;; rmailedit.el ends here
