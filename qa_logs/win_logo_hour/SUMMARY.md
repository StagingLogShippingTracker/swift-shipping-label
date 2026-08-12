# Windows Find-logo hour QA — SUMMARY

**Start:** 2026-08-05 22:14:43 (local)  
**End:** ~2026-08-05 23:05 (local)  
**Focus:** Receiving Label → **Find logo on the web** (All sources), Windows app GUI  
**Companies (12):** Mastec Purnell, Shell, Flint Energy, Strike Group, 5Blue Process Equipment, ATCO, Arc Resources LTD, CDE Engineering LTD, EPCOR, DNOW, Comco, Apex Valves

## Method
- Drove the **real Windows exe** (`dist\Swift Document Generator\swift_shipping_label.exe`) via Tools → Find logo on web…, type company, **4× Tab + Enter** to activate Search, wait ~55s for **Choose a logo**, screenshot, Esc.
- Companion Dart live test (`logo_finder_win_hour_12_test.dart`) used the same `LogoFinder.findDownloadedCandidates` path for tops dumps.
- Rebuilt Windows mid-session after crawler fixes (Ctrl+Shift+F hotkey + known-domain hardening).

## Rounds
| Round | Notes |
|-------|--------|
| Companion r1 (baseline) | Shell=favicon-only; ATCO=UK lawn-mower; CDE wrong domain; EPCOR/DNOW/Comco poisoned |
| Companion r2 (after fixes) | All 12 return correct primary sources |
| GUI round 3 | Dialog opened but Search never fired (3-tab landed on Cancel) |
| GUI round 4 | **Full success** — Choose-a-logo pickers for all 12 (see `round4/*_04_result.png`) |
| cal2 Shell | Confirmed Shell pecten picker |

## Final quality (GUI round 4 + companion)
| Company | Assessment |
|---------|------------|
| Mastec Purnell | Good — mastec.com site scrape |
| Shell | **Fixed** — Known brand pecten (was apple-touch favicon) |
| Flint Energy | Good — flintcorp.com |
| Strike Group | Good — StrikeGroup-Logo.png |
| 5Blue Process Equipment | Good — 5blue.com |
| ATCO | **Fixed** — atco.com Known brand (was atco.co.uk mowers) |
| Arc Resources LTD | Good — arcresources.com |
| CDE Engineering LTD | **Fixed** — cdeeng.com (was cde.com / wrong favicon) |
| EPCOR | **Fixed** — epcor.com logo first (was epcorfdy junk) |
| DNOW | **Fixed** — dnow.com featured logo first |
| Comco | **Fixed** — Comco Pipe known brand (was UK/misc Comco) |
| Apex Valves | **Fixed** — Apex/Russel Metals apex-logo (was NZ lead-free Apex) |

## Code changes
- `mobile/lib/logo_finder.dart`
  - Known domains + brand URLs for ATCO, Arc, CDE, EPCOR, DNOW, Comco, Apex, Shell
  - `_guessDomains`: known hints return **exclusively** (no TLD spray)
  - Stronger favicon/apple-touch demotion; partner/APEGA demotion
- `mobile/lib/windows_menu_bar.dart` + `home_screen.dart`
  - **Ctrl+Shift+F** → Find logo on web
- `mobile/test/logo_finder_win_hour_12_test.dart` — 12-company live companion

## Artifacts
- `qa_logs/win_logo_hour/round4/` — GUI Choose-a-logo screenshots
- `qa_logs/win_logo_hour/companion_*.json` + `images_*`
- `qa_logs/win_logo_hour/cal2/` — Shell calibration picker

## Remaining nits
- Sister Russel Metals logos still appear as secondary picks for Comco/Apex (Known brand ranks first).
- ATCO known PNG is small (~3KB); Bing alternates still shown as #2/#3.
- Gemini 429 circuit breaker still trips once per process (fail-open).
