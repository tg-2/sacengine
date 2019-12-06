#!/bin/bash
# TODO: figure out how to pass only -O -inline
d=$(date +%Y-%m-%d-%H-%M-%S)
wine ./ldc2-1.16.0-windows-x64/bin/dub.exe build -b release-debug --compiler=./ldc2-1.16.0-windows-x64/bin/ldc2.exe
cp 3d.exe SacEngine-$d.exe
strip SacEngine-$d.exe
zip SacEngine-$d.zip SacEngine-$d.exe SDL2.dll freetype.dll libmpg123-0.dll settings.txt
