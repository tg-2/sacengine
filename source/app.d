import options;
import dagonBackend;
import ntts, sacobject, sacmap, state;
import util;
import dlib.math;
import std.string, std.array, std.range, std.algorithm, std.stdio;
import std.exception, std.conv;

int main(string[] args){
	import derelict.openal.al;
	DerelictAL.load();
	import derelict.mpg123;
	DerelictMPG123.load();
	import core.memory;
	GC.disable(); // TODO: figure out where GC memory is used incorrectly
	if(args.length==1) args~="extracted/jamesmod/JMOD.WAD!/modl.FLDR/jman.MRMC/jman.MRMM";
	auto opts=args[1..$].filter!(x=>x.startsWith("--")).array;
	args=chain(args[0..1],args[1..$].filter!(x=>!x.startsWith("--"))).array;
	Options options={
		//shadowMapResolution: 8192,
		//shadowMapResolution: 4096,
		//shadowMapResolution: 2048,
		shadowMapResolution: 1024,
		enableWidgets: true,
	};
	foreach(opt;opts){
		if(opt.startsWith("--shadow-map-resolution=")){
			options.shadowMapResolution=to!int(opt["--shadow-map-resolution=".length..$]);
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
					case "--disable-"~getOptionName(member):
						__traits(getMember,options,member)=false;
						break LoptSwitch;
					case "--enable-"~getOptionName(member):
						__traits(getMember,options,member)=true;
						break LoptSwitch;
				}
			}
			default:
				stderr.writeln("unknown option: ",opt);
				break;
		}
	}
	auto backend=DagonBackend(options);
	GameState!DagonBackend state;
	foreach(ref i;1..args.length){
		string anim="";
		if(i+1<args.length&&args[i+1].endsWith(".SXSK"))
			anim=args[i+1];
		if(args[i].endsWith(".HMAP")){
			enforce(!state);
			auto map=new SacMap!DagonBackend(args[i]);
			auto ntts=loadNTTs(args[i][0..$-".HMAP".length]~".NTTS");
			state=new GameState!DagonBackend(map,ntts,options);
			backend.setState(state);
		}else{
			auto sac=new SacObject!DagonBackend(args[i], args[i].endsWith(".SXMD")?2e-3f:1,1.0f,anim);
			auto position=Vector3f(1270.0f, 1270.0f, 0.0f);
			if(state && state.current.isOnGround(position))
				position.z=state.current.getGroundHeight(position);
			backend.addObject(sac,position,facingQuaternion(0));
		}
		if(i+1<args.length&&args[i+1].endsWith(".SXSK"))
			i+=1;
	}
	backend.run();
	return 0;
}
