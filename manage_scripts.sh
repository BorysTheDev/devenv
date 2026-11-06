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

  # Re-attach if the container already exists
  if [ "$(docker ps -a -q -f name=${container_name})" ]; then
    docker start -ai "${container_name}"
    return 0
  fi

  # Ensure persistent state directories exist on host so Docker doesn't create
  # them as root-owned bind mount targets. AI settings are kept per container:
  # not shared with other containers, but preserved across reruns.
  local ai_dir="${HOME}/remote/containers/${container_name}"
  mkdir -p "${HOME}/remote/.vscode-server" \
           "${HOME}/remote/.cursor-server" \
           "${HOME}/remote/.cache" \
           "${HOME}/remote/.config/gh" \
           "${HOME}/remote/.local/share" \
           "${HOME}/remote/.npm-global" \
           "${ai_dir}/.claude" \
           "${ai_dir}/.copilot" \
           "${ai_dir}/.codex"

  # New interactive Copilot sessions start in autopilot with full access (like
  # --autopilot --allow-all) and trust every folder, so there is no trust prompt.
  # config.json will also hold Copilot's login, hence umask 077. Existing files
  # are left alone.
  [ -e "${ai_dir}/.copilot/settings.json" ] ||
    echo '{ "defaultPermissionMode": "allow-all", "defaultMode": "autopilot" }' > "${ai_dir}/.copilot/settings.json"
  [ -e "${ai_dir}/.copilot/config.json" ] ||
    (umask 077 && echo '{ "trustedFolders": ["/"] }' > "${ai_dir}/.copilot/config.json")

  # Single-file mounts need the same treatment: a missing source makes Docker
  # create a root-owned *directory* at that path, which then breaks git.
  [ -e "${HOME}/.gitignore_global" ] || touch "${HOME}/.gitignore_global"

  # n-1 physical cores: the first hardware thread of every core except core 0.
  local cpus
  cpus=$(lscpu -p=CPU,CORE | awk -F, '!/^#/ && !seen[$2]++ {print $1}' | tail -n +2 | paste -sd,)

  # /tmp and /dev/shm are tmpfs (RAM), each capped at 1/4 of host memory. They use
  # RAM only for what is stored, and /tmp starts empty on every container start.
  local tmpfs_size
  tmpfs_size=$(awk '/^MemTotal:/ {print int($2 / 4) "k"}' /proc/meminfo)

  # --group-add: the host docker socket's group, so builder needs no sudo. build
  # and update give the image's docker group this GID, so it also has a name.
  docker run --user builder --cpuset-cpus "${cpus}" \
    --tmpfs "/tmp:exec,size=${tmpfs_size}" --shm-size "${tmpfs_size}" \
    --group-add "$(stat -c %g /var/run/docker.sock)" \
    "$@" \
    --mount type=bind,source="${project_dir}",destination="/home/builder/${image_name}" \
    --mount type=bind,source="${HOME}/remote/.vscode-server",destination="/home/builder/.vscode-server" \
    --mount type=bind,source="${HOME}/remote/.cursor-server",destination="/home/builder/.cursor-server" \
    --mount type=bind,source="${HOME}/remote/.cache",destination="/home/builder/.cache" \
    --mount type=bind,source="${HOME}/remote/.config",destination="/home/builder/.config" \
    --mount type=bind,source="${HOME}/remote/.local/share",destination="/home/builder/.local/share" \
    --mount type=bind,source="${ai_dir}/.claude",destination="/home/builder/.claude" \
    --mount type=bind,source="${ai_dir}/.copilot",destination="/home/builder/.copilot" \
    --mount type=bind,source="${ai_dir}/.codex",destination="/home/builder/.codex" \
    --mount type=bind,source="${HOME}/remote/.npm-global",destination="/home/builder/.npm-global" \
    --mount type=bind,source="${HOME}/.ssh",destination="/home/builder/.ssh",readonly \
    --mount type=bind,source="${HOME}/.gitconfig",destination="/home/builder/.gitconfig",readonly \
    --mount type=bind,source="${HOME}/.gitignore_global",destination="/home/builder/.gitignore_global",readonly \
    -v /var/run/docker.sock:/var/run/docker.sock \
    --privileged \
    -it --name "${container_name}" "${image_name}"
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

  docker exec -it "${container_name}" /bin/bash
}


build() {
  # Check if the image tag is provided
  if [ -z "$1" ]; then
    echo "❌ Error: You must specify the image tag!"
    echo "👉 Usage example: build my_project"
    return 1
  fi

  local tag="$1"

  # Build the Docker image with the provided tag, user ID and docker socket GID
  docker build --no-cache --build-arg UID=$(id -u) --build-arg GID=$(id -g) \
    --build-arg DOCKER_GID="$(stat -c %g /var/run/docker.sock)" -t "$tag" .
}

update() {
  docker build --build-arg UID=$(id -u) --build-arg GID=$(id -g) \
    --build-arg DOCKER_GID="$(stat -c %g /var/run/docker.sock)" \
    --build-arg CACHE_BUST="$(date +%s)" -t "$1" .
}
