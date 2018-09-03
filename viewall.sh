#!/bin/bash

for f in $(ls $@/*/*.{MRMM,3DSM}); do
    echo $f
    ./3d $f
done
