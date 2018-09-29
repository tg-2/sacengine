import dagon;
import util;
import mrmm, _3dsm, txtr, saxs, sxsk;
import std.typecons: Tuple, tuple;
alias Tuple=std.typecons.Tuple;

import std.exception, std.algorithm, std.math, std.path;

class SacObject: Owner{
	DynamicArray!Mesh meshes;
	DynamicArray!Texture textures;

	bool isSaxs=false;
	SaxsInstance saxsi;
	Animation anim;

	DynamicArray!Entity entities;

	this(Owner o, string filename, string animation=""){
		super(o);
		enforce(filename.endsWith(".MRMM")||filename.endsWith(".3DSM")||filename.endsWith(".SXMD"));
		switch(filename[$-4..$]){
			case "MRMM":
				auto mt=loadMRMM(filename);
				meshes=move(mt[0]);
				textures=move(mt[1]);
				break;
			case "3DSM":
				auto mt=load3DSM(filename);
				meshes=move(mt[0]);
				textures=move(mt[1]);
				break;
			case "SXMD":
				isSaxs=true;
				saxsi=SaxsInstance(loadSaxs(filename));
				saxsi.createMeshes();
				if(animation.length){
					anim=loadSXSK(animation);
					saxsi.setPose(anim.frames[0]);
				}
				break;
			default:
				assert(0);
		}
	}

	void createEntities(Scene s){
		foreach(i;0..isSaxs?saxsi.meshes.length:meshes.length){
			auto obj=s.createEntity3D();
			obj.drawable = isSaxs?saxsi.meshes[i]:meshes[i];
			obj.position = Vector3f(0, 0, 0);
			obj.rotation = rotationQuaternion(Axis.y,cast(float)PI);
			auto mat=s.createMaterial();
			if((isSaxs?saxsi.saxs.bodyParts[i].texture:textures[i]) !is null) mat.diffuse=isSaxs?saxsi.saxs.bodyParts[i].texture:textures[i];
			mat.specular=Color4f(0,0,0,1);
			obj.material=mat;
			entities.insertBack(obj);
		}
	}

	size_t numFrames(){
		return anim.frames.length?anim.frames.length:1;
	}
	double animFPS(){
		return 32;
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

auto convertModel(Model)(string dir, Model model){
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
				mesh.vertices[i] = fromSac(vertex.pos);
			}
			mesh.texcoords=New!(Vector2f[])(nvertices);
			foreach(i,ref vertex;model.vertices){
				mesh.texcoords[i] = vertex.uv;
			}
			mesh.normals=New!(Vector3f[])(nvertices);
			foreach(i,ref vertex;model.vertices){
				mesh.normals[i] = fromSac(vertex.normal);
			}
		}
	}else{
		foreach(mesh;meshes){
			auto nvertices=model.positions.length;
			mesh.vertices=New!(Vector3f[])(nvertices);
			foreach(i;0..mesh.vertices.length){
				mesh.vertices[i]=Vector3f(fromSac(model.positions[i]));
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
	int[] sizes=new int[](names.length);
	foreach(ref face;model.faces){
		++sizes[names[face.textureName]];
	}
	foreach(k,mesh;meshes) meshes[k].indices = New!(uint[3][])(sizes[k]);
	auto curs=new int[](meshes.length);
	foreach(ref face;model.faces){
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
