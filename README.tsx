/** @jsxImportSource jsx-md */

import { existsSync, readFileSync, readdirSync, statSync } from "fs";
import { join, resolve } from "path";

import {
  Badge,
  Badges,
  Bold,
  Center,
  Code,
  CodeBlock,
  Details,
  Heading,
  Item,
  LineBreak,
  Link,
  List,
  Paragraph,
  Raw,
  Section,
  Sub,
} from "readme";

const PROJECT = {
  name: "voice",
  oneLine: "Capture local voice messages, transcribe them, and keep the artifact.",
  tagline: "A microphone is just another input surface.",
  license: "MIT",
};

const REPO_DIR = resolve(import.meta.dirname);
const TASK_DIR = join(REPO_DIR, ".mise/tasks");
const TEST_DIR = join(REPO_DIR, "test");

interface TaskInfo {
  name: string;
  description: string;
}

function read(path: string): string {
  return readFileSync(path, "utf8");
}

function walkFiles(dir: string, predicate: (path: string) => boolean): string[] {
  if (!existsSync(dir)) return [];

  const results: string[] = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...walkFiles(full, predicate));
    } else if (predicate(full)) {
      results.push(full);
    }
  }
  return results;
}

function discoverTasks(dir = TASK_DIR, prefix = ""): TaskInfo[] {
  if (!existsSync(dir)) return [];

  const tasks: TaskInfo[] = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith(".")) continue;
    const full = join(dir, entry.name);
    const name = entry.name === "_default" ? prefix : prefix ? `${prefix}:${entry.name}` : entry.name;

    if (entry.isDirectory()) {
      tasks.push(...discoverTasks(full, prefix ? `${prefix}:${entry.name}` : entry.name));
      continue;
    }

    const mode = statSync(full).mode;
    if ((mode & 0o111) === 0) continue;

    const src = read(full);
    const description = src.match(/^#MISE description="(.+)"$/m)?.[1] ?? "";
    tasks.push({ name, description });
  }

  return tasks.sort((a, b) => a.name.localeCompare(b.name));
}

function countBatsTests(): number {
  return walkFiles(TEST_DIR, (path) => path.endsWith(".bats"))
    .map(read)
    .join("\n")
    .match(/@test\s+"/g)?.length ?? 0;
}

function configuredLints(): string[] {
  const miseToml = read(join(REPO_DIR, "mise.toml"));
  const start = miseToml.indexOf("[_.codebase]");
  if (start === -1) return [];

  const lines = miseToml.slice(start).split("\n");
  const block: string[] = [];
  for (const [index, line] of lines.entries()) {
    if (index > 0 && line.startsWith("[")) break;
    block.push(line);
  }

  const list = block.join("\n").match(/lint\s*=\s*\[([\s\S]*?)\]/)?.[1] ?? "";
  return [...list.matchAll(/"([^"]+)"/g)].map((match) => match[1]);
}

function waveform(seed: string, width = 72): string {
  const bars = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"];
  if (!seed) return bars[0].repeat(width);

  let hash = 0;
  const out: string[] = [];
  for (let i = 0; i < width; i += 1) {
    hash = (hash * 33 + seed.charCodeAt(i % seed.length) + i * 17) % 9973;
    out.push(bars[hash % bars.length]);
  }
  return out.join("");
}

function task(name: string): TaskInfo | undefined {
  return tasks.find((candidate) => candidate.name === name);
}

function taskLine(name: string): string {
  const info = task(name);
  return `${name.padEnd(16)} ${info?.description ?? ""}`.trimEnd();
}

const tasks = discoverTasks();
const testCount = countBatsTests();
const lints = configuredLints();
const signal = waveform(tasks.map((item) => `${item.name}:${item.description}`).join("|"));
const captureFlow = [
  "mic",
  "capture:start",
  "audio.wav",
  "transcribe",
  "transcript.txt",
  "capture.md",
  "Pi editor",
].join("  →  ");

const commandDeck = [
  "capture",
  "capture:start",
  "capture:stop",
  "capture:toggle",
  "capture:status",
  "devices",
  "mic:probe",
  "mic:configure",
  "transcribe",
  "recording:list",
]
  .map(taskLine)
  .join("\n");

const readme = (
  <>
    <Center>
      <Heading level={1}>{PROJECT.name}</Heading>

      <Raw>{`<pre>
╭──────────────────────────────────────────────────────────────────────────────╮
│ ${signal} │
│ mic  →  audio.wav  →  transcript.txt  →  capture.md  →  agent/editor       │
╰──────────────────────────────────────────────────────────────────────────────╯
</pre>
`}</Raw>

      <Paragraph>
        <Bold>{PROJECT.oneLine}</Bold>
      </Paragraph>

      <Paragraph>{PROJECT.tagline}</Paragraph>

      <Badges>
        <Badge label="shape" value="mise + BATS" color="4EAA25" logo="gnubash" logoColor="white" />
        <Badge label="tests" value={`${testCount}`} color="brightgreen" href="test/" />
        <Badge label="tasks" value={`${tasks.length}`} color="8b5cf6" />
        <Badge label="lints" value={`${lints.length}`} color="blue" />
        <Badge label="README" value="TSX" color="f472b6" />
        <Badge label="License" value={PROJECT.license} color="blue" href="LICENSE" />
      </Badges>
    </Center>

    <LineBreak />

    <Section title="What this is">
      <Paragraph>
        <Code>voice</Code>
        {" records microphone audio with ffmpeg, sends the audio through "}
        <Code>monkeys listen</Code>
        {", and writes a capture artifact that has enough structure for humans and agents to use it later."}
      </Paragraph>

      <Paragraph>
        {"The first shape is deliberately batch-oriented: capture a thought, transcribe it, inspect or route it. That makes it useful for agent sessions, hotkeys, and Pi extensions without pretending every transcript is ready to auto-submit."}
      </Paragraph>
    </Section>

    <Section title="The signal path">
      <CodeBlock>{captureFlow}</CodeBlock>

      <Paragraph>
        {"The waveform at the top is generated from the current task tree at README build time. If the command surface changes, the strip changes with it."}
      </Paragraph>
    </Section>

    <Section title="Quick start">
      <CodeBlock lang="bash">{`gh repo clone KnickKnackLabs/voice
cd voice
mise trust
mise install

# See local AVFoundation audio devices and find a live input.
mise run devices
mise run mic:probe
mise run mic:configure --device :1

# Foreground capture: record, transcribe, render.
mise run capture --duration 5 --json

# Background/hotkey shape: start now, stop+transcribe later.
mise run capture:toggle --max-duration 300 --json
mise run capture:status --json
mise run capture:toggle --json

# List saved capture artifacts.
mise run recording:list`}</CodeBlock>
    </Section>

    <Section title="Installed command shape">
      <Paragraph>
        {"After shiv install, the same tasks become ordinary command words:"}
      </Paragraph>

      <CodeBlock lang="bash">{`voice capture
voice capture:start --max-duration 300
voice capture:stop --json
voice capture:toggle
voice capture:status
voice devices
voice mic:probe --yes --json
voice mic:configure --device :1
voice transcribe path/to/audio.wav
voice recording:list --json`}</CodeBlock>
    </Section>

    <Section title="Pi extension target">
      <CodeBlock>{`/voice
  idle     → start background capture, show recording status
  active   → stop, transcribe, paste transcript into the editor
  long     → let Pi collapse it with normal paste handling
  unsure   → user edits before sending`}</CodeBlock>
    </Section>

    <Section title="Artifact layout">
      <Paragraph>{"Captures are written outside the repo by default:"}</Paragraph>

      <CodeBlock>{`${"${XDG_DATA_HOME:-~/.local/share}"}/voice/captures/<capture-id>/
├── audio.wav
├── transcript.txt
└── capture.md`}</CodeBlock>

      <Paragraph>
        {"Background recording state lives under "}
        <Code>{"${XDG_STATE_HOME:-~/.local/state}/voice/recording.json"}</Code>
        {". The configured default microphone lives in "}
        <Code>{"${XDG_CONFIG_HOME:-~/.config}/voice/config.json"}</Code>
        {". Override with "}
        <Code>VOICE_DATA_HOME</Code>
        {", "}
        <Code>VOICE_STATE_HOME</Code>
        {", and "}
        <Code>VOICE_CONFIG_HOME</Code>
        {" when testing or routing captures into a custom workspace."}
      </Paragraph>
    </Section>

    <Section title="Why the artifact matters">
      <List>
        <Item>
          <Bold>Audio stays available</Bold>
          {" for re-transcription when ASR gets better."}
        </Item>
        <Item>
          <Bold>Transcript stays plain</Bold>
          {" so other tools can consume it cheaply."}
        </Item>
        <Item>
          <Bold>Markdown owns the thought</Bold>
          {" with frontmatter, notes, routing decisions, summaries, and follow-up."}
        </Item>
      </List>
    </Section>

    <Details summary="Current task deck">
      <CodeBlock>{commandDeck}</CodeBlock>
    </Details>

    <Section title="Development">
      <CodeBlock lang="bash">{`mise run test
mise run doctor
codebase lint "$PWD"
readme build --check
git diff --check`}</CodeBlock>
    </Section>

    <Center>
      <Raw>{"---\n\n"}</Raw>
      <Sub>
        {"Generated from "}
        <Code>README.tsx</Code>
        {" with "}
        <Link href="https://github.com/KnickKnackLabs/readme">KnickKnackLabs/readme</Link>
        {"."}
        <Raw>{"<br />"}</Raw>
        {"Speak, then decide what the words are for."}
      </Sub>
    </Center>
  </>
);

console.log(readme);
