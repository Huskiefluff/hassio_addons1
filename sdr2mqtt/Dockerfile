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

# Configure build
RUN cd /tmp/rtl_433 && \
    mkdir -p build && \
    cd build && \
    echo "Configuring cmake..." && \
    cmake .. -DCMAKE_BUILD_TYPE=Release

# Build
RUN cd /tmp/rtl_433/build && \
    echo "Building..." && \
    make -j$(nproc)

# Manual installation to ensure it goes to the right place
RUN cd /tmp/rtl_433/build && \
    echo "Installing manually..." && \
    cp src/rtl_433 /usr/bin/rtl_433 && \
    chmod +x /usr/bin/rtl_433

# Verify installation
RUN echo "Verifying installation..." && \
    ls -la /usr/bin/rtl_433 && \
    /usr/bin/rtl_433 -V

# Check for protocol 278
RUN echo "Checking for protocol 278..." && \
    /usr/bin/rtl_433 -R help | grep "278" || \
    (echo "Protocol 278 not found in help, checking source..." && \
     grep -r "HG9901\|Homelead" /tmp/rtl_433/ || echo "Protocol search completed")

# Cleanup
RUN rm -rf /tmp/rtl_433 && \
    apk del .build-deps

# Set permissions
RUN chmod +x /scripts/entry.sh && \
    chmod +x /scripts/rtl_433_mqtt_hass.py

# Execute entry script
ENTRYPOINT [ "/scripts/entry.sh" ]
