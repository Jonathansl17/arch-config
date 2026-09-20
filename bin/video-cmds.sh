# video-cmds.sh — subcommand implementations for `video` (cut, join, audio).
# Relies on the helpers in video-lib.sh being sourced first.

# Accurate cuts re-encode with these settings; --copy skips them (keyframe-bound).
readonly ENCODE_OPTS=(-c:v libx264 -crf 18 -preset veryfast -c:a aac -movflags +faststart)
readonly COPY_OPTS=(-c copy -avoid_negative_ts make_zero)

# cut_range INPUT START END OUTPUT COPY_FLAG
cut_range() {
  local input="$1" start="$2" end="$3" output="$4" copy="$5"
  local duration length
  duration=$(probe_duration "$input")
  cmp_lt "$start" "$end" || die "start ($(fmt_seconds "$start")) must be before end ($(fmt_seconds "$end"))"
  cmp_lt "$end" "$(awk -v d="$duration" 'BEGIN{print d + 0.001}')" \
    || die "end $(fmt_seconds "$end") exceeds duration $(fmt_seconds "$duration") of $input"
  length=$(awk -v s="$start" -v e="$end" 'BEGIN{printf "%.3f", e - s}')
  assert_output_free "$output"
  say "Cutting $(fmt_seconds "$start") -> $(fmt_seconds "$end") from $input"
  local -a codec_opts=("${ENCODE_OPTS[@]}")
  [[ "$copy" == 1 ]] && codec_opts=("${COPY_OPTS[@]}")
  ffmpeg -v error -stats -ss "$start" -i "$input" -t "$length" \
    "${codec_opts[@]}" "$output" || die "ffmpeg failed while cutting $input"
  ok "wrote $output"
}

# cmd_cut OUTPUT_OR_EMPTY COPY_FLAG TMP_DIR SOURCE START END [START END ...]
cmd_cut() {
  local output="$1" copy="$2" tmp_dir="$3" source="$4"; shift 4
  (( $# >= 2 && $# % 2 == 0 )) || die "cut needs START END pairs (got $# time args)"
  (( $# == 2 )) || [[ -z "$output" ]] || die "-o only works with a single START END pair"
  local input index=0 start end target
  local ranges=$(( $# / 2 ))
  input=$(resolve_inputs "$tmp_dir" "$source")
  while (( $# )); do
    index=$((index + 1))
    start=$(to_seconds "$1"); end=$(to_seconds "$2"); shift 2
    target="$output"
    if [[ -z "$target" ]]; then
      target=$(default_output "$input" cut "$( (( ranges > 1 )) && echo "$index" )")
    fi
    cut_range "$input" "$start" "$end" "$target" "$copy"
  done
}

# True when every input shares codec, resolution and frame rate and the audio
# situation is uniform, which is what the concat demuxer needs for -c copy.
inputs_match() {
  local first_sig first_audio sig file
  first_sig=$(probe_video_signature "$1")
  has_audio "$1" && first_audio=1 || first_audio=0
  for file in "$@"; do
    sig=$(probe_video_signature "$file")
    [[ "$sig" == "$first_sig" ]] || return 1
    has_audio "$file" && sig=1 || sig=0
    [[ "$sig" == "$first_audio" ]] || return 1
  done
}

# Fast path: stream copy through the concat demuxer.
join_copy() {
  local output="$1" list="$2"; shift 2
  local file
  : > "$list"
  for file in "$@"; do
    # The demuxer wants single quotes inside the path escaped as '\''.
    printf "file '%s'\n" "$(realpath "$file" | sed "s/'/'\\\\''/g")" >> "$list"
  done
  ffmpeg -v error -stats -f concat -safe 0 -i "$list" -c copy "$output" \
    || die "ffmpeg failed while joining (stream copy)"
}

# Slow path: scale/pad every input to the first one's resolution, re-encode.
join_reencode() {
  local output="$1"; shift
  local res width height filter="" index=0 file
  local -a inputs=()
  res=$(probe_resolution "$1"); width="${res%%,*}"; height="${res##*,}"
  for file in "$@"; do
    has_audio "$file" || die "cannot mix inputs with and without audio: $file has none"
    inputs+=(-i "$file")
    filter+="[$index:v]scale=${width}:${height}:force_original_aspect_ratio=decrease,"
    filter+="pad=${width}:${height}:(ow-iw)/2:(oh-ih)/2,setsar=1[v$index];"
    filter+="[$index:a]aresample=async=1[a$index];"
    index=$((index + 1))
  done
  local streams="" i
  for (( i = 0; i < index; i++ )); do streams+="[v$i][a$i]"; done
  filter+="${streams}concat=n=${index}:v=1:a=1[v][a]"
  ffmpeg -v error -stats "${inputs[@]}" -filter_complex "$filter" \
    -map '[v]' -map '[a]' "${ENCODE_OPTS[@]}" "$output" \
    || die "ffmpeg failed while joining (re-encode)"
}

# cmd_join OUTPUT_OR_EMPTY TMP_DIR INPUT [INPUT ...]
cmd_join() {
  local output="$1" tmp_dir="$2"; shift 2
  (( $# >= 2 )) || die "join needs at least two inputs"
  local -a files=()
  # Not a process substitution: a die inside must abort the whole command.
  resolved=$(resolve_inputs "$tmp_dir" "$@") || exit 1
  mapfile -t files <<< "$resolved"
  [[ -n "$output" ]] || output=$(default_output "${files[0]}" joined)
  assert_output_free "$output"
  if inputs_match "${files[@]}"; then
    say "Joining ${#files[@]} inputs (stream copy, same codec/resolution)"
    join_copy "$output" "$tmp_dir/list.txt" "${files[@]}"
  else
    say "Joining ${#files[@]} inputs (re-encoding, inputs differ)"
    join_reencode "$output" "${files[@]}"
  fi
  ok "wrote $output"
}

# Container extension that can hold each audio codec without re-encoding.
audio_ext_for() {
  case "$1" in
    aac) echo m4a ;; mp3) echo mp3 ;; opus) echo opus ;; vorbis) echo ogg ;; flac) echo flac ;;
    *) echo "" ;;
  esac
}

# extract_audio INPUT OUTPUT_OR_EMPTY INDEX_OR_EMPTY
# Without -o the stream is copied into a matching container; with -o ffmpeg
# encodes to whatever the extension implies.
extract_audio() {
  local input="$1" output="$2" index="$3" codec ext
  local -a codec_opts=(-c:a copy)
  has_audio "$input" || die "no audio stream in $input"
  if [[ -z "$output" ]]; then
    codec=$(probe_audio_codec "$input")
    ext=$(audio_ext_for "$codec")
    [[ -n "$ext" ]] || { ext=m4a; codec_opts=(-c:a aac); }
    output="$(default_output "$input" audio "$index")"; output="${output%.mp4}.$ext"
  else
    codec_opts=()
  fi
  assert_output_free "$output"
  say "Extracting audio from $input"
  ffmpeg -v error -stats -i "$input" -vn "${codec_opts[@]}" "$output" \
    || die "ffmpeg failed while extracting audio from $input"
  ok "wrote $output"
}

# cmd_audio OUTPUT_OR_EMPTY TMP_DIR INPUT [INPUT ...]
cmd_audio() {
  local output="$1" tmp_dir="$2"; shift 2
  (( $# >= 1 )) || die "audio needs at least one input"
  (( $# == 1 )) || [[ -z "$output" ]] || die "-o only works with a single input"
  local -a files=()
  local i index resolved
  # Not a process substitution: a die inside must abort the whole command.
  resolved=$(resolve_inputs "$tmp_dir" "$@") || exit 1
  mapfile -t files <<< "$resolved"
  # Inputs already give distinct names; an index is only needed under --name.
  for i in "${!files[@]}"; do
    index=""; [[ -n "$OUT_NAME" && ${#files[@]} -gt 1 ]] && index=$(( i + 1 ))
    extract_audio "${files[$i]}" "$output" "$index"
  done
}
