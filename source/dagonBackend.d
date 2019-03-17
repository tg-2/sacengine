import dagon;
import options,util;
import std.math;
import std.stdio;
import std.algorithm, std.range, std.exception, std.typecons;

import sacobject, nttData, sacmap, state;
import sxsk : gpuSkinning;

final class SacScene: Scene{
	//OBJAsset aOBJ;
	//Texture txta;
	Options options;
	this(SceneManager smngr, Options options){
		super(options.width, options.height, options.aspectDistortion, smngr);
		this.shadowMapResolution=options.shadowMapResolution;
		this.options=options;
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
		matSkyb.diffuse=map.textures[skybIndex];
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
		matSkyt.diffuse=map.textures[skytIndex];
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
		matSun.diffuse=map.textures[sunIndex];
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
		matSky.diffuse=map.textures[skyIndex];
		matSky.blending=Transparent;
		matSky.energy=map.Sky.energy;
		matSky.transparency=min(envi.maxAlphaFloat,1.0f);
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
		matUndr.diffuse=map.textures[undrIndex];
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
	SacSoul!DagonBackend sacSoul;
	void createSouls(){
		sacSoul=new SacSoul!DagonBackend();
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
		env.sunEnergy=min(12.0f*envi.sunDirectStrength,30.0f);
		Color4f fixColor(Color4f sacColor){
			return Color4f(0,0.3,1,1)*0.2+sacColor*0.8;
		}
		//env.ambientConstant = fixColor(Color4f(envi.ambientRed*ambi,envi.ambientGreen*ambi,envi.ambientBlue*ambi,1.0f));
		auto ambi=min(envi.sunAmbientStrength,2.0f);
		//auto ambi=1.5f*envi.sunAmbientStrength;
		//env.ambientConstant = fixColor(Color4f(envi.sunColorRed/255.0f*ambi,envi.sunColorGreen/255.0f*ambi,envi.sunColorBlue/255.0f*ambi,1.0f));
		env.ambientConstant = ambi*Color4f(envi.ambientRed/255.0f,envi.ambientGreen/255.0f,envi.ambientBlue/255.0f,1.0f);
		env.backgroundColor = Color4f(envi.skyRed/255.0f,envi.skyGreen/255.0f,envi.skyBlue/255.0f,1.0f);
		// envi.minAlphaInt, envi.maxAlphaInt, envi.minAlphaFloat ?
		// envi.maxAlphaFloat used for sky alpha
		// sky_, skyt, skyb, sun_, undr used above
		auto sunDirection=Vector3f(envi.sunDirectionX,envi.sunDirectionY,envi.sunDirectionZ);
		//sunDirection.z=abs(sunDirection.z);
		//sunDirection.z=max(0.7,sunDirection.z);
		//sunDirection=sunDirection.normalized(); // TODO: why are sun directions in standard maps so extreme?
		env.sunRotation=rotationBetween(Vector3f(0,0,1),sunDirection);
		//env.sunColor=fixColor(Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f));
		//env.sunColor=Color4f(envi.ambientRed/255.0f,envi.ambientGreen/255.0f,envi.ambientBlue/255.0f,1.0f);
		//env.sunColor=fixColor(Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f));
		//env.sunColor=Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f);
		/+env.sunColor=0.5f*Color4f(envi.ambientRed/255.0f,envi.ambientGreen/255.0f,envi.ambientBlue/255.0f,1.0f)+
			0.5f*Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f);+/
		env.sunColor=envi.sunAmbientStrength/(envi.sunDirectStrength+envi.sunAmbientStrength)*Color4f(envi.ambientRed/255.0f,envi.ambientGreen/255.0f,envi.ambientBlue/255.0f,1.0f)+
			envi.sunDirectStrength/(envi.sunDirectStrength+envi.sunAmbientStrength)*Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f);
		// TODO: figure this out
		/+if(exp(envi.sunDirectStrength)==float.infinity)
			env.sunColor=Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f);
		else
			//env.sunColor=(exp(envi.sunDirectStrength)*Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f)+exp(4*min(10,envi.sunAmbientStrength^^10))*Color4f(envi.ambientRed/255.0f,envi.ambientGreen/255.0f,envi.ambientBlue/255.0f,1.0f))/(exp(envi.sunDirectStrength)+exp(4*min(10,envi.sunAmbientStrength^^10)));
			env.sunColor=(exp(envi.sunDirectStrength)*Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f)+0.5f*exp(envi.sunAmbientStrength)*Color4f(envi.ambientRed/255.0f,envi.ambientGreen/255.0f,envi.ambientBlue/255.0f,1.0f))/(exp(envi.sunDirectStrength)+0.5f*exp(envi.sunAmbientStrength));+/
		/+if(envi.sunAmbientStrength>=envi.sunDirectStrength){
			env.sunColor=(exp(envi.sunDirectStrength)*Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f)+exp(4*envi.sunAmbientStrength)*Color4f(envi.ambientRed/255.0f,envi.ambientGreen/255.0f,envi.ambientBlue/255.0f,1.0f))/(exp(envi.sunDirectStrength)+exp(4*envi.sunAmbientStrength));
		}else{
			env.sunColor=(exp(4*envi.sunDirectStrength)*Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f)+exp(envi.sunAmbientStrength)*Color4f(envi.ambientRed/255.0f,envi.ambientGreen/255.0f,envi.ambientBlue/255.0f,1.0f))/(exp(4*envi.sunDirectStrength)+exp(envi.sunAmbientStrength));
		}+/
		// envi.sunFullbrightRed, envi.sunFullbrightGreen, envi.sunFullbrightBlue?
		// landscapeSpecularity, specularityRed, specularityGreen, specularityBlue and
		// landscapeGlossiness used for terrain material.
		//env.atmosphericFog=true;
		shadowMap.shadowColor=Color4f(envi.ambientRed/255.0f,envi.ambientGreen/255.0f,envi.ambientBlue/255.0f,1.0f);
		shadowMap.shadowBrightness=1.0f-envi.shadowStrength;
		env.fogColor=Color4f(envi.fogRed/255.0f,envi.fogGreen/255.0f,envi.fogBlue/255.0f,1.0f);
		// fogType ?
		if(options.enableFog){
			env.fogStart=envi.fogNearZ;
			env.fogEnd=envi.fogFarZ;
		}
		// fogDensity?
	}

	final void renderMap(RenderingContext* rc){
		auto map=state.current.map;
		rc.layer=1;
		rc.modelMatrix=Matrix4x4f.identity();
		rc.invModelMatrix=Matrix4x4f.identity();
		rc.prevModelViewProjMatrix=Matrix4x4f.identity(); // TODO: get rid of this?
		rc.modelViewMatrix=rc.viewMatrix*rc.modelMatrix;
		rc.blurModelViewProjMatrix=rc.projectionMatrix*rc.modelViewMatrix;
		GenericMaterial mat;
		if(!rc.shadowMode){
			mat=map.material; // TODO: get rid of this completely?
			mat.bind(rc);
			terrainMaterialBackend.bindColor(map.color);
		}else{
			mat=shadowMap.sm;
			mat.bind(rc);
		}
		foreach(i,mesh;map.meshes){
			if(!mesh) continue;
			if(!rc.shadowMode){
				terrainMaterialBackend.bindDiffuse(map.textures[i]);
				if(i<map.dti.length){
					assert(!!map.details[map.dti[i]]);
					terrainMaterialBackend.bindDetail(map.details[map.dti[i]]);
				}else terrainMaterialBackend.bindDetail(null);
				terrainMaterialBackend.bindEmission(map.textures[i]);
			}
			mesh.render(rc);
		}
		//mat.unbind(rc); // TODO: needed?
	}

	final void renderNTTs(RenderMode mode)(RenderingContext* rc){
		static void render(T)(ref T objects,bool enableWidgets,SacScene scene,RenderingContext* rc){ // TODO: why does this need to be static? DMD bug?
			static if(is(typeof(objects.sacObject))){
				auto sacObject=objects.sacObject;
				enum isMoving=is(T==MovingObjects!(DagonBackend, RenderMode.opaque))||is(T==MovingObjects!(DagonBackend, RenderMode.transparent));
				static if(is(T==MovingObjects!(DagonBackend, RenderMode.opaque))){
					auto materials=rc.shadowMode?sacObject.shadowMaterials:sacObject.materials;
				}else{
					auto materials=rc.shadowMode?sacObject.shadowMaterials:sacObject.materials; // TODO: add transparency here
				}
				foreach(i;0..materials.length){
					auto material=materials[i];
					if(!material) continue;
					auto blending=("blending" in material.inputs).asInteger;
					if((mode==RenderMode.transparent)!=(blending==Additive||blending==Transparent)) continue;
					if(rc.shadowMode&&blending==Additive) continue;
					material.bind(rc);
					scope(success) material.unbind(rc);
					static if(isMoving){
						auto mesh=sacObject.saxsi.meshes[i];
						foreach(j;0..objects.length){ // TODO: use instanced rendering instead
							material.backend.setTransformation(objects.positions[j], objects.rotations[j], rc);
							auto id=objects.ids[j];
							material.backend.setInformation(Vector4f(2.0f,id>>16,id&((1<<16)-1),1.0f));
							// TODO: interpolate animations to get 60 FPS?
							sacObject.setFrame(objects.animationStates[j],objects.frames[j]/updateAnimFactor);
							mesh.render(rc);
						}
					}else{
						static if(is(T==FixedObjects!DagonBackend)) if(!enableWidgets) return;
						material.backend.setInformation(Vector4f(0.0f,0.0f,0.0f,0.0f));
						auto mesh=sacObject.meshes[i];
						foreach(j;0..objects.length){
							material.backend.setTransformation(objects.positions[j], objects.rotations[j], rc);
							static if(is(T==StaticObjects!DagonBackend)){
								auto id=objects.ids[j];
								material.backend.setInformation(Vector4f(2.0f,id>>16,id&((1<<16)-1),1.0f));
							}
							mesh.render(rc);
						}
					}
				}
			}else static if(is(T==Souls!DagonBackend)){
				static if(mode==RenderMode.transparent){
					if(rc.shadowMode) return;
					auto sacSoul=scene.sacSoul;
					auto material=sacSoul.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					foreach(j;0..objects.length){
						// TODO: determine soul color based on side
						auto soul=objects[j];
						auto mesh=sacSoul.getMesh(soul.color(scene.renderSide,scene.state.current),soul.frame/updateAnimFactor); // TODO: do in shader?
						auto id=soul.id;
						material.backend.setInformation(Vector4f(3.0f,id>>16,id&((1<<16)-1),1.0f));
						if(objects[j].number==1){
							material.backend.setSpriteTransformationScaled(soul.position+soul.scaling*Vector3f(0.0f,0.0f,1.25f*sacSoul.soulHeight),soul.scaling,rc);
							mesh.render(rc);
						}else{
							auto number=objects[j].number;
							auto soulScaling=max(0.5f,1.0f-0.05f*number);
							auto radius=soul.scaling*sacSoul.soulRadius;
							if(number<=3) radius*=0.3*number;
							foreach(k;0..number){
								auto position=soul.position+rotate(facingQuaternion(objects[j].facing+2*PI*k/number), Vector3f(0.0f,radius,0.0f));
								material.backend.setSpriteTransformationScaled(position+soul.scaling*Vector3f(0.0f,0.0f,1.25f*sacSoul.soulHeight),soul.scaling*soulScaling,rc);
								mesh.render(rc);
							}
						}
					}
				}
			}else static if(is(T==Buildings!DagonBackend)){
				// do nothing
			}else static if(is(T==Particles!DagonBackend)){
				static if(mode==RenderMode.transparent){
					if(rc.shadowMode) return; // TODO: particle shadows?
					auto sacParticle=objects.sacParticle;
					if(!sacParticle) return; // TODO: get rid of this?
					auto material=sacParticle.material;
					material.bind(rc);
					material.backend.setInformation(Vector4f(0.0f,0.0f,0.0f,0.0f));
					scope(success) material.unbind(rc);
					foreach(j;0..objects.length){
						auto mesh=sacParticle.getMesh(objects.frames[j]/updateAnimFactor); // TODO: do in shader?
						material.backend.setSpriteTransformationScaled(objects.positions[j],sacParticle.getScale(objects.lifetimes[j]),rc);
						material.backend.setAlpha(sacParticle.getAlpha(objects.lifetimes[j]));
						mesh.render(rc);
					}
				}
			}else static assert(0);
		}
		state.current.eachByType!render(options.enableWidgets,this,rc);
	}

	static void renderBox(Vector3f[2] sl,bool wireframe,RenderingContext* rc){
		auto small=sl[0],large=sl[1];
		Vector3f[8] box=[Vector3f(small[0],small[1],small[2]),Vector3f(large[0],small[1],small[2]),
		                 Vector3f(large[0],large[1],small[2]),Vector3f(small[0],large[1],small[2]),
		                 Vector3f(small[0],small[1],large[2]),Vector3f(large[0],small[1],large[2]),
		                 Vector3f(large[0],large[1],large[2]),Vector3f(small[0],large[1],large[2])];
		if(wireframe){
			glPolygonMode(GL_FRONT_AND_BACK,GL_LINE);
			glDisable(GL_CULL_FACE);
		}
		auto mesh=New!Mesh(null);
		scope(exit) Delete(mesh);
		mesh.vertices=New!(Vector3f[])(8);
		mesh.vertices[]=box[];
		//foreach(ref x;mesh.vertices) x*=10;
		mesh.indices=New!(uint[3][])(6*2);
		mesh.indices[0]=[0,2,1];
		mesh.indices[1]=[2,0,3];
		mesh.indices[2]=[4,5,6];
		mesh.indices[3]=[6,7,4];
		mesh.indices[4]=[0,1,5];
		mesh.indices[5]=[0,5,4];
		mesh.indices[6]=[1,2,6];
		mesh.indices[7]=[6,5,1];
		mesh.indices[8]=[2,3,7];
		mesh.indices[9]=[7,6,2];
		mesh.indices[10]=[3,0,4];
		mesh.indices[11]=[4,7,3];
		mesh.texcoords=New!(Vector2f[])(mesh.vertices.length);
		mesh.texcoords[]=Vector2f(0,0);
		mesh.normals=New!(Vector3f[])(mesh.vertices.length);
		mesh.generateNormals();
		mesh.dataReady=true;
		mesh.prepareVAO();
		mesh.render(rc);
		if(wireframe){
			glPolygonMode(GL_FRONT_AND_BACK,GL_FILL);
			glEnable(GL_CULL_FACE);
		}
	}
	bool showHitboxes=false;
	GenericMaterial hitboxMaterial=null;
	final void renderHitboxes(RenderingContext* rc){
		static void render(T)(ref T objects,GenericMaterial material,RenderingContext* rc){
			enum isMoving=is(T==MovingObjects!(DagonBackend, RenderMode.opaque))||is(T==MovingObjects!(DagonBackend, RenderMode.transparent));
			static if(isMoving){
				auto sacObject=objects.sacObject;
				foreach(j;0..objects.length){
					material.backend.setTransformation(objects.positions[j], Quaternionf.identity(), rc);
					auto hitbox=sacObject.hitbox(objects.rotations[j],objects.animationStates[j],objects.frames[j]/updateAnimFactor);
					renderBox(hitbox,true,rc);
					auto meleeHitbox=sacObject.meleeHitbox(objects.rotations[j],objects.animationStates[j],objects.frames[j]/updateAnimFactor);
					renderBox(meleeHitbox,true,rc);
					/+foreach(i;1..sacObject.saxsi.saxs.bones.length){
						auto hitbox=sacObject.saxsi.saxs.bones[i].hitbox;
						foreach(ref x;hitbox){
							x=x*sacObject.animations[objects.animationStates[j]].frames[objects.frames[j]/updateAnimFactor].matrices[i];
						}
						Vector3f[8] box=[Vector3f(-1,-1,-1),Vector3f(1,-1,-1),Vector3f(1,1,-1),Vector3f(-1,1,-1),Vector3f(-1,-1,1),Vector3f(1,-1,1),Vector3f(1,1,1),Vector3f(-1,1,1)];
						foreach(curVert;/+0..8+/6..8){
							Vector3f[8] nbox;
							foreach(k;0..8)
								nbox[k]=hitbox[curVert]+(0.05*box[k]);//*(curVert==3?2:1);
							renderBox(nbox,rc);
						}
						/+Vector3f[8] hitbox=[Vector3f(-0.0730702, -0.0556806, 0),
						 Vector3f(0.22243, -0.0556806, 0),
						 Vector3f(-0.0730702, 0.0667194, 0),
						 Vector3f(0.22243, 0.0667194, 0),
						 Vector3f(0, -0.0556806, -0.247969),
						 Vector3f(0, -0.0556806, -0.0355686),
						 Vector3f(0, 0.0667194, -0.247969),
						 Vector3f(0, 0.0667194, -0.0355686)];+/
						//renderBox(hitbox,rc);
					}+/
				}
			}else static if(is(T==StaticObjects!DagonBackend)){
				auto sacObject=objects.sacObject;
				foreach(j;0..objects.length){
					material.backend.setTransformation(objects.positions[j], Quaternionf.identity(), rc);
					foreach(hitbox;sacObject.hitboxes(objects.rotations[j]))
						renderBox(hitbox,true,rc);
				}
			}
		}
		if(!hitboxMaterial){
			hitboxMaterial=createMaterial(shadelessMaterialBackend);
			hitboxMaterial.diffuse=Color4f(1.0f,1.0f,1.0f,1.0f);
		}
		hitboxMaterial.bind(rc); scope(exit) hitboxMaterial.unbind(rc);
		state.current.eachByType!render(hitboxMaterial,rc);
	}

	void renderFrame(Vector2f position,Vector2f size,Color4f color,RenderingContext* rc){
		colorHUDMaterialBackend2.bind(null,rc);
		scope(success) colorHUDMaterialBackend2.unbind(null, rc);
		auto scaling=Vector3f(size.x,size.y,1.0f);
		colorHUDMaterialBackend2.setTransformationScaled(Vector3f(position.x,position.y,0.0f), Quaternionf.identity(), scaling, rc);
		colorHUDMaterialBackend2.setColor(color);
		border.render(rc);
	}

	static Vector2f[2] fixHitbox2dSize(Vector2f[2] position){
		auto center=0.5f*(position[0]+position[1]);
		auto size=position[1]-position[0];
		foreach(k;0..2) size[k]=max(size[k],48.0f);
		return [center-0.5f*size,center+0.5f*size];
	}

	void renderFrame(Vector3f[2] hitbox2d,Color4f color,RenderingContext* rc){
		if(hitbox2d[0].z>1.0f) return;
		Vector2f[2] position=[Vector2f(0.5f*(hitbox2d[0].x+1.0f)*width,0.5f*(1.0f-hitbox2d[1].y)*height),
		                      Vector2f(0.5f*(hitbox2d[1].x+1.0f)*width,0.5f*(1.0f-hitbox2d[0].y)*height)];
		position=fixHitbox2dSize(position);
		auto size=position[1]-position[0];
		renderFrame(position[0],size,color,rc);
		mouse.inHitbox=!mouse.onMinimap&&position[0].x<=mouse.x&&mouse.x<=position[1].x&&
			position[0].y<=mouse.y&&mouse.y<=position[1].y;
	}

	Matrix4f getModelViewProjectionMatrix(Vector3f position,Quaternionf rotation){
		auto modelMatrix=translationMatrix(position)*rotation.toMatrix4x4;
		auto modelViewMatrix=rc3d.viewMatrix*modelMatrix;
		auto modelViewProjectionMatrix=rc3d.projectionMatrix*modelViewMatrix;
		return modelViewProjectionMatrix;
	}

	Matrix4f getSpriteModelViewProjectionMatrix(Vector3f position){
		auto modelViewMatrix=rc3d.viewMatrix*translationMatrix(position)*rc3d.invViewRotationMatrix;
		auto modelViewProjectionMatrix=rc3d.projectionMatrix*modelViewMatrix;
		return modelViewProjectionMatrix;
	}

	void renderTargetFrame(RenderingContext* rc){
		if(!mouse.showFrame) return;
		if(mouse.target.type.among(TargetType.creature,TargetType.building)){
			static void renderHitbox(T)(T obj,SacScene scene,RenderingContext* rc){
				alias B=DagonBackend;
				auto hitbox2d=obj.hitbox2d(scene.getModelViewProjectionMatrix(obj.position,obj.rotation));
				static if(is(T==MovingObject!B)) auto objSide=obj.side;
				else auto objSide=sideFromBuildingId!B(obj.buildingId,scene.state.current);
				auto color=scene.state.current.sides.sideColor(objSide);
				scene.renderFrame(hitbox2d,color,rc);
			}
			state.current.objectById!renderHitbox(mouse.target.id,this,rc);
			}else if(mouse.target.type==TargetType.soul){
			static void renderHitbox(B)(Soul!B soul,SacScene scene,RenderingContext* rc){
				auto hitbox2d=soul.hitbox2d(scene.getSpriteModelViewProjectionMatrix(soul.position+soul.scaling*Vector3f(0.0f,0.0f,1.25f*sacSoul.soulHeight)));
				auto color=soul.color(scene.renderSide,scene.state.current)==SoulColor.blue?blueSoulFrameColor:redSoulFrameColor;
				scene.renderFrame(hitbox2d,color,rc);
			}
			state.current.soulById!renderHitbox(mouse.target.id,this,rc);
		}
	}
	void renderCursor(RenderingContext* rc){
		if(mouse.target.id&&!state.current.isValidId(mouse.target.id)) mouse.target=Target.init;
		mouse.x=eventManager.mouseX;
		mouse.y=eventManager.mouseY;
		mouse.x=max(0,min(mouse.x,width-1));
		mouse.y=max(0,min(mouse.y,height-1));
		auto material=sacCursor.materials[mouse.cursor];
		material.bind(rc);
		scope(success) material.unbind(rc);
		auto size=options.cursorSize;
		auto position=Vector3f(mouse.x-0.5f*size,mouse.y,0);
		auto scaling=Vector3f(size,size,1.0f);
		material.backend.setTransformationScaled(position, Quaternionf.identity(), scaling, rc);
		quad.render(rc);
	}

	@property float hudScaling(){ return height/480.0f; }
	int hudSoulFrame=0;
	void updateHUD(float dt){
		hudSoulFrame+=1;
		if(hudSoulFrame>=sacSoul.numFrames*updateAnimFactor)
			hudSoulFrame=0;
	}
	void renderSelectionRoster(RenderingContext* rc){
		auto material=sacHud.frameMaterial;
		material.bind(rc);
		scope(success) material.unbind(rc);
		auto hudScaling=this.hudScaling;
		auto scaling=Vector3f(128.0f,256.0f,1.0f);
		scaling*=hudScaling;
		auto position=Vector3f(-32.0f*hudScaling,0.5*(height-scaling.y),0);
		material.backend.setTransformationScaled(position, Quaternionf.identity(), scaling, rc);
		selectionRoster.render(rc);
	}
	float minimapRadius(){ return hudScaling*80.0f; }
	bool isOnMinimap(Vector2f position){
		auto radius=minimapRadius;
		auto center=Vector2f(width-radius,height-radius);
		return (position-center).lengthsqr<=radius*radius;
	}
	void updateMinimapTarget(Target target,Vector2f center,Vector2f scaling){
		if(!mouse.onMinimap) return;
		auto topLeft=center-0.5f*scaling;
		auto bottomRight=center+0.5f*scaling;
		if(cast(int)topLeft.x<=mouse.x&&mouse.x<=cast(int)(bottomRight.x+0.5f)
		   && cast(int)topLeft.y<=mouse.y&&mouse.y<=cast(int)(bottomRight.y+0.5f))
			minimapTarget=target;
	}
	void updateMinimapTargetTriangle(Target target,Vector3f[3] triangle){
		if(!mouse.onMinimap) return;
		auto mousePos=Vector3f(mouse.x,mouse.y,0.0f);
		foreach(k;0..3) triangle[k]-=mousePos;
		foreach(k;0..3)
			if(cross(triangle[k],triangle[(k+1)%$]).z<0)
				return;
		minimapTarget=target;
	}
	void renderMinimap(RenderingContext* rc){
		auto map=state.current.map;
		auto radius=minimapRadius;
		auto left=cast(int)(width-2.0f*radius), top=cast(int)(height-2.0f*radius);
		auto yOffset=eventManager.windowHeight-height;
		glScissor(left,0+yOffset,width-left,height-top);
		auto hudScaling=this.hudScaling;
		auto scaling=Vector3f(2.0f*radius,2.0f*radius,0f);
		auto position=Vector3f(width-scaling.x,height-scaling.y,0);
		auto material=minimapMaterial;
		minimapMaterialBackend.center=Vector2f(width-radius,height-radius);
		minimapMaterialBackend.radius=0.95f*radius;
		material.bind(rc);
		minimapMaterialBackend.setTransformationScaled(position, Quaternionf.identity(), scaling, rc);
		quad.render(rc);
		auto minimapFactor=hudScaling/camera.minimapZoom;
		auto camPos=fpview.camera.position;
		auto mapRotation=facingQuaternion(-degtorad(fpview.camera.turn));
		auto minimapCenter=Vector3f(camPos.x,camPos.y,0.0f);
		auto minimapSize=Vector2f(2560.0f,2560.0f);
		auto mapCenter=Vector3f(width-radius,height-radius,0);
		auto mapPosition=mapCenter+rotate(mapRotation,minimapFactor*Vector3f(-minimapCenter.x,minimapCenter.y,0));
		auto mapScaling=Vector3f(1,-1,1)*minimapFactor;
		minimapMaterialBackend.setTransformationScaled(mapPosition,mapRotation,mapScaling,rc);
		minimapMaterialBackend.setColor(Color4f(0.5f,0.5f,0.5f,1.0f));
		foreach(i,mesh;map.minimapMeshes){
			if(!mesh) continue;
			minimapMaterialBackend.bindDiffuse(map.textures[i]);
			mesh.render(rc);
		}
		if(mouse.onMinimap){
			auto mouseOffset=Vector3f(mouse.x,mouse.y,0.0f)-mapCenter;
			auto minimapPosition=minimapCenter+rotate(mapRotation,Vector3f(mouseOffset.x,-mouseOffset.y,0.0f)/minimapFactor);
			if(state.current.isOnGround(minimapPosition)){
				minimapPosition.z=state.current.getGroundHeight(minimapPosition);
				auto target=Target(TargetType.terrain,0,minimapPosition,TargetLocation.minimap);
				minimapTarget=target;
			}else{
				minimapTarget=Target.init;
				minimapTarget.location=TargetLocation.minimap;
			}
		}
		minimapMaterialBackend.bindDiffuse(sacHud.minimapIcons);
		 // temporary scratch space. TODO: maybe share memory with other temporary scratch spaces
		import std.container: Array;
		static Array!uint creatureArrowIndices;
		static Array!uint structureArrowIndices;
		static void render(T)(ref T objects,float hudScaling,float minimapFactor,Vector3f minimapCenter,Vector3f mapCenter,float radius,Quaternionf mapRotation,SacScene scene,RenderingContext* rc){ // TODO: why does this need to be static? DMD bug?
			static if((is(typeof(objects.sacObject))||is(T==Souls!(DagonBackend)))&&!is(T==FixedObjects!DagonBackend)){
				auto quad=scene.minimapQuad;
				auto iconScaling=hudScaling*Vector3f(2.0f,2.0f,0.0f);
				static if(is(typeof(objects.sacObject))){
					auto sacObject=objects.sacObject;
					enum isMoving=is(T==MovingObjects!(DagonBackend, RenderMode.opaque))||is(T==MovingObjects!(DagonBackend, RenderMode.transparent));
					bool isManafount=false;
					static if(isMoving){
						enum mayShowArrow=true;
						bool isWizard=false;
						if(sacObject.isWizard){
							isWizard=true;
							quad=scene.minimapWizard;
							iconScaling=hudScaling*Vector3f(11.0f,11.0f,0.0f);
						}
					}else{
						bool mayShowArrow=false;
						enum isWizard=false;
						if(sacObject.isAltarRing){
							mayShowArrow=true;
							quad=scene.minimapAltarRing;
							iconScaling=hudScaling*Vector3f(10.0f,10.0f,0.0f);
						}else if(sacObject.isManalith){
							mayShowArrow=true;
							quad=scene.minimapManalith;
							iconScaling=hudScaling*Vector3f(12.0f,12.0f,0.0f);
						}else if(sacObject.isManafount){
							isManafount=true;
							quad=scene.minimapManafount;
							iconScaling=hudScaling*Vector3f(11.0f,11.0f,0.0f);
							scene.minimapMaterialBackend.setColor(Color4f(0.0f,160.0f/255.0f,219.0f/255.0f,1.0f));
						}else if(sacObject.isShrine){
							mayShowArrow=true;
							quad=scene.minimapShrine;
							iconScaling=hudScaling*Vector3f(12.0f,12.0f,0.0f);
						}
					}
				}else enum mayShowArrow=false;
				enforce(objects.length<=uint.max);
				foreach(j;0..cast(uint)objects.length){
					static if(is(typeof(objects.sacObject))){
						static if(isMoving) auto side=objects.sides[j];
						else auto side=sideFromBuildingId(objects.buildingIds[j],scene.state.current);
						auto showArrow=mayShowArrow&&
							(side==scene.renderSide||
							 (!isMoving||isWizard) && scene.state.current.sides.getStance(side,scene.renderSide)==Stance.ally);
					}else enum showArrow=false;
					auto clipRadiusFactor=showArrow?0.92f:1.08f;
					auto clipradiusSq=((clipRadiusFactor*radius+(showArrow?-1.0f:1.0f)*0.5f*iconScaling.x)*
					                   (clipRadiusFactor*radius+(showArrow?-1.0f:1.0f)*0.5f*iconScaling.y));
					static if(is(T==StaticObjects!DagonBackend)){
						if(!isManafount&&!scene.state.current.buildingById!((bldg)=>bldg.health!=0||bldg.isAltar,()=>false)(objects.buildingIds[j])) // TODO: merge with side lookup!
							continue;
					}
					static if(is(T==Souls!DagonBackend)) auto position=objects[j].position-minimapCenter;
					else auto position=objects.positions[j]-minimapCenter;
					auto iconOffset=rotate(mapRotation,minimapFactor*Vector3f(position.x,-position.y,0));
					if(iconOffset.lengthsqr<=clipradiusSq){
						auto iconCenter=mapCenter+iconOffset;
						scene.minimapMaterialBackend.setTransformationScaled(iconCenter-0.5f*iconScaling,Quaternionf.identity(),iconScaling,rc);
						static if(is(typeof(objects.sacObject))){
							if(!isManafount){
								auto color=scene.state.current.sides.sideColor(side);
								scene.minimapMaterialBackend.setColor(color);
							}
						}else static if(is(T==Souls!DagonBackend)){
							auto soul=objects[j];
							auto color=soul.color(scene.renderSide,scene.state.current)==SoulColor.blue?blueSoulMinimapColor:redSoulMinimapColor;
							scene.minimapMaterialBackend.setColor(color);
						}
						quad.render(rc);
						static if(is(typeof(objects.sacObject))){
							if(scene.mouse.onMinimap){
								auto target=Target(isMoving?TargetType.creature:TargetType.building,objects.ids[j],objects.positions[j],TargetLocation.minimap);
								scene.updateMinimapTarget(target,iconCenter.xy,iconScaling.xy);
							}
						}
					}else static if(is(typeof(objects.sacObject))){
						if(showArrow){
							static if(isMoving) creatureArrowIndices~=objects.ids[j];
							else structureArrowIndices~=objects.ids[j];
						}
					}
				}
			}else static if(is(T==FixedObjects!DagonBackend)){
				// do nothing
			}else static if(is(T==Buildings!DagonBackend)){
				// do nothing
			}else static if(is(T==Particles!DagonBackend)){
				// do nothing
			}else static assert(0);
		}
		state.current.eachByType!render(hudScaling,minimapFactor,minimapCenter,mapCenter,radius,mapRotation,this,rc);
		static void renderArrow(T)(T object,float hudScaling,float minimapFactor,Vector3f minimapCenter,Vector3f mapCenter,float radius,Quaternionf mapRotation,SacScene scene,RenderingContext* rc){ // TODO: why does this need to be static? DMD bug?
			static if(is(typeof(object.sacObject))&&!is(T==FixedObjects!DagonBackend)){
				auto sacObject=object.sacObject;
				enum isMoving=is(T==MovingObject!DagonBackend);
				auto arrowQuad=isMoving?scene.minimapCreatureArrow:scene.minimapStructureArrow;
				auto arrowScaling=hudScaling*Vector3f(11.0f,11.0f,0.0f);
				auto position=object.position-minimapCenter;
				auto iconOffset=rotate(mapRotation,minimapFactor*Vector3f(position.x,-position.y,0));
				auto offset=iconOffset.normalized*(0.92f*radius-hudScaling*6.0f);
				auto iconCenter=mapCenter+offset;
				auto rotation=rotationQuaternion(Axis.z,cast(float)PI/2+atan2(iconOffset.y,iconOffset.x));
				scene.minimapMaterialBackend.setTransformationScaled(iconCenter-rotate(rotation,0.5f*arrowScaling),rotation,arrowScaling,rc);
				static if(isMoving) auto side=object.side;
				else auto side=sideFromBuildingId(object.buildingId,scene.state.current);
				auto color=scene.state.current.sides.sideColor(side);
				scene.minimapMaterialBackend.setColor(color);
				arrowQuad.render(rc);
				if(scene.mouse.onMinimap){
					auto target=Target(isMoving?TargetType.creature:TargetType.building,object.id,object.position,TargetLocation.minimap);
					Vector3f[3] triangle=[Vector3f(0.0f,-9.0f,0.0f),Vector3f(6.0f,6.0f,0.0f),Vector3f(-6.0f,6.0f,0.0f)];
					foreach(k;0..3) triangle[k]=iconCenter+rotate(rotation,hudScaling*triangle[k]);
					scene.updateMinimapTargetTriangle(target,triangle);
				}
			}
		}
		static foreach(isMoving;[true,false])
			foreach(id;isMoving?creatureArrowIndices.data:structureArrowIndices.data)
				state.current.objectById!renderArrow(id,hudScaling,minimapFactor,minimapCenter,mapCenter,radius,mapRotation,this,rc);
		creatureArrowIndices.length=0;
		structureArrowIndices.length=0;
		material.unbind(rc);
		material=sacHud.frameMaterial;
		material.bind(rc);
		material.backend.setTransformationScaled(position, Quaternionf.identity(), scaling, rc);
		minimapFrame.render(rc);
		auto compassScaling=-hudScaling*Vector3f(21.0f,21.0f,0.0f);
		auto compassPosition=mapCenter+rotate(mapRotation,Vector3f(0.0f,radius-2.0f*hudScaling,0.0f)-0.5f*compassScaling);
		material.backend.setTransformationScaled(compassPosition, mapRotation, compassScaling, rc);
		glScissor(0,0+yOffset,width,height);
		minimapCompass.render(rc);
		material.unbind(rc);
	}
	void renderStats(RenderingContext* rc){
		auto material=sacHud.frameMaterial;
		material.bind(rc);
		auto hudScaling=this.hudScaling;
		auto scaling0=Vector3f(64.0f,96.0f,0.0f);
		scaling0*=hudScaling;
		auto scaling1=Vector3f(32.0f,96.0f,0.0f);
		scaling1*=hudScaling;
		auto position0=Vector3f(width-2*scaling1.x-scaling0.x,0,0);
		auto position1=Vector3f(width-2*scaling1.x,0,0);
		auto position2=Vector3f(width-scaling1.x,0,0);
		material.backend.setTransformationScaled(position0, Quaternionf.identity(), scaling0, rc);
		statsFrame.render(rc);
		material.backend.setTransformationScaled(position1, Quaternionf.identity(), scaling1, rc);
		statsFrame.render(rc);
		material.backend.setTransformationScaled(position2, Quaternionf.identity(), scaling1, rc);
		statsFrame.render(rc);
		material.unbind(rc);
		material=hudSoulMaterial;
		material.bind(rc);
		auto soulPosition=position0+0.5f*scaling0;
		auto soulScaling=scaling0;
		soulScaling.x/=sacSoul.soulWidth;
		soulScaling.y/=sacSoul.soulHeight;
		soulScaling.y*=-1;
		soulScaling*=0.85f;
		material.backend.setTransformationScaled(soulPosition, Quaternionf.identity(), soulScaling, rc);
		sacSoul.getMesh(SoulColor.blue,hudSoulFrame/updateAnimFactor).render(rc);
		material.unbind(rc);
		if(!state.current.isValidId(camera.target)) camera.target=0;
		if(camera.target){
			static float getRelativeMana(B)(MovingObject!B obj){
				if(obj.creatureStats.maxMana==0.0f) return 0.0f;
				return obj.creatureStats.mana/obj.creatureStats.maxMana;
			}
			static float getRelativeHealth(B)(MovingObject!B obj){
				if(obj.creatureStats.maxHealth==0.0f) return 0.0f;
				return obj.creatureStats.health/obj.creatureStats.maxHealth;
			}
			void renderStatBar(Vector3f origin,float relativeSize,GenericMaterial top,GenericMaterial mid,GenericMaterial bot){
				auto maxScaling=hudScaling*Vector3f(32.0f,68.0f,0.0f);
				auto position=origin+Vector3f(0.0f,hudScaling*14.0f+(1.0f-relativeSize)*maxScaling.y,0.0f);
				auto scaling=Vector3f(maxScaling.x,maxScaling.y*relativeSize,maxScaling.y);
				auto topPosition=position+Vector3f(0.0f,-hudScaling*4.0f,0.0f);
				auto topScaling=Vector3f(maxScaling.x,hudScaling*4.0f,maxScaling.y);
				auto bottomPosition=position+Vector3f(0.0f,scaling.y,0.0f);
				auto bottomScaling=Vector3f(maxScaling.x,hudScaling*6.0f,maxScaling.y);

				GenericMaterial[3] materials=[top,mid,bot];
				Vector3f[3] positions=[topPosition,position,bottomPosition];
				Vector3f[3] scalings=[topScaling,scaling,bottomScaling];
				static foreach(i;0..3){
					materials[i].bind(rc);
					materials[i].backend.setTransformationScaled(positions[i], Quaternionf.identity(), scalings[i], rc);
					quad.render(rc);
					materials[i].unbind(rc);
				}
			}
			auto relativeStats=state.current.movingObjectById!((obj)=>tuple(getRelativeMana(obj),getRelativeHealth(obj)),()=>tuple(0.0f,0.0f))(camera.target);
			auto relativeMana=relativeStats[0];
			renderStatBar(position1,relativeMana,sacHud.manaTopMaterial,sacHud.manaMaterial,sacHud.manaBottomMaterial);
			auto relativeHealth=relativeStats[1];
			renderStatBar(position2,relativeHealth,sacHud.healthTopMaterial,sacHud.healthMaterial,sacHud.healthBottomMaterial);
		}
	}
	void renderSpellbook(RenderingContext* rc){
		auto hudScaling=this.hudScaling;
		auto material=sacHud.frameMaterial; // TODO: share material binding with other drawing commands (or at least the backend binding)
		material.bind(rc);
		auto position=Vector3f(0.0f,height-hudScaling*32.0f,0.0f);
		auto numFrameSegments=10; // TODO: max(10, spells*2)
		auto scaling=hudScaling*Vector3f(16.0f,8.0f,0.0f);
		auto scaling2=hudScaling*Vector3f(48.0f,16.0f,0.0f);
		auto position2=Vector3f(hudScaling*16.0f*numFrameSegments-4.0f+scaling2.y,height-hudScaling*48.0f,0.0f);
		material.backend.setTransformationScaled(position2,facingQuaternion(PI/2),scaling2,rc);
		spellbookFrame2.render(rc);
		foreach(i;0..numFrameSegments){
			auto positioni=position+hudScaling*Vector3f(16.0f*i,-8.0f,0.0f);
			material.backend.setTransformationScaled(positioni,Quaternionf.identity(),scaling,rc);
			spellbookFrame1.render(rc);
		}
		material.unbind(rc);
		auto tabPosition=Vector3f(0.0f,height-hudScaling*80.0f,0.0f);
		auto tabScaling=hudScaling*Vector3f(48.0f,48.0f,0.0f);
		auto tabs=tuple(creatureTab,spellTab,structureTab);
		material=sacHud.tabsMaterial;
		material.bind(rc);
		foreach(i,tab;tabs){
			material.backend.setTransformationScaled(tabPosition+hudScaling*Vector3f(48.0f,0.0f,0.0f)*i,Quaternionf.identity(),tabScaling,rc);
			tab.render(rc);
		}
		auto spellbookTab=0; // TODO
		material.backend.setTransformationScaled(tabPosition+hudScaling*Vector3f(48.0f,0.0f,0.0f)*spellbookTab,Quaternionf.identity(),tabScaling,rc);
		tabSelector.render(rc);
		material.unbind(rc);
	}
	void renderHUD(RenderingContext* rc){
		renderMinimap(rc);
		renderStats(rc);
		renderSelectionRoster(rc);
		renderSpellbook(rc);
	}

	override void renderShadowCastingEntities3D(RenderingContext* rc){
		super.renderShadowCastingEntities3D(rc);
		if(!state) return;
		renderMap(rc);
		renderNTTs!(RenderMode.opaque)(rc);
	}

	override void renderOpaqueEntities3D(RenderingContext* rc){
		super.renderOpaqueEntities3D(rc);
		if(!state) return;
		renderMap(rc);
		renderNTTs!(RenderMode.opaque)(rc);
		if(showHitboxes) renderHitboxes(rc);
	}
	override void renderTransparentEntities3D(RenderingContext* rc){
		super.renderTransparentEntities3D(rc);
		if(!state) return;
		renderNTTs!(RenderMode.transparent)(rc);
	}
	override void renderEntities2D(RenderingContext* rc){
		super.renderEntities2D(rc);
		if(!state) return;
		if(mouse.visible){
			renderTargetFrame(rc);
			renderHUD(rc);
			renderCursor(rc);
		}
	}

	void setState(GameState!DagonBackend state)in{
		assert(this.state is null);
	}do{
		this.state=state;
		setupEnvironment(state.current.map);
		createSky(state.current.map);
		createSouls();
		initializeHUD();
		initializeMouse();
	}

	void addObject(SacObject!DagonBackend sobj,Vector3f position,Quaternionf rotation){
		foreach(i;0..sobj.isSaxs?sobj.saxsi.meshes.length:sobj.meshes.length){
			auto obj=createEntity3D();
			obj.drawable = sobj.isSaxs?cast(Drawable)sobj.saxsi.meshes[i]:cast(Drawable)sobj.meshes[i];
			obj.position = position;
			obj.rotation = rotation;
			obj.updateTransformation();
			obj.material=sobj.materials[i];
			obj.shadowMaterial=sobj.shadowMaterials[i];
		}
		sacs.insertBack(sobj);
	}

	override void onAllocate(){
		super.onAllocate();

		ssao.enabled=options.enableSSAO;
		glow.enabled=options.enableGlow;
		glow.brightness=options.glowBrightness;
		antiAliasing.enabled=options.enableAntialiasing;

		//view = New!Freeview(eventManager, assetManager);
		auto eCamera = createEntity3D();
		eCamera.position = Vector3f(1270.0f, 1270.0f, 2.0f);
		fpview = New!FirstPersonView2(eventManager, eCamera, assetManager);
		view = fpview;
		mouse.visible=true;
		//auto mat = createMaterial();
		//mat.diffuse = Color4f(0.2, 0.2, 0.2, 0.2);
		//mat.diffuse=txta;

		/+auto obj = createEntity3D();
		 obj.drawable = aOBJ.mesh;
		 obj.material = mat;
		 obj.position = Vector3f(0, 1, 0);
		 obj.rotation = rotationQuaternion(Axis.x,-cast(float)PI/2);+/

		/+if(!state){
			auto sky=createSky();
			sky.rotation=rotationQuaternion(Axis.z,cast(float)PI)*
				rotationQuaternion(Axis.x,cast(float)(PI/2));
		}+/
		/+auto ePlane = createEntity3D();
		 ePlane.drawable = New!ShapePlane(10, 10, 1, assetManager);
		 auto matGround = createMaterial();
		 //matGround.diffuse = ;
		 ePlane.material=matGround;+/
		//sortEntities(entities3D);
		//sortEntities(entities2D);
	}
	struct Camera{
		int target=0;
		float distance=6.0f;
		float height=2.0f;
		float zoom=0.125f;
		float targetZoom=0.125f;
		float minimapZoom=2.7f;
		float focusHeight;
		bool centering=false;
		enum rotationSpeed=0.95f*PI;
		float lastTargetFacing;
	}
	Camera camera;
	void focusCamera(int target){
		camera.target=target;
		import std.typecons;
		alias Tuple=std.typecons.Tuple;
		auto size=state.current.movingObjectById!((obj){
			auto hitbox=obj.relativeHitbox;
			return hitbox[1]-hitbox[0];
		},function Vector3f(){ assert(0); })(target);
		auto width=size.x,depth=size.y,height=size.z;
		height=max(height,1.5f);
		camera.distance=0.6f+2.32f*height;
		camera.distance=max(camera.distance,4.5f);
		camera.height=1.75f*height-1.15f;
		camera.focusHeight=camera.height-0.3f*(height-1.0f);
		updateCameraPosition(0.0f,true);
	}

	void positionCamera(){
		import std.typecons: Tuple, tuple;
		static Tuple!(Vector3f,float) computePosition(B)(MovingObject!B obj,float turn,Camera camera,ObjectState!B state){
			auto zoom=camera.zoom;
			// TODO: distanceFactor to depend on height as well: this is too far for Sorcha and too close for Marduk
			auto distanceFactor=0.6+3.13f*zoom;
			auto heightFactor=0.6+2.8f*zoom;
			camera.distance*=distanceFactor;
			camera.height*=heightFactor;
			auto focusHeightFactor=zoom>=0.125?1.0f:(0.75+0.25f*zoom/0.125f);
			camera.focusHeight*=focusHeightFactor;
			auto distance=camera.distance;
			auto height=camera.height;
			auto focusHeight=camera.focusHeight;
			auto position=obj.position+rotate(rotationQuaternion(Axis.z,-degtorad(turn)),Vector3f(0.0f,-1.0f,0.0f))*distance;
			position.z=(obj.position.z-state.getHeight(obj.position)+state.getHeight(position))+height;
			auto pitchOffset=atan2(position.z-(obj.position.z+focusHeight),(obj.position.xy-position.xy).length);
			return tuple(position,pitchOffset);
		}
		auto posPitch=state.current.movingObjectById!(
			computePosition,function Tuple!(Vector3f,float)(){ assert(0); }
		)(camera.target,fpview.camera.turn,camera,state.current);
		fpview.camera.position=posPitch[0];
		fpview.camera.pitchOffset=radtodeg(posPitch[1]);
	}

	void updateCameraPosition(float dt,bool center){
		if(center) camera.centering=true;
		if(!state.current.isValidId(camera.target)) camera.target=0;
		if(camera.target==0) return;
		while(fpview.camera.pitch>180.0f) fpview.camera.pitch-=360.0f;
		while(fpview.camera.pitch<-180.0f) fpview.camera.pitch+=360.0f;
		while(fpview.camera.turn>180.0f) fpview.camera.turn-=360.0f;
		while(fpview.camera.turn<-180.0f) fpview.camera.turn+=360.0f;
		if(camera.centering){
			auto newTurn=state.current.movingObjectById!(
				(obj)=>-radtodeg(obj.creatureState.facing),
				function float(){ assert(0); }
			)(camera.target);
			auto diff=newTurn-fpview.camera.turn;
			while(diff>180.0f) diff-=360.0f;
			while(diff<-180.0f) diff+=360.0f;
			auto speed=radtodeg(camera.rotationSpeed)*dt;
			if(dt==0.0f||abs(diff)<speed){
				fpview.camera.turn=newTurn;
				camera.centering=false;
			}else fpview.camera.turn+=sign(diff)*speed;
		}
		if(camera.targetZoom!=camera.zoom){
			auto factor=exp(2.0f*log(0.01f)*dt);
			camera.zoom=(1-factor)*camera.targetZoom+factor*camera.zoom;
			camera.zoom=max(0.0f,min(camera.zoom,1.0f));
		}
		positionCamera();
	}
	float speed = 100.0f;
	void cameraControl(double dt){
		Vector3f forward = fpview.camera.worldTrans.forward;
		Vector3f right = fpview.camera.worldTrans.right;
		Vector3f dir = Vector3f(0, 0, 0);
		//if(eventManager.keyPressed[KEY_X]) dir += Vector3f(1,0,0);
		//if(eventManager.keyPressed[KEY_Y]) dir += Vector3f(0,1,0);
		//if(eventManager.keyPressed[KEY_Z]) dir += Vector3f(0,0,1);
		fpview.control();
		if(!mouse.dragging) mouse.onMinimap=isOnMinimap(Vector2f(mouse.x,mouse.y));
		if(mouse.visible){
			if(((eventManager.keyPressed[KEY_LCTRL]||eventManager.keyPressed[KEY_CAPSLOCK])
			    && eventManager.mouseButtonPressed[MB_LEFT])||
			   eventManager.mouseButtonPressed[MB_MIDDLE]
			){
				if(eventManager.mouseRelX||eventManager.mouseRelY)
					mouse.dragging=true;
				if(!mouse.onMinimap){
					fpview.active=true;
					fpview.mouseFactor=-0.25f;
				}else{
					SDL_SetRelativeMouseMode(SDL_TRUE);
				}
				mouse.x+=eventManager.mouseRelX;
				mouse.y+=eventManager.mouseRelY;
				mouse.x=max(0,min(mouse.x,width-1));
				mouse.y=max(0,min(mouse.y,height-1));
			}else{
				mouse.dragging=false;
				if(!mouse.onMinimap){
					if(fpview.active){
						fpview.active=false;
						fpview.mouseFactor=1.0f;
						eventManager.setMouse(cast(int)mouse.x,cast(int)mouse.y);
					}
				}else{
					SDL_SetRelativeMouseMode(SDL_FALSE);
				}
			}
			if(!mouse.onMinimap){
				camera.targetZoom-=0.04f*eventManager.mouseWheelY;
				camera.targetZoom=max(0.0f,min(camera.targetZoom,1.0f));
			}else{
				camera.minimapZoom*=exp(log(1.3)*(-0.4f*eventManager.mouseWheelY+0.04f*(mouse.dragging?eventManager.mouseRelY:0)/hudScaling));
				camera.minimapZoom=max(0.5f,min(camera.minimapZoom,15.0f));
			}
		}
		if(camera.target!=0&&!state.current.isValidId(camera.target)) camera.target=0;
		if(camera.target==0){
			if(eventManager.keyPressed[KEY_E]) dir += -forward;
			if(eventManager.keyPressed[KEY_D]) dir += forward;
			if(eventManager.keyPressed[KEY_S]) dir += -right;
			if(eventManager.keyPressed[KEY_F]) dir += right;
			if(eventManager.keyPressed[KEY_I]) speed = 10.0f;
			if(eventManager.keyPressed[KEY_O]) speed = 100.0f;
			if(eventManager.keyPressed[KEY_P]) speed = 1000.0f;
			fpview.camera.position += dir.normalized * speed * dt;
			if(state) fpview.camera.position.z=max(fpview.camera.position.z, state.current.getHeight(fpview.camera.position));
		}else{
			// TODO: implement the following by sending commands to the game state!
			if(eventManager.keyPressed[KEY_E] && !eventManager.keyPressed[KEY_D]){
				state.current.movingObjectById!startMovingForward(camera.target,state.current);
			}else if(eventManager.keyPressed[KEY_D] && !eventManager.keyPressed[KEY_E]){
				state.current.movingObjectById!startMovingBackward(camera.target,state.current);
			}else state.current.movingObjectById!stopMovement(camera.target,state.current);
			if(eventManager.keyPressed[KEY_S] && !eventManager.keyPressed[KEY_F]){
				state.current.movingObjectById!startTurningLeft(camera.target,state.current);
			}else if(eventManager.keyPressed[KEY_F] && !eventManager.keyPressed[KEY_S]){
				state.current.movingObjectById!startTurningRight(camera.target,state.current);
			}else state.current.movingObjectById!stopTurning(camera.target,state.current);
			positionCamera();
		}
		if(eventManager.keyPressed[KEY_K]){
			fpview.active=false;
			mouse.visible=true;
		}
		if(eventManager.keyPressed[KEY_L]){
			fpview.active=true;
			mouse.visible=false;
			fpview.mouseFactor=2.0f;
		}
	}

	void stateTestControl()in{
		assert(!!state);
	}do{
		static void applyToMoving(alias f,B)(ObjectState!B state,Camera camera,Target target){
			if(!state.isValidId(camera.target)) camera.target=0;
			if(camera.target==0){
				if(!state.isValidId(target.id)) target=Target.init;
				if(target.type.among(TargetType.none,TargetType.terrain))
					state.eachMoving!f(state);
				else if(target.type==TargetType.creature)
					state.movingObjectById!f(target.id,state);
			}else state.movingObjectById!f(camera.target,state);
		}
		static void depleteMana(B)(ref MovingObject!B obj,ObjectState!B state){
			obj.creatureStats.mana=0.0f;
		}
		if(eventManager.keyPressed[KEY_B]) applyToMoving!depleteMana(state.current,camera,mouse.target);
		if(eventManager.keyPressed[KEY_T]) applyToMoving!kill(state.current,camera,mouse.target);
		if(eventManager.keyPressed[KEY_R]) applyToMoving!stun(state.current,camera,mouse.target);
		static void catapultRandomly(B)(ref MovingObject!B object,ObjectState!B state){
			import std.random;
			auto velocity=Vector3f(uniform!"[]"(-20.0f,20.0f), uniform!"[]"(-20.0f,20.0f), uniform!"[]"(10.0f,25.0f));
			//auto velocity=Vector3f(0.0f,0.0f,25.0f);
			object.catapult(velocity,state);
		}
		if(eventManager.keyPressed[KEY_W]) applyToMoving!catapultRandomly(state.current,camera,mouse.target);
		if(eventManager.keyPressed[KEY_RETURN]) applyToMoving!immediateRevive(state.current,camera,mouse.target);
		if(eventManager.keyPressed[KEY_BACKSPACE]){
			if(eventManager.keyPressed[KEY_LCTRL]||eventManager.keyPressed[KEY_CAPSLOCK]){
				applyToMoving!fastRevive(state.current,camera,mouse.target);
			}else applyToMoving!revive(state.current,camera,mouse.target);
		}
		if(eventManager.keyPressed[KEY_G]) applyToMoving!startFlying(state.current,camera,mouse.target);
		if(eventManager.keyPressed[KEY_V]) applyToMoving!land(state.current,camera,mouse.target);
		if(eventManager.keyPressed[KEY_SPACE]) applyToMoving!startMeleeAttacking(state.current,camera,mouse.target);
		// TODO: enabling the following destroys ESDF controls. Template-related compiler bug?
		/+if(eventManager.keyPressed[KEY_UP] && !eventManager.keyPressed[KEY_DOWN]){
			applyToMoving!startMovingForward(state.current,camera,mouse.target);
		}else if(eventManager.keyPressed[KEY_DOWN] && !eventManager.keyPressed[KEY_UP]){
			applyToMoving!startMovingBackward(state.current,camera,mouse.target);
		}else applyToMoving!stopMovement(state.current,camera,mouse.target);
		if(eventManager.keyPressed[KEY_LEFT] && !eventManager.keyPressed[KEY_RIGHT]){
			applyToMoving!startTurningLeft(state.current,camera,mouse.target);
		}else if(eventManager.keyPressed[KEY_RIGHT] && !eventManager.keyPressed[KEY_LEFT]){
			applyToMoving!startTurningRight(state.current,camera,mouse.target);
		}else applyToMoving!stopTurning(state.current,camera,mouse.target);+/

		if(eventManager.keyPressed[KEY_M]&&mouse.target.type==TargetType.creature&&mouse.target.id)
			focusCamera(mouse.target.id);
		if(eventManager.keyPressed[KEY_N]) camera.target=0;

		if(eventManager.keyPressed[KEY_Y]) showHitboxes=true;
		if(eventManager.keyPressed[KEY_U]) showHitboxes=false;
	}

	override void onViewUpdate(double dt){
		if(state) stateTestControl();
		cameraControl(dt);
		super.onViewUpdate(dt);
	}

	override void onLogicsUpdate(double dt){
		assert(dt==1.0f/updateFPS);
		//writeln(DagonBackend.getTotalGPUMemory()," ",DagonBackend.getAvailableGPUMemory());
		//writeln(eventManager.fps);
		if(state){
			state.step();
			state.commit();
			auto totalTime=state.current.frame*dt;
			if(skyEntities.length){
				sacSkyMaterialBackend.sunLoc = state.current.sunSkyRelLoc(fpview.camera.position);
				sacSkyMaterialBackend.cloudOffset+=dt*1.0f/64.0f*Vector2f(1.0f,-1.0f);
				sacSkyMaterialBackend.cloudOffset.x=fmod(sacSkyMaterialBackend.cloudOffset.x,1.0f);
				sacSkyMaterialBackend.cloudOffset.y=fmod(sacSkyMaterialBackend.cloudOffset.y,1.0f);
				rotateSky(rotationQuaternion(Axis.z,cast(float)(2*PI/512.0f*totalTime)));
			}
			if(camera.target){
				auto targetFacing=state.current.movingObjectById!((obj)=>obj.creatureState.facing, function float(){ assert(0); })(camera.target);
				updateCameraPosition(dt,targetFacing!=camera.lastTargetFacing && !mouse.dragging);
				camera.lastTargetFacing=targetFacing;
			}
			updateHUD(dt);
		}
		foreach(sac;sacs.data){
			static float totalTime=0.0f;
			totalTime+=dt;
			auto frame=totalTime*animFPS;
			import animations;
			if(sac.numFrames(cast(AnimationState)0)) sac.setFrame(cast(AnimationState)0,cast(size_t)(frame%sac.numFrames(cast(AnimationState)0)));
		}
	}
	ShapeQuad quad;
	ShapeSacCreatureFrame border;
	SacHud!DagonBackend sacHud;
	ShapeSubQuad selectionRoster, minimapFrame, minimapCompass;
	ShapeSacStatsFrame statsFrame;
	ShapeSubQuad creatureTab,spellTab,structureTab,tabSelector;
	ShapeSubQuad spellbookFrame1,spellbookFrame2;
	GenericMaterial hudSoulMaterial;
	GenericMaterial minimapMaterial;
	ShapeSubQuad minimapQuad;
	ShapeSubQuad minimapAltarRing,minimapManalith,minimapWizard,minimapManafount,minimapShrine;
	ShapeSubQuad minimapCreatureArrow,minimapStructureArrow;
	void initializeHUD(){
		quad=New!ShapeQuad(assetManager);
		border=New!ShapeSacCreatureFrame(assetManager);
		sacHud=new SacHud!DagonBackend();
		selectionRoster=New!ShapeSubQuad(assetManager,-0.5f,0.0f,0.5f,2.0f);
		minimapFrame=New!ShapeSubQuad(assetManager,0.5f,0.5f,1.5f,1.5f);
		minimapCompass=New!ShapeSubQuad(assetManager,101.0f/128.0f,3.0f/128.0f,122.0f/128.0f,24.0f/128.0f);
		statsFrame=New!ShapeSacStatsFrame(assetManager);
		creatureTab=New!ShapeSubQuad(assetManager,1.0f/128.0f,0.0f,47.0f/128,48.0f/128.0f);
		spellTab=New!ShapeSubQuad(assetManager,49.0f/128.0f,0.0f,95.0f/128.0f,48.0f/128.0f);
		structureTab=New!ShapeSubQuad(assetManager,1.0f/128.0f,48.0f/128.0f,47.0f/128,96.0f/128.0f);
		tabSelector=New!ShapeSubQuad(assetManager,49.0f/128.0f,48.0f/128.0f,95.0f/128,96.0f/128.0f);
		spellbookFrame1=New!ShapeSubQuad(assetManager,0.5f,40.0f/128.0f,0.625f,48.0f/128.0f);
		spellbookFrame2=New!ShapeSubQuad(assetManager,80.5f/128.0f,32.5f/128.0f,1.0f,48.0f/128.0f);
		assert(!!sacSoul.texture);
		hudSoulMaterial=createMaterial(hudMaterialBackend2);
		hudSoulMaterial.blending=Transparent;
		hudSoulMaterial.diffuse=sacSoul.texture;
		// minimap
		minimapMaterial=createMaterial(minimapMaterialBackend);
		minimapMaterial.diffuse=Color4f(0.0f,65.0f/255.0f,66.0f/255.0f,1.0f);
		minimapMaterial.blending=Transparent;
		minimapQuad=New!ShapeSubQuad(assetManager,16.5f/64.0f,4.5f/65.0f,16.5f/64.0f,4.5f/64.0f);
		minimapAltarRing=New!ShapeSubQuad(assetManager,1.0f/64.0f,1.0/65.0f,11.0f/64.0f,11.0f/64.0f);
		minimapManalith=New!ShapeSubQuad(assetManager,12.0f/64.0f,0.0/65.0f,24.0f/64.0f,12.0f/64.0f);
		minimapWizard=New!ShapeSubQuad(assetManager,25.0f/64.0f,1.0/65.0f,35.5f/64.0f,12.0f/64.0f);
		minimapManafount=New!ShapeSubQuad(assetManager,36.5f/64.0f,1.0/65.0f,47.0f/64.0f,11.0f/64.0f);
		minimapShrine=New!ShapeSubQuad(assetManager,48.0f/64.0f,0.0/65.0f,60.0f/64.0f,12.0f/64.0f);
		minimapCreatureArrow=New!ShapeSubQuad(assetManager,0.0f/64.0f,13.0/65.0f,11.0f/64.0f,24.0f/64.0f);
		minimapStructureArrow=New!ShapeSubQuad(assetManager,12.0f/64.0f,13.0/65.0f,23.0f/64.0f,24.0f/64.0f);
	}
	struct Mouse{
		float x,y;
		bool visible,showFrame,dragging;
		auto cursor=Cursor.normal;
		Target target;
		bool inHitbox=false;
		bool onMinimap=false;
	}
	Mouse mouse;
	SacCursor!DagonBackend sacCursor;
	int renderSide=0; // TODO
	void initializeMouse(){
		sacCursor=new SacCursor!DagonBackend();
		SDL_ShowCursor(SDL_DISABLE);
		mouse.x=width/2;
		mouse.y=height/2;
		fpview.oldMouseX=cast(int)mouse.x;
		fpview.oldMouseY=cast(int)mouse.y;
		eventManager.setMouse(cast(int)mouse.x, cast(int)mouse.y);
	}
	auto minimapTarget=Target.init;
	Target mouseCursorTargetImpl(){
		if(mouse.onMinimap) return minimapTarget;
		auto information=gbuffer.getInformation();
		auto cur=state.current;
		if(information.x==1){
			Vector3f position=2560.0f*information.yz;
			if(!cur.isOnGround(position)) return Target.init;
			position.z=cur.getGroundHeight(position);
			return Target(TargetType.terrain,0,position);
		}else if(information.x==2){
			auto id=(cast(int)information.y)<<16|cast(int)information.z;
			if(!cur.isValidId(id)) return Target.init;
			static Target handle(B,T)(T obj,int renderSide,ObjectState!B state){
				enum isMoving=is(T==MovingObject!B);
				static if(isMoving) return Target(TargetType.creature,obj.id,obj.position);
				else return Target(TargetType.building,obj.id,obj.position);
			}
			return cur.objectById!handle(id,renderSide,cur);
		}else if(information.x==3){
			auto id=(cast(int)information.y)<<16|cast(int)information.z;
			if(!cur.isValidId(id)) return Target.init;
			return Target(TargetType.soul,id,cur.soulById!((soul)=>soul.position,function Vector3f(){ assert(0); })(id));
		}else return Target.init;
	}
	Target cachedTarget;
	float cachedTargetX,cachedTargetY;
	int cachedTargetFrame;
	enum targetCacheDelta=10.0f;
	enum minimapTargetCacheDelta=2.0f;
	enum targetCacheDuration=1.2f*updateFPS;
	Target mouseCursorTarget(){
		auto target=mouseCursorTargetImpl();
		static immutable importantTargets=[TargetType.creature,TargetType.soul];
		if(cachedTarget.id!=0&&!state.current.isValidId(cachedTarget.id)) cachedTarget=Target.init;
		if(!importantTargets.canFind(target.type)&&!(target.location==TargetLocation.minimap&&target.type==TargetType.building)){
			auto delta=cachedTarget.location!=TargetLocation.minimap?targetCacheDelta:minimapTargetCacheDelta;
			if(cachedTarget.type!=TargetType.none){
				if((mouse.inHitbox || abs(cachedTargetX-mouse.x)<delta &&
				    abs(cachedTargetY-mouse.y)<delta)&&
				   cachedTargetFrame+targetCacheDuration>state.current.frame){
					target=cachedTarget;
				}else cachedTarget=Target.init;
			}
		}else{
			cachedTarget=target;
			cachedTargetX=mouse.x;
			cachedTargetY=mouse.y;
			cachedTargetFrame=state.current.frame;
		}
		return target;
	}
	void animateTarget(Target target){
		switch(target.type){
			case TargetType.none: return;
			case TargetType.terrain: animateManalith(target.position, renderSide, state.current); break;
			case TargetType.creature, TargetType.building: animateManafount(target.position, state.current); break;
			case TargetType.soul: animateManahoar(target.position, renderSide, 30.0f, state.current); break;
			default: assert(target.location!=TargetLocation.scene); break;
		}
	}
	void updateCursor(double dt){
		if(!state) return;
		mouse.target=mouseCursorTarget();
		if(mouse.dragging){
			mouse.cursor=Cursor.drag;
			mouse.showFrame=false;
		}else{
			mouse.cursor=mouse.target.cursor(renderSide,state.current);
			with(Cursor) // TODO: with icons, show border only if spell is applicable to target
				mouse.showFrame=mouse.target.location!=TargetLocation.minimap &&
					(mouse.target.type==TargetType.soul||
					 mouse.cursor.among(friendlyUnit,neutralUnit,rescuableUnit,talkingUnit,enemyUnit,iconFriendly,iconNeutral,iconEnemy));
		}
	}
	override void startGBufferInformationDownload(){
		if(mouse.onMinimap) return;
		static int i=0;
		if(options.printFPS && ((++i)%=2)==0) writeln(eventManager.fps);
		mouse.x=eventManager.mouseX;
		mouse.y=eventManager.mouseY;
		mouse.x=max(0,min(mouse.x,width-1));
		mouse.y=max(0,min(mouse.y,height-1));
		auto x=cast(int)(mouse.x+0.5f), y=cast(int)(height-1-mouse.y+0.5f);
		x=max(0,min(x,width-1));
		y=max(0,min(y,height-1));
		gbuffer.startInformationDownload(x,y);
	}
	override void onUpdate(double dt){
		super.onUpdate(dt);
		updateCursor(dt);
	}
}

class MyApplication: SceneApplication{
	SacScene scene;
	this(Options options){
		super(options.width,options.height,
		      false, "SacEngine", []);
		scene = New!SacScene(sceneManager, options);
		sceneManager.addScene(scene, "Sacrifice");
		scene.load();
	}
}

struct DagonBackend{
	static MyApplication app;
	static @property SacScene scene(){
		enforce(!!app, "Dagon backend not running.");
		assert(!!app.scene);
		return app.scene;
	}
	this(Options options){
		enforce(!app,"can only have one DagonBackend"); // TODO: fix?
		app = New!MyApplication(options);
	}
	void setState(GameState!DagonBackend state){
		scene.setState(state);
	}
	void addObject(SacObject!DagonBackend obj,Vector3f position,Quaternionf rotation){
		scene.addObject(obj,position,rotation);
	}
	void run(){
		app.sceneManager.goToScene("Sacrifice");
		app.run();
	}
	~this(){ Delete(app); }
static:
	alias Texture=.Texture;
	alias Material=.GenericMaterial;
	alias Mesh=.Mesh;
	alias Mesh2D=.Mesh2D;
	alias BoneMesh=.BoneMesh;
	alias TerrainMesh=.TerrainMesh;
	alias MinimapMesh=.Mesh2D;

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
	MinimapMesh makeMinimapMesh(size_t numVertices, size_t numFaces){
		auto m=new MinimapMesh(null); // TODO: set owner
		m.vertices=New!(Vector2f[])(numVertices);
		m.texcoords=New!(Vector2f[])(numVertices);
		m.indices=New!(uint[3][])(numFaces);
		return m;
	}
	void finalizeMinimapMesh(MinimapMesh mesh){
		mesh.dataReady=true;
		mesh.prepareVAO();
	}


	Material[] createMaterials(SacObject!DagonBackend sobj,SacObject!DagonBackend.MaterialConfig config){
		GenericMaterial[] materials;
		foreach(i;0..sobj.isSaxs?sobj.saxsi.meshes.length:sobj.meshes.length){
			GenericMaterial mat;
			if(i==config.sunBeamPart){
				mat=scene.createMaterial(gpuSkinning&&sobj.isSaxs?scene.shadelessBoneMaterialBackend:scene.shadelessMaterialBackend);
				mat.depthWrite=false;
				mat.blending=Additive;
				mat.energy=4.0f;
			}else if(i==config.locustWingPart){
				mat=scene.createMaterial(gpuSkinning&&sobj.isSaxs?scene.shadelessBoneMaterialBackend:scene.shadelessMaterialBackend);
				mat.depthWrite=false;
				mat.blending=Additive;
				mat.energy=20.0f;
			}else if(i==config.transparentShinyPart){
				mat=scene.createMaterial(gpuSkinning&&sobj.isSaxs?scene.shadelessBoneMaterialBackend:scene.shadelessMaterialBackend);
				mat.depthWrite=false;
				mat.blending=Transparent;
				mat.transparency=0.5f;
				mat.energy=20.0f;
			}else{
				mat=scene.createMaterial(gpuSkinning&&sobj.isSaxs?scene.boneMaterialBackend:scene.defaultMaterialBackend);
			}
			auto diffuse=sobj.isSaxs?sobj.saxsi.saxs.bodyParts[i].texture:sobj.textures[i];
			if(diffuse !is null) mat.diffuse=diffuse;
			mat.specular=sobj.isSaxs?Color4f(1,1,1,1):Color4f(0,0,0,1);
			mat.roughness=0.8;
			materials~=mat;
		}
		return materials;
	}

	Material[] createShadowMaterials(SacObject!DagonBackend sobj){
		GenericMaterial[] materials;
		materials=new GenericMaterial[](sobj.materials.length);
		foreach(i,mat;sobj.materials){
			auto blending=("blending" in mat.inputs).asInteger;
			if(blending!=Additive){
				auto shadowMat=scene.createMaterial(gpuSkinning&&sobj.isSaxs?scene.shadowMap.bsb:scene.shadowMap.sb); // TODO: use shadowMap.sm if no alpha channel
				shadowMat.diffuse=("diffuse" in mat.inputs).texture;
				materials[i]=shadowMat;
			}
		}
		return materials;
	}

	Material createMaterial(SacMap!DagonBackend map){
		auto mat=scene.createMaterial(scene.terrainMaterialBackend);
		auto specu=map.envi.landscapeSpecularity;
		mat.specular=Color4f(specu*map.envi.specularityRed/255.0f,specu*map.envi.specularityGreen/255.0f,specu*map.envi.specularityBlue/255.0f);
		//mat.roughness=1.0f-map.envi.landscapeGlossiness;
		mat.roughness=1.0f;
		mat.metallic=0.0f;
		mat.energy=0.05;
		return mat;
	}

	Material createMaterial(SacSoul!DagonBackend soul){
		auto mat=scene.createMaterial(scene.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=Transparent;
		mat.energy=20.0f;
		mat.diffuse=soul.texture;
		return mat;
	}

	Material createMaterial(SacParticle!DagonBackend particle){
		final switch(particle.type){
			case ParticleType.manafount, ParticleType.manalith, ParticleType.manahoar, ParticleType.shrine:
				auto mat=scene.createMaterial(scene.shadelessMaterialBackend);
				mat.depthWrite=false;
				mat.blending=Additive;
				mat.energy=particle.energy;
				mat.diffuse=particle.texture;
				mat.color=particle.color;
				return mat;
		}
	}

	Material[] createMaterials(SacCursor!DagonBackend sacCursor){
		auto materials=new Material[](sacCursor.textures.length);
		foreach(i;0..materials.length){
			auto mat=scene.createMaterial(scene.hudMaterialBackend);
			mat.blending=Transparent;
			mat.diffuse=sacCursor.textures[i];
			materials[i]=mat;
		}
		return materials;
	}

	Material[] createMaterials(SacHud!DagonBackend sacHud){
		auto materials=new Material[](sacHud.textures.length);
		foreach(i;0..materials.length){
			auto mat=scene.createMaterial(scene.hudMaterialBackend);
			mat.blending=Transparent;
			mat.diffuse=sacHud.textures[i];
			materials[i]=mat;
		}
		return materials;
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

// TODO: get rid of code duplication here?
class ShapeSacCreatureFrame: Owner, Drawable{
    Vector2f[20] vertices;
    float[20] alpha;
    uint[3][16] indices;

    GLuint vao = 0;
    GLuint vbo = 0;
    GLuint abo = 0;
    GLuint eao = 0;

    this(Owner o){
        super(o);

        enum size=0.1f;
        enum border=0.5f*size;
        enum gap=0.0f;
        enum left=-border,right=1.0f+border;
        enum bottom=1.0f+border,top=-border;
        vertices[0]=Vector2f(left+gap,top);
        vertices[1]=Vector2f(left+gap+size,top);
        vertices[2]=Vector2f(left+gap+size,top-size);
        vertices[3]=Vector2f(right,top);
        vertices[4]=Vector2f(left+gap+size,top+size);

        vertices[5]=Vector2f(left,top+gap);
        vertices[6]=Vector2f(left+size,top+gap+size);
        vertices[7]=Vector2f(left,top+gap+size);
        vertices[8]=Vector2f(left-size,top+gap+size);
        vertices[9]=Vector2f(left,bottom-gap);

        enum largeAlpha=1.0f;
        enum smallAlpha=0.0f;

        alpha[0]=smallAlpha;
        alpha[1]=largeAlpha;
        alpha[2]=smallAlpha;
        alpha[3]=smallAlpha;
        alpha[4]=smallAlpha;

        alpha[5]=smallAlpha;
        alpha[6]=smallAlpha;
        alpha[7]=largeAlpha;
        alpha[8]=smallAlpha;
        alpha[9]=smallAlpha;

        indices[0]=[0,1,2];
        indices[1]=[1,3,2];
        indices[2]=[0,4,1];
        indices[3]=[4,3,1];

        indices[4]=[5,6,7];
        indices[5]=[8,5,7];
        indices[6]=[7,9,6];
        indices[7]=[8,9,7];

        foreach(i;10..20){
	        vertices[i]=Vector2f(1.0f,1.0f)-vertices[i-10];
	        alpha[i]=alpha[i-10];
        }
        foreach(i;8..16){
	        indices[i]=indices[i-8][]+10;
	        import std.algorithm: swap;
	        swap(indices[i][1],indices[i][2]);
        }

        glGenBuffers(1, &vbo);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glBufferData(GL_ARRAY_BUFFER, vertices.length * float.sizeof * 2, vertices.ptr, GL_STATIC_DRAW);

        glGenBuffers(1, &abo);
        glBindBuffer(GL_ARRAY_BUFFER, abo);
        glBufferData(GL_ARRAY_BUFFER, alpha.length * float.sizeof, alpha.ptr, GL_STATIC_DRAW);

        glGenBuffers(1, &eao);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, eao);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.length * uint.sizeof * 3, indices.ptr, GL_STATIC_DRAW);

        glGenVertexArrays(1, &vao);
        glBindVertexArray(vao);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, eao);

        glEnableVertexAttribArray(0);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, null);

        glEnableVertexAttribArray(1);
        glBindBuffer(GL_ARRAY_BUFFER, abo);
        glVertexAttribPointer(1, 1, GL_FLOAT, GL_FALSE, 0, null);

        glBindVertexArray(0);
    }

    ~this(){
        glDeleteVertexArrays(1, &vao);
        glDeleteBuffers(1, &vbo);
        glDeleteBuffers(1, &abo);
        glDeleteBuffers(1, &eao);
    }

    void update(double dt){}

    void render(RenderingContext* rc){
        glDepthMask(0);
        glBindVertexArray(vao);
        glDrawElements(GL_TRIANGLES, cast(uint)indices.length * 3, GL_UNSIGNED_INT, cast(void*)0);
        glBindVertexArray(0);
        glDepthMask(1);
    }
}

class ShapeSubQuad: Owner, Drawable{
	Vector2f[4] vertices;
	Vector2f[4] texcoords;
	uint[3][2] indices;

	GLuint vao = 0;
	GLuint vbo = 0;
	GLuint tbo = 0;
	GLuint eao = 0;

	this(Owner o,float left,float top,float right,float bottom){
		super(o);

		vertices[0] = Vector2f(0, 1);
		vertices[1] = Vector2f(0, 0);
		vertices[2] = Vector2f(1, 0);
		vertices[3] = Vector2f(1, 1);

		texcoords[0] = Vector2f(left, bottom);
		texcoords[1] = Vector2f(left, top);
		texcoords[2] = Vector2f(right, top);
		texcoords[3] = Vector2f(right, bottom);

		indices[0][0] = 0;
		indices[0][1] = 2;
		indices[0][2] = 1;

		indices[1][0] = 0;
		indices[1][1] = 3;
		indices[1][2] = 2;

		glGenBuffers(1, &vbo);
		glBindBuffer(GL_ARRAY_BUFFER, vbo);
		glBufferData(GL_ARRAY_BUFFER, vertices.length * float.sizeof * 2, vertices.ptr, GL_STATIC_DRAW);

		glGenBuffers(1, &tbo);
		glBindBuffer(GL_ARRAY_BUFFER, tbo);
		glBufferData(GL_ARRAY_BUFFER, texcoords.length * float.sizeof * 2, texcoords.ptr, GL_STATIC_DRAW);

		glGenBuffers(1, &eao);
		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, eao);
		glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.length * uint.sizeof * 3, indices.ptr, GL_STATIC_DRAW);

		glGenVertexArrays(1, &vao);
		glBindVertexArray(vao);
		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, eao);

		glEnableVertexAttribArray(0);
		glBindBuffer(GL_ARRAY_BUFFER, vbo);
		glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, null);

		glEnableVertexAttribArray(1);
		glBindBuffer(GL_ARRAY_BUFFER, tbo);
		glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 0, null);

		glBindVertexArray(0);
	}

	~this()
		{
			glDeleteVertexArrays(1, &vao);
			glDeleteBuffers(1, &vbo);
			glDeleteBuffers(1, &tbo);
			glDeleteBuffers(1, &eao);
		}

	void update(double dt){ }

	void render(RenderingContext* rc){
		glDepthMask(0);
		glBindVertexArray(vao);
		glDrawElements(GL_TRIANGLES, cast(uint)indices.length * 3, GL_UNSIGNED_INT, cast(void*)0);
		glBindVertexArray(0);
		glDepthMask(1);
	}
}

class ShapeSacStatsFrame: Owner, Drawable{
	Vector2f[8] vertices;
	Vector2f[8] texcoords;
	uint[3][4] indices;

	GLuint vao = 0;
	GLuint vbo = 0;
	GLuint tbo = 0;
	GLuint eao = 0;

	this(Owner o){
		super(o);

		vertices[0] = Vector2f(0, 0.5);
		vertices[1] = Vector2f(0, 0);
		vertices[2] = Vector2f(1, 0);
		vertices[3] = Vector2f(1, 0.5);

		vertices[4] = Vector2f(0, 1);
		vertices[5] = Vector2f(0, 0.5);
		vertices[6] = Vector2f(1, 0.5);
		vertices[7] = Vector2f(1, 1);

		texcoords[0] = Vector2f(0.5, 0.25-0.5/64);
		texcoords[1] = Vector2f(0.5, 0);
		texcoords[2] = Vector2f(0.75, 0);
		texcoords[3] = Vector2f(0.75, 0.25-0.5/64);

		texcoords[4] = Vector2f(0.5, 0);
		texcoords[5] = Vector2f(0.5, 0.25-0.5/64);
		texcoords[6] = Vector2f(0.75, 0.25-0.5/64);
		texcoords[7] = Vector2f(0.75, 0);

		indices[0][0] = 0;
		indices[0][1] = 2;
		indices[0][2] = 1;

		indices[1][0] = 0;
		indices[1][1] = 3;
		indices[1][2] = 2;

		indices[2][0] = 4;
		indices[2][1] = 6;
		indices[2][2] = 5;

		indices[3][0] = 4;
		indices[3][1] = 7;
		indices[3][2] = 6;

		glGenBuffers(1, &vbo);
		glBindBuffer(GL_ARRAY_BUFFER, vbo);
		glBufferData(GL_ARRAY_BUFFER, vertices.length * float.sizeof * 2, vertices.ptr, GL_STATIC_DRAW);

		glGenBuffers(1, &tbo);
		glBindBuffer(GL_ARRAY_BUFFER, tbo);
		glBufferData(GL_ARRAY_BUFFER, texcoords.length * float.sizeof * 2, texcoords.ptr, GL_STATIC_DRAW);

		glGenBuffers(1, &eao);
		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, eao);
		glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.length * uint.sizeof * 3, indices.ptr, GL_STATIC_DRAW);

		glGenVertexArrays(1, &vao);
		glBindVertexArray(vao);
		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, eao);

		glEnableVertexAttribArray(0);
		glBindBuffer(GL_ARRAY_BUFFER, vbo);
		glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, null);

		glEnableVertexAttribArray(1);
		glBindBuffer(GL_ARRAY_BUFFER, tbo);
		glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 0, null);

		glBindVertexArray(0);
	}

	~this(){
		glDeleteVertexArrays(1, &vao);
		glDeleteBuffers(1, &vbo);
		glDeleteBuffers(1, &tbo);
		glDeleteBuffers(1, &eao);
	}

	void update(double dt){ }

	void render(RenderingContext* rc){
		glDepthMask(0);
		glBindVertexArray(vao);
		glDrawElements(GL_TRIANGLES, cast(uint)indices.length * 3, GL_UNSIGNED_INT, cast(void*)0);
		glBindVertexArray(0);
		glDepthMask(1);
	}
}
