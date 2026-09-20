# video-lib.sh — shared helpers for the `video` command: output, timestamps,
# media probing and input resolution. URL downloads live in video-fetch.sh.
# Sourced by `video`; not meant to be executed directly.

readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

readonly URL_RE='^https?://'
# SS | MM:SS | HH:MM:SS, each with optional fractional seconds.
readonly TIME_RE='^([0-9]{1,2}:)?([0-9]{1,2}:)?[0-9]+(\.[0-9]+)?$'
readonly SECS_PER_MIN=60
# Downloads land as dl-<index>-<title>.<ext>; the prefix keeps inputs ordered.
readonly DL_PREFIX='dl-'
readonly DL_PREFIX_RE='^dl-[0-9]+-(.*)$'

say() { printf "${CYAN}==>${NC} %s\n" "$*" >&2; }
ok()  { printf "${GREEN}  ok${NC} %s\n" "$*" >&2; }
die() { printf "${RED}error:${NC} %s\n" "$*" >&2; exit 1; }

require_tools() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 || die "missing tool: $tool"
  done
}

is_url() { [[ "$1" =~ $URL_RE ]]; }

# Convert "2:01", "1:02:03.5" or "90" into seconds (may be fractional).
# Fails when a minute/second field is out of range.
to_seconds() {
  local spec="$1" total=0 field i
  local -a fields
  [[ "$spec" =~ $TIME_RE ]] || die "bad time '$spec' (use SS, MM:SS or HH:MM:SS)"
  IFS=':' read -ra fields <<< "$spec"
  for i in "${!fields[@]}"; do
    field="${fields[$i]}"
    # Only the leading field may exceed 59 (plain seconds or hours).
    if (( i > 0 )) && awk -v f="$field" -v m="$SECS_PER_MIN" 'BEGIN{exit !(f >= m)}'; then
      die "bad time '$spec': field '$field' must be below $SECS_PER_MIN"
    fi
    total=$(awk -v t="$total" -v f="$field" -v m="$SECS_PER_MIN" 'BEGIN{printf "%.3f", t * m + f}')
  done
  printf '%s\n' "$total"
}

# Print seconds as H:MM:SS.mmm for messages.
fmt_seconds() {
  awk -v s="$1" 'BEGIN{h=int(s/3600); m=int((s%3600)/60); printf "%d:%02d:%06.3f", h, m, s%60}'
}

# awk-based float comparison: cmp_lt a b -> true when a < b.
cmp_lt() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a < b)}'; }

# Duration in seconds of a media file.
probe_duration() {
  local file="$1" dur
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$file") \
    || die "ffprobe failed on $file"
  [[ -n "$dur" && "$dur" != "N/A" ]] || die "no duration found in $file"
  printf '%s\n' "$dur"
}

# One line describing the first video stream: codec,width,height,fps.
probe_video_signature() {
  ffprobe -v error -select_streams v:0 \
    -show_entries stream=codec_name,width,height,r_frame_rate -of csv=p=0 "$1" \
    || die "ffprobe failed on $1"
}

# Width and height of the first video stream as "W,H".
probe_resolution() {
  ffprobe -v error -select_streams v:0 -show_entries stream=width,height \
    -of csv=p=0 "$1" || die "ffprobe failed on $1"
}

# Codec name of the first audio stream (empty when there is none).
probe_audio_codec() {
  ffprobe -v error -select_streams a:0 -show_entries stream=codec_name \
    -of csv=p=0 "$1" || die "ffprobe failed on $1"
}

has_audio() {
  [[ -n "$(ffprobe -v error -select_streams a:0 -show_entries stream=index -of csv=p=0 "$1")" ]]
}

assert_media() {
  local file="$1"
  [[ -f "$file" ]] || die "not a file: $file"
  ffprobe -v error -select_streams v:0 -show_entries stream=index -of csv=p=0 "$file" \
    | grep -q . || die "no video stream in $file"
}

# Resolve every input (path or URL) into a local file; prints one path per line.
# URLs are fetched into $2 (a temp dir owned by the caller).
resolve_inputs() {
  local tmp_dir="$1"; shift
  local arg index=0 path
  for arg in "$@"; do
    index=$((index + 1))
    if is_url "$arg"; then
      path=$(fetch_url "$arg" "$tmp_dir" "$index") || exit 1
      [[ -n "$path" ]] || die "yt-dlp produced no file for $arg"
    else
      path="$arg"
    fi
    assert_media "$path"
    printf '%s\n' "$path"
  done
}

# Default output name in the cwd: <input-basename>-<suffix>[-<index>].mp4, or
# <OUT_NAME>[-<index>].mp4 when --name was given. INDEX is empty for a single
# output. Downloaded inputs drop their dl-N- prefix so the title is used.
default_output() {
  local first="$1" suffix="$2" index="${3:-}" base
  if [[ -n "${OUT_NAME:-}" ]]; then
    base="$OUT_NAME"
  else
    base="${first##*/}"
    base="${base%.*}"
    [[ "$base" =~ $DL_PREFIX_RE ]] && base="${BASH_REMATCH[1]}"
    base="${base}-${suffix}"
  fi
  printf '%s\n' "${base}${index:+-$index}.mp4"
}

assert_output_free() {
  [[ -e "$1" ]] && die "output exists: $1 (pick another with -o)"
  return 0
}
