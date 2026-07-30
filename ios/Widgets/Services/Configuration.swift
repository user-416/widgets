import Foundation

enum Configuration {
    /// URL of the deployed Cloudflare Worker that handles upstream OAuth code-
    /// for-token exchanges (Strava). Set the `WORKER_BASE_URL` key in
    /// `Info.plist` to your deployed Worker (e.g.
    /// `https://widgets-worker.your-subdomain.workers.dev`). When `nil`, the
    /// Strava Add flow surfaces an inline "not configured" message instead of
    /// crashing.
    static var workerBaseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "WORKER_BASE_URL") as? String,
              !raw.isEmpty,
              !raw.contains("example.workers.dev"),
              let url = URL(string: raw)
        else { return nil }
        return url
    }

    /// Backwards-compatible alias kept for call sites that haven't migrated
    /// yet. Resolves to the same value as `workerBaseURL`.
    static var stravaWorkerBaseURL: URL? { workerBaseURL }
}
