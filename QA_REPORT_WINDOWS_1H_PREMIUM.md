# Windows QA Report — Swift Document Generator (~1 hour)

**Date:** 2026-08-05 (session ~01:50–02:04 local, ~74 minutes wall including retries)  
**Tester:** Automated UI exercise (pywinauto / pyautogui / screenshots) + real PDF generation & text extract  
**Scope:** Thorough feature pass on Windows portable build — **no code changes** during testing  
**Decision:** **Ship / continue** for v1.1.47+ desktop chrome — core flows pass; fix update messaging & a few polish items before calling the Windows experience fully premium-stable

---

## Environment

| Item | Value |
|------|--------|
| **Preferred exe** | `C:\Users\Brice\OneDrive\Documents\swift_document_generator\dist\Swift Document Generator\swift_shipping_label.exe` |
| **Session start version** | **1.1.47+70** (FileVersion / ProductVersion at launch; About confirmed) |
| **Session end version** | **1.1.48+71** (exe rewritten mid-session ~02:01; Update sheet + FileVersion) |
| **OS** | Windows 11 Home — `10.0.26200` |
| **Display** | Primary ~1440×900 logical (WinForms); app window rect ~2880×1800 client (DPI-scaled) |
| **Data root** | `C:\Users\Brice\OneDrive\Documents\swift_document_generator\` (`presets`, `customer_logos\`, `filled\`) |
| **Temp QA folder** | `%TEMP%\swift_qa_win_1h_20260805_015017\` (screenshots / PDF copies / notes — **deleted after this report**) |
| **Rebuild during QA?** | **No intentional rebuild** by tester; dist binary timestamp advanced to 1.1.48+71 during the session (likely parallel publish / overwrite) |

---

## Executive summary

Windows **1.1.47+** delivers the intended desktop shell: **MenuBar** (File/Edit/View/Document/Tools/Options/Help), **NavigationRail** (Shipping / Receiving / BOL), **Workspace** pane with a single primary **Generate PDF**, dark/light toggle with **persistence**, Customize / Update / Feedback / F2 forms, and Window snap. Real PDFs were generated for all three document types and verified on disk.

Compared with the prior 1.1.44 Windows QA (phone-style chrome), this build is a clear product step up. Remaining issues are mostly polish / messaging (update “up to date” when local > GitHub latest; Update attention badge), incomplete end-to-end Recreate under automation, and multiline scroll focus trapping (still present, mitigated by pinned rail/tabs).

**Verdict:** Core warehouse workflows are decision-ready on Windows. Address update-version copy before relying on Update UX; Recreate is “ready” (local Python + Fly healthy) but not fully proven in this session.

---

## Feature results

| # | Feature | Result | Notes |
|---|---------|--------|-------|
| 1 | Launch, window title, dark/light + persistence | **Pass** | Title `Swift Document Generator` (fixed vs old runner name). Dark via toolbar / Ctrl+Shift+D; **persists across restart**. |
| 2 | MenuBar key actions | **Pass** | All 7 menus present. Exercised: File→Updates, Edit→Load sample, View→Customize / Window snap, Document nav, Tools→Vectorizer status, Options→Hotkeys, Help→About / Feedback / F2. |
| 3 | Shipping / Receiving / BOL via NavigationRail | **Pass** | Click + Ctrl+1/2/3. Forms load; BOL shows freight Prepaid/Collect/Third Party + copy checkboxes. |
| 4 | Generate PDFs (real files) | **Pass** | See evidence table below. Snackbars confirmed paths under `filled\`. |
| 5 | Logos: upload / storage / dual C/O / Recreate | **Pass** / Partial | Dual **CUSTOMER + C/O** verified with Shell + Scotford logos. Upload manually opens file dialog (cancelled). Add-from-storage menu path exercised. Recreate UI + **Vectorizer status ready** (local Python + Fly online + native); checkbox toggle / full recreate pipeline **not** closed-loop proven. |
| 6 | Presets load/save | **Pass** (load) | Loaded **Shell Canada - Scotford**; fields + both logo slots populated. Save not fully closed-loop this hour. |
| 7 | Workspace Generate (no duplicate top Generate) | **Pass** | Single `Generate PDF` **Button** in Workspace (bottom-right). No sticky top/header Generate. Form actions are Load sample / Clear only. |
| 8 | Update dialog + Setup.exe messaging | **Pass** / note | Sheet opens; copy mentions **Setup.exe** / installer. Check ran. See bug: local **1.1.48+71** vs latest GitHub **v1.1.47** messaging. |
| 9 | Customize appearance & PDF | **Pass** | Dialog **Customize view & PDF** with Appearance / Layout / PDF output tabs; theme Light/Dark, UI scale, Dense forms; Cancel / Reset / Apply. |
| 10 | Help → Feedback & F2 error capture | **Pass** | Both open; mail target `warehouse2@swiftsupply.ca`. Opened only (no send). |
| 11 | Window snap | **Pass** | View → Window snap submenu; snap preset applied. |
| 12 | Scroll vs multiline | **Pass** (behavior noted) | `SPECIAL INSTRUCTIONS` takes focus (accent border). Wheel while focused prefers field; Tab/blur then wheel moves form. Rail remains available (better than 1.1.44 tab-in-scroll). |
| 13 | Premium feel | **Pass** with nits | See assessment below. |

---

## PDF generation evidence

| Doc | File (under `filled\` during test) | Pages | Notes |
|-----|--------------------------------------|-------|-------|
| Shipping | `SL-PACIFICCANBRIAMSO88421.pdf` | **1** | Piece-count dialog → Generate; snackbar `Saved (1 pages): …` |
| Receiving | `RL-CONOCOPHILLIPSCANADABRCPARTNERSHIP1380380.pdf` | **1** | Receiving sample data; snackbar `Saved: …` |
| BOL | `BOL-PACIFICCANBRIAMSO88421.pdf` | **3** | Store/Driver/Customer; **DOCUMENT NUMBER SW-0050**; freight Prepaid/Collect/3rd Party present in text extract |

QA copies lived under `%TEMP%\swift_qa_win_1h_20260805_015017\pdfs\` and were deleted in cleanup along with the test-created `filled\` PDFs above. Project `customer_logos\` / assets untouched.

---

## Bugs & observations

### Major

*None blocking core generate/print workflows on this build.*

### Minor

1. **Update check messaging when local build > GitHub latest**  
   - **Severity:** Minor (trust / support confusion)  
   - **Observed:** Installed **1.1.48+71**, Latest tag **v1.1.47**, status text: *“You are up to date (1.1.48+71). Latest is v1.1.47.”*  
   - **Expected:** Clear “ahead of published release” / “newer than latest Setup.exe” wording; avoid “up to date” + “latest is older” in the same breath.  
   - **Setup.exe path:** Sheet correctly states checks GitHub Releases for a newer Setup.exe and launches the installer.

2. **Update toolbar badge / emphasis while already current (or ahead)**  
   - **Severity:** Minor / Polish  
   - **Observed:** Update control often shows attention styling (exclamation) even after a successful “up to date / ahead” check.  
   - **Expected:** Quiet state when no newer installer is available.

3. **Multiline fields still capture wheel scroll**  
   - **Severity:** Minor  
   - **Steps:** Focus SPECIAL INSTRUCTIONS → mouse wheel scrolls the field, not the page.  
   - **Mitigation in this build:** NavigationRail + Workspace stay pinned (unlike 1.1.44 segmented tabs inside the scroll view).

4. **Dialog dismiss vs window close under automation / mis-click**  
   - **Severity:** Minor (observed twice in automation)  
   - **Notes:** App process exited when dismissing Update / native file dialogs if the wrong Close / Alt+F4 hit the shell. Worth hardening dialog focus / Escape handling for warehouse users.

### Polish / product notes

5. **Window title** is now user-facing **Swift Document Generator** — fixed from prior `swift_shipping_label` regression.  
6. **Vectorizer status** reports healthy stack: local `py`, tools under dist `\tools\logo_vectorizer`, Fly `swift-recreate-logo.fly.dev` online, native=true.  
7. **Dist version churn mid-QA** (1.1.47+70 → 1.1.48+71) — report treats UI behavior as continuous; version strings cited per observation time.  
8. **Recreate checkbox** visible with clear premium-tracer copy; automation did not reliably toggle/check it this run.  
9. **Preset Save** not fully exercised (load confirmed).

---

## Premium-feel assessment

| Dimension | Score (1–5) | Notes |
|-----------|-------------|-------|
| Chrome & IA | **4.5** | Real MenuBar + NavigationRail + Workspace reads like a desktop app, not a phone shell stretched wide. |
| Visual polish | **4** | Soft cards, orange CTAs, brand header, dark mode that looks intentional. |
| Density & layout | **4** | Two-column forms + workspace; Customize layout presets exist. Not cramped; not sparse. |
| Primary action clarity | **4.5** | One obvious Generate PDF in Workspace; no duplicate top Generate. |
| Trust / update UX | **3** | Setup.exe story is clear; version “up to date vs latest” copy undermines polish. |
| Motion / micro-interactions | **3.5** | Dialogs/sheets feel solid; snap is a nice touch; badge noise on Update hurts. |

**Overall premium feel:** **Strong pass for Windows desktop.** This is the first shipped Windows build in this QA series that matches the intended MenuBar/rail architecture. Remaining gaps are messaging and a few interaction nits, not “feels like a prototype.”

---

## Prioritized recommendations

1. **P0 / quick:** Fix Update result copy for `installed > latest` (and clear Update badge when no newer Setup.exe).  
2. **P1:** Soften multiline wheel capture (or blur-on-wheel-outside) so long BOL forms scroll predictably.  
3. **P1:** One manual Recreate smoke on a real logo (local Python path) before calling logo QA complete — tooling status already green.  
4. **P2:** Ensure dialog Escape / Close never maps to app exit; keep native file pickers modal to the app.  
5. **P2:** Optional: exercise **Save preset** + PDF-output folder change in the next short Windows pass.  
6. **Process:** Avoid overwriting `dist\` while a QA session is running (version jumped mid-test).

---

## Comparison vs prior Windows 1H QA (1.1.44)

| Item | 1.1.44 report | This session (1.1.47→1.1.48) |
|------|---------------|------------------------------|
| Desktop MenuBar / rail | Missing (phone chrome) | **Present** |
| Window title | `swift_shipping_label` | **Swift Document Generator** |
| Generate placement | Bottom sticky on phone layout | **Workspace only** (no duplicate top) |
| Dark mode persistence | Not emphasized | **Verified across restart** |
| PDF SL / RL / BOL | Pass | **Pass** (BOL SW-0050, 3 pages) |

---

## Artifacts & cleanup

- Temp screenshots, UI dumps, PDF copies, and helper scripts under `%TEMP%\swift_qa_win_1h_20260805_015017\` were **deleted** after writing this report.  
- Test-generated PDFs in `filled\` listed above were **deleted**.  
- **Kept:** this report only — `QA_REPORT_WINDOWS_1H_PREMIUM.md`.  
- **Not deleted:** `customer_logos\`, brand assets, unrelated older `filled\` PDFs from prior days.

---

*End of report.*
