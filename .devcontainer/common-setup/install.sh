#!/usr/bin/env bash
# Runs ONCE at image build time, as root. No network access to your host /
# no forwarded git credentials here — so we only install tooling and stage the
# runtime script. Actual cloning happens later in post-create.sh.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
  tmux git curl ca-certificates tar \
  ripgrep build-essential ncurses-term
rm -rf /var/lib/apt/lists/*
# ncurses-term provides the `alacritty` (and many other) terminfo entries. Without
# it, TERM=alacritty has no terminfo in the container and Neovim's redraws ghost
# (buffer text bleeding into the nvim-tree sidebar, etc.).
# build-essential provides gcc/g++/make — needed by nvim-treesitter to compile
# parsers (the Linux equivalent of NvChad's mingw + GnuWin32 requirement).
# ripgrep backs Telescope's live grep.

# Neovim: install the latest official static build (trixie's apt neovim is 0.10 —
# fine for LazyVim/NvChad, but this keeps us on the newest release).
NVIM_ARCH="$(uname -m)"   # x86_64 or aarch64
case "$NVIM_ARCH" in
  x86_64)  NVIM_ASSET="nvim-linux-x86_64" ;;
  aarch64) NVIM_ASSET="nvim-linux-arm64" ;;
  *) echo "unsupported arch for neovim: $NVIM_ARCH" >&2; exit 1 ;;
esac
curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/${NVIM_ASSET}.tar.gz" \
  | tar -xz -C /opt
ln -sf "/opt/${NVIM_ASSET}/bin/nvim" /usr/local/bin/nvim
echo "✔ neovim $(/usr/local/bin/nvim --version | head -1)"

# tree-sitter CLI: prebuilt binary (avoids needing npm/cargo, which not every
# base image has). Required by nvim-treesitter to build parsers. The latest
# binary needs glibc >= 2.39, satisfied by the trixie base (glibc 2.41).
case "$NVIM_ARCH" in
  x86_64)  TS_ASSET="tree-sitter-linux-x64" ;;
  aarch64) TS_ASSET="tree-sitter-linux-arm64" ;;
esac
curl -fsSL "https://github.com/tree-sitter/tree-sitter/releases/latest/download/${TS_ASSET}.gz" \
  | gunzip > /usr/local/bin/tree-sitter
chmod 0755 /usr/local/bin/tree-sitter
echo "✔ tree-sitter $(/usr/local/bin/tree-sitter --version)"

# Stage the runtime script + resolved option values to a persistent location so
# postCreateCommand can call it by absolute path (the feature's own build dir is
# temporary and the language folder that references it is not mounted at runtime).
SHARE_DIR=/usr/local/share/common-setup
install -d "$SHARE_DIR"
install -m 0755 "$(dirname "$0")/post-create.sh" "$SHARE_DIR/post-create.sh"

# Feature option ids are passed in as UPPERCASED env vars (dotfilesRepo -> DOTFILESREPO).
cat > "$SHARE_DIR/config.env" <<EOF
DOTFILES_REPO="${DOTFILESREPO:-}"
LLM_SKILLS_REPO="${LLMSKILLSREPO:-}"
EOF

# Convenience: let the user re-run the clone/bootstrap from the integrated
# terminal (where credential forwarding is always active) with 'dev-setup'.
ln -sf "$SHARE_DIR/post-create.sh" /usr/local/bin/dev-setup

echo "✔ common-setup: tooling installed, runtime script staged at $SHARE_DIR"
