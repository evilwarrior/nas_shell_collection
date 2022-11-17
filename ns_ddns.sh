#!/bin/bash

##IPv6 regex
RE='^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))$'

##Domain name:
DOMAIN=""

##Host name (subdomain). Optional.
HOST=""

##APIKEY obtained from Namesilo:
APIKEY=""

## Do not edit lines below ##

##Time IP last updated or 'No IP change' log message output
IP_TIME="/var/tmp/.ns_ddns-time"

##Interface of IPv6
IF_NAME=""

##How often to output 'No IP change' log messages
NO_IP_CHANGE_TIME=259200

##Response from Namesilo
RECORDS="/tmp/namesilo_records.xml"
RESPONSE="/tmp/namesilo_response.xml"

##Get the current public IP by localhost
#  mngtmpaddr - kernel manage temporary address on behalf of Privacy Extensions (RFC3041) for hiding fixed address.
CUR_IP=`ip addr show $IF_NAME | grep mngtmpaddr | grep -oP '(?<=inet6 ).*?(?=/64)' | sed -n '1p'`
## Exit if CUR_IP is not IPv6
if [[ ! $CUR_IP =~ $RE ]]; then
    logger -t ns_ddns -- CUR_IP{$CUR_IP} is not IPv6!
    exit 1
fi


##Fetch Host id and value in Namesilo:
curl -s "https://www.namesilo.com/api/dnsListRecords?version=1&type=xml&key=$APIKEY&domain=$DOMAIN" > $RECORDS
## Exit if fetch records failed
ERRNO=$?
if [ $ERRNO -ne 0 ]; then
    logger -t ns_ddns -- Fetch $DOMAIN records from NameSilo failed!
    exit 1
fi
RECORD_ID=`xmllint --xpath "//namesilo/reply/resource_record/record_id[../host/text() = '$HOST.$DOMAIN' ]" $RECORDS | grep -oP '(?<=<record_id>).*?(?=</record_id>)'`
KNOWN_IP=`xmllint --xpath "//namesilo/reply/resource_record/value[../host/text() = '$HOST.$DOMAIN' ]" $RECORDS | grep -oP '(?<=<value>).*?(?=</value>)'`

##See if the IP has changed
if [ "$CUR_IP" != "$KNOWN_IP" ]; then
    logger -t ns_ddns -- Public IP changed to $CUR_IP

    ##Update DNS record in Namesilo:
    if [ -n "$RECORD_ID" ]; then
        curl -s "https://www.namesilo.com/api/dnsUpdateRecord?version=1&type=xml&key=$APIKEY&domain=$DOMAIN&rrid=$RECORD_ID&rrhost=$HOST&rrvalue=$CUR_IP&rrttl=3600" > $RESPONSE
    else
        curl -s "https://www.namesilo.com/api/dnsAddRecord?version=1&type=xml&key=$APIKEY&domain=$DOMAIN&rrtype=AAAA&rrhost=$HOST&rrvalue=$CUR_IP&rrttl=3600" > $RESPONSE
    fi
    ## Exit if add/update record failed
    ERRNO=$?
    if [ $ERRNO -ne 0 ]; then
        logger -t ns_ddns -- Modification of $HOST.$DOMAIN record failed!
        exit 1
    fi
    RESPONSE_CODE=`xmllint --xpath "//namesilo/reply/code/text()"  $RESPONSE`
    case $RESPONSE_CODE in
        300)
            date "+%s" > $IP_TIME
            logger -t ns_ddns -- Update success. Now $HOST.$DOMAIN IP address is $CUR_IP;;
        *)
            ## put the old IP back, so that the update will be tried next time
            DETAIL=`xmllint --xpath "//namesilo/reply/detail/text()"  $RESPONSE`
            logger -t ns_ddns -- DDNS update failed code $RESPONSE_CODE! with detail {$DETAIL};;
    esac

else
    ## Only log all these events NO_IP_CHANGE_TIME after last update
    [ $(date "+%s") -gt $((($(cat $IP_TIME)+$NO_IP_CHANGE_TIME))) ] &&
        logger -t ns_ddns -- NO IP change &&
        date "+%s" > $IP_TIME
fi

exit 0
