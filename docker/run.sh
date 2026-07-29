#!/bin/bash

set +e

function show_help() {
  echo -e "
Usage:
  run.sh [OPTIONS]

Options:
  -i, --image_name        Name of the image (default: ros2_<ros_distro>_eta_interface)
  -c, --container_name    Name of the container (default: ros2_<ros_distro>_eta_interface_container)
  -d, --ros_distro        ROS 2 distro: kilted or jazzy (default: kilted)
      --use_nvidia        Enable NVIDIA runtime
  -h, --help              Show this help

Examples:
  ./run.sh
  ./run.sh --ros_distro jazzy
  ./run.sh --use_nvidia
"
}

echo "Running the container..."

# -----------------------
# Paths
# -----------------------

USER="admin"
REPOSITORY_FOLDER_PATH="$(cd "$(dirname "$0")"; cd ../..; pwd)"
WORKSPACE_SRC_HOST_PATH="$(cd "$(dirname "$0")"; cd ../../..; pwd)/src"
ROS_DISTRO=${ROS_DISTRO:-kilted}
IMAGE_NAME=${IMAGE_NAME:-ros2_${ROS_DISTRO}_eta_interface}
CONTAINER_NAME=${CONTAINER_NAME:-ros2_${ROS_DISTRO}_eta_interface_container}


WORKSPACE_ROOT_CONTAINER="/home/$USER/ros_ws"
WORKSPACE_BIND_SOURCE="$WORKSPACE_SRC_HOST_PATH"
WORKSPACE_BIND_TARGET="$WORKSPACE_ROOT_CONTAINER/mount"

## -----------------------
# Arguments
# -----------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--image_name)
            IMAGE_NAME="$2"
            shift 2
            ;;
        -c|--container_name)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        -d|--ros_distro)
            ROS_DISTRO="$2"
            shift 2
            ;;
        --use_nvidia)
            NVIDIA_FLAGS="--gpus=all -e NVIDIA_DRIVER_CAPABILITIES=all"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done


# -----------------------
# X11 setup
# -----------------------

if [ -z "$DISPLAY" ]; then
    export DISPLAY=:0
    echo "DISPLAY was empty. Setting DISPLAY=$DISPLAY"
fi

XAUTH=/tmp/.docker.xauth

if command -v xhost >/dev/null 2>&1; then
    echo "Configuring X11 access..."

    xauth nlist "$DISPLAY" 2>/dev/null | sed 's/^..../ffff/' | xauth -f "$XAUTH" nmerge - 2>/dev/null
    chmod 644 "$XAUTH"


else
    echo "Warning: xhost not found"
fi





# -----------------------
# Check container exists
# -----------------------

if sudo docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    if sudo docker inspect "$CONTAINER_NAME" --format '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}' | grep -qx "${WORKSPACE_BIND_SOURCE} -> ${WORKSPACE_BIND_TARGET}"; then
        if sudo docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            echo "Container '$CONTAINER_NAME' is already running."
        else
            echo "Starting existing container in detached mode..."
            sudo docker start "$CONTAINER_NAME" >/dev/null
        fi

        exit 0
    fi

    echo "Existing container '$CONTAINER_NAME' does not have the expected workspace bind mount."
    echo "Expected: '$WORKSPACE_BIND_SOURCE -> $WORKSPACE_BIND_TARGET'"
    echo "Remove it and rerun this script so Docker can recreate it with the current source layout."
    exit 1
fi


# -----------------------
# Docker run
# -----------------------

echo "Starting container:"
echo "  Image:     $IMAGE_NAME"
echo "  Container: $CONTAINER_NAME"
echo "  ROS:       $ROS_DISTRO"
echo "  DISPLAY:   $DISPLAY"
echo "  Workspace: $WORKSPACE_BIND_SOURCE -> $WORKSPACE_BIND_TARGET"


sudo docker run \
    --privileged \
    --net=host \
    --ipc=host \
    --pid=host \
    -d \
    $NVIDIA_FLAGS \
    \
    -e DISPLAY="$DISPLAY" \
    -e XAUTHORITY=/tmp/.docker.xauth \
    -e QT_X11_NO_MITSHM=1 \
    -e XDG_RUNTIME_DIR=/tmp/runtime-root \
    \
    -v "$XAUTH:/tmp/.docker.xauth:rw" \
    -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
    --mount type=bind,source="${WORKSPACE_BIND_SOURCE}",target="${WORKSPACE_BIND_TARGET}" \
    \
    --name "$CONTAINER_NAME" \
    "$IMAGE_NAME"