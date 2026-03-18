# Puppet Enterprise Installer Examples

## Handling the PE Installer Tar Archive

The container build process accepts the Puppet Enterprise installer as a local file system artifact and expects an **absolute file path** to an installer tar.gz archive.

### Build Input Requirements

1. **Installer Version (PE_VERSION)**: Version string matching the installer contents (e.g., `2024.1.0`).
2. **Installer Path (PE_INSTALLER_TAR_PATH)**: Absolute filesystem path to the installer tar.gz (e.g., `/var/pe-installers/puppet-enterprise-2024.1.0-el-7-x86_64.tar.gz`).

### Path Validation Rules

- **MUST be absolute**: Paths starting with `/` are required; relative paths are rejected.
- **MUST exist and be readable**: The build process validates that the file is accessible before commencing.
- **MUST match the versioned artifact**: Version metadata inside the archive must match `PE_VERSION`.

### Build Lifecycle

1. **Extract**: The build process extracts the installer archive to a staging location inside the container (`/puppet/installer-staging/`).
2. **Validate**: Metadata verification ensures the contents match the declared version.
3. **Install**: The installation script runs inside the container on first boot.
4. **Cleanup**: After verified installation completion, installer artifacts are removed from the runtime filesystem to reduce image bloat and operator confusion.

### Example Build Command

```bash
# Assuming the installer has been downloaded to the local filesystem
PE_VERSION="2024.1.0"
PE_INSTALLER_PATH="/opt/pe-installers/puppet-enterprise-${PE_VERSION}-el-7-x86_64.tar.gz"

# Build the container
make build PE_VERSION="${PE_VERSION}" PE_INSTALLER_TAR_PATH="${PE_INSTALLER_PATH}"

# Result: docker image tagged "pe-container:2024.1.0"
```

### Troubleshooting Build Input Errors

- **"PE_INSTALLER_TAR_PATH is not absolute"**: Provide a path starting with `/`.
- **"File not found"**: Verify the installer path is correct and accessible to Docker (consider host filesystem permissions).
- **"Version mismatch"**: Ensure `PE_VERSION` matches the version string inside the tar.gz archive.

## Notes

- The installer archive is held in the build context; Docker's build cache may retain it for subsequent builds using the same path.
- For production use, ensure installer artifacts are sourced from a trusted, verified location.
- The operator is responsible for validating the integrity (SHA256, GPG signing, etc.) of the installer before providing it to the build process.

