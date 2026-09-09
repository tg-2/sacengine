// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import dlib.math, dlib.math.portable;
import dlib.image : SuperImage;
import util;
import sxmd,sxsk,sxtx;

import std.stdio, std.path, std.string, std.exception, std.algorithm, std.range, std.conv;

struct Bone{
	Vector3f position; 
	size_t parent; // parent index (parent must have a smaller index than its children)
	Vector3f[8] hitbox;
}

struct Position{
	int bone;
	Vector3f offset;
	float weight;
	Vector3f normal;
}

struct Vertex{
	private int[3] indices_;
	Vector2f uv;
	this(R)(R indices, Vector2f uv){
		indices_[]=-1;
		size_t count;
		foreach(index;indices){
			enforce(count<indices_.length,"SXMD vertex has more than three source references"); 
			// I added a bunch of these in case we have any memory/disk corruptions, remove  if we dont need them
			indices_[count++]=index;
		}
		this.uv=uv;
	}
	@property const(int)[] indices() const return{
		foreach(i;0..3){
			if(indices_[i]==-1)
				return indices_[0..i];
		}
		return indices_[];
	}
}

struct BodyPart(B){
	Vertex[] vertices;
	uint[3][] faces;
	B.Texture texture;
	size_t seamFaceStart, seamFaceCount;
}

struct Saxs(B){
	float zfactor;
	float scaling;
	Bone[] bones;
	int[] hitboxBones;
	Position[] positions;
	BodyPart!B[] bodyParts;
}

Saxs!B loadSaxs(B)(string filename){
	enforce(filename.endsWith(".SXMD"));
	import saxs_;
	auto saxs=loadSAXS(filename[0..$-5]~".SAXS");
	auto scaling=saxs.scaling;
	int vertexStep=cast(int)(saxs.vertexQuality*65536.0f);
	int ringStep=cast(int)(saxs.ringQuality*65536.0f);
	enforce(vertexStep>0 && ringStep>0,"Invalid SAXS quality values");
	auto dir=dirName(filename);
	auto model = parseSXMD(readFile(filename));
	SuperImage[] textureImages;
	uint[] textureWidths,textureHeights;
	foreach(i;0..model.bodyParts.length){
		auto limb=saxs.limbs[i];
		auto chromaKey=(limb.flags&1)?cast(int)(limb.chromaKey&0xffffff):-1;
		auto image=loadSXTX(buildPath(dir,format(".%03d.SXTX",i+1)),chromaKey);
		textureWidths~=cast(uint)image.width;
		textureHeights~=cast(uint)image.height;
		textureImages~=image;
	}
	prepareRetailUVs(model,textureWidths,textureHeights);
	Vector3f[8] translateHitbox(float[3][8] hitbox){
		Vector3f[8] result;
		foreach(i;0..8) result[i]=Vector3f(fromSXMD(hitbox[i]))*scaling;
		return result;
	}
	auto bones=chain(only(Bone(Vector3f(0,0,0),0)),model.bones.map!(bone=>Bone(Vector3f(fromSXMD(bone.pos))*scaling,bone.parent,translateHitbox(bone.hitbox)))).array;
	enforce(iota(1,bones.length).all!(i=>bones[i].parent<i));
	auto hitboxBones=iota(cast(int)bones.length).filter!(i=>saxs.hitboxBones[i]).array;
	//enforce(saxs.hitboxBones[bones.length..$].all!(x=>!x)); // TODO: why does this not hold? 
	//Because SAXS leaves entries beyond the active bone count uninitialized (and that goes up to 40 bones btw).
	auto convertPosition(ref sxmd.Position position){
		return Position(
			position.bone,
			fromSXMD(Vector3f(position.pos))*scaling,
			position.weight/16384.0f,
			fromSXMD(Vector3f(position.normal))*(1.0f/32767.0f)
		);
	}
	auto positions=model.positions.map!convertPosition().array;
	SeamBody[] seamBodies=new SeamBody[](model.bodyParts.length);
	foreach(i,bodyPart;model.bodyParts){
		SeamRecord[] records;
		foreach(record;bodyPart.strips) records~=
			SeamRecord(record.bodyPart,record.ring,record.vertex,record.textureU,record.textureV);
		ubyte otherPart,wrapU;
		if(bodyPart.stripHeader){
			otherPart=bodyPart.stripHeader.unknown0[0];
			wrapU=bodyPart.stripHeader.unknown0[1];
		}
		seamBodies[i]=SeamBody(null,records,bodyPart.flags,otherPart,wrapU);
		prepareSeam(seamBodies[i],i);
	}
	int[][] selectedRings=new int[][](model.bodyParts.length);
	foreach(i,bodyPart;model.bodyParts){
		SeamRing[] selectorRings;
		foreach(ring;bodyPart.rings)
			selectorRings~=SeamRing(null,true,ring.header.unknown);
		seamBodies[i].rings=selectorRings;
		selectedRings[i]=selectRetailRings(seamBodies[i],0x1c10,ringStep);
	}
	uint[][][] selectedVertices=new uint[][][](model.bodyParts.length);
	bool[size_t] emittedSeamEntries;
	foreach(bodyPart;model.bodyParts) foreach(ring;bodyPart.rings)
		foreach(k;0..ring.entries.length)
			emittedSeamEntries[cast(size_t)(ring.entries.ptr+k)]=false;
	foreach(i,bodyPart;model.bodyParts){
		selectedVertices[i]=new uint[][](bodyPart.rings.length);
		foreach(selectedRing;selectedRings[i]){
			auto entries=bodyPart.rings[selectedRing].entries;
			ushort[] flags=entries.map!(entry=>cast(ushort)(entry.unknown1 & 0xfeff)).array;
			auto selection=selectRetailVertices(flags,vertexStep,
				bodyPart.numExplicitFaces!=0,0x1c10);
			selectedVertices[i][selectedRing]=selection;
			foreach(k;selection)
				emittedSeamEntries[cast(size_t)(entries.ptr+k)]=true;
		}
	}
	size_t[][] seamRingLengths=new size_t[][](model.bodyParts.length);
	foreach(i,bodyPart;model.bodyParts)
		seamRingLengths[i]=bodyPart.rings.map!(ring=>ring.entries.length).array;
	foreach(owner,body;seamBodies) foreach(record;body.records){
		if(record.bodyPart==owner){
			int ring=(body.flags & BodyPartFlags.HAS_SEAM)
				? ((body.flags & BodyPartFlags.SEAM_STARTS_RING_ZERO)
					? selectedRings[owner][0] : selectedRings[owner][$-1])
				: record.ring;
			if(ring>=0 && ring<model.bodyParts[owner].rings.length)
				seamRingLengths[owner][ring]=max(seamRingLengths[owner][ring],cast(size_t)record.vertex+1);
		}
		if(body.otherPart<model.bodyParts.length && record.bodyPart==body.otherPart && record.ring<model.bodyParts[body.otherPart].rings.length)
			seamRingLengths[body.otherPart][record.ring]=max(
				seamRingLengths[body.otherPart][record.ring],cast(size_t)record.vertex+1);
	}
	foreach(i,bodyPart;model.bodyParts){
		SeamRing[] rings;
		foreach(j,ring;bodyPart.rings){
			SeamVertex[] source;
			auto raw=ring.entries.ptr[0..seamRingLengths[i][j]];
			foreach(k,entry;raw){
				auto emitted=cast(size_t)(raw.ptr+k) in emittedSeamEntries;
				bool descriptorActive=emitted !is null ? *emitted : (entry.unknown1 & 0x100)!=0;
				source~=SeamVertex(entry.indices,entry.textureU,entry.textureV,descriptorActive);
			}
			bool active=selectedRings[i].canFind(cast(int)j);
			rings~=SeamRing(source,active,ring.header.unknown);
		}
		seamBodies[i].rings=rings;
	}
	BodyPart!B[] bodyParts;
	auto vrt=new uint[][][](model.bodyParts.length);
	foreach(i,bodyPart;model.bodyParts){
		Vertex[] vertices;
		vrt[i]=new uint[][](bodyPart.rings.length);
		foreach(selectedRing;selectedRings[i]){
			size_t j=cast(size_t)selectedRing;
			auto ring=bodyPart.rings[j];
			auto selection=selectedVertices[i][j];
			vrt[i][j]=new uint[](selection.length+1);
			foreach(ordinal,k;selection){
				auto entry=ring.entries[k];
				vrt[i][j][ordinal]=to!uint(vertices.length);
				auto indices=entry.indices[].map!(to!int).filter!(x=>x!=ushort.max);
				auto uv=Vector2f(entry.textureU/256.0f,entry.textureV/256.0f);
				vertices~=Vertex(indices,uv);
			}
			vrt[i][j][selection.length]=to!uint(vertices.length);
			vertices~=vertices[vrt[i][j][0]];
			vertices[$-1].uv[0]=ring.texture/256.0f;
		}
		uint[3][] faces;
		foreach(k;0..selectedRings[i].length-1){
			size_t j=cast(size_t)selectedRings[i][k];
			size_t next=cast(size_t)selectedRings[i][k+1];
			auto oldEntries=bodyPart.rings[j].entries;
			auto newEntries=bodyPart.rings[next].entries;
			auto oldSelected=selectedVertices[i][j];
			auto newSelected=selectedVertices[i][next];
			auto oldRing=oldEntries.map!(entry=>RetailRingVertex(entry.unknown1,entry.textureU,false)).array;
			auto newRing=newEntries.map!(entry=>RetailRingVertex(entry.unknown1,entry.textureU,false)).array;
			foreach(n;oldSelected) oldRing[n].active=true;
			foreach(n;newSelected) newRing[n].active=true;
			ushort oldPost=(oldEntries.ptr+oldEntries.length).unknown1;
			ushort newPost=(newEntries.ptr+newEntries.length).unknown1;
			auto ringFaces=buildRetailRingFaces(oldRing,newRing,oldPost,newPost);
			uint base=vrt[i][j][0];
			foreach(face;ringFaces) faces~=[face[0]+base,face[2]+base,face[1]+base];
		}
		foreach (first; [true, false]) {
			auto j=first ? selectedRings[i][0] : selectedRings[i][$-1];
			if(first ? j!=0 : j!=bodyPart.rings.length-1) continue;
			uint count=cast(uint)selectedVertices[i][j].length+(first ? 0u : 1u);
			foreach(face; buildRetailCap(0x1c10,bodyPart.flags,first,vrt[i][j][0],count))
				faces~=[face[0],face[2],face[1]];
		}
		if(bodyPart.explicitFaces.length){
			enforce(vrt[i].length==1);
			foreach(eface;bodyPart.explicitFaces)
				faces~=[vrt[i][0][eface[0]],vrt[i][0][eface[1]],vrt[i][0][eface[2]]];
		}
		auto texture=B.makeTexture(textureImages[i],false);
		//writeln(i,": ",bodyPart.flags," ",bodyPart.unknown0," ",bodyPart.unknown1);
		//if(bodyPart.flags==0&&bodyPart.unknown0[].all!(x=>x==0)&&bodyPart.unknown1[].all!(x=>x==0)) faces=[];
		bodyParts~=BodyPart!B(vertices,faces,texture);
	}
	foreach(i,ref seamBody;seamBodies){
		if(!seamBody.records.length) continue;
		int firstRing=selectedRings[i][0];
		int lastRing=selectedRings[i][$-1];
		auto seam=buildRetailSeam(seamBodies,i,firstRing,lastRing);
		bodyParts[i].seamFaceStart=bodyParts[i].faces.length;
		bodyParts[i].seamFaceCount=seam.faces.length;
		uint base=cast(uint)bodyParts[i].vertices.length;
		foreach(vertex;seam.vertices){
			auto indices=vertex.indices[].map!(to!int).filter!(x=>x!=ushort.max);
			bodyParts[i].vertices~=Vertex(indices,Vector2f(vertex.u,vertex.v));
		}
		foreach(face;seam.faces)
			bodyParts[i].faces~=[face[0]+base,face[2]+base,face[1]+base];
	}
	//writeln("numVertices: ",std.algorithm.sum(bodyParts.map!(bodyPart=>bodyPart.vertices.length)));
	//writeln("numFaces: ",std.algorithm.sum(bodyParts.map!(bodyPart=>bodyPart.vertices.length)));
	//writeln("numBones: ",bones.length);
	return Saxs!B(model.zfactor,scaling,bones,hitboxBones,positions,bodyParts);
}


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

B.BoneMesh[] createBoneMeshes(B)(Saxs!B saxs,Pose normalPose){
	auto meshes=new B.BoneMesh[](saxs.bodyParts.length);
	foreach(i,ref bodyPart;saxs.bodyParts){
		meshes[i]=B.makeBoneMesh(bodyPart.vertices.length,bodyPart.faces.length);
		meshes[i].retailSourceNormals=true;
		meshes[i].seamFaceStart=bodyPart.seamFaceStart;
		meshes[i].seamFaceCount=bodyPart.seamFaceCount;
		foreach(j,ref vertex;bodyPart.vertices){
			foreach(k,index;vertex.indices){
				meshes[i].vertices[k][j]=saxs.positions[index].offset;
				meshes[i].boneIndices[j][k]=to!uint(saxs.positions[index].bone);
				meshes[i].weights[j].arrayof[k]=saxs.positions[index].weight;
			}
			meshes[i].texcoords[j]=vertex.uv;
			meshes[i].normals[j]=saxs.positions[vertex.indices[0]].normal;
		}
		meshes[i].indices[]=bodyPart.faces[];
		B.finalizeBoneMesh(meshes[i]);
	}
	return meshes;
}

struct SaxsInstance(B){
	Saxs!B saxs;
	static if(!gpuSkinning) B.Mesh[] meshes;
	else B.BoneMesh[] meshes;
}

void createMeshes(B)(ref SaxsInstance!B saxsi,Pose normalPose){
	static if(!gpuSkinning) saxsi.meshes=createMeshes(saxsi.saxs,/+normalPose+/);
	else saxsi.meshes=createBoneMeshes!B(saxsi.saxs,normalPose);
}

void setPose(B)(ref Saxs!B saxs,ref B.Mesh[] meshes,Pose pose){
	enforce(saxs.bodyParts.length==meshes.length);
	enforce(saxs.bones.length<=maxNumBones);
	Transformation[maxNumBones] transform;
	transform[0]=Transformation(Quaternionf.identity,Vector3f(0,0,0));
	enforce(pose.rotations.length==saxs.bones.length);
	foreach(i,ref bone;saxs.bones)
		transform[i]=transform[bone.parent]*Transformation(pose.rotations[i],bone.position);
	auto displacement=pose.displacement;
	displacement.z*=saxs.zfactor;
	enforce(meshes.length==saxs.bodyParts.length);
	//Vector3f low=Vector3f(1,1,1)/0.0f, high=-Vector3f(1,1,1)/0.0f;
	foreach(i,ref bodyPart;saxs.bodyParts){
		enforce(meshes[i].vertices.length==bodyPart.vertices.length);
		foreach(j,ref vertex;bodyPart.vertices){
			auto position=displacement;
			foreach(k;vertex.indices)
				position+=transform[saxs.positions[k].bone](saxs.positions[k].offset)*saxs.positions[k].weight;
			//position+=offset*transform[saxs.positions[k].bone].getMatrix4f()*saxs.positions[k].weight;
			meshes[i].vertices[j]=position;
			/+static foreach(k;0..3){
				low.arrayof[k]=min(low.arrayof[k],position.arrayof[k]);
				high.arrayof[k]=max(high.arrayof[k],position.arrayof[k]);
			}+/
		}
		meshes[i].generateNormals();
		B.finalizeMesh(meshes[i]);
	}
	//return [low,high];
}
