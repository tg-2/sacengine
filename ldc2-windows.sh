#!/bin/bash
./ldc2-1.35.0-linux-x86_64/bin/ldc2 -mtriple=x86_64-windows-msvc $@

# in ldc2-1.35.0-linux-x86_64/etc/ldc2.conf:

# "x86_64-.*-windows-msvc":
# {
#     switches = [
#         "-defaultlib=phobos2-ldc,druntime-ldc",
#     ];
#     lib-dirs = [
#         "%%ldcbinarypath%%/../../ldc2-1.35.0-windows-x64/lib",
#     ];
# };
