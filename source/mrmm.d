import dagon;
import sacobject;
import std.algorithm, std.exception;
import std.stdio, std.path;
import std.typecons: Tuple, tuple;

struct Vertex{
	float[3] pos;
	float[2] uv;
	uint unknown1=0xffffffff;
	uint unknown2=0;
	float[3] normal;
}
static assert(Vertex.sizeof==40);

struct Face{
	uint[3] vertices;
	uint unknown1=0x00010001;
	char[4] retroName;
	string textureName(){
		auto tmp=retroName;
		reverse(tmp[]);
		return cast(string)tmp[].dup;
	}
	float[3] normal;
	uint unknown2;
}
static assert(Face.sizeof==36);

struct Model{
	Vertex[] vertices;
	Face[] faces;
}

Model parseMRMM(ubyte[] data){
	auto fileSize=*cast(uint*)&data[0];
	enforce(fileSize==data.length);
	auto numVertices=*cast(uint*)&data[4];
	auto numFaces=*cast(uint*)&data[12];
	auto vertexOff=*cast(uint*)&data[184];
	auto faceOff=*cast(uint*)&data[188];
	static assert(Vertex.sizeof==40);
	auto vertices = cast(Vertex[])data[vertexOff..vertexOff+Vertex.sizeof*numVertices];
	auto faces = cast(Face[])data[faceOff..faceOff+Face.sizeof*numFaces];
	foreach(ref face;faces){
		foreach(i;face.vertices){
			enforce(0<=i&&i<vertices.length);
		}
	}
	return Model(vertices, faces);
}

Tuple!(DynamicArray!Mesh, DynamicArray!Texture) loadMRMM(string filename){
	enforce(filename.endsWith(".MRMM"));
	auto dir = dirName(filename);
	ubyte[] data;
	foreach(ubyte[] chunk;chunks(File(filename,"rb"),4096)) data~=chunk;
	auto model = parseMRMM(data);
	return convertModel(dir, model);
}
