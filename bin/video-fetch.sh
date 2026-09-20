# video-fetch.sh — download URL inputs for the `video` command through yt-dlp.
# Needs video-lib.sh (say/die, DL_PREFIX) sourced first.

# Best video + best audio; ties resolved towards mp4/m4a so mp4 output muxes cleanly.
readonly YTDLP_FORMAT='bv*+ba/b'
readonly YTDLP_SORT='res,fps,ext:mp4:m4a'
# YouTube clients tried in turn when the default one reports the video as
# unavailable or without formats (happens on some videos; android usually works).
readonly YTDLP_FALLBACK_CLIENTS=(android ios web)
# YouTube hides most formats (1080p+) behind a JS challenge. Solving it needs a
# JS runtime (one --js-runtimes flag each) plus yt-dlp's solver script, which is
# fetched on demand from GitHub and cached.
readonly YTDLP_JS_RUNTIMES=(--js-runtimes deno --js-runtimes node)
readonly YTDLP_REMOTE_COMPONENTS='ejs:github'

# ytdlp_run TEMPLATE URL [EXTRA_ARGS...]
ytdlp_run() {
  local template="$1" url="$2"; shift 2
  yt-dlp --quiet --no-warnings --no-playlist --restrict-filenames \
    "${YTDLP_JS_RUNTIMES[@]}" --remote-components "$YTDLP_REMOTE_COMPONENTS" \
    -f "$YTDLP_FORMAT" -S "$YTDLP_SORT" --merge-output-format mp4 \
    "$@" -o "$template" "$url" >&2
}

# Download a URL into $tmp_dir with yt-dlp and print the resulting path.
# Retries with alternative YouTube player clients before giving up.
fetch_url() {
  local url="$1" dest_dir="$2" index="$3" template client
  template="$dest_dir/${DL_PREFIX}${index}-%(title)s.%(ext)s"
  say "Downloading $url (best quality)"
  if ! ytdlp_run "$template" "$url"; then
    for client in "${YTDLP_FALLBACK_CLIENTS[@]}"; do
      say "Retrying $url with player client '$client' (quality may be lower; install deno)"
      ytdlp_run "$template" "$url" --extractor-args "youtube:player_client=$client" && break
      client=""
    done
    [[ -n "$client" ]] || die "download failed: $url"
  fi
  find "$dest_dir" -maxdepth 1 -name "${DL_PREFIX}${index}-*" -print -quit
}
