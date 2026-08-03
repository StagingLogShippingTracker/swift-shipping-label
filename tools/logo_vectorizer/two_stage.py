"""Two-stage brand vectorization: embed-PNG (Stage A) + geometric polish (Stage B)."""

from __future__ import annotations

import tempfile
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

from .embed import write_embedded_png_svg
from .geometric_polish import PolishConfig, polish_png
from .qa import counter_hollow_score, supply_p_ranges, verify_p_counters
from .score import ScoreReport, score_candidate, trace_aligned_iou
from .backends import TraceCandidate

# QA gates for accepting polished path SVG over embed fallback
MIN_ALPHA_IOU = 0.885
MIN_P_HOLLOW = 0.65
REF_P_HOLLOW_MARGIN = 0.02  # allow tiny regression vs source PNG counter score


def _reference_p_hollow(ref_img: Image.Image, *, is_orange: bool) -> float:
    runs = supply_p_ranges(ref_img)
    if len(runs) < 4:
        return 0.0
    ratios: list[float] = []
    for idx in (2, 3):
        if idx < len(runs):
            r, _, _ = counter_hollow_score(ref_img, runs[idx], is_orange=is_orange)
            ratios.append(r)
    return sum(ratios) / len(ratios) if ratios else 0.0


@dataclass
class TwoStageResult:
    output_svg: Path
    stage: str  # "polished" | "embed"
    passed_qa: bool
    score: ScoreReport | None
    p_qa: dict[str, object] | None
    contour_count: int
    hole_count: int
    embed_svg: Path | None = None


def _score_polished(svg: str, ref_img: Image.Image, *, is_orange: bool, holes: int) -> ScoreReport | None:
    cand = TraceCandidate(
        svg=svg,
        backend="geometric-polish",
        preprocess=PolishConfig().preprocess(),
        contour_count=0,
        hole_count=holes,
    )
    item = score_candidate(cand, ref_img, is_orange=is_orange)
    if item is None:
        return None
    report = item.report
    # Replace raw PNG-alpha IoU with trace-aligned IoU (fair for vector QA)
    if item.rendered is not None:
        aligned = trace_aligned_iou(ref_img, item.rendered, cfg=PolishConfig().preprocess(), is_orange=is_orange)
        report = ScoreReport(
            total=report.total - 0.30 * report.alpha_iou + 0.30 * aligned,
            alpha_iou=aligned,
            edge_score=report.edge_score,
            ssim=report.ssim,
            p_hollow=report.p_hollow,
            hole_bonus=report.hole_bonus,
            details={**report.details, "trace_aligned_iou": aligned},
        )
    return report


def run_two_stage(
    png_path: Path,
    output_svg: Path,
    *,
    fill_hex: str = "#FFFFFF",
    qa: bool = True,
    qa_crop_path: Path | None = None,
    min_alpha_iou: float = MIN_ALPHA_IOU,
    min_p_hollow: float = MIN_P_HOLLOW,
    keep_embed_on_fail: bool = True,
) -> TwoStageResult:
    """
    Stage A: write embed-PNG SVG (pixel reference).
    Stage B: geometric polish → path SVG.
    Only overwrite *output_svg* with polished paths when QA passes; otherwise keep embed.
    """
    png_path = Path(png_path)
    output_svg = Path(output_svg)
    output_svg.parent.mkdir(parents=True, exist_ok=True)

    ref_img = Image.open(png_path).convert("RGBA")
    is_orange = "orange" in png_path.name.lower()

    with tempfile.TemporaryDirectory() as tmp:
        embed_path = Path(tmp) / f"{output_svg.stem}_embed.svg"
        write_embedded_png_svg(png_path, embed_path)

        polish_cfg = PolishConfig(fill_hex=fill_hex)
        polished = polish_png(ref_img, polish_cfg)

        score = _score_polished(polished.svg, ref_img, is_orange=is_orange, holes=polished.hole_count)
        p_qa: dict[str, object] | None = None

        passed = False
        ref_p = _reference_p_hollow(ref_img, is_orange=is_orange)
        p_floor = max(min_p_hollow, ref_p - REF_P_HOLLOW_MARGIN)
        if score is not None:
            passed = score.alpha_iou >= min_alpha_iou and score.p_hollow >= p_floor

        if qa:
            polished_tmp = Path(tmp) / "polished.svg"
            polished_tmp.write_text(polished.svg, encoding="utf-8")
            p_qa = verify_p_counters(
                polished_tmp,
                png_path,
                min_hollow_ratio=p_floor,
                qa_crop_path=qa_crop_path,
            )
            if not p_qa.get("ok"):
                passed = False

        if passed:
            output_svg.write_text(polished.svg, encoding="utf-8")
            stage = "polished"
        else:
            if keep_embed_on_fail:
                output_svg.write_text(embed_path.read_text(encoding="utf-8"), encoding="utf-8")
            stage = "embed"

        return TwoStageResult(
            output_svg=output_svg,
            stage=stage,
            passed_qa=passed,
            score=score,
            p_qa=p_qa,
            contour_count=polished.contour_count,
            hole_count=polished.hole_count,
            embed_svg=embed_path if not passed else None,
        )


def run_two_stage_file(
    input_png: Path,
    output_svg: Path,
    *,
    fill_hex: str = "#FFFFFF",
    qa: bool = False,
    qa_crop: Path | None = None,
) -> TwoStageResult:
    return run_two_stage(
        input_png,
        output_svg,
        fill_hex=fill_hex,
        qa=qa,
        qa_crop_path=qa_crop,
    )
