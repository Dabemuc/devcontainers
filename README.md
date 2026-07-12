# devcontainers

My collection of dev containers for programming — Rust / Go / TypeScript on Debian
trixie + Podman — sharing one `common-setup` feature that auto-installs my dotfiles,
Neovim, and tmux. A `dev.sh` launcher gives a one-command, terminal-first workflow.

## Prerequisites (host machine)

- **Container runtime** — [Podman](https://podman.io/) or Docker. `dev.sh`
  auto-detects (override with `DEV_DOCKER=docker`). On Windows, make sure the
  machine is up: `podman machine start`.
- **Node.js + the devcontainer CLI** — required by `dev.sh`:
  ```sh
  npm install -g @devcontainers/cli
  ```
- **A shell to run `dev.sh`** — **Git Bash** on Windows, or your native shell on
  macOS/Linux. It reuses your git credential helper (GCM / osxkeychain / …) to
  clone private repos into the container.
- **A Nerd Font**, installed on the host and selected in your terminal — otherwise
  Neovim/tmux icons render as boxes:
  ```sh
  # Windows
  winget install DEVCOM.JetBrainsMonoNerdFont
  # macOS
  brew install --cask font-jetbrains-mono-nerd-font
  # Linux: your package manager, or download from nerdfonts.com
  ```
  then set the family (e.g. `JetBrainsMono NFM`) in your terminal config.
- **A terminal** — Alacritty, or any modern terminal (Windows Terminal, VS Code,
  Ghostty, Kitty, …).
- *For the VS Code flow only (optional):* **VS Code** + the **Dev Containers**
  extension, with `"dev.containers.dockerPath": "podman"` in user settings.

## Layout

```
devcontainers/
└── .devcontainer/
    ├── dev.sh                     # host launcher: create/start container → tmux
    ├── README.md                  # provenance note (travels with vendored copies)
    ├── common-setup/              # shared local feature
    │   ├── devcontainer-feature.json  # metadata + options (dotfiles repo URLs)
    │   ├── install.sh                 # build time (root): install tooling
    │   └── post-create.sh             # container creation: clone + link dotfiles/skills
    ├── rust/devcontainer.json
    ├── go/devcontainer.json
    └── typescript/devcontainer.json
```

Everything lives under one `.devcontainer/` because the Dev Containers extension
only accepts local features that resolve **inside** that folder; each language
config references the shared feature as `../common-setup`.

## Use it — terminal (primary)

From the repo root (Git Bash on Windows, or your shell on macOS/Linux):

```sh
./.devcontainer/dev.sh            # rust (default)
./.devcontainer/dev.sh go
./.devcontainer/dev.sh typescript --rebuild   # force recreate (e.g. after changing the feature)
```

`dev.sh` creates the container if needed (else starts it) and drops you into a tmux
session. It drives the `@devcontainers/cli` + Podman directly — no VS Code. Because
the CLI doesn't forward credentials like VS Code does, `dev.sh` pulls your GitHub
token from Git Credential Manager and passes it to the build as a one-time
**secret**, so private dotfiles still clone on first creation. Reusing an existing
container needs no token.

## Use it — VS Code

Open the repo root in VS Code → `Ctrl+Shift+P` → **Dev Containers: Reopen in
Container**, then pick `rust-dev` / `go-dev` / `typescript-dev` (VS Code
auto-discovers every `.devcontainer/*/devcontainer.json`).

## Use in another project

Vendor just `.devcontainer/` into any project (no root README, no `.git` — plain
files; `common-setup` comes along since it lives inside `.devcontainer/`). From the
**project root** (Git Bash on Windows, or your shell on macOS/Linux):

```sh
curl -fsSL https://github.com/Dabemuc/devcontainers/archive/refs/heads/main.tar.gz \
  | tar -xz --strip-components=1 devcontainers-main/.devcontainer
```

Then `./.devcontainer/dev.sh rust` (or go / typescript). `dev.sh` locates itself, so
the project root becomes the workspace. Re-run the same `curl … | tar …` to update.

## How it works

- **`install.sh`** (build time, root): installs `tmux git curl ripgrep
  build-essential ncurses-term` + the latest Neovim static build + the tree-sitter
  CLI, then stages `post-create.sh` at `/usr/local/share/common-setup/` (also
  symlinked as `dev-setup`).
- **`post-create.sh`** (container creation, `vscode` user): sparse-clones the
  dotfiles repo (only the paths in its `DOTFILES_LINKS` map — `nvim` →
  `~/.config/nvim`, `tmux` → `~/.config/tmux`, incl. their git submodules) and
  symlinks them; then full-clones `llm-skills` and links each skill folder (any
  subdir with a `SKILL.md`) into `~/.claude/skills/` for Claude Code.

## Adding a language

Copy any `.devcontainer/<lang>/devcontainer.json`, change the `image` and the
`extensions` list. Everything else is identical.

## Notes / troubleshooting

- **Rendering:** run Neovim via `dev.sh` (inside tmux). A raw `podman exec` pty
  ghosts Neovim's redraws; tmux fixes it. `dev.sh` also forces
  `TERM=xterm-256color` and `LANG=C.UTF-8` for correct colors and nerd-font glyphs.
- **Credentials (VS Code flow):** relies on VS Code's git credential forwarding
  (supports GCM). If a clone fails at create time, re-run `dev-setup` in the
  integrated terminal. Use **HTTPS** repo URLs, not SSH.
- **Podman file permissions:** if bind-mounted workspace files show wrong
  ownership, add to the language `devcontainer.json`:
  ```json
  "runArgs": ["--userns=keep-id:uid=1000,gid=1000"]
  ```
