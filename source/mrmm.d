// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import sacobject;
import dlib.math;
import std.algorithm, std.range, std.exception;
import std.stdio, std.path;
import std.typecons: Tuple, tuple;
import util;

struct Vertex{
	float[3] pos;
	float[2] uv;
	uint unknown1=0xffffffff;
	uint unknown2=0;
	float[3] normal;
}
static assert(Vertex.sizeof==40);

struct Hitbox{
	uint unknown0;
	float[3][2] coords;
}
static assert(Hitbox.sizeof==28);

struct Face{
	uint[3] vertices;
	uint unknown0=0x00010001;
	char[4] retroName;
	string textureName(){
		auto tmp=retroName;
		reverse(tmp[]);
		return cast(string)tmp[].dup;
	}
	float[3] normal;
	uint lod;
}
static assert(Face.sizeof==36);

struct Model{
	Vertex[][] vertices;
	Face[] faces;
	Hitbox[] hitboxes;
}

Model parseMRMM(ubyte[] data){
	enforce(data.length>=192);
	auto fileSize=*cast(uint*)&data[0];
	enforce(fileSize==data.length);
	auto numVertices=*cast(uint*)&data[4];
	auto numFaces=*cast(uint*)&data[12];
	auto numFrames=*cast(uint*)&data[24];
	auto numHitboxes=*cast(uint*)&data[68];
	auto hitboxes=cast(Hitbox[])data[72..72+Hitbox.sizeof*numHitboxes];
	auto vertexOff=*cast(uint*)&data[184];
	auto faceOff=*cast(uint*)&data[188];
	static assert(Vertex.sizeof==40);
	auto vertices=new Vertex[][](numFrames);
	auto verticesSize=Vertex.sizeof*numVertices;
	enforce(data.length>=vertexOff+numFrames*verticesSize);
	foreach(i;0..numFrames)
		vertices[i]=cast(Vertex[])data[vertexOff+i*verticesSize..vertexOff+(i+1)*verticesSize];
	enforce(data.length>=faceOff+Face.sizeof*numFaces);
	auto faces = cast(Face[])data[faceOff..faceOff+Face.sizeof*numFaces];
	foreach(ref face;faces){
		foreach(i;face.vertices){
			enforce(0<=i&&i<numVertices);
		}
	}
	return Model(vertices, faces, hitboxes);
}

Tuple!(B.Mesh[][], B.Texture[], Vector3f[2][]) loadMRMM(B)(string filename, float scaling){
	enforce(filename.endsWith(".MRMM"));
	auto dir = dirName(filename);
	auto model = parseMRMM(readFile(filename));
	return tuple(convertModel!B(dir, model, scaling).expand,model.hitboxes.map!(b=>[Vector3f(b.coords[0])*scaling,Vector3f(b.coords[1])*scaling].staticArray).array);
}
