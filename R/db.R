# duckdb-backed storage for the local (server) variant.
#
# Only authentication tables live here (users, twofa_codes, device_tokens). Any
# domain data (projects, experiments, samples, ...) is the application's
# responsibility. Per-user profile fields travel as a JSON blob in `users.profile`
# so they can be exposed to the session without coupling the package to a schema.
#
# duckdb/DBI are Suggests (server-only) and loaded on demand. Timestamps are
# stored as epoch seconds (DOUBLE) to keep comparisons trivial and timezone-safe.

# Run `fn(con)` against a duckdb connection. `x` may be a path (opened and closed
# here) or an existing DBIConnection (used as-is).
with_con <- function(x, fn) {
  require_pkg("DBI"); require_pkg("duckdb")
  if (inherits(x, "DBIConnection")) return(fn(x))
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = x)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  fn(con)
}

now_epoch <- function() as.numeric(Sys.time())

# Add per-user auth-policy columns if they are missing, so databases created by
# older versions keep working without being recreated. ALTER ... ADD COLUMN IF
# NOT EXISTS is idempotent; the `users` table always exists where this is called.
db_ensure_user_settings <- function(con) {
  DBI::dbExecute(con, "ALTER TABLE users ADD COLUMN IF NOT EXISTS twofa_enabled BOOLEAN")
  DBI::dbExecute(con, "ALTER TABLE users ADD COLUMN IF NOT EXISTS device_ttl_hours DOUBLE")
  invisible(TRUE)
}

# Random, cookie-safe device token (64 hex chars).
generate_device_token <- function() {
  require_pkg("openssl")
  paste(sprintf("%02x", as.integer(openssl::rand_bytes(32))), collapse = "")
}

#' @title Create the local credentials database
#'
#' @description Create the duckdb file and the authentication tables used by the
#'   local (server) variant: \code{users}, \code{twofa_codes} and
#'   \code{device_tokens}. Server-only; never used in webR.
#'
#' @param dbdir Path to the duckdb file.
#' @param overwrite If \code{TRUE}, drop existing authentication tables first.
#'
#' @return Invisibly, \code{dbdir}.
#'
#' @export
create_user_db <- function(dbdir, overwrite = FALSE) {
  with_con(dbdir, function(con) {
    if (isTRUE(overwrite)) {
      for (tb in c("users", "twofa_codes", "device_tokens")) {
        DBI::dbExecute(con, sprintf("DROP TABLE IF EXISTS %s", tb))
      }
    }
    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS users (
        user_id TEXT PRIMARY KEY,
        email TEXT UNIQUE NOT NULL,
        name TEXT,
        role TEXT,
        password_hash TEXT NOT NULL,
        pushover_user_key_enc TEXT,
        profile TEXT,
        twofa_enabled BOOLEAN,
        device_ttl_hours DOUBLE,
        created_at DOUBLE
      )")
    db_ensure_user_settings(con)
    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS twofa_codes (
        user_id TEXT PRIMARY KEY,
        code_hash TEXT,
        created_at DOUBLE,
        attempts INTEGER,
        consumed BOOLEAN
      )")
    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS device_tokens (
        device_token TEXT PRIMARY KEY,
        user_id TEXT,
        created_at DOUBLE,
        last_used_at DOUBLE,
        expires_at DOUBLE
      )")
  })
  invisible(dbdir)
}

#' @title Add a user to the local credentials database
#'
#' @description Insert a user, hashing the password with Argon2id and encrypting
#'   the Pushover user key with the master key (\code{SHINYMANAGER_KEY}).
#'   Server-only; never used in webR.
#'
#' @param dbdir Path to the duckdb file, or an open DBIConnection.
#' @param email User email (login id, unique).
#' @param password Plain-text password (hashed before storage).
#' @param pushover_user_key The user's Pushover user key (encrypted before
#'   storage). Required to deliver the 2FA code.
#' @param name Optional display name.
#' @param role Optional role string.
#' @param profile Optional named list of extra profile fields, stored as JSON and
#'   exposed to the session after login.
#' @param twofa_enabled Whether this user must complete the Pushover two-factor
#'   step after a valid password. \code{TRUE} (default) keeps the 2FA challenge;
#'   \code{FALSE} logs the user straight into the app once credentials match.
#'   Stored per user in the database.
#' @param device_ttl_hours Per-user lifetime (in hours) of the "remember this
#'   device" token that skips 2FA on later logins. \code{NULL} (default) means
#'   the user has no override and the server's \code{device_ttl_hours} applies.
#' @param user_id Optional explicit user id (defaults to a random token).
#'
#' @return Invisibly, the \code{user_id}.
#'
#' @export
add_user <- function(dbdir, email, password,
                     pushover_user_key = NULL,
                     name = NULL, role = "user",
                     profile = list(),
                     twofa_enabled = TRUE,
                     device_ttl_hours = NULL,
                     user_id = NULL) {
  if (is.null(user_id)) user_id <- generate_device_token()
  profile_json <- if (length(profile)) as.character(jsonlite::toJSON(profile, auto_unbox = TRUE)) else NA_character_
  pk_enc <- if (is.null(pushover_user_key)) NA_character_ else encrypt_secret(pushover_user_key)
  with_con(dbdir, function(con) {
    db_ensure_user_settings(con)
    DBI::dbExecute(
      con,
      "INSERT INTO users (user_id, email, name, role, password_hash, pushover_user_key_enc, profile, twofa_enabled, device_ttl_hours, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      params = list(user_id, email, name %||% NA_character_, role,
                    hash_password(password), pk_enc, profile_json,
                    isTRUE(twofa_enabled), device_ttl_hours %||% NA_real_, now_epoch())
    )
  })
  invisible(user_id)
}

#' @title Update a user's authentication settings
#'
#' @description Change the per-user two-factor and device-remember settings of an
#'   existing user, in place. Server-only; never used in webR.
#'
#' @param dbdir Path to the duckdb file, or an open DBIConnection.
#' @param email Email of the user to update (case-insensitive).
#' @param twofa_enabled \code{NULL} leaves the flag unchanged; \code{TRUE}/
#'   \code{FALSE} sets whether the user must complete the 2FA step.
#' @param device_ttl_hours \code{NULL} leaves the value unchanged; a number sets
#'   the per-user device-token lifetime (hours); \code{NA} clears the override so
#'   the server's \code{device_ttl_hours} applies again.
#'
#' @return Invisibly, \code{email}.
#'
#' @export
set_user_settings <- function(dbdir, email,
                              twofa_enabled = NULL,
                              device_ttl_hours = NULL) {
  with_con(dbdir, function(con) {
    db_ensure_user_settings(con)
    if (!is.null(twofa_enabled)) {
      DBI::dbExecute(
        con, "UPDATE users SET twofa_enabled = ? WHERE lower(email) = lower(?)",
        params = list(isTRUE(twofa_enabled), email)
      )
    }
    if (!is.null(device_ttl_hours)) {
      DBI::dbExecute(
        con, "UPDATE users SET device_ttl_hours = ? WHERE lower(email) = lower(?)",
        params = list(if (is.na(device_ttl_hours)) NA_real_ else as.numeric(device_ttl_hours), email)
      )
    }
  })
  invisible(email)
}

# --- internal query helpers (operate on an open connection) ----------------

db_get_user <- function(con, email) {
  db_ensure_user_settings(con)
  res <- DBI::dbGetQuery(con, "SELECT * FROM users WHERE lower(email) = lower(?)", params = list(email))
  if (nrow(res) == 0) NULL else res[1, , drop = FALSE]
}

db_get_user_by_id <- function(con, user_id) {
  db_ensure_user_settings(con)
  res <- DBI::dbGetQuery(con, "SELECT * FROM users WHERE user_id = ?", params = list(user_id))
  if (nrow(res) == 0) NULL else res[1, , drop = FALSE]
}

db_set_twofa <- function(con, user_id, code_hash) {
  DBI::dbExecute(con, "DELETE FROM twofa_codes WHERE user_id = ?", params = list(user_id))
  DBI::dbExecute(
    con,
    "INSERT INTO twofa_codes (user_id, code_hash, created_at, attempts, consumed) VALUES (?, ?, ?, 0, FALSE)",
    params = list(user_id, code_hash, now_epoch())
  )
  invisible(TRUE)
}

db_get_twofa <- function(con, user_id) {
  res <- DBI::dbGetQuery(con, "SELECT * FROM twofa_codes WHERE user_id = ?", params = list(user_id))
  if (nrow(res) == 0) NULL else res[1, , drop = FALSE]
}

db_incr_twofa_attempts <- function(con, user_id) {
  DBI::dbExecute(con, "UPDATE twofa_codes SET attempts = attempts + 1 WHERE user_id = ?", params = list(user_id))
  invisible(TRUE)
}

db_consume_twofa <- function(con, user_id) {
  DBI::dbExecute(con, "UPDATE twofa_codes SET consumed = TRUE WHERE user_id = ?", params = list(user_id))
  invisible(TRUE)
}

db_add_device <- function(con, user_id, ttl_hours = 24) {
  token <- generate_device_token()
  ts <- now_epoch()
  DBI::dbExecute(
    con,
    "INSERT INTO device_tokens (device_token, user_id, created_at, last_used_at, expires_at) VALUES (?, ?, ?, ?, ?)",
    params = list(token, user_id, ts, ts, ts + ttl_hours * 3600)
  )
  token
}

# Return the user_id if the device token is valid and not expired (refreshing
# last_used_at), otherwise NULL.
db_check_device <- function(con, device_token) {
  if (is.null(device_token) || !nzchar(device_token)) return(NULL)
  res <- DBI::dbGetQuery(con, "SELECT * FROM device_tokens WHERE device_token = ?", params = list(device_token))
  if (nrow(res) == 0) return(NULL)
  if (res$expires_at[1] < now_epoch()) {
    DBI::dbExecute(con, "DELETE FROM device_tokens WHERE device_token = ?", params = list(device_token))
    return(NULL)
  }
  DBI::dbExecute(con, "UPDATE device_tokens SET last_used_at = ? WHERE device_token = ?",
                 params = list(now_epoch(), device_token))
  res$user_id[1]
}

db_remove_device <- function(con, device_token) {
  if (is.null(device_token) || !nzchar(device_token)) return(invisible(FALSE))
  DBI::dbExecute(con, "DELETE FROM device_tokens WHERE device_token = ?", params = list(device_token))
  invisible(TRUE)
}

# NULL-coalescing helper.
`%||%` <- function(a, b) if (is.null(a)) b else a
