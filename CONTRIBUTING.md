# Contributing

`voice` is a mise/shiv tool for local voice capture, transcription, and durable capture artifacts.

## Structure

```text
voice/
├── mise.toml                 # Tools, settings, codebase lint config
├── README.tsx                # Source for generated README.md
├── README.md                 # Generated; keep in sync with README.tsx
├── CONTRIBUTING.md           # Repo orientation surface
├── .mise/tasks/capture/      # Foreground/background capture tasks
├── .mise/tasks/transcribe/   # Audio → transcript wrapper
├── .mise/tasks/recording/    # Capture artifact listing and management
├── lib/common.sh             # Shared storage/state/Markdown helpers
└── test/                     # BATS tests and helpers
```

## Local setup

```bash
mise trust
mise install
mise run test
mise run doctor
```

`doctor` reports whether the optional local `codebase pre-commit` hook is installed.
Install it in your clone when you want convention lints to run before every commit:

```bash
codebase pre-commit
```

The hook lives under `.git/hooks/`, so it is intentionally not tracked by the repo.

## Task style

- Keep public behavior in mise tasks; shiv exposes them as `voice ...` commands.
- Use `$MISE_CONFIG_ROOT` only inside tasks.
- Use `${TOOL:-tool}` for external commands so tests can inject mocks.
- Preserve `--json` for automation and gum-styled output for humans.
- Audio/transcript artifacts live outside the repo by default under XDG data/state paths.

## README workflow

Edit `README.tsx`, then regenerate and check the output:

```bash
readme build
readme build --check
```

CI also checks that `README.md` matches `README.tsx`.

## Validation before merge

```bash
mise run test
codebase lint "$PWD"
readme build --check
git diff --check
```
