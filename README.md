# shinymanager.webr

Lightweight access container for Shiny apps, with two deployment variants that
share one package. All authentication UI is built with
[muiMaterial](https://felixluginbuhl.com/muiMaterial/) (Material UI).

1. **webR / external** — for apps running in the browser with webR/WebAssembly.
   Authentication is delegated to an external provider (Auth0/OIDC) or simply
   gated by a button. There is no credentials form, and the application HTML
   stays hidden inside the container until access is granted.
2. **local / server** — for apps hosted on a real server (code not exposed).
   Credential login against a [duckdb](https://duckdb.org/) user store, with
   passwords hashed using Argon2id and a Pushover two-factor step.

Heavy dependencies for the server variant (`DBI`, `duckdb`, `sodium`, `openssl`,
`pushoverr`) are declared in `Suggests` and loaded on demand, so the package
still installs in webR — the webR path never touches them.

The authentication screens are rendered with `muiMaterial::muiMaterialPage()` +
`CssBaseline()` (Bootstrap suppressed), following muiMaterial's guidance. Do not
mix `shiny::fluidPage()` with Material UI components on the same page; when your
protected app uses muiMaterial, build its UI from muiMaterial components too (see
the examples below) rather than `fluidPage()`.

## Install

```r
remotes::install_local("path/to/shinymanager-webr")
```

## Variant 1 — webR / external

Delegate to an external provider, or use `welcome_panel()` as a button-only gate
(no login). The button injects a configurable identity that
`check_credentials_external()` authorizes.

```r
library(shiny)
library(shinymanager.webr)

ui <- secure_app_external(
  ui = tagList(
    muiMaterial::CssBaseline(),
    muiMaterial::Box(sx = list(p = 3),
      muiMaterial::Typography("Protected app", variant = "h4"),
      verbatimTextOutput("auth"))
  ),
  waiting_ui = welcome_panel(
    muiMaterial::Typography("Welcome to the application", variant = "h5"),
    logo = "https://www.r-project.org/logo/Rlogo.png",
    button_label = "Enter",
    button_id = "no_login"
  )
)

server <- function(input, output, session) {
  auth <- secure_server_external(
    check_credentials = check_credentials_external(),  # open gate
    external_input = "no_login",
    timeout = 0
  )
  output$auth <- renderPrint(reactiveValuesToList(auth))
}

shinyApp(ui, server)
```

For Auth0/OIDC, restrict by email/domain and push the identity from JavaScript:

```r
check_credentials_external(allowed_domains = "cnb.csic.es", require_verified_email = TRUE)
```

```js
Shiny.setInputValue("auth0_user", {
  email: user.email, name: user.name, sub: user.sub,
  email_verified: user.email_verified, auth_provider: "auth0"
}, { priority: "event" });
```

Full example: `system.file("examples", "welcome_webr.R", package = "shinymanager.webr")`.

## Variant 2 — local / server (login + 2FA)

Email + password against duckdb, then a 6-digit Pushover code (valid 30s, with
attempt limiting). A per-device cookie can skip 2FA for a while. The user profile
is exposed to the session like the external variant's `user_info`.

Whether the 2FA step is required, and how long a remembered device skips it, are
decided **per user** and stored in the database:

- `twofa_enabled` (default `TRUE`) — set to `FALSE` to log a user straight into
  the app once the password matches, with no Pushover step.
- `device_ttl_hours` — per-user lifetime of the "remember this device" token;
  when unset (`NULL`), the server's `device_ttl_hours` (default 24) applies.

Set them at creation with `add_user(...)` or change them later for an existing
user with `set_user_settings(db, email, twofa_enabled = ..., device_ttl_hours = ...)`
(pass `device_ttl_hours = NA` to clear the override). Databases created by older
versions gain these columns automatically the first time they are opened.

```r
library(shiny)
library(shinymanager.webr)

Sys.setenv(SHINYMANAGER_KEY = "<a-long-random-secret>")  # encrypts stored Pushover keys

# One-off provisioning
db <- "users.duckdb"
create_user_db(db)
add_user(db, email = "user@example.org", password = "S3cr3t!",
         pushover_user_key = "<user-pushover-key>", name = "User", role = "admin",
         profile = list(lab = "Genomics"),
         twofa_enabled = TRUE, device_ttl_hours = 24)   # per-user 2FA policy

ui <- secure_app_local(
  ui = tagList(
    muiMaterial::CssBaseline(),
    muiMaterial::Box(sx = list(p = 3),
      muiMaterial::Typography("Protected app", variant = "h4"),
      verbatimTextOutput("auth"))
  )
)

server <- function(input, output, session) {
  auth <- secure_server_local(
    check_credentials = check_credentials_local(db),
    db = db,
    pushover_app_token = Sys.getenv("PUSHOVER_APP")
  )
  output$auth <- renderPrint(reactiveValuesToList(auth))
}

shinyApp(ui, server)
```

- **Passwords** are hashed one-way with Argon2id (`sodium`).
- **Pushover user keys** are encrypted (reversible, AES-CBC via `openssl`) with the
  master key from the `SHINYMANAGER_KEY` environment variable.
- Set `PUSHOVER_APP` to your Pushover application (API) token.

Full example (incl. a no-Pushover testing tip):
`system.file("examples", "local_auth.R", package = "shinymanager.webr")`.

## Logout

Both variants render a floating logout button (`fab_button()`) that removes the
local session token. In the external variant, supplying `logout_url` redirects
the browser to the provider's logout URL after clearing the token; alternatively
`logout_callback = "globalFnName"` calls a JavaScript function:

```js
window.globalFnName = function(message) {
  // Auth0 SDK logout flow here.
};
```

## Public API

```r
# External / webR variant
secure_app_external(); secure_server_external(); check_credentials_external()
welcome_panel()

# Local / server variant
secure_app_local(); secure_server_local(); check_credentials_local()
create_user_db(); add_user(); set_user_settings()
hash_password(); verify_password(); encrypt_secret(); decrypt_secret()

# Shared
fab_button(); use_language(); set_labels(); get_labels()
```
