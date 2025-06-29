ARG BUILD_FROM
FROM $BUILD_FROM

# Define environment variables
ENV MQTT_HOST=127.0.0.1 \
    MQTT_PORT=1883 \
    MQTT_USERNAME="" \
    MQTT_PASSWORD="" \
    MQTT_RETAIN=True \
    MQTT_TOPIC=rtl_433 \
    FREQUENCY=433.92M \
    PROTOCOL="" \
    RTL_SDR_SERIAL_NUM=433 \
    WHITELIST_ENABLE=False \
    EXPIRE_AFTER=0 \
    WHITELIST="" \
    DISCOVERY_PREFIX=homeassistant \
    DISCOVERY_INTERVAL=600 \
    AUTO_DISCOVERY=False \
    DEBUG=False \
    LANG=C.UTF-8

LABEL Maintainer="Huskie" \
Description="This image is used to start the RTL433 to HASS script that will monitor for 433Mhz devices and send the data to an MQTT server"

WORKDIR /data

# Copy scripts
COPY entry.sh rtl_433_mqtt_hass.py /scripts/

# Install build dependencies and runtime dependencies
RUN set -xe && \
    apk update && \
    apk add --no-cache --virtual .build-deps \
        git \
        cmake \
        make \
        gcc \
        g++ \
        libc-dev \
        libusb-dev \
        pkgconfig \
        linux-headers && \
    apk add --no-cache \
        rtl-sdr \
        libusb \
        mosquitto-clients \
        python3 \
        py3-paho-mqtt \
        sed && \
    echo "Cloning rtl_433 feat-gardensoil branch..." && \
    git clone --depth 1 --branch feat-gardensoil https://github.com/merbanan/rtl_433.git /tmp/rtl_433 && \
    echo "Successfully cloned feat-gardensoil branch" && \
    cd /tmp/rtl_433 && \
    echo "Contents of repository:" && \
    ls -la && \
    echo "Verifying protocol 278 exists:" && \
    grep -r "HG9901\|Homelead\|278" . || echo "Protocol 278 search completed" && \
    mkdir -p build && \
    cd build && \
    echo "Running cmake configuration..." && \
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DENABLE_RTLSDR=ON && \
    echo "Building rtl_433..." && \
    make -j$(nproc) && \
    echo "Installing rtl_433..." && \
    make install && \
    echo "Verifying installation..." && \
    rtl_433 -V && \
    echo "Checking for protocol 278..." && \
    rtl_433 -R help | grep -E "(278|HG9901|Homelead)" || echo "Protocol 278 check completed" && \
    echo "Cleaning up build files..." && \
    cd / && \
    rm -rf /tmp/rtl_433 && \
    apk del .build-deps && \
    echo "Making scripts executable..." && \
    chmod +x /scripts/entry.sh && \
    chmod +x /scripts/rtl_433_mqtt_hass.py && \
    echo "Build completed successfully!"

# Execute entry script
ENTRYPOINT [ "/scripts/entry.sh" ]
