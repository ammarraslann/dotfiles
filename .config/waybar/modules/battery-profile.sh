#!/bin/bash
profile=$(powerprofilesctl get)
capacity=$(cat /sys/class/power_supply/BAT0/capacity)
status=$(cat /sys/class/power_supply/BAT0/status)

case $profile in
"power-saver") css="power-saver" ;;
"balanced") css="balanced" ;;
"performance") css="performance" ;;
esac

if [ "$status" = "Charging" ]; then
  icon=" ${capacity}%"
elif [ "$status" = "Full" ]; then
  icon=" ${capacity}%"
else
  icon=" ${capacity}%"
fi

echo "{\"text\":\"$icon\", \"alt\":\"$css\", \"tooltip\":\"$profile — ${capacity}%\", \"class\":\"$css\"}"
