#!/bin/bash
docker run --rm -v "$(pwd)":/src -v "$HOME/.dub":/root/.dub reavershark/ldc2-rpi:aarch64 dub build -b debug $@ && ./anonymize-build.sh 3d
