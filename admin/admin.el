;;; admin.el --- utilities for Emacs administration

;; Copyright (C) 2001, 2002, 2003, 2004, 2005, 2006  Free Software
;;   Foundation, Inc.

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

;; add-release-logs	Add ``Version X released'' change log entries.
;; set-version		Change Emacs version number in source tree.

;;; Code:

(defun process-lines (program &rest args)
  "Execute PROGRAM with ARGS, returning its output as a list of lines.
Signal an error if the program returns with a non-zero exit status."
  (with-temp-buffer
    (let ((status (apply 'call-process program nil (current-buffer) nil args)))
      (unless (eq status 0)
	(error "%s exited with status %s" program status))
      (goto-char (point-min))
      (let (lines)
	(while (not (eobp))
	  (setq lines (cons (buffer-substring-no-properties
			     (line-beginning-position)
			     (line-end-position))
			    lines))
	  (forward-line 1))
	(nreverse lines)))))

(defun add-release-logs (root version)
  "Add \"Version VERSION released.\" change log entries in ROOT.
Root must be the root of an Emacs source tree."
  (interactive "DEmacs root directory: \nNVersion number: ")
  (setq root (expand-file-name root))
  (unless (file-exists-p (expand-file-name "src/emacs.c" root))
    (error "%s doesn't seem to be the root of an Emacs source tree" root))
  (require 'add-log)
  (let* ((logs (process-lines "find" root "-name" "ChangeLog"))
	 (entry (format "%s  %s  <%s>\n\n\t* Version %s released.\n\n"
			(funcall add-log-time-format)
			(or add-log-full-name (user-full-name))
			(or add-log-mailing-address user-mail-address)
			version)))
    (dolist (log logs)
      (unless (string-match "/gnus/" log)
	(find-file log)
	(goto-char (point-min))
	(insert entry)))))

(defun set-version-in-file (root file version rx)
  (find-file (expand-file-name file root))
  (goto-char (point-min))
  (unless (re-search-forward rx nil t)
    (error "Version not found in %s" file))
  (replace-match (format "%s" version) nil nil nil 1))

(defun set-version (root version)
  "Set Emacs version to VERSION in relevant files under ROOT.
Root must be the root of an Emacs source tree."
  (interactive "DEmacs root directory: \nsVersion number: ")
  (unless (file-exists-p (expand-file-name "src/emacs.c" root))
    (error "%s doesn't seem to be the root of an Emacs source tree" root))
  (set-version-in-file root "lisp/version.el" version
		       (rx (and "emacs-version" (0+ space)
				?\" (submatch (1+ (not (in ?\")))) ?\")))
  (set-version-in-file root "README" version
		       (rx (and "version" (1+ space)
				(submatch (1+ (in "0-9."))))))
  (set-version-in-file root "man/emacs.texi" version
		       (rx (and "EMACSVER" (1+ space)
				(submatch (1+ (in "0-9."))))))
  (set-version-in-file root "lispref/elisp.texi" version
		       (rx (and "EMACSVER" (1+ space)
				(submatch (1+ (in "0-9."))))))
  (set-version-in-file root "lib-src/makefile.w32-in" version
		       (rx (and "VERSION" (0+ space) "=" (0+ space)
				(submatch (1+ (in "0-9."))))))
  ;; nt/emacs.rc also contains the version number, but in an awkward
  ;; format. It must contain four components, separated by commas, and
  ;; in two places those commas are followed by space, in two other
  ;; places they are not.
  (let* ((version-components (append (split-string version "\\.")
				    '("0" "0")))
	 (comma-version
	  (concat (car version-components) ","
		  (cadr version-components) ","
		  (cadr (cdr version-components)) ","
		  (cadr (cdr (cdr version-components)))))
	 (comma-space-version
	  (concat (car version-components) ", "
		  (cadr version-components) ", "
		  (cadr (cdr version-components)) ", "
		  (cadr (cdr (cdr version-components))))))
    (set-version-in-file root "nt/emacs.rc" comma-version
			 (rx (and "FILEVERSION" (1+ space)
				  (submatch (1+ (in "0-9,"))))))
    (set-version-in-file root "nt/emacs.rc" comma-version
			 (rx (and "PRODUCTVERSION" (1+ space)
				  (submatch (1+ (in "0-9,"))))))
    (set-version-in-file root "nt/emacs.rc" comma-space-version
			 (rx (and "\"FileVersion\"" (0+ space) ?, (0+ space)
				  ?\" (submatch (1+ (in "0-9, "))) "\\0\"")))
    (set-version-in-file root "nt/emacs.rc" comma-space-version
			 (rx (and "\"ProductVersion\"" (0+ space) ?,
				  (0+ space) ?\" (submatch (1+ (in "0-9, ")))
				  "\\0\"")))
    ;; Some files in the "mac" subdirectory also contain the version
    ;; number.
    (set-version-in-file
     root "mac/Emacs.app/Contents/Resources/English.lproj/InfoPlist.strings"
     version (rx (and "CFBundleShortVersionString" (0+ space) ?= (0+ space) ?\"
		      (submatch (1+ (in "0-9."))))))
    (set-version-in-file
     root "mac/Emacs.app/Contents/Resources/English.lproj/InfoPlist.strings"
     version (rx (and "CFBundleGetInfoString" (0+ space) ?= (0+ space) ?\"
		      (submatch (1+ (in "0-9."))))))
    (set-version-in-file root "mac/src/Emacs.r" (car version-components)
			 (rx (and "GNU Emacs " (submatch (1+ (in "0-9")))
				  " for Mac OS")))
    (set-version-in-file root "mac/src/Emacs.r" (car version-components)
			 (rx (and (submatch (1+ (in "0-9"))) (0+ space) ?\,
				  (0+ space) "/* Major revision in BCD */")))
    (set-version-in-file root "mac/src/Emacs.r" (cadr version-components)
			 (rx (and (submatch (1+ (in "0-9"))) (0+ space) ?\,
				  (0+ space) "/* Minor revision in BCD */")))
    (set-version-in-file root "mac/src/Emacs.r" (cadr (cdr version-components))
			 (rx (and (submatch (1+ (in "0-9"))) (0+ space) ?\,
				  (0+ space) "/* Non-final release # */")))
    (set-version-in-file root "mac/src/Emacs.r" version
			 (rx (and (submatch (1+ (in "0-9."))) (0+ space) ?\" ?\,
				  (0+ space) "/* Short version number */")))
    (set-version-in-file root "mac/src/Emacs.r" version
			 (rx (and "/* Short version number */" (0+ space) ?\"
				  (submatch (1+ (in "0-9."))))))
    (let* ((third-component (string-to-number (cadr (cdr version-components))))
	   (release (cond ((>= third-component 90) "alpha")
			  ((>= third-component 50) "development")
			  (t "final"))))
      (set-version-in-file
       root "mac/src/Emacs.r" release
       (rx (and (submatch (1+ (in "a-z"))) (0+ space) ?\, (0+ space)
		"/* development, alpha, beta, or final (release) */"))))))

;;; arch-tag: 4ea83636-2293-408b-884e-ad64f22a3bf5
;; admin.el ends here.
