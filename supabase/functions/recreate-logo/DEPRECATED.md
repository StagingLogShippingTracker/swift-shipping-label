# Deprecated — cloud fallback only

This Deno/`vtracer` edge function is the **network fallback** for Recreate
when on-device Rust (`native/logo_recreate`) is unavailable and Windows
local Python is not present.

The Fly.io Python Bezier service experiment (`services/recreate-logo/`)
was **aborted** — do not treat fly.dev as the primary endpoint.

Preferred client order (see `mobile/lib/logo_recreate.dart`):

1. Windows local Python Bezier pipeline
2. On-device Rust FFI
3. This Supabase edge function
