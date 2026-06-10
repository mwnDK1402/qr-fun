package demos

import "core:fmt"
import win "core:sys/windows"

MOD_ALT 	:: 0x1
MOD_CONTROL :: 0x2
MOD_SHIFT 	:: 0x4
MOD_WIN 	:: 0x8

reg_key :: proc(id: win.c_int, fsModifiers: win.UINT, vk: win.UINT) -> win.BOOL {
	ok := win.RegisterHotKey(nil, id, fsModifiers, vk)
    if !ok {
        fmt.eprintfln("RegisterHotKey failed (%d)", id)
    }
    return ok
}

main :: proc() {
	if !reg_key(1, MOD_CONTROL | MOD_SHIFT, win.VK_K) { return }
	if !reg_key(2, MOD_CONTROL | MOD_SHIFT, win.VK_Q) { return }
	if !reg_key(3, MOD_WIN | MOD_SHIFT, win.VK_K) { return }
	if !reg_key(4, MOD_CONTROL | MOD_SHIFT, win.VK_SPACE) { return }

    msg: win.MSG
    for win.GetMessageW(&msg, nil, 0, 0) > 0 {
        if msg.message == win.WM_HOTKEY {
            fmt.println("WM_HOTKEY received!")
            return
        }
        win.TranslateMessage(&msg)
        win.DispatchMessageW(&msg)
    }
}
