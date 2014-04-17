#!/bin/sh
#
# This script will check the status of thin provisioned logical volumes
# 
# Author: Jeremy Kindy <jeremy.kindy@gmail.com>
# Also available at kindyjd@wfu.edu
#

### configuration
CONFIG_FILE=/etc/sysconfig/nagios-check-lvm
HOSTNAME=`/bin/hostname | /bin/cut -d. -f1`

WARN_THOLD=90
CRIT_THOLD=95

WARN_COLOR="blue"
CRIT_COLOR="red"
### end configuration

# these should be in $CONFIG_FILE
#NAGIOS_SERVICE_NAME="LVM"
#NAGIOS_SERVER=your.nagios.host.com
#NAGIOS_CONFIG=/etc/nagios/send_nsca.cfg

if [ -r $CONFIG_FILE ]; then
    . $CONFIG_FILE
else
    exit_error "$CONFIG_FILE not found!"
fi

if [ -z $NAGIOS_SERVICE_NAME ]; then
    exit_error "NAGIOS_SERVICE_NAME not provided.  Check $CONFIG_FILE for configuration"
fi

if [ -z $NAGIOS_SERVER ]; then
    exit_error "NAGIOS_SERVER not provided.  Check $CONFIG_FILE for configuration"
fi

if [ -z $NAGIOS_CONFIG ]; then
    exit_error "NAGIOS_CONFIG not provided.  Check $CONFIG_FILE for configuration"
fi

if [ ! -r $NAGIOS_CONFIG ]; then
    exit_error "NAGIOS_CONFIG ($NAGIOS_CONFIG) not readable!"
fi

while getopts d OPTION
do
    case $OPTION in
        d)
            DEBUG=1
            ;;
    esac
done

STATUS=0
CRIT_COUNT=0
WARN_COUNT=0
PROCESSED=0
IGNORED=0

function exit_error {
    echo "ERROR: $1" >2
    exit 1
}

function check_percent {
    # usage:
    #   check_percent name percent
        
    THIS_NAME=$1
    THIS_DATA_PCT=$2

    if [ ! -z $THIS_DATA_PCT ]; then
        if [ $(bc <<< "$THIS_DATA_PCT >= $CRIT_THOLD") -eq 1 ]; then
            ((CRIT_COUNT++))
            OUTPUT="${OUTPUT} <font color=${CRIT_COLOR}>${THIS_NAME} Use: ${THIS_DATA_PCT}%</font>"
        elif [ $(bc <<< "$THIS_DATA_PCT >= $WARN_THOLD") -eq 1 ]; then
            ((WARN_COUNT++))
            OUTPUT="${OUTPUT} <font color=${WARN_COLOR}>${THIS_NAME} Use: ${THIS_DATA_PCT}%</font>"
        else
            OUTPUT="${OUTPUT} ${THIS_NAME} Use: ${THIS_DATA_PCT}%"
        fi              
    fi              
}

############################################################################
# Check thin volumes

for cur_vg in $(vgs --noheadings --nosuffix | awk '{ print $1 }'); do
    for cur_lv in $(lvs --noheadings --nosuffix rootvg | awk '{ print $1 }'); do

        # grab the data for ${cur_vg}${cur_lv} in a parseable format
        LV_DATA=$(lvs --noheadings --nosuffix --units b --separator "," --options vg_name,lv_name,attr,segtype,data_percent,snap_percent,metadata_percent ${cur_vg}/${cur_lv})

        # grab individual pieces of data
        LV_TYPE=$(echo $LV_DATA | awk -F, '{ print $4 }')
        LV_DATA_PCT=$(echo $LV_DATA | awk -F, '{ print $5 }')
        LV_SNAP_PCT=$(echo $LV_DATA | awk -F, '{ print $6 }')
        LV_META_PCT=$(echo $LV_DATA | awk -F, '{ print $7 }')

        if [ "${DEBUG}" == "1" ]; then
            echo "${cur_vg}${cur_lv}: ${LV_TYPE}, Data %: ${LV_DATA_PCT:0}, Snap %: ${LV_SNAP_PCT:0}, Meta %: ${LV_META_PCT:0}"
        fi

        # if this is the first processed volume, then we do not want to begin with a new line
        if [ $PROCESSED == 0 ]; then
            LINEBREAK=""
        else
            LINEBREAK="<BR />"
        fi

        # for now, only process NON linear (thin) volumes
        if [ "${LV_TYPE}" != "linear" ]; then
            OUTPUT="${OUTPUT}${LINEBREAK}${cur_vg}/${cur_lv} (${LV_TYPE})"

            # capture whether data usage is above threshold
            check_percent Data "$LV_DATA_PCT"

            # capture whether snapshot usage is above threshold
            check_percent Snapshot "$LV_SNAP_PCT"

            # capture whether metadata usage is above threshold
            check_percent Meta "$LV_META_PCT"
            ((PROCESSED++))
        else
            ((IGNORED++))
        fi
    done
done

# process the status
if [ $WARN_COUNT -gt 0 ]; then
    STATUS=1
fi

if [ $CRIT_COUNT -gt 0 ]; then
    STATUS=2
fi

if [ "${DEBUG}" == "1" ]; then
    echo "$PROCESSED processed, $IGNORED ignored, $WARN_COUNT warning, $CRIT_COUNT critical"
fi

if [ $PROCESSED -eq 0 ] && [ $CRIT_COUNT -eq 0 ] && [ $WARN_COUNT -eq 0 ]; then
    STATUS=0
    OUTPUT="No thin provisioned volumes"
fi

############################################################################

if [ "${DEBUG}" == "1" ]; then
    /bin/echo -e "${HOSTNAME}\t${NAGIOS_SERVICE_NAME}\t${STATUS}\t$OUTPUT"
else
    /bin/echo -e "${HOSTNAME}\t${NAGIOS_SERVICE_NAME}\t${STATUS}\t$OUTPUT" | /usr/sbin/send_nsca -H ${NAGIOS_SERVER} -c ${NAGIOS_CONFIG}
fi

