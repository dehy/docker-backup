#!/bin/sh

rm -rf /data/*

no_of_files=10;
counter=1;
while [[ $counter -le $no_of_files ]];
do echo Creating file no $counter;
    dd bs=1024 count=$RANDOM skip=$RANDOM if=/dev/random of=/data/random-file.$counter;
    let "counter += 1";
done

tail -f /dev/null
