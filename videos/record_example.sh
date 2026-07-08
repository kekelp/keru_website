#!/usr/bin/env bash
# record_example.sh <example-name> [out.mp4]
#
# Launches a cargo example, records just its window with ffmpeg (X11),
# and stops automatically when you close the example.
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: bash record_example.sh <example-name> [out.mp4]" >&2
    exit 1
fi

ex="$1"
outdir="videos"
mkdir -p "$outdir"
out="$outdir/${2:-$ex.mp4}"

# The keru crate lives alongside this blog repo.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
keru_dir="$script_dir/../../keru"
if [[ ! -f "$keru_dir/Cargo.toml" ]]; then
    echo "cannot find keru Cargo.toml in $keru_dir" >&2
    exit 1
fi
# Resolve the output to an absolute path before we cd away.
out="$(cd "$outdir" && pwd)/$(basename "$out")"

# If the output already exists, rename it out of the way instead of overwriting.
if [[ -e "$out" ]]; then
    ts="$(date +%Y%m%d-%H%M%S)"
    backup="${out%.mp4}.$ts.mp4"
    mv "$out" "$backup"
    echo "renamed existing $out -> $backup"
fi

# Launch the example from inside the keru repo, so it runs exactly as it
# would there (picks up .cargo/config.toml, working-dir-relative paths, etc.).
( cd "$keru_dir" && cargo run --example "$ex" ) &
cargo_pid=$!

# Give the window a moment to appear, then grab the example's own window.
# The freshly launched example takes focus, so the active window is ours.
sleep 1
win="$(xdotool getactivewindow)"
# xwininfo reports the true absolute position on the root window, unlike
# xdotool's geometry X/Y which can be relative to the parent/decorations.
info="$(xwininfo -id "$win")"
X=$(echo "$info" | awk '/Absolute upper-left X/ {print $NF}')
Y=$(echo "$info" | awk '/Absolute upper-left Y/ {print $NF}')
WIDTH=$(echo "$info" | awk '/Width:/ {print $NF}')
HEIGHT=$(echo "$info" | awk '/Height:/ {print $NF}')
W=$(( WIDTH - WIDTH % 2 ))
H=$(( HEIGHT - HEIGHT % 2 ))

echo "recording ${W}x${H} at +${X},${Y} -> $out"
ffmpeg -f x11grab -framerate 30 -video_size "${W}x${H}" -i ":0+${X},${Y}" \
    -c:v libx264 -preset veryfast -pix_fmt yuv420p "$out" &
ff_pid=$!

# Stop recording when the example exits (you close the window).
wait "$cargo_pid"
kill -INT "$ff_pid" 2>/dev/null || true
wait "$ff_pid" 2>/dev/null || true
echo "saved $out"
