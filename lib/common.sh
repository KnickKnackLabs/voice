#!/usr/bin/env bash

set -euo pipefail

vc_data_home() {
  if [ -n "${VOICE_DATA_HOME:-}" ]; then
    printf '%s\n' "$VOICE_DATA_HOME"
    return 0
  fi

  # Backward-compatible with the first local dogfood prototype.
  if [ -n "${VOICE_CAPTURE_DATA_HOME:-}" ]; then
    printf '%s\n' "$VOICE_CAPTURE_DATA_HOME"
    return 0
  fi

  if [ -n "${XDG_DATA_HOME:-}" ]; then
    printf '%s/voice\n' "$XDG_DATA_HOME"
    return 0
  fi

  printf '%s/.local/share/voice\n' "$HOME"
}

vc_capture_root() {
  printf '%s/captures\n' "$(vc_data_home)"
}

vc_state_home() {
  if [ -n "${VOICE_STATE_HOME:-}" ]; then
    printf '%s\n' "$VOICE_STATE_HOME"
    return 0
  fi

  # Backward-compatible with the first local dogfood prototype.
  if [ -n "${VOICE_CAPTURE_STATE_HOME:-}" ]; then
    printf '%s\n' "$VOICE_CAPTURE_STATE_HOME"
    return 0
  fi

  if [ -n "${XDG_STATE_HOME:-}" ]; then
    printf '%s/voice\n' "$XDG_STATE_HOME"
    return 0
  fi

  printf '%s/.local/state/voice\n' "$HOME"
}

vc_state_file() {
  printf '%s/recording.json\n' "$(vc_state_home)"
}

vc_default_device() {
  printf '%s\n' "${VOICE_DEVICE:-${VOICE_CAPTURE_DEVICE:-:0}}"
}

vc_now_id() {
  date '+%Y%m%d-%H%M%S'
}

vc_iso_now() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

vc_normalize_empty() {
  case "${1:-}" in
    ""|"''") printf '\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

vc_require_duration() {
  case "$1" in
    ''|*[!0-9]*)
      printf 'voice: duration must be a positive integer number of seconds, got %s\n' "$1" >&2
      return 1
      ;;
    0)
      printf 'voice: duration must be greater than zero\n' >&2
      return 1
      ;;
  esac
}

vc_new_capture_dir() {
  local output_dir capture_id capture_dir suffix
  output_dir="$(vc_normalize_empty "${1:-}")"
  if [ -z "$output_dir" ]; then
    output_dir="$(vc_capture_root)"
  fi

  capture_id="$(vc_now_id)"
  capture_dir="$output_dir/$capture_id"

  # Avoid timestamp collision if two captures start in the same second.
  suffix=1
  while [ -e "$capture_dir" ]; do
    capture_dir="$output_dir/${capture_id}-$suffix"
    suffix=$((suffix + 1))
  done

  mkdir -p "$capture_dir"
  printf '%s\n' "$capture_dir"
}

vc_capture_id_from_dir() {
  basename "$1"
}

vc_file_link() {
  local label path esc bel
  label="$1"
  path="$2"

  if { [ -t 1 ] || [ "${VOICE_STDOUT_TTY:-${VOICE_CAPTURE_STDOUT_TTY:-0}}" = "1" ]; } && [ "${VOICE_OSC8:-${VOICE_CAPTURE_OSC8:-1}}" != "0" ]; then
    esc="$(printf '\033')"
    bel="$(printf '\a')"
    printf '%s]8;;file://%s%s%s%s]8;;%s' "$esc" "$path" "$bel" "$label" "$esc" "$bel"
  else
    printf '%s' "$path"
  fi
}

vc_pid_alive() {
  local pid
  pid="${1:-}"
  case "$pid" in
    ''|*[!0-9]*) return 1 ;;
  esac
  kill -0 "$pid" >/dev/null 2>&1
}

vc_state_pid() {
  local state_file
  state_file="$(vc_state_file)"
  [ -f "$state_file" ] || return 1
  jq -r '.pid // empty' "$state_file"
}

vc_state_capture_dir() {
  local state_file
  state_file="$(vc_state_file)"
  [ -f "$state_file" ] || return 1
  jq -r '.capture_dir // empty' "$state_file"
}

vc_state_status() {
  local state_file pid
  state_file="$(vc_state_file)"
  if [ ! -f "$state_file" ]; then
    printf 'idle\n'
    return 0
  fi

  if ! pid="$(jq -r '.pid // empty' "$state_file" 2>/dev/null)"; then
    pid=""
  fi
  if vc_pid_alive "$pid"; then
    printf 'active\n'
  else
    printf 'stale\n'
  fi
}

vc_clear_state() {
  rm -f "$(vc_state_file)"
}

vc_write_state() {
  local state_file tmp pid capture_dir audio device started_at max_duration
  pid="$1"
  capture_dir="$2"
  audio="$3"
  device="$4"
  started_at="$5"
  max_duration="$6"

  state_file="$(vc_state_file)"
  mkdir -p "$(dirname "$state_file")"

  tmp="${state_file}.tmp.$$"
  jq -n \
    --argjson pid "$pid" \
    --arg capture_id "$(vc_capture_id_from_dir "$capture_dir")" \
    --arg capture_dir "$capture_dir" \
    --arg audio "$audio" \
    --arg device "$device" \
    --arg started_at "$started_at" \
    --arg max_duration_seconds "$max_duration" \
    '{pid:$pid,capture_id:$capture_id,capture_dir:$capture_dir,audio:$audio,device:$device,started_at:$started_at,max_duration_seconds:($max_duration_seconds|tonumber)}' \
    > "$tmp"
  mv "$tmp" "$state_file"
}

vc_frontmatter_value() {
  local file key
  file="$1"
  key="$2"
  [ -f "$file" ] || return 1
  awk -F': ' -v key="$key" '
    $1 == key {
      value=$2
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
  ' "$file"
}

vc_write_markdown() {
  local capture_dir status device duration capture_id audio_rel transcript_rel markdown created
  capture_dir="$1"
  status="$2"
  device="$3"
  duration="$4"

  capture_id="$(vc_capture_id_from_dir "$capture_dir")"
  audio_rel="audio.wav"
  transcript_rel="transcript.txt"
  markdown="$capture_dir/capture.md"
  created="$(vc_iso_now)"

  {
    cat <<EOF
---
type: voice-capture
capture_id: "$capture_id"
created: "$created"
source: "local-avfoundation"
device: "$device"
duration_seconds: $duration
audio: "$audio_rel"
transcript: "$transcript_rel"
status: "$status"
---

# Voice capture $capture_id

## Audio

![[${audio_rel}]]

## Transcript

EOF

    if [ -s "$capture_dir/$transcript_rel" ]; then
      cat <<'EOF'
~~~text
EOF
      cat "$capture_dir/$transcript_rel"
      cat <<'EOF'
~~~
EOF
    else
      cat <<'EOF'
_Not transcribed yet._
EOF
    fi

    cat <<'EOF'

## Notes

_Add notes, routing decisions, or follow-up here._

## Agent follow-up

_Add agent response or next action here._
EOF
  } > "$markdown"

  printf '%s\n' "$markdown"
}
