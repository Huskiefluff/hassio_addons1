#!/usr/bin/env python3
# coding=utf-8

"""MQTT Home Assistant auto discovery for rtl_433 events."""

from __future__ import print_function, with_statement

import json
import os
import sys
import time
import paho.mqtt.client as mqtt
import logging
from datetime import datetime

MQTT_HOST = os.environ['MQTT_HOST']
MQTT_PORT = os.environ['MQTT_PORT']
MQTT_USERNAME = os.environ['MQTT_USERNAME']
MQTT_PASSWORD = os.environ['MQTT_PASSWORD']
MQTT_TOPIC = os.environ['MQTT_TOPIC']
DISCOVERY_PREFIX = os.environ['DISCOVERY_PREFIX']
WHITELIST_ENABLE = os.environ['WHITELIST_ENABLE']
WHITELIST = os.environ['WHITELIST']
DISCOVERY_INTERVAL = os.environ['DISCOVERY_INTERVAL']
AUTO_DISCOVERY = os.environ['AUTO_DISCOVERY']
DEBUG = os.environ['DEBUG']
EXPIRE_AFTER = os.environ['EXPIRE_AFTER']
MQTT_RETAIN = os.environ['MQTT_RETAIN']

# Convert number environment variables to int
MQTT_PORT = int(MQTT_PORT)
DISCOVERY_INTERVAL = int(DISCOVERY_INTERVAL)

discovery_timeouts = {}
whitelist_list = WHITELIST.split()
blocked = []
rate_limited = {}

if DEBUG == "true":
    LOGLEVEL = os.environ.get('LOGLEVEL', 'DEBUG').upper()
else:
    LOGLEVEL = os.environ.get('LOGLEVEL', 'INFO').upper()

whitelist_on = (WHITELIST_ENABLE == "true")
auto_discovery = (AUTO_DISCOVERY == "true")

# Configure logging
logging.basicConfig(format='%(levelname)s:%(message)s', level=LOGLEVEL)

mappings = {
    "time": {
        "device_type": "sensor",
        "object_suffix": "last_seen",
        "config": {
            "device_class": "timestamp",
            "entity_category": "diagnostic",
            "name": "last_seen",
            "value_template": "{{ value }}"
        }
    },
    "freq": {
        "device_type": "sensor",
        "object_suffix": "freq",
        "config": {
            "device_class": "frequency",
            "entity_category": "diagnostic",
            "name": "frequency",
            "unit_of_measurement": "MHz",
            "value_template": "{{ value }}"
        }
    },
    "channel": {
        "device_type": "sensor",
        "object_suffix": "channel",
        "config": {
            "device_class": "enum",
            "name": "device_channel",
            "options": ["A", "B", "C"],
            "entity_category": "diagnostic",
            "value_template": "{{ value }}"
        }
    },
    "temperature_C": {
        "device_type": "sensor",
        "object_suffix": "T",
        "config": {
            "device_class": "temperature",
            "state_class": "measurement",
            "name": "Temperature",
            "unit_of_measurement": "°C",
            "value_template": "{{ value|float }}"
        }
    },
    "temperature_F": {
        "device_type": "sensor",
        "object_suffix": "F",
        "config": {
            "device_class": "temperature",
            "state_class": "measurement",
            "name": "Temperature",
            "unit_of_measurement": "°F",
            "value_template": "{{ value|float }}"
        }
    },
    "battery_ok": {
        "device_type": "sensor",
        "object_suffix": "B",
        "config": {
            "device_class": "battery",
            "name": "Battery",
            "unit_of_measurement": "%",
            "value_template": "{{ float(value) * 99 + 1 | int }}"
        }
    },
    "humidity": {
        "device_type": "sensor",
        "object_suffix": "H",
        "config": {
            "device_class": "humidity",
            "state_class": "measurement",
            "name": "Humidity",
            "unit_of_measurement": "%",
            "value_template": "{{ value|float }}"
        }
    },
    "moisture": {
        "device_type": "sensor",
        "object_suffix": "M",
        "config": {
            "device_class": "moisture",
            "state_class": "measurement",
            "name": "Moisture",
            "unit_of_measurement": "%",
            "value_template": "{{ value|float }}"
        }
    },
    "light_lux": {
        "device_type": "sensor",
        "object_suffix": "L",
        "config": {
            "device_class": "illuminance",
            "state_class": "measurement",
            "name": "Light Level",
            "unit_of_measurement": "lx",
            "value_template": "{{ value|int }}"
        }
    },
    "rssi": {
        "device_type": "sensor",
        "object_suffix": "rssi",
        "config": {
            "device_class": "signal_strength",
            "state_class": "measurement",
            "unit_of_measurement": "dB",
            "entity_category": "diagnostic",
            "value_template": "{{ value|float|round(2) }}"
        }
    }
}


def mqtt_connect(client, userdata, flags, rc):
    """Callback for MQTT connects."""
    logging.info("MQTT connected: " + mqtt.connack_string(rc))
    # CRITICAL FIX: Publish to the exact status topic that rtl_433 expects
    client.publish(f"{MQTT_TOPIC}/status", payload="online", qos=0, retain=True)
    if rc != 0:
        logging.critical("Could not connect. Error: " + str(rc))


def mqtt_disconnect(client, userdata, rc):
    """Callback for MQTT disconnects."""
    logging.critical("MQTT disconnected: " + mqtt.connack_string(rc))


def sanitize(text):
    """Sanitize a name for Graphite/MQTT use."""
    return (text
            .replace(" ", "_")
            .replace("/", "_")
            .replace(".", "_")
            .replace("&", "")
            .replace("-", "_"))


def publish_config(mqttc, topic, model, instance, channel, mapping):
    """Publish Home Assistant auto discovery data."""
    global discovery_timeouts

    device_type = mapping["device_type"]
    object_id = "_".join([sanitize(model), str(instance)])
    object_suffix = mapping["object_suffix"]

    path = "/".join([DISCOVERY_PREFIX, device_type, object_id, object_suffix, "config"])

    # check timeout
    now = time.time()
    if path in discovery_timeouts:
        if discovery_timeouts[path] > now:
            return

    discovery_timeouts[path] = now + DISCOVERY_INTERVAL

    config = mapping["config"].copy()
    
    # CRITICAL FIX: Use the exact state topic format that matches rtl_433 structure
    config["state_topic"] = f"{MQTT_TOPIC}/{sanitize(model)}/{instance}/{channel}/{topic}"
    config["name"] = f"{model} {instance} {mapping['config']['name']}"
    config["unique_id"] = f"rtl433_{device_type}_{instance}_{object_suffix}"
    # CRITICAL FIX: Point to the correct availability topic
    config["availability_topic"] = f"{MQTT_TOPIC}/status"
    config["payload_available"] = "online"
    config["payload_not_available"] = "offline"
    
    if int(EXPIRE_AFTER) > 0:
        config["expire_after"] = int(EXPIRE_AFTER)

    # Add Home Assistant device info
    if '-' in model:
        manufacturer, model_name = model.split("-", 1)
    else:
        manufacturer = 'RTL433'
        model_name = model

    device = {
        "identifiers": [f"rtl433_{instance}"],
        "name": f"{model} {instance}",
        "model": model_name,
        "manufacturer": manufacturer
    }
    config["device"] = device

    mqttc.publish(path, json.dumps(config), qos=0, retain=True)
    logging.debug(f"Published config to {path}")


def bridge_event_to_hass(mqttc, topic, data):
    """Translate rtl_433 sensor data to Home Assistant auto discovery."""

    if "model" not in data:
        logging.debug("Ignoring non-device event")
        return

    model = sanitize(data["model"])
    logging.info(f"Processing device: {model}")

    if "id" in data:
        instance = str(data["id"])
    else:
        instance = "0"

    if instance == "0":
        logging.warning(f"Device Id:{instance} doesn't appear to be a valid device. Skipping...")
        return

    if "channel" in data:
        channel = str(data["channel"])
    else:
        channel = 'A'

    device = f'{data["id"]}-{data["model"]}'

    if whitelist_on and (instance not in whitelist_list):
        if instance not in blocked:
            logging.info(f"Device Id:{data['id']} Model: {data['model']} not in whitelist.")
        blocked.append(str(data['id']))
        return

    # CRITICAL FIX: Publish to BOTH rtl_433 structure AND individual topics
    
    # 1. Publish to rtl_433 events topic (this fixes the rtl_433 section not updating)
    events_topic = f"{MQTT_TOPIC}/events"
    mqttc.publish(events_topic, json.dumps(data), qos=0, retain=False)
    
    # 2. Publish to rtl_433 states topic
    states_topic = f"{MQTT_TOPIC}/states"
    mqttc.publish(states_topic, json.dumps(data), qos=0, retain=True)
    
    # 3. Publish to device-specific topics (this is what rtl_433 normally does)
    device_base_topic = f"{MQTT_TOPIC}/{sanitize(model)}/{instance}/{channel}"
    mqttc.publish(device_base_topic, json.dumps(data), qos=0, retain=True)
    
    # 4. Publish individual sensor values to separate topics
    for key, value in data.items():
        if key in mappings:
            state_topic = f"{device_base_topic}/{key}"
            mqttc.publish(state_topic, str(value), qos=0, retain=True)
            logging.debug(f"Published {key}={value} to {state_topic}")
            
            # 5. Publish auto-discovery config if enabled
            if auto_discovery:
                publish_config(mqttc, key, model, instance, channel, mappings[key])

    logging.info(f"Published complete data for {model} {instance} to all required topics")


def rtl_433_bridge():
    """Run a MQTT Home Assistant auto discovery bridge for rtl_433."""
    
    mqttc = mqtt.Client(client_id="rtl433_bridge")
    mqttc.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
    mqttc.on_connect = mqtt_connect
    mqttc.on_disconnect = mqtt_disconnect

    # Set will message to mark as offline when disconnected
    mqttc.will_set(f"{MQTT_TOPIC}/status", payload="offline", qos=0, retain=True)
    
    try:
        mqttc.connect(MQTT_HOST, MQTT_PORT, 60)
        mqttc.loop_start()
        logging.info('MQTT Bridge Started - publishing to all required topics...')
        
        # Read from stdin (rtl_433 output)
        for line in sys.stdin:
            line = line.strip()
            if line:
                try:
                    # Parse JSON from rtl_433
                    data = json.loads(line)
                    bridge_event_to_hass(mqttc, "events", data)
                except json.JSONDecodeError:
                    logging.debug(f"Non-JSON line: {line}")
                except Exception as e:
                    logging.error(f"Error processing line: {e}")
                    
    except KeyboardInterrupt:
        logging.info("Shutting down...")
    except Exception as e:
        logging.error(f"Error in main loop: {e}")
    finally:
        mqttc.publish(f"{MQTT_TOPIC}/status", payload="offline", qos=0, retain=True)
        mqttc.loop_stop()
        mqttc.disconnect()


if __name__ == "__main__":
    rtl_433_bridge()
