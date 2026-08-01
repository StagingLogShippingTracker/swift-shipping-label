"""
Swift Supply — Shipping Label Generator (Windows)

Modern UI aligned with the Android app: warm stone canvas, white cards,
Swift orange accents, grouped fields, primary Generate CTA.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, simpledialog, ttk

from app_paths import ensure_data_dirs, user_desktop
from generate_swift_shipping_label_pdf import (
    CUSTOMER_LOGO_SAMPLE,
    SAMPLE,
    build_pdf,
)
from version import __version__
import app_update

# ---- Shared brand tokens (match Android) ----
SWIFT = "#D94B2B"
SWIFT_SOFT = "#F8EBE7"
BG = "#F4F2EF"
SURFACE = "#FFFFFF"
INK = "#1A1A1A"
MUTED = "#6B6B6B"
BORDER = "#E6E2DC"
BORDER_FOCUS = "#D94B2B"
FONT = "Segoe UI"
FONT_DISPLAY = "Segoe UI Semibold"

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".tif", ".tiff"}

FIELDS = [
    ("customer", "Customer", False),
    ("po_num", "PO No.", True),
    ("project", "Project", True),
    ("special_instructions", "Special Instructions", True),
    ("ship_to", "Ship To", False),
    ("location", "Location", True),
    ("attn", "Attn", False),
    ("carrier", "Carrier", False),
    ("packing_slip", "Swift Packing Slip No.", False),
    ("sales_order", "Swift Sales Order No.", False),
    ("swift_contact", "Swift Contact", False),
    ("pallet_num", "Pallet / Crate #", False),
    ("pallet_of", "Pallet / Crate of", False),
    ("box_num", "Box #", False),
    ("box_of", "Box of", False),
]

FIELD_GROUPS = [
    (
        "Customer & job",
        "Who the shipment is for",
        ["customer", "po_num", "project", "special_instructions"],
    ),
    (
        "Ship to",
        "Destination the warehouse reads first",
        ["ship_to", "location", "attn"],
    ),
    (
        "Swift references",
        "Internal tracking",
        ["carrier", "packing_slip", "sales_order", "swift_contact"],
    ),
    (
        "Piece count",
        "Match the BOL",
        ["pallet_num", "pallet_of", "box_num", "box_of"],
    ),
]

PRESET_KEYS = [
    "customer",
    "ship_to",
    "location",
    "attn",
    "carrier",
    "swift_contact",
    "special_instructions",
]

FIELD_META = {k: (label, multi) for k, label, multi in FIELDS}


def safe_name(text: str) -> str:
    text = (text or "customer").strip() or "customer"
    return re.sub(r"[^\w\- ]+", "", text).strip() or "customer"


class FillApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title(f"Swift Supply — Shipping Label  v{__version__}")
        self.geometry("920x920")
        self.minsize(780, 720)
        self.configure(bg=BG)

        dirs = ensure_data_dirs()
        self.app_dir = dirs["data"]
        self.exe_dir = dirs["exe"]
        self.bundle_dir = dirs["bundle"]
        self.logo_dir = dirs["logos"]
        self.out_dir = dirs["filled"]
        self.presets_path = dirs["presets"]

        self.logo_folder = tk.StringVar(value=str(self.logo_dir))
        self.logo_path = tk.StringVar(value="")
        self.preset_name = tk.StringVar(value="")
        self.logo_pick = tk.StringVar(value="")
        self.status = tk.StringVar(value="Ready")
        self._update_busy = False
        self.widgets: dict[str, tk.Text | ttk.Entry] = {}
        self.presets: dict = self._load_presets()

        self._apply_style()
        self._seed_sample_logo()
        self._build_ui()
        self._refresh_preset_list()
        self._refresh_logo_list()

        if CUSTOMER_LOGO_SAMPLE.exists() and not self.logo_path.get():
            self.logo_path.set(str(CUSTOMER_LOGO_SAMPLE))

        self.logo_path.trace_add("write", lambda *_: self._update_logo_preview())

    def _apply_style(self) -> None:
        style = ttk.Style(self)
        try:
            style.theme_use("clam")
        except tk.TclError:
            pass

        style.configure(".", background=BG, foreground=INK, font=(FONT, 10))
        style.configure("TFrame", background=BG)
        style.configure("Card.TFrame", background=SURFACE)
        style.configure("Header.TFrame", background=SWIFT)
        style.configure("Bar.TFrame", background=SURFACE)

        style.configure(
            "Title.TLabel",
            background=SWIFT,
            foreground="#FFFFFF",
            font=(FONT_DISPLAY, 16),
        )
        style.configure(
            "Subtitle.TLabel",
            background=SWIFT,
            foreground="#FFE8E0",
            font=(FONT, 10),
        )
        style.configure(
            "CardTitle.TLabel",
            background=SURFACE,
            foreground=INK,
            font=(FONT_DISPLAY, 11),
        )
        style.configure(
            "CardHint.TLabel",
            background=SURFACE,
            foreground=MUTED,
            font=(FONT, 9),
        )
        style.configure(
            "Field.TLabel",
            background=SURFACE,
            foreground=MUTED,
            font=(FONT, 9),
        )
        style.configure(
            "Muted.TLabel",
            background=BG,
            foreground=MUTED,
            font=(FONT, 9),
        )
        style.configure(
            "Status.TLabel",
            background=SURFACE,
            foreground=MUTED,
            font=(FONT, 9),
        )

        style.configure(
            "TEntry",
            fieldbackground="#FAFAF8",
            foreground=INK,
            bordercolor=BORDER,
            lightcolor=BORDER_FOCUS,
            darkcolor=BORDER,
            padding=8,
            insertcolor=INK,
        )
        style.map(
            "TEntry",
            fieldbackground=[("focus", "#FFFFFF")],
            bordercolor=[("focus", BORDER_FOCUS)],
        )

        style.configure(
            "TCombobox",
            fieldbackground="#FAFAF8",
            foreground=INK,
            bordercolor=BORDER,
            padding=6,
            arrowsize=14,
        )
        style.map(
            "TCombobox",
            fieldbackground=[("readonly", "#FAFAF8")],
            bordercolor=[("focus", BORDER_FOCUS)],
        )

        style.configure(
            "Secondary.TButton",
            background=SURFACE,
            foreground=INK,
            bordercolor=BORDER,
            borderwidth=1,
            focuscolor=SWIFT_SOFT,
            padding=(12, 8),
            font=(FONT, 9),
        )
        style.map(
            "Secondary.TButton",
            background=[("active", SWIFT_SOFT), ("pressed", "#F0D8D0")],
            bordercolor=[("active", SWIFT)],
        )

        style.configure(
            "Ghost.TButton",
            background=BG,
            foreground=MUTED,
            bordercolor=BORDER,
            borderwidth=1,
            padding=(10, 6),
            font=(FONT, 9),
        )
        style.map(
            "Ghost.TButton",
            background=[("active", SURFACE)],
            foreground=[("active", INK)],
        )

        style.configure(
            "Primary.TButton",
            background=SWIFT,
            foreground="#FFFFFF",
            bordercolor=SWIFT,
            borderwidth=0,
            focuscolor=SWIFT,
            padding=(18, 11),
            font=(FONT_DISPLAY, 11),
        )
        style.map(
            "Primary.TButton",
            background=[("active", "#C44226"), ("pressed", "#A83820")],
            foreground=[("disabled", "#F5C4B8")],
        )

        style.configure(
            "Vertical.TScrollbar",
            background=BORDER,
            troughcolor=BG,
            bordercolor=BG,
            arrowcolor=MUTED,
        )

    def _card(self, parent: tk.Misc, title: str, hint: str = "") -> ttk.Frame:
        wrap = tk.Frame(parent, bg=BG)
        wrap.pack(fill="x", padx=20, pady=(0, 14))

        outer = tk.Frame(wrap, bg=BORDER, padx=1, pady=1)
        outer.pack(fill="x")
        card = tk.Frame(outer, bg=SURFACE, padx=18, pady=16)
        card.pack(fill="x")

        ttk.Label(card, text=title, style="CardTitle.TLabel").pack(anchor="w")
        if hint:
            ttk.Label(card, text=hint, style="CardHint.TLabel").pack(
                anchor="w", pady=(2, 0)
            )
        body = ttk.Frame(card, style="Card.TFrame")
        body.pack(fill="x", pady=(12, 0))
        return body

    def _field_row(
        self, parent: tk.Misc, key: str, label: str, multiline: bool
    ) -> None:
        ttk.Label(parent, text=label.upper(), style="Field.TLabel").pack(
            anchor="w", pady=(10, 4)
        )
        if multiline:
            wrap = tk.Frame(parent, bg=BORDER, padx=1, pady=1)
            wrap.pack(fill="x")
            w = tk.Text(
                wrap,
                height=3,
                wrap="word",
                font=("Calibri", 11),
                bg="#FAFAF8",
                fg=INK,
                relief="flat",
                padx=10,
                pady=8,
                insertbackground=INK,
                highlightthickness=0,
            )
            w.pack(fill="x")
        else:
            w = ttk.Entry(parent, font=("Calibri", 11))
            w.pack(fill="x")
        self.widgets[key] = w

    def _build_ui(self) -> None:
        # Header
        header = tk.Frame(self, bg=SWIFT)
        header.pack(fill="x")
        inner = tk.Frame(header, bg=SWIFT, padx=24, pady=18)
        inner.pack(fill="x")
        top = tk.Frame(inner, bg=SWIFT)
        top.pack(fill="x")
        left = tk.Frame(top, bg=SWIFT)
        left.pack(side="left", fill="x", expand=True)
        ttk.Label(left, text="SWIFT SUPPLY", style="Title.TLabel").pack(anchor="w")
        ttk.Label(
            left, text="Shipping Label Generator", style="Subtitle.TLabel"
        ).pack(anchor="w", pady=(2, 0))
        hdr_actions = tk.Frame(top, bg=SWIFT)
        hdr_actions.pack(side="right")
        ttk.Button(
            hdr_actions,
            text="Update",
            style="Secondary.TButton",
            command=self._check_for_update,
        ).pack(side="left", padx=(0, 8))
        ttk.Button(
            hdr_actions,
            text="Desktop shortcut",
            style="Secondary.TButton",
            command=self._create_shortcut,
        ).pack(side="left")

        # Scrollable body
        body_wrap = tk.Frame(self, bg=BG)
        body_wrap.pack(fill="both", expand=True)

        canvas = tk.Canvas(body_wrap, bg=BG, highlightthickness=0, bd=0)
        scroll = ttk.Scrollbar(
            body_wrap, orient="vertical", command=canvas.yview, style="Vertical.TScrollbar"
        )
        form = tk.Frame(canvas, bg=BG)
        form.bind(
            "<Configure>",
            lambda e: canvas.configure(scrollregion=canvas.bbox("all")),
        )
        win = canvas.create_window((0, 0), window=form, anchor="nw")
        canvas.configure(yscrollcommand=scroll.set)

        def _stretch(_event=None) -> None:
            canvas.itemconfigure(win, width=canvas.winfo_width())

        canvas.bind("<Configure>", _stretch)
        canvas.pack(side="left", fill="both", expand=True)
        scroll.pack(side="right", fill="y")

        def _wheel(event: tk.Event) -> None:
            canvas.yview_scroll(int(-event.delta / 120), "units")

        canvas.bind_all("<MouseWheel>", _wheel)

        ttk.Label(
            form,
            text="Pre-fill the label → Generate PDF. Long PO / Project lines wrap and shrink Special Instructions for print.",
            style="Muted.TLabel",
            wraplength=820,
        ).pack(anchor="w", padx=20, pady=(18, 14))

        # Preset card
        pre = self._card(form, "Customer preset", "Reuse customer defaults; shipment fields stay per job")
        row = ttk.Frame(pre, style="Card.TFrame")
        row.pack(fill="x")
        self.preset_combo = ttk.Combobox(
            row, textvariable=self.preset_name, state="readonly"
        )
        self.preset_combo.pack(side="left", fill="x", expand=True)
        self.preset_combo.bind("<<ComboboxSelected>>", lambda _e: self._apply_preset())
        ttk.Button(
            row, text="Load", style="Secondary.TButton", command=self._apply_preset
        ).pack(side="left", padx=(8, 0))
        ttk.Button(
            row, text="Save", style="Secondary.TButton", command=self._save_preset
        ).pack(side="left", padx=(8, 0))
        ttk.Button(
            row, text="Delete", style="Ghost.TButton", command=self._delete_preset
        ).pack(side="left", padx=(8, 0))

        # Logos card
        logos = self._card(form, "Customer logos", "Import once, pick per job")
        fr = ttk.Frame(logos, style="Card.TFrame")
        fr.pack(fill="x")
        ttk.Label(fr, text="LOGO FOLDER", style="Field.TLabel").pack(anchor="w")
        rowf = ttk.Frame(fr, style="Card.TFrame")
        rowf.pack(fill="x", pady=(4, 10))
        ttk.Entry(rowf, textvariable=self.logo_folder).pack(
            side="left", fill="x", expand=True
        )
        ttk.Button(
            rowf,
            text="Choose…",
            style="Secondary.TButton",
            command=self._choose_logo_folder,
        ).pack(side="left", padx=(8, 0))

        ttk.Label(logos, text="LOGOS IN FOLDER", style="Field.TLabel").pack(anchor="w")
        row2 = ttk.Frame(logos, style="Card.TFrame")
        row2.pack(fill="x", pady=(4, 10))
        self.logo_combo = ttk.Combobox(
            row2, textvariable=self.logo_pick, state="readonly"
        )
        self.logo_combo.pack(side="left", fill="x", expand=True)
        self.logo_combo.bind("<<ComboboxSelected>>", lambda _e: self._use_picked_logo())
        ttk.Button(
            row2, text="Use", style="Secondary.TButton", command=self._use_picked_logo
        ).pack(side="left", padx=(8, 0))
        ttk.Button(
            row2,
            text="Import…",
            style="Secondary.TButton",
            command=self._import_logos,
        ).pack(side="left", padx=(8, 0))

        ttk.Label(logos, text="ACTIVE LOGO", style="Field.TLabel").pack(anchor="w")
        row3 = ttk.Frame(logos, style="Card.TFrame")
        row3.pack(fill="x", pady=(4, 8))
        ttk.Entry(row3, textvariable=self.logo_path).pack(
            side="left", fill="x", expand=True
        )
        ttk.Button(
            row3, text="Browse…", style="Secondary.TButton", command=self._browse_logo
        ).pack(side="left", padx=(8, 0))

        self.logo_preview = tk.Label(logos, bg=SURFACE, text="")
        self.logo_preview.pack(anchor="w")

        # Field groups
        for title, hint, keys in FIELD_GROUPS:
            card = self._card(form, title, hint)
            if title == "Piece count":
                grid = ttk.Frame(card, style="Card.TFrame")
                grid.pack(fill="x")
                for i, key in enumerate(keys):
                    label, multi = FIELD_META[key]
                    cell = ttk.Frame(grid, style="Card.TFrame")
                    cell.grid(row=0, column=i, sticky="ew", padx=(0 if i == 0 else 8, 0))
                    grid.columnconfigure(i, weight=1)
                    self._field_row(cell, key, label, multi)
            else:
                for key in keys:
                    label, multi = FIELD_META[key]
                    self._field_row(card, key, label, multi)

        # Spacer for bottom bar
        tk.Frame(form, bg=BG, height=24).pack(fill="x")

        # Bottom action bar
        bar_border = tk.Frame(self, bg=BORDER, height=1)
        bar_border.pack(fill="x", side="bottom")
        bar = tk.Frame(self, bg=SURFACE, padx=20, pady=14)
        bar.pack(fill="x", side="bottom")

        left_actions = ttk.Frame(bar, style="Bar.TFrame")
        left_actions.pack(side="left")
        ttk.Button(
            left_actions,
            text="Load sample",
            style="Ghost.TButton",
            command=self._load_sample,
        ).pack(side="left")
        ttk.Button(
            left_actions,
            text="Clear shipment",
            style="Ghost.TButton",
            command=self._clear_shipment,
        ).pack(side="left", padx=(8, 0))
        ttk.Button(
            left_actions,
            text="Clear all",
            style="Ghost.TButton",
            command=self._clear,
        ).pack(side="left", padx=(8, 0))

        right = ttk.Frame(bar, style="Bar.TFrame")
        right.pack(side="right")
        ttk.Label(right, textvariable=self.status, style="Status.TLabel").pack(
            side="left", padx=(0, 14)
        )
        ttk.Button(
            right,
            text="Generate PDF",
            style="Primary.TButton",
            command=self._save,
        ).pack(side="left")

        self.after(100, self._update_logo_preview)

    def _update_logo_preview(self) -> None:
        path = self.logo_path.get().strip()
        if not path or not Path(path).is_file():
            self.logo_preview.configure(image="", text="")
            self.logo_preview.image = None  # type: ignore[attr-defined]
            return
        try:
            img = tk.PhotoImage(file=path)
            # Scale down if huge
            h = img.height()
            if h > 56:
                factor = max(1, h // 56)
                img = img.subsample(factor, factor)
            self.logo_preview.configure(image=img, text="")
            self.logo_preview.image = img  # type: ignore[attr-defined]
        except tk.TclError:
            # Non-GIF/PNG PhotoImage limitation — show filename only
            self.logo_preview.configure(
                image="", text=f"  {Path(path).name}", fg=MUTED, font=(FONT, 9)
            )
            self.logo_preview.image = None  # type: ignore[attr-defined]

    # ----- persistence -----

    def _load_presets(self) -> dict:
        if self.presets_path.exists():
            try:
                data = json.loads(self.presets_path.read_text(encoding="utf-8"))
                if isinstance(data, dict):
                    data.setdefault("customers", {})
                    data.setdefault("logo_folder", str(self.logo_dir))
                    return data
            except (json.JSONDecodeError, OSError):
                pass
        return {"logo_folder": str(self.logo_dir), "customers": {}}

    def _save_presets_file(self) -> None:
        self.presets["logo_folder"] = self.logo_folder.get()
        self.presets_path.write_text(
            json.dumps(self.presets, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )

    def _seed_sample_logo(self) -> None:
        if not CUSTOMER_LOGO_SAMPLE.exists():
            return
        dest = self.logo_dir / "Pacific Canbriam.png"
        if not dest.exists():
            try:
                shutil.copy2(CUSTOMER_LOGO_SAMPLE, dest)
            except OSError:
                return
        customers = self.presets.setdefault("customers", {})
        if "Pacific Canbriam" not in customers:
            customers["Pacific Canbriam"] = {
                "customer": "PACIFIC CANBRIAM",
                "logo": dest.name,
                "ship_to": "STRAIT PROJECTS",
                "location": "12341 271 RD, FORT ST. JOHN, BC",
                "attn": "RICK SHUMAN / JEREMY PLATZ",
                "carrier": "WILLYS",
            }
            self._save_presets_file()

    # ----- logos -----

    def _logo_dir_path(self) -> Path:
        p = Path(self.logo_folder.get().strip() or str(self.logo_dir))
        p.mkdir(parents=True, exist_ok=True)
        return p

    def _list_logos(self) -> list[str]:
        folder = self._logo_dir_path()
        return sorted(
            f.name
            for f in folder.iterdir()
            if f.is_file() and f.suffix.lower() in IMAGE_EXTS
        )

    def _refresh_logo_list(self) -> None:
        names = self._list_logos()
        self.logo_combo["values"] = names
        if names and self.logo_pick.get() not in names:
            self.logo_pick.set(names[0])

    def _choose_logo_folder(self) -> None:
        path = filedialog.askdirectory(
            title="Customer logo folder",
            initialdir=self.logo_folder.get() or str(self.logo_dir),
        )
        if not path:
            return
        self.logo_folder.set(path)
        self.logo_dir = Path(path)
        self._save_presets_file()
        self._refresh_logo_list()

    def _use_picked_logo(self) -> None:
        name = self.logo_pick.get()
        if not name:
            return
        self.logo_path.set(str(self._logo_dir_path() / name))

    def _browse_logo(self) -> None:
        path = filedialog.askopenfilename(
            title="Customer logo",
            initialdir=str(self._logo_dir_path()),
            filetypes=[
                ("Images", "*.png;*.jpg;*.jpeg;*.gif;*.webp;*.bmp"),
                ("All files", "*.*"),
            ],
        )
        if path:
            self.logo_path.set(path)

    def _import_logos(self) -> None:
        paths = filedialog.askopenfilenames(
            title="Import customer logos (multi-select)",
            initialdir=str(self._logo_dir_path()),
            filetypes=[
                ("Images", "*.png;*.jpg;*.jpeg;*.gif;*.webp;*.bmp"),
                ("All files", "*.*"),
            ],
        )
        if not paths:
            return

        dest_dir = self._logo_dir_path()
        imported: list[str] = []
        customers = self.presets.setdefault("customers", {})
        create_presets = messagebox.askyesno(
            "Create presets?",
            f"Import {len(paths)} logo(s) into:\n{dest_dir}\n\n"
            "Also create a customer preset from each file name?",
        )

        for src in paths:
            src_p = Path(src)
            if src_p.suffix.lower() not in IMAGE_EXTS:
                continue
            dest = dest_dir / src_p.name
            if dest.exists() and dest.resolve() != src_p.resolve():
                stem, suf = src_p.stem, src_p.suffix
                n = 2
                while dest.exists():
                    dest = dest_dir / f"{stem} ({n}){suf}"
                    n += 1
            try:
                if src_p.resolve() != dest.resolve():
                    shutil.copy2(src_p, dest)
            except OSError as exc:
                messagebox.showerror("Import failed", f"{src_p.name}: {exc}")
                continue
            imported.append(dest.name)

            if create_presets:
                name = safe_name(src_p.stem)
                if name not in customers:
                    customers[name] = {
                        "customer": name.upper(),
                        "logo": dest.name,
                    }

        self._save_presets_file()
        self._refresh_logo_list()
        self._refresh_preset_list()
        if imported:
            self.logo_pick.set(imported[0])
            self._use_picked_logo()
            self.status.set(f"Imported {len(imported)} logo(s)")
            messagebox.showinfo(
                "Imported",
                f"Added {len(imported)} logo(s) to:\n{dest_dir}",
            )

    # ----- presets -----

    def _refresh_preset_list(self) -> None:
        names = sorted(self.presets.get("customers", {}).keys())
        self.preset_combo["values"] = names

    def _apply_preset(self) -> None:
        name = self.preset_name.get()
        data = self.presets.get("customers", {}).get(name)
        if not data:
            return
        for key in PRESET_KEYS:
            if key in data:
                self._set(key, str(data.get(key, "")))
        logo = data.get("logo", "")
        if logo:
            folder = self._logo_dir_path()
            path = Path(logo)
            if not path.is_file():
                path = folder / logo
            if path.is_file():
                self.logo_path.set(str(path))
                self.logo_pick.set(path.name)
        self.status.set(f"Loaded preset “{name}”")

    def _save_preset(self) -> None:
        default = self._get("customer") or self.preset_name.get() or "New customer"
        name = simpledialog.askstring(
            "Save preset",
            "Preset name:",
            initialvalue=default,
            parent=self,
        )
        if not name:
            return
        name = name.strip()
        entry = {k: self._get(k) for k in PRESET_KEYS}
        logo = self.logo_path.get().strip()
        if logo:
            lp = Path(logo)
            folder = self._logo_dir_path()
            try:
                if lp.resolve().parent == folder.resolve():
                    entry["logo"] = lp.name
                else:
                    dest = folder / lp.name
                    if lp.exists() and (
                        not dest.exists() or dest.resolve() != lp.resolve()
                    ):
                        shutil.copy2(lp, dest)
                    entry["logo"] = dest.name if dest.exists() else str(lp)
            except OSError:
                entry["logo"] = logo
        else:
            entry["logo"] = ""

        self.presets.setdefault("customers", {})[name] = entry
        self._save_presets_file()
        self._refresh_preset_list()
        self.preset_name.set(name)
        self.status.set(f"Saved preset “{name}”")
        messagebox.showinfo("Preset saved", f"Saved “{name}”.")

    def _delete_preset(self) -> None:
        name = self.preset_name.get()
        if not name:
            return
        if not messagebox.askyesno("Delete preset", f"Delete preset “{name}”?"):
            return
        self.presets.get("customers", {}).pop(name, None)
        self._save_presets_file()
        self.preset_name.set("")
        self._refresh_preset_list()
        self.status.set(f"Deleted preset “{name}”")

    # ----- fields -----

    def _get(self, key: str) -> str:
        w = self.widgets[key]
        if isinstance(w, tk.Text):
            return w.get("1.0", "end").strip()
        return w.get().strip()

    def _set(self, key: str, value: str) -> None:
        w = self.widgets[key]
        if isinstance(w, tk.Text):
            w.delete("1.0", "end")
            w.insert("1.0", value)
        else:
            w.delete(0, "end")
            w.insert(0, value)

    def _load_sample(self) -> None:
        for key, _, _ in FIELDS:
            self._set(key, str(SAMPLE.get(key, "")))
        if CUSTOMER_LOGO_SAMPLE.exists():
            self.logo_path.set(str(CUSTOMER_LOGO_SAMPLE))
        self.preset_name.set("Pacific Canbriam")
        self.status.set("Sample loaded")

    def _clear_shipment(self) -> None:
        for key in (
            "po_num",
            "project",
            "packing_slip",
            "sales_order",
            "pallet_num",
            "pallet_of",
            "box_num",
            "box_of",
            "special_instructions",
        ):
            self._set(key, "")
        self.status.set("Shipment fields cleared")

    def _clear(self) -> None:
        for key, _, _ in FIELDS:
            self._set(key, "")
        self.logo_path.set("")
        self.preset_name.set("")
        self.status.set("Form cleared")

    def _save(self) -> None:
        data = {key: self._get(key) for key, _, _ in FIELDS}
        if not data.get("ship_to") and not data.get("customer"):
            messagebox.showwarning(
                "Missing info", "Enter at least Customer or Ship To before saving."
            )
            return

        logo = Path(self.logo_path.get()) if self.logo_path.get() else None
        if logo and not logo.exists():
            messagebox.showerror("Logo", f"Logo not found:\n{logo}")
            return

        stem = data.get("customer") or data.get("ship_to") or "label"
        slip = data.get("packing_slip") or "draft"
        out = self.out_dir / f"Shipping Label - {safe_name(stem)} - {safe_name(slip)}.pdf"

        self.status.set("Generating PDF…")
        self.update_idletasks()
        try:
            path = build_pdf(sample=data, out_path=out, customer_logo=logo)
        except Exception as exc:  # noqa: BLE001
            self.status.set("Generate failed")
            messagebox.showerror("Generate failed", str(exc))
            return

        self.status.set(f"Saved {path.name}")
        messagebox.showinfo("Saved", f"Print-ready label:\n{path}")
        try:
            os.startfile(path)  # type: ignore[attr-defined]
        except OSError:
            pass

    # ----- shortcut -----

    def _check_for_update(self) -> None:
        if self._update_busy:
            return
        self._update_busy = True
        self.status.set("Checking for updates…")
        self.update_idletasks()
        try:
            result = app_update.check_for_update(__version__)
        except Exception as exc:
            self._update_busy = False
            self.status.set("Ready")
            if messagebox.askyesno(
                "Update",
                f"Could not check for updates:\n{exc}\n\nOpen releases page in browser?",
            ):
                app_update.open_releases_page()
            return

        latest = result.latest
        tag = latest.tag_name or latest.name or "latest"

        if result.missing_windows_asset:
            self._update_busy = False
            self.status.set("Ready")
            if messagebox.askyesno(
                "Update",
                f"Latest {tag} has no Windows zip yet.\n\nOpen releases page?",
            ):
                app_update.open_releases_page(latest)
            return

        if not result.update_available:
            self._update_busy = False
            self.status.set("Ready")
            messagebox.showinfo(
                "Update",
                f"You are up to date.\n\nInstalled: {__version__}\nLatest: {tag}",
            )
            return

        if not messagebox.askyesno(
            "Update available",
            f"A newer build is available:\n"
            f"{latest.name or tag}\n\n"
            f"Installed: {__version__}\n"
            f"Package: {app_update.WINDOWS_ZIP_ASSET}\n\n"
            "Download to your user updates folder?\n"
            "(No admin — replace your portable folder when ready.)",
        ):
            self._update_busy = False
            self.status.set("Ready")
            return

        self.status.set("Downloading update…")
        self.update_idletasks()

        def _progress(p: float) -> None:
            self.status.set(f"Downloading… {int(p * 100)}%")
            self.update_idletasks()

        try:
            extract_dir = app_update.download_windows_update(
                latest, on_progress=_progress
            )
        except Exception as exc:
            self._update_busy = False
            self.status.set("Ready")
            if messagebox.askyesno(
                "Update",
                f"Download failed:\n{exc}\n\nOpen releases page instead?",
            ):
                app_update.open_releases_page(latest)
            return

        self._update_busy = False
        self.status.set("Update downloaded")
        open_folder = messagebox.askyesno(
            "Update downloaded",
            f"Downloaded and extracted to:\n{extract_dir}\n\n"
            "Close this app, then copy the new “Swift Shipping Label” folder "
            "over your current portable folder (or run the new exe).\n\n"
            "Your presets/logos stay in %LOCALAPPDATA%\\SwiftShippingLabel\\.\n\n"
            "Open the updates folder now?",
        )
        if open_folder:
            app_update.open_folder(extract_dir)
        self.status.set("Ready")

    def _create_shortcut(self) -> None:
        desktop = user_desktop()
        desktop.mkdir(parents=True, exist_ok=True)
        link = desktop / "Swift Shipping Label.lnk"

        if getattr(sys, "frozen", False):
            target = Path(sys.executable).resolve()
            work = str(target.parent)
            icon = str(target)
        else:
            candidates = [
                self.exe_dir
                / "dist"
                / "Swift Shipping Label"
                / "Swift Shipping Label.exe",
                self.exe_dir / "dist" / "Swift Shipping Label.exe",
            ]
            exe = next((p for p in candidates if p.exists()), None)
            if exe:
                target = exe
                work = str(exe.parent)
                icon = str(exe)
            else:
                target = Path(sys.executable).resolve()
                script = Path(__file__).resolve()
                work = str(script.parent)
                ps = (
                    "$ws = New-Object -ComObject WScript.Shell\n"
                    f"$sc = $ws.CreateShortcut({str(link)!r})\n"
                    f"$sc.TargetPath = {str(target)!r}\n"
                    f"$sc.Arguments = {str(script)!r}\n"
                    f"$sc.WorkingDirectory = {work!r}\n"
                    "$sc.WindowStyle = 1\n"
                    "$sc.Description = 'Swift Supply Shipping Label Generator'\n"
                    "$sc.Save()\n"
                )
                try:
                    subprocess.run(
                        [
                            "powershell",
                            "-NoProfile",
                            "-ExecutionPolicy",
                            "Bypass",
                            "-Command",
                            ps,
                        ],
                        check=True,
                        capture_output=True,
                        text=True,
                    )
                except subprocess.CalledProcessError as exc:
                    messagebox.showerror("Shortcut", exc.stderr or str(exc))
                    return
                messagebox.showinfo(
                    "Shortcut created",
                    f"Desktop shortcut:\n{link}\n\n"
                    "Tip: run build_exe.ps1 for a portable .exe, then recreate the shortcut.",
                )
                return

        ps = (
            "$ws = New-Object -ComObject WScript.Shell\n"
            f"$sc = $ws.CreateShortcut({str(link)!r})\n"
            f"$sc.TargetPath = {str(target)!r}\n"
            f"$sc.WorkingDirectory = {work!r}\n"
            f"$sc.IconLocation = {icon!r}\n"
            "$sc.WindowStyle = 1\n"
            "$sc.Description = 'Swift Supply Shipping Label Generator'\n"
            "$sc.Save()\n"
        )
        try:
            subprocess.run(
                [
                    "powershell",
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-Command",
                    ps,
                ],
                check=True,
                capture_output=True,
                text=True,
            )
        except subprocess.CalledProcessError as exc:
            messagebox.showerror("Shortcut", exc.stderr or str(exc))
            return
        messagebox.showinfo("Shortcut created", f"Desktop shortcut:\n{link}")


def main() -> None:
    ensure_data_dirs()
    app = FillApp()
    saved = app.presets.get("logo_folder")
    if saved and Path(saved).is_dir():
        app.logo_folder.set(saved)
        app.logo_dir = Path(saved)
        app._refresh_logo_list()
    app.mainloop()


if __name__ == "__main__":
    main()
