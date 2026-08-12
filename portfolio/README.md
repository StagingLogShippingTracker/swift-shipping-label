# Portfolio — interactive browser demos

Public GitHub Pages portfolio for:

- **Swift Document Generator** (`apps/sdg_web_demo`) — real PDF engines, generate + preview in browser
- **SLST / staging-tracker** (`apps/slst_web_demo`) — dashboard / staging / shipped / contacts with seeded sample data

## Live site

https://staginglogshippingtracker.github.io/portfolio/

- Launch SDG: https://staginglogshippingtracker.github.io/portfolio/demos/sdg/
- Launch SLST: https://staginglogshippingtracker.github.io/portfolio/demos/slst/

**No APK/EXE downloads** on this site — click-to-use demos only.

## Local run

```bash
cd apps/sdg_web_demo && flutter run -d chrome
cd apps/slst_web_demo && flutter run -d chrome
```

## Redeploy Pages

```powershell
.\scripts\deploy_pages.ps1
```

Builds both Flutter web demos and force-pushes the `gh-pages` branch.

## Notes

- SLST product repo locally is **staging-tracker** (`C:\Users\Brice\Downloads\staging-tracker`).
- These demos are sandboxes (sample data). Production apps ship as Flutter Windows + Android.
- Contacts in the SLST demo are fictional placeholders (not the production roster).
