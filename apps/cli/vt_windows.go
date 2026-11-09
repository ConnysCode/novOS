//go:build windows

package main

import (
	"os"

	"golang.org/x/sys/windows"
)

// enableVirtualTerminal lets the Windows console read arrow keys as escape sequences and
// draw the picker's ANSI codes, as other terminals do.
func enableVirtualTerminal() func() {
	in := windows.Handle(os.Stdin.Fd())
	out := windows.Handle(os.Stdout.Fd())
	var inMode, outMode uint32
	_ = windows.GetConsoleMode(in, &inMode)
	_ = windows.GetConsoleMode(out, &outMode)
	_ = windows.SetConsoleMode(in, inMode|windows.ENABLE_VIRTUAL_TERMINAL_INPUT)
	_ = windows.SetConsoleMode(out, outMode|windows.ENABLE_VIRTUAL_TERMINAL_PROCESSING)
	return func() {
		_ = windows.SetConsoleMode(in, inMode)
		_ = windows.SetConsoleMode(out, outMode)
	}
}
