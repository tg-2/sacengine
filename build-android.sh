#!/bin/bash
dub build -b debug --compiler=./ldc2-1.41.0-linux-x86_64/bin/ldc2 --arch=aarch64--linux-android $@
