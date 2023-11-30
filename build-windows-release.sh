#!/bin/bash
# wine ./ldc2-1.28.0-windows-x64/bin/dub.exe build -b release-debug --compiler=./ldc2-1.28.0-windows-x64/bin/ldc2.exe && ./anonymize-build.sh 3d.exe
dub build -b release-debug --compiler=./ldc2-1.28.0-linux-x86_64/bin/ldc2 --arch=x86_64-windows-msvc $@ && ./anonymize-build.sh 3d.exe
