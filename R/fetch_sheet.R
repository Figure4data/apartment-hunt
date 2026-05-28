library(googlesheets4)
library(dplyr)

#' Authenticate with Google Sheets using the user's OAuth client.
#'
#' The OAuth client ID and secret are read from `clientID` and `clientSecret`
#' in `.Renviron`. For local development, use a Desktop app / installed-app
#' OAuth client. If you use a web client, also set `clientRedirectUris` to the
#' exact redirect URI(s) configured in Google Cloud Console.
gs4_auth_sa <- function() {
  client_id <- trimws(Sys.getenv("clientID"))
  client_secret <- trimws(Sys.getenv("clientSecret"))
  client_type <- tolower(trimws(Sys.getenv("clientType", unset = "installed")))
  redirect_uris_raw <- trimws(Sys.getenv("clientRedirectUris"))

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
  gs4_auth()
}

#' Read the apartment listings sheet.
#'
#' @param sheet_id Google Sheet ID string.
#' @return A data frame with all columns from the sheet.
fetch_sheet <- function(sheet_id) {
  gs4_auth_sa()

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
  for (col in c("Rent", "Ttl_Cost", "Value_Cost")) {
    if (col %in% names(df)) {
      df[[col]] <- as.numeric(gsub("[$,]", "", df[[col]]))
    }
  }

  # Coerce known boolean columns
  bool_cols <- c("Parking_EV", "Laundry", "Gym", "Amenities")
  for (col in bool_cols) {
    if (col %in% names(df)) {
      df[[col]] <- df[[col]] %in% c("TRUE", "true", "True", "1", "yes", "Yes")
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
