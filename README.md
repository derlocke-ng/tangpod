# Tang Server Container

A containerized Tang server setup optimized for Podman with automatic key generation and management. Tang is a server for binding data to network presence, commonly used with Clevis for automated decryption of LUKS-encrypted drives.

[![Build and Publish](https://github.com/derlocke-ng/tangpod/actions/workflows/build-and-publish.yml/badge.svg)](https://github.com/derlocke-ng/tangpod/actions/workflows/build-and-publish.yml)

## Features

- 🔐 **Automatic Key Management**: Generates Tang keys if none exist, reuses existing keys
- 🐳 **Container Ready**: Optimized for Podman and Docker with multi-platform support
- 🛡️ **SELinux Compatible**: Proper labeling and permissions for SELinux systems
- 🔧 **Easy Management**: Simple control script for container lifecycle
- 📦 **Rootless Friendly**: Works with rootless Podman/Docker
- 🏗️ **CI/CD Ready**: GitHub Actions workflow for automated builds

## Quick Start

### Using Pre-built Container

```bash
# Pull the container
podman pull ghcr.io/derlocke-ng/tangpod:latest

# Create key directory
mkdir -p tang_keys

# Run the container
podman run -d \
  --name tangpod \
  -p 7500:80 \
  -v "$(pwd)/tang_keys:/var/db/tang:Z" \
  ghcr.io/derlocke-ng/tangpod:latest
```

### Using Local Build

1. **Clone this repository:**
   ```bash
   git clone https://github.com/derlocke-ng/tangpod.git
   cd tangpod
   ```

2. **Start the Tang server:**
   ```bash
   ./tangctl.sh start
   ```

That's it! The script will automatically:
- Create the `tang_keys` directory if it doesn't exist
- Build the container image if needed
- Generate Tang keys on first run
- Start the Tang server on port 7500

## Management Script Usage

The `tangctl.sh` script provides easy container management:

```bash
# Build the container image
./tangctl.sh build

# Start the Tang server
./tangctl.sh start

# Stop the Tang server
./tangctl.sh stop

# Restart the Tang server
./tangctl.sh restart

# Remove the container (keeps keys)
./tangctl.sh rm

# View container logs
./tangctl.sh logs

# Check status and recent logs
./tangctl.sh status
```

## Configuration

### Default Settings

- **Container Name**: `tangpod`
- **Host Port**: `7500`
- **Container Port**: `80`
- **Key Directory**: `./tang_keys`
- **Image Name**: `tang-server`

### Customization

Edit the variables at the top of `tangctl.sh`:

```bash
IMAGE_NAME="tang-server"
CONTAINER_NAME="tangpod"
HOST_PORT=7500
CONTAINER_PORT=80
HOST_KEY_DIR="$(pwd)/tang_keys"
```

## Using with Clevis

Once your Tang server is running, you can use it with Clevis for automated LUKS decryption:

### Encrypting a LUKS Device

```bash
# Add Tang binding to existing LUKS device
sudo clevis luks bind -d /dev/sdX tang '{"url":"http://your-server:7500"}'

# Or during initial LUKS setup
sudo cryptsetup luksFormat /dev/sdX
sudo clevis luks bind -d /dev/sdX tang '{"url":"http://your-server:7500"}'
```

### Getting Advertisement

```bash
# Get Tang server advertisement
curl http://localhost:7500/adv

# Verify Tang server is working
clevis encrypt tang '{"url":"http://localhost:7500"}' < /dev/null
```

## File Structure

```
tangpod/
├── Containerfile          # Container image definition
├── entrypoint.sh          # Container startup script
├── tangctl.sh             # Management script
├── tang_keys/             # Persistent key storage (created automatically)
├── .github/
│   └── workflows/
│       └── build-and-publish.yml  # CI/CD workflow
└── README.md              # This file
```

## How It Works

1. **Container Build**: The `Containerfile` creates a Fedora-based container with Tang server installed
2. **Key Management**: The `entrypoint.sh` script handles:
   - Directory permissions and ownership
   - Automatic key generation if none exist
   - Starting the Tang server with proper configuration
3. **Persistence**: Keys are stored in a volume-mounted directory that persists across container restarts
4. **Security**: Runs with proper user separation and SELinux compatibility

## Advanced Usage

### Custom Key Directory

```bash
# Use a different key directory
HOST_KEY_DIR="/path/to/custom/keys" ./tangctl.sh start
```

### Running with Docker

The scripts work with Docker as well:

```bash
# Modify tangctl.sh to use docker instead of podman
sed -i 's/podman/docker/g' tangctl.sh
./tangctl.sh start
```

### SELinux Considerations

On SELinux-enabled systems, the script automatically handles volume labeling with the `:Z` option. If you encounter permission issues:

```bash
# Set SELinux context manually
sudo chcon -Rt container_file_t ./tang_keys

# Or disable SELinux for the container (less secure)
# Edit tangctl.sh and add: --security-opt label=disable
```

### Rootless Podman

The setup works with rootless Podman out of the box. The container runs as root internally but maps to your user namespace, ensuring proper permission handling.

## Troubleshooting

### Container Exits Immediately

Check the logs:
```bash
./tangctl.sh logs
```

Common issues:
- Permission problems with key directory
- SELinux blocking volume access
- Port already in use

### Keys Not Persisting

Ensure the `tang_keys` directory has proper permissions:
```bash
ls -la tang_keys/
# Should show ownership by UID 525286 (container's tang user)
```

### Can't Access Tang Server

Check if the container is running and port is open:
```bash
./tangctl.sh status
curl http://localhost:7500/adv
```

### Permission Denied on Key Directory

The container changes ownership of the key directory. This is normal and expected for proper security.

## Security Notes

- 🔐 Keys are persistent and survive container restarts
- 👤 The Tang server runs as a non-root user inside the container
- 🛡️ SELinux labeling is handled automatically
- 🔒 The key directory is set to mode 700 (owner access only)
- 🚪 Only the Tang server port (80) is exposed from the container

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with `./tangctl.sh start`
5. Submit a pull request

## License

This project is licensed under the MIT License. See the Tang project for Tang-specific licensing.

## Related Projects

- [Tang](https://github.com/latchset/tang) - The original Tang server
- [Clevis](https://github.com/latchset/clevis) - Client-side tools for Tang
- [NBDE](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/security_hardening/configuring-automated-unlocking-of-encrypted-volumes-using-policy-based-decryption_security-hardening) - Network-Bound Disk Encryption documentation
