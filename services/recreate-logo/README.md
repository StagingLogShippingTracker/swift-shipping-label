# Swift Recreate Logo (Fly.io)

Premium Python Recreate service — same pipeline as Windows local
(`tools.logo_vectorizer.customer_recreate`).

Used by the Flutter app when online:

- **Android:** Fly first → on-device Rust if offline/Fly fails → optional
  Supabase vtracer last resort
- **Windows:** local Python if present; otherwise Fly when online, Rust offline

## Endpoints

- `GET /health` — liveness (`{"ok":true,"auth_configured":true}`)
- `POST /recreate-logo?render_width=3000` — raw image body → JSON
  (`svg`, `png_base64`, `palette_hex`, `section_count`, …)

Auth: `Authorization: Bearer <RECREATE_AUTH_TOKEN>` (or `apikey` header).
The mobile app sends the Supabase anon key; set that as the Fly secret.

## Optional Gemini assist

When `GEMINI_API_KEY` (or `GOOGLE_API_KEY`) is set on the machine / Fly secrets,
Recreate runs a Gemini vision pre-pass for brand colors, font hints, and layout
before vectorization. `/health` reports `gemini_configured`.

```bash
fly secrets set GEMINI_API_KEY="<key>" GEMINI_PROJECT_NUMBER="308655478522" GEMINI_MODEL="gemini-2.0-flash" -a swift-recreate-logo
```

## Deploy

From the **repo root** (build context = repo root):

```bash
fly auth login
fly apps create swift-recreate-logo
fly secrets set RECREATE_AUTH_TOKEN="<supabase anon key used by the app>" -a swift-recreate-logo
fly deploy . --config services/recreate-logo/fly.toml --ha=false
```

Live URL: https://swift-recreate-logo.fly.dev/
