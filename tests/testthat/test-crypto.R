context("test-crypto")

test_that("password hashing verifies correctly", {
  skip_if_not_installed("sodium")
  h <- hash_password("S3cr3t!")
  expect_true(nzchar(h))
  expect_true(verify_password("S3cr3t!", h))
  expect_false(verify_password("wrong", h))
  expect_false(verify_password("x", NA_character_))
})

test_that("secret encryption round-trips with the master key", {
  skip_if_not_installed("openssl")
  withr::local_envvar(SHINYMANAGER_KEY = "test-master-key-123")
  enc <- encrypt_secret("uPushKey-abc")
  expect_true(grepl(":", enc, fixed = TRUE))
  expect_identical(decrypt_secret(enc), "uPushKey-abc")
  expect_true(is.na(encrypt_secret(NA_character_)))
})

test_that("encrypt_secret requires the master key", {
  skip_if_not_installed("openssl")
  withr::local_envvar(SHINYMANAGER_KEY = "")
  expect_error(encrypt_secret("x"), "SHINYMANAGER_KEY")
})

test_that("2FA codes are six digits", {
  skip_if_not_installed("openssl")
  codes <- replicate(20, generate_2fa_code())
  expect_true(all(nchar(codes) == 6))
  expect_true(all(grepl("^[0-9]{6}$", codes)))
})
