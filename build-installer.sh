#!/usr/bin/env bash
# Build custom installer ISO for bee-gpu-server

set -e

echo "=== Building bee-gpu-server installer ISO ==="
echo ""

# Format code first
echo "Formatting Nix code with alejandra..."
alejandra .

# Build the ISO
echo ""
echo "Building ISO image (this may take a while)..."
nix build .#bee-gpu-server-iso

# Show result
echo ""
echo "Build complete!"
echo ""
echo "ISO location: ./result/iso/*.iso"
ls -lh ./result/iso/*.iso
echo ""
echo "To write to USB/SD card:"
echo "  sudo dd if=./result/iso/*.iso of=/dev/sdX bs=4M status=progress"
echo "  (Replace /dev/sdX with your USB/SD device)"
echo ""
