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

LABEL Maintainer="Jeffrey Stone" \
Description="This image is used to start the RTL433 to HASS script that will monitor for 433Mhz devices and send the data to an MQTT server"

WORKDIR /data

# Copy scripts
COPY entry.sh rtl_433_mqtt_hass.py /scripts/

# Install dependencies
RUN apk update && \
    apk add --no-cache --virtual .build-deps \
        git \
        cmake \
        make \
        gcc \
        g++ \
        libc-dev \
        libusb-dev \
        librtlsdr-dev \
        pkgconfig \
        linux-headers

RUN apk add --no-cache \
        rtl-sdr \
        libusb \
        mosquitto-clients \
        python3 \
        py3-paho-mqtt \
        sed

# Clone repository
RUN echo "Cloning feat-gardensoil branch..." && \
    git clone --depth 1 --branch feat-gardensoil https://github.com/merbanan/rtl_433.git /tmp/rtl_433

# Configure build with fixed version handling
RUN cd /tmp/rtl_433 && \
    mkdir -p build && \
    cd build && \
    echo "Configuring cmake..." && \
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DENABLE_RTLSDR=ON

# Build
RUN cd /tmp/rtl_433/build && \
    echo "Building..." && \
    make -j$(nproc)

# Manual installation
RUN cd /tmp/rtl_433/build && \
    echo "Installing..." && \
    cp src/rtl_433 /usr/bin/rtl_433 && \
    chmod +x /usr/bin/rtl_433

# Verify installation and protocol 278
RUN echo "Verifying installation..." && \
    ls -la /usr/bin/rtl_433 && \
    echo "Testing rtl_433 (ignoring version display issue)..." && \
    /usr/bin/rtl_433 -h > /dev/null 2>&1 && \
    echo "rtl_433 is functional!" && \
    echo "Checking for protocol 278 (Homelead HG9901)..." && \
    /usr/bin/rtl_433 -R help | grep -E "(278|HG9901|Homelead)" && \
    echo "Protocol 278 confirmed!"

# Cleanup
RUN rm -rf /tmp/rtl_433 && \
    apk del .build-deps

# Set permissions
RUN chmod +x /scripts/entry.sh && \
    chmod +x /scripts/rtl_433_mqtt_hass.py

# Execute entry script
ENTRYPOINT [ "/scripts/entry.sh" ]
