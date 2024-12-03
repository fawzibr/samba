#!/bin/sh

############################
# FILENAME FUNCTIONS
############################

filename(){
        local FILENAME=$(basename "$1")
        echo "${FILENAME%.*}"
}

extname(){
        local FILENAME=$(basename "$1")
        local EXTNAME="${FILENAME##*.}"
        #
        if [ "$FILENAME" = "$EXTNAME" ]; then
                echo ""
        else
                echo "$EXTNAME"
        fi
}

############################
# INI FUNCTIONS
############################

ini_list_sections(){
	local SOURCE="$1"
	crudini --get --ini-options=ignoreindent "$SOURCE"
}

ini_del_section(){
	local SOURCE="$1"
	local SECTION="$2"
	crudini --del --ini-options=ignoreindent,tidy "$SOURCE" "$SECTION"
}

ini_list_keys(){
	local SOURCE="$1"
	local SECTION="$2"
	crudini --get --ini-options=ignoreindent "$SOURCE" "$SECTION"
}

ini_get_key(){
	local SOURCE="$1"
	local SECTION="$2"
	local KEY="$3"
	local DEF="$4"
	#
	if ! crudini --get --ini-options=ignoreindent "$SOURCE" "$SECTION" "$KEY" 2> /dev/null;	then
		echo "$DEF"
	fi
}

ini_set_key(){
	local SOURCE="$1"
	local SECTION="$2"
	local KEY="$3"
	local VALUE="$4"
	#
	crudini --set --ini-options=ignoreindent "$SOURCE" "$SECTION" "$KEY" "$VALUE"
}

ini_del_key(){
	local SOURCE="$1"
	local SECTION="$2"
	local KEY="$3"
	local VALUE="$4"
	#
	crudini --del --ini-options=ignoreindent,tidy "$SOURCE" "$SECTION" "$KEY"
}

ini_copy_section(){
	local FROM_FILE="$1"
	local FROM_SECTION="$2"
	local TO_FILE="$3"
	local TO_SECTION="$4"
	local EXCLUDE="$5"
	#
	if [ -f "$FROM_FILE" ] && [ -z "$EXCLUDE" ]; then
		ini_list_keys "$FROM_FILE" "$FROM_SECTION" | while IFS= read -r KEY ; do
			VALUE=$(ini_get_key "$FROM_FILE" "$FROM_SECTION" "$KEY")
			ini_set_key "$TO_FILE" "$TO_SECTION" "$KEY" "$VALUE"
			echo "  $KEY=$VALUE"
		done
	elif [ -f "$FROM_FILE" ]; then
		ini_list_keys "$FROM_FILE" "$FROM_SECTION" | grep -v -E "$EXCLUDE" | while IFS= read -r KEY ; do
			VALUE=$(ini_get_key "$FROM_FILE" "$FROM_SECTION" "$KEY")
			ini_set_key "$TO_FILE" "$TO_SECTION" "$KEY" "$VALUE"
			echo "  $KEY=$VALUE"
		done
	fi
}

############################
# VOLUME FUNCTIONS
############################

volume_register(){
	local VOLUME_FILE="$1"
	local S_CONFIG="$2"
	local S_SOURCE="$3"
        local S_DIR=$(dirname "$S_SOURCE")
	local S_NAME=$(filename "$S_SOURCE")
	local S_EXT=$(extname "$S_SOURCE")
	local S_TYPE=$(ini_get_key "$VOLUME_FILE" "$S_NAME" "type")
	local S_USR="nobody"
	local S_GRP="nogroup"
	local S_WRITABLE="no"
	# check if valid name
	if echo "$S_NAME" | grep -E "global|home|printers" > /dev/null; then
		# reserved section name
		return 1
	elif [ "$S_TYPE" = "static" ]; then
		# already registered as static
		return 1
	fi
	# get volume type
	if [ -z "$S_TYPE" ] && ini_list_sections "$S_CONFIG" | grep "$S_NAME" > /dev/null; then
		local S_PATH=$(ini_get_key "$S_CONFIG" "$S_NAME" "path")
		local S_TEMPLATE=""
		local S_TYPE="static"
        elif [ -f "$S_SOURCE" ] && [ "$S_EXT" = "share" ]; then
		local S_PATH=$(ini_get_key "$S_SOURCE" "" "path")
		local S_TEMPLATE="$S_SOURCE"
		local S_TYPE="file"
        elif [ -d "$S_SOURCE" ] && [ -f "$S_DIR/$S_NAME.template" ] ; then
		local S_PATH="$S_SOURCE"
		local S_TEMPLATE="$S_DIR/$S_NAME.template"
		local S_TYPE="directory"
        elif [ -d "$S_SOURCE" ] && [ -f "$S_DIR/default.template" ] ; then
		local S_PATH="$S_SOURCE"
		local S_TEMPLATE="$S_DIR/default.template"
		local S_TYPE="directory"
	else
		return 1
        fi
	# get path information
	if [ -d "$S_PATH" ]; then
	        local S_PATH_STAT=$(stat -L "$S_PATH" -c "%A %G %U")
		S_USR=$(echo "$S_PATH_STAT" | cut -f 2 -d " ")
		S_GRP=$(echo "$S_PATH_STAT" | cut -f 3 -d " ")
		if echo "$S_PATH_STAT" | grep -E "^........w." > /dev/null; then
			S_WRITABLE="yes"
		elif echo "$S_PATH_STAT" | grep -E "^.....w...." > /dev/null && [ "$S_GRP" = "$SAMBA_DYNAMIC_GROUP" ]; then
			S_WRITABLE="yes"
		elif [ "$S_USR" = "$SAMBA_DYNAMIC_USER" ]; then
			S_WRITABLE="yes"
		fi
	fi
	# check if user/group/writeable changed
	local S_USR_PREV=$(ini_get_key "$VOLUME_FILE" "$S_NAME" "user")
	local S_GRP_PREV=$(ini_get_key "$VOLUME_FILE" "$S_NAME" "group")
	local S_WRITABLE_PREV=$(ini_get_key "$VOLUME_FILE" "$S_NAME" "writeable")
	if [ "$S_USR" = "$S_USR_PREV" ] && [ "$S_GRP" = "$S_GRP_PREV" ] && [ "$S_WRITABLE" = "$S_WRITABLE_PREV" ]; then
		return 1
	fi
	# add to volume registry
	echo ">> VOLUMES: Add to registry $S_NAME ($S_TYPE)"
	ini_set_key "$VOLUME_FILE" "$S_NAME" "path" "$S_PATH"
	ini_set_key "$VOLUME_FILE" "$S_NAME" "type" "$S_TYPE"
	ini_set_key "$VOLUME_FILE" "$S_NAME" "template" "$S_TEMPLATE"
	ini_set_key "$VOLUME_FILE" "$S_NAME" "user" "$S_USR"
	ini_set_key "$VOLUME_FILE" "$S_NAME" "group" "$S_GRP"
	ini_set_key "$VOLUME_FILE" "$S_NAME" "writeable" "$S_WRITABLE"
	ini_set_key "$VOLUME_FILE" "$S_NAME" "checksum" $([ -f "$S_TEMPLATE" ] && md5sum "$S_TEMPLATE" | cut -f 1 -d " ")
	# add to smb.conf
	if [ "$S_TYPE" = "file" ]; then
		echo ">> VOLUMES: Add to samba $S_NAME ($S_TYPE)"
		ini_copy_section "$S_TEMPLATE" "" "$S_CONFIG" "$S_NAME"
	elif [ "$S_TYPE" = "directory" ]; then
		echo ">> VOLUMES: Add to samba $S_NAME ($S_TYPE)"
		ini_set_key "$S_CONFIG" "$S_NAME" "path" "$S_PATH"
		ini_set_key "$S_CONFIG" "$S_NAME" "comment" "Share for $S_PATH in %L"
		ini_set_key "$S_CONFIG" "$S_NAME" "writeable" "$S_WRITABLE"
		ini_copy_section "$S_TEMPLATE" "" "$S_CONFIG" "$S_NAME" "path|comment|writeable|readable"
	fi
	return 0
}

volume_unregister(){
	local VOLUME_FILE="$1"
	local S_CONFIG="$2"
	local S_SOURCE="$3"
	local S_NAME=$(filename "$S_SOURCE")
	local S_TYPE=$(ini_get_key "$VOLUME_FILE" "$S_NAME" "type")
	local S_PATH=$(ini_get_key "$VOLUME_FILE" "$S_NAME" "path")
	local S_TEMPLATE=$(ini_get_key "$VOLUME_FILE" "$S_NAME" "template")
	# check if valid name and type
	if echo "$S_NAME" | grep -E "global|home|printers"; then
		# reserved section name
		return 1
	elif [ -z "$S_TYPE" ]; then
		# missing in volume dile,leave
		return 1
	elif [ "$S_TYPE" = "static" ]; then
		# registered as static, leave
		return 1
	elif [ "$S_TYPE" = "file" ] && [ -f "$S_TEMPLATE" ]; then
		# file share, and template exists, leave
		return 1
	elif [ "$S_TYPE" = "directory" ] && [ -d "$S_PATH" ]; then
		# directory share, and directory exists, leave
		return 1
	else
		echo ">> VOLUMES: Disconnect users from $S_NAME ($S_TYPE)"
		smbcontrol close-share "$S_NAME"
		# delete from smb.conf
		echo ">> VOLUMES: Remove from samba $S_NAME ($S_TYPE)"
	 	ini_del_section "$S_CONFIG" "$S_NAME"
		# delete from volume registry
		echo ">> VOLUMES: Remove from registry $S_NAME ($S_TYPE)"
	 	ini_del_section "$VOLUME_FILE" "$S_NAME"
		return 0
	fi
}

############################
# MAIN
############################

# variables

VOLUME_DIR="/dynamic-volumes"
VOLUME_REGISTRY="/tmp/volumes.ini"
SAMBA_CONFIG="/etc/samba/smb.conf"
SAMBA_CONFIG_CHANGED=""

# register static

for S_NAME in $(ini_list_sections "$SAMBA_CONFIG"); do
	if volume_register "$VOLUME_REGISTRY" "$SAMBA_CONFIG" "$S_NAME"; then
		SAMBA_CONFIG_CHANGED="true"
	fi
done

# register dynamic

for S_NAME in $(find "$VOLUME_DIR" -mindepth 1 -maxdepth 1 -type f -name "*.share" -o -type d); do
	if volume_register "$VOLUME_REGISTRY" "$SAMBA_CONFIG" "$S_NAME"; then
		SAMBA_CONFIG_CHANGED="true"
	fi
done

# unregister missing

for S_NAME in $(ini_list_sections "$VOLUME_REGISTRY"); do
	if volume_unregister "$VOLUME_REGISTRY" "$SAMBA_CONFIG" "$S_NAME"; then
		SAMBA_CONFIG_CHANGED="true"
	fi
done

# reload if smb.conf changed

if [ -z "$SAMBA_CONFIG_CHANGED" ]; then
        : # do nothing, smb.conf not changed
elif ! which smbcontrol > /dev/null; then
        : # do nothing, smb.conf not changed
elif ! smbcontrol all reload-config; then
        echo ">> VOLUMES: Failed to reload samba configuration"
else
        echo ">> VOLUMES: Reload samba configuration"
fi
