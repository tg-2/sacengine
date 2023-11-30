#!/bin/bash
d=${1:-$(date +%Y-%m-%d-%H-%M-%S)}
ssh tg@sacengine-osx-builder -C "eval \"\$(/opt/homebrew/bin/brew shellenv)\" && cd ~/Desktop/sacengine && ./release-osx.sh $d"
rsync -arzihv tg@sacengine-osx-builder:"~/Desktop/sacengine/SacEngine-$d-osx.zip" .
