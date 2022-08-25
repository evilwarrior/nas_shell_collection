#!/bin/bash

##IPv6 regex
RE='^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))$'

##Interface of IPv6
IF_NAME=""

##Set Host EUI-64 generated IP
PERM_IP=`ip addr show $IF_NAME | grep mngtmpaddr | grep -oP '(?<=inet6 ).*?(?=/64)'`

##Set EUI-64 generated IP from transmission container
MAC=`docker inspect --format='{{.NetworkSettings.Networks.macnet.MacAddress}}' transmission`
PREFIX=$(echo $PERM_IP | awk -F':' '{ print $1":"$2":"$3":"$4":" }')
TRAN_IP=$(python3 -c "mac=[int(x, 16) for x in '$MAC'.split(':')]; print('%s%02x%02x:%02xff:fe%02x:%02x%02x' % tuple(['$PREFIX'] + [mac[0]^2] + mac[1:]))" "$@")

if [[ $PERM_IP =~ $RE ]]; then
    ##Update ip6tables
    ip6tables -R INPUT 1 -p tcp -m tcp -d $PERM_IP --dport 12345 -j ACCEPT
    ip6tables -R INPUT 2 -p udp -m udp -d $PERM_IP --dport 12345 -j ACCEPT
else
    ##Log if IP is not IPv6
    logger -t ip6tables_update -- PERM_IP{$PERM_IP} is not IPv6!
fi

if [[ $TRAN_IP =~ $RE ]]; then
    ##Update ip6tables
    ip6tables -R INPUT 3 -p tcp -m tcp -d $TRAN_IP --dport 12345 -j ACCEPT
    ip6tables -R INPUT 4 -p udp -m udp -d $TRAN_IP --dport 12345 -j ACCEPT
else
    ##Log if IP is not IPv6
    logger -t ip6tables_update -- TRAN_IP{$TRAN_IP} is not IPv6!
fi

exit 0
