"""CLI: python -m tools.logo_vectorizer --input logo.png --output out.svg [--fill #HEX] [--qa] [--ai]"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.logo_vectorizer.ai_advisors import AIConfig  # noqa: E402
from tools.logo_vectorizer.ai_advisors.orchestrator import resolve_providers  # noqa: E402
from tools.logo_vectorizer.ensemble import vectorize_ensemble_file  # noqa: E402
from tools.logo_vectorizer.env_loader import load_env  # noqa: E402
from tools.logo_vectorizer.qa import verify_p_counters  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Ensemble vectorizer: multi-backend race + scoring + optional AI advisors."
    )
    parser.add_argument("--input", "-i", type=Path, required=True, help="Input transparent PNG")
    parser.add_argument("--output", "-o", type=Path, help="Output SVG path")
    parser.add_argument("--fill", default="#FFFFFF", help="SVG fill color (default #FFFFFF)")
    parser.add_argument("--qa", action="store_true", help="Run P-counter QA + overlay crop")
    parser.add_argument("--qa-crop", type=Path, help="Save SUPPLY P zoom QA crop PNG")
    parser.add_argument("--no-cache", action="store_true", help="Skip .cache/ param memory")
    parser.add_argument("--ai", action="store_true", help="Enable vision AI advisors (env API keys)")
    parser.add_argument(
        "--ai-providers",
        default="gemini,claude,openai",
        help="Comma-separated AI providers to use (default: all available)",
    )
    args = parser.parse_args()

    if not args.input.is_file():
        print(f"Input not found: {args.input}", file=sys.stderr)
        return 1

    loaded = load_env()
    if loaded:
        print(f"Loaded env from: {', '.join(str(p.name) for p in loaded)}", file=sys.stderr)

    ai_cfg = AIConfig(
        enabled=args.ai or bool(resolve_providers(["gemini", "claude", "openai"])),
        providers=[p.strip() for p in args.ai_providers.split(",") if p.strip()],
    )
    if args.ai and not ai_cfg.enabled:
        print("[ai] --ai set but no API keys found in env", file=sys.stderr)

    out = args.output or args.input.with_suffix(".svg")
    result = vectorize_ensemble_file(
        args.input,
        out,
        fill_hex=args.fill,
        use_cache=not args.no_cache,
        ai=ai_cfg,
    )
    sc = result.score
    print(
        f"Wrote {out} ({out.stat().st_size} bytes)\n"
        f"  winner: {result.method} ({result.candidates_tried} candidates)\n"
        f"  preprocess: {result.preprocess.key()}\n"
        f"  contours={result.contour_count} holes={result.hole_count}\n"
        f"  score={sc.total:.3f} iou={sc.alpha_iou:.3f} ssim={sc.ssim:.3f} "
        f"edge={sc.edge_score:.3f} p_hollow={sc.p_hollow:.3f}"
    )
    if result.ai.providers_used:
        print(f"  AI providers: {', '.join(result.ai.providers_used)}")
    if result.ai.hints and result.ai.hints.recommended_backends:
        print(f"  AI backends hint: {result.ai.hints.recommended_backends}")

    if args.qa:
        qa_crop = args.qa_crop or out.with_name(out.stem + "_qa_p_crop.png")
        report = verify_p_counters(out, args.input, qa_crop_path=qa_crop)
        print("QA:", report)
        if not report.get("ok"):
            return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
