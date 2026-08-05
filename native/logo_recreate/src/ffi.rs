//! C ABI for Flutter `dart:ffi`.
//!
//! ```c
//! // Returns heap UTF-8 JSON. Caller must free with logo_recreate_free.
//! char *logo_recreate_png(
//!     const uint8_t *data, size_t len,
//!     int32_t max_colors, int32_t render_width);
//! void logo_recreate_free(char *ptr);
//! ```
//!
//! Success JSON fields match the cloud/Python contract used by Dart:
//! `svg`, `png_base64`, `palette_hex`, `section_count`, `bg_stripped`,
//! `source_width`, `source_height`, `render_width`, `backend`, `notes`.
//!
//! Failure JSON: `{ "error": "..." }`.

use std::ffi::CString;
use std::os::raw::c_char;
use std::slice;

use crate::pipeline::{recreate_from_bytes, RecreateOptions};

fn json_error(msg: impl AsRef<str>) -> *mut c_char {
    let payload = serde_json::json!({ "error": msg.as_ref() }).to_string();
    CString::new(payload)
        .unwrap_or_else(|_| CString::new("{\"error\":\"encode\"}").unwrap())
        .into_raw()
}

/// Recreate a logo from encoded image bytes (PNG/JPEG/…).
///
/// # Safety
/// `data` must point to `len` readable bytes (or be null when `len == 0`).
#[no_mangle]
pub unsafe extern "C" fn logo_recreate_png(
    data: *const u8,
    len: usize,
    max_colors: i32,
    render_width: i32,
) -> *mut c_char {
    if data.is_null() || len == 0 {
        return json_error("empty image bytes");
    }
    let bytes = slice::from_raw_parts(data, len);
    let opts = RecreateOptions {
        max_colors: max_colors.clamp(1, 16) as usize,
        render_width: render_width.clamp(64, 4096) as u32,
    };
    match recreate_from_bytes(bytes, &opts) {
        Ok(out) => {
            let json = match serde_json::to_string(&out) {
                Ok(s) => s,
                Err(e) => return json_error(format!("json encode: {e}")),
            };
            CString::new(json)
                .unwrap_or_else(|_| CString::new("{\"error\":\"nul in json\"}").unwrap())
                .into_raw()
        }
        Err(e) => json_error(e.to_string()),
    }
}

/// Free a string returned by [`logo_recreate_png`].
///
/// # Safety
/// `ptr` must be null or a pointer previously returned by this crate.
#[no_mangle]
pub unsafe extern "C" fn logo_recreate_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    drop(CString::from_raw(ptr));
}
