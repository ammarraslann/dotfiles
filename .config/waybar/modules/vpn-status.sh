#!/bin/bash
mullvad_status=$(mullvad status 2>/dev/null | tr '\n' ' ' | tr -s ' ')
gpclient_running=$(pgrep gpclient)

if [ -n "$gpclient_running" ]; then
  echo "{\"text\":\" NEU\", \"alt\":\"neu\", \"tooltip\":\"Connected to Northeastern VPN\", \"class\":\"neu\"}"
elif echo "$mullvad_status" | grep -q "Connected"; then
  echo "{\"text\":\" Mullvad\", \"alt\":\"mullvad\", \"tooltip\":\"$mullvad_status\", \"class\":\"mullvad\"}"
elif echo "$mullvad_status" | grep -q "Connecting\|Disconnected"; then
  echo "{\"text\":\" VPN\", \"alt\":\"disconnected\", \"tooltip\":\"$mullvad_status\", \"class\":\"disconnected\"}"
else
  echo "{\"text\":\" VPN\", \"alt\":\"disconnected\", \"tooltip\":\"No VPN connected\", \"class\":\"disconnected\"}"
fi
