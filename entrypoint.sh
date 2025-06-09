#!/bin/bash
set -e

# Use environment variables set by the Containerfile, with fallbacks
TANG_KEY_DIR="${TANG_KEY_DIR:-/var/db/tang}"
TANG_USER="${TANG_USER:-tang}"
TANG_GROUP="${TANG_GROUP:-tang}"
TANG_UID="${TANG_UID:-1000}"
TANG_GID="${TANG_GID:-1000}"

echo "Starting Tang server entrypoint..."
echo "Using UID:GID ${TANG_UID}:${TANG_GID} for ${TANG_USER}:${TANG_GROUP}"

# Ensure the key directory exists
if [ ! -d "${TANG_KEY_DIR}" ]; then
    echo "Key directory ${TANG_KEY_DIR} not found. This should have been created by the Dockerfile or mount."
    exit 1
fi

# Set correct ownership and permissions on the key directory
# Using UID:GID directly to ensure proper permissions regardless of user namespace mapping
chown "${TANG_UID}:${TANG_GID}" "${TANG_KEY_DIR}" || echo "Warning: Could not chown ${TANG_KEY_DIR}"
chmod 700 "${TANG_KEY_DIR}"

# Check if keys exist. If not, generate them.
if ! ls "${TANG_KEY_DIR}"/*.jwk &>/dev/null; then
    echo "No keys found in ${TANG_KEY_DIR}. Generating new keys..."
    # Generate keys as the tang user using UID:GID
    setpriv --reuid="${TANG_UID}" --regid="${TANG_GID}" --clear-groups /usr/libexec/tangd-keygen "${TANG_KEY_DIR}"
    echo "Keys generated."
else
    echo "Existing keys found in ${TANG_KEY_DIR}."
fi

# Start the Tang server
# -l flag runs as a service and waits for connections
# -p 80 sets the port to 80 (container internal port)
echo "Starting Tang server on port 80..."
exec /usr/libexec/tangd -l -p 80 "${TANG_KEY_DIR}"
