if {([info commands ::tcl::pkgconfig] eq "")
	|| ([info sharedlibextension] ne ".dll")} return
if {[::tcl::pkgconfig get debug]} {
    package ifneeded registry 1.3.0 \
            [list load "" registry]
} else {
    package ifneeded registry 1.3.0 \
            [list load "" registry]
}
