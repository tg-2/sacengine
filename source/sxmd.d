// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import util;
import std.stdio;
import std.random;
import std.conv, std.algorithm, std.string, std.exception, std.path;
import std.array;
import std.typecons: tuple, Tuple;
import sxtx;

struct BoneData{
	float[3] pos;
	ushort parent;
	ushort unused0; // setting all those fields to 0 does not affect the ingame rendering
	float[3][8] hitbox;
	float[7] unused1; // setting all those fields to 0 does not affect the ingame rendering
}
static assert(BoneData.sizeof==140);

struct BodyPartHeader{
	ubyte numRings;
	ubyte additionalRingEntries;
	ushort numExplicitFaces;
	ubyte[16] unknown0;
	uint flags;
	uint explicitFaceOffset;
	uint stripsOffset;
	ubyte[4] unknown1;
}
static assert(BodyPartHeader.sizeof==36);

enum BodyPartFlags: uint{
	CLOSE_TOP=1, // make triangles from first vertex to all other vertices, facing up
	CLOSE_BOT=2, // make triangles from first vertex to all other vertices, facing down
}

struct RingHeader{
	ubyte numEntries; // number of RingEntries
	ubyte unknown;
	ushort texture; // this is some sort of offset into the texture data (multiplying by 2 duplicates textures).
	uint offset; // offset of first data byte of first TriangleStrip
}
static assert(RingHeader.sizeof==8);

struct Ring{
	RingHeader* header;
	alias header this;
	RingEntry[] entries;
	string toString(){
		return text("Ring(",*header,", ",entries,")");
	}
}

struct RingEntry{
	ushort[3] indices;
	ubyte alignment;
	ubyte textureV;
	ushort unknown1;
}
static assert(RingEntry.sizeof==10);

struct StripHeader{
	ubyte[2] unknown0;
	ushort numStrips;
	ubyte[4] unknown1;
}
static assert(StripHeader.sizeof==8);

static struct Strip{
	ushort bodyPart;
	ushort ring;
	ushort vertex;
	ubyte unknown; // setting to random data adds triangles that should not be there
	ubyte texture; // unknown what it does exactly
}
static assert(Strip.sizeof==8);

struct BodyPart{
	BodyPartHeader* header;
	alias header this;
	uint[] offsets;
	Ring[] rings;
	ushort[3][] explicitFaces;
	StripHeader* stripHeader;
	Strip[] strips;
	string toString(){
		return text("BodyPart(",*header,", ",rings,")");
	}
}

struct Position{
	short[3] pos;
	ushort bone;
	ubyte unknown0;
	ubyte weight;
	ubyte[6] unknown1;
}
static assert(Position.sizeof==16);

struct Model{
	float zfactor;
	BoneData[] bones;
	BodyPart[] bodyParts;
	Position[] positions;
}

Model parseSXMD(ubyte[] data){
	uint numBodyParts=data[0];
	float zfactor=*cast(float*)data[8..12].ptr;
	uint numBones=*cast(uint*)data[28..32].ptr-1;
	uint boneOffset=*cast(uint*)data[32..36].ptr+140;
	uint vertexOffset=*cast(uint*)data[36..40].ptr;
	auto bones=cast(BoneData[])data[boneOffset..boneOffset+numBones*BoneData.sizeof];
	BodyPart[] bodyParts;
	uint numPositions=0;
	for(int k=0;k<numBodyParts;k++){
		uint offset=*cast(uint*)data[40+4*k..44+4*k].ptr;
		auto header=cast(BodyPartHeader*)&data[offset];
		//writeln(header.numRings," ",header.unknown0);
		assert(offset<data.length);
		Ring[] edata;
		auto offsets=cast(uint[])data[offset+BodyPartHeader.sizeof..offset+BodyPartHeader.sizeof+uint.sizeof*header.numRings];
		foreach(i,off;offsets){
			auto ringHeader=cast(RingHeader*)&data[off];
			auto entries=cast(RingEntry[])data[ringHeader.offset..ringHeader.offset+(ringHeader.numEntries+256*header.additionalRingEntries)*RingEntry.sizeof];
			foreach(ref entry;entries){
				foreach(index;entry.indices){
					if(index!=ushort.max&&index>=numPositions) numPositions=index+1;
				}
			}
			version(change) eoffset=0;
			edata~=Ring(ringHeader,entries);
		}
		ushort[3][] explicitFaces=[];
		if(header.numExplicitFaces>0)
			explicitFaces=cast(ushort[3][])data[header.explicitFaceOffset..header.explicitFaceOffset+(ushort[3]).sizeof*header.numExplicitFaces];
		StripHeader* stripHeader;
		Strip[] strips;
		if(header.stripsOffset){
			stripHeader=cast(StripHeader*)data[header.stripsOffset..header.stripsOffset+StripHeader.sizeof];
			strips=cast(Strip[])data[header.stripsOffset+StripHeader.sizeof..header.stripsOffset+StripHeader.sizeof+Strip.sizeof*stripHeader.numStrips];
		}
		bodyParts~=BodyPart(header,offsets,edata,explicitFaces,stripHeader,strips);
	}
	auto positions=cast(Position[])data[vertexOffset..vertexOffset+Position.sizeof*numPositions];
	auto remainingDataOffset=vertexOffset+Position.sizeof*numPositions;
	return Model(zfactor,bones,bodyParts,positions);
}
