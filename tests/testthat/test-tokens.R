context("test-tokens")

.tok <- shinymanager.webr:::.tokens$new()

token_one = "token_one"
list_info_one <- list(user = "benoit", role = "full")

token_two = "token_two"
list_info_two <- list(user = "victor", role = "full")

test_that("create token", {
  expect_silent(.tok$add(token_one, list_info_one))
  expect_equal(.tok$get(token_one), list_info_one)
  
  expect_silent(.tok$add(token_two, list_info_two))
  expect_equal(.tok$get(token_two), list_info_two)
})

test_that("valid token", {
  # is valid TRUE one time only
  expect_true(.tok$is_valid(token_one))
  expect_true(.tok$is_valid(token_two))
  expect_false(.tok$is_valid("bad_token"))
  
  expect_false(.tok$is_valid(token_one))
  expect_false(.tok$is_valid(token_two))
  
  expect_true(.tok$is_valid_server(token_one))
  expect_true(.tok$is_valid_server(token_two))
  expect_false(.tok$is_valid_server("bad_token"))
})

test_that("get token user", {
  expect_equal(.tok$get_user(token_one), "benoit")
  expect_equal(.tok$get_user(token_two), "victor")
  expect_null(.tok$get_user("bad_token"))
})

test_that("token timeout", {
  expect_silent(.tok$set_timeout(10))
  expect_equal(.tok$get_timeout(), 10)
  
  expect_silent(.tok$set_timeout(0))
  expect_equal(.tok$get_timeout(), 0)
})

test_that("token timeout valid", {
  expect_true(.tok$is_valid_timeout(token_one))
  expect_true(.tok$is_valid_timeout(token_two))
})

test_that("token random string", {
  token <- .tok$generate("benoit")
  expect_is(token, "character")
  expect_equal(nchar(token), 64)
})

test_that("token remove", {
  expect_true(.tok$is_valid_server(token_two))
  expect_silent(.tok$remove(token_two))
  expect_false(.tok$is_valid_server(token_two))
})
