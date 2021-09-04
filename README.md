sacengine
=====
A new engine for the game [Sacrifice](https://en.wikipedia.org/wiki/Sacrifice_(video_game)) from Shiny Entertainment.

Discord server: https://discord.gg/CTkCPnZ (#sacengine-dev channel)

Any help is welcome!

Building
-----------

Building sacengine from scratch:
Set up some D compiler, ideally LDC, version 1.23 is known to work:
https://github.com/ldc-developers/ldc/releases/tag/v1.23.0

$ git clone https://github.com/tg-2/sacengine
cd sacengine
$ git submodule init
$ git submodule update
$ dub build -b release-debug

If you simply extract the binary release, there are some build scripts for linux already in the repository, on Windows the following command might work:

./ldc2-1.23.0-windows-x64/bin/dub.exe build -b release-debug --compiler=./ldc2-1.23.0-windows-x64/bin/ldc2.exe

To run the engine, symlink your maps and data folder into the sacengine directory, check settings.txt for additional options.

On Windows, you may need the following additional DLLs:
https://openal.org/downloads/
