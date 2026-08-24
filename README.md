<div align="center">

# voice

<pre>
╭──────────────────────────────────────────────────────────────────────────────╮
│ ▄▆▁▂▅▁█▂█▄▂▂▆▂▇▃▄█▂▂▄▆▁▇▁▆▇▄▂▂▄▃▂▄▅▁▂▆▂▁▄▅▃▅▄▇▄▄▇▅▆▄▃▅█▁▃▆▅▁▆█▅▆▄▄▃▂▇█▁▅ │
│ mic  →  audio.wav  →  transcript.txt  →  capture.md  →  agent/editor       │
╰──────────────────────────────────────────────────────────────────────────────╯
</pre>
**Capture local voice messages, transcribe them, and keep the artifact.**

A microphone is just another input surface.

![shape: mise + BATS](https://img.shields.io/badge/shape-mise%20%2B%20BATS-4EAA25?style=flat&logo=gnubash&logoColor=white)
[![tests: 17](https://img.shields.io/badge/tests-17-brightgreen?style=flat)](test/)
![tasks: 14](https://img.shields.io/badge/tasks-14-8b5cf6?style=flat)
![lints: 17](https://img.shields.io/badge/lints-17-blue?style=flat)
![README: TSX](https://img.shields.io/badge/README-TSX-f472b6?style=flat)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue?style=flat)](LICENSE)

</div>

<br />

## What this is

`voice` records microphone audio with ffmpeg, sends the audio through `monkeys listen`, and writes a capture artifact that has enough structure for humans and agents to use it later.

The first shape is deliberately batch-oriented: capture a thought, transcribe it, inspect or route it. That makes it useful for agent sessions, hotkeys, and Pi extensions without pretending every transcript is ready to auto-submit.

## The signal path

```
mic  →  capture:start  →  audio.wav  →  transcribe  →  transcript.txt  →  capture.md  →  Pi editor
```

The waveform at the top is generated from the current task tree at README build time. If the command surface changes, the strip changes with it.

## Quick start

```bash
gh repo clone KnickKnackLabs/voice
cd voice
mise trust
mise install

# See local AVFoundation audio devices, then choose a default mic.
mise run devices
mise run mic:probe
mise run mic:configure

# Foreground capture: record, transcribe, render.
mise run capture --duration 5 --json

# Background/hotkey shape: start now, stop+transcribe later.
mise run capture:toggle --max-duration 300 --json
mise run capture:status --json
mise run capture:toggle --json  # stop + transcribe
# Alternative while recording: mise run capture:cancel --json

# List saved capture artifacts.
mise run recording:list
```

## Installed command shape

After shiv install, the same tasks become ordinary command words:

```bash
voice capture
voice capture:start --max-duration 300
voice capture:stop --json
voice capture:cancel --json
voice capture:toggle
voice capture:status
voice devices
voice mic:probe --yes --json
voice mic:configure
voice mic:configure --device :1 --yes
voice transcribe path/to/audio.wav
voice recording:list --json
```

## Pi extension target

```
/voice
  opens an overlay
  Enter/Space → stop, transcribe, paste transcript into the editor
  Esc         → cancel without transcribing
  unsure      → user edits before sending
```

## Artifact layout

Captures are written outside the repo by default:

```
${XDG_DATA_HOME:-~/.local/share}/voice/captures/<capture-id>/
├── audio.wav
├── transcript.txt
└── capture.md
```

Background recording state lives under `${XDG_STATE_HOME:-~/.local/state}/voice/recording.json`. The configured default microphone lives in `${XDG_CONFIG_HOME:-~/.config}/voice/config.json`. Override with `VOICE_DATA_HOME`, `VOICE_STATE_HOME`, and `VOICE_CONFIG_HOME` when testing or routing captures into a custom workspace.

## Why the artifact matters

- **Audio stays available** for re-transcription when ASR gets better.
- **Transcript stays plain** so other tools can consume it cheaply.
- **Markdown owns the thought** with frontmatter, notes, routing decisions, summaries, and follow-up.

<details>
<summary><b>Current task deck</b></summary>

```
capture          Record, transcribe, and render one local voice capture
capture:start    Start a background voice recording
capture:stop     Stop the active background voice recording and transcribe it
capture:cancel   Cancel the active background voice recording without transcribing it
capture:toggle   Toggle background voice recording on or off
capture:status   Show background voice recording status
devices          List macOS AVFoundation recording devices visible to ffmpeg
mic:probe        Probe microphone inputs for live audio
mic:configure    Choose and save the default microphone device for voice capture
transcribe       Transcribe a captured audio file and refresh capture.md
recording:list   List local voice capture artifacts
```

</details>

## Development

```bash
mise run test
mise run doctor
codebase lint "$PWD"
readme build --check
git diff --check
```

<div align="center">

---

<sub>
Generated from `README.tsx` with [KnickKnackLabs/readme](https://github.com/KnickKnackLabs/readme).<br />Speak, then decide what the words are for.
</sub></div>
