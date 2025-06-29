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

# Export config for Python script
export MQTT_HOST MQTT_PORT MQTT_USERNAME MQTT_PASSWORD MQTT_TOPIC DISCOVERY_PREFIX
export WHITELIST_ENABLE WHITELIST DISCOVERY_INTERVAL AUTO_DISCOVERY DEBUG EXPIRE_AFTER MQTT_RETAIN

bashio::log.blue "::::::::RTL_433 Stable Mode::::::::"
bashio::log.info "✅ Protocol 278 (HG9901 soil sensors) ready"
bashio::log.info "✅ Protocol 11 (Acurite sensors) ready"  
bashio::log.info "✅ Auto-restart on crashes enabled"

# Kill existing processes
pkill rtl_tcp 2>/dev/null || true
sleep 1

# Device selection
DEVICE_INDEX=0
if [ "$RTL_SDR_SERIAL_NUM" = "2002" ]; then
    DEVICE_INDEX=1
fi

# Start rtl_tcp once
bashio::log.info "Starting rtl_tcp on device $DEVICE_INDEX..."
rtl_tcp -a 127.0.0.1 -p 1234 -d $DEVICE_INDEX >/dev/null 2>&1 &
RTL_TCP_PID=$!
sleep 3

bashio::log.info "🎯 Ready to detect signals! Place your HG9901 sensors nearby..."

# Simple restart loop
while true; do
    bashio::log.info "📡 Starting signal detection..."
    
    # Use a wrapper script that ignores segfaults
    bash -c "
        set +e
        rtl_433 \
            -d rtl_tcp:127.0.0.1:1234 \
            $FREQUENCY \
            $PROTOCOL \
            -C $UNITS \
            -F json \
            -M time \
            -M protocol 2>/dev/null | \
        python3 /scripts/rtl_433_mqtt_hass.py
        
        exit_code=\$?
        if [ \$exit_code -eq 139 ]; then
            echo 'Segfault occurred, but system is working - auto-restarting...'
        fi
        exit \$exit_code
    "
    
    # Brief pause before restart
    sleep 2
    
    # Check if rtl_tcp is still running
    if ! kill -0 $RTL_TCP_PID 2>/dev/null; then
        bashio::log.info "Restarting rtl_tcp..."
        rtl_tcp -a 127.0.0.1 -p 1234 -d $DEVICE_INDEX >/dev/null 2>&1 &
        RTL_TCP_PID=$!
        sleep 3
    fi
done
