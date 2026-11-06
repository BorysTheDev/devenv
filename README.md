# Dragonfly builder container

## Usage

`<name>` is the image tag and the project in `~/projects/<name>`, which is
mounted at `~/<name>` in the container `<name>-container`.

``` sh
./build.sh <name>    # build the image from scratch
./update.sh <name>   # cached rebuild that refreshes copilot, codex and tree-sitter
./run.sh <name>      # start the container, or re-attach if it already exists
./restart.sh <name>  # recreate the container, e.g. after build/update
./attach.sh <name>   # open another shell in the running container
```

Optional arm64 image, e.g. for testing on ARM. Not needed on x86: `build.sh`
and `update.sh` build for the host's own architecture. On an x86 host, the
first command registers QEMU to run arm64 binaries (much slower), and the
build replaces the `<name>` image:

``` sh
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
docker build --platform linux/arm64 --build-arg UID=$(id -u) --build-arg GID=$(id -g) \
  --build-arg DOCKER_GID=$(stat -c %g /var/run/docker.sock) -t <name> .
```

## Included CLI tools

The container installs:

- `@github/copilot`
- `@openai/codex`
- `tree-sitter`

Dragonfly's formatting tools come from pipx: `pre-commit`, plus `clang-format`,
`black` and `pyflakes` at the versions Dragonfly's `.pre-commit-config.yaml`
pins, so manual runs match CI.

Go, Rust and Python come from the Ubuntu repository (`golang-go`, `rustc`,
`cargo`, `python3`) rather than upstream installers or PPAs, so the build does
not depend on `go.dev`, `static.rust-lang.org` or Launchpad being reachable.
`~/.venv` (on `PATH` ahead of the system Python) has Dragonfly's test
requirements preinstalled. Their versions come only from Dragonfly's
`tests/dragonfly/requirements.txt`; to re-sync with a local checkout run
`pip install -r ~/dragonfly/tests/dragonfly/requirements.txt`.

Tree-sitter grammars are preinstalled for:

- C++ (`tree-sitter-cpp`)
- Python (`tree-sitter-python`)
- Go (`tree-sitter-go`)

## Investigation tooling and runtime defaults

- Performance/network tools from Ubuntu: bubblewrap, dig, ping, ip/ss,
  tcpdump, tshark, mtr, traceroute, nc, sysstat (iostat/pidstat/mpstat/sar),
  strace, lsof, ethtool, iperf3, GNU `time`. Capturing needs `sudo`.
- The host's AppArmor userns restriction only lets `/usr/bin/bwrap` set up
  namespaces; Codex's bundled bwrap failed with
  `loopback: Failed RTM_NEWADDR`, so its sandbox needs the bubblewrap package.
- `copilot` and `codex` run with full access by default. Codex gets it from
  `/etc/codex/config.toml`. For Copilot, `run.sh` seeds
  `~/.copilot/settings.json` with `"defaultPermissionMode": "allow-all"` and
  `"defaultMode": "autopilot"`, so new interactive sessions start in autopilot
  with allow-all, and `config.json` with `"trustedFolders": ["/"]`, so there is
  no folder-trust prompt. `copilot -p` ignores the permission setting and needs
  `--allow-all`.
- `run.sh` writes those Copilot files only when they are missing. If a
  container's `~/.copilot` predates them, run
  `copilot config defaultMode autopilot` there and answer the trust prompt with
  "Yes, and remember this folder". `COPILOT_ALLOW_ALL` is left unset on
  purpose: `true` overrides allow-all and auto-approves only tools.
- Both are told that `/tmp` is RAM-backed, so they keep scratch work there:
  `/etc/copilot/instructions/tmpfs.instructions.md` (via
  `COPILOT_CUSTOM_INSTRUCTIONS_DIRS`) and `developer_instructions` in
  `/etc/codex/config.toml`.
- `run.sh` pins the container to n-1 physical cores (one thread per core,
  core 0 left to the host), mounts `/tmp` and `/dev/shm` as tmpfs capped at 1/4
  of host RAM each (`/tmp` is emptied on every start) and adds the docker
  socket's group so `docker` works without `sudo`.
- `build.sh`/`update.sh` give the image's `docker` group the host socket's GID,
  so that group has a name inside the container (`groups` errors on unnamed
  ones); rebuild if the host's docker GID changes.
- `~/.copilot`, `~/.codex` and `~/.claude` come from
  `~/remote/containers/<container>/`: separate per container, kept across reruns.
- `~/.npm-global` (npm's global prefix, from `~/remote/.npm-global`, shared by
  all containers) is first on `PATH`: a CLI installed there with
  `npm install -g` shadows the image's copy, which `update.sh` refreshes.
  `npm uninstall -g <package>` switches back to the image's copy.
