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
	this(GameState!B gameState,bool finalized=true){
		auto state=gameState.current;
		enforce(state&&state.map);
		this(state.map.path,state.map,state.sides,state.proximity,state.pathFinder,state.triggers);
		this.gameInit=gameState.gameInit;
		if(finalized) finalize(gameState.commands);
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
		int slot;
		ObjectState!B desynchedState;
	}
	Array!Desynch desynchs;

	void logDesynch(int slot,scope ubyte[] serialized,ObjectState!B state)in{
		assert(!finalized);
	}do{
		auto desynchedState=new ObjectState!B(map,sides,proximity,pathFinder,triggers);
		deserialize(desynchedState,serialized);
		desynchs~=Desynch(slot,desynchedState);
	}

	void save(scope void delegate(scope const(ubyte)[]) sink,bool zlib=true){
		this.serialized((scope ubyte[] data){
			if(zlib){
				import std.zlib; // TOOD: compress on the fly
				data=compress(data);
				sink(cast(const(ubyte)[])"RCPC");
			}else{
				sink(cast(const(ubyte)[])"RCP_");
			}
			import std.conv: to;
			auto len=to!uint(commit.length);
			sink((*cast(const(ubyte)[4]*)&len)[]);
			sink(cast(const(ubyte)[])commit);
			sink(data);
		});
	}

	void save(string filename,bool zlib=true)in{
		assert(finalized);
	}do{
		auto file=File(filename,"wb");
		save(&file.rawWrite!ubyte,zlib);
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
	ObjectState!B desynch(int frame,out int slot){
		long l=-1,r=desynchs.length;
		enforce(l<r);
		while(l+1<r){
			long m=l+(r-l)/2;
			if(desynchs[m].desynchedState.frame<frame) l=m;
			else r=m;
		}
		if(r==desynchs.length) return null;
		if(desynchs[r].desynchedState.frame!=frame) return null;
		slot=desynchs[r].slot;
		return desynchs[r].desynchedState;
	}

	void report(GameState!B gameState){
		auto state=gameState.current;
		if(auto replacement=stateReplacement(state.frame)){
			assert(replacement.frame==state.frame);
			writeln("encountered state replacement at frame ",state.frame,replacement.hash!=state.hash?":":"");
			if(replacement.hash!=state.hash){
				import diff;
				diffStates(state,replacement);
				// state.copyFrom(replacement);
			}
		}
		int slot=-1;
		if(auto desynch=desynch(state.frame,slot)){
			auto slotName="";
			if(0<=slot&&slot<gameState.slots.length){
				auto side=gameState.slots[slot].controlledSide;
				slotName=getSideName(side,state);
			}
			if(slotName=="") writeln("player ",slot," desynched at frame ",state.frame);
			else writeln(slotName," (player ",slot,") desynched at frame ",state.frame);
			if(desynch.hash!=state.hash){
				writeln("their state was replaced:");
				import diff;
				diffStates(desynch,state);
			}
		}
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
	if(recordingCommit!=commit&&recordingCommit!="1f2dcc868277ad6d57ef4b5d5c09f77d00bee26c"){
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
