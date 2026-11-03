# harness-sandbox

Run [Harness](https://github.com/alexlayton/harness) inside an
[Apple container](https://github.com/apple/container) with the current
directory mounted as its workspace. Each run is a throwaway Linux VM. The
agent can only touch the folders you mount, but it still uses your signed-in
session, skills and git identity.

## Requirements

- A Mac with Apple silicon and macOS 26 or later
- [Apple `container`](https://github.com/apple/container/releases), started
  with `container system start`
- Harness signed in on the host (`~/.config/harness/auth.json` exists)

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/alexlayton/harness-sandbox/main/install.sh | sh
```

This installs one script to `~/.local/bin/harness-sandbox`. Then pull the
base image:

```sh
harness-sandbox update
```

To install a specific version, pass it through to the script:

```sh
curl -fsSL https://raw.githubusercontent.com/alexlayton/harness-sandbox/main/install.sh | sh -s -- --version v0.1.0
```

## Usage

```sh
cd ~/Code/some-repo
harness-sandbox                      # Harness, with this directory at /workspace
harness-sandbox -- --version         # arguments after -- go to harness
harness-sandbox -m 4g -c 4           # more memory / CPUs
harness-sandbox --github             # allow GitHub access (see below)
harness-sandbox shell                # bash instead of harness
harness-sandbox shell -- -c 'ls /workspace'
harness-sandbox --dry-run            # print the container command and exit
```

| Command | What it does |
| --- | --- |
| `harness-sandbox [options] [-- args]` | Run Harness in a container |
| `harness-sandbox shell [options] [-- cmd]` | Run bash (or `cmd`) instead |
| `harness-sandbox update` | Pull the latest base image |
| `harness-sandbox build` | Build the image locally (git checkout only) |
| `harness-sandbox ls` | List containers |
| `harness-sandbox clean` | Remove stopped `hs-*` containers |

| Option | |
| --- | --- |
| `-d, --dir DIR` | Project directory to mount (default: current directory) |
| `-m, --memory SIZE` / `-c, --cpus N` | VM resources |
| `-e, --env KEY[=VAL]` | Pass an environment variable (`KEY` alone forwards the host value) |
| `-v, --volume SPEC` | Extra mount, `host:container[:ro]` |
| `-g, --github` | GitHub access (see below) |
| `--image IMAGE` | Use a different image |
| `--dry-run` | Print the command instead of running it |

Options go before `--`, and subcommands such as `shell` come first.

## What gets mounted

| Host | Container | Mode |
| --- | --- | --- |
| Current directory | `/workspace` | read-write |
| `~/.config/harness` (symlinks resolved; or `$HARNESS_CONFIG_DIR`) | `/harness-config` | read-write |
| `config.toml` override (below) | `/harness-config/config.toml` | read-only |
| `~/.agents/skills`, `~/.harness/skills` | same paths under `/root` | read-only |
| `$HARNESS_SKILLS_DIR` | `/harness-skills` | read-only |
| `~/.gitconfig` (symlink resolved) | `/root/.gitconfig` | read-only |

The Harness config directory is mounted as a **directory** and read-write on
purpose: Harness refreshes your login by writing a temp file and renaming it
over `auth.json`, which fails on a single-file mount. Files written to
`/workspace` are owned by your user on the Mac.

### Sandbox-specific config

Your host `config.toml` may contain things that don't work in a container,
such as MCP servers that run `bunx` or drive Safari. The first of these that
exists replaces `config.toml` inside the sandbox:

1. `<project>/.harness-sandbox/config.toml`
2. `~/.config/harness-sandbox/config.toml` (or `$HARNESS_SANDBOX_CONFIG`)
3. otherwise your host `config.toml` is used unchanged

### GitHub access

`--github` gives the sandbox the `gh` CLI and lets git push over HTTPS. The
token is `$HARNESS_SANDBOX_GH_TOKEN` if set, otherwise `gh auth token` on the
host. It reaches the container as `GH_TOKEN` through the environment only
(never on a command line), and `git@github.com:` remotes are rewritten to
HTTPS so SSH keys aren't needed.

> `gh auth token` is your full login token, with every scope you granted `gh`.
> For anything sensitive, create a fine-grained personal access token limited
> to the repositories you want, and export it as `HARNESS_SANDBOX_GH_TOKEN`.

Without `--github` the container has no GitHub credentials. Commits still work
because your git identity is mounted.

### Per-project images

Different projects need different tools. Add `.harness-sandbox/Dockerfile` to a
project and it is built on top of the base image automatically:

```dockerfile
FROM ghcr.io/alexlayton/harness-sandbox
RUN apt-get update && apt-get install -y --no-install-recommends nodejs npm \
 && rm -rf /var/lib/apt/lists/*
```

## The base image

`ghcr.io/alexlayton/harness-sandbox` is Debian (bookworm-slim) with `git`,
`git-lfs`, `gh`, `ripgrep`, `curl`, `ssh` and the Harness release binary,
checksum verified. It is built for `linux/arm64`. Tags: `latest`,
`harness-X.Y.Z` (pin to a Harness version), plus a version tag for each release
of this repo.

## Security notes

- The container is a separate VM, but `/workspace` and `/harness-config` are
  **writable**, and the container has **full outbound network access**.
- The agent can read your Harness login (`auth.json`) and, with `--github`, a
  GitHub token. Only mount projects you are comfortable giving it.
- Safari and other host-only MCP servers are not available in the sandbox by
  default.

## Development

```sh
git clone https://github.com/alexlayton/harness-sandbox
cd harness-sandbox
./harness-sandbox build                         # builds harness-sandbox:local
HARNESS_SANDBOX_IMAGE=harness-sandbox:local ./harness-sandbox
```

The `Dockerfile` default only matters for local builds; CI always passes the
latest release. To use another Harness release, build with
`container build --build-arg HARNESS_VERSION=vX.Y.Z -t harness-sandbox:local .`.

`.github/workflows/image.yml` builds the Dockerfile on a native arm64 runner
and pushes it to GHCR on pushes to `main` and on `v*` tags. A daily schedule
checks for a new Harness release and rebuilds with it (skipping if that
`harness-X.Y.Z` tag already exists), and every Monday it rebuilds regardless to
pick up Debian updates. Pull requests build without pushing. After the first publish, set the package to
**public** in the GitHub package settings so that `harness-sandbox update` can
pull it without logging in.
