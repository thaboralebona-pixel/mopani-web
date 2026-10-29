# Mopani Corridor web app

Pilot build. Payments are not available. Increment 1: foundation.

## Setup

    npm ci                      # exact versions from package-lock.json
    cp dev-setup/config.example.js public/config.js   # then edit: anon key only

## Checks

    npm run check               # typecheck, format check, unit tests, build

## Rules

- Development never connects to the production project. The guard refuses it.
- Only the anon key is used in client code.
- No migrations are included. Database changes are owned by the team.

## Run the app

The app must be served over http, not opened from the file system.

    npm ci
    cp dev-setup/config.example.js public/config.js   # then edit: anon key only
    npm run build
    cd dist && python -m http.server 8080            # or any static server

Then open http://localhost:8080 in the browser.

If the page shows "The app has not started", the build has not run or the page was opened as a file.
If it shows a configuration message, check public/config.js against dev-setup/config.example.js.
