library(shiny)
library(leaflet)
library(DT)
library(dplyr)

source("R/fetch_sheet.R")
source("R/geocode_writeback.R")
source("R/fetch_essentials.R")
source("R/geocode_essentials.R")
source("R/fetch_zones.R")
source("R/build_map.R")

server <- function(input, output, session) {

  public_mode <- use_public_link_mode()
  auth_ready <- reactiveVal(public_mode || googlesheets4::gs4_has_token())

  output$google_auth_status <- renderText({
    if (public_mode) {
      return("Public-link mode (no Google login)")
    }
    if (auth_ready() && googlesheets4::gs4_has_token()) {
      paste("Connected as", googlesheets4::gs4_user())
    } else {
      "Not connected"
    }
  })
  output$public_link_mode <- reactive({ public_mode })
  outputOptions(output, "public_link_mode", suspendWhenHidden = FALSE)

  observeEvent(input$connect_google, {
    if (public_mode) {
      auth_ready(TRUE)
      showNotification(
        "Public-link mode enabled. Google login is not required.",
        type = "message",
        duration = 5
      )
      return()
    }

    tryCatch({
      gs4_auth_user()
      auth_ready(TRUE)
      showNotification(
        paste("Connected as", googlesheets4::gs4_user()),
        type = "message",
        duration = 5
      )
    }, error = function(e) {
      auth_ready(FALSE)
      showNotification(
        paste("Google auth failed:", conditionMessage(e)),
        type = "error",
        duration = 10
      )
    })
  })

  output$boolean_filters_ui <- renderUI({
    checkboxGroupInput(
      "bool_filters",
      label = "Features:",
      choices = character(0),
      selected = character(0)
    )
  })

  # ── Resolve sheet ID ────────────────────────────────────────────────────────
  # Extracts bare sheet ID from a full URL or returns the string unchanged
  # if it's already a bare ID.
  extract_id <- function(s) {
    m <- regmatches(s, regexpr("(?<=/d/)[A-Za-z0-9_-]+", s, perl = TRUE))
    if (length(m) == 1) return(m)
    if (grepl("^[A-Za-z0-9_-]{20,}$", s)) return(s)  # looks like a bare ID
    NULL
  }

  sheet_id <- reactive({
    url <- trimws(input$sheet_url)
    if (nchar(url) > 0) {
      id <- extract_id(url)
      if (!is.null(id)) return(id)
      showNotification("Could not parse Sheet ID from URL.", type = "error")
      return(NULL)
    }
    raw <- Sys.getenv("SHEET_ID")
    if (nchar(raw) == 0) {
      showNotification("No SHEET_ID env var set and no URL provided.", type = "error")
      return(NULL)
    }
    id <- extract_id(raw)
    if (is.null(id)) {
      showNotification("SHEET_ID env var is not a valid ID or URL.", type = "error")
      return(NULL)
    }
    id
  })

  # ── Fetch + geocode (triggered by reload button) ─────────────────────────────
  apt_data <- eventReactive(input$reload, {
    req(auth_ready())
    req(sheet_id())
    withProgress(message = "Loading sheet...", value = 0.2, {
      df <- fetch_sheet(sheet_id())
      if (!public_mode) {
        setProgress(0.5, message = "Geocoding new addresses...")
        df <- tryCatch(
          geocode_writeback(df, sheet_id()),
          error = function(e) {
            showNotification(paste("Geocoding error:", conditionMessage(e)),
                             type = "warning", duration = 10)
            df
          }
        )
      }
      setProgress(1, message = "Done")
      df
    })
  }, ignoreNULL = FALSE)

  # ── Fetch + geocode Essentials (same reload trigger) ─────────────────────────
  essentials_data <- eventReactive(input$reload, {
    req(auth_ready())
    req(sheet_id())
    tryCatch({
      df <- fetch_essentials(sheet_id())
      if (is.null(df) || nrow(df) == 0) {
        showNotification("Essentials sheet loaded but has no rows.", type = "warning")
        return(NULL)
      }
      if (public_mode) {
        df
      } else {
        tryCatch(
          geocode_essentials(df, sheet_id()),
          error = function(e) {
            showNotification(paste("Essentials geocoding error:", conditionMessage(e)),
                             type = "warning", duration = 15)
            df
          }
        )
      }
    }, error = function(e) {
      showNotification(paste("Could not load Essentials sheet:", conditionMessage(e)),
                       type = "warning", duration = 15)
      NULL
    })
  }, ignoreNULL = FALSE)

  # ── Filtered data ────────────────────────────────────────────────────────────
  filtered_data <- reactive({
    df <- apt_data()
    if (is.null(df) || nrow(df) == 0) return(df)

    bool_cols <- sheet_boolean_cols(df)
    selected_bool_filters <- if (is.null(input$bool_filters)) character(0) else input$bool_filters

    # Status filter
    if (length(input$status_filter) > 0) {
      df <- df |> filter(tolower(Status) %in% tolower(input$status_filter))
    }

    # Boolean filters (show only TRUE when checkbox ticked)
    selected_bool_cols <- intersect(selected_bool_filters, bool_cols)
    for (col_name in selected_bool_cols) {
      if (col_name %in% names(df)) {
        df <- df |> filter(.data[[col_name]] %in% TRUE)
      }
    }

    # Total cost filter
    if (!is.null(input$cost_filter)) {
      df <- df |> filter(
        is.na(Ttl_Cost) | (Ttl_Cost >= input$cost_filter[1] & Ttl_Cost <= input$cost_filter[2])
      )
    }

    # Type filter
    if (length(input$type_filter) > 0) {
      df <- df |> filter(tolower(trimws(Type)) %in% tolower(input$type_filter))
    }

    df
  })

  # ── Dynamic Status choices (update when sheet reloads) ──────────────────────
  observeEvent(apt_data(), {
    df <- apt_data()
    selected_bool_filters <- if (is.null(input$bool_filters)) character(0) else input$bool_filters

    statuses <- sort(unique(tolower(df$Status)))
    updateSelectInput(session, "status_filter",
                      choices  = statuses,
                      selected = intersect(c("tour", "open", "msg","applied","decide"), statuses))

    types <- sort(unique(tolower(trimws(df$Type))))
    updateSelectInput(session, "type_filter",
                      choices  = types,
                      selected = types)

    bool_cols <- sheet_boolean_cols(df)
    bool_labels <- setNames(gsub("_", " ", bool_cols), bool_cols)
    updateCheckboxGroupInput(
      session,
      "bool_filters",
      choices = bool_labels,
      selected = intersect(selected_bool_filters, bool_cols)
    )

    cost_vals <- as.numeric(df$Ttl_Cost)
    cost_vals <- cost_vals[!is.na(cost_vals)]
    if (length(cost_vals) > 0) {
      cmin <- floor(min(cost_vals) / 100) * 100
      cmax <- ceiling(max(cost_vals) / 100) * 100
      updateSliderInput(session, "cost_filter",
                        min   = cmin, max = cmax,
                        value = c(cmin, cmax))
    }
  })

  observeEvent(essentials_data(), {
    df <- essentials_data()
    if (is.null(df) || nrow(df) == 0) {
      updateCheckboxGroupInput(session, "essentials_filter",
                               choices = character(0), selected = character(0))
      return()
    }
    svcs <- sort(unique(trimws(df$Service)))
    updateCheckboxGroupInput(session, "essentials_filter",
                             choices  = svcs,
                             selected = svcs)
  }, ignoreNULL = FALSE)

  # ── Fetch + geocode Zones (same reload trigger) ─────────────────────────────
  zones_data <- eventReactive(input$reload, {
    req(auth_ready())
    req(sheet_id())
    tryCatch({
      df <- fetch_zones(sheet_id())
      if (is.null(df) || nrow(df) == 0) return(NULL)
      if (public_mode) {
        df
      } else {
        tryCatch(
          geocode_zones(df, sheet_id()),
          error = function(e) {
            showNotification(paste("Zone geocoding error:", conditionMessage(e)),
                             type = "warning", duration = 15)
            df
          }
        )
      }
    }, error = function(e) {
      showNotification(paste("Could not load Zones sheet:", conditionMessage(e)),
                       type = "warning", duration = 15)
      NULL
    })
  }, ignoreNULL = FALSE)

  # ── Map ──────────────────────────────────────────────────────────────────────
  output$map <- renderLeaflet({
    ess <- essentials_data()
    if (!is.null(ess) && nrow(ess) > 0 && length(input$essentials_filter) > 0) {
      ess <- ess[trimws(ess$Service) %in% input$essentials_filter, ]
    } else {
      ess <- NULL
    }
    zones <- if (isTRUE(input$show_zones)) zones_data() else NULL
    build_map(filtered_data(), size_col = input$size_col, color_col = input$color_col,
              essentials = ess, zones = zones)
  })

  # ── Table ────────────────────────────────────────────────────────────────────
  output$table <- renderDT({
    df <- filtered_data()
    cols <- sheet_table_cols(df)
    df_tbl <- df[, cols, drop = FALSE]
    bool_cols <- cols[vapply(df_tbl, is.logical, logical(1))]
    for (col in bool_cols) {
      df_tbl[[col]] <- ifelse(df_tbl[[col]], "\u2713", "\u2717")
    }
    curr_cols <- intersect(c("Rent", "Ttl_Cost", "Value_Cost"), cols)
    for (col in curr_cols) {
      df_tbl[[col]] <- paste0("$", formatC(as.numeric(df_tbl[[col]]), format = "f", digits = 0, big.mark = ","))
    }
    # Truncate long text columns with tooltip showing full text on hover
    truncate_col <- function(df_tbl, col, max_chars) {
      full <- ifelse(is.na(df_tbl[[col]]), "", df_tbl[[col]])
      ifelse(
        nchar(full) > max_chars,
        paste0("<span title='", gsub("'", "&#39;", full), "'>",
               substr(full, 1, max_chars), "&hellip;</span>"),
        paste0("<span title='", gsub("'", "&#39;", full), "'>", full, "</span>")
      )
    }
    if ("Apartment" %in% cols) {
      full_apt  <- ifelse(is.na(df_tbl[["Apartment"]]), "", df_tbl[["Apartment"]])
      has_link  <- "Link" %in% names(df) & !is.na(df[["Link"]]) & nchar(trimws(df[["Link"]])) > 0
      link_vals <- if ("Link" %in% names(df)) df[["Link"]] else rep(NA_character_, nrow(df_tbl))
      truncated <- ifelse(
        nchar(full_apt) > 25,
        paste0(substr(full_apt, 1, 25), "&hellip;"),
        full_apt
      )
      df_tbl[["Apartment"]] <- ifelse(
        !is.na(link_vals) & nchar(trimws(link_vals)) > 0,
        paste0("<a href='", link_vals, "' target='_blank' title='", gsub("'", "&#39;", full_apt), "'>", truncated, "</a>"),
        paste0("<span title='", gsub("'", "&#39;", full_apt), "'>", truncated, "</span>")
      )
    }
    if ("Notes"     %in% cols) df_tbl[["Notes"]]     <- truncate_col(df_tbl, "Notes",     20)
    bool_col_indices <- which(cols %in% bool_cols) - 1  # 0-based for JS
    curr_col_indices <- which(cols %in% curr_cols) - 1
    datatable(
      df_tbl,
      rownames  = FALSE,
      escape    = FALSE,
      filter    = "none",
      options   = list(
        pageLength  = 20,
        scrollX     = TRUE,
        columnDefs  = list(
          list(className = "dt-center", targets = bool_col_indices),
          list(className = "dt-right",  targets = curr_col_indices)
        )
      )
    )
  })
}
