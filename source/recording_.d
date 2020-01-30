import state, util, serialize_;
import std.exception, std.container, std.stdio;

enum EventType{
	addCommand,
	addExternalCommand,
	stepCommitted,
	step,
}

struct Event(B){
	EventType event;
	int frame;
	Command!B command;
}

class Recording(B){
	string mapName;
	this(string mapName){
		this.mapName=mapName;
	}
	bool finalized=false;
	Sides!B sides=null;
	int committedIndex=0;
	Array!(ObjectState!B) committed;
	Array!(Array!(Command!B)) commands;
	Array!(Event!B) events;

	bool logCore=false;
	void addCommitted(ObjectState!B state){
		if(!logCore&&sides) return;
		if(!sides) sides=state.sides;
		else enforce(sides is state.sides);
		if(committed.length<120){
			auto copy=new ObjectState!B(state.map,state.sides,state.proximity);
			copy.copyFrom(state);
			committed~=copy;
		}else{
			committedIndex=committedIndex+1;
			if(committedIndex>=committed.length) committedIndex=1;
			committed[committedIndex].copyFrom(state);
		}
	}
	void addCommand(int frame,Command!B command){
		events~=Event!B(EventType.addCommand,frame,command);
	}
	void addExternalCommand(int frame,Command!B command){
		events~=Event!B(EventType.addExternalCommand,frame,command);
	}
	void step(){ events~=Event!B(EventType.step); }

	void finalize(Array!(Array!(Command!B)) commands)in{
		assert(sides);
	}do{
		assignArray(this.commands,commands);
		finalized=true;
	}

	void save(string filename){
		ubyte[] data;
		void sink(scope ubyte[] bytes){ data~=bytes; }
		serialize!sink(this);
		auto file=File(filename,"wb");
		//import std.zlib; // TOOD: compress on the fly
		//file.rawWrite(compress(data));
		file.rawWrite(data);
	}
}

Recording!B loadRecording(B)(string filename){
	Array!ubyte rawData;
	foreach(ubyte[] chunk;chunks(File(filename,"rb"),4096))
		rawData~=chunk;
	auto recording=new Recording!B("");
	auto consumed=rawData.data;
	deserialize(recording,consumed);
	//import std.zlub;
	//deserialize(loadRecording,uncompress(rawData.data));
	return recording;
}
