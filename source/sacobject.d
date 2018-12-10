import dlib.math;
import util;
import mrmm, _3dsm, txtr, saxs, sxsk, widg;
import animations, ntts;
import std.typecons: Tuple, tuple;
alias Tuple=std.typecons.Tuple;

import std.exception, std.algorithm, std.math, std.path;

class SacObject(B){
	B.Mesh[] meshes;
	B.Texture[] textures;

	bool isSaxs=false;
	SaxsInstance!B saxsi;
	Animation[] animations;
	AnimationState animationState=AnimationState.stance1;
	size_t frame; // TODO: move out of here

	int sunBeamPart=-1;
	int transparentShinyPart=-1;

	this(SacObject!B rhs){ // TODO: get rid of this
		this.meshes=rhs.meshes;
		this.textures=rhs.textures;
		this.isSaxs=rhs.isSaxs;
		this.saxsi=rhs.saxsi;
		this.animations=rhs.animations;
		this.animationState=rhs.animationState;
		this.frame=rhs.frame;
		this.sunBeamPart=rhs.sunBeamPart;
		this.transparentShinyPart=rhs.transparentShinyPart;
	}

	private void setGraphicsProperties(char[4] retroKind){
		// TODO: this is a hack:
		// sunbeams
		if(retroKind.among("pcsb","casb")) sunBeamPart=0;
		// manaliths
		if(retroKind.among("mana","cama")) transparentShinyPart=0;
		if(retroKind.among("jman","stam","pyma")) transparentShinyPart=1;
		// crystals
		if(retroKind.among("crpt","stc1","stc2","stc3","sfir","stst")) transparentShinyPart=0;
		if(retroKind.among("sfor")) transparentShinyPart=0;
		if(retroKind.among("SAW1","SAW2","SAW3","SAW4","SAW5")) transparentShinyPart=0;
		// ethereal altar, ethereal sunbeams
		if(retroKind.among("ea_b","ea_r","esb1","esb2","esb_","etfn")) sunBeamPart=0;
		// "eis1","eis2", "eis3", "eis4" ?
		if(retroKind.among("st4a")){
			transparentShinyPart=0;
			sunBeamPart=1;
		}
	}

	private this(T)(char[4] retroKind,T* hack) if(is(T==Creature)||is(T==Wizard)){
		import nttData;
		isSaxs=true;
		auto data=creatureDataByTag(retroKind);
		enforce(!!data, retroKind[]);
		static if(is(T==Creature)) auto dat2=&cre8s[retroKind];
		else static if(is(T==Wizard)) auto dat2=&wizds[retroKind];
		else static assert(0);
		auto model=saxsModls[dat2.saxsModel];
		saxsi=SaxsInstance!B(loadSaxs!B(model,data.scaling));
		if(!isNaN(data.zfactorOverride)) saxsi.saxs.zfactor=data.zfactorOverride;
		auto anims=&dat2.animations;
		auto animIDs=dat2.animations.animations[];
		foreach(animID;animIDs){
			static immutable string[2][] bad=[["2fwc","oppx"],["pezH","tsZB"],["glsd","tsGB"],["ycrp","tsTS"],
			                                  ["bobs","tsZB"],["guls","tsGB"],["craa","tsGB"],["crpd","tsTS"]];
			if(!(animID=="rezW"||bad.any!(x=>x[0]==retroKind&&x[1]==animID))){
				auto anim=getSaxsAnim(model,animID);
				import std.file: exists;
				if(exists(anim)){
					auto animation=loadSXSK(anim,data.scaling);
					static if(gpuSkinning)
						animation.compile(saxsi.saxs);
					animations~=animation;
				}
			}
		}
		saxsi.createMeshes(animations[animationState].frames[0]);
		setGraphicsProperties(dat2.saxsModel);
		saxsi.setPose(animations[animationState].frames[frame]);
	}
	static SacObject!B[char[4]] objects;
	static SacObject!B getSAXS(T)(char[4] retroKind)if(is(T==Creature)||is(T==Wizard)){
		if(auto r=retroKind in objects) return *r;
		return objects[retroKind]=new SacObject!B(retroKind,(T*).init); // hack
	}

	this(string filename, float scaling=1.0, string animation=""){
		enforce(filename.endsWith(".MRMM")||filename.endsWith(".3DSM")||filename.endsWith(".WIDG")||filename.endsWith(".SXMD"));
		setGraphicsProperties(filename[$-9..$-5][0..4]);
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
				if(animation.length)
					loadAnimation(animation,scaling);
				saxsi.createMeshes();
				break;
			default:
				assert(0);
		}
	}

	void loadAnimation(string animation,float scaling){ // (just for testing)
		enforce(animations.length<=1);
		auto anim=loadSXSK(animation,scaling);
		static if(gpuSkinning)
			anim.compile(saxsi.saxs);
		frame=0;
		animations=[anim];
		saxsi.setPose(anim.frames[frame]);
	}

	void setAnimationState(AnimationState state){ // TODO: move out of here
		animationState=state;
		frame=0;
		if(animations[state].frames.length)
			saxsi.setPose(animations[state].frames[frame]);
	}

	Vector3f position = Vector3f(0,0,0); // TODO: move out of here
	Quaternionf rotation = rotationQuaternion(Axis.y,cast(float)0.0); // TODO: move out of here

	size_t numFrames(){
		if(animationState>=animations.length) return 1;
		return max(1,animations[animationState].frames.length);
	}
	double animFPS(){
		return 30;
	}

	void setFrame(size_t frame)in{
		assert(frame<numFrames());
	}body{
		if(isSaxs){
			this.frame=frame;
			if(animationState>=animations.length||animations[animationState].frames.length==0) return;
			saxsi.setPose(animations[animationState].frames[frame]);
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
