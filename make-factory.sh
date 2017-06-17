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
        printf "%s %s %s\n"  "$val_name" "$val_val" "$val_timestamp" \
        | nc -q 0 127.0.0.1 2003
    else
        printf "%s %s %s\n"  "$val_name" "$val_val" "$val_timestamp"
    fi
}

export PATH=".:$PATH"

python grab_data_from_web.py \
      | while read -r line
      do
        echo $line
        d1=$( echo "$line" | awk '{print $2}' )
        d1=$( convert_date "${d1}/12/31" )
        d2=$( echo "$line" | awk '{print $1}' )
        d3=$( echo "$line" | awk '{print $3}' )
        ( echo $line | grep -e '年底從業員工人數' > /dev/null 2>&1 ) &&  feed_data "econ3.workers.$d3" "$d1" "$d2"
        ( echo $line | grep -e '營運中工廠家數' > /dev/null 2>&1 ) &&  feed_data "econ3.factories.$d3" "$d1" "$d2"
      done
