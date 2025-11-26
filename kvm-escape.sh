#!/usr/bin/env bash

# KVM Escape Script for GPD Pocket 4
# This script forcefully kills all KVM-related processes

# Kill all video-related processes
pkill -f "mpv.*video" 2>/dev/null
pkill -f "ffmpeg.*video" 2>/dev/null
pkill -f "mpv.*kvm-input" 2>/dev/null

# Remove any leftover pipes
rm -f /tmp/kvm_pipe_*.fifo 2>/dev/null

# Notify user
notify-send "KVM Mode" "Forcefully exited KVM mode" -i display
echo "Forcefully exited KVM mode"

# Switch back to workspace 1 (or any default workspace)
hyprctl dispatch workspace 1
