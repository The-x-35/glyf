#!/bin/bash
# Turns a simulator screen recording into a 9:16 clip for Reels, TikTok and
# the App Store preview slot.
#
#   1. record   xcrun simctl io <udid> recordVideo --codec h264 raw.mov
#   2. this     tools/reels/make_reel.sh raw.mov out.mp4 "Headline" "Kicker"
#
# What it does: drops the dead frames between taps (driving a simulator by
# hand leaves seconds of nothing, and mpdecimate turns 70s of tapping into
# 7s of motion), crops to the keyboard — which is the product — scales to
# 1080x1920 on the brand ground, and lays a rendered caption over the top.
set -euo pipefail

RAW="${1:?raw recording}"
OUT="${2:?output mp4}"
HEADLINE="${3:?headline}"
KICKER="${4:-}"

DIR="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1. Cut the waiting.
ffmpeg -y -v error -i "$RAW" \
  -vf "mpdecimate=hi=64*12:lo=64*5:frac=0.33,setpts=N/FRAME_RATE/TB" \
  -an -c:v h264 -crf 20 "$TMP/tight.mp4"

# 2. Caption layer (Inter, the app's own face).
python3 "$DIR/caption.py" "$TMP/cap.png" "$HEADLINE" "$KICKER"

# 3. Crop to the keyboard, place it on the brand ground, lay the caption on.
#    The crop assumes a 1206x2622 capture (iPhone 17 Pro); pass CROP=... to
#    override for another device.
CROP="${CROP:-1206:1390:0:1232}"
ffmpeg -y -v error -i "$TMP/tight.mp4" -i "$TMP/cap.png" -filter_complex \
  "[0:v]crop=$CROP,scale=1080:-2[kb];color=0xF4F5F8:1080x1920[bgc];\
[bgc][kb]overlay=0:520:shortest=1[bg];[bg][1:v]overlay=0:0" \
  -c:v h264 -crf 20 -pix_fmt yuv420p "$OUT"

echo "wrote $OUT ($(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT")s)"
