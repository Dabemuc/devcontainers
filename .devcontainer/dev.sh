#!/usr/bin/env bash
# dev.sh — start (creating if needed) a language devcontainer and drop into tmux.
#
#   ./.devcontainer/dev.sh            # defaults to rust
#   ./.devcontainer/dev.sh go
#   ./.devcontainer/dev.sh typescript --rebuild
#
# Cross-platform: Git Bash on Windows, or a normal shell on macOS/Linux. Uses the
# @devcontainers/cli with Podman or Docker, and pulls your GitHub token from git's
# credential helper so private repos clone on first creation (the CLI, unlike VS
# Code, does not forward credentials).
#
# Env:
#   DEV_DOCKER=docker|podman   force the container runtime (default: auto-detect)
#   DEV_USE_WINPTY=1           Windows-only: use winpty for the legacy mintty window
set -euo pipefail

lang="rust"
rebuild=0
for arg in "$@"; do
  case "$arg" in
    --rebuild|-r)       rebuild=1 ;;
    rust|go|typescript) lang="$arg" ;;
    *) echo "Usage: $0 [rust|go|typescript] [--rebuild]" >&2; exit 1 ;;
  esac
done

# On Windows/Git Bash the CLI may not be on PATH yet (fresh install, unrefreshed
# shell); add the usual install dirs. No-op on macOS/Linux where it's already there.
if command -v cygpath >/dev/null 2>&1; then
  export PATH="/c/Program Files/nodejs:$(cygpath -u "$APPDATA")/npm:$PATH"
fi
command -v devcontainer >/dev/null \
  || { echo "devcontainer CLI not found — run: npm install -g @devcontainers/cli" >&2; exit 1; }

# Container runtime: DEV_DOCKER wins, else prefer podman, else docker.
docker_path="${DEV_DOCKER:-}"
if [ -z "$docker_path" ]; then
  if   command -v podman >/dev/null 2>&1; then docker_path=podman
  elif command -v docker >/dev/null 2>&1; then docker_path=docker
  else echo "neither podman nor docker found on PATH" >&2; exit 1; fi
fi

# Path form for the CLI. On Windows the CLI (and the container labels VS Code
# writes) use Windows paths with a lowercase drive letter; on POSIX, unchanged.
to_path() {
  if command -v cygpath >/dev/null 2>&1; then
    local w drive rest
    w="$(cygpath -w "$1")"; drive="${w%%:*}"; rest="${w#*:}"
    printf '%s:%s' "$(printf '%s' "$drive" | tr 'A-Z' 'a-z')" "$rest"
  else
    printf '%s' "$1"
  fi
}
dc_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # the .devcontainer folder
ws_root="$(to_path "$(dirname "$dc_dir")")"              # repo root = parent of .devcontainer
ws_config="$(to_path "$dc_dir/$lang/devcontainer.json")"

# Pull the GitHub token from git's credential helper (GCM on Windows, osxkeychain on
# macOS, etc.) and stage it as a devcontainer secret (removed right after the build).
# Absent token -> warn and continue (fine for reusing an existing container, or if
# the repos are already cloned). GIT_TERMINAL_PROMPT=0 avoids hanging on a prompt
# when no credential helper is configured.
secrets_file=""
cleanup() { [ -n "$secrets_file" ] && rm -f "$secrets_file" || true; }
trap cleanup EXIT
token="$(printf 'protocol=https\nhost=github.com\n\n' \
  | GIT_TERMINAL_PROMPT=0 git credential fill 2>/dev/null | sed -n 's/^password=//p' || true)"

up_args=(up --workspace-folder "$ws_root" --config "$ws_config" --docker-path "$docker_path")
[ "$rebuild" = 1 ] && up_args+=(--remove-existing-container)
if [ -n "$token" ]; then
  secrets_file="$(mktemp)"
  printf '{"GITHUB_TOKEN":"%s"}' "$token" > "$secrets_file"
  up_args+=(--secrets-file "$(to_path "$secrets_file")")
else
  echo "⚠ No GitHub token from credential helper; private clones may fail on a fresh build." >&2
fi

echo "▶ devcontainer up ($lang)…"
devcontainer "${up_args[@]}"

# Token only needed during the build above — remove it before the interactive shell.
cleanup; secrets_file=""; trap - EXIT

echo "▶ entering $lang container (tmux 'main' — detach with Ctrl-b d)…"
# Run inside tmux: the raw exec pty mangles Neovim's scroll/redraw sequences
# (ghosting — buffer text bleeding into the nvim-tree sidebar). tmux owns the screen
# and redraws cleanly, which fixes it. TERM=xterm-256color gives complete redraw
# caps; LANG=C.UTF-8 makes tmux render nerd-font glyphs (else they show as boxes).
exec_args=(exec --remote-env TERM=xterm-256color --remote-env LANG=C.UTF-8 \
  --workspace-folder "$ws_root" --config "$ws_config" --docker-path "$docker_path" \
  tmux -u new-session -A -s main)

# Modern terminals (Alacritty, Windows Terminal, VS Code, macOS/Linux terminals)
# give native programs a real TTY and pass truecolor through — run the CLI directly.
# The legacy Windows mintty window can't; it needs winpty (which mangles truecolor),
# so that path is opt-in via DEV_USE_WINPTY=1 and only reachable on Windows.
if [ "${DEV_USE_WINPTY:-0}" = 1 ] && command -v winpty >/dev/null 2>&1; then
  cli_js="$(cygpath -u "$APPDATA")/npm/node_modules/@devcontainers/cli/devcontainer.js"
  node_win="$(cygpath -w "$(command -v node)")"
  case "$node_win" in *.exe|*.EXE) ;; *) node_win="${node_win}.exe" ;; esac
  exec winpty "$node_win" "$(cygpath -w "$cli_js")" "${exec_args[@]}"
else
  exec devcontainer "${exec_args[@]}"
fi
