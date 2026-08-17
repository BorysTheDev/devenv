# Dragonfly builder container

## How to build container:

``` sh
docker build --build-arg UID=$(id -u) -t builder .
```

``` sh
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
docker build --platform linux/arm64 --build-arg UID=$(id -u) -t builder .
```

## Included CLI tools

The container installs:

- `@github/copilot`
- `tree-sitter`

`@openai/codex` is installed on first shell start into `~/.npm-global`, which is
bind-mounted from the host, so `codex-update` upgrades it without rebuilding the image.

Tree-sitter grammars are preinstalled for:

- C++ (`tree-sitter-cpp`)
- Python (`tree-sitter-python`)
- Go (`tree-sitter-go`)

## How to start zsh inside container:

First time:
``` sh
docker run --user builder --mount type=bind,source=${HOME}/dragonfly,destination=/home/builder/dragonfly -it --name builder-container builder /usr/bin/zsh
```

Restart:
``` sh
docker stop builder-container && docker rm builder-container && docker run --user builder --mount type=bind,source=${HOME}/dragonfly,destination=/home/builder/dragonfly --mount type=bind,source=${HOME}/.ssh,destination=/home/builder/.ssh,readonly --mount type=bind,source=${HOME}/.gitconfig,destination=/home/builder/.gitconfig,readonly -it --name builder-container builder /usr/bin/zsh
```
