#!/usr/bin/bashio
CONFIG_PATH=/data/options.json

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

# Exit immediately if a command exits with a non-zero status:
set -e

export LANG=C
export PATH="/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"
export LD_LIBRARY_PATH="/usr/local/lib:/usr/local/lib64:/usr/lib:/lib"

# Start the listener and enter an endless loop
bashio::log.blue "::::::::Starting RTL_433 with parameters::::::::"
bashio::log.info "MQTT Host =" $MQTT_HOST
bashio::log.info "MQTT port =" $MQTT_PORT
bashio::log.info "MQTT User =" $MQTT_USERNAME
bashio::log.info "MQTT Password =" $(echo $MQTT_PASSWORD | sha256sum | cut -f1 -d' ')
bashio::log.info "MQTT Topic =" $MQTT_TOPIC
bashio::log.info "MQTT Retain =" $MQTT_RETAIN
bashio::log.info "RTL-SDR Device Serial Number =" $RTL_SDR_SERIAL_NUM

# Check if rtl_433 exists and test it
if ! command -v rtl_433 >/dev/null 2>&1; then
    bashio::log.error "rtl_433 command not found!"
    exit 1
fi

# Test rtl_433 functionality (ignore version display issues)
bashio::log.info "Testing rtl_433 functionality..."
if rtl_433 -h > /dev/null 2>&1; then
    bashio::log.info "rtl_433 is functional"
else
    bashio::log.error "rtl_433 is not working properly"
    exit 1
fi

# Show version (may show NOTFOUND but that's OK)
bashio::log.info "RTL_433 Version:" 
rtl_433 -V 2>/dev/null || bashio::log.info "Version info has display issues but rtl_433 is working"

# Check for protocol 278
bashio::log.info "Checking for Protocol 278 (Homelead HG9901)..."
if rtl_433 -R help | grep -q "278"; then
    bashio::log.info "✓ Protocol 278 (Homelead HG9901) is available!"
    bashio::log.info "Protocol 278 details:"
    rtl_433 -R help | grep "278"
else
    bashio::log.warning "⚠ Protocol 278 may not be available"
fi

# Get device index - simplified approach
DEVICE_INDEX="0"
if command -v rtl_sdr >/dev/null 2>&1; then
    RTL_SDR_OUTPUT=$(rtl_sdr -d 9999 2>&1 || true)
    if echo "$RTL_SDR_OUTPUT" | grep -q "SN: $RTL_SDR_SERIAL_NUM"; then
        DEVICE_INDEX=$(echo "$RTL_SDR_OUTPUT" | grep "SN: $RTL_SDR_SERIAL_NUM" | grep -o '^[^:]*' | sed 's/^[ \t]*//;s/[ \t]*$//' || echo "0")
        bashio::log.info "RTL-SDR Device Index =" $DEVICE_INDEX
    else
        bashio::log.info "RTL-SDR Device with serial $RTL_SDR_SERIAL_NUM not found, using device 0"
    fi
else
    bashio::log.info "rtl_sdr not available, using device index 0"
fi

bashio::log.info "PROTOCOL =" $PROTOCOL
bashio::log.info "FREQUENCY =" $FREQUENCY
bashio::log.info "Whitelist Enabled =" $WHITELIST_ENABLE
bashio::log.info "Whitelist =" $WHITELIST
bashio::log.info "Expire After =" $EXPIRE_AFTER
bashio::log.info "UNITS =" $UNITS
bashio::log.info "DISCOVERY_PREFIX =" $DISCOVERY_PREFIX
bashio::log.info "DISCOVERY_INTERVAL =" $DISCOVERY_INTERVAL
bashio::log.info "AUTO_DISCOVERY =" $AUTO_DISCOVERY
bashio::log.info "DEBUG =" $DEBUG

# Test basic rtl_433 operation first
bashio::log.info "Testing basic rtl_433 operation..."
timeout 5 rtl_433 $FREQUENCY $PROTOCOL -C $UNITS -d $DEVICE_INDEX -T 1 > /dev/null 2>&1 || \
bashio::log.warning "Basic test completed (timeout/error expected)"

bashio::log.blue "::::::::rtl_433 running output::::::::"

# Choose output method based on auto_discovery setting
if [ "$AUTO_DISCOVERY" = "true" ]; then
    bashio::log.info "Starting rtl_433 with JSON output for Home Assistant auto-discovery..."
    
    # Use JSON output only and pipe to Python script for auto-discovery
    rtl_433 \
        $FREQUENCY \
        $PROTOCOL \
        -C $UNITS \
        -F json \
        -M time:tz:local \
        -M protocol \
        -M level \
        -d $DEVICE_INDEX | \
    python3 /scripts/rtl_433_mqtt_hass.py
    
else
    bashio::log.info "Starting rtl_433 with direct MQTT output (no auto-discovery)..."
    
    # Use direct MQTT output only (no Python script needed)
    rtl_433 \
        $FREQUENCY \
        $PROTOCOL \
        -C $UNITS \
        -F mqtt://$MQTT_HOST:$MQTT_PORT,user=$MQTT_USERNAME,pass=$MQTT_PASSWORD,retain=$MQTT_RETAIN,events=$MQTT_TOPIC/events,states=$MQTT_TOPIC/states,devices=$MQTT_TOPIC[/model][/id][/channel:A] \
        -M time:tz:local \
        -M protocol \
        -M level \
        -d $DEVICE_INDEX
fi
