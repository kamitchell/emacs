;;; utf-8.el --- Limited UTF-8 decoding/encoding support

;; Copyright (C) 2001 Electrotechnical Laboratory, JAPAN.
;; Licensed to the Free Software Foundation.

;; Keywords: multilingual, Unicode, UTF-8, i18n

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

;; The coding-system `mule-utf-8' supports encoding/decoding of the
;; following character sets to and from UTF-8:
;;
;;   ascii
;;   eight-bit-control
;;   latin-iso8859-1
;;   mule-unicode-0100-24ff
;;   mule-unicode-2500-33ff
;;   mule-unicode-e000-ffff
;;
;; Characters of other character sets cannot be encoded with
;; mule-utf-8.  Note that the mule-unicode charsets currently lack
;; case and syntax information, so things like `downcase' will only
;; work for characters from ASCII and Latin-1.
;;
;; On decoding, Unicode characters that do not fit into the above
;; character sets are handled as `eight-bit-control' or
;; `eight-bit-graphic' characters to retain the information about the
;; original byte sequence.

;; UTF-8 is defined in RFC 2279.  A sketch of the encoding is:

;;        scalar       |               utf-8
;;        value        | 1st byte  | 2nd byte  | 3rd byte
;; --------------------+-----------+-----------+----------
;; 0000 0000 0xxx xxxx | 0xxx xxxx |           |
;; 0000 0yyy yyxx xxxx | 110y yyyy | 10xx xxxx |
;; zzzz yyyy yyxx xxxx | 1110 zzzz | 10yy yyyy | 10xx xxxx

;;; Code:

(define-ccl-program ccl-decode-mule-utf-8
  ;;
  ;;        charset         | bytes in utf-8 | bytes in emacs
  ;; -----------------------+----------------+---------------
  ;;         ascii          |       1        |       1
  ;; -----------------------+----------------+---------------
  ;;    eight-bit-control   |       2        |       2
  ;;     latin-iso8859-1    |       2        |       2
  ;; -----------------------+----------------+---------------
  ;; mule-unicode-0100-24ff |       2        |       4
  ;;        (< 0800)        |                |
  ;; -----------------------+----------------+---------------
  ;; mule-unicode-0100-24ff |       3        |       4
  ;;        (>= 8000)       |                |
  ;; mule-unicode-2500-33ff |       3        |       4
  ;; mule-unicode-e000-ffff |       3        |       4
  ;;
  ;; Thus magnification factor is two.
  ;;
  `(2
    ((loop
      (read r0)

      ;; 1byte encoding, i.e., ascii
      (if (r0 < #x80)
	  (write r0)

	;; 2byte encoding
	(if (r0 < #xe0)
	    ((read r1)
	     (r0 &= #x1f)
	     (r0 <<= 6)
	     (r1 &= #x3f)
	     (r1 += r0)
	     ;; now r1 holds scalar value

	     ;; eight-bit-control
	     (if (r1 < 160)
		 ((r0 = ,(charset-id 'eight-bit-control))
		  (write-multibyte-character r0 r1))

	       ;; latin-iso8859-1
	       (if (r1 < 256)
		   ((r0 = ,(charset-id 'latin-iso8859-1))
		    (r1 -= 128)
		    (write-multibyte-character r0 r1))

		 ;; mule-unicode-0100-24ff (< 0800)
		 ((r0 = ,(charset-id 'mule-unicode-0100-24ff))
		  (r1 -= #x0100)
		  (r2 = (((r1 / 96) + 32) << 7))
		  (r1 %= 96)
		  (r1 += (r2 + 32))
		  (write-multibyte-character r0 r1)))))

	  ;; 3byte encoding
	  (if (r0 < #xf0)
	      ((read r1 r2)
	       (r3 = ((r0 & #x0f) << 12))
	       (r3 += ((r1 & #x3f) << 6))
	       (r3 += (r2 & #x3f))
	       ;; now r3 holds scalar value

	       ;; mule-unicode-0100-24ff (>= 0800)
	       (if (r3 < #x2500)
		   ((r0 = ,(charset-id 'mule-unicode-0100-24ff))
		    (r3 -= #x0100)
		    (r3 //= 96)
		    (r1 = (r7 + 32))
		    (r1 += ((r3 + 32) << 7))
		    (write-multibyte-character r0 r1))

		 ;; mule-unicode-2500-33ff
		 (if (r3 < #x3400)
		     ((r0 = ,(charset-id 'mule-unicode-2500-33ff))
		      (r3 -= #x2500)
		      (r3 //= 96)
		      (r1 = (r7 + 32))
		      (r1 += ((r3 + 32) << 7))
		      (write-multibyte-character r0 r1))

		   ;; U+3400 .. U+DFFF
		   ;; keep those bytes as eight-bit-{control|graphic}
		   (if (r3 < #xe000)
		       (;; #xe0 < r0 < #xf0, so r0 is eight-bit-graphic
			(r3 = ,(charset-id 'eight-bit-graphic))
			(write-multibyte-character r3 r0)
			(if (r1 < #xa0)
			    (r3 = ,(charset-id 'eight-bit-control)))
			(write-multibyte-character r3 r1)
			(if (r2 < #xa0)
			    (r3 = ,(charset-id 'eight-bit-control))
			  (r3 = ,(charset-id 'eight-bit-graphic)))
			(write-multibyte-character r3 r2))

		     ;; mule-unicode-e000-ffff
		     ((r0 = ,(charset-id 'mule-unicode-e000-ffff))
		      (r3 -= #xe000)
		      (r3 //= 96)
		      (r1 = (r7 + 32))
		      (r1 += ((r3 + 32) << 7))
		      (write-multibyte-character r0 r1))))))

	    ;; 4byte encoding
	    ;; keep those bytes as eight-bit-{control|graphic}
	    ((read r1 r2 r3)
	     ;; r0 > #xf0, thus eight-bit-graphic
	     (r4 = ,(charset-id 'eight-bit-graphic))
	     (write-multibyte-character r4 r0)
	     (if (r1 < #xa0)
		 (r4 = ,(charset-id 'eight-bit-control)))
	     (write-multibyte-character r4 r1)
	     (if (r2 < #xa0)
		 (r4 = ,(charset-id 'eight-bit-control))
	       (r4 = ,(charset-id 'eight-bit-graphic)))
	     (write-multibyte-character r4 r2)
	     (if (r3 < #xa0)
		 (r4 = ,(charset-id 'eight-bit-control))
	       (r4 = ,(charset-id 'eight-bit-graphic)))
	     (write-multibyte-character r4 r3)))))

      (repeat))))

  "CCL program to decode UTF-8.
Decoding is done into the charsets ascii, eight-bit-control,
latin-iso8859-1 and mule-unicode-* only.")

(define-ccl-program ccl-encode-mule-utf-8
  `(1
    (loop
     (read-multibyte-character r0 r1)

     (translate-character ucs-mule-8859-to-mule-unicode r0 r1)

     (if (r0 == ,(charset-id 'ascii))
	 (write r1)

       (if (r0 == ,(charset-id 'latin-iso8859-1))
	   ;; r1          scalar                  utf-8
	   ;;       0000 0yyy yyxx xxxx    110y yyyy 10xx xxxx
	   ;; 20    0000 0000 1010 0000    1100 0010 1010 0000
	   ;; 7f    0000 0000 1111 1111    1100 0011 1011 1111
	   ((r0 = (((r1 & #x40) >> 6) | #xc2))
	    (r1 &= #x3f)
	    (r1 |= #x80)
	    (write r0 r1))

	 (if (r0 == ,(charset-id 'mule-unicode-0100-24ff))
	     ((r0 = ((((r1 & #x3f80) >> 7) - 32) * 96))
	      ;; #x3f80 == (0011 1111 1000 0000)b
	      (r1 &= #x7f)
	      (r1 += (r0 + 224))	; 240 == -32 + #x0100
	      ;; now r1 holds scalar value
	      (if (r1 < #x0800)
		  ;; 2byte encoding
		  ((r0 = (((r1 & #x07c0) >> 6) | #xc0))
		   ;; #x07c0 == (0000 0111 1100 0000)b
		   (r1 &= #x3f)
		   (r1 |= #x80)
		   (write r0 r1))
		;; 3byte encoding
		((r0 = (((r1 & #xf000) >> 12) | #xe0))
		 (r2 = ((r1 & #x3f) | #x80))
		 (r1 &= #x0fc0)
		 (r1 >>= 6)
		 (r1 |= #x80)
		 (write r0 r1 r2))))

	   (if (r0 == ,(charset-id 'mule-unicode-2500-33ff))
	       ((r0 = ((((r1 & #x3f80) >> 7) - 32) * 96))
		(r1 &= #x7f)
		(r1 += (r0 + 9440))	; 9440 == -32 + #x2500
		(r0 = (((r1 & #xf000) >> 12) | #xe0))
		(r2 = ((r1 & #x3f) | #x80))
		(r1 &= #x0fc0)
		(r1 >>= 6)
		(r1 |= #x80)
		(write r0 r1 r2))

	     (if (r0 == ,(charset-id 'mule-unicode-e000-ffff))
		 ((r0 = ((((r1 & #x3f80) >> 7) - 32) * 96))
		  (r1 &= #x7f)
		  (r1 += (r0 + 57312))	; 57312 == -160 + #xe000
		  (r0 = (((r1 & #xf000) >> 12) | #xe0))
		  (r2 = ((r1 & #x3f) | #x80))
		  (r1 &= #x0fc0)
		  (r1 >>= 6)
		  (r1 |= #x80)
		  (write r0 r1 r2))

	       (if (r0 == ,(charset-id 'eight-bit-control))
		   ;; r1          scalar                  utf-8
		   ;;       0000 0yyy yyxx xxxx    110y yyyy 10xx xxxx
		   ;; 80    0000 0000 1000 0000    1100 0010 1000 0000
		   ;; 9f    0000 0000 1001 1111    1100 0010 1001 1111
		   (write r1)

		 (if (r0 == ,(charset-id 'eight-bit-graphic))
		     ;; r1          scalar                  utf-8
		     ;;       0000 0yyy yyxx xxxx    110y yyyy 10xx xxxx
		     ;; a0    0000 0000 1010 0000    1100 0010 1010 0000
		     ;; ff    0000 0000 1111 1111    1101 1111 1011 1111
		     (write r1)

		   ;; Unsupported character.
		   ;; Output U+FFFD, which is `ef bf bd' in UTF-8.
		   ((write #xef)
		    (write #xbf)
		    (write #xbd)))))))))
     (repeat)))

  "CCL program to encode into UTF-8.
Only characters from the charsets ascii, eight-bit-control,
latin-iso8859-1 and mule-unicode-* are recognized.  Others are encoded
as U+FFFD.")

;; Dummy definition needed by the CCL program.  The real data are
;; loaded on demand.
(define-translation-table 'ucs-mule-8859-to-mule-unicode)

(make-coding-system
 'mule-utf-8 4 ?u
 "UTF-8 encoding for Emacs-supported Unicode characters.
The supported Emacs character sets are:
   ascii
   eight-bit-control
   eight-bit-graphic
   latin-iso8859-1
   mule-unicode-0100-24ff
   mule-unicode-2500-33ff
   mule-unicode-e000-ffff

Unicode characters out of the ranges U+0000-U+33FF and U+E200-U+FFFF
are decoded into sequences of eight-bit-control and eight-bit-graphic
characters to preserve their byte sequences.  Emacs characters out of
these ranges are encoded into U+FFFD.

Note that, currently, characters in the mule-unicode charsets have no
syntax and case information.  Thus, for instance, upper- and
lower-casing commands won't work with them."

 '(ccl-decode-mule-utf-8 . ccl-encode-mule-utf-8)
 '((safe-charsets
    ascii
    eight-bit-control
    eight-bit-graphic
    latin-iso8859-1
    latin-iso8859-15
    latin-iso8859-14
    latin-iso8859-9
    hebrew-iso8859-8
    greek-iso8859-7
    cyrillic-iso8859-5
    latin-iso8859-4
    latin-iso8859-3
    latin-iso8859-2
    mule-unicode-0100-24ff
    mule-unicode-2500-33ff
    mule-unicode-e000-ffff)
   (mime-charset . utf-8)
   (valid-codes (0 . 255))
   ;; Kluge to get the real translation table loaded.
   (pre-write-conversion . internal-require-ucs-tables)))

(defun internal-require-ucs-tables (from to)
  (require 'ucs-tables)
  nil)

(define-coding-system-alias 'utf-8 'mule-utf-8)
