import dagon;
import std.stdio;
import std.random;
import std.conv, std.algorithm, std.string, std.exception, std.path;
import std.array;

struct BoneData{
	float[3] pos;
	ushort parent;
	ushort unused0;
	float[3][8] bbox;
	uint[7] unused1;
}
static assert(BoneData.sizeof==140);

struct TriangleStripsHeader{
	ubyte num;
	ubyte[3] unknown0;
	uint unknown1;
	float[3] unknown2;
	uint[4] unknown3;
}
struct TriangleStripsEntryHeader{
	ubyte num;
	ubyte unknown;
	ushort texture;
	uint offset;
}

struct TriangleStripsEntry{
	TriangleStripsEntryHeader* header;
	TriangleStrip[] strips;
	string toString(){
		return text("TriangleStripsEntry(",*header,", ",strips,")");
	}
}

struct TriangleStripData{
	ushort[3] indices;
	ushort unknown0;
	ushort unknown1;
}
static assert(TriangleStripData.sizeof==10);

struct TriangleStrip{
	TriangleStripData* data;
	alias data this;
	string toString(){
		return text("TriangleStrip(",*data,")");
	}
}

struct TriangleStrips{
	TriangleStripsHeader* header;
	uint[] offsets;
	TriangleStripsEntry[] entries;

	string toString(){
		return text("TriangleStrips(",*header,", ",entries,")");
	}
}

struct Vertex{
	short[3] pos;
	ushort bone;
	ushort[2] unknown1;
	uint unknown2;
}

struct Model{
	BoneData[] bones;
	TriangleStrips[] triangleStrips;
	Vertex[] vertices;
}

Model parseSXMD(ubyte[] data){
	uint numBones=*cast(uint*)data[28..32].ptr-1;
	uint boneOffset=*cast(uint*)data[32..36].ptr+140;
	uint vertexOffset=*cast(uint*)data[36..40].ptr;
	uint triangleStripsOffset=*cast(uint*)data[40..44].ptr;
	uint numTriangleStrips=data[0];
	auto bones=cast(BoneData[])data[boneOffset..boneOffset+numBones*BoneData.sizeof];
	TriangleStrips[] triangleStrips;
	uint numVertices=0;
	for(int k=0,offset=triangleStripsOffset;k<numTriangleStrips;k++){
		auto header=cast(TriangleStripsHeader*)&data[offset];
		offset+=TriangleStripsHeader.sizeof;
		assert(offset<data.length);
		TriangleStripsEntry[] edata;
		auto next = to!uint(offset+uint.sizeof*header.num);
		writeln(*header);
		auto offsets=cast(uint[])data[offset..next];
		offset=next;
		foreach(off;offsets){
			auto eheader=cast(TriangleStripsEntryHeader*)&data[off];
			auto tdata=cast(TriangleStripData[])data[eheader.offset..eheader.offset+eheader.num*TriangleStripData.sizeof];
			TriangleStrip[] tdata2;
			foreach(ref entry;tdata){
				foreach(index;entry.indices){
					if(index!=ushort.max&&index>=numVertices) numVertices=index+1;
				}
				tdata2~=TriangleStrip(&entry);
			}
			edata~=TriangleStripsEntry(eheader,tdata2);
		}
		triangleStrips~=TriangleStrips(header,offsets,edata);
	}
	auto vertices=cast(Vertex[])data[vertexOffset..vertexOffset+Vertex.sizeof*numVertices];
	auto unknownDataOffset=vertexOffset+Vertex.sizeof*numVertices;
	auto unknownData=data[unknownDataOffset..$];
	return Model(bones,triangleStrips,vertices);
}

Model loadSXMD(string filename){
	enforce(filename.endsWith(".SXMD"));
	auto dir=dirName(filename);
	ubyte[] data;
	foreach(ubyte[] chunk;chunks(File(filename,"rb"),4096)) data~=chunk;
	auto model = parseSXMD(data);
	return model;
}

class SXMDObject: Owner{
	Model m;
	this(Owner o, string filename){
		super(o);
		enforce(filename.endsWith(".SXMD"));
		this.m=loadSXMD(filename);
	}
	void createEntities(Scene s){
		enum factor=0.005f;
		auto ap = new Vector3f[](m.bones.length);
		auto vertices = New!(Vector3f[])(m.vertices.length);
		foreach(i,bone;m.bones){
			if(bone.parent==0) ap[i]=Vector3f(0,0,0);
			else ap[i]=ap[bone.parent-1];
			auto cpos=Vector3f(bone.pos);
			swap(cpos.y,cpos.z);
			/+if(6<=i+1&&i+1<=9){
				cpos.y=-100-cpos.y;
				//cpos.z=-cpos.z;
			}+/
			ap[i]+=cpos;
			/+auto e=s.createEntity3D();
			e.drawable=New!ShapePlane(2,2,1,null);
			e.position=ap[i];+/
		}
		Color4f[int] boneColor;
		//auto plane=New!ShapePlane(0.1f,0.1f,1,null);
		foreach(i,vertex;m.vertices){
			auto cpos=Vector3f(vertex.pos);
			swap(cpos.y,cpos.z);
			auto pos=(ap[vertex.bone-1]+cpos)*factor;
			vertices[i]=pos;
			//if(6<=vertex.bone&&vertex.bone<=9) continue; // ignore left leg
			//if(vertex.bone==11) continue;// ignore ??
			//if(12<=vertex.bone) continue; // ignore ears
			//if(vertex.bone!=10) continue; // main body
			//if(vertex.bone!=11) continue; // main body
			//if(vertex.bone!=6) continue; // right leg, upside down
			//if(vertex.bone!=2&&vertex.bone!=6) continue; // left leg
			/+if(vertex.bone !in boneColor) boneColor[vertex.bone]=Color4f(uniform(0.0,1.0),uniform(0.0,1.0),uniform(0.0,1.0));
			auto e=s.createEntity3D();
			e.drawable=plane;
			/+if(6<=vertex.bone&&vertex.bone<=9){
				cpos.y=-cpos.y;
				cpos.z=-cpos.z;
			}+/
			e.position=pos;
			auto mat=s.createMaterial();
			mat.diffuse=boneColor[vertex.bone];
			e.material=mat;+/
		}
		auto faces=(uint[3][]).init;
		/+foreach(i,tri;m.triangleStrips[0..1]){
			foreach(j,entry;tri.entries[0..$-1]){
				auto strips=entry.strips;
				auto next=tri.entries[j+1].strips;
				if(next.length!=strips.length){
					writeln(strips.length," ",next.length);
					int countIndices(TriangleStrip[] strips){
						int r=0;
						foreach(strip;strips){
							foreach(i;0..3) r+=strip.indices[i]!=ushort.max;
						}
						return r;
					}
					writeln(countIndices(strips)," ",countIndices(next));
					writeln();
					continue;
				}
				uint numEntries=to!uint(strips.length);
				foreach(k;0..numEntries){
					//faces~=[i,i+32,i+33];
					//faces~=[i+1,i,i+32];
					faces~=[strips[k].indices[0],next[k].indices[0],strips[(k+1)%$].indices[0]];
					faces~=[next[(k+1)%$].indices[0],strips[(k+1)%$].indices[0],next[k].indices[0]];
					/+uint[3] indices=[strips[k].indices[0],strips[k+1].indices[0],strips[k+2].indices[0]];
					faces~=indices;
					swap(indices[0],indices[1]);
					faces~=indices;+/
				}
			}
		}+/
		foreach(i,tri;m.triangleStrips){
			foreach(j,entry;tri.entries){
				auto strips=entry.strips;
				uint numEntries=to!uint(strips.length);
				foreach(k;0..numEntries){
					faces~=[strips[k].indices[0],strips[(k+1)%$].indices[0],strips[(k+2)%$].indices[0]];
					faces~=[strips[(k+1)%$].indices[0],strips[k].indices[0],strips[(k+2)%$].indices[0]];
				}
			}
		}
		/+uint[] raw_indices=File("/home/tgehr/games/sac/Sacrifice/dump.txt")
			.byLineCopy.map!strip.filter!(x=>!x.empty).map!(to!uint).array;
		faces=cast(uint[3][])raw_indices;+/
		auto entires=m.triangleStrips[0].entries;
		/+foreach(entry;zip(m.strips[0],m.strips[1])){
			
		}+/
		auto mesh = New!Mesh(null);
		mesh.vertices=vertices;
		mesh.indices=New!(uint[3][])(faces.length);
		mesh.indices[]=faces[];
		mesh.dataReady=true;
		if(s){
			mesh.prepareVAO();
			auto e=s.createEntity3D();
			e.drawable=mesh;
			auto mat=s.createMaterial();
			mat.diffuse=Color4f(0.2,0.2,0.2);
			e.material=mat;
		}
	}
}
