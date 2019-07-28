#!/bin/bash
# TODO: figure out how to pass only -O -inline
wine ./ldc2-1.16.0-windows-x64/bin/dub.exe build -b release-debug --compiler=./ldc2-1.16.0-windows-x64/bin/ldc2.exe
