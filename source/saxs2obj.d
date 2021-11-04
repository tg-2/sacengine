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

void saveSkeletonObj(B)(string filename,ref Saxs!B saxs,Pose pose=Pose.init){
	auto file=File(filename,"w");
	auto transform=new Transformation[](saxs.bones.length);
	transform[0]=Transformation(Quaternionf.identity,Vector3f(0,0,0));
	enforce(pose.rotations.length==saxs.bones.length);
	foreach(i,ref bone;saxs.bones)
		transform[i]=transform[bone.parent]*Transformation(pose.rotations[i],bone.position);
	foreach(t;transform) file.writefln!"v %.10f %.10f %.10f"(t.offset.x,t.offset.z,t.offset.y);
	foreach(i,b;saxs.bones) if(i) file.writefln!"l %d %d"(i+1,b.parent+1);
}
