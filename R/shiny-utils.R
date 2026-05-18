# Send input value to know where we are (auth or app).
shinymanager_where <- function(where) {
  tags$div(
    style = "display: none;",
    selectInput(inputId = "shinymanager_where", label = NULL,
                choices = where, selected = where, multiple = FALSE)
  )
}

shinymanager_language <- function(lan) {
  tags$div(
    style = "display: none;",
    selectInput(inputId = "shinymanager_language", label = NULL,
                choices = lan, selected = lan, multiple = FALSE)
  )
}

#' @importFrom shiny updateQueryString getDefaultReactiveDomain
clearQueryString <- function(session = getDefaultReactiveDomain()) {
  updateQueryString(session$clientData$url_pathname, mode = "replace", session = session)
}

#' @importFrom shiny getQueryString getDefaultReactiveDomain
getToken <- function(session = getDefaultReactiveDomain()) {
  query <- getQueryString(session = session)
  if (!is.null(query$token)) {
    gsub('\"', "", query$token)
  } else {
    NULL
  }
}

#' @importFrom shiny getQueryString getDefaultReactiveDomain
getLanguage <- function(session = getDefaultReactiveDomain()) {
  query <- getQueryString(session = session)
  if (!is.null(query$language)) {
    gsub('\"', "", query$language)
  } else {
    NULL
  }
}

#' @importFrom shiny updateQueryString getQueryString getDefaultReactiveDomain
resetQueryString <- function(session = getDefaultReactiveDomain()) {
  query <- getQueryString(session = session)
  query$token <- NULL
  query$language <- NULL
  if (length(query) == 0) {
    clearQueryString(session = session)
  } else {
    query <- paste(names(query), query, sep = "=", collapse = "&")
    query <- gsub("_inputs_=", "_inputs_", query, fixed = TRUE)
    updateQueryString(queryString = paste0("?", query), mode = "replace", session = session)
  }
}

#' @importFrom shiny updateQueryString getQueryString getDefaultReactiveDomain
addAuthToQuery <- function(session = getDefaultReactiveDomain(), token, language) {
  query <- getQueryString(session = session)
  query$token <- paste0('"', token, '"')
  query$language <- paste0('"', language, '"')
  query <- paste(names(query), query, sep = "=", collapse = "&")
  query <- gsub("_inputs_=", "_inputs_", query, fixed = TRUE)
  updateQueryString(queryString = paste0("?", query), mode = "replace", session = session)
}
