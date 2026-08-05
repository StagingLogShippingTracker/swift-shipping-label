# Swift Recreate Logo (Fly.io) — UNUSED

> **Aborted.** Do not deploy this service for production Recreate.
> On-device Rust (`native/logo_recreate`) + Supabase Deno fallback replace
> this path. Files here are kept only as unused scaffolding.

Runs the same Python pipeline as Windows local Recreate
(`tools.logo_vectorizer.customer_recreate`) — useful only if someone
intentionally revives a cloud Bezier server later.

## Endpoints (if ever redeployed)

- `GET /health` — liveness
- `POST /recreate-logo?render_width=3000` — raw image body → JSON

Auth: `Authorization: Bearer <RECREATE_AUTH_TOKEN>` (or `apikey` header).

## Deploy (do not run for current product direction)

```bash
fly auth login
fly apps create swift-recreate-logo
fly secrets set RECREATE_AUTH_TOKEN="<supabase anon key used by the app>" -a swift-recreate-logo
fly deploy --config services/recreate-logo/fly.toml --dockerfile services/recreate-logo/Dockerfile
```
