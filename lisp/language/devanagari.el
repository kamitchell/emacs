;;; devanagari.el --- Support for Devanagari -*- coding: iso-2022-7bit; -*-

;; Copyright (C) 1996, 2001 Free Software Foundation, Inc.

;; Maintainer:  KAWABATA, Taichi <batta@beige.ocn.ne.jp>
;; Keywords: multilingual, Indian, Devanagari

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

;; This file defines language-info of Devanagari script, and provides
;; compatibility support of old implementation of Devanagari script.

;;; Code:

(set-language-info-alist
 "Devanagari" '((charset indian-is13194 mule-unicode-0100-24ff
                         indian-2-column indian-glyph ;; comment out later
                         )
		(coding-system in-is13194-devanagari)
		(coding-priority in-is13194-devanagari)
		(input-method . "dev-aiba")
		(features devan-util)
		(documentation . "\
Such languages using Devanagari script as Hindi and Marathi
are supported in this language environment."))
 '("Indian"))

(provide 'devanagari)

;;; devanagari.el ends here
