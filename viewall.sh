#!/bin/bash

for f in $@/*; do
    ./3d $f/*.MRMM
done
