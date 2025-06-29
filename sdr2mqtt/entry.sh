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

# Export all config for Python script
export MQTT_HOST MQTT_PORT MQTT_USERNAME MQTT_PASSWORD MQTT_TOPIC DISCOVERY_PREFIX
export WHITELIST_ENABLE WHITELIST DISCOVERY_INTERVAL AUTO_DISCOVERY DEBUG EXPIRE_AFTER MQTT_RETAIN

bashio::log.blue "::::::::RTL_433 Working Mode::::::::"
bashio::log.info "Protocol 278 (HG9901) available for soil moisture sensors"

# Cleanup function
cleanup() {
    bashio::log.info "Shutting down gracefully..."
    if [ ! -z "$RTL_TCP_PID" ]; then
        kill -TERM $RTL_TCP_PID 2>/dev/null || true
        sleep 1
        kill -KILL $RTL_TCP_PID 2>/dev/null || true
    fi
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT SIGQUIT

# Kill any existing rtl_tcp
pkill rtl_tcp 2>/dev/null || true
sleep 1

# Start rtl_tcp with correct device
DEVICE_INDEX=0
if [ "$RTL_SDR_SERIAL_NUM" = "2002" ]; then
    DEVICE_INDEX=1
fi

bashio::log.info "Starting rtl_tcp on device $DEVICE_INDEX (SN: $RTL_SDR_SERIAL_NUM)..."
rtl_tcp -a 127.0.0.1 -p 1234 -d $DEVICE_INDEX &
RTL_TCP_PID=$!
sleep 3

bashio::log.info "RTL_433 is working! Listening for signals..."
bashio::log.info "Enabled protocols: $PROTOCOL"
bashio::log.info "Frequency: $FREQUENCY"

# Start the main process with error handling
while true; do
    bashio::log.info "Starting signal detection..."
    
    # Run rtl_433 with JSON output
    rtl_433 \
        -d rtl_tcp:127.0.0.1:1234 \
        $FREQUENCY \
        $PROTOCOL \
        -C $UNITS \
        -F json \
        -M time \
        -M protocol 2>/dev/null | \
    python3 /scripts/rtl_433_mqtt_hass.py
    
    # If we get here, rtl_433 exited
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ] || [ $EXIT_CODE -eq 130 ]; then
        # Normal exit or SIGINT
        bashio::log.info "rtl_433 exited normally"
        break
    else
        # Abnormal exit, restart after a delay
        bashio::log.warning "rtl_433 exited unexpectedly (code: $EXIT_CODE), restarting in 5 seconds..."
        sleep 5
        
        # Check if rtl_tcp is still running
        if ! kill -0 $RTL_TCP_PID 2>/dev/null; then
            bashio::log.info "Restarting rtl_tcp..."
            rtl_tcp -a 127.0.0.1 -p 1234 -d $DEVICE_INDEX &
            RTL_TCP_PID=$!
            sleep 3
        fi
    fi
done

cleanup
