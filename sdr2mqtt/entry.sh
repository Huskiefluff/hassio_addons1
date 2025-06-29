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
PATH="/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"
export LD_LIBRARY_PATH=/usr/local/lib64:/usr/local/lib:/usr/lib64:/usr/lib

# Find rtl_433 binary
RTL_433_BIN=""
for path in /usr/local/bin/rtl_433 /usr/bin/rtl_433 /bin/rtl_433; do
    if [ -x "$path" ]; then
        RTL_433_BIN="$path"
        break
    fi
done

if [ -z "$RTL_433_BIN" ]; then
    bashio::log.error "rtl_433 binary not found!"
    bashio::log.info "Searching for rtl_433..."
    find / -name "rtl_433" -type f 2>/dev/null || true
    bashio::log.info "Available binaries in common locations:"
    ls -la /usr/local/bin/ /usr/bin/ /bin/ 2>/dev/null | grep rtl || true
    exit 1
fi

bashio::log.info "Found rtl_433 at: $RTL_433_BIN"

# Start the listener and enter an endless loop
bashio::log.blue "::::::::Starting RTL_433 with parameters::::::::"
bashio::log.info "RTL_433 Binary =" $RTL_433_BIN
bashio::log.info "MQTT Host =" $MQTT_HOST
bashio::log.info "MQTT port =" $MQTT_PORT
bashio::log.info "MQTT User =" $MQTT_USERNAME
bashio::log.info "MQTT Password =" $(echo $MQTT_PASSWORD | sha256sum | cut -f1 -d' ')
bashio::log.info "MQTT Topic =" $MQTT_TOPIC
bashio::log.info "MQTT Retain =" $MQTT_RETAIN
bashio::log.info "RTL-SDR Device Serial Number =" $RTL_SDR_SERIAL_NUM

# Check for rtl_sdr binary and get device index
RTL_SDR_BIN=""
for path in /usr/local/bin/rtl_sdr /usr/bin/rtl_sdr /bin/rtl_sdr; do
    if [ -x "$path" ]; then
        RTL_SDR_BIN="$path"
        break
    fi
done

if [ -n "$RTL_SDR_BIN" ]; then
    bashio::log.info "RTL-SDR Device Index =" $($RTL_SDR_BIN -d 9999 2>&1 | grep "SN: $RTL_SDR_SERIAL_NUM" | grep -o '^[^:]*' | sed 's/^[ \t]*//;s/[ \t]*$//' || echo "0")
else
    bashio::log.warning "rtl_sdr binary not found, using device index 0"
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

# Test rtl_433 before starting
bashio::log.info "Testing rtl_433 binary..."
$RTL_433_BIN -V || {
    bashio::log.error "rtl_433 binary test failed!"
    exit 1
}

bashio::log.blue "::::::::rtl_433 running output::::::::"

# Get device index more safely
DEVICE_INDEX="0"
if [ -n "$RTL_SDR_BIN" ]; then
    DEVICE_INDEX=$($RTL_SDR_BIN -d 9999 2>&1 | grep "SN: $RTL_SDR_SERIAL_NUM" | grep -o '^[^:]*' | sed 's/^[ \t]*//;s/[ \t]*$//' || echo "0")
fi

# Check if device is found
if [ -z "$DEVICE_INDEX" ] || [ "$DEVICE_INDEX" = "" ]; then
    bashio::log.info "Matching RTL-SDR Device with serial number \"$RTL_SDR_SERIAL_NUM\" not found, using device 0"
    DEVICE_INDEX="0"
else
    bashio::log.blue "Using RTL-SDR Device with serial number \"$RTL_SDR_SERIAL_NUM\" at index $DEVICE_INDEX"
fi

# Run rtl_433 with error handling
$RTL_433_BIN $FREQUENCY $PROTOCOL -C $UNITS -F mqtt://$MQTT_HOST:$MQTT_PORT,user=$MQTT_USERNAME,pass=$MQTT_PASSWORD,retain=$MQTT_RETAIN,events=$MQTT_TOPIC/events,states=$MQTT_TOPIC/states,devices=$MQTT_TOPIC[/model][/id][/channel:A] -M time:tz:local -M protocol -M level -d $DEVICE_INDEX | /scripts/rtl_433_mqtt_hass.py
