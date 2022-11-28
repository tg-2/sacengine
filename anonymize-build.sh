#!/bin/bash
user=$(echo "$USER" | sed 's/./_/g' | sed 's/^../tg/g')
bbe -e "s/\x2F$USER\x2F/\x2F$user\x2F/" "$1" > tmp_"$1"_tmp && mv tmp_"$1"_tmp "$1" && chmod +x "$1"
