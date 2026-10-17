#!/usr/bin/env bash

# KVM Switch Script for GPD Pocket 4
#
# Toggles an mpv + ffmpeg view of the HDMI capture ("KVM input") device and
# reports that state to waybar.
#
# Usage:
#   kvm-switch.sh          # toggle view on/off (waybar on-click)
#   kvm-switch.sh start
#   kvm-switch.sh stop
#   kvm-switch.sh status   # emits a waybar JSON module (waybar exec)
#
# Design notes:
#   * No pgrep/pkill -f. `pgrep -f` scans /proc/<pid>/cmdline, which blocks
#     forever if any process is stuck in uninterruptible (D) state holding the
#     mmap lock — e.g. an amdgpu HMM deadlock. A waybar module polling that every
#     few seconds then leaks one stuck process per interval. The old regex
#     ("mpv.*kvm-input") also never matched this script's own mpv, whose command
#     line contains `--title="KVM Input"` and a `kvm_pipe_*.fifo` path (# vs -).
#     Children are now tracked by PID in a state dir and probed with `kill -0`.
#   * A watchdog tears the pipeline down if the capture device is unplugged, so
#     we don't leave orphaned mpv/ffmpeg behind when the HDMI source disappears.

set -uo pipefail

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/kvm-input"
MPV_PID="$RUNTIME_DIR/mpv.pid"
FFMPEG_PID="$RUNTIME_DIR/ffmpeg.pid"
WATCHDOG_PID="$RUNTIME_DIR/watchdog.pid"
PIPE_PATH="$RUNTIME_DIR/fifo"
KVM_WORKSPACE=10
VIDEO_SIZE=2560x1600
FRAMERATE=60

# --- helpers ---------------------------------------------------------------

# alive <pidfile> — true if the pid recorded in <pidfile> is still running
alive() {
    local pid
    pid=$(cat "$1" 2>/dev/null) || return 1
    [ -n "$pid" ] || return 1
    kill -0 "$pid" 2>/dev/null
}

# stop_pidfile <pidfile> — terminate the recorded process, escalating to KILL
stop_pidfile() {
    local pid tries=0
    [ -r "$1" ] || return 0
    pid=$(cat "$1" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill -TERM "$pid" 2>/dev/null
        while kill -0 "$pid" 2>/dev/null && [ "$tries" -lt 20 ]; do
            sleep 0.1
            tries=$((tries + 1))
        done
        kill -KILL "$pid" 2>/dev/null
    fi
    rm -f "$1"
}

find_device() {
    if [ -e /dev/kvm-input ]; then
        printf '%s\n' /dev/kvm-input
        return 0
    fi
    local device name
    for device in /dev/video*; do
        [ -c "$device" ] || continue
        name=$(cat "/sys/class/video4linux/$(basename "$device")/name" 2>/dev/null || echo "")
        case "$name" in
        *"HDMI Capture"*)
            # Confirm the node actually offers capture (skip metadata nodes)
            if timeout 5 ffmpeg -hide_banner -f v4l2 -list_formats all -i "$device" 2>&1 |
                grep -q "Compressed\|Raw"; then
                printf '%s\n' "$device"
                return 0
            fi
            ;;
        esac
    done
    return 1
}

# Tear the pipeline down. Silent — callers emit the user-facing message.
stop_kvm() {
    stop_pidfile "$FFMPEG_PID"
    stop_pidfile "$MPV_PID"
    rm -f "$PIPE_PATH"
}

# Watch the capture device and tear everything down if it is unplugged.
# This is what prevents orphaned mpv/ffmpeg when the HDMI source goes away.
start_watchdog() {
    local device="$1"
    (
        while [ -e "$device" ]; do
            sleep 1
        done
        stop_pidfile "$FFMPEG_PID"
        stop_pidfile "$MPV_PID"
        rm -f "$PIPE_PATH" "$WATCHDOG_PID"
        notify-send "KVM Mode" "KVM input device disconnected" -i dialog-warning 2>/dev/null
    ) &
    echo $! >"$WATCHDOG_PID"
}

start_kvm() {
    local device
    device=$(find_device) || {
        echo "No KVM input device found with capture capability"
        notify-send "KVM Mode" "No KVM input device found" -i dialog-error 2>/dev/null
        exit 1
    }

    mkdir -p "$RUNTIME_DIR"
    stop_kvm # clear any stale state before we start

    # Switch to the KVM workspace
    hyprctl dispatch workspace "$KVM_WORKSPACE" >/dev/null 2>&1

    # Named pipe carrying ffmpeg's output into mpv
    rm -f "$PIPE_PATH"
    mkfifo "$PIPE_PATH"

    # Start mpv reading from the pipe
    mpv --profile=low-latency \
        --no-cache \
        --untimed \
        --no-demuxer-thread \
        --no-fullscreen \
        --title="KVM Input" \
        --force-window=yes \
        --hwdec=auto-copy \
        "$PIPE_PATH" >/dev/null 2>&1 &
    echo $! >"$MPV_PID"

    # Give mpv time to start
    sleep 0.5

    # Start ffmpeg to capture from the device and write to the pipe.
    # The raw output gives better handling of corrupted frames.
    ffmpeg -hide_banner -loglevel error \
        -f v4l2 \
        -input_format mjpeg \
        -framerate "$FRAMERATE" \
        -video_size "$VIDEO_SIZE" \
        -i "$device" \
        -c:v rawvideo \
        -pix_fmt yuv420p \
        -f matroska \
        -y "$PIPE_PATH" >/dev/null 2>&1 &
    echo $! >"$FFMPEG_PID"

    start_watchdog "$device"

    # Move the mpv window onto the KVM workspace. `hyprctl clients` lines are
    # "Window <address> -> <title>:", so the address is field 2.
    sleep 1
    local window_id
    window_id=$(hyprctl clients | awk '/KVM Input/ {print $2; exit}')
    if [ -n "$window_id" ]; then
        hyprctl dispatch movetoworkspace "$KVM_WORKSPACE,address:$window_id" >/dev/null 2>&1
        echo "Window moved to workspace $KVM_WORKSPACE"
    else
        echo "KVM window not found, but it should appear shortly"
    fi

    notify-send "KVM Mode" "Switched to KVM input using $device on workspace $KVM_WORKSPACE" -i display 2>/dev/null
    echo "Switched to KVM input using $device on workspace $KVM_WORKSPACE"
}

status() {
    if alive "$MPV_PID" || alive "$FFMPEG_PID"; then
        echo '{"text": "Active", "class": "active", "alt": "active"}'
    else
        echo '{"text": "Inactive", "class": "inactive", "alt": "inactive"}'
    fi
}

# --- entry point -----------------------------------------------------------

case "${1:-toggle}" in
status)
    status
    ;;
stop)
    stop_pidfile "$WATCHDOG_PID"
    stop_kvm
    notify-send "KVM Mode" "Switched to normal display" -i display 2>/dev/null
    echo "Switched to normal display"
    ;;
start)
    start_kvm
    ;;
toggle)
    if alive "$MPV_PID" || alive "$FFMPEG_PID"; then
        stop_pidfile "$WATCHDOG_PID"
        stop_kvm
        notify-send "KVM Mode" "Switched to normal display" -i display 2>/dev/null
        echo "Switched to normal display"
    else
        start_kvm
    fi
    ;;
*)
    echo "usage: $(basename "$0") [toggle|start|stop|status]" >&2
    exit 2
    ;;
esac
