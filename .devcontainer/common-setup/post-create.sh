#!/usr/bin/env bash
# Runs at container creation (postCreateCommand) AND is re-runnable by hand as
# `dev-setup`. Runs as the remote user (vscode), with VS Code's forwarded git
# credentials active — so cloning private HTTPS repos "just works".
set -euo pipefail

# Load repo URLs staged by install.sh (may be overridden by env for manual runs).
CONFIG=/usr/local/share/common-setup/config.env
[ -f "$CONFIG" ] && . "$CONFIG"

DOTFILES_REPO="${DOTFILES_REPO:-}"
LLM_SKILLS_REPO="${LLM_SKILLS_REPO:-}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
LLM_SKILLS_DIR="${LLM_SKILLS_DIR:-$HOME/.llm-skills}"

# If a GitHub token was passed as a secret (the `dev` launcher extracts it from
# the host credential manager), set up a credential helper so private HTTPS
# clones work when the container was created outside VS Code — VS Code forwards
# credentials itself, in which case GITHUB_TOKEN is unset and this is skipped.
if [ -n "${GITHUB_TOKEN:-}" ]; then
  git config --global credential.helper store
  printf 'https://x-access-token:%s@github.com\n' "$GITHUB_TOKEN" > "$HOME/.git-credentials"
  chmod 600 "$HOME/.git-credentials"
  echo "✔  configured git credentials from provided token"
fi

# Which subpaths of the dotfiles repo we actually use in containers, mapped to
# where each should be linked. The repo as a whole is nix/home-manager-managed
# on macOS; here we sparse-fetch and link only these. Add an entry to extend.
declare -A DOTFILES_LINKS=(
  [nvim]="$HOME/.config/nvim"
)

# clone_or_update REPO DIR NAME [sparse_path...]
# With sparse paths: a partial (blob:none) + sparse clone — only those paths'
# blobs are downloaded. Without: a normal shallow clone of the whole repo.
clone_or_update() {
  local repo="$1" dir="$2" name="$3"; shift 3
  local sparse=("$@")

  if [ -z "$repo" ]; then
    echo "ℹ  $name: no repo configured — skipping"
    return 0
  fi

  if [ -d "$dir/.git" ]; then
    echo "↻  $name: already present at $dir — updating"
    if [ ${#sparse[@]} -gt 0 ]; then
      git -C "$dir" sparse-checkout set "${sparse[@]}" 2>/dev/null || true
    fi
    git -C "$dir" pull --ff-only || echo "⚠  $name: pull failed (continuing)"
    return 0
  fi

  if [ ${#sparse[@]} -gt 0 ]; then
    if git clone --depth=1 --filter=blob:none --sparse "$repo" "$dir" \
       && git -C "$dir" sparse-checkout set "${sparse[@]}"; then
      echo "✔  $name: sparse-cloned (${sparse[*]}) into $dir"
    else
      echo "⚠  $name: clone failed. If auth-related, open the integrated terminal"
      echo "   (credentials are forwarded there) and re-run: dev-setup"
    fi
  else
    if git clone --depth=1 "$repo" "$dir"; then
      echo "✔  $name: cloned into $dir"
    else
      echo "⚠  $name: clone failed — re-run 'dev-setup' from the integrated terminal"
    fi
  fi
}

link_config() {
  local src="$1" dst="$2"
  if [ ! -e "$src" ]; then
    echo "ℹ  $src not found — skipping"
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  ln -sfn "$src" "$dst"
  echo "✔  linked $dst -> $src"
}

# --- dotfiles: sparse-fetch only the paths we link, then link them ---
clone_or_update "$DOTFILES_REPO" "$DOTFILES_DIR" "dotfiles" "${!DOTFILES_LINKS[@]}"
for sub in "${!DOTFILES_LINKS[@]}"; do
  link_config "$DOTFILES_DIR/$sub" "${DOTFILES_LINKS[$sub]}"
done

# --- llm-skills: full clone, then symlink each skill into Claude Code's
# personal skills dir (~/.claude/skills). Claude reads skills live from disk, so
# a symlink per skill means later `git pull`s take effect with no re-run. Mirrors
# the repo's own sync_skills.py, but in bash so no Python is required. ---
clone_or_update "$LLM_SKILLS_REPO" "$LLM_SKILLS_DIR" "llm-skills"

CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
if [ -d "$LLM_SKILLS_DIR" ]; then
  mkdir -p "$CLAUDE_SKILLS_DIR"
  for skill in "$LLM_SKILLS_DIR"/*/; do
    [ -f "${skill}SKILL.md" ] || continue   # only dirs that are actually skills
    link_config "${skill%/}" "$CLAUDE_SKILLS_DIR/$(basename "$skill")"
  done
fi

echo "✔ common-setup: post-create complete"
