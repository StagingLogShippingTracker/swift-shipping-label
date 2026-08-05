# Swift Document Generator — Design System

Industrial shipping / receiving / BOL software for **Swift Oilfield Supply**.  
Goal: feel like top-tier logistics tooling — clear hierarchy, quiet chrome, brand orange as the only loud accent.

---

## Brand anchors (do not invent a new identity)

| Token | Value | Role |
|-------|-------|------|
| **Accent** | `#CE4E30` | Primary CTA, focus rings, selected rail, PDF brand stripe |
| **Accent soft** | `#F8EBE7` (light) / `#3A221C` (dark) | Selected segments, soft chips |
| **Ink** | `#1A1A1A` / `#F2F0EC` | Body & titles |
| **Muted** | `#6B6B6B` / `#A3A29C` | Hints, secondary labels |
| **Border** | `#E6E2DC` / `#2E333A` | Hairline structure |
| **Surface** | `#FFFFFF` / `#1C1F24` | Cards, dialogs, inputs |
| **Background** | `#F4F2EF` / `#121417` | App canvas |
| **Panel** | `#F7F5F2` / `#16191E` | Windows rail / side chrome |

Logos (refine in place, don’t replace):

- `swift_supply_logo_orange.png` — desktop toolbar / dark surfaces  
- `swift_supply_header_white.png` — Android orange header  
- PDF brand mark stays token-aligned (`PdfColor` `#CE4E30`) — geometry unchanged unless a dedicated PDF pass says otherwise

Fonts:

- **Oswald** — titles, labels, buttons, section headers (industrial condensed)  
- **Calibri** — body, menus, hints (readable forms)

---

## Spacing & radius tokens

Defined in `mobile/lib/theme.dart` as `SwiftSpace` / `SwiftRadius`.

| Token | Desktop | Mobile | Use |
|-------|---------|--------|-----|
| `xs` | 4 | 4 | Tight gaps |
| `sm` | 8 | 8 | Card inner rhythm |
| `md` | 12 | 12 | Form field gaps |
| `lg` | 16 | 16 | Screen padding |
| `xl` | 24 | 20 | Section breathing |
| Card radius | **8** | **14** | Desktop tighter; mobile more touch-friendly |
| Control radius | **6** | **10** | Inputs & buttons |
| Dialog radius | **10** | **16** | Sheets / dialogs |

Elevation:

- **Windows**: prefer hairline borders over shadows (desktop density).  
- **Android**: soft ambient shadow on bottom bar only; cards stay bordered + flat.

---

## Platform differences (intentional)

### Windows — premium desktop

- **MenuBar** + Customize (theme, layout density, PDF options)  
- **Navigation rail** for document kind (Shipping / Receiving / BOL)  
- Dark mode, font scale, keyboard shortcuts  
- Compact visual density; workspace side pane on wide layouts  
- Toolbar: orange logo + product name + context title + Update  

Do **not** strip these to match Android.

### Android — professional mobile

- Orange brand **header** (white logo lockup) + Update chip  
- Pinned **segmented** document-kind control (not a rail)  
- Scrollable form cards; fixed **Generate PDF** bottom bar  
- Bottom sheets for updates (not MenuBar)  
- Touch targets ≥ ~44dp; larger radii  

Do **not** add a desktop MenuBar or rail clone.

---

## Component recipes

### Buttons

- **Filled** — accent fill, white Oswald label → primary actions (Generate)  
- **Outlined** — ink on border → secondary (Update on desktop, utility)  
- **Text** — muted → tertiary / cancel  

### Inputs

- Filled wash (`#FAFAF8` / `#15181C`), Oswald floating labels in accent when focused  
- Focus ring: accent 1.4px (desktop) / 1.5px (mobile)

### Segmented controls

- Selected: accent-soft fill + accent ink  
- Unselected: surface + muted  
- Used for document kind (Android) and freight / theme chips  

### Cards (`_Card`)

- Title (Oswald) + one-line hint (Calibri muted) + content  
- Chrome-aware ink/muted for Windows dark mode  

### Snackbars / dialogs / tooltips

- Floating snackbars; ink / elevated dark panel  
- Dialogs: surface fill, platform radius  
- Tooltips: short delay, ink panel  

### Android header / bottom bar

- Header: full accent; subtitle `#FFE8E0`; white Update pill  
- Bottom bar: surface + top hairline (not a heavy Material shadow stack)

---

## App iconography

**Metaphor:** white shipping label on charcoal, Swift-orange up-arrow, barcode footer.  
Communicates “label / document generation” without lettering (legible at 16–48px).

Assets:

| Path | Purpose |
|------|---------|
| `mobile/assets/images/app_icon_1024.png` | Master source |
| `mobile/assets/images/app_icon.png` | In-app / tooling |
| `mobile/android/.../mipmap-*/ic_launcher.png` | Legacy launcher |
| `mobile/android/.../mipmap-anydpi-v26/` | Adaptive (fg + brand bg) |
| `mobile/windows/runner/resources/app_icon.ico` | Windows window / installer |

Regenerate mipmaps/ICO from the 1024 master via `scripts/deploy_app_icons.py`.

---

## Before → after intent

| Area | Before | After |
|------|--------|-------|
| Tokens | Colors only in `SwiftColors` | + spacing, radius, elevation, chrome extension |
| Theme | Solid baseline M3 | Tighter control themes, list/sheet/tab polish |
| Windows | Functional chrome | Clearer brand strip, rail accent, dialog/menu cohesion |
| Android | Good orange header | Refined header rhythm, quieter bottom bar, chrome-aware cards |
| Icon | Existing label metaphor | Same metaphor, cleaner contrast & brand orange fidelity |
| Docs | Implicit | This file as source of truth |

---

## Non-goals / constraints

- Do not change PDF page geometry for “visual polish” alone.  
- Do not clone Windows chrome onto Android.  
- Prefer elevating Swift Oilfield Supply look over a generic SaaS redesign.  
- Coordinate version bumps with other agents (target `1.1.48` for this design pass).
