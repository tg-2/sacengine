import util,state,controller;
import sacobject,sacspell;
import std.format,std.range,std.exception,std.utf,std.uni,std.string,std.algorithm,std.conv;
import dlib.math;

struct JSONBuilder{
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
		field("name"); value(spell.name); put(",");
		char[4] ntag=spell.tag;
		reverse(ntag[]);
		field("tag"); value(ntag);
		put("}");
	}
	void value(B)(SacObject!B obj){
		put("{");
		field("name"); value(obj.name); put(",");
		char[4] ntag=obj.tag;
		reverse(ntag[]);
		field("tag"); value(ntag);
		put("}");		
	}
	void value(B)(SacBuilding!B bldg){
		put("{");
		field("name"); value(bldg.name); put(",");
		char[4] ntag=bldg.tag;
		reverse(ntag[]);
		field("tag"); value(ntag);
		put("}");		
	}
}

enum JSONCommandType{
	nop,
	getState,
}

struct StateFlags{
	bool state;
	bool sideInfo;
	bool sideState;
	bool wizards;
	bool creatures;
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
			bool needComma=false;
			if(flags.state){
				if(needComma) json.put(",");
				json.field("state");
				json.put("{");
				json.field("frame"); json.value(state.frame);
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
	}
}
