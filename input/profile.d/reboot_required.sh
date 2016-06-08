#
# Alert when reboot is required.
#
# DOCS          :https://github.com/liske/needrestart/blob/master/perl/lib/NeedRestart/Kernel.pm#L33
# DEPENDS       :apt-get install needrestart
# LOCATION      :/etc/profile.d/reboot_required.sh

if [ "$(id -u)" == 0 ]; then
    NEEDRESTART="$(needrestart -b -k | grep -x "NEEDRESTART-KSTA: [0-9]")"
    NEEDRESTART="${NEEDRESTART#*: }"
    if [ "$NEEDRESTART" != 0 ] && [ "$NEEDRESTART" != 1 ]; then
        echo
        echo "[ALERT] Reboot required."
    fi
    unset NEEDRESTART
fi
