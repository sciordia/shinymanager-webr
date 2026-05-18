# shinymanager.webr

Lightweight external-authentication container for Shiny apps running with webR/WebAssembly.

`shinymanager.webr` is a small fork of `shinymanager` focused on one flow:

1. Wait for an external identity provider such as Auth0.
2. Authorize the identity by email and/or email domain.
3. Create a local session token.
4. Reveal the Shiny application.
5. Provide a floating logout button that clears the local token and redirects to Auth0, or calls a JavaScript logout callback.

Classic username/password login, SQLite/SQL credential storage, admin panels, password management, and heavy dependencies are intentionally not part of this package.

## Install

```r
remotes::install_local("path/to/shinymanager-webr")
```

## Example

```r
library(shiny)
library(shinymanager.webr)

ui <- secure_app_external(
  fluidPage(
    h2("Proteomics app")
  )
)

server <- function(input, output, session) {
  auth <- secure_server_external(
    check_credentials = check_credentials_external(
      allowed_domains = "cnb.csic.es",
      require_verified_email = TRUE
    ),
    external_input = "auth0_user",
    logout_url = "https://TU_DOMINIO_AUTH0/v2/logout?client_id=TU_CLIENT_ID&returnTo=https%3A%2F%2Ftu-app"
  )
}

shinyApp(ui, server)
```

From JavaScript/Auth0, send the resolved identity to Shiny:

```js
Shiny.setInputValue("auth0_user", {
  email: user.email,
  name: user.name,
  sub: user.sub,
  email_verified: user.email_verified,
  auth_provider: "auth0"
}, { priority: "event" });
```

## Logout

If `logout_url` is supplied, the floating logout button removes the local `shinymanager.webr` token, clears the local URL, and redirects the browser to the Auth0 logout URL.

Alternatively, pass `logout_callback = "nombreFuncionGlobal"` and define:

```js
window.nombreFuncionGlobal = function(message) {
  // Auth0 SDK logout flow here.
};
```

## Public API

```r
secure_app_external()
secure_server_external()
check_credentials_external()
fab_button()
use_language()
set_labels()
get_labels()
```
