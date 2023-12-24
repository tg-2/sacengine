#!/bin/bash
# TODO: figure out how to pass only -O -inline
d=$(date +%Y-%m-%d-%H-%M-%S)
#wine ./ldc2-1.35.0-windows-x64/bin/dub.exe build --compiler=./ldc2-1.35.0-windows-x64/bin/ldc2.exe && ./anonymize-build.sh 3d.exe
dub build -b debug --compiler=./ldc2-1.35.0-linux-x86_64/bin/ldc2 --arch=x86_64-windows-msvc $@ && ./anonymize-build.sh 3d.exe
# cp 3d.exe SacEngineDebug-$d.exe
# strip SacEngineDebug-$d.exe
# zip SacEngineDebug-$d.zip SacEngineDebug-$d.exe SDL2.dll freetype.dll libmpg123-0.dll settings.txt hotkeys.txt
