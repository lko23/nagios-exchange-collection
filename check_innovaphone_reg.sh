#!/bin/bash
#
#script for checking innovaphone registration
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
        -T [STRING]     Type
        ----------------------------------
END
}

if [ $# -lt 3 ]
then
        help;
        exit 3;
fi

while getopts "h:H:T:" OPT
do
        case $OPT in
        h) help ;;
        H) host="$OPTARG" ;;
        T) type="$OPTARG" ;;
        *) help ;;
        esac
done

uri="/PBX0/ADMIN/mod_cmd_login.xml?cmd=show&reg=$type"
api_return=`curl -s -u 'username:password' --basic --insecure https://$host$uri`
#echo "API-RETURN: "
#echo $api_return

count=$(echo $api_return | grep -oP '<reg' | wc -l)

#echo "Count: "
#echo $count

if ! [[ $count =~ ^[0-9]+$ ]]; then
        echo "UNKNOWN: Number of alerts is not numeric or not defined"
        exit 3

elif [[ $count -gt 0 ]]; then
        echo "OK: $type registration exists for $host"
        echo $api_return | grep -oP 'reg.*?pwd'
        exit 0

else
        echo "CRITICAL: $type registration does not exist for $host"
        echo $api_return | grep -oP 'show.*?admin'
        exit 2

fi
