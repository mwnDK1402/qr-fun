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

	win.SetProcessDpiAwareness(win.PROCESS_DPI_AWARENESS.PROCESS_SYSTEM_DPI_AWARE)

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

WM_HOTKEY :: proc(wparam: win.WPARAM) {
	switch wparam {
	case OPEN_HOTKEY:
		if APP.window != nil {
			win.DestroyWindow(APP.window)
		}
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

	pt, size := place_window()

	params := new(CreateParams, context.temp_allocator)
	params.wnd_data = new(Window)
	params.clipboard = clipboard

	return win.CreateWindowW(CLASS_NAME, TITLE, win.WS_POPUP, pt.x, pt.y, size, size, nil, nil, instance, params)
}

place_window :: proc() -> (pt: win.POINT, size: win.LONG) {
	// Get cursor's virtual screen position
	cursor_pt: win.POINT
	win.GetCursorPos(&cursor_pt)
	monitor := win.MonitorFromPoint(cursor_pt, win.Monitor_From_Flags.MONITOR_DEFAULTTOPRIMARY)

	mi: win.MONITORINFO
	mi.cbSize = size_of(win.MONITORINFO)
	win.GetMonitorInfoW(monitor, &mi)

	// Only place window within the monitor's work area
	monitor_left   := mi.rcWork.left
	monitor_top    := mi.rcWork.top
	monitor_width  := mi.rcWork.right - mi.rcWork.left
	monitor_height := mi.rcWork.bottom - mi.rcWork.top

	// Scale window size relative to monitor width
	size = win.LONG(f32(monitor_width) * .2)

	// Ensure the window is not pushed off-screen (clamp to monitor edge)
	min_x := cursor_pt.x - (size / 2)
	max_x := min_x + size
	if min_x < monitor_left { pt.x = monitor_left }
	else if max_x > monitor_left + monitor_width { pt.x = monitor_left + monitor_width - size }
	else { pt.x = min_x }

	min_y := cursor_pt.y - (size / 2)
	max_y := min_y + size
	if min_y < monitor_top { pt.y = monitor_top }
	else if max_y > monitor_top + monitor_height { pt.y = monitor_top + monitor_height - size }
	else { pt.y = min_y }

	return
}

win_proc :: proc "stdcall" (hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	context = runtime.default_context()
	switch(msg) {
	case win.WM_CREATE:     return WM_CREATE(hwnd, lparam)
	case win.WM_DESTROY:    return WM_DESTROY(hwnd)
	case win.WM_ERASEBKGND: return 1 // paint should fill out the client area so no need to erase the background
	case win.WM_PAINT:      return WM_PAINT(hwnd)
	case win.WM_NCHITTEST:  return win.HTCAPTION
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

	text := params.clipboard

	qr_code : [qr.BUFFER_LEN_MAX]u8 = ---
	qr_size := create_qr_code(qr_code[:], text)
	bitmap, pv_bits := create_bitmap(hwnd, qr_size)
	pv_slice := pv_slice(pv_bits, int(qr_size))
	draw_qr_code(pv_slice, qr_code[:], qr_size)

	wnd_data := params.wnd_data
	wnd_data.bitmap = bitmap
	wnd_data.qr_size = qr_size
	set_wnd_data(hwnd, wnd_data)

	return 0
}

create_qr_code :: proc(dest: []u8, text: string) -> (qr_size: c.int) {
	tmp_buf : [qr.BUFFER_LEN_MAX]u8 = ---
	ecc :: qr.Ecc.LOW
	ok := qr.encodeText(cstring(raw_data(text)), raw_data(tmp_buf[:]), raw_data(dest[:]), ecc, qr.VERSION_MIN, qr.VERSION_MAX, qr.Mask.AUTO, true)
	if !ok {show_error_and_panic("Failed to create qr code")}
	qr_size = qr.getSize(raw_data(dest[:]))
	return
}

create_bitmap :: proc(hwnd: win.HWND, size: c.int) -> (bitmap: win.HBITMAP, pv_bits: [^]u8) {
	hdc := win.GetDC(hwnd)
	defer win.ReleaseDC(hwnd, hdc)

	bitmap_info := BitmapInfo {
		bmiHeader = win.BITMAPINFOHEADER {
			biSize        = size_of(win.BITMAPINFOHEADER),
			biWidth       = size,
			biHeight      = -size, // minus for top-down
			biPlanes      = 1,
			biBitCount    = 8,
			biCompression = win.BI_RGB,
			biClrUsed     = 2,
		},
		bmiColors = {WHITE, BLACK},
	}

	bitmap = win.CreateDIBSection(hdc, cast(^win.BITMAPINFO)&bitmap_info, win.DIB_RGB_COLORS, (^rawptr)(&pv_bits), nil, 0)
	return
}

pv_slice :: proc(pv_bits: [^]u8, qr_size: int) -> (dest: []u8) {
	stride := qr_size + 3
	total_size := stride * qr_size
	dest = mem.slice_ptr(pv_bits, total_size)
	return
}

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

set_wnd_data :: #force_inline proc(hwnd: win.HWND, data: ^Window) {win.SetWindowLongPtrW(hwnd, win.GWLP_USERDATA, win.LONG_PTR(uintptr(data)))}

get_wnd_data :: #force_inline proc(hwnd: win.HWND) -> ^Window {return (^Window)(rawptr(uintptr(win.GetWindowLongPtrW(hwnd, win.GWLP_USERDATA))))}

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
		width, height := get_rect_size(&ps.rcPaint)
		win.StretchBlt(hdc, 0, 0, width, height, hdc_source, 0, 0, wnd_data.qr_size, wnd_data.qr_size, win.SRCCOPY)
	}

	return 0
}

get_rect_size :: #force_inline proc(rect: ^win.RECT) -> (w: i32, h: i32) {
	w = rect.right - rect.left
	h = rect.bottom - rect.top
	return
}

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
