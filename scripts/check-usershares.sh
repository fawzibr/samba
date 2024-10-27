#!/bin/sh

####################################
# FUNCTIONS
####################################

add_include_share(){
	SN=$1 # SHARE NAME
	SF=$2 # SHARE FILE
	#
	echo ">> USERSHARE: Add/Modify [$SN]"
	if [ -z "$SN" ]; then
		echo "  ERROR: Share name is empty"
		return 1
	elif echo "$SN" | grep -E "homes|global|printers" > /dev/null; then
		echo "  ERROR: Share name [$SN] is not allowed, it is a special samba section"
		return 1
	elif cat /tmp/sections.tmp | grep -E "$SN" > /dev/null; then
		echo "  ERROR: Share name [$SN] is not allowed, it is a existing share"
		return 1
	else
		# delete existing share
		crudini --del --ini-options=ignoreindent "/etc/samba/smb.conf" "$SN"
		# copy keys in file to smb.conf
		crudini --get --ini-options=ignoreindent "$SF" "" | while IFS= read -r KEY ; do
			VALUE=$(crudini --get "$SF" "" "$KEY")
			echo "     $KEY=$VALUE"
			crudini --set --ini-options=ignoreindent "/etc/samba/smb.conf" "$SN" "$KEY" "$VALUE"
	        done
		# reload config
		echo ">> USERSHARE: Reload config"
		smbcontrol all reload-config
		return 0
	fi
}

delete_include_share(){
	SN="$1"
	#
	echo ">> USERSHARE: Delete [$SN]"
	if [ -z "$SN" ]; then
		echo "  ERROR: Share name is empty"
		return 1
	elif echo "$SN" | grep -E "homes|global|printers" > /dev/null; then
		echo "  ERROR: Share name [$SN] is not allowed, it is a special samba section"
		return 1
	elif cat /tmp/sections.tmp | grep -E "$SN" > /dev/null; then
		echo "  ERROR: Share name [$SN] is not allowed, it is a existing share"
		return 1
	else
		# delete from smb.conf
		crudini --del --ini-options=ignoreindent "/etc/samba/smb.conf" "$SN"
		# reload config
		echo ">> USERSHARE: Reload config"
		smbcontrol all reload-config
		return 0
	fi
}

####################################
# MAIN
####################################

USERSHARE_DIR=$1
CHECKSUM_PREV=/tmp/checksum.prev
CHECKSUM_CURR=/tmp/checksum.curr
USERSHARE_FILES=""

# copy checksum to old, or create empty one

if [ -f $CHECKSUM_CURR ]; then
	mv $CHECKSUM_CURR $CHECKSUM_PREV
else
	touch $CHECKSUM_PREV
fi

# create new checksum

md5sum $USERSHARE_DIR/*.share 2> /dev/null > $CHECKSUM_CURR

# get all files in checksum.curr

while read -r LINE; do
	NAME=$(echo $LINE | cut -f 2 -d " ")
	USERSHARE_FILES="${USERSHARE_FILES} ${NAME}"
done < $CHECKSUM_CURR

# get all files missing in checksum.curr

while read -r LINE; do
	NAME=$(echo $LINE | cut -f 2 -d " ")
	if ! grep "$NAME" $CHECKSUM_CURR > /dev/null; then
		USERSHARE_FILES="${USERSHARE_FILES} ${NAME}"
	fi
done < $CHECKSUM_PREV

# process all files

for FILE_NAME in $USERSHARE_FILES; do
	# get share name (file name, no path, no extension)
	SHARE_NAME="${FILE_NAME##*/}"
	SHARE_NAME="${SHARE_NAME%.*}"
	# get MD5
	PREV_MD5=$(cat $CHECKSUM_PREV | grep "$FILE_NAME" | cut -f 1 -d " ")
	CURR_MD5=$(cat $CHECKSUM_CURR | grep "$FILE_NAME" | cut -f 1 -d " ")
	# process usershare
	RESULT=""
	if [ "$PREV_MD5" != "" ] && [ "$CURR_MD5" = "" ]; then # share file deleted
		# delete the share from samba
		# delete_net_share "$SHARE_NAME"
		delete_include_share "$SHARE_NAME"
	elif [ "$PREV_MD5" != "$CURR_MD5" ]; then # share file added or changed
		# get variables from usershare file
		SHARE_PATH=$(cat $FILE_NAME | grep -i "path\s*=" $FILE_NAME | cut -f 2 -d "="  | xargs)
		SHARE_COMMENT=$(cat $FILE_NAME | grep -i "comment\s*=" $FILE_NAME | cut -f 2 -d "="  | xargs)
		SHARE_ACL=$(cat $FILE_NAME | grep -i "acl\s*=" $FILE_NAME | cut -f 2 -d "="  | xargs)
		SHARE_GUEST=$(cat $FILE_NAME | grep -i "guest_ok\s*=" $FILE_NAME | cut -f 2 -d "="  | xargs)
		# add share to samba
		# add_net_share "$SHARE_NAME" "$SHARE_PATH" "$SHARE_COMMENT" "$SHARE_ACL" "$SHARE_GUEST"
		add_include_share "$SHARE_NAME" "$FILE_NAME"
	fi
done
