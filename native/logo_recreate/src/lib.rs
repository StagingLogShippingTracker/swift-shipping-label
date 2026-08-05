//! On-device logo Recreate pipeline (Rust).
//!
//! Ports the high-level stages of `tools/logo_vectorizer/customer_recreate.py`:
//! background strip → palette clustering → per-color sectional paths → SVG + PNG.
//!
//! **MVP fidelity:** sectional paths are contour polylines (not the Python
//! manual Bezier fitter). PNG is a clean posterized remaster from the palette
//! masks. Bezier/sectional parity with `manual_trace.py` is a follow-up sprint.
//!
//! C ABI entrypoints live in [`ffi`] for Flutter `dart:ffi` / Android JNI.

mod ffi;
mod pipeline;

pub use ffi::{logo_recreate_free, logo_recreate_png};
pub use pipeline::{recreate_from_bytes, RecreateError, RecreateOptions, RecreateOutput};
