#!/bin/bash
# TODO: figure out how to pass only -O -inline
dub build -b release-debug --compiler=./ldc2-1.16.0-linux-x86_64/bin/ldc2
