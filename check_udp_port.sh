#!/bin/sh
# 
# check_udp_port - Checks if a UDP port is open using nmap utility
#
# Author:	Aaron Eidt (aeidt4@uwo.ca)
#

STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3
STATE_DEPENDENT=4

usage () {
	printf "%s - Checks if a UDP port is open using nmap utility\n" $0
	printf "check_udp_port 2014-06-09 Written by: Aaron Eidt (aeidt4@uwo.ca)\n\n"
	printf "\nUsage: %s: -H remote_host -p port -s service_name\n\n  -H    Name or IP of remote host\n  -p    UDP port number to check\n  -s    Name of the service that should be listening on the port\n\n" $0
}

host=
port=
service=

# Print User ID
#id > /tmp/usr-id

while getopts H:p:s: o
do
	case $o in
		H)
			host="$OPTARG"
			;;
		p)
			port="$OPTARG"
			;;
		s)
			service="$OPTARG"
			;;
		?)
			usage
			exit ${STATE_UNKNOWN}
			;;
	esac
done

if [ x$host = x -o x$port = x -o x$service = x ]; then
	usage
	exit ${STATE_UNKNOWN}
fi

# execute as sudo, needs SElinux context 'nagios_unconfined_plugin_exec_t'
# Replace Charset by any Char
result=`sudo nmap -sU -p $port -P0 $host`

f_result=`echo $result | egrep -o "${port}/udp.*Nmap done"`
p_result=`echo $f_result | awk '{print $1" "$2" "$3}'`

if [ `echo $f_result | egrep -c 'open'` -gt 0 ]; then

	nmap_service=`echo $f_result | awk '{print $3}'`
	if [ $nmap_service = $service ]; then
        	echo "OK: $service listening on port $port: $p_result"
        	exit ${STATE_OK}
	elif [ $nmap_service = "unknown" ]; then
		echo "CRITICAL: Unknown service listening on port $port: $p_result"
		exit ${STATE_CRITICAL}
	else
                echo "WARNING: Incorrect service $nmap_service listening on port $port: $p_result"
                exit ${STATE_WARNING}
	fi
fi

echo "CRITICAL: $p_result"
exit ${STATE_CRITICAL}
