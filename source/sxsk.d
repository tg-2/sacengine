import dagon;
import util;

import std.stdio, std.exception, std.algorithm, std.array;


struct Transformation{
	Quaternionf rotation;
	Vector3f offset;
	this(Quaternionf rotation,Vector3f offset){
		this.rotation=rotation;
		this.offset=offset;
	}
	Vector3f rotate(Vector3f v){
		auto quat=Quaternionf(v[0],v[1],v[2],0.0);
		return Vector3f((rotation*quat*rotation.conj())[0..3]);
	}
	Vector3f opCall(Vector3f v){
		auto rotated=rotate(v);
		return rotated+offset;
	}
	Transformation opBinary(string op:"*")(Transformation rhs){
		return Transformation(rotation*rhs.rotation,opCall(rhs.offset));
	}
	Matrix4f getMatrix4f(){
		auto id=Matrix3f.identity();
		Matrix4f result;
		result.arrayof[0..3]=rotate(Vector3f(id.arrayof[0..3])).arrayof[];
		result.arrayof[3]=0.0f;
		result.arrayof[4..7]=rotate(Vector3f(id.arrayof[3..6])).arrayof[];
		result.arrayof[7]=0.0f;
		result.arrayof[8..11]=rotate(Vector3f(id.arrayof[6..9])).arrayof[];
		result.arrayof[11]=0.0f;
		result.arrayof[12..15]=offset.arrayof[];
		result.arrayof[15]=1.0f;
		return result;
	}
}

enum gpuSkinning=true;
struct Pose{
	Vector3f displacement;
	Quaternionf[] rotations;
	static if(gpuSkinning)
		Matrix4f[] matrices;
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
	enforce(numBones<=32);
	auto frameHeaders=cast(FrameHeader[])data[12..12+numFrames*FrameHeader.sizeof];
	Pose[] frames;
	foreach(i,ref frameHeader;frameHeaders){
		enforce(frameHeader.offset<=frameHeader.offset+numBones*(short[4]).sizeof && frameHeader.offset+numBones*(short[4]).sizeof<=data.length);
		auto anim=cast(short[4][])data[frameHeader.offset..frameHeader.offset+numBones*(short[4]).sizeof];
		auto displacement=fromSXMD(Vector3f(frameHeader.disp[0],frameHeader.disp[1],0))*scaling;
		auto rotations=anim.map!(x=>Quaternionf(Vector3f(fromSXMD([x[0],x[1],x[2]])),x[3]).normalized()).array;
		frames~=Pose(displacement,rotations);
	}
	return Animation(frames);
}

Animation loadSXSK(string filename,float scaling){
	enforce(filename.endsWith(".SXSK"), filename);
	ubyte[] data;
	foreach(ubyte[] chunk;chunks(File(filename,"rb"),4096)) data~=chunk;
	return parseSXSK(data,scaling);
}

static if(gpuSkinning){
	import saxs;
	void compile(ref Animation anim, ref Saxs saxs){
		enforce(saxs.bones.length<=32);
		foreach(ref frame;anim.frames){
			Transformation[32] transform;
			transform[0]=Transformation(Quaternionf.identity,Vector3f(0,0,0));
			foreach(j,ref bone;saxs.bones)
				transform[j]=transform[bone.parent]*Transformation(frame.rotations[j],bone.position);
			auto displacement=frame.displacement;
			displacement.z*=saxs.zfactor;
			foreach(j;0..saxs.bones.length)
				transform[j].offset+=displacement;
			auto matrices=new Matrix4f[](saxs.bones.length);
			foreach(j;0..saxs.bones.length)
				matrices[j]=transform[j].getMatrix4f();
			frame.matrices=matrices;
		}
	}
}
