sacengine
=========
Engine reimplementation for the game [Sacrifice](https://en.wikipedia.org/wiki/Sacrifice_(video_game)) from Shiny Entertainment.

Discord server: https://discord.gg/CTkCPnZ (#sacengine-dev channel)  
Trello board: https://trello.com/b/ZcrTsa4O/sacengine

Any help is welcome!

Building
-----------

Building sacengine from scratch:
Set up some D compiler, ideally LDC, version 1.28.0 is known to work:
https://github.com/ldc-developers/ldc/releases/tag/v1.28.0

```bash
$ git clone https://github.com/tg-2/sacengine
$ cd sacengine
$ git submodule init
$ git submodule update
$ dub build -b release-debug
```

If you simply extract the binary release, there are some build scripts for linux already in the repository, on Windows the following command might work:

```
ldc2-1.28.0-windows-x64\bin\dub.exe build -b release-debug --compiler=./ldc2-1.28.0-windows-x64/bin/ldc2.exe
```

To run the engine, symlink your maps and data folder into the sacengine directory, check settings.txt for additional options. (Alternatively, put the executable in the Sacrifice directory.)

On Windows, you may need the following additional DLLs:
* https://openal.org/downloads/
* https://mpg123.org/download/win64/1.29.2/
* https://www.libsdl.org/download-2.0.php
* https://github.com/ubawurinna/freetype-windows-binaries
