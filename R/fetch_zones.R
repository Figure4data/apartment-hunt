library(tidygeocoder)
library(googlesheets4)
library(dplyr)

#' Read the Zones sheet tab.
#' Headers are at row 2, data starts at row 3.
#'
#' @param sheet_id  Google Sheet ID string.
#' @return Data frame with zone corner strings and (possibly blank) lat/lng columns.
fetch_zones <- function(sheet_id) {
  if (use_public_link_mode()) {
    googlesheets4::gs4_deauth()
  }

  df <- read_sheet(sheet_id, sheet = "Zones", skip = 2, col_names = TRUE)
  df <- as.data.frame(df)

  # Coerce lat/lng columns to numeric if present
  latlon_cols <- c("lat_ne", "lng_ne", "lat_se", "lng_se",
                   "lat_sw", "lng_sw", "lat_nw", "lng_nw")
  for (col in intersect(latlon_cols, names(df))) {
    df[[col]] <- suppressWarnings(as.numeric(df[[col]]))
  }

  df
}

#' Geocode any zone corners with missing lat/lng and write results back to sheet.
#' Headers are at row 2, data starts at row 3.
#'
#' @param df        Data frame returned by fetch_zones().
#' @param sheet_id  Google Sheet ID string.
#' @return df with all geocodeable corner lat/lng columns filled in.
normalize_street <- function(x) {
  x <- gsub("\\bAve\\.?\\b",      "Avenue",    x, ignore.case = TRUE)
  x <- gsub("\\bBlvd\\.?\\b",     "Boulevard", x, ignore.case = TRUE)
  x <- gsub("\\bDr\\.?\\b",       "Drive",     x, ignore.case = TRUE)
  x <- gsub("\\bRd\\.?\\b",       "Road",      x, ignore.case = TRUE)
  x <- gsub("\\bSt\\.?(?=\\s|$)", "Street",    x, ignore.case = TRUE, perl = TRUE)
  x
}

geocode_zones <- function(df, sheet_id) {
  if (is.null(df) || nrow(df) == 0) return(df)

  corner_pairs <- list(
    ne = c("ne_corner", "lat_ne", "lng_ne"),
    se = c("se_corner", "lat_se", "lng_se"),
    sw = c("sw_corner", "lat_sw", "lng_sw"),
    nw = c("nw_corner", "lat_nw", "lng_nw")
  )

  any_new <- FALSE

  for (cp in corner_pairs) {
    addr_col <- cp[1]; lat_col <- cp[2]; lng_col <- cp[3]

    # Add lat/lng columns if absent
    if (!lat_col %in% names(df)) df[[lat_col]] <- NA_real_
    if (!lng_col %in% names(df)) df[[lng_col]] <- NA_real_

    has_addr     <- !is.na(df[[addr_col]]) & nchar(trimws(df[[addr_col]])) > 0
    needs_geocode <- has_addr & (is.na(df[[lat_col]]) | is.nan(df[[lat_col]]))

    if (!any(needs_geocode)) next

    message(sprintf("Geocoding %d zone %s corner(s)...", sum(needs_geocode), addr_col))
    any_new <- TRUE

    norm_addrs <- normalize_street(df[[addr_col]][needs_geocode])

    geocode_with_fallback <- function(addrs) {
      attempt <- function(fmt_addrs) {
        data.frame(address = paste0(fmt_addrs, ", Vancouver, BC, Canada"),
                   stringsAsFactors = FALSE) |>
          geocode(address = address, method = "osm", lat = lat_new, long = lng_new)
      }
      # Try with "&" first
      result <- attempt(addrs)
      # For any that returned NA, retry with " and "
      still_na <- is.na(result$lat_new)
      if (any(still_na)) {
        retry_addrs <- gsub("\\s*&\\s*", " and ", addrs[still_na])
        message(sprintf("Retrying %d corner(s) with 'and' separator...", sum(still_na)))
        retry <- attempt(retry_addrs)
        result$lat_new[still_na] <- retry$lat_new
        result$lng_new[still_na] <- retry$lng_new
      }
      # Last resort: convert "Nth Ave & Cross St" to approximate house number
      # Vancouver numbered avenues = N*100 block on cross streets (e.g. 16th Ave -> 1600 block)
      still_na <- is.na(result$lat_new)
      if (any(still_na)) {
        approx_addr <- sapply(addrs[still_na], function(a) {
          parts <- trimws(strsplit(a, "\\s*(and|&)\\s*")[[1]])
          if (length(parts) != 2) return(a)
          ave_pattern <- "^([NSEW]\\s+)?(\\d+)(st|nd|rd|th)\\s+Avenue?$"
          for (idx in 1:2) {
            m <- regmatches(parts[idx], regexpr(ave_pattern, parts[idx], ignore.case = TRUE, perl = TRUE))
            if (length(m) == 1) {
              n <- as.integer(gsub("[^0-9]", "", regmatches(parts[idx],
                    regexpr("\\d+", parts[idx]))))
              cross <- normalize_street(parts[3 - idx])
              return(paste0(n * 100, " ", cross))
            }
          }
          a  # no avenue found, return unchanged
        })
        message(sprintf("Retrying %d corner(s) as approximate house numbers...", sum(still_na)))
        retry3 <- attempt(approx_addr)
        result$lat_new[still_na] <- retry3$lat_new
        result$lng_new[still_na] <- retry3$lng_new
      }
      result
    }

    to_geocode <- geocode_with_fallback(norm_addrs)

    df[[lat_col]][needs_geocode] <- to_geocode$lat_new
    df[[lng_col]][needs_geocode] <- to_geocode$lng_new
    df[[lat_col]] <- as.numeric(df[[lat_col]])
    df[[lng_col]] <- as.numeric(df[[lng_col]])
  }

  if (!any_new) {
    message("No new zone corners to geocode.")
    return(df)
  }

  # Write all 8 lat/lng columns back to sheet (data starts row 3, so header_row = 2)
  latlon_cols <- c("lat_ne", "lng_ne", "lat_se", "lng_se",
                   "lat_sw", "lng_sw", "lat_nw", "lng_nw")
  col_names <- names(df)

  for (col in intersect(latlon_cols, col_names)) {
    col_idx <- which(col_names == col)
    rng     <- gs4_range_col(col_idx, nrow(df), header_row = 2)
    range_write(sheet_id,
                data      = data.frame(x = df[[col]]),
                range     = rng,
                sheet     = "Zones",
                col_names = FALSE,
                reformat  = FALSE)
  }

  message("Zone lat/lng written back to sheet.")
  df
}
