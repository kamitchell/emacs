;;; minibuffer.el --- Minibuffer completion functions

;; Copyright (C) 2008  Free Software Foundation, Inc.

;; Author: Stefan Monnier <monnier@iro.umontreal.ca>

;; This file is part of GNU Emacs.

;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Names starting with "minibuffer--" are for functions and variables that
;; are meant to be for internal use only.

;;; Todo:

;; - New command minibuffer-force-complete that chooses one of all-completions.
;; - Add vc-file-name-completion-table to read-file-name-internal.
;; - A feature like completing-help.el.
;; - Make the `hide-spaces' arg of all-completions obsolete?

;;; Code:

(eval-when-compile (require 'cl))

(defvar completion-all-completions-with-base-size nil
  "If non-nil, `all-completions' may return the base-size in the last cdr.
The base-size is the length of the prefix that is elided from each
element in the returned list of completions.  See `completion-base-size'.")

;;; Completion table manipulation

(defun completion--some (fun xs)
  "Apply FUN to each element of XS in turn.
Return the first non-nil returned value.
Like CL's `some'."
  (let (res)
    (while (and (not res) xs)
      (setq res (funcall fun (pop xs))))
    res))

(defun apply-partially (fun &rest args)
  "Do a \"curried\" partial application of FUN to ARGS.
ARGS is a list of the first N arguments to pass to FUN.
The result is a new function that takes the remaining arguments,
and calls FUN."
  (lexical-let ((fun fun) (args1 args))
    (lambda (&rest args2) (apply fun (append args1 args2)))))

(defun complete-with-action (action table string pred)
  "Perform completion ACTION.
STRING is the string to complete.
TABLE is the completion table, which should not be a function.
PRED is a completion predicate.
ACTION can be one of nil, t or `lambda'."
  ;; (assert (not (functionp table)))
  (funcall
   (cond
    ((null action) 'try-completion)
    ((eq action t) 'all-completions)
    (t 'test-completion))
   string table pred))

(defun completion-table-dynamic (fun)
  "Use function FUN as a dynamic completion table.
FUN is called with one argument, the string for which completion is required,
and it should return an alist containing all the intended possible completions.
This alist may be a full list of possible completions so that FUN can ignore
the value of its argument.  If completion is performed in the minibuffer,
FUN will be called in the buffer from which the minibuffer was entered.

The result of the `dynamic-completion-table' form is a function
that can be used as the ALIST argument to `try-completion' and
`all-completions'.  See Info node `(elisp)Programmed Completion'."
  (lexical-let ((fun fun))
    (lambda (string pred action)
      (with-current-buffer (let ((win (minibuffer-selected-window)))
                             (if (window-live-p win) (window-buffer win)
                               (current-buffer)))
        (complete-with-action action (funcall fun string) string pred)))))

(defmacro lazy-completion-table (var fun)
  "Initialize variable VAR as a lazy completion table.
If the completion table VAR is used for the first time (e.g., by passing VAR
as an argument to `try-completion'), the function FUN is called with no
arguments.  FUN must return the completion table that will be stored in VAR.
If completion is requested in the minibuffer, FUN will be called in the buffer
from which the minibuffer was entered.  The return value of
`lazy-completion-table' must be used to initialize the value of VAR.

You should give VAR a non-nil `risky-local-variable' property."
  (declare (debug (symbolp lambda-expr)))
  (let ((str (make-symbol "string")))
    `(completion-table-dynamic
      (lambda (,str)
        (when (functionp ,var)
          (setq ,var (,fun)))
        ,var))))

(defun completion-table-with-context (prefix table string pred action)
  ;; TODO: add `suffix' maybe?
  ;; Notice that `pred' is not a predicate when called from read-file-name
  ;; or Info-read-node-name-2.
  (if (functionp pred)
      (setq pred (lexical-let ((pred pred))
                   ;; FIXME: this doesn't work if `table' is an obarray.
                   (lambda (s) (funcall pred (concat prefix s))))))
  (let ((comp (complete-with-action action table string pred)))
    (cond
     ;; In case of try-completion, add the prefix.
     ((stringp comp) (concat prefix comp))
     ;; In case of non-empty all-completions,
     ;; add the prefix size to the base-size.
     ((consp comp)
      (let ((last (last comp)))
        (when completion-all-completions-with-base-size
          (setcdr last (+ (or (cdr last) 0) (length prefix))))
        comp))
     (t comp))))

(defun completion-table-with-terminator (terminator table string pred action)
  (cond
   ((eq action nil)
    (let ((comp (try-completion string table pred)))
      (if (eq comp t)
          (concat string terminator)
        (if (and (stringp comp)
                 (eq (try-completion comp table pred) t))
            (concat comp terminator)
          comp))))
   ((eq action t) (all-completions string table pred))
   ;; completion-table-with-terminator is always used for
   ;; "sub-completions" so it's only called if the terminator is missing,
   ;; in which case `test-completion' should return nil.
   ((eq action 'lambda) nil)))

(defun completion-table-with-predicate (table pred1 strict string pred2 action)
  "Make a completion table equivalent to TABLE but filtered through PRED1.
PRED1 is a function of one argument which returns non-nil iff the
argument is an element of TABLE which should be considered for completion.
STRING, PRED2, and ACTION are the usual arguments to completion tables,
as described in `try-completion', `all-completions', and `test-completion'.
If STRICT is t, the predicate always applies; if nil it only applies if
it does not reduce the set of possible completions to nothing.
Note: TABLE needs to be a proper completion table which obeys predicates."
  (cond
   ((and (not strict) (eq action 'lambda))
    ;; Ignore pred1 since it doesn't really have to apply anyway.
    (test-completion string table pred2))
   (t
    (or (complete-with-action action table string
                              (if (null pred2) pred1
                                (lexical-let ((pred1 pred2) (pred2 pred2))
                                  (lambda (x)
                                    ;; Call `pred1' first, so that `pred2'
                                    ;; really can't tell that `x' is in table.
                                    (if (funcall pred1 x) (funcall pred2 x))))))
        ;; If completion failed and we're not applying pred1 strictly, try
        ;; again without pred1.
        (and (not strict)
             (complete-with-action action table string pred2))))))

(defun completion-table-in-turn (&rest tables)
  "Create a completion table that tries each table in TABLES in turn."
  (lexical-let ((tables tables))
    (lambda (string pred action)
      (completion--some (lambda (table)
                          (complete-with-action action table string pred))
                        tables))))

;; (defmacro complete-in-turn (a b) `(completion-table-in-turn ,a ,b))
;; (defmacro dynamic-completion-table (fun) `(completion-table-dynamic ,fun))
(define-obsolete-function-alias
  'complete-in-turn 'completion-table-in-turn "23.1")
(define-obsolete-function-alias
  'dynamic-completion-table 'completion-table-dynamic "23.1")

;;; Minibuffer completion

(defgroup minibuffer nil
  "Controlling the behavior of the minibuffer."
  :link '(custom-manual "(emacs)Minibuffer")
  :group 'environment)

(defun minibuffer-message (message &rest args)
  "Temporarily display MESSAGE at the end of the minibuffer.
The text is displayed for `minibuffer-message-timeout' seconds,
or until the next input event arrives, whichever comes first.
Enclose MESSAGE in [...] if this is not yet the case.
If ARGS are provided, then pass MESSAGE through `format'."
  ;; Clear out any old echo-area message to make way for our new thing.
  (message nil)
  (setq message (if (and (null args) (string-match "\\[.+\\]" message))
                    ;; Make sure we can put-text-property.
                    (copy-sequence message)
                  (concat " [" message "]")))
  (when args (setq message (apply 'format message args)))
  (let ((ol (make-overlay (point-max) (point-max) nil t t)))
    (unwind-protect
        (progn
          (unless (zerop (length message))
            ;; The current C cursor code doesn't know to use the overlay's
            ;; marker's stickiness to figure out whether to place the cursor
            ;; before or after the string, so let's spoon-feed it the pos.
            (put-text-property 0 1 'cursor t message))
          (overlay-put ol 'after-string message)
          (sit-for (or minibuffer-message-timeout 1000000)))
      (delete-overlay ol))))

(defun minibuffer-completion-contents ()
  "Return the user input in a minibuffer before point as a string.
That is what completion commands operate on."
  (buffer-substring (field-beginning) (point)))

(defun delete-minibuffer-contents ()
  "Delete all user input in a minibuffer.
If the current buffer is not a minibuffer, erase its entire contents."
  (delete-field))

(defcustom completion-auto-help t
  "Non-nil means automatically provide help for invalid completion input.
If the value is t the *Completion* buffer is displayed whenever completion
is requested but cannot be done.
If the value is `lazy', the *Completions* buffer is only displayed after
the second failed attempt to complete."
  :type '(choice (const nil) (const t) (const lazy))
  :group 'minibuffer)

(defvar completion-styles-alist
  '((basic try-completion all-completions)
    ;; (partial-completion
    ;;  completion-pcm--try-completion completion-pcm--all-completions)
    )
  "List of available completion styles.
Each element has the form (NAME TRY-COMPLETION ALL-COMPLETIONS)
where NAME is the name that should be used in `completion-styles'
TRY-COMPLETION is the function that does the completion, and
ALL-COMPLETIONS is the function that lists the completions.")

(defcustom completion-styles '(basic)
  "List of completion styles to use."
  :type `(repeat (choice ,@(mapcar (lambda (x) (list 'const (car x)))
                                   completion-styles-alist)))
  :group 'minibuffer
  :version "23.1")

(defun completion-try-completion (string table pred)
  ;; The property `completion-styles' indicates that this functional
  ;; completion-table claims to take care of completion styles itself.
  ;; [I.e. It will most likely call us back at some point. ]
  (if (and (symbolp table) (get table 'completion-styles))
      (funcall table string pred nil)
    (completion--some (lambda (style)
                        (funcall (nth 1 (assq style completion-styles-alist))
                                 string table pred))
                      completion-styles)))

(defun completion-all-completions (string table pred)
  ;; The property `completion-styles' indicates that this functional
  ;; completion-table claims to take care of completion styles itself.
  ;; [I.e. It will most likely call us back at some point. ]
  (let ((completion-all-completions-with-base-size t))
    (if (and (symbolp table) (get table 'no-completion-styles))
        (funcall table string pred t)
      (completion--some (lambda (style)
                          (funcall (nth 2 (assq style completion-styles-alist))
                                   string table pred))
                        completion-styles))))

(defun minibuffer--bitset (modified completions exact)
  (logior (if modified    4 0)
          (if completions 2 0)
          (if exact       1 0)))

(defun completion--do-completion (&optional try-completion-function)
  "Do the completion and return a summary of what happened.
M = completion was performed, the text was Modified.
C = there were available Completions.
E = after completion we now have an Exact match.

 MCE
 000  0 no possible completion
 001  1 was already an exact and unique completion
 010  2 no completion happened
 011  3 was already an exact completion
 100  4 ??? impossible
 101  5 ??? impossible
 110  6 some completion happened
 111  7 completed to an exact completion"
  (let* ((beg (field-beginning))
         (end (point))
         (string (buffer-substring beg end))
         (completion (funcall (or try-completion-function
                                  'completion-try-completion)
                              string
                              minibuffer-completion-table
                              minibuffer-completion-predicate)))
    (cond
     ((null completion)
      (ding) (minibuffer-message "No match") (minibuffer--bitset nil nil nil))
     ((eq t completion) (minibuffer--bitset nil nil t)) ;Exact and unique match.
     (t
      ;; `completed' should be t if some completion was done, which doesn't
      ;; include simply changing the case of the entered string.  However,
      ;; for appearance, the string is rewritten if the case changes.
      (let ((completed (not (eq t (compare-strings completion nil nil
                                                   string nil nil t))))
	     (unchanged (eq t (compare-strings completion nil nil
					       string nil nil nil))))
        (unless unchanged

          ;; Insert in minibuffer the chars we got.
          (goto-char end)
          (insert completion)
          (delete-region beg end))

        (if (not (or unchanged completed))
	   ;; The case of the string changed, but that's all.  We're not sure
	   ;; whether this is a unique completion or not, so try again using
	   ;; the real case (this shouldn't recurse again, because the next
	   ;; time try-completion will return either t or the exact string).
           (completion--do-completion try-completion-function)

          ;; It did find a match.  Do we match some possibility exactly now?
          (let ((exact (test-completion (field-string)
					minibuffer-completion-table
					minibuffer-completion-predicate)))
            (unless completed
              ;; Show the completion table, if requested.
              (cond
               ((not exact)
                (if (case completion-auto-help
                      (lazy (eq this-command last-command))
                      (t completion-auto-help))
                    (minibuffer-completion-help)
                  (minibuffer-message "Next char not unique")))
               ;; If the last exact completion and this one were the same,
               ;; it means we've already given a "Complete but not unique"
               ;; message and the user's hit TAB again, so now we give him help.
               ((eq this-command last-command)
                (if completion-auto-help (minibuffer-completion-help)))))

            (minibuffer--bitset completed t exact))))))))

(defun minibuffer-complete ()
  "Complete the minibuffer contents as far as possible.
Return nil if there is no valid completion, else t.
If no characters can be completed, display a list of possible completions.
If you repeat this command after it displayed such a list,
scroll the window of possible completions."
  (interactive)
  ;; If the previous command was not this,
  ;; mark the completion buffer obsolete.
  (unless (eq this-command last-command)
    (setq minibuffer-scroll-window nil))

  (let ((window minibuffer-scroll-window))
    ;; If there's a fresh completion window with a live buffer,
    ;; and this command is repeated, scroll that window.
    (if (window-live-p window)
        (with-current-buffer (window-buffer window)
          (if (pos-visible-in-window-p (point-max) window)
	      ;; If end is in view, scroll up to the beginning.
	      (set-window-start window (point-min) nil)
	    ;; Else scroll down one screen.
	    (scroll-other-window))
	  nil)

      (case (completion--do-completion)
        (0 nil)
        (1 (goto-char (field-end))
           (minibuffer-message "Sole completion")
           t)
        (3 (goto-char (field-end))
           (minibuffer-message "Complete, but not unique")
           t)
        (t t)))))

(defun minibuffer-complete-and-exit ()
  "If the minibuffer contents is a valid completion then exit.
Otherwise try to complete it.  If completion leads to a valid completion,
a repetition of this command will exit."
  (interactive)
  (let ((beg (field-beginning))
        (end (field-end)))
    (cond
     ;; Allow user to specify null string
     ((= beg end) (exit-minibuffer))
     ((test-completion (buffer-substring beg end)
                       minibuffer-completion-table
                       minibuffer-completion-predicate)
      (when completion-ignore-case
        ;; Fixup case of the field, if necessary.
        (let* ((string (buffer-substring beg end))
               (compl (try-completion
                       string
                       minibuffer-completion-table
                       minibuffer-completion-predicate)))
          (when (and (stringp compl)
                     ;; If it weren't for this piece of paranoia, I'd replace
                     ;; the whole thing with a call to do-completion.
                     (= (length string) (length compl)))
            (goto-char end)
            (insert compl)
            (delete-region beg end))))
      (exit-minibuffer))

     ((eq minibuffer-completion-confirm 'confirm-only)
      ;; The user is permitted to exit with an input that's rejected
      ;; by test-completion, but at the condition to confirm her choice.
      (if (eq last-command this-command)
          (exit-minibuffer)
        (minibuffer-message "Confirm")
        nil))

     (t
      ;; Call do-completion, but ignore errors.
      (case (condition-case nil
                (completion--do-completion)
              (error 1))
        ((1 3) (exit-minibuffer))
        (7 (if (not minibuffer-completion-confirm)
               (exit-minibuffer)
             (minibuffer-message "Confirm")
             nil))
        (t nil))))))

(defun completion--try-word-completion (string table predicate)
  (let ((completion (completion-try-completion string table predicate)))
    (if (not (stringp completion))
        completion

      ;; If completion finds next char not unique,
      ;; consider adding a space or a hyphen.
      (when (= (length string) (length completion))
        (let ((exts '(" " "-"))
              tem)
          (while (and exts (not (stringp tem)))
            (setq tem (completion-try-completion
                       (concat string (pop exts))
                       table predicate)))
          (if (stringp tem) (setq completion tem))))

      ;; Completing a single word is actually more difficult than completing
      ;; as much as possible, because we first have to find the "current
      ;; position" in `completion' in order to find the end of the word
      ;; we're completing.  Normally, `string' is a prefix of `completion',
      ;; which makes it trivial to find the position, but with fancier
      ;; completion (plus env-var expansion, ...) `completion' might not
      ;; look anything like `string' at all.

      (when minibuffer-completing-file-name
	;; In order to minimize the problem mentioned above, let's try to
	;; reduce the different between `string' and `completion' by
	;; mirroring some of the work done in read-file-name-internal.
	(let ((substituted (condition-case nil
			       ;; Might fail when completing an env-var.
			       (substitute-in-file-name string)
			     (error string))))
	  (unless (eq string substituted)
	    (setq string substituted))))

      ;; Make buffer (before point) contain the longest match
      ;; of `string's tail and `completion's head.
      (let* ((startpos (max 0 (- (length string) (length completion))))
             (length (- (length string) startpos)))
        (while (and (> length 0)
                    (not (eq t (compare-strings string startpos nil
                                                completion 0 length
                                                completion-ignore-case))))
          (setq startpos (1+ startpos))
          (setq length (1- length)))

        (setq string (substring string startpos)))

      ;; Now `string' is a prefix of `completion'.

      ;; Otherwise cut after the first word.
      (if (string-match "\\W" completion (length string))
          ;; First find first word-break in the stuff found by completion.
          ;; i gets index in string of where to stop completing.
          (substring completion 0 (match-end 0))
        completion))))


(defun minibuffer-complete-word ()
  "Complete the minibuffer contents at most a single word.
After one word is completed as much as possible, a space or hyphen
is added, provided that matches some possible completion.
Return nil if there is no valid completion, else t."
  (interactive)
  (case (completion--do-completion 'completion--try-word-completion)
    (0 nil)
    (1 (goto-char (field-end))
       (minibuffer-message "Sole completion")
       t)
    (3 (goto-char (field-end))
       (minibuffer-message "Complete, but not unique")
       t)
    (t t)))

(defun completion--insert-strings (strings)
  "Insert a list of STRINGS into the current buffer.
Uses columns to keep the listing readable but compact.
It also eliminates runs of equal strings."
  (when (consp strings)
    (let* ((length (apply 'max
			  (mapcar (lambda (s)
				    (if (consp s)
					(+ (length (car s)) (length (cadr s)))
				      (length s)))
				  strings)))
	   (window (get-buffer-window (current-buffer) 0))
	   (wwidth (if window (1- (window-width window)) 79))
	   (columns (min
		     ;; At least 2 columns; at least 2 spaces between columns.
		     (max 2 (/ wwidth (+ 2 length)))
		     ;; Don't allocate more columns than we can fill.
		     ;; Windows can't show less than 3 lines anyway.
		     (max 1 (/ (length strings) 2))))
	   (colwidth (/ wwidth columns))
           (column 0)
	   (laststring nil))
      ;; The insertion should be "sensible" no matter what choices were made
      ;; for the parameters above.
      (dolist (str strings)
	(unless (equal laststring str)  ; Remove (consecutive) duplicates.
	  (setq laststring str)
	  (unless (bolp)
            (insert " \t")
            (setq column (+ column colwidth))
            ;; Leave the space unpropertized so that in the case we're
            ;; already past the goal column, there is still
            ;; a space displayed.
            (set-text-properties (- (point) 1) (point)
                                 ;; We can't just set tab-width, because
                                 ;; completion-setup-function will kill all
                                 ;; local variables :-(
                                 `(display (space :align-to ,column))))
	  (when (< wwidth (+ (max colwidth
				  (if (consp str)
				      (+ (length (car str)) (length (cadr str)))
				    (length str)))
			     column))
	    (delete-char -2) (insert "\n") (setq column 0))
	  (if (not (consp str))
	      (put-text-property (point) (progn (insert str) (point))
				 'mouse-face 'highlight)
	    (put-text-property (point) (progn (insert (car str)) (point))
			       'mouse-face 'highlight)
	    (put-text-property (point) (progn (insert (cadr str)) (point))
                               'mouse-face nil)))))))

(defvar completion-common-substring)

(defvar completion-setup-hook nil
  "Normal hook run at the end of setting up a completion list buffer.
When this hook is run, the current buffer is the one in which the
command to display the completion list buffer was run.
The completion list buffer is available as the value of `standard-output'.
The common prefix substring for completion may be available as the value
of `completion-common-substring'.  See also `display-completion-list'.")

(defun display-completion-list (completions &optional common-substring)
  "Display the list of completions, COMPLETIONS, using `standard-output'.
Each element may be just a symbol or string
or may be a list of two strings to be printed as if concatenated.
If it is a list of two strings, the first is the actual completion
alternative, the second serves as annotation.
`standard-output' must be a buffer.
The actual completion alternatives, as inserted, are given `mouse-face'
properties of `highlight'.
At the end, this runs the normal hook `completion-setup-hook'.
It can find the completion buffer in `standard-output'.
The optional second arg COMMON-SUBSTRING is a string.
It is used to put faces, `completions-first-difference' and
`completions-common-part' on the completion buffer.  The
`completions-common-part' face is put on the common substring
specified by COMMON-SUBSTRING.  If COMMON-SUBSTRING is nil
and the current buffer is not the minibuffer, the faces are not put.
Internally, COMMON-SUBSTRING is bound to `completion-common-substring'
during running `completion-setup-hook'."
  (if (not (bufferp standard-output))
      ;; This *never* (ever) happens, so there's no point trying to be clever.
      (with-temp-buffer
	(let ((standard-output (current-buffer))
	      (completion-setup-hook nil))
	  (display-completion-list completions))
	(princ (buffer-string)))

    (with-current-buffer standard-output
      (goto-char (point-max))
      (if (null completions)
	  (insert "There are no possible completions of what you have typed.")

	(insert "Possible completions are:\n")
        (let ((last (last completions)))
          ;; Get the base-size from the tail of the list.
          (set (make-local-variable 'completion-base-size) (or (cdr last) 0))
          (setcdr last nil)) ;Make completions a properly nil-terminated list.
	(completion--insert-strings completions))))

  (let ((completion-common-substring common-substring))
    (run-hooks 'completion-setup-hook))
  nil)

(defun minibuffer-completion-help ()
  "Display a list of possible completions of the current minibuffer contents."
  (interactive)
  (message "Making completion list...")
  (let* ((string (field-string))
         (completions (completion-all-completions
                       string
                       minibuffer-completion-table
                       minibuffer-completion-predicate)))
    (message nil)
    (if (and completions
             (or (consp (cdr completions))
                 (not (equal (car completions) string))))
        (with-output-to-temp-buffer "*Completions*"
          (let* ((last (last completions))
                 (base-size (cdr last)))
            ;; Remove the base-size tail because `sort' requires a properly
            ;; nil-terminated list.
            (when last (setcdr last nil))
            (display-completion-list (nconc (sort completions 'string-lessp)
                                            base-size))))

      ;; If there are no completions, or if the current input is already the
      ;; only possible completion, then hide (previous&stale) completions.
      (let ((window (and (get-buffer "*Completions*")
                         (get-buffer-window "*Completions*" 0))))
        (when (and (window-live-p window) (window-dedicated-p window))
          (condition-case ()
              (delete-window window)
            (error (iconify-frame (window-frame window))))))
      (ding)
      (minibuffer-message
       (if completions "Sole completion" "No completions")))
    nil))

(defun exit-minibuffer ()
  "Terminate this minibuffer argument."
  (interactive)
  ;; If the command that uses this has made modifications in the minibuffer,
  ;; we don't want them to cause deactivation of the mark in the original
  ;; buffer.
  ;; A better solution would be to make deactivate-mark buffer-local
  ;; (or to turn it into a list of buffers, ...), but in the mean time,
  ;; this should do the trick in most cases.
  (setq deactivate-mark nil)
  (throw 'exit nil))

(defun self-insert-and-exit ()
  "Terminate minibuffer input."
  (interactive)
  (if (characterp last-command-char)
      (call-interactively 'self-insert-command)
    (ding))
  (exit-minibuffer))

(defun minibuffer--double-dollars (str)
  (replace-regexp-in-string "\\$" "$$" str))

(defun completion--make-envvar-table ()
  (mapcar (lambda (enventry)
            (substring enventry 0 (string-match "=" enventry)))
          process-environment))

(defun completion--embedded-envvar-table (string pred action)
  (when (string-match (concat "\\(?:^\\|[^$]\\(?:\\$\\$\\)*\\)"
                              "$\\([[:alnum:]_]*\\|{\\([^}]*\\)\\)\\'")
                      string)
    (let* ((beg (or (match-beginning 2) (match-beginning 1)))
           (table (completion--make-envvar-table))
           (prefix (substring string 0 beg)))
      (if (eq (aref string (1- beg)) ?{)
          (setq table (apply-partially 'completion-table-with-terminator
                                       "}" table)))
      (completion-table-with-context prefix table
                                     (substring string beg)
                                     pred action))))

(defun completion--file-name-table (string pred action)
  "Internal subroutine for `read-file-name'.  Do not call this."
  (if (and (zerop (length string)) (eq 'lambda action))
      nil                               ; FIXME: why?
    (let* ((dir (if (stringp pred)
                    ;; It used to be that `pred' was abused to pass `dir'
                    ;; as an argument.
                    (prog1 (expand-file-name pred) (setq pred nil))
                  default-directory))
           (str (condition-case nil
                    (substitute-in-file-name string)
                  (error string)))
           (name (file-name-nondirectory str))
           (specdir (file-name-directory str))
           (realdir (if specdir (expand-file-name specdir dir)
                      (file-name-as-directory dir))))

      (cond
       ((null action)
        (let ((comp (file-name-completion name realdir
                                          read-file-name-predicate)))
          (if (stringp comp)
              ;; Requote the $s before returning the completion.
              (minibuffer--double-dollars (concat specdir comp))
            ;; Requote the $s before checking for changes.
            (setq str (minibuffer--double-dollars str))
            (if (string-equal string str)
                comp
              ;; If there's no real completion, but substitute-in-file-name
              ;; changed the string, then return the new string.
              str))))

       ((eq action t)
        (let ((all (file-name-all-completions name realdir))
              ;; Actually, this is not always right in the presence of
              ;; envvars, but there's not much we can do, I think.
              (base-size (length (file-name-directory string))))

          ;; Check the predicate, if necessary.
          (unless (memq read-file-name-predicate '(nil file-exists-p))
            (let ((comp ())
                  (pred
                   (if (eq read-file-name-predicate 'file-directory-p)
                       ;; Brute-force speed up for directory checking:
                       ;; Discard strings which don't end in a slash.
                       (lambda (s)
                         (let ((len (length s)))
                           (and (> len 0) (eq (aref s (1- len)) ?/))))
                     ;; Must do it the hard (and slow) way.
                     read-file-name-predicate)))
              (let ((default-directory realdir))
                (dolist (tem all)
                  (if (funcall pred tem) (push tem comp))))
              (setq all (nreverse comp))))

          (if (and completion-all-completions-with-base-size (consp all))
              ;; Add base-size, but only if the list is non-empty.
              (nconc all base-size))

          all))

       (t
        ;; Only other case actually used is ACTION = lambda.
        (let ((default-directory dir))
          (funcall (or read-file-name-predicate 'file-exists-p) str)))))))

(defalias 'read-file-name-internal
  (completion-table-in-turn 'completion--embedded-envvar-table
                            'completion--file-name-table)
  "Internal subroutine for `read-file-name'.  Do not call this.")

(defun internal-complete-buffer-except (&optional buffer)
  "Perform completion on all buffers excluding BUFFER.
Like `internal-complete-buffer', but removes BUFFER from the completion list."
  (lexical-let ((except (if (stringp buffer) buffer (buffer-name buffer))))
    (apply-partially 'completion-table-with-predicate
		     'internal-complete-buffer
		     (lambda (name)
		       (not (equal (if (consp name) (car name) name) except)))
		     nil)))

(provide 'minibuffer)

;; arch-tag: ef8a0a15-1080-4790-a754-04017c02f08f
;;; minibuffer.el ends here
