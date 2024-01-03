#!/bin/bash
dub build -b release-debug --compiler=./ldc2-1.35.0-linux-x86_64/bin/ldc2 --arch=aarch64--linux-android $@
