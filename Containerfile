FROM fedora:latest

ARG TANG_USER=tang
ARG TANG_GROUP=tang
ARG TANG_KEY_DIR=/var/db/tang

# Install Tang server and utility for privilege dropping
# hostname is a dependency for tangd in some setups or for key generation details
RUN dnf install -y tang hostname util-linux && \
    dnf clean all

# The tang package on Fedora creates the 'tang' user and group.
# We use ARGs for clarity, these are standard names for the tang package.

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
