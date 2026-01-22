#!/bin/bash
#
# script for checking innovaphone warnings and alerts
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

# define user, password and url
uri='/LOG0/FAULT/mod_cmd.xml?cmd=xml-alarms'
api_return=`curl -s -u 'username:password' --basic --insecure https://$host$uri`
#echo "API-RETURN: "
#echo $api_return

count=$(echo $api_return | grep -oP 'type="alarm"' | wc -l)
severity=$(echo $api_return | grep -oP '(?<=severity=")[^"]+')
time=$(echo $api_return | grep -oP '(?<=time=")[^"]+')
text=$(echo $api_return | grep -oP '(?<=text>)[^<]+')

#echo "Count, Severity, Time and Text: "
#echo $count
#echo $severity
#echo $time
#echo $text

if ! [[ $count =~ ^[0-9]+$ ]]; then
        echo "UNKNOWN: Number of alerts is not numeric or not defined"
        exit 3

elif [[ $count -gt 0 && $severity -gt 1 ]]; then
        echo "CRITICAL: there are $count alerts for $host"
        echo "$time $text"
        exit 2

elif [[ $count -gt 0 ]]; then
        echo "WARNING: there are $count alerts for $host"
        echo "$time $text"
        exit 1

else
        echo "OK: there are no alerts for $host"
        exit 0

fi
