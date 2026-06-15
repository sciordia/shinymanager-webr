# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this package is

`shinymanager.webr` is a fork of `shinymanager` providing an access gate for Shiny apps, with
**two deployment variants** that share one package. All auth UI is built with **muiMaterial**
(Material UI via shiny.react). Imports are kept light (`R6`, `shiny`, `htmltools`, `jsonlite`,
`muiMaterial`); everything the server variant needs is in `Suggests` and loaded on demand, so the
package still installs in webR.

1. **External / webR variant** (`R/external-auth.R`, `R/welcome_panel.R`). Authentication is
   delegated to an external provider (Auth0/OIDC) or simply gated by a button. The app runs in the
   browser with webR, so there is no credentials form; the package manages the access gate,
   authorization rules, an in-memory session token (persisted in the URL), and a floating logout
   button. The app HTML stays hidden inside the container until access is granted.

2. **Local / server variant** (`R/local-auth.R`, `R/db.R`, `R/crypto.R`). For apps hosted on a
   real server (code not exposed). Credential login (email + password) against a **duckdb** user
   store, passwords hashed with **Argon2id** (`sodium`), per-user Pushover key stored **encrypted**
   (`openssl`), then **two-factor authentication**: a 6-digit code sent via **Pushover**
   (`pushoverr`), valid for 30 s, with a per-device "remember device" cookie that skips 2FA.
   Whether 2FA is required at all, and the remember-device lifetime, are **per-user settings
   stored in the database** (`twofa_enabled`, `device_ttl_hours`); a user with 2FA disabled logs
   straight in after a valid password.

The server variant deliberately reintroduces DB/credentials (reversing the original fork's
"no DB" stance), but only behind `Suggests` + `requireNamespace()`, so the webR path never loads
those dependencies.

## Development commands

This is a standard R package documented with roxygen2 and tested with testthat.

```r
# Regenerate NAMESPACE and man/*.Rd from roxygen comments (run after changing @export/@param)
roxygen2::roxygenise()        # or devtools::document()

# Load the package for interactive work (devtools or the lighter pkgload)
pkgload::load_all(".")        # or devtools::load_all()

# Run the full test suite (needs SHINYMANAGER_KEY set for the crypto/local tests)
Sys.setenv(SHINYMANAGER_KEY = "test-master-key")
pkgload::load_all("."); testthat::test_dir("tests/testthat")   # or devtools::test()

# Full R CMD check
devtools::check()
```

Tests live in `tests/testthat/`: `test-external-auth.R`, `test-language.R`, `test-tokens.R`
(external/webR variant), plus `test-crypto.R`, `test-local-auth.R`, `test-2fa-flow.R` (server
variant; they `skip_if_not_installed()` the Suggests and need `SHINYMANAGER_KEY`). testthat uses
edition 3. The server tests drive the flow with `shiny::testServer()` and mock `send_2fa()` /
`generate_2fa_code()` via `local_mocked_bindings()` to avoid hitting Pushover.

## Architecture

Both variants share the same backbone: an R6 in-memory token manager (`.tok`), the URL/query-string
state helpers, i18n, the floating logout button, and the inactivity timeout. They differ in how
identity is acquired. Package-level `@import shiny` (in `R/shinymanager.webr-package.R`) makes all
of shiny available to the namespace — required because the server functions use many shiny
functions unqualified.

### External / webR flow (`R/external-auth.R`)
The flow is: external provider verifies identity in JS → JS pushes the identity into Shiny via
`Shiny.setInputValue()` → server authorizes it → a session token is minted in memory and persisted
in the URL query string.

#### Public API (`R/external-auth.R`)
- `secure_app_external(ui, ...)` — UI wrapper / access gate. Validates the token from the query
  string with `is_valid()`; if valid renders the app + floating logout button + timeout script,
  otherwise shows the waiting/login UI. Supports 11 languages and a custom Bootstrap theme.
- `secure_server_external(check_credentials, external_input = "auth0_user", ...)` — server logic.
  Observes the external identity input, runs `check_credentials`, mints/validates the token,
  appends it to the URL, handles logout (`logout_url` redirect or `logout_callback`) and session
  timeout (`invalidateLater`, checked every 30s).
- `check_credentials_external(allowed_users, allowed_domains, require_verified_email, user_info)`
  — returns a validation function. Authorizes by email allowlist and/or email domain, with an
  optional verified-email requirement. `normalize_external_identity()` standardizes the incoming
  identity object (email/user/name/sub/email_verified).
- `welcome_panel(..., logo, button_label, button_id, identity)` (`R/welcome_panel.R`) — editable
  muiMaterial welcome screen used as `waiting_ui`. The button injects a configurable identity via
  `onClick = muiMaterial::JS(...)`. With `check_credentials_external()` (no restrictions) this is
  the "no login" gate.

### Local / server flow (`R/local-auth.R`, `R/db.R`, `R/crypto.R`)
The flow is: login form → verify credentials (Argon2id) against duckdb → if the user has 2FA
disabled (`twofa_enabled = FALSE`) mint the token immediately; else if a valid device cookie exists
skip 2FA, else generate a 6-digit code, store its hash + timestamp + attempt counter in duckdb,
send it via Pushover → 2FA screen (six cells) → on success mint the session token (same `.tok`),
set the device cookie (per-user `device_ttl_hours`, falling back to the server default), and reload
into the app. Profile fields (stored as JSON in the user row) are exposed to the session exactly
like the external variant's `user_info`; the per-user policy fields (`twofa_enabled`,
`device_ttl_hours`) are returned by `check_credentials_local()` at the top level, **not** inside
`user_info`.

- `secure_app_local(ui, ...)` — UI gate. When the token is invalid it renders a
  `muiMaterial::muiMaterialPage()` (with `CssBaseline()`) hosting both the login and 2FA screens as
  static `conditionalPanel`s toggled by `output.sm_stage`. Auth CSS/JS (`styles-local.css`,
  `device-cookie.js`, `twofa.js`) are injected via the `sm_auth_dependency()` htmlDependency.
- `secure_server_local(check_credentials, db, pushover_app_token, ...)` — the login/2FA state
  machine (`rv$stage` = login/twofa), device-cookie checks, resend/cancel, logout and timeout
  (reusing the external scaffolding). Returns reactive values with the user profile.
- `check_credentials_local(db, allowed_roles)` — validates email+password against duckdb and returns
  the `list(result, expired, authorized, user_info)` shape **plus** the top-level policy fields
  `twofa_enabled` and `device_ttl_hours`. **Never exposes the password hash, Pushover key, or the
  policy fields** in `user_info`.
- `R/db.R` — duckdb schema (`users`, `twofa_codes`, `device_tokens`; timestamps as epoch seconds).
  The `users` table carries the per-user policy columns `twofa_enabled` and `device_ttl_hours`.
  Public helpers: `create_user_db()`, `add_user()` (both take `twofa_enabled`/`device_ttl_hours`),
  and `set_user_settings()` (update those for an existing user; `device_ttl_hours = NA` clears the
  override). Internal: `db_get_user()`, `db_set_twofa()`, `db_add_device()`, `db_check_device()`,
  etc., plus `db_ensure_user_settings()` which `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` migrates
  pre-existing databases (called from `create_user_db()`, `add_user()`, and the user readers).
  `with_con()` accepts a path or an open connection.
- `R/crypto.R` — `hash_password()`/`verify_password()` (Argon2id via `sodium`),
  `encrypt_secret()`/`decrypt_secret()` (AES-CBC via `openssl`, key from `SHINYMANAGER_KEY`),
  `generate_2fa_code()`. Password = one-way hash; Pushover key = reversible encryption.

### Session token manager (`R/tokens.R`)
An R6 class `.tokens`, instantiated once as the package-global `.tok`. **In-memory only, not
persisted.** Provides `generate()` (64-char token), `add()`, `get()`, `remove()`, and the
validation variants: `is_valid()` is single-use (replay protection on initial page load),
`is_valid_server()` allows repeated checks, `is_valid_timeout()` enforces the timeout window.

### URL/query-string session state (`R/shiny-utils.R`)
The session token lives in the URL query string (webR has no server-side sessions). Helpers:
`getToken()`, `addAuthToQuery()`, `clearQueryString()`, `resetQueryString()`, `getLanguage()`,
plus hidden inputs `shinymanager_where()` and `shinymanager_language()`. The server variant
additionally uses a real browser **cookie** (`shinymanager_device`, via `inst/assets/device-cookie.js`)
for the 24 h device-remember feature — available because it runs on a server, unlike webR.

### i18n (`R/language.R`)
`pkgEnv` holds label dictionaries for 11 languages (en, fr, pt-BR, es, de, pl, ja, el, id,
zh-CN, no). Public: `use_language()`, `set_labels()`, `get_labels()`. Most legacy labels are
unused since the classic login UI was removed.

### UI / assets
- `R/fab_button.R` — `fab_button()` renders the Material-design floating logout button.
- `R/onLoad.R` — `.onLoad()` registers `inst/assets/` as the Shiny resource path `"shinymanager"`,
  so any file added there is served under `shinymanager/...` automatically.
- `inst/assets/` — `styles-auth.css`, `timeout.js`, the `fab-button/` SCSS+CSS, the readable
  Bootstrap theme, Raleway fonts, plus the server-variant assets `styles-local.css`, `twofa.js`
  (six-cell widget → `input$sm_2fa_code`) and `device-cookie.js`.
- `R/utils.R` — `save_logs()`/`logout_logs()` are intentional no-op stubs.

## Conventions

- After editing roxygen comments or exports, run `roxygen2::roxygenise()` (or `devtools::document()`)
  — `NAMESPACE` and `man/*.Rd` are generated, not hand-edited.
- The external identity arrives from JavaScript on `input$auth0_user` by default
  (`external_input` argument). Keep server/JS input names in sync when changing it.
- Build auth UI with **muiMaterial** components (`Box`, `Typography`, `Button.shinyInput`,
  `TextField.shinyInput`, ...). They carry their own React dependencies automatically.
- Auth pages must use `muiMaterial::muiMaterialPage()` + `CssBaseline()` (Bootstrap suppressed),
  **never** `shiny::fluidPage()` — mixing Bootstrap with Material UI breaks MUI's rem sizing (per
  muiMaterial's "CSS conflicts with Bootstrap" guidance). The `theme` argument of the `secure_app_*`
  functions is deprecated/ignored as a result. Inject auth assets via `sm_auth_dependency()`
  (`R/shiny-utils.R`), not a `tags$head()` inside the page. The authenticated app's `ui` is the
  developer's responsibility, but examples/docs model muiMaterial there too (no `fluidPage`).
- Server-variant code must keep heavy deps optional: declare them in `Suggests` and guard every use
  with `require_pkg("<pkg>")` (in `R/crypto.R`) + `pkg::fn()`. Never promote `duckdb`, `DBI`,
  `sodium`, `openssl` or `pushoverr` to `Imports` — that would break webR installation.
- The master encryption key comes from the `SHINYMANAGER_KEY` environment variable; the server
  tests and any app using the local variant must set it.
