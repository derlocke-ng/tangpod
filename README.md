# TangPod - Flexible Tang Server Container Management

TangPod provides a production-ready, containerized Tang server with advanced management, flexible image source selection, and robust key handling. Tang is used for network-bound disk encryption (NBDE) with Clevis and LUKS.

[![Build and Publish](https://github.com/derlocke-ng/tangpod/actions/workflows/build-and-publish.yml/badge.svg)](https://github.com/derlocke-ng/tangpod/actions/workflows/build-and-publish.yml)

---

## ✨ Features

- **Flexible Image Sources**: Use local builds, registry images, or custom images
- **Smart Auto Mode**: Prefers local image, falls back to registry if missing
- **Comprehensive Management**: One script for build, pull, start, stop, logs, status, backup, restore, and more
- **Persistent Keys**: Uses named volumes for secure, permissionless key storage
- **Key Inspection**: View keys, advertisements, and volume info
- **Backup & Restore**: Easy backup and recovery of Tang keys
- **Rootless & Secure**: Works with rootless Podman/Docker, SELinux compatible
- **CI/CD Ready**: Automated multi-arch builds and security scanning

---

## 🚀 Quick Start

### Prerequisites

- **Container Runtime**: Podman (recommended) or Docker
- **System**: Linux (Fedora, RHEL, Ubuntu tested)
- **Architecture**: x86_64 or ARM64

### 1. Clone and Start (Auto Mode)

```bash
git clone https://github.com/derlocke-ng/tangpod.git
cd tangpod
./tangctl.sh start
```

- Auto mode uses local image if available, otherwise pulls from registry.

### 2. Use Registry Image Only

```bash
export TANG_IMAGE_SOURCE=registry
./tangctl.sh start
```

### 3. Use Local Build Only

```bash
export TANG_IMAGE_SOURCE=local
./tangctl.sh start
```

### 4. Use Custom Image

```bash
export TANG_IMAGE_SOURCE=my-registry.com/my-tang:v1.0
./tangctl.sh start
```

---

## 🛠️ Management Commands

| Command                  | Description                                      |
|--------------------------|--------------------------------------------------|
| `build`                  | Build or pull image (mode depends on image source)|
| `pull`                   | Pull registry image (auto/registry/custom mode)   |
| `start`                  | Start Tang server container                      |
| `stop`                   | Stop the container                              |
| `restart`                | Restart the container                           |
| `rm`                     | Remove the container                            |
| `logs`                   | Show container logs                             |
| `status`                 | Show container and volume status                |
| `keys`                   | Display Tang keys from the volume               |
| `adv`                    | Show Tang server advertisement                  |
| `volume-info`            | Show detailed volume information                |
| `volume-backup [file]`   | Backup volume to tar file                       |
| `volume-restore <file>`  | Restore volume from tar file                    |
| `volume-clean`           | Remove the Tang keys volume (DESTROYS KEYS!)    |
| `config`                 | Show current configuration and image source     |

---

## 🖼️ Image Source Configuration

Set the image source via `TANG_IMAGE_SOURCE`:

| Mode      | Description                                         | Use Case           |
|-----------|-----------------------------------------------------|--------------------|
| `auto`    | Use local image if available, else registry (default)| Most users         |
| `local`   | Always build and use local image                    | Development        |
| `registry`| Always use pre-built registry image                 | Production/CI      |
| `<custom>`| Use custom image name (e.g. my-registry.com/tang:v1)| Private registries |

**Change mode:**

```bash
export TANG_IMAGE_SOURCE=registry   # Use registry image
export TANG_IMAGE_SOURCE=local      # Use local build
export TANG_IMAGE_SOURCE=auto       # Auto mode (default)
export TANG_IMAGE_SOURCE=my-image:v1 # Custom image
```

---

## ⚙️ Configuration Reference

| Variable             | Default                        | Description                  |
|----------------------|--------------------------------|------------------------------|
| `TANG_IMAGE_SOURCE`  | `auto`                         | Image source mode            |
| `TANG_KEY_DIR`       | `/var/db/tang`                 | Key directory in container   |
| `CONTAINER_NAME`     | `tangpod`                      | Container name               |
| `VOLUME_NAME`        | `tang-keys`                    | Volume name                  |
| `HOST_PORT`          | `7500`                         | Host port                    |
| `CONTAINER_PORT`     | `80`                           | Container port               |
| `LOCAL_IMAGE_NAME`   | `tang-server`                  | Local image name             |
| `REGISTRY_IMAGE_NAME`| `ghcr.io/derlocke-ng/tangpod:latest` | Registry image name   |

Override by exporting before running commands, or edit at the top of `tangctl.sh`.

---

## 🔑 Tang Keys & Advertisement

- Keys are stored as `.jwk` files in the volume (private + public parts).
- Advertisement (`adv`) shows only public key info for clients.
- Use `./tangctl.sh keys` and `./tangctl.sh adv` to inspect.

---

## 🧑‍💻 Advanced Usage

- **Systemd Integration**: Use `tangctl.sh start/stop` in service files for auto-start.
- **Backup/Restore**: Use `volume-backup` and `volume-restore` for disaster recovery.
- **Rootless & SELinux**: Named volumes avoid permission issues and work with SELinux.
- **Custom Volumes/Ports**: Override `VOLUME_NAME` and `HOST_PORT` as needed.

---

## 🛡️ Security

- Runs as non-root user
- Keys persist in named volume, not container
- Minimal container exposure (only port 7500 exposed)

---

## 🤝 Contributing

- Fork, branch, and PRs welcome!
- Run `./tangctl.sh build` and `./tangctl.sh start` to test changes
- See `.github/workflows/build-and-publish.yml` for CI details

---

## 📄 License

MIT License. See [LICENSE](LICENSE).

---

## 📞 Support

- See `./tangctl.sh config` and this README for help
- File issues or feature requests on GitHub

---

Made with 🥝 for security enthusiasts
