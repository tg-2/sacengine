import dagon;
import util;
import mrmm, _3dsm, txtr, saxs, sxsk, widg;
import std.typecons: Tuple, tuple;
alias Tuple=std.typecons.Tuple;

import std.exception, std.algorithm, std.math, std.path;

class SacObject: Owner{
	DynamicArray!Mesh meshes;
	DynamicArray!Texture textures;

	bool isSaxs=false;
	SaxsInstance saxsi;
	Animation anim;

	int sunBeamPart=-1;
	int transparentShinyPart=-1;
	
	DynamicArray!Entity entities;

	this(Owner o, SacObject rhs){
		super(o);
		this.meshes=rhs.meshes;
		this.textures=rhs.textures;
		this.isSaxs=rhs.isSaxs;
		this.saxsi=rhs.saxsi;
		this.anim=rhs.anim;
		this.sunBeamPart=rhs.sunBeamPart;
		this.transparentShinyPart=rhs.transparentShinyPart;
	}

	this(Owner o, string filename, float scaling=1.0, string animation=""){
		super(o);
		enforce(filename.endsWith(".MRMM")||filename.endsWith(".3DSM")||filename.endsWith(".WIDG")||filename.endsWith(".SXMD"));
		auto name=filename[$-9..$-5];
		// TODO: this is a hack:
		// manaliths
		if(name.among("pcsb","casb")) sunBeamPart=0;
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
				auto mt=loadMRMM(filename, scaling);
				meshes=move(mt[0]);
				textures=move(mt[1]);
				break;
			case "3DSM":
				auto mt=load3DSM(filename, scaling);
				meshes=move(mt[0]);
				textures=move(mt[1]);
				break;
			case "WIDG":
				enforce(scaling==1.0);
				auto mt=loadWIDG(filename);
				meshes.insertBack(mt[0]);
				textures.insertBack(mt[1]);
				break;
			case "SXMD":
				isSaxs=true;
				saxsi=SaxsInstance(loadSaxs(filename,scaling));
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

	void createEntities(Scene s){
		foreach(i;0..isSaxs?saxsi.meshes.length:meshes.length){
			auto obj=s.createEntity3D();
			obj.drawable = isSaxs?cast(Drawable)saxsi.meshes[i]:cast(Drawable)meshes[i];
			obj.position = position;
			obj.rotation = rotation;
			obj.scaling = scaling*Vector3f(1,1,1);
			GenericMaterial mat;
			if(i==sunBeamPart){
				assert(!isSaxs);
				mat=s.createMaterial(s.shadelessMaterialBackend);
				obj.castShadow=false;
				mat.depthWrite=false;
				mat.blending=Additive;
				mat.energy=4.0f;				
			}else if(i==transparentShinyPart){
				mat=s.createMaterial(s.shadelessMaterialBackend);
				mat.depthWrite=false;
				mat.blending=Transparent;
				mat.transparency=0.5f;
				mat.energy=20.0f;
			}else{
				mat=s.createMaterial(gpuSkinning&&isSaxs?s.boneMaterialBackend:s.defaultMaterialBackend);
			}
			auto diffuse=isSaxs?saxsi.saxs.bodyParts[i].texture:textures[i];
			if(diffuse !is null) mat.diffuse=diffuse;
			mat.specular=Color4f(0,0,0,1);
			obj.material=mat;
			/+auto shadowMat=s.createMaterial(gpuSkinning&&isSaxs?s.shadowMap.bsb:s.shadowMap.sb);
			if(diffuse !is null) shadowMat.diffuse=diffuse;
			obj.shadowMaterial=shadowMat;+/
			entities.insertBack(obj);
		}
	}

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

auto convertModel(Model)(string dir, Model model, float scaling){
	int[string] names;
	int cur=0;
	foreach(f;model.faces){
		if(f.textureName!in names) names[f.textureName]=cur++;
	}
	DynamicArray!Mesh meshes;
	DynamicArray!Texture textures;

	foreach(i;0..names.length){
		 // TODO: improve dlib
		meshes.insertBack(New!Mesh(null));
		textures.insertBack(Texture.init);
	}
	auto namesRev=new string[](names.length);
	foreach(k,v;names){
		namesRev[v]=k;
		if(k[0]==0) continue;
		auto name=buildPath(dir, k~".TXTR");
		auto t=New!Texture(null);
		t.image=loadTXTR(name);
		t.createFromImage(t.image);
		textures[v]=t;
	}
	static if(is(typeof(model.vertices))){
		foreach(mesh;meshes){
			auto nvertices=model.vertices.length;
			mesh.vertices=New!(Vector3f[])(nvertices);
			foreach(i,ref vertex;model.vertices){
				mesh.vertices[i] = fromSac(Vector3f(vertex.pos))*scaling;
			}
			mesh.texcoords=New!(Vector2f[])(nvertices);
			foreach(i,ref vertex;model.vertices){
				mesh.texcoords[i] = Vector2f(vertex.uv);
			}
			mesh.normals=New!(Vector3f[])(nvertices);
			foreach(i,ref vertex;model.vertices){
				mesh.normals[i] = fromSac(Vector3f(vertex.normal));
			}
		}
	}else{
		foreach(mesh;meshes){
			auto nvertices=model.positions.length;
			mesh.vertices=New!(Vector3f[])(nvertices);
			foreach(i;0..mesh.vertices.length){
				mesh.vertices[i]=Vector3f(fromSac(model.positions[i]))*scaling;
			}
			mesh.texcoords=New!(Vector2f[])(nvertices);
			foreach(i;0..mesh.texcoords.length){
				mesh.texcoords[i]=Vector2f(model.uv[i]);
			}
			mesh.normals=New!(Vector3f[])(nvertices);
			foreach(i;0..mesh.normals.length){
				mesh.normals[i]=Vector3f(fromSac(model.normals[i]));
			}
		}
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
	foreach(k,mesh;meshes) meshes[k].indices = New!(uint[3][])(sizes[k]);
	auto curs=new int[](meshes.length);
	foreach(ref face;faces){
		auto k=names[face.textureName];
		meshes[k].indices[curs[k]++]=face.vertices;
	}
	foreach(mesh;meshes){
		mesh.dataReady=true;
		mesh.prepareVAO();
	}
	assert(curs==sizes);
	return tuple(move(meshes), move(textures));
}
