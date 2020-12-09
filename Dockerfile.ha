ARG BUILD_FROM=hassioaddons/base-aarch64:8.0.6
FROM $BUILD_FROM AS builder

ARG BUILD_DEPENDENCIES="\
autoconf                \
automake                \
libtool                 \
build-base              \
cairo-dev               \
libjpeg-turbo-dev       \
libpng-dev              \
ffmpeg-dev              \
freerdp-dev             \
pango-dev               \
libssh2-dev             \
libvncserver-dev        \
pulseaudio-dev          \
openssl-dev             \
libvorbis-dev           \
libwebp-dev             \
perl                    \
libwebsockets-dev       \
cunit-dev"

#ossp-uuid-dev           \

# Bring build environment up to date and install build dependencies
RUN apk add --no-cache $BUILD_DEPENDENCIES
RUN apk add ossp-uuid-dev --update-cache --repository http://dl-3.alpinelinux.org/alpine/edge/testing/ --allow-untrusted

ENV GUAC_VER=1.2.0

# Base directory for installed build artifacts.
# Due to limitations of the Docker image build process, this value is
# duplicated in an ARG in the second stage of the build.
#
ARG PREFIX_DIR=/usr/local/guacamole

# Build arguments
ARG BUILD_DIR=/tmp/guacd-docker-BUILD

# Add configuration scripts
COPY scripts "${PREFIX_DIR}/bin/"

# Build guacamole-server from local source
RUN chmod -R 777 ${PREFIX_DIR}/bin/build-guacd.sh
RUN ${PREFIX_DIR}/bin/build-guacd.sh "$BUILD_DIR" "$PREFIX_DIR" "$GUAC_VER"

# Record the packages of all runtime library dependencies
RUN chmod -R 777 ${PREFIX_DIR}/bin/list-dependencies.sh
RUN ${PREFIX_DIR}/bin/list-dependencies.sh    \
        ${PREFIX_DIR}/sbin/guacd              \
        ${PREFIX_DIR}/lib/libguac-client-*.so \
        ${PREFIX_DIR}/lib/freerdp2/guac*.so   \
        > ${PREFIX_DIR}/DEPENDENCIES

FROM $BUILD_FROM
# Base directory for installed build artifacts.
# Due to limitations of the Docker image build process, this value is
# duplicated in an ARG in the first stage of the build. See also the
# CMD directive at the end of this build stage.
#
ARG PREFIX_DIR=/usr/local/guacamole

# Runtime environment
ENV LC_ALL=C.UTF-8
ENV LD_LIBRARY_PATH=${PREFIX_DIR}/lib
ENV GUACD_LOG_LEVEL=info

ARG RUNTIME_DEPENDENCIES="            \
        netcat-openbsd                \
        ca-certificates               \
        ghostscript                   \
        fonts-liberation              \
        fonts-dejavu                  \
        xfonts-terminus"

# Copy build artifacts into this stage
COPY --from=builder ${PREFIX_DIR} ${PREFIX_DIR}

# Bring runtime environment up to date and install runtime dependencies
#RUN apt-get update                                                                  && \
#    apt-get install -y --no-install-recommends $RUNTIME_DEPENDENCIES                && \
#    apt-get install -y --no-install-recommends $(cat "${PREFIX_DIR}"/DEPENDENCIES)  && \
#    rm -rf /var/lib/apt/lists/*

# Link FreeRDP plugins into proper path
RUN chmod -R 777 ${PREFIX_DIR}/bin/link-freerdp-plugins.sh
RUN ${PREFIX_DIR}/bin/link-freerdp-plugins.sh \
        ${PREFIX_DIR}/lib/freerdp2/libguac*.so

# Checks the operating status every 5 minutes with a timeout of 5 seconds
HEALTHCHECK --interval=5m --timeout=5s CMD nc -z 127.0.0.1 4822 || exit 1

# Create a new user guacd
ARG UID=1000
RUN useradd --system --create-home --shell /usr/sbin/nologin --uid $UID --no-user-group guacd

RUN rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/* /usr/bin/qemu-*-static

# Run with user guacd
USER guacd

# Expose the default listener port
EXPOSE 4822

# Start guacd, listening on port 0.0.0.0:4822
#
# Note the path here MUST correspond to the value specified in the 
# PREFIX_DIR build argument.
#
CMD /usr/local/guacamole/sbin/guacd -b 0.0.0.0 -L $GUACD_LOG_LEVEL -f
