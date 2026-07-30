# Widgets

An iOS 17+ app that shows daily numbers as GitHub style contribution graph
widgets on your home and lock screen. Steps, workouts, Strava activity, Toggl
hours, or anything you count yourself.

Site: https://user-416.github.io/widgets-site/

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

## Tests

```sh
cd ios/Shared && swift test
```

App tests run from Xcode with the `Widgets` scheme.

## License

MIT
