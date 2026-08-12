# Windows QA Report — Swift Document Generator (1 hour)

**Date:** 2026-08-04 (session ~22:54–23:15 local)  
**Tester:** Automated UI exercise (pyautogui / screenshots) + PDF verification  
**Scope:** Windows portable build — no code/config changes

---

## Environment

| Item | Value |
|------|--------|
| **Exe** | `C:\Users\Brice\OneDrive\Documents\swift_document_generator\dist\Swift Document Generator\swift_shipping_label.exe` |
| **Build** | Existing dist (no rebuild). `data\app.so` / exe timestamp ~2026-08-04 22:45; published via `_publish_v1.1.44.log` |
| **Version (in-app)** | **1.1.44+67** (Update sheet: “Installed: 1.1.44+67”) |
| **pubspec** | `mobile\pubspec.yaml` → `1.1.44+67` |
| **OS** | Windows 10/11 Home — `10.0.26200` (report: WindowsVersion 2009 / HAL 10.0.26100.1) |
| **Display** | 2880×1800 physical, **200% DPI** |
| **Data root** | `C:\Users\Brice\OneDrive\Documents\swift_document_generator\` (presets, `customer_logos\`, `filled\`) |
| **Temp QA folder** | `%TEMP%\swift_qa_1h_20260804_225459\` (screenshots/PDFs copies — **deleted after this report**) |
| **Rebuild?** | **No** — used existing dist |

**Note:** Publish log builds from `C:\Users\Brice\AppData\Local\swift-document-generator-mobile`. Current repo `home_screen.dart` includes a Windows `NavigationRail` / `_DesktopToolbar` path; the **running 1.1.44 exe uses the phone-style chrome** (full-width orange header + Shipping / Receiving / Bill of Lading segmented control + bottom **Generate PDF**). Treat desktop-rail source as ahead of / different from this shipped binary.

---

## Executive summary

Core document generation on Windows **works**: Shipping, Receiving, and BOL PDFs were produced from the real UI, saved under `filled\`, and opened/shared. BOL cloud serial **SW-0048** was assigned; BOL PDF had **3 pages** (Store / Driver / Customer). Dual logos (Customer + C/O) and “slots full” disabling Find/Upload behaved as designed. Update sheet opens and shows the correct version; a full “Check for updates” result was only **partially** confirmed (sheet UI verified; post-check status screenshot flaky under automation). Recreate / Manual Crop / Find-on-web / Add-from-storage were **partial** (UI present; end-to-end recreate not cleanly proven in this session). Freight radios were not fully scrolled into view; freight terms still appear on the generated BOL PDF.

---

## Feature results

| # | Feature | Result | Notes |
|---|---------|--------|-------|
| 1 | App launch / window chrome / About·version | **Pass** | Launches; title `swift_shipping_label`; orange header + Update; version **1.1.44+67** in Update sheet |
| 2 | Shipping Label form (fields, calendars, presets, signatures) | **Pass** / Partial | Fields + presets exercised; calendars/signatures not deeply clicked this hour |
| 3 | Receiving Label form | **Pass** | Tab switch, hint text, customer/preset/logos, generate |
| 4 | BOL form (freight radios, serial, copies) | **Pass** / Partial | Copies checkboxes + cloud serial **SW-0048** verified; freight radios UI scroll **partial** (Prepaid/Collect/3rd Party present on PDF) |
| 5 | Generate PDFs (Shipping / Receiving / BOL) | **Pass** | See artifacts below |
| 6 | Customer logos: web / upload / Manual Crop / Auto / Leave as is | **Partial** | Dual logos via preset; Upload/Find UI visible; import-options (Manual Crop / Leave as is) not cleanly completed under automation |
| 7 | Recreate checkbox (Fly vs local Python) | **Partial** | Checkbox + help text visible (“local Python when available; else Fly cloud / Rust”); no definitive recreate completion / backend log this run |
| 8 | Add from storage / delete from storage | **Partial** | Delete (X) / Replace controls visible on logo rows; storage picker not fully completed |
| 9 | Dual logos / C/O | **Pass** | Wolf Midstream + Canadian Plains C/O on Receiving/BOL; special instructions include C/O wording |
| 10 | In-app Update check | **Partial** | Update sheet opens; shows installed **1.1.44+67**, “Check for updates”, “View releases”; full check outcome not reliably captured |
| 11 | Open/share PDF on Windows | **Pass** | Snackbar `Saved (N pages): …\filled\….pdf`; OS viewer launch path exercised (files appeared; viewers closed during test) |
| 12 | Preset save/load | **Pass** / Partial | Load via dropdown (Wolf NGL, Shell Scotford, etc.); Save dialog not fully closed-loop verified |
| 13 | Edge: empty fields / slots full / cancel dialogs | **Pass** / Partial | **Slots full:** Find/Upload disabled with 2 logos; **Cancel:** Escape dismisses “How many labels?”; empty-required not exhaustively validated |

---

## PDF generation evidence

| Doc | File (under `filled\` during test) | Pages | Notes |
|-----|--------------------------------------|-------|-------|
| Shipping | `SL-WolfNGLInc.pdf` (+ `(1)`/`(2)`/`(3)` retries) | **1** | Piece-count dialog → Generate; snackbar confirmed |
| Receiving | `RL-WolfNGLInc.pdf` | **1** | Receiving tab; no piece dialog |
| BOL | `BOL-WolfNGLInc.pdf` | **3** | Store+Driver+Customer; **DOCUMENT NUMBER SW-0048** (cloud counter) |

PDF text extract (BOL): STORE / DRIVER / CUSTOMER copies; freight line includes Prepaid / Collect / 3rd Party; consignee Canadian Plains Energy.

*(These `filled\` QA PDFs were deleted in cleanup; report retained only.)*

---

## Bugs & observations

### Major

1. **Shipped Windows UI ≠ current repo Windows scaffold**  
   - **Severity:** Major (product consistency / UX debt)  
   - **Expected:** Desktop NavigationRail + toolbar (as in current `home_screen.dart` when `Platform.isWindows`).  
   - **Actual:** 1.1.44 portable uses mobile segmented tabs + sticky bottom Generate + orange `_Header`.  
   - **Why it matters:** Wide monitors still use a single tall scroll list; tabs scroll away with content (see Polish #1). Publish source path differs from this repo checkout.

### Minor

2. **Window title is `swift_shipping_label`**  
   - **Severity:** Minor / Polish  
   - **Expected:** User-facing “Swift Document Generator”.  
   - **Actual:** Raw Flutter runner title.

3. **Segmented document tabs live inside the scrollable list**  
   - **Severity:** Minor  
   - **Steps:** Fill long form → scroll down → tabs leave the viewport → hard to switch Shipping/Receiving/BOL without scrolling to top.  
   - **Expected:** Tabs (or rail) stay pinned.  
   - **Actual:** Must scroll to top first (painful with focused multiline fields stealing PageUp/wheel).

4. **Multiline fields trap scroll focus**  
   - **Severity:** Minor  
   - **Steps:** Focus LOCATION (or similar) → mouse wheel / PageUp often scrolls the field, not the form.  
   - **Expected:** Prefer form scroll, or clear affordance to blur.  
   - **Actual:** Easy to get “stuck” mid-form (automation and likely users).

### Polish

5. **Update button contrast** — white on orange is fine; automation struggled with hit-target at 200% DPI (not necessarily a user bug).  
6. **Delete preset** disabled until a preset is selected — correct; no issue.  
7. **Recreate help text** correctly discloses Fly / local Python / Rust — good.

---

## Recreate backend observed

- **UI copy (verbatim sense):** Recreate runs premium tracer; “local Python when available; else Fly cloud / Rust”; ~5–30 s.  
- **This session:** Checkbox UI confirmed; **no successful end-to-end recreate** with new SVG/PNG + backend log captured.  
- **Backend used:** **Unknown / not observed.** Dist ships `tools\logo_vectorizer\` under the portable folder (local Python path available in package). Prefer a follow-up with DevTools/logging or a deliberate recreate while watching `%TEMP%` / app logs.

---

## Screenshots (captured during test, then deleted)

All under `%TEMP%\swift_qa_1h_20260804_225459\` (removed in cleanup):

| Shot | Purpose |
|------|---------|
| `70_calibrated_home.png` / `R2_tab.png` | Home / Receiving tab + dual logos |
| `B2_tab.png` / `B4_done.png` | BOL copies + dual logos |
| `U2_sheet.png` (earlier update pass) | Update sheet + **1.1.44+67** |
| `E2_dialog.png` | “How many labels?” piece-count dialog |
| `final_recv_done.png` / shipping snackbars | Saved PDF paths |
| `RC4_done.png` | Logos / Recreate unchecked after partial recreate attempt |

---

## Recommendations (prioritized — decisions only)

1. **Ship the Windows desktop scaffold** (rail + non-scrolling kind switch + toolbar Generate) in the next Windows release, or document that 1.1.44 intentionally keeps mobile chrome. Align publish source with the repo you care about.  
2. **Pin document-type switching** outside the ListView so tabs never scroll away.  
3. **Rename window title** to “Swift Document Generator”.  
4. **Improve scroll-vs-field focus** (tap outside to blur; or don’t nest aggressive scroll inside multiline fields).  
5. **QA follow-up (15–20 min):** Manual Crop + Leave as is; Recreate with one logo while watching Python vs Fly (portable `tools\logo_vectorizer`); complete Update “Check for updates” once and screenshot up-to-date vs newer; scroll BOL Billing & freight radios explicitly.  
6. **Optional:** Surface installed version in the header or an About row without opening Update.

---

## Test constraints / honesty box

- Exercised via **GUI automation + screenshots + PDF inspection** (Flutter exposes almost no UIA children).  
- **200% DPI** required careful coordinate handling; some clicks missed until blur-header + scroll-to-top.  
- Calendars, signature pad drawing, Manual Crop canvas, Find-on-web network results, and Add-from-storage delete-from-storage dialogs were **not** fully closed-loop.  
- No app source, config, or commit changes were made.

---

## Cleanup

- Deleted QA temp tree `%TEMP%\swift_qa_1h_20260804_225459\` (scripts, screenshots, PDF copies).  
- Deleted QA-generated PDFs created this session under `filled\` (`SL-WolfNGLInc*.pdf`, `RL-WolfNGLInc.pdf`, `BOL-WolfNGLInc.pdf`).  
- **Did not** delete `customer_logos\`, presets, or other project assets.  
- **Kept only this file:** `QA_REPORT_WINDOWS_1H.md`
