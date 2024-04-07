// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import options;
import dagonBackend;
import ntts:God;
import state:randomSpells,defaultSpells;
import recording_:loadRecording;
import lobby:Lobby,LobbyState;
import wadmanager,util;
import dlib.math;
import std.string, std.array, std.range, std.algorithm, std.stdio;
import std.exception, std.conv, std.typecons;

import speechexport;

void wait(B)(int msecs=1){
	import core.thread;
	Thread.sleep(msecs.msecs);
	if(!B.processEvents()) return;
}

Lobby!B makeLobby(B)(ref Options options)out(lobby){
	assert(lobby.state.among(LobbyState.offline,LobbyState.connected));
}do{
	auto lobby=new Lobby!B();
	auto slot=options.observer?-1:options.slot;
	lobby.initialize(slot,options);
	assert(lobby.state==LobbyState.initialized);
	while(!lobby.tryConnect(options))
		wait!B(200); // TODO: loop externally
	assert(lobby.state.among(LobbyState.offline,LobbyState.connected));
	if(lobby.canPlayRecording&&options.playbackFilename.length){
		auto recording=loadRecording!B(options.playbackFilename);
		lobby.initializePlayback(recording,options.continueFrame,options);
	}
	if(lobby.canContinue&&options.continueFilename.length){
		auto recording=loadRecording!B(options.continueFilename);
		lobby.continueGame(recording,options.continueFrame,options);
	}
	return lobby;
}

bool updateLobby(B)(Lobby!B lobby,ref Options options){
	if(lobby.state==LobbyState.incompatibleVersion)
		return true;
	if(!lobby.update(options))
		return false;
	assert(lobby.state==LobbyState.readyToStart);
	lobby.start(options);
	return true;
}

void loadGame(B)(ref Options options)in{
	assert(options.map.endsWith(".scp")||options.map.endsWith(".HMAP"));
}do{
	auto lobby=makeLobby!B(options);
	while(!updateLobby(lobby,options))
		wait!B();
}

string stripComment(string s){
	auto i=s.indexOf('#');
	if(i==-1) return s;
	return s[0..i];
}
string[] importSettings(string filename){
	return expandSettings(File(filename).byLineCopy.map!stripComment.map!strip.filter!(l=>l.length!=0).array);
}
string[] expandSettings(string[] settings){
	if(!settings.any!(setting=>setting.startsWith("--import="))) return settings;
	string[] result;
	foreach(setting;settings){
		if(setting.startsWith("--import=")){
			auto filename=setting["--import=".length..$];
			result~=importSettings(filename);
		}else result~=setting;
	}
	return result;
}

int run(string[] args){
	import std.file:thisExePath,chdir;
	import std.path:dirName;
	chdir(dirName(thisExePath()));
	import core.memory;
	GC.disable();
	if(args.length==0) args~="";
	bool redirected=false;
	void redirect(){
		if(redirected) return;
		if(args.canFind("--redirect-output")){
			stdout.reopen("SacEngine.out.txt","w");
			stderr.reopen("SacEngine.err.txt","w");
		}
		redirected=true;
	}
	redirect();
	args=expandSettings(args);
	redirect();
	import std.file:exists;
	if(!args.canFind("--ignore-settings")&&exists("settings.txt")) args=chain(args[0..1],importSettings("settings.txt"),args[1..$]).array;
	redirect();
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
		}else if(opt.startsWith("--double-click-speed=")){
			options.doubleClickSpeed=to!int(opt["--double-click-speed=".length..$]);
		}else if(opt.startsWith("--camera-mouse-sensitivity")){
			options.cameraMouseSensitivity=to!float(opt["--camera-mouse-sensitivity=".length..$]);
		}else if(opt.startsWith("--mouse-wheel-sensitivity")){
			options.mouseWheelSensitivity=to!float(opt["--mouse-wheel-sensitivity=".length..$]);
		}else if(opt.startsWith("--window-scroll-x-factor=")){
			options.windowScrollXFactor=to!float(opt["--window-scroll-x-factor=".length..$]);
		}else if(opt.startsWith("--window-scroll-y-factor=")){
			options.windowScrollYFactor=to!float(opt["--window-scroll-y-factor=".length..$]);
		}else if(opt.startsWith("--join=")){
			options.joinIP=opt["--join=".length..$];
		}else if(opt=="--join"){
			options.joinIP="255.255.255.255";
		}else if(opt.startsWith("--record=")){
			options.recordingFilename=opt["--record=".length..$];
		}else if(opt.startsWith("--record-folder=")){
			options.recordingFolder=opt["--record-folder=".length..$];
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
		}else if(opt=="--no-observer"){
			options.observer=false;
		}else if(opt=="--observer-chat"){
			options.observerChat=true;
		}else if(opt=="--no-observer-chat"){
			options.observerChat=false;
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
				reverse(cast(ubyte[])tag[]);
				if(wizards.canFind(reversed)){
					tag=reversed;
				}else{
					stderr.writefln!"error: unknown wizard '%s'"(wizard);
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
		}else if(opt.startsWith("--min-level=")){
			options.minLevel=to!int(opt["--min-level=".length..$]);
		}else if(opt.startsWith("--max-level=")){
			options.maxLevel=to!int(opt["--max-level=".length..$]);
		}else if(opt.startsWith("--xp-rate=")){
			options.xpRate=to!float(opt["--xp-rate=".length..$]);
		}else if(opt.startsWith("--map-list=")){
			options.mapList=opt["--map-list=".length..$];
		}else if(opt=="--scenario"){
			options.gameMode=GameMode.scenario;
		}else if(opt=="--skirmish"){
			options.gameMode=GameMode.skirmish;
		}else if(opt.startsWith("--slaughter=")){
			options.gameMode=GameMode.slaughter;
			options.gameModeParam=to!int(opt["--slaughter=".length..$]);
		}else if(opt.startsWith("--domination=")){
			options.gameMode=GameMode.domination;
			options.gameModeParam=to!int(opt["--domination=".length..$]);
		}else if(opt.startsWith("--soul-harvest=")){
			options.gameMode=GameMode.soulHarvest;
			options.gameModeParam=to!int(opt["--soul-harvest=".length..$]);
		}else if(opt.startsWith("--delay-start=")){
			options.delayStart=to!int(opt["--delay-start=".length..$]);
		}else if(opt.startsWith("--zerotier-network=")){
			options.zerotierNetwork=to!ulong(opt["--zerotier-network=".length..$],0x10);
		}else if(opt.startsWith("--zerotier-identity=")){
			options.zerotierIdentity=opt["--zerotier-identity=".length..$];
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
			static foreach(member;[__traits(allMembers,Options),__traits(allMembers,Settings)]){
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
	}

	if(options.zerotierNetwork&&(options.host||options.joinIP!="")){
		import zerotier;
		connectToZerotier(options.zerotierIdentity,options.zerotierNetwork);
	}
	if(options.map!=""&&!options.noMap){
		// loadGame!B(options);
		auto lobby=makeLobby!B(options);
		B.addLogicCallback(()=>!updateLobby(lobby,options));
	}else B.scene.fpview.active=true;

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
		if(!(args[i].endsWith(".scp")||args[i].endsWith(".rcp")||args[i].endsWith(".HMAP"))){
			import sacobject:SacObject;
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
	/+scope(exit){
		foreach(frame,ref inFrame;B.state.commands.data){
			writeln(frame,": ", inFrame.data.map!((ref c)=>text("(",c.side,",",c.id,",",c.type,")")).joiner(","));
			stdout.flush();
		}
	}+/
	scope(exit) if(B.network) B.network.shutdown();
	if(options.recordingFolder.length){
		if(!options.recordingFilename.length){
			auto recordingFolder=options.recordingFolder;
			string tag="";
			if(options.recordingFolder.canFind(':')){
				auto index=recordingFolder.indexOf(':');
				tag=recordingFolder[index+1..$];
				recordingFolder=recordingFolder[0..index];
			}
			auto recordingName="";
			if(tag.length){
				recordingName~=tag;
				recordingName~='-';
			}
			import std.datetime, std.utf;
			recordingName~=Clock.currTime.toISOExtString.byChar.until('.').text.replace('T','-').replace(':','-');
			import std.path:buildPath;
			recordingName=buildPath(recordingFolder,recordingName~".rcp");
			options.recordingFilename=recordingName;
		}else stderr.writeln("warning: used both --record=... and --record-folder=... options.");
	}
	scope(exit) if(B.controller&&B.controller.recording){
		B.controller.recording.finalize(B.state.commands);
		writeln("saving recording to '",options.recordingFilename,"'");
		B.controller.recording.save(options.recordingFilename,options.compressRecording);
	}
	GC.collect();
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
