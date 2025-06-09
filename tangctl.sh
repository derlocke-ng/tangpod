#!/bin/bash

# Configuration
# Image source: "local" to build locally, "registry" to use pre-built, or specify full image name
IMAGE_SOURCE="${TANG_IMAGE_SOURCE:-auto}"  # auto, local, registry, or full image name
LOCAL_IMAGE_NAME="tang-server"
REGISTRY_IMAGE_NAME="ghcr.io/derlocke-ng/tangpod:latest"
CONTAINER_NAME="tangpod"
VOLUME_NAME="tang-keys"
HOST_PORT=7500 # Or any other port you prefer on the host
CONTAINER_PORT=80 # Tang server default internal port

# Function to determine which image to use
get_image_name() {
    case "${IMAGE_SOURCE}" in
        "local")
            echo "${LOCAL_IMAGE_NAME}"
            ;;
        "registry")
            echo "${REGISTRY_IMAGE_NAME}"
            ;;
        "auto")
            # Auto-detect: prefer local if it exists, otherwise use registry
            if podman image exists "${LOCAL_IMAGE_NAME}"; then
                echo "${LOCAL_IMAGE_NAME}"
            else
                echo "${REGISTRY_IMAGE_NAME}"
            fi
            ;;
        *)
            # Assume it's a full image name
            echo "${IMAGE_SOURCE}"
            ;;
    esac
}

# Set the current image name
IMAGE_NAME=$(get_image_name)

# Function to create or ensure the volume exists
ensure_volume() {
    if ! podman volume exists "${VOLUME_NAME}"; then
        echo "Creating volume '${VOLUME_NAME}' for Tang keys..."
        podman volume create "${VOLUME_NAME}"
        if [ $? -eq 0 ]; then
            echo "✅ Volume '${VOLUME_NAME}' created successfully"
        else
            echo "❌ Failed to create volume '${VOLUME_NAME}'"
            exit 1
        fi
    else
        echo "Volume '${VOLUME_NAME}' already exists"
    fi
}

# Function to display Tang keys from the volume
show_keys() {
    echo "=== Tang Keys ==="
    echo
    
    if ! podman volume exists "${VOLUME_NAME}"; then
        echo "❌ Volume '${VOLUME_NAME}' does not exist. Start the container first to generate keys."
        return 1
    fi
    
    # Run a temporary container to read the keys from the volume
    echo "Retrieving keys from volume '${VOLUME_NAME}'..."
    
    # List key files - use our own tang-server image but bypass entrypoint
    echo "📁 Key files:"
    podman run --rm --entrypoint="" -v "${VOLUME_NAME}:/var/db/tang:ro" "${IMAGE_NAME}" ls -la /var/db/tang/ 2>/dev/null || {
        echo "❌ Could not access keys. Make sure the container has been started at least once."
        return 1
    }
    
    echo
    echo "🔑 Key contents (complete key pairs):"
    # Show content of .jwk files (these contain full public+private key pairs)
    podman run --rm --entrypoint="" -v "${VOLUME_NAME}:/var/db/tang:ro" "${IMAGE_NAME}" sh -c 'for key in /var/db/tang/*.jwk; do if [ -f "$key" ]; then echo "=== $(basename "$key") ==="; cat "$key" 2>/dev/null && echo; fi; done' 2>/dev/null || {
        echo "❌ Could not read key contents"
        return 1
    }
    
    echo "📋 Tang advertisement (use this to verify server identity):"
    # Get advertisement from the running server via HTTP
    if podman container exists "${CONTAINER_NAME}" && [ "$(podman container inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null)" == "true" ]; then
        curl -s "http://localhost:${HOST_PORT}/adv" 2>/dev/null | python3 -m json.tool 2>/dev/null || {
            echo "   (Could not retrieve advertisement via HTTP)"
        }
    else
        echo "   (Container not running - start it to see advertisement)"
    fi
}

# Function to get the Tang advertisement (what clients see)
show_advertisement() {
    echo "=== Tang Server Advertisement ==="
    echo
    
    # Check if container is running
    if ! podman container exists "${CONTAINER_NAME}" || [ "$(podman container inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null)" != "true" ]; then
        echo "❌ Container '${CONTAINER_NAME}' is not running. Start it first with: ./tangctl.sh start"
        return 1
    fi
    
    echo "🌐 Tang advertisement (what clients receive):"
    curl -s "http://localhost:${HOST_PORT}/adv" 2>/dev/null | python3 -m json.tool 2>/dev/null || {
        echo "❌ Could not retrieve advertisement. Check if the server is running and accessible."
        return 1
    }
}

# Function to show detailed volume information
volume_info() {
    echo "=== Tang Volume Information ==="
    echo
    
    if podman volume exists "${VOLUME_NAME}"; then
        echo "✅ Volume '${VOLUME_NAME}' exists"
        echo
        echo "📊 Volume Details:"
        podman volume inspect "${VOLUME_NAME}" --format "{{json .}}" | python3 -m json.tool 2>/dev/null || {
            podman volume inspect "${VOLUME_NAME}"
        }
        
        echo
        echo "📁 Volume Contents:"
        podman run --rm --entrypoint="" -v "${VOLUME_NAME}:/tang:ro" "${IMAGE_NAME}" ls -la /tang/ 2>/dev/null || {
            echo "❌ Could not list volume contents"
        }
        
        echo
        echo "💾 Volume Size:"
        podman run --rm --entrypoint="" -v "${VOLUME_NAME}:/tang:ro" "${IMAGE_NAME}" du -sh /tang/ 2>/dev/null || {
            echo "❌ Could not determine volume size"
        }
    else
        echo "❌ Volume '${VOLUME_NAME}' does not exist"
        echo "   Run './tangctl.sh start' to create the volume and generate keys"
    fi
}

# Function to backup volume to tar file
volume_backup() {
    local backup_file="${1:-tang-keys-backup-$(date +%Y%m%d-%H%M%S).tar.gz}"
    
    echo "=== Backing up Tang Volume ==="
    echo
    
    if ! podman volume exists "${VOLUME_NAME}"; then
        echo "❌ Volume '${VOLUME_NAME}' does not exist. Nothing to backup."
        return 1
    fi
    
    echo "📦 Creating backup: ${backup_file}"
    
    # Create backup using a temporary container
    if podman run --rm --entrypoint="" \
        -v "${VOLUME_NAME}:/tang:ro" \
        -v "$(pwd):/backup" \
        "${IMAGE_NAME}" \
        tar -czf "/backup/${backup_file}" -C /tang .; then
        echo "✅ Backup created successfully: ${backup_file}"
        echo "📏 Backup size: $(ls -lh "${backup_file}" | awk '{print $5}')"
    else
        echo "❌ Failed to create backup"
        return 1
    fi
}

# Function to restore volume from tar file
volume_restore() {
    local backup_file="$1"
    
    if [ -z "$backup_file" ]; then
        echo "❌ Usage: $0 volume-restore <backup-file>"
        return 1
    fi
    
    if [ ! -f "$backup_file" ]; then
        echo "❌ Backup file '${backup_file}' does not exist"
        return 1
    fi
    
    echo "=== Restoring Tang Volume ==="
    echo
    
    # Check if container is running and warn user
    if podman container exists "${CONTAINER_NAME}" && [ "$(podman container inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null)" == "true" ]; then
        echo "⚠️  WARNING: Container '${CONTAINER_NAME}' is currently running."
        echo "   Restoring keys while the container is running may cause issues."
        echo "   Consider stopping the container first: ./tangctl.sh stop"
        echo
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Operation cancelled."
            return 1
        fi
    fi
    
    # Ensure volume exists
    ensure_volume
    
    echo "📦 Restoring from: ${backup_file}"
    
    # Restore using a temporary container
    if podman run --rm --entrypoint="" \
        -v "${VOLUME_NAME}:/tang" \
        -v "$(pwd):/backup:ro" \
        "${IMAGE_NAME}" \
        sh -c "rm -rf /tang/* && tar -xzf /backup/${backup_file} -C /tang"; then
        echo "✅ Volume restored successfully from ${backup_file}"
        echo "🔄 Restart the container to use the restored keys: ./tangctl.sh restart"
    else
        echo "❌ Failed to restore volume"
        return 1
    fi
}

# Function to clean up (remove) the volume
volume_clean() {
    echo "=== Cleaning Tang Volume ==="
    echo
    
    if ! podman volume exists "${VOLUME_NAME}"; then
        echo "✅ Volume '${VOLUME_NAME}' does not exist. Nothing to clean."
        return 0
    fi
    
    # Check if container is using the volume
    if podman container exists "${CONTAINER_NAME}"; then
        echo "⚠️  WARNING: Container '${CONTAINER_NAME}' exists and may be using this volume."
        echo "   Removing the volume will destroy all Tang keys permanently!"
        echo "   You should stop and remove the container first:"
        echo "   ./tangctl.sh stop && ./tangctl.sh rm"
        echo
        read -p "Continue and remove volume anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Operation cancelled."
            return 1
        fi
        
        # Stop container if running
        if [ "$(podman container inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null)" == "true" ]; then
            echo "Stopping container..."
            podman stop "${CONTAINER_NAME}"
        fi
        
        # Remove container
        echo "Removing container..."
        podman rm "${CONTAINER_NAME}" 2>/dev/null || true
    fi
    
    echo "🗑️  Removing volume '${VOLUME_NAME}'..."
    if podman volume rm "${VOLUME_NAME}"; then
        echo "✅ Volume '${VOLUME_NAME}' removed successfully"
        echo "   All Tang keys have been permanently deleted."
        echo "   Run './tangctl.sh start' to create a new volume with new keys."
    else
        echo "❌ Failed to remove volume '${VOLUME_NAME}'"
        return 1
    fi
}

build_image() {
    local force_build="${1:-false}"
    
    if [ "${IMAGE_SOURCE}" = "registry" ] && [ "${force_build}" != "true" ]; then
        echo "Image source is set to 'registry'. Pulling latest image..."
        echo "Image: ${REGISTRY_IMAGE_NAME}"
        podman pull "${REGISTRY_IMAGE_NAME}"
        if [ $? -ne 0 ]; then
            echo "❌ Failed to pull registry image. You can:"
            echo "   1. Build locally: IMAGE_SOURCE=local $0 build"
            echo "   2. Check your internet connection"
            echo "   3. Verify the registry image exists"
            exit 1
        fi
        echo "✅ Registry image pulled successfully"
        return 0
    fi
    
    if [ "${IMAGE_SOURCE}" != "local" ] && [ "${IMAGE_SOURCE}" != "auto" ] && [ "${force_build}" != "true" ]; then
        echo "❌ Cannot build when IMAGE_SOURCE is set to '${IMAGE_SOURCE}'"
        echo "   Use IMAGE_SOURCE=local or 'auto' to enable local building"
        exit 1
    fi
    
    echo "Building Tang server image '${LOCAL_IMAGE_NAME}'..."
    if [ ! -f "Containerfile" ]; then
        echo "❌ Containerfile not found in current directory"
        echo "   Make sure you're running this script from the tangpod directory"
        exit 1
    fi
    
    podman build -t "${LOCAL_IMAGE_NAME}" .
    if [ $? -ne 0 ]; then
        echo "❌ Error building image. Exiting."
        exit 1
    fi
    echo "✅ Image '${LOCAL_IMAGE_NAME}' built successfully"
}

start_container() {
    echo "Starting Tang container '${CONTAINER_NAME}'..."
    echo "Using image: ${IMAGE_NAME}"
    
    # Ensure volume exists
    ensure_volume
    
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
                echo "✅ Container '${CONTAINER_NAME}' is now running."
                echo "📡 Accessible on host port: ${HOST_PORT}"
                echo "🔑 Keys are stored in volume: ${VOLUME_NAME}"
            else
                echo "❌ Container '${CONTAINER_NAME}' was started but is not currently running. It may have exited."
                echo "Showing last 10 lines of logs for '${CONTAINER_NAME}':"
                podman logs --tail 10 "${CONTAINER_NAME}"
                echo "For full logs, use: ./tangctl.sh logs"
                echo "For detailed status, use: ./tangctl.sh status"
            fi
        else
            echo "❌ Failed to execute start command for existing container '${CONTAINER_NAME}'. Try stopping and removing it first (./tangctl.sh stop && ./tangctl.sh rm)."
        fi
        return
    fi

    # Ensure image is available
    if ! podman image exists "${IMAGE_NAME}"; then
        echo "Image '${IMAGE_NAME}' not found."
        case "${IMAGE_SOURCE}" in
            "local"|"auto")
                echo "Building local image..."
                build_image
                # Update IMAGE_NAME after building
                IMAGE_NAME=$(get_image_name)
                ;;
            "registry")
                echo "Pulling from registry..."
                build_image  # This will handle registry pull
                ;;
            *)
                echo "Pulling custom image..."
                podman pull "${IMAGE_NAME}"
                if [ $? -ne 0 ]; then
                    echo "❌ Failed to pull image '${IMAGE_NAME}'"
                    echo "   Check if the image exists or use a different IMAGE_SOURCE"
                    exit 1
                fi
                ;;
        esac
    fi

    echo "Creating and starting new container '${CONTAINER_NAME}'..."
    
    # Run container with volume mount (no permission issues!)
    podman run -d \
        --name "${CONTAINER_NAME}" \
        -p "${HOST_PORT}:${CONTAINER_PORT}" \
        -v "${VOLUME_NAME}:/var/db/tang" \
        "${IMAGE_NAME}"

    if [ $? -eq 0 ]; then
        echo "✅ Tang container '${CONTAINER_NAME}' initiated startup."
        # Brief pause to allow container to fully start or fail
        sleep 3
        if podman container inspect "${CONTAINER_NAME}" &>/dev/null && \
           [ "$(podman container inspect -f '{{.State.Running}}' "${CONTAINER_NAME}")" == "true" ]; then
            echo "✅ Container '${CONTAINER_NAME}' is running."
            echo "📡 Accessible on host port: ${HOST_PORT}"
            echo "🔑 Keys are stored in volume: ${VOLUME_NAME}"
            echo "🖼️  Using image: ${IMAGE_NAME}"
        else
            echo "❌ Container '${CONTAINER_NAME}' started but is not running. It may have exited due to an error."
            echo "Showing last 10 lines of logs for '${CONTAINER_NAME}':"
            podman logs --tail 10 "${CONTAINER_NAME}"
            echo "For full logs, use: ./tangctl.sh logs"
            echo "For detailed status, use: ./tangctl.sh status"
        fi
    else
        echo "❌ Error creating/starting Tang container. Check Podman's ability to run the image."
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
    
    echo "\\nVolume information:"
    if podman volume exists "${VOLUME_NAME}"; then
        echo "✅ Volume '${VOLUME_NAME}' exists"
        podman volume inspect "${VOLUME_NAME}" --format "Mountpoint: {{.Mountpoint}}"
    else
        echo "❌ Volume '${VOLUME_NAME}' does not exist"
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
        build_image "$2"
        ;;
    pull)
        if [ "${IMAGE_SOURCE}" = "local" ]; then
            echo "❌ Cannot pull when IMAGE_SOURCE is set to 'local'"
            echo "   Use IMAGE_SOURCE=registry or IMAGE_SOURCE=auto to enable pulling"
            exit 1
        fi
        build_image  # This handles pulling for registry images
        ;;
    start)
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
    keys)
        show_keys
        ;;
    adv|advertisement)
        show_advertisement
        ;;
    volume-info)
        volume_info
        ;;
    volume-backup)
        volume_backup "$2"
        ;;
    volume-restore)
        volume_restore "$2"
        ;;
    volume-clean)
        volume_clean
        ;;
    config)
        echo "\n=== TangPod Configuration ==="
        echo "Image Source Mode : ${IMAGE_SOURCE}"
        echo "Current Image     : ${IMAGE_NAME}"
        echo "Local Image Name  : ${LOCAL_IMAGE_NAME}"
        echo "Registry Image    : ${REGISTRY_IMAGE_NAME}"
        echo "Container Name    : ${CONTAINER_NAME}"
        echo "Volume Name       : ${VOLUME_NAME}"
        echo "Host Port         : ${HOST_PORT}"
        echo "Container Port    : ${CONTAINER_PORT}"
        echo ""
        echo "Environment Variables (current values):"
        printf '  %-20s %s\n' "TANG_IMAGE_SOURCE" "${TANG_IMAGE_SOURCE:-auto} (image source mode)"
        printf '  %-20s %s\n' "TANG_KEY_DIR" "${TANG_KEY_DIR:-/var/db/tang} (key directory in container)"
        printf '  %-20s %s\n' "CONTAINER_NAME" "${CONTAINER_NAME} (container name)"
        printf '  %-20s %s\n' "VOLUME_NAME" "${VOLUME_NAME} (volume name)"
        printf '  %-20s %s\n' "HOST_PORT" "${HOST_PORT} (host port)"
        printf '  %-20s %s\n' "CONTAINER_PORT" "${CONTAINER_PORT} (container port)"
        printf '  %-20s %s\n' "LOCAL_IMAGE_NAME" "${LOCAL_IMAGE_NAME} (local image name)"
        printf '  %-20s %s\n' "REGISTRY_IMAGE_NAME" "${REGISTRY_IMAGE_NAME} (registry image name)"
        echo ""
        echo "Image Source Modes:"
        echo "  auto      - Use local image if available, otherwise registry (default)"
        echo "  local     - Always build and use local image"
        echo "  registry  - Always use pre-built registry image"
        echo "  <custom>  - Use custom image name (e.g. my-registry.com/tang:v1.0)"
        echo ""
        echo "To change image source, set TANG_IMAGE_SOURCE before running commands, e.g.:"
        echo "  export TANG_IMAGE_SOURCE=registry   # Use registry image"
        echo "  export TANG_IMAGE_SOURCE=local      # Use local build"
        echo "  export TANG_IMAGE_SOURCE=auto       # Auto mode (default)"
        echo "  export TANG_IMAGE_SOURCE=my-image:v1 # Custom image"
        echo ""
        echo "See README.md for full documentation."
        ;;
    *)
        echo "Usage: $0 {build|pull|start|stop|restart|rm|logs|status|keys|adv|volume-info|volume-backup|volume-restore|volume-clean|config}"
        echo ""
        echo "Container Commands:"
        echo "  build           - Build or pull Tang server image (mode depends on TANG_IMAGE_SOURCE)"
        echo "  pull            - Pull image from registry (registry/auto/custom mode only)"
        echo "  start           - Start Tang server container (auto-manages image)"
        echo "  stop            - Stop Tang server container"
        echo "  restart         - Stop and start the container"
        echo "  rm              - Remove the container"
        echo "  logs            - Show container logs"
        echo "  status          - Show container status and volume information"
        echo ""
        echo "Key Commands:"
        echo "  keys            - Display Tang keys from the volume"
        echo "  adv             - Show Tang server advertisement (what clients see)"
        echo ""
        echo "Volume Commands:"
        echo "  volume-info     - Show detailed volume information"
        echo "  volume-backup   - Backup volume to tar file (usage: $0 volume-backup [filename])"
        echo "  volume-restore  - Restore volume from tar file (usage: $0 volume-restore <filename>)"
        echo "  volume-clean    - Remove the Tang keys volume (WARNING: destroys keys!)"
        echo ""
        echo "Configuration:"
        echo "  config          - Show current configuration and image source options"
        echo ""
        echo "Image Source (set via TANG_IMAGE_SOURCE environment variable):"
        echo "  auto (default)  - Use local image if available, otherwise registry"
        echo "  local           - Build and use local image only"
        echo "  registry        - Use pre-built registry image: ${REGISTRY_IMAGE_NAME}"
        echo "  <custom>        - Use custom image name"
        echo ""
        echo "Current: IMAGE_SOURCE=${IMAGE_SOURCE}, Image=${IMAGE_NAME}"
        exit 1
        ;;
esac

exit 0
