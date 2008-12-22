;;; window.el --- GNU Emacs window commands aside from those written in C

;; Copyright (C) 1985, 1989, 1992, 1993, 1994, 2000, 2001, 2002,
;;   2003, 2004, 2005, 2006, 2007, 2008 Free Software Foundation, Inc.

;; Maintainer: FSF
;; Keywords: internal

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Window tree functions.

;;; Code:

(eval-when-compile (require 'cl))

(defvar window-size-fixed nil
 "*Non-nil in a buffer means windows displaying the buffer are fixed-size.
If the value is `height', then only the window's height is fixed.
If the value is `width', then only the window's width is fixed.
Any other non-nil value fixes both the width and the height.
Emacs won't change the size of any window displaying that buffer,
unless you explicitly change the size, or Emacs has no other choice.")
(make-variable-buffer-local 'window-size-fixed)

(defmacro save-selected-window (&rest body)
  "Execute BODY, then select the previously selected window.
The value returned is the value of the last form in BODY.

This macro saves and restores the selected window, as well as the
selected window in each frame.  If the previously selected window
is no longer live, then whatever window is selected at the end of
BODY remains selected.  If the previously selected window of some
frame is no longer live at the end of BODY, that frame's selected
window is left alone.

This macro saves and restores the current buffer, since otherwise
its normal operation could make a different buffer current.  The
order of recently selected windows and the buffer list ordering
are not altered by this macro (unless they are altered in BODY)."
  `(let ((save-selected-window-window (selected-window))
	 ;; It is necessary to save all of these, because calling
	 ;; select-window changes frame-selected-window for whatever
	 ;; frame that window is in.
	 (save-selected-window-alist
	  (mapcar (lambda (frame) (cons frame (frame-selected-window frame)))
		  (frame-list))))
     (save-current-buffer
       (unwind-protect
	   (progn ,@body)
	 (dolist (elt save-selected-window-alist)
	   (and (frame-live-p (car elt))
		(window-live-p (cdr elt))
		(set-frame-selected-window (car elt) (cdr elt) 'norecord)))
	 (when (window-live-p save-selected-window-window)
	   (select-window save-selected-window-window 'norecord))))))

(defun window-body-height (&optional window)
  "Return number of lines in WINDOW available for actual buffer text.
WINDOW defaults to the selected window.

The return value does not include the mode line or the header
line, if any.  If a line at the bottom of the window is only
partially visible, that line is included in the return value.  If
you do not want to include a partially visible bottom line in the
return value, use `window-text-height' instead."
  (or window (setq window (selected-window)))
  (if (window-minibuffer-p window)
      (window-height window)
    (with-current-buffer (window-buffer window)
      (max 1 (- (window-height window)
		(if mode-line-format 1 0)
		(if header-line-format 1 0))))))

(defun one-window-p (&optional nomini all-frames)
  "Return non-nil if the selected window is the only window.
Optional arg NOMINI non-nil means don't count the minibuffer
even if it is active.  Otherwise, the minibuffer is counted
when it is active.

The optional arg ALL-FRAMES t means count windows on all frames.
If it is `visible', count windows on all visible frames.
ALL-FRAMES nil or omitted means count only the selected frame,
plus the minibuffer it uses (which may be on another frame).
ALL-FRAMES 0 means count all windows in all visible or iconified frames.
If ALL-FRAMES is anything else, count only the selected frame."
  (let ((base-window (selected-window)))
    (if (and nomini (eq base-window (minibuffer-window)))
	(setq base-window (next-window base-window)))
    (eq base-window
	(next-window base-window (if nomini 'arg) all-frames))))

(defun window-current-scroll-bars (&optional window)
  "Return the current scroll bar settings for WINDOW.
WINDOW defaults to the selected window.

The return value is a cons cell (VERTICAL . HORIZONTAL) where
VERTICAL specifies the current location of the vertical scroll
bars (`left', `right', or nil), and HORIZONTAL specifies the
current location of the horizontal scroll bars (`top', `bottom',
or nil).

Unlike `window-scroll-bars', this function reports the scroll bar
type actually used, once frame defaults and `scroll-bar-mode' are
taken into account."
  (let ((vert (nth 2 (window-scroll-bars window)))
	(hor nil))
    (when (or (eq vert t) (eq hor t))
      (let ((fcsb (frame-current-scroll-bars
		   (window-frame (or window (selected-window))))))
	(if (eq vert t)
	    (setq vert (car fcsb)))
	(if (eq hor t)
	    (setq hor (cdr fcsb)))))
    (cons vert hor)))

(defun walk-windows (proc &optional minibuf all-frames)
  "Cycle through all windows, calling PROC for each one.
PROC must specify a function with a window as its sole argument.
The optional arguments MINIBUF and ALL-FRAMES specify the set of
windows to include in the walk, see also `next-window'.

MINIBUF t means include the minibuffer window even if the
minibuffer is not active.  MINIBUF nil or omitted means include
the minibuffer window only if the minibuffer is active.  Any
other value means do not include the minibuffer window even if
the minibuffer is active.

Several frames may share a single minibuffer; if the minibuffer
is active, all windows on all frames that share that minibuffer
are included too.  Therefore, if you are using a separate
minibuffer frame and the minibuffer is active and MINIBUF says it
counts, `walk-windows' includes the windows in the frame from
which you entered the minibuffer, as well as the minibuffer
window.

ALL-FRAMES nil or omitted means cycle through all windows on
 WINDOW's frame, plus the minibuffer window if specified by the
 MINIBUF argument, see above.  If the minibuffer counts, cycle
 through all windows on all frames that share that minibuffer
 too.
ALL-FRAMES t means cycle through all windows on all existing
 frames.
ALL-FRAMES `visible' means cycle through all windows on all
 visible frames.
ALL-FRAMES 0 means cycle through all windows on all visible and
 iconified frames.
ALL-FRAMES a frame means cycle through all windows on that frame
 only.
Anything else means cycle through all windows on WINDOW's frame
 and no others.

This function changes neither the order of recently selected
windows nor the buffer list."
  ;; If we start from the minibuffer window, don't fail to come
  ;; back to it.
  (when (window-minibuffer-p (selected-window))
    (setq minibuf t))
  ;; Make sure to not mess up the order of recently selected
  ;; windows.  Use `save-selected-window' and `select-window'
  ;; with second argument non-nil for this purpose.
  (save-selected-window
    (when (framep all-frames)
      (select-window (frame-first-window all-frames) 'norecord))
    (let* (walk-windows-already-seen
	   (walk-windows-current (selected-window)))
      (while (progn
	       (setq walk-windows-current
		     (next-window walk-windows-current minibuf all-frames))
	       (not (memq walk-windows-current walk-windows-already-seen)))
	(setq walk-windows-already-seen
	      (cons walk-windows-current walk-windows-already-seen))
	(funcall proc walk-windows-current)))))

(defun get-window-with-predicate (predicate &optional minibuf
					    all-frames default)
  "Return a window satisfying PREDICATE.
More precisely, cycle through all windows using `walk-windows',
calling the function PREDICATE on each one of them with the
window as its sole argument.  Return the first window for which
PREDICATE returns non-nil.  If no window satisfies PREDICATE,
return DEFAULT.

The optional arguments MINIBUF and ALL-FRAMES specify the set of
windows to include.  See `walk-windows' for the meaning of these
arguments."
  (catch 'found
    (walk-windows #'(lambda (window)
		      (when (funcall predicate window)
			(throw 'found window)))
		  minibuf all-frames)
    default))

(defalias 'some-window 'get-window-with-predicate)

;; This should probably be written in C (i.e., without using `walk-windows').
(defun get-buffer-window-list (&optional buffer-or-name minibuf all-frames)
  "Return list of all windows displaying BUFFER-OR-NAME, or nil if none.
BUFFER-OR-NAME may be a buffer or the name of an existing buffer
and defaults to the current buffer.

The optional arguments MINIBUF and ALL-FRAMES specify the set of
windows to consider.  See `walk-windows' for the precise meaning
of these arguments."
  (let ((buffer (cond
		 ((not buffer-or-name) (current-buffer))
		 ((bufferp buffer-or-name) buffer-or-name)
		 (t (get-buffer buffer-or-name))))
	windows)
    (walk-windows (function (lambda (window)
			      (if (eq (window-buffer window) buffer)
				  (setq windows (cons window windows)))))
		  minibuf all-frames)
    windows))

(defun minibuffer-window-active-p (window)
  "Return t if WINDOW is the currently active minibuffer window."
  (eq window (active-minibuffer-window)))

(defun count-windows (&optional minibuf)
   "Return the number of visible windows.
The optional argument MINIBUF specifies whether the minibuffer
window shall be counted.  See `walk-windows' for the precise
meaning of this argument."
   (let ((count 0))
     (walk-windows (lambda (w) (setq count (+ count 1)))
		   minibuf)
     count))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; `balance-windows' subroutines using `window-tree'

;;; Translate from internal window tree format

(defun bw-get-tree (&optional window-or-frame)
  "Get a window split tree in our format.

WINDOW-OR-FRAME must be nil, a frame, or a window.  If it is nil,
then the whole window split tree for `selected-frame' is returned.
If it is a frame, then this is used instead.  If it is a window,
then the smallest tree containing that window is returned."
  (when window-or-frame
    (unless (or (framep window-or-frame)
                (windowp window-or-frame))
      (error "Not a frame or window: %s" window-or-frame)))
  (let ((subtree (bw-find-tree-sub window-or-frame)))
    (when subtree
      (if (integerp subtree)
	  nil
	(bw-get-tree-1 subtree)))))

(defun bw-get-tree-1 (split)
  (if (windowp split)
      split
    (let ((dir (car split))
          (edges (car (cdr split)))
          (childs (cdr (cdr split))))
      (list
       (cons 'dir (if dir 'ver 'hor))
       (cons 'b (nth 3 edges))
       (cons 'r (nth 2 edges))
       (cons 't (nth 1 edges))
       (cons 'l (nth 0 edges))
       (cons 'childs (mapcar #'bw-get-tree-1 childs))))))

(defun bw-find-tree-sub (window-or-frame &optional get-parent)
  (let* ((window (when (windowp window-or-frame) window-or-frame))
         (frame (when (windowp window) (window-frame window)))
         (wt (car (window-tree frame))))
    (when (< 1 (length (window-list frame 0)))
      (if window
          (bw-find-tree-sub-1 wt window get-parent)
        wt))))

(defun bw-find-tree-sub-1 (tree win &optional get-parent)
  (unless (windowp win) (error "Not a window: %s" win))
  (if (memq win tree)
      (if get-parent
          get-parent
        tree)
    (let ((childs (cdr (cdr tree)))
          child
          subtree)
      (while (and childs (not subtree))
        (setq child (car childs))
        (setq childs (cdr childs))
        (when (and child (listp child))
          (setq subtree (bw-find-tree-sub-1 child win get-parent))))
      (if (integerp subtree)
          (progn
            (if (= 1 subtree)
                tree
              (1- subtree)))
        subtree
        ))))

;;; Window or object edges

(defun bw-l (obj)
  "Left edge of OBJ."
  (if (windowp obj) (nth 0 (window-edges obj)) (cdr (assq 'l obj))))
(defun bw-t (obj)
  "Top edge of OBJ."
  (if (windowp obj) (nth 1 (window-edges obj)) (cdr (assq 't obj))))
(defun bw-r (obj)
  "Right edge of OBJ."
  (if (windowp obj) (nth 2 (window-edges obj)) (cdr (assq 'r obj))))
(defun bw-b (obj)
  "Bottom edge of OBJ."
  (if (windowp obj) (nth 3 (window-edges obj)) (cdr (assq 'b obj))))

;;; Split directions

(defun bw-dir (obj)
  "Return window split tree direction if OBJ.
If OBJ is a window return 'both.  If it is a window split tree
then return its direction."
  (if (symbolp obj)
      obj
    (if (windowp obj)
        'both
      (let ((dir (cdr (assq 'dir obj))))
        (unless (memq dir '(hor ver both))
          (error "Can't find dir in %s" obj))
        dir))))

(defun bw-eqdir (obj1 obj2)
  "Return t if window split tree directions are equal.
OBJ1 and OBJ2 should be either windows or window split trees in
our format.  The directions returned by `bw-dir' are compared and
t is returned if they are `eq' or one of them is 'both."
  (let ((dir1 (bw-dir obj1))
        (dir2 (bw-dir obj2)))
    (or (eq dir1 dir2)
        (eq dir1 'both)
        (eq dir2 'both))))

;;; Building split tree

(defun bw-refresh-edges (obj)
  "Refresh the edge information of OBJ and return OBJ."
  (unless (windowp obj)
    (let ((childs (cdr (assq 'childs obj)))
          (ol 1000)
          (ot 1000)
          (or -1)
          (ob -1))
      (dolist (o childs)
        (when (> ol (bw-l o)) (setq ol (bw-l o)))
        (when (> ot (bw-t o)) (setq ot (bw-t o)))
        (when (< or (bw-r o)) (setq or (bw-r o)))
        (when (< ob (bw-b o)) (setq ob (bw-b o))))
      (setq obj (delq 'l obj))
      (setq obj (delq 't obj))
      (setq obj (delq 'r obj))
      (setq obj (delq 'b obj))
      (add-to-list 'obj (cons 'l ol))
      (add-to-list 'obj (cons 't ot))
      (add-to-list 'obj (cons 'r or))
      (add-to-list 'obj (cons 'b ob))
      ))
  obj)

;;; Balance windows

(defun balance-windows (&optional window-or-frame)
  "Make windows the same heights or widths in window split subtrees.

When called non-interactively WINDOW-OR-FRAME may be either a
window or a frame.  It then balances the windows on the implied
frame.  If the parameter is a window only the corresponding window
subtree is balanced."
  (interactive)
  (let (
        (wt (bw-get-tree window-or-frame))
        (w)
        (h)
        (tried-sizes)
        (last-sizes)
        (windows (window-list nil 0)))
    (when wt
      (while (not (member last-sizes tried-sizes))
        (when last-sizes (setq tried-sizes (cons last-sizes tried-sizes)))
        (setq last-sizes (mapcar (lambda (w)
                                   (window-edges w))
                                 windows))
        (when (eq 'hor (bw-dir wt))
          (setq w (- (bw-r wt) (bw-l wt))))
        (when (eq 'ver (bw-dir wt))
          (setq h (- (bw-b wt) (bw-t wt))))
        (bw-balance-sub wt w h)))))

(defun bw-adjust-window (window delta horizontal)
  "Wrapper around `adjust-window-trailing-edge' with error checking.
Arguments WINDOW, DELTA and HORIZONTAL are passed on to that function."
  ;; `adjust-window-trailing-edge' may fail if delta is too large.
  (while (>= (abs delta) 1)
    (condition-case err
        (progn
          (adjust-window-trailing-edge window delta horizontal)
          (setq delta 0))
      (error
       ;;(message "adjust: %s" (error-message-string err))
       (setq delta (/ delta 2))))))

(defun bw-balance-sub (wt w h)
  (setq wt (bw-refresh-edges wt))
  (unless w (setq w (- (bw-r wt) (bw-l wt))))
  (unless h (setq h (- (bw-b wt) (bw-t wt))))
  (if (windowp wt)
      (progn
        (when w
          (let ((dw (- w (- (bw-r wt) (bw-l wt)))))
            (when (/= 0 dw)
              (bw-adjust-window wt dw t))))
        (when h
          (let ((dh (- h (- (bw-b wt) (bw-t wt)))))
            (when (/= 0 dh)
              (bw-adjust-window wt dh nil)))))
    (let* ((childs (cdr (assq 'childs wt)))
           (cw (when w (/ w (if (bw-eqdir 'hor wt) (length childs) 1))))
           (ch (when h (/ h (if (bw-eqdir 'ver wt) (length childs) 1)))))
      (dolist (c childs)
        (bw-balance-sub c cw ch)))))

(defun window-fixed-size-p (&optional window direction)
  "Return t if WINDOW cannot be resized in DIRECTION.
WINDOW defaults to the selected window.  DIRECTION can be
nil (i.e. any), `height' or `width'."
  (with-current-buffer (window-buffer window)
    (when (and (boundp 'window-size-fixed) window-size-fixed)
      (not (and direction
		(member (cons direction window-size-fixed)
			'((height . width) (width . height))))))))

;;; A different solution to balance-windows.

(defvar window-area-factor 1
  "Factor by which the window area should be over-estimated.
This is used by `balance-windows-area'.
Changing this globally has no effect.")
(make-variable-buffer-local 'window-area-factor)

(defun balance-windows-area ()
  "Make all visible windows the same area (approximately).
See also `window-area-factor' to change the relative size of
specific buffers."
  (interactive)
  (let* ((unchanged 0) (carry 0) (round 0)
         ;; Remove fixed-size windows.
         (wins (delq nil (mapcar (lambda (win)
                                   (if (not (window-fixed-size-p win)) win))
                                 (window-list nil 'nomini))))
         (changelog nil)
         next)
    ;; Resizing a window changes the size of surrounding windows in complex
    ;; ways, so it's difficult to balance them all.  The introduction of
    ;; `adjust-window-trailing-edge' made it a bit easier, but it is still
    ;; very difficult to do.  `balance-window' above takes an off-line
    ;; approach: get the whole window tree, then balance it, then try to
    ;; adjust the windows so they fit the result.
    ;; Here, instead, we take a "local optimization" approach, where we just
    ;; go through all the windows several times until nothing needs to be
    ;; changed.  The main problem with this approach is that it's difficult
    ;; to make sure it terminates, so we use some heuristic to try and break
    ;; off infinite loops.
    ;; After a round without any change, we allow a second, to give a chance
    ;; to the carry to propagate a minor imbalance from the end back to
    ;; the beginning.
    (while (< unchanged 2)
      ;; (message "New round")
      (setq unchanged (1+ unchanged) round (1+ round))
      (dolist (win wins)
        (setq next win)
        (while (progn (setq next (next-window next))
                      (window-fixed-size-p next)))
        ;; (assert (eq next (or (cadr (member win wins)) (car wins))))
        (let* ((horiz
                (< (car (window-edges win)) (car (window-edges next))))
               (areadiff (/ (- (* (window-height next) (window-width next)
                                  (buffer-local-value 'window-area-factor
                                                      (window-buffer next)))
                               (* (window-height win) (window-width win)
                                  (buffer-local-value 'window-area-factor
                                                      (window-buffer win))))
                            (max (buffer-local-value 'window-area-factor
                                                     (window-buffer win))
                                 (buffer-local-value 'window-area-factor
                                                     (window-buffer next)))))
               (edgesize (if horiz
                             (+ (window-height win) (window-height next))
                           (+ (window-width win) (window-width next))))
               (diff (/ areadiff edgesize)))
          (when (zerop diff)
            ;; Maybe diff is actually closer to 1 than to 0.
            (setq diff (/ (* 3 areadiff) (* 2 edgesize))))
          (when (and (zerop diff) (not (zerop areadiff)))
            (setq diff (/ (+ areadiff carry) edgesize))
            ;; Change things smoothly.
            (if (or (> diff 1) (< diff -1)) (setq diff (/ diff 2))))
          (if (zerop diff)
              ;; Make sure negligible differences don't accumulate to
              ;; become significant.
              (setq carry (+ carry areadiff))
            (bw-adjust-window win diff horiz)
            ;; (sit-for 0.5)
            (let ((change (cons win (window-edges win))))
              ;; If the same change has been seen already for this window,
              ;; we're most likely in an endless loop, so don't count it as
              ;; a change.
              (unless (member change changelog)
                (push change changelog)
                (setq unchanged 0 carry 0)))))))
    ;; We've now basically balanced all the windows.
    ;; But there may be some minor off-by-one imbalance left over,
    ;; so let's do some fine tuning.
    ;; (bw-finetune wins)
    ;; (message "Done in %d rounds" round)
    ))


(defcustom display-buffer-function nil
  "If non-nil, function to call to handle `display-buffer'.
It will receive two args, the buffer and a flag which if non-nil
means that the currently selected window is not acceptable.  It
should choose or create a window, display the specified buffer in
it, and return the window.

Commands such as `switch-to-buffer-other-window' and
`find-file-other-window' work using this function."
  :type '(choice
	  (const nil)
	  (function :tag "function"))
  :group 'windows)

(defun special-display-p (buffer-name)
  "Return non-nil if a buffer named BUFFER-NAME gets a special frame.
If the value is t, `display-buffer' or `pop-to-buffer' would
create a special frame for that buffer using the default frame
parameters.

If the value is a list, it is a list of frame parameters that
would be used to make a frame for that buffer.  The variables
`special-display-buffer-names' and `special-display-regexps'
control this."
  (let (tmp)
  (cond
   ((not (stringp buffer-name)))
   ;; Make sure to return t in the following two cases.
   ((member buffer-name special-display-buffer-names) t)
     ((setq tmp (assoc buffer-name special-display-buffer-names)) (cdr tmp))
   ((catch 'found
      (dolist (regexp special-display-regexps)
	(cond
	 ((stringp regexp)
	  (when (string-match-p regexp buffer-name)
	    (throw 'found t)))
	 ((and (consp regexp) (stringp (car regexp))
	       (string-match-p (car regexp) buffer-name))
            (throw 'found (cdr regexp))))))))))

(defcustom special-display-buffer-names nil
  "List of buffer names that should have their own special frames.
Displaying a buffer with `display-buffer' or `pop-to-buffer', if
its name is in this list, makes a special frame for it using
`special-display-function'.  See also `special-display-regexps'.

An element of the list can be a list instead of just a string.
There are two ways to use a list as an element:
  (BUFFER FRAME-PARAMETERS...)  (BUFFER FUNCTION OTHER-ARGS...)
In the first case, the FRAME-PARAMETERS are pairs of the form
\(PARAMETER . VALUE); these parameter values are used to create
the frame.  In the second case, FUNCTION is called with BUFFER as
the first argument, followed by the OTHER-ARGS--it can display
BUFFER in any way it likes.  All this is done by the function
found in `special-display-function'.

If the specified frame parameters include (same-buffer . t), the
buffer is displayed in the currently selected window.  Otherwise, if
they include (same-frame . t), the buffer is displayed in a new window
in the currently selected frame.

If this variable appears \"not to work\", because you add a name to it
but that buffer still appears in the selected window, look at the
values of `same-window-buffer-names' and `same-window-regexps'.
Those variables take precedence over this one."
  :type '(repeat (choice :tag "Buffer"
			 :value ""
			 (string :format "%v")
			 (cons :tag "With attributes"
			       :format "%v"
			       :value ("" . nil)
			       (string :format "%v")
			       (repeat :tag "Attributes"
				       (cons :format "%v"
					     (symbol :tag "Parameter")
					     (sexp :tag "Value"))))))
  :group 'frames)

(defcustom special-display-regexps nil
  "List of regexps saying which buffers should have their own special frames.
When displaying a buffer with `display-buffer' or
`pop-to-buffer', if any regexp in this list matches the buffer
name, it makes a special frame for the buffer by calling
`special-display-function'.

An element of the list can be a list instead of just a string.
There are two ways to use a list as an element:
  (REGEXP FRAME-PARAMETERS...)  (REGEXP FUNCTION OTHER-ARGS...)
In the first case, the FRAME-PARAMETERS are pairs of the form
\(PARAMETER . VALUE); these parameter values are used to create
the frame.  In the second case, FUNCTION is called with BUFFER as
the first argument, followed by the OTHER-ARGS--it can display
the buffer in any way it likes.  All this is done by the function
found in `special-display-function'.

If the specified frame parameters include (same-buffer . t), the
buffer is displayed in the currently selected window.  Otherwise,
if they include (same-frame . t), the buffer is displayed in a
new window in the currently selected frame.

If this variable appears \"not to work\", because you add a
regexp to it but the matching buffers still appear in the
selected window, look at the values of `same-window-buffer-names'
and `same-window-regexps'.  Those variables take precedence over
this one."
  :type '(repeat (choice :tag "Buffer"
			 :value ""
			 (regexp :format "%v")
			 (cons :tag "With attributes"
			       :format "%v"
			       :value ("" . nil)
			       (regexp :format "%v")
			       (repeat :tag "Attributes"
				       (cons :format "%v"
					     (symbol :tag "Parameter")
					     (sexp :tag "Value"))))))
  :group 'frames)

(defcustom special-display-function 'special-display-popup-frame
  "Function to call to make a new frame for a special buffer.
It is called with two arguments, the buffer and optional buffer
specific data, and should return a window displaying that buffer.
The default value normally makes a separate frame for the buffer,
using `special-display-frame-alist' to specify the frame
parameters.

But if the buffer specific data includes (same-buffer . t) then
the buffer is displayed in the current selected window.
Otherwise if it includes (same-frame . t) then the buffer is
displayed in a new window in the currently selected frame.

A buffer is special if it is listed in
`special-display-buffer-names' or matches a regexp in
`special-display-regexps'."
  :type 'function
  :group 'frames)

(defun same-window-p (buffer-name)
  "Return non-nil if a buffer named BUFFER-NAME would be shown in the \"same\" window.
This function returns non-nil if `display-buffer' or
`pop-to-buffer' would show a buffer named BUFFER-NAME in the
selected rather than \(as usual\) some other window.  See
`same-window-buffer-names' and `same-window-regexps'."
  (cond
   ((not (stringp buffer-name)))
   ;; The elements of `same-window-buffer-names' can be buffer
   ;; names or cons cells whose cars are buffer names.
   ((member buffer-name same-window-buffer-names))
   ((assoc buffer-name same-window-buffer-names))
   ((catch 'found
      (dolist (regexp same-window-regexps)
	;; The elements of `same-window-regexps' can be regexps
	;; or cons cells whose cars are regexps.
	(when (or (and (stringp regexp)
		       (string-match regexp buffer-name))
		  (and (consp regexp) (stringp (car regexp))
		       (string-match-p (car regexp) buffer-name)))
	  (throw 'found t)))))))

(defcustom same-window-buffer-names nil
  "List of names of buffers that should appear in the \"same\" window.
`display-buffer' and `pop-to-buffer' show a buffer whose name is
on this list in the selected rather than some other window.

An element of this list can be a cons cell instead of just a
string.  In that case the car must be a string specifying the
buffer name.  This is for compatibility with
`special-display-buffer-names'; the cdr of the cons cell is
ignored.

See also `same-window-regexps'."
 :type '(repeat (string :format "%v"))
 :group 'windows)

(defcustom same-window-regexps nil
  "List of regexps saying which buffers should appear in the \"same\" window.
`display-buffer' and `pop-to-buffer' show a buffer whose name
matches a regexp on this list in the selected rather than some
other window.

An element of this list can be a cons cell instead of just a
string.  In that case the car must be a string, which specifies
the buffer name.  This is for compatibility with
`special-display-buffer-names'; the cdr of the cons cell is
ignored.

See also `same-window-buffer-names'."
  :type '(repeat (regexp :format "%v"))
  :group 'windows)

(defcustom pop-up-frames nil
  "Whether `display-buffer' should make a separate frame.
If nil, never make a seperate frame.
If the value is `graphic-only', make a separate frame
on graphic displays only.
Any other non-nil value means always make a separate frame."
  :type '(choice
	  (const :tag "Never" nil)
	  (const :tag "On graphic displays only" graphic-only)
	  (const :tag "Always" t))
  :group 'windows)

(defcustom display-buffer-reuse-frames nil
  "Non-nil means `display-buffer' should reuse frames.
If the buffer in question is already displayed in a frame, raise
that frame."
  :type 'boolean
  :version "21.1"
  :group 'windows)

(defcustom pop-up-windows t
  "Non-nil means `display-buffer' should make a new window."
  :type 'boolean
  :group 'windows)

(defcustom split-height-threshold 80
  "Minimum height of window to be split vertically.
If the value is a number, `display-buffer' can split a window
only if it has at least as many lines.  If the value is nil,
`display-buffer' cannot split a window vertically.

If the window is the only window on its frame, `display-buffer'
can split it regardless of this value."
  :type '(choice (const nil) (number :tag "lines"))
  :version "23.1"
  :group 'windows)

(defcustom split-width-threshold 160
  "Minimum width of window to be split horizontally.
If the value is a number, `display-buffer' can split a window
only if it has at least as many columns.  If the value is nil,
`display-buffer' cannot split a window horizontally."
  :type '(choice (const nil) (number :tag "columns"))
  :version "23.1"
  :group 'windows)

(defcustom split-window-preferred-function nil
  "Function used by `display-buffer' to split windows.
If non-nil, a function called with a window as single argument
supposed to split that window and return the new window.  If the
function returns nil the window is not split.

If nil, `display-buffer' will split the window respecting the
values of `split-height-threshold' and `split-width-threshold'."
  :type '(choice (const nil) (function :tag "Function"))
  :version "23.1"
  :group 'windows)

(defun window--splittable-p (window &optional horizontal)
  "Return non-nil if WINDOW can be split evenly.
Optional argument HORIZONTAL non-nil means check whether WINDOW
can be split horizontally.

WINDOW can be split vertically when the following conditions
hold:

- `window-size-fixed' is either nil or equals `width' for the
  buffer of WINDOW.

- `split-height-threshold' is a number and WINDOW is at least as
  high as `split-height-threshold'.

- When WINDOW is split evenly, the emanating windows are at least
  `window-min-height' lines tall and can accommodate at least one
  line plus - if WINDOW has one - a mode line.

WINDOW can be split horizontally when the following conditions
hold:

- `window-size-fixed' is either nil or equals `height' for the
  buffer of WINDOW.

- `split-width-threshold' is a number and WINDOW is at least as
  wide as `split-width-threshold'.

- When WINDOW is split evenly, the emanating windows are at least
  `window-min-width' or two (whichever is larger) columns wide."
  (when (window-live-p window)
    (with-current-buffer (window-buffer window)
      (if horizontal
	  ;; A window can be split horizontally when its width is not
	  ;; fixed, it is at least `split-width-threshold' columns wide
	  ;; and at least twice as wide as `window-min-width' and 2 (the
	  ;; latter value is hardcoded).
	  (and (memq window-size-fixed '(nil height))
	       ;; Testing `window-full-width-p' here hardly makes any
	       ;; sense nowadays.  This can be done more intuitively by
	       ;; setting up `split-width-threshold' appropriately.
	       (numberp split-width-threshold)
	       (>= (window-width window)
		   (max split-width-threshold
			(* 2 (max window-min-width 2)))))
	;; A window can be split vertically when its height is not
	;; fixed, it is at least `split-height-threshold' lines high,
	;; and it is at least twice as high as `window-min-height' and 2
	;; if it has a modeline or 1.
	(and (memq window-size-fixed '(nil width))
	     (numberp split-height-threshold)
	     (>= (window-height window)
		 (max split-height-threshold
		      (* 2 (max window-min-height
				(if mode-line-format 2 1))))))))))

(defun window--try-to-split-window (window)
  "Split WINDOW if it is splittable.
See `window--splittable-p' for how to determine whether a window
is splittable.  If WINDOW can be split, return the value returned
by `split-window' (or `split-window-preferred-function')."
  (when (and (window-live-p window)
	     (not (frame-parameter (window-frame window) 'unsplittable)))
    (if (functionp split-window-preferred-function)
	;; `split-window-preferred-function' is specified, so use it.
	(funcall split-window-preferred-function window)
      (or (and (window--splittable-p window)
	       ;; Split window vertically.
	       (split-window window))
	  (and (window--splittable-p window t)
	       ;; Split window horizontally.
	       (split-window window nil t))
	  (and (eq window (frame-root-window (window-frame window)))
	       (not (window-minibuffer-p window))
	       ;; If WINDOW is the only window on its frame and not the
	       ;; minibuffer window, attempt to split it vertically
	       ;; disregarding the value of `split-height-threshold'.
	       (let ((split-height-threshold 0))
		 (and (window--splittable-p window)
		      (split-window window))))))))

(defun window--frame-usable-p (frame)
  "Return FRAME if it can be used to display a buffer."
  (when (frame-live-p frame)
    (let ((window (frame-root-window frame)))
      ;; `frame-root-window' may be an internal window which is considered
      ;; "dead" by `window-live-p'.  Hence if `window' is not live we
      ;; implicitly know that `frame' has a visible window we can use.
      (unless (and (window-live-p window)
                   (or (window-minibuffer-p window)
                       ;; If the window is soft-dedicated, the frame is usable.
                       ;; Actually, even if the window is really dedicated,
                       ;; the frame is still usable by splitting it.
                       ;; At least Emacs-22 allowed it, and it is desirable
                       ;; when displaying same-frame windows.
                       nil ; (eq t (window-dedicated-p window))
                       ))
	frame))))

(defcustom even-window-heights t
  "If non-nil `display-buffer' will try to even window heights.
Otherwise `display-buffer' will leave the window configuration
alone.  Heights are evened only when `display-buffer' chooses a
window that appears above or below the selected window."
  :type 'boolean
  :group 'windows)

(defun window--even-window-heights (window)
  "Even heights of WINDOW and selected window.
Do this only if these windows are vertically adjacent to each
other, `even-window-heights' is non-nil, and the selected window
is higher than WINDOW."
  (when (and even-window-heights
	     (not (eq window (selected-window)))
	     ;; Don't resize minibuffer windows.
	     (not (window-minibuffer-p (selected-window)))
	     (> (window-height (selected-window)) (window-height window)) 
	     (eq (window-frame window) (window-frame (selected-window)))
	     (let ((sel-edges (window-edges (selected-window)))
		   (win-edges (window-edges window)))
	       (and (= (nth 0 sel-edges) (nth 0 win-edges))
		    (= (nth 2 sel-edges) (nth 2 win-edges))
		    (or (= (nth 1 sel-edges) (nth 3 win-edges))
			(= (nth 3 sel-edges) (nth 1 win-edges))))))
    (let ((window-min-height 1))
      ;; Don't throw an error if we can't even window heights for
      ;; whatever reason.
      (condition-case nil
	  (enlarge-window (/ (- (window-height window) (window-height)) 2))
	(error nil)))))

(defun window--display-buffer-1 (window)
  "Raise the frame containing WINDOW.
Do not raise the selected frame.  Return WINDOW."
  (let* ((frame (window-frame window))
	 (visible (frame-visible-p frame)))
    (unless (or (not visible)
		;; Assume the selected frame is already visible enough.
		(eq frame (selected-frame))
		;; Assume the frame from which we invoked the minibuffer
		;; is visible.
		(and (minibuffer-window-active-p (selected-window))
		     (eq frame (window-frame (minibuffer-selected-window)))))
      (raise-frame frame))
    window))

(defun window--display-buffer-2 (buffer window)
  "Display BUFFER in WINDOW and make its frame visible.
Return WINDOW."
  (when (and (buffer-live-p buffer) (window-live-p window))
    (set-window-buffer window buffer)
    (window--display-buffer-1 window)))

(defun display-buffer (buffer-or-name &optional not-this-window frame)
  "Make buffer BUFFER-OR-NAME appear in some window but don't select it.
BUFFER-OR-NAME must be a buffer or the name of an existing
buffer.  Return the window chosen to display BUFFER-OR-NAME or
nil if no such window is found.

Optional argument NOT-THIS-WINDOW non-nil means display the
buffer in a window other than the selected one, even if it is
already displayed in the selected window.

Optional argument FRAME specifies which frames to investigate
when the specified buffer is already displayed.  If the buffer is
already displayed in some window on one of these frames simply
return that window.  Possible values of FRAME are:

`visible' - consider windows on all visible frames.

0 - consider windows on all visible or iconified frames.

t - consider windows on all frames.

A specific frame - consider windows on that frame only.

nil - consider windows on the selected frame \(actually the
last non-minibuffer frame\) only.  If, however, either
`display-buffer-reuse-frames' or `pop-up-frames' is non-nil
\(non-nil and not graphic-only on a text-only terminal),
consider all visible or iconified frames."
  (interactive "BDisplay buffer:\nP")
  (let* ((can-use-selected-window
	  ;; The selected window is usable unless either NOT-THIS-WINDOW
	  ;; is non-nil, it is dedicated to its buffer, or it is the
	  ;; `minibuffer-window'.
	  (not (or not-this-window
		   (window-dedicated-p (selected-window))
		   (window-minibuffer-p))))
	 (buffer (if (bufferp buffer-or-name)
		     buffer-or-name
		   (get-buffer buffer-or-name)))
	 (name-of-buffer (buffer-name buffer))
	 ;; On text-only terminals do not pop up a new frame when
	 ;; `pop-up-frames' equals graphic-only.
	 (use-pop-up-frames (if (eq pop-up-frames 'graphic-only)
				(display-graphic-p)
			      pop-up-frames))
	 ;; `frame-to-use' is the frame where to show `buffer' - either
	 ;; the selected frame or the last nonminibuffer frame.
	 (frame-to-use
	  (or (window--frame-usable-p (selected-frame))
	      (window--frame-usable-p (last-nonminibuffer-frame))))
	 ;; `window-to-use' is the window we use for showing `buffer'.
	 window-to-use)
    (cond
     ((not (buffer-live-p buffer))
      (error "No such buffer %s" buffer))
     (display-buffer-function
      ;; Let `display-buffer-function' do the job.
      (funcall display-buffer-function buffer not-this-window))
     ((and (not not-this-window)
	   (eq (window-buffer (selected-window)) buffer))
      ;; The selected window already displays BUFFER and
      ;; `not-this-window' is nil, so use it.
      (window--display-buffer-1 (selected-window)))
     ((and can-use-selected-window (same-window-p name-of-buffer))
      ;; If the buffer's name tells us to use the selected window do so.
      (window--display-buffer-2 buffer (selected-window)))
     ((let ((frames (or frame
			(and (or use-pop-up-frames
				 display-buffer-reuse-frames
				 (not (last-nonminibuffer-frame)))
			     0)
			(last-nonminibuffer-frame))))
	(and (setq window-to-use (get-buffer-window buffer frames))
	     (or can-use-selected-window
		 (not (eq (selected-window) window-to-use)))))
      ;; If the buffer is already displayed in some window use that.
      (window--display-buffer-1 window-to-use))
     ((and special-display-function
	   ;; `special-display-p' returns either t or a list of frame
	   ;; parameters to pass to `special-display-function'.
	   (let ((pars (special-display-p name-of-buffer)))
	     (when pars
	       (funcall special-display-function
			buffer (if (listp pars) pars))))))
     ((or use-pop-up-frames (not frame-to-use))
      ;; We want or need a new frame.
      (window--display-buffer-2
       buffer (frame-selected-window (funcall pop-up-frame-function))))
     ((and pop-up-windows
	   ;; Make a new window.
	   (or (not (frame-parameter frame-to-use 'unsplittable))
	       ;; If the selected frame cannot be split look at
	       ;; `last-nonminibuffer-frame'.
	       (and (eq frame-to-use (selected-frame))
		    (setq frame-to-use (last-nonminibuffer-frame))
		    (window--frame-usable-p frame-to-use)
		    (not (frame-parameter frame-to-use 'unsplittable))))
	   ;; Attempt to split largest or least recently used window.
	   (setq window-to-use
		 (or (window--try-to-split-window
		      (get-largest-window frame-to-use t))
		     (window--try-to-split-window
		      (get-lru-window frame-to-use t))))
	   (window--display-buffer-2 buffer window-to-use)))
     ((let ((window-to-undedicate
	     ;; When NOT-THIS-WINDOW is non-nil, temporarily dedicate
	     ;; the selected window to its buffer, to avoid that some of
	     ;; the `get-' routines below choose it.  (Bug#1415)
	     (and not-this-window (not (window-dedicated-p))
		  (set-window-dedicated-p (selected-window) t)
		  (selected-window))))
	(unwind-protect
	    (setq window-to-use
		  ;; Reuse an existing window.
		  (or (get-lru-window frame-to-use)
		      (let ((window (get-buffer-window buffer 'visible)))
			(unless (and not-this-window
				     (eq window (selected-window)))
			  window))
		      (get-largest-window 'visible)
		      (let ((window (get-buffer-window buffer 0)))
			(unless (and not-this-window
				     (eq window (selected-window)))
			  window))
		      (get-largest-window 0)
		      (frame-selected-window (funcall pop-up-frame-function))))
	  (when (window-live-p window-to-undedicate)
	    ;; Restore dedicated status of selected window.
	    (set-window-dedicated-p window-to-undedicate nil))))
      (window--even-window-heights window-to-use)
      (window--display-buffer-2 buffer window-to-use)))))

(defun pop-to-buffer (buffer-or-name &optional other-window norecord)
  "Select buffer BUFFER-OR-NAME in some window, preferably a different one.
BUFFER-OR-NAME may be a buffer, a string \(a buffer name), or
nil.  If BUFFER-OR-NAME is a string not naming an existent
buffer, create a buffer with that name.  If BUFFER-OR-NAME is
nil, choose some other buffer.

If `pop-up-windows' is non-nil, windows can be split to display
the buffer.  If optional second arg OTHER-WINDOW is non-nil,
insist on finding another window even if the specified buffer is
already visible in the selected window, and ignore
`same-window-regexps' and `same-window-buffer-names'.

If the window to show BUFFER-OR-NAME is not on the selected
frame, raise that window's frame and give it input focus.

This function returns the buffer it switched to.  This uses the
function `display-buffer' as a subroutine; see the documentation
of `display-buffer' for additional customization information.

Optional third arg NORECORD non-nil means do not put this buffer
at the front of the list of recently selected ones."
  (let ((buffer
         ;; FIXME: This behavior is carried over from the previous C version
         ;; of pop-to-buffer, but really we should use just
         ;; `get-buffer' here.
         (if (null buffer-or-name) (other-buffer (current-buffer))
           (or (get-buffer buffer-or-name)
               (let ((buf (get-buffer-create buffer-or-name)))
                 (set-buffer-major-mode buf)
                 buf))))
	(old-window (selected-window))
	(old-frame (selected-frame))
	new-window new-frame)
    (set-buffer buffer)
    (setq new-window (display-buffer buffer other-window))
    (unless (eq new-window old-window)
      ;; `display-buffer' has chosen another window, select it.
      (select-window new-window norecord)
      (setq new-frame (window-frame new-window))
      (unless (eq new-frame old-frame)
	;; `display-buffer' has chosen another frame, make sure it gets
	;; input focus and is risen.
	(select-frame-set-input-focus new-frame)))
    buffer))

;; I think this should be the default; I think people will prefer it--rms.
(defcustom split-window-keep-point t
  "If non-nil, \\[split-window-vertically] keeps the original point \
in both children.
This is often more convenient for editing.
If nil, adjust point in each of the two windows to minimize redisplay.
This is convenient on slow terminals, but point can move strangely.

This option applies only to `split-window-vertically' and
functions that call it.  `split-window' always keeps the original
point in both children."
  :type 'boolean
  :group 'windows)

(defun split-window-vertically (&optional size)
  "Split selected window into two windows, one above the other.
The upper window gets SIZE lines and the lower one gets the rest.
SIZE negative means the lower window gets -SIZE lines and the
upper one the rest.  With no argument, split windows equally or
close to it.  Both windows display the same buffer, now current.

If the variable `split-window-keep-point' is non-nil, both new
windows will get the same value of point as the selected window.
This is often more convenient for editing.  The upper window is
the selected window.

Otherwise, we choose window starts so as to minimize the amount of
redisplay; this is convenient on slow terminals.  The new selected
window is the one that the current value of point appears in.  The
value of point can change if the text around point is hidden by the
new mode line.

Regardless of the value of `split-window-keep-point', the upper
window is the original one and the return value is the new, lower
window."
  (interactive "P")
  (let ((old-window (selected-window))
	(old-point (point))
	(size (and size (prefix-numeric-value size)))
        moved-by-window-height moved new-window bottom)
    (and size (< size 0)
	 ;; Handle negative SIZE value.
	 (setq size (+ (window-height) size)))
    (setq new-window (split-window nil size))
    (unless split-window-keep-point
      (save-excursion
	(set-buffer (window-buffer))
	(goto-char (window-start))
	(setq moved (vertical-motion (window-height)))
	(set-window-start new-window (point))
	(when (> (point) (window-point new-window))
	  (set-window-point new-window (point)))
	(when (= moved (window-height))
	  (setq moved-by-window-height t)
	  (vertical-motion -1))
	(setq bottom (point)))
      (and moved-by-window-height
	   (<= bottom (point))
	   (set-window-point old-window (1- bottom)))
      (and moved-by-window-height
	   (<= (window-start new-window) old-point)
	   (set-window-point new-window old-point)
	   (select-window new-window)))
    (split-window-save-restore-data new-window old-window)))

;; This is to avoid compiler warnings.
(defvar view-return-to-alist)

(defun split-window-save-restore-data (new-window old-window)
  (with-current-buffer (window-buffer)
    (when view-mode
      (let ((old-info (assq old-window view-return-to-alist)))
	(when old-info
	  (push (cons new-window (cons (car (cdr old-info)) t))
		view-return-to-alist))))
    new-window))

(defun split-window-horizontally (&optional size)
  "Split selected window into two windows side by side.
The selected window becomes the left one and gets SIZE columns.
SIZE negative means the right window gets -SIZE lines.

SIZE includes the width of the window's scroll bar; if there are
no scroll bars, it includes the width of the divider column to
the window's right, if any.  SIZE omitted or nil means split
window equally.

The selected window remains selected.  Return the new window."
  (interactive "P")
  (let ((old-window (selected-window))
	(size (and size (prefix-numeric-value size))))
    (and size (< size 0)
	 ;; Handle negative SIZE value.
	 (setq size (+ (window-width) size)))
    (split-window-save-restore-data (split-window nil size t) old-window)))


(defun set-window-text-height (window height)
  "Set the height in lines of the text display area of WINDOW to HEIGHT.
HEIGHT doesn't include the mode line or header line, if any, or
any partial-height lines in the text display area.

Note that the current implementation of this function cannot
always set the height exactly, but attempts to be conservative,
by allocating more lines than are actually needed in the case
where some error may be present."
  (let ((delta (- height (window-text-height window))))
    (unless (zerop delta)
      ;; Setting window-min-height to a value like 1 can lead to very
      ;; bizarre displays because it also allows Emacs to make *other*
      ;; windows 1-line tall, which means that there's no more space for
      ;; the modeline.
      (let ((window-min-height (min 2 height))) ; One text line plus a modeline.
	(if (and window (not (eq window (selected-window))))
	    (save-selected-window
	      (select-window window 'norecord)
	      (enlarge-window delta))
	  (enlarge-window delta))))))


(defun enlarge-window-horizontally (columns)
  "Make selected window COLUMNS wider.
Interactively, if no argument is given, make selected window one
column wider."
  (interactive "p")
  (enlarge-window columns t))

(defun shrink-window-horizontally (columns)
  "Make selected window COLUMNS narrower.
Interactively, if no argument is given, make selected window one
column narrower."
  (interactive "p")
  (shrink-window columns t))

(defun window-buffer-height (window)
  "Return the height (in screen lines) of the buffer that WINDOW is displaying."
  (with-current-buffer (window-buffer window)
    (max 1
	 (count-screen-lines (point-min) (point-max)
			     ;; If buffer ends with a newline, ignore it when
			     ;; counting height unless point is after it.
			     (eobp)
			     window))))

(defun count-screen-lines (&optional beg end count-final-newline window)
  "Return the number of screen lines in the region.
The number of screen lines may be different from the number of actual lines,
due to line breaking, display table, etc.

Optional arguments BEG and END default to `point-min' and `point-max'
respectively.

If region ends with a newline, ignore it unless optional third argument
COUNT-FINAL-NEWLINE is non-nil.

The optional fourth argument WINDOW specifies the window used for obtaining
parameters such as width, horizontal scrolling, and so on.  The default is
to use the selected window's parameters.

Like `vertical-motion', `count-screen-lines' always uses the current buffer,
regardless of which buffer is displayed in WINDOW.  This makes possible to use
`count-screen-lines' in any buffer, whether or not it is currently displayed
in some window."
  (unless beg
    (setq beg (point-min)))
  (unless end
    (setq end (point-max)))
  (if (= beg end)
      0
    (save-excursion
      (save-restriction
        (widen)
        (narrow-to-region (min beg end)
                          (if (and (not count-final-newline)
                                   (= ?\n (char-before (max beg end))))
                              (1- (max beg end))
                            (max beg end)))
        (goto-char (point-min))
        (1+ (vertical-motion (buffer-size) window))))))

(defun fit-window-to-buffer (&optional window max-height min-height)
  "Adjust height of WINDOW to display its buffer's contents exactly.
WINDOW defaults to the selected window.
Optional argument MAX-HEIGHT specifies the maximum height of the
window and defaults to the maximum permissible height of a window
on WINDOW's frame.
Optional argument MIN-HEIGHT specifies the minimum height of the
window and defaults to `window-min-height'.
Both, MAX-HEIGHT and MIN-HEIGHT are specified in lines and
include the mode line and header line, if any.

Return non-nil if height was orderly adjusted, nil otherwise.

Caution: This function can delete WINDOW and/or other windows
when their height shrinks to less than MIN-HEIGHT."
  (interactive)
  ;; Do all the work in WINDOW and its buffer and restore the selected
  ;; window and the current buffer when we're done.
  (let ((old-buffer (current-buffer))
	value)
    (with-selected-window (or window (setq window (selected-window)))
      (set-buffer (window-buffer))
      ;; Use `condition-case' to handle any fixed-size windows and other
      ;; pitfalls nearby.
      (condition-case nil
	  (let* (;; MIN-HEIGHT must not be less than 1 and defaults to
		 ;; `window-min-height'.
		 (min-height (max (or min-height window-min-height) 1))
		 (max-window-height
		  ;; Maximum height of any window on this frame.
		  (min (window-height (frame-root-window)) (frame-height)))
		 ;; MAX-HEIGHT must not be larger than max-window-height and
		 ;; defaults to max-window-height.
		 (max-height
		  (min (or max-height max-window-height) max-window-height))
		 (desired-height
		  ;; The height necessary to show all of WINDOW's buffer,
		  ;; constrained by MIN-HEIGHT and MAX-HEIGHT.
		  (max
		   (min
		    ;; For an empty buffer `count-screen-lines' returns zero.
		    ;; Even in that case we need one line for the cursor.
		    (+ (max (count-screen-lines) 1)
		       ;; For non-minibuffers count the mode line, if any.
		       (if (and (not (window-minibuffer-p)) mode-line-format)
			   1 0)
		       ;; Count the header line, if any.
		       (if header-line-format 1 0))
		    max-height)
		   min-height))
		 (delta
		  ;; How much the window height has to change.
		  (if (= (window-height) (window-height (frame-root-window)))
		      ;; Don't try to resize a full-height window.
		      0
		    (- desired-height (window-height))))
		 ;; Do something reasonable so `enlarge-window' can make
		 ;; windows as small as MIN-HEIGHT.
		 (window-min-height (min min-height window-min-height)))
	    ;; Don't try to redisplay with the cursor at the end on its
	    ;; own line--that would force a scroll and spoil things.
	    (when (and (eobp) (bolp) (not (bobp)))
	      (set-window-point window (1- (window-point))))
	    ;; Adjust WINDOW's height to the nominally correct one
	    ;; (which may actually be slightly off because of variable
	    ;; height text, etc).
	    (unless (zerop delta)
	      (enlarge-window delta))
	    ;; `enlarge-window' might have deleted WINDOW, so make sure
	    ;; WINDOW's still alive for the remainder of this.
	    ;; Note: Deleting WINDOW is clearly counter-intuitive in
	    ;; this context, but we can't do much about it given the
	    ;; current semantics of `enlarge-window'.
	    (when (window-live-p window)
	      ;; Check if the last line is surely fully visible.  If
	      ;; not, enlarge the window.
	      (let ((end (save-excursion
			   (goto-char (point-max))
			   (when (and (bolp) (not (bobp)))
			     ;; Don't include final newline.
			     (backward-char 1))
			   (when truncate-lines
			     ;; If line-wrapping is turned off, test the
			     ;; beginning of the last line for
			     ;; visibility instead of the end, as the
			     ;; end of the line could be invisible by
			     ;; virtue of extending past the edge of the
			     ;; window.
			     (forward-line 0))
			   (point))))
		(set-window-vscroll window 0)
		(while (and (< desired-height max-height)
			    (= desired-height (window-height))
			    (not (pos-visible-in-window-p end)))
		  (enlarge-window 1)
		  (setq desired-height (1+ desired-height))))
	      ;; Return non-nil only if nothing "bad" happened.
	      (setq value t)))
	(error nil)))
    (when (buffer-live-p old-buffer)
      (set-buffer old-buffer))
    value))

(defun window-safely-shrinkable-p (&optional window)
  "Return t if WINDOW can be shrunk without shrinking other windows.
WINDOW defaults to the selected window."
  (with-selected-window (or window (selected-window))
    (let ((edges (window-edges)))
      (or (= (nth 2 edges) (nth 2 (window-edges (previous-window))))
	  (= (nth 0 edges) (nth 0 (window-edges (next-window))))))))

(defun shrink-window-if-larger-than-buffer (&optional window)
  "Shrink height of WINDOW if its buffer doesn't need so many lines.
More precisely, shrink WINDOW vertically to be as small as
possible, while still showing the full contents of its buffer.
WINDOW defaults to the selected window.

Do not shrink to less than `window-min-height' lines.  Do nothing
if the buffer contains more lines than the present window height,
or if some of the window's contents are scrolled out of view, or
if shrinking this window would also shrink another window, or if
the window is the only window of its frame.

Return non-nil if the window was shrunk, nil otherwise."
  (interactive)
  (when (null window)
    (setq window (selected-window)))
  (let* ((frame (window-frame window))
	 (mini (frame-parameter frame 'minibuffer))
	 (edges (window-edges window)))
    (if (and (not (eq window (frame-root-window frame)))
	     (window-safely-shrinkable-p window)
	     (pos-visible-in-window-p (point-min) window)
	     (not (eq mini 'only))
	     (or (not mini)
		 (let ((mini-window (minibuffer-window frame)))
		   (or (null mini-window)
		       (not (eq frame (window-frame mini-window)))
		       (< (nth 3 edges)
			  (nth 1 (window-edges mini-window)))
		       (> (nth 1 edges)
			  (frame-parameter frame 'menu-bar-lines))))))
	(fit-window-to-buffer window (window-height window)))))

(defun kill-buffer-and-window ()
  "Kill the current buffer and delete the selected window."
  (interactive)
  (let ((window-to-delete (selected-window))
	(buffer-to-kill (current-buffer))
	(delete-window-hook (lambda ()
			      (condition-case nil
				  (delete-window)
				(error nil)))))
    (unwind-protect
	(progn
	  (add-hook 'kill-buffer-hook delete-window-hook t t)
	  (if (kill-buffer (current-buffer))
	      ;; If `delete-window' failed before, we rerun it to regenerate
	      ;; the error so it can be seen in the echo area.
	      (when (eq (selected-window) window-to-delete)
		(delete-window))))
      ;; If the buffer is not dead for some reason (probably because
      ;; of a `quit' signal), remove the hook again.
      (condition-case nil
	  (with-current-buffer buffer-to-kill
	    (remove-hook 'kill-buffer-hook delete-window-hook t))
	(error nil)))))

(defun quit-window (&optional kill window)
  "Quit WINDOW and bury its buffer.
With a prefix argument, kill the buffer instead.  WINDOW defaults
to the selected window.

If WINDOW is non-nil, dedicated, or a minibuffer window, delete
it and, if it's alone on its frame, its frame too.  Otherwise, or
if deleting WINDOW fails in any of the preceding cases, display
another buffer in WINDOW using `switch-to-buffer'.

Optional argument KILL non-nil means kill WINDOW's buffer.
Otherwise, bury WINDOW's buffer, see `bury-buffer'."
  (interactive "P")
  (let ((buffer (window-buffer window)))
    (if (or window
	    (window-minibuffer-p window)
	    (window-dedicated-p window))
	;; WINDOW is either non-nil, a minibuffer window, or dedicated;
	;; try to delete it.
	(let* ((window (or window (selected-window)))
	       (frame (window-frame window)))
	  (if (eq window (frame-root-window frame))
	      ;; WINDOW is alone on its frame.  `delete-windows-on'
	      ;; knows how to handle that case.
	      (delete-windows-on buffer frame)
	    ;; There are other windows on its frame, delete WINDOW.
	    (delete-window window)))
      ;; Otherwise, switch to another buffer in the selected window.
      (switch-to-buffer nil))

    ;; Deal with the buffer.
    (if kill
	(kill-buffer buffer)
      (bury-buffer buffer))))

(defvar recenter-last-op nil
  "Indicates the last recenter operation performed.
Possible values: `top', `middle', `bottom'.")

(defun recenter-top-bottom (&optional arg)
  "Move current line to window center, top, and bottom, successively.
With no prefix argument, the first call redraws the frame and
 centers point vertically within the window.  Successive calls
 scroll the window, placing point on the top, bottom, and middle
 consecutively.  The cycling order is middle -> top -> bottom.

A prefix argument is handled like `recenter':
 With numeric prefix ARG, move current line to window-line ARG.
 With plain `C-u', move current line to window center.

Top and bottom destinations are actually `scroll-margin' lines
 the from true window top and bottom."
  (interactive "P")
  (cond
   (arg (recenter arg))                 ; Always respect ARG.
   ((or (not (eq this-command last-command))
	(eq recenter-last-op 'bottom))
    (setq recenter-last-op 'middle)
    (recenter))
   (t
    (let ((this-scroll-margin
	   (min (max 0 scroll-margin)
		(truncate (/ (window-body-height) 4.0)))))
      (cond ((eq recenter-last-op 'middle)
	     (setq recenter-last-op 'top)
	     (recenter this-scroll-margin))
	    ((eq recenter-last-op 'top)
	     (setq recenter-last-op 'bottom)
	     (recenter (- -1 this-scroll-margin))))))))

(define-key global-map [?\C-l] 'recenter-top-bottom)

(defvar mouse-autoselect-window-timer nil
  "Timer used by delayed window autoselection.")

(defvar mouse-autoselect-window-position nil
  "Last mouse position recorded by delayed window autoselection.")

(defvar mouse-autoselect-window-window nil
  "Last window recorded by delayed window autoselection.")

(defvar mouse-autoselect-window-state nil
  "When non-nil, special state of delayed window autoselection.
Possible values are `suspend' \(suspend autoselection after a menu or
scrollbar interaction\) and `select' \(the next invocation of
'handle-select-window' shall select the window immediately\).")

(defun mouse-autoselect-window-cancel (&optional force)
  "Cancel delayed window autoselection.
Optional argument FORCE means cancel unconditionally."
  (unless (and (not force)
	       ;; Don't cancel for select-window or select-frame events
	       ;; or when the user drags a scroll bar.
	       (or (memq this-command
			 '(handle-select-window handle-switch-frame))
		   (and (eq this-command 'scroll-bar-toolkit-scroll)
			(memq (nth 4 (event-end last-input-event))
			      '(handle end-scroll)))))
    (setq mouse-autoselect-window-state nil)
    (when (timerp mouse-autoselect-window-timer)
      (cancel-timer mouse-autoselect-window-timer))
    (remove-hook 'pre-command-hook 'mouse-autoselect-window-cancel)))

(defun mouse-autoselect-window-start (mouse-position &optional window suspend)
  "Start delayed window autoselection.
MOUSE-POSITION is the last position where the mouse was seen as returned
by `mouse-position'.  Optional argument WINDOW non-nil denotes the
window where the mouse was seen.  Optional argument SUSPEND non-nil
means suspend autoselection."
  ;; Record values for MOUSE-POSITION, WINDOW, and SUSPEND.
  (setq mouse-autoselect-window-position mouse-position)
  (when window (setq mouse-autoselect-window-window window))
  (setq mouse-autoselect-window-state (when suspend 'suspend))
  ;; Install timer which runs `mouse-autoselect-window-select' after
  ;; `mouse-autoselect-window' seconds.
  (setq mouse-autoselect-window-timer
	(run-at-time
	 (abs mouse-autoselect-window) nil 'mouse-autoselect-window-select)))

(defun mouse-autoselect-window-select ()
  "Select window with delayed window autoselection.
If the mouse position has stabilized in a non-selected window, select
that window.  The minibuffer window is selected only if the minibuffer is
active.  This function is run by `mouse-autoselect-window-timer'."
  (condition-case nil
      (let* ((mouse-position (mouse-position))
	     (window
	      (condition-case nil
		  (window-at (cadr mouse-position) (cddr mouse-position)
			     (car mouse-position))
		(error nil))))
	(cond
	 ((or (menu-or-popup-active-p)
	      (and window
		   (not (coordinates-in-window-p (cdr mouse-position) window))))
	  ;; A menu / popup dialog is active or the mouse is on the scroll-bar
	  ;; of WINDOW, temporarily suspend delayed autoselection.
	  (mouse-autoselect-window-start mouse-position nil t))
	 ((eq mouse-autoselect-window-state 'suspend)
	  ;; Delayed autoselection was temporarily suspended, reenable it.
	  (mouse-autoselect-window-start mouse-position))
	 ((and window (not (eq window (selected-window)))
	       (or (not (numberp mouse-autoselect-window))
		   (and (> mouse-autoselect-window 0)
			;; If `mouse-autoselect-window' is positive, select
			;; window if the window is the same as before.
			(eq window mouse-autoselect-window-window))
		   ;; Otherwise select window if the mouse is at the same
		   ;; position as before.  Observe that the first test after
		   ;; starting autoselection usually fails since the value of
		   ;; `mouse-autoselect-window-position' recorded there is the
		   ;; position where the mouse has entered the new window and
		   ;; not necessarily where the mouse has stopped moving.
		   (equal mouse-position mouse-autoselect-window-position))
	       ;; The minibuffer is a candidate window if it's active.
	       (or (not (window-minibuffer-p window))
		   (eq window (active-minibuffer-window))))
	  ;; Mouse position has stabilized in non-selected window: Cancel
	  ;; delayed autoselection and try to select that window.
	  (mouse-autoselect-window-cancel t)
	  ;; Select window where mouse appears unless the selected window is the
	  ;; minibuffer.  Use `unread-command-events' in order to execute pre-
	  ;; and post-command hooks and trigger idle timers.  To avoid delaying
	  ;; autoselection again, set `mouse-autoselect-window-state'."
	  (unless (window-minibuffer-p (selected-window))
	    (setq mouse-autoselect-window-state 'select)
	    (setq unread-command-events
		  (cons (list 'select-window (list window))
			unread-command-events))))
	 ((or (and window (eq window (selected-window)))
	      (not (numberp mouse-autoselect-window))
	      (equal mouse-position mouse-autoselect-window-position))
	  ;; Mouse position has either stabilized in the selected window or at
	  ;; `mouse-autoselect-window-position': Cancel delayed autoselection.
	  (mouse-autoselect-window-cancel t))
	 (t
	  ;; Mouse position has not stabilized yet, resume delayed
	  ;; autoselection.
	  (mouse-autoselect-window-start mouse-position window))))
    (error nil)))

(defun handle-select-window (event)
  "Handle select-window events."
  (interactive "e")
  (let ((window (posn-window (event-start event))))
    (unless (or (not (window-live-p window))
		;; Don't switch if we're currently in the minibuffer.
		;; This tries to work around problems where the
		;; minibuffer gets unselected unexpectedly, and where
		;; you then have to move your mouse all the way down to
		;; the minibuffer to select it.
		(window-minibuffer-p (selected-window))
		;; Don't switch to minibuffer window unless it's active.
		(and (window-minibuffer-p window)
		     (not (minibuffer-window-active-p window)))
		;; Don't switch when autoselection shall be delayed.
		(and (numberp mouse-autoselect-window)
		     (not (zerop mouse-autoselect-window))
		     (not (eq mouse-autoselect-window-state 'select))
		     (progn
		       ;; Cancel any delayed autoselection.
		       (mouse-autoselect-window-cancel t)
		       ;; Start delayed autoselection from current mouse
		       ;; position and window.
		       (mouse-autoselect-window-start (mouse-position) window)
		       ;; Executing a command cancels delayed autoselection.
		       (add-hook
			'pre-command-hook 'mouse-autoselect-window-cancel))))
      (when mouse-autoselect-window
	;; Reset state of delayed autoselection.
	(setq mouse-autoselect-window-state nil)
	;; Run `mouse-leave-buffer-hook' when autoselecting window.
	(run-hooks 'mouse-leave-buffer-hook))
      (select-window window))))

(defun delete-other-windows-vertically (&optional window)
  "Delete the windows in the same column with WINDOW, but not WINDOW itself.
This may be a useful alternative binding for \\[delete-other-windows]
 if you often split windows horizontally."
  (interactive)
  (let* ((window (or window (selected-window)))
         (edges (window-edges window))
         (w window) delenda)
    (while (not (eq (setq w (next-window w 1)) window))
      (let ((e (window-edges w)))
        (when (and (= (car e) (car edges))
                   (= (caddr e) (caddr edges)))
          (push w delenda))))
    (mapc 'delete-window delenda)))

(defun truncated-partial-width-window-p (&optional window)
  "Return non-nil if lines in WINDOW are specifically truncated due to its width.
WINDOW defaults to the selected window.
Return nil if WINDOW is not a partial-width window
 (regardless of the value of `truncate-lines').
Otherwise, consult the value of `truncate-partial-width-windows'
 for the buffer shown in WINDOW."
  (unless window
    (setq window (selected-window)))
  (unless (window-full-width-p window)
    (let ((t-p-w-w (buffer-local-value 'truncate-partial-width-windows
				       (window-buffer window))))
      (if (integerp t-p-w-w)
	  (< (window-width window) t-p-w-w)
	t-p-w-w))))

(define-key ctl-x-map "2" 'split-window-vertically)
(define-key ctl-x-map "3" 'split-window-horizontally)
(define-key ctl-x-map "}" 'enlarge-window-horizontally)
(define-key ctl-x-map "{" 'shrink-window-horizontally)
(define-key ctl-x-map "-" 'shrink-window-if-larger-than-buffer)
(define-key ctl-x-map "+" 'balance-windows)
(define-key ctl-x-4-map "0" 'kill-buffer-and-window)

;; arch-tag: b508dfcc-c353-4c37-89fa-e773fe10cea9
;;; window.el ends here
