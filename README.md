# devcontainers

My collection of dev containers for programming, sharing one `common-setup` feature.

## Layout

```
devcontainers/
└── .devcontainer/
    ├── common-setup/               # shared local feature
    │   ├── devcontainer-feature.json   # metadata + options (repo URLs)
    │   ├── install.sh                  # build time (root): install tooling, stage runtime script
    │   └── post-create.sh              # container creation (vscode): clone + bootstrap dotfiles
    ├── rust/devcontainer.json
    ├── go/devcontainer.json
    └── typescript/devcontainer.json
```

Everything lives under one `.devcontainer/` because the Dev Containers extension
only accepts local features that resolve **inside** the `.devcontainer/` folder.
Each language config references the shared feature as `../common-setup`.

## How to use

Open the **repo root** in VS Code, then `Ctrl+Shift+P` → **Dev Containers: Reopen
in Container** — you'll get a picker listing `rust-dev`, `go-dev`, `typescript-dev`
(VS Code auto-discovers every `.devcontainer/*/devcontainer.json`). Pick one.

```
code G:\CodingProjects\devcontainers
```

## Terminal launcher (`dev.sh`)

For a terminal-first (nvim) workflow, `dev.sh` starts a container — **creating it if
it doesn't exist** — and drops you into a **tmux** session (`main`), all in one
command. Run it from **Git Bash**:

```sh
./.devcontainer/dev.sh            # rust (default)
./.devcontainer/dev.sh go
./.devcontainer/dev.sh typescript --rebuild   # force recreate (e.g. after feature changes)
```

It uses the `@devcontainers/cli` + Podman directly (no VS Code). Because the CLI
doesn't forward credentials the way VS Code does, `dev.sh` extracts your GitHub
token from the Windows credential manager (GCM) and passes it to the build as a
one-time **secret**, so private repos still clone on first creation. Reusing an
existing container needs no token.

Prerequisites (already installed on this machine):
- Podman (with `dev.containers.dockerPath: podman` for the VS Code flow)
- Node.js + `npm install -g @devcontainers/cli`

## How it works

- **`install.sh`** runs once at image build time as root: installs `tmux git curl`
  plus the latest official **neovim** static build (newer than the base image's
  apt neovim), then stages `post-create.sh` + the configured repo URLs at
  `/usr/local/share/common-setup/`. It also symlinks `dev-setup` onto the PATH.
- **`post-create.sh`** runs at container creation as the `vscode` user via
  `postCreateCommand`: sparse-clones the dotfiles repo (only the paths in its
  `DOTFILES_LINKS` map, e.g. `nvim` → `~/.config/nvim`) and symlinks them into
  place, then full-clones `llm-skills` to `~/.llm-skills` and symlinks each skill
  folder (any subdir with a `SKILL.md`) into `~/.claude/skills/` so Claude Code
  auto-discovers them.

## Credentials

Cloning private repos relies on **VS Code's automatic git credential forwarding**,
which supports Git Credential Manager. Nothing is copied or mounted. If a clone
fails at create time, open the integrated terminal (forwarding is always active
there) and re-run `dev-setup`. Use **HTTPS** repo URLs, not SSH.

## Runtime: Podman

This machine uses Podman, set in VS Code user settings:

```json
"dev.containers.dockerPath": "podman"
```

If bind-mounted workspace files show up with wrong ownership / permission errors,
add to the relevant `devcontainer.json`:

```json
"runArgs": ["--userns=keep-id:uid=1000,gid=1000"]
```

## Adding a language

Copy any `.devcontainer/<lang>/devcontainer.json`, change the `image` and the
`extensions` list. Everything else is identical.

## Reusing outside this repo

The local feature only resolves inside this repo's `.devcontainer/`. To use
`common-setup` in an arbitrary project, publish it to GHCR and reference it as
`ghcr.io/dabemuc/devcontainer-features/common-setup:1`. Ask and I'll add the
GitHub Actions publish workflow.
