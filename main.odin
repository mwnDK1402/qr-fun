package qr_fun

import "core:c"
import "core:mem"
import "base:runtime"
import win "core:sys/windows"
import fmt "core:fmt"
import os "core:os"
import qr "qrcodegen"

App :: struct {
	instance : win.HINSTANCE,
	atom	 : win.ATOM,
	window   : win.HWND,
}

CreateParams :: struct {
    wnd_data: ^Window,
    clipboard: string,
}

Window :: struct {
	size    : Int2,
	bitmap : win.HBITMAP,
	qr_size  : win.LONG,
}

APP : App

main :: proc() {
	exit_code := run()
	os.exit(exit_code)
}

OPEN_HOTKEY :: 1
QUIT_HOTKEY :: 2

MOD_ALT 	:: 0x1
MOD_CONTROL :: 0x2
MOD_SHIFT 	:: 0x4
MOD_WIN 	:: 0x8

run :: proc() -> int {
	defer free_all(context.temp_allocator)

	// This isn't exactly equivalent to getting the hInstance argument passed to wWinMain in C,
	// but it's good enough for all intents and purposes.
	instance := win.HINSTANCE(win.GetModuleHandleW(nil))
	if instance == nil {show_error_and_panic("No instance")}
	atom := register_class(instance)
	if atom == 0 {show_error_and_panic("Failed to register window class")}
	defer unregister_class(atom, instance)
	APP = App {
		instance = instance,
		atom = atom
	}

	reg_hotkey(OPEN_HOTKEY, MOD_CONTROL | MOD_ALT, win.VK_Q)
	reg_hotkey(QUIT_HOTKEY, MOD_CONTROL | MOD_ALT, win.VK_ESCAPE)

	return message_loop()
}

reg_hotkey :: proc(id: win.c_int, modifiers: win.UINT, key: win.UINT) {
	ok := win.RegisterHotKey(nil, id, modifiers, key)
	if !ok {show_error_and_panic("Failed to register hotkey")}
}

CLASS_NAME :: "QrMainClass"

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

show_error_and_panic :: proc(msg: string, loc := #caller_location) {
	message_box(fmt.tprintf("%s\nLast error: %x\n", msg, win.GetLastError()), "Panic")
	panic(msg, loc = loc)
}

message_box :: #force_inline proc(text, caption: string, loc := #caller_location) {
	win.MessageBoxW(nil, win.utf8_to_wstring(text), win.utf8_to_wstring(caption), win.MB_ICONSTOP | win.MB_OK)
}

message_loop :: proc() -> int {
	msg: win.MSG
	for win.GetMessageW(&msg, nil, 0, 0) > 0 {
		if msg.message == win.WM_HOTKEY {
			WM_HOTKEY(msg.wParam)
			continue
		}
		win.TranslateMessage(&msg)
		win.DispatchMessageW(&msg)
	}
	return int(msg.wParam)
}

Int2 :: [2]i32
WINDOW_SIZE :: Int2 {708, 708}

WM_HOTKEY :: proc(wparam: win.WPARAM) {
	switch wparam {
	case OPEN_HOTKEY:
		if APP.window != nil { return }
		clipboard := get_clipboard_text()
		if clipboard == "" { return }
		if APP.atom == 0 {show_error_and_panic("atom is zero")}
		hwnd := create_window(APP.instance, APP.atom, clipboard)
		if hwnd == nil {show_error_and_panic("Failed to create window")}
		APP.window = hwnd
		win.ShowWindow(hwnd, win.SW_SHOW)
		win.UpdateWindow(hwnd)
		win.SetForegroundWindow(hwnd)
	case QUIT_HOTKEY:
		if APP.window != nil {
			win.DestroyWindow(APP.window)
		}
		win.PostQuitMessage(0)
	}
}

get_clipboard_text :: proc() -> string {
    if !win.OpenClipboard(nil) { return "" }
    defer win.CloseClipboard()

    if !win.IsClipboardFormatAvailable(win.CF_UNICODETEXT) { return "" }

    cb_ptr := win.GetClipboardData(win.CF_UNICODETEXT)
    if cb_ptr == nil { return "" }

    cb_lock := win.HGLOBAL(cb_ptr)
    cb_data := win.GlobalLock(cb_lock)
    if cb_data == nil { return "" }
    defer win.GlobalUnlock(cb_lock)

    size := int(win.GlobalSize(cb_lock) / 2)
    text, err := win.wstring_to_utf8(win.wstring(cb_data), size, context.temp_allocator)
    if err != nil { return "" }

    return text
}

TITLE :: "QR Fun"

create_window :: #force_inline proc(instance: win.HINSTANCE, atom: win.ATOM, clipboard: string) -> win.HWND {
	if atom == 0 {show_error_and_panic("atom is zero")}

	params := new(CreateParams, context.temp_allocator)
	params.wnd_data = new(Window)
	params.clipboard = clipboard
	params.wnd_data.size = WINDOW_SIZE
	size := &params.wnd_data.size

	style :: win.WS_OVERLAPPED | win.WS_CAPTION | win.WS_SYSMENU
	adjust_size_for_style(size, style)

	pos := Int2{i32(win.CW_USEDEFAULT), i32(win.CW_USEDEFAULT)}
	center_window(&pos, size^)

	return win.CreateWindowW(CLASS_NAME, TITLE, style, pos.x, pos.y, size.x, size.y, nil, nil, instance, params)
}

adjust_size_for_style :: proc(size: ^Int2, style: win.DWORD) {
	rect := win.RECT{0, 0, size.x, size.y}
	if win.AdjustWindowRect(&rect, style, false) {
		size^ = {i32(rect.right - rect.left), i32(rect.bottom - rect.top)}
	}
}

center_window :: proc(position: ^Int2, size: Int2) {
	if device_mode: win.DEVMODEW; win.EnumDisplaySettingsW(nil, win.ENUM_CURRENT_SETTINGS, &device_mode) {
		device_size := Int2{i32(device_mode.dmPelsWidth), i32(device_mode.dmPelsHeight)}
		position^ = (device_size - size) / 2
	}
}

win_proc :: proc "stdcall" (hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	context = runtime.default_context()
	switch(msg) {
	case win.WM_CREATE:     return WM_CREATE(hwnd, lparam)
	case win.WM_DESTROY:    return WM_DESTROY(hwnd)
	case win.WM_ERASEBKGND: return 1 // paint should fill out the client area so no need to erase the background
	case win.WM_PAINT:      return WM_PAINT(hwnd)
	case win.WM_CHAR:       return WM_CHAR(hwnd, wparam, lparam)
	case win.WM_KILLFOCUS:  return WM_KILLFOCUS(hwnd)
	case: 				    return win.DefWindowProcW(hwnd, msg, wparam, lparam)
	}
}

BLACK :: win.RGBQUAD{0, 0, 0, 255}
WHITE :: win.RGBQUAD{255, 255, 255, 255}

COLOR_BITS :: 1
PALETTE_COUNT :: 1 << COLOR_BITS
ColorPalette :: [PALETTE_COUNT]win.RGBQUAD

BitmapInfo :: struct {
	bmiHeader: win.BITMAPINFOHEADER,
	bmiColors: ColorPalette,
}

WM_CREATE :: proc(hwnd: win.HWND, lparam: win.LPARAM) -> win.LRESULT {
	defer free_all(context.temp_allocator)
	pcs := (^win.CREATESTRUCTW)(rawptr(uintptr(lparam)))
	if pcs == nil {show_error_and_panic("lparam is nil")}
	params := (^CreateParams)(pcs.lpCreateParams)
	if params == nil {show_error_and_panic("lpCreateParams is nil")}
	set_wnd_data(hwnd, params.wnd_data)

	hdc := win.GetDC(hwnd)
	defer win.ReleaseDC(hwnd, hdc)

	text := params.clipboard
	fmt.println(text)

	qr_code : [qr.BUFFER_LEN_MAX]u8
	tmp_buf : [qr.BUFFER_LEN_MAX]u8
	ecc :: qr.Ecc.LOW
	ok := qr.encodeText(cstring(raw_data(text)), raw_data(tmp_buf[:]), raw_data(qr_code[:]), ecc, qr.VERSION_MIN, qr.VERSION_MAX, qr.Mask.AUTO, true)
	if !ok {show_error_and_panic("Failed to create qr code")}
	qr_size : c.int = qr.getSize(raw_data(qr_code[:]))

	bitmap_info := BitmapInfo {
		bmiHeader = win.BITMAPINFOHEADER {
			biSize        = size_of(win.BITMAPINFOHEADER),
			biWidth       = qr_size,
			biHeight      = -qr_size, // minus for top-down
			biPlanes      = 1,
			biBitCount    = 8,
			biCompression = win.BI_RGB,
			biClrUsed     = 2,
		},
		bmiColors = {WHITE, BLACK},
	}

	pv_bits: [^]u8
	params.wnd_data.bitmap = win.CreateDIBSection(hdc, cast(^win.BITMAPINFO)&bitmap_info, win.DIB_RGB_COLORS, (^rawptr)(&pv_bits), nil, 0)
	params.wnd_data.qr_size = qr_size
	stride := qr_size + 3
	total_size := stride * qr_size
	draw_qr_code(mem.slice_ptr(pv_bits, int(total_size)), qr_code[:], qr_size)

	return 0
}

set_wnd_data :: #force_inline proc(hwnd: win.HWND, data: ^Window) {win.SetWindowLongPtrW(hwnd, win.GWLP_USERDATA, win.LONG_PTR(uintptr(data)))}

get_wnd_data :: #force_inline proc(hwnd: win.HWND) -> ^Window {return (^Window)(rawptr(uintptr(win.GetWindowLongPtrW(hwnd, win.GWLP_USERDATA))))}

draw_qr_code :: #force_inline proc(pv_bits: []u8, qr_code: []u8, qr_size: c.int) {
	mem.zero_slice(pv_bits)
	stride := qr_size + 3
	for y: c.int = 0; y < qr_size; y+=1 {
	    row_offset := y * stride
	    for x: c.int = 0; x < qr_size; x+= 1 {
	        if qr.getModule(raw_data(qr_code), x, y) {
	            pv_bits[row_offset + x] = 1   // black
	        }
	    }
	}
}

WM_PAINT :: proc(hwnd: win.HWND) -> win.LRESULT {
	wnd_data := get_wnd_data(hwnd)
	if wnd_data == nil { return 0 }

	ps: win.PAINTSTRUCT
	hdc := win.BeginPaint(hwnd, &ps)
	defer win.EndPaint(hwnd, &ps)

	if wnd_data.bitmap != nil {
		hdc_source := win.CreateCompatibleDC(hdc)
		defer win.DeleteDC(hdc_source)

		win.SelectObject(hdc_source, win.HGDIOBJ(wnd_data.bitmap))
		client_size := get_rect_size(&ps.rcPaint)
		win.StretchBlt(hdc, 0, 0, client_size.x, client_size.y, hdc_source, 0, 0, wnd_data.qr_size, wnd_data.qr_size, win.SRCCOPY)
	}

	return 0
}

get_rect_size :: #force_inline proc(rect: ^win.RECT) -> Int2 { return { (rect.right - rect.left), (rect.bottom - rect.top) } }

WM_CHAR :: proc(hwnd: win.HWND, wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	switch wparam {
	case '\x1b':
		win.PostMessageW(hwnd, win.WM_CLOSE, 0, 0)
	}
	return 0
}

WM_KILLFOCUS :: proc(hwnd: win.HWND) -> win.LRESULT {
	win.DestroyWindow(hwnd)
	return 0
}

WM_DESTROY :: proc(hwnd: win.HWND) -> win.LRESULT {
	wnd_data := get_wnd_data(hwnd)
	if wnd_data == nil {show_error_and_panic("Missing app!")}
	if wnd_data.bitmap != nil {
		if !win.DeleteObject(win.HGDIOBJ(wnd_data.bitmap)) {
			message_box("Unable to delete hbitmap", "Error")
		}
		wnd_data.bitmap = nil
	}
	free(wnd_data)

	APP.window = nil
	return 0
}
