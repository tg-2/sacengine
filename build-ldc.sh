#!/bin/bash
dub build -b debug --compiler=./ldc2-1.28.0-linux-x86_64/bin/ldc2 $@ && ./anonymize-build.sh 3d
