#
# pvgo_mod.bbclass - Go modules support using pvgo toolchain
#
# Provides the same functionality as go-mod.bbclass but uses the
# isolated pvgo-provided Go toolchain.
#
# Usage: inherit pvgo_mod
#
# SPDX-License-Identifier: MIT
#

# The '-modcacherw' option ensures we have write access to the cached objects so
# we avoid errors during clean task as well as when removing the TMPDIR.
GOBUILDFLAGS:append = " -modcacherw"

inherit pvgo

GO_WORKDIR ?= "${GO_IMPORT}"
do_compile[dirs] += "${B}/src/${GO_WORKDIR}"

export GOMODCACHE = "${B}/.mod"

do_compile[cleandirs] += "${B}/.mod"
