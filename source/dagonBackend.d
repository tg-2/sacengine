import dagon;
import options,util;
import std.math;
import std.stdio;
import std.algorithm, std.range, std.exception;

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
			}
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

	void renderBorder(Vector2f position,Vector2f size,Color4f color,RenderingContext* rc){
		colorHUDMaterialBackend.bind(null,rc);
		scope(success) colorHUDMaterialBackend.unbind(null, rc);
		auto scaling=Vector3f(size.x,size.y,1.0f);
		colorHUDMaterialBackend.setTransformationScaled(Vector3f(position.x,position.y,0.0f), Quaternionf.identity(), scaling, rc);
		colorHUDMaterialBackend.setColor(color);
		border.render(rc);
	}

	static Vector2f[2] fixHitbox2dSize(Vector2f[2] position){
		auto center=0.5f*(position[0]+position[1]);
		auto size=position[1]-position[0];
		foreach(k;0..2) size[k]=max(size[k],48.0f);
		return [center-0.5f*size,center+0.5f*size];
	}

	void renderBorder(Vector3f[2] hitbox2d,Color4f color,RenderingContext* rc){
		if(hitbox2d[0].z>1.0f) return;
		Vector2f[2] position=[Vector2f(0.5f*(hitbox2d[0].x+1.0f)*width,0.5f*(1.0f-hitbox2d[1].y)*height),
		                      Vector2f(0.5f*(hitbox2d[1].x+1.0f)*width,0.5f*(1.0f-hitbox2d[0].y)*height)];
		position=fixHitbox2dSize(position);
		auto size=position[1]-position[0];
		renderBorder(position[0],size,color,rc);
		mouse.inHitbox=position[0].x<=mouse.x&&mouse.x<=position[1].x&&
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

	void renderCursor(RenderingContext* rc){
		if(mouse.target.id&&!state.current.isValidId(mouse.target.id)) mouse.target=Target.init;
		mouse.x=eventManager.mouseX;
		mouse.y=eventManager.mouseY;
		if(mouse.showBorder){
			if(mouse.target.type.among(TargetType.creature,TargetType.building)){
			   static void renderHitbox(T)(T obj,SacScene scene,RenderingContext* rc){
				   alias B=DagonBackend;
				   auto hitbox2d=obj.hitbox2d(scene.getModelViewProjectionMatrix(obj.position,obj.rotation));
				   static if(is(T==MovingObject!B)) auto objSide=obj.side;
				   else auto objSide=sideFromBuildingId!B(obj.buildingId,scene.state.current);
				   auto color=scene.state.current.sides.sideColor(objSide);
				   scene.renderBorder(hitbox2d,color,rc);
			   }
			   state.current.objectById!renderHitbox(mouse.target.id,this,rc);
			}else if(mouse.target.type==TargetType.soul){
				static void renderHitbox(B)(Soul!B soul,SacScene scene,RenderingContext* rc){
					auto hitbox2d=soul.hitbox2d(scene.getSpriteModelViewProjectionMatrix(soul.position+soul.scaling*Vector3f(0.0f,0.0f,1.25f*sacSoul.soulHeight)));
					auto color=soul.color(scene.renderSide,scene.state.current)==SoulColor.blue?blueSoulBorderColor:redSoulBorderColor;
					scene.renderBorder(hitbox2d,color,rc);
				}
				state.current.soulById!renderHitbox(mouse.target.id,this,rc);
			}
		}
		auto material=sacCursor.materials[mouse.cursor];
		material.bind(rc);
		scope(success) material.unbind(rc);
		auto size=options.cursorSize;
		auto position=Vector3f(mouse.x-0.5f*size,mouse.y,0);
		auto scaling=Vector3f(size,size,1.0f);
		material.backend.setTransformationScaled(position, Quaternionf.identity(), scaling, rc);
		quad.render(rc);
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
		if(mouse.visible) renderCursor(rc);
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
		if(mouse.visible){
			if(((eventManager.keyPressed[KEY_LCTRL]||eventManager.keyPressed[KEY_CAPSLOCK])
			    && eventManager.mouseButtonPressed[MB_LEFT])||
			   eventManager.mouseButtonPressed[MB_MIDDLE]
			){
				if(fpview.active){
					mouse.x+=eventManager.mouseRelX;
					mouse.y+=eventManager.mouseRelY;
					if(eventManager.mouseRelX||eventManager.mouseRelY)
						mouse.dragging=true;
					mouse.x=max(0,min(mouse.x,width-1));
					mouse.y=max(0,min(mouse.x,height-1));
				}
				fpview.active=true;
				fpview.mouseFactor=-0.25f;
			}else{
				mouse.dragging=false;
				if(fpview.active){
					fpview.active=false;
					fpview.mouseFactor=1.0f;
					eventManager.setMouse(cast(int)mouse.x,cast(int)mouse.y);
				}
			}
			camera.targetZoom-=0.04f*eventManager.mouseWheelY;
			camera.targetZoom=max(0.0f,min(camera.targetZoom,1.0f));
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
	ShapeSacCreatureBorder border;
	void initializeHUD(){
		quad=New!ShapeQuad(assetManager);
		border=New!ShapeSacCreatureBorder(assetManager);
	}
	struct Mouse{
		float x,y;
		bool visible,showBorder,dragging;
		auto cursor=Cursor.normal;
		Target target;
		bool inHitbox=false;
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
	Target mouseCursorTargetImpl(){
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
	enum targetCacheDuration=1.2f*updateFPS;
	Target mouseCursorTarget(){
		auto target=mouseCursorTargetImpl();
		static immutable importantTargets=[TargetType.creature,TargetType.soul];
		if(cachedTarget.id!=0&&!state.current.isValidId(cachedTarget.id)) cachedTarget=Target.init;
		if(!importantTargets.canFind(target.type)){
			if(cachedTarget.type!=TargetType.none){
				if((mouse.inHitbox || abs(cachedTargetX-mouse.x)<targetCacheDelta &&
				    abs(cachedTargetY-mouse.y)<targetCacheDelta)&&
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
		final switch(target.type){
			case TargetType.none: return;
			case TargetType.terrain: animateManalith(target.position, renderSide, state.current); break;
			case TargetType.creature, TargetType.building: animateManafount(target.position, state.current); break;
			case TargetType.soul: animateManahoar(target.position, renderSide, 30.0f, state.current); break;
		}
	}
	void updateCursor(double dt){
		mouse.target=mouseCursorTarget();
		if(mouse.dragging){
			mouse.cursor=Cursor.drag;
			mouse.showBorder=false;
		}else{
			mouse.cursor=mouse.target.cursor(renderSide,state.current);
			with(Cursor) // TODO: with icons, show border only if spell is applicable to target
				mouse.showBorder=mouse.target.type==TargetType.soul||
					mouse.cursor.among(friendlyUnit,neutralUnit,rescuableUnit,talkingUnit,enemyUnit,iconFriendly,iconNeutral,iconEnemy);
		}
	}
	override void startGBufferInformationDownload(){
		static int i=0;
		if(options.printFPS && ((++i)%=2)==0) writeln(eventManager.fps);
		mouse.x=eventManager.mouseX;
		mouse.y=eventManager.mouseY;
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
		super(options.width==0?1280:options.width,
		      options.height==0?1280:options.height,
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

class ShapeSacCreatureBorder: Owner, Drawable{
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
