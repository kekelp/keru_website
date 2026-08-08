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

# Snapshot the managed top-level windows that exist *before* we launch, so we
# can tell which window is the one the example creates.
before="$(wmctrl -l | awk '{print $1}' | sort)"

# Launch the example from inside the keru repo, so it runs exactly as it
# would there (picks up .cargo/config.toml, working-dir-relative paths, etc.).
( cd "$keru_dir" && cargo run --example "$ex" ) &
cargo_pid=$!

# Wait until the example's own window actually appears, instead of guessing
# with a fixed sleep. We poll for a new managed window (one that wasn't in the
# pre-launch snapshot) and only start recording once it exists.
win=""
for _ in $(seq 1 600); do
    # If cargo died (compile error, panic before the window), bail out.
    if ! kill -0 "$cargo_pid" 2>/dev/null; then
        echo "example exited before a window appeared" >&2
        wait "$cargo_pid" || true
        exit 1
    fi
    after="$(wmctrl -l | awk '{print $1}' | sort)"
    new="$(comm -13 <(echo "$before") <(echo "$after") | head -n1)"
    if [[ -n "$new" ]]; then
        win="$new"
        break
    fi
    sleep 0.1
done
if [[ -z "$win" ]]; then
    echo "example window never appeared" >&2
    kill "$cargo_pid" 2>/dev/null || true
    exit 1
fi

# Give the window one extra moment to finish mapping / its open animation so
# the first recorded frames are the window itself, not the desktop behind it.
sleep 0.3

# Grab only the window's *client* (content) area. xwininfo on the managed
# window id reports the true absolute position of the content on the root
# window, which already excludes the title bar and border decorations, so the
# recording is just the window and none of the stuff around it.
info="$(xwininfo -id "$win")"
X=$(echo "$info" | awk '/Absolute upper-left X/ {print $NF}')
Y=$(echo "$info" | awk '/Absolute upper-left Y/ {print $NF}')
WIDTH=$(echo "$info" | awk '/Width:/ {print $NF}')
HEIGHT=$(echo "$info" | awk '/Height:/ {print $NF}')
W=$(( WIDTH - WIDTH % 2 ))
H=$(( HEIGHT - HEIGHT % 2 ))

# Record to a temp file first so we can trim the tail afterwards.
raw="${out%.mp4}.raw.mp4"
echo "recording ${W}x${H} at +${X},${Y} -> $out"
ffmpeg -f x11grab -framerate 30 -video_size "${W}x${H}" -i ":0+${X},${Y}" \
    -c:v libx264 -preset veryfast -pix_fmt yuv420p "$raw" &
ff_pid=$!

# Stop recording when the example exits (you close the window).
wait "$cargo_pid"
kill -INT "$ff_pid" 2>/dev/null || true
wait "$ff_pid" 2>/dev/null || true

# The compositor's close animation (a few semitransparent frames) gets
# captured right before the process exits, so drop the last bit.
trim=0.4
dur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$raw")"
keep="$(awk -v d="$dur" -v t="$trim" 'BEGIN { k = d - t; print (k > 0 ? k : d) }')"
ffmpeg -y -v error -i "$raw" -t "$keep" -c copy "$out"
rm -f "$raw"
echo "saved $out"
