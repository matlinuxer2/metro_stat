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

function grab_pdf_urls(){
    local html_file="$1"

    cat $html_file  \
        | grep "href.*pdf.*運量" \
        | sed -e 's/.*href="//g' -e 's/pdf".*/pdf/g'  \
        | sort
}

function grab_data_from_pdf(){
    local pdf_file="$1"

    local cnt=$( pdftotext $pdf_file /dev/stdout | grep -P '\d+\/\d+\/\d+' | wc -l )
    for (( i=1; i<=$cnt ; i++ ))
    do
        str_date=$( pdftotext $pdf_file /dev/stdout | grep -P '\d+\/\d+\/\d+' | head -n $i | tail -1 )
        str_num=$( pdftotext $pdf_file /dev/stdout | grep -P '總運量' -A 100 | grep -v '總運量' | head -n $i | tail -1 | sed -e 's/,//g')

        printf "%s,%s\n" "$str_date" "$str_num"
    done

}

for hh in `ls *.html`
do
  for ff in $(grab_pdf_urls $hh)
  do
      # 如果沒有該檔案沒抓過，重新抓一個下來
      ff_name=$(basename $ff)
      ff_local="./pdfs/$ff_name"
      [ -e "$ff_local" ] || {
        install -D /dev/null "$ff_local"
        curl --output "$ff_local" "$ff"
      }
  done
done

for ff_local in $( find ./pdfs/ -type f | sort )
do
    echo $ff_local
    grab_data_from_pdf $ff_local \
      | while read -r line
        do
            d1=$( echo "$line" | sed -e 's/,/ /g'  | awk '{print $1}' )
            d1=$( convert_date $d1 )
            d2=$( echo "$line" | sed -e 's/,/ /g'  | awk '{print $2}' )
            feed_data "krt.num" "$d1" "$d2"
        done
done
