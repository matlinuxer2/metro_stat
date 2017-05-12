#!/usr/bin/env bash

function convert_date(){
    local input="$1"
python -c "$(cat <<EOPY
ss='$input'
rr=ss.split('/')
if int(rr[0]) < 200:
    rr[0] = str(int(rr[0])+1911)
print('/'.join(rr))
EOPY
)"
}

function feed_data(){
    local val_name="$1"
    local val_date="$2"
    local val_val="$3"

    local val_timestamp=$( echo "<?php date_default_timezone_set('Asia/Taipei'); echo( strtotime(\"$val_date 23:59 \") ); ?>" | php )

    echo "$val_date $val_val"

    # 先偵測有沒有開 influxdb / graphite
    if [ "$has_port" = "" ]; then
        nc -z 127.0.0.1 2003
        if [ $? -eq 0 ] ; then
            has_port="yes"
        else
            has_port="no"
        fi
    fi

    if [ "$has_port" = "yes" ] ; then
        printf "taiwan_data.%s %s %s\n"  "$val_name" "$val_val" "$val_timestamp" \
        | nc -q 0 127.0.0.1 2003
    else
        printf "taiwan_data.%s %s %s\n"  "$val_name" "$val_val" "$val_timestamp"
    fi
}

function grab_list_from_url(){
    curl -s "http://www.metro.taipei/ct.asp?xItem=1058535&CtNode=70073&mp=122035" | grep RidershipCounts | sed -e 's/.*href="//g' -e 's/htm".*/htm/g'
}


function grab_data_from_html(){
    local ff_local="$1"

    cat "$ff_local" | iconv -f big5 -t utf8 | html2text \
        | grep -P '\d+\/\d+\/\d+' \
        | awk '{print $1 , $3}'
}

for uu in $(grab_list_from_url )
do
    uu_local="./data-tp/$(basename $uu)"
    [ -e "$uu_local" ] || {
        install -D /dev/null "$uu_local"
        curl --output "$uu_local" "$uu"
    }

    grab_data_from_html "$uu_local" \
      | while read -r line
        do
            d1=$( echo "$line" | sed -e 's/,//g'  | awk '{print $1}' )
            d1=$( convert_date $d1 )
            d2=$( echo "$line" | sed -e 's/,//g'  | awk '{print $2}' )
            feed_data "mrt.num" "$d1" "$d2"
        done
done
