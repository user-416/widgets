import { Hono } from "hono";
import type { Context, MiddlewareHandler } from "hono";

type Env = {
  STRAVA_CLIENT_ID: string;
  STRAVA_CLIENT_SECRET: string;
};

type StravaForm = Record<string, string>;

const STRAVA_TOKEN_URL = "https://www.strava.com/oauth/token";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

const cors: MiddlewareHandler = async (c, next) => {
  await next();
  for (const [k, v] of Object.entries(corsHeaders)) {
    c.res.headers.set(k, v);
  }
};

const app = new Hono<{ Bindings: Env }>();

app.use("*", cors);

app.options("*", (c) => {
  return new Response(null, { status: 204, headers: corsHeaders });
});

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
