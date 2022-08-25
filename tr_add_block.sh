#!/bin/bash

##Username for Transmission RPC
Username=
##Password for Transmission RPC
Password=
##Specify clients which would block, clients separate with space and are case insensitive
ClientList=(xunlei thunder "-xl" "-sd" "-gt" "-xf" aria2 "-dl" "-qd" qq "-bn" cacao)
##The location of blocklists
ListAddress="/home/.transmission/blocklists.txt"

for CertainClient in ${ClientList[@]}; do
    TempList=$TempList$'\n'`docker exec transmission /bin/bash -c "transmission-remote --auth $Username:$Password -t all -ip" | grep -i -- $CertainClient | awk '{print $1}' | xargs -L1 -I {ip} echo "{ip}"`
done

for EachIp in $TempList; do
    if [[ ! $EachIp == `grep $EachIp $ListAddress` ]]; then
        docker exec transmission /bin/bash -c "ip route add blackhole $EachIp"
        echo "$EachIp" >> $ListAddress
        logger -t tr_add_block -- $EachIp not exists, adding to blocklists
    fi
done

exit 0
