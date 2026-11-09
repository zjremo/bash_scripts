#!/usr/bin/env bash

i=0
while read line; do
    echo "line: $line"
    ((i++))
done< <(cat data/sample.txt)

printf "lines count: %d\n" "$i"

echo "------error operation:------"
i=0
cat data/sample.txt | while read line; do
    echo "line: $line"
    ((i++))
    echo "now i: $i"
done
printf "file.txt word counts: $i\n"
