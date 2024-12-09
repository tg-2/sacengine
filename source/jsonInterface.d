import util,state,controller;
import sacobject,sacspell;
import std.format,std.range,std.exception,std.utf,std.uni,std.string,std.algorithm,std.conv;
import dlib.math;

struct JSONBuilder{
	bool names=true;
	bool numSouls=false;

	Array!char message;
	void put(scope const(char)[] data){
		message~=data.byChar; // TODO: probably this is quite slow
	}
	void put(T...)(T args)if(T.length!=1){
		foreach(arg;args) put(arg);
	}
	void begin(){
		message.length=0;
		put("{");
	}
	void end(scope void delegate(scope const(char)[] json) dg){
		put("}");
		dg(message.data);
		message.length=0;
	}
	void field(string name){
		put(`"`,name,`":`);
	}
	void value(T)(ref T val)if(!is(T==struct)&&!is(T==class)&&!is(T==S[],S)&&!is(T==S[n],S,size_t n)){
		formattedWrite!`"%s"`(&put,val);
	}
	int numArrayElements=0;
	void beginArray()in{
		assert(!numArrayElements,"nested arrays not supported yet");
	}do{
		put("[");
	}
	void arrayElement(T)(ref T val){
		if(numArrayElements++) put(",");
		value(val);
	}
	void endArray(){
		put("]");
		numArrayElements=0;
	}
	void value(scope const(char)[] val){
		put(`"`,val,`"`); // TODO: escape string
	}
	void value(T)(T[] vals)if(!is(T==immutable(char))){
		put("[");
		foreach(i,ref val;vals){
			if(i) put(",");
			value(val);
		}
		put("]");
	}
	void value(T,size_t n)(ref T[n] vals){
		value(vals[]);
	}
	void value(T)(ref Array!T vals)if(!is(T==bool)){
		value(vals.data);
	}
	void value(T)(ref T val)if(is(T==Vector!(S,n),S,size_t n)){
		value(val.arrayof[]);
	}
	void value(T)(ref T val)if(is(T==Quaternionf)){
		value(val.vectorof);
	}
	void value(T)(ref T val)if(is(T==struct)&&!is(T==Array!S,S)&&!is(T==Vector!(S,n),S,size_t n)&&!is(T==Quaternionf)){
		put("{");
		enum members=__traits(allMembers,T);
		static foreach(i,alias member;T.tupleof){
			if(i) put(",");
			field(__traits(identifier,member));
			value(__traits(getMember,val,__traits(identifier,member)));
		}
		put("}");
	}
	void value(B)(SacSpell!B spell){
		put("{");
		field("name"); value(spell?spell.name:""); put(",");
		field("tag");
		if(spell){
			char[4] ntag=spell.tag;
			reverse(ntag[]);
			value(ntag);
		}else value("");
		put("}");
	}
	void value(B)(SacObject!B obj){
		put("{");
		field("name"); value(obj?obj.name:""); put(",");
		field("tag");
		if(obj){
			char[4] ntag=obj.tag;
			reverse(ntag[]);
			value(ntag);
		}else value("");
		if(numSouls){
			put(",");
			auto numSouls=obj?obj.numSouls:-1;
			field("numSouls"); value(numSouls);
		}
		put("}");
	}
	void value(B)(SacBuilding!B bldg){
		put("{");
		field("name"); value(bldg?bldg.name:""); put(",");
		field("tag");
		if(bldg){
			char[4] ntag=bldg.tag;
			reverse(ntag[]);
			value(ntag);
		}else value("");
		put("}");
	}
}

enum JSONCommandType{
	nop,
	getState,
	getReplay,
}

struct StateFlags{
	bool engineVersion;

	bool gameInit;
	bool state;
	bool mapInfo;
	bool sideInfo;
	bool sideState;
	bool triggerState;
	bool wizards;

	bool creatures;
	bool numSouls;

	bool structures;
	bool buildings;
	bool souls;
	bool effects;
}


struct JSONCommand{
	JSONCommandType type;
	StateFlags stateFlags;
}

JSONCommand parseJSONCommand(scope const(char)[] data){
	void next(){
		data.popFront();
	}
	void skipWhitespace(){
		while(!data.empty&&data.front.isWhite())
			next();
	}
	void expect(T...)(T args){
		static if(T.length==1){
			const(char)[] s=args[0];
			skipWhitespace();
			enforce(data.startsWith(s), format("expected '%s' got '%s%s'",s,data[0..min(data.length,25)],data.length>25?"...":""));
			data=data[s.length..$];
		}else foreach(arg;args) expect(arg);
	}
	T getString(T)(scope T delegate(scope const(char)[]) dg){
		expect(`"`);
		int last=0;
		auto str=data;
		while(data.length&&data.front!='"'){
			data.popFront();
		}
		str=str[0..data.ptr-str.ptr]; // TODO: unescape
		expect(`"`);
		return dg(str);
	}
	void processStringArray(scope void delegate(scope const(char)[]) dg){
		expect("[");
		for(int i=0;;i++){
			if(i) expect(",");
			skipWhitespace();
			if(!data.startsWith(`"`))
				break;
			getString(dg);
			if(data.startsWith("]"))
				break;
		}
		expect("]");
	}
	expect(`{`,`"type"`,":");
	void finish(){
		expect(`}`);
		skipWhitespace();
		enforce(data.empty,format("too much data: '%s'",data));
	}
	auto type=getString((str)=>to!JSONCommandType(str));
	final switch(type)with(JSONCommandType){
		case nop: finish(); return JSONCommand(type);
		case getState:
			expect(",",`"flags"`,":");
			StateFlags flags;
			processStringArray((str){
				switch(str){
					static foreach(flag;__traits(allMembers,StateFlags)){
						case flag:
							__traits(getMember,flags,flag)=true;
							return;
					}
					default:
						enforce(0,format("unknown flag '%s'",str));
				}
			});
			finish();
			return JSONCommand(type,flags);
		case getReplay: finish(); return JSONCommand(type);
	}
}

void runJSONCommand(B)(JSONCommand command,Controller!B controller,scope void delegate(scope const(char)[]) respond){
	with(command)final switch(command.type)with(JSONCommandType){
		case nop:
			return;
		case getState:
			auto gameState=controller.state;
			enforce(!!gameState,"no game state");
			auto state=gameState.current;
			enforce(!!state,"no game state");
			JSONBuilder json;
			json.begin();
			auto flags=stateFlags;
			json.numSouls=flags.numSouls;
			bool needComma=false;
			if(flags.engineVersion){
				if(needComma) json.put(",");
				struct EngineVersion{
					string date;
					string time;
					string commit;
				}
				EngineVersion engineVersion={
					date: __DATE__,
					time: __TIME__,
					commit: commit,
				};
				json.field("engineVersion");
				json.value(engineVersion);
				needComma=true;
			}
			if(flags.gameInit){
				if(needComma) json.put(",");
				json.field("gameInit");
				json.value(gameState.gameInit);
				needComma=true;
			}
			if(flags.state){
				if(needComma) json.put(",");
				json.field("state");
				json.put("{");
				json.field("frame"); json.value(state.frame);
				json.put("}");
				needComma=true;
			}
			if(flags.mapInfo){
				if(needComma) json.put(",");
				json.field("mapInfo");
				json.put("{");
				json.field("path"); json.value(state.map.path); json.put(",");
				json.field("crc32"); json.value(format(".%08x.scp",state.map.crc32));
				json.put("}");
				needComma=true;
			}
			if(flags.sideInfo){
				if(needComma) json.put(",");
				json.field("sideInfo");
				json.value(__traits(getMember,state.sides,"sides"));
				needComma=true;
			}
			if(flags.sideState){
				if(needComma) json.put(",");
				json.field("sideState");
				json.value(state.sid);
				needComma=true;
			}
			if(flags.triggerState){
				if(needComma) json.put(",");
				json.field("triggerState");
				json.value(state.trig);
				needComma=true;
			}
			if(flags.wizards){
				if(needComma) json.put(",");
				json.field("wizards");
				json.beginArray();
				state.eachWizard!((ref wizInfo){ json.arrayElement(wizInfo); });
				json.endArray();
				needComma=true;
			}
			if(flags.creatures){
				if(needComma) json.put(",");
				json.field("creatures");
				json.beginArray();
				state.eachMoving!((ref obj){ json.arrayElement(obj); });
				json.endArray();
				needComma=true;
			}
			if(flags.structures){
				if(needComma) json.put(",");
				json.field("structures");
				json.beginArray();
				state.eachStatic!((ref obj){ json.arrayElement(obj); });
				json.endArray();
				needComma=true;
			}
			if(flags.buildings){
				if(needComma) json.put(",");
				json.field("buildings");
				json.beginArray();
				state.eachBuilding!((ref obj){ json.arrayElement(obj); });
				json.endArray();
				needComma=true;
			}
			if(flags.souls){
				if(needComma) json.put(",");
				json.field("souls");
				json.beginArray();
				state.eachSoul!((ref obj){ json.arrayElement(obj); });
				json.endArray();
				needComma=true;
			}
			if(flags.effects){
				if(needComma) json.put(",");
				json.field("effects");
				json.beginArray();
				state.eachEffects!((ref eff){ json.arrayElement(eff); });
				json.endArray();
				needComma=true;
			}
			return json.end(respond);
		case getReplay:
			Array!ubyte recData;
			import recording_;
			recData.length=__traits(classInstanceSize,Recording!B);
			import core.lifetime;
			auto gameState=controller.state;
			if(!gameState||!gameState.current||!gameState.current.map) return respond("{}");
			auto recording=emplace!(Recording!B)(recData.data,gameState);
			Array!ubyte recordingData;
			recording.save((scope const(ubyte)[] data){ recordingData~=data; });
			import std.base64;
			respond(`{"base64":"`);
			scope(exit){
				respond(`"}`);
				destroy(recording);
			}
			Base64.encoder(recordingData.data.chunks(57)).each!respond;
			break;
	}
}
