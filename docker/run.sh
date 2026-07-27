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
REPOSITORY_FOLDER_PATH="$(cd "$(dirname "$0")"; cd ../../..; pwd)"
ROS_DISTRO=${ROS_DISTRO:-kilted}
IMAGE_NAME=${IMAGE_NAME:-ros2_${ROS_DISTRO}_eta_interface}
CONTAINER_NAME=${CONTAINER_NAME:-ros2_${ROS_DISTRO}_eta_interface_container}


WORKSPACE_ROOT_CONTAINER="/home/$USER/ros_ws"

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
# Build cache folders
# -----------------------

mkdir -p "${REPOSITORY_FOLDER_PATH}/build"
mkdir -p "${REPOSITORY_FOLDER_PATH}/install"

sudo chown -R "$(whoami)" "${REPOSITORY_FOLDER_PATH}/build"
sudo chown -R "$(whoami)" "${REPOSITORY_FOLDER_PATH}/install"


# -----------------------
# Check container exists
# -----------------------

if sudo docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Starting existing container..."
    sudo docker start -ai "$CONTAINER_NAME"

    if command -v xhost >/dev/null 2>&1; then
        xhost -SI:localuser:$USER
    fi

    exit 0
fi


# -----------------------
# Docker run
# -----------------------

echo "Starting container:"
echo "  Image:     $IMAGE_NAME"
echo "  Container: $CONTAINER_NAME"
echo "  ROS:       $ROS_DISTRO"
echo "  DISPLAY:   $DISPLAY"


sudo docker run \
    --privileged \
    --net=host \
    --ipc=host \
    --pid=host \
    -it \
    $NVIDIA_FLAGS \
    \
    -e DISPLAY="$DISPLAY" \
    -e XAUTHORITY=/tmp/.docker.xauth \
    -e QT_X11_NO_MITSHM=1 \
    -e XDG_RUNTIME_DIR=/tmp/runtime-root \
    \
    -v "$XAUTH:/tmp/.docker.xauth:rw" \
    -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
    \
    -v "${REPOSITORY_FOLDER_PATH}:${WORKSPACE_ROOT_CONTAINER}" \
    -v "${REPOSITORY_FOLDER_PATH}/build:${WORKSPACE_ROOT_CONTAINER}/build:rw" \
    -v "${REPOSITORY_FOLDER_PATH}/install:${WORKSPACE_ROOT_CONTAINER}/install:rw" \
    \
    --name "$CONTAINER_NAME" \
    "$IMAGE_NAME"


# -----------------------
# Cleanup
# -----------------------

function onexit() {

    echo ""

    read -p "Save container changes into image '$IMAGE_NAME'? [y/n]: " answer

    if [[ "${answer:0:1}" =~ y|Y ]]; then
        echo "Saving image..."
        sudo docker commit "$CONTAINER_NAME" "$IMAGE_NAME"
    fi

    sudo docker stop "$CONTAINER_NAME" >/dev/null 2>&1

 
}

trap onexit EXIT