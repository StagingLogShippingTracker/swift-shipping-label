# Supabase (project `gdrpdiwykmnybmkadlrv`)

Shared backend for Swift Document Generator:

- **`next_bol_serial`** — shared BOL document numbers (SECURITY DEFINER RPC)
- **`customer_presets`** / **`customer_logos`** — presets and logo metadata synced across Windows/Android
- **`signatures`** — saved BOL shipper signatures (PNG metadata; bytes in Storage)
- **Storage bucket `customer-logos`** — customer logo image bytes
- **Storage bucket `signatures`** — shipper signature PNGs (max 2 MB, `image/png` only)

## Security posture

Same as BOL serial: the mobile app ships the **anon (publishable) key**. These tables use RLS policies that allow `anon` read/write because this is a single-company internal tool, not multi-tenant user auth. Anyone with the app can read/write shared presets and signatures (equivalent to editing a shared spreadsheet). Do not store secrets in presets.

### `signatures` table

| Column | Type | Notes |
|--------|------|-------|
| `id` | text PK | Client-generated id (used as storage filename stem) |
| `name` | text | Display name ("My signature", shipper cert name, etc.) |
| `storage_path` | text unique | e.g. `{id}.png` in bucket `signatures` |
| `updated_at` | timestamptz | Touch trigger on update |

App flow: draw signature → optional cloud save → pick from list on later BOLs → embed PNG on shipper certification signature line in flat PDF.

Migrations live in `supabase/migrations/`.
