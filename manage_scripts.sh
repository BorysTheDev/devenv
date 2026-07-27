run() {
  # Check if the image name is provided
  if [ -z "$1" ]; then
    echo "❌ Error: You must specify the image name!"
    echo "👉 Usage example: run my_project [container_name] [additional_docker_params]"
    return 1
  fi

  local image_name="$1"
  local container_name="${2:-${image_name}}-container"
  local project_dir="${HOME}/projects/${image_name}"
  shift

  if [ $# -gt 0 ]; then
    shift  # Shift the second parameter (container_name)
  fi

  # Stop and remove the container if it already exists
  if [ "$(docker ps -a -q -f name=${container_name})" ]; then
    docker start -ai "${container_name}"
    return 0
  fi

  # Ensure persistent state directories exist on host so Docker doesn't create
  # them as root-owned bind mount targets.
  mkdir -p "${HOME}/remote/.vscode-server" \
           "${HOME}/remote/.cursor-server" \
           "${HOME}/remote/.cache" \
           "${HOME}/remote/.config/gh" \
           "${HOME}/remote/.local/share" \
           "${HOME}/remote/.claude" \
           "${HOME}/remote/.copilot" \
           "${HOME}/remote/.codex"

  # Run the Docker container with the specified configurations
  docker run --user builder "$@" \
    --mount type=bind,source="${project_dir}",destination="/home/builder/${image_name}" \
    --mount type=bind,source="${HOME}/remote/.vscode-server",destination="/home/builder/.vscode-server" \
    --mount type=bind,source="${HOME}/remote/.cursor-server",destination="/home/builder/.cursor-server" \
    --mount type=bind,source="${HOME}/remote/.cache",destination="/home/builder/.cache" \
    --mount type=bind,source="${HOME}/remote/.config",destination="/home/builder/.config" \
    --mount type=bind,source="${HOME}/remote/.local/share",destination="/home/builder/.local/share" \
    --mount type=bind,source="${HOME}/remote/.claude",destination="/home/builder/.claude" \
    --mount type=bind,source="${HOME}/remote/.copilot",destination="/home/builder/.copilot" \
    --mount type=bind,source="${HOME}/remote/.codex",destination="/home/builder/.codex" \
    --mount type=bind,source="${HOME}/.ssh",destination="/home/builder/.ssh",readonly \
    --mount type=bind,source="${HOME}/.gitconfig",destination="/home/builder/.gitconfig",readonly \
    --mount type=bind,source="${HOME}/.gitignore_global",destination="/home/builder/.gitignore_global",readonly \
    -v /var/run/docker.sock:/var/run/docker.sock \
    --privileged \
    -it --name "${container_name}" "${image_name}" /usr/bin/zsh
}
restart() {
  # Check if the image name is provided
  if [ -z "$1" ]; then
    echo "❌ Error: You must specify the image name!"
    echo "👉 Usage example: restart my_project [container_name] [additional_docker_params]"
    return 1
  fi

  local image_name="$1"
  local container_name="${2:-${image_name}}-container"

  # Remove the container if it already exists
  if [ "$(docker ps -a -q -f name=${container_name})" ]; then
    docker rm -f "${container_name}"
  fi

  # Delegate actual start to run with the same arguments
  run "$@"
}
attach() {
  # Check if the image name is provided
  if [ -z "$1" ]; then
    echo "❌ Error: You must specify the image name!"
    echo "👉 Usage example: attach my_project"
    return 1
  fi

  local image_name="$1"
  local container_name="${image_name}-container"

  docker exec -it "${container_name}" /usr/bin/zsh
}


build() {
  # Check if the image tag is provided
  if [ -z "$1" ]; then
    echo "❌ Error: You must specify the image tag!"
    echo "👉 Usage example: build my_project"
    return 1
  fi

  local tag="$1"

  # Build the Docker image with the provided tag and user ID
  docker build --no-cache --build-arg UID=$(id -u) --build-arg GID=$(id -g) -t "$tag" .
}

update() {
  docker build --build-arg UID=$(id -u) --build-arg GID=$(id -g) \
    --build-arg CACHE_BUST="$(date +%s)" -t "$1" .
}
