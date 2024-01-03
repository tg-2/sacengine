#!/bin/bash
./ldc2-1.35.0-linux-x86_64/bin/ldc2 -mtriple=aarch64--linux-android

# in ldc2-1.35.0-linux-x86_64/etc/ldc2.conf:

# "aarch64-.*-linux-android":
# {
#     switches = [
#         "-defaultlib=phobos2-ldc,druntime-ldc",
# 	"-link-defaultlib-shared=false",
# 	"-gcc=%%ldcbinarypath%%/../../android-ndk-r21e/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang",
#     ];
#     lib-dirs = [
#         "%%ldcbinarypath%%/../../ldc2-1.35.0-android-aarch64/lib",
#     ];
#     rpath = "";
# };

