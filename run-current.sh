#!/bin/bash
gdb -ex=r -ex=q --args ./SacEngine-current $@
