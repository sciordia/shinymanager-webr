# authlas 0.4.1

## Changes

* The local/server two-factor step now allows **3 code attempts** (was 5) before
  returning the user to the login screen, and each failed attempt reports how many
  tries remain. Issuing a fresh code (re-login or *Resend*) resets the counter. The
  cap is still configurable via `secure_server_local(max_attempts = ...)`.

# authlas 0.4.0

## Breaking changes

* **The package has been renamed from `shinymanager.webr` to `authlas`** and is now a standalone
  package (no longer presented as a fork of `shinymanager`, from which it was originally derived,
  GPL-3). Update `library(shinymanager.webr)` to `library(authlas)`.
* The master-key environment variable is now **`AUTHLAS_KEY`**. The legacy `SHINYMANAGER_KEY` is
  still read as a fallback when `AUTHLAS_KEY` is unset, so existing deployments keep working.
* Bundled assets are now served from the `authlas/` Shiny resource path (was `shinymanager/`). This
  is internal; apps using the public API are unaffected.

Internal Shiny input ids, the device cookie (`shinymanager_device`) and CSS classes are unchanged.

# shinymanager.webr 0.3.0

## Features

* Two-factor authentication is now **optional per user** in the local/server
  variant. Each user has a `twofa_enabled` flag stored in the database; when
  `FALSE`, a valid password logs the user straight into the app with no Pushover
  step. Defaults to `TRUE` (unchanged behaviour).
* The "remember this device" lifetime is now configurable **per user** via the
  `device_ttl_hours` column. When a user has no value of their own, the server's
  `device_ttl_hours` argument (default 24) applies.
* `add_user()` gains `twofa_enabled` and `device_ttl_hours` arguments, and a new
  `set_user_settings()` function updates both for an existing user
  (`device_ttl_hours = NA` clears the per-user override).
* `check_credentials_local()` now also returns `twofa_enabled` and
  `device_ttl_hours` at the top level (kept out of the public `user_info`).
* Databases created by earlier versions are migrated automatically: the new
  columns are added on first open (`ALTER TABLE ... ADD COLUMN IF NOT EXISTS`),
  so existing user stores keep working without being recreated.

# shinymanager.webr 0.2.2

## Fixes

* Authentication screens are now built with `muiMaterial::muiMaterialPage()` +
  `CssBaseline()` instead of `shiny::fluidPage()`, following muiMaterial's
  guidance. Previously the Material UI login/2FA/welcome components were rendered
  inside `fluidPage()`, mixing Bootstrap with Material UI; Bootstrap's
  `html { font-size: 10px }` broke MUI's rem-based sizing (e.g. `Typography()`
  rendered too small). Bootstrap is now suppressed on the auth page.
* The `theme` argument of `secure_app_external()` / `secure_app_local()` is
  deprecated and ignored (Bootstrap no longer applies to the auth page).
* Auth assets are injected via an `htmlDependency` so they reach the document
  `<head>` under `muiMaterialPage()`.
* Examples and README now build the protected app UI from muiMaterial components
  too, instead of `fluidPage()`.

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
