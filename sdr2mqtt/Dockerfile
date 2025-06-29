ARG BUILD_FROM
FROM $BUILD_FROM

# Define environment variables
# Use this variable when creating a container to specify the MQTT broker host.
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

LABEL Maintainer="Jeffrey Stone" \
Description="This image is used to start the RTL433 to HASS script that will monitor for 433Mhz devices and send the data to an MQTT server"

WORKDIR /data

# Copy scripts
COPY entry.sh rtl_433_mqtt_hass.py /scripts/

# Install build dependencies and runtime dependencies
RUN apk add --no-cache --virtual .build-deps \
    git \
    cmake \
    make \
    gcc \
    g++ \
    libc-dev \
    libusb-dev \
    pkgconfig && \
    apk add --no-cache \
    rtl-sdr \
    libusb \
    mosquitto-clients \
    python3 \
    py3-paho-mqtt \
    sed && \
    # Clone and build rtl_433 from the feat-gardensoil branch with better error handling
    echo "Cloning rtl_433 feat-gardensoil branch..." && \
    git clone --depth 1 --branch feat-gardensoil https://github.com/merbanan/rtl_433.git /tmp/rtl_433 && \
    echo "Branch cloned successfully, contents:" && \
    ls -la /tmp/rtl_433/ && \
    cd /tmp/rtl_433 && \
    echo "Creating build directory..." && \
    mkdir -p build && \
    cd build && \
    echo "Running cmake..." && \
    cmake .. -DCMAKE_BUILD_TYPE=Release && \
    echo "Building with make..." && \
    make -j$(nproc) && \
    echo "Installing..." && \
    make install && \
    # Verify installation
    echo "Verifying rtl_433 installation..." && \
    rtl_433 -V && \
    # Clean up build dependencies and temporary files
    cd / && \
    rm -rf /tmp/rtl_433 && \
    apk del .build-deps && \
    # Make scripts executable
    chmod +x /scripts/entry.sh && \
    chmod +x /scripts/rtl_433_mqtt_hass.py

# Execute entry script
ENTRYPOINT [ "/scripts/entry.sh" ]
