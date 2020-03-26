# A simple Inoreader client

`inoreader.el` is a simple Inoreader client. It lets you read your unread
articles inside Emacs.

Currently you can use `M-x inoreader-list-unread` to list unread articles using
Tabulated List mode, and read an article with `RET`.

This pakage is not completed but it was frustrating to find that my network to
Inoreader is so unreliable and slow that 1/2 requests will hang forever. It's
unlikey that I can finish this project.

## Setup

Regiser an app, see https://www.inoreader.com/developers/register-app, then
change values of the following variables to yours

- `inoreader-app-id`
- `inoreader-app-secret`
- `inoreader-redirect-uri`

## Requires

- Emacs 25.1
- https://elpa.gnu.org/packages/oauth2.html
