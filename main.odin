package qr_fun

import "core:c"
import "core:mem"
import "base:runtime"
import win "core:sys/windows"
import fmt "core:fmt"
import os "core:os"
import qr "qrcodegen"

MOD_ALT 	:: 0x1
MOD_CONTROL :: 0x2
MOD_SHIFT 	:: 0x4
MOD_WIN 	:: 0x8

HOTKEY_ID :: 1

Color :: [4]u8
Int2 :: [2]i32

TITLE :: "QR Fun"
WINDOW_SIZE :: Int2 {708, 708}
CLASS_NAME :: "QrMainClass"

BLACK :: win.RGBQUAD{0, 0, 0, 255}
WHITE :: win.RGBQUAD{255, 255, 255, 255}

COLOR_BITS :: 1
PALETTE_COUNT :: 1 << COLOR_BITS
Color_Palette :: [PALETTE_COUNT]win.RGBQUAD

Bitmap_Info :: struct {
	bmiHeader: win.BITMAPINFOHEADER,
	bmiColors: Color_Palette,
}

Screen_Buffer :: [^]u8

Config_Flag :: enum u32 {
	CENTER = 1,
}
Config_Flags :: distinct bit_set[Config_Flag;u32]

App :: struct {
	instance : win.HINSTANCE,
	atom	 : win.ATOM
}

Window :: struct {
	hbitmap : win.HBITMAP,
	qrsize  : win.LONG,
	size    : Int2
}

message_box :: #force_inline proc(text, caption: string, loc := #caller_location) {
	win.MessageBoxW(nil, win.utf8_to_wstring(text), win.utf8_to_wstring(caption), win.MB_ICONSTOP | win.MB_OK)
}

show_error_and_panic :: proc(msg: string, loc := #caller_location) {
	message_box(fmt.tprintf("%s\nLast error: %x\n", msg, win.GetLastError()), "Panic")
	panic(msg, loc = loc)
}

get_rect_size :: #force_inline proc(rect: ^win.RECT) -> Int2 { return { (rect.right - rect.left), (rect.bottom - rect.top) } }

set_win_data :: #force_inline proc(hwnd: win.HWND, data: ^Window) {win.SetWindowLongPtrW(hwnd, win.GWLP_USERDATA, win.LONG_PTR(uintptr(data)))}

get_win_data :: #force_inline proc(hwnd: win.HWND) -> ^Window {return (^Window)(rawptr(uintptr(win.GetWindowLongPtrW(hwnd, win.GWLP_USERDATA))))}

draw_qr_code :: #force_inline proc(pvBits: Screen_Buffer, qrcode: []u8, qrsize: c.int) {
	stride := qrsize + 3
	total_size := stride * qrsize
	mem.zero_explicit(pvBits, int(total_size))
	for y: c.int = 0; y < qrsize; y+=1 {
	    row_offset := y * stride
	    for x: c.int = 0; x < qrsize; x+= 1 {
	        if qr.getModule(raw_data(qrcode), x, y) {
	            pvBits[row_offset + x] = 1   // black
	        }
	    }
	}
}

WM_CREATE :: proc(hwnd: win.HWND, lparam: win.LPARAM) -> win.LRESULT {
	pcs := (^win.CREATESTRUCTW)(rawptr(uintptr(lparam)))
	if pcs == nil {show_error_and_panic("lparam is nil")}
	win_data := (^Window)(pcs.lpCreateParams)
	if win_data == nil {show_error_and_panic("lpCreateParams is nil")}
	set_win_data(hwnd, win_data)

	hdc := win.GetDC(hwnd)
	defer win.ReleaseDC(hwnd, hdc)

	defer free_all(context.temp_allocator)
	text := get_clipboard_text()
	fmt.println(text)

	qrcode : [qr.BUFFER_LEN_MAX]u8
	tmp_buf : [qr.BUFFER_LEN_MAX]u8
	ecc :: qr.Ecc.LOW
	ok := qr.encodeText(cstring(raw_data(text)), raw_data(tmp_buf[:]), raw_data(qrcode[:]), ecc, qr.VERSION_MIN, qr.VERSION_MAX, qr.Mask.AUTO, true)
	if !ok {show_error_and_panic("Failed to create qr code")}
	qr_size : c.int = qr.getSize(raw_data(qrcode[:]))

	bitmap_info := Bitmap_Info {
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

	pvBits: Screen_Buffer
	win_data.hbitmap = win.CreateDIBSection(hdc, cast(^win.BITMAPINFO)&bitmap_info, win.DIB_RGB_COLORS, (^rawptr)(&pvBits), nil, 0)
	win_data.qrsize = qr_size
	draw_qr_code(pvBits, qrcode[:], qr_size)

	return 0
}

WM_DESTROY :: proc(hwnd: win.HWND) -> win.LRESULT {
	win_data := get_win_data(hwnd)
	if win_data == nil {show_error_and_panic("Missing app!")}
	if win_data.hbitmap != nil {
		if !win.DeleteObject(win.HGDIOBJ(win_data.hbitmap)) {
			message_box("Unable to delete hbitmap", "Error")
		}
		win_data.hbitmap = nil
	}
	free(win_data)
	return 0
}

WM_PAINT :: proc(hwnd: win.HWND) -> win.LRESULT {
	win_data := get_win_data(hwnd)
	if win_data == nil {return 0}

	ps: win.PAINTSTRUCT
	hdc := win.BeginPaint(hwnd, &ps)
	defer win.EndPaint(hwnd, &ps)

	if win_data.hbitmap != nil {
		hdc_source := win.CreateCompatibleDC(hdc)
		defer win.DeleteDC(hdc_source)

		win.SelectObject(hdc_source, win.HGDIOBJ(win_data.hbitmap))
		client_size := get_rect_size(&ps.rcPaint)
		win.StretchBlt(hdc, 0, 0, client_size.x, client_size.y, hdc_source, 0, 0, win_data.qrsize, win_data.qrsize, win.SRCCOPY)
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

create_window :: #force_inline proc(instance: win.HINSTANCE, atom: win.ATOM, win_data: ^Window) -> win.HWND {
	if atom == 0 {show_error_and_panic("atom is zero")}
	size := &win_data.size
	style :: win.WS_OVERLAPPED | win.WS_CAPTION | win.WS_SYSMENU
	pos := Int2{i32(win.CW_USEDEFAULT), i32(win.CW_USEDEFAULT)}
	adjust_size_for_style(size, style)
	center_window(&pos, size^)
	return win.CreateWindowW(CLASS_NAME, TITLE, style, pos.x, pos.y, size.x, size.y, nil, nil, instance, win_data)
}

get_clipboard_text :: proc() -> string {
    if !win.OpenClipboard(nil) {
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

WM_HOTKEY :: proc(app: ^App, wparam: win.WPARAM) {
	if wparam != HOTKEY_ID { return }

	win_data := new(Window)
	win_data.size = WINDOW_SIZE
	hwnd := create_window(app.instance, app.atom, win_data)
	if hwnd == nil {show_error_and_panic("Failed to create window")}
	win.ShowWindow(hwnd, win.SW_SHOWDEFAULT)
	win.UpdateWindow(hwnd)
}

message_loop :: proc(app: ^App) -> int {
	msg: win.MSG
	for win.GetMessageW(&msg, nil, 0, 0) > 0 {
		if msg.message == win.WM_HOTKEY {
			WM_HOTKEY(app, msg.wParam)
			continue
		}
		win.TranslateMessage(&msg)
		win.DispatchMessageW(&msg)
	}
	return int(msg.wParam)
}

run :: proc() -> int {
	defer free_all(context.temp_allocator)

	// This isn't exactly equivalent to getting the hInstance argument passed to wWinMain in C,
	// but it's good enough for all intents and purposes.
	instance := win.HINSTANCE(win.GetModuleHandleW(nil))
	if instance == nil {show_error_and_panic("No instance")}
	atom := register_class(instance)
	if atom == 0 {show_error_and_panic("Failed to register window class")}
	defer unregister_class(atom, instance)
	app := App {
		instance = instance,
		atom = atom
	}

	ok := win.RegisterHotKey(nil, HOTKEY_ID, MOD_CONTROL | MOD_ALT, win.VK_Q)
	if !ok {show_error_and_panic("Failed to register hotkey")}

	return message_loop(&app)
}

main :: proc() {
	exit_code := run()
	os.exit(exit_code)
}
