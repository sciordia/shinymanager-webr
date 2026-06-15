context("test-2fa-flow")

library(shiny)

skip_if_no_db <- function() {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")
  skip_if_not_installed("sodium")
  skip_if_not_installed("openssl")
}

seed_db <- function() {
  dbf <- tempfile(fileext = ".duckdb")
  create_user_db(dbf)
  add_user(dbf, email = "sergio@example.org", password = "S3cr3t!",
           pushover_user_key = "K", name = "Sergio", role = "admin")
  dbf
}

make_server <- function(dbf) {
  function(input, output, session) {
    session$userData$auth <- secure_server_local(
      check_credentials = check_credentials_local(dbf),
      db = dbf, pushover_app_token = "t",
      remember_device = TRUE, timeout = 0
    )
  }
}

test_that("full login + 2FA flow authenticates and creates a device token", {
  skip_if_no_db()
  withr::local_envvar(AUTHLAS_KEY = "test-master-key-123")
  # avoid hitting Pushover and pin the code
  local_mocked_bindings(generate_2fa_code = function(digits = 6L) "123456")
  local_mocked_bindings(send_2fa = function(db, user_id, code, pushover_app_token, title = "x") TRUE)
  dbf <- seed_db()

  testServer(make_server(dbf), {
    session$setInputs(shinymanager_device = "")

    # wrong password
    session$setInputs(sm_email = "sergio@example.org", sm_password = "bad")
    session$setInputs(sm_login = 1)
    expect_false(session$userData$auth$result)

    # right password -> 2FA challenge stored
    session$setInputs(sm_password = "S3cr3t!")
    session$setInputs(sm_login = 2)
    con <- DBI::dbConnect(duckdb::duckdb(), dbdir = dbf)
    uid <- db_get_user(con, "sergio@example.org")$user_id
    expect_false(is.null(db_get_twofa(con, uid)))

    # wrong code increments attempts, does not authenticate
    session$setInputs(sm_2fa_code = "000000", sm_2fa_submit = 1)
    expect_equal(db_get_twofa(con, uid)$attempts, 1)
    expect_false(session$userData$auth$result)

    # right code authenticates and consumes the challenge
    session$setInputs(sm_2fa_code = "123456", sm_2fa_submit = 2)
    expect_true(db_get_twofa(con, uid)$consumed)
    expect_true(session$userData$auth$result)
    expect_identical(session$userData$auth$email, "sergio@example.org")
    expect_equal(DBI::dbGetQuery(con, "SELECT count(*) n FROM device_tokens")$n, 1)
    DBI::dbDisconnect(con, shutdown = TRUE)
  })
})

test_that("a user with 2FA disabled logs in straight away", {
  skip_if_no_db()
  withr::local_envvar(AUTHLAS_KEY = "test-master-key-123")
  local_mocked_bindings(send_2fa = function(...) stop("2FA should not be sent"))
  dbf <- tempfile(fileext = ".duckdb")
  create_user_db(dbf)
  add_user(dbf, email = "direct@example.org", password = "S3cr3t!", twofa_enabled = FALSE)

  testServer(make_server(dbf), {
    session$setInputs(shinymanager_device = "")
    session$setInputs(sm_email = "direct@example.org", sm_password = "S3cr3t!")
    session$setInputs(sm_login = 1)
    expect_true(session$userData$auth$result)
    expect_identical(session$userData$auth$email, "direct@example.org")

    con <- DBI::dbConnect(duckdb::duckdb(), dbdir = dbf)
    uid <- db_get_user(con, "direct@example.org")$user_id
    expect_null(db_get_twofa(con, uid))                 # no 2FA challenge created
    DBI::dbDisconnect(con, shutdown = TRUE)
  })
})

test_that("a per-user device_ttl_hours overrides the server default", {
  skip_if_no_db()
  withr::local_envvar(AUTHLAS_KEY = "test-master-key-123")
  local_mocked_bindings(generate_2fa_code = function(digits = 6L) "123456")
  local_mocked_bindings(send_2fa = function(db, user_id, code, pushover_app_token, title = "x") TRUE)
  dbf <- tempfile(fileext = ".duckdb")
  create_user_db(dbf)
  add_user(dbf, email = "ttl@example.org", password = "S3cr3t!",
           pushover_user_key = "K", device_ttl_hours = 100)

  testServer(make_server(dbf), {           # server default device_ttl_hours = 24
    session$setInputs(shinymanager_device = "")
    session$setInputs(sm_email = "ttl@example.org", sm_password = "S3cr3t!")
    session$setInputs(sm_login = 1)
    session$setInputs(sm_2fa_code = "123456", sm_2fa_submit = 1)
    expect_true(session$userData$auth$result)

    con <- DBI::dbConnect(duckdb::duckdb(), dbdir = dbf)
    dev <- DBI::dbGetQuery(con, "SELECT created_at, expires_at FROM device_tokens")
    DBI::dbDisconnect(con, shutdown = TRUE)
    # ~100h, not the server's 24h
    expect_equal((dev$expires_at - dev$created_at) / 3600, 100, tolerance = 0.01)
  })
})

test_that("a valid device cookie skips 2FA", {
  skip_if_no_db()
  withr::local_envvar(AUTHLAS_KEY = "test-master-key-123")
  local_mocked_bindings(send_2fa = function(...) TRUE)
  dbf <- seed_db()
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = dbf)
  uid <- db_get_user(con, "sergio@example.org")$user_id
  devtok <- db_add_device(con, uid, 24)
  DBI::dbDisconnect(con, shutdown = TRUE)

  testServer(make_server(dbf), {
    session$setInputs(shinymanager_device = devtok)
    session$setInputs(sm_email = "sergio@example.org", sm_password = "S3cr3t!")
    session$setInputs(sm_login = 1)
    expect_true(session$userData$auth$result)
  })
})

test_that("an expired 2FA code is rejected", {
  skip_if_no_db()
  withr::local_envvar(AUTHLAS_KEY = "test-master-key-123")
  dbf <- seed_db()
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = dbf)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  uid <- db_get_user(con, "sergio@example.org")$user_id
  db_set_twofa(con, uid, hash_password("123456"))
  # push created_at 60s into the past
  DBI::dbExecute(con, "UPDATE twofa_codes SET created_at = created_at - 60 WHERE user_id = ?",
                 params = list(uid))
  tw <- db_get_twofa(con, uid)
  expect_true((as.numeric(Sys.time()) - tw$created_at) > 30)
  expect_true(verify_password("123456", tw$code_hash))  # code itself is correct, but stale
})
