#!/bin/bash
# --DRT-trapExceptions=0
gdb -ex=r -ex=q --args ./3d "$@"
