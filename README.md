sacengine
=========
Engine reimplementation for the game [Sacrifice](https://en.wikipedia.org/wiki/Sacrifice_(video_game)) from Shiny Entertainment.

Discord server: https://discord.gg/CTkCPnZ (#sacengine-dev channel)  
Trello board: https://trello.com/b/ZcrTsa4O/sacengine

Any help is welcome!

Building
-----------

Building sacengine from scratch:
Set up some D compiler, ideally LDC, version 1.41.0 is known to work:
https://github.com/ldc-developers/ldc/releases/tag/v1.41.0

```bash
$ git clone --recursive https://github.com/tg-2/sacengine
$ cd sacengine
$ dub build -b release-debug
```

If you simply extract the binary release, there are some build scripts for linux already in the repository, on Windows the following command might work:

```
ldc2-1.41.0-windows-x64\bin\dub.exe build -b release-debug --compiler=./ldc2-1.41.0-windows-x64/bin/ldc2.exe
```

To run the engine, symlink your maps and data folder into the sacengine directory, check settings.txt for additional options. (Alternatively, put the executable in the Sacrifice directory.)

Local Christmas hats
--------------------

Use `--local-christmas-hat` on the command line or in `settings.txt` to add Santa hats to the original Charlotte, Eldred, Sorcha, Ambassador Buta and Hachimen models. The option is disabled by default; use `--no-local-christmas-hat` to disable it explicitly. The hats are rendered locally and do not change gameplay state or send a setting to other players. Hat placement is experimental, especially for Buta and Hachimen.

For an approximate offline preview of Buta's hat, run `python tools/preview_buta.py --frame 15 --scale 1.15` from the repository root. It requires NumPy, SciPy, Matplotlib and locally installed game data in `data`. The preview uses an animated pose and an approximate untextured mesh, so it does not replace checking the result in game. It only reads the game data and writes a PNG into the repository root.

On Windows, you may need the following additional DLLs:
* https://openal.org/downloads/
* https://mpg123.org/download/win64/1.29.2/
* https://www.libsdl.org/download-2.0.php
* https://github.com/ubawurinna/freetype-windows-binaries
