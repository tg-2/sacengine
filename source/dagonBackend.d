import dagon;
import options,util;
import std.math;
import std.stdio;
import std.algorithm, std.range;

import sacobject, sacmap, state;
import sxsk : gpuSkinning;


class SacScene: Scene{
	//OBJAsset aOBJ;
	//Texture txta;
	this(SceneManager smngr, Options options){
		super(smngr);
		this.shadowMapResolution=options.shadowMapResolution;
	}
	FirstPersonView2 fpview;
	override void onAssetsRequest(){
		//aOBJ = addOBJAsset("../jman.obj");
		//txta = New!Texture(null);// TODO: why?
		//txta.image = loadTXTR("extracted/jamesmod/JMOD.WAD!/modl.FLDR/jman.MRMC/M001.TXTR");
		//txta.createFromImage(txta.image);
	}
	GameState!DagonBackend state;
	DynamicArray!(SacObject!DagonBackend) sacs;
	Entity[] skyEntities;
	alias createSky=typeof(super).createSky;
	void createSky(SacMap!DagonBackend map){
		auto envi=&map.envi;
		/+auto eSky=createSky();
		eSky.rotation=rotationQuaternion(Axiz,cast(float)PI)*
			rotationQuaternion(Axix,cast(float)(PI/2));+/
		auto x=10.0f*map.n/2, y=10.0f*map.m/2;

		//auto mesh=New!ShapeSphere(sqrt(0.5^^2+0.7^^2), 8, 4, true, assetManager);

		auto matSkyb = createMaterial(shadelessMaterialBackend);
		matSkyb.diffuse=map.textures[258];
		matSkyb.blending=Transparent;
		matSkyb.energy=map.Sky.energy;
		auto eSkyb = createEntity3D();
		eSkyb.castShadow = false;
		eSkyb.material = matSkyb;
		auto meshb=New!Mesh(assetManager);
		meshb.vertices=New!(Vector3f[])(2*(map.Sky.numSegs+1));
		meshb.texcoords=New!(Vector2f[])(2*(map.Sky.numSegs+1));
		meshb.indices=New!(uint[3][])(2*map.Sky.numSegs);
		foreach(i;0..map.Sky.numSegs+1){
			auto angle=2*PI*i/map.Sky.numSegs, ca=cos(angle), sa=sin(angle);
			meshb.vertices[2*i]=Vector3f(0.5*ca*0.8,0.5*sa*0.8,map.Sky.undrZ)*map.Sky.scaling;
			meshb.vertices[2*i+1]=Vector3f(0.5*ca,0.5*sa,0)*map.Sky.scaling;
			auto txc=cast(float)i*map.Sky.numTextureRepeats/map.Sky.numSegs;
			meshb.texcoords[2*i]=Vector2f(txc,0);
			meshb.texcoords[2*i+1]=Vector2f(txc,1);
		}
		foreach(i;0..map.Sky.numSegs){
			meshb.indices[2*i]=[2*i,2*i+1,2*(i+1)];
			meshb.indices[2*i+1]=[2*(i+1),2*i+1,2*(i+1)+1];
		}
		meshb.generateNormals();
		meshb.dataReady=true;
		meshb.prepareVAO();
		eSkyb.drawable = meshb;
		eSkyb.position=Vector3f(x,y,map.Sky.dZ*map.Sky.scaling+1);
		eSkyb.updateTransformation();

		auto matSkyt = createMaterial(shadelessMaterialBackend);
		matSkyt.diffuse=map.textures[259];
		matSkyt.blending=Transparent;
		matSkyt.energy=map.Sky.energy;
		auto eSkyt = createEntity3D();
		eSkyt.castShadow = false;
		eSkyt.material = matSkyt;
		auto mesht=New!Mesh(assetManager);
		mesht.vertices=New!(Vector3f[])(2*(map.Sky.numSegs+1));
		mesht.texcoords=New!(Vector2f[])(2*(map.Sky.numSegs+1));
		mesht.indices=New!(uint[3][])(2*map.Sky.numSegs);
		foreach(i;0..map.Sky.numSegs+1){
			auto angle=2*PI*i/map.Sky.numSegs, ca=cos(angle), sa=sin(angle);
			mesht.vertices[2*i]=Vector3f(0.5*ca,0.5*sa,0)*map.Sky.scaling;
			mesht.vertices[2*i+1]=Vector3f(0.5*ca,0.5*sa,map.Sky.skyZ)*map.Sky.scaling;
			auto txc=cast(float)i*map.Sky.numTextureRepeats/map.Sky.numSegs;
			mesht.texcoords[2*i]=Vector2f(txc,1);
			mesht.texcoords[2*i+1]=Vector2f(txc,0);
		}
		foreach(i;0..map.Sky.numSegs){
			mesht.indices[2*i]=[2*i,2*i+1,2*(i+1)];
			mesht.indices[2*i+1]=[2*(i+1),2*i+1,2*(i+1)+1];
		}
		mesht.generateNormals();
		mesht.dataReady=true;
		mesht.prepareVAO();
		eSkyt.drawable = mesht;
		eSkyt.position=Vector3f(x,y,map.Sky.dZ*map.Sky.scaling+1);
		eSkyt.updateTransformation();

		auto matSun = createMaterial(sacSunMaterialBackend);
		matSun.diffuse=map.textures[260];
		matSun.blending=Transparent;
		matSun.energy=25.0f*map.Sky.energy;
		auto eSun = createEntity3D();
		eSun.castShadow = false;
		eSun.material = matSun;
		auto meshsu=New!Mesh(assetManager);
		meshsu.vertices=New!(Vector3f[])(4);
		meshsu.texcoords=New!(Vector2f[])(4);
		meshsu.indices=New!(uint[3][])(2);
		copy(iota(4).map!(i=>Vector3f((-0.5+(i==1||i==2))*0.25,(-0.5+(i==2||i==3))*0.25,map.Sky.skyZ)*map.Sky.scaling),meshsu.vertices);
		copy(iota(4).map!(i=>Vector2f((i==1||i==2),(i==2||i==3))),meshsu.texcoords);
		meshsu.indices[0]=[0,2,1];
		meshsu.indices[1]=[0,3,2];
		meshsu.generateNormals();
		meshsu.dataReady=true;
		meshsu.prepareVAO();
		eSun.drawable=meshsu;
		eSun.position=Vector3f(x,y,map.Sky.dZ*map.Sky.scaling+1);
		eSun.updateTransformation();

		auto matSky = createMaterial(sacSkyMaterialBackend);
		matSky.diffuse=map.textures[257];
		matSky.blending=Transparent;
		matSky.energy=map.Sky.energy;
		matSky.transparency=envi.maxAlphaFloat;
		auto eSky = createEntity3D();
		eSky.castShadow = false;
		eSky.material = matSky;
		auto meshs=New!Mesh(assetManager);
		meshs.vertices=New!(Vector3f[])(4);
		meshs.texcoords=New!(Vector2f[])(4);
		meshs.indices=New!(uint[3][])(2);
		copy(iota(4).map!(i=>Vector3f(-0.5+(i==1||i==2),-0.5+(i==2||i==3),map.Sky.skyZ*map.Sky.relCloudLoc)*map.Sky.scaling),meshs.vertices);
		copy(iota(4).map!(i=>Vector2f(4*(i==1||i==2),4*(i==2||i==3))),meshs.texcoords);
		meshs.indices[0]=[0,2,1];
		meshs.indices[1]=[0,3,2];
		meshs.generateNormals();
		meshs.dataReady=true;
		meshs.prepareVAO();
		eSky.drawable=meshs;
		eSky.position=Vector3f(x,y,map.Sky.dZ*map.Sky.scaling+1);
		eSky.updateTransformation();

		auto matUndr = createMaterial(shadelessMaterialBackend);
		matUndr.diffuse=map.textures[261];
		matUndr.blending=Transparent;
		matUndr.energy=map.Sky.energy;
		auto eUndr = createEntity3D();
		eUndr.castShadow = false;
		eUndr.material = matUndr;
		auto meshu=New!Mesh(assetManager);
		meshu.vertices=New!(Vector3f[])(4);
		meshu.texcoords=New!(Vector2f[])(4);
		meshu.indices=New!(uint[3][])(2);
		copy(iota(4).map!(i=>Vector3f((-0.5+(i==1||i==2)),(-0.5+(i==2||i==3)),map.Sky.undrZ)*map.Sky.scaling),meshu.vertices);
		copy(iota(4).map!(i=>Vector2f((i==1||i==2),(i==2||i==3))),meshu.texcoords);
		meshu.indices[0]=[0,1,2];
		meshu.indices[1]=[0,2,3];
		meshu.generateNormals();
		meshu.dataReady=true;
		meshu.prepareVAO();
		eUndr.drawable=meshu;
		eUndr.position=Vector3f(x,y,map.Sky.dZ*map.Sky.scaling+1);
		eUndr.updateTransformation();
		skyEntities=[eUndr,eSkyb,eSkyt,eSky,eSun];
	}

	void rotateSky(Quaternionf rotation){
		foreach(e;skyEntities[0..3]){
			e.rotation=rotation;
			e.updateTransformation();
		}
	}

	void setupEnvironment(SacMap!DagonBackend map){
		auto env=environment;
		auto envi=&map.envi;
		//writeln(envi.sunDirectStrength," ",envi.sunAmbientStrength);
		env.sunEnergy=12.0f*(envi.sunDirectStrength+envi.sunAmbientStrength+max(0,7*log(envi.sunAmbientStrength)/log(2)));
		Color4f fixColor(Color4f sacColor){
			return Color4f(1,1,1,1)*0.2+sacColor*0.8;
		}
		//env.ambientConstant = fixColor(Color4f(envi.ambientRed*ambi,envi.ambientGreen*ambi,envi.ambientBlue*ambi,1.0f));
		auto ambi=envi.sunAmbientStrength;
		env.ambientConstant = fixColor(Color4f(envi.sunColorRed/255.0f*ambi,envi.sunColorGreen/255.0f*ambi,envi.sunColorBlue/255.0f*ambi,1.0f));
		env.backgroundColor = Color4f(envi.skyRed/255.0f,envi.skyGreen/255.0f,envi.skyBlue/255.0f,1.0f);
		// envi.minAlphaInt, envi.maxAlphaInt, envi.minAlphaFloat ?
		// envi.maxAlphaFloat used for sky alpha
		// sky_, skyt, skyb, sun_, undr used above
		// envi.shadowStrength ?
		auto sunDirection=Vector3f(envi.sunDirectionX,envi.sunDirectionY,envi.sunDirectionZ);
		sunDirection.z=abs(sunDirection.z); // TODO: support something like the effect you get in Sacrifice when setting sun direction from below
		//sunDirection.z=max(0.7,sunDirection.z);
		//sunDirection=sunDirection.normalized(); // TODO: why are sun directions in standard maps so extreme?
		env.sunRotation=rotationBetween(Vector3f(0,0,1),sunDirection);
		//env.sunColor=fixColor(Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f));
		//env.sunColor=Color4f(envi.ambientRed/255.0f,envi.ambientGreen/255.0f,envi.ambientBlue/255.0f,1.0f);
		// TODO: figure this out
		env.sunColor=(exp(envi.sunDirectStrength)*Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f)+exp(4*min(10,envi.sunAmbientStrength^^10))*Color4f(envi.ambientRed/255.0f,envi.ambientGreen/255.0f,envi.ambientBlue/255.0f,1.0f))/(exp(envi.sunDirectStrength)+exp(4*min(10,envi.sunAmbientStrength^^10)));
		/+if(envi.sunAmbientStrength>=envi.sunDirectStrength){
			env.sunColor=(exp(envi.sunDirectStrength)*Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f)+exp(4*envi.sunAmbientStrength)*Color4f(envi.ambientRed/255.0f,envi.ambientGreen/255.0f,envi.ambientBlue/255.0f,1.0f))/(exp(envi.sunDirectStrength)+exp(4*envi.sunAmbientStrength));
		}else{
			env.sunColor=(exp(4*envi.sunDirectStrength)*Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f)+exp(envi.sunAmbientStrength)*Color4f(envi.ambientRed/255.0f,envi.ambientGreen/255.0f,envi.ambientBlue/255.0f,1.0f))/(exp(4*envi.sunDirectStrength)+exp(envi.sunAmbientStrength));
		}+/
		// envi.sunFullbrightRed, envi.sunFullbrightGreen, envi.sunFullbrightBlue?
		// landscapeSpecularity, specularityRed, specularityGreen, specularityBlue and
		// landscapeGlossiness used for terrain material.
		//env.atmosphericFog=true;
		env.fogColor=Color4f(envi.fogRed/255.0f,envi.fogGreen/255.0f,envi.fogBlue/255.0f,1.0f);
		// fogType ?
		//env.fogStart=envi.fogNearZ;
		//env.fogEnd=envi.fogFarZ;
		// fogDensity?
	}

	void createEntities(GameState!DagonBackend state,bool sky=true){
		createEntities(state.map);
		state.current.each!((obj){
			createEntities(obj.sacObject,obj.position,obj.rotation);
		});
	}

	void createEntities(SacMap!DagonBackend map,bool sky=true){
		setupEnvironment(map);
		if(sky) createSky(map);
		foreach(i,mesh;map.meshes){
			if(!mesh) continue;
			auto obj=createEntity3D();
			obj.drawable = mesh;
			obj.position = Vector3f(0, 0, 0);
			obj.updateTransformation();
			auto mat=createMaterial(terrainMaterialBackend);
			assert(!!map.textures[i]);
			mat.diffuse=map.textures[i];
			if(i<map.dti.length){
				assert(!!map.details[map.dti[i]]);
				mat.detail=map.details[map.dti[i]];
			}else mat.detail=0;
			mat.color=map.color;
			auto specu=map.envi.landscapeSpecularity;
			mat.specular=Color4f(specu*map.envi.specularityRed/255.0f,specu*map.envi.specularityGreen/255.0f,specu*map.envi.specularityBlue/255.0f);
			//mat.roughness=1.0f-envi.landscapeGlossiness;
			mat.roughness=1.0f;
			mat.metallic=0.0f;
			mat.emission=map.textures[i];
			mat.energy=0.05;
			obj.material=mat;
			obj.shadowMaterial=shadowMap.sm;
		}
	}

	void createEntities(SacObject!DagonBackend sobj,Vector3f position,Quaternionf rotation){
		foreach(i;0..sobj.isSaxs?sobj.saxsi.meshes.length:sobj.meshes.length){
			auto obj=createEntity3D();
			obj.drawable = sobj.isSaxs?cast(Drawable)sobj.saxsi.meshes[i]:cast(Drawable)sobj.meshes[i];
			obj.position = position;
			obj.rotation = rotation;
			obj.updateTransformation();
			GenericMaterial mat;
			if(i==sobj.sunBeamPart){
				mat=createMaterial(gpuSkinning&&sobj.isSaxs?shadelessBoneMaterialBackend:shadelessMaterialBackend);
				obj.castShadow=false;
				mat.depthWrite=false;
				mat.blending=Additive;
				mat.energy=4.0f;
			}else if(i==sobj.locustWingPart){
				mat=createMaterial(gpuSkinning&&sobj.isSaxs?shadelessBoneMaterialBackend:shadelessMaterialBackend);
				obj.castShadow=false;
				mat.depthWrite=false;
				mat.blending=Additive;
				mat.energy=20.0f;
			}else if(i==sobj.transparentShinyPart){
				mat=createMaterial(gpuSkinning&&sobj.isSaxs?shadelessBoneMaterialBackend:shadelessMaterialBackend);
				mat.depthWrite=false;
				mat.blending=Transparent;
				mat.transparency=0.5f;
				mat.energy=20.0f;
			}else{
				mat=createMaterial(gpuSkinning&&sobj.isSaxs?boneMaterialBackend:defaultMaterialBackend);
			}
			auto diffuse=sobj.isSaxs?sobj.saxsi.saxs.bodyParts[i].texture:sobj.textures[i];
			if(diffuse !is null) mat.diffuse=diffuse;
			mat.specular=Color4f(0,0,0,1);
			obj.material=mat;
			if(obj.castShadow){
				auto shadowMat=createMaterial(gpuSkinning&&sobj.isSaxs?shadowMap.bsb:shadowMap.sb);
				if(diffuse !is null) shadowMat.diffuse=diffuse;
				obj.shadowMaterial=shadowMat;
			}
			//entities[sobj].insertBack(obj);
		}
	}

	void setState(GameState!DagonBackend state)in{
		assert(this.state is null);
	}do{
		this.state=state;
		createEntities(state);
	}

	void addObject(SacObject!DagonBackend obj,Vector3f position,Quaternionf rotation){
		createEntities(obj,position,rotation);
		sacs.insertBack(obj);
	}

	override void onAllocate(){
		super.onAllocate();

		//view = New!Freeview(eventManager, assetManager);
		auto eCamera = createEntity3D();
		eCamera.position = Vector3f(1270.0f, 1270.0f, 2.0f);
		fpview = New!FirstPersonView2(eventManager, eCamera, assetManager);
		fpview.active = true;
		view = fpview;
		//auto mat = createMaterial();
		//mat.diffuse = Color4f(0.2, 0.2, 0.2, 0.2);
		//mat.diffuse=txta;

		/+auto obj = createEntity3D();
		 obj.drawable = aOBJ.mesh;
		 obj.material = mat;
		 obj.position = Vector3f(0, 1, 0);
		 obj.rotation = rotationQuaternion(Axis.x,-cast(float)PI/2);+/

		if(!state){
			auto sky=createSky();
			sky.rotation=rotationQuaternion(Axis.z,cast(float)PI)*
				rotationQuaternion(Axis.x,cast(float)(PI/2));
		}
		/+auto ePlane = createEntity3D();
		 ePlane.drawable = New!ShapePlane(10, 10, 1, assetManager);
		 auto matGround = createMaterial();
		 //matGround.diffuse = ;
		 ePlane.material=matGround;+/
		//sortEntities(entities3D);
		//sortEntities(entities2D);
	}
	float speed = 100.0f;
	void cameraControl(double dt){
		Vector3f forward = fpview.camera.worldTrans.forward;
		Vector3f right = fpview.camera.worldTrans.right;
		Vector3f dir = Vector3f(0, 0, 0);
		if(eventManager.keyPressed[KEY_X]) dir += Vector3f(1,0,0);
		if(eventManager.keyPressed[KEY_Y]) dir += Vector3f(0,1,0);
		if(eventManager.keyPressed[KEY_Z]) dir += Vector3f(0,0,1);
		if(eventManager.keyPressed[KEY_E]) dir += -forward;
		if(eventManager.keyPressed[KEY_D]) dir += forward;
		if(eventManager.keyPressed[KEY_S]) dir += -right;
		if(eventManager.keyPressed[KEY_F]) dir += right;
		if(eventManager.keyPressed[KEY_O]) speed = 100.0f;
		if(eventManager.keyPressed[KEY_P]) speed = 1000.0f;
		if(eventManager.keyPressed[KEY_K]) fpview.active=false;
		if(eventManager.keyPressed[KEY_L]) fpview.active=true;
		fpview.camera.position += dir.normalized * speed * dt;
		if(state && state.isOnGround(fpview.camera.position)){
			fpview.camera.position.z=max(fpview.camera.position.z, state.getGroundHeight(fpview.camera.position));
		}
	}

	double totalTime=0;
	override void onLogicsUpdate(double dt){
		//writeln(DagonBackend.getTotalGPUMemory()," ",DagonBackend.getAvailableGPUMemory());
		//writeln(eventManager.fps);
		cameraControl(dt);
		totalTime+=dt;
		if(skyEntities.length){
			sacSkyMaterialBackend.sunLoc = state.sunSkyRelLoc(fpview.camera.position);
			sacSkyMaterialBackend.cloudOffset+=dt*1.0f/32.0f*Vector2f(1.0f,-1.0f);
			sacSkyMaterialBackend.cloudOffset.x=fmod(sacSkyMaterialBackend.cloudOffset.x,1.0f);
			sacSkyMaterialBackend.cloudOffset.y=fmod(sacSkyMaterialBackend.cloudOffset.y,1.0f);
			rotateSky(rotationQuaternion(Axis.z,cast(float)(2*PI/512.0f*totalTime)));
		}
		foreach(sac;sacs.data){
			auto frame=totalTime*sac.animFPS;
			if(sac.numFrames) sac.setFrame(cast(size_t)(frame%sac.numFrames));
		}
	}
}

class MyApplication: SceneApplication{
	this(Options options){
		super(1280, 720, false, "SacEngine", []);
		SacScene scene = New!SacScene(sceneManager, options);
		sceneManager.addScene(scene, "Sacrifice");
		sceneManager.goToScene("Sacrifice");
	}
}

struct DagonBackend{
	MyApplication app;
	@property SacScene scene(){
		auto r=cast(SacScene)app.sceneManager.currentScene;
		assert(!!r);
		return r;
	}
	this(Options options){
		app = New!MyApplication(options);
	}
	void setState(GameState!DagonBackend state){
		scene.setState(state);
	}
	void addObject(SacObject!DagonBackend obj,Vector3f position,Quaternionf rotation){
		scene.addObject(obj,position,rotation);
	}
	void run(){
		app.run();
	}
	~this(){ Delete(app); }
static:
	alias Texture=.Texture;
	alias Mesh=.Mesh;
	alias BoneMesh=.BoneMesh;
	alias TerrainMesh=.TerrainMesh;

	Texture makeTexture(SuperImage i,bool mirroredRepeat=true){
		auto repeat=mirroredRepeat?GL_MIRRORED_REPEAT:GL_REPEAT;
		auto texture=New!Texture(null); // TODO: set owner
		texture.image=i;
		texture.createFromImage(texture.image,true,repeat);
		return texture;
	}

	Mesh makeMesh(size_t numVertices,size_t numFaces){
		auto m=new Mesh(null); // TODO: set owner
		m.vertices=New!(Vector3f[])(numVertices);
		m.normals=New!(Vector3f[])(numVertices);
		m.texcoords=New!(Vector2f[])(numVertices);
		m.indices=New!(uint[3][])(numFaces);
		return m;
	}
	void finalizeMesh(Mesh mesh){
		mesh.dataReady=true;
		mesh.prepareVAO();
	}
	BoneMesh makeBoneMesh(size_t numVertices, size_t numFaces){
		auto m=new BoneMesh(null); // TODO: set owner
		foreach(j;0..3){
			m.vertices[j]=New!(Vector3f[])(numVertices);
			m.vertices[j][]=Vector3f(0,0,0);
		}
		m.normals=New!(Vector3f[])(numVertices);
		m.texcoords=New!(Vector2f[])(numVertices);
		m.boneIndices=New!(uint[3][])(numVertices);
		m.weights=New!(Vector3f[])(numVertices);
		m.weights[]=Vector3f(0,0,0);
		m.indices=New!(uint[3][])(numFaces);
		return m;
	}
	void finalizeBoneMesh(BoneMesh mesh){
		mesh.dataReady=true;
		mesh.prepareVAO();
	}
	TerrainMesh makeTerrainMesh(size_t numVertices, size_t numFaces){
		auto m=new TerrainMesh(null); // TODO: set owner
		m.vertices=New!(Vector3f[])(numVertices);
		m.normals=New!(Vector3f[])(numVertices);
		m.texcoords=New!(Vector2f[])(numVertices);
		m.coords=New!(Vector2f[])(numVertices);
		m.indices=New!(uint[3][])(numFaces);
		return m;
	}
	void finalizeTerrainMesh(TerrainMesh mesh){
		mesh.dataReady=true;
		mesh.prepareVAO();
	}

	enum GL_GPU_MEM_INFO_TOTAL_AVAILABLE_MEM_NVX=0x9048;
	enum GL_GPU_MEM_INFO_CURRENT_AVAILABLE_MEM_NVX=0x9049;

	GLint getTotalGPUMemory(){
		GLint total_mem_kb = 0;
		glGetIntegerv(GL_GPU_MEM_INFO_TOTAL_AVAILABLE_MEM_NVX,
		              &total_mem_kb);
		return total_mem_kb;
	}

	GLint getAvailableGPUMemory(){
		GLint cur_avail_mem_kb = 0;
		glGetIntegerv(GL_GPU_MEM_INFO_CURRENT_AVAILABLE_MEM_NVX,
		              &cur_avail_mem_kb);
		return cur_avail_mem_kb;
	}
}
