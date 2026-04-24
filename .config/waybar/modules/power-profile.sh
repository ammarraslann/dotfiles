#!/bin/bash
current=$(powerprofilesctl get)
case $current in
"balanced") powerprofilesctl set performance ;;
"performance") powerprofilesctl set power-saver ;;
"power-saver") powerprofilesctl set balanced ;;
esac
killall -SIGUSR2 waybar
