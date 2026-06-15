# Server-only cryptography helpers for the local (non-webR) variant.
#
# These functions are never reached in the webR variant, so their dependencies
# (sodium, openssl) are declared in Suggests and loaded on demand. Two distinct
# primitives live here:
#   * Passwords  -> one-way hash (Argon2id, via sodium). Cannot be recovered,
#     only verified.
#   * Pushover user keys -> reversible symmetric encryption (AES-CBC), because the
#     key must be decrypted to send the 2FA notification.

# Stop with a helpful message when an optional dependency is missing.
require_pkg <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop(sprintf(
      "Package '%s' is required for the local (server) variant. Install it with install.packages('%s').",
      pkg, pkg
    ), call. = FALSE)
  }
  invisible(TRUE)
}

#' @title Password hashing (server variant)
#'
#' @description One-way password hashing and verification with Argon2id (via the
#'   \code{sodium} package), used by the local credentials variant. Never called
#'   in webR.
#'
#' @param password A plain-text password.
#' @param hash An Argon2id hash previously produced by \code{hash_password()}.
#'
#' @return \code{hash_password()} returns an Argon2id hash string.
#'   \code{verify_password()} returns a logical.
#'
#' @export
hash_password <- function(password) {
  require_pkg("sodium")
  sodium::password_store(password)
}

#' @rdname hash_password
#' @export
verify_password <- function(password, hash) {
  require_pkg("sodium")
  if (is.null(hash) || is.na(hash) || !nzchar(hash)) return(FALSE)
  isTRUE(sodium::password_verify(hash, password))
}

# Resolve the 32-byte master key from the AUTHLAS_KEY environment variable. For
# backward compatibility, fall back to the legacy SHINYMANAGER_KEY if it is set.
sm_master_key <- function() {
  require_pkg("openssl")
  secret <- Sys.getenv("AUTHLAS_KEY", "")
  if (!nzchar(secret)) secret <- Sys.getenv("SHINYMANAGER_KEY", "")
  if (!nzchar(secret)) {
    stop("Set the AUTHLAS_KEY environment variable to encrypt/decrypt Pushover keys.", call. = FALSE)
  }
  openssl::sha256(charToRaw(secret))
}

#' @title Reversible encryption of a user secret (server variant)
#'
#' @description Symmetric AES-CBC encryption used to store each user's Pushover
#'   user key, which must later be decrypted to send the 2FA notification. The
#'   master key is read from the \code{AUTHLAS_KEY} environment variable (the
#'   legacy \code{SHINYMANAGER_KEY} is still honored as a fallback). Never called
#'   in webR.
#'
#' @param x A plain-text secret to encrypt.
#' @param stored A string previously produced by \code{encrypt_secret()}.
#'
#' @return \code{encrypt_secret()} returns a \code{"iv:ciphertext"} base64
#'   string. \code{decrypt_secret()} returns the original plain text.
#'
#' @export
encrypt_secret <- function(x) {
  require_pkg("openssl")
  if (is.null(x) || is.na(x) || !nzchar(x)) return(NA_character_)
  key <- sm_master_key()
  iv <- openssl::rand_bytes(16)
  ct <- openssl::aes_cbc_encrypt(charToRaw(as.character(x)), key = key, iv = iv)
  paste(openssl::base64_encode(iv), openssl::base64_encode(ct), sep = ":")
}

#' @rdname encrypt_secret
#' @export
decrypt_secret <- function(stored) {
  require_pkg("openssl")
  if (is.null(stored) || is.na(stored) || !nzchar(stored)) return(NA_character_)
  parts <- strsplit(stored, ":", fixed = TRUE)[[1]]
  if (length(parts) != 2) stop("Malformed encrypted secret.", call. = FALSE)
  iv <- openssl::base64_decode(parts[1])
  ct <- openssl::base64_decode(parts[2])
  rawToChar(openssl::aes_cbc_decrypt(ct, key = sm_master_key(), iv = iv))
}

# Generate a random numeric code of `digits` digits (as a zero-padded string).
generate_2fa_code <- function(digits = 6L) {
  require_pkg("openssl")
  max_val <- 10^digits
  # 4 cryptographic random bytes -> [0, 2^32); modulo bias over 1e6 is negligible.
  bytes <- as.numeric(openssl::rand_bytes(4))
  val <- sum(bytes * c(1, 256, 65536, 16777216))
  n <- val %% max_val
  formatC(n, width = digits, flag = "0", format = "d")
}
