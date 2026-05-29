library(tidygeocoder)
library(googlesheets4)
library(dplyr)

#' Geocode Essentials rows with missing lat/lng and write back to sheet.
#' Headers are at row 3, data starts at row 4.
geocode_essentials <- function(df, sheet_id) {

  find_col <- function(df, target) {
    nm <- names(df)
    idx <- match(target, trimws(tolower(nm)))
    if (is.na(idx)) return(NA_integer_)
    idx
  }

  # If lat/lng columns are absent, append them to the sheet header + data
  cols_missing <- !c("lat", "lng") %in% names(df)
  if (any(cols_missing)) {
    missing_names <- c("lat", "lng")[cols_missing]
    for (col in missing_names) df[[col]] <- NA_real_

    # Write header + empty data for each missing column
    n_cols_total <- ncol(df)  # after adding the new col(s)
    for (col in missing_names) {
      col_idx   <- which(names(df) == col)
      col_letter <- {
        n <- col_idx; s <- ""
        while (n > 0) { r <- (n - 1) %% 26; s <- paste0(LETTERS[r + 1], s); n <- (n - 1) %/% 26 }
        s
      }
      # Write header cell (row 3)
      range_write(sheet_id,
                  data      = data.frame(x = col),
                  range     = paste0(col_letter, "3"),
                  sheet     = "Essentials",
                  col_names = FALSE,
                  reformat  = FALSE)
    }
    message("Added missing lat/lng columns to Essentials sheet header.")
  }

  has_address   <- !is.na(df$Address) & nchar(trimws(df$Address)) > 0
  needs_geocode <- has_address & (is.na(df$lat) | is.nan(df$lat))

  if (!any(needs_geocode)) {
    message("No new Essentials addresses to geocode.")
    return(df)
  }

  message(sprintf("Geocoding %d new Essentials address(es)...", sum(needs_geocode)))

  to_geocode <- data.frame(
    address = paste0(df$Address[needs_geocode], ", Vancouver, BC, Canada"),
    stringsAsFactors = FALSE
  ) |>
    geocode(address = address, method = "osm", lat = lat_new, long = lng_new)

  df$lat[needs_geocode] <- to_geocode$lat_new
  df$lng[needs_geocode] <- to_geocode$lng_new
  df$lat <- as.numeric(df$lat)
  df$lng <- as.numeric(df$lng)

  col_names <- names(df)
  lat_col_idx <- find_col(df, "lat")
  lng_col_idx <- find_col(df, "lng")

  if (is.na(lat_col_idx) || is.na(lng_col_idx)) {
    stop("Essentials sheet must contain lat and lng columns.")
  }

  # header_row = 3 for Essentials (data starts row 4)
  lat_range <- gs4_range_col(lat_col_idx, nrow(df), header_row = 3)
  lng_range <- gs4_range_col(lng_col_idx, nrow(df), header_row = 3)

  range_write(sheet_id,
              data      = data.frame(lat = df$lat),
              range     = lat_range,
              sheet     = "Essentials",
              col_names = FALSE,
              reformat  = FALSE)

  range_write(sheet_id,
              data      = data.frame(lng = df$lng),
              range     = lng_range,
              sheet     = "Essentials",
              col_names = FALSE,
              reformat  = FALSE)

  message("Essentials lat/lng written back to sheet.")
  df
}
