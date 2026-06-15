#' Local (server) authentication helpers
#'
#' Use these helpers when the application runs on a server (not webR) and you
#' want credential-based login with a duckdb user store and Pushover two-factor
#' authentication. The application code is not exposed to the browser, so a real
#' login form is shown. Passwords are hashed with Argon2id and the per-user
#' Pushover key is stored encrypted. All heavy dependencies are Suggests.
#'
#' @param db Path to the duckdb file, or an open DBIConnection.
#' @param allowed_roles Optional character vector of roles allowed to log in. If
#'   \code{NULL}, any user in the database may log in.
#'
#' @return \code{check_credentials_local()} returns a validation function that
#'   takes \code{user} (email) and \code{password} and returns a list with
#'   \code{result}, \code{expired}, \code{authorized}, \code{user_info}, and the
#'   per-user policy fields \code{twofa_enabled} (logical) and
#'   \code{device_ttl_hours} (numeric or \code{NA}). The policy fields are kept
#'   out of \code{user_info} (which is exposed to the app and stored in the
#'   session token).
#'
#' @seealso A runnable example app:
#'   \code{system.file("examples", "local_auth.R", package = "authlas")}.
#'
#' @name local-authentication
#' @export
check_credentials_local <- function(db, allowed_roles = NULL) {
  force(db)
  function(user, password = NULL) {
    email <- as.character(user)
    row <- with_con(db, function(con) db_get_user(con, email))

    fail <- list(result = FALSE, expired = FALSE, authorized = FALSE, user_info = NULL)
    if (is.null(row)) return(fail)
    if (!verify_password(password, row$password_hash)) return(fail)
    if (!is.null(allowed_roles) && !isTRUE(tolower(row$role) %in% tolower(allowed_roles))) {
      return(fail)
    }

    # Build the public user_info: never expose password hash or Pushover key.
    info <- list(
      user_id = row$user_id,
      user = row$email,
      email = row$email,
      name = if (is.na(row$name)) row$email else row$name,
      role = row$role,
      auth_provider = "local"
    )
    if (!is.na(row$profile)) {
      extra <- tryCatch(jsonlite::fromJSON(row$profile), error = function(e) NULL)
      if (length(extra)) info <- utils::modifyList(info, as.list(extra))
    }

    # Per-user auth policy is returned at top level (not inside user_info, which
    # is public/stored in the token). Missing/NA falls back to secure defaults.
    twofa_enabled <- if (is.null(row$twofa_enabled) || is.na(row$twofa_enabled)) TRUE else isTRUE(row$twofa_enabled)
    device_ttl_hours <- if (is.null(row$device_ttl_hours) || is.na(row$device_ttl_hours)) NA_real_ else as.numeric(row$device_ttl_hours)

    list(result = TRUE, expired = FALSE, authorized = TRUE, user_info = info,
         twofa_enabled = twofa_enabled, device_ttl_hours = device_ttl_hours)
  }
}

# --- default screens (muiMaterial) -----------------------------------------
#
# Both screens are rendered statically into the auth page and toggled with
# conditionalPanel(output.sm_stage). muiMaterial components (pure React) are kept
# as siblings of plain elements (2FA cells, error text); the error messages are
# ordinary Shiny textOutputs, never embedded inside a React subtree. Rendering
# muiMaterial statically (as opposed to via renderUI) is what lets shiny.react
# initialize its runtime correctly.

# Plain centered wrapper.
local_centered <- function(...) {
  tags$div(
    style = paste0(
      "display:flex;flex-direction:column;align-items:center;",
      "justify-content:center;min-height:100vh;padding:16px;"
    ),
    tags$div(
      class = "sm-local-card",
      style = "width:100%;max-width:420px;text-align:center;",
      ...
    )
  )
}

# Default login screen.
local_login_ui <- function() {
  local_centered(
    muiMaterial::Typography("Acceso", variant = "h5", gutterBottom = TRUE),
    muiMaterial::TextField.shinyInput(
      "sm_email", label = "Email", type = "email",
      fullWidth = TRUE, margin = "normal"
    ),
    muiMaterial::TextField.shinyInput(
      "sm_password", label = "Contrase\u00f1a", type = "password",
      fullWidth = TRUE, margin = "normal"
    ),
    tags$div(
      style = "display:flex;gap:8px;justify-content:center;margin-top:16px;",
      muiMaterial::Button.shinyInput("sm_login", "Acceder", variant = "contained"),
      muiMaterial::Button.shinyInput("sm_cancel", "Cancelar", variant = "outlined")
    ),
    tags$div(class = "sm-local-error", textOutput("sm_login_error", inline = TRUE))
  )
}

# The six single-digit cells (plain inputs styled via styles-local.css; the
# values are assembled into input$sm_2fa_code by twofa.js).
twofa_cells <- function() {
  tags$div(
    class = "sm-2fa-cells",
    lapply(1:6, function(i) {
      tags$input(
        id = paste0("sm_2fa_", i), class = "sm-2fa-cell",
        type = "text", inputmode = "numeric", maxlength = "1", autocomplete = "off"
      )
    })
  )
}

# Default 2FA screen with a cosmetic countdown.
local_twofa_ui <- function(seconds = 30) {
  local_centered(
    muiMaterial::Typography("Verificaci\u00f3n en dos pasos", variant = "h5", gutterBottom = TRUE),
    muiMaterial::Typography(
      "Introduce el c\u00f3digo de 6 d\u00edgitos que has recibido en tu dispositivo.",
      variant = "body2"
    ),
    twofa_cells(),
    tags$div(
      style = "margin:4px 0;font-size:12px;color:#666;",
      "Caduca en ",
      tags$span(id = "sm-2fa-timer", `data-window` = seconds, seconds),
      " s"
    ),
    tags$div(class = "sm-local-error", textOutput("sm_twofa_error", inline = TRUE)),
    tags$div(
      style = "display:flex;gap:8px;justify-content:center;margin-top:16px;",
      muiMaterial::Button.shinyInput("sm_2fa_submit", "Validar", variant = "contained"),
      muiMaterial::Button.shinyInput("sm_2fa_resend", "Reenviar", variant = "text"),
      muiMaterial::Button.shinyInput("sm_2fa_cancel", "Cancelar", variant = "outlined")
    )
  )
}

# Send the 2FA code through Pushover. Returns TRUE on success.
send_2fa <- function(db, user_id, code, pushover_app_token, title = "C\u00f3digo de acceso") {
  require_pkg("pushoverr")
  row <- with_con(db, function(con) db_get_user_by_id(con, user_id))
  if (is.null(row) || is.na(row$pushover_user_key_enc)) return(FALSE)
  user_key <- decrypt_secret(row$pushover_user_key_enc)
  tryCatch({
    pushoverr::pushover(
      message = paste0("Tu c\u00f3digo de acceso es: ", code),
      title = title, user = user_key, app = pushover_app_token
    )
    TRUE
  }, error = function(e) FALSE)
}

#' @rdname local-authentication
#'
#' @param ui UI of the application (shown once authenticated).
#' @param theme Deprecated and ignored. The authentication page is now built
#'   with \code{muiMaterial::muiMaterialPage()} (Material UI), which suppresses
#'   Bootstrap; this argument no longer applies.
#' @param language Language used for shinymanager metadata.
#' @param timeout For \code{secure_app_local}, logical; whether to include the
#'   inactivity-timeout script. For \code{secure_server_local}, timeout in
#'   minutes (0 disables).
#' @param head_auth Tags to add to the authentication page head.
#' @param twofa_window Seconds shown by the cosmetic 2FA countdown (match the
#'   server's \code{twofa_window}).
#'
#' @return \code{secure_app_local()} returns a UI function.
#'
#' @export
secure_app_local <- function(ui,
                             theme = NULL,
                             language = "en",
                             timeout = TRUE,
                             twofa_window = 30,
                             head_auth = NULL) {
  lan <- use_language(language)
  ui <- force(ui)
  head_auth <- force(head_auth)

  function(request) {
    query <- parseQueryString(request$QUERY_STRING)
    token <- gsub('\"', "", query$token)

    if (.tok$is_valid(token)) {
      menu <- fab_button(list(
        inputId = ".shinymanager_logout",
        label = lan$get("Logout"),
        icon = icon("right-from-bracket")
      ))
      save_logs(token)
      if (is.function(ui)) ui <- ui(request)
      tagList(
        ui, menu, shinymanager_where("application"),
        shinymanager_language(lan$get_language()),
        singleton(tags$head(tags$script(HTML(external_logout_handler_js())))),
        if (isTRUE(timeout)) singleton(tags$head(tags$script(src = "authlas/timeout.js")))
      )
    } else {
      muiMaterial::muiMaterialPage(
        useFontRoboto = TRUE,
        muiMaterial::CssBaseline(),
        sm_auth_dependency(
          stylesheet = c("styles-auth.css", "styles-local.css"),
          script = c("device-cookie.js", "twofa.js"),
          head_auth = head_auth
        ),
        tags$div(
          class = "panel-auth",
          tags$div(style = "display:none;", textOutput("sm_stage")),
          conditionalPanel(condition = "output.sm_stage != 'twofa'", local_login_ui()),
          conditionalPanel(condition = "output.sm_stage == 'twofa'", local_twofa_ui(twofa_window))
        ),
        shinymanager_where("authentication"),
        shinymanager_language(lan$get_language())
      )
    }
  }
}

#' @rdname local-authentication
#'
#' @param pushover_app_token Pushover application (API) token used to deliver
#'   the 2FA code. Per-user keys are stored encrypted in the database.
#' @param pushover_title Title of the Pushover notification. If \code{NULL}, a
#'   default title is used.
#' @param twofa_window Seconds the 2FA code stays valid.
#' @param max_attempts Maximum wrong 2FA attempts before returning to login.
#' @param remember_device If \code{TRUE}, a valid device cookie skips 2FA.
#' @param device_ttl_hours Default lifetime of the device cookie/token, in hours,
#'   used for users that have no per-user \code{device_ttl_hours} of their own
#'   (see \code{\link{add_user}}/\code{\link{set_user_settings}}). Whether 2FA is
#'   required at all is also decided per user (\code{twofa_enabled}); users with
#'   2FA disabled log in straight after a valid password.
#' @param check_credentials Function returned by \code{check_credentials_local}.
#' @param session Shiny session.
#'
#' @return \code{secure_server_local()} returns reactive values with user
#'   information.
#'
#' @export
secure_server_local <- function(check_credentials,
                                db,
                                pushover_app_token = Sys.getenv("PUSHOVER_APP"),
                                pushover_title = NULL,
                                twofa_window = 30,
                                max_attempts = 5,
                                remember_device = TRUE,
                                device_ttl_hours = 24,
                                timeout = 15,
                                session = shiny::getDefaultReactiveDomain()) {
  if (is.null(pushover_title)) pushover_title <- "C\u00f3digo de acceso"
  input <- session$input
  output <- session$output

  session$setBookmarkExclude(c(session$getBookmarkExclude(),
                               "shinymanager_language", ".shinymanager_timeout",
                               ".shinymanager_logout", "shinymanager_where",
                               "sm_email", "sm_password", "sm_login", "sm_cancel",
                               "sm_2fa_code", "sm_2fa_submit", "sm_2fa_resend",
                               "sm_2fa_cancel", "shinymanager_device"))

  token_start <- isolate(getToken(session = session))
  isolate(resetQueryString(session = session))

  lan <- reactiveVal(use_language())
  observe({
    lang <- getLanguage(session = session)
    if (!is.null(lang)) lan(use_language(lang))
  })

  user_info_rv <- reactiveValues(result = FALSE, user = NULL, user_info = NULL)
  rv <- reactiveValues(stage = "login", error = NULL, pending = NULL, pending_ttl = NULL)

  # Populate user info once a valid session token is present (after reload).
  observe({
    token <- getToken(session = session)
    if (is.null(token)) token <- token_start
    if (!is.null(token) && .tok$is_valid_server(token)) {
      set_external_user_info(user_info_rv, .tok$get(token))
    }
  })

  # Drive the static auth screens: stage toggles the conditionalPanels, and the
  # error text feeds the visible screen's textOutput.
  output$sm_stage <- renderText(rv$stage)
  outputOptions(output, "sm_stage", suspendWhenHidden = FALSE)
  output$sm_login_error <- renderText(rv$error %||% "")
  output$sm_twofa_error <- renderText(rv$error %||% "")

  finish_login <- function(user_info) {
    token <- .tok$generate(user_info$user)
    .tok$add(token, as.list(user_info))
    set_external_user_info(user_info_rv, user_info)
    addAuthToQuery(session, token, lan()$get_language())
    session$reload()
  }

  start_2fa <- function(user_id) {
    code <- generate_2fa_code()
    with_con(db, function(con) db_set_twofa(con, user_id, hash_password(code)))
    send_2fa(db, user_id, code, pushover_app_token, pushover_title)
  }

  # Step 1: credentials.
  observeEvent(input$sm_login, {
    res <- check_credentials(input$sm_email, input$sm_password)
    if (!isTRUE(res$result) || !isTRUE(res$authorized)) {
      rv$error <- "Credenciales no v\u00e1lidas."
      return()
    }
    rv$pending <- res$user_info
    uid <- res$user_info$user_id

    # Effective per-user policy, falling back to the server defaults.
    user_twofa <- if (is.null(res$twofa_enabled)) TRUE else isTRUE(res$twofa_enabled)
    eff_ttl <- if (is.null(res$device_ttl_hours) || is.na(res$device_ttl_hours)) {
      device_ttl_hours
    } else {
      res$device_ttl_hours
    }
    rv$pending_ttl <- eff_ttl

    # 2FA disabled for this user: log straight in (no code, no device cookie).
    if (!user_twofa) {
      rv$error <- NULL
      finish_login(res$user_info)
      return()
    }

    dev <- isolate(input$shinymanager_device)
    remembered <- isTRUE(remember_device) && !is.null(dev) && nzchar(dev) &&
      identical(with_con(db, function(con) db_check_device(con, dev)), uid)

    if (remembered) {
      finish_login(res$user_info)
    } else if (start_2fa(uid)) {
      rv$error <- NULL
      rv$stage <- "twofa"
    } else {
      rv$error <- "No se pudo enviar el c\u00f3digo de verificaci\u00f3n."
    }
  }, ignoreInit = TRUE)

  # Cancel on login: clear the fields.
  observeEvent(input$sm_cancel, {
    muiMaterial::updateTextField.shinyInput(session, "sm_email", value = "")
    muiMaterial::updateTextField.shinyInput(session, "sm_password", value = "")
    rv$error <- NULL
  }, ignoreInit = TRUE)

  # Step 2: 2FA validation.
  observeEvent(input$sm_2fa_submit, {
    uid <- rv$pending$user_id
    if (is.null(uid)) { rv$stage <- "login"; return() }
    tw <- with_con(db, function(con) db_get_twofa(con, uid))
    if (is.null(tw) || isTRUE(tw$consumed)) {
      rv$error <- "El c\u00f3digo ya no es v\u00e1lido. Vuelve a iniciar sesi\u00f3n."
      rv$stage <- "login"
      return()
    }
    if (tw$attempts >= max_attempts) {
      rv$error <- "Demasiados intentos. Vuelve a iniciar sesi\u00f3n."
      rv$stage <- "login"
      return()
    }
    if ((now_epoch() - tw$created_at) > twofa_window) {
      rv$error <- "El c\u00f3digo ha caducado. Pulsa Reenviar."
      return()
    }
    code <- input$sm_2fa_code %||% ""
    if (!verify_password(code, tw$code_hash)) {
      with_con(db, function(con) db_incr_twofa_attempts(con, uid))
      rv$error <- "C\u00f3digo incorrecto."
      return()
    }
    with_con(db, function(con) db_consume_twofa(con, uid))
    if (isTRUE(remember_device)) {
      ttl <- rv$pending_ttl %||% device_ttl_hours
      tok <- with_con(db, function(con) db_add_device(con, uid, ttl))
      session$sendCustomMessage("shinymanager_set_device_cookie",
                                list(value = tok, max_age = ttl * 3600))
    }
    finish_login(rv$pending)
  }, ignoreInit = TRUE)

  observeEvent(input$sm_2fa_resend, {
    uid <- rv$pending$user_id
    if (!is.null(uid) && start_2fa(uid)) {
      rv$error <- NULL
    } else {
      rv$error <- "No se pudo reenviar el c\u00f3digo."
    }
  }, ignoreInit = TRUE)

  observeEvent(input$sm_2fa_cancel, {
    rv$stage <- "login"
    rv$error <- NULL
    rv$pending <- NULL
  }, ignoreInit = TRUE)

  # Logout.
  observeEvent(input$.shinymanager_logout, {
    token <- getToken(session = session)
    if (is.null(token)) token <- token_start
    logout_logs(token)
    .tok$remove(token)
    clearQueryString(session = session)
    session$reload()
  }, ignoreInit = TRUE)

  # Inactivity timeout (same mechanism as the external variant).
  .tok$set_timeout(timeout)
  if (timeout > 0) {
    observeEvent(input$.shinymanager_timeout, {
      token <- getToken(session = session)
      if (is.null(token)) token <- token_start
      if (!is.null(token) && !.tok$is_valid_timeout(token, update = TRUE)) {
        .tok$remove(token); clearQueryString(session = session); session$reload()
      }
    })
    observe({
      invalidateLater(30000, session)
      token <- getToken(session = session)
      if (is.null(token)) token <- token_start
      if (!is.null(token) && !.tok$is_valid_timeout(token, update = FALSE)) {
        .tok$remove(token); clearQueryString(session = session); session$reload()
      }
    })
  }

  user_info_rv
}
