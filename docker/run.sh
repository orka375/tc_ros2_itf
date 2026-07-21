#!/bin/bash



set +e

# Prints information about usage.
function show_help() {
  echo $'\nUsage:\t run.sh [OPTIONS] \n
  Options:\n
  \t-i --image_name\t\t Name of the image to be run (default eta_tc_ros2_itf).\n
  \t-c --container_name\t Name of the container(default eta_tc_ros2_itf_container).\n
  \t--use_nvidia\t\t Use nvidia runtime.\n
  Examples:\n
  \trun.sh\n
  \trun.sh --image_name custom_image_name --container_name custom_container_name \n'
}

# Returns true when the path is relative, false otherwise.
#
# Arguments
#   $1 -> Path
function is_relative_path() {
  case $1 in
    /*) return 1 ;; # false
    *) return 0 ;;  # true
  esac
}

echo "Running the container..."

# Location of the repository
REPOSITORY_FOLDER_PATH="$(cd "$(dirname "$0")"; cd ..; pwd)"
REPOSITORY_FOLDER_NAME="$(basename "$REPOSITORY_FOLDER_PATH")"

DSIM_REPOS_PARENT_FOLDER_PATH="$(cd "$(dirname "$0")"; cd ..; pwd)"
# Location from where the script was executed.
RUN_LOCATION="$(pwd)"

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -i|--image_name) IMAGE_NAME="${2}"; shift ;;
        -c|--container_name) CONTAINER_NAME="${2}"; shift ;;
        -h|--help) show_help ; exit 1 ;;
        --use_nvidia) NVIDIA_FLAGS="--gpus=all -e NVIDIA_DRIVER_CAPABILITIES=all -e NVIDIA_VISIBLE_DEVICES=all -e __NV_PRIME_RENDER_OFFLOAD=1 -e __GLX_VENDOR_LIBRARY_NAME=nvidia" ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Update the arguments to default values if needed.

IMAGE_NAME=${IMAGE_NAME:-orka375/eta_tc_ros2_itf}
CONTAINER_NAME=${CONTAINER_NAME:-eta_tc_ros2_itf_container}

SSH_PATH="/home/$USER/.ssh"
WORKSPACE_SRC_CONTAINER=/home/$(whoami)/ws/src/$REPOSITORY_FOLDER_NAME
WORKSPACE_ROOT_CONTAINER=/home/$(whoami)/ws
SSH_AUTH_SOCK_USER=$SSH_AUTH_SOCK
CONTAINER_STARTED=0

# Create cache folders to store colcon build files
mkdir -p "${REPOSITORY_FOLDER_PATH}/.build"
mkdir -p "${REPOSITORY_FOLDER_PATH}/.install"

# Transfer the ownership to the user
chown -R "$USER" "${REPOSITORY_FOLDER_PATH}/.build"
chown -R "$USER" "${REPOSITORY_FOLDER_PATH}/.install"

# Check if name container is already taken.
if sudo -g docker docker container ls -a | grep "${CONTAINER_NAME}$" -c &> /dev/null; then
   printf "Error: Docker container called $CONTAINER_NAME is already opened.     \
   \n\nTry removing the old container by doing: \n\t docker rm $CONTAINER_NAME   \
   \nor just initialize it with a different name.\n"
   exit 1
fi

USE_X11=0
USE_WSLG=0

if [[ -n "$DISPLAY" ]]; then
  USE_X11=1
fi

if [[ -n "$WAYLAND_DISPLAY" && -d /mnt/wslg ]]; then
  USE_WSLG=1
fi

if [[ "$USE_X11" -eq 1 && "$USE_WSLG" -ne 1 ]] && command -v xhost >/dev/null 2>&1; then
  xhost +local:root >/dev/null 2>&1 || true
fi

DOCKER_RUN_ARGS=(run --privileged --net=host --ipc=host --pid=host -it)

if [[ -n "$NVIDIA_FLAGS" ]]; then
  # NVIDIA flags are provided as a space-separated option string.
  read -r -a NVIDIA_ARGS <<< "$NVIDIA_FLAGS"
  DOCKER_RUN_ARGS+=("${NVIDIA_ARGS[@]}")
fi

if [[ "$USE_X11" -eq 1 ]]; then
  DOCKER_RUN_ARGS+=(-e "DISPLAY=$DISPLAY" -e QT_X11_NO_MITSHM=1 -v /tmp/.X11-unix:/tmp/.X11-unix)
fi

if [[ "$USE_WSLG" -eq 1 ]]; then
  DOCKER_RUN_ARGS+=(-e "WAYLAND_DISPLAY=$WAYLAND_DISPLAY" -v /mnt/wslg:/mnt/wslg)
  if [[ -n "$XDG_RUNTIME_DIR" ]]; then
    DOCKER_RUN_ARGS+=(-e "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR")
  fi
  if [[ -n "$PULSE_SERVER" ]]; then
    DOCKER_RUN_ARGS+=(-e "PULSE_SERVER=$PULSE_SERVER")
  fi
fi

if [[ "$USE_X11" -ne 1 && "$USE_WSLG" -ne 1 ]]; then
  echo "Warning: No GUI display variables detected. rviz2/rqt will not work."
  echo "Hint: start this script from a WSL distro with WSLg (Ubuntu), not from docker-desktop."
fi

if [[ -n "$SSH_AUTH_SOCK_USER" && "$SSH_AUTH_SOCK_USER" == /* ]]; then
  SSH_AUTH_SOCK_DIR="$(dirname "$SSH_AUTH_SOCK_USER")"
  DOCKER_RUN_ARGS+=(-e "SSH_AUTH_SOCK=$SSH_AUTH_SOCK_USER" -v "$SSH_AUTH_SOCK_DIR:$SSH_AUTH_SOCK_DIR")
else
  echo "Warning: SSH_AUTH_SOCK is not set to an absolute path. Skipping SSH agent forwarding."
fi

DOCKER_RUN_ARGS+=(
  -v "${REPOSITORY_FOLDER_PATH}:$WORKSPACE_SRC_CONTAINER"
  -v "${REPOSITORY_FOLDER_PATH}/.build:$WORKSPACE_ROOT_CONTAINER/build:rw"
  -v "${REPOSITORY_FOLDER_PATH}/.install:$WORKSPACE_ROOT_CONTAINER/install:rw"
  -v "$SSH_PATH:$SSH_PATH"
  --name "$CONTAINER_NAME"
  "$IMAGE_NAME"
)

sudo docker "${DOCKER_RUN_ARGS[@]}"
RUN_EXIT=$?

if [[ "$USE_X11" -eq 1 && "$USE_WSLG" -ne 1 ]] && command -v xhost >/dev/null 2>&1; then
  xhost -local:root >/dev/null 2>&1 || true
fi

if [[ "$RUN_EXIT" -ne 0 ]]; then
  echo "Container start failed with exit code $RUN_EXIT."
  exit "$RUN_EXIT"
fi

CONTAINER_STARTED=1

# Returns true when the container exists, false otherwise.
function container_exists() {
  sudo docker container inspect "$1" >/dev/null 2>&1
}

# Trap workspace exits and give the user the choice to save changes.
function onexit() {
  if [[ "$CONTAINER_STARTED" -ne 1 ]] || ! container_exists "$CONTAINER_NAME"; then
    return
  fi

  while true; do
    read -p "Do you want to overwrite the image called '$IMAGE_NAME' with the current changes? [y/n]: " answer
    if [[ "${answer:0:1}" =~ y|Y ]]; then
      echo "Overwriting docker image..."
      sudo docker commit "$CONTAINER_NAME" "$IMAGE_NAME"
      break
    elif [[ "${answer:0:1}" =~ n|N ]]; then
      break
    fi
  done
  sudo docker stop "$CONTAINER_NAME" > /dev/null || true

}

trap onexit EXIT
