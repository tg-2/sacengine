import dlib.math;
import util;
import sxmd,sxsk,sxtx;

import std.stdio, std.path, std.string, std.exception, std.algorithm, std.range, std.conv, std.math;

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

struct BodyPart(B){
	Vertex[] vertices;
	uint[3][] faces;
	B.Texture texture;
}

struct Saxs(B){
	float zfactor;
	Bone[] bones;
	Position[] positions;
	BodyPart!B[] bodyParts;
}

Saxs!B loadSaxs(B)(string filename, float scaling=1.0f, int alphaFlags=0){
	enforce(filename.endsWith(".SXMD"));
	auto dir=dirName(filename);
	ubyte[] data;
	foreach(ubyte[] chunk;chunks(File(filename,"rb"),4096)) data~=chunk;
	auto model = parseSXMD(data);
	auto bones=chain(only(Bone(Vector3f(0,0,0),0)),model.bones.map!(bone=>Bone(Vector3f(fromSXMD(bone.pos))*scaling,bone.parent))).array;
	enforce(iota(1,bones.length).all!(i=>bones[i].parent<i));
	auto convertPosition(ref sxmd.Position position){
		return Position(position.bone,fromSXMD(Vector3f(position.pos))*scaling,position.weight/64.0f);
	}
	auto positions=model.positions.map!convertPosition().array;
	BodyPart!B[] bodyParts;
	auto vrt=new uint[][][](model.bodyParts.length);
	foreach(i,bodyPart;model.bodyParts){
		Vertex[] vertices;
		vrt[i]=new uint[][](bodyPart.rings.length);
		double textureMax=bodyPart.rings[$-1].texture;
		foreach(j,ring;bodyPart.rings){
			vrt[i][j]=new uint[](ring.entries.length+1);
			foreach(k,entry;ring.entries){
				vrt[i][j][k]=to!uint(vertices.length);
				auto indices=entry.indices[].map!(to!int).filter!(x=>x!=ushort.max);
				auto uv=Vector2f(entry.alignment/256.0f,ring.texture/textureMax);
				if(bodyPart.explicitFaces.length) uv[1]=entry.textureV/256.0f;
				vertices~=Vertex(indices,uv);
			}
			vrt[i][j][ring.entries.length]=to!uint(vertices.length);
			vertices~=vertices[vrt[i][j][0]];
			vertices[$-1].uv[0]=1.0f;
		}
		uint[3][] faces;
		if(bodyPart.flags & BodyPartFlags.CLOSE_TOP){
			foreach(j;1..vrt[i][0].length-1){
				faces~=[vrt[i][0][0],vrt[i][0][j],vrt[i][0][j+1]];
			}
		}
		foreach(j,ring;bodyPart.rings[0..$-1]){
			auto entries=ring.entries;
			auto next=bodyPart.rings[j+1].entries;
			for(int a=0,b=0;a<entries.length||b<next.length;){
				if(b==next.length||a<entries.length&&entries[a].alignment<=next[b].alignment){
					faces~=[vrt[i][j][a],vrt[i][j+1][b],vrt[i][j][a+1]];
					a++;
				}else{
					faces~=[vrt[i][j+1][b],vrt[i][j+1][b+1],vrt[i][j][a]];
					b++;
				}
			}
		}
		if(bodyPart.flags & BodyPartFlags.CLOSE_BOT){
			foreach(j;1..vrt[i][$-1].length-1){
				faces~=[vrt[i][$-1][0],vrt[i][$-1][j+1],vrt[i][$-1][j]];
			}
		}
		if(bodyPart.explicitFaces.length){
			enforce(vrt[i].length==1);
			foreach(eface;bodyPart.explicitFaces)
				faces~=[vrt[i][0][eface[0]],vrt[i][0][eface[1]],vrt[i][0][eface[2]]];
		}
		auto texture=B.makeTexture(loadSXTX(buildPath(dir,format(".%03d.SXTX",i+1)),alphaFlags>>i&1),false);
		//writeln(i,": ",bodyPart.flags," ",bodyPart.unknown0," ",bodyPart.unknown1);
		//if(bodyPart.flags==0&&bodyPart.unknown0[].all!(x=>x==0)&&bodyPart.unknown1[].all!(x=>x==0)) faces=[];
		bodyParts~=BodyPart!B(vertices,faces,texture);
		if(bodyPart.strips.length){
			// TODO: enforce all in bounds
			// TODO: this is not the right way to interpret this data:
			for(int j=0;j<bodyPart.strips.length;j++){
				if(bodyPart.strips[j].bodyPart==i&&j+1<bodyPart.strips.length){
					auto strip1=bodyPart.strips[j];
					auto idx1=vrt[strip1.bodyPart][strip1.ring][strip1.vertex];
					auto strip2=bodyPart.strips[j+1];
					auto idx2=vrt[strip2.bodyPart][strip2.ring][strip2.vertex];
					//writeln(bodyParts.length," ",bodyPart.strips[j+1].bodyPart);
					bodyParts[strip1.bodyPart].vertices[idx1].indices_=bodyParts[strip2.bodyPart].vertices[idx2].indices_;
				}
			}
			/+
			auto vrts=bodyPart.strips.map!(strip=>bodyParts[strip.bodyPart].vertices[vrt[strip.bodyPart][strip.ring][strip.vertex]]);
			bodyParts[$-1].vertices~=chain(vrts,vrts).array;
			auto ind1=iota(to!uint(bodyParts[$-1].vertices.length-2*bodyPart.strips.length),to!uint(bodyParts[$-1].vertices.length-bodyPart.strips.length));
			auto ind2=iota(to!uint(bodyParts[$-1].vertices.length-bodyPart.strips.length),to!uint(bodyParts[$-1].vertices.length));
			foreach(j;0..bodyPart.strips.length){
				// TODO: is there a way to figure out what the orientation should be?
				bodyParts[$-1].faces~=[ind1[j],ind1[(j+1)%$],ind1[(j+2)%$]];
				bodyParts[$-1].faces~=[ind2[j],ind2[(j+2)%$],ind2[(j+1)%$]];
				//if(j&1) swap(bodyParts[$-1].faces[$-1][1],bodyParts[$-1].faces[$-1][2]);
				//bodyParts[$-1].faces~=[ind[j],ind[(j+2)%$],ind[(j+1)%$]];
			}+/
		}
	}
	//writeln("numVertices: ",std.algorithm.sum(bodyParts.map!(bodyPart=>bodyPart.vertices.length)));
	//writeln("numFaces: ",std.algorithm.sum(bodyParts.map!(bodyPart=>bodyPart.vertices.length)));
	//writeln("numBones: ",bones.length);
	return Saxs!B(model.zfactor,bones,positions,bodyParts);
}

static if(!gpuSkinning){
	B.Mesh[] createMeshes(B)(Saxs!B saxs){
		auto ap = new Vector3f[](saxs.bones.length);
		ap[0]=Vector3f(0,0,0);
		foreach(i,ref bone;saxs.bones[1..$]){
			ap[i+1]=bone.position;
			ap[i+1]+=ap[bone.parent];
		}
		auto meshes=new B.Mesh[](saxs.bodyParts.length);
		foreach(i,ref bodyPart;saxs.bodyParts){
			meshes[i]=B.makeMesh(bodyPart.vertices.length,bodyPart.faces.length);
			foreach(j,ref vertex;bodyPart.vertices){
				auto position=Vector3f(0,0,0);
				foreach(v;vertex.indices.map!(k=>(ap[saxs.positions[k].bone]+saxs.positions[k].offset)*saxs.positions[k].weight))
					position+=v;
				meshes[i].vertices[j]=position;
				meshes[i].texcoords[j]=vertex.uv;
			}
			meshes[i].indices[]=bodyPart.faces[];
			meshes[i].generateNormals();
			B.finalizeMesh(meshes[i]);
		}
		return meshes;
	}
}else{
	B.BoneMesh[] createBoneMeshes(B)(Saxs!B saxs,Pose normalPose){
		auto meshes=new B.BoneMesh[](saxs.bodyParts.length);
		foreach(i,ref bodyPart;saxs.bodyParts){
			meshes[i]=B.makeBoneMesh(bodyPart.vertices.length,bodyPart.faces.length);
			foreach(j,ref vertex;bodyPart.vertices){
				foreach(k,index;vertex.indices){
					meshes[i].vertices[k][j]=saxs.positions[index].offset;
					meshes[i].boneIndices[j][k]=to!uint(saxs.positions[index].bone);
					meshes[i].weights[j].arrayof[k]=saxs.positions[index].weight;
				}
				meshes[i].texcoords[j]=vertex.uv;
			}
			meshes[i].indices[]=bodyPart.faces[];
			meshes[i].pose=normalPose.matrices;
			meshes[i].generateNormals();
			B.finalizeBoneMesh(meshes[i]);
		}
		return meshes;
	}
}

struct SaxsInstance(B){
	Saxs!B saxs;
	static if(!gpuSkinning) B.Mesh[] meshes;
	else B.BoneMesh[] meshes;
}

void createMeshes(B)(ref SaxsInstance!B saxsi,Pose normalPose){
	static if(!gpuSkinning) saxsi.meshes=createMeshes(saxsi.saxs);
	else saxsi.meshes=createBoneMeshes!B(saxsi.saxs,normalPose);
}


void setPose(B)(ref SaxsInstance!B saxsi, Pose pose){
	auto saxs=saxsi.saxs;
	static if(gpuSkinning){
		foreach(i;0..saxs.bodyParts.length)
			saxsi.meshes[i].pose=pose.matrices;
	}else{
		enforce(saxs.bones.length<=32);
		Transformation[32] transform;
		transform[0]=Transformation(Quaternionf.identity,Vector3f(0,0,0));
		enforce(pose.rotations.length==saxs.bones.length);
		foreach(i,ref bone;saxs.bones)
			transform[i]=transform[bone.parent]*Transformation(pose.rotations[i],bone.position);
		auto displacement=pose.displacement;
		displacement.z*=saxsi.saxs.zfactor;
		enforce(saxsi.meshes.length==saxs.bodyParts.length);
		//Vector3f low=Vector3f(1,1,1)/0.0f, high=-Vector3f(1,1,1)/0.0f;
		foreach(i,ref bodyPart;saxs.bodyParts){
			enforce(saxsi.meshes[i].vertices.length==bodyPart.vertices.length);
			foreach(j,ref vertex;bodyPart.vertices){
				auto position=displacement;
				foreach(k;vertex.indices)
					position+=transform[saxs.positions[k].bone](saxs.positions[k].offset)*saxs.positions[k].weight;
					//position+=offset*transform[saxs.positions[k].bone].getMatrix4f()*saxs.positions[k].weight;
				saxsi.meshes[i].vertices[j]=position;
				/+static foreach(k;0..3){
					low.arrayof[k]=min(low.arrayof[k],position.arrayof[k]);
					high.arrayof[k]=max(high.arrayof[k],position.arrayof[k]);
				}+/
			}
			saxsi.meshes[i].generateNormals();
			B.finalizeMesh(saxsi.meshes[i]);
		}
		//return [low,high];
	}
}
