# Android QA Report — Swift Document Generator (~1 hour)

**Date:** 2026-08-05 (session ~02:07–02:36 local, ~50+ minutes wall including emulator boot, APK build, and extended passes)  
**Tester:** Automated UI exercise (adb / uiautomator / screenshots) + real PDF generation & text extract + Recreate closed-loop  
**Scope:** Thorough feature pass on Android emulator — **no code changes** during testing  
**Decision:** **Ship / continue** for v1.1.48+71 mobile — core SL/RL/BOL + share flows pass; fix Update messaging (same as Windows) and a few polish items before calling the Android experience fully premium-stable

---

## Environment

| Item | Value |
|------|--------|
| **AVD** | `Pixel_API_34` (`sdk_gphone64_x86_64`) |
| **Android / API** | Android 14 / API **34** |
| **Display** | 1080×2400 @ 420 dpi |
| **APK** | Fresh **debug** build from working tree / `main` — `mobile/build/app/outputs/flutter-apk/app-debug.apk` |
| **Version** | **1.1.48+71** (`versionName=1.1.48`, `versionCode=71`) |
| **Package** | `com.swiftoilfield.swift_shipping_label` |
| **Flutter SDK** | Repo `.tools\flutter\bin\flutter.bat` |
| **GitHub latest release (at test)** | **v1.1.47** (local debug **ahead** of published) |
| **Temp QA folder** | `%TEMP%\swift_qa_android_1h_20260805_020701\` (screenshots / PDF copies / notes — **deleted after this report**) |
| **Rebuild during QA?** | Yes — intentional debug APK build at session start only |

---

## Executive summary

Android **1.1.48+71** is a polished touch-first warehouse app: orange brand header, pinned Shipping / Receiving / BOL segmented control, sticky bottom **Generate PDF**, carded presets/logos/forms. Real PDFs were generated for all three document types, verified on-device under `app_flutter/swift_document_generator/filled\`, and text-extracted (SL 1p, RL 1p, BOL 3p with **SW-0051**).

Compared with Windows 1H premium QA: mobile correctly uses phone chrome (not a desktop MenuBar clone). Same Update-copy bug as Windows when local > GitHub latest. No app FATAL crashes; early System UI ANR on cold emulator was environmental.

**Verdict:** Core mobile workflows are decision-ready. Address Update messaging; polish Find-logo field prefill and optional mobile dark-mode affordance.

---

## Feature results

| # | Feature | Result | Notes |
|---|---------|--------|-------|
| 1 | Launch, splash/branding, header chrome | **Pass** | Orange header + white Swift Supply mark + “Document Generator”; Update chip; no layout overflow on launch |
| 2 | Shipping / Receiving / BOL switching | **Pass** | Pinned segmented control; BOL freight Prepaid/Collect/Third Party toggled; copy checkboxes present; 8-round tab stress OK |
| 3 | Generate PDFs (real files) | **Pass** | See evidence table. Piece-count dialog on Shipping; native share sheet (“Sharing 1 file”) for SL/RL/BOL |
| 4 | Logos: pick/upload/storage/dual C/O | **Pass** | Upload → Add from Storage / Browse; Find on web opens; dual CUSTOMER + C/O slots observed |
| 5 | Presets load/save | **Pass** (load) | Preset dropdown + Save control present; load exercised in harness. Save not fully closed-loop this session |
| 6 | Generate PDF / bottom bar / progress | **Pass** | Sticky bottom bar with progress affordance while busy; Generating… path observed during PDF build |
| 7 | Update check | **Pass** / note | Sheet: checks GitHub for newer **APK**. See bug: local 1.1.48+71 vs latest v1.1.47 |
| 8 | Settings / customize | **Partial** | Load sample / Clear shipment / Clear all present. **No** mobile dark-mode control in header (Windows toolbar has it). No Windows-style Customize sheet on phone chrome |
| 9 | Scroll vs multiline (touch) | **Partial** | Form scrolls; keyboardDismiss on drag. SPECIAL INSTRUCTIONS not reliably found via a11y in automation; touch scroll of long BOL forms worked in practice |
| 10 | Orientation / keyboard | **Pass** | Landscape usable (header + tabs + Generate remain). Soft keyboard; Generate bar stays pinned |
| 11 | Premium feel vs Windows | **Pass** with nits | See assessment below |
| 12 | Stability | **Pass** | No app FATAL; logcat “AndroidRuntime” hits were uiautomator process lifecycle only |

---

## PDF generation evidence

| Doc | On-device path (during test) | Pages | Notes |
|-----|------------------------------|-------|-------|
| Shipping | `…/filled/SL-PACIFICCANBRIAMSO88421.pdf` (~75 KB) | **1** | Piece-count → Generate; share sheet; sample Pacific Canbriam / SO-88421 |
| Receiving | `…/filled/RL-CONOCOPHILLIPSCANADABRCPARTNERSHIP1380380.pdf` (~75 KB) | **1** | ConocoPhillips receiving sample; special instructions present in extract |
| BOL | `…/filled/BOL-PACIFICCANBRIAMSO88421.pdf` (~168 KB) | **3** | **DOCUMENT NUMBER SW-0051**; STORE COPY; Prepaid/Collect/3rd Party; line items + totals |

Share sheet confirmed filename `BOL-PACIFICCANBRIAMSO88421.pdf` (and SL/RL counterparts). QA copies under temp were deleted in cleanup along with any test PDFs under app `filled\` for this session.

---

## Bugs & observations

### Major

*None blocking core generate/share workflows on this build.*

### Minor

1. **Update check messaging when local build > GitHub latest**  
   - **Severity:** Minor (trust / support confusion) — **same class as Windows QA**  
   - **Observed:** Installed **1.1.48+71**, Latest **v1.1.47**, status (emphasized/red): *“You are up to date (1.1.48+71). Latest is v1.1.47.”*  
   - **Expected:** Clear “ahead of published release” / “newer than latest APK” wording  
   - **Android path:** Sheet correctly states checks GitHub Releases for a newer **APK** (not Setup.exe)

2. **Find logo “CUSTOMER / COMPANY” prefill concatenates without separator**  
   - **Severity:** Minor  
   - **Observed:** With customer field `PACIFIC CANBRIAM`, typing a search appended as `PACIFIC CANBRIAMFastenal` / `PACIFIC CANBRIAMEPCOR`  
   - **Expected:** Replace selection, clear on focus, or insert a space/separator

3. **Mobile lacks in-header theme toggle**  
   - **Severity:** Polish  
   - **Observed:** Android `_Header` exposes Update only; Windows `_DesktopToolbar` has dark/light toggle  
   - **Expected (premium):** Optional theme control on mobile, or document that Android follows system theme only

### Polish / product notes

4. **Logo restore on Android** is Gemini (same as Windows), not a cloud ESRGAN host.  
5. Cloud ESRGAN restore is no longer part of the app.  
6. **Prepare for Recreate** is easy to miss in automation/support docs — operators must tap **Recreate & import** after crop choice.  
7. **Sticky Generate** + pinned tabs are the right mobile IA (better touch primary action than Windows’ workspace-only Generate).  
8. Cold emulator briefly showed System UI ANR before first stable launch — environmental, not app-repro after warm start.  
9. Preset **Save** not fully closed-loop; dual C/O visually supported after imports.

---

## Premium-feel assessment (Android vs Windows)

| Dimension | Android (1–5) | Windows (from Win report) | Notes |
|-----------|---------------|---------------------------|-------|
| Chrome & IA | **4.5** | 4.5 | Phone: sticky Generate + pinned tabs. Desktop: MenuBar + rail. Both feel intentional for their platform |
| Visual polish | **4.5** | 4 | Brand header, Oswald, orange CTAs, soft cards — strong warehouse brand on phone |
| Density & layout | **4** | 4 | Single-column cards; landscape remains usable |
| Primary action clarity | **5** | 4.5 | Full-width bottom Generate is clearer on touch than desktop workspace placement |
| Trust / update UX | **3** | 3 | Same “up to date vs older latest” copy; APK wording is otherwise clear |
| Motion / micro-interactions | **3.5** | 3.5 | Sheets/dialogs solid; Recreate crop sheet is a nice premium beat |
| Feature parity | **4** | 4.5 | Logo restore is Gemini on Android. Missing: desktop Customize / dark toggle / MenuBar tools |

**Overall premium feel:** **Strong pass for Android touch-first.** Does **not** feel like a stretched desktop clone. Remaining gaps are messaging and small polish, not “prototype.”

---

## Prioritized recommendations

1. **P0 / quick:** Fix Update result copy for `installed > latest` on **both** Android (APK) and Windows (Setup.exe); quiet attention styling when no newer package exists.  
2. **P1:** Fix Find-logo field prefill concatenation (clear/replace/select-all on open).  
3. **P1:** Optional mobile dark-mode control (or explicit “follows system” copy) for parity with Windows polish.  
4. **P2:** Short in-app hint on first Recreate that crop confirmation (**Recreate & import**) is required.  
5. **P2:** Next pass — exercise **Save preset** + Browse-from-Downloads + second C/O logo visual on a generated PDF page.  
6. **Process:** Prefer publishing GitHub `v1.1.48` before QA that judges Update UX against “latest.”

---

## Comparison vs Windows 1H premium QA

| Item | Windows 1.1.47→1.1.48 | This Android session (1.1.48+71) |
|------|------------------------|----------------------------------|
| Core SL / RL / BOL PDFs | Pass | **Pass** (BOL SW-0051, 3 pages) |
| Update “up to date” vs older latest | Bug noted | **Same bug** (APK copy) |
| Recreate | Tooling ready; E2E partial | Historical; restore is now Gemini |
| Chrome | MenuBar + NavigationRail | Orange header + segmented tabs + sticky Generate |
| Multiline scroll | Wheel trapping noted | Touch scroll OK; a11y label hunt partial |
| Dark mode | Verified + persists | Not exposed in mobile header |

---

## Artifacts & cleanup

- Temp screenshots, UI dumps, PDF copies, and harness scripts under `%TEMP%\swift_qa_android_1h_20260805_020701\` were **deleted** after writing this report.  
- Session-generated PDFs in the emulator app `filled\` used for this QA were **removed** where practical; project `customer_logos\` / brand assets **not** deleted.  
- **Kept:** this report only — `QA_REPORT_ANDROID_1H_PREMIUM.md`.  
- **No app source modifications** during testing.

---

*End of Android 1H premium QA report.*
