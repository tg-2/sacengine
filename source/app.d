import options;
import dagonBackend;
import sacobject, sacmap;
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
	SacMap!DagonBackend map;
	foreach(ref i;1..args.length){
		string anim="";
		if(i+1<args.length&&args[i+1].endsWith(".SXSK"))
			anim=args[i+1];
		if(args[i].endsWith(".HMAP")){
			enforce(!map);
			map=new SacMap!DagonBackend(args[i]);
			backend.addMap(map);
		}else{
			auto sac=new SacObject!DagonBackend(args[i], args[i].endsWith(".SXMD")?2e-3:1, anim);
			sac.position=Vector3f(1270.0f, 1270.0f, 0.0f);
			if(map && map.isOnGround(sac.position))
				sac.position.z=map.getGroundHeight(sac.position);
			backend.addObject(sac);
		}
		if(i+1<args.length&&args[i+1].endsWith(".SXSK"))
			i+=1;
	}
	backend.run();
}
