;;; apropos.el --- apropos commands for users and programmers

;; Copyright (C) 1989,94,1995,2001,02,03,2004  Free Software Foundation, Inc.

;; Author: Joe Wells <jbw@bigbird.bu.edu>
;; Rewritten: Daniel Pfeiffer <occitan@esperanto.org>
;; Keywords: help

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

;; The ideas for this package were derived from the C code in
;; src/keymap.c and elsewhere.  The functions in this file should
;; always be byte-compiled for speed.  Someone should rewrite this in
;; C (as part of src/keymap.c) for speed.

;; The idea for super-apropos is based on the original implementation
;; by Lynn Slater <lrs@esl.com>.

;; History:
;; Fixed bug, current-local-map can return nil.
;; Change, doesn't calculate key-bindings unless needed.
;; Added super-apropos capability, changed print functions.
;;; Made fast-apropos and super-apropos share code.
;;; Sped up fast-apropos again.
;; Added apropos-do-all option.
;;; Added fast-command-apropos.
;; Changed doc strings to comments for helping functions.
;;; Made doc file buffer read-only, buried it.
;; Only call substitute-command-keys if do-all set.

;; Optionally use configurable faces to make the output more legible.
;; Differentiate between command, function and macro.
;; Apropos-command (ex command-apropos) does cmd and optionally user var.
;; Apropos shows all 3 aspects of symbols (fn, var and plist)
;; Apropos-documentation (ex super-apropos) now finds all it should.
;; New apropos-value snoops through all values and optionally plists.
;; Reading DOC file doesn't load nroff.
;; Added hypertext following of documentation, mouse-2 on variable gives value
;;   from buffer in active window.

;;; Code:

(require 'button)
(eval-when-compile (require 'cl))

(defgroup apropos nil
  "Apropos commands for users and programmers"
  :group 'help
  :prefix "apropos")

;; I see a degradation of maybe 10-20% only.
(defcustom apropos-do-all nil
  "*Whether the apropos commands should do more.

Slows them down more or less.  Set this non-nil if you have a fast machine."
  :group 'apropos
  :type 'boolean)


(defcustom apropos-symbol-face 'bold
  "*Face for symbol name in Apropos output, or nil for none."
  :group 'apropos
  :type 'face)

(defcustom apropos-keybinding-face 'underline
  "*Face for lists of keybinding in Apropos output, or nil for none."
  :group 'apropos
  :type 'face)

(defcustom apropos-label-face 'italic
  "*Face for label (`Command', `Variable' ...) in Apropos output.
A value of nil means don't use any special font for them, and also
turns off mouse highlighting."
  :group 'apropos
  :type 'face)

(defcustom apropos-property-face 'bold-italic
  "*Face for property name in apropos output, or nil for none."
  :group 'apropos
  :type 'face)

(defcustom apropos-match-face 'secondary-selection
  "*Face for matching text in Apropos documentation/value, or nil for none.
This applies when you look for matches in the documentation or variable value
for the regexp; the part that matches gets displayed in this font."
  :group 'apropos
  :type 'face)

(defcustom apropos-sort-by-scores nil
  "*Non-nil means sort matches by scores; best match is shown first.
The computed score is shown for each match."
  :group 'apropos
  :type 'boolean)

(defvar apropos-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map button-buffer-map)
    ;; Use `apropos-follow' instead of just using the button
    ;; definition of RET, so that users can use it anywhere in an
    ;; apropos item, not just on top of a button.
    (define-key map "\C-m" 'apropos-follow)
    (define-key map " "    'scroll-up)
    (define-key map "\177" 'scroll-down)
    (define-key map "q"    'quit-window)
    map)
  "Keymap used in Apropos mode.")

(defvar apropos-mode-hook nil
  "*Hook run when mode is turned on.")

(defvar apropos-regexp nil
  "Regexp used in current apropos run.")

(defvar apropos-orig-regexp nil
  "Regexp as entered by user.")

(defvar apropos-all-regexp nil
  "Regexp matching apropos-all-words.")

(defvar apropos-files-scanned ()
  "List of elc files already scanned in current run of `apropos-documentation'.")

(defvar apropos-accumulator ()
  "Alist of symbols already found in current apropos run.")

(defvar apropos-item ()
  "Current item in or for `apropos-accumulator'.")

(defvar apropos-synonyms '(
  ("find" "open" "edit")
  ("kill" "cut")
  ("yank" "paste"))
  "List of synonyms known by apropos.
Each element is a list of words where the first word is the standard emacs
term, and the rest of the words are alternative terms.")

(defvar apropos-words ()
  "Current list of words.")

(defvar apropos-all-words ()
  "Current list of words and synonyms.")


;;; Button types used by apropos

(define-button-type 'apropos-symbol
  'face apropos-symbol-face
  'help-echo "mouse-2, RET: Display more help on this symbol"
  'action #'apropos-symbol-button-display-help
  'skip t)

(defun apropos-symbol-button-display-help (button)
  "Display further help for the `apropos-symbol' button BUTTON."
  (button-activate
   (or (apropos-next-label-button (button-start button))
       (error "There is nothing to follow for `%s'" (button-label button)))))

(define-button-type 'apropos-function
  'apropos-label "Function"
  'action (lambda (button)
	    (describe-function (button-get button 'apropos-symbol)))
  'help-echo "mouse-2, RET: Display more help on this function")
(define-button-type 'apropos-macro
  'apropos-label "Macro"
  'action (lambda (button)
	    (describe-function (button-get button 'apropos-symbol)))
  'help-echo "mouse-2, RET: Display more help on this macro")
(define-button-type 'apropos-command
  'apropos-label "Command"
  'action (lambda (button)
	    (describe-function (button-get button 'apropos-symbol)))
  'help-echo "mouse-2, RET: Display more help on this command")

;; We used to use `customize-variable-other-window' instead for a
;; customizable variable, but that is slow.  It is better to show an
;; ordinary help buffer and let the user click on the customization
;; button in that buffer, if he wants to.
;; Likewise for `customize-face-other-window'.
(define-button-type 'apropos-variable
  'apropos-label "Variable"
  'help-echo "mouse-2, RET: Display more help on this variable"
  'action (lambda (button)
	    (describe-variable (button-get button 'apropos-symbol))))

(define-button-type 'apropos-face
  'apropos-label "Face"
  'help-echo "mouse-2, RET: Display more help on this face"
  'action (lambda (button)
	    (describe-face (button-get button 'apropos-symbol))))

(define-button-type 'apropos-group
  'apropos-label "Group"
  'help-echo "mouse-2, RET: Display more help on this group"
  'action (lambda (button)
	    (customize-group-other-window
	     (button-get button 'apropos-symbol))))

(define-button-type 'apropos-widget
  'apropos-label "Widget"
  'help-echo "mouse-2, RET: Display more help on this widget"
  'action (lambda (button)
	    (widget-browse-other-window (button-get button 'apropos-symbol))))

(define-button-type 'apropos-plist
  'apropos-label "Plist"
  'help-echo "mouse-2, RET: Display more help on this plist"
  'action (lambda (button)
	    (apropos-describe-plist (button-get button 'apropos-symbol))))

(defun apropos-next-label-button (pos)
  "Return the next apropos label button after POS, or nil if there's none.
Will also return nil if more than one `apropos-symbol' button is encountered
before finding a label."
  (let* ((button (next-button pos t))
	 (already-hit-symbol nil)
	 (label (and button (button-get button 'apropos-label)))
	 (type (and button (button-get button 'type))))
    (while (and button
		(not label)
		(or (not (eq type 'apropos-symbol))
		    (not already-hit-symbol)))
      (when (eq type 'apropos-symbol)
	(setq already-hit-symbol t))
      (setq button (next-button (button-start button)))
      (when button
	(setq label (button-get button 'apropos-label))
	(setq type (button-get button 'type))))
    (and label button)))


(defun apropos-words-to-regexp (words wild)
  "Make regexp matching any two of the words in WORDS."
  (concat "\\("
	  (mapconcat 'identity words "\\|")
	  "\\)"
	  (if (cdr words)
	      (concat wild
		      "\\("
		      (mapconcat 'identity words "\\|")
		      "\\)")
	    "")))

(defun apropos-rewrite-regexp (regexp)
  "Rewrite a list of words to a regexp matching all permutations.
If REGEXP is already a regexp, don't modify it."
  (setq apropos-orig-regexp regexp)
  (setq apropos-words () apropos-all-words ())
  (if (string-equal (regexp-quote regexp) regexp)
      ;; We don't actually make a regexp matching all permutations.
      ;; Instead, for e.g. "a b c", we make a regexp matching
      ;; any combination of two or more words like this:
      ;; (a|b|c).*(a|b|c) which may give some false matches,
      ;; but as long as it also gives the right ones, that's ok.
      (let ((words (split-string regexp "[ \t]+")))
	(dolist (word words)
	  (let ((syn apropos-synonyms) (s word) (a word))
	    (while syn
	      (if (member word (car syn))
		  (progn
		    (setq a (mapconcat 'identity (car syn) "\\|"))
		    (if (member word (cdr (car syn)))
			(setq s a))
		    (setq syn nil))
		(setq syn (cdr syn))))
	    (setq apropos-words (cons s apropos-words)
		  apropos-all-words (cons a apropos-all-words))))
	(setq apropos-all-regexp (apropos-words-to-regexp apropos-all-words ".+"))
	(apropos-words-to-regexp apropos-words ".*?"))
    (setq apropos-all-regexp regexp)))

(defun apropos-calc-scores (str words)
  "Return apropos scores for string STR matching WORDS.
Value is a list of offsets of the words into the string."
  (let ((scores ())
	i)
    (if words
	(dolist (word words scores)
	  (if (setq i (string-match word str))
	      (setq scores (cons i scores))))
      ;; Return list of start and end position of regexp
      (string-match apropos-regexp str)
      (list (match-beginning 0) (match-end 0)))))

(defun apropos-score-str (str)
  "Return apropos score for string STR."
  (if str
      (let* (
	     (l (length str))
	     (score (- (/ l 10)))
	    i)
	(dolist (s (apropos-calc-scores str apropos-all-words) score)
	  (setq score (+ score 1000 (/ (* (- l s) 1000) l)))))
      0))

(defun apropos-score-doc (doc)
  "Return apropos score for documentation string DOC."
  (if doc
      (let ((score 0)
	    (l (length doc))
	    i)
	(dolist (s (apropos-calc-scores doc apropos-all-words) score)
	  (setq score (+ score 50 (/ (* (- l s) 50) l)))))
      0))

(defun apropos-score-symbol (symbol &optional weight)
  "Return apropos score for SYMBOL."
  (setq symbol (symbol-name symbol))
  (let ((score 0)
	(l (length symbol))
	i)
    (dolist (s (apropos-calc-scores symbol apropos-words) (* score (or weight 3)))
      (setq score (+ score (- 60 l) (/ (* (- l s) 60) l))))))

(defun apropos-true-hit (str words)
  "Return t if STR is a genuine hit.
This may fail if only one of the keywords is matched more than once.
This requires that at least 2 keywords (unless only one was given)."
  (or (not str)
      (not words)
      (not (cdr words))
      (> (length (apropos-calc-scores str words)) 1)))

(defun apropos-false-hit-symbol (symbol)
  "Return t if SYMBOL is not really matched by the current keywords."
  (not (apropos-true-hit (symbol-name symbol) apropos-words)))

(defun apropos-false-hit-str (str)
  "Return t if STR is not really matched by the current keywords."
  (not (apropos-true-hit str apropos-words)))

(defun apropos-true-hit-doc (doc)
  "Return t if DOC is really matched by the current keywords."
  (apropos-true-hit doc apropos-all-words))

(define-derived-mode apropos-mode fundamental-mode "Apropos"
  "Major mode for following hyperlinks in output of apropos commands.

\\{apropos-mode-map}")

;;;###autoload
(defun apropos-variable (regexp &optional do-all)
  "Show user variables that match REGEXP.
With optional prefix DO-ALL or if `apropos-do-all' is non-nil, also show
normal variables."
  (interactive (list (read-string
                      (concat "Apropos "
                              (if (or current-prefix-arg apropos-do-all)
				  "variable"
				"user option")
                              " (regexp or words): "))
                     current-prefix-arg))
  (apropos-command regexp nil
		   (if (or do-all apropos-do-all)
		       #'(lambda (symbol)
			   (and (boundp symbol)
				(get symbol 'variable-documentation)))
		     'user-variable-p)))

;; For auld lang syne:
;;;###autoload
(defalias 'command-apropos 'apropos-command)
;;;###autoload
(defun apropos-command (apropos-regexp &optional do-all var-predicate)
  "Show commands (interactively callable functions) that match APROPOS-REGEXP.
With optional prefix DO-ALL, or if `apropos-do-all' is non-nil, also show
noninteractive functions.

If VAR-PREDICATE is non-nil, show only variables, and only those that
satisfy the predicate VAR-PREDICATE."
  (interactive (list (read-string (concat
				   "Apropos command "
				   (if (or current-prefix-arg
					   apropos-do-all)
				       "or function ")
				   "(regexp or words): "))
		     current-prefix-arg))
  (setq apropos-regexp (apropos-rewrite-regexp apropos-regexp))
  (let ((message
	 (let ((standard-output (get-buffer-create "*Apropos*")))
	   (print-help-return-message 'identity))))
    (or do-all (setq do-all apropos-do-all))
    (setq apropos-accumulator
	  (apropos-internal apropos-regexp
			    (or var-predicate
				(if do-all 'functionp 'commandp))))
    (let ((tem apropos-accumulator))
      (while tem
	(if (or (get (car tem) 'apropos-inhibit)
		(apropos-false-hit-symbol (car tem)))
	    (setq apropos-accumulator (delq (car tem) apropos-accumulator)))
	(setq tem (cdr tem))))
    (let ((p apropos-accumulator)
	  doc symbol score)
      (while p
	(setcar p (list
		   (setq symbol (car p))
		   (setq score (apropos-score-symbol symbol))
		   (unless var-predicate
		     (if (functionp symbol)
			 (if (setq doc (documentation symbol t))
			     (progn
			       (setq score (+ score (apropos-score-doc doc)))
			       (substring doc 0 (string-match "\n" doc)))
			   "(not documented)")))
		   (and var-predicate
			(funcall var-predicate symbol)
			(if (setq doc (documentation-property
				       symbol 'variable-documentation t))
			     (progn
			       (setq score (+ score (apropos-score-doc doc)))
			       (substring doc 0
					  (string-match "\n" doc)))))))
	(setcar (cdr (car p)) score)
	(setq p (cdr p))))
    (and (apropos-print t nil)
	 message
	 (message message))))


;;;###autoload
(defun apropos-documentation-property (symbol property raw)
  "Like (documentation-property SYMBOL PROPERTY RAW) but handle errors."
  (condition-case ()
      (let ((doc (documentation-property symbol property raw)))
	(if doc (substring doc 0 (string-match "\n" doc))
	  "(not documented)"))
    (error "(error retrieving documentation)")))


;;;###autoload
(defun apropos (apropos-regexp &optional do-all)
  "Show all bound symbols whose names match APROPOS-REGEXP.
With optional prefix DO-ALL or if `apropos-do-all' is non-nil, also
show unbound symbols and key bindings, which is a little more
time-consuming.  Returns list of symbols and documentation found."
  (interactive "sApropos symbol (regexp or words): \nP")
  (setq apropos-regexp (apropos-rewrite-regexp apropos-regexp))
  (apropos-symbols-internal
   (apropos-internal apropos-regexp
			  (and (not do-all)
			       (not apropos-do-all)
			       (lambda (symbol)
				 (or (fboundp symbol)
				     (boundp symbol)
				     (facep symbol)
				     (symbol-plist symbol)))))
   (or do-all apropos-do-all)))

(defun apropos-symbols-internal (symbols keys &optional text)
  ;; Filter out entries that are marked as apropos-inhibit.
  (let ((all nil))
    (dolist (symbol symbols)
      (unless (get symbol 'apropos-inhibit)
	(push symbol all)))
    (setq symbols all))
  (let ((apropos-accumulator
	 (mapcar
	  (lambda (symbol)
	    (let (doc properties)
	      (list
	       symbol
	       (apropos-score-symbol symbol)
	       (when (fboundp symbol)
		 (if (setq doc (condition-case nil
				   (documentation symbol t)
				 (void-function
				  "(alias for undefined function)")
				 (error
				  "(can't retrieve function documentation)")))
		     (substring doc 0 (string-match "\n" doc))
		   "(not documented)"))
	       (when (boundp symbol)
		 (apropos-documentation-property
		    symbol 'variable-documentation t))
		 (when (setq properties (symbol-plist symbol))
		   (setq doc (list (car properties)))
		   (while (setq properties (cdr (cdr properties)))
		     (setq doc (cons (car properties) doc)))
		   (mapconcat #'symbol-name (nreverse doc) " "))
		 (when (get symbol 'widget-type)
		   (apropos-documentation-property
		    symbol 'widget-documentation t))
	       (when (facep symbol)
		 (apropos-documentation-property
		  symbol 'face-documentation t))
	       (when (get symbol 'custom-group)
		   (apropos-documentation-property
		    symbol 'group-documentation t)))))
	  symbols)))
    (apropos-print keys nil text)))


;;;###autoload
(defun apropos-value (apropos-regexp &optional do-all)
  "Show all symbols whose value's printed image matches APROPOS-REGEXP.
With optional prefix DO-ALL or if `apropos-do-all' is non-nil, also looks
at the function and at the names and values of properties.
Returns list of symbols and values found."
  (interactive "sApropos value (regexp or words): \nP")
  (setq apropos-regexp (apropos-rewrite-regexp apropos-regexp))
  (or do-all (setq do-all apropos-do-all))
  (setq apropos-accumulator ())
   (let (f v p)
     (mapatoms
      (lambda (symbol)
	(setq f nil v nil p nil)
	(or (memq symbol '(apropos-regexp
			   apropos-orig-regexp apropos-all-regexp
			   apropos-words apropos-all-words
			   do-all apropos-accumulator
			   symbol f v p))
	    (setq v (apropos-value-internal 'boundp symbol 'symbol-value)))
	(if do-all
	    (setq f (apropos-value-internal 'fboundp symbol 'symbol-function)
		  p (apropos-format-plist symbol "\n    " t)))
	(if (apropos-false-hit-str v)
	    (setq v nil))
	(if (apropos-false-hit-str f)
	    (setq f nil))
	(if (apropos-false-hit-str p)
	    (setq p nil))
	(if (or f v p)
	    (setq apropos-accumulator (cons (list symbol
						  (+ (apropos-score-str f)
						     (apropos-score-str v)
						     (apropos-score-str p))
						  f v p)
					    apropos-accumulator))))))
  (apropos-print nil "\n----------------\n"))


;;;###autoload
(defun apropos-documentation (apropos-regexp &optional do-all)
  "Show symbols whose documentation contain matches for APROPOS-REGEXP.
With optional prefix DO-ALL or if `apropos-do-all' is non-nil, also use
documentation that is not stored in the documentation file and show key
bindings.
Returns list of symbols and documentation found."
  (interactive "sApropos documentation (regexp or words): \nP")
  (setq apropos-regexp (apropos-rewrite-regexp apropos-regexp))
  (or do-all (setq do-all apropos-do-all))
  (setq apropos-accumulator () apropos-files-scanned ())
  (let ((standard-input (get-buffer-create " apropos-temp"))
	f v sf sv)
    (unwind-protect
	(save-excursion
	  (set-buffer standard-input)
	  (apropos-documentation-check-doc-file)
	  (if do-all
	      (mapatoms
	       (lambda (symbol)
		 (setq f (apropos-safe-documentation symbol)
		       v (get symbol 'variable-documentation))
		 (if (integerp v) (setq v))
		 (setq f (apropos-documentation-internal f)
		       v (apropos-documentation-internal v))
		 (setq sf (apropos-score-doc f)
		       sv (apropos-score-doc v))
		 (if (or f v)
		     (if (setq apropos-item
			       (cdr (assq symbol apropos-accumulator)))
			 (progn
			   (if f
			       (progn
				 (setcar (nthcdr 1 apropos-item) f)
				 (setcar apropos-item (+ (car apropos-item) sf))))
			   (if v
			       (progn
				 (setcar (nthcdr 2 apropos-item) v)
				 (setcar apropos-item (+ (car apropos-item) sv)))))
		       (setq apropos-accumulator
			     (cons (list symbol
					 (+ (apropos-score-symbol symbol 2) sf sv)
					 f v)
				   apropos-accumulator)))))))
	  (apropos-print nil "\n----------------\n"))
      (kill-buffer standard-input))))


(defun apropos-value-internal (predicate symbol function)
  (if (funcall predicate symbol)
      (progn
	(setq symbol (prin1-to-string (funcall function symbol)))
	(if (string-match apropos-regexp symbol)
	    (progn
	      (if apropos-match-face
		  (put-text-property (match-beginning 0) (match-end 0)
				     'face apropos-match-face
				     symbol))
	      symbol)))))

(defun apropos-documentation-internal (doc)
  (if (consp doc)
      (apropos-documentation-check-elc-file (car doc))
    (and doc
	 (string-match apropos-all-regexp doc)
	 (save-match-data (apropos-true-hit-doc doc))
	 (progn
	   (if apropos-match-face
	       (put-text-property (match-beginning 0)
				  (match-end 0)
				  'face apropos-match-face
				  (setq doc (copy-sequence doc))))
	   doc))))

(defun apropos-format-plist (pl sep &optional compare)
  (setq pl (symbol-plist pl))
  (let (p p-out)
    (while pl
      (setq p (format "%s %S" (car pl) (nth 1 pl)))
      (if (or (not compare) (string-match apropos-regexp p))
	  (if apropos-property-face
	      (put-text-property 0 (length (symbol-name (car pl)))
				 'face apropos-property-face p))
	(setq p nil))
      (if p
	  (progn
	    (and compare apropos-match-face
		 (put-text-property (match-beginning 0) (match-end 0)
				    'face apropos-match-face
				    p))
	    (setq p-out (concat p-out (if p-out sep) p))))
      (setq pl (nthcdr 2 pl)))
    p-out))


;; Finds all documentation related to APROPOS-REGEXP in internal-doc-file-name.

(defun apropos-documentation-check-doc-file ()
  (let (type symbol (sepa 2) sepb beg end)
    (insert ?\^_)
    (backward-char)
    (insert-file-contents (concat doc-directory internal-doc-file-name))
    (forward-char)
    (while (save-excursion
	     (setq sepb (search-forward "\^_"))
	     (not (eobp)))
      (beginning-of-line 2)
      (if (save-restriction
	    (narrow-to-region (point) (1- sepb))
	    (re-search-forward apropos-all-regexp nil t))
	  (progn
	    (setq beg (match-beginning 0)
		  end (point))
	    (goto-char (1+ sepa))
	    (setq type (if (eq ?F (preceding-char))
			   2	; function documentation
			 3)		; variable documentation
		  symbol (read)
		  beg (- beg (point) 1)
		  end (- end (point) 1)
		  doc (buffer-substring (1+ (point)) (1- sepb)))
	    (when (apropos-true-hit-doc doc)
	      (or (and (setq apropos-item (assq symbol apropos-accumulator))
		       (setcar (cdr apropos-item)
			       (+ (cadr apropos-item) (apropos-score-doc doc))))
		  (setq apropos-item (list symbol
					   (+ (apropos-score-symbol symbol 2)
					      (apropos-score-doc doc))
					   nil nil)
			apropos-accumulator (cons apropos-item
						  apropos-accumulator)))
	      (if apropos-match-face
		  (put-text-property beg end 'face apropos-match-face doc))
	      (setcar (nthcdr type apropos-item) doc))))
      (setq sepa (goto-char sepb)))))

(defun apropos-documentation-check-elc-file (file)
  (if (member file apropos-files-scanned)
      nil
    (let (symbol doc beg end this-is-a-variable)
      (setq apropos-files-scanned (cons file apropos-files-scanned))
      (erase-buffer)
      (insert-file-contents file)
      (while (search-forward "\n#@" nil t)
	;; Read the comment length, and advance over it.
	(setq end (read)
	      beg (1+ (point))
	      end (+ (point) end -1))
	(forward-char)
	(if (save-restriction
	      ;; match ^ and $ relative to doc string
	      (narrow-to-region beg end)
	      (re-search-forward apropos-all-regexp nil t))
	    (progn
	      (goto-char (+ end 2))
	      (setq doc (buffer-substring beg end)
		    end (- (match-end 0) beg)
		    beg (- (match-beginning 0) beg))
	      (when (apropos-true-hit-doc doc)
		(setq this-is-a-variable (looking-at "(def\\(var\\|const\\) ")
		      symbol (progn
			       (skip-chars-forward "(a-z")
			       (forward-char)
			       (read))
		      symbol (if (consp symbol)
				 (nth 1 symbol)
			       symbol))
		(if (if this-is-a-variable
			(get symbol 'variable-documentation)
		      (and (fboundp symbol) (apropos-safe-documentation symbol)))
		    (progn
		      (or (and (setq apropos-item (assq symbol apropos-accumulator))
			       (setcar (cdr apropos-item)
				       (+ (cadr apropos-item) (apropos-score-doc doc))))
			  (setq apropos-item (list symbol
						   (+ (apropos-score-symbol symbol 2)
						      (apropos-score-doc doc))
						   nil nil)
				apropos-accumulator (cons apropos-item
							  apropos-accumulator)))
		      (if apropos-match-face
			  (put-text-property beg end 'face apropos-match-face
					     doc))
		      (setcar (nthcdr (if this-is-a-variable 3 2)
				      apropos-item)
			      doc))))))))))



(defun apropos-safe-documentation (function)
  "Like `documentation', except it avoids calling `get_doc_string'.
Will return nil instead."
  (while (and function (symbolp function))
    (setq function (if (fboundp function)
		       (symbol-function function))))
  (if (eq (car-safe function) 'macro)
      (setq function (cdr function)))
  (setq function (if (byte-code-function-p function)
		     (if (> (length function) 4)
			 (aref function 4))
		   (if (eq (car-safe function) 'autoload)
		       (nth 2 function)
		     (if (eq (car-safe function) 'lambda)
			 (if (stringp (nth 2 function))
			     (nth 2 function)
			   (if (stringp (nth 3 function))
			       (nth 3 function)))))))
  (if (integerp function)
      nil
    function))


(defun apropos-print (do-keys spacing &optional text)
  "Output result of apropos searching into buffer `*Apropos*'.
The value of `apropos-accumulator' is the list of items to output.
Each element should have the format
 (SYMBOL SCORE FN-DOC VAR-DOC [PLIST-DOC WIDGET-DOC FACE-DOC GROUP-DOC]).
The return value is the list that was in `apropos-accumulator', sorted
alphabetically by symbol name; but this function also sets
`apropos-accumulator' to nil before returning.

If SPACING is non-nil, it should be a string; separate items with that string.
If non-nil TEXT is a string that will be printed as a heading."
  (if (null apropos-accumulator)
      (message "No apropos matches for `%s'" apropos-orig-regexp)
    (setq apropos-accumulator
	  (sort apropos-accumulator
		(lambda (a b)
		  ;; Don't sort by score if user can't see the score.
		  ;; It would be confusing.  -- rms.
		  (if apropos-sort-by-scores
		      (or (> (cadr a) (cadr b))
			  (and (= (cadr a) (cadr b))
			       (string-lessp (car a) (car b))))
		    (string-lessp (car a) (car b))))))
    (with-output-to-temp-buffer "*Apropos*"
      (let ((p apropos-accumulator)
	    (old-buffer (current-buffer))
	    symbol item)
	(set-buffer standard-output)
	(apropos-mode)
	(if (display-mouse-p)
	    (insert
	     "If moving the mouse over text changes the text's color, "
	     "you can click\n"
	     "mouse-2 (second button from right) on that text to "
	     "get more information.\n"))
	(insert "In this buffer, go to the name of the command, or function,"
		" or variable,\n"
		(substitute-command-keys
		 "and type \\[apropos-follow] to get full documentation.\n\n"))
	(if text (insert text "\n\n"))
	(while (consp p)
	  (when (and spacing (not (bobp)))
	    (princ spacing))
	  (setq apropos-item (car p)
		symbol (car apropos-item)
		p (cdr p))
	  (insert-text-button (symbol-name symbol)
			      'type 'apropos-symbol
			      ;; Can't use default, since user may have
			      ;; changed the variable!
			      ;; Just say `no' to variables containing faces!
			      'face apropos-symbol-face)
	  (if apropos-sort-by-scores
	      (insert " (" (number-to-string (cadr apropos-item)) ") "))
	  ;; Calculate key-bindings if we want them.
	  (and do-keys
	       (commandp symbol)
	       (indent-to 30 1)
	       (if (let ((keys
			  (save-excursion
			    (set-buffer old-buffer)
			    (where-is-internal symbol)))
			 filtered)
		     ;; Copy over the list of key sequences,
		     ;; omitting any that contain a buffer or a frame.
		     (while keys
		       (let ((key (car keys))
			     (i 0)
			     loser)
			 (while (< i (length key))
			   (if (or (framep (aref key i))
				   (bufferp (aref key i)))
			       (setq loser t))
			   (setq i (1+ i)))
			 (or loser
			     (setq filtered (cons key filtered))))
		       (setq keys (cdr keys)))
		     (setq item filtered))
		   ;; Convert the remaining keys to a string and insert.
		   (insert
		    (mapconcat
		     (lambda (key)
		       (setq key (condition-case ()
				     (key-description key)
				   (error)))
		       (if apropos-keybinding-face
			   (put-text-property 0 (length key)
					      'face apropos-keybinding-face
					      key))
		       key)
		     item ", "))
		 (insert "M-x")
		 (put-text-property (- (point) 3) (point)
				    'face apropos-keybinding-face)
		 (insert " " (symbol-name symbol) " ")
		 (insert "RET")
		 (put-text-property (- (point) 3) (point)
				    'face apropos-keybinding-face)))
	  (terpri)
	  (apropos-print-doc 2
			     (if (commandp symbol)
				 'apropos-command
			       (if (apropos-macrop symbol)
				   'apropos-macro
				 'apropos-function))
			     t)
	  (apropos-print-doc 3 'apropos-variable t)
	  (apropos-print-doc 7 'apropos-group t)
	  (apropos-print-doc 6 'apropos-face t)
	  (apropos-print-doc 5 'apropos-widget t)
	  (apropos-print-doc 4 'apropos-plist nil))
	(setq buffer-read-only t))))
  (prog1 apropos-accumulator
    (setq apropos-accumulator ())))	; permit gc


(defun apropos-macrop (symbol)
  "T if SYMBOL is a Lisp macro."
  (and (fboundp symbol)
       (consp (setq symbol
		    (symbol-function symbol)))
       (or (eq (car symbol) 'macro)
	   (if (eq (car symbol) 'autoload)
	       (memq (nth 4 symbol)
		     '(macro t))))))


(defun apropos-print-doc (i type do-keys)
  (if (stringp (setq i (nth i apropos-item)))
      (progn
	(insert "  ")
	(insert-text-button (button-type-get type 'apropos-label)
			    'type type
			    ;; Can't use the default button face, since
			    ;; user may have changed the variable!
			    ;; Just say `no' to variables containing faces!
			    'face apropos-label-face
			    'apropos-symbol (car apropos-item))
	(insert ": ")
	(insert (if do-keys (substitute-command-keys i) i))
	(or (bolp) (terpri)))))


(defun apropos-follow ()
  "Invokes any button at point, otherwise invokes the nearest label button."
  (interactive)
  (button-activate
   (or (apropos-next-label-button (line-beginning-position))
       (error "There is nothing to follow here"))))


(defun apropos-describe-plist (symbol)
  "Display a pretty listing of SYMBOL's plist."
  (help-setup-xref (list 'apropos-describe-plist symbol) (interactive-p))
  (with-output-to-temp-buffer (help-buffer)
    (set-buffer standard-output)
    (princ "Symbol ")
    (prin1 symbol)
    (princ "'s plist is\n (")
    (if apropos-symbol-face
	(put-text-property (+ (point-min) 7) (- (point) 14)
			   'face apropos-symbol-face))
    (insert (apropos-format-plist symbol "\n  "))
    (princ ")")
    (print-help-return-message)))


(provide 'apropos)

;;; arch-tag: d56fa2ac-e56b-4ce3-84ff-852f9c0dc66e
;;; apropos.el ends here
