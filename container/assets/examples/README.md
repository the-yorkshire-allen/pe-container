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

1. **Stage into Build Context**: `make build` copies the installer tar.gz from `PE_INSTALLER_TAR_PATH` to `container/assets/pe-installer/installer.tar.gz` so Docker build can access it.
2. **Validate**: Build-time validation ensures archive readability and version metadata consistency.
3. **Install**: On first boot, bootstrap extracts `/puppet/installer-staging/installer.tar.gz` and runs the installer.
4. **Cleanup**: After verified installation completion, extracted installer artifacts are removed from the runtime filesystem.

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
- **"File not found"**: Verify the installer path is correct and readable on the host. Docker `RUN` steps cannot directly access arbitrary host absolute paths, so `make build` stages the file into build context first.
- **"Version mismatch"**: Ensure `PE_VERSION` matches the version string inside the tar.gz archive.

## Notes

- The installer archive is held in the build context; Docker's build cache may retain it for subsequent builds using the same path.
- For production use, ensure installer artifacts are sourced from a trusted, verified location.
- The operator is responsible for validating the integrity (SHA256, GPG signing, etc.) of the installer before providing it to the build process.

