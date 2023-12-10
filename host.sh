tag=1v1
nplayers=2

name=tg
wizard=sorcha

level=5
souls=12

map=--map-list=lists/maps-tg-1v1.txt
# map=--map-list=maps-2v2.txt
# map=--map-list=maps-3ffa.txt
# map=--map-list=maps-5ffa.txt
# map=--map-list=maps-3v3.txt

# map='maps/(2) Ferry.scp'
# map='maps/(2) EM-Greed.scp'
# map='maps/(2) WM-ColdKiss.scp'
# map='maps/(2) TM-Chain of Being.scp'
# map='maps/(2) TM-Glaciers.scp'
# map='maps/(2) Oval kopia.scp'

# map='maps/(2) Pure 1on1 1.scp'

# map='maps/(3) Gladiator.scp'
# map='maps/(3) Rotation.scp'

# map='maps/(4) EM-Slaughter Only.scp'

# map='maps/(4) Ferry.scp'

# map='maps/(5) Vampire Planet.scp'
# map='maps/(5) Flower Power.scp'

date=$(date +%Y-%m-%d-%H-%M-%S)
args=("$map" --name="$name" --host="$nplayers" --resolution=2160 --level="$level" --souls="$souls" --wizard="$wizard" --record=replays/"$tag"-"$date".rcp --random-gods --shuffle-sides --2v2 "$@")
echo "${args[@]}"

./run-current.sh "${args[@]}"
# ./build-release.sh && ./run.sh "${args[@]}"
# ./build-ldc.sh && ./run.sh "${args[@]}"
# wine explorer /desktop=1920x1080 SacEngine-current.exe "${args[@]}"
