#!/usr/bin/env bash

# KVM Switch Script for GPD Pocket 4
# This script toggles between normal display and KVM input

# Function to kill all video-related processes
kill_video_processes() {
    # Kill any processes using video devices or ffmpeg
    pkill -f "mpv.*video" 2>/dev/null
    pkill -f "ffmpeg.*video" 2>/dev/null
    pkill -f "mpv.*kvm-input" 2>/dev/null
    sleep 2  # Give it time to release the device
}

# Check if KVM viewer is running
if pgrep -f "mpv.*kvm-input" > /dev/null || pgrep -f "mpv.*video" > /dev/null || pgrep -f "ffmpeg.*video" > /dev/null; then
    # KVM viewer is running, so kill it to return to normal display
    kill_video_processes
    
    
    notify-send "KVM Mode" "Switched to normal display" -i display
    echo "Switched to normal display"
else
    # Make sure no processes are using the video device
    kill_video_processes
    
    # First check if the device exists
    if [ -e /dev/kvm-input ] || ls /dev/video* > /dev/null 2>&1; then
        # Find the KVM input device
        if [ -e /dev/kvm-input ]; then
            KVM_DEVICE="/dev/kvm-input"
        else
            # Try to find the HDMI capture device
            for device in /dev/video*; do
                if v4l2-ctl --device="$device" --all 2>/dev/null | grep -q "HDMI Capture"; then
                    KVM_DEVICE="$device"
                    break
                fi
            done
            
            # If no device found, use video3 as fallback
            if [ -z "$KVM_DEVICE" ]; then
                if [ -e /dev/video3 ]; then
                    KVM_DEVICE="/dev/video3"
                else
                    echo "No KVM input device found"
                    exit 1
                fi
            fi
        fi
        
        # Switch to workspace 10
        KVM_WORKSPACE=10
        hyprctl dispatch workspace $KVM_WORKSPACE
        
        # Create a named pipe for ffmpeg to mpv communication
        PIPE_PATH="/tmp/kvm_pipe_$$.fifo"
        rm -f "$PIPE_PATH"
        mkfifo "$PIPE_PATH"
        
        # Start MPV reading from the pipe
        mpv --profile=low-latency \
            --no-cache \
            --untimed \
            --no-demuxer-thread \
            --no-fullscreen \
            --title="KVM Input" \
            --force-window=yes \
            --hwdec=auto \
            "$PIPE_PATH" &
        
        # Give MPV time to start
        sleep 0.5
        
        # Start ffmpeg to process the video and write to the pipe
        # This approach provides better handling of corrupted frames
        ffmpeg -hide_banner -loglevel error \
            -f v4l2 \
            -input_format mjpeg \
            -framerate 60 \
            -video_size 2560x1600 \
            -i "$KVM_DEVICE" \
            -c:v rawvideo \
            -pix_fmt yuv420p \
            -f matroska \
            -y "$PIPE_PATH" &
        
        # Get the window ID and move it to the KVM workspace
        sleep 1  # Wait for MPV to start
        KVM_WINDOW_ID=$(hyprctl clients | grep "KVM Input" | awk '{print $1}')
        if [ -n "$KVM_WINDOW_ID" ]; then
            hyprctl dispatch movetoworkspace "$KVM_WORKSPACE,address:$KVM_WINDOW_ID"
            echo "Window moved to workspace $KVM_WORKSPACE"
        else
            echo "KVM window not found, but it should appear shortly"
        fi
        
        notify-send "KVM Mode" "Switched to KVM input using $KVM_DEVICE on workspace $KVM_WORKSPACE" -i display
        echo "Switched to KVM input using $KVM_DEVICE on workspace $KVM_WORKSPACE"
        
        
        # Wait a moment for the MPV window to fully initialize
        sleep 2
        
    else
        echo "No video devices found"
        exit 1
    fi
    
    # Add a cleanup trap to remove the pipe when the script exits
    trap "rm -f $PIPE_PATH 2>/dev/null" EXIT
fi
