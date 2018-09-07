import dagon;
import util;
import std.stdio;
import std.random;
import std.conv, std.algorithm, std.string, std.exception, std.path;
import std.array;
import std.typecons: tuple, Tuple;
import sxtx;

struct BoneData{
	float[3] pos;
	ushort parent; // TODO: figure out how to use this (related to animation)
	ushort unused0; // setting all those fields to 0 does not affect the ingame rendering
	float[3][8] bbox; // TODO: figure out what this does exactly (it affects the bone shadow and the bounding box, but unclear how)
	uint[7] unused1; // setting all those fields to 0 does not affect the ingame rendering
}
static assert(BoneData.sizeof==140);

struct BodyPartHeader{
	ubyte numRings;
	ubyte unknown0;
	ushort numExplicitFaces;
	ubyte[16] unknown1;
	uint flags;
	uint explicitFaceOffset;
	ubyte[8] unknown2;
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
	ubyte unknown0;
	ushort unknown1;
}
static assert(RingEntry.sizeof==10);

struct BodyPart{
	BodyPartHeader* header;
	alias header this;
	uint[] offsets;
	Ring[] rings;
	ushort[3][] explicitFaces;
	string toString(){
		return text("BodyPart(",*header,", ",rings,")");
	}
}

struct Vertex{
	short[3] pos;
	ushort bone;
	ubyte unknown0;
	ubyte weight;
	ubyte[6] unknown1;
}
static assert(Vertex.sizeof==16);

struct Model{
	BoneData[] bones;
	BodyPart[] bodyParts;
	Vertex[] vertices;
}

Model parseSXMD(ubyte[] data){
	uint numBodyParts=data[0];
	float offsetY=*cast(float*)data[8..12].ptr;
	uint numBones=*cast(uint*)data[28..32].ptr-1;
	uint boneOffset=*cast(uint*)data[32..36].ptr+140;
	uint vertexOffset=*cast(uint*)data[36..40].ptr;
	auto bones=cast(BoneData[])data[boneOffset..boneOffset+numBones*BoneData.sizeof];
	BodyPart[] bodyParts;
	uint numVertices=0;
	for(int k=0;k<numBodyParts;k++){
		uint offset=*cast(uint*)data[40+4*k..44+4*k].ptr;
		auto header=cast(BodyPartHeader*)&data[offset];
		assert(offset<data.length);
		Ring[] edata;
		auto offsets=cast(uint[])data[offset+BodyPartHeader.sizeof..offset+BodyPartHeader.sizeof+uint.sizeof*header.numRings];
		foreach(i,off;offsets){
			auto ringHeader=cast(RingHeader*)&data[off];
			auto entries=cast(RingEntry[])data[ringHeader.offset..ringHeader.offset+ringHeader.numEntries*RingEntry.sizeof];
			foreach(ref entry;entries){
				foreach(index;entry.indices){
					if(index!=ushort.max&&index>=numVertices) numVertices=index+1;
				}
			}
			version(change) eoffset=0;
			edata~=Ring(ringHeader,entries);
		}
		ushort[3][] explicitFaces=[];
		if(header.numExplicitFaces>0)
			explicitFaces=cast(ushort[3][])data[header.explicitFaceOffset..header.explicitFaceOffset+(ushort[3]).sizeof*header.numExplicitFaces];
		bodyParts~=BodyPart(header,offsets,edata,explicitFaces);
	}
	auto vertices=cast(Vertex[])data[vertexOffset..vertexOffset+Vertex.sizeof*numVertices];
	auto remainingDataOffset=vertexOffset+Vertex.sizeof*numVertices;
	return Model(bones,bodyParts,vertices);
}

Tuple!(DynamicArray!Mesh, DynamicArray!Texture) loadSXMD(string filename){
	enforce(filename.endsWith(".SXMD"));
	auto dir=dirName(filename);
	ubyte[] data;
	foreach(ubyte[] chunk;chunks(File(filename,"rb"),4096)) data~=chunk;
	auto model = parseSXMD(data);
	return convertSXMDModel(dir,model);
}

auto convertSXMDModel(string dir, Model m){
	enum factor=0.005f;
	DynamicArray!Mesh meshes;
	DynamicArray!Texture textures;
	foreach(i;0..m.bodyParts.length){
		// TODO: improve dlib
		meshes.insertBack(New!Mesh(null));
		auto texture = New!Texture(null);
		texture.image = loadSXTX(buildPath(dir,format(".%03d.SXTX",i+1)));
		texture.createFromImage(texture.image);
		textures.insertBack(texture);
	}
	auto ap = new Vector3f[](m.bones.length+1);
	ap[0]=Vector3f(0,0,0);
	foreach(i,bone;m.bones){
		ap[i+1]=ap[bone.parent];
		auto cpos=Vector3f(fromSXMD(bone.pos));
		ap[i+1]+=cpos;
	}
	auto vpos = new Vector3f[](m.vertices.length);
	foreach(i,vertex;m.vertices){
		auto cpos=fromSXMD(Vector3f(vertex.pos));
		auto pos=(ap[vertex.bone]+cpos)*factor;
		vpos[i]=pos;
	}
	foreach(i,bodyPart;m.bodyParts){
		Vector3f[] vertices;
		Vector2f[] uv;
		auto vrt=new uint[][](bodyPart.rings.length);
		double textureMax=bodyPart.rings[$-1].texture;
		foreach(j,ring;bodyPart.rings){
			vrt[j]=new uint[](ring.entries.length+1);
			foreach(k,entry;ring.entries){
				vrt[j][k]=to!uint(vertices.length);
				auto components=entry.indices[].filter!(x=>x!=ushort.max);
				import std.algorithm;
				auto tot=std.algorithm.sum(components.map!(l=>m.vertices[l].weight));
				auto vertex=Vector3f(0,0,0);
				foreach(v;components.map!(l=>vpos[l]*m.vertices[l].weight/tot)) vertex+=v;
				vertices~=vertex;
				uv~=Vector2f(entry.alignment/256.0f,ring.texture/textureMax);
			}
			vrt[j][ring.entries.length]=to!uint(vertices.length);
			vertices~=vertices[vrt[j][0]];
			uv~=uv[vrt[j][0]];
			uv[$-1][0]=1.0f;
		}
		auto faces=(uint[3][]).init;
		if(bodyPart.flags & BodyPartFlags.CLOSE_TOP){
			foreach(j;1..vrt[0].length-1){
				faces~=[vrt[0][0],vrt[0][j],vrt[0][j+1]];
			}
		}
		auto maxScaleY=bodyPart.rings[$-1].texture;
		foreach(j,ring;bodyPart.rings[0..$-1]){
			auto entries=ring.entries;
			auto next=bodyPart.rings[j+1].entries;
			for(int a=0,b=0;a<entries.length||b<next.length;){
				if(b==next.length||a<entries.length&&entries[a].alignment<=next[b].alignment){
					faces~=[vrt[j][a],vrt[j+1][b],vrt[j][a+1]];
					a++;
				}else{
					faces~=[vrt[j+1][b],vrt[j+1][b+1],vrt[j][a]];
					b++;
				}
			}
		}
		if(bodyPart.flags & BodyPartFlags.CLOSE_BOT){
			foreach(j;1..vrt[$-1].length-1){
				faces~=[vrt[$-1][0],vrt[$-1][j+1],vrt[$-1][j]];
			}
		}
		meshes[i].vertices=New!(Vector3f[])(vertices.length);
		meshes[i].vertices[]=vertices[];
		meshes[i].texcoords=New!(Vector2f[])(vertices.length);
		/+foreach(j;0..vertices.length){
			meshes[i].texcoords[j]=Vector2f(uniform(0.0f,1.0f),uniform(0.0f,1.0f));
		}+/
		meshes[i].texcoords=uv[];
		meshes[i].indices=New!(uint[3][])(faces.length);
		meshes[i].indices[]=faces[];
		meshes[i].normals=New!(Vector3f[])(vertices.length);
		meshes[i].generateNormals();
		meshes[i].dataReady=true;
		meshes[i].prepareVAO();
	}
	return tuple(move(meshes),move(textures));
}
