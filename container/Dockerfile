# Puppet Enterprise in Docker
# Build arguments for versioning and installer artifact handoff
ARG BASE_IMAGE=almalinux:9
ARG PE_VERSION
ARG PE_INSTALLER_TAR_PATH
ARG PE_INSTALLER_TAR_CONTEXT_PATH=container/assets/pe-installer/installer.tar.gz

# Validate build inputs and prepare installer archive (build stage)
FROM ${BASE_IMAGE} as build-validator

ARG PE_VERSION
ARG PE_INSTALLER_TAR_PATH
ARG PE_INSTALLER_TAR_CONTEXT_PATH

# Copy validation helpers
COPY container/scripts/lib/state.sh /tmp/state.sh

# Copy installer archive from build context into image-local path for validation
COPY ${PE_INSTALLER_TAR_CONTEXT_PATH} /tmp/pe-installer.tar.gz
RUN source /tmp/state.sh && \
    validate_installer_tar_at_build_time "/tmp/pe-installer.tar.gz" "${PE_VERSION}" || exit 1 && \
    verify_installer_version_match "/tmp/pe-installer.tar.gz" "${PE_VERSION}" && \
    echo "Build input validation: PASS"

# Stage validated installer archive for runtime extraction.
RUN mkdir -p /puppet-staging && \
    cp /tmp/pe-installer.tar.gz /puppet-staging/installer.tar.gz && \
    echo "Installer archive staging: SUCCESS to /puppet-staging/installer.tar.gz"

#  Record build metadata for runtime use
RUN echo "PE_VERSION=${PE_VERSION}" > /puppet-staging/.build-metadata && \
    echo "PE_INSTALLER_TAR_PATH=${PE_INSTALLER_TAR_PATH}" >> /puppet-staging/.build-metadata && \
    echo "BUILD_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> /puppet-staging/.build-metadata

# Final runtime image
FROM ${BASE_IMAGE}

# Install systemd container support and the runtime packages PE expects.
RUN dnf install -y epel-release procps-ng iproute cronie glibc-langpack-en && \
    dnf clean all

# Create directories for lifecycle scripts and persistent state
RUN mkdir -p /puppet/scripts/lib /puppet/state /puppet/installer-staging

# Copy lifecycle scripts from host
COPY container/scripts/lib/state.sh /puppet/scripts/lib/state.sh
COPY container/scripts/lib/logging.sh /puppet/scripts/lib/logging.sh
COPY container/scripts/lib/status-probe.sh /puppet/scripts/lib/status-probe.sh
COPY container/scripts/entrypoint.sh /puppet/entrypoint.sh
COPY container/scripts/code-manager-initial-deploy.sh /puppet/code-manager-initial-deploy.sh
COPY container/scripts/healthcheck.sh /puppet/healthcheck.sh
COPY container/scripts/validate-runtime-state.sh /puppet/validate-runtime-state.sh
COPY container/scripts/reset-runtime-state.sh /puppet/reset-runtime-state.sh

# Copy installer archive from build stage (runtime extracts during bootstrap)
COPY --from=build-validator /puppet-staging /puppet/installer-staging/
COPY --from=build-validator /puppet-staging/.build-metadata /puppet/state/.build-metadata

# Make scripts executable
RUN chmod +x /puppet/entrypoint.sh /puppet/healthcheck.sh \
             /puppet/validate-runtime-state.sh /puppet/reset-runtime-state.sh \
             /puppet/code-manager-initial-deploy.sh

COPY container/scripts/bootstrap-pe.sh /puppet/bootstrap-pe.sh
RUN chmod +x /puppet/bootstrap-pe.sh

# Install bootstrap orchestration as a systemd unit so PE bootstrap/restore runs at container boot.
COPY container/systemd/pe-container-bootstrap.service /etc/systemd/system/pe-container-bootstrap.service
RUN chmod 0644 /etc/systemd/system/pe-container-bootstrap.service && \
    systemctl enable pe-container-bootstrap.service


# Set environment for state management and systemd-in-container mode.
ENV PE_STATE_DIR=/puppet/state
ENV PE_INSTALLER_STAGING=/puppet/installer-staging
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV container=docker

# Run systemd as PID 1 so the PE installer and managed services can function.
STOPSIGNAL SIGRTMIN+3
VOLUME ["/sys/fs/cgroup"]
CMD ["/usr/sbin/init"]

# Docker healthcheck configuration
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD /puppet/healthcheck.sh
