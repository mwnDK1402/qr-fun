package qrcodegen

import "core:c"

// --- Enums (as defined in header) ---

Ecc :: enum c.int {
    LOW      = 0,
    MEDIUM   = 1,
    QUARTILE = 2,
    HIGH     = 3,
}

Mask :: enum c.int {
    AUTO = -1,
    M0   = 0,
    M1   = 1,
    M2   = 2,
    M3   = 3,
    M4   = 4,
    M5   = 5,
    M6   = 6,
    M7   = 7,
}

// --- Constants ---

VERSION_MIN :: 1
VERSION_MAX :: 40

// The maximum buffer size needed for any QR version (version 40)
BUFFER_LEN_MAX :: ((40 * 4 + 17) * (40 * 4 + 17) + 7) / 8 + 1  // = 3918

// Convenience macro: buffer size for a specific version
buffer_len_for_version :: #force_inline proc(n: c.int) -> c.int {
    return ((n * 4 + 17) * (n * 4 + 17) + 7) / 8 + 1
}

// --- Link to static library ---

when ODIN_OS == .Windows {
    // Adjust the path relative to the location of this file.
    // If your .odin file is in the project root and lib/ is next to it:
    foreign import qrcode_lib "../lib/qrcodegen.lib"
    // Alternatively, use a full absolute path or a system path.
}

// --- Foreign function declarations ---

@(default_calling_convention = "c")
@(link_prefix = "qrcodegen_")
foreign qrcode_lib {
    // High-level encode text
    encodeText :: proc(
        text: cstring,
        tempBuffer: [^]u8,
        qrcode: [^]u8,
        ecl: Ecc,
        minVersion, maxVersion: c.int,
        mask: Mask,
        boostEcl: bool,
    ) -> bool ---

    // Extract size and module
    getSize   :: proc(qrcode: [^]u8) -> c.int ---
    getModule :: proc(qrcode: [^]u8, x: c.int, y: c.int) -> bool ---

    // Optional: encode binary (if you need it)
    encodeBinary :: proc(
        dataAndTemp: [^]u8,
        dataLen: c.size_t,
        qrcode: [^]u8,
        ecl: Ecc,
        minVersion, maxVersion: c.int,
        mask: Mask,
        boostEcl: bool,
    ) -> bool ---
}
