<div align="center">

# 📦 Devbox

#### Prepare a development environment once — then pull it as a ready-to-use image, or restore your whole home directory onto any Ubuntu box.

[![GHCR](https://img.shields.io/badge/GHCR-devbox-2496ED?logo=docker&logoColor=white)](https://github.com/charles1614/devbox/pkgs/container/devbox)
[![Multi-arch](https://img.shields.io/badge/arch-amd64_·_arm64-4c1)](#-quick-start)
[![Ubuntu 24.04](https://img.shields.io/badge/Ubuntu-24.04-E95420?logo=ubuntu&logoColor=white)](https://releases.ubuntu.com/24.04/)
[![CUDA 13.1](https://img.shields.io/badge/CUDA-13.1--devel-76B900?logo=nvidia&logoColor=white)](https://hub.docker.com/r/nvidia/cuda)
[![mise](https://img.shields.io/badge/mise-managed-fb923c)](https://mise.jdx.dev/)
[![Neovim](https://img.shields.io/badge/Neovim-lazy.nvim-57A143?logo=neovim&logoColor=white)](https://neovim.io/)
[![zsh](https://img.shields.io/badge/zsh-zinit_·_starship-89e051)](https://starship.rs/)

[Quick start](#-quick-start) · [How it works](#-how-it-works) · [Profiles](#-profiles) · [SSH](#-ssh-access) · [Restore](#-restore) · [Build](#-build-locally) · [Configuration](#-configuration)

</div>

---

**Devbox** is two halves of one pipeline:

- 🐳 **A reproducible Docker image** — `mise` tools, `zinit` shell plugins, a `starship` prompt, and `lazy.nvim` Neovim plugins are all installed *at build time*, then published multi-arch to **GHCR**. `docker pull` and you have a shell that's ready on the first prompt.
- 📦 **A portable offline bundle** — the fully-initialized home directory, packaged to a single `.tar.gz` and restorable onto any Ubuntu host or container, with no network fetches at restore time.

The two are decoupled: **you build online once** (locally or in CI), and **consume offline anywhere** — pull the image, or lay the home archive down on bare metal. New tools are baked in at build; restoring never re-downloads them.

## ✨ Features

- ⚡ **Ready on the first prompt** — every tool, plugin, and prompt is pre-installed during the image build. No `mise install`, no plugin sync, no first-run wait.
- 🎛 **Two profiles** — `mini` for a lean core, `extra` for the full toolbox (languages + modern CLIs). Pick per pull.
- 🧬 **Multi-arch** — `linux/amd64` and `linux/arm64` published together; `docker pull` selects the variant matching your host.
- 🔐 **SSH-native** — an `sshd` on port 22 out of the box, so VS Code Remote-SSH, JetBrains Gateway, or a plain terminal all just connect.
- 🪞 **UID/GID remapping** — [`run-ssh.sh`](scripts/run-ssh.sh) remaps the container user to your host UID/GID at runtime, so bind-mounted `~/.ssh` and `~/.claude` are owned correctly and writable immediately.
- 💾 **Bare-metal restore** — one plain-bash entry point (`scripts/restore.sh`, no `make`/`git` needed) that downloads the Release bundle or consumes a local archive, as the packaged `charles` or **into your own login user** (`--current-user`).
- 🛡 **Fail-fast compatibility** — the restore step refuses incompatible hosts (non-Ubuntu/Debian, or glibc below the build's `2.39`) *before* you end up with silently broken binaries.
- ♻️ **Auto-rebuild on dotfiles** — a push to your dotfiles repo can trigger the devbox CI via `repository_dispatch`, busting the cache from the chezmoi step onward.

## 🏗 How it works

```
  docker/Dockerfile  (CUDA 13.1-devel · Ubuntu 24.04)
      │
      ▼  make prepare  /  CI                build image + run the dotfiles setup
  mise tools · zinit · starship · lazy.nvim        ← baked into /home/<user>
      │
      ├──▶  GHCR    ghcr.io/charles1614/devbox:{mini,extra}-latest   (amd64 + arm64)
      │              docker pull → run → SSH in → ready
      │
      ▼  make package
  charles_home_<profile>_<arch>.tar.gz             ← the whole initialized home
      │
      ▼  restore.sh   (target: Ubuntu ≥ 24.04 · glibc ≥ 2.39)
  /home/<user>  →  su - <user>  →  ready, no network needed
```

The image is the *fast path*; the home archive is the *portable path* for hosts where you'd rather not run a container.

## 🚀 Quick start

> **Prerequisites** — [Docker](https://docs.docker.com/get-docker/). Pre-built,
> multi-arch images are published to GHCR on every push to `main`.

```bash
# Pull a profile (mini or extra)
docker pull ghcr.io/charles1614/devbox:extra-latest

# Interactive shell — ready to use immediately
docker run -it ghcr.io/charles1614/devbox:extra-latest

# …or run in the background with SSH exposed on 2222
docker run -d -p 2222:22 --name devbox ghcr.io/charles1614/devbox:extra-latest
ssh -p 2222 charles@localhost          # default password: devbox
```

All tools (mise), shell plugins (zinit), the starship prompt, and Neovim plugins
(lazy.nvim) are already installed in the image — no initialization needed.

## 🎛 Profiles

| Profile | Tools |
| --- | --- |
| **mini** | python · uv · neovim · fzf · zoxide · chezmoi · zellij · starship · jq · ripgrep · fd |
| **extra** | everything in **mini** + node.js · go · rust · eza · lazygit · delta · bat · dust · yazi · btop · procs · tealdeer · xh · gping · llvm/clang |

Both profiles ship for `amd64` and `arm64`. Tags: `mini-latest`, `extra-latest`
(and per-commit `mini-<sha>` / `extra-<sha>`).

## 🔐 SSH access

The image runs `sshd` on port 22 automatically, so you can connect with any SSH
client instead of `docker exec`.

```bash
docker run -d -p 2222:22 --name devbox ghcr.io/charles1614/devbox:extra-latest
ssh -p 2222 charles@localhost          # default password: devbox
```

> The default SSH password is **`devbox`**. For local builds, override it by
> passing a Docker build secret named `ssh_password` (see [Build locally](#-build-locally)).

<details>
<summary><b>Correct UID/GID + auto-mounted volumes (<code>run-ssh.sh</code>)</b></summary>

The image is built with a fixed username/UID. [`run-ssh.sh`](scripts/run-ssh.sh)
remaps it to the host user at runtime so bind-mounts line up with no permission
dance. It auto-mounts `~/.ssh` (read-only) and `~/.claude` when present.

```bash
./scripts/run-ssh.sh --uid 1001 --gid 1001
./scripts/run-ssh.sh -v ~/projects:/home/charles/projects -v ~/data:/data:ro
ssh -p 2222 charles@localhost
```
</details>

<details>
<summary><b>VS Code Remote-SSH</b></summary>

Add an entry to `~/.ssh/config`:

```
Host devbox
    HostName localhost
    Port 2222
    User charles
```

Then connect to `devbox` from the **Remote-SSH** extension.
</details>

<details>
<summary><b>Use a public key (recommended)</b></summary>

```bash
ssh-copy-id -p 2222 charles@localhost
# or manually
docker exec devbox bash -c "mkdir -p ~/.ssh && echo '$(cat ~/.ssh/id_ed25519.pub)' >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
```

Once a key is installed, password auth is no longer required. Change the password
inside the container with `passwd`.
</details>

## 💾 Restore

For hosts where you'd rather run natively than in a container, restore the
packaged home directory straight onto the machine. Pre-built archives live on the
[Releases](https://github.com/charles1614/devbox/releases) page — pick the one
matching your profile and CPU arch (`uname -m` → `x86_64` = amd64, `aarch64` = arm64):

| Profile | amd64 | arm64 |
| --- | --- | --- |
| **mini** | `charles_home_mini_amd64.tar.gz` | `charles_home_mini_arm64.tar.gz` |
| **extra** | `charles_home_extra_amd64.tar.gz` | `charles_home_extra_arm64.tar.gz` |

One entry point covers both cases — [`scripts/restore.sh`](scripts/restore.sh),
plain bash with **no `make` or `git` required** on the target (minimal cloud
images often lack both). `--file` decides the source:

```bash
# Online host — no --file: auto-detects your CPU arch, downloads the bundle
# from the latest Release, then restores  (--profile extra by default)
sudo ./scripts/restore.sh
sudo ./scripts/restore.sh --profile mini --current-user

# Offline host — --file: restore a local archive you carried over, no download
sudo ./scripts/restore.sh --file charles_home_extra_amd64.tar.gz
sudo ./scripts/restore.sh --file charles_home_extra_amd64.tar.gz --current-user
```

Every flag also works as an environment variable (`CURRENT_USER=1`, `ARCHIVE_FILE=…`,
`PROFILE=…`, `ASSUME_YES=1`, `SKIP_OS_CHECK=1` — flag wins); see `--help` for the
full list. If you have `make`, the equivalent wrapper is:

```bash
sudo make restore                                          # download + restore
sudo make restore FILE=charles_home_extra_amd64.tar.gz     # local archive
make test FILE=charles_home_extra_amd64.tar.gz             # dry-run in Docker
```

No clone yet? Bootstrap everything in one line (needs only curl + tar):

```bash
curl -fsSL https://github.com/charles1614/devbox/archive/refs/heads/main.tar.gz | tar xz \
  && cd devbox-main && sudo ./scripts/restore.sh --current-user
```

Download details: pin a release with `--version <tag>`; force a fresh download with
`--force-download`. The downloaded archive is kept in the working directory, so a
re-run skips the download. If APT can't reach the network during restore, the home
directory is restored anyway (the bundle's tools are self-contained) — the missing
system packages are listed for you to install later. One of those packages is
`zsh` itself: on a host where it can't be installed, the login shell is left
unchanged (instead of pointing at a missing `/bin/zsh` and locking the account
out) — install zsh later and run `chsh -s "$(command -v zsh)" <user>`.

> The restore refuses hosts older than the build (Ubuntu < 24.04 / glibc < 2.39),
> because mise-managed binaries would fail with `GLIBC_x.yz not found`. Force past
> it at your own risk with `SKIP_OS_CHECK=1`.

<details>
<summary><b>Restore into your own login user (<code>--current-user</code>)</b></summary>

By default the environment restores to `charles`. To restore into the account
you're already logged in as (e.g. `ubuntu` on a cloud VM), add `--current-user` —
the target user/UID/GID come from `SUDO_USER`/`SUDO_UID`/`SUDO_GID`:

```bash
sudo ./scripts/restore.sh --current-user               # downloads, then restores
sudo ./scripts/restore.sh -f <archive> --current-user  # local archive
# non-interactive:  add --yes
```

- **Overwrite guard** — restoring into a pre-existing home prompts before
  overwriting dotfiles and switching the login shell to zsh. The archive's `.ssh`
  is always skipped in this case, so existing keys are never clobbered (no lockout).
- **Match the username** — source-compiled tools (notably mise's Python) bake the
  build-time home path into their binaries, so a `charles` bundle may fail under a
  different username. For a fully-clean restore, build a bundle for your user:
  ```bash
  USERNAME=ubuntu USER_ID=1001 GROUP_ID=1001 make prepare PROFILE=extra
  make package FILE=ubuntu_home_extra_amd64.tar.gz
  ```
  Prebuilt static tools (ripgrep, fd, starship, eza, neovim) work regardless.
</details>

## 🛠 Build locally

Prefer to build the image yourself instead of pulling from GHCR:

```bash
git clone git@github.com:charles1614/devbox.git && cd devbox

make setup                             # create config.env from the example
# …edit config.env with your settings…

make prepare PROFILE=extra             # build image + start a container
# NO_CACHE=1 for a clean rebuild:  make prepare PROFILE=extra NO_CACHE=1

make package FILE=charles_home_extra.tar.gz   # package the initialized home
```

## 🔧 Configuration

All settings live in `config.env` (copy it from
[`config.env.example`](config.env.example) via `make setup`).

| Variable | Description |
| --- | --- |
| `USERNAME` | Username baked into the environment. |
| `USER_ID` · `GROUP_ID` | UID/GID for that user. |
| `SETUP_SCRIPT_URL` | URL to the dotfiles setup script run during the build. |
| `APT_PACKAGES` | Space-separated APT packages installed by the restore step. |

> The Docker base image (`nvidia/cuda:13.1.0-devel-ubuntu24.04`) is fixed in
> [`docker/Dockerfile`](docker/Dockerfile) — edit it there if you need a different base.

<details>
<summary><b>Auto-rebuild the image when your dotfiles change</b></summary>

The CI listens for `repository_dispatch`, so a push to your
[dotfiles repo](https://github.com/charles1614/dotfiles) can rebuild the image
(cache busted from the chezmoi step onward). Add a `DEVBOX_PAT` secret to the
dotfiles repo and a workflow that POSTs to the devbox `dispatches` endpoint:

```yaml
name: Notify devbox
on:
  push:
    branches: [main]
jobs:
  trigger:
    runs-on: ubuntu-latest
    steps:
      - run: |
          curl -X POST \
            -H "Accept: application/vnd.github.v3+json" \
            -H "Authorization: token ${{ secrets.DEVBOX_PAT }}" \
            https://api.github.com/repos/charles1614/devbox/dispatches \
            -d '{"event_type":"dotfiles-updated","client_payload":{"timestamp":"'"$(date +%s)"'"}}'
```

```
dotfiles push → notify-devbox.yml → repository_dispatch → devbox CI rebuilds
```
</details>

## 🧰 Workflow commands

| Command | Description |
| --- | --- |
| `make setup` | Create `config.env` from the example. |
| `make prepare PROFILE=<mini\|extra>` | Build the image and start a container (`NO_CACHE=1` for a clean build). |
| `make package FILE=<out.tar.gz>` | Package the initialized environment into an offline bundle. |
| `make restore [FILE=<archive>]` | Restore onto an Ubuntu host — requires `sudo`. With `FILE`: local archive (offline). Without: download from Releases (`PROFILE=`, `VERSION=`). Flags: `CURRENT_USER=1`, `ASSUME_YES=1`, `SKIP_OS_CHECK=1`. |
| `make test FILE=<archive>` | Dry-run the restore inside an isolated Docker container. |
| `make clean` | Remove containers, images, and temp files. |
| `make workflow` | Run `setup` + `prepare` in sequence. |

## 🗂 Project structure

```
.github/workflows/   CI: multi-arch build → GHCR → package → Release
docker/Dockerfile    CUDA 13.1-devel · Ubuntu 24.04 base + dev stage
scripts/
  common.sh                 shared utils, config, OS/glibc compatibility gate
  prepare_online_env.sh     build image + start the init container
  package_offline_bundle.sh package the home dir into a .tar.gz
  restore_ubuntu_env.sh     restore on an Ubuntu host (CURRENT_USER-aware)
  restore.sh                single restore entry point: download or --file, no make needed
  run-ssh.sh                run a container with UID/GID remap + SSH
  init_plugins.sh           install zsh/neovim plugins at build time
tests/               isolated Docker restoration test
dotfiles/            chezmoi-managed dotfiles (submodule)
config.env.example   configuration template
Makefile             all workflow commands
```

## 🧱 Tech stack

**Docker** (multi-arch buildx) · **NVIDIA CUDA 13.1-devel** on **Ubuntu 24.04** ·
**mise** (tool manager) · **zsh** + **zinit** · **starship** · **Neovim** +
**lazy.nvim** · **chezmoi** dotfiles · **OpenSSH** · **GitHub Actions** → **GHCR** + Releases.
