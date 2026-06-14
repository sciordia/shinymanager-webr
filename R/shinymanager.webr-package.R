#' shinymanager.webr: lightweight access container for Shiny and webR
#'
#' Two access variants share one package: an external/no-login gate for apps
#' running in the browser with webR, and a server variant with credential login,
#' Argon2id password hashing, a duckdb user store and Pushover two-factor
#' authentication. The UI is built with muiMaterial (Material UI).
#'
#' @keywords internal
#' @import shiny
#' @importFrom htmltools tags tagList HTML
"_PACKAGE"
