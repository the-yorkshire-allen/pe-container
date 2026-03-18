# Puppet Enterprise in Docker
# Build arguments for versioning and installer artifact handoff
ARG BASE_IMAGE=almalinux:9
ARG PE_VERSION
ARG PE_INSTALLER_TAR_PATH

# Validate build inputs and prepare installer (build stage)
FROM ${BASE_IMAGE} as build-validator

ARG PE_VERSION
ARG PE_INSTALLER_TAR_PATH

# Copy validation helpers
COPY container/scripts/lib/state.sh /tmp/state.sh
RUN source /tmp/state.sh && \
    validate_installer_tar_at_build_time "${PE_INSTALLER_TAR_PATH}" "${PE_VERSION}" || exit 1 && \
    verify_installer_version_match "${PE_INSTALLER_TAR_PATH}" "${PE_VERSION}" && \
    echo "Build input validation: PASS"

# Extract installer to staging location
RUN mkdir -p /puppet-staging && \
    tar -xzf "${PE_INSTALLER_TAR_PATH}" -C /puppet-staging && \
    echo "Installer extraction: SUCCESS to /puppet-staging"

#  Record build metadata for runtime use
RUN echo "PE_VERSION=${PE_VERSION}" > /puppet-staging/.build-metadata && \
    echo "PE_INSTALLER_TAR_PATH=${PE_INSTALLER_TAR_PATH}" >> /puppet-staging/.build-metadata && \
    echo "BUILD_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> /puppet-staging/.build-metadata

# Final runtime image
FROM ${BASE_IMAGE}

# Install tini as PID 1 (handles signals and orphaned processes)
RUN dnf install -y tini && dnf clean all

# Create directories for lifecycle scripts and persistent state
RUN mkdir -p /puppet/scripts/lib /puppet/state /puppet/installer-staging

# Copy lifecycle scripts from host
COPY container/scripts/lib/state.sh /puppet/scripts/lib/state.sh
COPY container/scripts/lib/logging.sh /puppet/scripts/lib/logging.sh
COPY container/scripts/lib/status-probe.sh /puppet/scripts/lib/status-probe.sh
COPY container/scripts/entrypoint.sh /puppet/entrypoint.sh
COPY container/scripts/healthcheck.sh /puppet/healthcheck.sh
COPY container/scripts/validate-runtime-state.sh /puppet/validate-runtime-state.sh
COPY container/scripts/reset-runtime-state.sh /puppet/reset-runtime-state.sh

# Copy extracted installer from build stage (T018a)
COPY --from=build-validator /puppet-staging /puppet/installer-staging/
COPY --from=build-validator /puppet-staging/.build-metadata /puppet/state/.build-metadata

# Make scripts executable
RUN chmod +x /puppet/entrypoint.sh /puppet/healthcheck.sh \
             /puppet/validate-runtime-state.sh /puppet/reset-runtime-state.sh

COPY container/scripts/bootstrap-pe.sh /puppet/bootstrap-pe.sh
RUN chmod +x /puppet/bootstrap-pe.sh


# Set environment for state management
ENV PE_STATE_DIR=/puppet/state
ENV PE_INSTALLER_STAGING=/puppet/installer-staging

# Use tini as PID 1 to forward signals
ENTRYPOINT ["tini", "--", "/puppet/entrypoint.sh"]
CMD ["start"]

# Docker healthcheck configuration
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD /puppet/healthcheck.sh
