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

void loadMap(B)(ref B backend,ref Options options)in{
	assert(options.map.endsWith(".scp")||options.map.endsWith(".HMAP"));
}do{
	auto controlledSide=options.settings.controlledSide;
	Network!B network=null;
	if(options.host){
		network=new Network!B();
		network.hostGame();
	}else if(options.joinIP!=""){
		network=new Network!B();
		auto address=new InternetAddress(options.joinIP,listeningPort);
		while(!network.joinGame(address)){
			import core.thread;
			Thread.sleep(200.msecs);
			if(!backend.processEvents()) return;
		}
	}
	Recording!B playback=null;
	if(!network&&options.playbackFilename.length){
		playback=loadRecording!B(options.playbackFilename);
		enforce(playback.mapName.endsWith(".scp")||playback.mapName.endsWith(".HMAP"));
		options.map=playback.mapName;
		controlledSide=-1;
	}
	if(network){
		network.dumpTraffic=options.dumpTraffic;
		network.checkDesynch=options.checkDesynch;
		while(!network.synched){
			network.idleLobby();
			if(!backend.processEvents()) return;
		}
		network.updateSettings(options.settings);
		if(!network.isHost) network.updateStatus(PlayerStatus.readyToLoad);
		while(!network.readyToLoad){
			network.idleLobby();
			if(!backend.processEvents()) return;
			if(network.isHost&&network.players.length>=options.host&&network.clientsReadyToLoad()){
				//network.acceptingNewConnections=false; // TODO: accept observers later
				network.stopListening();
				network.synchronizeSetting!"map"();
				bool[32] sideTaken=false;
				foreach(ref player;network.players){
					if(player.settings.observer) continue;
					auto side=player.settings.controlledSide;
					if(side<0||side>=sideTaken.length||sideTaken[side]) player.settings.controlledSide=-1;
					else sideTaken[side]=true;
				}
				auto freeSides=iota(32).filter!(i=>!sideTaken[i]);
				foreach(i,ref player;network.players){
					if(player.settings.observer) continue;
					if(freeSides.empty) break;
					if(player.settings.controlledSide!=-1) continue;
					network.updateSetting!"controlledSide"(cast(int)i,freeSides.front);
					freeSides.popFront();
				}
				if(options._2v2||options._3v3){
					int teamSize=1;
					if(options._2v2) teamSize=2;
					if(options._3v3) teamSize=3;
					foreach(i,ref player;network.players){
						auto side=player.settings.controlledSide;
						if(side>=0) network.updateSetting!"team"(cast(int)i,side/teamSize);
					}
				}
				if(options.shuffleSides){
					auto π=iota(network.players.length).array;
					import std.random:randomShuffle;
					randomShuffle(π);
					auto sides=network.players.map!((ref p)=>p.settings.controlledSide).array;
					auto teams=network.players.map!((ref p)=>p.settings.team).array;
					foreach(i,j;π){
						network.updateSetting!"controlledSide"(cast(int)i,sides[j]);
						network.updateSetting!"team"(cast(int)i,teams[j]);
					}
				}
				if(options.shuffleTeams){
					auto π=iota(network.players.length).array;
					import std.random:randomShuffle;
					randomShuffle(π);
					auto teams=network.players.map!((ref p)=>p.settings.team).array;
					foreach(i,j;π) network.updateSetting!"team"(cast(int)i,teams[j]);
				}
				if(options.synchronizeLevel) network.synchronizeSetting!"level"();
				if(options.synchronizeSouls) network.synchronizeSetting!"souls"();
				foreach(player;0..cast(int)network.players.length){
					if(player==network.me) continue;
					if(options.randomSpellbooks) network.updateSetting!"spellbook"(player,randomSpells());
					import std.random: uniform;
					import nttData:wizards;
					if(options.randomWizards) network.updateSetting!"wizard"(player,cast(char[4])wizards[uniform!"[)"(0,$)]);
				}
				network.updateStatus(PlayerStatus.readyToLoad);
				assert(network.readyToLoad());
				break;
			}
		}
		if(network.isHost){
			network.load();
		}else{
			while(!network.loading){
				network.idleLobby();
				if(!backend.processEvents()) return;
			}
		}
		options.settings=network.settings;
		controlledSide=options.settings.controlledSide;
	}
	auto hmap=getHmap(options.map);
	auto map=new SacMap!B(hmap);
	auto sids=loadSids(hmap[0..$-".HMAP".length]~".SIDS");
	auto ntts=loadNTTs(hmap[0..$-".HMAP".length]~".NTTS");
	auto sides=new Sides!B(sids);
	auto state=new GameState!B(map,sides,ntts,options);
	int[32] multiplayerSides=-1;
	bool[32] matchedSides=false;
	foreach(i,ref side;sids){
		int mpside=side.assignment&PlayerAssignment.multiplayerMask;
		if(!mpside) continue;
		multiplayerSides[mpside-1]=cast(int)i;
		matchedSides[i]=true;
	}
	iota(32).filter!(i=>!matchedSides[i]).copy(multiplayerSides[].filter!(x=>x==-1));
	int multiplayerSide(int side){
		if(side<0||side>=multiplayerSides.length) return side;
		return multiplayerSides[side];
	}
	if(network){ // TODO: factor out relevant parts for local games
		foreach(i,ref a;network.players){
			if(a.settings.observer) continue;
			foreach(ref b;network.players[i+1..$]){
				if(b.settings.observer) continue;
				int s=multiplayerSide(a.settings.controlledSide), t=multiplayerSide(b.settings.controlledSide);
				assert(s!=t);
				int x=a.settings.team, y=b.settings.team;
				auto stance=x!=-1&&y!=-1&&x==y?Stance.ally:Stance.enemy;
				sides.setStance(s,t,stance);
				sides.setStance(t,s,stance);
			}
		}
	}
	int id=0;
	if(!playback){
		void placeWizard(Settings settings){
			if(settings.observer) return;
			auto wizard=SacObject!B.getSAXS!Wizard(settings.wizard[0..4]);
			//printWizardStats(wizard);
			auto spellbook=getSpellbook!B(settings.spellbook);
			auto flags=0;
			auto wizId=state.current.placeWizard(wizard,flags,multiplayerSide(settings.controlledSide),settings.level,settings.souls,move(spellbook));
			if(settings.controlledSide==controlledSide) id=wizId;
		}
		if(network){
			foreach(ref player;network.players)
				placeWizard(player.settings);
		}else{
			placeWizard(options.settings);
			if(options.protectManafounts){
				foreach(i;0..options.protectManafounts) state.current.uniform(2);
				state.current.eachBuilding!((bldg,state){
					if(bldg.componentIds.length==0||!bldg.isManafount) return;
					auto bpos=bldg.position(state);
					import nttData;
					static immutable lv1Creatures=[persephoneCreatures[0..3],pyroCreatures[0..3],jamesCreatures[0..3],stratosCreatures[0..3],charnelCreatures[0..3]];
					auto tags=lv1Creatures[state.uniform(cast(int)$)];
					foreach(i;0..10){
						auto tag=tags[state.uniform(cast(int)$)];
						int flags=0;
						int side=1;
						auto position=bpos+10.0f*state.uniformDirection();
						import dlib.math.portable;
						auto facing=state.uniform(-pi!float,pi!float);
						state.placeCreature(tag,flags,side,position,facing);
					}
				})(state.current);
			}
		}
	}else{
		enforce(playback.committed.length&&playback.committed[0].frame==0);
		state.current.copyFrom(playback.committed[0]);
		assignArray(state.commands,playback.commands);
	}
	state.commit();
	Recording!B recording=null;
	if(!playback&&options.recordingFilename.length){
		recording=new Recording!B(options.map);
		recording.logCore=options.logCore;
	}
	auto controller=new Controller!B(multiplayerSide(controlledSide),state,network,recording);
	backend.setState(state);
	if(id) backend.focusCamera(id);
	else backend.scene.fpview.active=true;
	backend.setController(controller);
	if(options.observer) controller.controlledSide=-1;
}

int main(string[] args){
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
		//shadowMapResolution: 8192,
		//shadowMapResolution: 4096,
		//shadowMapResolution: 2048,
		shadowMapResolution: 1024,
		enableWidgets: true,
	};
	options.controlledSide=int.min;
	static Tuple!(int,"width",int,"height") parseResolution(string s){
		auto t=s.split('x');
		if(t.length==2) return tuple!("width","height")(to!int(t[0]),to!int(t[1]));
		return tuple!("width","height")(16*to!int(s)/9,to!int(s));
	}
	foreach(opt;opts){
		if(opt.startsWith("--resolution=")){
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
		}else if(opt=="--observer"){
			options.observer=true;
		}else if(opt.startsWith("--side=")){
			options.controlledSide=to!int(opt["--side=".length..$]);
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
			options.host=2;
		}else if(opt.startsWith("--host=")){
			options.host=to!int(opt["--host=".length..$]);
		}else LoptSwitch: switch(opt){
			static string getOptionName(string memberName){
				import std.ascii;
				auto m=memberName;
				if(m.startsWith("_")) m=m["_".length..$];
				if(m.startsWith("enable")) m=m["enable".length..$];
				else if(m.startsWith("disable")) m=m["disable".length..$];
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
	if(options.controlledSide==int.min){
		options.controlledSide=options.observer?-1:0;
	}
	if(options.host&&options._2v2) options.host=max(options.host,4);
	if(options.host&&options._3v3) options.host=max(options.host,6);
	if(options.wizard=="\0\0\0\0"||options.randomWizards){
		import std.random: uniform;
		import nttData:wizards;
		options.wizard=cast(char[4])wizards[uniform!"[)"(0,$)];
	}
	if(options.god==God.none){
		import std.random: uniform;
		options.god=cast(God)uniform!"[]"(1,5);
	}
	if(options.randomSpellbook||options.randomSpellbooks){
		options.spellbook=randomSpells();
	}else options.spellbook=defaultSpells[options.god];
	enum commit = tryImport!("git/"~tryImport!("git/HEAD","ref: ")["ref: ".length..$],"");
	writeln("SacEngine ",commit.length?text("commit ",commit):"","build ",__DATE__," ",__TIME__);
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
	auto backend=B(options);
	foreach(arg;args){
		if(arg.endsWith(".scp")||arg.endsWith(".HMAP")){
			options.map=arg;
		}
	}
	if(options.map==""){
		import std.file;
		auto candidates=!options.mapList?dirEntries("maps","*.scp",SpanMode.depth).map!(x=>cast(string)x).array:File(options.mapList).byLineCopy.map!(l=>stripComment(l.strip)).filter!(l=>!l.empty).array;
		import std.random:uniform;
		auto map=candidates.length?candidates[uniform!"[)"(0,$)]:"";
		if(map!="") stdout.writefln!"selected map '%s'"(map);
		options.map=map;
	}
	if(options.map!="") loadMap(backend,options);

	foreach(ref i;1..args.length){
		string anim="";
		if(i+1<args.length&&args[i+1].endsWith(".SXSK"))
			anim=args[i+1];
		if(!(args[i].endsWith(".scp")||args[i].endsWith(".HMAP"))){
			auto sac=new SacObject!B(args[i],float.nan,anim);
			auto position=Vector3f(1270.0f, 1270.0f, 0.0f);
			if(B.state && B.state.current.isOnGround(position))
				position.z=B.state.current.getGroundHeight(position);
			backend.addObject(sac,position,facingQuaternion(0));
		}
		if(i+1<args.length&&args[i+1].endsWith(".SXSK")){
			i+=1;
			import sxsk;
			static if(!gpuSkinning){
				if(i+1<args.length&&args[i+1].toLower.endsWith(".obj")){
					auto sacObj=backend.scene.sacs[backend.scene.sacs.length-1];
					auto file=File(args[i+1],"w");
					import saxs2obj;
					file.writeObj(sacObj.saxsi.saxs,sacObj.animations[0].frames[0]);
					i+=1;
				}
			}
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
		B.controller.recording.save(options.recordingFilename);
	}
	backend.run();
	return 0;
}
