#!/bin/bash
WALLPAPER_DIR="$HOME/Downloads/Backgrounds"
CACHE_DIR="$HOME/.cache/wallpapers"
mkdir -p "$CACHE_DIR"

wallpapers=("$WALLPAPER_DIR"/*)
current=$(cat ~/.cache/current_wallpaper 2>/dev/null)
total=${#wallpapers[@]}

current_index=0
for i in "${!wallpapers[@]}"; do
  [[ "${wallpapers[$i]}" == "$current" ]] && current_index=$i
done

next_index=$(((current_index + 1) % total))
next="${wallpapers[$next_index]}"

filename=$(basename "$next")
cached="$CACHE_DIR/$filename"

if [ ! -f "$cached" ]; then
  width=$(magick identify -format "%w" "$next" 2>/dev/null)
  height=$(magick identify -format "%h" "$next" 2>/dev/null)
  if [ "$height" -gt "$width" ]; then
    magick "$next" -rotate 90 -resize 2560x1440\> "$cached"
  else
    magick "$next" -resize 2560x1440\> "$cached"
  fi
fi

awww img "$cached" --resize fit
echo "$next" >~/.cache/current_wallpaper
notify-send "Wallpaper" "$filename"
