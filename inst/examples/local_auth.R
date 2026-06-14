# Server (local) variant: credential login + Pushover two-factor auth, muiMaterial UI.
#
# This variant runs on a real server (not webR): the app code is not exposed to
# the browser, so a real login form is shown. Passwords are hashed with Argon2id
# and the per-user Pushover key is stored encrypted.
#
# Setup before running:
#   1. Master key used to encrypt stored Pushover keys (keep it secret/stable):
#        Sys.setenv(SHINYMANAGER_KEY = "<a-long-random-secret>")
#   2. Your Pushover application (API) token:
#        Sys.setenv(PUSHOVER_APP = "<your-pushover-app-token>")
#   3. Provision users with add_user() (done here once into a temp duckdb). Each
#      user needs a valid Pushover *user key* to receive the 2FA code.
#
# Tip: to try the flow without sending real Pushover notifications, override the
# internal sender so the code is printed instead:
#   assignInNamespace(
#     "send_2fa",
#     function(db, user_id, code, pushover_app_token, title = "x") {
#       message(">>> 2FA code: ", code); TRUE
#     },
#     "shinymanager.webr"
#   )

library(shiny)
library(shinymanager.webr)

# --- one-off database setup -------------------------------------------------
db <- file.path(tempdir(), "users.duckdb")
if (!file.exists(db)) {
  create_user_db(db)
  add_user(
    db,
    email             = "sergio@example.org",
    password          = "S3cr3t!",                          # hashed (Argon2id)
    pushover_user_key = "REPLACE_WITH_USER_PUSHOVER_KEY",   # encrypted at rest
    name              = "Sergio",
    role              = "admin",
    profile           = list(lab = "Genomics", projects = 3)
  )
}

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
