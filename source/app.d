import options;
import dagonBackend;
import ntts, sacobject, sacmap, state;
import util;
import dlib.math;
import std.string;
import std.exception;
import std.algorithm;

void main(string[] args){
	import core.memory;
	GC.disable(); // TODO: figure out where GC memory is used incorrectly
	if(args.length==1) args~="extracted/jamesmod/JMOD.WAD!/modl.FLDR/jman.MRMC/jman.MRMM";
	Options options={
		//shadowMapResolution: 8192,
		//shadowMapResolution: 4096,
		//shadowMapResolution: 2048,
		shadowMapResolution: 1024,
	};
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
			auto sac=new SacObject!DagonBackend(args[i], args[i].endsWith(".SXMD")?2e-3:1, anim);
			auto position=Vector3f(1270.0f, 1270.0f, 0.0f);
			if(state && state.isOnGround(position))
				position.z=state.getGroundHeight(position);
			backend.addObject(sac,position,facingQuaternion(0));
		}
		if(i+1<args.length&&args[i+1].endsWith(".SXSK"))
			i+=1;
	}
	backend.run();
}
