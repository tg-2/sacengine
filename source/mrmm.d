import dagon;
import txtr;
import dlib.filesystem.filesystem;
import dlib.filesystem.stdfs;
import std.algorithm, std.exception;
import std.typecons: Tuple, tuple;
import std.stdio, std.path;
import std.math;

struct Vertex{
	Vector3f pos;
	Vector2f uv;
	uint unknown1=0xffffffff;
	uint unknown2=0;
	Vector3f normal;
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
	Vector3f normal;
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
	foreach(face;faces){
		foreach(i;face.vertices){
			enforce(0<=i&&i<vertices.length);
		}
	}
	return Model(vertices, faces);
}

Tuple!(DynamicArray!Mesh, DynamicArray!Texture) loadMRMM(Owner o, string filename){
	enforce(filename.endsWith(".MRMM"));
	auto base = filename[0..$-".TXTR".length];
	ubyte[] data;
	foreach(ubyte[] chunk;chunks(File(filename,"rb"),4096)) data~=chunk;
	auto model = parseMRMM(data);
	int[string] names;
	int cur=0;
	foreach(f;model.faces){
		if(f.textureName!in names) names[f.textureName]=cur++;
	}
	auto dir=dirName(filename);
	DynamicArray!Mesh meshes;
	DynamicArray!Texture textures;
	
	foreach(i;0..names.length){
		 // TODO: improve dlib
		meshes.insertBack(New!Mesh(null));
		textures.insertBack(Texture.init);
	}
	auto namesRev=new string[](names.length);
	foreach(k,v;names){
		namesRev[v]=k;
		auto name=buildPath(dir, k~".TXTR");
		auto t=New!Texture(null);
		t.image=loadTXTR(name);
		t.createFromImage(t.image);
		textures[v]=t;
	}
	foreach(mesh;meshes){
		auto nvertices=model.vertices.length;
		mesh.vertices=New!(Vector3f[])(nvertices);
		foreach(i,ref vertex;model.vertices){
			mesh.vertices[i] = vertex.pos;
		}
		mesh.texcoords=New!(Vector2f[])(nvertices);
		foreach(i,ref vertex;model.vertices){
			mesh.texcoords[i] = vertex.uv;
		}
		mesh.normals=New!(Vector3f[])(nvertices);
		foreach(i,ref vertex;model.vertices){
			mesh.normals[i] = vertex.normal;
		}
	}
	int[] sizes=new int[](names.length);
	foreach(ref face;model.faces){
		++sizes[names[face.textureName]];
	}
	foreach(k,mesh;meshes) meshes[k].indices = New!(uint[3][])(sizes[k]);
	auto curs=new int[](meshes.length);
	foreach(ref face;model.faces){
		auto k=names[face.textureName];
		meshes[k].indices[curs[k]++]=face.vertices;
	}
	foreach(mesh;meshes){
		mesh.dataReady=true;
		mesh.prepareVAO();
	}
	assert(curs==sizes);
	return tuple(move(meshes), move(textures));
}

class MRMMObject: Owner{
	DynamicArray!Mesh meshes;
	DynamicArray!Texture textures;
	
	this(Owner o, string filename){
		super(o);
		auto mt=loadMRMM(o, filename);
		meshes=move(mt[0]);
		textures=move(mt[1]);
	}

	void createEntities(Scene s){
		foreach(i;0..meshes.length){
			auto obj=s.createEntity3D();
			obj.drawable = meshes[i];
			obj.position = Vector3f(0, 0, 0);
			obj.rotation = rotationQuaternion(Axis.x,-cast(float)PI/2);
			auto mat=s.createMaterial();
			mat.diffuse=textures[i];
			mat.specular=Color4f(0,0,0,1);
			obj.material=mat;
		}
	}
}
