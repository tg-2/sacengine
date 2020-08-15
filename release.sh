#!/bin/bash
# TODO: figure out how to pass only -O -inline
d=$(date +%Y-%m-%d-%H-%M-%S)
./build-windows-release.sh
cp 3d.exe SacEngine-$d.exe
strip SacEngine-$d.exe
zip SacEngine-$d.zip SacEngine-$d.exe SDL2.dll freetype.dll libmpg123-0.dll settings.txt hotkeys.txt

./build-release.sh
cp 3d SacEngine-$d
strip SacEngine-$d
zip SacEngine-$d-linux.zip SacEngine-$d