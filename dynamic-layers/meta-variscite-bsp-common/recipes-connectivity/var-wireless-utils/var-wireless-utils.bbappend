# pv-avahi-browse/empty-image do_rootfs fail on imx8mn-var-som/imx8mm-var-dart:
# var-wireless-utils-wifi/-ot's postinst runs `update-rc.d ... variscite-wifi
# start ...`, but that fails with "file does not exist" — reproduced directly
# against the native update-rc.d tool used at rootfs time. Root cause: PACKAGES
# lists ${PN}-bt first, and FILES:${PN}-bt claims the whole ${sysconfdir}/init.d
# (and, on a systemd DISTRO_FEATURES, the whole systemd_unitdir/system)
# directory rather than just its own script/unit, so OE's package splitter
# hands variscite-wifi/-ot's own init script (or .service unit) to -bt instead
# of to -wifi/-ot, whose postinst then references a file their own package
# never contains. Narrow each package's FILES to its own script/unit so every
# package actually owns the file its postinst enables.
FILES:${PN}-bt = " \
    ${sysconfdir}/bluetooth/* \
    ${@bb.utils.contains('DISTRO_FEATURES','systemd', \
    '${systemd_unitdir}/system/variscite-bt.service', \
    '${sysconfdir}/init.d/variscite-bt',d)} \
"

FILES:${PN}-ot = " \
    ${sysconfdir}/openthread/* \
    ${@bb.utils.contains('DISTRO_FEATURES','systemd', \
    '${systemd_unitdir}/system/variscite-ot.service', \
    '${sysconfdir}/init.d/variscite-ot',d)} \
"

FILES:${PN}-wifi = " \
    ${sysconfdir}/wifi/* \
    ${@bb.utils.contains('DISTRO_FEATURES','systemd', \
    '${systemd_unitdir}/system/variscite-wifi.service', \
    '${sysconfdir}/init.d/variscite-wifi',d)} \
"
