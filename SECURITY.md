# Security posture — Swift Document Generator

## Shared org tool (intentional)

Supabase tables and storage buckets used by this app (presets, logos, signatures,
delivery addresses, generated documents / History) are readable and writable with
the **anon** (publishable) key. There is no end-user auth.

This matches a closed Swift Oilfield Supply internal tool: anyone with the
bundled project URL + anon key can read/write shared data.

### Do not

- Publish the anon key or project URL outside the company
- Treat History / presets as multi-tenant or customer-isolated
- Open RLS further without a real auth model

### If the key leaks

Rotate the anon key in Supabase, ship a new app build with the new key, and
review `generated_documents` / storage for unexpected objects.

## Android signing

Release APKs use the **debug** keystore when `mobile/android/key.properties` is
absent so existing in-app Update installs keep working. For Play Store or
enterprise trust, add a release keystore via `key.properties.example`.

## Logo restore

Real-ESRGAN runs locally on Windows (Python). Gemini (when configured) may send
logo rasters to Google’s API — only for optional assist; redraws are rejected.
