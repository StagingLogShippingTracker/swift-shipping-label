# Windows Desktop UX

Platform-branched UI so **Windows** feels like a native productivity app while **Android** keeps the existing mobile layout.

## What changed

### Shell (v1.1.44+)
- **NavigationRail** for Shipping / Receiving / BOL (labels extend on wide windows).
- **Compact toolbar** (surface, not full orange mobile header): brand mark, app name, current document type, **Update** + **Generate PDF**.
- **Split layout** (≥1180px): scrollable form left, fixed **Workspace** pane right (presets, logos/Recreate, BOL copies, sticky Generate).
- Narrower Windows widths keep Generate in the toolbar and fold Workspace cards into the main scroll.

### QA follow-ups (v1.1.45)
- Win32 + VERSIONINFO product name **Swift Document Generator**.
- Multiline fields prefer **form scroll** (wheel / PageUp / PageDown) when content does not overflow.
- Android document-type selector **pinned** above the scrollable form.
- Freight charges always selected (defaults to Prepaid); 3rd-party billing saved in BOL presets.
- Add-from-storage attaches existing files (no duplicate) unless Recreate is on.
- Recreate success/failure **SnackBars**; **No crop** skips background removal.
- Update check: 20s timeout, clearer rate-limit errors; **dialog** on Windows.

### Forms & chrome
- **Two-column** single-line fields on Windows; multiline fields stay full width.
- Denser card padding, compact `VisualDensity`, tighter inputs (see `theme.dart`).
- Scrollbar on the main form pane; “Add line” is an outlined button (not a mobile tonal FAB icon).
- Win32 window title **Swift Document Generator**, default size **1440×900**.

### Unchanged / isolated
- Android path still uses orange `_Header`, segmented control, single-column cards, and full-width bottom Generate bar (`Platform.isWindows` branch only).
- Logo restore is Gemini (Windows and Android), with local rebuild if Gemini is down.
- All document generation, presets, logos, signatures, and update flows share the same state methods.

## Files
- `mobile/lib/home_screen.dart` — dual scaffolds + shared section builders
- `mobile/lib/form_scroll_text_field.dart` — desktop scroll forwarding
- `mobile/lib/theme.dart` — Windows density / rail / card tokens
- `mobile/windows/runner/main.cpp` / `Runner.rc` — title + product name

## Next polish backlog
1. Live PDF / label preview pane (replace or complement Workspace).
2. Menu bar or command palette (File → Generate, presets, Clear).
3. Keyboard shortcuts (Ctrl+Enter Generate, Ctrl+S Save preset).
4. Persist window size/position; optional maximized-first launch.
5. Fluent-style dialogs for piece counts / logo pick (less mobile `AlertDialog`).
6. Optional `NavigationRail` collapse preference in settings.
7. High-DPI polish on logo thumbnails in the Workspace pane.
