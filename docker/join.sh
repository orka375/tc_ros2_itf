#!/bin/bash

ROS_DISTRO=${ROS_DISTRO:-kilted}
CONTAINER_NAME=${CONTAINER_NAME:-ros2_${ROS_DISTRO}_eta_interface_container}

echo "Using Container Name: $CONTAINER_NAME"
docker exec -it "$CONTAINER_NAME" bash
