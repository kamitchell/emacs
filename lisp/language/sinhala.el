;;; sinhala.el --- support for Sinhala -*- coding: utf-8; no-byte-compile: t -*-

;; Copyright (C) 2008, 2009
;;   National Institute of Advanced Industrial Science and Technology (AIST)
;;   Registration Number H13PRO009

;; Keywords: multilingual, Sinhala, i18n

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

;;; Code:

(set-language-info-alist
 "Sinhala" '((charset unicode)
	     (coding-system utf-8)
	     (coding-priority utf-8)
	     (sample-text . "Sinhala (සිංහල)	ආයුබෝවන්")
	     (documentation . t)))

(set-char-table-range 
 composition-function-table
 '(#xD80 . #xDFF)
 (list (vector "[\xD80-\xDFF\x200C\x200D]+" 0 'font-shape-gstring)))

;; arch-tag: 87b9ad3b-5090-422f-b942-eb85b9d52e7c
;; sinhala.el ends here
