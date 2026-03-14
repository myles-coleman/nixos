#!/usr/bin/env bash

swww init &

swww-daemon & sleep 0.1 && swww img ~/Wallpapers/wallpaper4.jpg &

nm-applet --indicator &

waybar &

dunst
