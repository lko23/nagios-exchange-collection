#!/bin/bash
#
#script for checking sanswitch error log of today
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

today=$(date '+%Y-%m-%d')
#today="2025-03-14"

uri='/rest/running/brocade-logging/error-log'

api_return=`curl -s -H 'Accept: application/yang-data+json' -u 'username:password' --basic --insecure https://$host$uri | tr -cd '[:alnum:][],: "{}._-' `
#echo $api_return

today_msg=$( jq -r '.Response."error-log".[] | select(."time-stamp" | contains("'$today'"))' <<< "${api_return}" )
today_msg_no=$(echo $today_msg | tr -cd '{' | wc -c)
msg_no=$( jq -r '.Response."error-log" | length' <<< "${api_return}" )
#echo $today_msg
#echo $msg_no
#echo $today_msg_no

#info=$( jq -c '.Response."error-log".[] | select(."severity-level" | contains("info"))' <<< "${api_return}" )
#warning=$( jq -c '.Response."error-log".[] | select(."severity-level" | contains("warning"))' <<< "${api_return}" )
#error=$( jq -c '.Response."error-log".[] | select(."severity-level" | contains("error"))' <<< "${api_return}" )
#critical=$( jq -c '.Response."error-log".[] | select(."severity-level" | contains("critical"))' <<< "${api_return}" )
info=$( jq -c '. | select(."severity-level" | contains("info"))' <<< "${today_msg}" )
warning=$( jq -c '. | select(."severity-level" | contains("warning"))' <<< "${today_msg}" )
error=$( jq -c '. | select(."severity-level" | contains("error"))' <<< "${today_msg}" )
critical=$( jq -c '. | select(."severity-level" | contains("critical"))' <<< "${today_msg}" )
info_no=$(echo $info | tr -cd '{' | wc -c)
warning_no=$(echo $warning | tr -cd '{' | wc -c)
error_no=$(echo $error | tr -cd '{' | wc -c)
critical_no=$(echo $critical | tr -cd '{' | wc -c)

#echo $info
#echo $warning
#echo $error
#echo $critical
#echo $info_no
#echo $warning_no
#echo $error_no
#echo $critical_no

#echo $api_return  | jq -c '.Response."error-log".[] | select(."severity-level" | contains("warning"))' # | jq -r '.Response."error-log".[] | "\(."time-stamp") \(."slot-id") \(."fabric-id") \(."severity-level") \(."message-text")"''

if ! [[ $info_no =~ ^[0-9]+$ || $warning_no =~ ^[0-9]+$ ||  $error_no =~ ^[0-9]+$ ||  $critical_no =~ ^[0-9]+$ ]]; then
        echo "UNKNOWN: Number of messages is not numeric or not defined."
        exit 3

elif [[ msg_no -le 0 ]]; then
        echo "UNKNOWN: Got no messages in API return."
        exit 3

elif [[ $critical_no -gt 0 ]]; then
        echo "CRITICAL: today there are $critical_no critical messages for $host"
        echo $critical
        exit 2

elif [[ $error_no -gt 0 ]]; then
        echo "WARNING: today there are $error_no error messages for $host"
        echo $error
        exit 1

else
        echo "OK: today there are $critical_no critical, $error_no error, $warning_no warning and $info_no info messages for $host"
        echo $warning | jq -r '. | "\(."switch-user-friendly-name") \(."slot-id") \(."fabric-id") \(."severity-level") \(."message-text")"'
        echo $info | jq -r '. | "\(."switch-user-friendly-name") \(."slot-id") \(."fabric-id") \(."severity-level") \(."message-text")"'
        exit 0

fi
