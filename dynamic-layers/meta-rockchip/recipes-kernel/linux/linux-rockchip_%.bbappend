FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# JeffyCN's vendor kernel fork ships no Orange Pi RK3588(S) devicetrees. Add
# rk3588s-orangepi-5b (plus its rk3588s-orangepi-5 parent and camera dtsi
# includes), taken from armbian/linux-rockchip rk-6.1-rkr6.1 — same vendor
# RK3588S BSP devicetree conventions as this fork.
SRC_URI:append:orangepi-5b = " file://0001-arm64-dts-rockchip-add-orangepi-5b.patch"
