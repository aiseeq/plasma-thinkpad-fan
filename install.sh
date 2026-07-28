#!/bin/bash
# Installs the ThinkPad Fan Control applet, its helpers and the polkit rule.
#
#   ./install.sh            install or upgrade
#   ./install.sh --uninstall remove everything this script installed
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLET_ID=com.github.aiseeq.thinkpadfan
POLICY=com.github.aiseeq.thinkpadfan.policy
HELPERS=(thinkpad-fan-status thinkpad-fan-set thinkpad-fan-hold)

die() { echo "error: $*" >&2; exit 1; }

need_root() {
    [[ $EUID -eq 0 ]] && return 0
    command -v sudo >/dev/null || die "need root to install system files"
    SUDO=sudo
}
SUDO=""

if [[ "${1:-}" == "--uninstall" ]]; then
    need_root
    kpackagetool6 --type Plasma/Applet --remove "$APPLET_ID" 2>/dev/null || true
    for h in "${HELPERS[@]}"; do $SUDO rm -f "/usr/local/bin/$h"; done
    $SUDO rm -f "/usr/share/polkit-1/actions/$POLICY"
    $SUDO systemctl stop thinkpad-fan-hold.service 2>/dev/null || true
    echo "removed. Restart the panel: systemctl --user restart plasma-plasmashell"
    exit 0
fi

# --- checks -----------------------------------------------------------------
[[ -e /proc/acpi/ibm/fan ]] ||
    die "/proc/acpi/ibm/fan not found — this applet needs a ThinkPad with thinkpad_acpi"

if [[ "$(cat /sys/module/thinkpad_acpi/parameters/fan_control 2>/dev/null)" != "Y" ]]; then
    cat >&2 <<'EOF'
warning: fan control is disabled in thinkpad_acpi, manual levels will not work.
         Enable it with:

           echo 'options thinkpad_acpi fan_control=1' | sudo tee /etc/modprobe.d/thinkpad_acpi.conf
           sudo modprobe -r thinkpad_acpi && sudo modprobe thinkpad_acpi

EOF
fi

command -v kpackagetool6 >/dev/null || die "kpackagetool6 not found — is Plasma 6 installed?"

# --- install ----------------------------------------------------------------
need_root

for h in "${HELPERS[@]}"; do
    $SUDO install -m 0755 "$HERE/helpers/$h" "/usr/local/bin/$h"
done
echo "helpers  -> /usr/local/bin/"

$SUDO install -m 0644 "$HERE/polkit/$POLICY" "/usr/share/polkit-1/actions/$POLICY"
echo "polkit   -> /usr/share/polkit-1/actions/$POLICY"

if kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -qx "$APPLET_ID"; then
    kpackagetool6 --type Plasma/Applet --upgrade "$HERE/package"
else
    kpackagetool6 --type Plasma/Applet --install "$HERE/package"
fi
echo "applet   -> $APPLET_ID"

cat <<'EOF'

Done. Now:
  1. systemctl --user restart plasma-plasmashell
  2. right-click the panel -> Add Widgets -> "ThinkPad Fan Control"
  3. if the fan reading stays 0, open the widget settings and pick the right
     sensor id (the settings page shows how to list them)
EOF
