;;; malayalam.el --- Support for Malayalam -*- coding: iso-2022-7bit; no-byte-compile: t -*-

;; Copyright (C) 2003 Free Software Foundation, Inc.

;; Maintainer:  KAWABATA, Taichi <kawabata@m17n.org>
;; Keywords: multilingual, Indian, Malayalam

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

;; This file defines language-info of Malayalam script.

;;; Code:

(set-language-info-alist
 "Malayalam" '((charset mule-unicode-0100-24ff indian-glyph )
               ;;          indian-2-column 
               ;; comment out later
               ;;          )
		(coding-system utf-8)
		(coding-priority utf-8)
		(input-method . "malayalam-itrans")
		(features mlm-util)
		(documentation . "\
South Indian language Malayalam is supported in this language environment."))
 '("Indian"))

(provide 'malayalam)

;;; malayalam.el ends here
