# webR (external) variant: editable welcome screen, no credentials, muiMaterial UI.
#
# This variant is meant for apps running in the browser with webR, where the
# code is exposed: there is no real login. A single button gates access and the
# app HTML stays hidden inside the container until it is pressed. The button
# injects a configurable identity, which check_credentials_external() authorizes.
#
# Runs anywhere (no extra setup): the only Imports are R6, shiny, htmltools,
# jsonlite and muiMaterial. To deploy in webR, ship this app with shinylive.

library(shiny)
library(shinymanager.webr)

ui <- secure_app_external(
  ui = tagList(
    muiMaterial::CssBaseline(),
    muiMaterial::Box(
      sx = list(p = 3),
      muiMaterial::Typography("Protected app (webR variant)", variant = "h4"),
      verbatimTextOutput("whoami")
    )
  ),
  waiting_ui = welcome_panel(
    muiMaterial::Typography("Welcome to the application", variant = "h5"),
    muiMaterial::Typography(
      "Press the button to enter.", variant = "body2"
    ),
    logo         = "https://www.r-project.org/logo/Rlogo.png",
    button_label = "Enter",
    button_id    = "no_login",
    identity     = list(user = "guest", name = "Guest", auth_provider = "none")
  )
)

server <- function(input, output, session) {
  auth <- secure_server_external(
    check_credentials = check_credentials_external(),  # no restrictions: open gate
    external_input    = "no_login",
    timeout           = 0
  )

  output$whoami <- renderPrint({
    list(user = auth$user, name = auth$name, provider = auth$auth_provider)
  })
}

shinyApp(ui, server)
