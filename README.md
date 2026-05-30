# apartment-hunt
Decision support for apartment hunting — a Shiny app that reads apartment listings from a Google Sheet, geocodes addresses, and displays them on an interactive map with filtering and colour/shape encoding based on listing attributes.

## What it does

- **Loads listings from a Google Sheet** — in public-link mode (recommended for Connect Cloud), no Google login is required in the app. The sheet URL can be overridden at runtime by pasting it into the app UI, otherwise the `SHEET_ID` environment variable is used.
- **Geocodes addresses automatically** — in authenticated mode, new addresses (rows where `lat`/`lng` are blank) are geocoded via OpenStreetMap using `tidygeocoder`, with ", Vancouver, BC, Canada" appended for accuracy, then written back to Google Sheets. In public-link mode, writeback is disabled.
- **Displays an interactive leaflet map** with markers encoding:
  - **Colour** → `Status` (open=blue, tour=green, msg=amber, unavail=grey, denied=red, reject=dark red)
  - **Shape** → `Type` (studio=solid filled circle, 1 bdrm=hollow ring)
  - **Size** → `Rent` or `Ttl_Cost` (user-selectable; defaults to total cost)
- **Filters** in the sidebar:
  - `Status` multi-select (defaults to open/tour/msg)
  - `Type` multi-select (all types selected by default; updates dynamically from sheet values)
  - Four boolean `req_1`–`req_4` checkboxes that are mapped at runtime to the boolean columns between `Ttl_Cost` and `Convenience`
- **Summary table** below the map showing the columns present in the sheet from `Apartment` through `Convenience`, with dynamic boolean formatting and pagination via `DT`.

## Project structure

```
apartment-hunt/
├── ui.R                    # bslib sidebar layout and all controls
├── server.R                # Reactive chain: fetch → geocode → filter → render
├── R/
│   ├── fetch_sheet.R       # Google Sheets auth and data read
│   ├── geocode_writeback.R # Incremental geocoding; writes lat/lng back to sheet
│   └── build_map.R         # leaflet map builder (colour, shape, size, popups)
├── renv.lock               # Pinned R package versions
├── manifest.json           # Posit Connect Cloud deployment manifest
├── .Renviron.example       # Template for required environment variables
└── .gitignore
```

## Google Sheet schema

The sheet is expected to have headers at **row 8**, with at minimum the following columns:

| Column | Description |
|---|---|
| `Address` | Street address (city appended automatically for geocoding) |
| `lat` / `lng` | Populated automatically by the app on first load |
| `Apartment` | Name/identifier of the listing |
| `Status` | Workflow status: `open`, `tour`, `msg`, `unavail`, `denied`, `reject` |
| `Type` | Unit type: `studio`, `1 bdrm`, etc. |
| `Rent` | Monthly rent (numeric or currency-formatted) |
| `Ttl_Cost` | Total monthly cost (numeric or currency-formatted) |
| `Parking_EV` | Boolean — EV parking available |
| `Laundry` | Boolean — in-suite or in-building laundry |
| `Gym` | Boolean — gym available |
| `Amenities` | Boolean — other amenities present |
| `Storage` | Storage availability |
| `Convenience` | Sheet boundary after the boolean requirement columns |
| `date_created` | Row creation date (used as stable key) |
| `date_mod` | Last modified date (used to detect changed rows for re-geocoding) |

## Setup

### Local development

1. Copy `.Renviron.example` to `.Renviron` and fill in:
   ```
   SHEET_ID=<your_google_sheet_id>
  clientID=<oauth_client_id>
  clientSecret=<oauth_client_secret>
  clientType=installed
   ```
  If you created a web OAuth client instead, add `clientRedirectUris` with the exact redirect URI(s) registered in Google Cloud Console.
  If you have multiple Google accounts cached locally, set `GARGLE_OAUTH_EMAIL` to preselect one and skip the chooser.
2. Restore packages: `renv::restore()`
3. Run: `shiny::runApp()`

### Deployment

For Posit Connect Cloud, use public-link mode and set these project variables:

```text
PUBLIC_LINK_MODE=true
SHEET_ID=<google_sheet_id>
SHEET_NAME=<tab_name_optional>
```

In this mode, the app reads sheets without user OAuth and skips writeback operations. Ensure the target sheets are shared for reading by link.

## Dependencies

Key packages: `shiny`, `bslib`, `leaflet`, `DT`, `googlesheets4`, `gargle`, `tidygeocoder`, `dplyr`, `scales`, `jsonlite`, `rsconnect`. All pinned in `renv.lock`.
