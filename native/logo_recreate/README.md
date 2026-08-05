# logo_recreate (on-device Rust)

On-device port of the Windows Python Recreate pipeline
(`tools/logo_vectorizer/customer_recreate.py` + `manual_trace.py` +
`sectional.py`) for Android (and optionally Windows without Python).

**Fly.io Python cloud Recreate is aborted** — do not deploy
`services/recreate-logo/` for production. That folder is unused scaffolding.
Cloud fallback is the existing Supabase Deno/`vtracer` edge function only.

## Architecture choice

| Option | Verdict |
|--------|---------|
| **`dart:ffi` + Rust `cdylib`** | **Chosen.** One C ABI (`logo_recreate_png` / `logo_recreate_free`), no FRB codegen, clear Android `jniLibs` + Windows DLL story. |
| `flutter_rust_bridge` | Fine later if the API grows; overkill for a single recreate entrypoint. |
| WASM-in-Dart first | Attractive for one artifact, weaker Flutter mobile story vs native `.so`; keep as optional second target from the same crate (`crate-type` already includes `cdylib`). |

### Call priority (Flutter)

1. **Windows:** local Python Bezier pipeline (unchanged, highest fidelity)
2. **All platforms:** on-device Rust (`LogoRecreateNative`) when the dynamic library is present
3. **Fallback:** Supabase `recreate-logo` edge function (vtracer) — not Fly

## MVP scope (this crate today)

Working stages:

1. Background strip (corner flood, conservative)
2. Palette k-means + near-duplicate merge
3. Sectional SVG via **contour polylines** (not Schneider Bezier)
4. Posterized transparent PNG from palette masks

`backend` field in JSON: `native_rust_mvp`.

## Build

```bash
cd native/logo_recreate
cargo test
cargo build --release
# Windows: target/release/logo_recreate.dll
```

### Android (next)

```bash
# After installing Android NDK + cargo-ndk:
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -o ../../mobile/android/app/src/main/jniLibs build --release
```

Ship `liblogo_recreate.so` under `mobile/android/app/src/main/jniLibs/<abi>/`.
Dart loads `logo_recreate` via `DynamicLibrary.open`.

### Windows optional

Copy `logo_recreate.dll` next to the Flutter runner (or under a known
`native/` path). Dart already probes common locations; Python remains primary.

## C ABI

```c
char *logo_recreate_png(const uint8_t *data, size_t len,
                        int32_t max_colors, int32_t render_width);
void logo_recreate_free(char *ptr);
```

Success JSON mirrors cloud: `svg`, `png_base64`, `palette_hex`,
`section_count`, `bg_stripped`, `source_width`, `source_height`,
`render_width`, plus `backend` / `notes`. Errors: `{ "error": "..." }`.

## Bezier parity roadmap (multi-sprint)

| Sprint | Work |
|--------|------|
| **Done (scaffold)** | Crate + FFI + Dart hooks; MVP polyline + palette PNG; Fly URL reverted to Supabase fallback |
| **1** | Ship Android `.so` via CI/`cargo-ndk`; wire jniLibs into release APK |
| **2** | Replace polylines with `vtracer` per color section (closer to Deno cloud quality, still not designer Bezier) |
| **3** | Port `manual_trace.py` Schneider least-squares + corner/inflection anchors into Rust |
| **4** | Port recreate tuning from `analyze.py` / `_tune_analysis_for_recreate`; morphology cleanup parity with OpenCV |
| **5** | Optional: Windows prefer Rust when Python missing; drop network dependency when native passes QA |

Full Bezier parity with Python is **not** a one-session port (~700+ lines in
`manual_trace.py` alone, plus analyze/sectional tuning).

## Related paths

- Python source of truth: `tools/logo_vectorizer/`
- Flutter: `mobile/lib/logo_recreate.dart`, `logo_recreate_native.dart`, `logo_recreate_cloud.dart`
- Unused Fly scaffold: `services/recreate-logo/`
- Cloud fallback: `supabase/functions/recreate-logo/`
