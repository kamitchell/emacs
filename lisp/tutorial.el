;;; tutorial.el --- tutorial for Emacs

;; Copyright (C) 2006 Free Software Foundation, Inc.

;; Maintainer: FSF
;; Keywords: help, internal

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

;; Code for running the Emacs tutorial.

;;; History:

;; File was created 2006-09.

;;; Code:

(require 'help-mode) ;; for function help-buffer
(eval-when-compile (require 'cl))

(defface tutorial-warning-face
  '((((class color) (min-colors 88) (background light))
     (:foreground "Red1" :weight bold))
    (((class color) (min-colors 88) (background dark))
     (:foreground "Pink" :weight bold))
    (((class color) (min-colors 16) (background light))
     (:foreground "Red1" :weight bold))
    (((class color) (min-colors 16) (background dark))
     (:foreground "Pink" :weight bold))
    (((class color) (min-colors 8)) (:foreground "red"))
    (t (:inverse-video t :weight bold)))
  "Face used to highlight warnings in the tutorial."
  :group 'font-lock-faces)

(defvar tutorial--point-before-chkeys 0
  "Point before display of key changes.")
(make-variable-buffer-local 'tutorial--point-before-chkeys)

(defvar tutorial--point-after-chkeys 0
  "Point after display of key changes.")
(make-variable-buffer-local 'tutorial--point-after-chkeys)

(defvar tutorial--lang nil
  "Tutorial language.")
(make-variable-buffer-local 'tutorial--lang)

(defun tutorial--describe-nonstandard-key (value)
  "Give more information about a changed key binding.
This is used in `help-with-tutorial'.  The information includes
the key sequence that no longer has a default binding, the
default binding and the current binding.  It also tells in what
keymap the new binding has been done and how to access the
function in the default binding from the keyboard.

For `cua-mode' key bindings that try to combine CUA key bindings
with default Emacs bindings information about this is shown.

VALUE should have either of these formats:

  \(cua-mode)
  \(current-binding KEY-FUN DEF-FUN KEY WHERE)

Where
  KEY         is a key sequence whose standard binding has been changed
  KEY-FUN     is the actual binding for KEY
  DEF-FUN     is the standard binding of KEY
  WHERE       is a text describing the key sequences to which DEF-FUN is
              bound now (or, if it is remapped, a key sequence
              for the function it is remapped to)"
  (with-output-to-temp-buffer (help-buffer)
    (help-setup-xref (list #'tutorial--describe-nonstandard-key value)
                     (interactive-p))
    (with-current-buffer (help-buffer)
      (insert
       "Your Emacs customizations override the default binding for this key:"
       "\n\n")
      (let ((inhibit-read-only t))
        (cond
         ((eq (car value) 'cua-mode)
          (insert
           "CUA mode is enabled.

When CUA mode is enabled, you can use C-z, C-x, C-c, and C-v to
undo, cut, copy, and paste in addition to the normal Emacs
bindings.  The C-x and C-c keys only do cut and copy when the
region is active, so in most cases, they do not conflict with the
normal function of these prefix keys.

If you really need to perform a command which starts with one of
the prefix keys even when the region is active, you have three
options:
- press the prefix key twice very quickly (within 0.2 seconds),
- press the prefix key and the following key within 0.2 seconds, or
- use the SHIFT key with the prefix key, i.e. C-S-x or C-S-c."))
         ((eq (car value) 'current-binding)
          (let ((cb    (nth 1 value))
                (db    (nth 2 value))
                (key   (nth 3 value))
                (where (nth 4 value))
                map
                (maps (current-active-maps))
                mapsym)
            ;; Look at the currently active keymaps and try to find
            ;; first the keymap where the current binding occurs:
            (while maps
              (let* ((m (car maps))
                     (mb (lookup-key m key t)))
                (setq maps (cdr maps))
                (when (eq mb cb)
                  (setq map m)
                  (setq maps nil))))
            ;; Now, if a keymap was found we must found the symbol
            ;; name for it to display to the user.  This can not
            ;; always be found since all keymaps does not have a
            ;; symbol pointing to them, but here they should have
            ;; that:
            (when map
              (mapatoms (lambda (s)
                          (and
                           ;; If not already found
                           (not mapsym)
                           ;; and if s is a keymap
                           (and (boundp s)
                                (keymapp (symbol-value s)))
                           ;; and not the local symbol map
                           (not (eq s 'map))
                           ;; and the value of s is map
                           (eq map (symbol-value s))
                           ;; then save this value in mapsym
                           (setq mapsym s)))))
            (insert "The default Emacs binding for the key "
                    (key-description key)
                    " is the command `")
            (insert (format "%s" db))
            (insert "'.  "
                    "However, your customizations have rebound it to the command `")
            (insert (format "%s" cb))
            (insert "'.")
            (when mapsym
              (insert "  (For the more advanced user:"
                      " This binding is in the keymap `"
                      (format "%s" mapsym)
                      "'.)"))
            (if (string= where "")
                (unless (keymapp db)
                  (insert "\n\nYou can use M-x "
                          (format "%s" db)
                          " RET instead."))
              (insert "\n\nWith you current key bindings"
                      " you can use the key "
                      where
                      " to get the function `"
                      (format "%s" db)
                      "'."))
            )
          (fill-region (point-min) (point)))))
      (print-help-return-message))))

(defun tutorial--sort-keys (left right)
  "Sort predicate for use with `tutorial--default-keys'.
This is a predicate function to `sort'.

The sorting is for presentation purpose only and is done on the
key sequence.

LEFT and RIGHT are the elements to compare."
  (let ((x (append (cadr left)  nil))
        (y (append (cadr right) nil)))
    ;; Skip the front part of the key sequences if they are equal:
    (while (and x y
                (listp x) (listp y)
                (equal (car x) (car y)))
      (setq x (cdr x))
      (setq y (cdr y)))
    ;; Try to make a comparision that is useful for presentation (this
    ;; could be made nicer perhaps):
    (let ((cx (car x))
          (cy (car y)))
      ;;(message "x=%s, y=%s;;;; cx=%s, cy=%s" x y cx cy)
      (cond
       ;; Lists? Then call this again
       ((and cx cy
             (listp cx)
             (listp cy))
        (tutorial--sort-keys cx cy))
       ;; Are both numbers? Then just compare them
       ((and (wholenump cx)
             (wholenump cy))
        (> cx cy))
       ;; Is one of them a number? Let that be bigger then.
       ((wholenump cx)
        t)
       ((wholenump cy)
        nil)
       ;; Are both symbols? Compare the names then.
       ((and (symbolp cx)
             (symbolp cy))
        (string< (symbol-name cy)
                 (symbol-name cx)))
       ))))

(defconst tutorial--default-keys
  (let* (
         ;; On window system suspend Emacs is replaced in the
         ;; default keymap so honor this here.
         (suspend-emacs (if window-system
                            'iconify-or-deiconify-frame
                          'suspend-emacs))
         (default-keys
           `(
             ;; These are not mentioned but are basic:
             (ESC-prefix [27])
             (Control-X-prefix [?\C-x])
             (mode-specific-command-prefix [?\C-c])

             (save-buffers-kill-emacs [?\C-x ?\C-c])


             ;; * SUMMARY
             (scroll-up [?\C-v])
             (scroll-down [?\M-v])
             (recenter [?\C-l])


             ;; * BASIC CURSOR CONTROL
             (forward-char [?\C-f])
             (backward-char [?\C-b])

             (forward-word [?\M-f])
             (backward-word [?\M-b])

             (next-line [?\C-n])
             (previous-line [?\C-p])

             (move-beginning-of-line [?\C-a])
             (move-end-of-line [?\C-e])

             (backward-sentence [?\M-a])
             (forward-sentence [?\M-e])


             (beginning-of-buffer [?\M-<])
             (end-of-buffer [?\M->])

             (universal-argument [?\C-u])


             ;; * WHEN EMACS IS HUNG
             (keyboard-quit [?\C-g])


             ;; * DISABLED COMMANDS
             (downcase-region [?\C-x ?\C-l])


             ;; * WINDOWS
             (delete-other-windows [?\C-x ?1])
             ;; C-u 0 C-l
             ;; Type CONTROL-h k CONTROL-f.


             ;; * INSERTING AND DELETING
             ;; C-u 8 * to insert ********.

             (delete-backward-char [backspace])
             (delete-char [?\C-d])

             (backward-kill-word [(meta backspace)])
             (kill-word [?\M-d])

             (kill-line [?\C-k])
             (kill-sentence [?\M-k])

             (set-mark-command [?\C-@])
             (set-mark-command [?\C- ])
             (kill-region [?\C-w])
             (yank [?\C-y])
             (yank-pop [?\M-y])


             ;; * UNDO
             (advertised-undo [?\C-x ?u])
             (advertised-undo [?\C-x ?u])


             ;; * FILES
             (find-file [?\C-x ?\C-f])
             (save-buffer [?\C-x ?\C-s])


             ;; * BUFFERS
             (list-buffers [?\C-x ?\C-b])
             (switch-to-buffer [?\C-x ?b])
             (save-some-buffers [?\C-x ?s])


             ;; * EXTENDING THE COMMAND SET
             ;; C-x	Character eXtend.  Followed by one character.
             (execute-extended-command [?\M-x])

             ;; C-x C-f		Find file
             ;; C-x C-s		Save file
             ;; C-x s		Save some buffers
             ;; C-x C-b		List buffers
             ;; C-x b		Switch buffer
             ;; C-x C-c		Quit Emacs
             ;; C-x 1		Delete all but one window
             ;; C-x u		Undo


             ;; * MODE LINE
             (describe-mode [?\C-h ?m])

             (set-fill-column [?\C-x ?f])
             (fill-paragraph [?\M-q])


             ;; * SEARCHING
             (isearch-forward [?\C-s])
             (isearch-backward [?\C-r])


             ;; * MULTIPLE WINDOWS
             (split-window-vertically [?\C-x ?2])
             (scroll-other-window [?\C-\M-v])
             (other-window [?\C-x ?o])
             (find-file-other-window [?\C-x ?4 ?\C-f])


             ;; * RECURSIVE EDITING LEVELS
             (keyboard-escape-quit [27 27 27])


             ;; * GETTING MORE HELP
             ;; The most basic HELP feature is C-h c
             (describe-key-briefly [?\C-h ?c])
             (describe-key [?\C-h ?k])


             ;; * MORE FEATURES
             ;; F10


             ;; * CONCLUSION
             ;;(iconify-or-deiconify-frame [?\C-z])
             (,suspend-emacs [?\C-z])
             )))
    (sort default-keys 'tutorial--sort-keys))
  "Default Emacs key bindings that the tutorial depends on.")

(defun tutorial--detailed-help (button)
  "Give detailed help about changed keys."
  (with-output-to-temp-buffer (help-buffer)
    (help-setup-xref (list #'tutorial--detailed-help button)
                     (interactive-p))
    (with-current-buffer (help-buffer)
      (let* ((tutorial-buffer  (button-get button 'tutorial-buffer))
             ;;(tutorial-arg     (button-get button 'tutorial-arg))
             (explain-key-desc (button-get button 'explain-key-desc))
             (changed-keys (with-current-buffer tutorial-buffer
                             (tutorial--find-changed-keys tutorial--default-keys))))
        (when changed-keys
          (insert
           "The following key bindings used in the tutorial had been changed
from Emacs default in the " (buffer-name tutorial-buffer) " buffer:\n\n" )
          (let ((frm "   %-9s %-27s %-11s %s\n"))
            (insert (format frm "Key" "Standard Binding" "Is Now On" "Remark")))
          (dolist (tk changed-keys)
            (let* ((def-fun     (nth 1 tk))
                   (key         (nth 0 tk))
                   (def-fun-txt (nth 2 tk))
                   (where       (nth 3 tk))
                   (remark      (nth 4 tk))
                   (rem-fun (command-remapping def-fun))
                   (key-txt (key-description key))
                   (key-fun (with-current-buffer tutorial-buffer (key-binding key)))
                   tot-len)
              (unless (eq def-fun key-fun)
                ;; Insert key binding description:
                (when (string= key-txt explain-key-desc)
                  (put-text-property 0 (length key-txt)
				     'face 'tutorial-warning-face key-txt))
                (insert "   " key-txt " ")
                (setq tot-len (length key-txt))
                (when (> 9 tot-len)
                  (insert (make-string (- 9 tot-len) ? ))
                  (setq tot-len 9))
                ;; Insert a link describing the old binding:
                (insert-button def-fun-txt
                               'value def-fun
                               'action
                               (lambda(button) (interactive)
                                 (describe-function
                                  (button-get button 'value)))
                               'follow-link t)
                (setq tot-len (+ tot-len (length def-fun-txt)))
                (when (> 36 tot-len)
                  (insert (make-string (- 36 tot-len) ? )))
                (when (listp where)
                  (setq where "list"))
                ;; Tell where the old binding is now:
                (insert (format " %-11s " where))
                ;; Insert a link with more information, for example
                ;; current binding and keymap or information about
                ;; cua-mode replacements:
                (insert-button (car remark)
                               'action
                               (lambda(b) (interactive)
                                 (let ((value (button-get b 'value)))
                                   (tutorial--describe-nonstandard-key value)))
                               'value (cdr remark)
                               'follow-link t)
                (insert "\n")))))

        (insert "
It is legitimate to change key bindings, but changed bindings do not
correspond to what the tutorial says.  (See also " )
        (insert-button "Key Binding Conventions"
                       'action
                       (lambda(button) (interactive)
                         (info
                          "(elisp) Key Binding Conventions")
                         (message "Type C-x 0 to close the new window"))
                       'follow-link t)
        (insert ".)\n\n")
        (print-help-return-message)))))

(defun tutorial--find-changed-keys (default-keys)
  "Find the key bindings that have changed.
Check if the default Emacs key bindings that the tutorial depends
on have been changed.

Return a list with the keys that have been changed.  The element
of this list have the following format:

  \(list KEY DEF-FUN DEF-FUN-TXT WHERE REMARK)

Where
  KEY         is a key sequence whose standard binding has been changed
  DEF-FUN     is the standard binding of KEY
  DEF-FUN-TXT is a short descriptive text for DEF-FUN
  WHERE       is a text describing the key sequences to which DEF-FUN is
              bound now (or, if it is remapped, a key sequence
              for the function it is remapped to)
  REMARK      is a list with info about rebinding. It has either of these
              formats:

                \(TEXT cua-mode)
                \(TEXT current-binding KEY-FUN DEF-FUN KEY WHERE)

              Here TEXT is a link text to show to the user.  The
              rest of the list is used to show information when
              the user clicks the link.

              KEY-FUN is the actual binding for KEY."
  (let (changed-keys remark)
    ;; (default-keys tutorial--default-keys))
    (dolist (kdf default-keys)
      ;; The variables below corresponds to those with the same names
      ;; described in the doc string.
      (let* ((key     (nth 1 kdf))
             (def-fun (nth 0 kdf))
             (def-fun-txt (format "%s" def-fun))
             (rem-fun (command-remapping def-fun))
             (key-fun (if (eq def-fun 'ESC-prefix)
			  (lookup-key global-map [27])
			(key-binding key)))
             (where (where-is-internal (if rem-fun rem-fun def-fun))))
        (if where
            (progn
              (setq where (key-description (car where)))
              (when (and (< 10 (length where))
                         (string= (substring where 0 (length "<menu-bar>"))
                                  "<menu-bar>"))
                (setq where "the menus")))
          (setq where ""))
        (setq remark nil)
        (unless
            (cond ((eq key-fun def-fun)
                   ;; No rebinding, return t
                   t)
                  ((eq key-fun (command-remapping def-fun))
                   ;; Just a remapping, return t
                   t)
                  ;; cua-mode specials:
                  ((and cua-mode
                        (or (and
                             (equal key [?\C-v])
                             (eq key-fun 'cua-paste))
                            (and
                             (equal key [?\C-z])
                             (eq key-fun 'undo))))
                   (setq remark (list "cua-mode, more info" 'cua-mode))
                   nil)
                  ((and cua-mode
                        (or
                         (and (eq def-fun 'ESC-prefix)
                              (equal key-fun
                                     `(keymap
                                       (118 . cua-repeat-replace-region))))
                         (and (eq def-fun 'mode-specific-command-prefix)
                              (equal key-fun
                                     '(keymap
                                       (timeout . copy-region-as-kill))))
                         (and (eq def-fun 'Control-X-prefix)
                              (equal key-fun
                                     '(keymap (timeout . kill-region))))))
                   (setq remark (list "cua-mode replacement" 'cua-mode))
                   (cond
                    ((eq def-fun 'mode-specific-command-prefix)
                     (setq def-fun-txt "\"C-c prefix\""))
                    ((eq def-fun 'Control-X-prefix)
                     (setq def-fun-txt "\"C-x prefix\""))
                    ((eq def-fun 'ESC-prefix)
                     (setq def-fun-txt "\"ESC prefix\"")))
                   (setq where "Same key")
                   nil)
                  ;; viper-mode specials:
                  ((and (boundp 'viper-mode-string)
			(boundp 'viper-current-state)
                        (eq viper-current-state 'vi-state)
                        (or (and (eq def-fun 'isearch-forward)
                                 (eq key-fun 'viper-isearch-forward))
                            (and (eq def-fun 'isearch-backward)
                                 (eq key-fun 'viper-isearch-backward))))
                   ;; These bindings works as the default bindings,
                   ;; return t
                   t)
                  ((when normal-erase-is-backspace
                     (or (and (equal key [C-delete])
                              (equal key-fun 'kill-word))
                         (and (equal key [C-backspace])
                              (equal key-fun 'backward-kill-word))))
                   ;; This is the strange handling of C-delete and
                   ;; C-backspace, return t
                   t)
                  (t
                   ;; This key has indeed been rebound. Put information
                   ;; in `remark' and return nil
                   (setq remark
                         (list "more info" 'current-binding
                               key-fun def-fun key where))
                   nil))
          (add-to-list 'changed-keys
                       (list key def-fun def-fun-txt where remark)))))
    changed-keys))

(defvar tutorial--tab-map
  (let ((map (make-sparse-keymap)))
    (define-key map [tab] 'forward-button)
    (define-key map [(shift tab)] 'backward-button)
    (define-key map [(meta tab)] 'backward-button)
    map)
  "Keymap that allows tabbing between buttons.")

(defun tutorial--display-changes (changed-keys)
  "Display changes to some default key bindings.
If some of the default key bindings that the tutorial depends on
have been changed then display the changes in the tutorial buffer
with some explanatory links.

CHANGED-KEYS should be a list in the format returned by
`tutorial--find-changed-keys'."
  (when (or changed-keys
            (boundp 'viper-mode-string))
    ;; Need the custom button face for viper buttons:
    (when (boundp 'viper-mode-string)
      (require 'cus-edit))
    (let ((start (point))
          end
          (head  (get-lang-string tutorial--lang 'tut-chgdhead))
          (head2 (get-lang-string tutorial--lang 'tut-chgdhead2)))
      (when (and head head2)
        (goto-char tutorial--point-before-chkeys)
        (insert head)
        (insert-button head2
                       'tutorial-buffer
                       (current-buffer)
                       ;;'tutorial-arg arg
                       'action
                       'tutorial--detailed-help
                       'follow-link t
                       'face 'link)
        (insert "]\n\n" )
        (when changed-keys
          (dolist (tk changed-keys)
            (let* ((def-fun     (nth 1 tk))
                   (key         (nth 0 tk))
                   (def-fun-txt (nth 2 tk))
                   (where       (nth 3 tk))
                   (remark      (nth 4 tk))
                   (rem-fun (command-remapping def-fun))
                   (key-txt (key-description key))
                   (key-fun (key-binding key))
                   tot-len)
              (unless (eq def-fun key-fun)
                ;; Mark the key in the tutorial text
                (unless (string= "Same key" where)
                  (let ((here (point))
			(case-fold-search nil)
                        (key-desc (key-description key)))
                    (while (re-search-forward
			    (concat (regexp-quote key-desc)
				    "[[:space:]]") nil t)
                      (put-text-property (match-beginning 0)
                                         (match-end 0)
                                         'tutorial-remark 'only-colored)
                      (put-text-property (match-beginning 0)
                                         (match-end 0)
                                         'face 'tutorial-warning-face)
                      (forward-line)
                      (let ((s  (get-lang-string tutorial--lang 'tut-chgdkey))
                            (s2 (get-lang-string tutorial--lang 'tut-chgdkey2))
                            (start (point))
                            end)
                        (when (and s s2)
                          (setq s (format s key-desc where s2))
                          (insert s)
                          (insert-button s2
                                         'tutorial-buffer
                                         (current-buffer)
                                         ;;'tutorial-arg arg
                                         'action
                                         'tutorial--detailed-help
                                         'explain-key-desc key-desc
                                         'follow-link t
                                         'face 'link)
                          (insert "] **")
                          (insert "\n")
                          (setq end (point))
                          (put-text-property start end 'local-map tutorial--tab-map)
                          ;; Add a property so we can remove the remark:
                          (put-text-property start end 'tutorial-remark t)
                          (put-text-property start end
                                             'face 'tutorial-warning-face)
                          (put-text-property start end 'read-only t))))
                    (goto-char here)))))))


        (setq end (point))
        ;; Make the area with information about change key
        ;; bindings stand out:
        (put-text-property start end 'tutorial-remark t)
        (put-text-property start end
                           'face 'tutorial-warning-face)
        ;; Make it possible to use Tab/S-Tab between fields in
        ;; this area:
        (put-text-property start end 'local-map tutorial--tab-map)
        (setq tutorial--point-after-chkeys (point-marker))
        ;; Make this area read-only:
        (put-text-property start end 'read-only t)))))

(defun tutorial--saved-dir ()
  "Directory where to save tutorials."
  (expand-file-name ".emacstut" "~/"))

(defun tutorial--saved-file ()
  "File name in which to save tutorials."
  (let ((file-name tutorial--lang)
        (ext (file-name-extension tutorial--lang)))
    (when (or (not ext)
              (string= ext ""))
      (setq file-name (concat file-name ".tut")))
    (expand-file-name file-name (tutorial--saved-dir))))

(defun tutorial--remove-remarks()
  "Remove the remark lines that was added to the tutorial buffer."
  (save-excursion
    (goto-char (point-min))
    (let (prop-start
          prop-end
          prop-val)
      ;; Catch the case when we already are on a remark line
      (while (if (get-text-property (point) 'tutorial-remark)
                 (setq prop-start (point))
               (setq prop-start (next-single-property-change (point) 'tutorial-remark)))
        (setq prop-end (next-single-property-change prop-start 'tutorial-remark))
        (setq prop-val (get-text-property prop-start 'tutorial-remark))
        (unless prop-end
          (setq prop-end (point-max)))
        (goto-char prop-end)
        (if (eq prop-val 'only-colored)
            (put-text-property prop-start prop-end 'face '(:background nil))
          (let ((orig-text (get-text-property prop-start 'tutorial-orig)))
            (delete-region prop-start prop-end)
            (when orig-text (insert orig-text))))))))

(defun tutorial--save-tutorial ()
  "Save the tutorial buffer.
This saves the part of the tutorial before and after the area
showing changed keys.  It also saves the point position and the
position where the display of changed bindings was inserted."
  ;; This runs in a hook so protect it:
  (condition-case err
      (tutorial--save-tutorial-to (tutorial--saved-file))
    (error (message "Error saving tutorial state: %s" (error-message-string err))
           (sit-for 4))))

(defun tutorial--save-tutorial-to (saved-file)
  "Save the tutorial buffer to SAVED-FILE.
See `tutorial--save-tutorial' for more information."
  ;; Anything to save?
  (when (or (buffer-modified-p)
            (< 1 (point)))
    (let ((tutorial-dir (tutorial--saved-dir))
          save-err)
      ;; The tutorial is saved in a subdirectory in the user home
      ;; directory. Create this subdirectory first.
      (unless (file-directory-p tutorial-dir)
        (condition-case err
            (make-directory tutorial-dir nil)
          (error (setq save-err t)
                 (warn "Could not create directory %s: %s" tutorial-dir
                       (error-message-string err)))))
      ;; Make sure we have that directory.
      (if (file-directory-p tutorial-dir)
          (let ((tut-point (if (= 0 tutorial--point-after-chkeys)
                               ;; No info about changed keys is
                               ;; displayed.
                               (point)
                             (if (< (point) tutorial--point-after-chkeys)
                                 (- (point))
                               (- (point) tutorial--point-after-chkeys))))
                (old-point (point))
                ;; Use a special undo list so that we easily can undo
                ;; the changes we make to the tutorial buffer.  This is
                ;; currently not needed since we now delete the buffer
                ;; after saving, but kept for possible future use of
                ;; this function.
                buffer-undo-list
                (inhibit-read-only t))
            ;; Delete the area displaying info about changed keys.
            ;;             (when (< 0 tutorial--point-after-chkeys)
            ;;               (delete-region tutorial--point-before-chkeys
            ;;                              tutorial--point-after-chkeys))
            ;; Delete the remarks:
            (tutorial--remove-remarks)
            ;; Put the value of point first in the buffer so it will
            ;; be saved with the tutorial.
            (goto-char (point-min))
            (insert (number-to-string tut-point)
                    "\n"
                    (number-to-string (marker-position
                                       tutorial--point-before-chkeys))
                    "\n")
            (condition-case err
                (write-region nil nil saved-file)
              (error (setq save-err t)
                     (warn "Could not save tutorial to %s: %s"
                           saved-file
                           (error-message-string err))))
            ;; An error is raised here?? Is this a bug?
            (condition-case err
                (undo-only)
              (error nil))
            ;; Restore point
            (goto-char old-point)
            (if save-err
                (message "Could not save tutorial state.")
              (message "Saved tutorial state.")))
        (message "Can't save tutorial: %s is not a directory"
                 tutorial-dir)))))


;;;###autoload
(defun help-with-tutorial (&optional arg dont-ask-for-revert)
  "Select the Emacs learn-by-doing tutorial.
If there is a tutorial version written in the language
of the selected language environment, that version is used.
If there's no tutorial in that language, `TUTORIAL' is selected.
With ARG, you are asked to choose which language.
If DONT-ASK-FOR-REVERT is non-nil the buffer is reverted without
any question when restarting the tutorial.

If any of the standard Emacs key bindings that are used in the
tutorial have been changed then an explanatory note about this is
shown in the beginning of the tutorial buffer.

When the tutorial buffer is killed the content and the point
position in the buffer is saved so that the tutorial may be
resumed later."
  (interactive "P")
  (if (boundp 'viper-current-state)
      (let ((prompt1
             "You can not run the Emacs tutorial directly because you have \
enabled Viper.")
	    (prompt2 "\nThere is however a Viper tutorial you can run instead.
Run the Viper tutorial? "))
	(if (fboundp 'viper-tutorial)
	    (if (y-or-n-p (concat prompt1 prompt2))
		(progn (message "")
		       (funcall 'viper-tutorial 0))
	      (message "Tutorial aborted by user"))
	  (message prompt1)))
    (let* ((lang (if arg
                     (let ((minibuffer-setup-hook minibuffer-setup-hook))
                       (add-hook 'minibuffer-setup-hook
                                 'minibuffer-completion-help)
                       (read-language-name 'tutorial "Language: " "English"))
                   (if (get-language-info current-language-environment 'tutorial)
                       current-language-environment
                     "English")))
           (filename (get-language-info lang 'tutorial))
           ;; Choose a buffer name including the language so that
           ;; several languages can be tested simultaneously:
           (tut-buf-name (concat "TUTORIAL (" lang ")"))
           (old-tut-buf (get-buffer tut-buf-name))
           (old-tut-win (when old-tut-buf (get-buffer-window old-tut-buf t)))
           (old-tut-is-ok (when old-tut-buf
                            (not (buffer-modified-p old-tut-buf))))
           old-tut-file
           (old-tut-point 1))
      (setq tutorial--point-after-chkeys (point-min))
      ;; Try to display the tutorial buffer before asking to revert it.
      ;; If the tutorial buffer is shown in some window make sure it is
      ;; selected and displayed:
      (if old-tut-win
          (raise-frame
           (window-frame
            (select-window (get-buffer-window old-tut-buf t))))
        ;; Else, is there an old tutorial buffer? Then display it:
        (when old-tut-buf
          (switch-to-buffer old-tut-buf)))
      ;; Use whole frame for tutorial
      (delete-other-windows)
      ;; If the tutorial buffer has been changed then ask if it should
      ;; be reverted:
      (when (and old-tut-buf
                 (not old-tut-is-ok))
        (setq old-tut-is-ok
              (if dont-ask-for-revert
                  nil
                (not (y-or-n-p
                      "You have changed the Tutorial buffer.  Revert it? ")))))
      ;; (Re)build the tutorial buffer if it is not ok
      (unless old-tut-is-ok
        (switch-to-buffer (get-buffer-create tut-buf-name))
        (unless old-tut-buf (text-mode))
        (unless lang (error "Variable lang is nil"))
        (setq tutorial--lang lang)
        (setq old-tut-file (file-exists-p (tutorial--saved-file)))
        (let ((inhibit-read-only t))
          (erase-buffer))
        (message "Preparing tutorial ...") (sit-for 0)

        ;; Do not associate the tutorial buffer with a file. Instead use
        ;; a hook to save it when the buffer is killed.
        (setq buffer-auto-save-file-name nil)
        (add-hook 'kill-buffer-hook 'tutorial--save-tutorial nil t)

        ;; Insert the tutorial. First offer to resume last tutorial
        ;; editing session.
        (when dont-ask-for-revert
          (setq old-tut-file nil))
        (when old-tut-file
          (setq old-tut-file
                (y-or-n-p "Resume your last saved tutorial? ")))
        (if old-tut-file
            (progn
              (insert-file-contents (tutorial--saved-file))
              (goto-char (point-min))
              (setq old-tut-point
                    (string-to-number
                     (buffer-substring-no-properties
                      (line-beginning-position) (line-end-position))))
              (forward-line)
              (setq tutorial--point-before-chkeys
                    (string-to-number
                     (buffer-substring-no-properties
                      (line-beginning-position) (line-end-position))))
              (forward-line)
              (delete-region (point-min) (point))
              (goto-char tutorial--point-before-chkeys)
              (setq tutorial--point-before-chkeys (point-marker)))
          (insert-file-contents (expand-file-name filename data-directory))
          (forward-line)
          (setq tutorial--point-before-chkeys (point-marker)))


        ;; Check if there are key bindings that may disturb the
        ;; tutorial.  If so tell the user.
        (let ((changed-keys (tutorial--find-changed-keys tutorial--default-keys)))
          (when changed-keys
            (tutorial--display-changes changed-keys)))


        ;; Clear message:
        (unless dont-ask-for-revert
          (message "") (sit-for 0))


        (if old-tut-file
            ;; Just move to old point in saved tutorial.
            (let ((old-point
                   (if (> 0 old-tut-point)
                       (- old-tut-point)
                     (+ old-tut-point tutorial--point-after-chkeys))))
              (when (< old-point 1)
                (setq old-point 1))
              (goto-char old-point))
          (goto-char (point-min))
          (search-forward "\n<<")
          (beginning-of-line)
          ;; Convert the <<...>> line to the proper [...] line,
          ;; or just delete the <<...>> line if a [...] line follows.
          (cond ((save-excursion
                   (forward-line 1)
                   (looking-at "\\["))
                 (delete-region (point) (progn (forward-line 1) (point))))
                ((looking-at "<<Blank lines inserted.*>>")
                 (replace-match "[Middle of page left blank for didactic purposes.   Text continues below]"))
                (t
                 (looking-at "<<")
                 (replace-match "[")
                 (search-forward ">>")
                 (replace-match "]")))
          (beginning-of-line)
          (let ((n (- (window-height (selected-window))
                      (count-lines (point-min) (point))
                      6)))
            (if (< n 8)
                (progn
                  ;; For a short gap, we don't need the [...] line,
                  ;; so delete it.
                  (delete-region (point) (progn (end-of-line) (point)))
                  (newline n))
              ;; Some people get confused by the large gap.
              (newline (/ n 2))

              ;; Skip the [...] line (don't delete it).
              (forward-line 1)
              (newline (- n (/ n 2)))))
          (goto-char (point-min)))
        (setq buffer-undo-list nil)
        (set-buffer-modified-p nil)))))


;; Below is some attempt to handle language specific strings. These
;; are currently only used in the tutorial.

(defconst lang-strings
  '(
    ("English" .
     (
      (tut-chgdkey . "** The key %s has been rebound, but you can use %s instead [")
      (tut-chgdkey2 . "More information")
      (tut-chgdhead . "
 NOTICE: The main purpose of the Emacs tutorial is to teach you
 the most important standard Emacs commands (key bindings).
 However, your Emacs has been customized by changing some of
 these basic editing commands, so it doesn't correspond to the
 tutorial.  We have inserted colored notices where the altered
 commands have been introduced. [")
      (tut-chgdhead2 . "Details")
      )
     )
    )
  "Language specific strings for Emacs.
This is an association list with the keys equal to the strings
that can be returned by `read-language-name'.  The elements in
the list are themselves association lists with keys that are
string ids and values that are the language specific strings.

See `get-lang-string' for more information.")

(defun get-lang-string(lang stringid &optional no-eng-fallback)
  "Get a language specific string for Emacs.
In certain places Emacs can replace a string showed to the user with a language specific string.
This function retrieves such strings.

LANG is the language specification. It should be one of those
strings that can be returned by `read-language-name'.  STRINGID
is a symbol that specifies the string to retrieve.

If no string is found for STRINGID in the choosen language then
the English string is returned unless NO-ENG-FALLBACK is non-nil.

See `lang-strings' for more information.

Currently this feature is only used in `help-with-tutorial'."
  (let ((my-lang-strings (assoc lang lang-strings))
        (found-string))
    (when my-lang-strings
      (let ((entry (assoc stringid (cdr my-lang-strings))))
        (when entry
          (setq found-string (cdr entry)))))
    ;; Fallback to English strings
    (unless (or found-string
                no-eng-fallback)
      (setq found-string (get-lang-string "English" stringid t)))
    found-string))

;;(get-lang-string "English" 'tut-chgdkey)

(provide 'tutorial)

;; arch-tag: c8e80aef-c3bb-4ffb-8af6-22171bf0c100
;;; tutorial.el ends here
