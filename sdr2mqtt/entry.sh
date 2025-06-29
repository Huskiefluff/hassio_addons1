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
DEBUG="$(bashio::config 'debug')"

export LANG=C
export PATH="/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"

bashio::log.blue "::::::::Starting RTL_433 with Hardware Safety::::::::"
bashio::log.info "MQTT Host: $MQTT_HOST"
bashio::log.info "Protocol: $PROTOCOL"
bashio::log.info "Frequency: $FREQUENCY"

# Check if we have protocol 278
if rtl_433 -R help | grep -q "278.*HG9901"; then
    bashio::log.info "✓ Protocol 278 (Homelead HG9901) confirmed available"
else
    bashio::log.warning "Protocol 278 status unknown"
fi

# Test hardware access safely
bashio::log.info "Testing RTL-SDR hardware access..."

# Method 1: Try with explicit device detection
DEVICE_FOUND=false
DEVICE_INDEX=0

# Check if RTL-SDR devices are available
if command -v rtl_test >/dev/null 2>&1; then
    bashio::log.info "Testing with rtl_test..."
    if timeout 3 rtl_test -t 2>/dev/null; then
        bashio::log.info "✓ RTL-SDR hardware detected with rtl_test"
        DEVICE_FOUND=true
    else
        bashio::log.warning "rtl_test failed or timed out"
    fi
fi

# Try alternative device detection
if ! $DEVICE_FOUND && command -v rtl_sdr >/dev/null 2>&1; then
    bashio::log.info "Testing with rtl_sdr..."
    RTL_OUTPUT=$(timeout 3 rtl_sdr -d 9999 2>&1 || true)
    if echo "$RTL_OUTPUT" | grep -q "Found.*device"; then
        bashio::log.info "✓ RTL-SDR devices found"
        DEVICE_FOUND=true
        # Try to find specific device by serial
        if echo "$RTL_OUTPUT" | grep -q "SN: $RTL_SDR_SERIAL_NUM"; then
            DEVICE_INDEX=$(echo "$RTL_OUTPUT" | grep "SN: $RTL_SDR_SERIAL_NUM" | grep -o '^[^:]*' | head -1)
            bashio::log.info "Found device with serial $RTL_SDR_SERIAL_NUM at index $DEVICE_INDEX"
        fi
    fi
fi

# Try the safest approach - let rtl_433 auto-detect
if ! $DEVICE_FOUND; then
    bashio::log.info "Using rtl_433 auto-detection..."
    DEVICE_INDEX=""
fi

bashio::log.blue "::::::::Starting rtl_433 with safe hardware access::::::::"

# Build rtl_433 command with error handling
RTL_CMD="rtl_433"
RTL_CMD="$RTL_CMD $FREQUENCY"
RTL_CMD="$RTL_CMD $PROTOCOL"
RTL_CMD="$RTL_CMD -C $UNITS"

# Add device specification only if we found one
if [ -n "$DEVICE_INDEX" ]; then
    RTL_CMD="$RTL_CMD -d $DEVICE_INDEX"
    bashio::log.info "Using device index: $DEVICE_INDEX"
else
    bashio::log.info "Using auto-detection (no -d parameter)"
fi

# Choose output method
if [ "$AUTO_DISCOVERY" = "true" ]; then
    bashio::log.info "Using JSON output for auto-discovery..."
    RTL_CMD="$RTL_CMD -F json -M time -M protocol"
    bashio::log.info "Command: $RTL_CMD"
    
    # Run with error handling and pipe to Python
    set +e  # Don't exit on error
    $RTL_CMD | python3 /scripts/rtl_433_mqtt_hass.py
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -ne 0 ]; then
        bashio::log.error "rtl_433 exited with code $EXIT_CODE"
        bashio::log.info "This might be due to hardware access issues"
        bashio::log.info "Try checking your RTL-SDR device connection"
    fi
    
else
    bashio::log.info "Using direct MQTT output..."
    # Use simplified MQTT format to avoid segfaults
    RTL_CMD="$RTL_CMD -F mqtt://$MQTT_HOST:$MQTT_PORT,user=$MQTT_USERNAME,pass=$MQTT_PASSWORD,events=$MQTT_TOPIC/events"
    RTL_CMD="$RTL_CMD -M time -M protocol"
    
    bashio::log.info "Command: $RTL_CMD"
    
    # Run with error handling
    set +e  # Don't exit on error
    $RTL_CMD
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -ne 0 ]; then
        bashio::log.error "rtl_433 exited with code $EXIT_CODE"
        bashio::log.info "This might be due to hardware access issues"
    fi
fi
