# Building a Puppet Enterprise Container

This guide explains how to build a versioned PE container image from a local installer artifact.

## Prerequisites

1. **Docker** installed and configured for building images
2. **Puppet Enterprise installer** downloaded and verified on your local filesystem  
   - Recommended: Verify SHA256 and/or GPG signature from Puppet's official source
3. **Absolute file path** to the installer (Linux/Mac use `/path/to/installer.tar.gz`)
4. **PE version identifier** matching the installer (e.g., `2024.1.0`)

## Build Command

Use the provided `Makefile` target to build:

```bash
PE_VERSION="2024.1.0"
PE_INSTALLER_TAR_PATH="/opt/pe-installers/puppet-enterprise-2024.1.0-el-7-x86_64.tar.gz"

make build PE_VERSION="${PE_VERSION}" PE_INSTALLER_TAR_PATH="${PE_INSTALLER_TAR_PATH}"
```

### Parameters

- **PE_VERSION**: Version string identifying the PE release. Must match the installer archive contents.
- **PE_INSTALLER_TAR_PATH**: Full absolute path to the installer tar.gz on your filesystem.

## What Happens During Build

1. **Input Validation** (fail-fast)
   - Verifies PE_VERSION is provided
   - Verifies PE_INSTALLER_TAR_PATH is absolute (starts with `/`)
   - Confirms installer file exists and is readable
   - Validates tar.gz format

2. **Installer Extraction**
   - Extracts tar contents into a staging location inside the container
   - Records build metadata (version, timestamp, source path)

3. **Lifecycle Scripts Setup**
   - Copies entrypoint, healthcheck, bootstrap, state management into container
   - Configures tini as PID 1 for signal handling
   - Wires Docker healthcheck endpoint

4. **Image Tagging**
   - Tags image as `pe-container:${PE_VERSION}` and `pe-container:latest`
   - Ready for immediate deployment or registry push

## Build Validation Output

On success, you'll see:
```
[Build] Validating PE_VERSION and PE_INSTALLER_TAR_PATH...
[Build] Starting Docker build with PE_VERSION=2024.1.0...
... (docker build output)
[Build] SUCCESS: Image tagged as pe-container:2024.1.0
```

On failure, docker build exits with clear error messaging:
```
ERROR: PE_INSTALLER_TAR_PATH file not found: /nonexistent/installer.tar.gz
```

## Using the Built Image

After build completes, run with:

```bash
docker-compose -f container/compose/docker-compose.example.yml up -d
```

Or manually:

```bash
docker run \
  --name pe-primary \
  --volume pe-config:/etc/puppetlabs \
  --volume pe-data:/opt/puppetlabs \
  --volume pe-logs:/var/log/puppetlabs \
  -e PE_STATE_DIR=/puppet/state \
  "pe-container:2024.1.0"
```

First startup will bootstrap PE from the staged installer. Subsequent restarts restore from persisted state.

## Troubleshooting

### "PE_INSTALLER_TAR_PATH must be an absolute path"

Ensure the path starts with `/`. Relative paths (e.g., `./installer.tar.gz` or `~/path`) are not supported.

### "PE_INSTALLER_TAR_PATH file not found"

Verify the installer is located at the path you provided and is readable by your user/Docker:
```bash
ls -l /opt/pe-installers/puppet-enterprise-*.tar.gz
```

### "PE_INSTALLER_TAR_PATH is not a valid tar.gz archive"

Verify the file is a valid archive:
```bash
tar -tzf /opt/pe-installers/puppet-enterprise-*.tar.gz > /dev/null && echo "Valid" || echo "Invalid"
```

### Build takes a very long time

The first build performs image extraction and script setup. Subsequent builds using the same base image will be faster due to Docker layer caching.

## Next Steps

- See [Quickstart](../quickstart.md) for first-time startup and verification
- See [Build Interface Contract](./build-interface.md) for detailed input/output specifications
- See [Container Runtime Contract](./container-runtime.md) for runtime behavior and lifecycle

