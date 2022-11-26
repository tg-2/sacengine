// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import sacmap, state, util, serialize_;
import std.exception, std.stdio, std.algorithm;

class Recording(B){
	string mapName;
	SacMap!B map;
	Sides!B sides;
	Proximity!B proximity;
	PathFinder!B pathFinder;
	Triggers!B triggers;
	this(string mapName,SacMap!B map,Sides!B sides,Proximity!B proximity,PathFinder!B pathFinder,Triggers!B triggers){
		this.mapName=mapName;
		this.map=map;
		this.sides=sides;
		this.proximity=proximity;
		this.pathFinder=pathFinder;
		this.triggers=triggers;
	}
	private this(){}
	GameInit!B gameInit;
	bool finalized=false;
	Array!(Array!(Command!B)) commands;
	void finalize(ref Array!(Array!(Command!B)) commands){
		if(finalized) return;
		this.commands=commands;
		sort!((a,b)=>a.frame<b.frame,SwapStrategy.stable)(stateReplacements.data);
		sort!((a,b)=>a.desynchedState.frame<b.desynchedState.frame,SwapStrategy.stable)(desynchs.data);
		finalized=true;
	}

	enum EventType{
		addCommand,
		addExternalCommand,
		stepCommitted,
		step,
	}
	static struct Event{
		EventType event;
		int frame;
		Command!B command;
	}
	Array!Event events;

	int logCore=0;
	int coreIndex=0;
	Array!(ObjectState!B) core;
	void stepCommitted(ObjectState!B state)in{
		assert(!finalized);
	}do{
		events~=Event(EventType.stepCommitted);
		if(!logCore) return;
		if(core.length<logCore){
			auto copy=new ObjectState!B(map,sides,proximity,pathFinder,triggers);
			copy.copyFrom(state);
			core~=copy;
		}else{
			coreIndex=coreIndex+1;
			if(coreIndex>=core.length) coreIndex=1;
			core[coreIndex].copyFrom(state);
		}
	}
	void addCommand(int frame,Command!B command)in{
		assert(!finalized);
	}do{
		events~=Event(EventType.addCommand,frame,command);
	}
	void addExternalCommand(int frame,Command!B command)in{
		assert(!finalized);
	}do{
		events~=Event(EventType.addExternalCommand,frame,command);
	}
	void step(){ events~=Event(EventType.step); }

	Array!(ObjectState!B) stateReplacements;
	void replaceState(ObjectState!B state,Array!(Array!(Command!B)) commands)in{
		assert(!finalized);
	}do{
		auto copy=new ObjectState!B(map,sides,proximity,pathFinder,triggers);
		copy.copyFrom(state);
		stateReplacements~=copy;
		// ignore commands for now
	}

	static struct Desynch{
		int side;
		ObjectState!B desynchedState;
	}
	Array!Desynch desynchs;

	void logDesynch(int side,scope ubyte[] serialized,ObjectState!B state)in{
		assert(!finalized);
	}do{
		auto desynchedState=new ObjectState!B(map,sides,proximity,pathFinder,triggers);
		deserialize(desynchedState,serialized);
		desynchs~=Desynch(side,desynchedState);
	}

	void save(string filename,bool zlib=true)in{
		assert(finalized);
	}do{
		this.serialized((scope ubyte[] data){
			auto file=File(filename,"wb");
			if(zlib){
				import std.zlib; // TOOD: compress on the fly
				data=compress(data);
				file.rawWrite("RCPC");
			}else{
				file.rawWrite("RCP_");
			}
			import std.conv: to;
			auto len=to!uint(commit.length);
			file.rawWrite((*cast(ubyte[4]*)&len)[]);
			file.rawWrite(commit);
			file.rawWrite(data);
		});
	}

	ObjectState!B stateReplacement(int frame){
		long l=-1,r=stateReplacements.length;
		enforce(l<r);
		while(l+1<r){
			long m=l+(r-l)/2;
			if(stateReplacements[m].frame<=frame) l=m;
			else r=m;
		}
		if(l==-1) return null;
		if(stateReplacements[l].frame!=frame) return null;
		return stateReplacements[l];
	}
	ObjectState!B desynch(int frame,out int side){
		long l=-1,r=desynchs.length;
		enforce(l<r);
		while(l+1<r){
			long m=l+(r-l)/2;
			if(desynchs[m].desynchedState.frame<frame) l=m;
			else r=m;
		}
		if(r==desynchs.length) return null;
		if(desynchs[r].desynchedState.frame!=frame) return null;
		side=desynchs[r].side;
		return desynchs[r].desynchedState;
	}
}

Recording!B loadRecording(B)(string filename)out(r){
	assert(r.finalized);
}do{
	Array!ubyte rawData;
	foreach(ubyte[] chunk;chunks(File(filename,"rb"),4096))
		rawData~=chunk;
	auto recording=new Recording!B;
	auto consumed=rawData.data;
	import std.algorithm;
	bool zlib=consumed.startsWith("RCPC");
	if(!zlib) enforce(consumed.startsWith("RCP_"));
	consumed=consumed[4..$];
	auto commitLength=consumed.parseUint;
	auto recordingCommit=consumed[0..commitLength];
	consumed=consumed[commitLength..$];
	if(recordingCommit!=commit){
		stderr.writeln("warning: recording '",filename,"' was saved with engine version:");
		stderr.writeln(cast(string)recordingCommit);
		stderr.writeln("this may be incompatible with the current version:");
		stderr.writeln(commit);
	}
	if(zlib){
		import std.zlib;
		consumed=cast(ubyte[])uncompress(consumed); // TODO: uncompress on the fly
	}
	deserialize(recording,consumed);
	enforce(recording.finalized);
	return recording;
}
