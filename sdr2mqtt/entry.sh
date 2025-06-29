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

bashio::log.blue "::::::::RTL_433 Multi-Protocol Mode::::::::"

# Parse and validate protocol string
if [ -n "$PROTOCOL" ] && [ "$PROTOCOL" != "" ]; then
    bashio::log.info "Raw protocol config: '$PROTOCOL'"
    
    # Clean up protocol string - remove extra quotes and normalize
    PROTOCOL_CLEAN=$(echo "$PROTOCOL" | sed 's/^["'\'']*//g' | sed 's/["'\'']*$//g' | tr -s ' ')
    bashio::log.info "Cleaned protocol: '$PROTOCOL_CLEAN'"
    
    # Validate each protocol
    PROTOCOL_VALID=""
    for proto in $PROTOCOL_CLEAN; do
        if [[ "$proto" =~ ^-R[[:space:]]*[0-9]+$ ]]; then
            PROTOCOL_VALID="$PROTOCOL_VALID $proto"
            bashio::log.info "✓ Valid protocol: $proto"
        else
            bashio::log.warning "⚠ Invalid protocol format: '$proto' (should be -R followed by number)"
        fi
    done
    
    if [ -n "$PROTOCOL_VALID" ]; then
        PROTOCOL="$PROTOCOL_VALID"
        bashio::log.info "Final protocols: $PROTOCOL"
    else
        bashio::log.warning "No valid protocols found, using all protocols"
        PROTOCOL=""
    fi
else
    bashio::log.info "No specific protocols configured, using all available"
    PROTOCOL=""
fi

# Check protocol availability
bashio::log.info "Checking protocol availability..."
if echo "$PROTOCOL" | grep -q "278"; then
    if rtl_433 -R help | grep -q "278.*HG9901"; then
        bashio::log.info "✅ Protocol 278 (HG9901 soil sensors) confirmed available"
    else
        bashio::log.error "❌ Protocol 278 not found in this rtl_433 build"
    fi
fi

if echo "$PROTOCOL" | grep -q "11"; then
    if rtl_433 -R help | grep -q "11.*Acurite"; then
        bashio::log.info "✅ Protocol 11 (Acurite sensors) confirmed available"
    else
        bashio::log.warning "⚠ Protocol 11 may not be available"
    fi
fi

# Kill existing processes
pkill rtl_tcp 2>/dev/null || true
sleep 1

# Device selection
DEVICE_INDEX=0
if [ "$RTL_SDR_SERIAL_NUM" = "2002" ]; then
    DEVICE_INDEX=1
fi

# Start rtl_tcp
bashio::log.info "Starting rtl_tcp on device $DEVICE_INDEX..."
rtl_tcp -a 127.0.0.1 -p 1234 -d $DEVICE_INDEX >/dev/null 2>&1 &
RTL_TCP_PID=$!
sleep 3

bashio::log.info "🎯 Multi-protocol detection ready!"
bashio::log.info "📡 Protocols: ${PROTOCOL:-"ALL"}"
bashio::log.info "📊 Frequency: $FREQUENCY"

# Main loop with restart capability
while true; do
    bashio::log.info "📡 Starting multi-protocol detection..."
    
    # Build rtl_433 command with proper protocol handling
    RTL_CMD="rtl_433 -d rtl_tcp:127.0.0.1:1234 $FREQUENCY"
    
    # Add protocols if specified
    if [ -n "$PROTOCOL" ] && [ "$PROTOCOL" != "" ]; then
        RTL_CMD="$RTL_CMD $PROTOCOL"
        bashio::log.info "Using protocols: $PROTOCOL"
    else
        bashio::log.info "Using all available protocols"
    fi
    
    # Add remaining parameters
    RTL_CMD="$RTL_CMD -C $UNITS -F json -M time -M protocol"
    
    bashio::log.debug "Full command: $RTL_CMD"
    
    # Execute the command
    $RTL_CMD 2>/dev/null | python3 /scripts/rtl_433_mqtt_hass.py
    
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
