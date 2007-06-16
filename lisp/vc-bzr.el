;;; vc-bzr.el --- VC backend for the bzr revision control system

;; Copyright (C) 2006, 2007  Free Software Foundation, Inc.

;; NOTE: THIS IS A MODIFIED VERSION OF Dave Love's vc-bzr.el,
;; which you can find at: http://www.loveshack.ukfsn.org/emacs/vc-bzr.el
;; I could not get in touch with Dave Love by email, so 
;; I am releasing my changes separately. -- Riccardo

;; Author: Dave Love <fx@gnu.org>, Riccardo Murri <riccardo.murri@gmail.com>
;; Keywords: tools
;; Created: Sept 2006
;; Version: 2007-01-17
;; URL: http://launchpad.net/vc-bzr

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.


;;; Commentary:

;; NOTE: THIS IS A MODIFIED VERSION OF Dave Love's vc-bzr.el,
;; which you can find at: http://www.loveshack.ukfsn.org/emacs/vc-bzr.el

;; See <URL:http://bazaar-vcs.org/> concerning bzr.

;; Load this library to register bzr support in VC.  The support is
;; preliminary and incomplete, adapted from my darcs version.  Lightly
;; exercised with bzr 0.8 and Emacs 21, and bzr 0.11 on Emacs 22.  See
;; various Fixmes below.

;; This should be suitable for direct inclusion in Emacs if someone
;; can persuade rms.


;;; Code:

(eval-when-compile
  (require 'vc))                        ; for vc-exec-after

(defgroup vc-bzr nil
  "VC bzr backend."
;;   :version "22"
  :group 'vc)

(defcustom vc-bzr-program "bzr"
  "*Name of the bzr command (excluding any arguments)."
  :group 'vc-bzr
  :type 'string)

;; Fixme: there's probably no call for this.
(defcustom vc-bzr-program-args nil
  "*List of global arguments to pass to `vc-bzr-program'."
  :group 'vc-bzr
  :type '(repeat string))

(defcustom vc-bzr-diff-switches nil
  "*String/list of strings specifying extra switches for bzr diff under VC."
  :type '(choice (const :tag "None" nil)
                 (string :tag "Argument String")
                 (repeat :tag "Argument List" :value ("") string))
  :group 'vc-bzr)

(defvar vc-bzr-version nil
  "Internal use.")

;; Could be used for compatibility checks if bzr changes.
(defun vc-bzr-version ()
  "Return a three-numeric element list with components of the bzr version.
This is of the form (X Y Z) for revision X.Y.Z.  The elements are zero
if running `vc-bzr-program' doesn't produce the expected output."
  (if vc-bzr-version
      vc-bzr-version
    (let ((s (shell-command-to-string
              (concat (shell-quote-argument vc-bzr-program) " --version"))))
      (if (string-match "\\([0-9]+\\)\\.\\([0-9]+\\)\\.\\([0-9]+\\)$" s)
          (setq vc-bzr-version (list (string-to-number (match-string 1 s))
                                     (string-to-number (match-string 2 s))
                                     (string-to-number (match-string 3 s))))
        '(0 0 0)))))

(defun vc-bzr-at-least-version (vers)
  "Return t if the bzr command reports being a least version VERS.
First argument VERS is a list of the form (X Y Z), as returned by `vc-bzr-version'."
  (version-list-<= vers (vc-bzr-version)))

;; XXX: vc-do-command is tailored for RCS and assumes that command-line
;; options precede the file name (ci -something file); with bzr, we need
; to pass options *after* the subcommand, e.g. bzr ls --versioned.
(defun vc-bzr-do-command* (buffer okstatus command &rest args)
  "Execute bzr COMMAND, notifying user and checking for errors.
This is a wrapper around `vc-do-command', which see for detailed
explanation of arguments BUFFER, OKSTATUS and COMMAND.

If the optional list of ARGS is present, its elements are
appended to the command line, in the order given.

Unlike `vc-do-command', this has no way of telling which elements
in ARGS are file names and which are command-line options, so be
sure to pass absolute file names if needed.  On the other hand,
you can mix options and file names in any order."
  (apply 'vc-do-command buffer okstatus command nil args))

(cond
 ((vc-bzr-at-least-version '(0 9))
  ;; since v0.9, bzr supports removing the progress indicators
  ;; by setting environment variable BZR_PROGRESS_BAR to "none".
  (defun vc-bzr-command (bzr-command buffer okstatus file &rest args)
    "Wrapper round `vc-do-command' using `vc-bzr-program' as COMMAND.
Invoke the bzr command adding `BZR_PROGRESS_BAR=none' to the environment."
    (let ((process-environment (cons "BZR_PROGRESS_BAR=none" process-environment)))
      (apply 'vc-do-command buffer okstatus vc-bzr-program
             file bzr-command (append vc-bzr-program-args args))))
  
  (defun vc-bzr-command* (bzr-command buffer okstatus file &rest args)
    "Wrapper round `vc-bzr-do-command*' using `vc-bzr-program' as COMMAND.
Invoke the bzr command adding `BZR_PROGRESS_BAR=none' to the environment.
First argument BZR-COMMAND is passed as the first optional argument to
`vc-bzr-do-command*'."
    (let ((process-environment (cons "BZR_PROGRESS_BAR=none" process-environment)))
      (apply 'vc-bzr-do-command* buffer okstatus vc-bzr-program
             bzr-command (append vc-bzr-program-args args)))))
  
 (t
  ;; for older versions, we fall back to washing the log buffer
  ;; when all output has been gathered.
  (defun vc-bzr-command (command buffer okstatus file &rest args) 
    "Wrapper round `vc-do-command' using `vc-bzr-program' as COMMAND."
    ;; Note:  The ^Ms from the progress-indicator stuff that bzr prints
    ;; on stderr cause auto-detection of a mac coding system on the
    ;; stream for async output.  bzr ought to be fixed to be able to
    ;; suppress this.  See also `vc-bzr-post-command-function'.  (We
    ;; can't sink the stderr output in `vc-do-command'.)
    (apply 'vc-do-command buffer okstatus vc-bzr-program
           file command (append vc-bzr-program-args args)))

  (defun vc-bzr-command* (command buffer okstatus &rest args) 
    "Wrapper round `vc-bzr-do-command*' using `vc-bzr-program' as COMMAND."
    (apply 'vc-bzr-do-command* buffer okstatus vc-bzr-program
           command file (append vc-bzr-program-args args)))

  (defun vc-bzr-post-command-function (command file flags)
    "`vc-post-command-functions' function to remove progress messages."
    ;; Note that using this requires that the vc command is run
    ;; synchronously.  Otherwise, the ^Ms in the leading progress
    ;; message on stdout cause the stream to be interpreted as having
    ;; DOS line endings, losing the ^Ms, so the search fails.  I don't
    ;; know how this works under Windows.
    (when (equal command vc-bzr-program)
      (save-excursion
        (goto-char (point-min))
        (if (looking-at "^\\(\r.*\r\\)[^\r]+$")
            (replace-match "" nil nil nil 1)))
      (save-excursion
        (goto-char (point-min))
        ;; This is inserted by bzr 0.11 `log', at least
        (while (looking-at "read knit.*\n")
          (replace-match "")))))

  (add-hook 'vc-post-command-functions 'vc-bzr-post-command-function)))

;; Fixme:  If we're only interested in status messages, we only need
;; to set LC_MESSAGES, and we might need finer control of this.  This
;; is moot anyhow, since bzr doesn't appear to be localized at all
;; (yet?).
(eval-when-compile
(defmacro vc-bzr-with-c-locale (&rest body)
  "Run BODY with LC_ALL=C in the process environment.
This ensures that messages to be matched come out as expected."
  `(let ((process-environment (cons "LC_ALL=C" process-environment)))
     ,@body)))
(put 'vc-bzr-with-c-locale 'edebug-form-spec t)
(put 'vc-bzr-with-c-locale 'lisp-indent-function 0)

(defun vc-bzr-bzr-dir (file)
  "Return the .bzr directory in the hierarchy above FILE.
Return nil if there isn't one."
  (setq file (expand-file-name file))
  (let ((dir (if (file-directory-p file)
                 file
               (file-name-directory file)))
        bzr)
    (catch 'found
      (while t
        (setq bzr (expand-file-name ".bzr" dir)) ; fixme: "_bzr" on Doze??
        (if (file-directory-p bzr)
            (throw 'found (file-name-as-directory bzr)))
        (if (equal "" (file-name-nondirectory (directory-file-name dir)))
            (throw 'found nil)
          (setq dir (file-name-directory (directory-file-name dir))))))))

(defun vc-bzr-registered (file)
  "Return non-nil if FILE is registered with bzr."
  (if (vc-bzr-bzr-dir file)             ; short cut
      (vc-bzr-state file)))             ; expensive

(defun vc-bzr-state (file)
  (let (ret state conflicts pending-merges)
    (with-temp-buffer
      (cd (file-name-directory file))
      (setq ret (vc-bzr-with-c-locale (vc-bzr-command "status" t 255 file)))
      (goto-char 1)
      (save-excursion
        (when (re-search-forward "^conflicts:" nil t)
          (message "Warning -- conflicts in bzr branch")))
      (save-excursion
        (when (re-search-forward "^pending merges:" nil t)
          (message "Warning -- pending merges in bzr branch")))
      (setq state
            (cond ((not (equal ret 0)) nil)
                  ((looking-at "added\\|renamed\\|modified\\|removed") 'edited)
                  ;; Fixme:  Also get this in a non-registered sub-directory.
                  ((looking-at "^$") 'up-to-date)
                  ;; if we're seeing this as first line of text,
                  ;; then the status is up-to-date, 
                  ;; but bzr output only gives the warning to users.
                  ((looking-at "conflicts\\|pending") 'up-to-date)
                  ((looking-at "unknown\\|ignored") nil)
                  (t (error "Unrecognized output from `bzr status'"))))
      (when (or conflicts pending-merges)
        (message 
         (concat "Warning -- "
                 (if conflicts "conflicts ")
                 (if (and conflicts pending-merges) "and ")
                 (if pending-merges "pending merges ")
                 "in bzr branch")))
      (when state
        (vc-file-setprop file 'vc-workfile-version
                         (vc-bzr-workfile-version file))
        (vc-file-setprop file 'vc-state state))
      state)))

(defun vc-bzr-workfile-unchanged-p (file)
  (eq 'up-to-date (vc-bzr-state file)))

(defun vc-bzr-workfile-version (file)
  (with-temp-buffer
    (vc-bzr-command "revno" t 0 file)
    (goto-char 1)
    (buffer-substring 1 (line-end-position))))

(defun vc-bzr-checkout-model (file)
  'implicit)

(defun vc-bzr-register (file &optional rev comment)
  "Register FILE under bzr.
Signal an error unless REV is nil.
COMMENT is ignored."
  (if rev (error "Can't register explicit version with bzr"))
  (vc-bzr-command "add" nil 0 file))

;; Could run `bzr status' in the directory and see if it succeeds, but
;; that's relatively expensive.
(defun vc-bzr-responsible-p (file)
  "Return non-nil if FILE is (potentially) controlled by bzr.
The criterion is that there is a `.bzr' directory in the same
or a superior directory."
  (vc-bzr-bzr-dir file))

(defun vc-bzr-could-register (file)
  "Return non-nil if FILE could be registered under bzr."
  (and (vc-bzr-responsible-p file)      ; shortcut
       (condition-case ()
           (with-temp-buffer
             (vc-bzr-command "add" t 0 file "--dry-run")
             ;; The command succeeds with no output if file is
             ;; registered (in bzr 0.8).
             (goto-char 1)
             (looking-at "added "))
         (error))))

(defun vc-bzr-unregister (file)
  "Unregister FILE from bzr."
  (vc-bzr-command "remove" nil 0 file))

(defun vc-bzr-checkin (file rev comment)
  "Check FILE in to bzr with log message COMMENT.
REV non-nil gets an error."
  (if rev (error "Can't check in a specific version with bzr"))
  (vc-bzr-command "commit" nil 0 file "-m" comment))

(defun vc-bzr-checkout (file &optional editable rev destfile)
  "Checkout revision REV of FILE from bzr to DESTFILE.
EDITABLE is ignored."
  (unless destfile
    (setq destfile (vc-version-backup-file-name file rev)))
  (let ((coding-system-for-read 'binary)
        (coding-system-for-write 'binary))
  (with-temp-file destfile
    (if rev
        (vc-bzr-command "cat" t 0 file "-r" rev)
      (vc-bzr-command "cat" t 0 file)))))

(defun vc-bzr-revert (file &optional contents-done)
  (unless contents-done
    (with-temp-buffer (vc-bzr-command "revert" t 'async file))))

(eval-when-compile
  (defvar log-view-message-re)
  (defvar log-view-file-re)
  (defvar log-view-font-lock-keywords)
  (defvar log-view-current-tag-function))

;; Grim hack to account for lack of an extension mechanism for
;; log-view.  Should be fixed in VC...
(defun vc-bzr-view-log-function ()
  "To be added to `log-view-mode-hook' to set variables for bzr output.
Removes itself after running."
  (remove-hook 'log-view-mode-hook 'vc-bzr-view-log-function)
  (require 'add-log)
  ;; Don't have file markers, so use impossible regexp.
  (set (make-local-variable 'log-view-file-re) "\\'\\`")
  (set (make-local-variable 'log-view-message-re) "^ *-+\n *\\(revno: [0-9]+\\|merged: .+\\)")
  (set (make-local-variable 'log-view-font-lock-keywords)
       `(("^ *committer: \
\\([^<(]+?\\)[  ]*[(<]\\([A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+\\)[>)]"
          nil nil
          (1 'change-log-name-face nil t)
          (2 'change-log-email-face nil t)
          (3 'change-log-email-face nil t))
         ("^ *timestamp: \\(.*\\)" (1 'change-log-date-face))
         (,log-view-message-re . 'log-view-message-face)
;;       ("^  \\(.*\\)$" (1 'log-view-message-face))
         )))

(defun vc-bzr-print-log (file &optional buffer) ; get buffer arg in Emacs 22
  "Get bzr change log for FILE into specified BUFFER."
  ;; Fixme: VC needs a hook to sort out the mode for the buffer, or at
  ;; least set the regexps right.
  ;; Fixme: This might need the locale fixing up if things like `revno'
  ;; got localized, but certainly it shouldn't use LC_ALL=C.
  ;; NB.  Can't be async -- see `vc-bzr-post-command-function'.
  (vc-bzr-command "log" buffer 0 file)
  (add-hook 'log-view-mode-hook 'vc-bzr-view-log-function))

(defun vc-bzr-show-log-entry (version)
  "Find entry for patch name VERSION in bzr change log buffer."
  (goto-char (point-min))
  (let (case-fold-search)
    (if (re-search-forward (concat "^-+\nrevno: " version "$") nil t)
        (beginning-of-line 0)
      (goto-char (point-min)))))

;; Fixem: vc-bzr-wash-log

(autoload 'vc-diff-switches-list "vc" nil nil t)

(defun vc-bzr-diff (file &optional rev1 rev2 buffer)
  "VC bzr backend for diff."
  (let ((working (vc-workfile-version file)))
    (if (and (equal rev1 working) (not rev2))
        (setq rev1 nil))
    (if (and (not rev1) rev2)
        (setq rev1 working))
    ;; NB.  Can't be async -- see `vc-bzr-post-command-function'.
    ;; bzr diff produces condition code 1 for some reason.
    (apply #'vc-bzr-command "diff" (or buffer "*vc-diff*") 1 file
           "--diff-options" (mapconcat 'identity (vc-diff-switches-list bzr)
                                       " ")
           (when rev1
             (if rev2
                 (list "-r" (format "%s..%s" rev1 rev2))
               (list "-r" rev1))))))

(defalias 'vc-bzr-diff-tree 'vc-bzr-diff)

;; Fixme: implement vc-bzr-dir-state, vc-bzr-dired-state-info

;; Fixme: vc-{next,previous}-version need fixing in vc.el to deal with
;; straight integer versions.

(defun vc-bzr-delete-file (file)
  "Delete FILE and delete it in the bzr repository."
  (condition-case ()
      (delete-file file)
    (file-error nil))
  (vc-bzr-command "remove" nil 0 file))

(defun vc-bzr-rename-file (old new)
  "Rename file from OLD to NEW using `bzr mv'."
  (vc-bzr-command "mv" nil 0 new old))

(defvar vc-bzr-annotation-table nil
  "Internal use.")
(make-variable-buffer-local 'vc-bzr-annotation-table)

(defun vc-bzr-annotate-command (file buffer &optional version)
  "Prepare BUFFER for `vc-annotate' on FILE.
Each line is tagged with the revision number, which has a `help-echo'
property containing author and date information."
  (apply #'vc-bzr-command "annotate" buffer 0 file "-l" "--all"
         (if version (list "-r" version)))
  (with-current-buffer buffer
    ;; Store the tags for the annotated source lines in a hash table
    ;; to allow saving space by sharing the text properties.
    (setq vc-bzr-annotation-table (make-hash-table :test 'equal))
    (goto-char (point-min))
    (while (re-search-forward "^\\( *[0-9]+\\) \\(.+\\) +\\([0-9]\\{8\\}\\) |"
                              nil t)
      (let* ((rev (match-string 1))
             (author (match-string 2))
             (date (match-string 3))
             (key (match-string 0))
             (tag (gethash key vc-bzr-annotation-table)))
        (unless tag
          (save-match-data
            (string-match " +\\'" author)
            (setq author (substring author 0 (match-beginning 0))))
          (setq tag (propertize rev 'help-echo (concat "Author: " author
                                                       ", date: " date)
                                'mouse-face 'highlight))
          (puthash key tag vc-bzr-annotation-table))
        (replace-match "")
        (insert tag " |")))))

;; Definition from Emacs 22
(unless (fboundp 'vc-annotate-convert-time)
(defun vc-annotate-convert-time (time)
  "Convert a time value to a floating-point number of days.
The argument TIME is a list as returned by `current-time' or
`encode-time', only the first two elements of that list are considered."
  (/ (+ (* (float (car time)) (lsh 1 16)) (cadr time)) 24 3600)))

(defun vc-bzr-annotate-time ()
  (when (re-search-forward "^ *[0-9]+ |" nil t)
    (let ((prop (get-text-property (line-beginning-position) 'help-echo)))
      (string-match "[0-9]+\\'" prop)
      (vc-annotate-convert-time
       (encode-time 0 0 0
                    (string-to-number (substring (match-string 0 prop) 6 8))
                    (string-to-number (substring (match-string 0 prop) 4 6))
                    (string-to-number (substring (match-string 0 prop) 0 4))
                    )))))

(defun vc-bzr-annotate-extract-revision-at-line ()
  "Return revision for current line of annoation buffer, or nil.
Return nil if current line isn't annotated."
  (save-excursion
    (beginning-of-line)
    (if (looking-at " *\\([0-9]+\\) | ")
        (match-string-no-properties 1))))

;; Not needed for Emacs 22
(defun vc-bzr-annotate-difference (point)
  (let ((next-time (vc-bzr-annotate-time)))
    (if next-time
        (- (vc-annotate-convert-time (current-time)) next-time))))

;; FIXME: `bzr root' will return the real path to the repository root,
;; that is, it can differ from the buffer's current directory name
;; if there are any symbolic links.
(defun vc-bzr-root (dir)
  "Return the root directory of the bzr repository containing DIR."
  ;; Cache technique copied from vc-arch.el.
  (or (vc-file-getprop dir 'bzr-root)
      (vc-file-setprop
       dir 'bzr-root
       (substring 
	(shell-command-to-string (concat vc-bzr-program " root " dir)) 0 -1))))

;; TODO: it would be nice to mark the conflicted files in  VC Dired,
;; and implement a command to run ediff and `bzr resolve' once the 
;; changes have been merged.
(defun vc-bzr-dir-state (dir &optional localp)
  "Find the VC state of all files in DIR.
Optional argument LOCALP is always ignored."
  (let (at-start bzr-root-directory current-bzr-state current-vc-state)
    ;; check that DIR is a bzr repository
    (set 'bzr-root-directory (vc-bzr-root dir))
    (unless (string-match "^/" bzr-root-directory)
      (error "Cannot find bzr repository for directory `%s'" dir))
    ;; `bzr ls --versioned' lists all versioned files;
    ;; assume they are up-to-date, unless we are given
    ;; evidence of the contrary.
    (set 'at-start t)
    (with-temp-buffer
      (vc-bzr-command* "ls" t 0 "--versioned" "--non-recursive")
      (goto-char (point-min))
      (while (or at-start 
                 (eq 0 (forward-line)))
        (set 'at-start nil)
        (let ((file (expand-file-name
                     (buffer-substring-no-properties 
                      (line-beginning-position) (line-end-position))
                     bzr-root-directory)))
          (vc-file-setprop file 'vc-state 'up-to-date)
          ;; XXX: is this correct? what happens if one 
          ;; mixes different SCMs in the same dir?
          (vc-file-setprop file 'vc-backend 'BZR))))
    ;; `bzr status' reports on added/modified/renamed and unknown/ignored files
    (set 'at-start t)
    (with-temp-buffer 
      (vc-bzr-with-c-locale (vc-bzr-command "status" t 0 nil))
      (goto-char (point-min))
      (while (or at-start 
                 (eq 0 (forward-line)))
        (set 'at-start nil)
        (cond 
         ((looking-at "^added") 
          (set 'current-vc-state 'edited)
          (set 'current-bzr-state 'added))
         ((looking-at "^modified") 
          (set 'current-vc-state 'edited)
          (set 'current-bzr-state 'modified))
         ((looking-at "^renamed") 
          (set 'current-vc-state 'edited)
          (set 'current-bzr-state 'renamed))
         ((looking-at "^\\(unknown\\|ignored\\)")
          (set 'current-vc-state nil)
          (set 'current-bzr-state 'not-versioned))
         ((looking-at "  ")
          ;; file names are indented by two spaces
          (when current-vc-state
            (let ((file (expand-file-name
                         (buffer-substring-no-properties
                          (match-end 0) (line-end-position))
                         bzr-root-directory)))
              (vc-file-setprop file 'vc-state current-vc-state)
              (vc-file-setprop file 'vc-bzr-state current-bzr-state)
              (when (eq 'added current-bzr-state)
                (vc-file-setprop file 'vc-workfile-version "0"))))
          (when (eq 'not-versioned current-bzr-state)
            (let ((file (expand-file-name
                         (buffer-substring-no-properties
                          (match-end 0) (line-end-position))
                         bzr-root-directory)))
              (vc-file-setprop file 'vc-backend 'none)
              (vc-file-setprop file 'vc-state nil))))
         (t
          ;; skip this part of `bzr status' output
          (set 'current-vc-state nil)
          (set 'current-bzr-state nil)))))))

(defun vc-bzr-dired-state-info (file)
  "Bzr-specific version of `vc-dired-state-info'."
  (if (eq 'edited (vc-state file))
      (let ((bzr-state (vc-file-getprop file 'vc-bzr-state)))
        (if bzr-state
            (concat "(" (symbol-name bzr-state) ")")
          ;; else fall back to default vc representation
          (vc-default-dired-state-info 'BZR file)))))

;; In case of just `(load "vc-bzr")', but that's probably the wrong
;; way to do it.
(add-to-list 'vc-handled-backends 'BZR)

(eval-after-load "vc"
  '(add-to-list 'vc-directory-exclusion-list ".bzr" t))

(defconst vc-bzr-unload-hook
  (lambda ()
    (setq vc-handled-backends (delq 'BZR vc-handled-backends))
    (remove-hook 'vc-post-command-functions 'vc-bzr-post-command-function)))

(provide 'vc-bzr)
;; arch-tag: 8101bad8-4e92-4e7d-85ae-d8e08b4e7c06
;;; vc-bzr.el ends here
