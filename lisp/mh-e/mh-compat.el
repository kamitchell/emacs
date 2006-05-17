;;; mh-compat.el --- make MH-E compatibile with various versions of Emacs

;; Copyright (C) 2006 Free Software Foundation, Inc.

;; Author: Bill Wohler <wohler@newt.com>
;; Maintainer: Bill Wohler <wohler@newt.com>
;; Keywords: mail
;; See: mh-e.el

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

;;; Change Log:

;;; Code:

;; This is a good place to gather code that is used for compatibility
;; between different versions of Emacs. Please document which versions
;; of Emacs that the defsubst, defalias, or defmacro applies. That
;; way, it's easy to occasionally go through this file and see which
;; macros we can retire.

;; Please use mh-gnus.el when providing compatibility with different
;; versions of Gnus.

;; Items are listed alphabetically (except for mh-require which is
;; needed by a lesser character).

(require 'mh-acros)

(mh-do-in-gnu-emacs
  (defalias 'mh-require 'require))

(mh-do-in-xemacs
  (defun mh-require (feature &optional filename noerror)
    "If feature FEATURE is not loaded, load it from FILENAME.
If FEATURE is not a member of the list `features', then the feature
is not loaded; so load the file FILENAME.
If FILENAME is omitted, the printname of FEATURE is used as the file name.
If the optional third argument NOERROR is non-nil,
then return nil if the file is not found instead of signaling an error.

Simulate NOERROR argument in XEmacs which lacks it."
    (if (not (featurep feature))
        (if filename
            (load filename noerror t)
          (load (format "%s" feature) noerror t)))))

(mh-defun-compat mh-assoc-string assoc-string (key list case-fold)
  "Like `assoc' but specifically for strings.
Case is ignored if CASE-FOLD is non-nil.
This function is used by Emacs versions that lack `assoc-string',
introduced in Emacs 22."
  (if case-fold
      (assoc-ignore-case key list)
    (assoc key list)))

;; For XEmacs.
(defalias 'mh-cancel-timer
  (if (fboundp 'cancel-timer)
      'cancel-timer
    'delete-itimer))

(mh-defun-compat mh-display-color-cells display-color-cells (&optional display)
  "Return the number of color cells supported by DISPLAY.
This function is used by XEmacs to always return 0 when compiling
to avoid compiling errors. Otherwise uses `device-color-cells'."
  (if mh-compiling-flag
      0
    (device-color-cells display)))

(defmacro mh-display-completion-list (completions &optional common-substring)
  "Display the list of COMPLETIONS.
See documentation for `display-completion-list' for a description of the
arguments COMPLETIONS and perhaps COMMON-SUBSTRING.
This macro is used by Emacs versions that lack a COMMON-SUBSTRING
argument, introduced in Emacs 22."
  (if (< emacs-major-version 22)
      `(display-completion-list ,completions)
    `(display-completion-list ,completions ,common-substring)))

(defmacro mh-face-foreground (face &optional frame inherit)
  "Return the foreground color name of FACE, or nil if unspecified.
See documentation for `face-foreground' for a description of the
arguments FACE, FRAME, and perhaps INHERIT.
This macro is used by Emacs versions that lack an INHERIT argument,
introduced in Emacs 22."
  (if (< emacs-major-version 22)
      `(face-foreground ,face ,frame)
    `(face-foreground ,face ,frame ,inherit)))

(defmacro mh-face-background (face &optional frame inherit)
  "Return the background color name of face, or nil if unspecified.
See documentation for `back-foreground' for a description of the
arguments FACE, FRAME, and INHERIT.
This macro is used by Emacs versions that lack an INHERIT argument,
introduced in Emacs 22."
  (if (< emacs-major-version 22)
      `(face-background ,face ,frame)
    `(face-background ,face ,frame ,inherit)))

;; For XEmacs.
(defalias 'mh-line-beginning-position
  (if (fboundp 'line-beginning-position)
      'line-beginning-position
    'point-at-bol))

;; For XEmacs.
(defalias 'mh-line-end-position
  (if (fboundp 'line-end-position)
      'line-end-position
    'point-at-eol))

(mh-require 'mailabbrev nil t)
(mh-defun-compat mh-mail-abbrev-make-syntax-table
  mail-abbrev-make-syntax-table ()
  "Emacs 21 and XEmacs don't have `mail-abbrev-make-syntax-table'.
This function does nothing on those systems."
  nil)

(mh-defun-compat mh-match-string-no-properties
  match-string-no-properties (num &optional string)
  "Return string of text matched by last search, without text properties.
This function is used by XEmacs that lacks `match-string-no-properties'.
The function `buffer-substring-no-properties' is used instead.
The argument STRING is ignored."
  (buffer-substring-no-properties
   (match-beginning num) (match-end num)))

(mh-defun-compat mh-replace-regexp-in-string replace-regexp-in-string
  (regexp rep string &optional fixedcase literal subexp start)
  "Replace REGEXP with REP everywhere in STRING and return result.
This function is used by XEmacs that lacks `replace-regexp-in-string'.
The function `replace-in-string' is used instead.
The arguments FIXEDCASE, LITERAL, SUBEXP, and START are ignored."
  (replace-in-string string regexp rep))

;; Copy of constant from url-util.el in Emacs 22; needed by Emacs 21.
(if (not (boundp 'url-unreserved-chars))
    (defconst mh-url-unreserved-chars
      '(
        ?a ?b ?c ?d ?e ?f ?g ?h ?i ?j ?k ?l ?m ?n ?o ?p ?q ?r ?s ?t ?u ?v ?w ?x ?y ?z
        ?A ?B ?C ?D ?E ?F ?G ?H ?I ?J ?K ?L ?M ?N ?O ?P ?Q ?R ?S ?T ?U ?V ?W ?X ?Y ?Z
        ?0 ?1 ?2 ?3 ?4 ?5 ?6 ?7 ?8 ?9
        ?- ?_ ?. ?! ?~ ?* ?' ?\( ?\))
      "A list of characters that are _NOT_ reserved in the URL spec.
This is taken from RFC 2396."))

(mh-defun-compat mh-url-hexify-string url-hexify-string (str)
  "Escape characters in a string.
This is a copy of `url-hexify-string' from url-util.el in Emacs
22; needed by Emacs 21."
  (mapconcat
   (lambda (char)
     ;; Fixme: use a char table instead.
     (if (not (memq char mh-url-unreserved-chars))
         (if (> char 255)
               (error "Hexifying multibyte character %s" str)
           (format "%%%02X" char))
       (char-to-string char)))
   str ""))

(mh-defun-compat mh-view-mode-enter
  view-mode-enter (&optional return-to exit-action)
  "Enter View mode.
This function is used by XEmacs that lacks `view-mode-enter'.
The function `view-mode' is used instead.
The arguments RETURN-TO and EXIT-ACTION are ignored."
  ;; Shush compiler.
  (if return-to nil)
  (if exit-action nil)
  (view-mode 1))

(defmacro mh-write-file-functions ()
  "Return `write-file-functions' if it exists.
Otherwise return `local-write-file-hooks'.
This macro exists purely for compatibility. The former symbol is used
in Emacs 22 onward while the latter is used in previous versions and
XEmacs."
  (if (boundp 'write-file-functions)
      ''write-file-functions            ;Emacs 22 on
    ''local-write-file-hooks))          ;XEmacs

(provide 'mh-compat)

;; Local Variables:
;; no-byte-compile: t
;; indent-tabs-mode: nil
;; sentence-end-double-space: nil
;; End:

;; arch-tag: 577b0eab-a5cd-45e1-8d9f-c1a426f4d73c
;;; mh-compat.el ends here
