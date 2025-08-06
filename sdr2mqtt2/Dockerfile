ARG BUILD_FROM
FROM $BUILD_FROM

# Define RTL_433 version
ARG RTL433_VERSION=25.02

# Define environment variables
# Use this variable when creating a container to specify the MQTT broker host.
ENV MQTT_HOST=127.0.0.1 \
    MQTT_PORT=1883 \
    MQTT_USERNAME="" \
    MQTT_PASSWORD="" \
    MQTT_RETAIN=True \
    MQTT_TOPIC=rtl_433 \
    FREQUENCY=915.00M \
    PROTOCOL="" \
    RTL_SDR_SERIAL_NUM=915 \
    WHITELIST_ENABLE=False \
    EXPIRE_AFTER=0 \
    WHITELIST="" \
    DISCOVERY_PREFIX=homeassistant \
    DISCOVERY_INTERVAL=600 \
    AUTO_DISCOVERY=False \
    DEBUG=False \
    LANG=C.UTF-8

LABEL Maintainer="Jeffrey Stone" \
Description="This image is used to start the RTL433 to HASS script that will monitor for 915Mhz devices and send the data to an MQTT server"

WORKDIR /data

# Copy scripts
COPY entry.sh rtl_433_mqtt_hass.py /scripts/

# Install build dependencies and runtime dependencies
RUN apk add --no-cache \
        # Runtime dependencies
        rtl-sdr \
        libusb \
        mosquitto-clients \
        python3 \
        py3-paho-mqtt \
        sed \
        libusb-dev \
        librtlsdr \
        # Build dependencies (will be removed later)
        && \
    apk add --no-cache --virtual .build-deps \
        build-base \
        cmake \
        git \
        libtool \
        pkgconfig \
        rtl-sdr-dev \
        libusb-dev && \
    # Build RTL_433 from source
    cd /tmp && \
    git clone https://github.com/merbanan/rtl_433.git && \
    cd rtl_433 && \
    git checkout ${RTL433_VERSION} && \
    mkdir build && \
    cd build && \
    cmake -DCMAKE_BUILD_TYPE=Release .. && \
    make -j$(nproc) && \
    make install && \
    # Clean up build dependencies and temporary files
    cd / && \
    rm -rf /tmp/rtl_433 && \
    apk del .build-deps && \
    # Make scripts executable
    chmod +x /scripts/entry.sh && \
    chmod +x /scripts/rtl_433_mqtt_hass.py

# Execute entry script
ENTRYPOINT [ "/scripts/entry.sh" ]
