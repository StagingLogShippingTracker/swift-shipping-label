# Deprecated naming — still the last-resort cloud path

This Deno/`vtracer` edge function is the **network last resort** for Recreate
when Fly.io Python fails (or is unreachable) and on-device Rust
(`native/logo_recreate`) is unavailable, and (on Windows) local Python is
not present.

**Preferred client order** (see `mobile/lib/logo_recreate.dart`):

1. Windows local Python Bezier pipeline
2. Fly.io Python (`services/recreate-logo/` / `swift-recreate-logo.fly.dev`)
3. On-device Rust FFI
4. This Supabase edge function
