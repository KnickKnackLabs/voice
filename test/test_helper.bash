#!/usr/bin/env bash
# Shared fixtures for voice tests.

# Run a repo task through mise so tests exercise the real task path.
voice() {
  cd "$REPO_DIR" && mise run -q "$@"
}
export -f voice
