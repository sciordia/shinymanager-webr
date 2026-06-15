context("test-local-auth")

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
           pushover_user_key = "K", name = "Sergio", role = "admin",
           profile = list(lab = "Genomica", proyectos = 3))
  dbf
}

test_that("check_credentials_local validates credentials and exposes the profile", {
  skip_if_no_db()
  withr::local_envvar(SHINYMANAGER_KEY = "test-master-key-123")
  chk <- check_credentials_local(seed_db())

  ok <- chk("sergio@example.org", "S3cr3t!")
  expect_true(ok$result)
  expect_true(ok$authorized)
  expect_identical(ok$user_info$email, "sergio@example.org")
  expect_identical(ok$user_info$role, "admin")
  expect_identical(ok$user_info$lab, "Genomica")
  # the Pushover key must never be exposed to the client
  expect_false(any(grepl("pushover", names(ok$user_info), ignore.case = TRUE)))

  expect_false(chk("sergio@example.org", "wrong")$result)
  expect_false(chk("nobody@example.org", "x")$result)
})

test_that("check_credentials_local can restrict by role", {
  skip_if_no_db()
  withr::local_envvar(SHINYMANAGER_KEY = "test-master-key-123")
  chk <- check_credentials_local(seed_db(), allowed_roles = "user")
  expect_false(chk("sergio@example.org", "S3cr3t!")$result)
})

test_that("check_credentials_local exposes per-user 2FA policy", {
  skip_if_no_db()
  withr::local_envvar(SHINYMANAGER_KEY = "test-master-key-123")
  dbf <- tempfile(fileext = ".duckdb")
  create_user_db(dbf)
  add_user(dbf, email = "twofa@example.org", password = "S3cr3t!", pushover_user_key = "K")
  add_user(dbf, email = "direct@example.org", password = "S3cr3t!",
           twofa_enabled = FALSE, device_ttl_hours = 72)
  chk <- check_credentials_local(dbf)

  on_default <- chk("twofa@example.org", "S3cr3t!")
  expect_true(on_default$twofa_enabled)
  expect_true(is.na(on_default$device_ttl_hours))

  no_2fa <- chk("direct@example.org", "S3cr3t!")
  expect_false(no_2fa$twofa_enabled)
  expect_equal(no_2fa$device_ttl_hours, 72)
})

test_that("set_user_settings updates and clears per-user policy", {
  skip_if_no_db()
  withr::local_envvar(SHINYMANAGER_KEY = "test-master-key-123")
  dbf <- seed_db()
  chk <- check_credentials_local(dbf)

  set_user_settings(dbf, "sergio@example.org", twofa_enabled = FALSE, device_ttl_hours = 48)
  res <- chk("sergio@example.org", "S3cr3t!")
  expect_false(res$twofa_enabled)
  expect_equal(res$device_ttl_hours, 48)

  # NULL leaves untouched; NA clears the TTL override back to the default
  set_user_settings(dbf, "sergio@example.org", device_ttl_hours = NA)
  res <- chk("sergio@example.org", "S3cr3t!")
  expect_false(res$twofa_enabled)        # unchanged
  expect_true(is.na(res$device_ttl_hours))
})

test_that("databases from older versions are auto-migrated", {
  skip_if_no_db()
  withr::local_envvar(SHINYMANAGER_KEY = "test-master-key-123")
  dbf <- tempfile(fileext = ".duckdb")
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = dbf)
  # legacy schema: no twofa_enabled / device_ttl_hours columns
  DBI::dbExecute(con, "CREATE TABLE users (
      user_id TEXT PRIMARY KEY, email TEXT UNIQUE NOT NULL, name TEXT, role TEXT,
      password_hash TEXT NOT NULL, pushover_user_key_enc TEXT, profile TEXT, created_at DOUBLE)")
  DBI::dbDisconnect(con, shutdown = TRUE)

  add_user(dbf, email = "legacy@example.org", password = "S3cr3t!")
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = dbf)
  cols <- DBI::dbGetQuery(con, "PRAGMA table_info('users')")$name
  DBI::dbDisconnect(con, shutdown = TRUE)
  expect_true(all(c("twofa_enabled", "device_ttl_hours") %in% cols))
  expect_true(check_credentials_local(dbf)("legacy@example.org", "S3cr3t!")$twofa_enabled)
})

test_that("device tokens are validated and expire", {
  skip_if_no_db()
  withr::local_envvar(SHINYMANAGER_KEY = "test-master-key-123")
  dbf <- seed_db()
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = dbf)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  uid <- db_get_user(con, "sergio@example.org")$user_id

  tok <- db_add_device(con, uid, ttl_hours = 24)
  expect_identical(db_check_device(con, tok), uid)

  db_remove_device(con, tok)
  expect_null(db_check_device(con, tok))

  expired <- db_add_device(con, uid, ttl_hours = -1)
  expect_null(db_check_device(con, expired))
})
