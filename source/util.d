import dlib.math;
import std.typecons, std.algorithm;

alias Seq(T...)=T;

uint parseLE(ubyte[] raw)in{
	assert(raw.length<=4);
}body{
	uint r=0;
	foreach_reverse(x;raw) r=256*r+x;
	return r;
}

Vector3f fromSac(Vector3f v){
	return v;
}
float[3] fromSac(float[3] v){
	return v;
}

Vector3f fromSXMD(Vector3f v){
	return Vector3f(-v.x,-v.z,v.y);
}
float[3] fromSXMD(float[3] v){
	return [-v[0],-v[2],v[1]];
}

ubyte[] readFile(string filename){
	ubyte[] data;
	import std.stdio;
	foreach(ubyte[] chunk;chunks(File(filename,"rb"),4096)) data~=chunk;
	return data;
}

Quaternionf facingQuaternion(float facing){
	return rotationQuaternion(Axis.z,facing);
}

Vector3f rotate(Quaternionf rotation, Vector3f v){
	return rotation.rotate(v);
}

Quaternionf limitRotation(Quaternionf q, float maxAbsAngle){
	import std.math, std.algorithm;
	auto len=q.xyz.length;
	auto angle=atan2(len,q.w);
	if(angle<-maxAbsAngle) angle=-maxAbsAngle;
	if(angle>maxAbsAngle) angle=maxAbsAngle;
	if(angle==0.0f||len==0.0f) return Quaternionf.identity();
	return rotationQuaternion(q.xyz/len,angle); // dlib's rotationAxis is wrong
}

struct Transformation{
	Quaternionf rotation;
	Vector3f offset;
	this(Quaternionf rotation,Vector3f offset){
		this.rotation=rotation;
		this.offset=offset;
	}
	Vector3f rotate(Vector3f v){
		return .rotate(rotation,v);
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

Tuple!(Vector3f,Vector3f) bbox(R)(R positions){
	auto small=Vector3f(float.max,float.max,float.max);
	auto large=-small;
	foreach(p;positions){
		static foreach(k;0..3){
			small[k]=min(small[k],p[k]);
			large[k]=max(large[k],p[k]);
		}
	}
	return tuple(small,large);
}

import std.container.array;
T[] data(T)(ref Array!T array){
	// std.container.array should just provide this functionality...
	auto implPtr=array.tupleof[0]._refCounted.tupleof[0];
	if(!implPtr) return [];
	return implPtr._payload.tupleof[1];
}


void assignArray(T)(ref Array!T to, ref Array!T from){
	to.length=from.length;
	to.data[]=from.data[];
}
