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
export LD_LIBRARY_PATH=/usr/local/lib64

# Start the listener and enter an endless loop
bashio::log.blue "::::::::Starting RTL_433 with parameters::::::::"
bashio::log.info "MQTT Host =" $MQTT_HOST
bashio::log.info "MQTT port =" $MQTT_PORT
bashio::log.info "MQTT User =" $MQTT_USERNAME
bashio::log.info "MQTT Password =" $(echo $MQTT_PASSWORD | sha256sum | cut -f1 -d' ')
bashio::log.info "MQTT Topic =" $MQTT_TOPIC
bashio::log.info "MQTT Retain =" $MQTT_RETAIN
bashio::log.info "RTL-SDR Device Serial Number =" $RTL_SDR_SERIAL_NUM
bashio::log.info "RTL-SDR Device Index =" $(rtl_sdr -d 9999 |& grep "SN: $RTL_SDR_SERIAL_NUM" |& grep -o '^[^:]*' | sed 's/^[ \t]*//;s/[ \t]*$//')
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
bashio::log.blue "::::::::rtl_433 running output::::::::"

# Check if device is found
if [ -z "$(rtl_sdr -d 9999 |& grep "SN: $RTL_SDR_SERIAL_NUM" |& grep -o '^[^:]*' | sed 's/^[ \t]*//;s/[ \t]*$//')" ]
then
      bashio::log.info "Matching RTL-SDR Device with serial number \"$RTL_SDR_SERIAL_NUM\" not found"
else
      bashio::log.blue "Using RTL-SDR Device with serial number \"$RTL_SDR_SERIAL_NUM\" at index $(rtl_sdr -d 9999 |& grep "SN: $RTL_SDR_SERIAL_NUM" |& grep -o '^[^:]*' | sed 's/^[ \t]*//;s/[ \t]*$//')"
fi

rtl_433 git:feat-hg9901 $FREQUENCY $PROTOCOL -C $UNITS  -F mqtt://$MQTT_HOST:$MQTT_PORT,user=$MQTT_USERNAME,pass=$MQTT_PASSWORD,retain=$MQTT_RETAIN,events=$MQTT_TOPIC/events,states=$MQTT_TOPIC/states,devices=$MQTT_TOPIC[/model][/id][/channel:A]  -M time:tz:local -M protocol -M level -d $(rtl_sdr -d 9999 |& grep "SN: $RTL_SDR_SERIAL_NUM" |& grep -o '^[^:]*' | sed 's/^[ \t]*//;s/[ \t]*$//') | /scripts/rtl_433_mqtt_hass.py
