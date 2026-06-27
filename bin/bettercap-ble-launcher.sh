#!/bin/bash
# bettercap-ble-launcher.sh
# Dedicated desktop launcher for bettercap focused on Bluetooth / BLE.
# - First choose your Bluetooth device (hci0 built-in, Raytac/nRF in HCI mode, Ubertooth for sniffing).
# - Then pick from a dropdown/preset list of common bettercap commands and BLE actions.
# - Supports "all commands" via the full interactive shell + custom entry.
# - Uses your existing patterns (qterminal preference, launch_in_terminal, sudo caching).
#
# Your hardware:
#   - Raytac Bluetooth dongle (likely the Nordic nRF 1915:522a)
#   - Ubertooth One (1d50:6002)
#   - Built-in Realtek hci0
#
# For best BLE recon with bettercap use a standard HCI adapter (hciX).
# Ubertooth is excellent for passive wideband BLE sniffing (use ubertooth-btle alongside bettercap).
#
# Desktop icon: ~/Desktop/Bettercap-BLE-Launcher.desktop
# To (re)install bettercap from the GUI: select the Install option (uses pkexec for GUI password prompt).

set -euo pipefail

HOME_DIR="${HOME}"
LAUNCHER_NAME="Bettercap BLE"

# Terminal launcher helper - heavily hardened so the sudo password prompt
# happens *inside the terminal that will actually run bettercap/ubertooth*,
# and the window does NOT close the moment you type the password.
launch_in_terminal() {
    local raw_cmd="$1"
    local title="${2:-Bettercap}"

    # Work out the inner command (strip a leading "sudo " if present; we control elevation)
    local inner="$raw_cmd"
    if [[ "$inner" == sudo\ * ]]; then
        inner="${inner#sudo }"
    fi

    # Decide how to wrap it.
    # For anything that starts with "bettercap" we want an interactive session that stays alive.
    # We run `sudo bash -c 'bettercap ... ; exec bash'` so:
    #   - Password prompt appears in THIS terminal (only one terminal window).
    #   - After you type the password, a root bash runs bettercap.
    #   - When bettercap exits (you type exit inside it, or it ends), you drop to a root shell (# prompt)
    #     instead of the window disappearing.
    local shell_fragment=""

    if [[ "$inner" == bettercap* ]]; then
        # Interactive bettercap (the main useful case). Keep a root shell afterwards.
        # Note: we put the *original* -eval or other args inside the root bash.
        shell_fragment="sudo bash -c '$inner ; echo; echo \"[bettercap ended - you are now in a root shell. Type exit to close.]\"; exec bash'"
    else
        # One-shot tools (ubertooth-btle -f, crackle examples, install notes, custom one-liners, etc.)
        # Run whatever was requested (it may contain its own sudo), then hold the window.
        shell_fragment="bash -c '$raw_cmd ; echo; read -p \"Press Enter to close terminal...\"'"
    fi

    # Now launch the chosen terminal with the safe fragment.
    # We avoid "eval" on the whole thing to reduce quoting disasters.
    if command -v qterminal >/dev/null 2>&1; then
        qterminal -e bash -c "$shell_fragment" &
    elif command -v xfce4-terminal >/dev/null 2>&1; then
        xfce4-terminal --title="$title" --geometry=120x40 --command="bash -c '$shell_fragment'" &
    elif command -v gnome-terminal >/dev/null 2>&1; then
        gnome-terminal --title="$title" --geometry=120x40 -- bash -c "$shell_fragment" &
    elif command -v terminator >/dev/null 2>&1; then
        terminator -T "$title" -e "bash -c '$shell_fragment'" &
    elif command -v x-terminal-emulator >/dev/null 2>&1; then
        x-terminal-emulator -e bash -c "$shell_fragment" &
    else
        echo "No terminal emulator found. Trying to run directly (you will need to be root or use sudo yourself):"
        bash -c "$raw_cmd"
    fi
}

# No longer doing a preflight sudo -v here.
# Reason: we want the password prompt to happen *only* inside the single final
# working terminal (the one running bettercap or ubertooth), not in a throwaway
# terminal or before the zenity dialogs. The new launch_in_terminal logic
# handles elevation inside that terminal.
preflight_sudo() {
    :   # intentionally a no-op now
}

# Detect available Bluetooth / sniffer devices
detect_devices() {
    local -a devs=()
    local -a descs=()

    # Standard HCI adapters (these are what bettercap's ble.recon uses via BlueZ)
    if command -v hciconfig >/dev/null 2>&1; then
        while read -r h; do
            if [[ "$h" =~ hci([0-9]+) ]]; then
                local idx="${BASH_REMATCH[1]}"
                local mac
                mac=$(hciconfig "hci${idx}" 2>/dev/null | awk '/BD Address/ {print $3}' | head -1 || echo "unknown")
                devs+=("hci${idx}")
                descs+=("hci${idx} (standard HCI, MAC ${mac}) — best for bettercap ble.recon")
            fi
        done < <(hciconfig 2>/dev/null | grep -o 'hci[0-9]*' || true)
    fi

    # Built-in fallback if no hci listed yet but we know there is Realtek
    if [ ${#devs[@]} -eq 0 ] && lsusb | grep -qi '0bda:4853\|Realtek.*Bluetooth'; then
        devs+=("hci0")
        descs+=("hci0 (built-in Realtek) — will be brought up automatically")
    fi

    # Ubertooth One (passive BLE sniffer, pairs great with bettercap for other modules)
    if lsusb 2>/dev/null | grep -q '1d50:6002'; then
        if command -v ubertooth-btle >/dev/null 2>&1; then
            devs+=("ubertooth")
            descs+=("Ubertooth One — passive BLE sniffing (ubertooth-btle). Use alongside bettercap.")
        fi
    fi

    # Raytac / Nordic nRF Sniffer dongle (1915:522a)
    if lsusb 2>/dev/null | grep -q '1915:522a'; then
        devs+=("raytac-nrf")
        descs+=("Raytac / nRF Sniffer (1915:522a) — for sniffer mode + Kismet/Wireshark. For bettercap ble.recon put it in normal HCI mode or use built-in.")
    fi

    # Always offer a generic "default / autodetect"
    devs+=("default")
    descs+=("Autodetect / default adapter (let bettercap + BlueZ decide)")

    # If nothing at all
    if [ ${#devs[@]} -eq 0 ]; then
        devs+=("default")
        descs+=("No devices detected — will use bettercap defaults")
    fi

    # Return as two parallel arrays via global
    DETECTED_DEVS=("${devs[@]}")
    DETECTED_DESCS=("${descs[@]}")
}

# Present device chooser (zenity)
choose_device() {
    detect_devices

    local zenity_args=()
    for i in "${!DETECTED_DEVS[@]}"; do
        zenity_args+=("FALSE" "${DETECTED_DEVS[$i]}" "${DETECTED_DESCS[$i]}")
    done

    local choice
    choice=$(zenity --list \
        --title="Bettercap BLE Launcher — Choose Device" \
        --text="Select the Bluetooth hardware to target.\n\n• hci* entries → bettercap will set ble.device and use it for active BLE recon (scanning, enumeration, GATT).\n• Ubertooth → great for passive wide spectrum BLE capture (run ubertooth-btle in parallel).\n• Raytac nRF → usually used in sniffer mode with Kismet/Wireshark (bettercap prefers standard HCI).\n" \
        --radiolist \
        --column="Select" --column="ID" --column="Description" \
        --width=720 --height=320 \
        "${zenity_args[@]}" 2>/dev/null || true)

    echo "$choice"
}

# Build a nice list of presets (the "dropdown tool with all commands")
# We return the internal key; descriptions shown to user.
get_presets() {
    # Format for zenity: key|visible label|description
    # We'll split later.
    cat <<'EOF'
interactive|Full interactive bettercap shell|Start bettercap with device pre-configured (if applicable). Use tab-completion and "help" inside for every command.
ble-recon|BLE recon + show devices|set ble.device + ble.recon on; ble.show   (classic BLE discovery + services)
wifi-ble|WiFi + BLE recon together|wifi.recon on; ble.recon on  (great for combined wireless audits)
ble-ui|Bettercap Web UI (HTTP interface)|Launch with http-ui caplet (point browser at http://127.0.0.1:8080 or 8081)
ble-enum-example|Example: enum a specific device|ble.enum 00:11:22:33:44:55  (edit the MAC in the custom step or inside shell)
ubertooth-follow|Ubertooth: follow active BLE connections|sudo ubertooth-btle -f   (passive, great next to bettercap)
ubertooth-advert|Ubertooth: advertisements only (fast scan)|sudo ubertooth-btle -n
ubertooth-promisc|Ubertooth: promiscuous (all connections)|sudo ubertooth-btle -p
install-bettercap|Install / Update bettercap + caplets + UI|Uses pkexec so you get a graphical password prompt. Run this first if bettercap is missing.
custom|Custom command or eval|Free text entry — type any bettercap args, -eval '...', or full command line.
EOF
}

choose_preset() {
    local dev_id="$1"

    # Dynamic text hint
    local hint="Device: ${dev_id}\nSelect a preset action. 'Full interactive' gives you the complete bettercap experience (all modules + commands via help / tab)."
    if [[ "$dev_id" == "ubertooth" ]]; then
        hint="${hint}\n(Ubertooth selected: the presets below launch ubertooth-btle. You can also start bettercap separately for its other features.)"
    fi

    local selection
    selection=$(zenity --list \
        --title="Bettercap — ${dev_id}" \
        --text="${hint}" \
        --column="Key" --column="Action / Preset" --column="What it does" \
        --width=820 --height=480 \
        --hide-column=1 \
        $(get_presets | awk -F'|' '{print $1, $2, $3}') 2>/dev/null || true)

    echo "$selection"
}

# For custom, get free-form input
get_custom_command() {
    local default="$1"
    local entry
    entry=$(zenity --entry \
        --title="Bettercap Custom Command" \
        --text="Enter full command or bettercap arguments.\nExamples:\n  bettercap\n  bettercap -eval 'set ble.device 0; ble.recon on; ble.show'\n  bettercap -caplet http-ui" \
        --entry-text="$default" \
        --width=600 2>/dev/null || true)
    echo "$entry"
}

# Construct the actual command string to run based on device + preset key
build_command() {
    local dev="$1"
    local preset="$2"

    local base_sudo="sudo"
    local bettercap_cmd="bettercap"

    # Check if bettercap exists (we still allow install option)
    if ! command -v bettercap >/dev/null 2>&1; then
        if [[ "$preset" != "install-bettercap" ]]; then
            zenity --warning --title="bettercap not installed" \
                   --text="bettercap is not in PATH yet.\n\nChoose the 'Install / Update bettercap' preset (it uses a graphical pkexec prompt) or install manually with:\n\nsudo apt update && sudo apt install -y bettercap bettercap-caplets bettercap-ui" \
                   --width=520 2>/dev/null || true
        fi
    fi

    case "$preset" in
        install-bettercap)
            # Graphical privileged install
            echo "pkexec bash -c 'apt-get update && apt-get install -y bettercap bettercap-caplets bettercap-ui && echo \"Install complete. You can now launch bettercap from the menu.\" || echo \"Install failed or was cancelled.\"'; read -p 'Press Enter to close...'"
            return
            ;;

        interactive)
            if [[ "$dev" =~ ^hci ]]; then
                local idx="${dev#hci}"
                echo "${base_sudo} ${bettercap_cmd} -eval \"set ble.device ${idx}; net.recon off; events.stream off; ble.recon on\" "
            elif [[ "$dev" == "default" ]]; then
                echo "${base_sudo} ${bettercap_cmd} -eval \"ble.recon on\" "
            else
                # ubertooth / raytac-nrf → still give full interactive bettercap (user can combine with ubertooth tools)
                echo "${base_sudo} ${bettercap_cmd}"
            fi
            ;;

        ble-recon)
            if [[ "$dev" =~ ^hci ]]; then
                local idx="${dev#hci}"
                echo "${base_sudo} ${bettercap_cmd} -eval \"set ble.device ${idx}; ble.recon on; ble.show\" "
            else
                echo "${base_sudo} ${bettercap_cmd} -eval \"ble.recon on; ble.show\" "
            fi
            ;;

        wifi-ble)
            if [[ "$dev" =~ ^hci ]]; then
                local idx="${dev#hci}"
                echo "${base_sudo} ${bettercap_cmd} -eval \"set ble.device ${idx}; wifi.recon on; ble.recon on\" "
            else
                echo "${base_sudo} ${bettercap_cmd} -eval \"wifi.recon on; ble.recon on\" "
            fi
            ;;

        ble-ui)
            if [[ "$dev" =~ ^hci ]]; then
                local idx="${dev#hci}"
                echo "${base_sudo} ${bettercap_cmd} -caplet http-ui -eval \"set ble.device ${idx}\" "
            else
                echo "${base_sudo} ${bettercap_cmd} -caplet http-ui "
            fi
            ;;

        ble-enum-example)
            if [[ "$dev" =~ ^hci ]]; then
                local idx="${dev#hci}"
                echo "${base_sudo} ${bettercap_cmd} -eval \"set ble.device ${idx}; ble.recon on; ble.enum 00:11:22:33:44:55\" ; echo 'Edit the MAC address inside the shell or re-run with custom.'"
            else
                echo "${base_sudo} ${bettercap_cmd} -eval \"ble.recon on; ble.enum 00:11:22:33:44:55\" ; echo 'Replace the example MAC and re-run or use the interactive shell.'"
            fi
            ;;

        ubertooth-follow)
            echo "${base_sudo} ubertooth-btle -f"
            ;;

        ubertooth-advert)
            echo "${base_sudo} ubertooth-btle -n"
            ;;

        ubertooth-promisc)
            echo "${base_sudo} ubertooth-btle -p"
            ;;

        custom)
            local default_cmd
            if [[ "$dev" =~ ^hci ]]; then
                local idx="${dev#hci}"
                default_cmd="bettercap -eval 'set ble.device ${idx}; ble.recon on'"
            else
                default_cmd="bettercap"
            fi
            local user_cmd
            user_cmd=$(get_custom_command "$default_cmd")
            if [[ -z "${user_cmd}" ]]; then
                echo "echo 'No custom command entered.'; read -p 'Press Enter...'"
            else
                # If it doesn't start with sudo or bettercap, prefix reasonably
                if [[ "$user_cmd" != sudo* && "$user_cmd" != bettercap* && "$user_cmd" != ubertooth* ]]; then
                    echo "${base_sudo} ${user_cmd}"
                else
                    echo "${user_cmd}"
                fi
            fi
            ;;

        *)
            # Fallback to interactive
            echo "${base_sudo} ${bettercap_cmd}"
            ;;
    esac
}

# Main flow
main() {
    preflight_sudo

    local device
    device=$(choose_device)

    if [[ -z "$device" ]]; then
        echo "No device selected. Exiting."
        exit 0
    fi

    local preset
    preset=$(choose_preset "$device")

    if [[ -z "$preset" ]]; then
        echo "No action selected. Exiting."
        exit 0
    fi

    local cmd_to_run
    cmd_to_run=$(build_command "$device" "$preset")

    if [[ -z "$cmd_to_run" ]]; then
        cmd_to_run="echo 'Nothing to run.'; read -p 'Press Enter to close...'"
    fi

    # Special case: some ubertooth commands are short — still launch in term so output is visible
    local title="Bettercap / BLE — ${device}"
    if [[ "$preset" == install-bettercap ]]; then
        title="Install bettercap"
    fi

    launch_in_terminal "$cmd_to_run" "$title"
}

# Only run main when executed directly (not when sourced for testing functions)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
