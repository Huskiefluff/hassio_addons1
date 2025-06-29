#!/usr/bin/bashio

# Get config
MQTT_HOST="$(bashio::config 'mqtt_host')"
MQTT_PORT="$(bashio::config 'mqtt_port')"
MQTT_USERNAME="$(bashio::config 'mqtt_user')"
MQTT_PASSWORD="$(bashio::config 'mqtt_password')"
MQTT_TOPIC="$(bashio::config 'mqtt_topic')"
MQTT_RETAIN="$(bashio::config 'mqtt_retain')"
RTL_SDR_SERIAL_NUM="$(bashio::config 'rtl_sdr_serial_num')"
PROTOCOL="$(bashio::config 'protocol')"
FREQUENCY="$(bashio::config 'frequency')"
UNITS="$(bashio::config 'units')"
DISCOVERY_PREFIX="$(bashio::config 'discovery_prefix')"
DISCOVERY_INTERVAL="$(bashio::config 'discovery_interval')"
WHITELIST_ENABLE="$(bashio::config 'whitelist_enable')"
WHITELIST="$(bashio::config 'whitelist')"
AUTO_DISCOVERY="$(bashio::config 'auto_discovery')"
DEBUG="$(bashio::config 'debug')"
EXPIRE_AFTER="$(bashio::config 'expire_after')"

export LANG=C

bashio::log.blue "::::::::RTL_433 JSON-Only Safe Mode::::::::"
bashio::log.info "Using JSON output with Python MQTT bridge"

# Check protocol 278
if rtl_433 -R help | grep -q "278.*HG9901"; then
    bashio::log.info "✓ Protocol 278 (Homelead HG9901) available"
fi

# Kill any existing rtl_tcp
pkill rtl_tcp 2>/dev/null || true
sleep 2

# Start rtl_tcp with correct device
DEVICE_INDEX=0
if [ "$RTL_SDR_SERIAL_NUM" = "2002" ]; then
    DEVICE_INDEX=1
fi

bashio::log.info "Starting rtl_tcp on device $DEVICE_INDEX (SN: $RTL_SDR_SERIAL_NUM)..."
rtl_tcp -a 127.0.0.1 -p 1234 -d $DEVICE_INDEX &
RTL_TCP_PID=$!
sleep 3

# Export config for Python script
export MQTT_HOST MQTT_PORT MQTT_USERNAME MQTT_PASSWORD MQTT_TOPIC DISCOVERY_PREFIX
export WHITELIST_ENABLE WHITELIST DISCOVERY_INTERVAL AUTO_DISCOVERY DEBUG EXPIRE_AFTER MQTT_RETAIN

bashio::log.info "Starting rtl_433 with JSON output only..."
bashio::log.info "Command: rtl_433 -d rtl_tcp:127.0.0.1:1234 $FREQUENCY $PROTOCOL -C $UNITS -F json -M time -M protocol"

# Use only JSON output - safest approach
rtl_433 \
    -d rtl_tcp:127.0.0.1:1234 \
    $FREQUENCY \
    $PROTOCOL \
    -C $UNITS \
    -F json \
    -M time \
    -M protocol | \
python3 /scripts/rtl_433_mqtt_hass.py

# Cleanup
kill $RTL_TCP_PID 2>/dev/null || true
