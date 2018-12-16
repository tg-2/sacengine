import options;
import dagonBackend;
import ntts, sacobject, sacmap, state;
import util;
import dlib.math;
import std.string, std.array, std.range, std.algorithm, std.stdio;
import std.exception, std.conv;

int main(string[] args){
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
		}else if(opt=="--disable-widgets"){
			options.enableWidgets=false;
		}else{
			stderr.writeln("unknown option: ",opt);
			return 1;
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
			state=new GameState!DagonBackend(map,ntts);
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
