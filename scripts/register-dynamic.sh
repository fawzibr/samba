#!/bin/sh

. "/container/scripts/ini-functions.include"

remove_line(){
	sed -i "/$1/d; /^[[:space:]]*$/d" "$DYNAMIC_REGISTRY"
}

register_directory(){
	local S_SOURCE="$1"
        local S_DIR=$(dirname "$S_SOURCE")
	local S_NAME=$(filename "$S_SOURCE")
	local S_TYPE=$(ini_get_key "$VOLUME_REGISTRY" "$S_NAME" "type")
	local S_CSUM=$(ini_get_key "$VOLUME_REGISTRY" "$S_NAME" "checksum")
	local S_TEMPLATE="$S_DIR/directory.template"
	local S_USR="nobody"
	local S_GRP="nogroup"
	local S_WRITABLE="no"
	local CURR_CSUM=$(cat "$S_TEMPLATE" 2> /dev/null | md5sum | cut -f 1 -d " ")
	# check if valid name
	if echo "$S_NAME" | grep -E "global|home|printers" > /dev/null; then
		# reserved section name
		return 1
	elif [ "$S_TYPE" = "static" ]; then
		# already registered as static
		return 1
	fi
	# check if already registered
	if ini_has_section "$VOLUME_REGISTRY" "$S_NAME"; then
		# check if checkums match
		if [ "$S_CSUM" = "$CURR_CSUM" ]; then
			# they match so no change, remove from delete list and return ok
			remove_line "$S_NAME"
			return 0
		fi
	fi
	# get directory information
        local S_SOURCE_STAT=$(stat -L "$S_SOURCE" -c "%A %G %U")
	S_USR=$(echo "$S_SOURCE_STAT" | cut -f 2 -d " ")
	S_GRP=$(echo "$S_SOURCE_STAT" | cut -f 3 -d " ")
	if echo "$S_SOURCE_STAT" | grep -E "^........w." > /dev/null; then
		S_WRITABLE="yes"
	elif echo "$S_SOURCE_STAT" | grep -E "^.....w...." > /dev/null && [ "$S_GRP" = "$SAMBA_DYNAMIC_GROUP" ]; then
		S_WRITABLE="yes"
	elif [ "$S_USR" = "$SAMBA_DYNAMIC_USER" ]; then
		S_WRITABLE="yes"
	fi
	# add to registry
	ini_set_key "$VOLUME_REGISTRY" "$S_NAME" "type" "dynamic"
	ini_set_key "$VOLUME_REGISTRY" "$S_NAME" "checksum" "$CURR_CSUM"
	# add to samba
	ini_set_key "$SAMBA_CONFIG" "$S_NAME" "path" "$S_SOURCE"
	ini_set_key "$SAMBA_CONFIG" "$S_NAME" "comment" "Share for $S_SOURCE in %L"
	ini_set_key "$SAMBA_CONFIG" "$S_NAME" "writeable" "$S_WRITABLE"
	# if templare exists add its keys
	if [ -f "$S_TEMPLATE"  ]; then
		# copy default keys (no section)
		ini_copy_section "$S_TEMPLATE" "" "$SAMBA_CONFIG" "$S_NAME" "path|comment|writeable|readable"
		# copy keys for name if found
		if ini_has_section "$S_TEMPLATE" "$S_NAME"; then
			ini_copy_section "$S_TEMPLATE" "$S_NAME" "$SAMBA_CONFIG" "$S_NAME" "path|comment|writeable|readable"
		fi
	fi
	# registered, remove from deleted list
	remove_line "$S_NAME"
	# set samba changed flag
	SAMBA_CONFIG_CHANGED="yes"
       	echo ">> DYNAMIC-VOLUMES: Register directory [$S_NAME]"
	ini_print_section "$SAMBA_CONFIG" "$S_NAME" | while IFS= read -r LINE; do
		echo "    $LINE"
	done
	#
	return 0
}


register_file(){
	local S_SOURCE="$1"
        local S_DIR=$(dirname "$S_SOURCE")
	local S_NAME=$(filename "$S_SOURCE")
	local S_EXT=$(extname "$S_SOURCE")
	local S_USR="nobody"
	local S_GRP="nogroup"
	local S_WRITABLE="no"
	local CURR_CSUM=$(cat "$S_SOURCE" 2> /dev/null | md5sum | cut -f 1 -d " ")
	# check if valid name
	if echo "$S_NAME" | grep -E "global|home|printers" > /dev/null; then
		# reserved section name
		return 1
	elif [ "$S_TYPE" = "static" ]; then
		# already registered as static
		return 1
	fi
	# read all sections in share file and add to samba
	ini_list_sections "$S_SOURCE" | while IFS= read -r S_SECTION; do
		local S_TYPE=$(ini_get_key "$VOLUME_REGISTRY" "$S_SECTION" "type")
		local S_PATH=$(ini_get_key "$S_SOURCE" "$S_SECTION" "path")
		local S_CSUM=$(ini_get_key "$VOLUME_REGISTRY" "$S_SECTION" "checksum")
	        # check if valid name
	        if echo "$S_SECTION" | grep -E "global|home|printers" > /dev/null; then
	        	echo ">> DYNAMIC-VOLUMES: Error adding directory [$S_SECTION], reserved name "
		elif [ "$S_TYPE" = "static" ]; then
	        	echo ">> DYNAMIC-VOLUMES: Error adding directory [$S_SECTION], already exists as static"
		elif df --output=source "$S_PATH" 2> /dev/null | tail -n 1 | grep -E "^\/$|^overlay$|^shm$" > /dev/null; then
	        	echo ">> DYNAMIC-VOLUMES: Error adding directory [$S_SECTION], path to internal file"
		elif [ "$S_CSUM" = "$CURR_CSUM" ]; then
			# checksum same, no change, remove from delete list and continue
			remove_line "$S_SECTION"
		else
			# add to registry
	                ini_set_key "$VOLUME_REGISTRY" "$S_SECTION" "type" "dynamic"
	                ini_set_key "$VOLUME_REGISTRY" "$S_SECTION" "checksum" "$CURR_CSUM"
			# add to samba
			ini_copy_section "$S_SOURCE" "$S_SECTION" "$SAMBA_CONFIG" "$S_SECTION" ""
			# registered, remove from deleted list
			remove_line "$S_SECTION"
			# set samba changed flag
			SAMBA_CONFIG_CHANGED="yes"
	        	echo ">> DYNAMIC-VOLUMES: Register directory [$S_SECTION] from $(basename $S_SOURCE)"
			ini_print_section "$SAMBA_CONFIG" "$S_NAME" | while IFS= read -r LINE; do
				echo "    $LINE"
			done
		fi
	done
	return 0
}

############################
# MAIN
############################

# variables

VOLUME_DIR="/dynamic-volumes"
VOLUME_REGISTRY="/tmp/volumes.ini"
DYNAMIC_REGISTRY="/tmp/dynamic-shares.txt"
SAMBA_CONFIG="/etc/samba/smb.conf"
SAMBA_CONFIG_CHANGED=""

# save dynamic share names

echo "" > "$DYNAMIC_REGISTRY"
ini_list_sections "$VOLUME_REGISTRY" | while IFS= read -r S_SECTION; do
	S_TYPE=$(ini_get_key "$VOLUME_REGISTRY" "$S_NAME" "type")
	if [ "$S_TYPE" = "dynamic" ]; then
		echo "$S_SECTION" >> "$DYNAMIC_REGISTRY"
	fi
done

# register dynamic volumes

for S_NAME in $(find "$VOLUME_DIR" -mindepth 1 -maxdepth 1 -type f -name "*.share" -o -type d); do
	if [ -d "$S_NAME" ]; then
		register_directory "$S_NAME"
	else
		register_file "$S_NAME"
	fi
done

# remove inactive shares

for S_NAME in $(cat "$DYNAMIC_REGISTRY"); do
       	echo ">> DYNAMIC-VOLUMES: Unregister directory $S_NAME"
	# remove from samba
	ini_del_section "$SAMBA_CONFIG" "$S_NAME"
	# remove from registry
	ini_del_section "$VOLUME_REGISTRY" "$S_NAME"
done

# reload samba if needed

if [ -z "$SAMBA_CONFIG_CHANGED" ]; then
        : # do nothing, smb.conf not changed
elif ! which smbcontrol > /dev/null; then
        echo ">> DYNAMIC-VOLUMES: Samba configuration changed, smbcontrol missing!!"
elif ! smbcontrol all reload-config; then
        echo ">> DYNAMIC-VOLUMES: Samba configuration changed, error reloading!!"
else
        echo ">> DYNAMIC-VOLUMES: Samba configuration changed, reload"
fi
