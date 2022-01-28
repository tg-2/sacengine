#!/bin/bash
d=$(date +%Y-%m-%d-%H-%M-%S)
./build-windows-release.sh
cp 3d.exe SacEngine-$d.exe
strip SacEngine-$d.exe
zip SacEngine-$d.zip SacEngine-$d.exe SDL2.dll OpenAL32.dll wrap_oal.dll freetype.dll libmpg123-0.dll settings.txt hotkeys.txt
