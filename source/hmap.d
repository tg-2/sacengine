import dagon;
import util;
import std.stdio, std.exception, std.string;

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
	auto edges=new bool[][](height,width);
	auto heights=new float[][](height,width);
	foreach(y;0..height){
		foreach(x;0..width){
			auto elevation=hmapData[(height-1-y)*width+x];
			auto isVoid=!!(elevation&(1<<15));
			elevation&=~(1<<15);
			edges[y][x]=isVoid;
			heights[y][x]=elevation/0.1f;
		}
	}
	return HMap(edges,heights);
}

HMap loadHMap(string filename){
	enforce(filename.endsWith(".HMAP"));
	ubyte[] data;
	foreach(ubyte[] chunk;chunks(File(filename,"rb"),4096)) data~=chunk;
	return parseHMap(data);
}
