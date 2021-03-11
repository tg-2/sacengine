// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import util;
import std.stdio, std.exception, std.string, std.path, std.file, std.conv;

struct HMap{
	bool[][] edges;
	float[][] heights;
}

HMap parseHMap(ubyte[] data){
	auto width=parseLE(data[0..2]);
	data=data[2..$];
	auto height=parseLE(data[0..2]);
	data=data[2..$];
	auto hmapData=cast(ushort[])data[0..2*width*height];
	auto edges=new bool[][](width,height);
	auto heights=new float[][](width,height);
	foreach(y;0..height){
		foreach(x;0..width){
			auto elevation=hmapData[(height-1-y)*width+x];
			auto isVoid=!!(elevation&(1<<15));
			elevation&=~(1<<15);
			edges[y][x]=isVoid;
			heights[y][x]=elevation*0.1f;
		}
	}
	return HMap(edges,heights);
}

HMap loadHMap(string filename){
	enforce(filename.endsWith(".HMAP"));
	return parseHMap(readFile(filename));
}


struct TMap{
	ubyte[][] tiles;
}
TMap loadTMap(string filename){
	enforce(filename.endsWith(".TMAP"));
	auto data=readFile(filename);
	data=data[512..$]; // TODO: what is this data?
	auto tiles=new ubyte[][](256);
	foreach(y;0..256) tiles[y]=data[256*y..256*(y+1)];
	return TMap(tiles);
}

struct DTIndex{
	ubyte[] dts; // texture index to detail texture
}

struct MapGroup{
	ubyte[33] unknown0;
	ubyte num;
	ubyte[14] indices;
	ubyte[7] unknown1;
	ubyte dt;
	ubyte[4] unknown2;
}
static assert(MapGroup.sizeof==60);

DTIndex loadDTIndex(string dir){
	auto dts=new ubyte[](256);
	for(int i=0;fileExists(buildPath(dir,format("MG%02d.MAPG",i)));i++){
		auto mapgData=readFile(buildPath(dir,format("MG%02d.MAPG",i)));
		enforce(mapgData.length==MapGroup.sizeof);
		auto mapg=cast(MapGroup*)mapgData.ptr;
		foreach(j;0..mapg.num){
			dts[mapg.indices[j]]=mapg.dt;
		}
	}
	return DTIndex(dts);
}

struct LMap{
	ubyte[4][][] colors;
}

LMap parseLMap(ubyte[] data){
	enforce(data.length==4*256*256);
	auto colors=new ubyte[4][][](256);
	foreach(y;0..256) colors[y]=cast(ubyte[4][])data[4*256*y..4*256*(y+1)];
	return LMap(colors);
}

LMap loadLMap(string filename){
	enforce(filename.endsWith(".LMAP"));
	auto data=readFile(filename);
	auto tiles=new ubyte[][](256);
	foreach(y;0..256) tiles[y]=data[256*y..256*(y+1)];
	return parseLMap(data);
}

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

enum Tileset{
	ethereal,
	persephone,
	pyro,
	james,
	stratos,
	charnel
}

Tileset detectTileset(string filename){
	enforce(filename.endsWith(".LEVL"));
	auto data=readFile(filename);
	enforce(data.length==Levl.sizeof);
	auto Levl=cast(Levl*)data.ptr;
	switch(Levl.retroTileset) with(Tileset){
		case "rhte": return ethereal;
		case "csrp": return persephone;
		case "A_YP": return pyro;
		case "A_AJ": return james;
		case "A_TS": return stratos;
		case "rahc": return charnel;
		default: enforce(0); assert(0);
	}
}
