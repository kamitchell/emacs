;;; bibtex.el --- BibTeX mode for GNU Emacs

;; Copyright (C) 1992,94,95,96,97,98,1999,2003  Free Software Foundation, Inc.

;; Author: Stefan Schoef <schoef@offis.uni-oldenburg.de>
;;      Bengt Martensson <bengt@mathematik.uni-Bremen.de>
;;      Mark Shapiro <shapiro@corto.inria.fr>
;;      Mike Newton <newton@gumby.cs.caltech.edu>
;;      Aaron Larson <alarson@src.honeywell.com>
;;      Dirk Herrmann <D.Herrmann@tu-bs.de>
;; Maintainer: Roland Winkler <roland.winkler@physik.uni-erlangen.de>
;; Keywords: BibTeX, LaTeX, TeX

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

;;  Major mode for editing and validating BibTeX files.

;;  Usage:
;;  See documentation for function bibtex-mode (or type "\M-x describe-mode"
;;  when you are in BibTeX mode).

;;  Todo:
;;  Distribute texinfo file.

;;; Code:


;; User Options:

(defgroup bibtex nil
  "BibTeX mode"
  :group 'tex
  :prefix "bibtex-")

(defgroup bibtex-autokey nil
  "Generate automatically a key from the author/editor and the title field"
  :group 'bibtex
  :prefix "bibtex-autokey-")

(defcustom bibtex-mode-hook nil
  "List of functions to call on entry to BibTeX mode."
  :group 'bibtex
  :type 'hook)

(defcustom bibtex-field-delimiters 'braces
  "*Type of field delimiters. Allowed values are `braces' or `double-quotes'."
  :group 'bibtex
  :type '(choice (const braces)
                 (const double-quotes)))

(defcustom bibtex-entry-delimiters 'braces
  "*Type of entry delimiters. Allowed values are `braces' or `parentheses'."
  :group 'bibtex
  :type '(choice (const braces)
                 (const parentheses)))

(defcustom bibtex-include-OPTcrossref '("InProceedings" "InCollection")
  "*List of entries that get an OPTcrossref field."
  :group 'bibtex
  :type '(repeat string))

(defcustom bibtex-include-OPTkey t
  "*If non-nil, all entries will have an OPTkey field.
If this is a string, it will be used as the initial field text.
If this is a function, it will be called to generate the initial field text."
  :group 'bibtex
  :type '(choice (const :tag "None" nil)
                 (string :tag "Initial text")
                 (function :tag "Initialize Function" :value fun)
                 (other :tag "Default" t)))

(defcustom bibtex-user-optional-fields
  '(("annote" "Personal annotation (ignored)"))
  "*List of optional fields the user wants to have always present.
Entries should be of the same form as the OPTIONAL and
CROSSREF-OPTIONAL lists in `bibtex-entry-field-alist' (see documentation
of this variable for details)."
  :group 'bibtex
  :type '(repeat (group (string :tag "Field")
                        (string :tag "Comment")
                        (option (group :inline t
                                       :extra-offset -4
                                       (choice :tag "Init" :value ""
                                               string
                                               function))))))

(defcustom bibtex-entry-format
  '(opts-or-alts required-fields numerical-fields)
  "*Type of formatting performed by `bibtex-clean-entry'.
It may be t, nil, or a list of symbols out of the following:
opts-or-alts        Delete empty optional and alternative fields and
                      remove OPT and ALT prefixes from used fields.
required-fields     Signal an error if a required field is missing.
numerical-fields    Delete delimiters around numeral fields.
page-dashes         Change double dashes in page field to single dash
                      (for scribe compatibility).
inherit-booktitle   If entry contains a crossref field and booktitle
                      field is empty, it is set to the contents of the
                      title field of the crossreferenced entry.
                      Caution: this will work only if buffer is
                       correctly sorted.
realign             Realign entries, so that field texts and perhaps equal
                      signs (depending on the value of
                      `bibtex-align-at-equal-sign') begin in the same column.
last-comma          Add or delete comma on end of last field in entry,
                      according to value of `bibtex-comma-after-last-field'.
delimiters          Change delimiters according to variables
                      `bibtex-field-delimiters' and `bibtex-entry-delimiters'.
unify-case          Change case of entry and field names.

The value t means do all of the above formatting actions.
The value nil means do no formatting at all."
  :group 'bibtex
  :type '(choice (const :tag "None" nil)
                 (const :tag "All" t)
                 (set :menu-tag "Some"
                      (const opts-or-alts)
                      (const required-fields)
                      (const numerical-fields)
                      (const page-dashes)
                      (const inherit-booktitle)
                      (const realign)
                      (const last-comma)
                      (const delimiters)
                      (const unify-case))))

(defcustom bibtex-clean-entry-hook nil
  "*List of functions to call when entry has been cleaned.
Functions are called with point inside the cleaned entry, and the buffer
narrowed to just the entry."
  :group 'bibtex
  :type 'hook)

(defcustom bibtex-maintain-sorted-entries nil
  "*If non-nil, BibTeX mode maintains all BibTeX entries in sorted order.
Allowed non-nil values are:
plain        All entries are sorted alphabetically.
crossref     All entries are sorted alphabetically unless an entry has a
             crossref field. These crossrefed entries are placed in
             alphabetical order immediately preceding the main entry.
entry-class  The entries are divided into classes according to their
             entry name, see `bibtex-sort-entry-class'. Within each class
             the entries are sorted alphabetically.
See also `bibtex-sort-ignore-string-entries'."
  :group 'bibtex
  :type '(choice (const nil)
                 (const plain)
                 (const crossref)
                 (const entry-class)))

(defvar bibtex-sort-entry-class
  '(("String")
    (catch-all)
    ("Book" "Proceedings"))
  "*List of classes of BibTeX entry names, used for sorting entries.
If value of `bibtex-maintain-sorted-entries' is `entry-class'
entries are ordered according to the classes they belong to. Each
class contains a list of entry names. An entry `catch-all' applies
to all entries not explicitely mentioned.")

(defcustom bibtex-sort-ignore-string-entries t
  "*If non-nil, BibTeX @String entries are not sort-significant.
That means they are ignored when determining ordering of the buffer
\(e.g., sorting, locating alphabetical position for new entries, etc.)."
  :group 'bibtex
  :type 'boolean)

(defcustom bibtex-field-kill-ring-max 20
  "*Max length of `bibtex-field-kill-ring' before discarding oldest elements."
  :group 'bibtex
  :type 'integer)

(defcustom bibtex-entry-kill-ring-max 20
  "*Max length of `bibtex-entry-kill-ring' before discarding oldest elements."
  :group 'bibtex
  :type 'integer)

(defcustom bibtex-parse-keys-timeout 60
  "*Specify interval for parsing BibTeX buffers.
All BibTeX buffers in Emacs are parsed if Emacs has been idle
`bibtex-parse-keys-timeout' seconds.  Only buffers which were modified
after last parsing and which are maintained in sorted order are parsed."
  :group 'bibtex
  :type 'integer)

(defcustom bibtex-parse-keys-fast t
  "*If non-nil, use fast but simplified algorithm for parsing BibTeX keys.
If parsing fails, try to set this variable to nil."
  :group 'bibtex
  :type 'boolean)

(defvar bibtex-entry-field-alist
  '(
    ("Article"
     ((("author" "Author1 [and Author2 ...] [and others]")
       ("title" "Title of the article (BibTeX converts it to lowercase)")
       ("journal" "Name of the journal (use string, remove braces)")
       ("year" "Year of publication"))
      (("volume" "Volume of the journal")
       ("number" "Number of the journal (only allowed if entry contains volume)")
       ("pages" "Pages in the journal")
       ("month" "Month of the publication as a string (remove braces)")
       ("note" "Remarks to be put at the end of the \\bibitem")))
     ((("author" "Author1 [and Author2 ...] [and others]")
       ("title" "Title of the article (BibTeX converts it to lowercase)"))
      (("pages" "Pages in the journal")
       ("journal" "Name of the journal (use string, remove braces)")
       ("year" "Year of publication")
       ("volume" "Volume of the journal")
       ("number" "Number of the journal")
       ("month" "Month of the publication as a string (remove braces)")
       ("note" "Remarks to be put at the end of the \\bibitem"))))
    ("Book"
     ((("author" "Author1 [and Author2 ...] [and others]" "" t)
       ("editor" "Editor1 [and Editor2 ...] [and others]" "" t)
       ("title" "Title of the book")
       ("publisher" "Publishing company")
       ("year" "Year of publication"))
      (("volume" "Volume of the book in the series")
       ("number" "Number of the book in a small series (overwritten by volume)")
       ("series" "Series in which the book appeared")
       ("address" "Address of the publisher")
       ("edition" "Edition of the book as a capitalized English word")
       ("month" "Month of the publication as a string (remove braces)")
       ("note" "Remarks to be put at the end of the \\bibitem")))
     ((("author" "Author1 [and Author2 ...] [and others]" "" t)
       ("editor" "Editor1 [and Editor2 ...] [and others]" "" t)
       ("title" "Title of the book"))
      (("publisher" "Publishing company")
       ("year" "Year of publication")
       ("volume" "Volume of the book in the series")
       ("number" "Number of the book in a small series (overwritten by volume)")
       ("series" "Series in which the book appeared")
       ("address" "Address of the publisher")
       ("edition" "Edition of the book as a capitalized English word")
       ("month" "Month of the publication as a string (remove braces)")
       ("note" "Remarks to be put at the end of the \\bibitem"))))
    ("Booklet"
     ((("title" "Title of the booklet (BibTeX converts it to lowercase)"))
      (("author" "Author1 [and Author2 ...] [and others]")
       ("howpublished" "The way in which the booklet was published")
       ("address" "Address of the publisher")
       ("month" "Month of the publication as a string (remove braces)")
       ("year" "Year of publication")
       ("note" "Remarks to be put at the end of the \\bibitem"))))
    ("InBook"
     ((("author" "Author1 [and Author2 ...] [and others]" "" t)
       ("editor" "Editor1 [and Editor2 ...] [and others]" "" t)
       ("title" "Title of the book")
       ("chapter" "Chapter in the book")
       ("publisher" "Publishing company")
       ("year" "Year of publication"))
      (("volume" "Volume of the book in the series")
       ("number" "Number of the book in a small series (overwritten by volume)")
       ("series" "Series in which the book appeared")
       ("type" "Word to use instead of \"chapter\"")
       ("address" "Address of the publisher")
       ("edition" "Edition of the book as a capitalized English word")
       ("month" "Month of the publication as a string (remove braces)")
       ("pages" "Pages in the book")
       ("note" "Remarks to be put at the end of the \\bibitem")))
     ((("author" "Author1 [and Author2 ...] [and others]" "" t)
       ("editor" "Editor1 [and Editor2 ...] [and others]" "" t)
       ("title" "Title of the book")
       ("chapter" "Chapter in the book"))
      (("pages" "Pages in the book")
       ("publisher" "Publishing company")
       ("year" "Year of publication")
       ("volume" "Volume of the book in the series")
       ("number" "Number of the book in a small series (overwritten by volume)")
       ("series" "Series in which the book appeared")
       ("type" "Word to use instead of \"chapter\"")
       ("address" "Address of the publisher")
       ("edition" "Edition of the book as a capitalized English word")
       ("month" "Month of the publication as a string (remove braces)")
       ("note" "Remarks to be put at the end of the \\bibitem"))))
    ("InCollection"
     ((("author" "Author1 [and Author2 ...] [and others]")
       ("title" "Title of the article in book (BibTeX converts it to lowercase)")
       ("booktitle" "Name of the book")
       ("publisher" "Publishing company")
       ("year" "Year of publication"))
      (("editor" "Editor1 [and Editor2 ...] [and others]")
       ("volume" "Volume of the book in the series")
       ("number" "Number of the book in a small series (overwritten by volume)")
       ("series" "Series in which the book appeared")
       ("type" "Word to use instead of \"chapter\"")
       ("chapter" "Chapter in the book")
       ("pages" "Pages in the book")
       ("address" "Address of the publisher")
       ("edition" "Edition of the book as a capitalized English word")
       ("month" "Month of the publication as a string (remove braces)")
       ("note" "Remarks to be put at the end of the \\bibitem")))
     ((("author" "Author1 [and Author2 ...] [and others]")
       ("title" "Title of the article in book (BibTeX converts it to lowercase)")
       ("booktitle" "Name of the book"))
      (("pages" "Pages in the book")
       ("publisher" "Publishing company")
       ("year" "Year of publication")
       ("editor" "Editor1 [and Editor2 ...] [and others]")
       ("volume" "Volume of the book in the series")
       ("number" "Number of the book in a small series (overwritten by volume)")
       ("series" "Series in which the book appeared")
       ("type" "Word to use instead of \"chapter\"")
       ("chapter" "Chapter in the book")
       ("address" "Address of the publisher")
       ("edition" "Edition of the book as a capitalized English word")
       ("month" "Month of the publication as a string (remove braces)")
       ("note" "Remarks to be put at the end of the \\bibitem"))))
    ("InProceedings"
     ((("author" "Author1 [and Author2 ...] [and others]")
       ("title" "Title of the article in proceedings (BibTeX converts it to lowercase)")
       ("booktitle" "Name of the conference proceedings")
       ("year" "Year of publication"))
      (("editor" "Editor1 [and Editor2 ...] [and others]")
       ("volume" "Volume of the conference proceedings in the series")
       ("number" "Number of the conference proceedings in a small series (overwritten by volume)")
       ("series" "Series in which the conference proceedings appeared")
       ("pages" "Pages in the conference proceedings")
       ("address" "Location of the Proceedings")
       ("month" "Month of the publication as a string (remove braces)")
       ("organization" "Sponsoring organization of the conference")
       ("publisher" "Publishing company, its location")
       ("note" "Remarks to be put at the end of the \\bibitem")))
     ((("author" "Author1 [and Author2 ...] [and others]")
       ("title" "Title of the article in proceedings (BibTeX converts it to lowercase)"))
      (("booktitle" "Name of the conference proceedings")
       ("pages" "Pages in the conference proceedings")
       ("year" "Year of publication")
       ("editor" "Editor1 [and Editor2 ...] [and others]")
       ("volume" "Volume of the conference proceedings in the series")
       ("number" "Number of the conference proceedings in a small series (overwritten by volume)")
       ("series" "Series in which the conference proceedings appeared")
       ("address" "Location of the Proceedings")
       ("month" "Month of the publication as a string (remove braces)")
       ("organization" "Sponsoring organization of the conference")
       ("publisher" "Publishing company, its location")
       ("note" "Remarks to be put at the end of the \\bibitem"))))
    ("Manual"
     ((("title" "Title of the manual"))
      (("author" "Author1 [and Author2 ...] [and others]")
       ("organization" "Publishing organization of the manual")
       ("address" "Address of the organization")
       ("edition" "Edition of the manual as a capitalized English word")
       ("month" "Month of the publication as a string (remove braces)")
       ("year" "Year of publication")
       ("note" "Remarks to be put at the end of the \\bibitem"))))
    ("MastersThesis"
     ((("author" "Author1 [and Author2 ...] [and others]")
       ("title" "Title of the master\'s thesis (BibTeX converts it to lowercase)")
       ("school" "School where the master\'s thesis was written")
       ("year" "Year of publication"))
      (("type" "Type of the master\'s thesis (if other than \"Master\'s thesis\")")
       ("address" "Address of the school (if not part of field \"school\") or country")
       ("month" "Month of the publication as a string (remove braces)")
       ("note" "Remarks to be put at the end of the \\bibitem"))))
    ("Misc"
     (()
      (("author" "Author1 [and Author2 ...] [and others]")
       ("title" "Title of the work (BibTeX converts it to lowercase)")
       ("howpublished" "The way in which the work was published")
       ("month" "Month of the publication as a string (remove braces)")
       ("year" "Year of publication")
       ("note" "Remarks to be put at the end of the \\bibitem"))))
    ("PhdThesis"
     ((("author" "Author1 [and Author2 ...] [and others]")
       ("title" "Title of the PhD. thesis")
       ("school" "School where the PhD. thesis was written")
       ("year" "Year of publication"))
      (("type" "Type of the PhD. thesis")
       ("address" "Address of the school (if not part of field \"school\") or country")
       ("month" "Month of the publication as a string (remove braces)")
       ("note" "Remarks to be put at the end of the \\bibitem"))))
    ("Proceedings"
     ((("title" "Title of the conference proceedings")
       ("year" "Year of publication"))
      (("booktitle" "Title of the proceedings for cross references")
       ("editor" "Editor1 [and Editor2 ...] [and others]")
       ("volume" "Volume of the conference proceedings in the series")
       ("number" "Number of the conference proceedings in a small series (overwritten by volume)")
       ("series" "Series in which the conference proceedings appeared")
       ("address" "Location of the Proceedings")
       ("month" "Month of the publication as a string (remove braces)")
       ("organization" "Sponsoring organization of the conference")
       ("publisher" "Publishing company, its location")
       ("note" "Remarks to be put at the end of the \\bibitem"))))
    ("TechReport"
     ((("author" "Author1 [and Author2 ...] [and others]")
       ("title" "Title of the technical report (BibTeX converts it to lowercase)")
       ("institution" "Sponsoring institution of the report")
       ("year" "Year of publication"))
      (("type" "Type of the report (if other than \"technical report\")")
       ("number" "Number of the technical report")
       ("address" "Address of the institution (if not part of field \"institution\") or country")
       ("month" "Month of the publication as a string (remove braces)")
       ("note" "Remarks to be put at the end of the \\bibitem"))))
    ("Unpublished"
     ((("author" "Author1 [and Author2 ...] [and others]")
       ("title" "Title of the unpublished work (BibTeX converts it to lowercase)")
       ("note" "Remarks to be put at the end of the \\bibitem"))
      (("month" "Month of the publication as a string (remove braces)")
       ("year" "Year of publication"))))
    )

  "Defines entry types and their associated fields.
List of
\(ENTRY-NAME (REQUIRED OPTIONAL) (CROSSREF-REQUIRED CROSSREF-OPTIONAL))
triples.
If the third element is nil, the first pair is always used.
If not, the second pair is used in the case of presence of a crossref
field and the third in the case of absence.
REQUIRED, OPTIONAL, CROSSREF-REQUIRED and CROSSREF-OPTIONAL are lists.
Each element of these lists is a list of the form
\(FIELD-NAME COMMENT-STRING INIT ALTERNATIVE-FLAG).
COMMENT-STRING, INIT, and ALTERNATIVE-FLAG are optional.
FIELD-NAME is the name of the field, COMMENT-STRING the comment to
appear in the echo area, INIT is either the initial content of the
field or a function, which is called to determine the initial content
of the field, and ALTERNATIVE-FLAG (either nil or t) marks if the
field is an alternative.  ALTERNATIVE-FLAG may be t only in the
REQUIRED or CROSSREF-REQUIRED lists.")

(defvar bibtex-comment-start "@Comment"
  "String starting a BibTeX comment.")

(defcustom bibtex-add-entry-hook nil
  "List of functions to call when entry has been inserted."
  :group 'bibtex
  :type 'hook)

(defcustom bibtex-predefined-month-strings
  '(("jan" . "January")
    ("feb" . "February")
    ("mar" . "March")
    ("apr" . "April")
    ("may" . "May")
    ("jun" . "June")
    ("jul" . "July")
    ("aug" . "August")
    ("sep" . "September")
    ("oct" . "October")
    ("nov" . "November")
    ("dec" . "December"))
  "Alist of month string definitions used in the BibTeX style files.
Each element is a pair of strings (ABBREVIATION . EXPANSION)."
  :group 'bibtex
  :type '(repeat (cons (string :tag "Month abbreviation")
                       (string :tag "Month expansion"))))

(defcustom bibtex-predefined-strings
  (append
   bibtex-predefined-month-strings
   '(("acmcs"    . "ACM Computing Surveys")
     ("acta"     . "Acta Informatica")
     ("cacm"     . "Communications of the ACM")
     ("ibmjrd"   . "IBM Journal of Research and Development")
     ("ibmsj"    . "IBM Systems Journal")
     ("ieeese"   . "IEEE Transactions on Software Engineering")
     ("ieeetc"   . "IEEE Transactions on Computers")
     ("ieeetcad" . "IEEE Transactions on Computer-Aided Design of Integrated Circuits")
     ("ipl"      . "Information Processing Letters")
     ("jacm"     . "Journal of the ACM")
     ("jcss"     . "Journal of Computer and System Sciences")
     ("scp"      . "Science of Computer Programming")
     ("sicomp"   . "SIAM Journal on Computing")
     ("tcs"      . "Theoretical Computer Science")
     ("tocs"     . "ACM Transactions on Computer Systems")
     ("tods"     . "ACM Transactions on Database Systems")
     ("tog"      . "ACM Transactions on Graphics")
     ("toms"     . "ACM Transactions on Mathematical Software")
     ("toois"    . "ACM Transactions on Office Information Systems")
     ("toplas"   . "ACM Transactions on Programming Languages and Systems")))
  "Alist of string definitions used in the BibTeX style files.
Each element is a pair of strings (ABBREVIATION . EXPANSION)."
  :group 'bibtex
  :type '(repeat (cons (string :tag "String")
                       (string :tag "String expansion"))))

(defcustom bibtex-string-files nil
  "*List of BibTeX files containing string definitions.
Those files must be specified using pathnames relative to the
directories specified in `bibtex-string-file-path'."
  :group 'bibtex
  :type '(repeat file))

(defvar bibtex-string-file-path (getenv "BIBINPUTS")
  "*Colon separated list of paths to search for `bibtex-string-files'.")

(defcustom bibtex-help-message t
  "*If non-nil print help messages in the echo area on entering a new field."
  :group 'bibtex
  :type 'boolean)

(defcustom bibtex-autokey-prefix-string ""
  "*String to use as a prefix for all generated keys.
See `bibtex-generate-autokey' for details."
  :group 'bibtex-autokey
  :type 'string)

(defcustom bibtex-autokey-names 1
  "*Number of names to use for the automatically generated reference key.
Possibly more names are used according to `bibtex-autokey-names-stretch'.
If this variable is nil, all names are used.
See `bibtex-generate-autokey' for details."
  :group 'bibtex-autokey
  :type '(choice (const :tag "All" infty)
                 integer))

(defcustom bibtex-autokey-names-stretch 0
  "*Number of names that can additionally be used.
These names are used only, if all names are used then.
See `bibtex-generate-autokey' for details."
  :group 'bibtex-autokey
  :type 'integer)

(defcustom bibtex-autokey-additional-names ""
  "*String to prepend to the generated key if not all names could be used.
See `bibtex-generate-autokey' for details."
  :group 'bibtex-autokey
  :type 'string)

(defvar bibtex-autokey-transcriptions
  '(;; language specific characters
    ("\\\\aa" . "a")                      ; \aa           -> a
    ("\\\\AA" . "A")                      ; \AA           -> A
    ("\\\"a\\|\\\\\\\"a\\|\\\\ae" . "ae") ; "a,\"a,\ae    -> ae
    ("\\\"A\\|\\\\\\\"A\\|\\\\AE" . "Ae") ; "A,\"A,\AE    -> Ae
    ("\\\\i" . "i")                       ; \i            -> i
    ("\\\\j" . "j")                       ; \j            -> j
    ("\\\\l" . "l")                       ; \l            -> l
    ("\\\\L" . "L")                       ; \L            -> L
    ("\\\"o\\|\\\\\\\"o\\|\\\\o\\|\\\\oe" . "oe") ; "o,\"o,\o,\oe -> oe
    ("\\\"O\\|\\\\\\\"O\\|\\\\O\\|\\\\OE" . "Oe") ; "O,\"O,\O,\OE -> Oe
    ("\\\"s\\|\\\\\\\"s\\|\\\\3" . "ss")  ; "s,\"s,\3     -> ss
    ("\\\"u\\|\\\\\\\"u" . "ue")          ; "u,\"u        -> ue
    ("\\\"U\\|\\\\\\\"U" . "Ue")          ; "U,\"U        -> Ue
    ;; accents
    ("\\\\`\\|\\\\'\\|\\\\\\^\\|\\\\~\\|\\\\=\\|\\\\\\.\\|\\\\u\\|\\\\v\\|\\\\H\\|\\\\t\\|\\\\c\\|\\\\d\\|\\\\b" . "")
    ;; braces, quotes, concatenation.
    ("[`'\"{}#]" . "")
    ;; spaces
    ("[ \t\n]+" . " "))
  "Alist of (OLD-REGEXP . NEW-STRING) pairs.
Used by the default values of `bibtex-autokey-name-change-strings' and
`bibtex-autokey-titleword-change-strings'.  Defaults to translating some
language specific characters to their ASCII transcriptions, and
removing any character accents.")

(defcustom bibtex-autokey-name-change-strings
  bibtex-autokey-transcriptions
  "Alist of (OLD-REGEXP . NEW-STRING) pairs.
Any part of name matching a OLD-REGEXP is replaced by NEW-STRING.
Case is significant in OLD-REGEXP.  All regexps are tried in the
order in which they appear in the list.
See `bibtex-generate-autokey' for details."
  :group 'bibtex-autokey
  :type '(repeat (cons (regexp :tag "Old")
                       (string :tag "New"))))

(defcustom bibtex-autokey-name-case-convert 'downcase
  "*Function called for each name to perform case conversion.
See `bibtex-generate-autokey' for details."
  :group 'bibtex-autokey
  :type '(choice (const :tag "Preserve case" identity)
                 (const :tag "Downcase" downcase)
                 (const :tag "Capitalize" capitalize)
                 (const :tag "Upcase" upcase)
                 (function :tag "Conversion function")))

(defcustom bibtex-autokey-name-length 'infty
  "*Number of characters from name to incorporate into key.
If this is set to anything but a number, all characters are used.
See `bibtex-generate-autokey' for details."
  :group 'bibtex-autokey
  :type '(choice (const :tag "All" infty)
                 integer))

(defcustom bibtex-autokey-name-separator ""
  "*String that comes between any two names in the key.
See `bibtex-generate-autokey' for details."
  :group 'bibtex-autokey
  :type 'string)

(defcustom bibtex-autokey-year-length 2
  "*Number of rightmost digits from the year field to incorporate into key.
See `bibtex-generate-autokey' for details."
  :group 'bibtex-autokey
  :type 'integer)

(defcustom bibtex-autokey-use-crossref t
  "*If non-nil use fields from crossreferenced entry if necessary.
If this variable is non-nil and some field has no entry, but a
valid crossref entry, the field from the crossreferenced entry is used.
See `bibtex-generate-autokey' for details."
  :group 'bibtex-autokey
  :type 'boolean)

(defcustom bibtex-autokey-titlewords 5
  "*Number of title words to use for the automatically generated reference key.
If this is set to anything but a number, all title words are used.
Possibly more words from the title are used according to
`bibtex-autokey-titlewords-stretch'.
See `bibtex-generate-autokey' for details."
  :group 'bibtex-autokey
  :type '(choice (const :tag "All" infty)
                 integer))

(defcustom bibtex-autokey-title-terminators
  '("\\." "!"  "\\?" ":" ";" "--")
  "*Regexp list defining the termination of the main part of the title.
Case of the regexps is ignored.
See `bibtex-generate-autokey' for details."
  :group 'bibtex-autokey
  :type '(repeat regexp))

(defcustom bibtex-autokey-titlewords-stretch 2
  "*Number of words that can additionally be used from the title.
These words are used only, if a sentence from the title can be ended then.
See `bibtex-generate-autokey' for details."
  :group 'bibtex-autokey
  :type 'integer)

(defcustom bibtex-autokey-titleword-ignore
  '("A" "An" "On" "The" "Eine?" "Der" "Die" "Das"
    "[^A-Z].*" ".*[^a-zA-Z0-9].*")
  "*Determines words from the title that are not to be used in the key.
Each item of the list is a regexp.  If a word of the title matchs a
regexp from that list, it is not included in the title part of the key.
See `bibtex-generate-autokey' for details."
  :group 'bibtex-autokey
  :type '(repeat regexp))

(defcustom bibtex-autokey-titleword-case-convert 'downcase
  "*Function called for each titleword to perform case conversion.
See `bibtex-generate-autokey' for details."
  :group 'bibtex-autokey
  :type '(choice (const :tag "Preserve case" identity)
                 (const :tag "Downcase" downcase)
                 (const :tag "Capitalize" capitalize)
                 (const :tag "Upcase" upcase)
                 (function :tag "Conversion function")))

(defcustom bibtex-autokey-titleword-abbrevs nil
  "*Determines exceptions to the usual abbreviation mechanism.
An alist of (OLD-REGEXP . NEW-STRING) pairs.  Case is ignored
in matching against OLD-REGEXP, and the first matching pair is used.
See `bibtex-generate-autokey' for details."
  :group 'bibtex-autokey
  :type '(repeat (cons (regexp :tag "Old")
                       (string :tag "New"))))

(defcustom bibtex-autokey-titleword-change-strings
  bibtex-autokey-transcriptions
  "Alist of (OLD-REGEXP . NEW-STRING) pairs.
Any part of title word matching a OLD-REGEXP is replaced by NEW-STRING.
Case is significant in OLD-REGEXP.  All regexps are tried in the
order in which they appear in the list.
See `bibtex-generate-autokey' for details."
  :group 'bibtex-autokey
  :type '(repeat (cons (regexp :tag "Old")
                       (string :tag "New"))))

(defcustom bibtex-autokey-titleword-length 5
  "*Number of characters from title words to incorporate into key.
If this is set to anything but a number, all characters are used.
See `bibtex-generate-autokey' for details."
  :group 'bibtex-autokey
  :type '(choice (const :tag "All" infty)
                 integer))

(defcustom bibtex-autokey-titleword-separator "_"
  "*String to be put between the title words.
See `bibtex-generate-autokey' for details."
  :group 'bibtex-autokey
  :type 'string)

(defcustom bibtex-autokey-name-year-separator ""
  "*String to be put between name part and year part of key.
See `bibtex-generate-autokey' for details."
  :group 'bibtex-autokey
  :type 'string)

(defcustom bibtex-autokey-year-title-separator ":_"
  "*String to be put between name part and year part of key.
See `bibtex-generate-autokey' for details."
  :group 'bibtex-autokey
  :type 'string)

(defcustom bibtex-autokey-edit-before-use t
  "*If non-nil, user is allowed to edit the generated key before it is used."
  :group 'bibtex-autokey
  :type 'boolean)

(defcustom bibtex-autokey-before-presentation-function nil
  "*Function to call before the generated key is presented.
If non-nil this should be a function which is called before the generated key
is presented.  The function must take one argument (the automatically
generated key), and must return a string (the key to use)."
  :group 'bibtex-autokey
  :type '(choice (const nil) function))

(defcustom bibtex-entry-offset 0
  "*Offset for BibTeX entries.
Added to the value of all other variables which determine colums."
  :group 'bibtex
  :type 'integer)

(defcustom bibtex-field-indentation 2
  "*Starting column for the name part in BibTeX fields."
  :group 'bibtex
  :type 'integer)

(defcustom bibtex-text-indentation
  (+ bibtex-field-indentation
     (length "organization = "))
  "*Starting column for the text part in BibTeX fields.
Should be equal to the space needed for the longest name part."
  :group 'bibtex
  :type 'integer)

(defcustom bibtex-contline-indentation
  (+ bibtex-text-indentation 1)
  "*Starting column for continuation lines of BibTeX fields."
  :group 'bibtex
  :type 'integer)

(defcustom bibtex-align-at-equal-sign nil
  "*If non-nil, align fields at equal sign instead of field text.
If non-nil, the column for the equal sign is the value of
`bibtex-text-indentation', minus 2."
  :group 'bibtex
  :type 'boolean)

(defcustom bibtex-comma-after-last-field nil
  "*If non-nil, a comma is put at end of last field in the entry template."
  :group 'bibtex
  :type 'boolean)

(defcustom bibtex-autoadd-commas t
  "If non-nil automatically add missing commas at end of BibTeX fields."
  :type 'boolean)

(defcustom bibtex-autofill-types '("Proceedings")
  "Automatically fill fields if possible for those BibTeX entry types."
  :type '(repeat string))

(defcustom bibtex-complete-key-cleanup nil
  "*Function called by `bibtex-complete' after insertion of a key fragment."
  :group 'bibtex-autokey
  :type '(choice (const :tag "None" nil)
                 (function :tag "Cleanup function")))

;; bibtex-font-lock-keywords is a user option as well, but since the
;; patterns used to define this variable are defined in a later
;; section of this file, it is defined later.


;; Syntax Table, Keybindings and BibTeX Entry List
(defvar bibtex-mode-syntax-table
  (let ((st (make-syntax-table)))
    (modify-syntax-entry ?\" "\"" st)
    (modify-syntax-entry ?$ "$$  " st)
    (modify-syntax-entry ?% "<   " st)
    (modify-syntax-entry ?' "w   " st)
    (modify-syntax-entry ?@ "w   " st)
    (modify-syntax-entry ?\\ "\\" st)
    (modify-syntax-entry ?\f ">   " st)
    (modify-syntax-entry ?\n ">   " st)
    ;; Keys cannot have = in them (wrong font-lock of @string{foo=bar}).
    (modify-syntax-entry ?= "." st)
    (modify-syntax-entry ?~ " " st)
    st)
  "Syntax table used in BibTeX mode buffers.")

(defvar bibtex-mode-map
  (let ((km (make-sparse-keymap)))
    ;; The Key `C-c&' is reserved for reftex.el
    (define-key km "\t" 'bibtex-find-text)
    (define-key km "\n" 'bibtex-next-field)
    (define-key km "\M-\t" 'bibtex-complete)
    (define-key km "\C-c\"" 'bibtex-remove-delimiters)
    (define-key km "\C-c{" 'bibtex-remove-delimiters)
    (define-key km "\C-c}" 'bibtex-remove-delimiters)
    (define-key km "\C-c\C-c" 'bibtex-clean-entry)
    (define-key km "\C-c\C-q" 'bibtex-fill-entry)
    (define-key km "\C-c?" 'bibtex-print-help-message)
    (define-key km "\C-c\C-p" 'bibtex-pop-previous)
    (define-key km "\C-c\C-n" 'bibtex-pop-next)
    (define-key km "\C-c\C-k" 'bibtex-kill-field)
    (define-key km "\C-c\M-k" 'bibtex-copy-field-as-kill)
    (define-key km "\C-c\C-w" 'bibtex-kill-entry)
    (define-key km "\C-c\M-w" 'bibtex-copy-entry-as-kill)
    (define-key km "\C-c\C-y" 'bibtex-yank)
    (define-key km "\C-c\M-y" 'bibtex-yank-pop)
    (define-key km "\C-c\C-d" 'bibtex-empty-field)
    (define-key km "\C-c\C-f" 'bibtex-make-field)
    (define-key km "\C-c$" 'bibtex-ispell-abstract)
    (define-key km "\M-\C-a" 'bibtex-beginning-of-entry)
    (define-key km "\M-\C-e" 'bibtex-end-of-entry)
    (define-key km "\C-\M-l" 'bibtex-reposition-window)
    (define-key km "\C-\M-h" 'bibtex-mark-entry)
    (define-key km "\C-c\C-b" 'bibtex-entry)
    (define-key km "\C-c\C-rn" 'bibtex-narrow-to-entry)
    (define-key km "\C-c\C-rw" 'widen)
    (define-key km "\C-c\C-o" 'bibtex-remove-OPT-or-ALT)
    (define-key km "\C-c\C-e\C-i" 'bibtex-InProceedings)
    (define-key km "\C-c\C-ei" 'bibtex-InCollection)
    (define-key km "\C-c\C-eI" 'bibtex-InBook)
    (define-key km "\C-c\C-e\C-a" 'bibtex-Article)
    (define-key km "\C-c\C-e\C-b" 'bibtex-InBook)
    (define-key km "\C-c\C-eb" 'bibtex-Book)
    (define-key km "\C-c\C-eB" 'bibtex-Booklet)
    (define-key km "\C-c\C-e\C-c" 'bibtex-InCollection)
    (define-key km "\C-c\C-e\C-m" 'bibtex-Manual)
    (define-key km "\C-c\C-em" 'bibtex-MastersThesis)
    (define-key km "\C-c\C-eM" 'bibtex-Misc)
    (define-key km "\C-c\C-e\C-p" 'bibtex-InProceedings)
    (define-key km "\C-c\C-ep" 'bibtex-Proceedings)
    (define-key km "\C-c\C-eP" 'bibtex-PhdThesis)
    (define-key km "\C-c\C-e\M-p" 'bibtex-Preamble)
    (define-key km "\C-c\C-e\C-s" 'bibtex-String)
    (define-key km "\C-c\C-e\C-t" 'bibtex-TechReport)
    (define-key km "\C-c\C-e\C-u" 'bibtex-Unpublished)
    km)
  "Keymap used in BibTeX mode.")

(easy-menu-define
  bibtex-edit-menu bibtex-mode-map "BibTeX-Edit Menu in BibTeX mode"
  '("BibTeX-Edit"
    ("Moving inside an Entry"
     ["End of Field" bibtex-find-text t]
     ["Next Field" bibtex-next-field t]
     ["Beginning of Entry" bibtex-beginning-of-entry t]
     ["End of Entry" bibtex-end-of-entry t])
    ("Moving in BibTeX Buffer"
     ["Find Entry" bibtex-find-entry t]
     ["Find Crossref Entry" bibtex-find-crossref t])
    ("Operating on Current Entry"
     ["Fill Entry" bibtex-fill-entry t]
     ["Clean Entry" bibtex-clean-entry t]
     "--"
     ["Kill Entry" bibtex-kill-entry t]
     ["Copy Entry to Kill Ring" bibtex-copy-entry-as-kill t]
     ["Paste Most Recently Killed Entry" bibtex-yank t]
     ["Paste Previously Killed Entry" bibtex-yank-pop t]
     "--"
     ["Ispell Entry" bibtex-ispell-entry t]
     ["Ispell Entry Abstract" bibtex-ispell-abstract t]
     ["Narrow to Entry" bibtex-narrow-to-entry t]
     "--"
     ["View Cite Locations (RefTeX)" reftex-view-crossref-from-bibtex
      (fboundp 'reftex-view-crossref-from-bibtex)])
    ("Operating on Current Field"
     ["Fill Field" fill-paragraph t]
     ["Remove Delimiters" bibtex-remove-delimiters t]
     ["Remove OPT or ALT Prefix" bibtex-remove-OPT-or-ALT t]
     ["Clear Field" bibtex-empty-field t]
     "--"
     ["Kill Field" bibtex-kill-field t]
     ["Copy Field to Kill Ring" bibtex-copy-field-as-kill t]
     ["Paste Most Recently Killed Field" bibtex-yank t]
     ["Paste Previously Killed Field" bibtex-yank-pop t]
     "--"
     ["Make New Field" bibtex-make-field t]
     "--"
     ["Snatch from Similar Following Field" bibtex-pop-next t]
     ["Snatch from Similar Preceding Field" bibtex-pop-previous t]
     "--"
     ["String or Key Complete" bibtex-complete t]
     "--"
     ["Help about Current Field" bibtex-print-help-message t])
    ("Operating on Buffer or Region"
     ["Validate Entries" bibtex-validate t]
     ["Sort Entries" bibtex-sort-buffer t]
     ["Reformat Entries" bibtex-reformat t]
     ["Count Entries" bibtex-count-entries t])
    ("Miscellaneous"
     ["Convert Alien Buffer" bibtex-convert-alien t])))

(easy-menu-define
  bibtex-entry-menu bibtex-mode-map "Entry-Types Menu in BibTeX mode"
  (list "Entry-Types"
        ["Article in Journal" bibtex-Article t]
        ["Article in Conference Proceedings" bibtex-InProceedings t]
        ["Article in a Collection" bibtex-InCollection t]
        ["Chapter or Pages in a Book" bibtex-InBook t]
        ["Conference Proceedings" bibtex-Proceedings t]
        ["Book" bibtex-Book t]
        ["Booklet (Bound, but no Publisher/Institution)" bibtex-Booklet t]
        ["PhD. Thesis" bibtex-PhdThesis t]
        ["Master's Thesis" bibtex-MastersThesis t]
        ["Technical Report" bibtex-TechReport t]
        ["Technical Manual" bibtex-Manual t]
        ["Unpublished" bibtex-Unpublished t]
        ["Miscellaneous" bibtex-Misc t]
        ["String" bibtex-String t]
        ["Preamble" bibtex-Preamble t]))


;; Internal Variables

(defvar bibtex-pop-previous-search-point nil
  "Next point where `bibtex-pop-previous' starts looking for a similar entry.")

(defvar bibtex-pop-next-search-point nil
  "Next point where `bibtex-pop-next' starts looking for a similar entry.")

(defvar bibtex-field-kill-ring nil
  "Ring of least recently killed fields.
At most `bibtex-field-kill-ring-max' items are kept here.")

(defvar bibtex-field-kill-ring-yank-pointer nil
  "The tail of `bibtex-field-kill-ring' whose car is the last item yanked.")

(defvar bibtex-entry-kill-ring nil
  "Ring of least recently killed entries.
At most `bibtex-entry-kill-ring-max' items are kept here.")

(defvar bibtex-entry-kill-ring-yank-pointer nil
  "The tail of `bibtex-entry-kill-ring' whose car is the last item yanked.")

(defvar bibtex-last-kill-command nil
  "Type of the last kill command (either 'field or 'entry).")

(defvar bibtex-strings
  (lazy-completion-table bibtex-strings
                         bibtex-parse-strings (bibtex-string-files-init))
  "Completion table for BibTeX string keys.
Initialized from `bibtex-predefined-strings' and `bibtex-string-files'.")
(make-variable-buffer-local 'bibtex-strings)

(defvar bibtex-reference-keys
  (lazy-completion-table bibtex-reference-keys bibtex-parse-keys nil nil t)
  "Completion table for BibTeX reference keys.")
(make-variable-buffer-local 'bibtex-reference-keys)

(defvar bibtex-buffer-last-parsed-tick nil
  "Last value returned by `buffer-modified-tick' when buffer
was parsed for keys the last time.")

(defvar bibtex-parse-idle-timer nil
  "Stores if timer is already installed.")

(defvar bibtex-progress-lastperc nil
  "Last reported percentage for the progress message.")

(defvar bibtex-progress-lastmes nil
  "Last reported progress message.")

(defvar bibtex-progress-interval nil
  "Interval for progress messages.")

(defvar bibtex-key-history nil
  "History list for reading keys.")

(defvar bibtex-entry-type-history nil
  "History list for reading entry types.")

(defvar bibtex-field-history nil
  "History list for reading field names.")

(defvar bibtex-reformat-previous-options nil
  "Last reformat options given.")

(defvar bibtex-reformat-previous-reference-keys nil
  "Last reformat reference keys option given.")

(defconst bibtex-field-name "[^\"#%'(),={} \t\n0-9][^\"#%'(),={} \t\n]*"
  "Regexp matching the name part of a BibTeX field.")

(defconst bibtex-entry-type (concat "@" bibtex-field-name)
  "Regexp matching the type part of a BibTeX entry.")

(defconst bibtex-reference-key "[][a-zA-Z0-9.:;?!`'/*@+|()<>&_^$-]+"
  "Regexp matching the reference key part of a BibTeX entry.")

(defconst bibtex-field-const "[][a-zA-Z0-9.:;?!`'/*@+=|<>&_^$-]+"
  "Regexp matching a BibTeX field constant.")

(defconst bibtex-entry-head
  (concat "^[ \t]*\\("
          bibtex-entry-type
          "\\)[ \t]*[({][ \t\n]*\\("
          bibtex-reference-key
          "\\)")
  "Regexp matching the header line of a BibTeX entry.")

(defconst bibtex-entry-maybe-empty-head
  (concat bibtex-entry-head "?")
  "Regexp matching the header line of a BibTeX entry (possibly without key).")

(defconst bibtex-type-in-head 1
  "Regexp subexpression number of the type part in `bibtex-entry-head'.")

(defconst bibtex-key-in-head 2
  "Regexp subexpression number of the key part in `bibtex-entry-head'.")

(defconst bibtex-entry-postfix "[ \t\n]*,?[ \t\n]*[})]"
  "Regexp matching the postfix of a BibTeX entry.")

(defvar bibtex-known-entry-type-re
  (regexp-opt (mapcar 'car bibtex-entry-field-alist))
  "Regexp matching the name of a BibTeX entry type.")

(defvar bibtex-valid-entry-re
  (concat "@[ \t]*\\(" bibtex-known-entry-type-re "\\)")
  "Regexp matching the name of a valid BibTeX entry.")

(defvar bibtex-valid-entry-whitespace-re
  (concat "[ \t\n]*\\(" bibtex-valid-entry-re "\\)")
  "Regexp matching the name of a valid BibTeX entry preceded by whitespace.")

(defvar bibtex-any-valid-entry-re
  (concat "@[ \t]*"
          (regexp-opt (append '("String")
                              (mapcar 'car bibtex-entry-field-alist))
                      t))
  "Regexp matching the name of any valid BibTeX entry (including string).")


(defconst bibtex-empty-field-re "\"\"\\|{}"
  "Regexp matching an empty field.")

(defconst bibtex-quoted-string-re
  (concat "\""
          "\\("
          "[^\"\\]"          ; anything but quote or backslash
          "\\|"
          "\\("
          "\\\\\\(.\\|\n\\)" ; any backslash quoted character
          "\\)"
          "\\)*"
          "\"")
  "Regexp matching a field string enclosed by quotes.")

(defconst bibtex-font-lock-syntactic-keywords
  `((,(concat "^[ \t]*\\(" (substring bibtex-comment-start 0 1) "\\)"
              (substring bibtex-comment-start 1) "\\>")
     1 '(11))))

(defvar bibtex-font-lock-keywords
  (list
   ;; entry type and reference key
   (list bibtex-entry-maybe-empty-head
         (list bibtex-type-in-head 'font-lock-function-name-face)
         (list bibtex-key-in-head 'font-lock-constant-face nil t))
   ;; optional field names (treated as comments)
   (list
    (concat "^[ \t]*\\(OPT" bibtex-field-name "\\)[ \t]*=")
    1 'font-lock-comment-face)
   ;; field names
   (list (concat "^[ \t]*\\(" bibtex-field-name "\\)[ \t]*=")
         1 'font-lock-variable-name-face))
  "*Default expressions to highlight in BibTeX mode.")

(defvar bibtex-field-name-for-parsing nil
  "Temporary variable storing the name string to be parsed by the callback
function `bibtex-parse-field-name'.")

(defvar bibtex-sort-entry-class-alist
  (let ((i -1) alist)
    (dolist (class bibtex-sort-entry-class alist)
      (setq i (1+ i))
      (dolist (entry class)
        ;; all entry names should be downcase (for ease of comparison)
        (push (cons (if (stringp entry) (downcase entry) entry) i) alist))))
  "Alist for the classes of the entry types if the value of
`bibtex-maintain-sorted-entries' is `entry-class'.")


;; Special support taking care of variants
(defvar zmacs-regions)
(if (boundp 'mark-active)
    (defun bibtex-mark-active ()
      ;; In Emacs mark-active indicates if mark is active.
      mark-active)
  (defun bibtex-mark-active ()
    ;; In XEmacs (mark) returns nil when not active.
    (if zmacs-regions (mark) (mark t))))

(if (fboundp 'run-with-idle-timer)
    ;; timer.el is distributed with Emacs
    (fset 'bibtex-run-with-idle-timer 'run-with-idle-timer)
  ;; timer.el is not distributed with XEmacs
  ;; Notice that this does not (yet) pass the arguments, but they
  ;; are not used (yet) in bibtex.el. Fix if needed.
  (defun bibtex-run-with-idle-timer (secs repeat function &rest args)
    (start-itimer "bibtex" function secs (if repeat secs nil) t)))


;; Support for hideshow minor mode
(defun bibtex-hs-forward-sexp (arg)
  "Replacement for `forward-sexp' to be used by `hs-minor-mode'."
  (if (< arg 0)
      (backward-sexp 1)
    (if (looking-at "@\\S(*\\s(")
        (progn
          (goto-char (match-end 0))
          (forward-char -1)
          (forward-sexp 1))
      (forward-sexp 1))))

(add-to-list
 'hs-special-modes-alist
 '(bibtex-mode "@\\S(*\\s(" "\\s)" nil bibtex-hs-forward-sexp nil))


(defconst bibtex-braced-string-syntax-table
  (let ((st (make-syntax-table)))
    (modify-syntax-entry ?\{ "(}" st)
    (modify-syntax-entry ?\} "){" st)
    (modify-syntax-entry ?\[ "." st)
    (modify-syntax-entry ?\] "." st)
    (modify-syntax-entry ?\( "." st)
    (modify-syntax-entry ?\) "." st)
    (modify-syntax-entry ?\\ "." st)
    (modify-syntax-entry ?\" "." st)
    st)
  "Syntax-table to parse matched braces.")

(defconst bibtex-quoted-string-syntax-table
  (let ((st (make-syntax-table)))
    (modify-syntax-entry ?\\ "\\" st)
    (modify-syntax-entry ?\" "\"" st)
    st)
  "Syntax-table to parse matched quotes.")

(defun bibtex-parse-field-string ()
  "Parse a field string enclosed by braces or quotes.
If a syntactically correct string is found, a pair containing the start and
end position of the field string is returned, nil otherwise."
  (let ((end-point
         (or (and (eq (following-char) ?\")
                  (save-excursion
                    (with-syntax-table bibtex-quoted-string-syntax-table
                      (forward-sexp 1))
                    (point)))
             (and (eq (following-char) ?\{)
                  (save-excursion
                    (with-syntax-table bibtex-braced-string-syntax-table
                      (forward-sexp 1))
                    (point))))))
    (if end-point
        (cons (point) end-point))))

(defun bibtex-parse-association (parse-lhs parse-rhs)
  "Parse a string of the format <left-hand-side = right-hand-side>.
The functions PARSE-LHS and PARSE-RHS are used to parse the corresponding
substrings.  These functions are expected to return nil if parsing is not
successfull.  If both functions return non-nil, a pair containing the returned
values of the functions PARSE-LHS and PARSE-RHS is returned."
  (save-match-data
    (save-excursion
      (let ((left (funcall parse-lhs))
            right)
        (if (and left
                 (looking-at "[ \t\n]*=[ \t\n]*")
                 (goto-char (match-end 0))
                 (setq right (funcall parse-rhs)))
            (cons left right))))))

(defun bibtex-parse-field-name ()
  "Parse the field name stored in `bibtex-field-name-for-parsing'.
If the field name is found, return a triple consisting of the position of the
very first character of the match, the actual starting position of the name
part and end position of the match. Move point to end of field name.
If `bibtex-autoadd-commas' is non-nil add missing comma at end of preceeding
BibTeX field as necessary."
  (cond ((looking-at ",[ \t\n]*")
         (let ((start (point)))
           (goto-char (match-end 0))
           (when (looking-at bibtex-field-name-for-parsing)
             (goto-char (match-end 0))
             (list start (match-beginning 0) (match-end 0)))))
        ;; Maybe add a missing comma.
        ((and bibtex-autoadd-commas
              (looking-at (concat "[ \t\n]*\\(?:" bibtex-field-name-for-parsing
                                  "\\)[ \t\n]*=")))
         (skip-chars-backward " \t\n")
         (insert ",")
         (forward-char -1)
         ;; Now try again.
         (bibtex-parse-field-name))))

(defun bibtex-parse-field-text ()
  "Parse the text part of a BibTeX field.
The text part is either a string, or an empty string, or a constant followed
by one or more <# (string|constant)> pairs.  If a syntactically correct text
is found, a pair containing the start and end position of the text is
returned, nil otherwise. Move point to end of field text."
  (let ((starting-point (point))
        end-point failure boundaries)
    (while (not (or end-point failure))
      (cond ((looking-at bibtex-field-const)
             (goto-char (match-end 0)))
            ((setq boundaries (bibtex-parse-field-string))
             (goto-char (cdr boundaries)))
            ((setq failure t)))
      (if (not (looking-at "[ \t\n]*#[ \t\n]*"))
          (setq end-point (point))
        (goto-char (match-end 0))))
    (if (and (not failure)
             end-point)
        (cons starting-point end-point))))

(defun bibtex-parse-field (name)
  "Parse a BibTeX field of regexp NAME.
If a syntactically correct field is found, a pair containing the boundaries of
the name and text parts of the field is returned."
  (let ((bibtex-field-name-for-parsing name))
    (bibtex-parse-association 'bibtex-parse-field-name
                              'bibtex-parse-field-text)))

(defun bibtex-search-forward-field (name &optional bound)
  "Search forward to find a field of name NAME.
If a syntactically correct field is found, a pair containing the boundaries of
the name and text parts of the field is returned.  The search is limited by
optional arg BOUND. If BOUND is t the search is limited by the end of the current
entry. Do not move point."
  (save-match-data
    (save-excursion
      (unless (integer-or-marker-p bound)
        (setq bound (if bound
                        (save-excursion (bibtex-end-of-entry))
                      (point-max))))
      (let ((case-fold-search t)
            (bibtex-field-name-for-parsing name)
            boundaries temp-boundaries)
        (while (and (not boundaries)
                    (< (point) bound)
                    (search-forward "," bound t))
          (goto-char (match-beginning 0))
          (if (and (setq temp-boundaries
                         (bibtex-parse-association 'bibtex-parse-field-name
                                                   'bibtex-parse-field-text))
                   (<= (cddr temp-boundaries) bound))
              (setq boundaries temp-boundaries)
            (forward-char 1)))
        boundaries))))

(defun bibtex-search-backward-field (name &optional bound)
  "Search backward to find a field of name NAME.
If a syntactically correct field is found, a pair containing the boundaries of
the name and text parts of the field is returned.  The search is limited by
optional arg BOUND. If BOUND is t the search is limited by the beginning of the
current entry. Do not move point."
  (save-match-data
    (save-excursion
      (unless (integer-or-marker-p bound)
        (setq bound (if bound
                        (save-excursion (bibtex-beginning-of-entry))
                      (point-min))))
      (let ((case-fold-search t)
            (bibtex-field-name-for-parsing name)
            boundaries temp-boundaries)
        (while (and (not boundaries)
                    (>= (point) bound)
                    (search-backward "," bound t))
          (if (setq temp-boundaries
                    (bibtex-parse-association 'bibtex-parse-field-name
                                              'bibtex-parse-field-text))
              (setq boundaries temp-boundaries)))
        boundaries))))

(defsubst bibtex-start-of-field (bounds)
  (nth 0 (car bounds)))
(defsubst bibtex-start-of-name-in-field (bounds)
  (nth 1 (car bounds)))
(defsubst bibtex-end-of-name-in-field (bounds)
  (nth 2 (car bounds)))
(defsubst bibtex-end-of-field (bounds)
  (cddr bounds))
(defsubst bibtex-start-of-text-in-field (bounds)
  (cadr bounds))
(defsubst bibtex-end-of-text-in-field (bounds)
  (cddr bounds))

(defun bibtex-name-in-field (bounds)
  "Get content of name in BibTeX field defined via BOUNDS."
  (buffer-substring-no-properties (nth 1 (car bounds))
                                  (nth 2 (car bounds))))

(defun bibtex-text-in-field-bounds (bounds &optional remove-delim)
  "Get content of text in BibTeX field defined via BOUNDS.
If optional arg REMOVE-DELIM is non-nil remove enclosing field delimiters
if present."
  (let ((content (buffer-substring-no-properties (cadr bounds)
                                                 (cddr bounds))))
    (if (and remove-delim
             (string-match "\\`[{\"]\\(.*\\)[}\"]\\'" content))
        (substring content (match-beginning 1) (match-end 1))
      content)))

(defun bibtex-text-in-field (field &optional follow-crossref)
  "Get content of field FIELD of current BibTeX entry. Return nil if not found.
If optional arg FOLLOW-CROSSREF is non-nil, follow crossref."
  (save-excursion
    (save-restriction
      ;; We want to jump back and forth while searching FIELD
      (bibtex-narrow-to-entry)
      (goto-char (point-min))
      (let ((bounds (bibtex-search-forward-field field))
            crossref-field)
        (cond (bounds (bibtex-text-in-field-bounds bounds t))
              ((and follow-crossref
                    (progn (goto-char (point-min))
                           (setq bounds (bibtex-search-forward-field
                                         "\\(OPT\\)?crossref"))))
               (setq crossref-field (bibtex-text-in-field-bounds bounds t))
               (widen)
               (if (bibtex-find-crossref crossref-field)
                   ;; Do not pass FOLLOW-CROSSREF because we want
                   ;; to follow crossrefs only one level of recursion.
                   (bibtex-text-in-field field))))))))

(defun bibtex-parse-string-prefix ()
  "Parse the prefix part of a BibTeX string entry, including reference key.
If the string prefix is found, return a triple consisting of the position of
the very first character of the match, the actual starting position of the
reference key and the end position of the match."
  (let ((case-fold-search t))
    (if (looking-at "^[ \t]*@string[ \t\n]*[({][ \t\n]*")
        (let ((start (point)))
          (goto-char (match-end 0))
          (when (looking-at bibtex-reference-key)
            (goto-char (match-end 0))
            (list start
                  (match-beginning 0)
                  (match-end 0)))))))

(defun bibtex-parse-string-postfix ()
  "Parse the postfix part of a BibTeX string entry, including the text.
If the string postfix is found, return a triple consisting of the position of
the actual starting and ending position of the text and the very last
character of the string entry. Move point past BibTeX string entry."
  (let* ((case-fold-search t)
         (bounds (bibtex-parse-field-text)))
    (when bounds
      (goto-char (cdr bounds))
      (when (looking-at "[ \t\n]*[})]")
        (goto-char (match-end 0))
        (list (car bounds)
              (cdr bounds)
              (match-end 0))))))

(defun bibtex-parse-string ()
  "Parse a BibTeX string entry.
If a syntactically correct entry is found, a pair containing the boundaries of
the reference key and text parts of the entry is returned.
Move point past BibTeX string entry."
  (bibtex-parse-association 'bibtex-parse-string-prefix
                            'bibtex-parse-string-postfix))

(defun bibtex-search-forward-string ()
  "Search forward to find a BibTeX string entry.
If a syntactically correct entry is found, a pair containing the boundaries of
the reference key and text parts of the string is returned. Do not move point."
  (save-excursion
    (save-match-data
      (let ((case-fold-search t)
            boundaries)
        (while (and (not boundaries)
                    (search-forward-regexp
                     "^[ \t]*@string[ \t\n]*[({][ \t\n]*" nil t))
          (goto-char (match-beginning 0))
          (unless (setq boundaries (bibtex-parse-string))
            (forward-char 1)))
        boundaries))))

(defun bibtex-search-backward-string ()
  "Search backward to find a BibTeX string entry.
If a syntactically correct entry is found, a pair containing the boundaries of
the reference key and text parts of the field is returned. Do not move point."
  (save-excursion
    (save-match-data
      (let ((case-fold-search t)
            boundaries)
        (while (and (not boundaries)
                    (search-backward-regexp
                     "^[ \t]*@string[ \t\n]*[({][ \t\n]*" nil t))
          (goto-char (match-beginning 0))
          (setq boundaries (bibtex-parse-string)))
        boundaries))))

(defun bibtex-reference-key-in-string (bounds)
  (buffer-substring-no-properties (nth 1 (car bounds))
                                  (nth 2 (car bounds))))

(defun bibtex-text-in-string (bounds &optional remove-delim)
  "Get content of text in BibTeX string field defined via BOUNDS.
If optional arg REMOVE-DELIM is non-nil remove enclosing field
delimiters if present."
  (let ((content (buffer-substring-no-properties (nth 0 (cdr bounds))
                                                 (nth 1 (cdr bounds)))))
    (if (and remove-delim
             (string-match "\\`{\\(.*\\)}\\'" content))
        (substring content (match-beginning 1) (match-end 1))
      content)))

(defsubst bibtex-start-of-text-in-string (bounds)
  (nth 0 (cdr bounds)))
(defsubst bibtex-end-of-text-in-string (bounds)
  (nth 1 (cdr bounds)))
(defsubst bibtex-end-of-string (bounds)
  (nth 2 (cdr bounds)))

(defsubst bibtex-type-in-head ()
  "Extract BibTeX type in head."
  ;;                              ignore @
  (buffer-substring-no-properties (1+ (match-beginning bibtex-type-in-head))
                                  (match-end bibtex-type-in-head)))

(defun bibtex-key-in-head (&optional empty)
  "Extract BibTeX key in head. Return optional arg EMPTY if key is empty."
  (if (match-beginning bibtex-key-in-head)
      (buffer-substring-no-properties (match-beginning bibtex-key-in-head)
                                      (match-end bibtex-key-in-head))
    empty))

;; Helper Functions

(defun bibtex-delete-whitespace ()
  "Delete all whitespace starting at point."
  (if (looking-at "[ \t\n]+")
      (delete-region (point) (match-end 0))))

(defun bibtex-current-line ()
  "Compute line number of point regardless whether the buffer is narrowed."
  (+ (count-lines 1 (point))
     (if (equal (current-column) 0) 1 0)))

(defun bibtex-member-of-regexp (string list)
  "Return non-nil if STRING is exactly matched by an element of LIST.
The value is actually the tail of LIST whose car matches STRING."
  (let (case-fold-search)
    (while (and list
                (not (string-match (concat "\\`\\(?:" (car list) "\\)\\'") string)))
      (setq list (cdr list)))
    list))

(defun bibtex-assoc-of-regexp (string alist)
  "Return non-nil if STRING is exactly matched by the car of an
element of ALIST (case ignored). The value is actually the element
of LIST whose car matches STRING."
  (let ((case-fold-search t))
    (while (and alist
                (not (string-match (concat "\\`\\(?:" (caar alist) "\\)\\'") string)))
      (setq alist (cdr alist)))
    (car alist)))

(defun bibtex-skip-to-valid-entry (&optional backward)
  "Unless at beginning of a valid BibTeX entry, move point to beginning of the
next valid one. With optional argument BACKWARD non-nil, move backward to
beginning of previous valid one. A valid entry is a syntactical correct one
with type contained in `bibtex-entry-field-alist' or, if
`bibtex-sort-ignore-string-entries' is nil, a syntactical correct string
entry. Return buffer position of beginning and ending of entry if a valid
entry is found, nil otherwise."
  (interactive "P")
  (let ((case-fold-search t)
        found)
    (while (not (or found (if backward (bobp) (eobp))))
      (let ((pnt (point))
            bounds)
        (cond ((or (and (looking-at bibtex-valid-entry-re)
                        (setq found (bibtex-search-entry nil nil t))
                        (equal (match-beginning 0) pnt))
                   (and (not bibtex-sort-ignore-string-entries)
                        (setq bounds (bibtex-parse-string))
                        (setq found (cons (bibtex-start-of-field bounds)
                                          (bibtex-end-of-string bounds)))))
               (goto-char pnt))
              (backward
               (if (re-search-backward "^[ \t]*\\(@\\)" nil 'move)
                   (goto-char (match-beginning 1))))
              (t (if (re-search-forward "\n[ \t]*@" nil 'move)
                     (forward-char -1))))))
    found))

(defun bibtex-map-entries (fun)
  "Call FUN for each BibTeX entry starting with the current.
Do this to the end of the file. FUN is called with three arguments, the key of
the entry and the buffer positions (marker) of beginning and end of entry.
Point is inside the entry. If `bibtex-sort-ignore-string-entries' is non-nil,
FUN will not be called for @String entries."
  (let ((case-fold-search t))
    (bibtex-beginning-of-entry)
    (while (re-search-forward bibtex-entry-head nil t)
      (let ((entry-type (bibtex-type-in-head))
            (key (bibtex-key-in-head ""))
            (beg (copy-marker (match-beginning 0)))
            (end (copy-marker (save-excursion (bibtex-end-of-entry)))))
        (save-excursion
          (if (or (and (not bibtex-sort-ignore-string-entries)
                       (string-equal "string" (downcase entry-type)))
                  (assoc-ignore-case entry-type bibtex-entry-field-alist))
              (funcall fun key beg end)))
        (goto-char end)))))

(defun bibtex-progress-message (&optional flag interval)
  "Echo a message about progress of current buffer.
If FLAG is a string, the message is initialized (in this case a
value for INTERVAL may be given as well (if not this is set to 5)).
If FLAG is done, the message is deinitialized.
If FLAG is absent, a message is echoed if point was incremented
at least INTERVAL percent since last message was echoed."
  (cond ((stringp flag)
         (setq bibtex-progress-lastmes flag)
         (setq bibtex-progress-interval (or interval 5)
               bibtex-progress-lastperc 0))
        ((equal flag 'done)
         (message  "%s (done)" bibtex-progress-lastmes)
         (setq bibtex-progress-lastmes nil))
        (t
         (let* ((size (- (point-max) (point-min)))
                (perc (if (= size 0)
                          100
                        (/ (* 100 (- (point) (point-min))) size))))
           (when (>= perc (+ bibtex-progress-lastperc
                             bibtex-progress-interval))
             (setq bibtex-progress-lastperc perc)
             (message "%s (%d%%)" bibtex-progress-lastmes perc))))))

(defun bibtex-field-left-delimiter ()
  "Return a string dependent on `bibtex-field-delimiters'."
  (if (equal bibtex-field-delimiters 'braces)
      "{"
    "\""))

(defun bibtex-field-right-delimiter ()
  "Return a string dependent on `bibtex-field-delimiters'."
  (if (equal bibtex-field-delimiters 'braces)
      "}"
    "\""))

(defun bibtex-entry-left-delimiter ()
  "Return a string dependent on `bibtex-field-delimiters'."
  (if (equal bibtex-entry-delimiters 'braces)
      "{"
    "("))

(defun bibtex-entry-right-delimiter ()
  "Return a string dependent on `bibtex-field-delimiters'."
  (if (equal bibtex-entry-delimiters 'braces)
      "}"
    ")"))

(defun bibtex-search-entry (empty-head &optional bound noerror backward)
  "Search for a BibTeX entry (maybe without reference key if EMPTY-HEAD is t).
BOUND and NOERROR are exactly as in `re-search-forward'. If BACKWARD
is non-nil, search is done in reverse direction. Point is moved past the
closing delimiter (at the beginning of entry if BACKWARD is non-nil).
Return a cons pair with buffer positions of beginning and end of entry.
After call to this function MATCH-BEGINNING and MATCH-END functions
are defined, but only for the head part of the entry
\(especially (match-end 0) just gives the end of the head part)."
  (let ((pnt (point))
        (entry-head-re (if empty-head
                           bibtex-entry-maybe-empty-head
                         bibtex-entry-head)))
    (if backward
        (let (found)
          (while (and (not found)
                      (re-search-backward entry-head-re bound noerror))
            (setq found (bibtex-search-entry empty-head pnt t)))
          (if found
              (progn (goto-char (match-beginning 0))
                     found)
            (cond ((equal noerror nil)
                   ;; yell
                   (error "Backward search of BibTeX entry failed"))
                  ((equal noerror t)
                   ;; don't move
                   (goto-char pnt)))
            nil))
      (let ((limit (or bound (point-max)))
            found)
        (while (and (not found)
                    (re-search-forward entry-head-re bound noerror))
          (save-match-data
            (let ((entry-closer
                   (if (save-excursion
                         (goto-char (match-end bibtex-type-in-head))
                         (looking-at "[ \t]*("))
                       ;; entry opened with parenthesis
                       ?\)
                     ?\}))
                  (infix-start (point))
                  finished bounds)
              (while (not finished)
                (skip-chars-forward " \t\n" limit)
                (if (and (setq bounds (bibtex-parse-field bibtex-field-name))
                         (<= (bibtex-end-of-field bounds) limit))
                    (setq infix-start (bibtex-end-of-field bounds))
                  (setq finished t))
                (goto-char infix-start))
              ;; This matches the infix* part. The AND construction assures
              ;; that BOUND is respected.
              (when (and (looking-at bibtex-entry-postfix)
                         (eq (char-before (match-end 0)) entry-closer)
                         (<= (match-end 0) limit))
                (goto-char (match-end 0))
                (setq found t)))))
        (if found
            (cons (match-beginning 0) (point))
          (cond ((not noerror)
                 ;; yell
                 (error "Search of BibTeX entry failed"))
                ((equal noerror t)
                 ;; don't move
                 (goto-char pnt)))
          nil)))))

(defun bibtex-flash-head ()
  "Flash at BibTeX entry head before point, if exists."
  (let ((case-fold-search t)
        flash)
    (cond ((re-search-backward bibtex-entry-head nil t)
           (goto-char (match-beginning bibtex-type-in-head))
           (setq flash (match-end bibtex-key-in-head)))
          (t
           (end-of-line)
           (skip-chars-backward " \t")
           (setq flash (point))
           (beginning-of-line)
           (skip-chars-forward " \t")))
    (if (pos-visible-in-window-p (point))
        (sit-for 1)
      (message "From: %s"
               (buffer-substring (point) flash)))))

(defun bibtex-make-optional-field (field)
  "Make an optional field named FIELD in current BibTeX entry."
  (if (consp field)
      (bibtex-make-field (cons (concat "OPT" (car field)) (cdr field)))
    (bibtex-make-field (concat "OPT" field))))

(defun bibtex-move-outside-of-entry ()
  "Make sure point is outside of a BibTeX entry."
  (let ((orig-point (point)))
    (bibtex-end-of-entry)
    (when (< (point) orig-point)
      ;; We moved backward, so we weren't inside an entry to begin with.
      ;; Leave point at the beginning of a line, and preferably
      ;; at the beginning of a paragraph.
      (goto-char orig-point)
      (beginning-of-line 1)
      (unless (= ?\n (char-before (1- (point))))
        (re-search-forward "^[ \t]*[@\n]" nil 'move)
        (backward-char 1)))
    (skip-chars-forward " \t\n")))

(defun bibtex-beginning-of-first-entry ()
  "Go to the beginning of the first BibTeX entry in buffer. Return point."
  (goto-char (point-min))
  (if (re-search-forward "^[ \t]*@" nil 'move)
      (beginning-of-line))
  (point))

(defun bibtex-beginning-of-last-entry ()
  "Go to the beginning of the last BibTeX entry in buffer."
  (goto-char (point-max))
  (if (re-search-backward "^[ \t]*@" nil 'move)
      (beginning-of-line))
  (point))

(defun bibtex-inside-field ()
  "Try to avoid point being at end of a BibTeX field."
  (end-of-line)
  (skip-chars-backward " \t")
  (cond ((= (preceding-char) ?,)
         (forward-char -2)))
  (cond ((or (= (preceding-char) ?})
             (= (preceding-char) ?\"))
         (forward-char -1))))

(defun bibtex-enclosing-field (&optional noerr)
  "Search for BibTeX field enclosing point. Point moves to end of field.
Use `match-beginning' and `match-end' to parse the field. If NOERR is non-nil,
no error is signalled. In this case, bounds are returned on success,
nil otherwise."
  (let ((bounds (bibtex-search-backward-field bibtex-field-name t)))
    (if (and bounds
             (<= (bibtex-start-of-field bounds) (point))
             (>= (bibtex-end-of-field bounds) (point)))
        bounds
      (unless noerr
        (error "Can't find enclosing BibTeX field")))))

(defun bibtex-enclosing-entry-maybe-empty-head ()
  "Search for BibTeX entry enclosing point. Move point to end of entry.
Beginning (but not end) of entry is given by (`match-beginning' 0)."
  (let ((case-fold-search t)
        (old-point (point)))
    (unless (re-search-backward bibtex-entry-maybe-empty-head nil t)
      (goto-char old-point)
      (error "Can't find beginning of enclosing BibTeX entry"))
    (goto-char (match-beginning bibtex-type-in-head))
    (unless (bibtex-search-entry t nil t)
      (goto-char old-point)
      (error "Can't find end of enclosing BibTeX entry"))))

(defun bibtex-insert-current-kill (n)
  (if (not bibtex-last-kill-command)
      (error "BibTeX kill ring is empty")
    (let* ((kr (if (equal bibtex-last-kill-command 'field)
                   'bibtex-field-kill-ring
                 'bibtex-entry-kill-ring))
           (kryp (if (equal bibtex-last-kill-command 'field)
                     'bibtex-field-kill-ring-yank-pointer
                   'bibtex-entry-kill-ring-yank-pointer))
           (ARGth-kill-element (nthcdr (mod (- n (length (eval kryp)))
                                            (length (eval kr)))
                                       (eval kr)))
           (current (car (set kryp ARGth-kill-element))))
      (cond
       ((equal bibtex-last-kill-command 'field)
        (let (bibtex-help-message)
          (bibtex-find-text nil t)
          (if (looking-at "[}\"]")
              (forward-char)))
        (set-mark (point))
        (message "Mark set")
        (bibtex-make-field (list (elt current 1) nil (elt current 2)) t))
       ((equal bibtex-last-kill-command 'entry)
        (if (not (eobp))
            (bibtex-beginning-of-entry))
        (set-mark (point))
        (message "Mark set")
        (insert (elt current 1)))
       (t
        (error "Unknown tag field: %s.  Please submit a bug report"
               bibtex-last-kill-command))))))

(defun bibtex-format-entry ()
  "Helper function for `bibtex-clean-entry'.
Formats current entry according to variable `bibtex-entry-format'."
  (save-excursion
    (save-restriction
      (bibtex-narrow-to-entry)
      (let ((case-fold-search t)
            (format (if (equal bibtex-entry-format t)
                        '(realign opts-or-alts required-fields
                                  numerical-fields
                                  last-comma page-dashes delimiters
                                  unify-case inherit-booktitle)
                      bibtex-entry-format))
            crossref-key bounds alternatives-there non-empty-alternative
            entry-list req creq field-done field-list)

        ;; identify entry type
        (goto-char (point-min))
        (re-search-forward bibtex-entry-type)
        (let ((beg-type (1+ (match-beginning 0)))
              (end-type (match-end 0)))
          (setq entry-list (assoc-ignore-case (buffer-substring-no-properties
                                               beg-type end-type)
                                              bibtex-entry-field-alist)
                req  (nth 0 (nth 1 entry-list))  ; required part
                creq (nth 0 (nth 2 entry-list))) ; crossref part

          ;; unify case of entry name
          (when (memq 'unify-case format)
            (delete-region beg-type end-type)
            (insert (car entry-list)))

          ;; update left entry delimiter
          (when (memq 'delimiters format)
            (goto-char end-type)
            (skip-chars-forward " \t\n")
            (delete-char 1)
            (insert (bibtex-entry-left-delimiter))))

        ;; determine if entry has crossref field and if at least
        ;; one alternative is non-empty
        (goto-char (point-min))
        (while (setq bounds (bibtex-search-forward-field
                             bibtex-field-name))
          (goto-char (bibtex-start-of-name-in-field bounds))
          (cond ((looking-at "ALT")
                 (setq alternatives-there t)
                 (goto-char (bibtex-start-of-text-in-field bounds))
                 (if (not (looking-at bibtex-empty-field-re))
                     (setq non-empty-alternative t)))
                ((and (looking-at "\\(OPT\\)?crossref\\>")
                      (progn (goto-char (bibtex-start-of-text-in-field bounds))
                             (not (looking-at bibtex-empty-field-re))))
                 (setq crossref-key
                       (bibtex-text-in-field-bounds bounds t))))
          (goto-char (bibtex-end-of-field bounds)))
        (if (and alternatives-there
                 (not non-empty-alternative)
                 (memq 'required-fields format))
            (error "All alternatives are empty"))

        ;; process all fields
        (goto-char (point-min))
        (while (setq bounds (bibtex-search-forward-field bibtex-field-name))
          (let* ((beg-field (copy-marker (bibtex-start-of-field bounds)))
                 (end-field (copy-marker (bibtex-end-of-field bounds)))
                 (beg-name  (copy-marker (bibtex-start-of-name-in-field bounds)))
                 (end-name  (copy-marker (bibtex-end-of-name-in-field bounds)))
                 (beg-text  (copy-marker (bibtex-start-of-text-in-field bounds)))
                 (end-text  (copy-marker (bibtex-end-of-text-in-field bounds)))
                 (opt-alt   (string-match "OPT\\|ALT"
                                          (buffer-substring-no-properties beg-name (+ beg-name 3))))
                 (field-name (buffer-substring-no-properties
                              (if opt-alt (+ beg-name 3) beg-name) end-name))
                 (empty-field (string-match bibtex-empty-field-re
                                            (buffer-substring-no-properties beg-field end-field)))
                 deleted)

            ;; We have more elegant high-level functions for several
            ;; tasks done by bibtex-format-entry. However, they contain
            ;; quite some redundancy compared with what we need to do
            ;; anyway. So for speed-up we avoid using them.

            (when (and opt-alt
                       (memq 'opts-or-alts format))
              (if empty-field
                  ;; Either it is an empty ALT field. Then we have checked
                  ;; already that we have one non-empty alternative.
                  ;; Or it is an empty OPT field that we do not miss anyway.
                  ;; So we can safely delete this field.
                  (progn (delete-region beg-field end-field)
                         (setq deleted t))
                ;; otherwise: not empty, delete "OPT" or "ALT"
                (goto-char beg-name)
                (delete-char 3)))

            (unless deleted
              (push field-name field-list)

              ;; remove delimiters from purely numerical fields
              (when (and (memq 'numerical-fields format)
                         (progn (goto-char beg-text)
                                (looking-at "\\(\"[0-9]+\"\\)\\|\\({[0-9]+}\\)")))
                (goto-char end-text)
                (delete-char -1)
                (goto-char beg-text)
                (delete-char 1))

              ;; update delimiters
              (when (memq 'delimiters format)
                (goto-char beg-text)
                (when (looking-at "[{\"]")
                  (delete-char 1)
                  (insert (bibtex-field-left-delimiter)))
                (goto-char (1- (marker-position end-text)))
                (when (looking-at "[}\"]")
                  (delete-char 1)
                  (insert (bibtex-field-right-delimiter))))

              ;; update page dashes
              (if (and (memq 'page-dashes format)
                       (string-match "\\`\\(OPT\\)?pages\\'" field-name)
                       (progn (goto-char beg-text)
                              (looking-at
                               "\\([\"{][0-9]+\\)[ \t\n]*--?[ \t\n]*\\([0-9]+[\"}]\\)")))
                  (replace-match "\\1-\\2"))

              ;; use book title of crossref'd entry
              (if (and (memq 'inherit-booktitle format)
                       empty-field
                       (equal (downcase field-name) "booktitle")
                       crossref-key)
                  (let ((title (save-restriction
                                 (widen)
                                 (if (bibtex-find-entry crossref-key)
                                     (bibtex-text-in-field "title")))))
                    (when title
                      (setq empty-field nil)
                      (goto-char (1+ beg-text))
                      (insert title))))

	      ;; Use booktitle to set a missing title.
	      (if (and empty-field
		       (equal (downcase field-name) "title"))
		  (let ((booktitle (bibtex-text-in-field "booktitle")))
		    (when booktitle
		      (setq empty-field nil)
		      (goto-char (1+ beg-text))
		      (insert booktitle))))

              ;; if empty field, complain
              (if (and empty-field
                       (memq 'required-fields format)
                       (assoc-ignore-case field-name
                                          (if crossref-key creq req)))
                  (error "Mandatory field `%s' is empty" field-name))

              ;; unify case of field name
              (if (memq 'unify-case format)
                  (let ((fname (car (assoc-ignore-case
                                     field-name (append (nth 0 (nth 1 entry-list))
                                                        (nth 1 (nth 1 entry-list))
                                                        bibtex-user-optional-fields)))))
                    (if fname
                        (progn
                          (delete-region beg-name end-name)
                          (goto-char beg-name)
                          (insert fname))
                      ;; there are no rules we could follow
                      (downcase-region beg-name end-name))))

              ;; update point
              (goto-char end-field))))

        ;; check whether all required fields are present
        (if (memq 'required-fields format)
            (let (altlist (found 0))
              (dolist (fname (if crossref-key creq req))
                (if (nth 3 fname)
                    (push (car fname) altlist))
                (unless (or (member (car fname) field-list)
                            (nth 3 fname))
                  (error "Mandatory field `%s' is missing" (car fname))))
              (when altlist
                (dolist (fname altlist)
                  (if (member fname field-list)
                      (setq found (1+ found))))
                (cond ((= found 0)
                       (error "Alternative mandatory field `%s' is missing"
                              altlist))
                      ((> found 1)
                       (error "Alternative fields `%s' is defined %s times"
                              altlist found))))))

        ;; update point
        (if (looking-at (bibtex-field-right-delimiter))
            (forward-char))

        ;; update comma after last field
        (if (memq 'last-comma format)
            (cond ((and bibtex-comma-after-last-field
                        (not (looking-at ",")))
                   (insert ","))
                  ((and (not bibtex-comma-after-last-field)
                        (looking-at ","))
                   (delete-char 1))))

        ;; update right entry delimiter
        (if (looking-at ",")
            (forward-char))
        (when (memq 'delimiters format)
          (skip-chars-forward " \t\n")
          (delete-char 1)
          (insert (bibtex-entry-right-delimiter)))

        ;; fill entry
        (if (memq 'realign format)
            (bibtex-fill-entry))))))


(defun bibtex-autokey-abbrev (string len)
  "Return an abbreviation of STRING with at least LEN characters.
If LEN is positive the abbreviation is terminated only after a consonant
or at the word end. If LEN is negative the abbreviation is strictly
enforced using abs (LEN) characters. If LEN is not a number, STRING
is returned unchanged."
  (cond ((or (not (numberp len))
             (<= (length string) (abs len)))
         string)
        ((equal len 0)
         "")
        ((< len 0)
         (substring string 0 (abs len)))
        (t (let* ((case-fold-search t)
                  (abort-char (string-match "[^aeiou]" string (1- len))))
             (if abort-char
                 (substring string 0 (1+ abort-char))
               string)))))

(defun bibtex-autokey-get-field (field &optional change-list)
  "Get content of BibTeX field FIELD. Return empty string if not found.
Optional arg CHANGE-LIST is a list of substitution patterns that is
applied to the content of FIELD. It is an alist with pairs
\(OLD-REGEXP . NEW-STRING\)."
  (let ((content (bibtex-text-in-field field bibtex-autokey-use-crossref))
        case-fold-search)
    (unless content (setq content ""))
    (dolist (pattern change-list content)
      (setq content (replace-regexp-in-string (car pattern)
                                              (cdr pattern)
                                              content)))))

(defun bibtex-autokey-get-names ()
  "Get contents of the name field of the current entry.
Do some modifications based on `bibtex-autokey-name-change-strings'
and return results as a list."
  (let ((case-fold-search t))
    (mapcar 'bibtex-autokey-demangle-name
            (split-string (bibtex-autokey-get-field
                           "author\\|editor"
                           bibtex-autokey-name-change-strings)
                          "[ \t\n]+and[ \t\n]+"))))

(defun bibtex-autokey-demangle-name (fullname)
  "Get the last part from a well-formed name and perform abbreviations."
  (let* (case-fold-search
         (name (cond ((string-match "\\([A-Z][^, ]*\\)[^,]*," fullname)
                      ;; Name is of the form "von Last, First" or
                      ;; "von Last, Jr, First"
                      ;; --> Take the first capital part before the comma
                      (match-string 1 fullname))
                     ((string-match "\\([^, ]*\\)," fullname)
                      ;; Strange name: we have a comma, but nothing capital
                      ;; So we accept even lowercase names
                      (match-string 1 fullname))
                     ((string-match "\\(\\<[a-z][^ ]* +\\)+\\([A-Z][^ ]*\\)"
                                    fullname)
                      ;; name is of the form "First von Last", "von Last",
                      ;; "First von von Last", or "d'Last"
                      ;; --> take the first capital part after the "von" parts
                      (match-string 2 fullname))
                     ((string-match "\\([^ ]+\\) *\\'" fullname)
                      ;; name is of the form "First Middle Last" or "Last"
                      ;; --> take the last token
                      (match-string 1 fullname))
                     (t (error "Name `%s' is incorrectly formed" fullname)))))
    (bibtex-autokey-abbrev
     (funcall bibtex-autokey-name-case-convert name)
     bibtex-autokey-name-length)))

(defun bibtex-autokey-get-title ()
  "Get title field contents up to a terminator."
  (let ((titlestring
         (bibtex-autokey-get-field "title"
                                   bibtex-autokey-titleword-change-strings)))
    ;; ignore everything past a terminator
    (let ((case-fold-search t))
      (dolist (terminator bibtex-autokey-title-terminators)
        (if (string-match terminator titlestring)
            (setq titlestring (substring titlestring 0 (match-beginning 0))))))
    ;; gather words from titlestring into a list. Ignore
    ;; specific words and use only a specific amount of words.
    (let (case-fold-search titlewords titlewords-extra titleword end-match
                           (counter 0))
      (while (and (or (not (numberp bibtex-autokey-titlewords))
                      (< counter (+ bibtex-autokey-titlewords
                                    bibtex-autokey-titlewords-stretch)))
                  (string-match "\\b\\w+" titlestring))
        (setq end-match (match-end 0)
              titleword (substring titlestring
                                   (match-beginning 0) end-match))
        (unless (bibtex-member-of-regexp titleword
                                         bibtex-autokey-titleword-ignore)
          (setq titleword
                (funcall bibtex-autokey-titleword-case-convert titleword))
          (if (or (not (numberp bibtex-autokey-titlewords))
                  (< counter bibtex-autokey-titlewords))
              (setq titlewords (append titlewords (list titleword)))
            (setq titlewords-extra
                  (append titlewords-extra (list titleword))))
          (setq counter (1+ counter)))
        (setq titlestring (substring titlestring end-match)))
      (unless (string-match "\\b\\w+" titlestring)
        (setq titlewords (append titlewords titlewords-extra)))
      (mapcar 'bibtex-autokey-demangle-title titlewords))))

(defun bibtex-autokey-demangle-title (titleword)
  "Do some abbreviations on TITLEWORD.
The rules are defined in `bibtex-autokey-titleword-abbrevs'
and `bibtex-autokey-titleword-length'."
  (let ((abbrev (bibtex-assoc-of-regexp
                 titleword bibtex-autokey-titleword-abbrevs)))
    (if abbrev
        (cdr abbrev)
      (bibtex-autokey-abbrev titleword
                             bibtex-autokey-titleword-length))))

(defun bibtex-generate-autokey ()
  "Generate automatically a key from the author/editor and the title field.
This will only work for entries where each field begins on a separate line.
The generation algorithm works as follows:
 1. Use the value of `bibtex-autokey-prefix-string' as a prefix.
 2. If there is a non-empty author (preferred) or editor field,
    use it as the name part of the key.
 3. Change any substring found in
    `bibtex-autokey-name-change-strings' to the corresponding new
    one (see documentation of this variable for further detail).
 4. For every of at least first `bibtex-autokey-names' names in
    the name field, determine the last name. If there are maximal
    `bibtex-autokey-names' + `bibtex-autokey-names-stretch'
    names, all names are used.
 5. From every last name, take at least `bibtex-autokey-name-length'
    characters (abort only after a consonant or at a word end).
 6. Convert all last names according to the conversion function
    `bibtex-autokey-name-case-convert'.
 7. Build the name part of the key by concatenating all
    abbreviated last names with the string
    `bibtex-autokey-name-separator' between any two. If there are
    more names than are used in the name part, prepend the string
    contained in `bibtex-autokey-additional-names'.
 8. Build the year part of the key by truncating the contents of
    the year field to the rightmost `bibtex-autokey-year-length'
    digits (useful values are 2 and 4). If the year field (or any
    other field required to generate the key) is absent, but the entry
    has a valid crossref field and the variable
    `bibtex-autokey-use-crossref' is non-nil, use the field of the
    crossreferenced entry instead.
 9. For the title part of the key change the contents of the
    title field of the entry according to
    `bibtex-autokey-titleword-change-strings' to the
    corresponding new one (see documentation of this variable for
    further detail).
10. Abbreviate the result to the string up to (but not including)
    the first occurrence of a regexp matched by the items of
    `bibtex-autokey-title-terminators' and delete those words which
    appear in `bibtex-autokey-titleword-ignore'.
    Build the title part of the key by using at least the first
    `bibtex-autokey-titlewords' words from this
    abbreviated title. If the abbreviated title ends after
    maximal `bibtex-autokey-titlewords' +
    `bibtex-autokey-titlewords-stretch' words, all
    words from the abbreviated title are used.
11. Convert all used titlewords according to the conversion function
    `bibtex-autokey-titleword-case-convert'.
12. For every used title word that appears in
    `bibtex-autokey-titleword-abbrevs' use the corresponding
    abbreviation (see documentation of this variable for further
    detail).
13. From every title word not generated by an abbreviation, take
    at least `bibtex-autokey-titleword-length' characters (abort
    only after a consonant or at a word end).
14. Build the title part of the key by concatenating all
    abbreviated title words with the string
    `bibtex-autokey-titleword-separator' between any two.
15. At least, to get the key, concatenate
    `bibtex-autokey-prefix-string', the name part, the year part
    and the title part with `bibtex-autokey-name-year-separator'
    between the name part and the year part if both are non-empty
    and `bibtex-autokey-year-title-separator' between the year
    part and the title part if both are non-empty. If the year
    part is empty, but not the other two parts,
    `bibtex-autokey-year-title-separator' is used as well.
16. If the value of `bibtex-autokey-before-presentation-function'
    is non-nil, it must be a function taking one argument. This
    function is then called with the generated key as the
    argument. The return value of this function (a string) is
    used as the key.
17. If the value of `bibtex-autokey-edit-before-use' is non-nil,
    the key is then presented in the minibuffer to the user,
    where it can be edited.  The key given by the user is then
    used."
  (let* ((name-etal "")
         (namelist
          (let ((nl (bibtex-autokey-get-names))
                nnl)
            (if (or (not (numberp bibtex-autokey-names))
                    (<= (length nl)
                        (+ bibtex-autokey-names
                           bibtex-autokey-names-stretch)))
                nl
              (setq name-etal bibtex-autokey-additional-names)
              (while (< (length nnl) bibtex-autokey-names)
                (setq nnl (append nnl (list (car nl)))
                      nl (cdr nl)))
              nnl)))
         (namepart (concat (mapconcat 'identity
                                      namelist
                                      bibtex-autokey-name-separator)
                           name-etal))
         (yearfield (bibtex-autokey-get-field "year"))
         (yearpart (if (equal yearfield "")
                       ""
                     (substring yearfield
                                (- (length yearfield)
                                   bibtex-autokey-year-length))))
         (titlepart (mapconcat 'identity
                               (bibtex-autokey-get-title)
                               bibtex-autokey-titleword-separator))
         (autokey (concat bibtex-autokey-prefix-string
                          namepart
                          (unless (or (equal namepart "")
                                      (equal yearpart ""))
                            bibtex-autokey-name-year-separator)
                          yearpart
                          (unless (or (and (equal namepart "")
                                           (equal yearpart ""))
                                      (equal titlepart ""))
                            bibtex-autokey-year-title-separator)
                          titlepart)))
    (if bibtex-autokey-before-presentation-function
        (funcall bibtex-autokey-before-presentation-function autokey)
      autokey)))


(defun bibtex-parse-keys (&optional add abortable verbose)
  "Set `bibtex-reference-keys' to the keys used in the whole buffer.
The buffer might possibly be restricted.
Find both entry keys and crossref entries.
If ADD is non-nil add the new keys to `bibtex-reference-keys' instead of
simply resetting it. If ADD is an alist of keys, also add ADD to
`bibtex-reference-keys'. If ABORTABLE is non-nil abort on user
input. If VERBOSE is non-nil gives messages about progress.
Return alist of keys if parsing was completed, `aborted' otherwise."
  (let ((reference-keys (if (and add
                                 (listp bibtex-reference-keys))
                            bibtex-reference-keys)))
    (if (listp add)
        (dolist (key add)
          (unless (assoc (car key) reference-keys)
                      (push key reference-keys))))
    (save-excursion
      (save-match-data
        (if verbose
            (bibtex-progress-message
             (concat (buffer-name) ": parsing reference keys")))
        (catch 'userkey
          (goto-char (point-min))
          (if bibtex-parse-keys-fast
              (let ((case-fold-search t)
                    (re (concat bibtex-entry-head "\\|"
                                ",[ \t\n]*crossref[ \t\n]*=[ \t\n]*"
                                "\\(\"[^\"]*\"\\|{[^}]*}\\)[ \t\n]*[,})]")))
                (while (re-search-forward re nil t)
                  (if (and abortable (input-pending-p))
                      ;; user has aborted by typing a key --> return `aborted'
                      (throw 'userkey 'aborted))
                  (let ((key (cond ((match-end 3)
                                    ;; This is a crossref.
                                    (buffer-substring-no-properties
                                     (1+ (match-beginning 3)) (1- (match-end 3))))
                                   ((assoc-ignore-case (bibtex-type-in-head)
                                                       bibtex-entry-field-alist)
                                    ;; This is an entry.
                                    (match-string-no-properties bibtex-key-in-head)))))
                    (if (and (stringp key)
                             (not (assoc key reference-keys)))
                      (push (list key) reference-keys)))))

            (let (;; ignore @String entries because they are handled
                  ;; separately by bibtex-parse-strings
                  (bibtex-sort-ignore-string-entries t)
                  crossref-key bounds)
              (bibtex-map-entries
               (lambda (key beg end)
                 (if (and abortable
                          (input-pending-p))
                     ;; user has aborted by typing a key --> return `aborted'
                     (throw 'userkey 'aborted))
                 (if verbose (bibtex-progress-message))
                 (unless (assoc key reference-keys)
                   (push (list key) reference-keys))
                 (if (and (setq bounds (bibtex-search-forward-field "crossref" end))
                          (setq crossref-key (bibtex-text-in-field-bounds bounds t))
                          (not (assoc crossref-key reference-keys)))
                     (push (list crossref-key) reference-keys))))))

          (if verbose
              (bibtex-progress-message 'done))
          ;; successful operation --> return `bibtex-reference-keys'
          (setq bibtex-reference-keys reference-keys))))))

(defun bibtex-parse-strings (&optional add abortable)
  "Set `bibtex-strings' to the string definitions in the whole buffer.
The buffer might possibly be restricted.
If ADD is non-nil add the new strings to `bibtex-strings' instead of
simply resetting it. If ADD is an alist of strings, also add ADD to
`bibtex-strings'. If ABORTABLE is non-nil abort on user input.
Return alist of strings if parsing was completed, `aborted' otherwise."
  (save-excursion
    (save-match-data
      (goto-char (point-min))
      (let ((strings (if (and add
                              (listp bibtex-strings))
                         bibtex-strings))
            bounds key)
        (if (listp add)
            (dolist (string add)
              (unless (assoc (car string) strings)
                (push string strings))))
        (catch 'userkey
          (while (setq bounds (bibtex-search-forward-string))
            (if (and abortable
                     (input-pending-p))
                ;; user has aborted by typing a key --> return `aborted'
                (throw 'userkey 'aborted))
            (setq key (bibtex-reference-key-in-string bounds))
            (if (not (assoc-ignore-case key strings))
                (push (cons key (bibtex-text-in-string bounds t))
                      strings))
            (goto-char (bibtex-end-of-text-in-string bounds)))
          ;; successful operation --> return `bibtex-strings'
          (setq bibtex-strings strings))))))

(defun bibtex-string-files-init ()
  "Return initialization for `bibtex-strings'.
Use `bibtex-predefined-strings' and bib files `bibtex-string-files'."
  (save-match-data
    ;; collect pathnames
    (let ((dirlist (split-string (or bibtex-string-file-path ".")
                                 ":+"))
          (case-fold-search)
          compl)
      (dolist (filename bibtex-string-files)
        (unless (string-match "\\.bib\\'" filename)
          (setq filename (concat filename ".bib")))
        ;; test filenames
        (let (fullfilename bounds found)
          (dolist (dir dirlist)
            (when (file-readable-p
                   (setq fullfilename (expand-file-name filename dir)))
              ;; file was found
              (with-temp-buffer
                (insert-file-contents fullfilename)
                (goto-char (point-min))
                (while (setq bounds (bibtex-search-forward-string))
                  (push (cons (bibtex-reference-key-in-string bounds)
                              (bibtex-text-in-string bounds t))
                        compl)
                  (goto-char (bibtex-end-of-string bounds))))
              (setq found t)))
          (unless found
            (error "File %s not in paths defined via bibtex-string-file-path"
                   filename))))
      (append bibtex-predefined-strings (nreverse compl)))))

(defun bibtex-parse-buffers-stealthily ()
  "Called by `bibtex-run-with-idle-timer'. Whenever emacs has been idle
for `bibtex-parse-keys-timeout' seconds, all BibTeX buffers (starting
with the current) are parsed."
  (save-excursion
    (let ((buffers (buffer-list))
          (strings-init (bibtex-string-files-init)))
      (while (and buffers (not (input-pending-p)))
        (set-buffer (car buffers))
        (if (and (eq major-mode 'bibtex-mode)
                 (not (eq (buffer-modified-tick)
                          bibtex-buffer-last-parsed-tick)))
            (save-restriction
              (widen)
              ;; Output no progress messages in bibtex-parse-keys
              ;; because when in y-or-n-p that can hide the question.
              (if (and (listp (bibtex-parse-keys nil t))
                       ;; update bibtex-strings
                       (listp (bibtex-parse-strings strings-init t)))

                  ;; remember that parsing was successful
                  (setq bibtex-buffer-last-parsed-tick (buffer-modified-tick)))))
        (setq buffers (cdr buffers))))))

(defun bibtex-complete-internal (completions)
  "Complete word fragment before point to longest prefix of one
string defined in list COMPLETIONS.  If point is not after the part
of a word, all strings are listed. Return completion."
  (let* ((case-fold-search t)
         (beg (save-excursion
                (re-search-backward "[ \t{\"]")
                (forward-char)
                (point)))
         (end (point))
         (part-of-word (buffer-substring-no-properties beg end))
         (completion (try-completion part-of-word completions)))
    (cond ((not completion)
           (error "Can't find completion for `%s'" part-of-word))
          ((eq completion t)
           part-of-word)
          ((not (string= part-of-word completion))
           (delete-region beg end)
           (insert completion)
           completion)
          (t
           (message "Making completion list...")
           (with-output-to-temp-buffer "*Completions*"
             (display-completion-list (all-completions part-of-word
                                                       completions)))
           (message "Making completion list...done")
           nil))))

(defun bibtex-complete-string-cleanup (str)
  "Cleanup after inserting string STR.
Remove enclosing field delimiters for string STR. Display message with
expansion of STR."
  (let ((pair (assoc str bibtex-strings)))
    (when pair
      (if (cdr pair)
          (message "Abbreviation for `%s'" (cdr pair)))
      (save-excursion
        (bibtex-inside-field)
        (let ((bounds (bibtex-enclosing-field)))
          (goto-char (bibtex-start-of-text-in-field bounds))
          (let ((boundaries (bibtex-parse-field-string)))
            (if (and boundaries
                     (equal (cdr boundaries)
                            (bibtex-end-of-text-in-field bounds)))
                (bibtex-remove-delimiters))))))))

(defun bibtex-choose-completion-string (choice buffer mini-p base-size)
  ;; Code borrowed from choose-completion-string:
  ;; We must duplicate the code from choose-completion-string
  ;; because it runs the hook choose-completion-string-functions
  ;; before it inserts the completion. But we want to do something
  ;; after the completion has been inserted.
  ;;
  ;; Insert the completion into the buffer where it was requested.
  (set-buffer buffer)
  (if base-size
      (delete-region (+ base-size (point-min))
                     (point))
    ;; Delete the longest partial match for CHOICE
    ;; that can be found before point.
   (choose-completion-delete-max-match choice))
  (insert choice)
  (remove-text-properties (- (point) (length choice)) (point)
                          '(mouse-face nil))
  ;; Update point in the window that BUFFER is showing in.
  (let ((window (get-buffer-window buffer t)))
    (set-window-point window (point))))

(defun bibtex-pop (arg direction)
  "Generic function used by `bibtex-pop-previous' and `bibtex-pop-next'."
  (let (bibtex-help-message)
    (bibtex-find-text nil))
  (save-excursion
    ;; parse current field
    (bibtex-inside-field)
    (let* ((case-fold-search t)
           (bounds (bibtex-enclosing-field))
           (start-old-text (bibtex-start-of-text-in-field bounds))
           (stop-old-text (bibtex-end-of-text-in-field bounds))
           (start-name (bibtex-start-of-name-in-field bounds))
           (stop-name (bibtex-end-of-name-in-field bounds))
           ;; construct regexp for field with same name as this one,
           ;; ignoring possible OPT's or ALT's
           (field-name (progn
                         (goto-char start-name)
                         (buffer-substring-no-properties
                          (if (looking-at "\\(OPT\\)\\|\\(ALT\\)")
                              (match-end 0)
                            (point))
                          stop-name))))
      ;; if executed several times in a row, start each search where
      ;; the last one was finished
      (unless (eq last-command 'bibtex-pop)
        (bibtex-enclosing-entry-maybe-empty-head)
        (setq bibtex-pop-previous-search-point (match-beginning 0)
              bibtex-pop-next-search-point (point)))
      (if (eq direction 'previous)
          (goto-char bibtex-pop-previous-search-point)
        (goto-char bibtex-pop-next-search-point))
      ;; Now search for arg'th previous/next similar field
      (let (bounds failure new-text)
        (while (and (not failure)
                    (> arg 0))
          (cond ((eq direction 'previous)
                 (if (setq bounds (bibtex-search-backward-field field-name))
                     (goto-char (bibtex-start-of-field bounds))
                   (setq failure t)))
                ((eq direction 'next)
                 (if (setq bounds (bibtex-search-forward-field field-name))
                     (goto-char (bibtex-end-of-field bounds))
                   (setq failure t))))
          (setq arg (- arg 1)))
        (if failure
            (error "No %s matching BibTeX field"
                   (if (eq direction 'previous) "previous" "next"))
          ;; Found a matching field. Remember boundaries.
          (setq bibtex-pop-previous-search-point (bibtex-start-of-field bounds)
                bibtex-pop-next-search-point (bibtex-end-of-field bounds)
                new-text (bibtex-text-in-field-bounds bounds))
          (bibtex-flash-head)
          ;; Go back to where we started, delete old text, and pop new.
          (goto-char stop-old-text)
          (delete-region start-old-text stop-old-text)
          (insert new-text)))))
  (let (bibtex-help-message)
    (bibtex-find-text nil))
  (setq this-command 'bibtex-pop))

(defsubst bibtex-read-key (prompt &optional key)
  "Read BibTeX key from minibuffer using PROMPT and default KEY."
  (completing-read prompt bibtex-reference-keys
                   nil nil key 'bibtex-key-history))

;; Interactive Functions:

;;;###autoload
(defun bibtex-mode ()
  "Major mode for editing BibTeX files.

General information on working with BibTeX mode:

You should use commands such as \\[bibtex-Book] to get a template for a
specific entry. You should then fill in all desired fields using
\\[bibtex-next-field] to jump from field to field. After having filled
in all desired fields in the entry, you should clean the new entry
with the command \\[bibtex-clean-entry].

Some features of BibTeX mode are available only by setting the variable
`bibtex-maintain-sorted-entries' to non-nil. However, then BibTeX mode will
work only with buffers containing valid (syntactical correct) entries
and with entries being sorted. This is usually the case, if you have
created a buffer completely with BibTeX mode and finished every new
entry with \\[bibtex-clean-entry].

For third party BibTeX files, call the function `bibtex-convert-alien'
to fully take advantage of all features of BibTeX mode.


Special information:

A command such as \\[bibtex-Book] will outline the fields for a BibTeX book entry.

The optional fields start with the string OPT, and are thus ignored by BibTeX.
Alternatives from which only one is required start with the string ALT.
The OPT or ALT string may be removed from a field with \\[bibtex-remove-OPT-or-ALT].
\\[bibtex-make-field] inserts a new field after the current one.
\\[bibtex-kill-field] kills the current field entirely.
\\[bibtex-yank] yanks the last recently killed field after the current field.
\\[bibtex-remove-delimiters] removes the double-quotes or braces around the text of the current field.
 \\[bibtex-empty-field] replaces the text of the current field with the default \"\" or {}.

The command \\[bibtex-clean-entry] cleans the current entry, i.e. it removes OPT/ALT
from all non-empty optional or alternative fields, checks that no required
fields are empty, and does some formatting dependent on the value of
`bibtex-entry-format'.
Note: some functions in BibTeX mode depend on entries being in a special
format (all fields beginning on separate lines), so it is usually a bad
idea to remove `realign' from `bibtex-entry-format'.

Use \\[bibtex-find-text] to position the cursor at the end of the current field.
Use \\[bibtex-next-field] to move to end of the next field.

The following may be of interest as well:

  Functions:
    `bibtex-entry'
    `bibtex-kill-entry'
    `bibtex-yank-pop'
    `bibtex-pop-previous'
    `bibtex-pop-next'
    `bibtex-complete'
    `bibtex-print-help-message'
    `bibtex-generate-autokey'
    `bibtex-beginning-of-entry'
    `bibtex-end-of-entry'
    `bibtex-reposition-window'
    `bibtex-mark-entry'
    `bibtex-ispell-abstract'
    `bibtex-ispell-entry'
    `bibtex-narrow-to-entry'
    `bibtex-sort-buffer'
    `bibtex-validate'
    `bibtex-count'
    `bibtex-fill-entry'
    `bibtex-reformat'
    `bibtex-convert-alien'

  Variables:
    `bibtex-field-delimiters'
    `bibtex-include-OPTcrossref'
    `bibtex-include-OPTkey'
    `bibtex-user-optional-fields'
    `bibtex-entry-format'
    `bibtex-sort-ignore-string-entries'
    `bibtex-maintain-sorted-entries'
    `bibtex-entry-field-alist'
    `bibtex-predefined-strings'
    `bibtex-string-files'

---------------------------------------------------------
Entry to BibTeX mode calls the value of `bibtex-mode-hook' if that value is
non-nil.

\\{bibtex-mode-map}"
  (interactive)
  (kill-all-local-variables)
  (use-local-map bibtex-mode-map)
  (setq major-mode 'bibtex-mode)
  (setq mode-name "BibTeX")
  (set-syntax-table bibtex-mode-syntax-table)
  (make-local-variable 'bibtex-buffer-last-parsed-tick)
  ;; Install stealthy parse function if not already installed
  (unless bibtex-parse-idle-timer
    (setq bibtex-parse-idle-timer (bibtex-run-with-idle-timer
                                   bibtex-parse-keys-timeout t
                                   'bibtex-parse-buffers-stealthily)))
  (set (make-local-variable 'paragraph-start) "[ \f\n\t]*$")
  (set (make-local-variable 'comment-start) bibtex-comment-start)
  (set (make-local-variable 'comment-start-skip)
       (concat (regexp-quote bibtex-comment-start) "\\>[ \t]*"))
  (set (make-local-variable 'comment-column) 0)
  (set (make-local-variable 'defun-prompt-regexp) "^[ \t]*@[a-zA-Z0-9]+[ \t]*")
  (set (make-local-variable 'outline-regexp) "[ \t]*@")
  (set (make-local-variable 'fill-paragraph-function) 'bibtex-fill-field)
  (set (make-local-variable 'fill-prefix) (make-string (+ bibtex-entry-offset
                                                         bibtex-contline-indentation)
                                                      ? ))
  (set (make-local-variable 'font-lock-defaults)
       '(bibtex-font-lock-keywords
         nil t ((?$ . "\"")
                ;; Mathematical expressions should be fontified as strings
                (?\" . ".")
                ;; Quotes are field delimiters and quote-delimited
                ;; entries should be fontified in the same way as
                ;; brace-delimited ones
                )
         nil
         (font-lock-syntactic-keywords . bibtex-font-lock-syntactic-keywords)
	 (font-lock-mark-block-function
	  . (lambda ()
         (set-mark (bibtex-end-of-entry))
	      (bibtex-beginning-of-entry)))))
  (setq imenu-generic-expression
        (list (list nil bibtex-entry-head bibtex-key-in-head)))
  (make-local-variable 'choose-completion-string-functions)
  (setq imenu-case-fold-search t)
  ;; XEmacs needs easy-menu-add, Emacs does not care
  (easy-menu-add bibtex-edit-menu)
  (easy-menu-add bibtex-entry-menu)
  (run-hooks 'bibtex-mode-hook))

(defun bibtex-entry (entry-type)
  "Insert a new BibTeX entry.
After insertion it calls the functions in `bibtex-add-entry-hook'."
  (interactive (let* ((completion-ignore-case t)
                      (e-t (completing-read
                            "Entry Type: "
                            bibtex-entry-field-alist
                            nil t nil 'bibtex-entry-type-history)))
                 (list e-t)))
  (let* (required optional
         (key (if bibtex-maintain-sorted-entries
                  (bibtex-read-key (format "%s key: " entry-type))))
         (e (assoc-ignore-case entry-type bibtex-entry-field-alist))
         (r-n-o (elt e 1))
         (c-ref (elt e 2)))
    (if (not e)
        (error "Bibtex entry type %s not defined" entry-type))
    (if (and (member entry-type bibtex-include-OPTcrossref)
             c-ref)
        (setq required (elt c-ref 0)
              optional (elt c-ref 1))
      (setq required (elt r-n-o 0)
            optional (elt r-n-o 1)))
    (unless (bibtex-prepare-new-entry (list key nil entry-type))
      (error "Entry with key `%s' already exists" key))
    (indent-to-column bibtex-entry-offset)
    (insert "@" entry-type (bibtex-entry-left-delimiter))
    (if key
        (insert key))
    (save-excursion
      (mapcar 'bibtex-make-field required)
      (if (member entry-type bibtex-include-OPTcrossref)
          (bibtex-make-optional-field '("crossref")))
      (if bibtex-include-OPTkey
          (if (or (stringp bibtex-include-OPTkey)
                  (fboundp bibtex-include-OPTkey))
              (bibtex-make-optional-field
               (list "key" nil bibtex-include-OPTkey))
            (bibtex-make-optional-field '("key"))))
      (mapcar 'bibtex-make-optional-field optional)
      (mapcar 'bibtex-make-optional-field bibtex-user-optional-fields)
      (if bibtex-comma-after-last-field
          (insert ","))
      (insert "\n")
      (indent-to-column bibtex-entry-offset)
      (insert (bibtex-entry-right-delimiter) "\n\n"))
    (bibtex-next-field t)
    (if (member-ignore-case entry-type bibtex-autofill-types)
	(bibtex-autofill-entry))
    (run-hooks 'bibtex-add-entry-hook)))

(defun bibtex-parse-entry ()
  "Parse entry at point, return an alist.
The alist elements have the form (FIELD . TEXT), where FIELD can also be
the special strings \"=type=\" and \"=key=\"."
  (let (alist bounds)
    (when (looking-at bibtex-entry-head)
      (push (cons "=type=" (match-string bibtex-type-in-head)) alist)
      (push (cons "=key=" (match-string bibtex-key-in-head)) alist)
      (goto-char (match-end bibtex-key-in-head))
      (while (setq bounds (bibtex-parse-field bibtex-field-name))
	(push (cons (bibtex-name-in-field bounds)
		    (bibtex-text-in-field-bounds bounds))
	      alist)
	(goto-char (bibtex-end-of-field bounds))))
    alist))

(defun bibtex-autofill-entry ()
  "Try to fill fields based on surrounding entries."
  (interactive)
  (undo-boundary)	;So you can easily undo it, if it didn't work right.
  (bibtex-beginning-of-entry)
  (when (looking-at bibtex-entry-head)
    (let ((type (match-string bibtex-type-in-head))
	  (key (match-string bibtex-key-in-head))
	  (key-end (match-end bibtex-key-in-head))
          (case-fold-search t)
	  tmp other-key other bounds)
      ;; The fields we want to change start right after the key.
      (goto-char key-end)
      ;; First see whether to use the previous or the next entry
      ;; for "inspiration".
      (save-excursion
	(goto-char (1- (match-beginning 0)))
	(bibtex-beginning-of-entry)
	(when (and
	       (looking-at bibtex-entry-head)
	       (equal type (match-string bibtex-type-in-head))
	       ;; In case we found ourselves :-(
	       (not (equal key (setq tmp (match-string bibtex-key-in-head)))))
	  (setq other-key tmp)
	  (setq other (point))))
      (save-excursion
	(bibtex-end-of-entry)
	(bibtex-skip-to-valid-entry)
	(when (and
	       (looking-at bibtex-entry-head)
	       (equal type (match-string bibtex-type-in-head))
	       ;; In case we found ourselves :-(
	       (not (equal key (setq tmp (match-string bibtex-key-in-head))))
	       (or (not other-key)
		   ;; Check which is the best match.
		   (< (length (try-completion "" (list key other-key)))
		      (length (try-completion "" (list key tmp))))))
	  (setq other-key tmp)
	  (setq other (point))))
      ;; Then fill the new entry's fields with the chosen other entry.
      (when other
	(setq other (save-excursion (goto-char other) (bibtex-parse-entry)))
	(setq key-end (point))	    ;In case parse-entry changed the buffer.
	(while (setq bounds (bibtex-parse-field bibtex-field-name))
	  (goto-char (bibtex-start-of-name-in-field bounds))
	  (let* ((name (buffer-substring
			(if (looking-at "ALT\\|OPT") (match-end 0) (point))
			(bibtex-end-of-name-in-field bounds)))
		 (text (assoc-ignore-case name other)))
	    (goto-char (bibtex-start-of-text-in-field bounds))
	    (if (not (and (looking-at bibtex-empty-field-re) text))
		(goto-char (bibtex-end-of-field bounds))
	      (delete-region (point) (bibtex-end-of-text-in-field bounds))
	      (insert (cdr text)))))
	;; Finally try to update the text based on the difference between
	;; the two keys.
	(let* ((prefix (try-completion "" (list key other-key)))
	       ;; If the keys are foo91 and foo92, don't replace 1 for 2
	       ;; but 91 for 92 instead.
	       (_ (if (string-match "[0-9]+\\'" prefix)
		      (setq prefix (substring prefix 0 (match-beginning 0)))))
	       (suffix (substring key (length prefix)))
	       (other-suffix (substring other-key (length prefix))))
	  (while (re-search-backward (regexp-quote other-suffix) key-end 'move)
	    (replace-match suffix)))))))

(defun bibtex-print-help-message ()
  "Print helpful information about current field in current BibTeX entry."
  (interactive)
  (save-excursion
    (let* ((case-fold-search t)
           (bounds (bibtex-enclosing-field))
           (mb (bibtex-start-of-name-in-field bounds))
           (field-name (buffer-substring-no-properties
                        (if (progn (goto-char mb)
                                   (looking-at "OPT\\|ALT"))
                            (match-end 0) mb)
                        (bibtex-end-of-name-in-field bounds)))
           (entry-type (progn (re-search-backward
                               bibtex-entry-maybe-empty-head nil t)
                              (bibtex-type-in-head)))
           (entry-list (assoc-ignore-case entry-type
                                          bibtex-entry-field-alist))
           (c-r-list (elt entry-list 2))
           (req-opt-list (if (and (member entry-type
                                          bibtex-include-OPTcrossref)
                                  c-r-list)
                             c-r-list
                           (elt entry-list 1)))
           (list-of-entries (append (elt req-opt-list 0)
                                    (elt req-opt-list 1)
                                    bibtex-user-optional-fields
                                    (if (member entry-type
                                                bibtex-include-OPTcrossref)
                                        '(("crossref" "Reference key of the cross-referenced entry")))
                                    (if bibtex-include-OPTkey
                                        '(("key" "Used for reference key creation if author and editor fields are missing")))))
           (comment (assoc-ignore-case field-name list-of-entries)))
      (if comment
          (message (elt comment 1))
        (message "No comment available")))))

(defun bibtex-make-field (field &optional called-by-yank)
  "Make a field named FIELD in current BibTeX entry.
FIELD is either a string or a list of the form
\(FIELD-NAME COMMENT-STRING INIT ALTERNATIVE-FLAG) as in
`bibtex-entry-field-alist'."
  (interactive
   (list (let* ((entry-type
                 (save-excursion
                   (bibtex-enclosing-entry-maybe-empty-head)
                   (bibtex-type-in-head)))
                ;; "preliminary" completion list
                (fl (nth 1 (assoc-ignore-case
                            entry-type bibtex-entry-field-alist)))
                ;; "full" completion list
                (field-list (append (nth 0 fl)
                                    (nth 1 fl)
                                    bibtex-user-optional-fields
                                    (if (member entry-type
                                                bibtex-include-OPTcrossref)
                                        '(("crossref")))
                                    (if bibtex-include-OPTkey
                                        '(("key")))))
                (completion-ignore-case t))
           (completing-read "BibTeX field name: " field-list
                            nil nil nil bibtex-field-history))))
  (unless (consp field)
    (setq field (list field)))
  (if (or (interactive-p) called-by-yank)
      (let (bibtex-help-message)
        (bibtex-find-text nil t t)
        (if (looking-at "[}\"]")
            (forward-char))))
  (insert ",\n")
  (indent-to-column (+ bibtex-entry-offset bibtex-field-indentation))
  (if (nth 3 field) (insert "ALT"))
  (insert (car field) " ")
  (if bibtex-align-at-equal-sign
      (indent-to-column (+ bibtex-entry-offset
                           (- bibtex-text-indentation 2))))
  (insert "= ")
  (if (not bibtex-align-at-equal-sign)
      (indent-to-column (+ bibtex-entry-offset
                           bibtex-text-indentation)))
  (if (not called-by-yank) (insert (bibtex-field-left-delimiter)))
  (let ((init (nth 2 field)))
    (cond ((stringp init)
           (insert init))
          ((fboundp init)
           (insert (funcall init)))))
  (if (not called-by-yank) (insert (bibtex-field-right-delimiter)))
  (if (interactive-p)
      (forward-char -1)))

(defun bibtex-beginning-of-entry ()
  "Move to beginning of BibTeX entry (beginning of line).
If inside an entry, move to the beginning of it, otherwise move to the
beginning of the previous entry. If point is ahead of all BibTeX entries
move point to the beginning of buffer. Return the new location of point."
  (interactive)
  (skip-chars-forward " \t")
  (if (looking-at "@")
      (forward-char))
  (re-search-backward "^[ \t]*@" nil 'move)
  (point))

(defun bibtex-end-of-entry ()
  "Move to end of BibTeX entry (past the closing brace).
If inside an entry, move to the end of it, otherwise move to the end
of the previous entry. Do not move if ahead of first entry.
Return the new location of point."
  (interactive)
  (let ((case-fold-search t)
        (org (point))
        (pnt (bibtex-beginning-of-entry))
        err bounds)
    (cond ((looking-at bibtex-valid-entry-whitespace-re)
           (bibtex-search-entry t nil t)
           (unless (equal (match-beginning 0) pnt)
             (setq err t)))
          ((setq bounds (bibtex-parse-string))
           (goto-char (bibtex-end-of-string bounds)))
          ((looking-at "[ \t]*@[ \t]*preamble[ \t\n]*")
           (goto-char (match-end 0))
           (cond ((looking-at "(")
                  (unless (re-search-forward ")[ \t]*\n\n" nil 'move)
                    (setq err t)))
                 ((looking-at "{")
                  (unless (re-search-forward "}[ \t]*\n\n" nil 'move)
                    (setq err t)))
                 (t
                  (setq err t)))
           (unless err
             (goto-char (match-beginning 0))
             (forward-char)))
          (t
           (if (interactive-p)
               (message "Not on a known BibTeX entry."))
           (goto-char org)))
    (when err
      (goto-char pnt)
      (error "Syntactically incorrect BibTeX entry starts here")))
  (point))

(defun bibtex-reposition-window (&optional arg)
  "Make the current BibTeX entry visible.
Optional argument ARG is exactly as in `recenter'."
  (interactive "P")
  (save-excursion
    (goto-char
     (/ (+ (bibtex-beginning-of-entry) (bibtex-end-of-entry)) 2))
    (recenter arg)))

(defun bibtex-mark-entry ()
  "Put mark at beginning, point at end of current BibTeX entry."
  (interactive)
  (set-mark (bibtex-beginning-of-entry))
  (bibtex-end-of-entry))

(defun bibtex-count-entries (&optional count-string-entries)
  "Count number of entries in current buffer or region.
With prefix argument COUNT-STRING-ENTRIES it counts all entries,
otherwise it counts all except Strings.
If mark is active it counts entries in region, if not in whole buffer."
  (interactive "P")
  (let ((number 0)
        (bibtex-sort-ignore-string-entries
         (not count-string-entries)))
    (save-excursion
      (save-restriction
        (narrow-to-region (if (bibtex-mark-active)
                              (region-beginning)
                            (bibtex-beginning-of-first-entry))
                          (if (bibtex-mark-active)
                              (region-end)
                            (point-max)))
        (goto-char (point-min))
        (bibtex-map-entries (lambda (key beg end)
                              (setq number (1+ number))))))
    (message "%s contains %d entries."
             (if (bibtex-mark-active) "Region" "Buffer")
             number)))

(defun bibtex-ispell-entry ()
  "Spell whole BibTeX entry."
  (interactive)
  (ispell-region (save-excursion (bibtex-beginning-of-entry))
                 (save-excursion (bibtex-end-of-entry))))

(defun bibtex-ispell-abstract ()
  "Spell abstract of BibTeX entry."
  (interactive)
  (let ((bounds (save-excursion
                  (bibtex-beginning-of-entry)
                  (bibtex-search-forward-field "abstract" t))))
    (if bounds
        (ispell-region (bibtex-start-of-text-in-field bounds)
                       (bibtex-end-of-text-in-field bounds))
      (error "No abstract in entry"))))

(defun bibtex-narrow-to-entry ()
  "Narrow buffer to current BibTeX entry."
  (interactive)
  (save-excursion
    (widen)
    (narrow-to-region (bibtex-beginning-of-entry)
                      (bibtex-end-of-entry))))

(defun bibtex-entry-index ()
  "Return the index of the BibTeX entry at point. Move point.
The index is a list (KEY CROSSREF-KEY ENTRY-NAME) that is used for sorting
the entries of the BibTeX buffer. Return nil if no entry found."
  (let ((case-fold-search t))
    (if (re-search-forward bibtex-entry-maybe-empty-head nil t)
        (let ((key (bibtex-key-in-head))
              ;; all entry names should be downcase (for ease of comparison)
              (entry-name (downcase (bibtex-type-in-head))))
          ;; Don't search CROSSREF-KEY if we don't need it.
          (if (equal bibtex-maintain-sorted-entries 'crossref)
              (save-excursion
                (bibtex-beginning-of-entry)
                (let ((bounds (bibtex-search-forward-field
                               "\\(OPT\\)?crossref" t)))
                  (list key
                        (if bounds (bibtex-text-in-field-bounds bounds t))
                        entry-name))))
          (list key nil entry-name)))))

(defun bibtex-lessp (index1 index2)
  "Predicate for sorting BibTeX entries with indices INDEX1 and INDEX2.
Each index is a list (KEY CROSSREF-KEY ENTRY-NAME).
The predicate depends on the variable `bibtex-maintain-sorted-entries'."
  (cond ((not index1) (not index2)) ; indices can be nil
        ((not index2) nil)
        ((equal bibtex-maintain-sorted-entries 'crossref)
         (if (nth 1 index1)
             (if (nth 1 index2)
                 (or (string-lessp (nth 1 index1) (nth 1 index2))
                     (and (string-equal (nth 1 index1) (nth 1 index2))
                          (string-lessp (nth 0 index1) (nth 0 index2))))
               (not (string-lessp (nth 0 index2) (nth 1 index1))))
           (if (nth 1 index2)
               (string-lessp (nth 0 index1) (nth 1 index2))
             (string-lessp (nth 0 index1) (nth 0 index2)))))
        ((equal bibtex-maintain-sorted-entries 'entry-class)
         (let ((n1 (cdr (or (assoc (nth 2 index1) bibtex-sort-entry-class-alist)
                            (assoc 'catch-all bibtex-sort-entry-class-alist)
                            '(nil . 1000))))  ; if there is nothing else
               (n2 (cdr (or (assoc (nth 2 index2) bibtex-sort-entry-class-alist)
                            (assoc 'catch-all bibtex-sort-entry-class-alist)
                            '(nil . 1000))))) ; if there is nothing else
           (or (< n1 n2)
               (and (= n1 n2)
                    (string-lessp (car index1) (car index2))))))
        (t ; (equal bibtex-maintain-sorted-entries 'plain)
         (string-lessp (car index1) (car index2)))))

(defun bibtex-sort-buffer ()
  "Sort BibTeX buffer alphabetically by key.
The predicate for sorting is defined via `bibtex-maintain-sorted-entries'.
Text outside of BibTeX entries is not affected.  If
`bibtex-sort-ignore-string-entries' is non-nil, @String entries will be
ignored."
  (interactive)
  (unless bibtex-maintain-sorted-entries
    (error "You must choose a sorting scheme"))
  (save-restriction
    (narrow-to-region (bibtex-beginning-of-first-entry)
                      (save-excursion (goto-char (point-max))
                                      (bibtex-end-of-entry)))
    (bibtex-skip-to-valid-entry)
    (sort-subr nil
               'bibtex-skip-to-valid-entry ; NEXTREC function
               'bibtex-end-of-entry        ; ENDREC function
               'bibtex-entry-index         ; STARTKEY function
               nil                         ; ENDKEY function
               'bibtex-lessp)))            ; PREDICATE

(defun bibtex-find-crossref (crossref-key)
  "Move point to the beginning of BibTeX entry CROSSREF-KEY.
Return position of entry if CROSSREF-KEY is found and nil otherwise.
If position of current entry is after CROSSREF-KEY an error is signaled.
If called interactively, CROSSREF-KEY defaults to crossref key of current
entry."
  (interactive
   (let ((crossref-key
          (save-excursion
            (bibtex-beginning-of-entry)
            (let ((bounds (bibtex-search-forward-field "crossref" t)))
              (if bounds
                  (bibtex-text-in-field-bounds bounds t))))))
     (list (bibtex-read-key "Find crossref key: " crossref-key))))
  (let ((pos (save-excursion (bibtex-find-entry crossref-key))))
    (if (and pos (> (point) pos))
        (error "This entry must not follow the crossrefed entry!"))
    (goto-char pos)))

(defun bibtex-find-entry (key)
  "Move point to the beginning of BibTeX entry named KEY.
Return position of entry if KEY is found or nil if not found."
  (interactive (list (bibtex-read-key "Find key: ")))
  (let* (case-fold-search
         (pnt (save-excursion
                (goto-char (point-min))
                (if (re-search-forward (concat "^[ \t]*\\("
                                               bibtex-entry-type
                                               "\\)[ \t]*[({][ \t\n]*\\("
                                               (regexp-quote key)
                                               "\\)[ \t\n]*[,=]")
                                       nil t)
                    (match-beginning 0)))))
    (cond (pnt
           (goto-char pnt))
          ((interactive-p)
           (message "Key `%s' not found" key)))))

(defun bibtex-prepare-new-entry (index)
  "Prepare a new BibTeX entry with index INDEX.
INDEX is a list (KEY CROSSREF-KEY ENTRY-NAME).
Move point where the entry KEY should be placed.
If `bibtex-maintain-sorted-entries' is non-nil, perform a binary
search to look for place for KEY. This will fail if buffer is not in
sorted order, see \\[bibtex-validate].)
Return t if preparation was successful or nil if entry KEY already exists."
  (let ((key (nth 0 index))
        key-exist)
    (cond ((or (null key)
               (and (stringp key)
                    (string-equal key ""))
               (and (not (setq key-exist (bibtex-find-entry key)))
                    (not bibtex-maintain-sorted-entries)))
           (bibtex-move-outside-of-entry))
          ;; if key-exist is non-nil due to the previous cond clause
          ;; then point will be at beginning of entry named key.
          (key-exist)
          (t             ; bibtex-maintain-sorted-entries is non-nil
           (let* ((case-fold-search t)
                  (left (save-excursion (bibtex-beginning-of-first-entry)
                                        (bibtex-skip-to-valid-entry)
                                        (point)))
                  (right (save-excursion (bibtex-beginning-of-last-entry)
                                         (bibtex-end-of-entry)))
                  (found (if (>= left right) left))
                  actual-index new)
             (save-excursion
               ;; Binary search
               (while (not found)
                 (goto-char (/ (+ left right) 2))
                 (bibtex-skip-to-valid-entry t)
                 (setq actual-index (bibtex-entry-index))
                 (cond ((bibtex-lessp index actual-index)
                        (setq new (bibtex-beginning-of-entry))
                        (if (equal right new)
                            (setq found right)
                          (setq right new)))
                       (t
                        (bibtex-end-of-entry)
                        (bibtex-skip-to-valid-entry)
                        (setq new (point))
                        (if (equal left new)
                            (setq found right)
                          (setq left new))))))
             (goto-char found)
             (bibtex-beginning-of-entry)
             (setq actual-index (save-excursion (bibtex-entry-index)))
             (when (or (not actual-index)
                       (bibtex-lessp actual-index index))
               ;; buffer contains no valid entries or
               ;; greater than last entry --> append
               (bibtex-end-of-entry)
               (if (not (bobp))
                   (newline (forward-line 2)))
               (beginning-of-line)))))
    (unless key-exist t)))

(defun bibtex-validate (&optional test-thoroughly)
  "Validate if buffer or region is syntactically correct.
Only known entry types are checked, so you can put comments
outside of entries.
With optional argument TEST-THOROUGHLY non-nil it checks for absence of
required fields and questionable month fields as well.
If mark is active, validate current region, if not the whole buffer.
Returns t if test was successful, nil otherwise."
  (interactive "P")
  (let* ((case-fold-search t)
         error-list syntax-error)
    (save-excursion
      (save-restriction
        (narrow-to-region (if (bibtex-mark-active)
                              (region-beginning)
                            (bibtex-beginning-of-first-entry))
                          (if (bibtex-mark-active)
                              (region-end)
                            (point-max)))

        ;; looking if entries fit syntactical structure
        (goto-char (point-min))
        (bibtex-progress-message "Checking syntactical structure")
        (let (bibtex-sort-ignore-string-entries)
          (while (re-search-forward "^[ \t]*@" nil t)
            (bibtex-progress-message)
            (forward-char -1)
            (let ((pnt (point)))
              (if (not (looking-at bibtex-any-valid-entry-re))
                  (forward-char)
                (bibtex-skip-to-valid-entry)
                (if (equal (point) pnt)
                    (forward-char)
                  (goto-char pnt)
                  (push (list (bibtex-current-line)
                              "Syntax error (check esp. commas, braces, and quotes)")
                        error-list)
                  (forward-char))))))
        (bibtex-progress-message 'done)

        (if error-list
            (setq syntax-error t)
          ;; looking for correct sort order and duplicates (only if
          ;; there were no syntax errors)
          (if bibtex-maintain-sorted-entries
              (let (previous current)
                (goto-char (point-min))
                (bibtex-progress-message "Checking correct sort order")
                (bibtex-map-entries
                 (lambda (key beg end)
                   (bibtex-progress-message)
                   (goto-char beg)
                   (setq current (bibtex-entry-index))
                   (cond ((or (not previous)
                              (bibtex-lessp previous current))
                          (setq previous current))
                         ((string-equal (car previous) (car current))
                          (push (list (bibtex-current-line)
                                      "Duplicate key with previous")
                                error-list))
                         (t
                          (setq previous current)
                          (push (list (bibtex-current-line)
                                      "Entries out of order")
                                error-list)))))
                (bibtex-progress-message 'done)))

          (when test-thoroughly
            (goto-char (point-min))
            (bibtex-progress-message
             "Checking required fields and month fields")
            (let ((bibtex-sort-ignore-string-entries t)
                  (questionable-month
                   (regexp-opt (mapcar 'car bibtex-predefined-month-strings))))
              (bibtex-map-entries
               (lambda (key beg end)
                 (bibtex-progress-message)
                 (let* ((entry-list (progn
                                      (goto-char beg)
                                      (bibtex-search-entry nil end)
                                      (assoc-ignore-case (bibtex-type-in-head)
                                                         bibtex-entry-field-alist)))
                        (req (copy-sequence (elt (elt entry-list 1) 0)))
                        (creq (copy-sequence (elt (elt entry-list 2) 0)))
                        crossref-there bounds)
                   (goto-char beg)
                   (while (setq bounds (bibtex-search-forward-field
                                        bibtex-field-name end))
                     (goto-char (bibtex-start-of-text-in-field bounds))
                     (let ((field-name (downcase (bibtex-name-in-field bounds)))
                           case-fold-search)
                       (if (and (equal field-name "month")
                                (not (string-match questionable-month
                                                   (bibtex-text-in-field-bounds bounds))))
                           (push (list (bibtex-current-line)
                                       "Questionable month field")
                                 error-list))
                       (setq req (delete (assoc-ignore-case field-name req) req)
                             creq (delete (assoc-ignore-case field-name creq) creq))
                       (if (equal field-name "crossref")
                           (setq crossref-there t))))
                   (if crossref-there
                       (setq req creq))
                   (if (or (> (length req) 1)
                           (and (= (length req) 1)
                                (not (elt (car req) 3))))
                       ;; two (or more) fields missed or one field
                       ;; missed and this isn't flagged alternative
                       ;; (notice that this fails if there are more
                       ;; than two alternatives in a BibTeX entry,
                       ;; which isn't the case momentarily)
                       (push (list (save-excursion
                                     (bibtex-beginning-of-entry)
                                     (bibtex-current-line))
                                   (concat "Required field `" (caar req) "' missing"))
                             error-list))))))
            (bibtex-progress-message 'done)))))
    (if error-list
        (let ((bufnam (buffer-name))
              (dir default-directory))
          (setq error-list
                (sort error-list
                      (lambda (a b)
                        (< (car a) (car b)))))
          (let ((pop-up-windows t))
            (pop-to-buffer nil t))
          (switch-to-buffer
           (get-buffer-create "*BibTeX validation errors*") t)
          ;; don't use switch-to-buffer-other-window, since this
          ;; doesn't allow the second parameter NORECORD
          (setq default-directory dir)
          (toggle-read-only -1)
          (compilation-mode)
          (delete-region (point-min) (point-max))
          (goto-char (point-min))
          (insert "BibTeX mode command `bibtex-validate'\n"
                  (if syntax-error
                      "Maybe undetected errors due to syntax errors. Correct and validate again."
                    "")
                  "\n")
          (dolist (err error-list)
            (insert bufnam ":" (number-to-string (elt err 0))
                    ": " (elt err 1) "\n"))
          (compilation-parse-errors nil nil)
          (setq compilation-old-error-list compilation-error-list)
          ;; this is necessary to avoid reparsing of buffer if you
          ;; switch to compilation buffer and enter `compile-goto-error'
          (set-buffer-modified-p nil)
          (toggle-read-only 1)
          (goto-char (point-min))
          (other-window -1)
          ;; return nil
          nil)
      (if (bibtex-mark-active)
          (message "Region is syntactically correct")
        (message "Buffer is syntactically correct"))
      t)))

(defun bibtex-next-field (arg)
  "Find end of text of next BibTeX field; with ARG, to its beginning."
  (interactive "P")
  (bibtex-inside-field)
  (let ((start (point)))
    (condition-case ()
        (let ((bounds (bibtex-enclosing-field)))
          (goto-char (bibtex-end-of-field bounds))
          (forward-char 2))
      (error
       (goto-char start)
       (end-of-line)
       (forward-char))))
  (bibtex-find-text arg t))

(defun bibtex-find-text (arg &optional as-if-interactive no-error)
  "Go to end of text of current field; with ARG, go to beginning."
  (interactive "P")
  (bibtex-inside-field)
  (let ((bounds (bibtex-enclosing-field (or (interactive-p)
                                            as-if-interactive))))
    (if bounds
        (progn (if arg
                   (progn (goto-char (bibtex-start-of-text-in-field bounds))
                          (if (looking-at "[{\"]")
                              (forward-char)))
                 (goto-char (bibtex-end-of-text-in-field bounds))
                 (if (or (= (preceding-char) ?})
                         (= (preceding-char) ?\"))
                     (forward-char -1)))
               (if bibtex-help-message
                   (bibtex-print-help-message)))
      (beginning-of-line)
      (cond ((setq bounds (bibtex-parse-string))
             (goto-char (if arg
                            (bibtex-start-of-text-in-string bounds)
                          (bibtex-end-of-text-in-string bounds))))
            ((looking-at bibtex-entry-maybe-empty-head)
             (goto-char (if arg
                            (match-beginning bibtex-key-in-head)
                          (match-end 0))))
            (t
             (unless no-error
                 (error "Not on BibTeX field")))))))

(defun bibtex-remove-OPT-or-ALT ()
  "Remove the string starting optional/alternative fields.
Align text and go thereafter to end of text."
  (interactive)
  (bibtex-inside-field)
  (let ((case-fold-search t)
        (bounds (bibtex-enclosing-field)))
    (save-excursion
      (goto-char (bibtex-start-of-name-in-field bounds))
      (when (looking-at "OPT\\|ALT")
        (delete-region (match-beginning 0) (match-end 0))
        ;; make field non-OPT
        (search-forward "=")
        (forward-char -1)
        (delete-horizontal-space)
        (if bibtex-align-at-equal-sign
            (indent-to-column (- bibtex-text-indentation 2))
          (insert " "))
        (search-forward "=")
        (delete-horizontal-space)
        (if bibtex-align-at-equal-sign
            (insert " ")
          (indent-to-column bibtex-text-indentation))))
    (bibtex-inside-field)))

(defun bibtex-remove-delimiters ()
  "Remove \"\" or {} around string."
  (interactive)
  (save-excursion
    (bibtex-inside-field)
    (let ((bounds (bibtex-enclosing-field)))
      (goto-char (bibtex-start-of-text-in-field bounds))
      (delete-char 1)
      (goto-char (1- (bibtex-end-of-text-in-field bounds)))
      (delete-backward-char 1))))

(defun bibtex-kill-field (&optional copy-only)
  "Kill the entire enclosing BibTeX field.
With prefix arg COPY-ONLY, copy the current field to `bibtex-field-kill-ring',
but do not actually kill it."
  (interactive "P")
  (save-excursion
    (bibtex-inside-field)
    (let* ((case-fold-search t)
           (bounds (bibtex-enclosing-field))
           (end (bibtex-end-of-field bounds))
           (beg (bibtex-start-of-field bounds)))
      (goto-char end)
      (skip-chars-forward " \t\n,")
      (push (list 'field (bibtex-name-in-field bounds)
                  (bibtex-text-in-field-bounds bounds))
            bibtex-field-kill-ring)
      (if (> (length bibtex-field-kill-ring) bibtex-field-kill-ring-max)
          (setcdr (nthcdr (1- bibtex-field-kill-ring-max)
                          bibtex-field-kill-ring)
                  nil))
      (setq bibtex-field-kill-ring-yank-pointer bibtex-field-kill-ring)
      (unless copy-only
        (delete-region beg end))))
  (setq bibtex-last-kill-command 'field))

(defun bibtex-copy-field-as-kill ()
  (interactive)
  (bibtex-kill-field t))

(defun bibtex-kill-entry (&optional copy-only)
  "Kill the entire enclosing BibTeX entry.
With prefix arg COPY-ONLY the current entry to
`bibtex-entry-kill-ring', but do not actually kill it."
  (interactive "P")
  (save-excursion
    (let* ((case-fold-search t)
           (beg (bibtex-beginning-of-entry))
           (end (progn (bibtex-end-of-entry)
                       (if (re-search-forward
                            bibtex-entry-maybe-empty-head nil 'move)
                           (goto-char (match-beginning 0)))
                       (point))))
      (push (list 'entry (buffer-substring-no-properties beg end))
            bibtex-entry-kill-ring)
      (if (> (length bibtex-entry-kill-ring) bibtex-entry-kill-ring-max)
          (setcdr (nthcdr (1- bibtex-entry-kill-ring-max)
                          bibtex-entry-kill-ring)
                  nil))
    (setq bibtex-entry-kill-ring-yank-pointer bibtex-entry-kill-ring)
    (unless copy-only
      (delete-region beg end))))
  (setq bibtex-last-kill-command 'entry))

(defun bibtex-copy-entry-as-kill ()
  (interactive)
  (bibtex-kill-entry t))

(defun bibtex-yank (&optional n)
  "Reinsert the last BibTeX item.
More precisely, reinsert the field or entry killed or yanked most recently.
With argument N, reinsert the Nth most recently killed BibTeX item.
See also the command \\[bibtex-yank-pop]]."
  (interactive "*p")
  (bibtex-insert-current-kill (1- n))
  (setq this-command 'bibtex-yank))

(defun bibtex-yank-pop (n)
  "Replace just-yanked killed BibTeX item with a different.
This command is allowed only immediately after a `bibtex-yank' or a
`bibtex-yank-pop'.
At such a time, the region contains a reinserted previously killed
BibTeX item.  `bibtex-yank-pop' deletes that item and inserts in its
place a different killed BibTeX item.

With no argument, the previous kill is inserted.
With argument N, insert the Nth previous kill.
If N is negative, this is a more recent kill.

The sequence of kills wraps around, so that after the oldest one
comes the newest one."
  (interactive "*p")
  (if (not (eq last-command 'bibtex-yank))
      (error "Previous command was not a BibTeX yank"))
  (setq this-command 'bibtex-yank)
  (let ((inhibit-read-only t))
    (delete-region (point) (mark t))
    (bibtex-insert-current-kill n)))

(defun bibtex-empty-field ()
  "Delete the text part of the current field, replace with empty text."
  (interactive)
  (bibtex-inside-field)
  (let ((bounds (bibtex-enclosing-field)))
    (goto-char (bibtex-start-of-text-in-field bounds))
    (delete-region (point) (bibtex-end-of-text-in-field bounds))
    (insert (concat (bibtex-field-left-delimiter)
                    (bibtex-field-right-delimiter)) )
    (bibtex-find-text t)))

(defun bibtex-pop-previous (arg)
  "Replace text of current field with the similar field in previous entry.
With arg, goes up ARG entries.  Repeated, goes up so many times.  May be
intermixed with \\[bibtex-pop-next] (bibtex-pop-next)."
  (interactive "p")
  (bibtex-pop arg 'previous))

(defun bibtex-pop-next (arg)
  "Replace text of current field with the text of similar field in next entry.
With arg, goes down ARG entries.  Repeated, goes down so many times.  May be
intermixed with \\[bibtex-pop-previous] (bibtex-pop-previous)."
  (interactive "p")
  (bibtex-pop arg 'next))

(defun bibtex-clean-entry (&optional new-key called-by-reformat)
  "Finish editing the current BibTeX entry and clean it up.
Check that no required fields are empty and formats entry dependent
on the value of `bibtex-entry-format'.
If the reference key of the entry is empty or a prefix argument is given,
calculate a new reference key. (Note: this will only work if fields in entry
begin on separate lines prior to calling `bibtex-clean-entry' or if
'realign is contained in `bibtex-entry-format'.)
Don't call `bibtex-clean-entry' on @Preamble entries.
At end of the cleaning process, the functions in
`bibtex-clean-entry-hook' are called with region narrowed to entry."
  ;; Opt. arg called-by-reformat is t if bibtex-clean-entry
  ;; is called by bibtex-reformat
  (interactive "P")
  (let ((case-fold-search t)
        entry-type key)
    (bibtex-beginning-of-entry)
    (save-excursion
      (when (re-search-forward bibtex-entry-maybe-empty-head nil t)
        (setq entry-type (downcase (bibtex-type-in-head)))
        (setq key (bibtex-key-in-head))))
    ;; formatting
    (cond ((equal entry-type "preamble")
           ;; (bibtex-format-preamble)
           (error "No clean up of @Preamble entries"))
          ((equal entry-type "string"))
           ;; (bibtex-format-string)
          (t (bibtex-format-entry)))
    ;; set key
    (when (or new-key (not key))
      (setq key (bibtex-generate-autokey))
      (if bibtex-autokey-edit-before-use
          (setq key (bibtex-read-key "Key to use: " key)))
      (re-search-forward bibtex-entry-maybe-empty-head)
      (if (match-beginning bibtex-key-in-head)
          (delete-region (match-beginning bibtex-key-in-head)
                         (match-end bibtex-key-in-head)))
      (insert key))
    ;; sorting
    (let* ((start (bibtex-beginning-of-entry))
           (end (progn (bibtex-end-of-entry)
                       (if (re-search-forward
                            bibtex-entry-maybe-empty-head nil 'move)
                           (goto-char (match-beginning 0)))
                       (point)))
           (entry (buffer-substring start end))
           (index (progn (goto-char start)
                         (bibtex-entry-index))))
      (delete-region start end)
      (unless (prog1 (or called-by-reformat
                         (if (and bibtex-maintain-sorted-entries
                                  (not (and bibtex-sort-ignore-string-entries
                                            (equal entry-type "string"))))
                             (bibtex-prepare-new-entry index)
                           (not (bibtex-find-entry (car index)))))
                (insert entry)
                (forward-char -1)
                (bibtex-beginning-of-entry) ; moves backward
                (re-search-forward bibtex-entry-head))
        (error "New inserted entry yields duplicate key")))
    ;; final clean up
    (unless called-by-reformat
      (save-excursion
        (save-restriction
          (bibtex-narrow-to-entry)
          ;; Only update the list of keys if it has been built already.
          (cond ((equal entry-type "string")
                 (if (listp bibtex-strings) (bibtex-parse-strings t)))
                ((listp bibtex-reference-keys) (bibtex-parse-keys t)))
          (run-hooks 'bibtex-clean-entry-hook))))))

(defun bibtex-fill-field-bounds (bounds justify &optional move)
  "Fill BibTeX field delimited by BOUNDS.
If JUSTIFY is non-nil justify as well.
If optional arg MOVE is non-nil move point to end of field."
  (let ((end-field (copy-marker (bibtex-end-of-field bounds))))
    (goto-char (bibtex-start-of-field bounds))
    (if justify
        (progn
          (forward-char)
          (bibtex-delete-whitespace)
          (open-line 1)
          (forward-char)
          (indent-to-column (+ bibtex-entry-offset
                               bibtex-field-indentation))
          (re-search-forward "[ \t\n]*=" end-field)
          (replace-match "=")
          (forward-char -1)
          (if bibtex-align-at-equal-sign
              (indent-to-column
               (+ bibtex-entry-offset (- bibtex-text-indentation 2)))
            (insert " "))
          (forward-char)
          (bibtex-delete-whitespace)
          (if bibtex-align-at-equal-sign
              (insert " ")
            (indent-to-column bibtex-text-indentation)))
      (re-search-forward "[ \t\n]*=[ \t\n]*" end-field))
    (while (re-search-forward "[ \t\n]+" end-field 'move)
      (replace-match " "))
    (do-auto-fill)
    (if move (goto-char end-field))))

(defun bibtex-fill-field (&optional justify)
  "Like \\[fill-paragraph], but fill current BibTeX field.
Optional prefix arg JUSTIFY non-nil means justify as well.
In BibTeX mode this function is bound to `fill-paragraph-function'."
  (interactive "*P")
  (let ((pnt (copy-marker (point)))
        (bounds (bibtex-enclosing-field)))
    (when bounds
      (bibtex-fill-field-bounds bounds justify)
      (goto-char pnt))))

(defun bibtex-fill-entry ()
  "Fill current BibTeX entry.
Realign entry, so that every field starts on a separate line.  Field
names appear in column `bibtex-field-indentation', field text starts in
column `bibtex-text-indentation' and continuation lines start here, too.
If `bibtex-align-at-equal-sign' is non-nil, align equal signs, too."
  (interactive "*")
  (let ((pnt (copy-marker (point)))
        (end (copy-marker (bibtex-end-of-entry)))
        bounds)
    (bibtex-beginning-of-entry)
    (bibtex-delete-whitespace)
    (indent-to-column bibtex-entry-offset)
    (while (setq bounds (bibtex-search-forward-field bibtex-field-name end))
      (bibtex-fill-field-bounds bounds t t))
    (if (looking-at ",")
        (forward-char))
    (bibtex-delete-whitespace)
    (open-line 1)
    (forward-char)
    (indent-to-column bibtex-entry-offset)
    (goto-char pnt)))

(defun bibtex-reformat (&optional additional-options called-by-convert-alien)
  "Reformat all BibTeX entries in buffer or region.
With prefix argument, read options for reformatting from minibuffer.
With \\[universal-argument] \\[universal-argument] prefix argument, reuse previous answers (if any) again.
If mark is active it reformats entries in region, if not in whole buffer."
  (interactive "*P")
  (let* ((pnt (point))
         (use-previous-options
          (and (equal (prefix-numeric-value additional-options) 16)
               (or bibtex-reformat-previous-options
                   bibtex-reformat-previous-reference-keys)))
         (bibtex-entry-format
          (if additional-options
              (if use-previous-options
                  bibtex-reformat-previous-options
                (setq bibtex-reformat-previous-options
                      (delq nil (list
                                 (if (or called-by-convert-alien
                                         (y-or-n-p "Realign entries (recommended)? "))
                                     'realign)
                                 (if (y-or-n-p "Remove empty optional and alternative fields? ")
                                     'opts-or-alts)
                                 (if (y-or-n-p "Remove delimiters around pure numerical fields? ")
                                     'numerical-fields)
                                 (if (y-or-n-p (concat (if bibtex-comma-after-last-field "Insert" "Remove")
                                                       " comma at end of entry? "))
                                     'last-comma)
                                 (if (y-or-n-p "Replace double page dashes by single ones? ")
                                     'page-dashes)
                                 (if (y-or-n-p "Force delimiters? ")
                                     'delimiters)
                                 (if (y-or-n-p "Unify case of entry types and field names? ")
                                     'unify-case)))))
            '(realign)))
         (reformat-reference-keys (if additional-options
                                      (if use-previous-options
                                          bibtex-reformat-previous-reference-keys
                                        (setq bibtex-reformat-previous-reference-keys
                                              (y-or-n-p "Generate new reference keys automatically? ")))))
         bibtex-autokey-edit-before-use
         (bibtex-sort-ignore-string-entries t)
         (start-point (if (bibtex-mark-active)
                          (region-beginning)
                        (bibtex-beginning-of-first-entry)
                        (bibtex-skip-to-valid-entry)
                        (point)))
         (end-point (if (bibtex-mark-active)
                        (region-end)
                      (point-max))))
    (save-restriction
      (narrow-to-region start-point end-point)
      (when (memq 'realign bibtex-entry-format)
        (goto-char (point-min))
        (while (re-search-forward bibtex-valid-entry-whitespace-re nil t)
          (replace-match "\n\\1")))
      (goto-char start-point)
      (bibtex-progress-message "Formatting" 1)
      (bibtex-map-entries (lambda (key beg end)
                            (bibtex-progress-message)
                            (bibtex-clean-entry reformat-reference-keys t)
                            (when (memq 'realign bibtex-entry-format)
                              (goto-char end)
                              (bibtex-delete-whitespace)
                              (open-line 2))))
      (bibtex-progress-message 'done))
    (when (and reformat-reference-keys
               bibtex-maintain-sorted-entries
               (not called-by-convert-alien))
      (bibtex-sort-buffer)
      (kill-local-variable 'bibtex-reference-keys))
    (goto-char pnt)))

(defun bibtex-convert-alien (&optional do-additional-reformatting)
  "Convert an alien BibTeX buffer to be fully usable by BibTeX mode.
If a file does not conform with some standards used by BibTeX mode,
some of the high-level features of BibTeX mode will not be available.
This function tries to convert current buffer to conform with these standards.
With prefix argument DO-ADDITIONAL-REFORMATTING
non-nil, read options for reformatting entries from minibuffer."
  (interactive "*P")
  (message "Starting to validate buffer...")
  (sit-for 1 nil t)
  (goto-char (point-min))
  (while (re-search-forward "[ \t\n]+@" nil t)
    (replace-match "\n@"))
  (message
   "If errors occur, correct them and call `bibtex-convert-alien' again")
  (sit-for 5 nil t)
  (deactivate-mark)  ; So bibtex-validate works on the whole buffer.
  (when (let (bibtex-maintain-sorted-entries)
          (bibtex-validate))
    (message "Starting to reformat entries...")
    (sit-for 2 nil t)
    (bibtex-reformat do-additional-reformatting t)
    (when bibtex-maintain-sorted-entries
      (message "Starting to sort buffer...")
      (bibtex-sort-buffer))
    (goto-char (point-max))
    (message "Buffer is now parsable. Please save it.")))

(defun bibtex-complete ()
  "Complete word fragment before point according to context.
If point is inside key or crossref field perform key completion based on
`bibtex-reference-keys'. Inside any other field perform string
completion based on `bibtex-strings'. An error is signaled if point
is outside key or BibTeX field."
  (interactive)
  (let* ((pnt (point))
         (case-fold-search t)
         bounds compl)
    (save-excursion
      (if (and (setq bounds (bibtex-enclosing-field t))
               (>= pnt (bibtex-start-of-text-in-field bounds))
               (<= pnt (bibtex-end-of-text-in-field bounds)))
          (progn
            (goto-char (bibtex-start-of-name-in-field bounds))
            (setq compl (if (string= "crossref"
                                     (downcase
                                      (buffer-substring-no-properties
                                       (if (looking-at "\\(OPT\\)\\|\\(ALT\\)")
                                           (match-end 0)
                                         (point))
                                       (bibtex-end-of-name-in-field bounds))))
                            'key
                          'str)))
        (bibtex-beginning-of-entry)
        (if (and (re-search-forward bibtex-entry-maybe-empty-head nil t)
                 ;; point is inside a key
                 (or (and (match-beginning bibtex-key-in-head)
                          (>= pnt (match-beginning bibtex-key-in-head))
                          (<= pnt (match-end bibtex-key-in-head)))
                     ;; or point is on empty key
                     (and (not (match-beginning bibtex-key-in-head))
                          (= pnt (match-end 0)))))
            (setq compl 'key))))

    (cond ((equal compl 'key)
           ;; key completion
           (setq choose-completion-string-functions
                 (lambda (choice buffer mini-p base-size)
                   (bibtex-choose-completion-string choice buffer mini-p base-size)
                   (if bibtex-complete-key-cleanup
                       (funcall bibtex-complete-key-cleanup choice))
                   ;; return t (required by choose-completion-string-functions)
                   t))
           (let ((choice (bibtex-complete-internal bibtex-reference-keys)))
             (if bibtex-complete-key-cleanup
                 (funcall bibtex-complete-key-cleanup choice))))

          ((equal compl 'str)
           ;; string completion
           (setq choose-completion-string-functions
                 (lambda (choice buffer mini-p base-size)
                   (bibtex-choose-completion-string choice buffer mini-p base-size)
                   (bibtex-complete-string-cleanup choice)
                   ;; return t (required by choose-completion-string-functions)
                   t))
           (bibtex-complete-string-cleanup (bibtex-complete-internal bibtex-strings)))

          (t (error "Point outside key or BibTeX field")))))

(defun bibtex-Article ()
  "Insert a new BibTeX @Article entry; see also `bibtex-entry'."
  (interactive "*")
  (bibtex-entry "Article"))

(defun bibtex-Book ()
  "Insert a new BibTeX @Book entry; see also `bibtex-entry'."
  (interactive "*")
  (bibtex-entry "Book"))

(defun bibtex-Booklet ()
  "Insert a new BibTeX @Booklet entry; see also `bibtex-entry'."
  (interactive "*")
  (bibtex-entry "Booklet"))

(defun bibtex-InBook ()
  "Insert a new BibTeX @InBook entry; see also `bibtex-entry'."
  (interactive "*")
  (bibtex-entry "InBook"))

(defun bibtex-InCollection ()
  "Insert a new BibTeX @InCollection entry; see also `bibtex-entry'."
  (interactive "*")
  (bibtex-entry "InCollection"))

(defun bibtex-InProceedings ()
  "Insert a new BibTeX @InProceedings entry; see also `bibtex-entry'."
  (interactive "*")
  (bibtex-entry "InProceedings"))

(defun bibtex-Manual ()
  "Insert a new BibTeX @Manual entry; see also `bibtex-entry'."
  (interactive "*")
  (bibtex-entry "Manual"))

(defun bibtex-MastersThesis ()
  "Insert a new BibTeX @MastersThesis entry; see also `bibtex-entry'."
  (interactive "*")
  (bibtex-entry "MastersThesis"))

(defun bibtex-Misc ()
  "Insert a new BibTeX @Misc entry; see also `bibtex-entry'."
  (interactive "*")
  (bibtex-entry "Misc"))

(defun bibtex-PhdThesis ()
  "Insert a new BibTeX @PhdThesis entry; see also `bibtex-entry'."
  (interactive "*")
  (bibtex-entry "PhdThesis"))

(defun bibtex-Proceedings ()
  "Insert a new BibTeX @Proceedings entry; see also `bibtex-entry'."
  (interactive "*")
  (bibtex-entry "Proceedings"))

(defun bibtex-TechReport ()
  "Insert a new BibTeX @TechReport entry; see also `bibtex-entry'."
  (interactive "*")
  (bibtex-entry "TechReport"))

(defun bibtex-Unpublished ()
  "Insert a new BibTeX @Unpublished entry; see also `bibtex-entry'."
  (interactive "*")
  (bibtex-entry "Unpublished"))

(defun bibtex-String (&optional key)
  "Insert a new BibTeX @String entry with key KEY."
  (interactive (list (completing-read "String key: " bibtex-strings
                                      nil nil nil 'bibtex-key-history)))
  (let ((bibtex-maintain-sorted-entries
         (if (not bibtex-sort-ignore-string-entries)
             bibtex-maintain-sorted-entries))
        endpos)
    (unless (bibtex-prepare-new-entry (list key nil "String"))
      (error "Entry with key `%s' already exists" key))
    (if (zerop (length key)) (setq key nil))
    (indent-to-column bibtex-entry-offset)
    (insert "@String"
            (bibtex-entry-left-delimiter))
    (if key
        (insert key)
      (setq endpos (point)))
    (insert " = "
            (bibtex-field-left-delimiter))
    (if key
        (setq endpos (point)))
    (insert (bibtex-field-right-delimiter)
            (bibtex-entry-right-delimiter)
            "\n")
    (goto-char endpos)))

(defun bibtex-Preamble ()
  "Insert a new BibTeX @Preamble entry."
  (interactive "*")
  (bibtex-move-outside-of-entry)
  (indent-to-column bibtex-entry-offset)
  (insert "@Preamble"
          (bibtex-entry-left-delimiter))
  (let ((endpos (point)))
    (insert (bibtex-entry-right-delimiter)
            "\n")
    (goto-char endpos)))


;; Make BibTeX a Feature

(provide 'bibtex)

;;; arch-tag: ee2be3af-caad-427f-b42a-d20fad630d04
;;; bibtex.el ends here
