#!/bin/bash
# launch-bettercap-ble.sh
# Thin wrapper.
# We run the chooser script *directly* (no terminal wrapper here).
# The chooser uses zenity (GUI dialogs) for device + preset selection.
# Only *after* you make a choice does it open a single terminal for the actual work.
# This prevents the old behavior of "sudo password prompt in a different/throwaway terminal"
# and "window closes as soon as you type the password".

SCRIPT="$HOME/bin/bettercap-ble-launcher.sh"

if [[ -x "$SCRIPT" ]]; then
    exec "$SCRIPT" "$@"
else
    echo "bettercap-ble-launcher.sh not found or not executable at $SCRIPT"
    read -p "Press Enter..."
    exit 1
fi
