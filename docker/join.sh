#!/bin/bash

CONTAINER_NAME="eta_tc_ros2_itf_container"
echo "Using Container Name: $CONTAINER_NAME"
docker exec -it "$CONTAINER_NAME" bash
