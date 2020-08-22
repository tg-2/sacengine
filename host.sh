event=1v1-horse

# map='maps/(2) Ferry.scp'
# map='maps/(2) WM-ColdKiss.scp'
# map='maps/(2) TM-Chain of Being.scp'
# map='maps/(2) TM-Glaciers.scp'

#map='maps/(3) Gladiator.scp'
#map='maps/(3) Rotation.scp'
#map='maps/(4) EM-Slaughter Only.scp'

#map='maps/(4) Ferry.scp'
#map='maps/(4) Ferry.scp'

map=--map-list=maps-1v1.txt
#map=--map-list=maps-2v2.txt
echo $map
#map='maps/(2) Oval kopia.scp'

level=1
souls=12
wizard=sorcha
NAME=$(date +%Y-%m-%d-%H-%M-%S)
echo "run" > /tmp/cmds
#gdb -x /tmp/cmds --args ./SacEngine-current --resolution=1080 --cursor-size=64 --level=$level --souls=$souls --wizard=sorcha --souls=$souls "$map" --random-spellbooks --shuffle-sides --record=replays/"$event"-"$NAME".scr --host
./build-release.sh && gdb -x /tmp/cmds --args ./3d --resolution=1080 --cursor-size=64 --level=$level --souls=$souls --wizard=sorcha --souls=$souls "$map" --random-spellbooks --shuffle-sides --record=replays/"$event"-"$NAME".rcp --host
# ./build-ldc.sh && gdb -x /tmp/cmds --args ./3d --resolution=2160 --shadow-map-resolution=10000 --cursor-size=128 --level=$level --souls=$souls --wizard=sorcha --record=replays/"$event"-"$NAME".scr --souls=$souls "$map" --no-widgets --random-spellbooks --shuffle-sides --host

