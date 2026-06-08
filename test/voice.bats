#!/usr/bin/env bats

load test_helper

setup() {
  export VOICE_DATA_HOME="$BATS_TEST_TMPDIR/data"
  export VOICE_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export VOICE_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  export VOICE_TEST_TRANSCRIPT="mock transcript from background capture"
  export VOICE_STOP_GRACE_ATTEMPTS=2
  export VOICE_STOP_TERM_ATTEMPTS=10
  export VOICE_TEST_FFMPEG_LOG="$BATS_TEST_TMPDIR/ffmpeg-calls.log"
  export VOICE_TEST_MONKEYS_LOG="$BATS_TEST_TMPDIR/monkeys-calls.log"
  : > "$VOICE_TEST_FFMPEG_LOG"
  : > "$VOICE_TEST_MONKEYS_LOG"

  mock_bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$mock_bin"

  cat > "$mock_bin/ffmpeg" <<'MOCK_FFMPEG'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\t%s\n' "$$" "$*" >> "$VOICE_TEST_FFMPEG_LOG"

for arg in "$@"; do
  if [ "$arg" = "volumedetect" ]; then
    input=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -i)
          input="$2"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    if grep -Eq 'device=:(live|1)' "$input" 2>/dev/null; then
      printf '[Parsed_volumedetect_0] mean_volume: -35.0 dB\n' >&2
      printf '[Parsed_volumedetect_0] max_volume: -20.0 dB\n' >&2
    else
      printf '[Parsed_volumedetect_0] mean_volume: -91.0 dB\n' >&2
      printf '[Parsed_volumedetect_0] max_volume: -91.0 dB\n' >&2
    fi
    exit 0
  fi

done

if [ "${1:-}" = "-hide_banner" ] && printf '%s\n' "$*" | grep -q -- '-list_devices true'; then
  printf '[AVFoundation indev] AVFoundation video devices:\n' >&2
  printf '[AVFoundation indev] [0] Mock Camera\n' >&2
  printf '[AVFoundation indev] AVFoundation audio devices:\n' >&2
  printf '[AVFoundation indev] [0] Quiet Mic\n' >&2
  printf '[AVFoundation indev] [1] Live Mic\n' >&2
  exit 1
fi

if [ "${VOICE_TEST_FFMPEG_DRAIN_STDIN:-0}" = "1" ]; then
  dd bs=1 count=3 of=/dev/null 2>/dev/null || true
fi

out="${@: -1}"
device=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -i)
      device="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
mkdir -p "$(dirname "$out")"
write_audio() {
  printf 'mock audio from pid %s\ndevice=%s\n' "$$" "$device" > "$out"
}
trap 'write_audio; exit 0' INT TERM
if [ "${VOICE_TEST_FFMPEG_EXIT_IMMEDIATELY:-0}" = "1" ]; then
  exit 2
fi
if [ "${VOICE_TEST_FFMPEG_RECORD_IMMEDIATELY:-0}" = "1" ]; then
  write_audio
  exit 0
fi
while :; do
  sleep 0.05
done
MOCK_FFMPEG

  cat > "$mock_bin/monkeys" <<'MOCK_MONKEYS'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$VOICE_TEST_MONKEYS_LOG"
if [ "${VOICE_TEST_MONKEYS_FAIL:-0}" = "1" ]; then
  printf 'mock transcription failed\n' >&2
  exit 3
fi
if [ "${1:-}" != "listen" ]; then
  printf 'unexpected monkeys command: %s\n' "$*" >&2
  exit 2
fi
shift
output=""
audio=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      output="$2"
      shift 2
      ;;
    *)
      audio="$1"
      shift
      ;;
  esac
done
: "${audio:?audio missing}"
: "${output:?output missing}"
printf '%s\n' "${VOICE_TEST_TRANSCRIPT:-mock transcript}" > "$output"
MOCK_MONKEYS

  chmod +x "$mock_bin/ffmpeg" "$mock_bin/monkeys"
  export FFMPEG="$mock_bin/ffmpeg"
  export MONKEYS="$mock_bin/monkeys"
}

teardown() {
  state_file="$VOICE_STATE_HOME/recording.json"
  if [ -f "$state_file" ]; then
    pid="$(jq -r '.pid // empty' "$state_file" 2>/dev/null || true)"
    if [ -n "$pid" ]; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
  fi
}

state_file() {
  printf '%s/recording.json\n' "$VOICE_STATE_HOME"
}

@test "standard voice surfaces exist" {
  for path in \
    mise.toml \
    README.tsx \
    README.md \
    CONTRIBUTING.md \
    .mise/tasks/test \
    .mise/tasks/doctor \
    .mise/tasks/capture/_default \
    .mise/tasks/capture/start \
    .mise/tasks/capture/stop \
    .mise/tasks/capture/toggle \
    .mise/tasks/devices \
    .mise/tasks/mic/configure \
    .mise/tasks/mic/probe \
    .mise/tasks/transcribe/_default \
    .mise/tasks/recording/list \
    lib/common.sh
  do
    [ -e "$REPO_DIR/$path" ]
  done
}

@test "capture:status reports idle with no state" {
  run voice capture:status --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.status' <<< "$output")" = "idle" ]
  [ "$(jq -r '.pid' <<< "$output")" = "null" ]
}

@test "capture:start creates active state and refuses a second active recording" {
  run voice capture:start --device ':test' --max-duration 300 --json
  [ "$status" -eq 0 ]

  pid="$(jq -r '.pid' <<< "$output")"
  capture_dir="$(jq -r '.capture_dir' <<< "$output")"
  [ -n "$pid" ]
  kill -0 "$pid"
  [ -f "$(state_file)" ]
  [ -f "$capture_dir/capture.md" ]
  [ "$(jq -r '.device' "$(state_file)")" = ":test" ]

  run voice capture:start --device ':test' --json
  [ "$status" -ne 0 ]
  [[ "$output" == *"recording already active"* ]]

  run voice capture:stop --json
  [ "$status" -eq 0 ]
}

@test "capture:stop finalizes, transcribes, and clears state" {
  run voice capture:start --device ':test' --json
  [ "$status" -eq 0 ]
  capture_dir="$(jq -r '.capture_dir' <<< "$output")"

  run voice capture:stop --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.status' <<< "$output")" = "transcribed" ]
  [ ! -f "$(state_file)" ]
  [ -s "$capture_dir/audio.wav" ]
  [ "$(cat "$capture_dir/transcript.txt")" = "$VOICE_TEST_TRANSCRIPT" ]
  grep -q "$VOICE_TEST_TRANSCRIPT" "$capture_dir/capture.md"
}

@test "capture:toggle starts when idle and stops when active" {
  run voice capture:toggle --device ':test' --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.status' <<< "$output")" = "active" ]
  [ -f "$(state_file)" ]

  run voice capture:toggle --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.status' <<< "$output")" = "transcribed" ]
  [ ! -f "$(state_file)" ]
}

@test "capture:start cleans stale state before starting" {
  mkdir -p "$VOICE_STATE_HOME" "$BATS_TEST_TMPDIR/stale-capture"
  cat > "$(state_file)" <<EOF
{"pid":999999,"capture_id":"stale","capture_dir":"$BATS_TEST_TMPDIR/stale-capture","audio":"$BATS_TEST_TMPDIR/stale-capture/audio.wav","device":":old","started_at":"2026-01-01T00:00:00+0000","max_duration_seconds":300}
EOF

  run voice capture:start --device ':new' --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.device' "$(state_file)")" = ":new" ]
  [ "$(jq -r '.pid' "$(state_file)")" != "999999" ]

  run voice capture:stop --json
  [ "$status" -eq 0 ]
}

@test "capture:stop fails clearly when idle" {
  run voice capture:stop --json
  [ "$status" -ne 0 ]
  [[ "$output" == *"no active recording state"* ]]
}

@test "capture:stop leaves audio and state recoverable when transcription fails" {
  run voice capture:start --device ':test' --json
  [ "$status" -eq 0 ]
  capture_dir="$(jq -r '.capture_dir' <<< "$output")"

  VOICE_TEST_MONKEYS_FAIL=1 run voice capture:stop --json
  [ "$status" -ne 0 ]
  [[ "$output" == *"mock transcription failed"* ]]
  [ -f "$(state_file)" ]
  [ -s "$capture_dir/audio.wav" ]

  run voice capture:status --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.status' <<< "$output")" = "stale" ]
}

@test "recording:list reports transcribed captures" {
  run voice capture:start --device ':test' --json
  [ "$status" -eq 0 ]

  run voice capture:stop --json
  [ "$status" -eq 0 ]

  run voice recording:list --json
  [ "$status" -eq 0 ]
  [ "$(jq 'length' <<< "$output")" -eq 1 ]
  [ "$(jq -r '.[0].status' <<< "$output")" = "transcribed" ]
  [ "$(jq -r '.[0].transcript_excerpt' <<< "$output")" = "$VOICE_TEST_TRANSCRIPT" ]
}

@test "mic:probe requires explicit approval for JSON/non-TTY use" {
  run voice mic:probe --json
  [ "$status" -ne 0 ]
  [[ "$output" == *"rerun with --yes to approve"* ]]
}

@test "mic:probe reports the loudest live audio device" {
  VOICE_TEST_FFMPEG_RECORD_IMMEDIATELY=1 run voice mic:probe --json --yes --duration 1
  [ "$status" -eq 0 ]
  [ "$(jq -r '.best_device' <<< "$output")" = ":1" ]
  [ "$(jq '.devices | length' <<< "$output")" -eq 2 ]
  [ "$(jq -r '.devices[] | select(.device == ":0") | .live' <<< "$output")" = "false" ]
  [ "$(jq -r '.devices[] | select(.device == ":1") | .live' <<< "$output")" = "true" ]
}

@test "mic:probe keeps ffmpeg stdin isolated from the device list" {
  VOICE_TEST_FFMPEG_RECORD_IMMEDIATELY=1 VOICE_TEST_FFMPEG_DRAIN_STDIN=1 run voice mic:probe --json --yes --duration 1
  [ "$status" -eq 0 ]
  [ "$(jq -r '.best_device' <<< "$output")" = ":1" ]
  [ "$(jq -r '.devices[1].device' <<< "$output")" = ":1" ]
  [ "$(jq -r '.devices[1].name' <<< "$output")" = "Live Mic" ]
}

@test "mic:configure saves the explicit default capture device" {
  run voice mic:configure --device ':live' --json --yes
  [ "$status" -eq 0 ]
  [ "$(jq -r '.device' <<< "$output")" = ":live" ]
  [ "$(jq -r '.default_device' "$VOICE_CONFIG_HOME/config.json")" = ":live" ]

  run voice capture:start --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.device' "$(state_file)")" = ":live" ]

  run voice capture:stop --json
  [ "$status" -eq 0 ]
}

@test "mic:configure auto-picks the best live input in JSON mode" {
  VOICE_TEST_FFMPEG_RECORD_IMMEDIATELY=1 run voice mic:configure --json --yes
  [ "$status" -eq 0 ]
  [ "$(jq -r '.device' <<< "$output")" = ":1" ]
  [ "$(jq -r '.default_device' "$VOICE_CONFIG_HOME/config.json")" = ":1" ]
}
