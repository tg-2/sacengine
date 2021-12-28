 // copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import state, util, serialize_;
import std.exception, std.stdio;

class Recording(B){
	string mapName;
	this(string mapName){
		this.mapName=mapName;
	}
	GameInit!B gameInit;
	bool finalized=false;
	Array!(Array!(Command!B)) commands;
	void finalize(Array!(Array!(Command!B)) commands){
		assignArray(this.commands,commands);
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
	void stepCommitted(ObjectState!B state){
		events~=Event(EventType.stepCommitted);
		if(!logCore) return;
		if(core.length<logCore){
			auto copy=new ObjectState!B(state.map,state.sides,state.proximity,state.pathFinder);
			copy.copyFrom(state);
			core~=copy;
		}else{
			coreIndex=coreIndex+1;
			if(coreIndex>=core.length) coreIndex=1;
			core[coreIndex].copyFrom(state);
		}
	}
	void addCommand(int frame,Command!B command){
		events~=Event(EventType.addCommand,frame,command);
	}
	void addExternalCommand(int frame,Command!B command){
		events~=Event(EventType.addExternalCommand,frame,command);
	}
	void step(){ events~=Event(EventType.step); }

	static struct Desynch{
		int side;
		ObjectState!B desynchedState;
	}
	Array!Desynch desynchs;

	void save(string filename,bool zlib=true){
		ubyte[] data;
		void sink(scope ubyte[] bytes){ data~=bytes; }
		serialize!sink(this);
		auto file=File(filename,"wb");
		if(zlib){
			import std.zlib; // TOOD: compress on the fly
			data=compress(data);
			file.rawWrite("RCPC");
		}else{
			file.rawWrite("RCP_");
		}
		file.rawWrite(data);
	}
}

Recording!B loadRecording(B)(string filename){
	Array!ubyte rawData;
	foreach(ubyte[] chunk;chunks(File(filename,"rb"),4096))
		rawData~=chunk;
	auto recording=new Recording!B("");
	auto consumed=rawData.data;
	import std.algorithm;
	if(consumed.startsWith("RCPC")){
		import std.zlib;
		consumed=cast(ubyte[])uncompress(consumed[4..$]); // TODO: uncompress on the fly
	}else{
		enforce(consumed.startsWith("RCP_"));
		consumed=consumed[4..$];
	}
	deserialize(recording,consumed);
	return recording;
}
