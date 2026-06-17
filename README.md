# apartment-hunt
Decision support for apartment hunting — a Shiny app that reads apartment listings from a Google Sheet, geocodes addresses, and displays them on an interactive map with filtering and colour/shape encoding based on listing attributes.

Published on Posit Connect Cloud.

## What it does

- **Loads listings from a Google Sheet** — in public-link mode (recommended for Connect Cloud), no Google login is required in the app. The sheet URL can be overridden at runtime by pasting it into the app UI, otherwise the `SHEET_ID` environment variable is used.
- **Template onboarding link** — optionally show a "Get Template Sheet" link in the sidebar by setting `TEMPLATE_SHEET_URL` (and optional `TEMPLATE_SHEET_LABEL`).
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

Fetching is handled via fetch_sheet.R
- sheet name for main listings sheet is specified in env vars.
- headers are expected at row 10; set in fetch_sheet.R, range_spec (ln 259)

The sheet is expected to have headers at **row 10**, with at minimum the following columns:

| Column | Description |
|---|---|
| `Address` | Street address (city appended automatically for geocoding) |
| `lat` / `lng` | Populated automatically by the app on first load |
| `Apartment` | Name/identifier of the listing |
| `Status` | Workflow status: `open`, `tour`, `msg`, `unavail`, `denied`, `reject` |
| `Type` | Unit type: `studio`, `1 bdrm`, etc. |
| `Rent` | Monthly rent (numeric or currency-formatted) |
| `Ttl_Cost` | Total monthly cost (numeric or currency-formatted) |
| `main requiremments (up to 4)` | Boolean |
| `Convenience` | Sheet boundary after the boolean requirement columns |
| `secondary requirements (up to 4)` | Boolean |
| `Value_Cost`| numeric value representing value relative to ttl cost |
| `Notes` | comments on the listing |
| `Link` | url for listing |
| `date_created` | Row creation date (used as stable key) |
| `date_mod` | Last modified date (used to detect changed rows for re-geocoding) |

## Setup

- ensure sheet range used matches header rows of main sheet (Prospects):
  - fetch_sheet.R > range_spec (ln 259)
  - geocode_writeback.R > gs4_range_col (ln 91)

### Local development

1. Copy `.Renviron.example` to `.Renviron` and fill in:
   ```
   SHEET_ID=<your_google_sheet_id>
   SHEET_NAME=<name of main listings sheet>
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

### Deployment with real-time writeback (service account)

If you need geocode writeback in hosted mode, enable service-account mode and set:

```text
SERVICE_ACCOUNT_MODE=true
SERVICE_ACCOUNT_EMAIL=<service_account_email>
GCP_SA_JSON=<single-line-service-account-json>
SHEET_ID=<default_sheet_id_optional>
SHEET_NAME=<tab_name_optional>
```

In this mode, the app checks access for the pasted sheet and, if needed, shows an onboarding modal telling the user to share the sheet with the service account as Editor. After sharing, users click Retry Access and continue without restarting the app.

## Dependencies

Key packages: `shiny`, `bslib`, `leaflet`, `DT`, `googlesheets4`, `gargle`, `tidygeocoder`, `dplyr`, `scales`, `jsonlite`, `rsconnect`. All pinned in `renv.lock`.
