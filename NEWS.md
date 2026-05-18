# shinymanager.webr 0.1.0

* Initial lightweight fork for Shiny apps running with webR/WebAssembly.
* Authentication is delegated to an external identity provider such as Auth0.
* Added `secure_app_external()`, `secure_server_external()`, and `check_credentials_external()`.
* Kept the shinymanager visual container, language labels, session token gate, and floating logout button.
* Removed classic username/password login, SQLite/SQL credential storage, admin panel, password management, and related heavy dependencies.
