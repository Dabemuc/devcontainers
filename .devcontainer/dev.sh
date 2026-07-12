#!/usr/bin/env bash
# dev.sh — start (creating if needed) a language devcontainer and drop into bash.
#
#   ./.devcontainer/dev.sh            # defaults to rust
#   ./.devcontainer/dev.sh go
#   ./.devcontainer/dev.sh typescript --rebuild
#
# Run from Git Bash on Windows. Uses Podman + the @devcontainers/cli, and pulls
# your GitHub token from the Windows credential manager so private repos clone on
# first creation (the CLI, unlike VS Code, does not forward credentials).
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

# Ensure node + the devcontainer CLI are reachable even if this shell's PATH was
# not refreshed since install ($APPDATA is a Windows path, so convert it).
export PATH="/c/Program Files/nodejs:$(cygpath -u "$APPDATA")/npm:$PATH"
command -v devcontainer >/dev/null \
  || { echo "devcontainer CLI not found — run: npm install -g @devcontainers/cli" >&2; exit 1; }

# Windows path with a lowercase drive letter (matches the container labels VS Code
# writes, so we reuse the same container instead of creating a duplicate).
to_win() {
  local w drive rest
  w="$(cygpath -w "$1")"
  drive="${w%%:*}"; rest="${w#*:}"
  printf '%s:%s' "$(printf '%s' "$drive" | tr 'A-Z' 'a-z')" "$rest"
}
dc_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # the .devcontainer folder
win_root="$(to_win "$(dirname "$dc_dir")")"              # repo root = parent of .devcontainer
win_config="$(to_win "$dc_dir/$lang/devcontainer.json")"

# Pull the GitHub token and stage it as a devcontainer secret (removed right after
# the build). Absent token -> warn and continue (fine for reusing an existing
# container, or if the repos are already cloned).
secrets_file=""
cleanup() { [ -n "$secrets_file" ] && rm -f "$secrets_file" || true; }
trap cleanup EXIT
token="$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill 2>/dev/null | sed -n 's/^password=//p' || true)"

up_args=(up --workspace-folder "$win_root" --config "$win_config" --docker-path podman)
[ "$rebuild" = 1 ] && up_args+=(--remove-existing-container)
if [ -n "$token" ]; then
  secrets_file="$(mktemp)"
  printf '{"GITHUB_TOKEN":"%s"}' "$token" > "$secrets_file"
  up_args+=(--secrets-file "$(cygpath -w "$secrets_file")")
else
  echo "⚠ No GitHub token from credential manager; private clones may fail on a fresh build." >&2
fi

echo "▶ devcontainer up ($lang)…"
devcontainer "${up_args[@]}"

# Token only needed during the build above — remove it before the interactive shell.
cleanup; secrets_file=""; trap - EXIT

echo "▶ entering $lang container (tmux 'main' — detach with Ctrl-b d)…"
# Run inside tmux: the raw podman-exec pty mangles Neovim's scroll/redraw sequences
# (ghosting — buffer text bleeding into the nvim-tree sidebar). tmux owns the screen
# and redraws cleanly, which fixes it. TERM=xterm-256color gives complete redraw
# caps; LANG=C.UTF-8 makes tmux render nerd-font glyphs (else they show as boxes).
exec_args=(exec --remote-env TERM=xterm-256color --remote-env LANG=C.UTF-8 \
  --workspace-folder "$win_root" --config "$win_config" --docker-path podman \
  tmux -u new-session -A -s main)

# Modern terminals (Alacritty, Windows Terminal, VS Code) provide a ConPTY: it
# gives native programs a real TTY AND passes 24-bit truecolor through, so run the
# CLI directly. Legacy mintty (the classic Git Bash window) can't hand a ConPTY to
# native programs and needs winpty — but winpty mangles truecolor SGR codes. Only
# opt into it with DEV_USE_WINPTY=1 if you launch from a mintty window.
if [ "${DEV_USE_WINPTY:-0}" = 1 ] && command -v winpty >/dev/null 2>&1; then
  cli_js="$(cygpath -u "$APPDATA")/npm/node_modules/@devcontainers/cli/devcontainer.js"
  node_win="$(cygpath -w "$(command -v node)")"
  case "$node_win" in *.exe|*.EXE) ;; *) node_win="${node_win}.exe" ;; esac
  exec winpty "$node_win" "$(cygpath -w "$cli_js")" "${exec_args[@]}"
else
  exec devcontainer "${exec_args[@]}"
fi
