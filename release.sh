#!/bin/bash
d=$(date +%Y-%m-%d-%H-%M-%S)
echo $d
./release-windows.sh $d & ./release-linux.sh $d
wait
