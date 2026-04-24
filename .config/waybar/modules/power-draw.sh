#!/usr/bin/env bash
POWER_PATH="/sys/class/power_supply/BAT0/power_now"
[[ ! -f "$POWER_PATH" ]] && POWER_PATH="/sys/class/power_supply/BAT1/power_now"
if [[ ! -f "$POWER_PATH" ]]; then
  echo "{\"text\":\"\", \"tooltip\":\"No battery found\"}"
  exit 0
fi
STATUS_PATH="${POWER_PATH%power_now}status"
status=$(cat "$STATUS_PATH" 2>/dev/null)
raw=$(cat "$POWER_PATH" 2>/dev/null)
watts=$(echo "scale=1; $raw / 1000000" | bc)
if [[ "$status" == "Charging" ]]; then
  icon="⚡"
  tooltip="Charging at ${watts}W"
elif [[ "$status" == "Full" ]]; then
  icon="󱟢"
  tooltip="Fully charged"
  watts="0.0"
else
  icon="󰂄"
  tooltip="Discharging at ${watts}W"
fi
echo "{\"text\":\"$icon ${watts}W\", \"tooltip\":\"$tooltip\"}"
