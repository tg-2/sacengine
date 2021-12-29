event=1v1-horse-test

map='maps/(2) Ferry.scp'
# map='maps/(2) WM-ColdKiss.scp'
# map='maps/(2) TM-Chain of Being.scp'
# map='maps/(2) TM-Glaciers.scp'

#map='maps/(3) Gladiator.scp'
#map='maps/(3) Rotation.scp'
#map='maps/(4) EM-Slaughter Only.scp'

#map='maps/(4) Ferry.scp'
#map='maps/(4) Ferry.scp'

#map=--map-list=maps-1v1.txt
#map=--map-list=maps-2v2.txt
#map=--map-list=maps-3ffa.txt
echo $map
#map='maps/(2) Oval kopia.scp'

level=4
souls=12
wizard=sorcha
NAME=$(date +%Y-%m-%d-%H-%M-%S)
echo "run" > /tmp/cmds
#gdb -x /tmp/cmds --args ./SacEngine-current --host --resolution=1080 --level=$level --souls=$souls --wizard=sorcha --souls=$souls "$map" --record=replays/"$event"-"$NAME".rcp --random-spellbooks --shuffle-sides
./build-release.sh && gdb -x /tmp/cmds --args ./3d --host --resolution=1080 --level=$level --souls=$souls --wizard=sorcha --souls=$souls "$map" --record=replays/"$event"-"$NAME".rcp --random-spellbooks --shuffle-sides
# ./build-ldc.sh && gdb -x /tmp/cmds --args ./3d --host --resolution=1080 --level=$level --souls=$souls --wizard=sorcha --souls=$souls "$map" --record=replays/"$event"-"$NAME".rcp --random-spellbooks --shuffle-sides
#wine explorer /desktop=1920x1080 SacEngine-2021-12-26-20-56-33.exe --host --resolution=1080 --level=$level --souls=$souls --wizard=sorcha --souls=$souls "$map" --record=replays/"$event"-"$NAME".rcp --random-spellbooks --shuffle-sides
