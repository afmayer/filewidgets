if {([info commands ::tcl::pkgconfig] eq "")
	|| ([info sharedlibextension] ne ".dll")} return
if {[::tcl::pkgconfig get debug]} {
    package ifneeded dde 1.4.0 [list load "" dde]
} else {
    package ifneeded dde 1.4.0 [list load "" dde]
}
