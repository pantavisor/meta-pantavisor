# poky's vim turns its GTK3 GUI on whenever x11 is in DISTRO_FEATURES, which
# panta-distro inherits from poky.conf. Nothing built here has a display, and
# the GUI drags gtk+3, cairo, pango, libepoxy and the machine's whole GL stack
# into headless containers - on rk3588 that reaches rockchip-libmali, a glibc
# blob whose file-rdeps are fatal on musl. Alpine's vim, which labutils ships,
# is a full build with --enable-gui=no; match it.
PACKAGECONFIG:remove = "gtkgui x11"
