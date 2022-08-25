#!/bin/bash

##The location of blocklists
ListAddress="/home/.transmission/blocklists.txt"

TempList=`cat $ListAddress`

if [ "$TempList" ]; then
    for EachIp in $TempList; do
        docker exec transmission /bin/bash -c "ip route delete $EachIp"
    done
    logger -t tr_del_block -- Refresh blocklists
    rm $ListAddress
    touch $ListAddress
fi

exit 0
