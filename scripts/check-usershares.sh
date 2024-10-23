#!/bin/sh

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
	if [ "$PREV_MD5" != "" ] && [ "$CURR_MD5" = "" ]; then # delete
		echo ">> USERSHARE: Delete [$SHARE_NAME]"
		net usershare delete "$SHARE_NAME"
	elif [ "$PREV_MD5" != "$CURR_MD5" ]; then # added or modified
		echo ">> USERSHARE: Modify [$SHARE_NAME]"
		# get variables from usershare file
		SHARE_PATH=$(cat $FILE_NAME | grep -i "path\s*=" $FILE_NAME | cut -f 2 -d "="  | xargs)
		SHARE_COMMENT=$(cat $FILE_NAME | grep -i "comment\s*=" $FILE_NAME | cut -f 2 -d "="  | xargs)
		SHARE_ACL=$(cat $FILE_NAME | grep -i "acl\s*=" $FILE_NAME | cut -f 2 -d "="  | xargs)
		SHARE_GUEST=$(cat $FILE_NAME | grep -i "guest_ok\s*=" $FILE_NAME | cut -f 2 -d "="  | xargs)
		# add usershare
		if [ -z "$SHARE_PATH" ]; then
			echo "  ERROR: Path variavble not set in $FILE_NAME"
		elif [ -z "$SHARE_GUEST" ]; then 
			net usershare add "$SHARE_NAME" "$SHARE_PATH" "${SHARE_COMMENT:-$SHARE_NAME share}" "${SHARE_ACL:-Everyone:R}"
		else
			net usershare add "$SHARE_NAME" "$SHARE_PATH" "${SHARE_COMMENT:-$SHARE_NAME share}" "${SHARE_ACL:-Everyone:R}" "guest_ok=$SHARE_GUEST"
		fi
	fi
done
