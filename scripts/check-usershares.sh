#!/bin/sh

####################################
# FUNCTIONS
####################################

add_share(){
	SN=$1 # SHARE NAME
	SD=$2 # SHARE DIR
	SC=$3 # SHARE COMMENT
	SP=$4 # SHARE PERMISSIONS
	SG=$5 # SHARE GUEST OK
	# validate arguments
	if [ -z "$SN" ]; then
		echo "  ERROR: Share name is empty"
		return 1
	elif [ -z "$SD" ]; then
		echo "  ERROR: Path variable is empty"
		return 1
	elif [ ! -d "$SD" ]; then
		echo "  ERROR: Path is missing or not a directory"
		return 1
	fi
	# config permissions and guest
	if [ -z "$SP" ] && [ -z "$SG" ] ; then # not set
		NET_OPTS=""
	elif [ ! -z "$SP" ] && [ -z "$SG" ] ; then # acl set, guest not set
		NET_OPTS="$SP"
	elif [ -z "$SP" ] && [ ! -z "$SG" ] ; then # acl not set, guest set
		NET_OPTS="Everyone:R guest_ok=$SG"
	else # acl/guest set
		NET_OPTS="$SP guest_ok=$SG"
	fi
	# start share
	echo ">> USERSHARE: Add/Modify [$SN]"
	echo ">> USERSHARE: net usershare add \"$SN\" \"$SD\" \"${SC:-$SC share}\" $NET_OPTS"
	if net usershare add "$SN" "$SD" "${SC:-$SC share}" $NET_OPTS; then
		echo "     SUCCESS"
                net usershare info --long "$SN" | while IFS= read -r LINE ; do
  			echo "     $LINE"
                done
		return 0
	else
		echo "     ERROR"
		return 1
	fi
}

delete_share(){
	SN="$1"
	#
	echo ">> USERSHARE: Add/Modify [$SN]"
	echo ">> USERSHARE: net usershare delete \"$SN\""
	if net usershare delete "$SN"; then 
		echo "  SUCCESS"
		return 0
	else
		echo "  ERROR"
		return 1
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

md5sum $USERSHARE_DIR/*.usershare 2> /dev/null > $CHECKSUM_CURR

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
		delete_share "$SHARE_NAME"
	elif [ "$PREV_MD5" != "$CURR_MD5" ]; then # share file added or changed
		# get variables from usershare file
		SHARE_PATH=$(cat $FILE_NAME | grep -i "path\s*=" $FILE_NAME | cut -f 2 -d "="  | xargs)
		SHARE_COMMENT=$(cat $FILE_NAME | grep -i "comment\s*=" $FILE_NAME | cut -f 2 -d "="  | xargs)
		SHARE_ACL=$(cat $FILE_NAME | grep -i "acl\s*=" $FILE_NAME | cut -f 2 -d "="  | xargs)
		SHARE_GUEST=$(cat $FILE_NAME | grep -i "guest_ok\s*=" $FILE_NAME | cut -f 2 -d "="  | xargs)
		# add share to samba
		add_share "$SHARE_NAME" "$SHARE_PATH" "$SHARE_COMMENT" "$SHARE_ACL" "$SHARE_GUEST"
	fi
done
