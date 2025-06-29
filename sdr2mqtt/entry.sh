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

bashio::log.blue "::::::::RTL_433 Robust Multi-Protocol Mode::::::::"

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

# Start rtl_tcp ONCE and keep it running
start_rtl_tcp() {
    bashio::log.info "Starting rtl_tcp on device $DEVICE_INDEX..."
    rtl_tcp -a 127.0.0.1 -p 1234 -d $DEVICE_INDEX >/dev/null 2>&1 &
    RTL_TCP_PID=$!
    sleep 3
    bashio::log.info "rtl_tcp started (PID: $RTL_TCP_PID)"
}

start_rtl_tcp

# Start Python MQTT bridge in background
start_python_bridge() {
    python3 /scripts/rtl_433_mqtt_hass.py &
    PYTHON_PID=$!
    bashio::log.info "MQTT bridge started (PID: $PYTHON_PID)"
}

start_python_bridge

bashio::log.info "🎯 Robust multi-protocol detection ready!"
bashio::log.info "📡 Protocols: ${PROTOCOL:-"ALL"}"
bashio::log.info "📊 Frequency: $FREQUENCY"
bashio::log.info "🔄 Auto-restart enabled for segfaults"

# Cleanup function
cleanup() {
    bashio::log.info "Cleaning up processes..."
    kill $RTL_TCP_PID $PYTHON_PID 2>/dev/null || true
    exit 0
}

trap cleanup SIGTERM SIGINT

# Main loop with intelligent restart
RESTART_COUNT=0
LAST_SUCCESS_TIME=$(date +%s)

while true; do
    RESTART_COUNT=$((RESTART_COUNT + 1))
    CURRENT_TIME=$(date +%s)
    
    bashio::log.info "📡 Starting detection session #$RESTART_COUNT"
    
    # Build rtl_433 command
    RTL_CMD="rtl_433 -d rtl_tcp:127.0.0.1:1234 $FREQUENCY"
    
    # Add protocols if specified
    if [ -n "$PROTOCOL" ] && [ "$PROTOCOL" != "" ]; then
        RTL_CMD="$RTL_CMD $PROTOCOL"
        bashio::log.debug "Command: $RTL_CMD -C $UNITS -F json -M time -M protocol"
    else
        bashio::log.debug "Command: $RTL_CMD -C $UNITS -F json -M time -M protocol (all protocols)"
    fi
    
    # Create a named pipe for communication
    PIPE="/tmp/rtl433_pipe_$$"
    mkfifo "$PIPE" 2>/dev/null || true
    
    # Start rtl_433 and redirect to pipe
    (
        set +e  # Don't exit on errors
        $RTL_CMD -C $UNITS -F json -M time -M protocol 2>/dev/null > "$PIPE"
        echo "RTL_433_EXIT_CODE=$?" > /tmp/rtl433_exit
    ) &
    RTL_PID=$!
    
    # Read from pipe and send to Python bridge
    timeout 3600 cat "$PIPE" | python3 -c "
import sys
import json
import os
import paho.mqtt.client as mqtt

# Connect to MQTT
client = mqtt.Client()
client.username_pw_set('$MQTT_USERNAME', '$MQTT_PASSWORD')
client.connect('$MQTT_HOST', $MQTT_PORT, 60)
client.publish('$MQTT_TOPIC/status', 'online', retain=True)

try:
    for line in sys.stdin:
        line = line.strip()
        if line:
            try:
                data = json.loads(line)
                # Publish to events topic
                client.publish('$MQTT_TOPIC/events', json.dumps(data), retain=False)
                print(f'Published: {data.get(\"model\", \"unknown\")} {data.get(\"id\", \"\")}')
            except:
                pass
finally:
    client.disconnect()
" 2>/dev/null || true
    
    # Clean up pipe
    rm -f "$PIPE" 2>/dev/null || true
    
    # Check exit status
    if [ -f /tmp/rtl433_exit ]; then
        source /tmp/rtl433_exit
        rm -f /tmp/rtl433_exit
        
        if [ "$RTL_433_EXIT_CODE" = "139" ]; then
            bashio::log.warning "Segfault detected in session #$RESTART_COUNT - restarting..."
            sleep 1
        else
            bashio::log.info "rtl_433 exited with code $RTL_433_EXIT_CODE"
            sleep 2
        fi
    else
        bashio::log.info "Session #$RESTART_COUNT completed"
        sleep 1
    fi
    
    # Check if components are still running
    if ! kill -0 $RTL_TCP_PID 2>/dev/null; then
        bashio::log.info "Restarting rtl_tcp..."
        start_rtl_tcp
    fi
    
    if ! kill -0 $PYTHON_PID 2>/dev/null; then
        bashio::log.info "Restarting MQTT bridge..."
        start_python_bridge
    fi
    
    # Prevent rapid restart loops
    if [ $RESTART_COUNT -gt 20 ]; then
        bashio::log.warning "Many restarts detected, pausing 30 seconds..."
        sleep 30
        RESTART_COUNT=0
    fi
done
