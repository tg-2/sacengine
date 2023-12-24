#!/bin/bash
dub build --config=application-audioformats -b release-debug --compiler=./ldc2-1.35.0-osx-arm64/bin/ldc2 && ./anonymize-build.sh 3d
