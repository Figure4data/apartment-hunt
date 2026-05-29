library(googlesheets4)
library(dplyr)

decode_oauth_token <- function(x) {
  tryCatch(
    {
      raw <- base64enc::base64decode(x)
      unserialize(raw)
    },
    error = function(e) {
      stop(
        paste(
          "Failed to decode GS4_OAUTH_TOKEN_B64.",
          "Recreate it from a successfully authenticated local session.",
          "Make sure the value was pasted as a single line with no quotes or truncation.",
          conditionMessage(e)
        ),
        call. = FALSE
      )
    }
  )
}

get_env_chunked <- function(prefix) {
  single <- trimws(Sys.getenv(prefix, unset = ""))
  if (nchar(single) > 0) return(single)

  chunks <- character()
  for (i in seq_len(1000)) {
    value <- trimws(Sys.getenv(sprintf("%s_%d", prefix, i), unset = ""))
    if (nchar(value) == 0) {
      if (i == 1) return("")
      break
    }
    chunks <- c(chunks, value)
  }
  paste(chunks, collapse = "")
}

sheet_cols_between <- function(df, start_col, end_col = NULL) {
  nm <- names(df)
  if (is.null(nm) || length(nm) == 0) return(character())

  start_idx <- match(start_col, nm)
  if (is.na(start_idx)) start_idx <- 1L

  end_idx <- if (is.null(end_col)) {
    length(nm)
  } else {
    match(end_col, nm)
  }
  if (is.na(end_idx) || end_idx < start_idx) end_idx <- length(nm)

  nm[start_idx:end_idx]
}

sheet_col_is_blank <- function(x) {
  if (is.null(x)) return(TRUE)
  x_chr <- trimws(as.character(x))
  all(is.na(x_chr) | x_chr == "")
}

sheet_col_is_flag <- function(x) {
  if (is.logical(x)) return(TRUE)
  x_chr <- tolower(trimws(as.character(x)))
  x_chr <- x_chr[!is.na(x_chr) & x_chr != ""]
  if (length(x_chr) == 0) return(FALSE)
  all(x_chr %in% c("true", "false", "1", "0", "yes", "no", "y", "n"))
}

sheet_boolean_cols <- function(df) {
  cols <- names(df)
  cols <- cols[!grepl("req", cols, ignore.case = TRUE)]
  cols <- cols[cols %in% names(df)]
  cols[vapply(df[cols], sheet_col_is_flag, logical(1))]
}

sheet_table_cols <- function(df) {
  cols <- names(df)
  if ("Apartment" %in% cols) {
    cols <- cols[match("Apartment", cols):length(cols)]
  }

  exclude <- c("convenience", "ttl_conditions", "added_value", "lat", "lng", "link", "heat")
  cols <- cols[!grepl("req", cols, ignore.case = TRUE)]
  cols <- cols[!tolower(cols) %in% exclude]
  cols <- cols[cols %in% names(df)]
  cols[!vapply(df[cols], sheet_col_is_blank, logical(1))]
}

sheet_as_flag <- function(x) {
  if (is.logical(x)) return(x)
  x_chr <- tolower(trimws(as.character(x)))
  ifelse(is.na(x_chr) | x_chr == "", NA, x_chr %in% c("true", "1", "yes", "y"))
}

#' Authenticate with Google Sheets using the user's OAuth client.
#'
#' The OAuth client ID and secret are read from `clientID` and `clientSecret`
#' in `.Renviron`. For local development, use a Desktop app / installed-app
#' OAuth client. If you use a web client, also set `clientRedirectUris` to the
#' exact redirect URI(s) configured in Google Cloud Console.
#'
#' If `GARGLE_OAUTH_EMAIL` is set, it will be used to preselect a cached Google
#' account and avoid the account chooser when multiple identities are available.
gs4_auth_user <- function() {
  client_id <- trimws(Sys.getenv("clientID"))
  client_secret <- trimws(Sys.getenv("clientSecret"))
  client_type <- tolower(trimws(Sys.getenv("clientType", unset = "installed")))
  redirect_uris_raw <- trimws(Sys.getenv("clientRedirectUris"))
  oauth_email <- trimws(Sys.getenv("GARGLE_OAUTH_EMAIL", unset = ""))
  oauth_token_b64 <- get_env_chunked("GS4_OAUTH_TOKEN_B64")

  if (nchar(client_id) == 0 || nchar(client_secret) == 0) {
    stop("clientID and clientSecret must be set in .Renviron.")
  }

  redirect_uris <- if (identical(client_type, "web")) {
    if (nchar(redirect_uris_raw) > 0) {
      strsplit(redirect_uris_raw, "\\s*,\\s*")[[1]]
    } else {
      c("http://localhost:1410/", "http://localhost:1410")
    }
  } else if (nchar(redirect_uris_raw) > 0) {
    strsplit(redirect_uris_raw, "\\s*,\\s*")[[1]]
  } else {
    NULL
  }

  client <- gargle::gargle_oauth_client(
    id = client_id,
    secret = client_secret,
    type = if (client_type %in% c("web", "installed")) client_type else "installed",
    redirect_uris = redirect_uris,
    name = "apartment-hunt"
  )

  gs4_auth_configure(client = client)

  if (nchar(oauth_token_b64) > 0) {
    gs4_auth(token = decode_oauth_token(oauth_token_b64))
    return(invisible(TRUE))
  }

  if (!interactive()) {
    stop(
      paste(
        "No noninteractive Google token is available.",
        "Set GS4_OAUTH_TOKEN_B64 as a Connect Cloud secret variable,",
        "or authenticate interactively once so a cached token can be discovered."
      )
    )
  }

  if (nchar(oauth_email) > 0) {
    gs4_auth(email = oauth_email)
  } else {
    gs4_auth()
  }
}

#' Read the apartment listings sheet.
#'
#' @param sheet_id Google Sheet ID string.
#' @return A data frame with all columns from the sheet.
fetch_sheet <- function(sheet_id) {
  # Headers are at row 8; read from row 8 onward
  sheet_name <- Sys.getenv("SHEET_NAME", unset = NA)
  range_spec  <- if (!is.na(sheet_name) && nchar(sheet_name) > 0) {
    googlesheets4::cell_limits(
      ul = c(8, 1), lr = c(NA, NA), sheet = sheet_name
    )
  } else {
    "8:10000"
  }
  df <- read_sheet(sheet_id, range = range_spec, col_types = "c")

  # Drop rows where Address is blank — these are empty trailing rows
  if ("Address" %in% names(df)) {
    df <- df[!is.na(df$Address) & nchar(trimws(df$Address)) > 0, ]
  }

  # Coerce known numeric columns, stripping currency formatting if present
  for (col in c("Rent", "Ttl_Cost")) {
    if (col %in% names(df)) {
      df[[col]] <- as.numeric(gsub("[$,]", "", df[[col]]))
    }
  }

  # Coerce boolean columns so the app can adapt to different sheet layouts.
  bool_cols <- sheet_boolean_cols(df)
  for (col in bool_cols) {
    if (col %in% names(df)) {
      df[[col]] <- sheet_as_flag(df[[col]])
    }
  }

  # Coerce lat/lng to numeric
  for (col in c("lat", "lng")) {
    if (col %in% names(df)) {
      df[[col]] <- as.numeric(df[[col]])
    }
  }

  df
}
