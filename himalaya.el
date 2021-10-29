;;; himalaya.el --- Interface for the himalaya email client  -*- lexical-binding: t -*-

;; Copyright (C) 2021 Dante Catalfamo

;; Author: Dante Catalfamo

;; This file is not part of GNU Emacs

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.


;;; Commentary:

;; Interface for the himalaya email client
;; https://github.com/soywod/himalaya

;;; Code:

(require 'subr-x)
(require 'mailheader)

(defgroup himalaya nil
  "Options related to the himalaya mail client."
  :group 'mail)

(defcustom himalaya-executable "himalaya"
  "Name or location of the himalaya executable."
  :type 'text
  :group 'himalaya)

(defcustom himalaya-page-size 100
  "The number of emails to return per mailbox page."
  :type 'number
  :group 'himalaya)

(defcustom himalaya-id-face font-lock-variable-name-face
  "Font face for himalaya email IDs."
  :type 'face
  :group 'himalaya)

(defcustom himalaya-sender-face font-lock-function-name-face
  "Font face for himalaya sender names."
  :type 'face
  :group 'himalaya)

(defcustom himalaya-date-face font-lock-constant-face
  "Font face for himalaya dates."
  :type 'face
  :group 'himalaya)

(defcustom himalaya-unseen-face font-lock-string-face
  "Font face for unseen message symbol."
  :type 'face
  :group 'himalaya)

(defcustom himalaya-flagged-face font-lock-warning-face
  "Font face for flagged message symbol."
  :type 'face
  :group 'himalaya)

(defcustom himalaya-headers-face font-lock-constant-face
  "Font face for headers when reading a message."
  :type 'face
  :group 'himalaya)

(defcustom himalaya-unseen-symbol "●"
  "Symbol to display in the flags column when a message hasn't been read yet."
  :type 'text
  :group 'himalaya)

(defcustom himalaya-answered-symbol "↵"
  "Symbol to display in the flags column when a message has been replied to."
  :type 'text
  :group 'himalaya)

(defcustom himalaya-flagged-symbol "⚑"
  "Symbol to display in the flags column when a message has been flagged."
  :type 'text
  :group 'himalaya)

(defcustom himalaya-subject-width 70
  "Width of the subject column in the message list."
  :type 'number
  :group 'himalaya)

(defcustom himalaya-from-width 30
  "Width of the from column in the message list."
  :type 'number
  :group 'himalaya)


(defvar-local himalaya-mailbox nil
  "The current mailbox.")

(defvar-local himalaya-account nil
  "The current account.")

(defvar-local himalaya-uid nil
  "The current message uid.")

(defvar-local himalaya-page 1
  "The current mailbox page.")

(defun himalaya--run (&rest args)
  "Run himalaya with ARGS.
Results are returned as a string. Signals a Lisp error and
displaus the output on non-zero exit."
  (with-temp-buffer
    (let* ((args (flatten-list args))
           (ret (apply #'call-process himalaya-executable nil t nil args))
           (output (buffer-string)))
      (unless (eq ret 0)
        (with-current-buffer-window "*himalaya error*" nil nil
          (insert output))
        (error "Himalaya exited with a non-zero status"))
      output)))

(defun himalaya--run-json (&rest args)
  "Run himalaya with ARGS arguments.
The result is parsed as JSON and returned."
  (let ((args (append '("-o" "json") args)))
    ;; Remove { "response": [...] } wrapper
    (cadr (json-parse-string (himalaya--run args)
                             :object-type 'plist
                             :array-type 'list))))

(defun himalaya--extract-headers (message)
  "Extract email headers from MESSAGE."
  (with-temp-buffer
    (insert message)
    (goto-char (point-min))
    (mail-header-extract-no-properties)))

(defun himalaya--mailbox-list (&optional account)
  "Return a list of mailboxes for ACCOUNT.
If ACCOUNT is nil, the default account is used."
  (himalaya--run-json (when account (list "-a" account)) "mailboxes"))

(defun himalaya--mailbox-list-names (&optional account)
  "Return a list of mailbox names for ACCOUNT.
If ACCOUNT is nil, the default account is used."
  (mapcar (lambda (mbox) (plist-get mbox :name))
          (himalaya--mailbox-list account)))

(defun himalaya--message-list (&optional account mailbox page)
  "Return a list of emails from ACCOUNT in MAILBOX.
Paginate using PAGE of PAGE-SIZE.
If ACCOUNT, MAILBOX, or PAGE are nil, the default values are used."
  (himalaya--run-json (when account (list "-a" account))
                      (when mailbox (list "-m" mailbox))
                      "list"
                      (when page (list "-p" (format "%s" page)))
                      (when himalaya-page-size (list "-s" (prin1-to-string himalaya-page-size)))))

(defun himalaya--message-read (uid &optional account mailbox raw html)
  "Return the contents of message with UID from MAILBOX on ACCOUNT.
If ACCOUNT or MAILBOX are nil, use the defaults. If RAW is
non-nil, return the raw contents of the email including headers.
If HTML is non-nil, return the HTML version of the email,
otherwise return the plain text version."
  (himalaya--run-json (when account (list "-a" account))
                      (when mailbox (list "-m" mailbox))
                      "read"
                      (when raw "-r")
                      (when html (list "-t" "html"))
                      (format "%s" uid))) ; Ensure uid is a string

(defun himalaya--message-copy (uid target &optional account mailbox)
  "Copy message with UID from MAILBOX to TARGET mailbox on ACCOUNT.
If ACCOUNT or MAILBOX are nil, use the defaults."
  (himalaya--run-json (when account (list "-a" account))
                      (when mailbox (list "-m" mailbox))
                      "copy"
                      (format "%s" uid)
                      target))

(defun himalaya--message-move (uid target &optional account mailbox)
  "Move message with UID from MAILBOX to TARGET mailbox on ACCOUNT.
If ACCOUNT or MAILBOX are nil, use the defaults."
  (himalaya--run-json (when account (list "-a" account))
                      (when mailbox (list "-m" mailbox))
                      "move"
                      (format "%s" uid)
                      target))

(defun himalaya--message-flag-symbols (flags)
  "Generate a display string for FLAGS."
  (concat
   (if (member "Seen" flags) " " (propertize himalaya-unseen-symbol 'face himalaya-unseen-face))
   (if (member "Answered" flags) himalaya-answered-symbol " ")
   (if (member "Flagged" flags) (propertize himalaya-flagged-symbol 'face himalaya-flagged-face) " ")))

(defun himalaya--message-list-build-table ()
  "Construct the message list table."
  (let ((messages (himalaya--message-list himalaya-account himalaya-mailbox himalaya-page))
        entries)
    (dolist (message messages entries)
      (push (list (plist-get message :id)
                  (vector
                   (propertize (prin1-to-string (plist-get message :id)) 'face himalaya-id-face)
                   (himalaya--message-flag-symbols (plist-get message :flags))
                   (plist-get message :subject)
                   (propertize (plist-get message :sender) 'face himalaya-sender-face)
                   (propertize (plist-get message :date) 'face himalaya-date-face)))
            entries))))

(defun himalaya-message-list (&optional account mailbox page)
  "List messages in MAILBOX on ACCOUNT."
  (interactive)
  (switch-to-buffer (concat "*Himalaya Mailbox"
                            (when (or account mailbox) ": ")
                            account
                            (and account mailbox "/")
                            mailbox
                            "*"))

  (himalaya-message-list-mode)
  (setq himalaya-mailbox mailbox)
  (setq himalaya-account account)
  (setq himalaya-page (or page himalaya-page))
  (setq mode-line-process (format " [Page %s]" himalaya-page))
  (revert-buffer))

;;;###autoload
(defalias 'himalaya #'himalaya-message-list)

(defun himalaya-switch-mailbox (mailbox)
  "Switch to MAILBOX on the current email account."
  (interactive (list (completing-read "Mailbox: " (himalaya--mailbox-list-names himalaya-account))))
  (himalaya-message-list himalaya-account mailbox))

(defun himalaya-message-read (uid &optional account mailbox)
  "Display message UID from MAILBOX on ACCOUNT.
If ACCOUNT or MAILBOX are nil, use the defaults."
  (let* ((message (replace-regexp-in-string "" "" (himalaya--message-read uid account mailbox)))
         (message-raw (replace-regexp-in-string "" "" (himalaya--message-read uid account mailbox 'raw)))
         (headers (himalaya--extract-headers message-raw)))
    (switch-to-buffer (format "*%s*" (alist-get 'subject headers)))
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (propertize "From: " 'face himalaya-headers-face)
              (alist-get 'from headers) "\n")
      (insert (propertize "To: " 'face himalaya-headers-face)
              (alist-get 'to headers) "\n")
      (insert (propertize "Subject: " 'face himalaya-headers-face)
              (alist-get 'subject headers) "\n")
      (insert (propertize "Date: " 'face himalaya-headers-face)
              (alist-get 'date headers) "\n")
      (insert "\n")
      (insert message))
    (himalaya-message-read-mode)
    (setq himalaya-account account)
    (setq himalaya-mailbox mailbox)
    (setq himalaya-uid uid)))

(defun himalaya-message-read-raw (uid &optional account mailbox)
  "Display raw message UID from MAILBOX on ACCOUNT.
If ACCOUNT or MAILBOX are nil, use the defaults."
  (let* ((message-raw (replace-regexp-in-string "" "" (himalaya--message-read uid account mailbox 'raw)))
         (headers (himalaya--extract-headers message-raw)))
    (switch-to-buffer (format "*Raw: %s*" (alist-get 'subject headers)))
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert message-raw))
    (himalaya-message-read-raw-mode)
    (setq himalaya-account account)
    (setq himalaya-mailbox mailbox)
    (setq himalaya-uid uid)))

(defun himalaya-message-read-switch-raw ()
  "Read a raw version of the current message."
  (interactive)
  (himalaya-message-read-raw himalaya-uid himalaya-account himalaya-mailbox))

(defun himalaya-message-read-switch-plain ()
  "Read a plain version of the current message."
  (interactive)
  (himalaya-message-read himalaya-uid himalaya-account himalaya-mailbox))

(defun himalaya-message-select ()
  "Read the message at point."
  (interactive)
  (let* ((message (tabulated-list-get-entry))
         (uid (substring-no-properties (elt message 0))))
    (himalaya-message-read uid himalaya-account himalaya-mailbox)))

(defun himalaya-forward-page ()
  "Go to the next page of the current mailbox."
  (interactive)
  (himalaya-message-list himalaya-account himalaya-mailbox (1+ himalaya-page)))

(defun himalaya-backward-page ()
  "Go to the previous page of the current mailbox."
  (interactive)
  (himalaya-message-list himalaya-account himalaya-mailbox (max 1 (1- himalaya-page))))

(defun himalaya-jump-to-page (page)
  "Jump to PAGE of current mailbox."
  (interactive "nJump to page: ")
  (himalaya-message-list himalaya-account himalaya-mailbox (max 1 page)))

(defvar himalaya-message-list-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "m") #'himalaya-switch-mailbox)
    (define-key map (kbd "RET") #'himalaya-message-select)
    (define-key map (kbd "f") #'himalaya-forward-page)
    (define-key map (kbd "b") #'himalaya-backward-page)
    (define-key map (kbd "j") #'himalaya-jump-to-page)
    map))

(define-derived-mode himalaya-message-list-mode tabulated-list-mode "Himylaya-Messages"
  "Himylaya email client message list mode."
  (setq tabulated-list-format (vector
                               '("ID" 5 nil :right-align t)
                               '("Flags" 6 nil)
                               (list "Subject" himalaya-subject-width nil)
                               (list "Sender" himalaya-from-width nil)
                               '("Date" 19 nil)))
  (setq tabulated-list-sort-key nil)
  (setq tabulated-list-entries #'himalaya--message-list-build-table)
  (tabulated-list-init-header)
  (hl-line-mode))

(defvar himalaya-message-read-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "R") #'himalaya-message-read-switch-raw)
    map))

(define-derived-mode himalaya-message-read-mode special-mode "Himalaya-Read"
  "Himalaya email client message reading mode.")

(defvar himalaya-message-read-raw-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "R") #'himalaya-message-read-switch-plain)
    map))

(define-derived-mode himalaya-message-read-raw-mode special-mode "Himalaya-Read-Raw"
  "Himalaya email client raw message mode.")

(provide 'himalaya)
;;; himalaya.el ends here
