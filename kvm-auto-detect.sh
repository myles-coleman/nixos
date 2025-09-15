#!/usr/bin/env bash
#
# Auto-detect KVM connection and start touchscreen forwarding
# This script monitors for HDMI capture device and USB-C connection
#

LOG_FILE="/tmp/kvm-auto-detect.log"

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to check if KVM HDMI is connected
check_hdmi_connected() {
    # Check for HDMI capture device
    if [ -e /dev/kvm-input ] || [ -e /dev/video3 ]; then
        # Check if device is actually available
        if v4l2-ctl --device=/dev/video3 --all 2>/dev/null | grep -q "HDMI"; then
            return 0
        fi
    fi
    
    # Check for any video capture device
    for device in /dev/video*; do
        if [ -e "$device" ]; then
            if v4l2-ctl --device="$device" --all 2>/dev/null | grep -q "HDMI Capture"; then
                return 0
            fi
        fi
    done
    
    return 1
}

# Function to check if USB-C is in gadget mode
check_usb_gadget_mode() {
    # Check if any USB gadget is configured
    if [ -d /sys/kernel/config/usb_gadget/*/UDC ]; then
        for udc in /sys/kernel/config/usb_gadget/*/UDC; do
            if [ -n "$(cat "$udc" 2>/dev/null)" ]; then
                return 0
            fi
        done
    fi
    
    # Alternative: check if USB is in device mode (not host)
    if [ -e /sys/class/udc ]; then
        if [ -n "$(ls /sys/class/udc/ 2>/dev/null)" ]; then
            return 0
        fi
    fi
    
    return 1
}

# Function to check KVM state
is_kvm_active() {
    # Check if HDMI capture is connected AND we might be in KVM mode
    if check_hdmi_connected; then
        log_msg "HDMI capture device detected"
        return 0
    fi
    return 1
}

# Function to start KVM mode with touchscreen
start_kvm_with_touch() {
    log_msg "Starting KVM mode with touchscreen forwarding..."
    
    # Start video display
    if [ -f /home/bee/nixos/kvm-switch.sh ]; then
        /home/bee/nixos/kvm-switch.sh &
    fi
    
    # Wait a moment for video to start
    sleep 2
    
    # Start touchscreen forwarding
    # Try USB gadget first
    if [ -f /home/bee/nixos/kvm-touch-gadget.sh ]; then
        if sudo /home/bee/nixos/kvm-touch-gadget.sh start 2>&1 | tee -a "$LOG_FILE"; then
            log_msg "USB HID touchscreen gadget started successfully"
            return 0
        fi
    fi
    
    # Fallback to evdev forwarding
    if [ -f /home/bee/nixos/kvm-touch-forward.py ]; then
        python3 /home/bee/nixos/kvm-touch-forward.py >> "$LOG_FILE" 2>&1 &
        echo $! > /tmp/touch_forward.pid
        log_msg "Evdev touchscreen forwarding started (PID: $(cat /tmp/touch_forward.pid))"
        return 0
    fi
    
    log_msg "Warning: No touchscreen forwarding method available"
    return 1
}

# Function to stop KVM mode
stop_kvm_mode() {
    log_msg "Stopping KVM mode..."
    
    # Kill video processes
    pkill -f "mpv.*kvm-input" 2>/dev/null
    pkill -f "mpv.*video" 2>/dev/null
    pkill -f "ffmpeg.*video" 2>/dev/null
    
    # Stop touchscreen forwarding
    if [ -f /tmp/touch_forward.pid ]; then
        PID=$(cat /tmp/touch_forward.pid)
        if kill -0 "$PID" 2>/dev/null; then
            kill "$PID"
            log_msg "Touchscreen forwarding stopped"
        fi
        rm -f /tmp/touch_forward.pid
    fi
    
    # Stop USB gadget
    if [ -f /home/bee/nixos/kvm-touch-gadget.sh ]; then
        sudo /home/bee/nixos/kvm-touch-gadget.sh stop 2>/dev/null || true
    fi
}

# Main monitoring loop
main_loop() {
    log_msg "KVM auto-detection started"
    
    KVM_ACTIVE=false
    LAST_CHECK=""
    
    while true; do
        # Check every 2 seconds
        sleep 2
        
        if is_kvm_active; then
            if [ "$KVM_ACTIVE" = false ]; then
                log_msg "KVM connection detected!"
                KVM_ACTIVE=true
                start_kvm_with_touch
                
                # Send notification
                notify-send "KVM Auto-Detect" "KVM mode activated with touchscreen" -i video-display
            fi
        else
            if [ "$KVM_ACTIVE" = true ]; then
                log_msg "KVM disconnected"
                KVM_ACTIVE=false
                stop_kvm_mode
                
                # Send notification
                notify-send "KVM Auto-Detect" "KVM mode deactivated" -i video-display
            fi
        fi
    done
}

# Handle script arguments
case "${1:-}" in
    start)
        log_msg "Starting KVM auto-detection service..."
        main_loop
        ;;
    stop)
        log_msg "Stopping KVM auto-detection..."
        pkill -f "kvm-auto-detect.sh start" 2>/dev/null || true
        stop_kvm_mode
        ;;
    once)
        # Run detection once
        if is_kvm_active; then
            log_msg "KVM detected, starting..."
            start_kvm_with_touch
        else
            log_msg "No KVM connection detected"
        fi
        ;;
    status)
        if pgrep -f "kvm-auto-detect.sh start" > /dev/null; then
            echo "KVM auto-detection is running"
            if is_kvm_active; then
                echo "KVM connection: ACTIVE"
            else
                echo "KVM connection: INACTIVE"
            fi
        else
            echo "KVM auto-detection is not running"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|once|status}"
        echo ""
        echo "  start  - Start monitoring for KVM connection"
        echo "  stop   - Stop monitoring and KVM mode"
        echo "  once   - Check once and start if detected"
        echo "  status - Show current status"
        exit 1
        ;;
esac
