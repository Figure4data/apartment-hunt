library(googlesheets4)

#' Read the Essentials sheet (headers at row 3).
#'
#' @param sheet_id Google Sheet ID string.
#' @return A data frame with Service, Name, Address, lat, lng columns.
fetch_essentials <- function(sheet_id) {
  df <- read_sheet(sheet_id, sheet = "Essentials", skip=2, col_types = "c")

  # Drop rows where Address is blank
  if ("Address" %in% names(df)) {
    df <- df[!is.na(df$Address) & nchar(trimws(df$Address)) > 0, ]
  }

  # Coerce lat/lng to numeric
  for (col in c("lat", "lng")) {
    if (col %in% names(df)) df[[col]] <- as.numeric(df[[col]])
  }

  df
}
