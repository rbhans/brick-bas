#!/bin/zsh
# Renders tools/demo_video.gd with Godot's Movie Maker (every frame at a fixed
# 60 fps, so pacing is exact however long rendering takes) and encodes an MP4.
# Usage: tools/render_demo_video.sh [output.mp4]
set -e
cd "$(dirname "$0")/.."
out=${1:-docs/demo-video/brick-bas-gameplay.mp4}
godot=${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}
work=$(mktemp -d)
mkdir -p "$(dirname "$out")"
# Record at 1920x1080 (the project's window override is 1280x800).
cat > override.cfg <<CFG
[display]
window/size/window_width_override=1920
window/size/window_height_override=1080
CFG
trap 'rm -f override.cfg' EXIT
"$godot" --path . --resolution 1920x1080 --fixed-fps 60 --write-movie "$work/raw.avi" --script res://tools/demo_video.gd
ffmpeg -y -loglevel error -i "$work/raw.avi" -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -c:a aac -b:a 160k -movflags +faststart "$out"
rm -rf "$work"
echo "Demo video: $out"
