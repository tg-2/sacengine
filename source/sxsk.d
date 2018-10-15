import dagon;
import util;

import std.stdio, std.exception, std.algorithm, std.array;

struct Pose{
	Vector3f displacement;
	Quaternionf[] rotations;
}
private struct FrameHeader{
	short unknown;
	short[2] disp;
	uint offset;
}
static assert(FrameHeader.sizeof==12);

struct Animation{
	Pose[] frames;
}

Animation parseSXSK(ubyte[] data,float scaling){
	auto numFrames=*cast(ushort*)data[2..4].ptr;
	double offsetY=*cast(float*)data[4..8].ptr;
	auto numBones=*data[8..12].ptr;
	auto frameHeaders=cast(FrameHeader[])data[12..12+numFrames*FrameHeader.sizeof];
	Pose[] frames;
	foreach(i,ref frameHeader;frameHeaders){
		enforce(frameHeader.offset<=frameHeader.offset+numBones*(short[4]).sizeof && frameHeader.offset+numBones*(short[4]).sizeof<=data.length);
		auto anim=cast(short[4][])data[frameHeader.offset..frameHeader.offset+numBones*(short[4]).sizeof];
		auto rotations=anim.map!(x=>Quaternionf(Vector3f(fromSXMD([x[0],x[1],x[2]])),x[3]).normalized()).array;
		frames~=Pose(fromSXMD(Vector3f(frameHeader.disp[0],frameHeader.disp[1],0))*scaling,rotations);
	}
	return Animation(frames);
}

Animation loadSXSK(string filename,float scaling){
	enforce(filename.endsWith(".SXSK"), filename);
	ubyte[] data;
	foreach(ubyte[] chunk;chunks(File(filename,"rb"),4096)) data~=chunk;
	return parseSXSK(data,scaling);
}
