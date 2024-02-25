#!/bin/bash


####
## FUNCTIONS to workaround the lack of GOTOs
####

function observer {
	# Prompt for enabling observer mode
	read -p "Do you want to observe ? (Y/N): " observe_choice
	case $observe_choice in
		[Yy]) echo "--observer" >> settings.txt ;;
		*) echo "# --observer" >> settings.txt ;;
	esac

	final_crap
}

function final_crap {
    echo "# --shuffle-slots                            # randomly distribute players to slots, teams stick to slots" >> settings.txt
    echo "# --shuffle-teams                            # randomly shuffle team assignments" >> settings.txt
    echo "# --random-wizards                           # enforce random wizard for everyone" >> settings.txt
    echo "# --random-spellbooks                        # enforce random spellbook for everyone" >> settings.txt
    echo "# --no-synchronize-level                     # allow different players to start at different levels" >> settings.txt
    echo "# --no-synchronize-souls                     # allow different players to start with different amounts of souls" >> settings.txt
    echo "# --no-pause-on-drop                         # do not pause until rejoin if a player drops" >> settings.txt
    echo "### miscellanneous ###" >> settings.txt
    echo "# --redirect-output                          # print diagnostics to SacEngine.out.txt and SacEngine.err.txt" >> settings.txt
    echo "# --record=replay.rcp                        # record a replay. experimental. will only be compatible with exact same version of engine and map" >> settings.txt
    echo "# --log-core                                 # when recording, save the full game state of the last two seconds of gameplay, useful for troubleshooting" >> settings.txt
    echo "# --play=replay.rcp                          # play a replay. experimental." >> settings.txt
    echo "# --debug-hotkeys                            # adds a few hardcoded hotkeys" >> settings.txt
    echo "# --protect-manafounts=1                     # put random level 1 creatures on top of each mana fountain" >> settings.txt
    echo "# --replicate-creatures=2                    # create multiple copies of all creatures on the map" >> settings.txt
    echo "# --terrain-sine-wave                        # displace the terrain using a moving sine wave" >> settings.txt
}

function typical_baggage {
    echo "--random-gods" >> settings.txt
    echo "--shuffle-sides" >> settings.txt
    echo "--stutter-on-desynch" >> settings.txt

    particles=""
    read -p "Enable particles (do NOT use --no-particles) ? (Y/N): " particles
    case $particles in
        [Yy]) echo "#--no-particles" >> settings.txt ;;
        *) echo "--no-particles" >> settings.txt ;;
    esac
}

# Function for error message
function print_error_message {
    echo "Invalid input. Please enter a valid choice."
}

#########################
## START OF THE SCRIPT ##
#########################

# Reuse the existing portion of the bash script
echo "### input options ###" > settings.txt
echo "--hotkeys=hotkeys.txt" >> settings.txt
echo "# --camera-mouse-sensitivity=1.0" >> settings.txt
echo "# --mouse-wheel-sensitivity=1.0" >> settings.txt
echo "# --no-window-scroll-x" >> settings.txt
echo "# --no-window-scroll-y" >> settings.txt
echo "# --window-scroll-x-factor=1.0" >> settings.txt
echo "# --window-scroll-y-factor=1.0" >> settings.txt
echo "--capture-mouse" >> settings.txt
echo "--focus-on-start" >> settings.txt
echo "### game options ###" >> settings.txt

read -p "Nickname: " answer
echo "--name=$answer" >> settings.txt

read -p "Wizard: " answer
echo "--wizard=$answer" >> settings.txt

# Prompt for choosing starting level with error handling
level=""
while [[ ! $level =~ ^[1-9]$ ]]; do
    read -p "Choose starting level [1-9]: " level
    if [[ ! $level =~ ^[1-9]$ ]]; then
        print_error_message
    fi
done

echo "--level=$level" >> settings.txt
echo "--min-level=$level" >> settings.txt

echo "1. 10 starting souls"
echo "2. 12 starting souls"
echo "3. 14 starting souls"
echo "4. 16 starting souls"
echo "Any other positive number - use that as the number of souls. Ex: 8 = 8 starting souls"
# Prompt for choosing starting souls with error handling
final_souls=0
while [[ $final_souls -lt 1 ]]; do
    echo "Choose amount of starting souls [1,2,3,4 or custom number]:"
    read -p "Enter the number of starting souls: " souls_choice
    if [[ $souls_choice -lt 1 ]]; then
        echo "Invalid input. Please enter a number greater than or equal to 1."
    else
        case $souls_choice in
            1) final_souls=10 ;;
            2) final_souls=12 ;;
            3) final_souls=14 ;;
            4) final_souls=16 ;;
            *) final_souls=$souls_choice ;;
        esac
    fi
done

# Finally, echo the souls parameter into the settings.txt
echo "--souls=$final_souls" >> settings.txt

# print god-related and other commented-out crap
god_choice=0
echo "1. Persephone"
echo "2. James"
echo "3. Stratos"
echo "4. Pyro"
echo "5. Charnel"
echo "6. Random"
while [[ ! $god_choice =~ ^[1-6]$ && ! $god_choice =~ ^[sS]$ ]]; do
    read -p "Choose God [1-6] or 's' for skip (which defaults to random): " god_choice
    if [[ ! $god_choice =~ ^[1-6]$ && ! $god_choice =~ ^[sS]$ ]]; then
        print_error_message
    fi
done
god=""
case $god_choice in
	6) god="random" ;;
	5) god="charnel" ;;
	4) god="pyro" ;;
	3) god="stratos" ;;
	2) god="james" ;;
	1) god="persephone" ;;
esac
if [[ $god_choice =~ ^[sS]$ || $god_choice == 6 ]]; then
    echo "# --god=persephone                           # choose god (default: random god)" >> settings.txt
else
    echo "--god=${god}                           # choose god (default: random god)" >> settings.txt
fi
random_spellbook=""
read -p "Use random spellbook ? (Y/N): " random_spellbook
case $random_spellbook in
    [Yy]) echo "--random-spellbook                         # choose fully random spellbook" >> settings.txt ;;
    *) echo "# --random-spellbook                         # choose fully random spellbook" >> settings.txt ;;
esac

echo "### integrated zerotier client ###" >> settings.txt
echo "--zerotier-network=6ab565387ab194c6          # play over tg zerotier network without zerotier installation" >> settings.txt
echo "# --zerotier-network=12ac4a1e71282878        # play over darkstorm's zerotier network without zerotier installation" >> settings.txt  

# on to the graphics part
echo ### graphics options ### >> settings.txt
echo "1. 720p"
echo "2. 1080p"
echo "3. 1440p"
echo "4. 2160p"
echo "5. Detect resolution"
# Prompt for choosing resolution with error handling
resolution=""
while [[ ! $resolution =~ ^[1-5]$ ]]; do
    read -p "Enter a number between 1 and 5: " resolution
    if [[ ! $resolution =~ ^[1-5]$ ]]; then
        print_error_message
    fi
done

case $resolution in
    5) echo "--detect-resolution" >> settings.txt ;;
    4) echo "--resolution=2160" >> settings.txt ;;
    3) echo "--resolution=1440" >> settings.txt ;;
    2) echo "--resolution=1080" >> settings.txt ;;
    1) echo "--resolution=720" >> settings.txt ;;
esac

# Scaling part

# Prompt for scale factor
scale_factor=""
while [[ ! $scale_factor =~ ^[0-5]\.[0-9]+$ && ! $scale_factor =~ ^[sS]$ ]]; do
    read -p "Enter a floating-point number between 0.1 and 5.0 for scale factor (values smaller than 1 can be used for supersampling, use 1.0 for default or 's' for skip) : " scale_factor
    if [[ ! $scale_factor =~ ^[0-5]\.[0-9]+$  && ! $scale_factor =~ ^[sS]$ ]]; then
        print_error_message
    fi
done
if [[ $scale_factor =~ ^[sS]$ ]]; then
    echo "# --scale=1.0                                # scale width and height of window (values smaller than 1 can be used for supersampling)" >> settings.txt
else
    echo " --scale=$scale_factor                                # scale width and height of window (values smaller than 1 can be used for supersampling)" >> settings.txt
fi
# and other commented out stuff
echo "# --resizable-window                         # allow resizing of the window (does not affect 3d rendering resolution)" >> settings.txt
echo "# --no-scale-to-fit                          # do not scale rendered scene to match size of window" >> settings.txt

# Prompt for enabling fullscreen
read -p "Enable fullscreen ? (Y/N): " fullscreen_choice
case $fullscreen_choice in
    [Yy]) echo "--fullscreen" >> settings.txt ;;
    *) echo "# --fullscreen" >> settings.txt ;;
esac

# Prompt for enabling widgets
read -p "Disable widgets ? (Y/N): " widgets_choice
case $widgets_choice in
    [Yy]) echo "--no-widgets" >> settings.txt ;;
    *) echo "# --no-widgets" >> settings.txt ;;
esac
# put the rest of the commented-out crap there
echo "# --cursor-size=32                           # change size of cursor (default: 32)" >> settings.txt
echo "# --shadow-map-resolution=4096               # change resolution of cascading shadow maps (default: 1024)" >> settings.txt
echo "# --fog                                      # render fog (currently ignores linear vs exponential falloff setting)" >> settings.txt
echo "# --no-map-bottom                            # do not render bottom of map (similar to original engine)" >> settings.txt
echo "# --no-glow                                  # disable glow effect" >> settings.txt
echo "# --glow-brightness=0.5                      # tweak glow effect (default: 0.5)" >> settings.txt
echo "# --no-antialiasing                          # disable FXAA effect" >> settings.txt
echo "# --ambient-factor=1.0                       # tweak strength of ambient lighting" >> settings.txt
echo "# --sun-factor=1.0                           # tweak strength of sun lighting" >> settings.txt

echo "### audio options ###" >> settings.txt
# Prompt for music volume with error handling
volume_choice=""
while [[ ! $volume_choice =~ ^[0-5]\.[0-9]+$ && ! $volume_choice =~ ^[sS]$ ]]; do
    read -p "Enter a floating-point number between 0.0 and 5.0 to be used as factor for global volume (or 's' for skip and use default): " volume_choice
    if [[ ! $volume_choice =~ ^[0-5]\.[0-9]+$ && ! $volume_choice =~ ^[sS]$ ]]; then
        print_error_message
    fi
done
if [[ $music_volume =~ ^[sS]$ ]]; then
    echo "# --volume=0.5                               # global factor on volume" >> settings.txt
else
    echo "--volume=$volume_choice                               # global factor on volume" >> settings.txt
fi

# Prompt for music volume with error handling
music_volume=""
while [[ ! $music_volume =~ ^[0-5]\.[0-9]+$ && ! $music_volume =~ ^[sS]$ ]]; do
    read -p "Enter a floating-point number between 0.0 and 5.0 to be used as factor for music volume (or 's' for skip and use default): " music_volume
    if [[ ! $music_volume =~ ^[0-5]\.[0-9]+$ && ! $music_volume =~ ^[sS]$ ]]; then
        print_error_message
    fi
done
if [[ $music_volume =~ ^[sS]$ ]]; then
    echo "# --music-volume=0.5                           # additional factor on music volume" >> settings.txt
else
    echo "--music-volume=$music_volume                           # additional factor on music volume" >> settings.txt
fi

# Prompt for sound volume
sound_volume=""
while [[ ! $sound_volume =~ ^[0-5]\.[0-9]+$ && ! $sound_volume =~ ^[sS]$ ]]; do
    read -p "Enter a floating-point number between 0.0 and 5.0 to be used as factor for sound volume (or 's' for skip and use default): " sound_volume
    if [[ ! $sound_volume =~ ^[0-5]\.[0-9]+$ && ! $sound_volume =~ ^[sS]$ ]]; then
        print_error_message
    fi
done
if [[ $sound_volume =~ ^[sS]$ ]]; then
    echo "# --sound-volume=0.5                           # additional factor on sound volume" >> settings.txt
else
    echo "--sound-volume=$sound_volume                           # additional factor on sound volume" >> settings.txt
fi

echo # --no-advisor-help-speech                   # disable zyzyx >> settings.txt
# end of sound options

# Multiplayer part
echo "### multiplayer options for host ###" >> settings.txt

echo "1. Host for 1v1"
echo "2. Host for 2v2"
echo "3. Host for 3v3"
echo "4. Join"
echo "5. Host FFA"

hostmode=""
while [[ ! $hostmode =~ ^[1-5]$ ]]; do
    read -p "Enter a number between 1 and 5: " hostmode
    if [[ ! $hostmode =~ ^[1-5]$ ]]; then
        print_error_message
    fi
done

## HOSTMODE
case $hostmode in
    # FFA
    5)  
		echo "1. Host for 3"
		echo "2. Host for 4"
		echo "3. Host for 5"
		echo "Hosting FFA for 6 is not available due to lack of maps and maplists"
		ffamode=""
		while [[ ! $ffamode =~ ^[1-3]$ ]]; do
			read -p "Enter a number between 1 and 3: " ffamode
			if [[ ! $ffamode =~ ^[1-3]$ ]]; then
				print_error_message
			fi
		done
		ffaplayers=""
		case $ffamode in
			1) ffaplayers=3 ;;
			2) ffaplayers=4 ;;
			3) ffaplayers=5 ;;
		esac

		# Finally, echo everything to settings.txt
		echo "--host=$ffaplayers" >> settings.txt
		echo "--ffa                                        # host ffa (overrides team settings)" >> settings.txt
		typical_baggage
		# if there's only 3 ffa players, offer another choice, otherwise use tg-{$ffaplayers}ffa.txt maplist
		if [ $ffaplayers != 3 ]; then
			echo "--map-list=maps-tg-{ffaplayers}ffa.txt" >> settings.txt
		else
			# another maplist choice
			echo "1. shiny's 3ffa map list"
			echo "2. tg's 3ffa map list"
			echo "3. tree's 3ffa map list"
			maplist=""
			while [[ ! $maplist =~ ^[1-3]$ ]]; do
				read -p "Enter a number between 1 and 3: " maplist
				if [[ ! $maplist =~ ^[1-3]$ ]]; then
					print_error_message
				fi
			done
			case $maplist in
				1) # shiny ffa3
					echo "--map-list=maps-shiny-3ffa.txt" >> settings.txt
					;;
				2) # tg ffa3
					echo "--map-list=maps-tg-3ffa.txt" >> settings.txt
					;;
				3) # tree ffa3
					echo "--map-list=maps-tree-3ffa.txt" >> settings.txt
					;;
			esac
		fi
		;;
	# join
	4)
		echo "--join" >> settings.txt
		# call the observer() function we declared at the top of the file
		observer
		;;
	# 3v3
	3)
		echo "--host=6" >> settings.txt
		echo "--map-list=maps-tg-3v3.txt" >> settings.txt
		echo "--3v3                                        # host 3v3 (overrides team settings)" >> settings.txt
		typical_baggage
		;;
	# 2v2
	2)
		echo "--host=4" >> settings.txt
		echo "--2v2                                        # host 2v2 (overrides team settings)" >> settings.txt
		typical_baggage
		
		# another map selection ...
		echo "1. shiny's 2v2 map list"
		echo "2. tg's 2v2 map list"
		echo "3. tree's 2v2 map list"
	
		maplist=""
		while [[ ! $maplist =~ ^[1-3]$ ]]; do
			read -p "Enter a number between 1 and 3: " maplist
			if [[ ! $maplist =~ ^[1-3]$ ]]; then
				print_error_message
			fi
		done
		case $maplist in
			1) # shiny 2v2
				echo "--map-list=maps-shiny-2v2.txt" >> settings.txt
				;;
			2) # tg 2v2
				echo "--map-list=maps-tg-2v2.txt" >> settings.txt
				;;
			3) # tree 2v2
				echo "--map-list=maps-tree-2v2.txt" >> settings.txt
				;;
		esac
		;;
	# 1v1
	1)
		echo --host=2 >> settings.txt
		typical_baggage

		# another 1v1 map selection...
		echo "1. shiny's 1v1 map list"
		echo "2. tg's 1v1 map list"
		echo "3. tree's 1v1 map list"
		echo "4. (2) Ferry.scp"
		maplist=""
		while [[ ! $maplist =~ ^[1-4]$ ]]; do
			read -p "Enter a number between 1 and 4: " maplist
			if [[ ! $maplist =~ ^[1-4]$ ]]; then
				print_error_message
			fi
		done
		case $maplist in
			1) # shiny 1v1
				echo "--map-list=maps-shiny-1v1.txt" >> settings.txt
				;;
			2) # tg 1v1
				echo "--map-list=maps-tg-1v1.txt" >> settings.txt
				;;
			3) # tree 1v1
				echo "--map-list=maps-tree-1v1.txt" >> settings.txt
				;;
		esac
		;;
	
esac


# Prompt for enabling Slaughter
read -p "Enable Slaughter (Y/N): " slaughter_choice
if [[ $slaughter_choice =~ ^[Yy]$ ]]; then
    echo "Choose the number of kills required to win:"
    echo "1. 100 kills"
    echo "2. 250 kills"
    echo "3. 500 kills"
    echo "4. 999 kills"
    read -p "Enter the number corresponding to the desired option: " slaughter_kills
    case $slaughter_kills in
        4) echo "--slaughter=999" >> settings.txt ;;
        3) echo "--slaughter=500" >> settings.txt ;;
        2) echo "--slaughter=250" >> settings.txt ;;
        1) echo "--slaughter=100" >> settings.txt ;;
    esac
else
    echo "# --slaughter" >> settings.txt
fi
# with everything done, call the observer() function located at the top of the file
observer

# Prompt for miscellaneous options
echo "Press enter to continue..."
read -r

# End of the script
echo "Script execution completed."
