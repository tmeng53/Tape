#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

clips="$HOME/Library/Application Support/Tape/Clips"
tool="build/smoke-tool"
failures=0

mkdir -p build
swiftc -O -suppress-warnings scripts/smoke-tool.swift -o "$tool"

if ! "$tool" preflight; then
  echo "Turn on the app running this script under System Settings > Privacy & Security > Accessibility, then rerun."
  exit 2
fi

if ! pgrep -qf "Tape.app/Contents/MacOS/Tape"; then
  echo "Tape is not running. Launch it first."
  exit 2
fi

if osascript -e 'output muted of (get volume settings)' | grep -q true; then
  echo "Warning: sound output is muted, so the spoken test sentences will not reach the mic."
fi

log_file="build/smoke-log.ndjson"
log stream --level debug --style ndjson --predicate 'subsystem == "app.tape.mac"' >"$log_file" &
log_pid=$!
trap 'kill "$log_pid" 2>/dev/null || true' EXIT
sleep 1

clip_list() {
  ls -1 "$clips" 2>/dev/null | sort
}

wait_for_new_clip() {
  local before="$1" deadline=$((SECONDS + 20)) id
  while ((SECONDS < deadline)); do
    id=$(comm -13 <(echo "$before") <(clip_list) | head -1)
    if [[ -n "$id" && -f "$clips/$id/clip.json" ]]; then
      echo "$id"
      return 0
    fi
    sleep 0.25
  done
  return 1
}

describe_clip() {
  local dir="$clips/$1"
  local delivery video created
  delivery=$(plutil -extract delivery json -o - "$dir/clip.json")
  video=$(plutil -extract videoFile raw -o - "$dir/clip.json")
  created=$(plutil -extract createdAt raw -o - "$dir/clip.json")
  echo "  clip $1"
  echo "  createdAt $created"
  echo "  delivery $delivery"
  level=$("$tool" level "$dir/$video")
  echo "  $level"
  echo "  clip.json written at $(stat -f %Fm "$dir/clip.json")"
}

last_stamp() {
  awk -v label="$1" '$1 == label { value = $2 } END { print value }' <<<"$2"
}

check_speech() {
  local peak
  peak=$(sed -E 's/.*peak=(-?[0-9.]+)dBFS.*/\1/' <<<"$level")
  awk -v p="$peak" 'BEGIN { exit !(p > -30) }' && check ok "speech captured ($1)" || check no "speech captured ($1, peak ${peak} dBFS)"
}

check_cue_delay() {
  local delay
  sleep 0.5
  if delay=$("$tool" cue-delay "$log_file" stop "$1"); then
    echo "  stop cue ${delay} ms after $2"
    awk -v d="$delay" 'BEGIN { exit !(d < 100) }' && check ok "stop cue under 100 ms ($3)" || check no "stop cue under 100 ms ($3)"
  else
    check no "stop cue logged ($3)"
  fi
}

check() {
  if [[ "$1" == "ok" ]]; then
    echo "PASS $2"
  else
    echo "FAIL $2"
    failures=$((failures + 1))
  fi
}

document="build/smoke-$(date +%s).rtfd"
mkdir -p "$document"
printf '{\\rtf1\\ansi }' >"$document/TXT.rtf"
focus_document() {
  local attempt
  for attempt in 1 2 3 4 5 6; do
    [[ "$("$tool" frontmost)" == "com.apple.TextEdit" ]] && break
    open -a TextEdit
    sleep 0.5
  done
  if [[ "$("$tool" frontmost)" != "com.apple.TextEdit" ]]; then
    echo "TextEdit is not in front, stopping so no key presses reach another app."
    exit 3
  fi
}

open -a TextEdit "$document"
sleep 2

echo "== hold left control for 3.5 s while speaking"
before=$(clip_list)
focus_document
say "This is the Tape smoke test. I am holding the control key." &
say_pid=$!
keys=$("$tool" hold 3.5)
wait "$say_pid"
echo "$keys"
check_cue_delay "$(last_stamp control-up "$keys")" "key up" hold
if id=$(wait_for_new_clip "$before"); then
  describe_clip "$id"
  grep -q '"pasted"' "$clips/$id/clip.json" && check ok "hold clip pasted" || check no "hold clip pasted"
  check_speech hold
else
  check no "hold produced a clip"
fi

sleep 2
echo "== tap, speak, tap"
before=$(clip_list)
focus_document
"$tool" tap
say "Hands free mode. Tap to start and tap again to stop."
keys=$("$tool" tap)
echo "$keys"
check_cue_delay "$(last_stamp control-down "$keys")" "second tap" hands-free
if id=$(wait_for_new_clip "$before"); then
  describe_clip "$id"
  grep -q '"pasted"' "$clips/$id/clip.json" && check ok "hands-free clip pasted" || check no "hands-free clip pasted"
  check_speech hands-free
else
  check no "hands-free produced a clip"
fi

sleep 2
echo "== hold, press escape, release"
before=$(clip_list)
focus_document
"$tool" escape-during-hold
if id=$(wait_for_new_clip "$before"); then
  describe_clip "$id"
  grep -q '"kept"' "$clips/$id/clip.json" && check ok "escape kept the clip without pasting" || check no "escape kept the clip without pasting"
else
  check no "escape kept a clip"
fi

focus_document
attachments=$("$tool" attachments TextEdit || echo 0)
echo "== TextEdit document has $attachments attachment(s)"
[[ "$attachments" -ge 2 ]] && check ok "TextEdit received both clips" || check no "TextEdit received both clips"

echo "== Tape log during the run"
"$tool" log-lines "$log_file"

echo "== $failures failure(s)"
exit $((failures > 0 ? 1 : 0))
