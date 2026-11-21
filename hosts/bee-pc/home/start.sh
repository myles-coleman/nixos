#!/usr/bin/env bash

nm-applet --indicator &

# Waybar runs as a systemd user unit so systemd restarts it after a crash
# (libpulse aborts it when PipeWire restarts). greetd does not set up
# graphical-session.target, so hand the compositor environment over and
# restart the unit — restart, not start, so a bar left over from the
# previous session is replaced.
systemctl --user import-environment WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE PATH
systemctl --user restart waybar.service

dunst &

hyprpaper
