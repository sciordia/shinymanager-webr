#' Adds the content of inst/assets/ to authlas/
#'
#' @importFrom shiny addResourcePath
#'
#' @noRd
#'
.onLoad <- function(...) {
  shiny::addResourcePath("authlas", system.file("assets", package = "authlas"))
}
