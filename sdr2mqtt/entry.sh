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
export PATH="/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"

bashio::log.info "=== RTL_433 Diagnostic Mode ==="
bashio::log.info "Protocol: $PROTOCOL"
bashio::log.info "Frequency: $FREQUENCY"

# Test 1: Basic help
bashio::log.info "Test 1: Basic help command"
if rtl_433 -h > /dev/null 2>&1; then
    bashio::log.info "✓ Help command works"
else
    bashio::log.error "✗ Help command failed"
    exit 1
fi

# Test 2: Version check
bashio::log.info "Test 2: Version check"
rtl_433 -V || bashio::log.info "Version check completed"

# Test 3: List devices (no RTL-SDR access)
bashio::log.info "Test 3: List available protocols"
rtl_433 -R help | head -5

# Test 4: Test without RTL-SDR device
bashio::log.info "Test 4: Test with file input (no hardware)"
echo '{"test": "data"}' > /tmp/test.json
if timeout 3 rtl_433 -r /tmp/test.json -F json 2>/dev/null; then
    bashio::log.info "✓ File input works"
else
    bashio::log.info "File input test completed"
fi

# Test 5: Very basic RTL-SDR test
bashio::log.info "Test 5: Basic RTL-SDR detection"
if timeout 5 rtl_433 -d 0 -T 1 2>/dev/null; then
    bashio::log.info "✓ RTL-SDR basic test passed"
else
    bashio::log.warning "RTL-SDR basic test failed or timed out"
fi

# Test 6: JSON output only (no MQTT)
bashio::log.info "Test 6: JSON output test (5 seconds)"
timeout 5 rtl_433 $FREQUENCY $PROTOCOL -C $UNITS -F json -d 0 || \
bashio::log.info "JSON test completed"

# Test 7: Test individual components of MQTT command
bashio::log.info "Test 7: Testing MQTT parameters"
bashio::log.info "MQTT Host: $MQTT_HOST"
bashio::log.info "MQTT Port: $MQTT_PORT"
bashio::log.info "MQTT User: $MQTT_USERNAME"
bashio::log.info "MQTT Topic: $MQTT_TOPIC"

# Test 8: Simple MQTT test (if previous tests pass)
bashio::log.info "Test 8: Simple MQTT connection test"
SIMPLE_MQTT="mqtt://$MQTT_HOST:$MQTT_PORT,user=$MQTT_USERNAME,pass=$MQTT_PASSWORD"
bashio::log.info "Testing: rtl_433 -F $SIMPLE_MQTT -T 1"
timeout 3 rtl_433 -F "$SIMPLE_MQTT" -T 1 -d 0 2>/dev/null || \
bashio::log.info "Simple MQTT test completed"

# Test 9: If all else fails, try without device selection
bashio::log.info "Test 9: Try without device specification"
timeout 3 rtl_433 $FREQUENCY $PROTOCOL -F json -T 1 2>/dev/null || \
bashio::log.info "No device test completed"

bashio::log.info "=== Diagnostic completed ==="
bashio::log.info "If all tests passed, the issue may be with the complex MQTT format or long-running operation"

# Final attempt with simpler MQTT format
bashio::log.info "Final test: Simplified MQTT format"
rtl_433 $FREQUENCY $PROTOCOL -C $UNITS -F "mqtt://$MQTT_HOST:$MQTT_PORT,user=$MQTT_USERNAME,pass=$MQTT_PASSWORD,events=$MQTT_TOPIC/events" -d 0
