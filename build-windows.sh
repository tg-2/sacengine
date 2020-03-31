#!/bin/bash
# TODO: figure out how to pass only -O -inline
d=$(date +%Y-%m-%d-%H-%M-%S)
wine ./ldc2-1.16.0-windows-x64/bin/dub.exe build --compiler=./ldc2-1.16.0-windows-x64/bin/ldc2.exe
# cp 3d.exe SacEngineDebug-$d.exe
# strip SacEngineDebug-$d.exe
# zip SacEngineDebug-$d.zip SacEngineDebug-$d.exe SDL2.dll freetype.dll libmpg123-0.dll settings.txt hotkeys.txt
