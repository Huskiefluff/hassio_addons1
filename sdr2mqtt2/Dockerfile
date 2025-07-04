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

# Install runtime dependencies - try to get everything from apk first
RUN apk add --no-cache \
    python3 \
    py3-pip \
    mosquitto-clients \
    jq \
    libusb \
    rtl-sdr \
    bash && \
    apk add --no-cache py3-paho-mqtt || pip3 install --no-cache-dir --break-system-packages paho-mqtt

# Install build dependencies including rtl-sdr-dev from testing
RUN apk add --no-cache --virtual .build-deps \
    git \
    cmake \
    make \
    g++ \
    gcc \
    musl-dev \
    libusb-dev \
    librtlsdr \
    linux-headers \
    pkgconf

# Build and install rtl-sdr from source first
RUN cd /tmp && \
    git clone https://github.com/osmocom/rtl-sdr.git && \
    cd rtl-sdr && \
    mkdir build && \
    cd build && \
    cmake .. -DINSTALL_UDEV_RULES=OFF -DDETACH_KERNEL_DRIVER=ON && \
    make && \
    make install && \
    cd / && \
    rm -rf /tmp/rtl-sdr

# Clone and build rtl_433 from feat-gardensoil branch
RUN cd /tmp && \
    git clone https://github.com/merbanan/rtl_433.git && \
    cd rtl_433 && \
    git checkout feat-gardensoil || git checkout master && \
    mkdir build && \
    cd build && \
    cmake .. && \
    make && \
    make install && \
    cd / && \
    apk del .build-deps && \
    rm -rf /tmp/rtl_433 && \
    rm -rf /var/cache/apk/*

# Copy scripts
COPY entry.sh rtl_433_mqtt_hass.py /scripts/

# Make scripts executable
RUN chmod +x /scripts/entry.sh && \
    chmod +x /scripts/rtl_433_mqtt_hass.py

# Verify rtl_433 installation
RUN rtl_433 -V || echo "rtl_433 installation verification failed"

# Execute entry script
ENTRYPOINT [ "/scripts/entry.sh" ]
