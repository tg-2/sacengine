#!/bin/bash
# TODO: figure out how to pass only -O -inline
d=$(date +%Y-%m-%d-%H-%M-%S)
#wine ./ldc2-1.28.0-windows-x64/bin/dub.exe build --compiler=./ldc2-1.28.0-windows-x64/bin/ldc2.exe && bbe -e "s/\x5C$USER\x5C/\x5Ctg___\x5C/" 3d.exe > tmp_3d_tmp && mv tmp_3d_tmp 3d.exe
dub build -b debug --compiler=./ldc2-1.28.0-linux-x86_64/bin/ldc2 --arch=x86_64-windows-msvc && bbe -e "s/\x2F$USER\x2F/\x2Ftg___\x2F/" 3d.exe > tmp_3d_tmp && mv tmp_3d_tmp 3d.exe
# cp 3d.exe SacEngineDebug-$d.exe
# strip SacEngineDebug-$d.exe
# zip SacEngineDebug-$d.zip SacEngineDebug-$d.exe SDL2.dll freetype.dll libmpg123-0.dll settings.txt hotkeys.txt
