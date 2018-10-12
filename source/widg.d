import dagon;
import util;
import sacobject;
import txtr;
import std.algorithm, std.range, std.exception;
import std.stdio, std.path, std.conv;
import std.typecons: Tuple, tuple;

struct Vertex{
	float[3] pos;
	float[2] uv;
}
static assert(Vertex.sizeof==20);
struct Face{
	ubyte[3] indices;
	ubyte unknown;
}
static assert(Face.sizeof==4);


struct Model{
	char[] retroTextureName;
	string textureName(){
		return retroTextureName.retro.to!string;
	}
	Vertex[] vertices;
	Face[] faces;
}

Model parseWIDG(ubyte[] data){
	auto numVertices=*cast(uint*)data[0..4].ptr;
	auto numFaces=*cast(short*)data[4..6].ptr;
	auto retroTextureName=cast(char[])data[8..12];
	auto vertices=cast(Vertex[])data[12..12+numVertices*Vertex.sizeof];
	auto faces=cast(Face[])data[8+numVertices*Vertex.sizeof+4..$];
	enforce(faces.length==numFaces);
	return Model(retroTextureName,vertices,faces);
}

Tuple!(Mesh, Texture) loadWIDG(string filename){
	enforce(filename.endsWith(".WIDG"));
	auto data=readFile(filename);
	Model model=parseWIDG(data);	
	auto dir=dirName(filename);
	auto mesh=New!Mesh(null);
	auto nvertices=to!int(model.vertices.length);
	mesh.vertices=New!(Vector3f[])(2*nvertices);
	foreach(i,ref vertex;model.vertices){
		mesh.vertices[i] = fromSac(Vector3f(vertex.pos));
		mesh.vertices[i+nvertices] = fromSac(Vector3f(vertex.pos));
	}
	mesh.texcoords=New!(Vector2f[])(2*nvertices);
	foreach(i,ref vertex;model.vertices){
		mesh.texcoords[i] = Vector2f(vertex.uv[0],-vertex.uv[1]);
		mesh.texcoords[i+nvertices] = Vector2f(vertex.uv[0],-vertex.uv[1]);
	}
	mesh.normals=New!(Vector3f[])(2*nvertices);
	mesh.indices=New!(uint[3][])(2*model.faces.length);
	foreach(i;0..model.faces.length){
		auto indices=model.faces[i].indices;
		mesh.indices[i]=[indices[0],indices[1],indices[2]];
		mesh.indices[i+model.faces.length]=[nvertices+indices[0],nvertices+indices[2],nvertices+indices[1]];
	}
	mesh.generateNormals();
	mesh.dataReady=true;
	mesh.prepareVAO();
	auto txtr=loadTXTR(buildPath(dir,chain(retro(model.retroTextureName),".TXTR").to!string),true);
	auto texture=New!Texture(null);
	texture.image=txtr;
	texture.createFromImage(texture.image);
	return tuple(mesh,texture);
}
