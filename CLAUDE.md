# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this package is

`shinymanager.webr` is a lightweight fork of `shinymanager` for Shiny apps running with
webR/WebAssembly. Authentication is delegated to an **external** identity provider (Auth0/OIDC)
in the browser. This package only manages the access gate, authorization rules, an in-memory
session token, and a floating logout button.

Key consequence: the classic shinymanager features are **deliberately removed** — no
username/password login form, no SQLite credentials database, no admin panel, no password
management, and no heavy dependencies. The only Imports are `R6`, `shiny`, and `htmltools`.
Do not reintroduce database/credential storage; webR apps run entirely in the browser with no
persistent server.

## Development commands

This is a standard R package documented with roxygen2 and tested with testthat.

```r
# Regenerate NAMESPACE and man/*.Rd from roxygen comments (run after changing @export/@param)
devtools::document()

# Load the package for interactive work
devtools::load_all()

# Run the full test suite
devtools::test()

# Run a single test file
testthat::test_file("tests/testthat/test-tokens.R")

# Full R CMD check
devtools::check()
```

Tests live in `tests/testthat/`: `test-external-auth.R`, `test-language.R`, `test-tokens.R`.

## Architecture

The whole package is the three-function public API in `R/external-auth.R` plus supporting
infrastructure. The auth flow is: external provider verifies identity in JS → JS pushes the
identity into Shiny via `Shiny.setInputValue()` → server authorizes it → a session token is
minted in memory and persisted in the URL query string.

### Public API (`R/external-auth.R`)
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

### Session token manager (`R/tokens.R`)
An R6 class `.tokens`, instantiated once as the package-global `.tok`. **In-memory only, not
persisted.** Provides `generate()` (64-char token), `add()`, `get()`, `remove()`, and the
validation variants: `is_valid()` is single-use (replay protection on initial page load),
`is_valid_server()` allows repeated checks, `is_valid_timeout()` enforces the timeout window.

### URL/query-string session state (`R/shiny-utils.R`)
Because webR has no server-side sessions or cookies, auth state lives in the URL. Helpers:
`getToken()`, `addAuthToQuery()`, `clearQueryString()`, `resetQueryString()`, `getLanguage()`,
plus hidden inputs `shinymanager_where()` and `shinymanager_language()`.

### i18n (`R/language.R`)
`pkgEnv` holds label dictionaries for 11 languages (en, fr, pt-BR, es, de, pl, ja, el, id,
zh-CN, no). Public: `use_language()`, `set_labels()`, `get_labels()`. Most legacy labels are
unused since the classic login UI was removed.

### UI / assets
- `R/fab_button.R` — `fab_button()` renders the Material-design floating logout button.
- `R/onLoad.R` — `.onLoad()` registers `inst/assets/` as the Shiny resource path `"shinymanager"`.
- `inst/assets/` — `styles-auth.css`, `timeout.js`, the `fab-button/` SCSS+CSS, the readable
  Bootstrap theme, and Raleway fonts.
- `R/utils.R` — `save_logs()`/`logout_logs()` are intentional no-op stubs (DB logging removed).

## Conventions

- After editing roxygen comments or exports, run `devtools::document()` — `NAMESPACE` and
  `man/*.Rd` are generated, not hand-edited.
- The external identity arrives from JavaScript on `input$auth0_user` by default
  (`external_input` argument). Keep server/JS input names in sync when changing it.
