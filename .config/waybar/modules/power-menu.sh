#!/usr/bin/env bash
chosen=$(printf "  Sleep\n  Reboot\n  Shutdown\n  Logout\n  Lock" |
  wofi --dmenu --prompt "Session" --width 200 --height 230 --no-actions --insensitive)
case "$chosen" in
"  Sleep") systemctl suspend ;;
"  Reboot") systemctl reboot ;;
"  Shutdown") systemctl poweroff ;;
"  Logout") loginctl terminate-user "" ;;
"  Lock") hyprlock ;;
esac
