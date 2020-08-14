#!/bin/bash
dub build -b release-debug --compiler=./ldc2-1.16.0-linux-x86_64/bin/ldc2 && bbe -e "s/\x2F$USER\x2F/\x2Ftg___\x2F/" 3d > tmp_3d_tmp && mv tmp_3d_tmp 3d && chmod +x 3d
