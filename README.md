# Widgets

## What this is

Widgets is an iOS 17+ app that turns personal KPIs into GitHub-style contribution heatmap widgets for your home and lock screens. Each metric becomes a grid of squares filling in over the year.

Sources: Apple Health (steps, workouts, sleep, HRV, and more), Strava (activity minutes), Toggl Track (tracked hours), and manual entry. Built with SwiftUI, WidgetKit, and SwiftData.

## Try it without any accounts (fake mode)

DEBUG builds auto-enable **fake mode** when no real credentials are present in the
Keychain. Strava, Apple Health, and manual entry work end-to-end against
deterministic but realistic fake data that mirrors the real API response shapes:

- **Strava**: a faithful `#FC4C02` consent sheet replaces the real OAuth web view,
  followed by a 90-day activity backfill paced and rate-limited like the real API.
- **Apple Health**: 180-day step and workout-minute series with disjoint seeds so
  the two metrics don't visually rhyme.
- **Manual**: unchanged. Manual entry has no network surface.

The toggle lives at **Settings → Debug → Show advanced → Fake mode**, with three
options (`Auto` / `On` / `Off`) and a sub-menu of failure scenarios. Fake mode is
compiled out of RELEASE entirely.

This is the default for simulator work. The integration setup section below is optional.

## Try it in 5 minutes (simulator only)

The fastest way to see it work, with no integration setup:

```bash
git clone <this-repo> widgets
cd widgets
brew install xcodegen
cd ios && xcodegen generate
open Widgets.xcodeproj
```

In Xcode, pick the `Widgets` scheme and any iPhone simulator, then hit Cmd+R.

On first launch you'll see a **Quick start** screen. The simulator has no real Health data, so you'll typically want sample data instead:

1. Tap **Settings**.
2. Scroll to **Debug** (DEBUG builds only).
3. Tap **Seed sample data**. This creates 3 sample metrics with 180 days of deterministic, realistic-looking data.
4. Go back to the metric list to see the heatmaps render with distinct colors per metric.

### Test the widget on the simulator's home screen

The home-screen widget is the actual product. To see it on the simulator's home screen:

```bash
./scripts/sim-prep-for-widget.sh
```

The script builds, re-signs with the correct App Group entitlement (xcodebuild's auto-sign strips it for the simulator), installs into the iPhone simulator, seeds sample data, and brings the simulator window forward.

Then in the simulator:

1. Click and hold an empty area of the home screen for about 1.5 seconds. Icons start jiggling.
2. Click **Edit** (top-left), then **Add Widget**.
3. Find **KPI Grid** in the gallery (search if needed) and tap it.
4. Pick **Small**, **Medium**, or **Large**, then click **Add Widget**.
5. Click **Done** (top-right).

The widget renders today's bucket plus the last 13 to 24 weeks of the seeded data. To switch which metric the widget shows, long-press the placed widget, tap **Edit Widget**, and pick a metric.

For the lock-screen variant: **Settings → Wallpaper → Customize Lock Screen**, tap a widget slot, search **KPI Grid**, pick the rectangular size.

## Run on your iPhone

For real device data (HealthKit, real widgets), you need code signing.

### Apple Developer setup

A free personal Apple Developer team works. Note that personal-team provisioning profiles expire after 7 days, so you'll need to rebuild from Xcode roughly weekly. A paid account ($99/yr) removes that limit.

### Xcode signing

Open `Widgets.xcodeproj` and configure both targets:

1. Select the `Widgets` target.
2. Go to **Signing & Capabilities**.
3. Set **Team** to your Apple ID.
4. Repeat for the **WidgetsWidget** target. Both targets must be signed or the build fails with a missing-entitlement error.

### Bundle ID collision

The default bundle ID is `io.github.user-416.widgets`. If Xcode reports the ID is already taken, edit `ios/project.yml`:

```yaml
options:
  bundleIdPrefix: com.yourname
```

And update the two `PRODUCT_BUNDLE_IDENTIFIER` values lower in the file. Then re-run:

```bash
cd ios && xcodegen generate
```

### Build and run

Plug in your iPhone, select it in the Xcode toolbar device picker, and hit Cmd+R. Trust the developer certificate on the device when prompted (Settings → General → VPN & Device Management).

### First launch

1. Tap **Add metric**.
2. Pick **Steps** or **Workouts**.
3. Grant Apple Health permission when iOS prompts.
4. Your real step history backfills as a heatmap.

## Integration setup (optional)

Fake mode (above) is the default for simulator work. Real-credential setup is only
required when you want to verify against your own live data, or when shipping a
release build (fake mode is `#if DEBUG`-gated and absent from RELEASE).

### Apple Health

Works automatically once you accept the permission prompt. The `NSHealthShareUsageDescription` string is declared in `Info.plist`, and the HealthKit entitlement is in `Widgets/Resources/Widgets.entitlements`. Read-only in release builds.

### Toggl Track

No server needed. In the app, tap **Add metric**, pick **Toggl hours**, and paste your API token (32 hex characters) from https://track.toggl.com/profile. The token is stored in the iOS Keychain and only ever sent to Toggl's API.

### Strava

The most involved integration. Strava's OAuth requires a `client_secret`, which can't ship in the app, so a small Cloudflare Worker handles the code-for-token exchange.

#### 1. Register a Strava app

Go to https://www.strava.com/settings/api and create an app:

- **Application Name**: whatever you want
- **Website**: anything
- **Authorization Callback Domain**: leave the default. Strava's UI requires HTTPS here, but the app uses a custom URL scheme (`widgets://localhost/strava-callback`) for the actual callback.

Note your **Client ID** and **Client Secret**.

#### 2. Deploy the Worker

```bash
cd worker
cp .dev.vars.example .dev.vars   # for `wrangler dev` only, never committed
# edit .dev.vars and paste your real values
npm install
npx wrangler login
npx wrangler secret put STRAVA_CLIENT_ID      # paste Client ID when prompted
npx wrangler secret put STRAVA_CLIENT_SECRET  # paste Client Secret when prompted
npx wrangler deploy
```

`wrangler deploy` prints the deployed URL, something like:

```
https://widgets-worker.<your-account>.workers.dev
```

You can sanity-check with `curl https://<your-deploy>/healthz` — it should return `{"ok":true}`.

#### 3. Set the Client ID and Worker URL in the app

The app reads both values from `Info.plist` keys, populated by `ios/project.yml`. Open `ios/project.yml` and find the two keys under the `Widgets` target's `info.properties`:

```yaml
WORKER_BASE_URL: ''    # paste your wrangler deploy URL
STRAVA_CLIENT_ID: ''   # paste your Strava Client ID
```

Then re-generate the project:

```bash
cd ios && xcodegen generate
```

> Both values fail safely if blank. The Add Strava flow renders an inline "not configured" message instead of crashing, so it's fine to leave them empty until you're ready to test a real Strava build.

#### 4. Connect

Rebuild and run the app. **Add metric** → **Strava** → **Connect** runs the OAuth flow in a system web view. After authorization, a 90-day backfill runs in chunks over the next 10 to 15 minutes (paced for Strava's rate limit).

## Project layout

| Path | Role |
|---|---|
| `ios/project.yml` | xcodegen spec, the source of truth for the Xcode project |
| `ios/Shared/` | Swift package: models, heatmap component, palette |
| `ios/Widgets/` | Main app (SwiftUI, SwiftData, WidgetKit host) |
| `ios/Widgets/Integrations/` | HealthKit, Strava, Toggl, manual entry clients |
| `ios/Widgets/Services/` | Configuration, sync, snapshot writer |
| `ios/WidgetsWidget/` | Widget extension, reads the App Group snapshot only |
| `worker/` | Cloudflare Worker for Strava token exchange |

## Build commands

Regenerate the Xcode project after editing `project.yml` or adding source files:

```bash
cd ios && xcodegen generate
```

Run shared package tests:

```bash
cd ios/Shared && swift test
```

CLI build to simulator:

```bash
cd ios && xcodebuild -project Widgets.xcodeproj -scheme Widgets \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Local Worker dev server:

```bash
cd worker && npx wrangler dev
```

## Troubleshooting

- **Build fails: "missing entitlement"** — you set Team on the `Widgets` target but not on `WidgetsWidget`. Both need a team configured under Signing & Capabilities.
- **Widget doesn't appear in the picker** — wait 30 seconds after install. Widget extensions take a moment to register with the system.
- **Strava OAuth opens but never returns** — verify the `WORKER_BASE_URL` and `STRAVA_CLIENT_ID` keys in `ios/project.yml` are set, you've re-run `xcodegen generate`, and the resulting `ios/Widgets/Resources/Info.plist` shows your real values. `curl https://<worker>/healthz` should return `{"ok":true}`.
- **Add Strava shows "isn't configured for this build"** — same as above; the keys are blank or still contain a placeholder. They're read live from `Bundle.main.object(forInfoDictionaryKey:)`, so a clean install and re-launch picks up changes.
- **Toggl token rejected** — make sure it's the API token (32 hex characters) from track.toggl.com/profile, not your account password.
- **HealthKit shows 0 steps in simulator** — HealthKit observer queries don't fire in the simulator. Use a real device, or open the Health app in the simulator and add manual step entries to seed data.

## License

[MIT](LICENSE).
