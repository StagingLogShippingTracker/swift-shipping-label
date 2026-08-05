//! Core recreate stages (MVP).

use base64::{engine::general_purpose::STANDARD as B64, Engine};
use image::{DynamicImage, ImageBuffer, ImageFormat, Rgba, RgbaImage};
use imageproc::contours::{find_contours, BorderType, Contour};
use serde::Serialize;
use thiserror::Error;

const ALPHA_HAS_HOLES: u8 = 32;
const FG_ALPHA: u8 = 40;
const CORNER_TOLERANCE: i16 = 26;

#[derive(Debug, Error)]
pub enum RecreateError {
    #[error("decode failed: {0}")]
    Decode(String),
    #[error("no foreground pixels after background strip")]
    NoForeground,
    #[error("encode failed: {0}")]
    Encode(String),
}

#[derive(Debug, Clone)]
pub struct RecreateOptions {
    pub max_colors: usize,
    pub render_width: u32,
}

impl Default for RecreateOptions {
    fn default() -> Self {
        Self {
            max_colors: 6,
            render_width: 2000,
        }
    }
}

#[derive(Debug, Serialize)]
pub struct RecreateOutput {
    pub svg: String,
    pub png_base64: String,
    pub palette_hex: Vec<String>,
    pub section_count: usize,
    pub bg_stripped: bool,
    pub source_width: u32,
    pub source_height: u32,
    pub render_width: u32,
    /// Always `native_rust_mvp` until Bezier parity lands.
    pub backend: &'static str,
    pub notes: Vec<String>,
}

pub fn recreate_from_bytes(
    bytes: &[u8],
    opts: &RecreateOptions,
) -> Result<RecreateOutput, RecreateError> {
    let img = image::load_from_memory(bytes)
        .map_err(|e| RecreateError::Decode(e.to_string()))?
        .to_rgba8();
    let (sw, sh) = img.dimensions();
    let mut notes = Vec::new();

    let (stripped, bg_stripped) = strip_background(&img);
    notes.push(if bg_stripped {
        "background stripped (corner flood)".into()
    } else {
        "kept existing transparency / no strip".into()
    });

    let (palette, labels) = cluster_palette(&stripped, opts.max_colors)?;
    if palette.is_empty() {
        return Err(RecreateError::NoForeground);
    }
    notes.push(format!(
        "palette: {}",
        palette
            .iter()
            .map(|c| hex_rgb(*c))
            .collect::<Vec<_>>()
            .join(", ")
    ));
    notes.push(
        "trace: contour polylines (MVP) — Bezier port pending".into(),
    );

    let svg = compose_sectional_svg(&labels, &palette, sw, sh);
    let png = rasterize_palette(&labels, &palette, opts.render_width);
    let png_b64 = encode_png_b64(&png)?;

    Ok(RecreateOutput {
        svg,
        png_base64: png_b64,
        palette_hex: palette.iter().map(|c| hex_rgb(*c)).collect(),
        section_count: palette.len(),
        bg_stripped,
        source_width: sw,
        source_height: sh,
        render_width: opts.render_width,
        backend: "native_rust_mvp",
        notes,
    })
}

fn hex_rgb(c: [u8; 3]) -> String {
    format!("#{:02X}{:02X}{:02X}", c[0], c[1], c[2])
}

fn border_has_transparency(img: &RgbaImage) -> bool {
    let (w, h) = img.dimensions();
    if w < 4 || h < 4 {
        return false;
    }
    let mut transparent = 0u32;
    let mut total = 0u32;
    for x in 0..w {
        total += 2;
        if img.get_pixel(x, 0)[3] < ALPHA_HAS_HOLES {
            transparent += 1;
        }
        if img.get_pixel(x, h - 1)[3] < ALPHA_HAS_HOLES {
            transparent += 1;
        }
    }
    for y in 1..h - 1 {
        total += 2;
        if img.get_pixel(0, y)[3] < ALPHA_HAS_HOLES {
            transparent += 1;
        }
        if img.get_pixel(w - 1, y)[3] < ALPHA_HAS_HOLES {
            transparent += 1;
        }
    }
    (transparent as f32 / total as f32) >= 0.35
}

/// Corner flood-fill bg strip (conservative; preserves interior white/black).
fn strip_background(img: &RgbaImage) -> (RgbaImage, bool) {
    if border_has_transparency(img) {
        return (img.clone(), false);
    }
    let (w, h) = img.dimensions();
    let corners = [
        (0u32, 0u32),
        (w - 1, 0),
        (0, h - 1),
        (w - 1, h - 1),
    ];
    let mut corner_rgb: Vec<[i16; 3]> = corners
        .iter()
        .map(|&(x, y)| {
            let p = img.get_pixel(x, y);
            [p[0] as i16, p[1] as i16, p[2] as i16]
        })
        .collect();
    corner_rgb.sort_by_key(|c| (c[0] as i32) + (c[1] as i32) + (c[2] as i32));
    let median = corner_rgb[corner_rgb.len() / 2];
    let agree = corner_rgb
        .iter()
        .filter(|c| {
            ((c[0] - median[0]).abs() + (c[1] - median[1]).abs() + (c[2] - median[2]).abs())
                <= CORNER_TOLERANCE * 2
        })
        .count();
    if agree < 3 {
        // Corners disagree — leave alone rather than punching holes.
        return (img.clone(), false);
    }

    let mut visited = vec![false; (w * h) as usize];
    let mut stack: Vec<(u32, u32)> = corners.to_vec();
    let mut bg_count = 0u32;

    while let Some((x, y)) = stack.pop() {
        let idx = (y * w + x) as usize;
        if visited[idx] {
            continue;
        }
        visited[idx] = true;
        let p = img.get_pixel(x, y);
        let d = (p[0] as i16 - median[0]).abs()
            + (p[1] as i16 - median[1]).abs()
            + (p[2] as i16 - median[2]).abs();
        if d > CORNER_TOLERANCE {
            continue;
        }
        bg_count += 1;
        if x > 0 {
            stack.push((x - 1, y));
        }
        if x + 1 < w {
            stack.push((x + 1, y));
        }
        if y > 0 {
            stack.push((x, y - 1));
        }
        if y + 1 < h {
            stack.push((x, y + 1));
        }
    }

    // Only strip if a meaningful outer region was hit.
    let area = (w * h) as f32;
    if (bg_count as f32 / area) < 0.02 {
        return (img.clone(), false);
    }

    let mut out = img.clone();
    for y in 0..h {
        for x in 0..w {
            let idx = (y * w + x) as usize;
            if !visited[idx] {
                continue;
            }
            let p = img.get_pixel(x, y);
            let d = (p[0] as i16 - median[0]).abs()
                + (p[1] as i16 - median[1]).abs()
                + (p[2] as i16 - median[2]).abs();
            if d <= CORNER_TOLERANCE {
                out.put_pixel(x, y, Rgba([0, 0, 0, 0]));
            }
        }
    }
    (out, true)
}

fn cluster_palette(
    img: &RgbaImage,
    max_colors: usize,
) -> Result<(Vec<[u8; 3]>, ImageBuffer<image::Luma<u8>, Vec<u8>>), RecreateError> {
    let (w, h) = img.dimensions();
    let mut samples: Vec<[f32; 3]> = Vec::new();
    for p in img.pixels() {
        if p[3] < FG_ALPHA {
            continue;
        }
        samples.push([p[0] as f32, p[1] as f32, p[2] as f32]);
    }
    if samples.is_empty() {
        return Err(RecreateError::NoForeground);
    }

    // Stratified subsample for k-means speed.
    const MAX_SAMPLES: usize = 50_000;
    if samples.len() > MAX_SAMPLES {
        let step = samples.len() / MAX_SAMPLES;
        samples = samples.into_iter().step_by(step.max(1)).collect();
    }

    let k = max_colors.clamp(1, samples.len().min(12));
    let (centroids, _) = kmeans(&samples, k, 12);

    // Merge near-duplicate centroids (Euclidean < 24).
    let mut merged: Vec<[f32; 3]> = Vec::new();
    let mut remap = vec![0usize; centroids.len()];
    for (i, c) in centroids.iter().enumerate() {
        let mut found = None;
        for (j, m) in merged.iter().enumerate() {
            let d = dist3(c, m);
            if d < 24.0 {
                found = Some(j);
                break;
            }
        }
        if let Some(j) = found {
            remap[i] = j;
            // Running mean toward sample (simple).
            for t in 0..3 {
                merged[j][t] = (merged[j][t] + c[t]) * 0.5;
            }
        } else {
            remap[i] = merged.len();
            merged.push(*c);
        }
    }

    // Assign every opaque pixel.
    let mut labels = ImageBuffer::from_pixel(w, h, image::Luma([0u8]));
    let mut counts = vec![0u32; merged.len()];
    for y in 0..h {
        for x in 0..w {
            let p = img.get_pixel(x, y);
            if p[3] < FG_ALPHA {
                continue;
            }
            let rgb = [p[0] as f32, p[1] as f32, p[2] as f32];
            let mut best = 0usize;
            let mut best_d = f32::MAX;
            for (i, c) in merged.iter().enumerate() {
                let d = dist3(&rgb, c);
                if d < best_d {
                    best_d = d;
                    best = i;
                }
            }
            labels.put_pixel(x, y, image::Luma([(best + 1) as u8]));
            counts[best] += 1;
        }
    }

    // Drop tiny clusters (< 1% of fg) by remapping to nearest large.
    let total_fg: u32 = counts.iter().sum();
    let min_count = ((total_fg as f32) * 0.01).max(8.0) as u32;
    let keep: Vec<usize> = counts
        .iter()
        .enumerate()
        .filter(|(_, &n)| n >= min_count)
        .map(|(i, _)| i)
        .collect();
    if keep.is_empty() {
        return Err(RecreateError::NoForeground);
    }

    let palette: Vec<[u8; 3]> = keep
        .iter()
        .map(|&i| {
            [
                merged[i][0].round().clamp(0.0, 255.0) as u8,
                merged[i][1].round().clamp(0.0, 255.0) as u8,
                merged[i][2].round().clamp(0.0, 255.0) as u8,
            ]
        })
        .collect();

    // Rebuild labels with compacted ids (1..N), largest-first order.
    let mut order: Vec<usize> = (0..keep.len()).collect();
    order.sort_by_key(|&i| std::cmp::Reverse(counts[keep[i]]));
    let mut compact = ImageBuffer::from_pixel(w, h, image::Luma([0u8]));
    let mut ordered_palette = Vec::with_capacity(palette.len());
    for (new_i, &old_i) in order.iter().enumerate() {
        ordered_palette.push(palette[old_i]);
        let old_label = (keep[old_i] + 1) as u8;
        let new_label = (new_i + 1) as u8;
        for (x, y, pix) in labels.enumerate_pixels() {
            if pix[0] == old_label {
                compact.put_pixel(x, y, image::Luma([new_label]));
            }
        }
    }

    Ok((ordered_palette, compact))
}

fn dist3(a: &[f32; 3], b: &[f32; 3]) -> f32 {
    let dr = a[0] - b[0];
    let dg = a[1] - b[1];
    let db = a[2] - b[2];
    (dr * dr + dg * dg + db * db).sqrt()
}

fn kmeans(samples: &[[f32; 3]], k: usize, iters: usize) -> (Vec<[f32; 3]>, Vec<usize>) {
    let n = samples.len();
    let k = k.min(n).max(1);
    // Init: stride through samples.
    let mut centroids: Vec<[f32; 3]> = (0..k)
        .map(|i| samples[i * n / k])
        .collect();
    let mut labels = vec![0usize; n];

    for _ in 0..iters {
        for (i, s) in samples.iter().enumerate() {
            let mut best = 0usize;
            let mut best_d = f32::MAX;
            for (j, c) in centroids.iter().enumerate() {
                let d = dist3(s, c);
                if d < best_d {
                    best_d = d;
                    best = j;
                }
            }
            labels[i] = best;
        }
        let mut sums = vec![[0.0f32; 3]; k];
        let mut counts = vec![0u32; k];
        for (i, s) in samples.iter().enumerate() {
            let lab = labels[i];
            sums[lab][0] += s[0];
            sums[lab][1] += s[1];
            sums[lab][2] += s[2];
            counts[lab] += 1;
        }
        for j in 0..k {
            if counts[j] == 0 {
                continue;
            }
            let c = counts[j] as f32;
            centroids[j] = [sums[j][0] / c, sums[j][1] / c, sums[j][2] / c];
        }
    }
    (centroids, labels)
}

fn compose_sectional_svg(
    labels: &ImageBuffer<image::Luma<u8>, Vec<u8>>,
    palette: &[[u8; 3]],
    w: u32,
    h: u32,
) -> String {
    let mut parts = Vec::new();
    parts.push(format!(
        r#"<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" style="background:transparent">"#
    ));

    for (i, rgb) in palette.iter().enumerate() {
        let label = (i + 1) as u8;
        let mask = label_to_mask(labels, label);
        let contours = find_contours::<u8>(&mask);
        let fill = hex_rgb(*rgb);
        let name = format!("color-{}", fill.trim_start_matches('#').to_lowercase());
        let mut d = String::new();
        for contour in contours {
            if contour.points.len() < 3 {
                continue;
            }
            // Skip tiny speckles.
            if contour.points.len() < 8 && contour.border_type == BorderType::Outer {
                // still allow holes; tiny outers drop
                if contour.points.len() < 6 {
                    continue;
                }
            }
            append_path_d(&mut d, &contour);
        }
        if d.is_empty() {
            continue;
        }
        parts.push(format!(
            r#"<g id="{name}"><path fill="{fill}" fill-rule="evenodd" d="{d}"/></g>"#
        ));
    }
    parts.push("</svg>".into());
    parts.join("")
}

fn label_to_mask(
    labels: &ImageBuffer<image::Luma<u8>, Vec<u8>>,
    label: u8,
) -> ImageBuffer<image::Luma<u8>, Vec<u8>> {
    let (w, h) = labels.dimensions();
    let mut mask = ImageBuffer::new(w, h);
    for (x, y, p) in labels.enumerate_pixels() {
        let v = if p[0] == label { 255u8 } else { 0u8 };
        mask.put_pixel(x, y, image::Luma([v]));
    }
    mask
}

fn append_path_d(out: &mut String, contour: &Contour<u8>) {
    let pts = &contour.points;
    if pts.is_empty() {
        return;
    }
    // Decimate long contours for compact MVP SVG.
    let step = ((pts.len() / 400).max(1)) as usize;
    let first = &pts[0];
    out.push_str(&format!("M{:.1} {:.1}", first.x as f32, first.y as f32));
    let mut i = step;
    while i < pts.len() {
        let p = &pts[i];
        out.push_str(&format!("L{:.1} {:.1}", p.x as f32, p.y as f32));
        i += step;
    }
    out.push('Z');
}

fn rasterize_palette(
    labels: &ImageBuffer<image::Luma<u8>, Vec<u8>>,
    palette: &[[u8; 3]],
    render_width: u32,
) -> RgbaImage {
    let (sw, sh) = labels.dimensions();
    let scale = render_width as f32 / sw.max(1) as f32;
    let dw = render_width.max(1);
    let dh = ((sh as f32) * scale).round().max(1.0) as u32;
    let mut out = ImageBuffer::from_pixel(dw, dh, Rgba([0, 0, 0, 0]));
    for y in 0..dh {
        let sy = ((y as f32) / scale).floor().clamp(0.0, (sh - 1) as f32) as u32;
        for x in 0..dw {
            let sx = ((x as f32) / scale).floor().clamp(0.0, (sw - 1) as f32) as u32;
            let lab = labels.get_pixel(sx, sy)[0];
            if lab == 0 {
                continue;
            }
            let idx = (lab as usize) - 1;
            if idx >= palette.len() {
                continue;
            }
            let c = palette[idx];
            out.put_pixel(x, y, Rgba([c[0], c[1], c[2], 255]));
        }
    }
    out
}

fn encode_png_b64(img: &RgbaImage) -> Result<String, RecreateError> {
    let mut buf = Vec::new();
    let dyn_img = DynamicImage::ImageRgba8(img.clone());
    dyn_img
        .write_to(&mut std::io::Cursor::new(&mut buf), ImageFormat::Png)
        .map_err(|e| RecreateError::Encode(e.to_string()))?;
    Ok(B64.encode(buf))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recreates_solid_on_white() {
        let mut img = RgbaImage::from_pixel(64, 64, Rgba([255, 255, 255, 255]));
        for y in 16..48 {
            for x in 16..48 {
                img.put_pixel(x, y, Rgba([200, 40, 40, 255]));
            }
        }
        let mut png = Vec::new();
        DynamicImage::ImageRgba8(img)
            .write_to(&mut std::io::Cursor::new(&mut png), ImageFormat::Png)
            .unwrap();
        let out = recreate_from_bytes(
            &png,
            &RecreateOptions {
                max_colors: 4,
                render_width: 128,
            },
        )
        .expect("recreate");
        assert!(out.section_count >= 1);
        assert!(!out.png_base64.is_empty());
        assert!(out.svg.contains("<svg"));
        assert!(out.bg_stripped);
    }
}
