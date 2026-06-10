package demos

import "core:fmt"
import qr "../qrcodegen"

main :: proc() {
	text :: "Hello, world!"
	ecc :: qr.Ecc.LOW

	qrcode : [qr.BUFFER_LEN_MAX]u8
	tmp_buf : [qr.BUFFER_LEN_MAX]u8
	ok := qr.encodeText(text, raw_data(tmp_buf[:]), raw_data(qrcode[:]), ecc, qr.VERSION_MIN, qr.VERSION_MAX, qr.Mask.AUTO, true)
	if ok {
		print_qr(raw_data(qrcode[:]))
	}
}

print_qr :: proc(qrcode: [^]u8) {
	size := qr.getSize(qrcode)
	border :: 4

	for y in -border..<size+border {
		for x in -border..<size+border {
			fmt.print(qr.getModule(qrcode, x, y) ? "##" : "  ")
		}
		fmt.println()
	}
}

// static void doBasicDemo(void) {
// 	const char *text = "Hello, world!";                // User-supplied text
// 	enum qrcodegen_Ecc errCorLvl = qrcodegen_Ecc_LOW;  // Error correction level

// 	// Make and print the QR Code symbol
// 	uint8_t qrcode[qrcodegen_BUFFER_LEN_MAX];
// 	uint8_t tempBuffer[qrcodegen_BUFFER_LEN_MAX];
// 	bool ok = qrcodegen_encodeText(text, tempBuffer, qrcode, errCorLvl,
// 		qrcodegen_VERSION_MIN, qrcodegen_VERSION_MAX, qrcodegen_Mask_AUTO, true);
// 	if (ok)
// 		printQr(qrcode);
// }

// static void printQr(const uint8_t qrcode[]) {
// 	int size = qrcodegen_getSize(qrcode);
// 	int border = 4;
// 	for (int y = -border; y < size + border; y++) {
// 		for (int x = -border; x < size + border; x++) {
// 			fputs((qrcodegen_getModule(qrcode, x, y) ? "##" : "  "), stdout);
// 		}
// 		fputs("\n", stdout);
// 	}
// 	fputs("\n", stdout);
// }
