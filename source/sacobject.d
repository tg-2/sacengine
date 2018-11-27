import dlib.math;
import util;
import mrmm, _3dsm, txtr, saxs, sxsk, widg;
import std.typecons: Tuple, tuple;
alias Tuple=std.typecons.Tuple;

import std.exception, std.algorithm, std.math, std.path;

class SacObject(B){
	B.Mesh[] meshes;
	B.Texture[] textures;

	bool isSaxs=false;
	SaxsInstance!B saxsi;
	Animation anim;

	int sunBeamPart=-1;
	int transparentShinyPart=-1;

	this(SacObject rhs){
		this.meshes=rhs.meshes;
		this.textures=rhs.textures;
		this.isSaxs=rhs.isSaxs;
		this.saxsi=rhs.saxsi;
		this.anim=rhs.anim;
		this.sunBeamPart=rhs.sunBeamPart;
		this.transparentShinyPart=rhs.transparentShinyPart;
	}

	this(string filename, float scaling=1.0, string animation=""){
		enforce(filename.endsWith(".MRMM")||filename.endsWith(".3DSM")||filename.endsWith(".WIDG")||filename.endsWith(".SXMD"));
		auto name=filename[$-9..$-5];
		// TODO: this is a hack:
		// sunbeams
		if(name.among("pcsb","casb")) sunBeamPart=0;
		// manaliths
		if(name.among("mana","cama")) transparentShinyPart=0;
		if(name.among("jman","stam","pyma")) transparentShinyPart=1;
		// crystals
		if(name.among("crpt","stc1","stc2","stc3","sfir","stst")) transparentShinyPart=0;
		if(name.among("sfor")) transparentShinyPart=0;
		if(name.among("SAW1","SAW2","SAW3","SAW4","SAW5")) transparentShinyPart=0;
		// ethereal altar, ethereal sunbeams
		if(name.among("ea_b","ea_r","esb1","esb2","esb_","etfn")) sunBeamPart=0;
		// "eis1","eis2", "eis3", "eis4" ?
		if(name.among("st4a")){
			transparentShinyPart=0;
			sunBeamPart=1;
		}
		switch(filename[$-4..$]){
			case "MRMM":
				auto mt=loadMRMM!B(filename, scaling);
				meshes=mt[0];
				textures=mt[1];
				break;
			case "3DSM":
				auto mt=load3DSM!B(filename, scaling);
				meshes=mt[0];
				textures=mt[1];
				break;
			case "WIDG":
				enforce(scaling==1.0);
				auto mt=loadWIDG!B(filename);
				meshes=[mt[0]];
				textures=[mt[1]];
				break;
			case "SXMD":
				isSaxs=true;
				saxsi=SaxsInstance!B(loadSaxs!B(filename,scaling));
				saxsi.createMeshes();
				if(animation.length)
					loadAnimation(animation,scaling);
				break;
			default:
				assert(0);
		}
	}

	void loadAnimation(string animation,float scaling){
		anim=loadSXSK(animation,scaling);
		static if(gpuSkinning)
			anim.compile(saxsi.saxs);
		saxsi.setPose(anim.frames[0]);
	}

	Vector3f position = Vector3f(0,0,0); // TODO: make SacObject an entity
	Quaternionf rotation = rotationQuaternion(Axis.y,cast(float)0.0);
	float scaling = 1.0;

	size_t numFrames(){
		return anim.frames.length?anim.frames.length:1;
	}
	double animFPS(){
		return 30;
	}

	void setFrame(size_t frame)in{
		assert(frame<numFrames());
	}body{
		if(isSaxs){
			if(anim.frames.length==0) return;
			saxsi.setPose(anim.frames[frame]);
		}
	}
}

auto convertModel(B,Model)(string dir, Model model, float scaling){
	int[string] names;
	int cur=0;
	foreach(f;model.faces){
		if(f.textureName!in names) names[f.textureName]=cur++;
	}
	auto meshes=new B.Mesh[](names.length);
	auto textures=new B.Texture[](names.length);
	auto namesRev=new string[](names.length);
	foreach(k,v;names){
		namesRev[v]=k;
		if(k[0]==0) continue;
		auto name=buildPath(dir, k~".TXTR");
		textures[v]=B.makeTexture(loadTXTR(name));
	}

	static if(is(typeof(model.faces[0].lod))){
		auto maxLod=model.faces.map!(f=>f.lod).reduce!max;
		auto faces=model.faces.filter!(f=>f.lod==maxLod);
	}else{
		auto faces=model.faces;
	}
	int[] sizes=new int[](names.length);
	foreach(ref face;faces){
		++sizes[names[face.textureName]];
	}
	
	static if(is(typeof(model.vertices))){
		foreach(k,ref mesh;meshes){
			auto nvertices=model.vertices.length;
			mesh=B.makeMesh(nvertices,sizes[k]);
			foreach(i,ref vertex;model.vertices){
				mesh.vertices[i] = fromSac(Vector3f(vertex.pos))*scaling;
			}
			foreach(i,ref vertex;model.vertices){
				mesh.texcoords[i] = Vector2f(vertex.uv);
			}
			foreach(i,ref vertex;model.vertices){
				mesh.normals[i] = fromSac(Vector3f(vertex.normal));
			}
		}
	}else{
		foreach(k,ref mesh;meshes){
			auto nvertices=model.positions.length;
			mesh=B.makeMesh(nvertices,sizes[k]);
			foreach(i;0..mesh.vertices.length){
				mesh.vertices[i]=Vector3f(fromSac(model.positions[i]))*scaling;
			}
			foreach(i;0..mesh.texcoords.length){
				mesh.texcoords[i]=Vector2f(model.uv[i]);
			}
			foreach(i;0..mesh.normals.length){
				mesh.normals[i]=Vector3f(fromSac(model.normals[i]));
			}
		}
	}
	auto curs=new int[](meshes.length);
	foreach(ref face;faces){
		auto k=names[face.textureName];
		meshes[k].indices[curs[k]++]=face.vertices;
	}
	foreach(mesh;meshes) B.finalizeMesh(mesh);
	assert(curs==sizes);
	return tuple(meshes, textures);
}
