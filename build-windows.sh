#!/bin/bash
# TODO: figure out how to pass only -O -inline
d=$(date +%Y-%m-%d-%H-%M-%S)
wine ./ldc2-1.24.0-windows-x64/bin/dub.exe build --compiler=./ldc2-1.24.0-windows-x64/bin/ldc2.exe && bbe -e "s/\x5C$USER\x5C/\x5Ctg___\x5C/" 3d.exe > tmp_3d_tmp && mv tmp_3d_tmp 3d.exe
# cp 3d.exe SacEngineDebug-$d.exe
# strip SacEngineDebug-$d.exe
# zip SacEngineDebug-$d.zip SacEngineDebug-$d.exe SDL2.dll freetype.dll libmpg123-0.dll settings.txt hotkeys.txt
