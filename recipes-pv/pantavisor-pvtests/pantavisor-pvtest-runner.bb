SUMMARY = "pvtest in-container test runner"
DESCRIPTION = "pvtest-run, the runner that drives a pantavisor target from inside \
the tester container, plus the utils/common shell libraries that pvtest-run and \
every test's resources/test script source."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# Pure POSIX/bash shell — no compiled output, so one build serves every MACHINE.
inherit allarch

SRC_URI = "file://pvtest"

S = "${WORKDIR}"

# What pvtest-run and utils actually invoke inside the tester container:
#   bash        - exec_interactive runs `bash --rcfile`; both libs use `local`
#   coreutils   - timeout(1) wall-bounds every forwarded exec; mktemp, date, sort
#   util-linux  - script(1) for pty capture of the test script, flock(1) for slots
#   jq          - test.json parsing and every pvcontrol/devmeta assertion
#   curl        - pvr HTTP endpoint readiness probe on :12368
#   pvr         - clone/post/get against the target's trail
#   openssh-ssh - PVTEST_EXEC forwarding to the target's dropbear-pv on :8222
# Deliberately absent: bc (unused by the runner; an interactive-debug convenience
# kept at image level) and pantavisor-pvcontrol/-pvtx, which run on the *target*
# over PVTEST_EXEC, not on the tester.
RDEPENDS:${PN} = " \
	bash \
	coreutils \
	curl \
	jq \
	openssh-ssh \
	pvr \
	util-linux \
"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
	install -d ${D}${bindir}
	install -m 0755 ${WORKDIR}/pvtest/pvtest-run ${D}${bindir}/pvtest-run

	# This path is hardcoded in pvtest-run and in every test's resources/test
	# (`source /usr/share/pantavisor/pvtest/utils`) — do not relocate.
	install -d ${D}${datadir}/pantavisor/pvtest
	install -m 0644 ${WORKDIR}/pvtest/utils  ${D}${datadir}/pantavisor/pvtest/utils
	install -m 0644 ${WORKDIR}/pvtest/common ${D}${datadir}/pantavisor/pvtest/common
}

FILES:${PN} = " \
	${bindir}/pvtest-run \
	${datadir}/pantavisor/pvtest/utils \
	${datadir}/pantavisor/pvtest/common \
"
