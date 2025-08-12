# Common handy shell script functions

l=/var/run/reboot-lock

reboot_lock () {
    exec 3<$l
    if ! flock --shared -w 0 3; then
	echo 2>&1 "Cannot acquire reboot lock."
	#exit 1
    fi
}

reboot_unlock () {
    flock --shared -u 3
}

now () {
    date -u +%F:%H:%M:%S
}

build_description () {
    case $1 in
        NI)
	    DESC="Netinst CD";;
        MACNI)
	    DESC="Mac Netinst CD";;
        CD)
	    DESC="Full CD";;
        DVD)
            DESC="Full DVD";;
        BD)
            DESC="Blu-ray";;
        DLBD)
            DESC="Dual-layer Blu-ray";;
        KDECD)
	    DESC="KDE CD";;
        GNOMECD)
	    DESC="GNOME CD";;
        LIGHTCD)
	    DESC="XFCE/lxde CD";;
        XFCECD)
	    DESC="XFCE CD";;
        LXDECD)
	    DESC="lxde CD";;
	*)
	    DESC="UNKNOWN";;
    esac
    echo "$DESC"
}    

calc_time () {
    echo $1 $2 | awk '
    {
        split($1, start, ":")
        start_time = (3600*start[2]) + (60*start[3]) + start[4]
        split($2, end, ":")
        end_time = (3600*end[2]) + (60*end[3]) + end[4]
        # Cope with going to a new day; do not worry about more than 1 day!
        if (start[1] != end[1]) { end_time += 86400 }
        time_taken = end_time - start_time
        hours = int(time_taken / 3600)
        time_taken -= (hours * 3600)
        minutes = int(time_taken / 60)
        time_taken -= (minutes * 60)
        seconds = time_taken
        printf("%dh%2.2dm%2.2ds\n", hours, minutes, seconds)
    }'
}

# Slightly complicated setup
# iso-*   dirs have checksums for ISO files only
# bt-*    dirs have checksums for ISO and torrrent files only
# jigdo-* dirs have checksums for ISO and jigdo files only
#
# Uses the imagesums tool from debian-cd to grab pre-calculated ISO
# checksums from the jigdo files where possible, to save a lot of time
generate_checksums_for_arch () {
    ARCH=$1
    JIGDO_DIR=$2
    ISO_DIR=$(echo $JIGDO_DIR | sed 's,jigdo-,iso-,g')
    BT_DIR=$(echo $JIGDO_DIR | sed 's,jigdo-,bt-,g')

    # Do the torrents first, if they exist
    if [ -e $BT_DIR ]; then
	$TOPDIR/debian-cd/tools/imagesums $BT_DIR $EXTENSION > /dev/null
    fi

    # Now do the jigdos, if they exist
    if [ -e $JIGDO_DIR ]; then
	$TOPDIR/debian-cd/tools/imagesums $JIGDO_DIR $EXTENSION > /dev/null
	# And grep out the .iso checksums from there to the iso directory
	for file in $JIGDO_DIR/*SUMS*${EXTENSION}; do
	    out=$ISO_DIR/$(basename $file)
	    grep \\.iso $file > $out
	done
	if [ -e $BT_DIR ]; then
	    # Ditto for the bt directory
	    for file in $JIGDO_DIR/*SUMS*${EXTENSION}; do
		out=$BT_DIR/$(basename $file)
		grep \\.iso $file >> $out
	    done
	fi
    else
	# No jigdos, so do the ISOs by hand
	$TOPDIR/debian-cd/tools/imagesums $ISO_DIR $EXTENSION > /dev/null
	if [ -e $BT_DIR ]; then
	    for file in $ISO_DIR/*SUMS*${EXTENSION}; do
		out=$BT_DIR/$(basename $file)
		grep \\.iso $file >> $out
	    done
	fi
    fi
}

catch_live_builds () {
    # Catch parallel build types here

    if [ "$NOLIVE"x = ""x ] && [ "$NOOPENSTACK"x = ""x ] ; then
	return
    fi
    
    while [ ! -f $PUBDIRLIVETRACE ] || [ ! -f $PUBDIROSTRACE ] ; do
	sleep 1
    done

    . $PUBDIROSTRACE
    time_spent=`calc_time $start $end`
    echo "openstack build started at $start, ended at $end (took $time_spent), error $error"

    . $PUBDIRLIVETRACE
    time_spent=`calc_time $start $end`
    echo "live builds started at $start, ended at $end (took $time_spent), error $error"

}

get_archive_serial () {
    trace_file="$MIRROR/project/trace/ftp-master.debian.org"
    if [ -f "$trace_file" ]; then
        awk '/^Archive serial: / {print $3}' "$trace_file"
    else
        echo 'unknown'
    fi
}

rsync_to_umu () {
    LOCAL=$1
    REMOTE=$2
    OPTIONS="$3"
    case $(hostname) in
	pettersson*)
	    rsync -a --delete $OPTIONS $LOCAL /mnt/nfs-cdimage/.incoming/$REMOTE
	    ;;
	*)
	    rsync -az --delete $OPTIONS $LOCAL sync-to-umu:$REMOTE
	    ;;
    esac
}

publish_at_umu () {
    TARGETS="$@"
    case $(hostname) in
	pettersson*)
	    echo "$TARGETS" | ~/bin/publish_from_casulana
	    ;;
	*)
	    echo "$TARGETS" | ssh publish-at-umu ./bin/publish_from_casulana
	    ;;
    esac
}

check_variables () {
    for VAR in $@; do
	if [ "${!VAR}"x = ""x ]; then
	    echo "$BUILD: required variable $VAR is unset; ABORT"
	    exit 1
	fi
    done
}

# helper for trigger_openqa() to avoid depending on openqa-client
openqa_cli_api_isos() {
    OPENQA_HOST=$1; shift
    if [ -x /usr/bin/openqa-cli ]; then
        openqa-cli api --host https://$OPENQA_HOST -X POST isos "$@"
    else
        OPENQA_TOKEN=images-team-openqa-trigger:$(sed -n -E '/\['$OPENQA_HOST'\]/,/^$/s/^key *= *//p' $HOME/.config/openqa/client.conf):$(sed -n -E '/\['$OPENQA_HOST'\]/,/^$/s/^secret *= *//p' $HOME/.config/openqa/client.conf)
        curl -sS -u $OPENQA_TOKEN -X POST $(
                for i in "$@"; do printf ' -d %s' "$i"; done
            ) https://$OPENQA_HOST/api/v1/isos
    fi
    echo
}

debversion() {
    # This outputs the value set for DEBVERSION in the current config file
    awk -F'[="]+' '!/#/ && /DEBVERSION=/{v=$2};END{print v}' "${CONF:-$TOPDIR/CONF.sh}"
}

trigger_openqa () {
    IMAGE_DIR=$1;  shift # e.g. daily-builds/sid_d-i/20230601-1 / weekly-builds / .trixie_di_alpha1
    DEB_VER=$1;    shift # e.g. testing / trixie-DI-alpha1
    DATE_BUILD=$1; shift # e.g. 20230601-1
    DEB_ARCHS=$1;  shift # e.g. amd64,arm64
    # we probably also need a parameter to use in place of 'netinst' at some point

    for DEB_ARCH in ${DEB_ARCHS/,/ }; do
        case "$DEB_ARCH" in
            amd64) OQA_ARCH=x86_64 ;;
            arm64) OQA_ARCH=aarch64 ;;
            *)     OQA_ARCH="$DEB_ARCH" ;;
        esac

        ISO_URL="https://cdimage.debian.org/images/${IMAGE_DIR}/${DEB_ARCH}/iso-cd/debian-${DEB_VER}-${DEB_ARCH}-netinst.iso"

        curl_result=$(curl --head --location --silent --write-out "%{http_code}" --output /dev/null "$ISO_URL")

        if [ "200" = "$curl_result" ]; then
            # this needs an openQA API key & secret to be in the running user's ~/.config/openqa/client.conf, in this form:
            #   [openqa.debian.net]
            #   key = XXXXXXXXXXXXXXXX
            #   secret = YYYYYYYYYYYYYYYY
            openqa_cli_api_isos openqa.debian.net \
                DISTRI=debian VERSION="${DEB_VER}" FLAVOR=netinst-iso ARCH="${OQA_ARCH}" BUILD="${DATE_BUILD}" \
                ISO_URL="$ISO_URL" ISO="${DATE_BUILD}-debian-${DEB_VER}-${DEB_ARCH}-netinst.iso"
        else
            printf "ERROR: ISO for arch=%s not found. http_resp=[%s] url='%s'\n" "$DEB_ARCH" "$curl_result" "$ISO_URL"  >&2
        fi
    done
}
