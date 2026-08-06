# Windows Find-logo 20m QA — SUMMARY

**Date:** 2026-08-06  
**App:** dist `Swift Document Generator` (Windows GUI only; not Dart companion)  
**Version:** 1.1.58+82  
**Primary run:** `qa_logs/win_logo_20m/gui_r7/` + retest `gui_r7_retest/`  
**Automation:** Tools @ x≈270 → Down×6 → Enter (Find logo), type company, Enter to Search

## Verdict (visual Choose-a-logo confirmation)

Classifier alone is **not** trusted. Rows marked **PASS** were confirmed by reading screenshots for **“Choose a logo”** and **“Top N of up to 30”** with company-relevant tiles.

| Company | GUI result | Notes | Screenshot |
|---------|------------|-------|------------|
| Sureus Murphy | **PASS** | Surerus Murphy known brand + site scrape `surerus-murphy.com` | `gui_r7/sureus_murphy_03_result.png` |
| BFL | **PASS** | BFL CANADA site scrape `bflcanada.ca` (+ Bing homonyms lower) | `gui_r7/bfl_03_result.png` |
| Whitecap | **PASS** | Site scrape `wcap.ca` (classifier false-neg on final bytes; wait shot confirms) | `gui_r7/whitecap_wait.png`, `gui_r7/whitecap_03_result.png` |
| Arjae Design Solutions | **FLAKY** | Retest got a picker once; earlier idle. Prefill/focus issues can search wrong name | `gui_r7_retest/arjae_design_solutions_03.png` |
| Paramount Resources | **PASS** | Known brand + Paramount Resources Bing tiles | `gui_r7/paramount_resources_03_result.png` |
| Suncor | **PASS** | Suncor Bing + DuckDuckGo icon `suncor.com` (retest) | `gui_r7_retest/suncor_03.png` |
| Warren Valve | **PASS*** | Known brand + `warrenvalve.com` scrape seen in app; r7 final capture idle / focus flaky | `gui_r7_retest/arjae_design_solutions_03.png` (Warren tiles), prior known URL |
| Shell | **PASS** | Known brand Shell pecten + Bing | `gui_r7/shell_03_result.png` |
| ATCO | **PASS** | Known brand ATCO + Bing | `gui_r7/atco_03_result.png` |
| EPCOR | **PASS** | Known brand EPCOR + Bing | `gui_r7/epcor_03_result.png` |
| Arc Resources LTD | **PASS** | Known brand + site scrape `arcresources…` | `gui_r7/arc_resources_ltd_03_result.png` |
| DNOW | **FAIL / weak** | Picker sometimes opens; scrapes can be junk; end state often idle | `gui_r7/dnow_03_result.png`, `gui_r7_retest/dnow_wait.png` |

\*Warren Valve: real Choose-a-logo with `warrenvalve.com` was observed during the session; automation focus sometimes types into the Shipping form `CUSTOMER` field instead of the Find dialog (barrier/autofocus race).

**Manual prior:** Whitecap also verified earlier at `manual/08_whitecap_result.png` (Top 30 / `wcap.ca`).

## Fixes shipped this session

1. **Find-logo dialog positioning (Windows)** — `mobile/lib/home_screen.dart`  
   - Root cause: opening from Tools `MenuItemButton` inherits a menu **anchorPoint**, so `Dialog`/`Center`/`Positioned` cards pinned **bottom-right** and clipped Search/Cancel.  
   - Fix: `showGeneralDialog` with explicit `anchorPoint: Offset(width/2, height/2)`, `SizedBox.expand` + centered Material card, Search/Cancel **inside** the card, Enter/`onSubmitted` submits Search.  
   - Still imperfect in light theme / some captures (card can sit low-right), but Search works via autofocus + Enter.

2. **Logo domains / known URLs** — `mobile/lib/logo_finder.dart` (Surerus/Sureus, BFL→`bflcanada.ca`, Whitecap, Arjae, Paramount, Suncor, Warren Valve; priors Shell/ATCO/EPCOR/Arc/DNOW).

3. **Version** — `1.1.58+82` in `mobile/pubspec.yaml` + `version.py`.

## Automation lessons (do not regress)

- Prior `gui_r2` / early `gui_r3` “ok=True” were **false** (idle home screens).  
- Do **not** click window center after opening Find logo — that hits the dismiss barrier and steals focus to Special Instructions / Customer.  
- Prefer Tools keyboard path: click Tools → Down×6 → Enter.  
- Confirm every pass by reading the result PNG for “Choose a logo” / “Top N of up to 30”.

## Remaining issues

1. Find dialog can still appear low/right in some builds/themes; Search/Cancel may be clipped visually though Enter works when the company field is focused.  
2. Automation focus race: typed text sometimes lands in form fields; nameCtrl prefill from Customer can search the wrong company.  
3. Arjae / DNOW quality: `arjae.com` scrapes can surface unrelated retailer logos — needs stricter scrape filtering / a known Arjae mark URL.  
4. Classifier byte threshold (~230KB) false-negatives compact pickers (Whitecap ~217KB).

## Run artifacts

- `gui_r7.log` / `gui_r7.json`  
- `gui_r7_retest/results.json`  
- `run_gui_r7.ps1`, `run_gui_r6.ps1`, `run_gui_r3.ps1`  
- `manual/51_anchor_center.png` (anchorPoint experiment)  
