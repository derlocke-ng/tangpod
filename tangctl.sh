#!/bin/bash

# Configuration
IMAGE_NAME="tang-server"
CONTAINER_NAME="tangpod"
HOST_PORT=7500 # Or any other port you prefer on the host
CONTAINER_PORT=80 # Tang server default internal port
# IMPORTANT: Create this directory on your host system first!
# mkdir -p ./tang_keys
# For SELinux systems, you might need to label the host directory:
# sudo chcon -Rt container_file_t ./tang_keys
# Or, if running rootless Podman, ensure the user running podman has access
# and consider the :Z or :z mount options if SELinux is enforcing.
HOST_KEY_DIR="$(pwd)/tang_keys" # Store keys in a subdirectory of the current location

# Ensure the host key directory exists, create if not
if [ ! -d "${HOST_KEY_DIR}" ]; then
    echo "Host key directory '${HOST_KEY_DIR}' does not exist. Creating it..."
    mkdir -p "${HOST_KEY_DIR}"
    if [ $? -ne 0 ]; then
        echo "Failed to create host key directory '${HOST_KEY_DIR}'. Please check permissions."
        exit 1
    fi
    echo "Host key directory created."
    # Advise on SELinux context if the directory was just created.
    # This is a common gotcha.
    if sestatus &>/dev/null && getenforce &>/dev/null && [ "$(getenforce)" == "Enforcing" ]; then
        echo "INFO: SELinux is in enforcing mode. If you encounter permission issues,"
        echo "you might need to set the correct SELinux context for the new directory:"
        echo "sudo chcon -Rt container_file_t ${HOST_KEY_DIR}"
    fi
fi

build_image() {
    echo "Building Tang server image '${IMAGE_NAME}'..."
    # Assuming Containerfile is in the same directory as this script
    podman build -t "${IMAGE_NAME}" .
    if [ $? -ne 0 ]; then
        echo "Error building image. Exiting."
        exit 1
    fi
}

start_container() {
    echo "Starting Tang container '${CONTAINER_NAME}'..."
    # Check if container already exists
    if podman container exists "${CONTAINER_NAME}"; then
        echo "Container '${CONTAINER_NAME}' already exists."
        echo "Attempting to start it..."
        if podman start "${CONTAINER_NAME}"; then
            echo "Start command for existing container '${CONTAINER_NAME}' issued."
            # Brief pause to allow container to fully start or fail
            sleep 3
            if podman container inspect "${CONTAINER_NAME}" &>/dev/null && \
               [ "$(podman container inspect -f '{{.State.Running}}' "${CONTAINER_NAME}")" == "true" ]; then
                echo "Container '${CONTAINER_NAME}' is now running."
                echo "Accessible on host port: ${HOST_PORT}"
                echo "Keys are stored in: ${HOST_KEY_DIR}"
            else
                echo "Error: Container '${CONTAINER_NAME}' was started but is not currently running. It may have exited."
                echo "Showing last 10 lines of logs for '${CONTAINER_NAME}':"
                podman logs --tail 10 "${CONTAINER_NAME}"
                echo "For full logs, use: ./tangctl.sh logs"
                echo "For detailed status, use: ./tangctl.sh status"
            fi
        else
            echo "Failed to execute start command for existing container '${CONTAINER_NAME}'. Try stopping and removing it first (./tangctl.sh stop && ./tangctl.sh rm)."
        fi
        return
    fi

    echo "Creating and starting new container '${CONTAINER_NAME}'..."
    # Podman specific considerations:
    # 1. SELinux: Use `:Z` or `:z` for volume mounts if SELinux is enforcing.
    #    `:Z` (uppercase) labels the content on the host as private and unshared.
    #    `:z` (lowercase) labels the content on the host as shared among containers.
    #    For tang keys, `:Z` is generally safer.
    # 2. Rootless: If running Podman rootless, the user running podman needs r/w access to HOST_KEY_DIR.
    #    The container's 'tang' user (UID/GID might differ from host) also needs to be able to write to it.
    #    The entrypoint.sh script attempts to chown/chmod, but this can be tricky with rootless.
    #    One common approach for rootless is to `podman unshare chown <uid>:<gid> ${HOST_KEY_DIR}` on the host,
    #    where <uid>:<gid> are the UID/GID of the 'tang' user *inside the container*.
    #    However, the entrypoint script tries to handle this internally.

    # For Docker, you might remove `--security-opt label=disable` if not needed,
    # and the volume mount syntax is similar (e.g., -v "${HOST_KEY_DIR}:/var/db/tang")
    podman run -d \
        --name "${CONTAINER_NAME}" \
        -p "${HOST_PORT}:${CONTAINER_PORT}" \
        -v "${HOST_KEY_DIR}:/var/db/tang:Z" \
        --security-opt label=disable `# May be needed for SELinux if :Z is not enough or not desired` \
        --user root `# Run entrypoint as root to handle initial permissions, then it drops to 'tang'` \
        "${IMAGE_NAME}"

    if [ $? -eq 0 ]; then
        echo "Tang container '${CONTAINER_NAME}' initiated startup."
        # Brief pause to allow container to fully start or fail
        sleep 3
        if podman container inspect "${CONTAINER_NAME}" &>/dev/null && \
           [ "$(podman container inspect -f '{{.State.Running}}' "${CONTAINER_NAME}")" == "true" ]; then
            echo "Container '${CONTAINER_NAME}' is running."
            echo "Accessible on host port: ${HOST_PORT}"
            echo "Keys are stored in: ${HOST_KEY_DIR}"
        else
            echo "Error: Container '${CONTAINER_NAME}' started but is not running. It may have exited due to an error."
            echo "Showing last 10 lines of logs for '${CONTAINER_NAME}':"
            podman logs --tail 10 "${CONTAINER_NAME}"
            echo "For full logs, use: ./tangctl.sh logs"
            echo "For detailed status, use: ./tangctl.sh status"
        fi
    else
        echo "Error creating/starting Tang container. Check Podman's ability to run the image."
        # It's unlikely to have logs if podman run itself failed, but check anyway
        if podman container exists "${CONTAINER_NAME}"; then
            podman logs --tail 10 "${CONTAINER_NAME}"
        fi
    fi
}

stop_container() {
    echo "Stopping Tang container '${CONTAINER_NAME}'..."
    podman stop "${CONTAINER_NAME}"
    if [ $? -eq 0 ]; then
        echo "Container '${CONTAINER_NAME}' stopped."
    else
        echo "Could not stop container '${CONTAINER_NAME}'. It might not be running or may not exist."
    fi
}

remove_container() {
    echo "Removing Tang container '${CONTAINER_NAME}'..."
    # Ensure it's stopped first
    if podman container inspect "${CONTAINER_NAME}" &>/dev/null && [ "$(podman container inspect -f '{{.State.Status}}' "${CONTAINER_NAME}")" == "running" ]; then
      echo "Container is running. Stopping it first..."
      podman stop "${CONTAINER_NAME}" >/dev/null
    fi
    podman rm "${CONTAINER_NAME}"
    if [ $? -eq 0 ]; then
        echo "Container '${CONTAINER_NAME}' removed."
    else
        echo "Could not remove container '${CONTAINER_NAME}'. It might have already been removed."
    fi
}

logs_container() {
    echo "Displaying logs for Tang container '${CONTAINER_NAME}'..."
    podman logs -f "${CONTAINER_NAME}"
}

status_container(){
    echo "Status for Tang container '${CONTAINER_NAME}':"
    podman ps -a -f name="${CONTAINER_NAME}" --format "table {{.ID}}\\t{{.Image}}\\t{{.Command}}\\t{{.CreatedAt}}\\t{{.Status}}\\t{{.Ports}}\\t{{.Names}}"
    
    echo "\\nKey directory contents (${HOST_KEY_DIR}):"
    if [ -r "${HOST_KEY_DIR}" ]; then
        ls -l "${HOST_KEY_DIR}"
    else
        echo "Cannot read ${HOST_KEY_DIR} (permission denied or doesn't exist)"
    fi

    # Check if the container is not running and show recent logs
    # Ensure container exists before trying to inspect its state
    if podman container exists "${CONTAINER_NAME}"; then
        if [ "$(podman container inspect -f '{{.State.Running}}' "${CONTAINER_NAME}")" != "true" ]; then
            echo "\\nContainer '${CONTAINER_NAME}' is not currently running."
            echo "Showing last 10 lines of logs for '${CONTAINER_NAME}':"
            podman logs --tail 10 "${CONTAINER_NAME}"
        fi
    else
        echo "\\nContainer '${CONTAINER_NAME}' does not exist."
    fi
}

case "$1" in
    build)
        build_image
        ;;
    start)
        # Check if image exists, build if not
        if ! podman image exists "${IMAGE_NAME}"; then
            echo "Image '${IMAGE_NAME}' not found. Building it first..."
            build_image
        fi
        start_container
        ;;
    stop)
        stop_container
        ;;
    restart)
        stop_container
        # Small delay to ensure port is free if restarting quickly
        sleep 2
        start_container
        ;;
    rm)
        remove_container
        ;;
    logs)
        logs_container
        ;;
    status)
        status_container
        ;;
    *)
        echo "Usage: $0 {build|start|stop|restart|rm|logs|status}"
        exit 1
        ;;
esac

exit 0
