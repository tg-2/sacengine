#!/bin/bash
d=${1:-$(date +%Y-%m-%d-%H-%M-%S)}
./build-osx-release.sh
cp 3d SacEngine-current
cp 3d SacEngine-$d
strip SacEngine-$d
zip SacEngine-$d.zip SacEngine-$d libSDL2.dylib libfreetype.6.dylib libzt.dylib settings.txt hotkeys.txt
