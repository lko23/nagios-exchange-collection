#!/bin/bash

# script for checking HPE oneview alerts

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

# safe token initialy to file
token="check_oneview_$host.token"
header1='Accept: application/json'
header2='Content-Type: application/json'

if [ ! -f $token ] || [ `stat --format=%Y $token` -le $(( `date +%s` - 3600 )) ]; then
        auth_uri='/rest/login-sessions'
        auth_return=`curl -s -H "$header1" -H "$header2" -X POST --data @"$scriptpath/check_oneview_$host.json" https://$host$auth_uri`
        echo "$auth_return" | sed 's/sessionID/auth/g' | sed 's/[\{\"\}]//g' | sed 's/:/: /g' | tr -d '\n' > "$scriptpath/$token"
fi

#uri='/rest/alerts?start=0&count=-1&filter="alertState EQ 'Active' AND severity EQ 'MAJOR'"'
uri='/rest/alerts?start=0&count=-1&filter="alertState%20EQ%20%27Active%27%20AND%20severity%20EQ%20%27MAJOR%27"'
#uri='/rest/alerts?start=0&count=-1&filter="alertState%20EQ%20%27Active%27%20AND%20severity%20EQ%20%27MAJOR%27AND%20urgency%20EQ%20%27High%27%20AND%20physicalResourceType%20EQ%20%27server-hardware%27"'

api_return=`curl -s -H "$header1" -H "$header2" -H @"$scriptpath/$token" -X GET https://$host$uri`

tree_size=$( jq -r '.total' <<< "${api_return}" )
#echo $tree_size

if [ ! -e $"$scriptpath/check_oneview_$host.json" ]; then
        echo "UNKNOWN: credentials file check_oneview_$host.json does not exist"
        exit 3

elif ! [[ $tree_size =~ ^[0-9]+$ ]]; then
        rm -f "$token"
        echo "UNKNOWN: Number of alerts is not numeric or not defined."
        exit 3

elif [[ $tree_size -gt 0 ]]; then
        echo "CRITICAL: there are $tree_size alerts for $host"
        echo $api_return | jq -r '.members[] | "\(.description)"'
#       echo $api_return | jq -r '.members | to_entries' #| .[] | [.physicalResourceType]'
#       echo $api_return | jq -r 'to_entries[] | [.members.physicalResourceType, .members.urgency] | @tsv'
#       echo $api_return | jq -r '.members[] | "\(.physicalResourceType) \(.urgency) \(.description)"' # |to_entries|map(.value)|@tsv'  # ,.members.[].correctiveAction'   #'to_entries|map(.value)|@tsv' # jq '.|@tsv'
#       echo $api_return | jq -r '.members.[].[physicalResourceType],.members.[].[urgency],.members.[].[description]' #|to_entries|map(.value)|@tsv'
#       echo "$api_return" | jq -r 'map(.sensors.[].)|@tsv'
#       echo "$api_return" | jq -r '.sensors.[].device,.sensors.[].sensor,.sensors.[].status,.sensors.[].lastvalue,.sensors.[].message_raw'
#       echo "$api_return" | jq -r 'to_entries|map(.sensors.[].device)|@tsv'
        exit 2
else
        echo "OK: there are no alerts for $host"
        exit 0

fi
