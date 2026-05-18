context("test-external-auth")

library(shiny)

test_that("check_credentials_external allows users and domains", {
  check_user <- check_credentials_external(
    allowed_users = "fanny@example.com",
    allowed_domains = "example.org"
  )

  expect_true(check_user("fanny@example.com")$result)
  expect_true(check_user(list(email = "victor@example.org"))$result)
  expect_false(check_user("benoit@example.net")$result)
})

test_that("check_credentials_external can require verified email", {
  check_user <- check_credentials_external(
    allowed_domains = "example.org",
    require_verified_email = TRUE
  )

  expect_true(check_user(list(email = "fanny@example.org", email_verified = TRUE))$result)
  expect_false(check_user(list(email = "fanny@example.org", email_verified = FALSE))$result)
})

test_that("secure_app_external works", {
  sa <- secure_app_external(fluidPage())

  expect_is(sa, "function")
})
