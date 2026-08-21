# Shipping header logo guide — px dimensions

Source constants: `mobile/lib/pdf/shipping_label_pdf.dart`  
Guide screenshot: red (square/circular), green (rectangular), pink (Swift stop).

PDF uses **points** (1 inch = 72 pt). Pixel equivalents:

| Box | Role | PDF pt | px @ 72 dpi | px @ 96 dpi | px @ 2× QA render |
|-----|------|--------|-------------|-------------|-------------------|
| **Red** | Fill height for square / square-ish / circular (aspect ≤ 1.4) | **62.24** | **62** | **83** | **125** |
| **Green** | Fill height for rectangular / long (aspect > 1.4) | **46.0** | **46** | **61** | **92** |
| **Pink gap** | Stop expanding before Swift logo | **12.0** | **12** | **16** | **24** |

Formula: `pixels = points × (dpi / 72)`.

**Rule:** Scale each logo so its visible ink fills the red or green target height.
Shrink only when a single logo or dual-logo row would reach the pink limit
(`customerLogoToSwiftGap` before the Swift lockup).
