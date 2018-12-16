import dlib.math;
import util;
import mrmm, _3dsm, txtr, saxs, sxsk, widg;
import animations, ntts, nttData, spells, bldg;
import std.typecons: Tuple, tuple;
alias Tuple=std.typecons.Tuple;

import std.exception, std.algorithm, std.math, std.path;

enum animFPS=30;

class SacObject(B){
	char[4] tag;
	char[4] nttTag;
	int stateIndex=-1;
	B.Mesh[] meshes;
	B.Texture[] textures;
	bool isSaxs=false;
	SaxsInstance!B saxsi;
	B.Material[] materials;
	B.Material[] shadowMaterials;
	Animation[] animations;
	immutable(Cre8)* cre8;
	immutable(Wizd)* wizd;
	immutable(Strc)* strc;

	@property bool mustFly(){
		return cre8&&cre8.creatureType=="ylfo";
	}
	@property bool canFly(){
		return hasAnimationState(AnimationState.fly);
	}
	@property bool canDie(){
		return hasAnimationState(AnimationState.death0);
	}
	struct MaterialConfig{
		int sunBeamPart=-1;
		int locustWingPart=-1;
		int transparentShinyPart=-1;
	}

	private void initializeNTTData(char[4] tag){
		this.tag=tag;
		this.nttTag=tag in tagsFromModel?tagsFromModel[tag]:tag;
		cre8=nttTag in cre8s;
		wizd=nttTag in wizds;
		strc=nttTag in strcs;
		assert((cre8 !is null)+(wizd !is null)+(strc !is null)<=1);
		MaterialConfig conf;
		// TODO: this is a hack:
		auto kind=tag;
		reverse(kind[]);
		// sunbeams
		if(kind.among("pcsb","casb")) conf.sunBeamPart=0;
		// manaliths
		if(kind.among("mana","cama")) conf.transparentShinyPart=0;
		if(kind.among("jman","stam","pyma")) conf.transparentShinyPart=1;
		// crystals
		if(kind.among("crpt","stc1","stc2","stc3","sfir","stst")) conf.transparentShinyPart=0;
		if(kind.among("sfor")) conf.transparentShinyPart=0;
		if(kind.among("SAW1","SAW2","SAW3","SAW4","SAW5")) conf.transparentShinyPart=0;
		if(kind.among("ST01","ST02","ST03")) conf.transparentShinyPart=0;
		// ethereal altar, ethereal sunbeams
		if(kind.among("ea_b","ea_r","esb1","esb2","esb_","etfn")) conf.sunBeamPart=0;
		// "eis1","eis2", "eis3", "eis4" ?
		if(kind.among("st4a")){
			conf.transparentShinyPart=0;
			conf.sunBeamPart=1;
		}
		// locust wings
		if(kind.among("bugz"))
			conf.locustWingPart=3;
		materials=B.createMaterials(this,conf);
		shadowMaterials=B.createShadowMaterials(this);
	}
	final int alphaFlags(char[4] tag){
		switch(tag){
			case "zidd","enab","2nab": return 1<<5;
			case "kacd": return 1<<5;
			case "mmag": return 1<<6;
			case "kacf": return 1<<7;
			//case "lbog": return 8; // TODO: looks bad, why?
			case "rmAF": return 1<<3;
			case "tbhe": return 1<<6;
			case "tbhf","tbsh","tbhl": return 1<<5;
			case "bobs","aras": return 1<<2;
			case "mwas": return 1<<6;
			case "grps","lrps": return 1<<4|1<<5;
			case "grda","nmdd": return 1<<9;
			case "gard","ybab","cris": return 1<<8;
			case "grdf": return 1<<5;
			case "oreh": return 1<<6;
			case "tkhs": return 1<<10;
			case "lgir","ziwx": return 1<<7;
			default: return 0;
		}
	}

	private this(T)(char[4] tag,T* hack) if(is(T==Creature)||is(T==Wizard)){
		isSaxs=true;
		auto data=creatureDataByTag(tag);
		enforce(!!data, tag[]);
		static if(is(T==Creature)) auto dat2=&cre8s[tag];
		else static if(is(T==Wizard)) auto dat2=&wizds[tag];
		else static assert(0);
		auto model=saxsModls[dat2.saxsModel];
		saxsi=SaxsInstance!B(loadSaxs!B(model,data.scaling,alphaFlags(dat2.saxsModel)));
		if(!isNaN(data.zfactorOverride)) saxsi.saxs.zfactor=data.zfactorOverride;
		auto anims=&dat2.animations;
		auto animIDs=dat2.animations.animations[];
		animations=new Animation[](animIDs.length);
		foreach(i,ref animID;animIDs){
			static immutable string[2][] bad=[["2fwc","oppx"],["pezH","tsZB"],["glsd","tsGB"],["ycrp","tsTS"],
			                                  ["bobs","tsZB"],["guls","tsGB"],["craa","tsGB"],["crpd","tsTS"]];
			if(!(animID=="rezW"||animID[0..2]=="00"||bad.any!(x=>x[0]==tag&&x[1]==animID))){
				auto anim=getSaxsAnim(model,animID);
				import std.file: exists;
				if(exists(anim)&&!(&animID !is &dat2.animations.stance1 && animID==dat2.animations.stance1)){
					auto animation=loadSXSK(anim,data.scaling);
					static if(gpuSkinning)
						animation.compile(saxsi.saxs);
					animations[i]=animation;
				}
			}
		}
		saxsi.createMeshes(animations[AnimationState.stance1].frames[0]);
		initializeNTTData(dat2.saxsModel);
	}
	static SacObject!B[char[4]] objects;
	static SacObject!B getSAXS(T)(char[4] tag)if(is(T==Creature)||is(T==Wizard)){
		if(auto r=tag in objects) return *r;
		return objects[tag]=new SacObject!B(tag,(T*).init); // hack
	}

	private this(T)(char[4] tag, T* hack) if(is(T==Structure)){
		auto mt=loadMRMM!B(bldgModls[tag],1.0f);
		meshes=mt[0];
		textures=mt[1];
		initializeNTTData(tag);
	}
	static SacObject!B getBLDG(char[4] tag){
		if(auto r=tag in objects) return *r;
		return objects[tag]=new SacObject!B(tag,(Structure*).init); // hack
	}

	private this(T)(char[4] tag, T* hack) if(is(T==Widgets)){
		auto mt=loadWIDG!B(widgModls[tag]);
		meshes=[mt[0]];
		textures=[mt[1]];
		initializeNTTData(tag);
	}
	static SacObject!B getWIDG(char[4] tag){
		if(auto r=tag in objects) return *r;
		return objects[tag]=new SacObject!B(tag,(Widgets*).init); // hack
	}

	this(string filename, float scaling=1.0, string animation=""){
		enforce(filename.endsWith(".MRMM")||filename.endsWith(".3DSM")||filename.endsWith(".WIDG")||filename.endsWith(".SXMD"));
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
				saxsi=SaxsInstance!B(loadSaxs!B(filename,scaling,alphaFlags(tag)));
				import std.range, std.array;
				if(animation.length)
					loadAnimation(animation,scaling);
				if(!animations.length){
					auto anim=Animation([Pose(Vector3f(0,0,0),facingQuaternion(0).repeat(saxsi.saxs.bones.length).array)]);
					if(gpuSkinning)
						anim.compile(saxsi.saxs);
					animations=[anim];
				}
				saxsi.createMeshes(animations[0].frames[0]);
				break;
			default:
				assert(0);
		}
		char[4] tag=filename[$-9..$-5][0..4];
		reverse(tag[]);
		initializeNTTData(tag);
	}

	void loadAnimation(string animation,float scaling){ // (just for testing)
		enforce(animations.length<=1);
		auto anim=loadSXSK(animation,scaling);
		static if(gpuSkinning)
			anim.compile(saxsi.saxs);
		animations=[anim];
		if(saxsi.meshes.length) saxsi.setPose(anim.frames[0]);
	}

	final bool hasAnimationState(AnimationState state){
		return state<animations.length&&animations[state].frames.length;
	}

	final int numFrames(AnimationState animationState){
		return isSaxs?cast(int)animations[animationState].frames.length:0;
	}

	void setFrame(AnimationState animationState,size_t frame)in{
		assert(frame<numFrames(animationState));
	}body{
		saxsi.setPose(animations[animationState].frames[frame]);
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
		textures[v]=B.makeTexture(loadTXTR(name),false);
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
