#!/bin/sh

############################
# FUNCTIONS
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

is_writable(){
        # $1=ITEM
        # $2=GROUP
        # $3=USER
        local ITEM_STAT=$(stat -L "$1" -c "%A %G %U")
        local ITEM_GRP=$(echo "$ITEM_STAT" | cut -f 2 -d " ")
        local ITEM_USR=$(echo "$ITEM_STAT" | cut -f 3 -d " ")
        #
        if echo "$ITEM_STAT" | grep -E "^........w." > /dev/null; then
                # writable by everyone
                return 0
        elif echo "$ITEM_STAT" | grep -E "^.....w...." > /dev/null && groups "$3" | grep -E "\s$ITEM_GRP(\s|$)" > /dev/null; then
                # writable by group and user member of group
                return 0
        elif [ "$3" = "$ITEM_USR" ]; then
                # check if owner is user
                return 0
        else
                # not writable
                return 1
        fi
}

register_share_type(){
        # $1=JSON FILE
	# $2=SHARE_NAME
        # $3=SHARE TYPE
        # $4=SHARE PATH
	# $5=CHECKSUM

        # file missing, create it
        if [ ! -f "$1" ]; then
                echo "{}" > "$1"
        fi
	# get path information
	if [ -d "$4" ]; then
	        local ITEM_STAT=$(stat -L "$4" -c "%A %G %U")
	        local ITEM_GRP=$(echo "$ITEM_STAT" | cut -f 2 -d " ")
	        local ITEM_USR=$(echo "$ITEM_STAT" | cut -f 3 -d " ")
		echo "$ITEM_STAT" | grep -E "^........w." > /dev/null && local ITEM_OTH_WRITE="true"
        	echo "$ITEM_STAT" | grep -E "^.....w...." > /dev/null && local ITEM_GRP_WRITE="true"
	fi
        # add share type
        local JSON=$(cat "$1")
        echo "$JSON" | jq \
		--arg n "$2" \
		--arg t "$3" \
		--arg p "$4" \
		--arg c "$5" \
		--arg u "$ITEM_USR" \
		--arg g "$ITEM_GRP" \
		--arg ow "$ITEM_OTH_WRITE" \
		--arg gw "$ITEM_GRP_WRITE" \
		'. += { $n: { "path":$p,"type":$t,"uid":$u,"gid":$g,"group_write":$gw,"other_write":$ow,"checksum":$c  } }' > "$1"
}

unregister_share_type(){
        # $1=JSON FILE
        # $2=SHARE PATH
        if [ -f "$1" ]; then
                JSON=$(cat "$1")
		SHARE_NAME=$(filename $2)
                echo "$JSON" |  jq "del(.[\"$SHARE_NAME\"])" > "$1"
        fi
}

get_share_info(){
	local VOL_REG=$1
	local S_NAME=$2
	local S_FIELD=$3
        # file missing, create it
        if [ ! -f "$VOL_REG" ]; then
                echo "{}" > "$VOL_REG"
        fi
        # get share type
        jq -r --arg n "$S_NAME" --arg f "$S_FIELD" '.[$n][$f]' "$VOL_REG" | grep -v -E "null"
}

copy_keys(){
	# $1=SAMBA_CONFIG
	# $2=SOURCE
	# $3=SHARE NAME
	# $4=EXCLUDES

	if [ -z "$4" ]; then
		crudini --get --ini-options=ignoreindent "$2" "" | while IFS= read -r KEY ; do
			VALUE=$(crudini --get --ini-options=ignoreindent "$2" "" "$KEY")
			echo "  $KEY=$VALUE"
			crudini --set --ini-options=ignoreindent $SAMBA_CONFIG "$3" "$KEY" "$VALUE"
		done
	else
		crudini --get --ini-options=ignoreindent "$2" "" | grep -v -E "$4" | while IFS= read -r KEY ; do
			VALUE=$(crudini --get --ini-options=ignoreindent "$2" "" "$KEY")
			echo "  $KEY=$VALUE"
			crudini --set --ini-options=ignoreindent $SAMBA_CONFIG "$3" "$KEY" "$VALUE"
		done
	fi
}

calc_checksum(){
	if [ -f "$1" ]; then
		 md5sum "$1" | cut -f 1 -d " "
	else
		echo ""
	fi
}

register_file(){
	local SMB_CONF=$1
	local VOL_REG=$2
	local S_NAME=$3
	local S_FILE=$4
	local S_PATH=$(crudini --get --ini-options=ignoreindent "$S_FILE" "" "path")
	local S_CURR_CSUM=$(calc_checksum "$S_FILE")
	local S_PREV_CSUM=$(get_share_info "$VOL_REG" "$S_NAME" "checksum")
	local S_STATE=""

	# check if we should register it

	if ! crudini --get --ini-options=ignoreindent $SMB_CONF | grep "$S_NAME" > /dev/null; then
		# missing from smb.conf
		S_STATE="ADD$([ ! -d $S_PATH ] && echo ', PATH MISSING')"
	elif [ "$S_CURR_CSUM" != "$S_PREV_CSUM" ]; then
		# file was changed
		S_STATE="MODIFY$([ ! -d $S_PATH ] && echo ', PATH MISSING')"
	else
		return 1
	fi

	# register from share file

	echo ">> VOLUMES: Register file share [$S_NAME] ($S_STATE)"
	register_share_type "$VOL_REG" "$S_NAME" "file" "$S_PATH" "$S_CURR_CSUM"

	# delete section before creating new one
	crudini --del --ini-options=ignoreindent "$SMB_CONF" "$S_NAME"

	# create section
	crudini --set --ini-options=ignoreindent "$SMB_CONF" "$S_NAME"

	# add keys
	copy_keys "$SMB_CONF" "$S_FILE" "$S_NAME"

	#
	return 0
}

register_directory(){
	local SMB_CONF=$1
	local VOL_REG=$2
	local S_NAME=$3
	local S_PATH=$4
	local S_PARENT=$(dirname $S_PATH)
	local S_TEMPLATE=""
	local S_PREV_CSUM=$(get_share_info "$VOL_REG" "$S_NAME" "checksum")
	local S_CURR_CSUM=""

	# get template

        if [ -f "$S_PARENT/$S_NAME.template" ]; then
		S_TEMPLATE="$S_PARENT/$S_NAME.template"
		S_CURR_CSUM=$(calc_checksum "$S_TEMPLATE")
        elif [ -f "$S_PARENT/default.template" ]; then
		S_TEMPLATE="$S_PARENT/default.template"
		S_CURR_CSUM=$(calc_checksum "$S_TEMPLATE")
	else
		S_TEMPLATE=""
		S_CURR_CSUM=""
	fi

	# check if we should register it

	if ! crudini --get --ini-options=ignoreindent $SMB_CONF | grep "$S_NAME" > /dev/null; then
		# missing from smb.conf
		S_STATE="ADD$([ ! -d $S_PATH ] && echo ', PATH MISSING')"
	elif [ "$S_CURR_CSUM" != "$S_PREV_CSUM" ]; then
		# file was changed
		S_STATE="MODIFY$([ ! -d $S_PATH ] && echo ', PATH MISSING')"
	else
		return 1
	fi

	# register from directory, use template
	echo ">> VOLUMES: Register directory share [$S_NAME] ($S_STATE)"
	register_share_type "$VOL_REG" "$S_NAME" "directory" "$S_PATH" "$S_CURR_CSUM"

	# delete section before creating new one
	crudini --del --ini-options=ignoreindent "$SMB_CONF" "$S_NAME"

	# create section
	crudini --set --ini-options=ignoreindent "$SMB_CONF" "$S_NAME"

	# set path
	echo "  path=$S_PATH"
	crudini --set --ini-options=ignoreindent "$SMB_CONF" "$S_NAME" "path" "$S_PATH"

	# set comment
	echo "  comment=Share $S_PATH on %L"
	crudini --set --ini-options=ignoreindent "$SMB_CONF" "$S_NAME" "comment" "Share $S_PATH on %L"

	# set writable
	if is_writable "$S_PATH" "$SAMBA_DYNAMIC_GROUP" "$SAMBA_DYNAMIC_USER"; then
		echo "  writeable=yes"
		crudini --set --ini-options=ignoreindent "$SMB_CONF" "$S_NAME" "writeable" "yes"
	else
		echo "  writeable=no"
		crudini --set --ini-options=ignoreindent "$SMB_CONF" "$S_NAME" "writeable" "no"
	fi
	# copy from template if exists

        if [ ! -z "$S_TEMPLATE" ]; then
		copy_keys "$SMB_CONF" "$S_TEMPLATE" "$S_NAME" "path|comment|writeable"
	fi
	return 0
}

############################
# MAIN
############################

VOLUME_DIR="./data" #   "/dynamic-shares"
VOLUME_REGISTER="./volumes.json" # "/tmp/volumes.json"
SAMBA_CONFIG="./smb.conf" # "/etc/samba/smb.conf"
SAMBA_CONFIG_CHANGED=""

# update static shares

for SHARE_NAME in $(crudini --get --ini-options=ignoreindent "$SAMBA_CONFIG" |  grep -v -E "homes|global|printers"); do
	SHARE_TYPE=$(get_share_info "$VOLUME_REGISTER" "$SHARE_NAME" "type")
        DIR=$(crudini --get --ini-options=ignoreindent "$SAMBA_CONFIG" "$SHARE_NAME" "path" 2> /dev/null)
	# register static
	if [ -z "$SHARE_TYPE" ]; then
		echo ">> VOLUMES: Register static share $DIR as [$SHARE_NAME]"
		register_share_type "$VOLUME_REGISTER" "$SHARE_NAME" "static" "$DIR"
	fi
done

# process dynamic shares

for ITEM in $(find "$VOLUME_DIR" -mindepth 1 -maxdepth 1); do
	# get share name and type
	SHARE_FILE=$(basename $ITEM)
	SHARE_NAME=$(filename $ITEM)
	SHARE_EXT=$(extname $ITEM)
	SHARE_TYPE=$(get_share_info "$VOLUME_REGISTER" "$SHARE_NAME" "type")
	IN_CONF=$(crudini --get --ini-options=ignoreindent "$SAMBA_CONFIG" | grep "$SHARE_NAME")
	# check smb.conf for share
        if echo "$SHARE_NAME" | grep -E "homes|global|printers" > /dev/null; then
		: # reserved section name
	elif [ "$SHARE_TYPE" = "static" ]; then
		: # static share
		echo "$ITEM is static"
	elif [ -f "$ITEM" ] && [ "$SHARE_EXT" = "share" ]; then
		register_file "$SAMBA_CONFIG" "$VOLUME_REGISTER" "$SHARE_NAME" "$ITEM" && SAMBA_CONFIG_CHANGED="yes"
	elif [ -d "$ITEM" ]; then
		register_directory "$SAMBA_CONFIG" "$VOLUME_REGISTER" "$SHARE_NAME" "$ITEM" && SAMBA_CONFIG_CHANGED="yes"
	fi
done

# remove deleted shares

for SHARE_NAME in $(crudini --get --ini-options=ignoreindent "$SAMBA_CONFIG" |  grep -v -E "homes|global|printers"); do
	SHARE_TYPE=$(get_share_info "$VOLUME_REGISTER" "$SHARE_NAME" "type")
        DIR=$(crudini --get --ini-options=ignoreindent "$SAMBA_CONFIG" "$SHARE_NAME" "path" 2> /dev/null)

        if [ -z "$DIR" ]; then
        	: # not a share, do nothing
	elif [ -d "$DIR" ]; then
		: # exists, do nothing
	elif [ "$SHARE_TYPE" = "file" ] && [ ! -f "$VOLUME_DIR/$SHARE_NAME.share" ]; then
		# remove file share
		echo ">> VOLUMES: Unregister file share [$SHARE_NAME]"
		crudini --del "$SAMBA_CONFIG" --ini-options=ignoreindent "$SHARE_NAME"
		unregister_share_type "$VOLUME_REGISTER" "$SHARE_NAME"
		SAMBA_CONFIG_CHANGED="yes"
	elif [ "$SHARE_TYPE" = "directory" ] && [ ! -d "$VOLUME_DIR/$SHARE_NAME" ]; then
		# remove directory share
		echo ">> VOLUMES: Unregister directory share [$SHARE_NAME]"
		crudini --del "$SAMBA_CONFIG" --ini-options=ignoreindent "$SHARE_NAME"
		unregister_share_type "$VOLUME_REGISTER" "$SHARE_NAME"
		SAMBA_CONFIG_CHANGED="yes"
	fi
done

# remove double spaces

cat "$SAMBA_CONFIG" | uniq | sponge "$SAMBA_CONFIG"

# reload samba config

if [ -z "$SAMBA_CONFIG_CHANGED" ]; then
	: # do nothing, smb.conf not changed
elif ! which smbcontrol > /dev/null; then
	: # do nothing, smb.conf not changed
elif ! smbcontrol all reload-config; then
	echo ">> VOLUMES: Failed to reload samba configuration"
else
	echo ">> VOLUMES: Reload samba configuration: CONFIG_CHANGED=$SAMBA_CONFIG_CHANGED"
fi
