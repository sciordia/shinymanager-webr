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
