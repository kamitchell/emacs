;;; easy-mmode.el --- easy definition for major and minor modes

;; Copyright (C) 1997,2000,01,02,03,2004  Free Software Foundation, Inc.

;; Author: Georges Brun-Cottan <Georges.Brun-Cottan@inria.fr>
;; Maintainer: Stefan Monnier <monnier@gnu.org>

;; Keywords: extensions lisp

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

;; Minor modes are useful and common.  This package makes defining a
;; minor mode easy, by focusing on the writing of the minor mode
;; functionalities themselves.  Moreover, this package enforces a
;; conventional naming of user interface primitives, making things
;; natural for the minor-mode end-users.

;; For each mode, easy-mmode defines the following:
;; <mode>      : The minor mode predicate. A buffer-local variable.
;; <mode>-map  : The keymap possibly associated to <mode>.
;; <mode>-hook : The hook run at the end of the toggle function.
;;       see `define-minor-mode' documentation
;;
;; eval
;;  (pp (macroexpand '(define-minor-mode <your-mode> <doc>)))
;; to check the result before using it.

;; The order in which minor modes are installed is important.  Keymap
;; lookup proceeds down minor-mode-map-alist, and the order there
;; tends to be the reverse of the order in which the modes were
;; installed.  Perhaps there should be a feature to let you specify
;; orderings.

;; Additionally to `define-minor-mode', the package provides convenient
;; ways to define keymaps, and other helper functions for major and minor modes.

;;; Code:

(eval-when-compile (require 'cl))

(defun easy-mmode-pretty-mode-name (mode &optional lighter)
  "Turn the symbol MODE into a string intended for the user.
If provided LIGHTER will be used to help choose capitalization."
  (let* ((case-fold-search t)
	 (name (concat (replace-regexp-in-string
			"-Minor" " minor"
			(capitalize (replace-regexp-in-string
				     "-mode\\'" "" (symbol-name mode))))
		       " mode")))
    (if (not (stringp lighter)) name
      (setq lighter (replace-regexp-in-string "\\`\\s-+\\|\\-s+\\'" "" lighter))
      (replace-regexp-in-string lighter lighter name t t))))

;;;###autoload
(defalias 'easy-mmode-define-minor-mode 'define-minor-mode)
;;;###autoload
(defmacro define-minor-mode (mode doc &optional init-value lighter keymap &rest body)
  "Define a new minor mode MODE.
This function defines the associated control variable MODE, keymap MODE-map,
toggle command MODE, and hook MODE-hook.

DOC is the documentation for the mode toggle command.
Optional INIT-VALUE is the initial value of the mode's variable.
Optional LIGHTER is displayed in the modeline when the mode is on.
Optional KEYMAP is the default (defvar) keymap bound to the mode keymap.
  If it is a list, it is passed to `easy-mmode-define-keymap'
  in order to build a valid keymap.  It's generally better to use
  a separate MODE-map variable than to use this argument.
The above three arguments can be skipped if keyword arguments are
used (see below).

BODY contains code that will be executed each time the mode is (dis)activated.
  It will be executed after any toggling but before running the hooks.
  Before the actual body code, you can write
  keyword arguments (alternating keywords and values).
  These following keyword arguments are supported (other keywords
  will be passed to `defcustom' if the minor mode is global):
:group GROUP	Custom group name to use in all generated `defcustom' forms.
:global GLOBAL	If non-nil specifies that the minor mode is not meant to be
              	buffer-local, so don't make the variable MODE buffer-local.
		By default, the mode is buffer-local.
:init-value VAL	Same as the INIT-VALUE argument.
:lighter SPEC	Same as the LIGHTER argument.
:keymap MAP	Same as the KEYMAP argument.
:require SYM	Same as in `defcustom'.

For example, you could write
  (define-minor-mode foo-mode \"If enabled, foo on you!\"
    :lighter \" Foo\" :require 'foo :global t :group 'hassle :version \"27.5\"
    ...BODY CODE...)"
  (declare (debug (&define name stringp
			   [&optional [&not keywordp] sexp
			    &optional [&not keywordp] sexp
			    &optional [&not keywordp] sexp]
			   [&rest [keywordp sexp]]
			   def-body)))

  ;; Allow skipping the first three args.
  (cond
   ((keywordp init-value)
    (setq body (list* init-value lighter keymap body)
	  init-value nil lighter nil keymap nil))
   ((keywordp lighter)
    (setq body (list* lighter keymap body) lighter nil keymap nil))
   ((keywordp keymap) (push keymap body) (setq keymap nil)))

  (let* ((mode-name (symbol-name mode))
	 (pretty-name (easy-mmode-pretty-mode-name mode lighter))
	 (globalp nil)
	 (group nil)
	 (extra-args nil)
	 (extra-keywords nil)
	 (require t)
	 (hook (intern (concat mode-name "-hook")))
	 (hook-on (intern (concat mode-name "-on-hook")))
	 (hook-off (intern (concat mode-name "-off-hook")))
	 keyw keymap-sym)

    ;; Check keys.
    (while (keywordp (setq keyw (car body)))
      (setq body (cdr body))
      (case keyw
	(:init-value (setq init-value (pop body)))
	(:lighter (setq lighter (pop body)))
	(:global (setq globalp (pop body)))
	(:extra-args (setq extra-args (pop body)))
	(:group (setq group (nconc group (list :group (pop body)))))
	(:require (setq require (pop body)))
	(:keymap (setq keymap (pop body)))
	(t (push keyw extra-keywords) (push (pop body) extra-keywords))))

    (setq keymap-sym (if (and keymap (symbolp keymap)) keymap
		       (intern (concat mode-name "-map"))))

    (unless group
      ;; We might as well provide a best-guess default group.
      (setq group
	    `(:group ',(or (custom-current-group)
			   (intern (replace-regexp-in-string
				    "-mode\\'" "" mode-name))))))

    `(progn
       ;; Define the variable to enable or disable the mode.
       ,(if (not globalp)
	    `(progn
	       (defvar ,mode ,init-value ,(format "Non-nil if %s is enabled.
Use the command `%s' to change this variable." pretty-name mode))
	       (make-variable-buffer-local ',mode))

	  (let ((curfile (or (and (boundp 'byte-compile-current-file)
				  byte-compile-current-file)
			     load-file-name)))
	    `(defcustom ,mode ,init-value
	       ,(format "Non-nil if %s is enabled.
See the command `%s' for a description of this minor-mode.
Setting this variable directly does not take effect;
use either \\[customize] or the function `%s'."
			pretty-name mode mode)
	       :set 'custom-set-minor-mode
	       :initialize 'custom-initialize-default
	       ,@group
	       :type 'boolean
	       ,@(cond
		  ((not (and curfile require)) nil)
		  ((not (eq require t)) `(:require ,require))
		  (t `(:require
		       ',(intern (file-name-nondirectory
				  (file-name-sans-extension curfile))))))
	       ,@(nreverse extra-keywords))))

       ;; The actual function.
       (defun ,mode (&optional arg ,@extra-args)
	 ,(or doc
	      (format (concat "Toggle %s on or off.
Interactively, with no prefix argument, toggle the mode.
With universal prefix ARG turn mode on.
With zero or negative ARG turn mode off.
\\{%s}") pretty-name keymap-sym))
	 ;; Use `toggle' rather than (if ,mode 0 1) so that using
	 ;; repeat-command still does the toggling correctly.
	 (interactive (list (or current-prefix-arg 'toggle)))
	 (setq ,mode
	       (cond
		((eq arg 'toggle) (not ,mode))
		(arg (> (prefix-numeric-value arg) 0))
		(t
		 (if (null ,mode) t
		   (message
		    "Toggling %s off; better pass an explicit argument."
		    ',mode)
		   nil))))
	 ,@body
	 ;; The on/off hooks are here for backward compatibility only.
	 (run-hooks ',hook (if ,mode ',hook-on ',hook-off))
	 (if (called-interactively-p)
	     (progn
	       ,(if globalp `(customize-mark-as-set ',mode))
	       (unless (current-message)
		 (message ,(format "%s %%sabled" pretty-name)
			  (if ,mode "en" "dis")))))
	 (force-mode-line-update)
	 ;; Return the new setting.
	 ,mode)

       ;; Autoloading an easy-mmode-define-minor-mode autoloads
       ;; everything up-to-here.
       :autoload-end

       ;; The toggle's hook.
       (defcustom ,hook nil
	 ,(format "Hook run at the end of function `%s'." mode-name)
	 ,@group
	 :type 'hook)

       ;; Define the minor-mode keymap.
       ,(unless (symbolp keymap)	;nil is also a symbol.
	  `(defvar ,keymap-sym
	     (let ((m ,keymap))
	       (cond ((keymapp m) m)
		     ((listp m) (easy-mmode-define-keymap m))
		     (t (error "Invalid keymap %S" ,keymap))))
	     ,(format "Keymap for `%s'." mode-name)))

       (add-minor-mode ',mode ',lighter
		       ,(if keymap keymap-sym
			  `(if (boundp ',keymap-sym)
			       (symbol-value ',keymap-sym))))

       ;; If the mode is global, call the function according to the default.
       ,(if globalp
	    `(if (and load-file-name (not (equal ,init-value ,mode)))
		 (eval-after-load load-file-name '(,mode (if ,mode 1 -1))))))))

;;;
;;; make global minor mode
;;;

;;;###autoload
(defmacro easy-mmode-define-global-mode (global-mode mode turn-on
						     &rest keys)
  "Make GLOBAL-MODE out of the buffer-local minor MODE.
TURN-ON is a function that will be called with no args in every buffer
  and that should try to turn MODE on if applicable for that buffer.
KEYS is a list of CL-style keyword arguments:
:group to specify the custom group."
  (let* ((global-mode-name (symbol-name global-mode))
	 (pretty-name (easy-mmode-pretty-mode-name mode))
	 (pretty-global-name (easy-mmode-pretty-mode-name global-mode))
	 (group nil)
	 (extra-args nil)
	 (buffers (intern (concat global-mode-name "-buffers")))
	 (cmmh (intern (concat global-mode-name "-cmmh"))))

    ;; Check keys.
    (while (keywordp (car keys))
      (case (pop keys)
	(:extra-args (setq extra-args (pop keys)))
	(:group (setq group (nconc group (list :group (pop keys)))))
	(t (setq keys (cdr keys)))))

    (unless group
      ;; We might as well provide a best-guess default group.
      (setq group
	    `(:group ',(or (custom-current-group)
			   (intern (replace-regexp-in-string
				    "-mode\\'" "" (symbol-name mode)))))))

    `(progn
       ;; The actual global minor-mode
       (define-minor-mode ,global-mode
	 ,(format "Toggle %s in every buffer.
With prefix ARG, turn %s on if and only if ARG is positive.
%s is actually not turned on in every buffer but only in those
in which `%s' turns it on."
		  pretty-name pretty-global-name pretty-name turn-on)
	 :global t :extra-args ,extra-args ,@group

	 ;; Setup hook to handle future mode changes and new buffers.
	 (if ,global-mode
	     (progn
	       (add-hook 'find-file-hook ',buffers)
	       (add-hook 'change-major-mode-hook ',cmmh))
	   (remove-hook 'find-file-hook ',buffers)
	   (remove-hook 'change-major-mode-hook ',cmmh))

	 ;; Go through existing buffers.
	 (dolist (buf (buffer-list))
	   (with-current-buffer buf
	     (if ,global-mode (,turn-on) (when ,mode (,mode -1))))))

       ;; Autoloading easy-mmode-define-global-mode
       ;; autoloads everything up-to-here.
       :autoload-end

       ;; List of buffers left to process.
       (defvar ,buffers nil)

       ;; The function that calls TURN-ON in each buffer.
       (defun ,buffers ()
	 (remove-hook 'post-command-hook ',buffers)
	 (while ,buffers
	   (let ((buf (pop ,buffers)))
	     (when (buffer-live-p buf)
	       (with-current-buffer buf (,turn-on))))))
       (put ',buffers 'definition-name ',global-mode)

       ;; The function that catches kill-all-local-variables.
       (defun ,cmmh ()
	 (add-to-list ',buffers (current-buffer))
	 (add-hook 'post-command-hook ',buffers))
       (put ',cmmh 'definition-name ',global-mode))))

;;;
;;; easy-mmode-defmap
;;;

(if (fboundp 'set-keymap-parents)
    (defalias 'easy-mmode-set-keymap-parents 'set-keymap-parents)
  (defun easy-mmode-set-keymap-parents (m parents)
    (set-keymap-parent
     m
     (cond
      ((not (consp parents)) parents)
      ((not (cdr parents)) (car parents))
      (t (let ((m (copy-keymap (pop parents))))
	   (easy-mmode-set-keymap-parents m parents)
	   m))))))

;;;###autoload
(defun easy-mmode-define-keymap (bs &optional name m args)
  "Return a keymap built from bindings BS.
BS must be a list of (KEY . BINDING) where
KEY and BINDINGS are suitable for `define-key'.
Optional NAME is passed to `make-sparse-keymap'.
Optional map M can be used to modify an existing map.
ARGS is a list of additional keyword arguments."
  (let (inherit dense)
    (while args
      (let ((key (pop args))
	    (val (pop args)))
	(case key
	 (:name (setq name val))
	 (:dense (setq dense val))
	 (:inherit (setq inherit val))
	 (:group)
	 (t (message "Unknown argument %s in defmap" key)))))
    (unless (keymapp m)
      (setq bs (append m bs))
      (setq m (if dense (make-keymap name) (make-sparse-keymap name))))
    (dolist (b bs)
      (let ((keys (car b))
	    (binding (cdr b)))
	(dolist (key (if (consp keys) keys (list keys)))
	  (cond
	   ((symbolp key)
	    (substitute-key-definition key binding m global-map))
	   ((null binding)
	    (unless (keymapp (lookup-key m key)) (define-key m key binding)))
	   ((let ((o (lookup-key m key)))
	      (or (null o) (numberp o) (eq o 'undefined)))
	    (define-key m key binding))))))
    (cond
     ((keymapp inherit) (set-keymap-parent m inherit))
     ((consp inherit) (easy-mmode-set-keymap-parents m inherit)))
    m))

;;;###autoload
(defmacro easy-mmode-defmap (m bs doc &rest args)
  `(defconst ,m
     (easy-mmode-define-keymap ,bs nil (if (boundp ',m) ,m) ,(cons 'list args))
     ,doc))


;;;
;;; easy-mmode-defsyntax
;;;

(defun easy-mmode-define-syntax (css args)
  (let ((st (make-syntax-table (plist-get args :copy)))
	(parent (plist-get args :inherit)))
    (dolist (cs css)
      (let ((char (car cs))
	    (syntax (cdr cs)))
	(if (sequencep char)
	    (mapcar (lambda (c) (modify-syntax-entry c syntax st)) char)
	  (modify-syntax-entry char syntax st))))
    (if parent (set-char-table-parent
		st (if (symbolp parent) (symbol-value parent) parent)))
    st))

;;;###autoload
(defmacro easy-mmode-defsyntax (st css doc &rest args)
  "Define variable ST as a syntax-table.
CSS contains a list of syntax specifications of the form (CHAR . SYNTAX)."
  `(progn
     (autoload 'easy-mmode-define-syntax "easy-mmode")
     (defconst ,st (easy-mmode-define-syntax ,css ,(cons 'list args)) ,doc)))



;;;
;;; easy-mmode-define-navigation
;;;

(defmacro easy-mmode-define-navigation (base re &optional name endfun narrowfun)
  "Define BASE-next and BASE-prev to navigate in the buffer.
RE determines the places the commands should move point to.
NAME should describe the entities matched by RE.  It is used to build
  the docstrings of the two functions.
BASE-next also tries to make sure that the whole entry is visible by
  searching for its end (by calling ENDFUN if provided or by looking for
  the next entry) and recentering if necessary.
ENDFUN should return the end position (with or without moving point).
NARROWFUN non-nil means to check for narrowing before moving, and if
found, do widen first and then call NARROWFUN with no args after moving."
  (let* ((base-name (symbol-name base))
	 (prev-sym (intern (concat base-name "-prev")))
	 (next-sym (intern (concat base-name "-next")))
         (check-narrow-maybe
	  (when narrowfun
	    '(setq was-narrowed
		   (prog1 (or (< (- (point-max) (point-min)) (buffer-size)))
		     (widen)))))
         (re-narrow-maybe (when narrowfun
                            `(when was-narrowed (,narrowfun)))))
    (unless name (setq name base-name))
    `(progn
       (add-to-list 'debug-ignored-errors
		    ,(concat "^No \\(previous\\|next\\) " (regexp-quote name)))
       (defun ,next-sym (&optional count)
	 ,(format "Go to the next COUNT'th %s." name)
	 (interactive)
	 (unless count (setq count 1))
	 (if (< count 0) (,prev-sym (- count))
	   (if (looking-at ,re) (setq count (1+ count)))
           (let (was-narrowed)
             ,check-narrow-maybe
             (if (not (re-search-forward ,re nil t count))
                 (if (looking-at ,re)
                     (goto-char (or ,(if endfun `(,endfun)) (point-max)))
                   (error "No next %s" ,name))
               (goto-char (match-beginning 0))
               (when (and (eq (current-buffer) (window-buffer (selected-window)))
                          (interactive-p))
                 (let ((endpt (or (save-excursion
                                    ,(if endfun `(,endfun)
                                       `(re-search-forward ,re nil t 2)))
                                  (point-max))))
                   (unless (pos-visible-in-window-p endpt nil t)
                     (recenter '(0))))))
             ,re-narrow-maybe)))
       (defun ,prev-sym (&optional count)
	 ,(format "Go to the previous COUNT'th %s" (or name base-name))
	 (interactive)
	 (unless count (setq count 1))
	 (if (< count 0) (,next-sym (- count))
           (let (was-narrowed)
             ,check-narrow-maybe
             (unless (re-search-backward ,re nil t count)
               (error "No previous %s" ,name))
             ,re-narrow-maybe))))))


(provide 'easy-mmode)

;;; arch-tag: d48a5250-6961-4528-9cb0-3c9ea042a66a
;;; easy-mmode.el ends here
