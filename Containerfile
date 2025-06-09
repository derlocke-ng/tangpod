FROM fedora:latest

ARG TANG_USER=tang
ARG TANG_GROUP=tang
ARG TANG_UID=1000
ARG TANG_GID=1000
ARG TANG_KEY_DIR=/var/db/tang

# Install Tang server and utility for privilege dropping
# hostname is a dependency for tangd in some setups or for key generation details
RUN dnf install -y tang hostname util-linux && \
    dnf clean all

# Modify the existing tang user/group to use standard UID/GID 1000:1000
# This avoids user namespace mapping issues with rootless containers
RUN usermod -u ${TANG_UID} ${TANG_USER} && \
    groupmod -g ${TANG_GID} ${TANG_GROUP}

# Set environment variables for the entrypoint script
ENV TANG_USER=${TANG_USER} \
    TANG_GROUP=${TANG_GROUP} \
    TANG_UID=${TANG_UID} \
    TANG_GID=${TANG_GID} \
    TANG_KEY_DIR=${TANG_KEY_DIR}

# Create the key directory structure within the image.
# The actual keys will reside in the mounted volume from the host.
RUN mkdir -p ${TANG_KEY_DIR} && \
    # Set initial ownership; entrypoint will re-assert on the mounted volume.
    chown ${TANG_USER}:${TANG_GROUP} ${TANG_KEY_DIR} && \
    chmod 700 ${TANG_KEY_DIR}

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Volume for persistent keys
VOLUME [\"${TANG_KEY_DIR}\"]

# Expose port 80 (default internal port for tangd)
EXPOSE 80

# The entrypoint script will handle initial setup and then execute tangd
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
