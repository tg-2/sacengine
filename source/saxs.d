import dagon;
import util;
import sxmd,sxsk,sxtx;

import std.stdio, std.path, std.string, std.exception, std.algorithm, std.range, std.conv;

struct Bone{
	Vector3f position;
	size_t parent;
}

struct Position{
	size_t bone;
	Vector3f offset;
	float weight;
}

struct Vertex{
	private int[3] indices_;
	Vector2f uv;
	this(R)(R indices, Vector2f uv){
		this.indices=indices;
		this.uv=uv;
	}
	@property int[] indices(){
		foreach(i;0..3){
			if(indices_[i]==-1)
				return indices_[0..i];
		}
		return indices_[];
	}
	@property void indices(R)(R range){
		auto len=range.walkLength;
		copy(range,indices[0..len]);
		indices[len..$]=-1;
	}
}

struct BodyPart{
	Vertex[] vertices;
	uint[3][] faces;
	Texture texture;
}

struct Saxs{
	Bone[] bones;
	Position[] positions;
	BodyPart[] bodyParts;
}

Saxs loadSaxs(string filename){
	enforce(filename.endsWith(".SXMD"));
	auto dir=dirName(filename);
	ubyte[] data;
	foreach(ubyte[] chunk;chunks(File(filename,"rb"),4096)) data~=chunk;
	auto model = parseSXMD(data);
	auto bones=chain(only(Bone(Vector3f(0,0,0),0)),model.bones.map!(bone=>Bone(Vector3f(fromSXMD(bone.pos)),bone.parent))).array;
	auto convertPosition(ref sxmd.Position position){
		return Position(position.bone,fromSXMD(Vector3f(position.pos)),position.weight/64.0f);
	}
	auto positions=model.positions.map!convertPosition().array;
	BodyPart[] bodyParts;
	foreach(i,bodyPart;model.bodyParts){
		Vertex[] vertices;
		auto vrt=new uint[][](bodyPart.rings.length);
		double textureMax=bodyPart.rings[$-1].texture;
		foreach(j,ring;bodyPart.rings){
			vrt[j]=new uint[](ring.entries.length+1);
			foreach(k,entry;ring.entries){
				vrt[j][k]=to!uint(vertices.length);
				auto indices=entry.indices[].map!(to!int).filter!(x=>x!=ushort.max);
				auto uv=Vector2f(entry.alignment/256.0f,ring.texture/textureMax);
				if(bodyPart.explicitFaces.length) uv[1]=entry.textureV/256.0f;
				vertices~=Vertex(indices,uv);
			}
			vrt[j][ring.entries.length]=to!uint(vertices.length);
			vertices~=vertices[vrt[j][0]];
			vertices[$-1].uv[0]=1.0f;
		}
		uint[3][] faces;
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
		if(bodyPart.explicitFaces.length){
			enforce(vrt.length==1);
			foreach(eface;bodyPart.explicitFaces)
				faces~=[vrt[0][eface[0]],vrt[0][eface[1]],vrt[0][eface[2]]];
		}
		auto texture=New!Texture(null); // TODO: how not to leak this memory without crashing at shutdown?
		texture.image = loadSXTX(buildPath(dir,format(".%03d.SXTX",i+1)));
		texture.createFromImage(texture.image);
		bodyParts~=BodyPart(vertices,faces,texture);
	}
	return Saxs(bones,positions,bodyParts);
}


Mesh[] createMeshes(Saxs saxs){
	enum factor=0.005f;
	auto ap = new Vector3f[](saxs.bones.length);
	ap[0]=Vector3f(0,0,0);
	foreach(i,ref bone;saxs.bones[1..$]){
		ap[i+1]=bone.position;
		ap[i+1]+=ap[bone.parent];
	}
	auto meshes=new Mesh[](saxs.bodyParts.length);
	foreach(i,ref bodyPart;saxs.bodyParts){
		meshes[i]=new Mesh(null);
		meshes[i].vertices=New!(Vector3f[])(bodyPart.vertices.length);
		meshes[i].texcoords=New!(Vector2f[])(bodyPart.vertices.length);
		foreach(j,ref vertex;bodyPart.vertices){
			auto position=Vector3f(0,0,0);
			foreach(v;vertex.indices.map!(k=>(ap[saxs.positions[k].bone]+saxs.positions[k].offset)*saxs.positions[k].weight))
				position+=v;
			meshes[i].vertices[j]=position*factor;
			meshes[i].texcoords[j]=vertex.uv;
		}
		meshes[i].indices=New!(uint[3][])(bodyPart.faces.length);
		meshes[i].indices[]=bodyPart.faces[];
		meshes[i].normals=New!(Vector3f[])(bodyPart.vertices.length);
		meshes[i].generateNormals();
		meshes[i].dataReady=true;
		meshes[i].prepareVAO();
	}
	return meshes;
}

struct SaxsInstance{
	Saxs saxs;
	Mesh[] meshes;
}

void createMeshes(ref SaxsInstance saxsi){
	saxsi.meshes=createMeshes(saxsi.saxs);
}

void createEntities(ref SaxsInstance saxsi, Scene s){
	foreach(i,ref bodyPart;saxsi.saxs.bodyParts){
		auto obj=s.createEntity3D();
		obj.drawable=saxsi.meshes[i];
		auto mat=s.createMaterial();
		if(bodyPart.texture !is null)
			mat.diffuse=bodyPart.texture;
		obj.material=mat;
	}
}
	
void setPose(ref SaxsInstance saxs, Quaternionf[] rotations){
	
}
