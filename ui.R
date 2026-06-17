library(shiny)
library(bslib)
library(leaflet)
library(DT)

ui <- page_sidebar(
  title = tagList(
    tags$span(
      style = "display:flex; align-items:center; gap:0.4em; font-size:1.6rem; font-weight:700; line-height:1.2;",
      icon("house", style = "width:1.3em; height:1.3em;"),
      "APARTMENT HUNTER"
    )
  ),
  theme = bs_theme(
    bootswatch = "litera",
    primary    = "#2C7BB6",   # teal-blue — complements the map palette
    secondary  = "#6C757D"
  ),
  tags$head(tags$style(HTML("
    .navbar { min-height: 72px !important; padding-top: 0.6rem !important; padding-bottom: 0.6rem !important; }
    .navbar .navbar-brand, .navbar .navbar-brand * { font-size: 1.6rem !important; line-height: 1.2 !important; }
    .navbar-brand svg { width: 1.4em !important; height: 1.4em !important; vertical-align: middle !important; }
  "))),
  sidebar = sidebar(
    width = 280,
    bg = "#f4f7fa",           # faint blue-grey sidebar background

    # --- Sheet connection ---
    card(
      card_header("Google Sheet", class = "bg-light fw-semibold"),
      {
        template_url <- trimws(Sys.getenv("TEMPLATE_SHEET_URL", unset = ""))
        template_label <- trimws(Sys.getenv("TEMPLATE_SHEET_LABEL", unset = "Get Template Sheet"))
        if (nchar(template_url) > 0) {
          tags$p(
            tags$a(
              href = template_url,
              target = "_blank",
              rel = "noopener noreferrer",
              template_label
            ),
            style = "margin: 0 0 0.1rem 0; text-align: center; font-size: 0.86rem; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;"
          )
        }
      },
      textInput(
        "sheet_url",
        label = NULL,
        placeholder = "Paste Sheet URL or sheet ID (optional)"
      ),
      uiOutput("auth_controls_ui"),
      textOutput("google_auth_status"),
      actionButton("reload", "Load / Reload", icon = icon("rotate"),
                   class = "btn-primary w-100")
    ),

    # --- Map encoding ---
    card(
      card_header("Map Encoding", class = "bg-light fw-semibold"),
      radioButtons(
        "color_col",
        "Marker colour:",
        choices = c("Status" = "Status", "Value-Cost" = "Value_Cost"),
        selected = "Status",
        inline = TRUE
      ),
      radioButtons(
        "size_col",
        "Marker size:",
        choices = c("Rent" = "Rent", "Total Cost" = "Ttl_Cost"),
        selected = "Ttl_Cost",
        inline = TRUE
      )
    ),

    # --- Filters ---
    card(
      card_header("Filters", class = "bg-light fw-semibold"),
      selectInput(
        "status_filter",
        "Status:",
        choices  = c("denied", "tour", "open", "ref", "unavail", "reject", "msg"),
        selected = c("tour", "open", "msg","applied","decide"),
        multiple = TRUE
      ),
      selectInput(
        "type_filter",
        "Type:",
        choices  = c("studio", "1 bdrm"),
        selected = c("studio", "1 bdrm"),
        multiple = TRUE
      ),
      sliderInput(
        "cost_filter",
        "Total Cost ($):",
        min   = 0,
        max   = 5000,
        value = c(0, 5000),
        step  = 100,
        pre   = "$"
      ),
      uiOutput("boolean_filters_ui")
    ),

    # --- Zones overlay ---
    card(
      card_header("Zones", class = "bg-light fw-semibold"),
      checkboxInput("show_zones", "Show priority zones", value = TRUE)
    ),

    # --- Essentials overlay ---
    card(
      card_header("Essentials", class = "bg-light fw-semibold"),
      checkboxGroupInput(
        "essentials_filter",
        label = NULL,
        choices  = character(0),
        selected = character(0)
      )
    )
  ),

  # --- Main panel ---
  layout_columns(
    col_widths = 12,
    min_height = "1200px",

    card(
      full_screen = TRUE,
      card_header("Map", class = "bg-primary text-white"),
      leafletOutput("map")
    ),

    card(
      card_header("Listings", class = "bg-primary text-white"),
      DTOutput("table")
    )
  )
)
