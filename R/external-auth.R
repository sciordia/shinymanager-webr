#' External authentication helpers
#'
#' Use these helpers when authentication is handled before Shiny, for example by
#' Auth0 or Cloudflare Access. In this mode shinymanager only creates its session
#' token and applies lightweight authorization rules.
#'
#' @param ui UI of the application.
#' @param waiting_ui UI shown while waiting for the external identity.
#' @param head_auth Tags to add to the authentication page head, typically Auth0
#'   scripts.
#' @param theme Alternative Bootstrap stylesheet.
#' @param language Language used for shinymanager metadata.
#' @param timeout Timeout session in minutes before logout if sleeping. Use 0 to
#'   disable.
#' @param logout_url URL to navigate to after shinymanager removes its local
#'   token. For Auth0 this is usually the \code{/v2/logout} URL.
#' @param logout_callback Name of a JavaScript function on \code{window} to call
#'   after shinymanager removes its local token. Used when Auth0 logout is handled
#'   by the browser SDK.
#' @param allowed_users Character vector of allowed emails or user ids.
#' @param allowed_domains Character vector of allowed email domains.
#' @param require_verified_email Require \code{email_verified = TRUE} when the
#'   external identity payload contains that field.
#' @param user_info Optional function receiving the normalized external identity
#'   and returning extra fields to expose in \code{user_info}.
#' @param check_credentials Function returned by \code{check_credentials_external}.
#' @param external_input Shiny input id populated by JavaScript with the external
#'   identity. A character email/user id or a list with \code{email}, \code{user},
#'   \code{name}, \code{sub}, and \code{email_verified} is accepted.
#' @param keep_token Logical, keep the token used to authenticate in the URL.
#' @param session Shiny session.
#'
#' @return \code{secure_app_external()} returns a UI function.
#'   \code{secure_server_external()} returns reactive values with user
#'   information.
#'
#' @name external-authentication
#' @export
secure_app_external <- function(ui,
                                waiting_ui = NULL,
                                head_auth = NULL,
                                theme = NULL,
                                language = "en",
                                timeout = TRUE) {
  if (!language %in% c("en", "fr", "pt-BR", "es", "de", "pl", "ja", "el", "id", "zh-CN", "no")) {
    warning("Only supported language for the now are: en, fr, pt-BR, es, de, pl, ja, el, id, zh-CN, no", call. = FALSE)
    language <- "en"
  }

  lan <- use_language(language)
  ui <- force(ui)
  head_auth <- force(head_auth)
  if (is.null(theme)) {
    theme <- "shinymanager/css/readable.min.css"
  }
  if (is.null(waiting_ui)) {
    waiting_ui <- tags$div(
      class = "panel-auth",
      tags$br(), tags$div(style = "height: 70px;"), tags$br(),
      tags$div(
        class = "panel panel-primary",
        style = "max-width: 520px; margin: 0 auto;",
        tags$div(
          class = "panel-body",
          style = "text-align: center;",
          tags$h3(lan$get("Please authenticate")),
          tags$p("Waiting for external authentication.")
        )
      )
    )
  }

  function(request) {
    query <- parseQueryString(request$QUERY_STRING)
    token <- gsub('\"', "", query$token)
    language <- query$language
    if (!is.null(language)) {
      lan <- use_language(gsub('\"', "", language))
    }

    if (.tok$is_valid(token)) {
      menu <- fab_button(
        list(
          inputId = ".shinymanager_logout",
          label = lan$get("Logout"),
          icon = icon("right-from-bracket")
        )
      )
      save_logs(token)
      if (is.function(ui)) {
        ui <- ui(request)
      }
      tagList(
        ui, menu, shinymanager_where("application"),
        shinymanager_language(lan$get_language()),
        singleton(tags$head(tags$script(HTML(external_logout_handler_js())))),
        if (isTRUE(timeout)) singleton(tags$head(tags$script(src = "shinymanager/timeout.js")))
      )
    } else {
      fluidPage(
        theme = theme,
        singleton(tags$head(
          tags$link(href = "shinymanager/styles-auth.css", rel = "stylesheet"),
          head_auth
        )),
        waiting_ui,
        shinymanager_where("authentication"),
        shinymanager_language(lan$get_language())
      )
    }
  }
}

#' @rdname external-authentication
#' @export
check_credentials_external <- function(allowed_users = NULL,
                                       allowed_domains = NULL,
                                       require_verified_email = FALSE,
                                       user_info = NULL) {
  force(allowed_users)
  force(allowed_domains)
  force(require_verified_email)
  force(user_info)

  if (!is.null(allowed_users)) {
    allowed_users <- tolower(as.character(allowed_users))
  }
  if (!is.null(allowed_domains)) {
    allowed_domains <- tolower(as.character(allowed_domains))
  }

  function(user, password = NULL) {
    identity <- normalize_external_identity(user)
    external_user <- identity$user
    email <- identity$email
    domain <- sub("^.*@", "", email)

    allowed <- is.null(allowed_users) && is.null(allowed_domains)
    if (!is.null(allowed_users)) {
      allowed <- tolower(external_user) %in% allowed_users || tolower(email) %in% allowed_users
    }
    if (!is.null(allowed_domains)) {
      allowed <- allowed || tolower(domain) %in% allowed_domains
    }
    if (isTRUE(require_verified_email) && !isTRUE(identity$email_verified)) {
      allowed <- FALSE
    }

    info <- identity
    if (is.function(user_info)) {
      info <- modifyList(info, as.list(user_info(identity)))
    }

    list(
      result = isTRUE(allowed),
      expired = FALSE,
      authorized = isTRUE(allowed),
      user_info = info
    )
  }
}

#' @rdname external-authentication
#' @export
secure_server_external <- function(check_credentials = check_credentials_external(),
                                   external_input = "auth0_user",
                                   logout_url = NULL,
                                   logout_callback = NULL,
                                   timeout = 15,
                                   keep_token = FALSE,
                                   session = shiny::getDefaultReactiveDomain()) {
  session$setBookmarkExclude(c(session$getBookmarkExclude(),
                               "shinymanager_language",
                               ".shinymanager_timeout",
                               ".shinymanager_logout",
                               "shinymanager_where",
                               external_input))

  token_start <- isolate(getToken(session = session))
  if (isTRUE(keep_token)) {
    .tok$reset_count(token_start)
  } else {
    isolate(resetQueryString(session = session))
  }

  lan <- reactiveVal(use_language())
  observe({
    lang <- getLanguage(session = session)
    if (!is.null(lang)) {
      lan(use_language(lang))
    }
  })

  user_info_rv <- reactiveValues(result = FALSE, user = NULL, user_info = NULL)

  observe({
    token <- getToken(session = session)
    if (is.null(token)) {
      token <- token_start
    }
    if (!is.null(token) && .tok$is_valid_server(token)) {
      user_info <- .tok$get(token)
      set_external_user_info(user_info_rv, user_info)
    }
  })

  observeEvent(session$input[[external_input]], {
    identity <- session$input[[external_input]]
    res_auth <- check_credentials(identity, NULL)
    normalized <- normalize_external_identity(identity)

    if (isTRUE(res_auth$result) && isTRUE(res_auth$authorized)) {
      token <- .tok$generate(normalized$user)
      .tok$add(token, as.list(res_auth$user_info))
      set_external_user_info(user_info_rv, res_auth$user_info)
      addAuthToQuery(session, token, lan()$get_language())
      session$reload()
    } else {
      user_info_rv$result <- FALSE
      user_info_rv$user <- normalized$user
      user_info_rv$user_info <- res_auth$user_info
    }
  }, ignoreInit = FALSE)

  observeEvent(session$input$.shinymanager_logout, {
    token <- getToken(session = session)
    if (is.null(token)) {
      token <- token_start
    }
    logout_logs(token)
    .tok$remove(token)
    clearQueryString(session = session)
    if (!is.null(logout_url) || !is.null(logout_callback)) {
      session$sendCustomMessage(
        type = "shinymanager-external-logout",
        message = list(url = logout_url, callback = logout_callback)
      )
    } else {
      session$reload()
    }
  }, ignoreInit = TRUE)

  .tok$set_timeout(timeout)
  if (timeout > 0) {
    observeEvent(session$input$.shinymanager_timeout, {
      token <- getToken(session = session)
      if (is.null(token)) {
        token <- token_start
      }
      if (!is.null(token)) {
        valid_timeout <- .tok$is_valid_timeout(token, update = TRUE)
        if (!valid_timeout) {
          .tok$remove(token)
          clearQueryString(session = session)
          session$reload()
        }
      }
    })

    observe({
      invalidateLater(30000, session)
      token <- getToken(session = session)
      if (is.null(token)) {
        token <- token_start
      }
      if (!is.null(token)) {
        valid_timeout <- .tok$is_valid_timeout(token, update = FALSE)
        if (!valid_timeout) {
          .tok$remove(token)
          clearQueryString(session = session)
          session$reload()
        }
      }
    })
  }

  user_info_rv
}

normalize_external_identity <- function(identity) {
  if (is.data.frame(identity)) {
    identity <- as.list(identity[1, , drop = FALSE])
  } else if (is.atomic(identity) && length(identity) == 1) {
    identity <- list(email = as.character(identity), user = as.character(identity))
  } else {
    identity <- as.list(identity)
  }

  email <- first_not_null(identity$email, identity$user, identity$name, identity$sub)
  user <- first_not_null(identity$user, identity$email, identity$sub, identity$name)
  email_verified <- identity$email_verified
  if (is.null(email_verified)) {
    email_verified <- NA
  }

  list(
    user = as.character(user),
    email = as.character(email),
    name = as.character(first_not_null(identity$name, user)),
    sub = as.character(first_not_null(identity$sub, user)),
    email_verified = isTRUE(email_verified),
    auth_provider = as.character(first_not_null(identity$auth_provider, "external"))
  )
}

first_not_null <- function(...) {
  values <- list(...)
  for (value in values) {
    if (!is.null(value) && length(value) > 0 && !is.na(value[[1]]) && nzchar(as.character(value[[1]]))) {
      return(value[[1]])
    }
  }
  NA_character_
}

set_external_user_info <- function(rv, user_info) {
  rv$result <- TRUE
  rv$user <- user_info$user
  rv$user_info <- user_info
  for (i in names(user_info)) {
    rv[[i]] <- user_info[[i]]
  }
  invisible(rv)
}

external_logout_handler_js <- function() {
  "
  Shiny.addCustomMessageHandler('shinymanager-external-logout', function(message) {
    if (message.callback && typeof window[message.callback] === 'function') {
      window[message.callback](message);
      return;
    }
    if (message.url) {
      window.location.assign(message.url);
      return;
    }
    window.location.reload();
  });
  "
}
