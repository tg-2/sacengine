// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt
import std.stdio, std.string, std.container.array, std.exception, std.range, std.algorithm, std.conv;
import saxs, sxsk;
import dlib.math,util;

B.Mesh[] loadObj(B)(string filename){
	auto file=File(filename,"r");
	B.Mesh[] meshes;
	static struct Parts{
		size_t positionIndex;
		size_t textureIndex;
		size_t faceIndex;
	}
	Parts[] parts;
	Array!Vector3f positions;
	Array!Vector2f texcoords;
	static struct Vertex{
		Vector3f position;
		Vector2f texcoord;
	}
	Array!(int[3][3]) faces;
	while(!file.eof()){
		auto line=file.readln.strip().split();
		if(!line.length) continue;
		switch(line[0]){
			case "o":
				parts~=Parts(positions.length,texcoords.length,faces.length);
				break;
			case "v":
				enforce(line.length==4);
				Vector3f position;
				line[1..4].map!(to!float).copy(position[]);
				swap(position.y,position.z);
				positions~=position;
				break;
			case "vt":
				enforce(line.length==3);
				Vector2f texcoord;
				line[1..3].map!(to!float).copy(texcoord[]);
				texcoord.y=1.0f-texcoord.y;
				texcoords~=texcoord;
				break;
			case "f":
				int[3] parseVertex(string vertex){
					int[3] r=-1;
					auto s=vertex.split("/");
					enforce(s.length<=3);
					s.map!(to!int).map!(i=>i-1).copy(r[0..s.length]);
					return r;
				}
				void addFace(string[3] vertexStrings){
					int[3][3] vertices;
					vertexStrings[].map!parseVertex.copy(vertices[]);
					faces~=vertices;
				}
				if(line.length==4) addFace(line[1..4]);
				else if(line.length==5){
					addFace(line[1..4]);
					addFace([line[3],line[4],line[1]]);
				}else enforce("unsupported face shape");
				break;
			default:
				break;
		}
	}
	parts~=Parts(positions.length,texcoords.length,faces.length);
	foreach(i,ref part;parts[0..$-1]){
		Array!Vertex vertices;
		uint[int[3]] vertexMap;
		uint getVertex(int[3] vertex){
			if(vertex in vertexMap) return vertexMap[vertex];
			auto r=Vertex(positions[vertex[0]],texcoords[vertex[1]]);
			vertices~=r;
			return vertexMap[vertex]=cast(uint)vertices.length-1;
		}
		Array!(uint[3]) tfaces;
		foreach(face;faces.data[parts[i].faceIndex..parts[i+1].faceIndex]){
			auto tface=[getVertex(face[0]),getVertex(face[1]),getVertex(face[2])].staticArray;
			enforce(tface[].all!(x=>x>=0));
			tfaces~=tface;
		}
		auto mesh=B.makeMesh(vertices.length,tfaces.length);
		copy(vertices[].map!((ref v)=>v.position),mesh.vertices[]);
		copy(vertices[].map!((ref v)=>v.texcoord),mesh.texcoords[]);
		copy(tfaces.data[],mesh.indices[]);
		mesh.generateNormals();
		B.finalizeMesh(mesh);
		meshes~=mesh;
	}
	return meshes;
}
