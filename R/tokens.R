

#' @importFrom R6 R6Class
.tokens <- R6::R6Class(
  classname = "shinymanager_tokens",
  public = list(
    initialize = function() {
      invisible(self)
    },
    generate = function(user) {
      paste(
        sample(c(letters, LETTERS, 0:9), size = 64, replace = TRUE),
        collapse = ""
      )
    },
    add = function(token, ...) {
      args <- list(...)
      if(length(args) > 0){
        args[[1]]$shinymanager_datetime <- Sys.time()
      } else {
        args <- list(list(shinymanager_datetime = Sys.time()))
      }
      private$tokens <- union(private$tokens, token)
      if (length(args) > 0) {
        private$tokens_user <- append(
          x = private$tokens_user,
          values = setNames(
            object = args,
            nm = token
          )
        )
      }
      invisible(self)
    },
    is_valid_timeout = function(token, update = TRUE) {
      datetime <- private$tokens_user[[token]]$shinymanager_datetime
      if(!is.null(datetime) && private$timeout  > 0){
        valid <- difftime(Sys.time(), datetime, units = "mins") <= private$timeout
      } else {
        valid <- TRUE
      }
      if(valid && update) private$tokens_user[[token]]$shinymanager_datetime <- Sys.time()
      valid
    },
    get_user = function(token) {
      private$tokens_user[[token]]$user
    },
    is_valid = function(token) {
      valid <- token %in% private$tokens
      count <- sum(private$tokens_count %in% token, na.rm = TRUE)
      private$tokens_count <- c(private$tokens_count, token)
      isTRUE(valid) & isTRUE(count < 1)
    },
    is_valid_server = function(token) {
      isTRUE(token %in% private$tokens)
    },
    get = function(token) {
      info <- private$tokens_user[[token]]
      if("shinymanager_datetime" %in% names(info)) info$shinymanager_datetime <- NULL
      info
    },
    remove = function(token) {
      if (private$length() == 0) return(NULL)
      private$tokens <- setdiff(private$tokens, token)
      invisible()
    },
    reset_count = function(token) {
      private$tokens_count <- setdiff(private$tokens_count, token)
    },
    set_timeout = function(timeout) {
      private$timeout <- timeout
      invisible()
    },
    get_timeout = function() {
      private$timeout
    }
  ),
  private = list(
    tokens = character(0),
    tokens_count = character(0),
    tokens_user = list(),
    timeout = 0,
    length = function() base::length(private$tokens)
  )
)
.tok <- .tokens$new()
