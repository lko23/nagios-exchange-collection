#!/bin/bash
#
#script for checking storeonce health
#

progname=`basename $0`
script=$(realpath "$0")
scriptpath=$(dirname "$script")

help() {
cat << END
Usage :
        $PROGNAME -H [STRING]

        OPTION          DESCRIPTION
        ----------------------------------
        -h              Help
        -H [STRING]     Host
        ----------------------------------
END
}

if [ $# -lt 2 ]
then
        help;
        exit 3;
fi

while getopts "h:H:" OPT
do
        case $OPT in
        h) help ;;
        H) host="$OPTARG" ;;
        *) help ;;
        esac
done

uri='/storeonceservices/cluster/'
header1='Accept: application/json'
header2='Content-Type: application/json'

api_return=`curl -s -H "$header1" -H "$header2" -u 'user:password/' --basic --insecure https://$host$uri`
#echo $api_return

health=$( jq -r '.cluster.properties | .health ' <<< "${api_return}" )
status=$( jq -r '.cluster.properties | .status' <<< "${api_return}" )
rephealth=$( jq -r '.cluster.properties | .repHealth' <<< "${api_return}" )
repstatus=$( jq -r '.cluster.properties | .repStatus' <<< "${api_return}" )
freespace=$( jq -r '.cluster.properties | .freeSpace' <<< "${api_return}" )
freespace=$( printf "%.0f" $freespace )
output=$( jq -r '.cluster.properties | "health=\(.health) status=\(.status) repHealth=\(.repHealth) repStatus=\(.repStatus) freeSpace=\(.freeSpace)"' <<< "${api_return}" )

if [ -z "$api_return" ]; then
        echo "UNKNOWN: no return from StoreOnce API"
        exit 3

elif [[ "$health" != "OK" || "$status" != "Running" ]]; then
        echo "CRITICAL: StoreOnce node $host is not running or has some alerts"
        echo $api_return | jq -r '.cluster.properties | "health=\(.health) status=\(.status) repHealth=\(.repHealth) repStatus=\(.repStatus) freeSpace=\(.freeSpace)"'
        exit 2

elif [[ "$rephealth" != "OK" || "$repstatus" != "Running" ]]; then
        echo "WARNING: replication of StoreOnce node $host is not running or has some alerts"
        echo $api_return | jq -r '.cluster.properties | "health=\(.health) status=\(.status) repHealth=\(.repHealth) repStatus=\(.repStatus) freeSpace=\(.freeSpace)"'
        exit 1

elif [[ $freespace -lt 100000 ]]; then
        echo "WARNING: free space on StoreOnce node $host is lower than 100 TB"
        echo $api_return | jq -r '.cluster.properties | "health=\(.health) status=\(.status) repHealth=\(.repHealth) repStatus=\(.repStatus) freeSpace=\(.freeSpace)"'
        exit 1

elif [[ "$health" == "OK" && "$status" == "Running" && "$rephealth" == "OK" && "$repstatus" == "Running" && "$freespace" -ge "100000" ]]; then
        echo "OK: there are no alerts for StoreOnce node $host"
        exit 0

else
        echo "UNKNOWN: some undefined error occured"
        exit 3

fi
