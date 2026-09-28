#!/bin/sh

. "/container/scripts/ini-functions.include"

############################
# MAIN
############################

# variables

VOLUME_REGISTRY="/tmp/volumes.ini"
DYNAMIC_REGISTRY="/tmp/dynamic-shares.txt"
SAMBA_CONFIG="/etc/samba/smb.conf"

# create files

touch "$VOLUME_REGISTRY"
touch "$DYNAMIC_REGISTRY"

# register static volumes, only runs on start

ini_list_sections "$SAMBA_CONFIG" | while IFS= read -r S_NAME; do
	# check if valid name
	if echo "$S_NAME" | grep -E "global|home|printers" > /dev/null; then
		# reserved section name
		continue
	else
		echo ">> DYNAMIC-VOLUMES: Register static directory [$S_NAME]"
		ini_set_key "$VOLUME_REGISTRY" "$S_NAME" "type" "static"
	fi
done
