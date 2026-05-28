# Installation

The one-liner from [README.md](../README.md) covers 95% of cases. This file documents the details, manual install, env-var overrides, and security inspection — for anyone who needs more control than the default install gives.

## What `install.sh` does

```bash
curl --proto '=https' --tlsv1.2 -fsSL \
    https://raw.githubusercontent.com/restarter/bb-bash/main/scripts/install.sh | bash
```

On run:

1. Fetches the latest tagged release from `restarter/bb-bash`.
2. Installs the binary into `~/.local/share/bb-bash/` (data dir).
3. Symlinks the binary into your `$PATH`:
   - `/usr/local/bin/bbb` if writable (system-wide).
   - Otherwise `~/.local/bin/bbb` (user-only, no sudo).
4. On first install only, creates `.env` from `.env.example` (chmod 600 via `umask 077`).
5. Refreshes `.env.example` on every run (chmod 644) so you can `diff` for new variables.
6. Writes a `VERSION` marker so repeated runs at the same tag skip the download.

**Re-running the same command upgrades to the latest release. Your `.env` is never overwritten.**

## Env-var overrides

| Variable | Purpose |
|---|---|
| `BB_BASH_USER_ONLY=1` | Force install into `~/.local/bin` even if `/usr/local/bin` is writable. |
| `BB_BASH_FORCE=1` | Overwrite an existing non-symlink at the target PATH location (default: refuses). |
| `BB_BASH_REF=<git-ref>` | `install-agent` only — pin agent-artifact fetch to a specific ref (default `main`). |

## Manual install (no `install.sh`)

For air-gapped boxes, custom layouts, or contributing:

```bash
git clone https://github.com/restarter/bb-bash ~/.local/share/bb-bash
ln -s ~/.local/share/bb-bash/bbb ~/.local/bin/bbb    # or /usr/local/bin/bbb
cp ~/.local/share/bb-bash/.env.example ~/.local/share/bb-bash/.env
chmod 600 ~/.local/share/bb-bash/.env
$EDITOR ~/.local/share/bb-bash/.env                  # add BB_BASH_EMAIL + BB_BASH_TOKEN
```

`bbb` resolves symlinks at startup so it always finds `.env` in the data dir, regardless of which `$PATH` location you symlinked through.

## Security inspection

The default install relies on HTTPS transport integrity (the `--proto '=https' --tlsv1.2` curl flags reject HTTP redirects and TLS downgrade attempts). There's no SHA pinning on `install.sh` itself.

If your threat model requires offline review, download first and read it:

```bash
curl --proto '=https' --tlsv1.2 -fsSL \
    https://raw.githubusercontent.com/restarter/bb-bash/main/scripts/install.sh -o install.sh
less install.sh   # review
bash install.sh
```

Same applies to `bbb install-agent --rule --skill --claude --agents` — it fetches artifact files from `raw.githubusercontent.com`. Pin a release tag for reproducibility:

```bash
BB_BASH_REF=v0.2.0 bbb install-agent --rule --skill --claude --agents
```

## Dependencies

- `curl` — for `install.sh` and runtime API calls.
- `jq` — for JSON parsing. Install via `brew install jq` (macOS) / `apt install jq` (Debian/Ubuntu).
