library(shiny)
library(shinymanager.webr)

ui <- secure_app_external(
  fluidPage(
    h2("Proteomics app")
  )
)

server <- function(input, output, session) {
  secure_server_external(
    check_credentials = check_credentials_external(
      allowed_domains = "cnb.csic.es",
      require_verified_email = TRUE
    ),
    external_input = "auth0_user",
    logout_url = "https://TU_DOMINIO_AUTH0/v2/logout?client_id=TU_CLIENT_ID&returnTo=https%3A%2F%2Ftu-app"
  )
}

shinyApp(ui, server)
