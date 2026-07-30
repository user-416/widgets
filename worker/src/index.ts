import { Hono } from "hono";
import type { Context, MiddlewareHandler } from "hono";

// Rate limiter binding (configured in wrangler.toml). Optional at runtime so
// `wrangler dev` and older deployments without the binding still work.
type RateLimiter = { limit(opts: { key: string }): Promise<{ success: boolean }> };

type Env = {
  STRAVA_CLIENT_ID: string;
  STRAVA_CLIENT_SECRET: string;
  TOKEN_RATE_LIMITER?: RateLimiter;
};

type StravaForm = Record<string, string>;

const STRAVA_TOKEN_URL = "https://www.strava.com/oauth/token";

const app = new Hono<{ Bindings: Env }>();

// No CORS headers: this worker is called by a native iOS app, never a browser.
// Omitting them keeps a malicious page from relaying through it from a
// victim's browser.

// Throttle the token endpoints per client IP. These endpoints spend our Strava
// client credentials and count against our API quota, so an open relay is a
// quota-burn risk now that the worker URL is public.
const rateLimit: MiddlewareHandler<{ Bindings: Env }> = async (c, next) => {
  const limiter = c.env.TOKEN_RATE_LIMITER;
  if (limiter) {
    const ip = c.req.header("CF-Connecting-IP") ?? "unknown";
    const { success } = await limiter.limit({ key: ip });
    if (!success) {
      return c.json({ error: "rate_limited" }, 429);
    }
  }
  await next();
};

app.use("/strava/*", rateLimit);

app.get("/healthz", (c) => c.json({ ok: true }));

app.post("/strava/exchange", async (c) => {
  const parsed = await readJsonBody(c);
  if (!parsed.ok) {
    return c.json({ error: "bad_body", message: parsed.message }, 400);
  }
  const body = parsed.value;

  const code = body["code"];
  const codeVerifier = body["code_verifier"];
  if (typeof code !== "string" || code.length === 0) {
    return c.json({ error: "bad_body", message: "code must be a non-empty string" }, 400);
  }
  if (typeof codeVerifier !== "string" || codeVerifier.length === 0) {
    return c.json({ error: "bad_body", message: "code_verifier must be a non-empty string" }, 400);
  }

  const form: StravaForm = {
    client_id: c.env.STRAVA_CLIENT_ID,
    client_secret: c.env.STRAVA_CLIENT_SECRET,
    code,
    code_verifier: codeVerifier,
    grant_type: "authorization_code",
  };

  return await postToStrava(c, form);
});

app.post("/strava/refresh", async (c) => {
  const parsed = await readJsonBody(c);
  if (!parsed.ok) {
    return c.json({ error: "bad_body", message: parsed.message }, 400);
  }
  const body = parsed.value;

  const refreshToken = body["refresh_token"];
  if (typeof refreshToken !== "string" || refreshToken.length === 0) {
    return c.json({ error: "bad_body", message: "refresh_token must be a non-empty string" }, 400);
  }

  const form: StravaForm = {
    client_id: c.env.STRAVA_CLIENT_ID,
    client_secret: c.env.STRAVA_CLIENT_SECRET,
    grant_type: "refresh_token",
    refresh_token: refreshToken,
  };

  return await postToStrava(c, form);
});

type JsonResult =
  | { ok: true; value: Record<string, unknown> }
  | { ok: false; message: string };

async function readJsonBody(c: Context<{ Bindings: Env }>): Promise<JsonResult> {
  let raw: unknown;
  try {
    raw = await c.req.json();
  } catch {
    return { ok: false, message: "request body must be valid JSON" };
  }
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
    return { ok: false, message: "request body must be a JSON object" };
  }
  return { ok: true, value: raw as Record<string, unknown> };
}

async function postToStrava(
  c: Context<{ Bindings: Env }>,
  form: StravaForm,
): Promise<Response> {
  const body = new URLSearchParams(form).toString();

  let upstream: Response;
  try {
    upstream = await fetch(STRAVA_TOKEN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "unknown";
    console.error(`strava fetch failed: ${message}`);
    return c.json({ error: "strava_error", status: 502, body: message }, 502);
  }

  const text = await upstream.text();

  if (!upstream.ok) {
    // Privacy: log status only, never response body.
    console.error(`strava non-2xx status=${upstream.status}`);
    return c.json(
      { error: "strava_error", status: upstream.status },
      upstream.status as 400 | 401 | 403 | 404 | 429 | 500,
    );
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    console.error(`strava success but body was not JSON`);
    return c.json({ error: "strava_error", status: 502 }, 502);
  }

  return c.json(parsed as Record<string, unknown>, 200);
}

export default app;
