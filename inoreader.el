;;; inoreader.el --- A simple Inoreader client       -*- lexical-binding: t; -*-

;; Copyright (C) 2020  Xu Chunyang

;; Author: Xu Chunyang
;; Homepage: https://github.com/xuchunyang/inoreader.el
;; Package-Requires: ((emacs "25.1") (oauth2 "0.11"))
;; Version: 0
;; Keywords: news

;; This program is free software; you can redistribute it and/or modify
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

;; inoreader.el is a simple Inoreader <https://www.inoreader.com/> client. It
;; lets you read news inside Emacs.

;;; Code:

(require 'oauth2)

(defvar url-http-end-of-headers)
(defvar url-http-response-status)

(defgroup inoreader nil
  "A simple Inoreader client."
  :group 'news)

(defcustom inoreader-app-id nil
  "The app ID that you got when registering your app.
See URL `https://www.inoreader.com/developers/register-app'."
  :type '(choice (const :tag "Unknown" nil)
                 (string :tag "Your App ID")))

(defcustom inoreader-app-secret nil
  "The app key that you got when registering your app.
See URL `https://www.inoreader.com/developers/register-app'."
  :type '(choice (const :tag "Not set" nil)
                 (string :tag "Your App key")))

(defcustom inoreader-redirect-uri "http://localhost:8888/"
  "The redirect URI that you set when registering your app."
  :type 'string)

(defconst inoreader--app-scope "read write"
  "The app permissions that you choose when registering your app.
You must NOT set \"Read only\" in your app settings, we need the
write permission to mark a item read.")

(defconst inoreader--state "ignored" "The CSRF protection string.")

(defconst inoreader--auth-url "https://www.inoreader.com/oauth2/auth"
  "The oauth2 authorization URL.")

(defconst inoreader--token-url "https://www.inoreader.com/oauth2/token"
  "The oauth2 token URL.")

(defvar inoreader--token nil
  "Nil or an object of `oauth2-token'.")

(defun inoreader--token ()
  "Return the token."
  (unless inoreader--token
    (setq inoreader--token
          (oauth2-auth-and-store inoreader--auth-url
                                 inoreader--token-url
                                 inoreader--app-scope
                                 inoreader-app-id
                                 inoreader-app-secret
                                 inoreader-redirect-uri
                                 inoreader--state)))
  inoreader-token)

(defconst inoreader--api-base-url "https://www.inoreader.com/reader/api/0"
  "The API base URL.")

(defun inoreader--url-encode-params (params)
  (mapconcat (lambda (param)
               (pcase-let ((`(,key . ,val) param))
                 (concat (url-hexify-string (symbol-name key)) "="
                         (if (integerp val)
                             (number-to-string val)
                           (url-hexify-string val)))))
             params "&"))

(defun inoreader--json-read ()
  (let ((json-object-type 'alist)
        (json-array-type  'list)
        (json-key-type    'symbol)
        (json-false       nil)
        (json-null        nil))
    (json-read)))

(defun inoreader--request (method resource &optional query payload)
  (cl-assert (member method '("GET" "POST")))
  (unless (string-prefix-p "/" resource)
    (setq resource (concat "/" resource)))
  (with-current-buffer (oauth2-url-retrieve-synchronously
                        (inoreader-token)
                        (concat inoreader--api-base-url
                                resource
                                (and query
                                     (concat "?" (inoreader--url-encode-params query))))
                        method
                        (and payload (inoreader--url-encode-params payload)))
    (cl-assert (<= 200 url-http-response-status 299))
    (goto-char (1+ url-http-end-of-headers))
    (prog1 (cond
            ((eobp) nil)                ; empty response body
            (t (set-buffer-multibyte t)
               (inoreader--json-read)))
      (kill-buffer))))

(defconst inoreader--read-tag "user/-/state/com.google/read")

(defun inoreader--fetch-unread ()
  "Return a list of unread items."
  (let ((query `((xt . ,inoreader--read-tag)
                 (n . 20)))
        (first t)
        continuation result)
    (while (or first continuation)
      (setq first nil)
      (let-alist (inoreader--request "GET" "/stream/contents/"
                                     (if continuation
                                         (cons `(c . ,continuation) query)
                                       query))
        (setq continuation .continuation)
        (setq result (nconc result .items))))
    result))

(define-derived-mode inoreader--list-mode tabulated-list-mode "Inoreader List"
  "Major mode for browse a list of articles."
  (setq tabulated-list-format
        [("Title" 72 t)
         ("Feed" 0 t)])
  (tabulated-list-init-header)
  (add-hook 'tabulated-list-revert-hook #'inoreader--revert nil t))

(defun inoreader--revert ()
  (setq tabulated-list-entries
        (mapcar
         (lambda (item)
           (let-alist item
             (list
              ;; .id
              item                  ; use `tabulated-list-get-id' to get it back
              (vector (list .title
                            'action #'inoreader--show-article)
                      .origin.title))))
         (inoreader--fetch-unread))))

(defun inoreader--show-article (&optional _button)
  (interactive)
  (when-let ((item (tabulated-list-get-id)))
    (let-alist item
      (with-current-buffer (get-buffer-create "Inoreader Article*")
        (let ((inhibit-read-only t))
          (read-only-mode)
          (erase-buffer)
          (shr-insert-document
           (with-temp-buffer
             (insert .summary.content)
             (libxml-parse-html-region (point-min) (point-max)
                                       ;; XXX what's the purpose
                                       .canonical.href)))
          (goto-char (point-min)))
        (switch-to-buffer (current-buffer))))))

(defun inoreader-list-unread ()
  (interactive)
  (with-current-buffer (get-buffer-create "*Inoreader Unread*")
    (switch-to-buffer (current-buffer))
    (inoreader--list-mode)
    (inoreader--revert)
    (tabulated-list-print)))

(provide 'inoreader)
;;; inoreader.el ends here
