// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import dagon;
import saxs, sxsk, obj, dagonBackend, util;
import std.algorithm, std.range, std.stdio, std.exception;

alias saveObj=obj.saveObj;
void saveObj(B)(string filename,ref Saxs!B saxs,Pose pose=Pose.init){
	auto saxsi=SaxsInstance!B(saxs);
	auto meshes=createMeshes(saxs);
	if(pose !is pose.init) setPose!B(saxs,meshes,pose);
	.saveObj!B(filename,meshes);
}

Transformation[] transformationsOf(B)(Saxs!B saxs,Pose pose=Pose.init){
	auto transform=new Transformation[](saxs.bones.length);
	transform[0]=Transformation(Quaternionf.identity,Vector3f(0,0,0));
	enforce(pose.rotations.length==saxs.bones.length);
	foreach(i,ref bone;saxs.bones)
		transform[i]=transform[bone.parent]*Transformation(pose.rotations[i],bone.position);
	auto displacement=pose.displacement;
	displacement.z*=saxs.zfactor;
	foreach(j;0..saxs.bones.length)
		transform[j].offset+=displacement;
	return transform;
}

void saveSkeletonObj(B)(string filename,Saxs!B saxs,Pose pose=Pose.init){
	auto file=File(filename,"w");
	auto transform=transformationsOf(saxs,pose);
	foreach(t;transform) file.writefln!"v %.10f %.10f %.10f"(t.offset.x,t.offset.z,-t.offset.y);
	foreach(i,b;saxs.bones) if(i) file.writefln!"l %d %d"(i+1,b.parent+1);
}

B.BoneMesh[] transferModel(B)(B.Mesh[] meshes,Saxs!B saxs,Pose pose=Pose.init){
	auto bmeshes=new B.BoneMesh[](meshes.length);
	foreach(i,ref bmesh;bmeshes) bmesh=transferModel!B(i,meshes[i],saxs,pose);
	return bmeshes;
}

B.BoneMesh transferModel(B)(size_t meshIndex,B.Mesh mesh,Saxs!B saxs,Pose pose){
	auto bmesh=B.makeBoneMesh(mesh.vertices.length,mesh.indices.length);
	auto transform=transformationsOf(saxs,pose);
	foreach(i,vertex;mesh.vertices){
		/*auto bestBone=0, bestDistanceSqr=float.infinity;
		foreach(j,bone;saxs.bones){
			if(j==0) continue;
			auto position=transform[j].offset;
			auto distanceSqr=(vertex-position).lengthsqr;
			if(distanceSqr<bestDistanceSqr){
				bestBone=cast(int)j;
				bestDistanceSqr=distanceSqr;
			}
		}
		bmesh.vertices[0][i]=rotate(transform[bestBone].rotation.conj(),vertex-transform[bestBone].offset);
		bmesh.boneIndices[i]=[bestBone,0,0];*/
		Vector3f bestPosition=Vector3f(0.0f,0.0f,0.0f);
		uint[3] bestBones=[0,0,0];
		Vector3f[3] bestOffsets=Vector3f(0.0f,0.0f,0.0f);
		auto bestWeights=Vector3f(1.0f,0.0f,0.0f);
		auto bestDistanceSqr=float.infinity;
		foreach(bp;saxs.bodyParts){
			foreach(bvertex;bp.vertices){
				Vector3f bvertexPosition=Vector3f(0.0f,0.0f,0.0f);
				uint[3] bones=[0,0,0];
				Vector3f[3] offsets=Vector3f(0.0f,0.0f,0.0f);
				auto weights=Vector3f(0.0f,0.0f,0.0f);
				foreach(k,index;bvertex.indices){
					auto position=saxs.positions[index];
					bvertexPosition+=transform[position.bone](position.offset)*position.weight;
					bones[k]=cast(uint)position.bone;
					offsets[k]=position.offset;
					weights[k]=position.weight;
				}
				auto distanceSqr=(vertex-bvertexPosition).lengthsqr;
				if(distanceSqr<bestDistanceSqr){
					bestPosition=bvertexPosition;
					bestBones=bones;
					bestOffsets=offsets;
					bestWeights=weights;
					bestDistanceSqr=distanceSqr;
				}
			}
		}
		bmesh.boneIndices[i]=bestBones;
		//int bestNumOffsets=0;
		//foreach(k;0..3) bestNumOffsets+=bestWeights[k]!=0.0f;
		/*int primary=0;
		float primaryWeight=-1.0f;
		foreach(k;0..3) if(bestWeights[k]>primaryWeight){
			primary=k;
			primaryWeight=bestWeights[k];
		}*/
		foreach(k;0..3){
			if(bestWeights[k]==0.0f) continue;
			//bmesh.vertices[k][i]=bestOffsets[k]+rotate(transform[bestBones[k]].rotation.conj(),(vertex-bestPosition)/(bestNumOffsets*bestWeights[k]));
			bmesh.vertices[k][i]=bestOffsets[k]+rotate(transform[bestBones[k]].rotation.conj(),vertex-bestPosition);
			//if(k==primary) bmesh.vertices[k][i]+=rotate(transform[bestBones[k]].rotation.conj(),(vertex-bestPosition)/bestWeights[k]);
		}
		bmesh.weights[i]=bestWeights;
	}
	/*bmesh.boneIndices[]=[0,0,0];
	bmesh.vertices[0][]=mesh.vertices[];
	bmesh.vertices[1][]=Vector3f(0.0f,0.0f,0.0f);
	bmesh.vertices[2][]=Vector3f(0.0f,0.0f,0.0f);
	bmesh.weights[]=Vector3f(1.0f,0.0f,0.0f);*/
	bmesh.texcoords[]=mesh.texcoords[];
	bmesh.indices[]=mesh.indices[];
	bmesh.pose=pose.matrices;
	bmesh.generateNormals();
	B.finalizeBoneMesh(bmesh);
	return bmesh;
}
