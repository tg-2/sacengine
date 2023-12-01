#!/bin/bash
d=${1:-$(date +%Y-%m-%d-%H-%M-%S)}
./build-release.sh
cp 3d SacEngine-current
cp 3d SacEngine-$d
strip SacEngine-$d
zip SacEngine-$d-linux.zip libzt.so SacEngine-$d
