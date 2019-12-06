import options;
import dagonBackend;
import sids, ntts, sacobject, sacmap, state, controller, network;
import wadmanager,util;
import dlib.math;
import std.string, std.array, std.range, std.algorithm, std.stdio;
import std.exception, std.conv, std.typecons;

int main(string[] args){
	import audio;
	loadAudio();
	scope(exit) unloadAudio();
	import core.memory;
	GC.disable(); // TODO: figure out where GC memory is used incorrectly
	if(args.length==0) args~="";
	import std.file:exists;
	if(!args.canFind("--ignore-settings")&&exists("settings.txt")) args=chain(args[0..1],File("settings.txt").byLineCopy.map!strip,args[1..$]).array;
	auto opts=args[1..$].filter!(x=>x.startsWith("--")).array;
	args=chain(args[0..1],args[1..$].filter!(x=>!x.startsWith("--"))).array;
	if(args.length==1){
		import std.file;
		auto candidates=dirEntries("maps","*.scp",SpanMode.depth).array;
		import std.random:uniform;
		auto map=candidates[uniform!"[)"(0,$)];
		stderr.writefln!"no map specified, selected '%s'"(map);
		args~=map;
		//args~="extracted/jamesmod/JMOD.WAD!/modl.FLDR/jman.MRMC/jman.MRMM".fixPath;
	}
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
		}else if(opt.startsWith("--shadow-map-resolution=")){
			options.shadowMapResolution=to!int(opt["--shadow-map-resolution=".length..$]);
		}else if(opt.startsWith("--glow-brightness=")){
			options.glowBrightness=to!float(opt["--glow-brightness=".length..$]);
		}else if(opt.startsWith("--replicate-creatures=")){
			options.replicateCreatures=to!int(opt["--replicate-creatures=".length..$]);
		}else if(opt.startsWith("--cursor-size=")){
			options.cursorSize=to!int(opt["--cursor-size=".length..$]);
		}else if(opt.startsWith("--volume=")){
			options.volume=to!float(opt["--volume=".length..$]);
		}else if(opt.startsWith("--music-volume=")){
			options.musicVolume=to!float(opt["--music-volume=".length..$]);
		}else if(opt.startsWith("--sound-volume=")){
			options.soundVolume=to!float(opt["--sound-volume=".length..$]);
		}else if(opt.startsWith("--join=")){
			options.joinIP=opt["--join=".length..$];
		}else if(opt.startsWith("--side=")){
			options.controlledSide=to!int(opt["--side=".length..$]);
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
			default:
				stderr.writeln("unknown option: ",opt);
				return 1;
		}
	}
	if(options.controlledSide==int.min){
		options.controlledSide=0;
	}
	if(options.wizard=="\0\0\0\0"){
		import std.random: uniform;
		import nttData:wizards;
		options.wizard=text((cast(char[4])wizards[uniform!"[)"(0,$)]));
	}
	if(options.god==God.none){
		import std.random: uniform;
		options.god=cast(God)uniform!"[]"(1,5);
	}
	enum commit = tryImport!("git/"~tryImport!("git/HEAD","ref: ")["ref: ".length..$],"");
	writeln("SacEngine ",commit.length?text("commit ",commit):"","build ",__DATE__," ",__TIME__);
	if(options.enableReadFromWads){
		wadManager=new WadManager;
		wadManager.indexWADs("data");
	}
	import nttData:initNTTData;
	initNTTData(options.enableReadFromWads);
	alias B=DagonBackend;
	auto backend=B(options);
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
		}
	}
	if(network){
		if(options.dumpTraffic) network.dumpTraffic=true;
		while(!network.synched) network.idleLobby();
		network.updateSettings(options.settings);
		if(!network.isHost) network.updateStatus(PlayerStatus.readyToLoad);
		while(!network.readyToLoad){
			network.idleLobby();
			if(network.isHost&&network.players.length>=options.host)
				network.updateStatus(PlayerStatus.readyToLoad);
		}
		if(network.isHost){
			network.load();
		}else{
			while(!network.loading) network.idleLobby();
		}
	}
	GameState!B state;
	int controlledSide=options.settings.controlledSide;
	void loadMap(string hmap){
		enforce(hmap.endsWith(".HMAP"));
		enforce(!state);
		auto map=new SacMap!B(hmap);
		auto sids=loadSids(hmap[0..$-".HMAP".length]~".SIDS");
		auto ntts=loadNTTs(hmap[0..$-".HMAP".length]~".NTTS");
		state=new GameState!B(map,sids,ntts,options);
		int id=0;
		void placeWizard(Settings settings){
			auto wizard=SacObject!B.getSAXS!Wizard(settings.wizard[0..4]);
			//printWizardStats(wizard);
			auto spellbook=getDefaultSpellbook!B(settings.god);
			auto wizId=state.current.placeWizard(wizard,settings.controlledSide,settings.level,settings.souls,spellbook);
			if(settings.controlledSide==controlledSide) id=wizId;
		}
		if(network){
			foreach(ref player;network.players)
				placeWizard(player.settings);
		}else placeWizard(options.settings);
		auto controller=new Controller!B(controlledSide,state,network);
		state.commit();
		backend.setState(state);
		if(id) backend.focusCamera(id);
		backend.setController(controller);
	}
	foreach(ref i;1..args.length){
		string anim="";
		if(i+1<args.length&&args[i+1].endsWith(".SXSK"))
			anim=args[i+1];
		if(args[i].endsWith(".scp")){
			if(!wadManager) wadManager=new WadManager();
			static string hmap; // TODO: this is a hack
			static int curMapNum=0;
			static void handle(string name){
				if(name.endsWith(".HMAP")) hmap=name;
			}
			wadManager.indexWAD!handle(args[i],text("`_map",curMapNum++));
			if(hmap) loadMap(hmap);
		}else if(args[i].endsWith(".HMAP")){
			loadMap(args[i]);
		}else{
			auto sac=new SacObject!B(args[i],float.nan,anim);
			auto position=Vector3f(1270.0f, 1270.0f, 0.0f);
			if(state && state.current.isOnGround(position))
				position.z=state.current.getGroundHeight(position);
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
	if(!network||network.isHost){
		auto delay=options.delayStart;
		while(delay){
			writeln(delay);
			delay--;
			import core.thread;
			Thread.sleep(1.dur!"seconds");
		}
	}
	backend.run();
	return 0;
}
