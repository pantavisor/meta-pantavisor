# var-wireless-utils-wifi/-ot's systemctl-enable postinst fails do_rootfs on
# imx8mn-var-som/imx8mm-var-dart (build-time only; the units work fine once a
# real systemd is running). Drop them from SYSTEMD_PACKAGES so systemd.bbclass
# stops generating a build-time pkg_postinst for them, and enable the units
# ourselves via pkg_postinst_ontarget instead, deferring to first real boot.
# -bt is left alone: it enables cleanly at rootfs time today.
SYSTEMD_PACKAGES:remove = "${PN}-wifi ${PN}-ot"

pkg_postinst_ontarget:${PN}-wifi () {
	if systemctl >/dev/null 2>/dev/null; then
		systemctl enable variscite-wifi.service
		systemctl daemon-reload
		systemctl preset variscite-wifi.service
		systemctl --no-block restart variscite-wifi.service
	fi
}

pkg_postinst_ontarget:${PN}-ot () {
	if systemctl >/dev/null 2>/dev/null; then
		systemctl enable variscite-ot.service
		systemctl daemon-reload
		systemctl preset variscite-ot.service
		systemctl --no-block restart variscite-ot.service
	fi
}
