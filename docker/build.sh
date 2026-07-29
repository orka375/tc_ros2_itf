#!/bin/bash

set -e

######################
# 1) Help
######################
show_help() {
  echo $'\nUsage:\tbuild.sh [OPTIONS]\n
Options:\n
	-i, --image-name\tDocker image name (default: ros2_<ros_distro>_eta_interface)\n
	-d, --ros-distro\tROS 2 distro (default: kilted)\n
	-h, --help\t\tShow this help message\n
Example:\n
	build.sh --ros-distro kilted --image-name custom_image\n'
}

######################
# 2) Paths
######################
SCRIPT_FOLDER_PATH="$(cd "$(dirname "$0")"; pwd)"
CONTEXT_FOLDER_PATH="$(cd "$SCRIPT_FOLDER_PATH/.."; pwd)"
DOCKERFILE_PATH="$SCRIPT_FOLDER_PATH/dockerfile"


######################
# 3) Parse Arguments
######################
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -i|--image-name|--image_name)
      IMAGE_NAME="$2"
      shift
      ;;
    -d|--ros-distro|--ros_distro)
      ROS_DISTRO="$2"
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "Unknown parameter: $1"
      show_help
      exit 1
      ;;
  esac
  shift
done

######################
# 4) Defaults
######################
ROS_DISTRO="${ROS_DISTRO:-kilted}"
IMAGE_NAME="${IMAGE_NAME:-ros2_${ROS_DISTRO}_eta_interface}"
USERID="1000"
USER="admin"

######################
# 5) Build
######################
echo "Building image '${IMAGE_NAME}' for ROS 2 distro '${ROS_DISTRO}'"
sudo docker build \
  --file "$DOCKERFILE_PATH" \
  --build-arg "USERID=$USERID" \
  --build-arg "USER=$USER" \
  --build-arg "ROS_DISTRO=$ROS_DISTRO" \
  --tag "$IMAGE_NAME" \
  "$CONTEXT_FOLDER_PATH"
