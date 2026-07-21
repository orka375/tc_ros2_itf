#!/bin/bash

set -e

IMAGE_NAME=${1:-orka375/eta_tc_ros2_itf}
CONTAINER_NAME=${2:-eta_tc_ros2_itf_container}

echo "Starting Docker container..."
echo "Image: $IMAGE_NAME"
echo "Container: $CONTAINER_NAME"

# Repository root (folder above docker/)
REPOSITORY_FOLDER_PATH="$(cd "$(dirname "$0")/.." && pwd)"

USER_NAME=$(whoami)

WORKSPACE=/home/$USER_NAME/ros_ws

# Create persistent build cache
mkdir -p "$REPOSITORY_FOLDER_PATH/.build"
mkdir -p "$REPOSITORY_FOLDER_PATH/.install"

# Remove old container if it exists
if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    echo "Removing old container..."
    docker rm -f "$CONTAINER_NAME"
fi


# GUI support
GUI_ARGS=""

if [ -n "$DISPLAY" ]; then
    echo "Using X11 display"

    xhost +local:root >/dev/null 2>&1 || true

    GUI_ARGS="
        -e DISPLAY=$DISPLAY
        -e QT_X11_NO_MITSHM=1
        -v /tmp/.X11-unix:/tmp/.X11-unix
    "
fi


docker run \
    -it \
    --privileged \
    --net=host \
    --ipc=host \
    --pid=host \
    $GUI_ARGS \
    -v "$REPOSITORY_FOLDER_PATH:$WORKSPACE/src" \
    -v "$REPOSITORY_FOLDER_PATH/.build:$WORKSPACE/build" \
    -v "$REPOSITORY_FOLDER_PATH/.install:$WORKSPACE/install" \
    --name "$CONTAINER_NAME" \
    "$IMAGE_NAME"


echo "Container exited."

# Cleanup
docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true

if [ -n "$DISPLAY" ]; then
    xhost -local:root >/dev/null 2>&1 || true
fi