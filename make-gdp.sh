#!/usr/bin/env bash

URL2="http://www.dgbas.gov.tw/public/data/open/Stat/NA/NA8102A5A.xml"
URL3="http://www.dgbas.gov.tw/public/data/open/Stat/NA/NA8102A6Q.xml"

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

function get_data(){
    uu="$1"
    ff=$(basename $uu)

    test -e $ff || {
        curl --silent "$uu" | iconv -f utf16le -t utf8 | sed -e 's/utf-16/utf-8/g' > $ff
    }
}

function parse_data_99(){
    local period_key="$1"

    [ "$period_key" = "年" ] && ff=$(basename $URL2)
    [ "$period_key" = "季" ] && ff=$(basename $URL3)

    test -e $ff && {


python -c "$(cat <<EOPY
import xml.etree.ElementTree
import datetime
import sys

def parse_into_matrix(xpath_str,val_matrix):
    for item in root.findall(xpath_str):
        if item.items()[0][0] == "OBS_VALUE" :
            val = item.items()[0][1]
            ttt = item.items()[1][1]
        else:
            val = item.items()[1][1]
            ttt = item.items()[0][1]

        val_matrix[ttt] = val


tree = xml.etree.ElementTree.parse("$ff")
root = tree.getroot()

var_Y = {}
val_C = {}
val_I = {}
val_G = {}
val_X = {}
val_M = {}
val_F = {}
val_F1 = {}

common_xpath_substr = "SeriesProperty[@TableName=\"國內生產毛額依支出分-${period_key}(1981以後)\"][@SERIESTYPE=\"原始值\"]/Obs"

parse_into_matrix( './/Series[@ITEM="當期價格(新台幣百萬元)-6.GDP"]/'+common_xpath_substr , var_Y )
parse_into_matrix( './/Series[@ITEM="當期價格(新台幣百萬元)-1.民間消費"]/'+common_xpath_substr, val_C )
parse_into_matrix( './/Series[@ITEM="當期價格(新台幣百萬元)-2.政府消費"]/'+common_xpath_substr, val_G )
parse_into_matrix( './/Series[@ITEM="當期價格(新台幣百萬元)-4.商品及服務輸出:4.1--4.2合計"]/'+common_xpath_substr , val_X )
parse_into_matrix( './/Series[@ITEM="當期價格(新台幣百萬元)-5.商品及服務輸入:5.1--5.2合計"]/'+common_xpath_substr , val_M )
parse_into_matrix( './/Series[@ITEM="當期價格(新台幣百萬元)-3.資本形成:3.1--3.2合計"]/'+common_xpath_substr, val_F )
parse_into_matrix( './/Series[@ITEM="當期價格(新台幣百萬元)-3.1固定資本形成"]/'+common_xpath_substr, val_F1 )

for tt in var_Y.keys():
    var_y = float(var_Y[tt])
    var_c = float(val_C[tt])
    var_g = float(val_G[tt])
    var_x = float(val_X[tt])
    var_m = float(val_M[tt])
    var_i = var_y - var_c - var_g - ( var_x - var_m )
    var_nx = var_x - var_m
    var_f = float(val_F[tt])
    var_f1 = float(val_F1[tt])

    sys.stdout.write( "%s %s %s\n" % (var_y, tt, "GDP" ))
    sys.stdout.write( "%s %s %s\n" % (var_c, tt, "民間消費" ))
    sys.stdout.write( "%s %s %s\n" % (var_g, tt, "政府消費" ))
    sys.stdout.write( "%s %s %s\n" % (var_x, tt, "出口" ))
    sys.stdout.write( "%s %s %s\n" % (var_m, tt, "進口" ))
    sys.stdout.write( "%s %s %s\n" % (var_i, tt, "民間投資" ))
    sys.stdout.write( "%s %s %s\n" % (var_nx, tt, "淨出口" ))
    sys.stdout.write( "%s %s %s\n" % (var_f, tt, "資本形成" ))
    sys.stdout.write( "%s %s %s\n" % (var_f1, tt, "固定資本形成" ))

EOPY
)"


    }
}


function filter_data_99(){
    local period_key="$1"
    local keyword="$2"
    local rec_name="$3"

    parse_data_99 "$period_key" \
      | grep -e "\s${keyword}\s*" \
      | while read -r line
      do
        echo $line
        d1=$( echo "$line" | awk '{print $2}' )
        [ "$period_key" = "季" ] && { d1=$( echo "$d1" | sed -e 's#Q1#/03/31#g' -e 's#Q2#/06/30#g' -e 's#Q3#/09/30#g' -e 's#Q4#/12/31#g' ); }
        [ "$period_key" = "年" ] && { d1="${d1}/12/31"; }
        d1=$( convert_date "${d1}" )
        d2=$( echo "$line" | awk '{print $1}' )
        feed_data "$rec_name" "$d1" "$d2"
      done
}

get_data $URL2
get_data $URL3

filter_data_99 "年" "民間投資"     "econ.investment"
filter_data_99 "年" "民間消費"     "econ.consumption"
filter_data_99 "年" "GDP"          "econ.GDP"
filter_data_99 "年" "出口"         "econ.exports"
filter_data_99 "年" "進口"         "econ.imports"
filter_data_99 "年" "政府消費"     "econ.government_spending"
filter_data_99 "年" "淨出口"       "econ.net_exports"
filter_data_99 "年" "資本形成"     "econ.capital_formation"
filter_data_99 "年" "固定資本形成" "econ.capital_formation1"

filter_data_99 "季" "民間投資"     "econ2.investment"
filter_data_99 "季" "民間消費"     "econ2.consumption"
filter_data_99 "季" "GDP"          "econ2.GDP"
filter_data_99 "季" "出口"         "econ2.exports"
filter_data_99 "季" "進口"         "econ2.imports"
filter_data_99 "季" "政府消費"     "econ2.government_spending"
filter_data_99 "季" "淨出口"       "econ2.net_exports"
filter_data_99 "季" "資本形成"     "econ2.capital_formation"
filter_data_99 "季" "固定資本形成" "econ2.capital_formation1"
