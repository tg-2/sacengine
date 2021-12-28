// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import util;
import std.exception, std.string;

import ntts:God;
struct Levl{
	uint[3] unknown;
	uint multiSouls;
	uint multiMinLevel;
	uint multiMaxLevel;
	uint singleSouls;
	uint singleStartLevel;
	uint singleMaxLevel;
	God singleAssociatedGod;
	char[4] retroTileset;
}
static assert(Levl.sizeof==44);

Levl parseLevl(ubyte[] data){
	enforce(data.length==Levl.sizeof);
	auto levl=*cast(Levl*)data.ptr;
	return levl;
}

Levl loadLevl(string filename){
	enforce(filename.endsWith(".LEVL"));
	auto data=readFile(filename);
	return parseLevl(data);
}

enum Tileset{
	ethereal,
	persephone,
	pyro,
	james,
	stratos,
	charnel
}

Tileset detectTileset(ref Levl levl){
	switch(levl.retroTileset) with(Tileset){
		case "rhte": return ethereal;
		case "csrp": return persephone;
		case "A_YP": return pyro;
		case "A_AJ": return james;
		case "A_TS": return stratos;
		case "rahc": return charnel;
		default: enforce(0); assert(0);
	}
}
