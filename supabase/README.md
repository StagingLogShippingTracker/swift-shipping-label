# Supabase (project `gdrpdiwykmnybmkadlrv`)

Shared backend for Swift Document Generator:

- **`next_bol_serial`** — shared BOL document numbers (SECURITY DEFINER RPC)
- **`customer_presets`** / **`customer_logos`** — presets and logo metadata synced across Windows/Android
- **Storage bucket `customer-logos`** — customer logo image bytes

## Security posture

Same as BOL serial: the mobile app ships the **anon (publishable) key**. These tables use RLS policies that allow `anon` read/write because this is a single-company internal tool, not multi-tenant user auth. Anyone with the app can read/write shared presets (equivalent to editing a shared spreadsheet). Do not store secrets in presets.

Migrations live in `supabase/migrations/`.
