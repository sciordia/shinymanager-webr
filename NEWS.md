# shinymanager.webr 0.2.1

## Fixes

* The local/server example (`inst/examples/local_auth.R`) is now runnable
  out-of-the-box: it sets a default `SHINYMANAGER_KEY` if none is present,
  re-seeds a fresh database each run with `create_user_db(overwrite = TRUE)`,
  and prints the 2FA code to the console (demo mode) so the full flow works
  without a Pushover account. Previously a first run without `SHINYMANAGER_KEY`
  left an empty database that later runs reused, so the documented credentials
  returned "invalid credentials".

# shinymanager.webr 0.2.0

## New features

* All authentication UI is now built with **muiMaterial** (Material UI via shiny.react).
* **Two access variants** share one package:
  * **webR / external** — `welcome_panel()` adds an editable muiMaterial welcome
    screen (logo + free content + access button) for use as the `waiting_ui` of
    `secure_app_external()`. The button injects a configurable identity, so the
    external flow doubles as a "no login" gate.
  * **local / server** — credential login + Pushover two-factor authentication:
    * `secure_app_local()` / `secure_server_local()` drive a login -> 2FA -> app
      flow against a duckdb user store.
    * `check_credentials_local()` validates email + password and exposes the user
      profile (JSON) to the session, never the password hash or Pushover key.
    * `create_user_db()` / `add_user()` provision users; passwords are hashed with
      Argon2id (`sodium`) and the per-user Pushover key is encrypted (`openssl`,
      key from the `SHINYMANAGER_KEY` environment variable).
    * 6-digit Pushover code valid 30s with attempt limiting, six-cell input
      widget, and a per-device "remember for 24h" cookie that skips 2FA.

## Infrastructure

* Server-variant dependencies (`DBI`, `duckdb`, `sodium`, `openssl`, `pushoverr`)
  are `Suggests` loaded via `requireNamespace()`, so the package still installs in
  webR; `muiMaterial` and `jsonlite` are now `Imports`.
* Added package-level `@import shiny` (fixes server functions that referenced
  shiny functions unqualified).
* Tests added: `test-crypto`, `test-local-auth`, `test-2fa-flow` (testthat
  edition 3, Pushover mocked).

# shinymanager.webr 0.1.1

* Fixed external domain authorization when only `allowed_domains` is supplied.
* Fixed server-side auth state restoration after the UI token gate accepts a session token.

# shinymanager.webr 0.1.0

* Initial lightweight fork for Shiny apps running with webR/WebAssembly.
* Authentication is delegated to an external identity provider such as Auth0.
* Added `secure_app_external()`, `secure_server_external()`, and `check_credentials_external()`.
* Kept the shinymanager visual container, language labels, session token gate, and floating logout button.
* Removed classic username/password login, SQLite/SQL credential storage, admin panel, password management, and related heavy dependencies.
