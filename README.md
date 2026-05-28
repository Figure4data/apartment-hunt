# apartment-hunt
Decision support for apartment hunting — a Shiny app that reads apartment listings from a Google Sheet, geocodes addresses, and displays them on an interactive map with filtering and colour/shape encoding based on listing attributes.

## What it does

- **Loads listings from a Google Sheet** — authenticated via a Google OAuth client for local development. The sheet URL can be overridden at runtime by pasting it into the app UI, otherwise the `SHEET_ID` environment variable is used.
- **Geocodes addresses automatically** — new addresses (rows where `lat`/`lng` are blank) are geocoded via OpenStreetMap using `tidygeocoder`, with ", Vancouver, BC, Canada" appended for accuracy. Results are written back to the `lat` and `lng` columns of the Google Sheet so geocoding only runs for new rows on subsequent loads.
- **Displays an interactive leaflet map** with markers encoding:
  - **Colour** → `Status` (open=blue, tour=green, msg=amber, unavail=grey, denied=red, reject=dark red)
  - **Shape** → `Type` (studio=solid filled circle, 1 bdrm=hollow ring)
  - **Size** → `Rent` or `Ttl_Cost` (user-selectable; defaults to total cost)
- **Filters** in the sidebar:
  - `Status` multi-select (defaults to open/tour/msg)
  - `Type` multi-select (all types selected by default; updates dynamically from sheet values)
  - Boolean checkboxes for `Parking_EV`, `Laundry`, `Gym`, `Amenities` (when checked, shows only TRUE rows)
- **Summary table** below the map showing: Apartment, Status, Rent, Ttl_Cost, Parking_EV, Laundry, Gym, Storage — with column-level filtering and pagination via `DT`.

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
2. Restore packages: `renv::restore()`
3. Run: `shiny::runApp()`

### Posit Connect Cloud (GitHub-based deployment)

Deployment is triggered automatically on push to `main` via a linked GitHub repo. Before deploying:

1. In the Connect Cloud project settings → **Environment Variables**, set:
   - `SHEET_ID` — bare Google Sheet ID
  - `GCP_SA_JSON` — contents of the service account JSON as a **single-line string**
2. Ensure `manifest.json` is up to date: `rsconnect::writeManifest()`
3. The service account requires read/write access to the Google Sheet (`spreadsheets` scope — not readonly, as the app writes geocoded coordinates back).

## Dependencies

Key packages: `shiny`, `bslib`, `leaflet`, `DT`, `googlesheets4`, `gargle`, `tidygeocoder`, `dplyr`, `scales`, `jsonlite`, `rsconnect`. All pinned in `renv.lock`.
