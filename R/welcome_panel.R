#' @title Welcome panel for the webR access gate
#'
#' @description Build an editable welcome screen, rendered with 'muiMaterial'
#'   (Material UI), to use as the \code{waiting_ui} of
#'   \code{\link{secure_app_external}} in the webR variant. There is no login
#'   form: the application code runs in the browser, so access is only gated by a
#'   single button. Clicking the button pushes a (configurable) identity into
#'   Shiny via \code{Shiny.setInputValue()}, which \code{secure_server_external}
#'   then authorizes. The application HTML stays hidden inside the container until
#'   the button is pressed.
#'
#' @param ... Static content to display between the logo and the button. Any
#'   'muiMaterial' component or \code{htmltools}/\code{shiny} tag is accepted, so
#'   the screen can be freely customized.
#' @param logo Optional logo. Either a URL/path (character, rendered as an
#'   \code{<img>}) or a tag built by the caller.
#' @param button_label Text of the access button.
#' @param button_id Shiny input id the button writes to. Must match the
#'   \code{external_input} passed to \code{\link{secure_server_external}}.
#' @param identity Named list pushed as the external identity when the button is
#'   clicked (e.g. \code{list(user = "guest", name = "Invitado")}). Use
#'   \code{NULL} to push an empty object.
#' @param button_props Named list of extra props forwarded to the 'muiMaterial'
#'   \code{Button} (e.g. \code{variant}, \code{size}, \code{color}).
#' @param max_width Maximum width (px) of the centered content column.
#'
#' @return A \code{shiny.tag} suitable as the \code{waiting_ui} argument of
#'   \code{\link{secure_app_external}}.
#'
#' @seealso \code{\link{secure_app_external}}. A runnable example app:
#'   \code{system.file("examples", "welcome_webr.R", package = "shinymanager.webr")}.
#'
#' @export
#'
#' @importFrom htmltools tags
#' @importFrom jsonlite toJSON
#'
#' @examples
#' if (interactive()) {
#'   library(shiny)
#'   library(shinymanager.webr)
#'
#'   ui <- secure_app_external(
#'     ui = fluidPage(h2("App protegida"), verbatimTextOutput("auth")),
#'     waiting_ui = welcome_panel(
#'       muiMaterial::Typography("Bienvenido a la aplicacion", variant = "h5"),
#'       logo = "https://www.r-project.org/logo/Rlogo.png",
#'       button_label = "Acceder",
#'       button_id = "no_login"
#'     )
#'   )
#'
#'   server <- function(input, output, session) {
#'     auth <- secure_server_external(
#'       check_credentials = check_credentials_external(),
#'       external_input = "no_login",
#'       timeout = 0
#'     )
#'     output$auth <- renderPrint(reactiveValuesToList(auth))
#'   }
#'
#'   shinyApp(ui, server)
#' }
welcome_panel <- function(...,
                          logo = NULL,
                          button_label = "Acceder",
                          button_id = "no_login",
                          identity = list(user = "guest", name = "Invitado", auth_provider = "none"),
                          button_props = list(variant = "contained", size = "large", color = "primary"),
                          max_width = 520) {

  identity_json <- if (is.null(identity)) "{}" else as.character(toJSON(identity, auto_unbox = TRUE))
  onclick_js <- sprintf(
    "function() { Shiny.setInputValue('%s', %s, {priority: 'event'}); }",
    button_id, identity_json
  )

  if (is.character(logo)) {
    logo <- tags$img(src = logo, style = "max-width: 200px; margin-bottom: 16px;")
  }

  button <- do.call(
    muiMaterial::Button,
    c(list(button_label, onClick = muiMaterial::JS(onclick_js)), button_props)
  )

  tags$div(
    class = "panel-auth",
    muiMaterial::Box(
      sx = list(
        display = "flex",
        flexDirection = "column",
        alignItems = "center",
        justifyContent = "center",
        minHeight = "100vh",
        gap = 2,
        padding = 4,
        textAlign = "center",
        maxWidth = max_width,
        marginLeft = "auto",
        marginRight = "auto"
      ),
      logo,
      ...,
      button
    )
  )
}
