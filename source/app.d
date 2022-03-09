// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import options;
import dagonBackend;
import sids, ntts, sacobject, sacmap, state, controller, network, recording_;
import wadmanager,util;
import dlib.math;
import std.string, std.array, std.range, std.algorithm, std.stdio;
import std.exception, std.conv, std.typecons;

import speechexport;

GameInit!B gameInit(alias multiplayerSide,B,R)(R playerSettings,ref Options options){
	GameInit!B gameInit;
	auto numSlots=options.numSlots;
	if(options._2v2) enforce(numSlots>=4);
	if(options._3v3) enforce(numSlots>=6);
	gameInit.slots=new GameInit!B.Slot[](numSlots);
	auto sides=iota(numSlots).map!(i=>multiplayerSide(i)).array;
	if(options.shuffleSides){
		import std.random: randomShuffle;
		randomShuffle(sides);
	}
	auto teams=(-1).repeat(numSlots).array;
	if(options.ffa||options._2v2||options._3v3){
		int teamSize=1;
		if(options._2v2) teamSize=2;
		if(options._3v3) teamSize=3;
		foreach(slot,ref team;teams)
			team=cast(int)slot/teamSize;
	}else{
		foreach(ref settings;playerSettings)
			if(settings.slot!=-1)
				teams[settings.slot]=settings.team;
	}
	if(options.shuffleTeams){
		import std.random: randomShuffle;
		randomShuffle(teams);
	}
	void placeWizard(ref Settings settings){
		if(settings.observer) return;
		import std.random: uniform;
		int slot=settings.slot;
		if(slot<0||slot>=numSlots||gameInit.slots[slot].wizardIndex!=-1)
			return;
		char[4] tag=settings.wizard[0..4];
		if(options.randomWizards){
			import nttData:wizards;
			tag=cast(char[4])wizards[uniform!"[)"(0,$)];
		}
		auto name=settings.name;
		auto side=sides[settings.slot];
		auto level=settings.level;
		auto souls=settings.souls;
		float experience=0.0f;
		auto spells=settings.spellbook;
		if(options.randomGods) spells=defaultSpells[uniform!"[]"(1,5)];
		if(options.randomSpellbooks) spells=randomSpells();
		auto spellbook=getSpellbook!B(spells);
		import nttData:WizardTag;
		assert(gameInit.slots[slot]==GameInit!B.Slot(-1));
		int wizardIndex=cast(int)gameInit.wizards.length;
		gameInit.slots[slot]=GameInit!B.Slot(wizardIndex);
		gameInit.wizards~=GameInit!B.Wizard(to!WizardTag(tag),name,side,level,souls,experience,spellbook);
	}
	foreach(ref settings;playerSettings) placeWizard(settings);
	if(options.shuffleSlots){
		import std.random: randomShuffle;
		randomShuffle(zip(gameInit.slots,teams));
	}
	foreach(i;0..numSlots){
		foreach(j;i+1..numSlots){
			int wi=gameInit.slots[i].wizardIndex, wj=gameInit.slots[j].wizardIndex;
			if(wi==-1||wj==-1) continue;
			int s=gameInit.wizards[wi].side, t=gameInit.wizards[wj].side;
			if(s==-1||t==-1) continue;
			assert(s!=t);
			int x=teams[i], y=teams[j];
			auto stance=x!=-1&&y!=-1&&x==y?Stance.ally:Stance.enemy;
			gameInit.stanceSettings~=GameInit!B.StanceSetting(s,t,stance);
			gameInit.stanceSettings~=GameInit!B.StanceSetting(t,s,stance);
		}
	}
	if(options.mirrorMatch){
		int[int] teamLoc;
		int[][] teamIndex;
		foreach(slot;0..numSlots) if(teams[slot]!=-1){
			if(teams[slot]!in teamLoc){
				teamLoc[teams[slot]]=cast(int)teamIndex.length;
				teamIndex~=[[]];
			}
			teamIndex[teamLoc[teams[slot]]]~=slot;
		}
		foreach(slot;0..numSlots) if(teams[slot]<0) teamIndex~=[slot];
		teamIndex.sort!("a.length > b.length",SwapStrategy.stable);
		foreach(t;teamIndex[1..$]){
			foreach(i;0..t.length){
				void copyWizard(T)(ref T a,ref T b){
					if(options.randomWizards) a.tag=b.tag;
					a.spellbook=b.spellbook;
				}
				copyWizard(gameInit.wizards[t[i]],gameInit.wizards[teamIndex[0][i]]);
			}
		}
	}
	gameInit.replicateCreatures=options.replicateCreatures;
	gameInit.protectManafounts=options.protectManafounts;
	return gameInit;
}

void loadMap(B)(ref Options options)in{
	assert(options.map.endsWith(".scp")||options.map.endsWith(".HMAP"));
}do{
	auto slot=options.observer?-1:options.slot;
	Network!B network=null;
	if(options.host){
		network=new Network!B();
		network.hostGame(options.settings);
	}else if(options.joinIP!=""){
		network=new Network!B();
		auto address=new InternetAddress(options.joinIP,listeningPort);
		while(!network.joinGame(address,options.settings)){
			import core.thread;
			Thread.sleep(200.msecs);
			if(!B.processEvents()) return;
		}
	}
	Recording!B playback=null;
	SacMap!B map;
	Sides!B sides;
	Proximity!B proximity;
	PathFinder!B pathFinder;
	Triggers!B triggers;
	if(!network&&options.playbackFilename.length){
		playback=loadRecording!B(options.playbackFilename);
		enforce(playback.mapName.endsWith(".scp")||playback.mapName.endsWith(".HMAP"));
		options.map=playback.mapName;
		slot=-1;
		map=playback.map;
		sides=playback.sides;
		proximity=playback.proximity;
		pathFinder=playback.pathFinder;
		triggers=playback.triggers;
	}
	ubyte[] mapData;
	Recording!B toContinue;
	if(!playback&&(!network||network.isHost)){
		if((!network||network.isHost)&&options.continueFilename.length){
			toContinue=loadRecording!B(options.continueFilename);
			if(options.continueFrame!=-1){
				toContinue.commands.length=options.continueFrame;
				toContinue.commands~=Array!(Command!B)();
			}else{
				if(toContinue.commands[$-1].length) toContinue.commands~=Array!(Command!B)();
				options.continueFrame=max(0,to!int(toContinue.commands.length)-1);
			}
			options.map=toContinue.mapName;
			if(network) network.hostSettings=options.settings;
			options.numSlots=to!int(toContinue.gameInit.slots.length);
			map=toContinue.map;
			sides=toContinue.sides;
			proximity=toContinue.proximity;
			pathFinder=toContinue.pathFinder;
			triggers=toContinue.triggers;
			if(network){
				static struct SlotData{
					int slot;
					string name;
				}
				SlotData toSlotData(int i){
					return SlotData(i,toContinue.gameInit.wizards[toContinue.gameInit.slots[i].wizardIndex].name);
				}
				assert(network.players.length==1);
				network.players[network.me].committedFrame=options.continueFrame;
				network.initSlots(iota(options.numSlots).map!toSlotData);
			}
		}else map=loadSacMap!B(options.map,&mapData); // TODO: compute hash without loading map
		options.mapHash=map.crc32;
	}
	if(network){
		network.dumpTraffic=options.dumpTraffic;
		network.checkDesynch=options.checkDesynch;
		network.logDesynch_=options.logDesynch;
		network.pauseOnDrop=options.pauseOnDrop;
		while(!network.synched){
			network.idleLobby();
			if(!B.processEvents()) return;
		}
		network.updateSetting!"mapHash"(options.mapHash);
		network.updateStatus(PlayerStatus.commitHashReady);
		if(!network.isHost){
			while(!network.hostCommitHashReady){
				network.idleLobby();
				if(!B.processEvents()) return;
			}
			if(network.hostSettings.commit!=options.commit){
				writeln("incompatible version #");
				writeln("host is using version ",network.hostSettings.commit);
				network.disconnectPlayer(network.host,null);
				return;
			}
			network.updateStatus(PlayerStatus.readyToLoad);
		}
		while(!network.readyToLoad&&!network.pendingResynch){
			network.idleLobby();
			if(!B.processEvents()) return;
			if(network.isHost&&network.numReadyPlayers+(network.players[network.host].wantsToControlState)>=options.numSlots&&network.clientsReadyToLoad()){
				network.acceptingNewConnections=false;
				//network.stopListening();
				auto numSlots=options.numSlots;
				auto slotTaken=new bool[](numSlots);
				foreach(i,ref player;network.players){
					if(player.settings.observer) continue;
					auto pslot=player.settings.slot;
					if(0<=pslot && pslot<options.numSlots && !slotTaken[pslot])
						slotTaken[pslot]=true;
					else pslot=-1;
					network.updateSlot(cast(int)i,pslot);
				}
				auto freeSlots=iota(numSlots).filter!(i=>!slotTaken[i]);
				foreach(i,ref player;network.players){
					if(player.settings.observer) continue;
					if(freeSlots.empty) break;
					if(player.slot==-1){
						network.updateSlot(cast(int)i,freeSlots.front);
						freeSlots.popFront();
					}
				}
				if(options.synchronizeLevel) network.synchronizeSetting!"level"();
				if(options.synchronizeSouls) network.synchronizeSetting!"souls"();
				network.updateStatus(PlayerStatus.readyToLoad);
				assert(network.readyToLoad());
				break;
			}
		}
		auto mapName=network.hostSettings.map;
		if(network.settings.map!=mapName)
			network.updateSetting!"map"(mapName);
		auto hash=network.hostSettings.mapHash;
		if(!network.isHost){
			import std.file: exists;
			if(exists(mapName)){
				map=loadSacMap!B(mapName); // TODO: compute hash without loading map
				options.mapHash=map.crc32;
			}
			network.updateSetting!"mapHash"(options.mapHash);
			network.updateStatus(PlayerStatus.mapHashed);
		}else{
			network.mapData=mapData;
			network.updateStatus(PlayerStatus.mapHashed);
		}
		void loadMap(string name){
			mapName=name;
			map=loadSacMap!B(mapName);
			enforce(map.crc32==hash,"map hash mismatch");
			network.updateSetting!"mapHash"(map.crc32);
			network.updateStatus(PlayerStatus.mapHashed);
		}
		while(!network.synchronizeMap(&loadMap)){
			network.idleLobby();
			if(!B.processEvents()) return;
		}
		if(network.isHost){
			network.load();
		}else{
			while(!network.loading&&network.players[network.me].status!=PlayerStatus.desynched){ // desynched at start if late join
				network.idleLobby();
				if(!B.processEvents()) return;
			}
		}
		options.settings=network.settings;
		slot=network.slot;
	}
	if(!playback&&!toContinue){
		enforce(!!map); // map already loaded
		sides=new Sides!B(map.sids);
		proximity=new Proximity!B();
		pathFinder=new PathFinder!B(map);
		triggers=new Triggers!B(map.trig);
	}
	auto state=new GameState!B(map,sides,proximity,pathFinder,triggers);
	int[32] multiplayerSides=-1;
	bool[32] matchedSides=false;
	foreach(i,ref side;sides){
		int mpside=side.assignment&PlayerAssignment.multiplayerMask;
		if(!mpside) continue;
		multiplayerSides[mpside-1]=cast(int)i;
		matchedSides[i]=true;
	}
	iota(32).filter!(i=>!matchedSides[i]).copy(multiplayerSides[].filter!(x=>x==-1));
	int multiplayerSide(int slot){
		if(slot<0||slot>=multiplayerSides.length) return slot;
		return multiplayerSides[slot];
	}
	GameInit!B gameInit;
	if(!playback||network){
		if(network){
			import serialize_;
			if(network.isHost){
				if(toContinue) gameInit=toContinue.gameInit;
				else gameInit=.gameInit!(multiplayerSide,B)(network.players.map!(ref(return ref x)=>x.settings),options);
				gameInit.serialized(&network.initGame);
			}else{
				while(!network.gameInitData){
					network.idleLobby();
					if(!B.processEvents()) return;
				}
				deserialize(gameInit,state.current,network.gameInitData);
				network.gameInitData=null;
			}
		}else{
			if(toContinue) gameInit=toContinue.gameInit;
			else gameInit=.gameInit!(multiplayerSide,B)(only(options.settings),options);
		}
	}else gameInit=playback.gameInit;
	Recording!B recording=null;
	if((!playback||network)&&options.recordingFilename.length){
		recording=new Recording!B(options.map,map,sides,proximity,pathFinder,triggers);
		recording.gameInit=gameInit;
		recording.logCore=options.logCore;
	}
	state.initGame(gameInit);
	bool hasSlot=0<=slot&&slot<=state.slots.length;
	int wizId=hasSlot?state.slots[slot].wizard:0;
	state.current.map.makeMeshes(options.enableMapBottom);
	if(toContinue){
		state.commands=toContinue.commands;
		playAudio=false;
		while(state.current.frame+1<state.commands.length){
			state.step();
			if(state.current.frame%1000==0){
				writeln("continue: simulated ",state.current.frame," of ",state.commands.length-1," frames");
			}
		}
		playAudio=true;
		assert(state.current.frame==options.continueFrame);
		if(network){
			assert(network.isHost);
			foreach(i;network.connectedPlayerIds) if(i!=network.host) network.updateStatus(cast(int)i,PlayerStatus.desynched);
			network.continueSynchAt(options.continueFrame);
		}
	}
	state.commit();
	if(network && network.isHost) network.addSynch(state.lastCommitted.frame,state.lastCommitted.hash);
	if(recording) recording.stepCommitted(state.lastCommitted);
	auto controller=new Controller!B(hasSlot?state.slots[slot].controlledSide:-1,state,network,recording,playback);
	B.setState(state);
	if(wizId) B.focusCamera(wizId);
	else B.scene.fpview.active=true;
	B.setController(controller);
}

int run(string[] args){
	import core.memory;
	GC.disable(); // TODO: figure out where GC memory is used incorrectly
	if(args.length==0) args~="";
	import std.file:exists;
	static string stripComment(string s){
		auto i=s.indexOf('#');
		if(i==-1) return s;
		return s[0..i];
	}
	if(!args.canFind("--ignore-settings")&&exists("settings.txt")) args=chain(args[0..1],File("settings.txt").byLineCopy.map!stripComment.map!strip.filter!(l=>l.length!=0),args[1..$]).array;
	if(args.canFind("--redirect-output")){
		stdout.reopen("SacEngine.out.txt","w");
		stderr.reopen("SacEngine.err.txt","w");
	}
	auto opts=args[1..$].filter!(x=>x.startsWith("--")).array;
	args=chain(args[0..1],args[1..$].filter!(x=>!x.startsWith("--"))).array;
	Options options={
		settings: { commit: commit },
		//shadowMapResolution: 8192,
		//shadowMapResolution: 4096,
		//shadowMapResolution: 2048,
		shadowMapResolution: 1024,
		enableWidgets: true,
	};
	options.slot=int.min;
	static Tuple!(int,"width",int,"height") parseResolution(string s){
		auto t=s.split('x');
		if(t.length==2) return tuple!("width","height")(to!int(t[0]),to!int(t[1]));
		return tuple!("width","height")(16*to!int(s)/9,to!int(s));
	}
	foreach(opt;opts){
		if(opt.startsWith("--spoof-commit-hash=")){ // for testing
			options.commit=opt["--spoof-commit-hash=".length..$];
		}else if(opt.startsWith("--resolution=")){
			auto resolution=parseResolution(opt["--resolution=".length..$]);
			options.width=resolution.width;
			options.height=resolution.height;
		}else if(opt.startsWith("--scale=")){
			options.scale=to!float(opt["--scale=".length..$]);
		}else if(opt.startsWith("--aspect-distortion=")){
			options.aspectDistortion=to!float(opt["--aspect-distortion=".length..$]);
		}else if(opt.startsWith("--sun-factor=")){
			options.sunFactor=to!float(opt["--sun-factor=".length..$]);
		}else if(opt.startsWith("--ambient-factor=")){
			options.ambientFactor=to!float(opt["--ambient-factor=".length..$]);
		}else if(opt.startsWith("--shadow-map-resolution=")){
			options.shadowMapResolution=to!int(opt["--shadow-map-resolution=".length..$]);
		}else if(opt.startsWith("--glow-brightness=")){
			options.glowBrightness=to!float(opt["--glow-brightness=".length..$]);
		}else if(opt.startsWith("--replicate-creatures=")){
			options.replicateCreatures=to!int(opt["--replicate-creatures=".length..$]);
		}else if(opt.startsWith("--protect-manafounts=")){
			options.protectManafounts=to!int(opt["--protect-manafounts=".length..$]);
		}else if(opt.startsWith("--cursor-size=")){
			options.cursorSize=to!int(opt["--cursor-size=".length..$]);
		}else if(opt.startsWith("--volume=")){
			options.volume=to!float(opt["--volume=".length..$]);
		}else if(opt.startsWith("--music-volume=")){
			options.musicVolume=to!float(opt["--music-volume=".length..$]);
		}else if(opt.startsWith("--sound-volume=")){
			options.soundVolume=to!float(opt["--sound-volume=".length..$]);
		}else if(opt.startsWith("--hotkeys=")){
			options.hotkeyFilename=opt["--hotkeys=".length..$];
		}else if(opt.startsWith("--camera-mouse-sensitivity")){
			options.cameraMouseSensitivity=to!float(opt["--camera-mouse-sensitivity=".length..$]);
		}else if(opt.startsWith("--mouse-wheel-sensitivity")){
			options.mouseWheelSensitivity=to!float(opt["--mouse-wheel-sensitivity=".length..$]);
		}else if(opt.startsWith("--join=")){
			options.joinIP=opt["--join=".length..$];
		}else if(opt.startsWith("--record=")){
			options.recordingFilename=opt["--record=".length..$];
		}else if(opt.startsWith("--play=")){
			options.playbackFilename=opt["--play=".length..$];
		}else if(opt.startsWith("--continue=")){
			options.continueFilename=opt["--continue=".length..$];
		}else if(opt.startsWith("--continue-at=")){
			options.continueFrame=to!int(opt["--continue-at=".length..$]);
		}else if(opt.startsWith("--logCore")){
			if(opt.startsWith("--logCore=")){
			   options.logCore=to!int(opt["--logCore=".length..$]);
			}else options.logCore=120;
		}else if(opt.startsWith("--export-folder=")){
			options.exportFolder=opt["--export-folder=".length..$];
		}else if(opt=="--observer"){
			options.observer=true;
		}else if(opt.startsWith("--slot=")){
			options.slot=to!int(opt["--slot=".length..$]);
		}else if(opt.startsWith("--team=")){
			options.team=to!int(opt["--team=".length..$]);
		}else if(opt.startsWith("--name=")){
			options.name=opt["--name=".length..$];
		}else if(opt.startsWith("--wizard=")){
			auto wizard=opt["--wizard=".length..$];
			import nttData:tagFromCreatureName;
			auto tag=tagFromCreatureName(wizard);
			if(tag!=(char[4]).init) wizard=text(tag);
			import nttData:wizards;
			if(!wizards.canFind(tag)){
				auto reversed=tag;
				reverse(tag[]);
				if(wizards.canFind(reversed)){
					tag=reversed;
				}else{
					stderr.writefln!"error: unknown wizard '%s'"(options.wizard);
					return 1;
				}
			}
			options.wizard=tag;
		}else if(opt.startsWith("--god=")){
			try{
				options.god=to!God(opt["--god=".length..$]);
			}catch(Exception e){
				stderr.writefln!"error: unknown god '%s'"(opt["--god=".length..$]);
				return 1;
			}
		}else if(opt.startsWith("--level=")){
			options.level=to!int(opt["--level=".length..$]);
		}else if(opt.startsWith("--souls=")){
			options.souls=to!int(opt["--souls=".length..$]);
		}else if(opt.startsWith("--map-list=")){
			options.mapList=opt["--map-list=".length..$];
		}else if(opt.startsWith("--delay-start=")){
			options.delayStart=to!int(opt["--delay-start=".length..$]);
		}else if(opt=="--host"){
			options.host=true;
			options.numSlots=2;
		}else if(opt.startsWith("--host=")){
			options.host=true;
			options.numSlots=to!int(opt["--host=".length..$]);
		}else if(opt.startsWith("--num-slots=")){
			options.numSlots=to!int(opt["--num-slots=".length..$]);
		}else LoptSwitch: switch(opt){
			static string getOptionName(string memberName){
				import std.ascii;
				auto m=memberName;
				if(m.startsWith("_")) m=m["_".length..$];
				if(m.startsWith("enable")) m=m["enable".length..$];
				//else if(m.startsWith("disable")) m=m["disable".length..$]; // TODO: flip setting
				string r;
				foreach(char c;m){
					if(isUpper(c)) r~="-"~toLower(c);
					else r~=c;
				}
				if(r[0]=='-') r=r[1..$];
				return r;
			}
			static foreach(member;__traits(allMembers,Options)){
				static if(is(typeof(__traits(getMember,options,member))==bool)){
					case "--no-"~getOptionName(member):
						__traits(getMember,options,member)=false;
						break LoptSwitch;
					case "--"~getOptionName(member):
						__traits(getMember,options,member)=true;
						break LoptSwitch;
				}
			}
			case "--ignore-settings": break;
			case "--redirect-output": break;
			case "--no-join": options.joinIP=""; break;
			default:
				stderr.writeln("unknown option: ",opt);
				return 1;
		}
	}
	if(options.slot==int.min) options.slot=options.observer?-1:0;
	if(options._2v2) options.numSlots=max(options.numSlots,4);
	if(options._3v3) options.numSlots=max(options.numSlots,6);
	if(options.wizard=="\0\0\0\0"||options.randomWizards){
		import std.random: uniform;
		import nttData:wizards;
		options.wizard=cast(char[4])wizards[uniform!"[)"(0,$)];
	}
	if(options.god==God.none||options.randomGods){
		import std.random: uniform;
		options.god=cast(God)uniform!"[]"(1,5);
	}
	if(options.randomSpellbook||options.randomSpellbooks){
		options.spellbook=randomSpells();
	}else options.spellbook=defaultSpells[options.god];
	writeln("SacEngine build ",__DATE__," ",__TIME__,commit.length?text(", commit ",commit):"");
	import audio;
	if(!loadAudio()){
		stderr.writeln("failed to initialize audio");
		options.volume=0.0f;
	}
	scope(exit) unloadAudio();
	if(options.enableReadFromWads){
		wadManager=new WadManager;
		wadManager.indexWADs("data");
	}
	import nttData:initNTTData;
	initNTTData(options.enableReadFromWads);
	import hotkeys_:initHotkeys,defaultHotkeys,loadHotkeys;
	initHotkeys();
	if(options.hotkeyFilename.length){
		options.hotkeys=loadHotkeys(options.hotkeyFilename);
	}else options.hotkeys=defaultHotkeys();
	alias B=DagonBackend;
	B.initialize(options);
	foreach(arg;args){
		if(arg.endsWith(".scp")||arg.endsWith(".HMAP")||arg.startsWith("export-speech:")){
			options.map=arg;
		}else if(arg.endsWith(".rcp")){
			options.playbackFilename=arg;
		}
	}
	if(options.map==""&&!options.noMap){
		import std.file;
		auto candidates=!options.mapList?dirEntries("maps","*.scp",SpanMode.depth).map!(x=>cast(string)x).array:File(options.mapList).byLineCopy.map!(l=>stripComment(l.strip)).filter!(l=>!l.empty).array;
		import std.random:uniform;
		auto map=candidates.length?candidates[uniform!"[)"(0,$)]:"";
		if(map!="") stdout.writefln!"selected map '%s'"(map);
		options.map=map;
	}
	if(options.map.startsWith("export-speech:")){
		options.map=options.map["export-speech:".length..$];
		exportSpeech!B(options);
		return 0;
	}else if(options.map!=""&&!options.noMap) loadMap!B(options);
	else B.scene.fpview.active=true;

	foreach(ref i;1..args.length){
		if(args[i].endsWith(".SAMP")){
			import samp,audio;
			auto filename=args[i];
			bool loop=false;
			if(filename.startsWith("loop:")){
				loop=true;
				filename=filename["loop:".length..$];
			}
			auto sample=loadSAMP(filename);
			auto buffer=makeBuffer(sample);
			auto source=makeSource();
			source.looping=loop;
			source.buffer=buffer;
			source.play();
			import core.thread;
			while(source.isPlaying()){ Thread.sleep(1.dur!"msecs"); }
			continue;
		}
		string anim="";
		if(i+1<args.length&&args[i+1].endsWith(".SXSK"))
			anim=args[i+1];
		if(!(args[i].endsWith(".scp")||args[i].endsWith(".HMAP"))){
			auto sac=new SacObject!B(args[i],float.nan,anim);
			auto position=Vector3f(1270.0f, 1270.0f, 0.0f);
			if(B.state && B.state.current.isOnGround(position))
				position.z=B.state.current.getGroundHeight(position);
			if(anim.length) i+=1;
			if(i+1<args.length&&args[i+1].endsWith(".obj")){
				if(args[i+1].startsWith("export:")){
					import sxsk,saxs2obj;
					auto filename=args[i+1]["export:".length..$];
					int frame=0; // TODO: make configurable
					if(sac.isSaxs) saveObj!B(filename,sac.saxsi.saxs,anim?sac.animations[0].frames[frame]:Pose.init);
					else saveObj!B(filename,sac.meshes[frame]);
					i+=1;
				}else if(args[i+1].startsWith("import:")){
					import obj,sxsk;
					auto filename=args[i+1]["import:".length..$];
					auto meshes=loadObj!B(filename);
					sac.setMeshes(meshes,anim?sac.animations[0].frames[0]:Pose.init);
					i+=1;
					bool parseTexture(){
						import dlib.image.io.png;
						if(i+1>=args.length||!args[i+1].endsWith(".png")) return false;
						auto texture=B.makeTexture(loadPNG(args[i+1]));
						if(args[i+1].canFind("normal")){
							sac.setNormal([texture]);
						}else{
							sac.setDiffuse([texture]);
						}
						return true;
					}
					while(parseTexture()) i++;
					sac.setOverride();
				}else if(args[i+1].startsWith("export-skeleton:")){
					import sxsk,saxs2obj;
					auto filename=args[i+1]["export-skeleton:".length..$];
					if(sac.isSaxs) saveSkeletonObj!B(filename,sac.saxsi.saxs,anim?sac.animations[0].frames[0]:Pose.init);
					else stderr.writeln("no bones");
					i+=1;
				}
			}
			B.addObject(sac,position,facingQuaternion(0));
		}
	}
	if(!B.network||B.network.isHost){
		auto delay=options.delayStart;
		while(delay){
			writeln(delay);
			delay--;
			import core.thread;
			Thread.sleep(1.dur!"seconds");
		}
	}
	scope(exit) if(B.controller&&B.controller.recording){
		B.controller.recording.finalize(B.state.commands);
		writeln("saving recording to '",options.recordingFilename,"'");
		B.controller.recording.save(options.recordingFilename,options.compressRecording);
	}
	B.run();
	return 0;
}

int main(string[] args){
	int r;
	version(Windows){
		import core.sys.windows.windows;
		SetConsoleOutputCP(CP_UTF8);
		try r=run(args);
		catch(Throwable e){
			writeln(e.toString());
			import core.stdc.stdlib;
			system("pause");
			return 1;
		}
	}else r=run(args);
	return r;
}
