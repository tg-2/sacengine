// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import std.exception, std.string;
import util;

enum BldgFlags:uint{
	none=0,
	unknown=1<<3,
	shelter=1<<15, // TODO: correct?
	ground=1<<31,
}
struct BldgHeader{
	BldgFlags flags;
	ubyte[8][8] ground;
	uint maxHealth;
	float[10] unknown1;
	char[4] tileset;
	char[4] unknown2;
	uint numComponents;
	char[4] base;
}
static assert(BldgHeader.sizeof==128);
struct BldgComponent{
	char[4] kind;
	char[4] tag;
	char[4] unknown0;
	char[4] destroyed;
	float unknown1;
	float x,y,z;
	float facing;
	ubyte[8] unknown2;
	char[4] destruction;
}
static assert(BldgComponent.sizeof==48);

struct Bldg{
	BldgHeader* header;
	alias header this;
	BldgComponent[] components;
}

Bldg parseBldg(ubyte[] data){
	auto header=cast(BldgHeader*)data[0..BldgHeader.sizeof].ptr;
	enforce(data.length==BldgHeader.sizeof+header.numComponents*BldgComponent.sizeof);
	auto components=cast(BldgComponent[])data[BldgHeader.sizeof..$];
	auto bldg=Bldg(header,components);
	return bldg;
}

Bldg loadBldg(string filename){
	enforce(filename.endsWith(".BLDG"));
	return parseBldg(readFile(filename));
}
