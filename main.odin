package qr_fun

import "core:mem"
import "base:runtime"
import win "core:sys/windows"
import fmt "core:fmt"
import os "core:os"
import qr "qrcodegen"

Color :: [4]u8
Int2 :: [2]i32

TITLE :: "QR Fun"
WINDOW_SIZE :: Int2 {708, 708}
CLASS_NAME :: "QrMainClass"

BLACK :: Color{0, 0, 0, 255}
WHITE :: Color{255, 255, 255, 255}

COLOR_BITS :: 1
PALETTE_COUNT :: 1 << COLOR_BITS
Color_Palette :: [PALETTE_COUNT]Color

Bitmap_Info :: struct {
	bmiHeader: win.BITMAPINFOHEADER,
	bmiColors: Color_Palette,
}

Screen_Buffer :: [^]u8

Config_Flag :: enum u32 {
	CENTER = 1,
}
Config_Flags :: distinct bit_set[Config_Flag;u32]

Window :: struct {
	name:          win.wstring,
	size:          Int2,
	control_flags: Config_Flags,
}

App :: struct {
	qrcode: [qr.BUFFER_LEN_MAX]u8,
	qrsize: int,
	hbitmap: win.HBITMAP,
	pvBits:  Screen_Buffer,
	window:  Window,
}

draw_qr_code :: #force_inline proc(app: ^App) {
	stride := app.qrsize + 3
	total_size := stride * app.qrsize
	mem.zero_explicit(app.pvBits, total_size)
	for y in 0..<app.qrsize {
	    row_offset := y * stride
	    for x in 0..<app.qrsize {
	        if qr.getModule(raw_data(app.qrcode[:]), i32(x), i32(y)) {
	            app.pvBits[row_offset + x] = 1   // black
	        }
	    }
	}
}

message_box :: #force_inline proc(text, caption: string, loc := #caller_location) {
	win.MessageBoxW(nil, win.utf8_to_wstring(text), win.utf8_to_wstring(caption), win.MB_ICONSTOP | win.MB_OK)
}

show_error_and_panic :: proc(msg: string, loc := #caller_location) {
	message_box(fmt.tprintf("%s\nLast error: %x\n", msg, win.GetLastError()), "Panic")
	panic(msg, loc = loc)
}

get_rect_size :: #force_inline proc(rect: ^win.RECT) -> Int2 {return {(rect.right - rect.left), (rect.bottom - rect.top)}}

set_app :: #force_inline proc(hwnd: win.HWND, app: ^App) {win.SetWindowLongPtrW(hwnd, win.GWLP_USERDATA, win.LONG_PTR(uintptr(app)))}

get_app :: #force_inline proc(hwnd: win.HWND) -> ^App {return (^App)(rawptr(uintptr(win.GetWindowLongPtrW(hwnd, win.GWLP_USERDATA))))}

WM_CREATE :: proc(hwnd: win.HWND, lparam: win.LPARAM) -> win.LRESULT {
	pcs := (^win.CREATESTRUCTW)(rawptr(uintptr(lparam)))
	if pcs == nil {show_error_and_panic("lparam is nil")}
	app := (^App)(pcs.lpCreateParams)
	if app == nil {show_error_and_panic("lpCreateParams is nil")}
	set_app(hwnd, app)

	hdc := win.GetDC(hwnd)
	defer win.ReleaseDC(hwnd, hdc)

	bitmap_info := Bitmap_Info {
		bmiHeader = win.BITMAPINFOHEADER {
			biSize        = size_of(win.BITMAPINFOHEADER),
			biWidth       = i32(app.qrsize),
			biHeight      = i32(-app.qrsize), // minus for top-down
			biPlanes      = 1,
			biBitCount    = 8,
			biCompression = win.BI_RGB,
			biClrUsed     = 2,
		},
		bmiColors = {WHITE, BLACK},
	}

	app.hbitmap = win.CreateDIBSection(hdc, cast(^win.BITMAPINFO)&bitmap_info, win.DIB_RGB_COLORS, (^rawptr)(&app.pvBits), nil, 0)
	draw_qr_code(app)

	return 0
}

WM_DESTROY :: proc(hwnd: win.HWND) -> win.LRESULT {
	app := get_app(hwnd)
	if app == nil {show_error_and_panic("Missing app!")}
	if app.hbitmap != nil {
		if !win.DeleteObject(win.HGDIOBJ(app.hbitmap)) {
			message_box("Unable to delete hbitmap", "Error")
		}
		app.hbitmap = nil
	}
	win.PostQuitMessage(0)
	return 0
}

WM_PAINT :: proc(hwnd: win.HWND) -> win.LRESULT {
	app := get_app(hwnd)
	if app == nil {return 0}

	ps: win.PAINTSTRUCT
	hdc := win.BeginPaint(hwnd, &ps)
	defer win.EndPaint(hwnd, &ps)

	if app.hbitmap != nil {
		hdc_source := win.CreateCompatibleDC(hdc)
		defer win.DeleteDC(hdc_source)

		win.SelectObject(hdc_source, win.HGDIOBJ(app.hbitmap))
		client_size := get_rect_size(&ps.rcPaint)
		win.StretchBlt(hdc, 0, 0, client_size.x, client_size.y, hdc_source, 0, 0, i32(app.qrsize), i32(app.qrsize), win.SRCCOPY)
	}

	return 0
}

WM_CHAR :: proc(hwnd: win.HWND, wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	switch wparam {
	case '\x1b':
		win.PostMessageW(hwnd, win.WM_CLOSE, 0, 0)
	}
	return 0
}

win_proc :: proc "stdcall" (hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	context = runtime.default_context()
	switch(msg) {
	case win.WM_CREATE:     return WM_CREATE(hwnd, lparam)
	case win.WM_DESTROY:    return WM_DESTROY(hwnd)
	case win.WM_ERASEBKGND: return 1 // paint should fill out the client area so no need to erase the background
	case win.WM_PAINT:      return WM_PAINT(hwnd)
	case win.WM_CHAR:       return WM_CHAR(hwnd, wparam, lparam)
	case: 				    return win.DefWindowProcW(hwnd, msg, wparam, lparam)
	}
}

register_class :: proc(instance: win.HINSTANCE) -> win.ATOM {
	cursor := win.LoadCursorA(nil, win.IDC_ARROW)
	if cursor == nil {show_error_and_panic("Missing cursor")}
	wcx := win.WNDCLASSW {
		style         = win.CS_HREDRAW | win.CS_VREDRAW | win.CS_OWNDC,
		lpfnWndProc   = win_proc,
		lpszClassName = CLASS_NAME,
		hInstance     = instance,
		hCursor       = cursor,
		hbrBackground = cast(win.HBRUSH)cast(uintptr)(win.COLOR_WINDOW + 1),
	}
	return win.RegisterClassW(&wcx)
}

unregister_class :: proc(atom: win.ATOM, instance: win.HINSTANCE) {
	if atom == 0 {show_error_and_panic("atom is zero")}
	if !win.UnregisterClassW(CLASS_NAME, instance) {show_error_and_panic("UnregisterClassW")}
}

adjust_size_for_style :: proc(size: ^Int2, dwStyle: win.DWORD) {
	rect := win.RECT{0, 0, size.x, size.y}
	if win.AdjustWindowRect(&rect, dwStyle, false) {
		size^ = {i32(rect.right - rect.left), i32(rect.bottom - rect.top)}
	}
}

center_window :: proc(position: ^Int2, size: Int2) {
	if deviceMode: win.DEVMODEW; win.EnumDisplaySettingsW(nil, win.ENUM_CURRENT_SETTINGS, &deviceMode) {
		device_size := Int2{i32(deviceMode.dmPelsWidth), i32(deviceMode.dmPelsHeight)}
		position^ = (device_size - size) / 2
	}
}

create_window :: #force_inline proc(instance: win.HINSTANCE, atom: win.ATOM, app: ^App) -> win.HWND {
	if atom == 0 {show_error_and_panic("atom is zero")}
	style :: win.WS_OVERLAPPED | win.WS_CAPTION | win.WS_SYSMENU
	size := app.window.size
	pos := Int2{i32(win.CW_USEDEFAULT), i32(win.CW_USEDEFAULT)}
	adjust_size_for_style(&size, style)
	if .CENTER in app.window.control_flags {
		center_window(&pos, size)
	}
	return win.CreateWindowW(CLASS_NAME, app.window.name, style, pos.x, pos.y, size.x, size.y, nil, nil, instance, app)
}

message_loop :: proc() -> int {
	msg: win.MSG
	for win.GetMessageW(&msg, nil, 0, 0) > 0 {
		win.TranslateMessage(&msg)
		win.DispatchMessageW(&msg)
	}
	return int(msg.wParam)
}

get_clipboard_text :: proc(hwnd: win.HWND) -> string {
    if !win.OpenClipboard(hwnd) {
        return ""
    }
    defer win.CloseClipboard()

    if !win.IsClipboardFormatAvailable(win.CF_UNICODETEXT) {
        return ""
    }

    hData := win.GetClipboardData(win.CF_UNICODETEXT)
    if hData == nil {
        return ""
    }

    h := win.HGLOBAL(hData)
    vptr := win.GlobalLock(h)
    if vptr == nil {
        return ""
    }
    defer win.GlobalUnlock(h)

    wptr := cast(^u16)vptr
    len := 0
    for ;mem.ptr_offset(wptr, len)^ != 0; len += 1 { }
    utf16 := mem.slice_ptr(wptr, len)
    text, err := win.utf16_to_utf8_alloc(utf16[:], context.temp_allocator)
    if err != nil { show_error_and_panic("Arena allocation error") }

    return text
}

run :: proc() -> int {
	defer free_all(context.temp_allocator)

	text : string
	if len(os.args) < 2 {
		text = get_clipboard_text(nil)
    }
    else {
	    text = os.args[1]
    }

	ecc :: qr.Ecc.LOW
	qrcode : [qr.BUFFER_LEN_MAX]u8
	tmp_buf : [qr.BUFFER_LEN_MAX]u8
	ok := qr.encodeText(cstring(raw_data(text)), raw_data(tmp_buf[:]), raw_data(qrcode[:]), ecc, qr.VERSION_MIN, qr.VERSION_MAX, qr.Mask.AUTO, true)
	if !ok {show_error_and_panic("failed to create qr code")}
	qr_size := qr.getSize(raw_data(qrcode[:]))

	app := App {
		window = Window{name = TITLE, size = WINDOW_SIZE, control_flags = {.CENTER}},
		qrcode = qrcode,
		qrsize = int(qr_size),
	}

	// This isn't exactly equivalent to getting the hInstance argument passed to wWinMain in C,
	// but it's good enough for all intents and purposes.
	instance := win.HINSTANCE(win.GetModuleHandleW(nil))
	if (instance == nil) {show_error_and_panic("No instance")}
	atom := register_class(instance)
	if atom == 0 {show_error_and_panic("Failed to register window class")}
	defer unregister_class(atom, instance)

	hwnd := create_window(instance, atom, &app)
	if hwnd == nil {show_error_and_panic("Failed to create window")}
	win.ShowWindow(hwnd, win.SW_SHOWDEFAULT)
	win.UpdateWindow(hwnd)

	return message_loop()
}

main :: proc() {
	exit_code := run()
	os.exit(exit_code)
}
