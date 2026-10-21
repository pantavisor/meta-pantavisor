# The layer's busybox is built without FEATURE_EDITING_FANCY_PROMPT
# (recipes-pv/busybox/files/trim.cfg), so the '\u@\h:\w\$ ' that /etc/profile
# sets prints literally. ASH_EXPAND_PRMT is on, so ash expands $(...) and ${...}
# in PS1 at every prompt: build the same prompt from those instead.
if [ -n "$PS1" ]; then
	[ "$(id -u)" = 0 ] && _sdk_mark='#' || _sdk_mark='$'
	PS1="$(id -un)@\$(hostname):\${PWD}$_sdk_mark "
	unset _sdk_mark
fi
