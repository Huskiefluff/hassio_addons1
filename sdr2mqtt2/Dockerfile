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

# Copy scripts
COPY entry.sh rtl_433_mqtt_hass.py /scripts/

# Install runtime dependencies first
RUN apk add --no-cache \
    python3 \
    py3-pip \
    py3-paho-mqtt \
    mosquitto-clients \
    jq \
    libusb \
    rtl-sdr

# Install rtl_433 from feat-gardensoil branch
RUN apk add --no-cache --virtual .build-deps \
    git \
    cmake \
    make \
    g++ \
    libusb-dev \
    rtl-sdr-dev \
    && git clone -b feat-gardensoil https://github.com/merbanan/rtl_433.git /tmp/rtl_433 \
    && cd /tmp/rtl_433 \
    && mkdir build \
    && cd build \
    && cmake .. \
    && make \
    && make install \
    && apk del .build-deps \
    && rm -rf /tmp/rtl_433 \
    && chmod +x /scripts/entry.sh \
    && chmod +x /scripts/rtl_433_mqtt_hass.py

# Execute entry script
ENTRYPOINT [ "/scripts/entry.sh" ]
