#!/bin/sh
# Starts Mosquitto for deploy/docker-compose.yml: writes the password file for the one RIoT2
# account from RIOT2_MQTT_USERNAME and RIOT2_MQTT_PASSWORD, then runs the broker as PID 1.
set -eu

: "${RIOT2_MQTT_USERNAME:?RIOT2_MQTT_USERNAME is required}"
: "${RIOT2_MQTT_PASSWORD:?RIOT2_MQTT_PASSWORD is required}"

mkdir -p /mosquitto/auth
mosquitto_passwd -c -b /mosquitto/auth/password.txt "$RIOT2_MQTT_USERNAME" "$RIOT2_MQTT_PASSWORD"
# Mosquitto reads the file after dropping to its own user, and warns unless only it can read it.
chown -R mosquitto:mosquitto /mosquitto/auth
chmod 0700 /mosquitto/auth
chmod 0600 /mosquitto/auth/password.txt

exec mosquitto -c /mosquitto/config/mosquitto.conf
