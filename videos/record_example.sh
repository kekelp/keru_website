#!/usr/bin/env bash
# record_example.sh <example-name> [out.mp4]
#
# Launches a cargo example, records its window with ffmpeg (X11),
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
keru_manifest="$script_dir/../../keru/Cargo.toml"
if [[ ! -f "$keru_manifest" ]]; then
    echo "cannot find keru Cargo.toml at $keru_manifest" >&2
    exit 1
fi

# If the output already exists, rename it out of the way instead of overwriting.
if [[ -e "$out" ]]; then
    ts="$(date +%Y%m%d-%H%M%S)"
    backup="${out%.mp4}.$ts.mp4"
    mv "$out" "$backup"
    echo "renamed existing $out -> $backup"
fi

# Build first so the compile step doesn't race the window-detection poll.
echo "building $ex ..."
cargo build --manifest-path "$keru_manifest" --example "$ex"

# Snapshot existing visible windows.
mapfile -t before < <(xdotool search --onlyvisible "" 2>/dev/null || true)

# Launch the example.
cargo run --manifest-path "$keru_manifest" --example "$ex" &
cargo_pid=$!

# Wait for a NEW visible window to appear.
wid=""
for _ in $(seq 1 150); do
    while read -r w; do
        [[ -z "$w" ]] && continue
        found=0
        for b in "${before[@]}"; do
            [[ "$w" == "$b" ]] && { found=1; break; }
        done
        if [[ $found -eq 0 ]]; then
            wid="$w"
            break
        fi
    done < <(xdotool search --onlyvisible "" 2>/dev/null || true)
    [[ -n "$wid" ]] && break
    sleep 0.2
done

if [[ -z "$wid" ]]; then
    echo "no window appeared" >&2
    kill "$cargo_pid" 2>/dev/null || true
    exit 1
fi

# Let the window finish mapping/sizing, then read the client-area geometry.
# xwininfo's "Absolute upper-left" + width/height is the inner content area,
# excluding the WM title bar and borders.
sleep 0.3
info="$(xwininfo -id "$wid")"
X=$(awk '/Absolute upper-left X/ {print $4}' <<<"$info")
Y=$(awk '/Absolute upper-left Y/ {print $4}' <<<"$info")
WIDTH=$(awk '/Width:/ {print $2}' <<<"$info")
HEIGHT=$(awk '/Height:/ {print $2}' <<<"$info")
W=$(( WIDTH - WIDTH % 2 ))
H=$(( HEIGHT - HEIGHT % 2 ))

echo "recording window $wid (${W}x${H} at +${X},${Y}) -> $out"
ffmpeg -f x11grab -framerate 30 -video_size "${W}x${H}" -i ":0+${X},${Y}" \
    -c:v libx264 -preset veryfast -pix_fmt yuv420p "$out" &
ff_pid=$!

# Stop recording when the example exits (you close the window).
wait "$cargo_pid"
kill -INT "$ff_pid" 2>/dev/null || true
wait "$ff_pid" 2>/dev/null || true
echo "saved $out"
