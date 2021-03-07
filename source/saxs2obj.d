// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import dagon;
import saxs, sxsk, obj, dagonBackend;
import std.algorithm, std.range, std.stdio;

alias saveObj=obj.saveObj;
void saveObj(B)(string filename,ref Saxs!B saxs,Pose pose=Pose.init){
	auto saxsi=SaxsInstance!B(saxs);
	auto meshes=createMeshes(saxs);
	if(pose !is pose.init) setPose!B(saxs,meshes,pose);
	.saveObj!B(filename,meshes);
}
