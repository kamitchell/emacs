;;; thumbs.el --- Thumbnails previewer for images files

;; Copyright 2004 Free Software Foundation, Inc

;; Author: Jean-Philippe Theberge <jphiltheberge@videotron.ca>
;; Keywords: Multimedia

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
;;              
;; Thanks: Alex Schroeder <alex@gnu.org> for maintaining the package at some time
;;         The peoples at #emacs@freenode.net for numerous help
;;         RMS for emacs and the GNU project.
;;

;;; Commentary:

;; This package create two new mode: thumbs-mode and
;; thumbs-view-image-mode. It is used for images browsing and viewing
;; from within emacs. Minimal image manipulation functions are also
;; available via external programs.
;;
;; The 'convert' program from 'ImageMagick'
;; [URL:http://www.imagemagick.org/] is required.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; CHANGELOG
;;
;; This is version 2.0
;;
;; USAGE
;;
;; Type M-x thumbs RET DIR RET to view the directory DIR in Thumbs mode.
;; That should be a directory containing image files.
;; from dired, C-t m enter in thumbs-mode with all marked files
;;             C-t a enter in thumbs-mode with all files in current-directory
;; In thumbs-mode, pressing <return> on a image will bring you in image view mode
;; for that image.  C-h m will give you a list of available keybinding.

;;; History:
;;

;;; Code:

(require 'dired)

;; CUSTOMIZATIONS

(defgroup thumbs nil
  "Thumbnails previewer."
  :group 'multimedia)

(defcustom thumbs-thumbsdir
  (expand-file-name "~/.emacs-thumbs")
  "*Directory to store thumbnails."
  :type 'directory
  :group 'thumbs)

(defcustom thumbs-geometry "100x100"
  "*Size of thumbnails."
  :type 'string
  :group 'thumbs)

(defcustom thumbs-per-line 5
  "*Number of thumbnails per line to show in directory."
  :type 'string
  :group 'thumbs)

(defcustom thumbs-thumbsdir-max-size 50000000
  "Max size for thumbnails directory.
When it reach that size (in bytes), a warning is send."
  :type 'string
  :group 'thumbs)

(defcustom thumbs-conversion-program
  (if (equal 'windows-nt system-type)
      "convert.exe"
    (or (executable-find "convert")
	"/usr/X11R6/bin/convert"))
  "*Name of conversion program for thumbnails generation.
It must be 'convert'."
  :type 'string
  :group 'thumbs)

(defcustom thumbs-setroot-command
  "xloadimage -onroot -fullscreen *"
  "Command to set the root window."
  :type 'string
  :group 'thumbs)

(defcustom thumbs-relief 5
  "*Size of button-like border around thumbnails."
  :type 'string
  :group 'thumbs)

(defcustom thumbs-margin 2
  "*Size of the margin around thumbnails.
This is where you see the cursor."
  :type 'string
  :group 'thumbs)

(defcustom thumbs-thumbsdir-auto-clean t
  "If set, delete older file in the thumbnails directory.
Deletion is done at load time when the directory size is bigger
than 'thumbs-thumbsdir-max-size'."
  :type 'boolean
  :group 'thumbs)

(defcustom thumbs-image-resizing-step 10
  "Step by wich to resize image."
  :type 'string
  :group 'thumbs)

(defcustom thumbs-temp-dir
  "/tmp/"
  "Temporary directory to use.
Leaving it to default '/tmp/' can let another user
see some of your images."
  :type 'directory
  :group 'thumbs)

(defcustom thumbs-temp-prefix "emacsthumbs"
  "Prefix to add to temp files."
  :type 'string
  :group 'thumbs)

;; Initialize some variable, for later use.
(defvar thumbs-temp-file
  (concat thumbs-temp-dir thumbs-temp-prefix)
  "Temporary filesname for images.")

(defvar thumbs-current-tmp-filename
  nil
  "Temporary filename of current image.")
(defvar thumbs-current-image-filename
  nil
  "Filename of current image.")
(defvar thumbs-current-image-size
  nil
  "Size of current image.")
(defvar thumbs-image-num
  nil
  "Number of current image.")
(defvar thumbs-current-dir
  nil
  "Current directory.")
(defvar thumbs-markedL
  nil
  "List of marked files.")

;; Make sure auto-image-file-mode is ON.
(auto-image-file-mode t)

;; Create the thumbs directory if it does not exists.
(setq thumbs-thumbsdir (expand-file-name thumbs-thumbsdir))

(when (not (file-directory-p thumbs-thumbsdir))
  (progn
    (make-directory thumbs-thumbsdir)
    (message "Creating thumbnails directory")))

(defvar thumbs-gensym-counter 0)

(defun thumbs-gensym (&optional arg)
  "Generate a new uninterned symbol.
The name is made by appending a number to PREFIX, default \"Thumbs\"."
  (let ((prefix (if (stringp arg) arg "Thumbs"))
	(num (if (integerp arg) arg
	       (prog1
		   thumbs-gensym-counter
		 (setq thumbs-gensym-counter (1+ thumbs-gensym-counter))))))
    (make-symbol (format "%s%d" prefix num))))

(defun thumbs-cleanup-thumbsdir ()
  "Clean the thumbnails directory.
If the total size of all files in 'thumbs-thumbsdir' is bigger than
'thumbs-thumbsdir-max-size', files are deleted until the max size is
reached."
  (let* ((filesL
	  (sort
	   (mapcar
	    (lambda (f)
	      (let ((fattribsL (file-attributes f)))
		`(,(nth 4 fattribsL) ,(nth 7 fattribsL) ,f)))
	    (directory-files thumbs-thumbsdir t (image-file-name-regexp)))
	   '(lambda (l1 l2) (time-less-p (car l1)(car l2)))))
	 (dirsize (apply '+ (mapcar (lambda (x) (cadr x)) filesL))))
    (while (> dirsize thumbs-thumbsdir-max-size)
      (progn
	(message "Deleting file %s" (cadr (cdar filesL))))
      (delete-file (cadr (cdar filesL)))
      (setq dirsize (- dirsize (car (cdar filesL))))
      (setq filesL (cdr filesL)))))

;; Check the thumbsnail directory size and clean it if necessary.
(when thumbs-thumbsdir-auto-clean
  (thumbs-cleanup-thumbsdir))

(defun thumbs-call-convert (filein fileout action
				   &optional arg output-format action-prefix)
  "Call the convert program.
FILEIN is the input file,
FILEOUT is the output file,
ACTION is the command to send to convert.
Optional argument are:
ARG any arguments to the ACTION command,
OUTPUT-FORMAT is the file format to output, default is jpeg
ACTION-PREFIX is the symbol to place before the ACTION command
              (default to '-' but can sometime be '+')."
  (let ((command (format "%s %s%s %s \"%s\" \"%s:%s\""
			 thumbs-conversion-program
			 (or action-prefix "-")
			 action
			 (or arg "")
			 filein
			 (or output-format "jpeg")
			 fileout)))
    (shell-command command)))

(defun thumbs-increment-image-size-element (n d)
  "Increment number N by D percent."
  (round (+ n (/ (* d n) 100))))

(defun thumbs-decrement-image-size-element (n d)
  "Decrement number N by D percent."
  (round (- n (/ (* d n) 100))))

(defun thumbs-increment-image-size (s)
  "Increment S (a cons of width x heigh)."
  (cons
   (thumbs-increment-image-size-element (car s)
					thumbs-image-resizing-step)
   (thumbs-increment-image-size-element (cdr s)
					thumbs-image-resizing-step)))

(defun thumbs-decrement-image-size (s)
  "Decrement S (a cons of width x heigh)."
  (cons
   (thumbs-decrement-image-size-element (car s)
					thumbs-image-resizing-step)
   (thumbs-decrement-image-size-element (cdr s)
					thumbs-image-resizing-step)))

(defun thumbs-resize-image (&optional increment size)
  "Resize image in current buffer.
if INCREMENT is set, make the image bigger, else smaller.
Or, alternatively, a SIZE may be specified."
  (interactive)
  ;; cleaning of old temp file
  (condition-case nil
    (apply 'delete-file
	   (directory-files
	    thumbs-temp-dir t
	    thumbs-temp-prefix))
    (error nil))
  (let ((buffer-read-only nil)
	(x (if size
	       size
	     (if increment
		 (thumbs-increment-image-size
		  thumbs-current-image-size)
	       (thumbs-decrement-image-size
		thumbs-current-image-size))))
	(tmp (format "%s%s.jpg" thumbs-temp-file (thumbs-gensym))))
    (erase-buffer)
    (thumbs-call-convert thumbs-current-image-filename
			 tmp "sample"
			 (concat (number-to-string (car x)) "x"
				 (number-to-string (cdr x))))
    (thumbs-insert-image tmp 'jpeg 0)
    (setq thumbs-current-tmp-filename tmp)))

(defun thumbs-resize-interactive (width height)
  "Resize Image interactively to specified WIDTH and HEIGHT."
  (interactive "nWidth: \nnHeight: ")
  (thumbs-resize-image nil (cons width height)))

(defun thumbs-resize-image-size-down ()
  "Resize image (smaller)."
  (interactive)
  (thumbs-resize-image nil))

(defun thumbs-resize-image-size-up ()
  "Resize image (bigger)."
  (interactive)
  (thumbs-resize-image t))

(defun thumbs-thumbname (img)
  "Return a thumbnail name for the image IMG."
  (concat thumbs-thumbsdir "/"
	  (subst-char-in-string
	   ?\  ?\_
	   (apply
	    'concat
	    (split-string
	     (expand-file-name img) "/")))))

(defun thumbs-make-thumb (img)
  "Create the thumbnail for IMG."
  (let* ((fn (expand-file-name img))
	 (tn (thumbs-thumbname img)))
    (if (or (not (file-exists-p tn))
	    ;;  This is not the right fix, but I don't understand
	    ;;  the external program or why it produces a geometry
	    ;;  unequal to the one requested -- rms.
;;;	    (not (equal (thumbs-file-size tn) thumbs-geometry))
	    )
	(thumbs-call-convert fn tn "sample" thumbs-geometry))
    tn))

(defun thumbs-image-type (img)
  "Return image type from filename IMG."
  (cond ((string-match ".*\\.jpe?g\\'" img) 'jpeg)
	((string-match ".*\\.xpm\\'" img) 'xpm)
	((string-match ".*\\.xbm\\'" img) 'xbm)
	((string-match ".*\\.gif\\'" img) 'gif)
	((string-match ".*\\.bmp\\'" img) 'bmp)
	((string-match ".*\\.png\\'" img) 'png)
	((string-match ".*\\.tiff?\\'" img) 'tiff)))

(defun thumbs-file-size (img)
  (let ((i (image-size (find-image `((:type ,(thumbs-image-type img) :file ,img))) t)))
    (concat (number-to-string (round (car i)))
	    "x"
	    (number-to-string (round (cdr i))))))

;;;###autoload
(defun thumbs-find-thumb (img)
  "Display the thumbnail for IMG."
  (interactive "f")
  (find-file (thumbs-make-thumb img)))

(defun thumbs-insert-image (img type relief &optional marked)
  "Insert image IMG at point.
TYPE and RELIEF will be used in constructing the image; see `image'
in the emacs-lisp manual for further documentation.
if MARKED is non-nil, the image is marked."
  (let ((i `(image :type ,type
		   :file ,img
		   :relief ,relief
		   :conversion ,(if marked 'disabled)
		   :margin ,thumbs-margin)))
    (insert-image i)
    (setq thumbs-current-image-size
	  (image-size i t))))

(defun thumbs-insert-thumb (img &optional marked)
  "Insert the thumbnail for IMG at point.
if MARKED is non-nil, the image is marked"
  (thumbs-insert-image
   (thumbs-make-thumb img) 'jpeg thumbs-relief marked)
  (put-text-property (1- (point)) (point)
		     'thumb-image-file img))

(defun thumbs-do-thumbs-insertion (L)
  "Insert all thumbs in list L."
  (let ((i 0))
    (dolist (img L)
      (thumbs-insert-thumb img
			   (member img thumbs-markedL))
      (when (= 0 (mod (setq i (1+ i)) thumbs-per-line))
	(newline)))
    (unless (bobp) (newline))))

(defun thumbs-show-thumbs-list (L &optional buffer-name same-window)
  (when (not (display-images-p))
    (error "Images are not supported in this Emacs session"))
  (funcall (if same-window 'switch-to-buffer 'pop-to-buffer)
	   (or buffer-name "*THUMB-View*"))
  (let ((inhibit-read-only t))
    (erase-buffer)
    (thumbs-mode)
    (thumbs-do-thumbs-insertion L)
    (goto-char (point-min))
    (setq thumbs-current-dir default-directory)
    (make-variable-buffer-local 'thumbs-current-dir)))

;;;###autoload
(defun thumbs-show-all-from-dir (dir &optional reg same-window)
  "Make a preview buffer for all images in DIR.
Optional argument REG to select file matching a regexp,
and SAME-WINDOW to show thumbs in the same window."
  (interactive "DDir: ")
  (thumbs-show-thumbs-list
   (directory-files dir t
		    (or reg (image-file-name-regexp)))
   (concat "*Thumbs: " dir) same-window))

;;;###autoload
(defun thumbs-dired-show-marked ()
  "In Dired, make a thumbs buffer with all marked files."
  (interactive)
  (thumbs-show-thumbs-list (dired-get-marked-files) nil t))

;;;###autoload
(defun thumbs-dired-show-all ()
  "In dired, make a thumbs buffer with all files in current directory."
  (interactive)
  (thumbs-show-all-from-dir default-directory nil t))

;;;###autoload
(defalias 'thumbs 'thumbs-show-all-from-dir)

(defun thumbs-find-image (img &optional num otherwin)
  (funcall 
   (if otherwin 'switch-to-buffer-other-window 'switch-to-buffer)
   (concat "*Image: " (file-name-nondirectory img) " - "
	   (number-to-string (or num 0)) "*"))
  (thumbs-view-image-mode)
  (let ((inhibit-read-only t))
    (setq thumbs-current-image-filename img
	  thumbs-current-tmp-filename nil
	  thumbs-image-num (or num 0))
    (make-variable-buffer-local 'thumbs-current-image-filename)
    (make-variable-buffer-local 'thumbs-current-tmp-filename)
    (make-variable-buffer-local 'thumbs-current-image-size)
    (make-variable-buffer-local 'thumbs-image-num)
    (delete-region (point-min)(point-max))
    (thumbs-insert-image img (thumbs-image-type img) 0)))

(defun thumbs-find-image-at-point (&optional img otherwin)
  "Display image IMG for thumbnail at point.
use another window it OTHERWIN is t."
  (interactive)
  (let* ((i (or img (thumbs-current-image))))
    (thumbs-find-image i (point) otherwin)))

(defun thumbs-find-image-at-point-other-window ()
  "Display image for thumbnail at point in the preview buffer.
Open another window."
  (interactive)
  (thumbs-find-image-at-point nil t))

(defun thumbs-mouse-find-image (event)
  "Display image for thumbnail at mouse click EVENT."
  (interactive "e")
  (mouse-set-point event)
  (thumbs-find-image-at-point))

(defun thumbs-call-setroot-command (img)
  "Call the setroot program for IMG."
  (run-hooks 'thumbs-before-setroot-hook)
  (shell-command (replace-regexp-in-string
		  "\\*"
		  (shell-quote-argument (expand-file-name img))
		  thumbs-setroot-command nil t))
  (run-hooks 'thumbs-after-setroot-hook))

(defun thumbs-set-image-at-point-to-root-window ()
  "Set the image at point as the desktop wallpaper."
  (interactive)
  (thumbs-call-setroot-command
   (thumbs-current-image)))

(defun thumbs-set-root ()
  "Set the current image as root."
  (interactive)
  (thumbs-call-setroot-command
   (or thumbs-current-tmp-filename
       thumbs-current-image-filename)))

(defun thumbs-file-alist ()
  "Make an alist of elements (POS . FILENAME) for all images in thumb buffer."
  (save-excursion
    (let (list)
      (goto-char (point-min))
      (while (not (eobp))
	(if (thumbs-current-image)
	    (push (cons (point-marker)
			(thumbs-current-image))
		  list))
	(forward-char 1))
      list)))

(defun thumbs-file-list ()
  "Make a list of file names for all images in thumb buffer."
  (save-excursion
    (let (list)
      (goto-char (point-min))
      (while (not (eobp))
	(if (thumbs-current-image)
	    (push (thumbs-current-image) list))
	(forward-char 1))
      (nreverse list))))

(defun thumbs-delete-images ()
  "Delete the image at point (and it's thumbnail) (or marked files if any)."
  (interactive)
  (let ((files (or thumbs-markedL (list (thumbs-current-image)))))
    (if (yes-or-no-p (format "Really delete %d files? " (length files)))
	(let ((thumbs-fileL (thumbs-file-alist))
	      (inhibit-read-only t))
	  (dolist (x files)
	    (let (failure)
	      (condition-case ()
		  (progn
		    (delete-file x)
		    (delete-file (thumbs-thumbname x)))
		(file-error (setq failure t)))
	      (unless failure
		(when (rassoc x thumbs-fileL)
		  (goto-char (car (rassoc x thumbs-fileL)))
		  (delete-region (point) (1+ (point))))
		(setq thumbs-markedL
		      (delq x thumbs-markedL)))))))))

(defun thumbs-rename-images (newfile)
  "Rename the image at point (and it's thumbnail) (or marked files if any)."
  (interactive "FRename to file or directory: ")
  (let ((files (or thumbs-markedL (list (thumbs-current-image))))
	failures)
    (if (and (not (file-directory-p newfile))
	     thumbs-markedL)
	(if (file-exists-p newfile)
	    (error "Renaming marked files to file name `%s'" newfile)
	  (make-directory newfile t)))
    (if (yes-or-no-p (format "Really rename %d files? " (length files)))
	(let ((thumbs-fileL (thumbs-file-alist))
	      (inhibit-read-only t))
	  (dolist (file files)
	    (let (failure)
	      (condition-case ()
		  (if (file-directory-p newfile)
		      (rename-file file
				   (expand-file-name
				    (file-name-nondirectory file)
				    newfile))
		    (rename-file file newfile))
		(file-error (setq failure t)
			    (push file failures)))
	      (unless failure
		(when (rassoc file thumbs-fileL)
		  (goto-char (car (rassoc file thumbs-fileL)))
		  (delete-region (point) (1+ (point))))
		(setq thumbs-markedL
		      (delq file thumbs-markedL)))))))
    (if failures
	(display-warning 'file-error
			 (format "Rename failures for %s into %s"
				 failures newfile)
			 :error))))

(defun thumbs-kill-buffer ()
  "Kill the current buffer."
  (interactive)
  (let ((buffer (current-buffer)))
    (condition-case nil
	(delete-window (selected-window))
      (error nil))
    (kill-buffer buffer)))

(defun thumbs-show-image-num (num)
  "Show the image with number NUM."
  (let ((image-buffer (get-buffer-create "*Image*")))
    (let ((i (thumbs-current-image)))
      (with-current-buffer image-buffer
	(thumbs-insert-image i (thumbs-image-type i) 0))
      (setq thumbs-image-num num
	    thumbs-current-image-filename i))))

(defun thumbs-next-image ()
  "Show next image."
  (interactive)
  (let* ((i (1+ thumbs-image-num))
	 (list (thumbs-file-alist))
	 (l (caar list)))
    (while (and (/= i thumbs-image-num) (not (assoc i list)))
      (setq i (if (>= i l) 1 (1+ i))))
    (thumbs-show-image-num i)))

(defun thumbs-previous-image ()
  "Show the previous image."
  (interactive)
  (let* ((i (- thumbs-image-num 1))
	 (list (thumbs-file-alist))
	 (l (caar list)))
    (while (and (/= i thumbs-image-num) (not (assoc i list)))
      (setq i (if (<= i 1) l (1- i))))
    (thumbs-show-image-num i)))

(defun thumbs-redraw-buffer ()
  "Redraw the current thumbs buffer."
  (let ((p (point))
	(inhibit-read-only t)
	(files (thumbs-file-list)))
    (erase-buffer)
    (thumbs-do-thumbs-insertion files)
    (goto-char p)))

(defun thumbs-mark ()
  "Mark the image at point."
  (interactive)
  (let ((elt (thumbs-current-image)))
    (unless elt
      (error "No image here"))
    (push elt thumbs-markedL)
    (let ((inhibit-read-only t))
      (delete-char 1)
      (thumbs-insert-thumb elt t)))
  (when (eolp) (forward-char)))

(defun thumbs-unmark ()
  "Unmark the image at point."
  (interactive)
  (let ((elt (thumbs-current-image)))
    (unless elt
      (error "No image here"))
    (setq thumbs-markedL (delete elt thumbs-markedL))
    (let ((inhibit-read-only t))
      (delete-char 1)
      (thumbs-insert-thumb elt nil)))
  (when (eolp) (forward-char)))

;; Image modification routines

(defun thumbs-modify-image (action &optional arg)
  "Call convert to do ACTION on image with argument ARG.
ACTION and ARG should be legal convert command."
  (interactive "sAction: \nsValue: ")
  ;; cleaning of old temp file
  (mapc 'delete-file
	(directory-files
	 thumbs-temp-dir
	 t
	 thumbs-temp-prefix))
  (let ((buffer-read-only nil)
	(tmp (format "%s%s.jpg" thumbs-temp-file (thumbs-gensym))))
    (erase-buffer)
    (thumbs-call-convert thumbs-current-image-filename
			 tmp
			 action
			 (or arg ""))
    (thumbs-insert-image tmp 'jpeg 0)
    (setq thumbs-current-tmp-filename tmp)))

(defun thumbs-emboss-image (emboss)
  "Emboss the image with value EMBOSS."
  (interactive "nEmboss value: ")
  (if (or (< emboss 3) (> emboss 31) (zerop (% emboss 2)))
      (error "Arg must be an odd number between 3 and 31"))
  (thumbs-modify-image "emboss" (number-to-string emboss)))

(defun thumbs-monochrome-image ()
  "Turn the image to monochrome."
  (interactive)
  (thumbs-modify-image "monochrome"))

(defun thumbs-negate-image ()
  "Negate the image."
  (interactive)
  (thumbs-modify-image "negate"))

(defun thumbs-rotate-left ()
  "Rotate the image 90 degrees counter-clockwise."
  (interactive)
  (thumbs-modify-image "rotate" "270"))

(defun thumbs-rotate-right ()
  "Rotate the image 90 degrees clockwise."
  (interactive)
  (thumbs-modify-image "rotate" "90"))

(defun thumbs-current-image ()
  "Return the name of the image file name at point."
  (get-text-property (point) 'thumb-image-file))

(defun thumbs-forward-char ()
  "Move forward one image."
  (interactive)
  (forward-char)
  (while (and (not (eobp)) (not (thumbs-current-image)))
    (forward-char))
  (thumbs-show-name))

(defun thumbs-backward-char ()
  "Move backward one image."
  (interactive)
  (forward-char -1)
  (while (and (not (bobp)) (not (thumbs-current-image)))
    (forward-char -1))
  (thumbs-show-name))

(defun thumbs-forward-line ()
  "Move down one line."
  (interactive)
  (forward-line 1)
  (thumbs-show-name))

(defun thumbs-backward-line ()
  "Move up one line."
  (interactive)
  (forward-line -1)
  (thumbs-show-name))

(defun thumbs-show-name ()
  "Show the name of the current file."
  (interactive)
  (let ((f (thumbs-current-image)))
    (and f (message "%s [%s]" f (thumbs-file-size f)))))

(defun thumbs-save-current-image ()
  "Save the current image."
  (interactive)
  (let ((f (or thumbs-current-tmp-filename
	       thumbs-current-image-filename))
	(sa (read-from-minibuffer "Save image file as: "
				  thumbs-current-image-filename)))
    (copy-file f sa)))

(defun thumbs-dired ()
  "Use `dired' on the current thumbs directory."
  (interactive)
  (dired thumbs-current-dir))

;; thumbs-mode

(defvar thumbs-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map [return] 'thumbs-find-image-at-point)
    (define-key map [mouse-2] 'thumbs-mouse-find-image)
    (define-key map [(meta return)] 'thumbs-find-image-at-point-other-window)
    (define-key map [(control return)] 'thumbs-set-image-at-point-to-root-window)
    (define-key map [delete] 'thumbs-delete-images)
    (define-key map [right] 'thumbs-forward-char)
    (define-key map [left] 'thumbs-backward-char)
    (define-key map [up] 'thumbs-backward-line)
    (define-key map [down] 'thumbs-forward-line)
    (define-key map "d" 'thumbs-dired)
    (define-key map "m" 'thumbs-mark)
    (define-key map "u" 'thumbs-unmark)
    (define-key map "R" 'thumbs-rename-images)
    (define-key map "x" 'thumbs-delete-images)
    (define-key map "s" 'thumbs-show-name)
    (define-key map "q" 'thumbs-kill-buffer)
    map)
  "Keymap for `thumbs-mode'.")

(put 'thumbs-mode 'mode-class 'special)
(define-derived-mode thumbs-mode
  fundamental-mode "thumbs"
  "Preview images in a thumbnails buffer"
  (make-variable-buffer-local 'thumbs-markedL)
  (setq buffer-read-only t)
  (setq thumbs-markedL nil))

(defvar thumbs-view-image-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map [prior] 'thumbs-previous-image)
    (define-key map [next] 'thumbs-next-image)
    (define-key map "-" 'thumbs-resize-image-size-down)
    (define-key map "+" 'thumbs-resize-image-size-up)
    (define-key map "<" 'thumbs-rotate-left)
    (define-key map ">" 'thumbs-rotate-right)
    (define-key map "e" 'thumbs-emboss-image)
    (define-key map "r" 'thumbs-resize-interactive)
    (define-key map "s" 'thumbs-save-current-image)
    (define-key map "q" 'thumbs-kill-buffer)
    (define-key map "w" 'thumbs-set-root)
    map)
  "Keymap for `thumbs-view-image-mode'.")

;; thumbs-view-image-mode
(put 'thumbs-view-image-mode 'mode-class 'special)
(define-derived-mode thumbs-view-image-mode
  fundamental-mode "image-view-mode"
  (setq buffer-read-only t))

;;;###autoload
(defun thumbs-dired-setroot ()
  "In dired, Call the setroot program on the image at point."
  (interactive)
  (thumbs-call-setroot-command (dired-get-filename)))

;; Modif to dired mode map
(define-key dired-mode-map "\C-ta" 'thumbs-dired-show-all)
(define-key dired-mode-map "\C-tm" 'thumbs-dired-show-marked)
(define-key dired-mode-map "\C-tw" 'thumbs-dired-setroot)

(provide 'thumbs)

;;; thumbs.el ends here


;;; arch-tag: f9ac1ef8-83fc-42c0-8069-1fae43fd2e5c
