#!/bin/bash
# Launch Bettercap with BLE focus + Web UI for pentesting
set -e
echo "[*] Starting Bettercap BLE pentest session with Web UI..."
echo "[*] Web UI will be at http://127.0.0.1:8080 (or check output)"
echo "[*] In the UI or console use: ble.recon on ; ble.show ; etc."
echo ""
# Start bettercap in background with http-ui caplet, focusing BLE
bettercap -caplet http-ui -eval "ble.recon on" &
BETTERCAP_PID=$!
sleep 3
# Open browser to UI (use xdg-open or sensible-browser)
if command -v xdg-open >/dev/null; then
  xdg-open "http://127.0.0.1:8080" 2>/dev/null || true
elif command -v sensible-browser >/dev/null; then
  sensible-browser "http://127.0.0.1:8080" 2>/dev/null || true
fi
echo "[*] Bettercap running (PID $BETTERCAP_PID). Use the web UI or attach with 'bettercap -caplet http-ui'."
echo "[*] To stop: kill $BETTERCAP_PID or pkill bettercap"
wait $BETTERCAP_PID || true
