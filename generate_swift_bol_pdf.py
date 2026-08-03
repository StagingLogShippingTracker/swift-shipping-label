"""
Swift Oilfield Supply — Fillable Bill of Lading
"""
from __future__ import annotations

from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.lib.units import inch
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas
from pypdf import PdfReader, PdfWriter
from pypdf.generic import (
    ArrayObject, BooleanObject, DictionaryObject, FloatObject, NameObject,
    NumberObject, StreamObject, TextStringObject,
)

SWIFT = colors.HexColor("#D94B2B")
SWIFT_LIGHT = colors.HexColor("#FDF4F1")
BLACK = colors.HexColor("#1A1A1A")
WHITE = colors.white
INK_SECONDARY = colors.HexColor("#4A4A4A")
INK_MUTED = colors.HexColor("#767676")
INK_HINT = colors.HexColor("#9A9A9A")
RULE = colors.HexColor("#C8C8C8")
TABLE_HEAD = colors.HexColor("#F0F0F0")
ZEBRA = colors.HexColor("#F7F7F7")
FIELD_BG = colors.HexColor("#F4F7FA")
WATERMARK = colors.HexColor("#ECECEC")
CLEAR = colors.Color(1, 1, 1, alpha=0)

PAGE_W, PAGE_H = letter
MARGIN = 0.4 * inch
FOOTER_H = 0.52 * inch
CONTENT_W = PAGE_W - 2 * MARGIN
FOOTER_BASE = MARGIN + 2
FOOTER_BOX_H = FOOTER_H - 2
# Content ends just above the footer (no Print BOL button).
CONTENT_BOTTOM = FOOTER_BASE + FOOTER_BOX_H + 8
GAP = 7
PAD = 6
BODY_INSET = 8  # Clear air between section header bars and body content
INSET = 3.0
ROW = 12
LBL = 7
LINE_ROWS = 7
ITEM_TYPE_OPTIONS = ("Pallet", "Crate", "Box", "Pipe", "Bundle", "Other")
PRODUCT_TOTAL_LABELS = ("Pallets", "Crates", "Boxes", "Pipes", "Bundles", "Other")

_ITEM_TYPE_PLURAL = {
    "Pallet": "Pallets",
    "Crate": "Crates",
    "Box": "Boxes",
    "Pipe": "Pipes",
    "Bundle": "Bundles",
    "Other": "Other",
}


def pluralize_item_type(value: str, qty: float) -> str:
    """Singular dropdown value → PDF line text (plural when qty > 1)."""
    s = (value or "").strip()
    if not s:
        return ""
    singular = s
    for opt in ITEM_TYPE_OPTIONS:
        if s.lower() in (opt.lower(), _ITEM_TYPE_PLURAL.get(opt, opt).lower()):
            singular = opt
            break
    if qty <= 1:
        return singular
    return _ITEM_TYPE_PLURAL.get(singular, singular)


def normalize_item_type(value: str) -> str:
    s = (value or "").strip()
    if not s:
        return ""
    for opt in ITEM_TYPE_OPTIONS:
        if s.lower() in (opt.lower(), _ITEM_TYPE_PLURAL.get(opt, opt).lower()):
            return opt
    return s


from app_paths import bundle_dir

OUT_PATH = Path(__file__).resolve().parent / "Swift Supply Bill of Lading.pdf"
SERIAL_PATH = OUT_PATH.with_name("bol_serial.txt")
XLSM_PATH = Path(r"C:\Users\Brice\OneDrive\Documents\Swift Waybill Document.xlsm")
LOGO_PATH = bundle_dir() / "assets" / "brand" / "swift_supply_logo_orange.png"


def _safe_replace(tmp: Path, pdf_path: Path) -> Path:
    """Replace pdf_path with tmp; if locked, keep a .new.pdf beside it."""
    try:
        tmp.replace(pdf_path)
        return pdf_path
    except PermissionError:
        fallback = pdf_path.with_name(pdf_path.stem + ".new.pdf")
        try:
            if fallback.exists():
                fallback.unlink()
        except OSError:
            pass
        tmp.replace(fallback)
        print(
            f"Note: {pdf_path.name} is open/locked — wrote {fallback.name}. "
            "Close the PDF and rename/replace when ready."
        )
        return fallback


def ensure_logo() -> Path:
    """Brand orange wordmark shipped under assets/brand/."""
    return LOGO_PATH


SHIPPER_LINES = (
    "Swift Oilfield Supply",
    "Unit 200, 920 - 36 Avenue",
    "Nisku, AB  T9E 1C6",
    "780-423-6979",
)

LEGAL = (
    "RECEIVED AT THE POINT OF ORIGIN ON THE DATE SPECIFIED, FROM THE CONSIGNOR MENTIONED HEREIN, "
    "THE PROPERTY DESCRIBED IN APPARENT GOOD ORDER EXCEPT AS NOTED (CONTENTS AND CONDITION OF "
    "CONTENTS OF PACKAGES UNKNOWN), MARKED, CONSIGNED, AND DESTINED AS INDICATED BELOW. "
    "NOTICE OF CLAIM: (A) NO CARRIER IS LIABLE FOR LOSS, DAMAGE, OR DELAY TO ANY GOODS UNDER THIS "
    "BILL OF LADING UNLESS NOTICE THEREOF IS GIVEN IN WRITING TO THE ORIGINATING CARRIER OR THE "
    "DELIVERING CARRIER WITHIN FIVE (5) DAYS AFTER DELIVERY OF THE GOODS, OR IN THE CASE OF FAILURE "
    "TO MAKE DELIVERY, WITHIN NINE (9) MONTHS FROM THE DATE OF SHIPMENT. (B) THE FINAL STATEMENT OF "
    "THE CLAIM MUST BE FILED WITHIN NINE (9) MONTHS FROM THE DATE OF SHIPMENT, TOGETHER WITH A COPY "
    "OF THE PAID FREIGHT BILL. THE CONTRACT FOR CARRIAGE IS DEEMED TO CONTAIN AND BE SUBJECT TO ALL "
    "CONDITIONS NOT PROHIBITED BY LAW UNDER THE MOTOR TRANSPORT ACT (ALBERTA)."
)

SHIPPER_CERT = (
    "This is to certify that the above-named materials are properly classified, described, packaged, "
    "marked and labeled, and are in proper condition for transportation according to the applicable "
    "regulations of the Department of Transportation."
)

COPY_TYPES = ("STORE COPY", "DRIVER COPY", "CUSTOMER COPY")

# Inlined into field actions so totals work even if document-level JS is blocked.
_PRODUCT_TOTAL_TYPES_JS = ", ".join(f'"{t}"' for t in PRODUCT_TOTAL_LABELS)
_ITEM_TYPE_SINGULAR_JS = ", ".join(f'"{t}"' for t in ITEM_TYPE_OPTIONS)

PRODUCT_TOTALS_JS = f"""\
var PRODUCT_TOTAL_TYPES = [{_PRODUCT_TOTAL_TYPES_JS}];
var ITEM_TYPE_SINGULAR = [{_ITEM_TYPE_SINGULAR_JS}];
var ITEM_TYPE_PLURAL = {{
    "Pallet": "Pallets", "Crate": "Crates", "Box": "Boxes",
    "Pipe": "Pipes", "Bundle": "Bundles", "Other": "Other"
}};
var PRODUCT_TOTAL_ROWS = {LINE_ROWS};

function parseQty(raw) {{
    var n = parseFloat(String(raw == null ? "" : raw).replace(/,/g, ""));
    return isNaN(n) ? 0 : n;
}}

function normalizeItemType(raw) {{
    var s = String(raw == null ? "" : raw).trim();
    if (!s) return "";
    var lower = s.toLowerCase();
    for (var i = 0; i < ITEM_TYPE_SINGULAR.length; i++) {{
        var opt = ITEM_TYPE_SINGULAR[i];
        var pl = ITEM_TYPE_PLURAL[opt] || opt;
        if (lower === opt.toLowerCase() || lower === pl.toLowerCase()) return opt;
    }}
    return s;
}}

function totalCategory(raw) {{
    var s = normalizeItemType(raw);
    if (!s) return "";
    return ITEM_TYPE_PLURAL[s] || s;
}}

function fieldQty(doc, name) {{
    var f = doc.getField(name);
    if (!f) return 0;
    try {{ return parseQty(f.valueAsString); }} catch (e) {{ return parseQty(f.value); }}
}}

function fieldText(doc, name) {{
    var f = doc.getField(name);
    if (!f) return "";
    try {{ return String(f.valueAsString || ""); }} catch (e) {{ return String(f.value || ""); }}
}}

function qtyForItemType(doc, typeName) {{
    var sum = 0;
    for (var i = 1; i <= PRODUCT_TOTAL_ROWS; i++) {{
        if (totalCategory(fieldText(doc, "line_" + i + "_item_type")) !== typeName) continue;
        sum += fieldQty(doc, "line_" + i + "_pieces");
    }}
    return sum;
}}

function sumLineColumn(doc, suffix) {{
    var sum = 0;
    for (var i = 1; i <= PRODUCT_TOTAL_ROWS; i++) {{
        sum += fieldQty(doc, "line_" + i + "_" + suffix);
    }}
    return sum;
}}

function setTotalField(doc, name, sum) {{
    var f = doc.getField(name);
    if (!f) return;
    try {{ f.value = sum ? String(sum) : ""; }} catch (e) {{}}
}}

function updateAllTotals() {{
    var doc = this;
    try {{
        for (var i = 0; i < PRODUCT_TOTAL_TYPES.length; i++) {{
            var t = PRODUCT_TOTAL_TYPES[i];
            setTotalField(doc, "product_total_" + t.toLowerCase(), qtyForItemType(doc, t));
        }}
        setTotalField(doc, "total_pieces", sumLineColumn(doc, "pieces"));
        setTotalField(doc, "total_weight", sumLineColumn(doc, "weight"));
    }} catch (e) {{}}
}}

function calcProductTotal() {{
    updateAllTotals();
    var name = "";
    try {{ name = String(event.target.name || ""); }} catch (e0) {{}}
    for (var i = 0; i < PRODUCT_TOTAL_TYPES.length; i++) {{
        var key = "product_total_" + PRODUCT_TOTAL_TYPES[i].toLowerCase();
        if (name === key || name.indexOf(key) === 0) {{
            var sum = qtyForItemType(this, PRODUCT_TOTAL_TYPES[i]);
            event.value = sum ? String(sum) : "";
            return;
        }}
    }}
}}

function calcTotalPieces() {{
    updateAllTotals();
    var sum = sumLineColumn(this, "pieces");
    event.value = sum ? String(sum) : "";
}}

function calcTotalWeight() {{
    updateAllTotals();
    var sum = sumLineColumn(this, "weight");
    event.value = sum ? String(sum) : "";
}}

function refreshProductTotals() {{
    try {{ updateAllTotals(); }} catch (e0) {{}}
    try {{ this.calculateNow(); }} catch (e1) {{}}
}}
"""

# Short field actions — full calc helpers live in document-level PRODUCT_TOTALS_JS.
# (Avoid inlining multi-KB scripts onto every widget; that made Android lag badly.)
CALC_PRODUCT_TOTAL_JS = "calcProductTotal();"
CALC_TOTAL_PIECES_JS = "calcTotalPieces();"
CALC_TOTAL_WEIGHT_JS = "calcTotalWeight();"
REFRESH_TOTALS_JS = "refreshProductTotals();"
REFRESH_KEYSTROKE_JS = "if(event.willCommit){refreshProductTotals();}"

# Combo + commit selected value immediately (bit 18 + bit 26).
ITEM_TYPE_FF = 131072 | 67108864

PRINT_JS = """\
function _bolResolveDoc() {
    var doc = this;
    try {
        if (event && event.target && event.target.doc) {
            doc = event.target.doc;
        }
    } catch (e0) {}
    if (!doc || typeof doc.getField !== "function") {
        try { doc = app.activeDocs[0]; } catch (e1) { doc = null; }
    }
    return doc;
}

function _setFieldAllWidgets(doc, name, value) {
    // Parent + page widgets (name.0 / name.1 / …) so Android Acrobat paints every copy.
    var f = doc.getField(name);
    if (!f) return;
    try { f.value = value; } catch (e0) {}
    var n = 0;
    try { n = doc.numPages; } catch (e1) { n = 3; }
    for (var i = 0; i < n; i++) {
        try {
            var w = doc.getField(name + "." + i);
            if (w) w.value = value;
        } catch (e2) {}
    }
}

function assignNextDocumentNumber(doc) {
    if (!doc || typeof doc.getField !== "function") return null;
    var counter = doc.getField("bol_serial_counter");
    if (!counter) return null;
    var serial = parseInt(counter.value, 10);
    if (isNaN(serial)) serial = 24;
    serial = serial + 1;
    try { counter.value = String(serial); } catch (eC) {}
    var docNo = "SW-" + ("0000" + serial).slice(-4);
    _setFieldAllWidgets(doc, "document_number", docNo);

    var dateField = doc.getField("document_date");
    var curDate = "";
    try { curDate = String(dateField ? (dateField.value || "") : ""); } catch (eD0) {}
    if (dateField && !curDate) {
        var d = new Date();
        var months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
        var dateStr = months[d.getMonth()] + " " + d.getDate() + ", " + d.getFullYear();
        _setFieldAllWidgets(doc, "document_date", dateStr);
    } else if (dateField && curDate) {
        // Re-push existing date onto every page widget (Android print sync).
        _setFieldAllWidgets(doc, "document_date", curDate);
    }
    try { doc.dirty = true; } catch (eD) {}
    try { doc.calculateNow(); } catch (eCalc) {}
    return serial;
}

function willPrintBOL() {
    // Fires for File > Print / system print on Acrobat (desktop + Android).
    var doc = _bolResolveDoc();
    if (!doc) return;
    assignNextDocumentNumber(doc);
}
"""


def draw_watermark(c: canvas.Canvas) -> None:
    """No background watermark — kept as a no-op for call-site compatibility."""
    return


def draw_page_frame(c: canvas.Canvas, content_bot: float | None = None) -> None:
    top = PAGE_H - MARGIN + 4
    bot = (content_bot if content_bot is not None else CONTENT_BOTTOM) - 2
    c.setStrokeColor(RULE)
    c.setLineWidth(0.75)
    c.rect(MARGIN - 3, bot, CONTENT_W + 6, top - bot, stroke=1, fill=0)
    c.setFillColor(SWIFT)
    c.rect(MARGIN - 3, PAGE_H - MARGIN + 2, CONTENT_W + 6, 3, stroke=0, fill=1)


def orange_bar(c: canvas.Canvas, x: float, y: float, w: float, h: float, r: float = 3) -> None:
    c.setFillColor(SWIFT)
    c.roundRect(x, y, w, h, r, stroke=0, fill=1)


def rect_stroke(c: canvas.Canvas, x: float, y: float, w: float, h: float, lw: float = 0.5) -> None:
    c.setStrokeColor(RULE)
    c.setLineWidth(lw)
    c.rect(x, y, w, h, stroke=1, fill=0)


def hline(c: canvas.Canvas, x: float, y: float, w: float) -> None:
    c.setStrokeColor(RULE)
    c.setLineWidth(0.4)
    c.line(x, y, x + w, y)


def section_title(c: canvas.Canvas, x: float, y: float, w: float, text: str, h: float = 16) -> None:
    # Sharp corners so panel grids join cleanly (no floating/rounded header gaps).
    c.setFillColor(SWIFT)
    c.rect(x, y - h, w, h, stroke=0, fill=1)
    c.setStrokeColor(RULE)
    c.setLineWidth(0.5)
    c.rect(x, y - h, w, h, stroke=1, fill=0)
    c.setFillColor(WHITE)
    font_size = 6.5
    c.setFont("Helvetica-Bold", font_size)
    # Optically center title in the bar (not jammed to the bottom edge).
    c.drawString(x + PAD, y - h + (h - font_size) / 2 + 0.5, text)


def micro_label(c: canvas.Canvas, x: float, y: float, text: str) -> None:
    c.setFillColor(INK_MUTED)
    c.setFont("Helvetica-Bold", 5.5)
    c.drawString(x, y, text.upper())


def body_label(c: canvas.Canvas, x: float, y: float, text: str) -> None:
    c.setFillColor(BLACK)
    c.setFont("Helvetica-Bold", 6.5)
    c.drawString(x, y, text)


def static_bold_lines(c: canvas.Canvas, x: float, y: float, lines: tuple[str, ...], size: float = 7.5) -> float:
    c.setFillColor(BLACK)
    c.setFont("Helvetica-Bold", size)
    for line in lines:
        c.drawString(x, y, line)
        y -= size + 4
    return y


def wrap_text_lines(c: canvas.Canvas, text: str, x: float, y: float, max_w: float,
                    font: str = "Helvetica", size: float = 3.8, leading: float = 4.2,
                    color=INK_MUTED, min_y: float | None = None) -> float:
    c.setFillColor(color)
    c.setFont(font, size)
    words, cur_y = text.split(), y
    current: list[str] = []
    for word in words:
        trial = " ".join(current + [word])
        if c.stringWidth(trial, font, size) <= max_w:
            current.append(word)
        else:
            if current:
                if min_y is not None and cur_y < min_y:
                    return cur_y
                c.drawString(x, cur_y, " ".join(current))
                cur_y -= leading
            current = [word]
    if current:
        if min_y is None or cur_y >= min_y:
            c.drawString(x, cur_y, " ".join(current))
            cur_y -= leading
    return cur_y


def put_textfield(form, name: str, x: float, y: float, w: float, h: float,
                  value: str = "", font_size: float = 7.5, fill=CLEAR,
                  field_flags: str = "") -> None:
    """Place an AcroForm field flush to the given rect — no extra underlines or borders."""
    if w <= 2 or h <= 2:
        return
    # Keep enough vertical room so glyphs are not clipped (esp. Adobe Android).
    h = max(h, font_size + 5)
    kwargs = dict(
        name=name,
        tooltip=name.replace("_", " ").title(),
        x=x, y=y, width=w, height=h,
        borderStyle="underlined", borderWidth=0, forceBorder=False,
        fillColor=fill, textColor=BLACK, fontSize=font_size, value=value,
    )
    if field_flags:
        kwargs["fieldFlags"] = field_flags
    form.textfield(**kwargs)


def ruled_field(c: canvas.Canvas, form, name: str, x: float, y_bottom: float, w: float,
                field_h: float = ROW, value: str = "", font_size: float = 8) -> None:
    """Entry field with a single underline; no box border (avoids label/box collisions)."""
    if w <= 2:
        return
    # Widget sits fully above the rule so the annotation does not cover it.
    form.textfield(
        name=name,
        tooltip=name.replace("_", " ").title(),
        x=x,
        y=y_bottom + 1.5,
        width=w,
        height=max(field_h - 1.0, font_size + 4),
        borderWidth=0,
        borderStyle="solid",
        forceBorder=False,
        fillColor=CLEAR,
        textColor=BLACK,
        fontSize=font_size,
        value=value,
    )
    hline(c, x, y_bottom, w)


def cell_field(form, name: str, cell_x: float, cell_y: float, cell_w: float, cell_h: float,
               font_size: float = 7, fill=None) -> None:
    """Field strictly inset inside a table cell so it never covers grid strokes."""
    put_textfield(
        form, name,
        cell_x + INSET, cell_y + INSET,
        max(cell_w - 2 * INSET, 2), max(cell_h - 2 * INSET, 6),
        font_size=font_size, fill=CLEAR if fill is None else fill,
    )


def choice_cell_field(form, name: str, cell_x: float, cell_y: float, cell_w: float, cell_h: float,
                      options: tuple[str, ...] | list[str], font_size: float = 7) -> None:
    """Dropdown (combo) inset inside a table cell."""
    w = max(cell_w - 2 * INSET, 2)
    h = max(cell_h - 2 * INSET, 6)
    if w <= 2 or h <= 2:
        return
    opts = list(options)
    # ReportLab requires a non-empty value when options are set (upstream bug with lbextras).
    # We clear the default after the PDF is written so rows start blank.
    form.choice(
        name=name,
        tooltip="Item Type",
        options=opts,
        value=opts[0],
        x=cell_x + INSET,
        y=cell_y + INSET,
        width=w,
        height=h,
        borderWidth=0,
        borderStyle="solid",
        forceBorder=False,
        fillColor=WHITE,
        textColor=BLACK,
        fontSize=font_size,
        fieldFlags="combo",
    )


def _blank_choice_ap(width: float, height: float) -> StreamObject:
    """Empty dropdown appearance (no selected text)."""
    data = (
        f"q\n1 1 1 rg\n0 0 {width:.2f} {height:.2f} re f\nQ\n"
    ).encode("ascii")
    stream = StreamObject()
    stream._data = data
    stream.update({
        NameObject("/Type"): NameObject("/XObject"),
        NameObject("/Subtype"): NameObject("/Form"),
        NameObject("/BBox"): ArrayObject([
            FloatObject(0), FloatObject(0), FloatObject(width), FloatObject(height),
        ]),
        NameObject("/Resources"): DictionaryObject(),
        NameObject("/Length"): NumberObject(len(data)),
    })
    return stream


def clear_item_type_defaults(pdf_path: Path) -> None:
    """Ensure Item Type dropdowns have options, blank value, and blank appearance."""
    reader = PdfReader(str(pdf_path))
    writer = PdfWriter()
    writer.append(reader)
    opt = ArrayObject([TextStringObject(o) for o in ITEM_TYPE_OPTIONS])
    for page in writer.pages:
        for ref in page.get("/Annots") or []:
            annot = ref.get_object()
            name = annot.get("/T")
            parent = annot.get("/Parent")
            if parent is not None:
                name = parent.get_object().get("/T")
            if not name or not str(name).endswith("_item_type"):
                continue
            target = parent.get_object() if parent is not None else annot
            target[NameObject("/FT")] = NameObject("/Ch")
            target[NameObject("/Ff")] = NumberObject(ITEM_TYPE_FF)  # combo + commitOnSelChange
            target[NameObject("/Opt")] = opt
            target[NameObject("/V")] = TextStringObject("")
            target[NameObject("/DV")] = TextStringObject("")
            if "/I" in target:
                del target[NameObject("/I")]

            rect = [float(v) for v in annot.get("/Rect")]
            w = max(rect[2] - rect[0], 2)
            h = max(rect[3] - rect[1], 6)
            blank = writer._add_object(_blank_choice_ap(w, h))
            annot[NameObject("/V")] = TextStringObject("")
            annot[NameObject("/DV")] = TextStringObject("")
            annot[NameObject("/AP")] = DictionaryObject({NameObject("/N"): blank})
            if "/I" in annot:
                del annot[NameObject("/I")]
            if "/MK" in annot:
                # Drop caption so viewers don't paint "Pallets" from MK.
                mk = annot.get("/MK")
                if mk is not None:
                    mk_obj = mk.get_object() if hasattr(mk, "get_object") else mk
                    if "/CA" in mk_obj:
                        del mk_obj[NameObject("/CA")]

    acro = writer._root_object.get("/AcroForm")
    if acro is not None:
        acro.get_object()[NameObject("/NeedAppearances")] = BooleanObject(True)

    tmp = pdf_path.with_suffix(".choices.tmp.pdf")
    with open(tmp, "wb") as fh:
        writer.write(fh)
    return _safe_replace(tmp, pdf_path)


def area_field(form, name: str, x: float, y: float, w: float, h: float,
               font_size: float = 7) -> None:
    """Multi-line text area: top-left aligned, Enter starts a new line."""
    if w <= 2 or h <= 2:
        return
    form.textfield(
        name=name,
        tooltip=name.replace("_", " ").title(),
        x=x, y=y, width=w, height=h,
        borderWidth=0,
        borderStyle="solid",
        forceBorder=False,
        fillColor=CLEAR,
        textColor=BLACK,
        fontSize=font_size,
        fieldFlags="multiline",
    )


def labeled_ruled_field(c: canvas.Canvas, form, name: str, x: float, y: float, w: float,
                        label: str, field_h: float = ROW, gap: float = 8,
                        value: str = "") -> float:
    """Label at y, entry line directly under it; returns y below the field."""
    micro_label(c, x, y, label)
    y_bottom = y - 5 - field_h
    ruled_field(c, form, name, x, y_bottom, w, field_h, value)
    return y_bottom - gap


def checkbox_field(c: canvas.Canvas, form, name: str, x: float, y: float, label: str) -> None:
    form.checkbox(
        name=name, tooltip=label, x=x, y=y, size=9,
        borderWidth=0.75, borderColor=BLACK, fillColor=WHITE, buttonStyle="check",
    )
    c.setFillColor(INK_SECONDARY)
    c.setFont("Helvetica", 6.5)
    c.drawString(x + 13, y + 1.5, label)


def radio_option(c: canvas.Canvas, form, group: str, value: str, x: float, y: float, label: str,
                 size: float = 8) -> float:
    """Circular radio widget. Returns the width occupied (widget + label)."""
    label_size = 6.5
    label_gap = 4.0
    # No widget border — rebuild_freight_radios supplies the only visible circle.
    form.radio(
        name=group,
        tooltip=label,
        value=value,
        x=x,
        y=y,
        size=size,
        selected=False,
        buttonStyle="circle",
        shape="circle",
        borderStyle="solid",
        borderWidth=0,
        borderColor=WHITE,
        fillColor=WHITE,
        forceBorder=False,
    )
    c.setFillColor(INK_SECONDARY)
    c.setFont("Helvetica", label_size)
    label_x = x + size + label_gap
    label_y = y + size / 2 - label_size * 0.35
    c.drawString(label_x, label_y, label)
    return size + label_gap + c.stringWidth(label, "Helvetica", label_size)


def _bezier_circle(cx: float, cy: float, r: float) -> str:
    """Approximate a circle with four cubic Bezier curves (valid PDF path ops)."""
    k = 0.5522847498 * r
    return (
        f"{cx + r:.3f} {cy:.3f} m "
        f"{cx + r:.3f} {cy + k:.3f} {cx + k:.3f} {cy + r:.3f} {cx:.3f} {cy + r:.3f} c "
        f"{cx - k:.3f} {cy + r:.3f} {cx - r:.3f} {cy + k:.3f} {cx - r:.3f} {cy:.3f} c "
        f"{cx - r:.3f} {cy - k:.3f} {cx - k:.3f} {cy - r:.3f} {cx:.3f} {cy - r:.3f} c "
        f"{cx + k:.3f} {cy - r:.3f} {cx + r:.3f} {cy - k:.3f} {cx + r:.3f} {cy:.3f} c "
    )


def _radio_circle_ap(on: bool, size: float = 8) -> StreamObject:
    """Clean circular radio AP — no square frame (avoids the vertical bleed line)."""
    cx = cy = size / 2.0
    # Keep ring fully inside the widget so stroke never clips into a square edge.
    r = (size / 2.0) - 0.9
    ring = _bezier_circle(cx, cy, r)
    if on:
        dot = _bezier_circle(cx, cy, r * 0.42)
        data = (
            f"q\n"
            f"1 1 1 rg 0 0 {size:.2f} {size:.2f} re f\n"
            f"0 0 0 RG 1.1 w {ring} s\n"
            f"0 0 0 rg {dot} f\n"
            f"Q\n"
        )
    else:
        data = (
            f"q\n"
            f"1 1 1 rg 0 0 {size:.2f} {size:.2f} re f\n"
            f"0 0 0 RG 1.1 w {ring} s\n"
            f"Q\n"
        )
    encoded = data.encode("ascii")
    stream = StreamObject()
    stream._data = encoded
    stream.update({
        NameObject("/Type"): NameObject("/XObject"),
        NameObject("/Subtype"): NameObject("/Form"),
        NameObject("/BBox"): ArrayObject([
            FloatObject(0), FloatObject(0), FloatObject(size), FloatObject(size),
        ]),
        NameObject("/Matrix"): ArrayObject([
            FloatObject(1), FloatObject(0), FloatObject(0), FloatObject(1),
            FloatObject(0), FloatObject(0),
        ]),
        NameObject("/Resources"): DictionaryObject(),
        NameObject("/Length"): NumberObject(len(encoded)),
    })
    return stream


def rebuild_freight_radios(pdf_path: Path) -> None:
    """One mutually-exclusive freight_charges group with working circular appearances."""
    reader = PdfReader(str(pdf_path))
    writer = PdfWriter()
    writer.append(reader)

    states = ["prepaid", "collect", "third_party"]
    widgets: list = []
    for page in writer.pages:
        for ref in page.get("/Annots") or []:
            annot = ref.get_object()
            parent = annot.get("/Parent")
            name = annot.get("/T")
            if parent is not None:
                parent_obj = parent.get_object()
                if parent_obj.get("/T") == "freight_charges":
                    widgets.append(ref)
            elif name == "freight_charges":
                pass

    if not widgets:
        return

    export_for: list[str] = []
    for i, ref in enumerate(widgets):
        annot = ref.get_object()
        state = None
        ap = annot.get("/AP")
        if ap:
            n = ap.get("/N")
            if n is not None:
                nobj = n.get_object() if hasattr(n, "get_object") else n
                if hasattr(nobj, "keys"):
                    for key in nobj.keys():
                        key_s = str(key).lstrip("/")
                        if key_s and key_s != "Off":
                            state = key_s
                            break
        if not state:
            as_val = annot.get("/AS")
            if as_val is not None:
                key_s = str(as_val).lstrip("/")
                if key_s and key_s != "Off":
                    state = key_s
        export_for.append(state or states[i % len(states)])

    parent = DictionaryObject({
        NameObject("/FT"): NameObject("/Btn"),
        NameObject("/T"): TextStringObject("freight_charges"),
        NameObject("/Ff"): NumberObject(32768),  # Radio
        NameObject("/V"): NameObject("/Off"),
        NameObject("/DV"): NameObject("/Off"),
        NameObject("/Kids"): ArrayObject(widgets),
    })
    parent_ref = writer._add_object(parent)

    for ref, state in zip(widgets, export_for):
        annot = ref.get_object()
        rect = [float(v) for v in annot.get("/Rect")]
        size = max(rect[2] - rect[0], rect[3] - rect[1], 8)
        off_ap = writer._add_object(_radio_circle_ap(False, size))
        on_ap = writer._add_object(_radio_circle_ap(True, size))
        ap_n = DictionaryObject({
            NameObject("/Off"): off_ap,
            NameObject(f"/{state}"): on_ap,
        })
        annot[NameObject("/Parent")] = parent_ref
        annot[NameObject("/FT")] = NameObject("/Btn")
        annot[NameObject("/AP")] = DictionaryObject({
            NameObject("/N"): ap_n,
            NameObject("/D"): ap_n,
        })
        annot[NameObject("/AS")] = NameObject("/Off")
        annot[NameObject("/F")] = NumberObject(4)
        # Strip ReportLab square borders — those cause the vertical bleed line.
        for key in ("/T", "/Ff", "/BS", "/MK", "/Border", "/BC", "/BG", "/H"):
            if key in annot:
                del annot[NameObject(key)]
        # Explicit empty border style so viewers don't invent a frame.
        annot[NameObject("/BS")] = DictionaryObject({
            NameObject("/W"): NumberObject(0),
            NameObject("/S"): NameObject("/S"),
        })

    acro = writer._root_object.get("/AcroForm")
    if acro is not None:
        acro_obj = acro.get_object()
        fields = []
        for ref in acro_obj.get("/Fields", []):
            obj = ref.get_object()
            if obj.get("/T") == "freight_charges":
                continue
            fields.append(ref)
        fields.append(parent_ref)
        acro_obj[NameObject("/Fields")] = ArrayObject(fields)
        acro_obj[NameObject("/NeedAppearances")] = BooleanObject(True)

    tmp = pdf_path.with_suffix(".freight.tmp.pdf")
    with open(tmp, "wb") as fh:
        writer.write(fh)
    return _safe_replace(tmp, pdf_path)


def sig_fields(c: canvas.Canvas, form, x: float, y_top: float, y_bottom: float, w: float,
               rows: list[list[tuple[str, str, float]]], *,
               top_inset: float | None = None) -> None:
    """Sub-label + entry line as a tight centered pair in each row band."""
    inner_x = x + PAD
    inner_w = w - 2 * PAD
    inset_top = BODY_INSET if top_inset is None else top_inset
    inset_bot = 5
    content_top = y_top - inset_top
    content_bot = y_bottom + inset_bot
    avail_h = content_top - content_bot
    if avail_h < 20 or not rows:
        return

    n = len(rows)
    field_h = 11.0
    label_to_rule = 13.0
    stack_h = label_to_rule + 2
    col_gap = 10
    row_h = avail_h / n

    for i, row in enumerate(rows):
        band_top = content_top - i * row_h
        band_bot = band_top - row_h
        # Center the label→line stack in the band (even air above & below).
        label_y = band_bot + (row_h + stack_h) / 2 - 1
        label_y = min(label_y, band_top - 3)
        label_y = max(label_y, band_bot + stack_h)
        y_rule = label_y - label_to_rule

        total = sum(frac for _, _, frac in row)
        cx = inner_x
        avail = inner_w - col_gap * (len(row) - 1)
        for name, label, frac in row:
            fw = avail * (frac / total)
            micro_label(c, cx, label_y, label)
            ruled_field(c, form, name, cx, y_rule, fw, field_h, font_size=8)
            cx += fw + col_gap


def draw_copy_label(c: canvas.Canvas, y: float, band_h: float, copy_label: str) -> None:
    c.setFillColor(WHITE)
    c.setFont("Helvetica-Bold", 7)
    c.drawRightString(MARGIN + CONTENT_W - PAD, y - band_h + 6, copy_label)


def measure_wrapped_text(c: canvas.Canvas, text: str, max_w: float,
                         font: str = "Helvetica", size: float = 3.8,
                         leading: float = 4.2) -> float:
    """Return the height needed to wrap `text` at `max_w`."""
    c.setFont(font, size)
    words, lines, current = text.split(), 0, []
    for word in words:
        trial = " ".join(current + [word])
        if c.stringWidth(trial, font, size) <= max_w:
            current.append(word)
        else:
            if current:
                lines += 1
            current = [word]
    if current:
        lines += 1
    if lines <= 0:
        return 0.0
    # First line sits on its baseline; subsequent lines add `leading` each.
    return size + (lines - 1) * leading


def draw_footer(c: canvas.Canvas) -> None:
    box_y = FOOTER_BASE
    box_h = FOOTER_BOX_H
    box_top = box_y + box_h
    c.setStrokeColor(RULE)
    c.setLineWidth(0.5)
    c.rect(MARGIN, box_y, CONTENT_W, box_h, stroke=1, fill=0)
    c.setFillColor(SWIFT)
    c.rect(MARGIN, box_top - 2, CONTENT_W, 2, stroke=0, fill=1)

    # Readable disclaimer — was ~2.3pt and illegible on phones.
    size, leading = 5.2, 6.2
    text_w = CONTENT_W - 2 * PAD
    text_h = measure_wrapped_text(c, LEGAL, text_w, size=size, leading=leading)
    body_top = box_top - 3
    body_bot = box_y + 2
    body_h = body_top - body_bot
    top_pad = max((body_h - text_h) / 2, 1.0)
    legal_top = body_top - top_pad - size + 0.5
    wrap_text_lines(
        c, LEGAL, MARGIN + PAD, legal_top, text_w,
        size=size, leading=leading, min_y=body_bot + 1,
    )


def add_interactive_features(pdf_path: Path, serial_start: int) -> Path:
    """Add hidden serial counter, WillPrint hook, and document-level JavaScript."""
    reader = PdfReader(str(pdf_path))
    writer = PdfWriter()
    writer.append(reader)
    writer.add_js(PRODUCT_TOTALS_JS)
    writer.add_js(PRINT_JS)

    # Strip any leftover Print BOL widgets from older builds.
    for page_obj in writer.pages:
        annots = list(page_obj.get("/Annots") or [])
        kept = []
        for ref in annots:
            annot = ref.get_object()
            name = annot.get("/T")
            parent = annot.get("/Parent")
            parent_obj = parent.get_object() if parent is not None else None
            if parent_obj is not None and not name:
                name = parent_obj.get("/T")
            if str(name or "") == "print_bol":
                continue
            kept.append(ref)
        if kept:
            page_obj[NameObject("/Annots")] = ArrayObject(kept)
        elif "/Annots" in page_obj:
            del page_obj[NameObject("/Annots")]

    page = writer.pages[0]
    serial_annot = DictionaryObject({
        NameObject("/Type"): NameObject("/Annot"),
        NameObject("/Subtype"): NameObject("/Widget"),
        NameObject("/FT"): NameObject("/Tx"),
        NameObject("/T"): TextStringObject("bol_serial_counter"),
        NameObject("/V"): TextStringObject(str(serial_start)),
        NameObject("/Rect"): ArrayObject([
            FloatObject(-200), FloatObject(-200), FloatObject(-100), FloatObject(-180),
        ]),
        NameObject("/F"): NumberObject(2),
        NameObject("/Ff"): NumberObject(1),
    })
    serial_ref = writer._add_object(serial_annot)
    page[NameObject("/Annots")] = ArrayObject(list(page.get("/Annots", [])) + [serial_ref])

    for page_obj in writer.pages:
        for ref in page_obj.get("/Annots") or []:
            annot = ref.get_object()
            name = annot.get("/T")
            parent = annot.get("/Parent")
            parent_obj = parent.get_object() if parent is not None else None
            if parent_obj is not None and not name:
                name = parent_obj.get("/T")
            if str(name or "") == "document_number":
                target = parent_obj if parent_obj is not None else annot
                target[NameObject("/Ff")] = NumberObject(1)
                target[NameObject("/V")] = TextStringObject("")
                target[NameObject("/DV")] = TextStringObject("")

    will_print = DictionaryObject({
        NameObject("/S"): NameObject("/JavaScript"),
        NameObject("/JS"): TextStringObject("willPrintBOL();"),
    })
    catalog = writer._root_object
    cat_aa = catalog.get("/AA")
    if cat_aa is None:
        cat_aa = DictionaryObject()
        catalog[NameObject("/AA")] = cat_aa
    else:
        cat_aa = cat_aa.get_object()
    cat_aa[NameObject("/WP")] = will_print
    if "/DP" in cat_aa:
        del cat_aa[NameObject("/DP")]

    acro_ref = writer._root_object.get("/AcroForm")
    if acro_ref is None:
        acro = DictionaryObject()
        writer._root_object[NameObject("/AcroForm")] = acro
    else:
        acro = acro_ref.get_object()
    fields = []
    for ref in list(acro.get("/Fields", [])):
        obj = ref.get_object()
        if str(obj.get("/T") or "") == "print_bol":
            continue
        fields.append(ref)
    fields.append(serial_ref)
    acro[NameObject("/Fields")] = ArrayObject(fields)
    # Critical for Android: regenerate appearances for sibling page widgets.
    acro[NameObject("/NeedAppearances")] = BooleanObject(True)

    tmp = pdf_path.with_suffix(".interactive.tmp.pdf")
    with open(tmp, "wb") as fh:
        writer.write(fh)
    return _safe_replace(tmp, pdf_path)


def read_serial_start() -> int:
    """Seed for the hidden counter embedded in the shared OneDrive PDF."""
    if SERIAL_PATH.exists():
        try:
            return int(SERIAL_PATH.read_text(encoding="utf-8").strip())
        except ValueError:
            pass
    if XLSM_PATH.exists():
        try:
            import re
            import zipfile

            with zipfile.ZipFile(XLSM_PATH) as zf:
                sheet = zf.read("xl/worksheets/sheet1.xml").decode("utf-8", "replace")
            match = re.search(r'<c r="B1"[^>]*><v>(\d+)</v></c>', sheet)
            if match:
                return int(match.group(1))
        except (OSError, ValueError, KeyError):
            pass
    return 24


def draw_aligned_bottom_row(c: canvas.Canvas, form, y: float, block_h: float, hdr_h: float) -> None:
    """Product Total | Special Instructions | Totals — even panels with clear header clearance."""
    block_bot = y - block_h
    pw = 1.48 * inch
    tw = 1.28 * inch
    iw = CONTENT_W - pw - tw - 2 * GAP
    ix = MARGIN + pw + GAP
    tx = ix + iw + GAP

    body_h = block_h - hdr_h
    body_top = y - hdr_h

    section_title(c, MARGIN, y, pw, "PRODUCT TOTAL", hdr_h)
    rect_stroke(c, MARGIN, block_bot, pw, body_h, 0.75)

    section_title(c, ix, y, iw, "SPECIAL INSTRUCTIONS", hdr_h)
    rect_stroke(c, ix, block_bot, iw, body_h, 0.75)

    section_title(c, tx, y, tw, "TOTALS", hdr_h)
    c.setFillColor(SWIFT_LIGHT)
    c.rect(tx, block_bot, tw, body_h, stroke=0, fill=1)
    rect_stroke(c, tx, block_bot, tw, body_h, 0.75)

    # --- Product totals: qty sum per Item Type from goods rows ---
    categories = PRODUCT_TOTAL_LABELS
    n = len(categories)
    avail = body_h - BODY_INSET - 4
    row_h = avail / n
    label_w = 0.72 * inch
    inner_x = MARGIN + PAD
    field_x = inner_x + label_w
    field_w = pw - 2 * PAD - label_w
    for i, label in enumerate(categories):
        row_top = body_top - BODY_INSET - i * row_h
        label_y = row_top - 8
        micro_label(c, inner_x, label_y, label)
        field_h = min(11, max(8, row_h - 10))
        field_bot = row_top - row_h + 3
        put_textfield(
            form, f"product_total_{label.lower()}",
            field_x, field_bot,
            field_w, field_h,
            font_size=8, fill=CLEAR, field_flags="readOnly",
        )
        hline(c, field_x, field_bot, field_w)

    # --- Special instructions ---
    area_field(
        form, "special_instructions",
        ix + PAD, block_bot + BODY_INSET - 2,
        iw - 2 * PAD, body_h - BODY_INSET - (BODY_INSET - 2),
        font_size=7,
    )

    # --- Totals band ---
    mid_tot = block_bot + body_h / 2
    c.setStrokeColor(RULE)
    c.setLineWidth(0.45)
    c.line(tx, mid_tot, tx + tw, mid_tot)

    micro_label(c, tx + PAD, body_top - BODY_INSET - 1, "Total Piece Count")
    pieces_top = body_top - BODY_INSET - 12
    put_textfield(
        form, "total_pieces",
        tx + PAD, mid_tot + 5,
        tw - 2 * PAD, max(pieces_top - (mid_tot + 5), 11),
        font_size=8, fill=CLEAR, field_flags="readOnly",
    )

    micro_label(c, tx + PAD, mid_tot - BODY_INSET - 1, "Total Weight")
    put_textfield(
        form, "total_weight",
        tx + PAD, block_bot + 16,
        tw - 2 * PAD, max(mid_tot - BODY_INSET - 12 - (block_bot + 16), 11),
        font_size=8, fill=CLEAR, field_flags="readOnly",
    )
    c.setFillColor(INK_HINT)
    c.setFont("Helvetica", 5)
    c.drawString(tx + PAD, block_bot + 6, "LBS")


def draw_meta_strip(c: canvas.Canvas, form, y: float) -> float:
    """Three equal meta cells in one bordered strip — labels and fields stay inside."""
    strip_h = 36
    bot = y - strip_h
    c.setFillColor(FIELD_BG)
    c.rect(MARGIN, bot, CONTENT_W, strip_h, stroke=0, fill=1)
    rect_stroke(c, MARGIN, bot, CONTENT_W, strip_h, 0.75)
    col_w = CONTENT_W / 3
    specs = (
        ("document_number", "Document Number"),
        ("document_date", "Date"),
        ("booking_ref", "Booking Ref"),
    )
    for i, (name, label) in enumerate(specs):
        cx = MARGIN + i * col_w
        if i > 0:
            c.setStrokeColor(RULE)
            c.setLineWidth(0.5)
            c.line(cx, bot, cx, y)
        micro_label(c, cx + PAD, y - 10, label)
        # Document Number is auto-assigned on print (SW-####) — not editable.
        flags = "readOnly" if name == "document_number" else ""
        put_textfield(
            form, name, cx + 4, bot + 5, col_w - 8, 14,
            font_size=8, fill=CLEAR, field_flags=flags,
        )
        hline(c, cx + 4, bot + 5, col_w - 8)
    return bot - GAP


def draw_probill_cutout(c: canvas.Canvas, form, logo_x: float, logo_w: float,
                        logo_top: float, logo_h: float) -> None:
    """Dashed 'affix probill sticker' box beside the logo (logo position unchanged)."""
    box_w = 2.35 * inch
    box_h = min(logo_h, 0.85 * inch)
    gap = 14
    # Prefer the right of the logo; fall back to the left if it would clip the margin.
    right_x = logo_x + logo_w + gap
    left_x = logo_x - gap - box_w
    if right_x + box_w <= MARGIN + CONTENT_W - 2:
        box_x = right_x
    elif left_x >= MARGIN:
        box_x = left_x
    else:
        box_x = min(max(MARGIN, right_x), MARGIN + CONTENT_W - box_w)
    box_y = logo_top - logo_h + (logo_h - box_h) / 2

    # Cutout look: dashed border + light fill.
    c.setFillColor(colors.HexColor("#FAFAFA"))
    c.rect(box_x, box_y, box_w, box_h, stroke=0, fill=1)
    c.setStrokeColor(SWIFT)
    c.setDash(3, 2)
    c.setLineWidth(1.0)
    c.rect(box_x, box_y, box_w, box_h, stroke=1, fill=0)
    c.setDash()

    c.setFillColor(SWIFT)
    c.setFont("Helvetica-Bold", 6)
    c.drawCentredString(box_x + box_w / 2, box_y + box_h - 11, "PROBILL")
    c.setFillColor(INK_MUTED)
    c.setFont("Helvetica", 5)
    c.drawCentredString(box_x + box_w / 2, box_y + box_h - 20, "AFFIX STICKER HERE")

    # Optional handwritten / typed fallback number line inside the cutout.
    put_textfield(
        form, "probill_number",
        box_x + 6, box_y + 6,
        box_w - 12, 12,
        font_size=8, fill=CLEAR,
    )
    hline(c, box_x + 6, box_y + 6, box_w - 12)


def draw_bol_page(c: canvas.Canvas, form, copy_label: str) -> None:
    """Draw one BOL page. Identical fields/widgets on every page sync by name."""
    draw_watermark(c)

    y = PAGE_H - MARGIN - 2

    # Cropped wordmark centered — do not shift when adding the probill cutout.
    logo_h = 0.82 * inch
    logo_x = MARGIN
    logo_w = 0.0
    logo = ensure_logo()
    if logo.exists():
        img = ImageReader(str(logo))
        iw, ih = img.getSize()
        logo_w = logo_h * iw / ih
        max_w = CONTENT_W * 0.92
        if logo_w > max_w:
            logo_w = max_w
            logo_h = logo_w * ih / iw
        logo_x = (PAGE_W - logo_w) / 2
        c.drawImage(img, logo_x, y - logo_h, logo_w, logo_h, mask="auto")

    # Probill sticker cutout — sits beside the logo without moving it.
    draw_probill_cutout(c, form, logo_x, logo_w, y, logo_h)
    y -= logo_h + 6

    band_h = 22
    orange_bar(c, MARGIN, y - band_h, CONTENT_W, band_h, r=3)
    c.setFillColor(WHITE)
    c.setFont("Helvetica-Bold", 8.5)
    c.drawCentredString(PAGE_W / 2, y - 11, "SWIFT OILFIELD SUPPLY")
    c.setFont("Helvetica", 6.5)
    c.drawCentredString(PAGE_W / 2, y - 18, "STRAIGHT BILL OF LADING  \u00b7  NOT NEGOTIABLE")
    draw_copy_label(c, y, band_h, copy_label)
    y -= band_h + 10

    y = draw_meta_strip(c, form, y)

    col_w = (CONTENT_W - GAP) / 2
    lx, rx = MARGIN, MARGIN + col_w + GAP
    hdr_h = 15
    # Equal-height panels — no staggered bottoms / floating gaps.
    panel_h = 1.12 * inch

    section_title(c, lx, y, col_w, "SHIPPER (CONSIGNOR)", hdr_h)
    section_title(c, rx, y, col_w, "SHIP TO (CONSIGNEE)", hdr_h)
    top = y - hdr_h
    bot = top - panel_h
    rect_stroke(c, lx, bot, col_w, panel_h, 0.75)
    static_bold_lines(c, lx + PAD, top - 12, SHIPPER_LINES, size=7.0)

    # Consignee body = four abutting cells (no outer wrapper, so rules meet cleanly).
    row1 = top - panel_h * 0.30
    row2 = top - panel_h * 0.58
    mid_x = rx + col_w / 2
    cells = (
        ("consignee_name", rx, row1, col_w, top - row1, "Ship To Name"),
        ("consignee_address", rx, row2, col_w, row1 - row2, "Delivery Address"),
        ("consignee_contact_name", rx, bot, mid_x - rx, row2 - bot, "Contact Name"),
        ("consignee_contact_number", mid_x, bot, rx + col_w - mid_x, row2 - bot, "Contact Number"),
    )
    for name, cx, cy, cw, ch, label in cells:
        rect_stroke(c, cx, cy, cw, ch, 0.6)
        micro_label(c, cx + PAD, cy + ch - 10, label)
        put_textfield(
            form, name, cx + PAD, cy + 4,
            cw - 2 * PAD, max(ch - 16, 8),
            font_size=7.5, fill=CLEAR,
        )

    y = bot - GAP

    bill_h = 0.42 * inch
    section_title(c, lx, y, col_w, "3RD PARTY BILLING (COLLECT)", hdr_h)
    body_bot = y - hdr_h - bill_h
    rect_stroke(c, lx, body_bot, col_w, bill_h, 0.75)
    area_field(form, "third_party_billing", lx + PAD, body_bot + PAD,
               col_w - 2 * PAD, bill_h - 2 * PAD, font_size=7)

    freight_h = hdr_h + bill_h
    rect_stroke(c, rx, y - freight_h, col_w, freight_h, 0.75)
    section_title(c, rx, y, col_w, "FREIGHT CHARGES", hdr_h)
    # Vertically center radios + labels in the body; evenly distribute across the panel width.
    radio_size = 8
    body_bot = y - freight_h
    body_top = y - hdr_h
    row_center = (body_bot + body_top) / 2
    ry = row_center - radio_size / 2
    options = (
        ("prepaid", "Prepaid"),
        ("collect", "Collect"),
        ("third_party", "3rd Party"),
    )
    inner_left = rx + PAD
    inner_right = rx + col_w - PAD
    # Measure each option width, then space remaining gap evenly between them.
    c.setFont("Helvetica", 6.5)
    widths = [radio_size + 4 + c.stringWidth(lbl, "Helvetica", 6.5) for _, lbl in options]  # 4 = label gap
    total_w = sum(widths)
    gaps = 2  # spaces between the three options
    free = max(inner_right - inner_left - total_w, 0)
    gap = free / gaps if gaps else 0
    ox = inner_left
    for (value, label), ow in zip(options, widths):
        radio_option(c, form, "freight_charges", value, ox, ry, label, size=radio_size)
        ox += ow + gap

    y -= freight_h + GAP

    track_hdr = 13
    section_title(c, MARGIN, y, CONTENT_W, "TRACKING & REFERENCE NUMBERS", track_hdr)
    y -= track_hdr
    # Tracking (PRO) #, Booking #, and Ref # removed — remaining fields expand to fill the row.
    track_cols = [
        ("po_num", "PO #", 1.15),
        ("packing_list", "PACKING LIST #", 1.45),
        ("order_num", "ORDER #", 1.15),
        ("project", "PROJECT", 1.35),
    ]
    th, rh = 12, 14
    total = sum(u for _, _, u in track_cols)
    widths = [CONTENT_W * u / total for _, _, u in track_cols]
    # Header row
    cx = MARGIN
    for (_, title, _), cw in zip(track_cols, widths):
        c.setFillColor(TABLE_HEAD)
        c.rect(cx, y - th, cw, th, stroke=1, fill=1)
        c.setFillColor(INK_SECONDARY)
        c.setFont("Helvetica-Bold", 5)
        c.drawString(cx + 3, y - th + 3.5, title)
        cx += cw
    y -= th
    # Input row — same column widths as header
    cx = MARGIN
    for (key, _, _), cw in zip(track_cols, widths):
        rect_stroke(c, cx, y - rh, cw, rh)
        cell_field(form, key, cx, y - rh, cw, rh, font_size=7)
        cx += cw
    y -= rh + GAP

    line_cols = [
        ("pieces", "QTY", 0.55),
        ("item_type", "ITEM TYPE", 1.05),
        ("dimensions", "DIMENSIONS (in)", 0.95),
        ("description", "DESCRIPTION OF GOODS", 2.2),
        ("weight", "WEIGHT (LBS)", 0.8),
    ]
    lh, lr = 14, 14
    total = sum(u for _, _, u in line_cols)
    widths = [CONTENT_W * u / total for _, _, u in line_cols]
    cx = MARGIN
    for (_, title, _), cw in zip(line_cols, widths):
        orange_bar(c, cx, y - lh, cw, lh, r=0)
        c.setStrokeColor(RULE)
        c.setLineWidth(0.4)
        c.rect(cx, y - lh, cw, lh, stroke=1, fill=0)
        c.setFillColor(WHITE)
        c.setFont("Helvetica-Bold", 5)
        c.drawString(cx + 3, y - lh + 4, title)
        cx += cw
    y -= lh
    for row in range(LINE_ROWS):
        cx = MARGIN
        for (key, _, _), cw in zip(line_cols, widths):
            if row % 2 == 1:
                c.setFillColor(ZEBRA)
                c.rect(cx, y - lr, cw, lr, stroke=0, fill=1)
            rect_stroke(c, cx, y - lr, cw, lr)
            field_name = f"line_{row + 1}_{key}"
            if key == "item_type":
                choice_cell_field(
                    form, field_name, cx, y - lr, cw, lr,
                    ITEM_TYPE_OPTIONS, font_size=6.5,
                )
            else:
                cell_field(form, field_name, cx, y - lr, cw, lr, font_size=7)
            cx += cw
        y -= lr
    y -= GAP

    block_h = 1.40 * inch
    draw_aligned_bottom_row(c, form, y, block_h, 16)
    y -= block_h + GAP

    sw = (CONTENT_W - 2 * GAP) / 3
    sh = 1.38 * inch
    hdr = 16
    sx = MARGIN
    body_top = y - hdr
    body_bot = body_top - sh
    pad_in = PAD

    # --- Shipper's Certification ---
    section_title(c, sx, y, sw, "SHIPPER'S CERTIFICATION", hdr)
    rect_stroke(c, sx, body_bot, sw, sh, 0.75)
    # Keep certification text compact; give Name/Signature/Date real room.
    cert_bot = body_bot + sh * 0.55
    wrap_text_lines(
        c, SHIPPER_CERT,
        sx + pad_in, body_top - BODY_INSET,
        sw - 2 * pad_in,
        size=4.4, leading=5.2, color=INK_SECONDARY, min_y=cert_bot + 3,
    )
    c.setStrokeColor(RULE)
    c.setLineWidth(0.5)
    c.line(sx, cert_bot, sx + sw, cert_bot)
    sig_fields(c, form, sx, cert_bot, body_bot, sw, [
        [("shipper_cert_name", "Name", 1.0)],
        [("shipper_cert_sign", "Signature", 0.62), ("shipper_cert_date", "Date", 0.38)],
    ], top_inset=7)
    sx += sw + GAP

    # --- Carrier / Driver Acceptance ---
    section_title(c, sx, y, sw, "CARRIER / DRIVER ACCEPTANCE", hdr)
    rect_stroke(c, sx, body_bot, sw, sh, 0.75)
    sig_fields(c, form, sx, body_top, body_bot, sw, [
        [("driver_company", "Company", 1.0)],
        [("driver_print", "Driver Print Name", 1.0)],
        [("driver_sign", "Signature", 1.0)],
        [("vehicle_id", "Vehicle ID", 1.0)],
        [("departure_time", "Departure", 0.62), ("driver_date", "Date", 0.38)],
    ], top_inset=BODY_INSET)
    sx += sw + GAP

    # --- Consignee Delivery Receipt ---
    section_title(c, sx, y, sw, "CONSIGNEE DELIVERY RECEIPT", hdr)
    rect_stroke(c, sx, body_bot, sw, sh, 0.75)
    sig_fields(c, form, sx, body_top, body_bot, sw, [
        [("consignee_sign", "Consignee Signature", 1.0)],
        [("consignee_print", "Print Name", 1.0)],
        [("consignee_date", "Date", 1.0)],
    ], top_inset=BODY_INSET)

    # Outer page frame stops above the footer.
    draw_page_frame(c, content_bot=body_bot - 4)
    draw_footer(c)


def merge_same_name_fields(pdf_path: Path) -> None:
    """Join duplicate same-name widgets into single AcroForm parents with /Kids."""
    reader = PdfReader(str(pdf_path))
    writer = PdfWriter()
    writer.append(reader)

    acro_ref = writer._root_object.get("/AcroForm")
    if acro_ref is None:
        return
    acro = acro_ref.get_object()
    fields = list(acro.get("/Fields", []))

    by_name: dict[str, list] = {}
    order: list[str] = []
    untouched = []
    for ref in fields:
        obj = ref.get_object()
        name = obj.get("/T")
        if not name:
            untouched.append(ref)
            continue
        key = str(name)
        if key not in by_name:
            by_name[key] = []
            order.append(key)
        by_name[key].append(ref)

    new_fields = list(untouched)
    for key in order:
        refs = by_name[key]
        if len(refs) == 1:
            new_fields.append(refs[0])
            continue
        # Prefer an existing parent (radios already have kids).
        parent_ref = None
        widgets = []
        for ref in refs:
            obj = ref.get_object()
            if obj.get("/Kids") is not None and obj.get("/Parent") is None:
                parent_ref = ref
            else:
                widgets.append(ref)
        if parent_ref is None:
            first = refs[0].get_object()
            parent = DictionaryObject({
                NameObject("/T"): first.get("/T"),
                NameObject("/FT"): first.get("/FT"),
                NameObject("/Kids"): ArrayObject(refs),
            })
            if first.get("/Ff") is not None:
                parent[NameObject("/Ff")] = first.get("/Ff")
            if first.get("/V") is not None:
                parent[NameObject("/V")] = first.get("/V")
            if first.get("/Opt") is not None:
                parent[NameObject("/Opt")] = first.get("/Opt")
            parent_ref = writer._add_object(parent)
            for ref in refs:
                w = ref.get_object()
                w[NameObject("/Parent")] = parent_ref
                if "/T" in w:
                    # Keep name only on parent to avoid duplicate top-level fields.
                    del w[NameObject("/T")]
        else:
            parent = parent_ref.get_object()
            kids = list(parent.get("/Kids", []))
            for ref in widgets:
                w = ref.get_object()
                w[NameObject("/Parent")] = parent_ref
                if "/T" in w:
                    del w[NameObject("/T")]
                if ref not in kids:
                    kids.append(ref)
            parent[NameObject("/Kids")] = ArrayObject(kids)
        new_fields.append(parent_ref)

    acro[NameObject("/Fields")] = ArrayObject(new_fields)
    acro[NameObject("/NeedAppearances")] = BooleanObject(True)

    tmp = pdf_path.with_suffix(".merged.tmp.pdf")
    with open(tmp, "wb") as fh:
        writer.write(fh)
    return _safe_replace(tmp, pdf_path)


def wire_product_total_calculations(pdf_path: Path) -> None:
    """Wire Acrobat scripts: product-type totals, total pieces, and total weight.

    Calculation/refresh scripts are inlined on the fields so they work even when
    document-level JavaScript is stripped or blocked. Triggers are attached to
    each widget (kid), not only the parent field dict.
    """
    reader = PdfReader(str(pdf_path))
    writer = PdfWriter()
    writer.append(reader)

    calc_scripts = {
        **{f"product_total_{t.lower()}": CALC_PRODUCT_TOTAL_JS for t in PRODUCT_TOTAL_LABELS},
        "total_pieces": CALC_TOTAL_PIECES_JS,
        "total_weight": CALC_TOTAL_WEIGHT_JS,
    }
    trigger_suffixes = ("_pieces", "_item_type", "_weight")
    co_refs: list = []

    def _js_action(script: str) -> DictionaryObject:
        return DictionaryObject({
            NameObject("/S"): NameObject("/JavaScript"),
            NameObject("/JS"): TextStringObject(script),
        })

    def _ensure_aa(annot) -> DictionaryObject:
        aa = annot.get("/AA")
        if aa is None:
            aa = DictionaryObject()
            annot[NameObject("/AA")] = aa
        else:
            aa = aa.get_object()
        return aa

    def _resolve_name(annot) -> str | None:
        name = annot.get("/T")
        parent = annot.get("/Parent")
        parent_obj = parent.get_object() if parent is not None else None
        if parent_obj is not None and not name:
            name = parent_obj.get("/T")
        return str(name) if name else None

    for page in writer.pages:
        for ref in page.get("/Annots") or []:
            annot = ref.get_object()
            name_s = _resolve_name(annot)
            if not name_s:
                continue
            parent = annot.get("/Parent")
            parent_obj = parent.get_object() if parent is not None else None
            field_obj = parent_obj if parent_obj is not None else annot
            field_ref = parent if parent is not None else ref

            if name_s in calc_scripts:
                field_obj[NameObject("/Ff")] = NumberObject(1)  # ReadOnly
                aa = _ensure_aa(field_obj)
                aa[NameObject("/C")] = _js_action(calc_scripts[name_s])
                # Drop accidental Bl/K on calculated totals (e.g. total_pieces).
                for key in ("/Bl", "/K", "/V"):
                    if key in aa:
                        del aa[NameObject(key)]
                co_refs.append(field_ref)

            # Only goods-grid inputs — not total_pieces / total_weight.
            is_line_trigger = (
                name_s.startswith("line_")
                and any(name_s.endswith(suf) for suf in trigger_suffixes)
            )
            if is_line_trigger:
                # Parent-only actions (avoid duplicating heavy AA on every page widget).
                aa = _ensure_aa(field_obj)
                aa[NameObject("/V")] = _js_action(REFRESH_TOTALS_JS)
                aa[NameObject("/Bl")] = _js_action(REFRESH_TOTALS_JS)
                aa[NameObject("/K")] = _js_action(REFRESH_KEYSTROKE_JS)
                if name_s.endswith("_item_type"):
                    ff = int(field_obj.get("/Ff") or 0)
                    field_obj[NameObject("/Ff")] = NumberObject(ff | ITEM_TYPE_FF)

    acro = writer._root_object.get("/AcroForm")
    if acro is not None and co_refs:
        acro_obj = acro.get_object()
        seen: set[int] = set()
        ordered = []
        # Stable order: product totals first, then piece/weight totals.
        preferred = [
            *[f"product_total_{t.lower()}" for t in PRODUCT_TOTAL_LABELS],
            "total_pieces",
            "total_weight",
        ]
        by_name: dict[str, object] = {}
        for ref in co_refs:
            obj = ref.get_object() if hasattr(ref, "get_object") else ref
            n = str(obj.get("/T") or "")
            if n and id(ref) not in seen:
                by_name[n] = ref
                seen.add(id(ref))
        for n in preferred:
            if n in by_name:
                ordered.append(by_name[n])
        acro_obj[NameObject("/CO")] = ArrayObject(ordered)
        acro_obj[NameObject("/NeedAppearances")] = BooleanObject(True)

    tmp = pdf_path.with_suffix(".product_totals.tmp.pdf")
    with open(tmp, "wb") as fh:
        writer.write(fh)
    return _safe_replace(tmp, pdf_path)


def build_pdf() -> Path:
    out = OUT_PATH
    try:
        # Probe whether the destination is writable before a long render.
        with open(out, "ab"):
            pass
    except PermissionError:
        out = OUT_PATH.with_name(OUT_PATH.stem + ".new.pdf")
        print(f"Note: {OUT_PATH.name} is open/locked — writing {out.name} instead.")

    c = canvas.Canvas(str(out), pagesize=letter)
    form = c.acroForm
    for i, copy_type in enumerate(COPY_TYPES):
        if i > 0:
            c.showPage()
        draw_bol_page(c, form, copy_type)
    c.save()
    serial_start = read_serial_start()
    out = merge_same_name_fields(out)
    out = clear_item_type_defaults(out)
    out = rebuild_freight_radios(out)
    out = wire_product_total_calculations(out)
    out = add_interactive_features(out, serial_start)
    SERIAL_PATH.write_text(str(serial_start), encoding="utf-8")
    return out


if __name__ == "__main__":
    print(f"Created: {build_pdf()}")
