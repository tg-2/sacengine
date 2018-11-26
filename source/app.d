import dagon;
import std.math;
import std.stdio;
import std.string;
import std.exception;
import std.algorithm, std.range;

import sacobject, sacmap;

class TestScene: Scene{
	//OBJAsset aOBJ;
	//Texture txta;
	string[] args;
	this(SceneManager smngr, string[] args){
		super(smngr);
		this.args=args;
		this.shadowMapResolution=8192;
		//this.shadowMapResolution=2048;
		//this.shadowMapResolution=512;
	}
	DynamicArray!SacObject sacs;
	FirstPersonView2 fpview;
	override void onAssetsRequest(){
		//aOBJ = addOBJAsset("../jman.obj");
		//txta = New!Texture(null);// TODO: why?
		//txta.image = loadTXTR("extracted/jamesmod/JMOD.WAD!/modl.FLDR/jman.MRMC/M001.TXTR");
		//txta.createFromImage(txta.image);
	}
	SacMap map;
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

		foreach(ref i;1..args.length){
			string anim="";
			if(i+1<args.length&&args[i+1].endsWith(".SXSK"))
				anim=args[i+1];
			if(args[i].endsWith(".HMAP")){
				enforce(map is null);
				map=New!SacMap(args[i]);
				map.createEntities(this);
			}else{
				auto sac=New!SacObject(this, args[i], args[i].endsWith(".SXMD")?2e-3:1, anim);
				sac.position=Vector3f(1270.0f, 1270.0f, 0.0f);
				if(map && map.isOnGround(sac.position))
					sac.position.z=map.getGroundHeight(sac.position);
				sac.createEntities(this);
				sacs.insertBack(sac);
			}
			if(i+1<args.length&&args[i+1].endsWith(".SXSK"))
				i+=1;
		}

		if(!map){
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
		if(map && map.isOnGround(fpview.camera.position)){
			fpview.camera.position.z=max(fpview.camera.position.z, map.getGroundHeight(fpview.camera.position));
		}
	}

	double totalTime=0;
	override void onLogicsUpdate(double dt){
		writeln(eventManager.fps);
		cameraControl(dt);
		totalTime+=dt;
		if(map){
			sacSkyMaterialBackend.sunLoc = map.sunSkyRelLoc(fpview.camera.position);
			sacSkyMaterialBackend.cloudOffset+=dt*1.0f/32.0f*Vector2f(1.0f,-1.0f);
			sacSkyMaterialBackend.cloudOffset.x=fmod(sacSkyMaterialBackend.cloudOffset.x,1.0f);
			sacSkyMaterialBackend.cloudOffset.y=fmod(sacSkyMaterialBackend.cloudOffset.y,1.0f);
			map.rotateSky(rotationQuaternion(Axis.z,cast(float)(2*PI/512.0f*totalTime)));
		}
		foreach(sac;chain(sacs.data,map?map.ntts:[])){
			auto frame=totalTime*sac.animFPS;
			sac.setFrame(cast(size_t)(frame%sac.numFrames));
		}
	}
}

class MyApplication: SceneApplication{
	this(string[] args){
		super(1280, 720, false, "SacEngine", args);
		TestScene test = New!TestScene(sceneManager, args);
		sceneManager.addScene(test, "Sacrifice");
		sceneManager.goToScene("Sacrifice");
	}
}

void main(string[] args){
	import core.memory;
	GC.disable(); // TODO: figure out where GC memory is used incorrectly
	if(args.length==1) args~="extracted/jamesmod/JMOD.WAD!/modl.FLDR/jman.MRMC/jman.MRMM";
	MyApplication app = New!MyApplication(args);
	app.run();
	Delete(app);
}
