#!/usr/bin/env bash

for ((i=0;i<5;i++)); do 
    printf "hello, this is $i\n"
done

while [[ -f data/loop_test.txt ]]; do
    echo "data/sample.txt exists, and it's a regular file"
    sleep 2
done

printf "data/sample.txt has been removed!\n"

until [[ -f data/loop_test.txt ]]; do
    echo "data/sample.txt not exists"
    sleep 2
done

printf "data/sample.txt exists, and it's a regular file\n"
