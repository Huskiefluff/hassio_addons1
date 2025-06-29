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
AUTO_DISCOVERY="$(bashio::config 'auto_discovery')"

export LANG=C

bashio::log.blue "::::::::Starting RTL_433 with RTL-TCP approach::::::::"
bashio::log.info "This approach separates hardware access from signal processing"

# Check if we have protocol 278
if rtl_433 -R help | grep -q "278.*HG9901"; then
    bashio::log.info "✓ Protocol 278 (Homelead HG9901) available"
fi

# Method 1: Try with rtl_tcp server
bashio::log.info "Starting rtl_tcp server..."

# Start rtl_tcp in background
if command -v rtl_tcp >/dev/null 2>&1; then
    # Kill any existing rtl_tcp
    pkill rtl_tcp 2>/dev/null || true
    sleep 1
    
    # Start rtl_tcp server
    rtl_tcp -a 127.0.0.1 -p 1234 -d 0 &
    RTL_TCP_PID=$!
    sleep 3
    
    bashio::log.info "RTL-TCP server started (PID: $RTL_TCP_PID)"
    
    # Now connect rtl_433 to rtl_tcp
    bashio::log.info "Connecting rtl_433 to rtl_tcp..."
    
    if [ "$AUTO_DISCOVERY" = "true" ]; then
        rtl_433 -d rtl_tcp:127.0.0.1:1234 $FREQUENCY $PROTOCOL -C $UNITS -F json -M time -M protocol | python3 /scripts/rtl_433_mqtt_hass.py
    else
        rtl_433 -d rtl_tcp:127.0.0.1:1234 $FREQUENCY $PROTOCOL -C $UNITS -F "mqtt://$MQTT_HOST:$MQTT_PORT,user=$MQTT_USERNAME,pass=$MQTT_PASSWORD,events=$MQTT_TOPIC/events" -M time -M protocol
    fi
    
    # Cleanup
    kill $RTL_TCP_PID 2>/dev/null || true
    
else
    bashio::log.error "rtl_tcp not available, trying fallback approach..."
    
    # Fallback: Use stable system rtl_433 if available
    if command -v /usr/bin/rtl_433 >/dev/null 2>&1; then
        bashio::log.info "Trying system rtl_433..."
        /usr/bin/rtl_433 $FREQUENCY $PROTOCOL -C $UNITS -F "mqtt://$MQTT_HOST:$MQTT_PORT,user=$MQTT_USERNAME,pass=$MQTT_PASSWORD,events=$MQTT_TOPIC/events" -M time -M protocol
    else
        bashio::log.error "No working rtl_433 available"
        exit 1
    fi
fi
