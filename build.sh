#!/bin/bash
dub build && bbe -e "s/\x2F$USER\x2F/\x2Ftg___\x2F/" 3d > tmp_3d_tmp && mv tmp_3d_tmp 3d && chmod +x 3d
