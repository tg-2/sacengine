#!/bin/bash

for f in $(find $1/ -name '*.MRMM' -type f; find $1/ -name '*.3DSM' -type f; find $1/ -name '*.SXMD' -type f); do
    echo $f
    ./3d $f
done
