# .devcontainer

Vendored from **[Dabemuc/devcontainers](https://github.com/Dabemuc/devcontainers)** — a
shared dev container setup (Rust / Go / TypeScript on Debian trixie + Podman, with
dotfiles, Neovim, and tmux auto-installed). These are plain files copied from that
repo — there's no git history here; the upstream repo is the source of truth.

## Use

From the **project root** (Git Bash on Windows, or your shell on macOS/Linux):

```sh
./.devcontainer/dev.sh rust        # or: go | typescript
```

It creates-or-starts the container and drops you into a tmux session. Force a
rebuild after changing anything here with `--rebuild`. See the upstream repo's
README for how it all works.

## Update

Re-run the same command that vendored it, from the **project root**:

```sh
curl -fsSL https://github.com/Dabemuc/devcontainers/archive/refs/heads/main.tar.gz \
  | tar -xz --strip-components=1 devcontainers-main/.devcontainer
```

This overwrites `.devcontainer/` with the latest upstream. Review the diff and
commit it.
