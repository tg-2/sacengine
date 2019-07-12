import util;
import std.stdio, std.traits, std.string, std.conv, std.exception, std.range, std.algorithm;

enum Type:uint{
	structure=2,
	wizard=4,
	spirit=8,
	creature=64,
	scar=128,
	marker=4096,
	widgets=8192,
}


struct Structure{
	Type type=Type.structure;
	uint size=48;
	float x,y,z;
	float facing;
	char[4] tag;
	Flags flags;
	uint side;
	uint unknown1=0;
	uint id; // 1-based id (0 is nothing)
	uint base=0; // for manaliths: id of manafount
}
static assert(Structure.sizeof==48);

enum God:uint{
	none=0,
	persephone=1,
	pyro=2,
	james=3,
	stratos=4,
	charnel=5,
}
enum Flags:uint{
	none=0,
	harmless=1,
	rescuable=2,
	corpse=4,
	damaged=8,
	cannotGib=16,
	destroyed=65536,
	notOnMinimap=33554432,
	cannotDamage=536870912,
	cannotDestroyKill=1073741824,
}
static foreach(e;EnumMembers!Flags) static assert((e&-e)==e);
struct Wizard{
	Type type=Type.wizard;
	uint size=56;
	float x,y,z;
	float facing;
	char[4] tag;
	Flags flags;
	uint side;
	uint unknown0=0;
	uint id;
	uint level;
	uint souls;
	God allegiance;
}
static assert(Wizard.sizeof==56);

struct Spirit{
	Type type=Type.spirit;
	uint size=28;
	float x,y,z;
	uint[2] unknown;
}
static assert(Spirit.sizeof==28);

struct Creature{
	Type type=Type.creature;
	uint size=48;
	float x,y,z;
	float facing;
	char[4] tag;
	Flags flags;
	uint side;
	uint unknown0=0;
	uint id;
	uint unknown1=0xffffffff;
}
static assert(Creature.sizeof==48);
struct Scar{
	Type type=Type.scar;
	uint size=36;
	float x,y;
	uint[5] unknown;
}
static assert(Scar.sizeof==36);

struct Marker{
	Type type=Type.marker;
	uint size=52;
	float x,y,z;
	uint[3] unknown0;
	uint side;
	uint[2] unknown1;
	float[2] unknown2;
}
static assert(Marker.sizeof==52);

struct WidgetHeader{
	Type type=Type.widgets;
	uint size;
	char[4] tag;
	uint num;
}
static assert(WidgetHeader.sizeof==16);
struct Widgets{
	WidgetHeader header;
	alias header this;
	float[3][] positions;
	string toString(){
		return text(`Widgets(`,type,", ",size,", ",tag,", ",num,", ",positions.map!(to!string).join(`, `),`)`);
	}	
}

struct NTTs{	
	//static foreach(t;[EnumMembers!Type].filter!(function(x)=>x!=Type.widgets)) // TODO: file bug
	static foreach(t;EnumMembers!Type)
		mixin(capitalize(text(t))~`[] `~text(t)~`s;`);	
}

NTTs parseNTTs(ubyte[] data){
	uint numNTTs=*cast(uint*)data[0..4].ptr;
	uint size=0;
	static foreach(t;[EnumMembers!Type].filter!(x=>x!=Type.widgets))
		mixin(capitalize(text(t))~`[] `~text(t)~`s;`);
	Widgets[] widgetss;
	for(int i=4;i<data.length;i+=size){
		auto type=*cast(Type*)data[i..i+4].ptr;
		size=*cast(uint*)data[i+4..i+8].ptr;
	Lswitch: switch(type){
			static foreach(t;[EnumMembers!Type].filter!(x=>x!=Type.widgets)){
				case t:
					enforce(size==mixin(capitalize(text(t))).sizeof,text(t," ",size," ",mixin(capitalize(text(t))).sizeof));
					enforce(i+size<=data.length);
					mixin(text(t)~`s`)~=mixin(`*cast(`~capitalize(text(t))~`*)&data[i]`);
					break Lswitch;
			}
			case Type.widgets:
				auto header=*cast(WidgetHeader*)&data[i];
				enforce(WidgetHeader.sizeof+header.num*(float[3]).sizeof==header.size);
				auto positions=cast(float[3][])data[i+WidgetHeader.sizeof..i+header.size];
				widgetss~=Widgets(header,positions);
				break;
			default:
				enforce(0, text("unknown entity type ",cast(uint)type));
		}
	}
	NTTs result;
	static foreach(t;EnumMembers!Type){
		mixin(text(`result.`,t,"s=",t,"s;"));
	}
	return result;
}

NTTs loadNTTs(string filename){
	enforce(filename.endsWith(".NTTS"));
	auto data=readFile(filename);
	return parseNTTs(data);
}
