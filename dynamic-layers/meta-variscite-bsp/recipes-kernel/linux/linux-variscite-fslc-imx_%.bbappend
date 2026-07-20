FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# Enable the SoC SNVS RTC on the VAR-SOM-MX8M-NANO Symphony board so Pantavisor
# "managed" power mode has a wakeup-capable RTC alarm (CLOCK_BOOTTIME_ALARM) to
# wake the device from suspend-to-RAM. The board otherwise only exposes the
# external DS1307, whose alarm IRQ is not wired as a wakeup source. Guarded on
# virtual/kernel so it only applies to the kernel recipe, not shared providers.
SRC_URI:append:imx8mn-var-som = " \
	${@'file://0001-arm64-dts-imx8mn-var-som-symphony-enable-snvs-rtc.patch' if bb.utils.contains('PROVIDES', 'virtual/kernel', True, False, d) else ''} \
"
