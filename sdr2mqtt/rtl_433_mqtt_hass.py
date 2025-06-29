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
import threading

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

# Global MQTT client for availability updates
mqtt_client = None

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


def keep_alive():
    """Keep availability status alive by periodically publishing online status."""
    global mqtt_client
    while mqtt_client and mqtt_client.is_connected():
        try:
            mqtt_client.publish(f"{MQTT_TOPIC}/status", payload="online", qos=0, retain=True)
            logging.debug("Published keep-alive status")
            time.sleep(30)  # Publish every 30 seconds
        except:
            break


def mqtt_connect(client, userdata, flags, rc):
    """Callback for MQTT connects."""
    global mqtt_client
    logging.info("MQTT connected: " + mqtt.connack_string(rc))
    
    # Publish online status immediately
    client.publish(f"{MQTT_TOPIC}/status", payload="online", qos=0, retain=True)
    
    if rc != 0:
        logging.critical("Could not connect. Error: " + str(rc))
    else:
        # Start keep-alive thread
        keep_alive_thread = threading.Thread(target=keep_alive, daemon=True)
        keep_alive_thread.start()


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
    
    # Use proper state topic format
    config["state_topic"] = f"{MQTT_TOPIC}/{sanitize(model)}/{instance}/{channel}/{topic}"
    config["name"] = f"{model} {instance} {mapping['config']['name']}"
    config["unique_id"] = f"rtl433_{device_type}_{instance}_{object_suffix}"
    
    # CRITICAL FIX: Configure availability properly
    config["availability_topic"] = f"{MQTT_TOPIC}/status"
    config["payload_available"] = "online"
    config["payload_not_available"] = "offline"
    
    # CRITICAL FIX: Handle expire_after properly
    expire_after_val = int(EXPIRE_AFTER)
    if expire_after_val > 0:
        # Set expire_after to a reasonable value (not too short)
        config["expire_after"] = max(expire_after_val, 300)  # Minimum 5 minutes
        logging.debug(f"Set expire_after to {config['expire_after']} seconds")
    else:
        # Don't set expire_after if it's 0 or disabled
        logging.debug("expire_after disabled")

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

    # Ensure we have a current online status
    mqttc.publish(f"{MQTT_TOPIC}/status", payload="online", qos=0, retain=True)

    # Publish to multiple MQTT topics for compatibility
    
    # 1. Publish to rtl_433 events topic
    events_topic = f"{MQTT_TOPIC}/events"
    mqttc.publish(events_topic, json.dumps(data), qos=0, retain=False)
    
    # 2. Publish to rtl_433 states topic
    states_topic = f"{MQTT_TOPIC}/states"
    mqttc.publish(states_topic, json.dumps(data), qos=0, retain=True)
    
    # 3. Publish to device-specific topics
    device_base_topic = f"{MQTT_TOPIC}/{sanitize(model)}/{instance}/{channel}"
    mqttc.publish(device_base_topic, json.dumps(data), qos=0, retain=True)
    
    # 4. Publish individual sensor values
    for key, value in data.items():
        if key in mappings:
            state_topic = f"{device_base_topic}/{key}"
            mqttc.publish(state_topic, str(value), qos=0, retain=True)
            logging.debug(f"Published {key}={value} to {state_topic}")
            
            # 5. Publish auto-discovery config if enabled
            if auto_discovery:
                publish_config(mqttc, key, model, instance, channel, mappings[key])

    logging.info(f"Published complete data for {model} {instance}")


def rtl_433_bridge():
    """Run a MQTT Home Assistant auto discovery bridge for rtl_433."""
    global mqtt_client
    
    mqtt_client = mqtt.Client(client_id="rtl433_bridge")
    mqtt_client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
    mqtt_client.on_connect = mqtt_connect
    mqtt_client.on_disconnect = mqtt_disconnect

    # Set will message to mark as offline when disconnected
    mqtt_client.will_set(f"{MQTT_TOPIC}/status", payload="offline", qos=0, retain=True)
    
    try:
        mqtt_client.connect(MQTT_HOST, MQTT_PORT, 60)
        mqtt_client.loop_start()
        logging.info('MQTT Bridge Started with stable availability...')
        
        # Read from stdin (rtl_433 output)
        for line in sys.stdin:
            line = line.strip()
            if line:
                try:
                    # Parse JSON from rtl_433
                    data = json.loads(line)
                    bridge_event_to_hass(mqtt_client, "events", data)
                except json.JSONDecodeError:
                    logging.debug(f"Non-JSON line: {line}")
                except Exception as e:
                    logging.error(f"Error processing line: {e}")
                    
    except KeyboardInterrupt:
        logging.info("Shutting down...")
    except Exception as e:
        logging.error(f"Error in main loop: {e}")
    finally:
        if mqtt_client:
            mqtt_client.publish(f"{MQTT_TOPIC}/status", payload="offline", qos=0, retain=True)
            mqtt_client.loop_stop()
            mqtt_client.disconnect()


if __name__ == "__main__":
    rtl_433_bridge()
