#!/usr/bin/env bash
# Toggle wvkbd on-screen keyboard with overlay and transparency

WVKBD_BIN="/home/bee/wvkbd/wvkbd-deskintl"
WVKBD_OPTS="--non-exclusive -l full,special,hyprland"

# Check if wvkbd is running
if pgrep -x "wvkbd-deskintl" > /dev/null; then
    # Kill all wvkbd instances
    pkill -x "wvkbd-deskintl"
    echo "wvkbd stopped"
else
    # Start wvkbd in overlay mode (non-exclusive)
    # The --non-exclusive flag makes it overlay without taking window space
    # Transparency is configured in config.deskintl.h
    $WVKBD_BIN $WVKBD_OPTS &
    echo "wvkbd started"
fi
