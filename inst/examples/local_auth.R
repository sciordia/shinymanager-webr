# Server (local) variant: credential login + Pushover two-factor auth, muiMaterial UI.
#
# This variant runs on a real server (not webR): the app code is not exposed to
# the browser, so a real login form is shown. Passwords are hashed with Argon2id
# and the per-user Pushover key is stored encrypted.
#
# This file is a SELF-CONTAINED DEMO: it runs out-of-the-box with no external
# setup and no Pushover account. The 2FA code is printed to the R console.
# See the PRODUCTION NOTES at the bottom for what to change for a real deployment.
#
# Log in with:  sergio@example.org  /  S3cr3t!

library(shiny)
library(shinymanager.webr)

# --- demo configuration (REPLACE for production) ----------------------------

# Master key used to encrypt stored Pushover keys. For the demo we set a default
# if none is present; in production set SHINYMANAGER_KEY via an environment
# variable, keep it secret and stable, and remove this fallback.
if (!nzchar(Sys.getenv("SHINYMANAGER_KEY"))) {
  Sys.setenv(SHINYMANAGER_KEY = "demo-shinymanager-key-change-me")
}

# DEMO ONLY: print the 2FA code to the console instead of delivering it via
# Pushover, so the flow can be completed without a Pushover account. Remove this
# block in production (and set PUSHOVER_APP + each user's real Pushover key).
assignInNamespace(
  "send_2fa",
  function(db, user_id, code, pushover_app_token, title = "x") {
    message(">>> [DEMO] 2FA code: ", code)
    TRUE
  },
  "shinymanager.webr"
)

# --- database setup (re-seeded fresh on each run for the demo) ---------------
db <- file.path(tempdir(), "users.duckdb")
create_user_db(db, overwrite = TRUE)
add_user(
  db,
  email             = "sergio@example.org",
  password          = "S3cr3t!",                  # hashed (Argon2id)
  pushover_user_key = "demo-user-key",            # unused in demo (send_2fa stubbed)
  name              = "Sergio",
  role              = "admin",
  profile           = list(lab = "Genomics", projects = 3)
)

# --- app --------------------------------------------------------------------
ui <- secure_app_local(
  ui = fluidPage(
    h2("Protected app (server variant)"),
    verbatimTextOutput("whoami")
  ),
  twofa_window = 30
)

server <- function(input, output, session) {
  auth <- secure_server_local(
    check_credentials  = check_credentials_local(db),
    db                 = db,
    pushover_app_token = Sys.getenv("PUSHOVER_APP"),
    twofa_window       = 30,
    remember_device    = TRUE,
    timeout            = 15
  )

  # The authenticated profile is available to the app through `auth`.
  output$whoami <- renderPrint({
    list(email = auth$email, name = auth$name, role = auth$role, lab = auth$lab)
  })
}

shinyApp(ui, server)

# --- PRODUCTION NOTES -------------------------------------------------------
# 1. Set SHINYMANAGER_KEY (a long, stable secret) via an environment variable
#    and remove the fallback above.
# 2. Remove the assignInNamespace(send_2fa, ...) demo block.
# 3. Set PUSHOVER_APP to your Pushover application (API) token, and give each
#    user a real Pushover user key via add_user(..., pushover_user_key = ...).
# 4. Provision users once into a persistent duckdb file (not tempdir()), e.g.
#    with a separate admin script, instead of re-seeding on every run.
