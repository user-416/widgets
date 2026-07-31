# Widgets

An iOS 17+ app that shows daily numbers as GitHub style contribution graph
widgets on your home and lock screen. Steps, workouts, Strava activity, Toggl
hours, or anything you count yourself.

Site: https://user-416.github.io/widgets-site/

## Before you build

The project was renamed from GridKit to Widgets, which has one consequence:
**it installs as a new app.** The bundle ID, app group, and Keychain service
all changed, so iOS treats it as unrelated to any previously installed build.
Old tokens and cached data won't carry over — delete the old app first.

The Cloudflare Worker deliberately keeps its old name (`gridkit-worker`), since
Cloudflare scopes secrets per worker name and renaming it would mean
re-entering the Strava credentials. It's already deployed and working; nothing
is required to build and run.

## Build

```sh
brew install xcodegen
cd ios && xcodegen generate
open Widgets.xcodeproj
```

Pick the `Widgets` scheme and run. DEBUG builds fall back to fake data when no
real accounts are connected, so everything works in the simulator with no
setup. To seed sample metrics: Settings > Debug > Seed sample data.

To run on a real device, set your team on both the `Widgets` and
`WidgetsWidget` targets under Signing & Capabilities. If the bundle ID is
taken, change `bundleIdPrefix` in `ios/project.yml` and regenerate.

## Integrations

- **Apple Health**: works once you grant permission. Read only.
- **Toggl**: paste your API token from track.toggl.com/profile. Stored in the
  iOS Keychain.
- **Strava**: OAuth needs a client secret, which can't ship in the app, so you
  deploy the small Cloudflare Worker in `worker/`. Register an app at
  strava.com/settings/api, run `npx wrangler deploy` in `worker/`, set
  `STRAVA_CLIENT_ID` and `STRAVA_CLIENT_SECRET` with `wrangler secret put`,
  then put the worker URL and client ID in `ios/project.yml` and regenerate.

## Layout

- `ios/` app, widget extension, and shared Swift package (xcodegen project)
- `worker/` Cloudflare Worker for the Strava token exchange

## Scripts

- `./scripts/sim-prep-for-widget.sh` builds, re-signs with the App Group
  entitlement (xcodebuild strips it for the simulator), seeds sample data, and
  opens the simulator so you can add the widget to the home screen. Search the
  widget gallery for "KPI Grid".
- `./scripts/install-on-iphone.sh` builds and installs on a connected iPhone.
- `./scripts/run-ui-tests.sh` runs the UI tests with the same re-signing fix.

## Tests

```sh
cd ios/Shared && swift test
```

App tests run from Xcode with the `Widgets` scheme. CI runs the unit tests and
the shared package on every push; the UI tests are not run in CI (they need a
booted simulator and are slow), so run them locally with the script above.

## License

MIT
