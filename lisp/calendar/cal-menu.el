;;; cal-menu.el --- calendar functions for menu bar and popup menu support

;; Copyright (C) 1994, 1995, 2001, 2002, 2003, 2004, 2005, 2006, 2007,
;;   2008  Free Software Foundation, Inc.

;; Author: Edward M. Reingold <reingold@cs.uiuc.edu>
;;         Lara Rios <lrios@coewl.cen.uiuc.edu>
;; Maintainer: Glenn Morris <rgm@gnu.org>
;; Keywords: calendar
;; Human-Keywords: calendar, popup menus, menu bar

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

;; See calendar.el.

;;; Code:

(require 'calendar)

(defconst cal-menu-moon-menu
  '("Moon"
    ["Lunar Phases" calendar-phases-of-moon]))

(defconst cal-menu-diary-menu
  '("Diary"
    ["Other File" diary-view-other-diary-entries]
    ["Cursor Date" diary-view-entries]
    ["Mark All" diary-mark-entries]
    ["Show All" diary-show-all-entries]
    ["Insert Diary Entry" diary-insert-entry]
    ["Insert Weekly" diary-insert-weekly-entry]
    ["Insert Monthly" diary-insert-monthly-entry]
    ["Insert Yearly" diary-insert-yearly-entry]
    ["Insert Anniversary" diary-insert-anniversary-entry]
    ["Insert Block" diary-insert-block-entry]
    ["Insert Cyclic" diary-insert-cyclic-entry]
    ("Insert Baha'i"
     ["One time" diary-bahai-insert-entry]
     ["Monthly" diary-bahai-insert-monthly-entry]
     ["Yearly" diary-bahai-insert-yearly-entry])
    ("Insert Islamic"
     ["One time" diary-islamic-insert-entry]
     ["Monthly" diary-islamic-insert-monthly-entry]
     ["Yearly" diary-islamic-insert-yearly-entry])
    ("Insert Hebrew"
     ["One time" diary-hebrew-insert-entry]
     ["Monthly" diary-hebrew-insert-monthly-entry]
     ["Yearly" diary-hebrew-insert-yearly-entry])))

(defun cal-menu-holiday-window-suffix ()
  "Return a string suffix for the \"Window\" entry in `cal-menu-holidays-menu'."
  (let ((my1 (calendar-increment-month-cons -1))
        (my2 (calendar-increment-month-cons 1)))
    (if (= (cdr my1) (cdr my2))
        (format "%s-%s, %d"
                (calendar-month-name (car my1) 'abbrev)
                (calendar-month-name (car my2) 'abbrev)
                (cdr my2))
      (format "%s, %d-%s, %d"
              (calendar-month-name (car my1) 'abbrev)
              (cdr my1)
              (calendar-month-name (car my2) 'abbrev)
              (cdr my2)))))

(defvar displayed-year)                 ; from calendar-generate

(defconst cal-menu-holidays-menu
  `("Holidays"
    ["For Cursor Date -" calendar-cursor-holidays
     :suffix (calendar-date-string (calendar-cursor-to-date) t t)
     :visible (calendar-cursor-to-date)]
    ["For Window -" calendar-list-holidays
     :suffix (cal-menu-holiday-window-suffix)]
    ["For Today -" cal-menu-today-holidays
     :suffix (calendar-date-string (calendar-current-date) t t)]
    "--"
    ,@(let ((l ()))
        ;; Show 11 years--5 before, 5 after year of middle month.
        ;; We used to use :suffix rather than :label and bumped into
        ;; an easymenu bug:
        ;; http://lists.gnu.org/archive/html/emacs-devel/2007-11/msg01813.html
        ;; The bug has since been fixed.
        (dotimes (i 11)
          (push (vector (format "hol-year-%d" i)
                        `(lambda ()
                           (interactive)
                           (holiday-list (+ displayed-year ,(- i 5))))
                        :label `(format "For Year %d"
                                       (+ displayed-year ,(- i 5))))
                l))
        (nreverse l))
    "--"
    ["Unmark Calendar" calendar-unmark]
    ["Mark Holidays" calendar-mark-holidays]))

(defconst cal-menu-goto-menu
  '("Go To"
    ["Today" calendar-goto-today]
    ["Beginning of Week" calendar-beginning-of-week]
    ["End of Week" calendar-end-of-week]
    ["Beginning of Month" calendar-beginning-of-month]
    ["End of Month" calendar-end-of-month]
    ["Beginning of Year" calendar-beginning-of-year]
    ["End of Year" calendar-end-of-year]
    ["Other Date" calendar-goto-date]
    ["Day of Year" calendar-goto-day-of-year]
    ["ISO Week" calendar-iso-goto-week]
    ["ISO Date" calendar-iso-goto-date]
    ["Astronomical Date" calendar-astro-goto-day-number]
    ["Hebrew Date" calendar-hebrew-goto-date]
    ["Persian Date" calendar-persian-goto-date]
    ["Baha'i Date" calendar-bahai-goto-date]
    ["Islamic Date" calendar-islamic-goto-date]
    ["Julian Date" calendar-julian-goto-date]
    ["Chinese Date" calendar-chinese-goto-date]
    ["Coptic Date" calendar-coptic-goto-date]
    ["Ethiopic Date" calendar-ethiopic-goto-date]
    ("Mayan Date"
     ["Next Tzolkin" calendar-mayan-next-tzolkin-date]
     ["Previous Tzolkin" calendar-mayan-previous-tzolkin-date]
     ["Next Haab" calendar-mayan-next-haab-date]
     ["Previous Haab" calendar-mayan-previous-haab-date]
     ["Next Round" calendar-mayan-next-round-date]
     ["Previous Round" calendar-mayan-previous-round-date])
    ["French Date" calendar-french-goto-date]))

(defconst cal-menu-scroll-menu
  '("Scroll"
    ["Forward 1 Month" calendar-scroll-left]
    ["Forward 3 Months" calendar-scroll-left-three-months]
    ["Forward 1 Year" (calendar-scroll-left 12) :keys "4 C-v"]
    ["Backward 1 Month" calendar-scroll-right]
    ["Backward 3 Months" calendar-scroll-right-three-months]
    ["Backward 1 Year" (calendar-scroll-right 12) :keys "4 M-v"]))

(defun cal-menu-x-popup-menu (position menu)
  "Like `x-popup-menu', but print an error message if popups are unavailable.
POSITION and MENU are passed to `x-popup-menu'."
  (if (display-popup-menus-p)
      (x-popup-menu position menu)
    (error "Popup menus are not available on this system")))

(defun cal-menu-list-holidays-year ()
  "Display a list of the holidays of the selected date's year."
  (interactive)
  (holiday-list (calendar-extract-year (calendar-cursor-to-date))))

(defun cal-menu-list-holidays-following-year ()
  "Display a list of the holidays of the following year."
  (interactive)
  (holiday-list (1+ (calendar-extract-year (calendar-cursor-to-date)))))

(defun cal-menu-list-holidays-previous-year ()
  "Display a list of the holidays of the previous year."
  (interactive)
  (holiday-list (1- (calendar-extract-year (calendar-cursor-to-date)))))

(defun cal-menu-event-to-date (&optional error)
  "Date of last event.
If event is not on a specific date, signals an error if optional parameter
ERROR is non-nil, otherwise just returns nil."
  (with-current-buffer
      (window-buffer (posn-window (event-start last-input-event)))
    (goto-char (posn-point (event-start last-input-event)))
    (calendar-cursor-to-date error)))

(defun calendar-mouse-goto-date (date)
  "Go to DATE in the buffer specified by `last-input-event'."
  (set-buffer (window-buffer (posn-window (event-start last-input-event))))
  (calendar-goto-date date))

(defun calendar-mouse-sunrise/sunset ()
  "Show sunrise/sunset times for mouse-selected date."
  (interactive)
  (save-excursion
    (calendar-mouse-goto-date (cal-menu-event-to-date))
    (calendar-sunrise-sunset)))

(defun cal-menu-today-holidays ()
  "Show holidays for today's date."
  (interactive)
  (save-excursion
    (calendar-cursor-to-date (calendar-current-date))
    (calendar-cursor-holidays)))

(autoload 'calendar-check-holidays "holidays")

(defun calendar-mouse-holidays (&optional event)
  "Pop up menu of holidays for mouse selected date.
EVENT is the event that invoked this command."
  (interactive "e")
  (let* ((date (cal-menu-event-to-date))
         (title (format "Holidays for %s" (calendar-date-string date)))
         (selection
          (cal-menu-x-popup-menu
           event
           (list title
                 (append (list title)
                         (or (mapcar 'list (calendar-check-holidays date))
                             '("None")))))))
    (and selection (call-interactively selection))))

(autoload 'diary-list-entries "diary-lib")
(defvar diary-show-holidays-flag)       ; only called from calendar.el

(defun calendar-mouse-view-diary-entries (&optional date diary event)
  "Pop up menu of diary entries for mouse-selected date.
Use optional DATE and alternative file DIARY.  EVENT is the event
that invoked this command.  Shows holidays if `diary-show-holidays-flag'
is non-nil."
  (interactive "i\ni\ne")
  (let* ((date (or date (cal-menu-event-to-date)))
         (diary-file (or diary diary-file))
         (diary-list-include-blanks nil)
         (diary-entries
          (mapcar (lambda (x) (split-string (cadr x) "\n"))
                  (diary-list-entries date 1 'list-only)))
         (holidays (if diary-show-holidays-flag
                       (calendar-check-holidays date)))
         (title (concat "Diary entries "
                        (if diary (format "from %s " diary) "")
                        "for "
                        (calendar-date-string date)))
         (selection
          (cal-menu-x-popup-menu
           event
           (list title
                 (append
                  (list title)
                  (mapcar (lambda (x) (list (concat "     " x))) holidays)
                  (if holidays
                      (list "--shadow-etched-in" "--shadow-etched-in"))
                  (if diary-entries
                      (mapcar 'list (apply 'append diary-entries))
                    '("None")))))))
    (and selection (call-interactively selection))))

(defun calendar-mouse-view-other-diary-entries ()
  "Pop up menu of diary entries from alternative file on mouse-selected date."
  (interactive)
  (calendar-mouse-view-diary-entries
   (cal-menu-event-to-date)
   (read-file-name "Enter diary file name: " default-directory nil t)))

(defun calendar-mouse-insert-diary-entry ()
  "Insert diary entry for mouse-selected date."
  (interactive)
  (save-excursion
    (calendar-mouse-goto-date (cal-menu-event-to-date))
    (diary-insert-entry nil)))

(defun calendar-mouse-set-mark ()
  "Mark the date under the cursor."
  (interactive)
  (save-excursion
    (calendar-mouse-goto-date (cal-menu-event-to-date))
    (calendar-set-mark nil)))

(defun calendar-mouse-tex-day ()
  "Make a buffer with LaTeX commands for the day mouse is on."
  (interactive)
  (save-excursion
    (calendar-mouse-goto-date (cal-menu-event-to-date))
    (cal-tex-cursor-day nil)))

(defun calendar-mouse-tex-week ()
  "One page calendar for week indicated by cursor.
Holidays are included if `cal-tex-holidays' is non-nil."
  (interactive)
  (save-excursion
    (calendar-mouse-goto-date (cal-menu-event-to-date))
    (cal-tex-cursor-week nil)))

(defun calendar-mouse-tex-week2 ()
  "Make a buffer with LaTeX commands for the week cursor is on.
The printed output will be on two pages."
  (interactive)
  (save-excursion
    (calendar-mouse-goto-date (cal-menu-event-to-date))
    (cal-tex-cursor-week2 nil)))

(defun calendar-mouse-tex-week-iso ()
  "One page calendar for week indicated by cursor.
Holidays are included if `cal-tex-holidays' is non-nil."
  (interactive)
  (save-excursion
    (calendar-mouse-goto-date (cal-menu-event-to-date))
    (cal-tex-cursor-week-iso nil)))

(defun calendar-mouse-tex-week-monday ()
  "One page calendar for week indicated by cursor."
  (interactive)
  (save-excursion
    (calendar-mouse-goto-date (cal-menu-event-to-date))
    (cal-tex-cursor-week-monday nil)))

(defun calendar-mouse-tex-filofax-daily ()
  "Day-per-page Filofax calendar for week indicated by cursor."
  (interactive)
  (save-excursion
    (calendar-mouse-goto-date (cal-menu-event-to-date))
    (cal-tex-cursor-filofax-daily nil)))

(defun calendar-mouse-tex-filofax-2week ()
  "One page Filofax calendar for week indicated by cursor."
  (interactive)
  (save-excursion
    (calendar-mouse-goto-date (cal-menu-event-to-date))
    (cal-tex-cursor-filofax-2week nil)))

(defun calendar-mouse-tex-filofax-week ()
  "Two page Filofax calendar for week indicated by cursor."
  (interactive)
  (save-excursion
    (calendar-mouse-goto-date (cal-menu-event-to-date))
    (cal-tex-cursor-filofax-week nil)))

(defun calendar-mouse-tex-month ()
  "Make a buffer with LaTeX commands for the month cursor is on.
Calendar is condensed onto one page."
  (interactive)
  (save-excursion
    (calendar-mouse-goto-date (cal-menu-event-to-date))
    (cal-tex-cursor-month nil)))

(defun calendar-mouse-tex-month-landscape ()
  "Make a buffer with LaTeX commands for the month cursor is on.
The output is in landscape format, one month to a page."
  (interactive)
  (save-excursion
    (calendar-mouse-goto-date (cal-menu-event-to-date))
    (cal-tex-cursor-month-landscape nil)))

(defun calendar-mouse-tex-year ()
  "Make a buffer with LaTeX commands for the year cursor is on."
  (interactive)
  (save-excursion
    (calendar-mouse-goto-date (cal-menu-event-to-date))
    (cal-tex-cursor-year nil)))

(defun calendar-mouse-tex-filofax-year ()
  "Make a buffer with LaTeX commands for Filofax calendar of year cursor is on."
  (interactive)
  (save-excursion
    (calendar-mouse-goto-date (cal-menu-event-to-date))
    (cal-tex-cursor-filofax-year nil)))

(defun calendar-mouse-tex-year-landscape ()
  "Make a buffer with LaTeX commands for the year cursor is on."
  (interactive)
  (save-excursion
    (calendar-mouse-goto-date (cal-menu-event-to-date))
    (cal-tex-cursor-year-landscape nil)))

(defun calendar-mouse-print-dates (&optional event)
  "Pop up menu of equivalent dates to mouse selected date.
EVENT is the event that invoked this command."
  (interactive "e")
  (let* ((date (cal-menu-event-to-date))
         (title (format "%s (Gregorian)" (calendar-date-string date)))
         (selection
          (cal-menu-x-popup-menu
           event
           (list title
                 (append (list title)
                         (mapcar 'list (calendar-other-dates date)))))))
    (and selection (call-interactively selection))))

(defun cal-menu-set-date-title (menu)
  "Convert date of last event to title suitable for MENU."
  (easy-menu-filter-return
   menu (calendar-date-string (cal-menu-event-to-date t) t nil)))

(easy-menu-define cal-menu-context-mouse-menu nil
  "Pop up menu for Mouse-2 for selected date in the calendar window."
  '("cal-menu-mouse2" :filter cal-menu-set-date-title
    "--"
    ["Holidays" calendar-mouse-holidays]
    ["Mark date" calendar-mouse-set-mark]
    ["Sunrise/sunset" calendar-mouse-sunrise/sunset]
    ["Other calendars" calendar-mouse-print-dates]
    ("Prepare LaTeX buffer"
     ["Daily (1 page)" calendar-mouse-tex-day]
     ["Weekly (1 page)" calendar-mouse-tex-week]
     ["Weekly (2 pages)" calendar-mouse-tex-week2]
     ["Weekly (other style; 1 page)" calendar-mouse-tex-week-iso]
     ["Weekly (yet another style; 1 page)" calendar-mouse-tex-week-monday]
     ["Monthly" calendar-mouse-tex-month]
     ["Monthly (landscape)" calendar-mouse-tex-month-landscape]
     ["Yearly" calendar-mouse-tex-year]
     ["Yearly (landscape)" calendar-mouse-tex-year-landscape]
     ("Filofax styles"
      ["Filofax Daily (one-day-per-page)" calendar-mouse-tex-filofax-daily]
      ["Filofax Weekly (2-weeks-at-a-glance)" calendar-mouse-tex-filofax-2week]
      ["Filofax Weekly (week-at-a-glance)" calendar-mouse-tex-filofax-week]
      ["Filofax Yearly" calendar-mouse-tex-filofax-year]))
    ["Diary entries" calendar-mouse-view-diary-entries]
    ["Insert diary entry" calendar-mouse-insert-diary-entry]
    ["Other diary file entries" calendar-mouse-view-other-diary-entries]))

(easy-menu-define cal-menu-global-mouse-menu nil
  "Menu bound to a mouse event, not specific to the mouse-click location."
  '("Calendar"
    ["Scroll forward" calendar-scroll-left-three-months]
    ["Scroll backward" calendar-scroll-right-three-months]
    ["Mark diary entries" diary-mark-entries]
    ["List holidays" calendar-list-holidays]
    ["Mark holidays" calendar-mark-holidays]
    ["Unmark" calendar-unmark]
    ["Lunar phases" calendar-phases-of-moon]
    ["Show diary" diary-show-all-entries]
    ["Exit calendar" calendar-exit]))

;; Undocumented and probably useless.
(defvar cal-menu-load-hook nil
  "Hook run on loading of the `cal-menu' package.")
(make-obsolete-variable 'cal-menu-load-hook
                        "it will be removed in future." "23.1")

(run-hooks 'cal-menu-load-hook)

(provide 'cal-menu)

;; arch-tag: aa81cf73-ce89-48a4-97ec-9ef861e87fe9
;;; cal-menu.el ends here
