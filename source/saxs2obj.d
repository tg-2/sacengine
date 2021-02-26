// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import dagon;
import saxs, sxsk, dagonBackend;
static if(!gpuSkinning):
	import std.algorithm, std.range, std.stdio;

void writeObj(B)(File file,Saxs!B saxs,Pose pose=Pose.init){
	auto saxsi=SaxsInstance!B(saxs);
	saxsi.createMeshes(pose);
	if(pose !is pose.init) saxsi.setPose(pose);
	auto meshes=saxsi.meshes;
	int numVertices=0;
	foreach(i,mesh;meshes){
		file.writefln!"o bodypart%03d"(i+1);
		file.writefln!"usemtl bodypart%03d"(i+1);
		int firstVertex=numVertices+1;
		foreach(j;0..mesh.vertices.length){
			file.writefln!"v %.10f %.10f %.10f"(mesh.vertices[j].x,mesh.vertices[j].z,mesh.vertices[j].y);
			file.writefln!"vn %.10f %.10f %.10f"(mesh.normals[j].x,mesh.normals[j].z,mesh.normals[j].y);
			file.writefln!"vt %.10f %.10f"(mesh.texcoords[j].x,1.0f-mesh.texcoords[j].y);
			numVertices++;
		}
		foreach(tri;mesh.indices){
			file.writefln!"f %d/%d/%d %d/%d/%d %d/%d/%d"(firstVertex+tri[0],firstVertex+tri[0],
			                                             firstVertex+tri[0],
			                                             firstVertex+tri[1],firstVertex+tri[1],
			                                             firstVertex+tri[1],
			                                             firstVertex+tri[2],firstVertex+tri[2],
			                                             firstVertex+tri[2]);
		}
	}
}
