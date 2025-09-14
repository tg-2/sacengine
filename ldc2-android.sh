#!/bin/bash
./ldc2-1.41.0-linux-x86_64/bin/ldc2 -mtriple=aarch64--linux-android

# in ldc2-1.41.0-linux-x86_64/etc/ldc2.conf:

# "aarch64-.*-linux-android":
# {
#     switches = [
#       "-defaultlib=phobos2-ldc,druntime-ldc",
#       "-link-defaultlib-shared=false",
#       "-gcc=%%ldcbinarypath%%/../../android-ndk-r28c/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android30-clang"
#     ];
#     lib-dirs = [
#         "%%ldcbinarypath%%/../../ldc2-1.41.0-android-aarch64/lib",
#     ];
#     rpath = "";
# };

