import dagon;
import options,util;
import std.math;
import std.stdio;
import std.algorithm, std.range, std.exception, std.typecons;

import sacobject, sacspell, mrmm, nttData, sacmap, maps, state;
import sxsk : gpuSkinning;
import audioBackend;

final class SacScene: Scene{
	//OBJAsset aOBJ;
	//Texture txta;
	Options options;
	this(SceneManager smngr, Options options){
		super(options.width, options.height, options.scale, options.aspectDistortion, smngr);
		this.shadowMapResolution=options.shadowMapResolution;
		this.options=options;
		if(options.volume!=0.0f) initializeAudio();
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
	SacObject!DagonBackend sacDebris;
	struct Explosion{
		Texture texture;
		GenericMaterial material;
		ShapeSubSphere[16] frames;
		auto getFrame(int i){ return frames[i/updateAnimFactor]; }
	}
	Explosion explosion;
	void createEffects(){
		sacDebris=new SacObject!DagonBackend("extracted/models/MODL.WAD!/bold.MRMC/bold.MRMM");
		enum nU=4,nV=4;
		import txtr;
		explosion.texture=DagonBackend.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pyro.FLDR/txtr.FLDR/exeg.TXTR"));
		auto mat=createMaterial(shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=Additive;
		mat.energy=1.0f;
		mat.diffuse=explosion.texture;
		explosion.material=mat;
		foreach(i,ref frame;explosion.frames){
			int u=cast(int)i%nU,v=cast(int)i/nU;
			frame=new ShapeSubSphere(1.0f,25,25,true,null,1.0f/nU*u,1.0f/nV*v,1.0f/nU*(u+1),1.0f/nV*(v+1));
		}
	}
	SacCommandCone!DagonBackend sacCommandCone;
	void createCommandCones(){
		sacCommandCone=new SacCommandCone!DagonBackend();
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
			}else static if(is(T==Effects!DagonBackend)){
				static if(mode==RenderMode.opaque) if(objects.debris.length){
					auto materials=scene.sacDebris.materials;
					foreach(i;0..materials.length){
						auto material=materials[i];
						material.bind(rc);
						scope(success) material.unbind(rc);
						auto mesh=scene.sacDebris.meshes[i];
						foreach(j;0..objects.debris.length){
							material.backend.setTransformationScaled(objects.debris[j].position,objects.debris[j].rotation,0.2f*Vector3f(1.0f,1.0f,1.0f),rc);
							mesh.render(rc);
						}
					}
				}
				static if(mode==RenderMode.transparent) if(objects.explosions.length){
					auto material=scene.explosion.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					foreach(j;0..objects.explosions.length){
						auto mesh=scene.explosion.getFrame(objects.explosions[j].frame);
						material.backend.setTransformationScaled(objects.explosions[j].position,Quaternionf.identity(),objects.explosions[j].scale*Vector3f(1.0f,1.0f,1.0f),rc);
						mesh.render(rc);
					}
				}
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
						auto mesh=sacParticle.getMesh(objects.frames[j]); // TODO: do in shader?
						material.backend.setSpriteTransformationScaled(objects.positions[j],sacParticle.getScale(objects.lifetimes[j]),rc);
						material.backend.setAlpha(sacParticle.getAlpha(objects.lifetimes[j]));
						mesh.render(rc);
					}
				}
			}else static if(is(T==CommandCones!DagonBackend)) with(scene){
				static if(mode==RenderMode.transparent){
					if(rc.shadowMode) return;
					if(objects.cones.length<=renderSide) return;
					if(iota(CommandConeColor.max+1).map!(i=>objects.cones[renderSide][i].length).all!(l=>l==0)) return;
					sacCommandCone.material.bind(rc);
					assert(sacCommandCone.material.backend is shadelessMaterialBackend);
					shadelessMaterialBackend.setInformation(Vector4f(0.0f,0.0f,0.0f,0.0f));
					scope(success) sacCommandCone.material.unbind(rc);
					enum maxLifetime=cast(int)(sacCommandCone.lifetime*updateFPS);
					foreach(i;0..CommandConeColor.max+1){
						if(objects.cones[renderSide][i].length==0) continue;
						auto color=sacCommandCone.colors[i];
						auto energy=0.4f*(3.0f/(color.r+color.g+color.b))^^4;
						shadelessMaterialBackend.setEnergy(energy);
						shadelessMaterialBackend.setColor(color);
						foreach(j;0..objects.cones[renderSide][i].length){
							auto dat=objects.cones[renderSide][i][j];
							auto position=dat.position;
							auto rotation=facingQuaternion(dat.lifetime);
							auto fraction=(1.0f-cast(float)dat.lifetime/maxLifetime);
							shadelessMaterialBackend.setAlpha(sacCommandCone.getAlpha(fraction));
							auto vertScaling=1.0f+0.25f*fraction;
							auto horzScaling=1.0f+2.0f*fraction;
							auto scaling=Vector3f(horzScaling,horzScaling,vertScaling);
							shadelessMaterialBackend.bindDiffuse(sacCommandCone.texture);
							shadelessMaterialBackend.setTransformationScaled(position, rotation, scaling, rc);
							sacCommandCone.mesh.render(rc);
							enum numShells=8;
							enum scalingFactor=0.95f;
							foreach(k;0..numShells){
								horzScaling*=scalingFactor;
								rotation=facingQuaternion((k&1?-1.0f:1.0f)*2.0f*cast(float)PI*fraction*(k+1));
								scaling=Vector3f(horzScaling,horzScaling,vertScaling);
								if(k+1==numShells) shadelessMaterialBackend.bindDiffuse(whiteTexture);
								shadelessMaterialBackend.setTransformationScaled(position, rotation, scaling, rc);
								sacCommandCone.mesh.render(rc);
							}
						}
					}
				}
			}else static assert(0);
		}
		state.current.eachByType!render(options.enableWidgets,this,rc);
	}

	bool selectionUpdated=false;
	int lastSelectedId=0,lastSelectedFrame=0;
	float lastSelectedX,lastSelectedY;
	CreatureGroup renderedSelection;
	CreatureGroup rectangleSelection;
	void renderCreatureStats(RenderingContext* rc){
		bool updateRectangleSelect=!selectionUpdated&&mouse.status==Mouse.Status.rectangleSelect;
		if(updateRectangleSelect){
			rectangleSelection=CreatureGroup.init;
			if(mouse.additiveSelect) renderedSelection=state.current.getSelection(renderSide);
			else renderedSelection=CreatureGroup.init;
		}else if(!selectionUpdated) renderedSelection=state.current.getSelection(renderSide);
		rc.information=Vector4f(0.0f,0.0f,0.0f,0.0f);
		shadelessMaterialBackend.bind(null,rc);
		scope(success) shadelessMaterialBackend.unbind(null,rc);
		static void renderCreatureStat(B)(MovingObject!B obj,SacScene scene,bool healthAndMana,RenderingContext* rc){
			if(obj.creatureState.mode.among(CreatureMode.dying,CreatureMode.dead)) return;
			auto backend=scene.shadelessMaterialBackend;
			backend.bindDiffuse(scene.sacHud.statusArrows);
			backend.setColor(scene.state.current.sides.sideColor(obj.side));
			// TODO: how is this actually supposed to work?
			import animations;
			auto hitbox0=obj.sacObject.hitbox(obj.rotation,AnimationState.stance1,0);
			auto hitbox=obj.sacObject.hitbox(obj.rotation,obj.animationState,obj.frame/updateAnimFactor);
			auto scaling=1.0f;
			auto position=obj.position+Vector3f(0.5f*(hitbox[0].x+hitbox[1].x),0.5f*(hitbox[0].y+hitbox[1].y),0.5f*(hitbox[0].z+hitbox[1].z)+0.75f*(hitbox0[1].z-hitbox0[0].z)+0.5f*scaling);
			backend.setSpriteTransformationScaled(position,scaling,rc);
			scene.sacHud.statusArrowMeshes[0].render(rc);
			if(healthAndMana){
				backend.bindDiffuse(scene.whiteTexture);
				enum width=92.0f/64.0f, height=10.0f/64.0f, gap=3.0f/64.0f;
				Vector3f fixPre(Vector3f prescaling){ // TODO: This is a hack. get rid of this.
					prescaling.x/=1.25f;
					return prescaling;
				}
				if(obj.creatureStats.maxHealth!=0.0f){
					Vector3f offset=Vector3f(0.0f,0.5f*height+0.5f,0.0f);
					Vector3f prescaling=Vector3f(width,height,0.0f);
					backend.setSpriteTransformationScaledPreprocess(position,scaling,offset,fixPre(prescaling),rc);
					backend.setColor(Color4f(0.5f,0.0f,0.0f));
					backend.setEnergy(4.0f);
					scene.sacHud.statusArrowMeshes[0].render(rc); // TODO: different mesh?
					prescaling=Vector3f(width*obj.creatureStats.health/obj.creatureStats.maxHealth,height,0.0f);
					backend.setSpriteTransformationScaledPreprocess(position,scaling,offset+Vector3f(-0.5f*(width-prescaling.x),0.0f,0.0f),fixPre(prescaling),rc);
					backend.setColor(Color4f(1.0f,0.0f,0.0f));
					backend.setEnergy(8.0f);
					scene.sacHud.statusArrowMeshes[0].render(rc); // TODO: different mesh?
				}
				if(obj.creatureStats.maxMana!=0.0f){
					Vector3f offset=Vector3f(0.0f,1.5f*height+gap+0.5f,0.0f);
					Vector3f prescaling=Vector3f(width,height,0.0f);
					backend.setSpriteTransformationScaledPreprocess(position,scaling,offset,fixPre(prescaling),rc);
					backend.setColor(Color4f(0.0f,0.25f,0.5f));
					backend.setEnergy(2.5f);
					scene.sacHud.statusArrowMeshes[0].render(rc); // TODO: different mesh?
					prescaling=Vector3f(width*obj.creatureStats.mana/obj.creatureStats.maxMana,height,0.0f);
					backend.setSpriteTransformationScaledPreprocess(position,scaling,offset+Vector3f(-0.5f*(width-prescaling.x),0.0f,0.0f),fixPre(prescaling),rc);
					backend.setColor(Color4f(0.0f,0.5f,1.0f));
					backend.setEnergy(5.0f);
					scene.sacHud.statusArrowMeshes[0].render(rc); // TODO: different mesh?
				}
			}
		}
		static void renderOtherSides(B)(MovingObject!B obj,SacScene scene,bool updateRectangleSelect,bool onMinimap,RenderingContext* rc){
			if(updateRectangleSelect){
				if(onMinimap){
					// TODO: get rid of code duplication somehow
					auto radius=scene.minimapRadius;
					auto minimapFactor=scene.hudScaling/scene.camera.minimapZoom;
					auto camPos=scene.fpview.camera.position;
					auto mapRotation=facingQuaternion(-degtorad(scene.fpview.camera.turn));
					auto minimapCenter=Vector3f(camPos.x,camPos.y,0.0f)+rotate(mapRotation,Vector3f(0.0f,scene.camera.distance*3.73f,0.0f));
					auto mapCenter=Vector3f(scene.width-radius,scene.height-radius,0);
					auto relativePosition=obj.position-minimapCenter;
					auto iconOffset=rotate(mapRotation,minimapFactor*Vector3f(relativePosition.x,-relativePosition.y,0));
					auto iconCenter=mapCenter+iconOffset;
					if(scene.isOnMinimap(iconCenter.xy)&&scene.isInRectangleSelect(iconCenter.xy)&&canSelect(scene.renderSide,obj.id,scene.state.current))
						scene.rectangleSelection.addSorted(obj.id);
				}else{
					auto hitbox=obj.sacObject.hitbox(obj.rotation,obj.animationState,obj.frame/updateAnimFactor); // TODO: share computation with some other place?
					auto center2d=transform(scene.getModelViewProjectionMatrix(obj.position,obj.rotation),0.5f*(hitbox[0]+hitbox[1]));
					if(center2d.z>1.0f) return;
					auto screenPosition=Vector2f(0.5f*(center2d.x+1.0f)*scene.width,0.5f*(1.0f-center2d.y)*scene.height);
					if(scene.isInRectangleSelect(screenPosition)&&canSelect(scene.renderSide,obj.id,scene.state.current)) scene.rectangleSelection.addSorted(obj.id);
				}
			}
			if(obj.side!=scene.renderSide) renderCreatureStat(obj,scene,false,rc);
		}
		state.current.eachMoving!renderOtherSides(this,updateRectangleSelect,mouse.loc==Mouse.Location.minimap,rc);
		if(updateRectangleSelect) renderedSelection.addFront(rectangleSelection.creatureIds[]);
		foreach(id;renderedSelection.creatureIds)
			if(id) state.current.movingObjectById!renderCreatureStat(id,this,true,rc);
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
		mouse.inHitbox=mouse.loc==Mouse.Location.scene&&position[0].x<=mouse.x&&mouse.x<=position[1].x&&
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
		if(mouse.target.id&&!state.current.isValidId(mouse.target.id,mouse.target.type)) mouse.target=Target.init;
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
	bool isInRectangleSelect(Vector2f position){
		if(mouse.status!=Mouse.Status.rectangleSelect) return false;
		auto x1=min(mouse.leftButtonX,mouse.x), x2=max(mouse.leftButtonX,mouse.x);
		auto y1=min(mouse.leftButtonY,mouse.y), y2=max(mouse.leftButtonY,mouse.y);
		return x1<=position.x&&position.x<=x2 && y1<=position.y&&position.y<=y2;
	}
	void renderRectangleSelectFrame(RenderingContext* rc){
		if(mouse.status!=Mouse.Status.rectangleSelect) return;
		auto x1=min(mouse.leftButtonX,mouse.x), x2=max(mouse.leftButtonX,mouse.x);
		auto y1=min(mouse.leftButtonY,mouse.y), y2=max(mouse.leftButtonY,mouse.y);
		auto color=Color4f(1.0f,1.0f,1.0f);
		if(mouse.loc==Mouse.Location.minimap){
			auto radius=minimapRadius;
			x1=max(x1,width-2.0f*radius);
			y1=max(y1,height-2.0f*radius);
			color=Color4f(1.0f,0.0f,0.0f);
		}
		auto rectWidth=x2-x1,rectHeight=y2-y1;
		colorHUDMaterialBackend.bind(null,rc);
		scope(success) colorHUDMaterialBackend.unbind(null,rc);
		colorHUDMaterialBackend.bindDiffuse(whiteTexture);
		colorHUDMaterialBackend.setColor(color);
		auto thickness=0.5f*hudScaling;
		auto scaling1=Vector3f(rectWidth+thickness,thickness,0.0f);
		auto position1=Vector3f(x1,y1,0.0f);
		auto position2=Vector3f(x1,y2,0.0f);
		colorHUDMaterialBackend.setTransformationScaled(position1, Quaternionf.identity(), scaling1, rc);
		quad.render(rc);
		colorHUDMaterialBackend.setTransformationScaled(position2, Quaternionf.identity(), scaling1, rc);
		quad.render(rc);
		auto scaling2=Vector3f(thickness,rectHeight+thickness,0.0f);
		auto position3=Vector3f(x1,y1,0.0f);
		auto position4=Vector3f(x2,y1,0.0f);
		colorHUDMaterialBackend.setTransformationScaled(position3, Quaternionf.identity(), scaling2, rc);
		quad.render(rc);
		colorHUDMaterialBackend.setTransformationScaled(position4, Quaternionf.identity(), scaling2, rc);
		quad.render(rc);
	}
	void renderCursor(RenderingContext* rc){
		if(mouse.target.id&&!state.current.isValidId(mouse.target.id,mouse.target.type)) mouse.target=Target.init;
		mouse.x=eventManager.mouseX/screenScaling;
		mouse.y=eventManager.mouseY/screenScaling;
		mouse.x=max(0,min(mouse.x,width-1));
		mouse.y=max(0,min(mouse.y,height-1));
		auto size=options.cursorSize;
		auto position=Vector3f(mouse.x-0.5f*size,mouse.y,0);
		if(mouse.status==Mouse.Status.rectangleSelect) position.y-=1.0f;
		auto scaling=Vector3f(size,size,1.0f);
		if(mouse.status==Mouse.Status.icon){
			auto iconPosition=position+Vector3f(0.0f,4.0f/32.0f*size,0.0f);
			if(mouse.icon!=MouseIcon.spell){
				auto material=sacCursor.iconMaterials[mouse.icon];
				material.bind(rc);
				material.backend.setTransformationScaled(iconPosition, Quaternionf.identity(), scaling, rc);
				quad.render(rc);
				material.unbind(rc);
			}else{
				hudMaterialBackend.bind(null,rc);
				hudMaterialBackend.bindDiffuse(sacHud.pages);
				ShapeSubQuad[3] pages=[creaturePage,spellPage,structurePage];
				auto page=pages[spellbookTab];
				hudMaterialBackend.setTransformationScaled(iconPosition, Quaternionf.identity(), scaling, rc);
				page.render(rc);
				hudMaterialBackend.bindDiffuse(mouse.spell.icon);
				quad.render(rc);
				hudMaterialBackend.unbind(null,rc);
			}
			if(!mouse.targetValid){
				auto material=sacCursor.invalidTargetIconMaterial;
				material.bind(rc);
				material.backend.setTransformationScaled(iconPosition, Quaternionf.identity(), scaling, rc);
				quad.render(rc);
				material.unbind(rc);
			}
		}
		auto material=sacCursor.materials[mouse.cursor];
		material.bind(rc);
		material.backend.setTransformationScaled(position, Quaternionf.identity(), scaling, rc);
		quad.render(rc);
		material.unbind(rc);
	}

	@property float hudScaling(){ return height/480.0f; }
	int hudSoulFrame=0;
	void updateHUD(float dt){
		hudSoulFrame+=1;
		if(hudSoulFrame>=sacSoul.numFrames*updateAnimFactor)
			hudSoulFrame=0;
	}
	bool isOnSelectionRoster(Vector2f center){
		auto scaling=hudScaling*Vector3f(138.0f,256.0f-64.0f,1.0f);
		auto position=Vector3f(-34.0f*hudScaling,0.5*(height-scaling.y),0);
		auto topLeft=position;
		auto bottomRight=position+scaling;
		return floor(topLeft.x)<=center.x&&center.x<=cast(int)ceil(bottomRight.x)
			&& floor(topLeft.y)<=center.y&&center.y<=cast(int)ceil(bottomRight.y);
	}
	void updateSelectionRosterTarget(Target target,Vector2f position,Vector2f scaling){
		if(!mouse.onSelectionRoster) return;
		auto topLeft=position;
		auto bottomRight=position+scaling;
		if(floor(topLeft.x)<=mouse.x&&mouse.x<=ceil(bottomRight.x)
		   && floor(topLeft.y)<=mouse.y&&mouse.y<=ceil(bottomRight.y))
			selectionRosterTarget=target;
	}
	void renderSelectionRoster(RenderingContext* rc){
		if(mouse.onSelectionRoster) selectionRosterTarget=Target.init;
		auto material=sacHud.frameMaterial;
		material.bind(rc);
		scope(success) material.unbind(rc);
		auto hudScaling=this.hudScaling;
		auto scaling=hudScaling*Vector3f(138.0f,256.0f,1.0f);
		auto position=Vector3f(-34.0f*hudScaling,0.5*(height-scaling.y),0);
		material.backend.setTransformationScaled(position, Quaternionf.identity(), scaling, rc);
		selectionRoster.render(rc);
		int i=0; // idiotic deprecation of foreach(int i,x;selection)
		foreach(x;renderedSelection.creatureIds){
			scope(success) i++;
			if(!renderedSelection.creatureIds[i]) continue;
			static void renderIcon(B)(MovingObject!B obj,int i,Vector3f position,float hudScaling,SacScene scene,RenderingContext* rc){
				auto cpos=position+hudScaling*Vector3f(i>=6?35.0f:-1.0f,(i%6)*32.0f,0.0f);
				auto scaling=hudScaling*Vector3f(34.0f,32.0f,0.0f);
				if(obj.sacObject.icon){
					scene.hudMaterialBackend.setTransformationScaled(cpos, Quaternionf.identity(), scaling, rc);
					scene.hudMaterialBackend.bindDiffuse(obj.sacObject.icon);
					scene.quad.render(rc);
					if(scene.mouse.onSelectionRoster){
						auto target=Target(TargetType.creature,obj.id,obj.position,TargetLocation.selectionRoster);
						scene.updateSelectionRosterTarget(target,cpos.xy,scaling.xy);
					}
					if(obj.creatureStats.maxHealth!=0.0f){
						auto healthScaling=hudScaling*Vector3f(2.0f,30.0f*obj.creatureStats.health/obj.creatureStats.maxHealth,0.0f);
						auto healthPos=cpos+Vector3f(hudScaling*32.0f,hudScaling*30.0f-healthScaling.y,0.0f);
						scene.hudMaterialBackend.setTransformationScaled(healthPos, Quaternionf.identity(), healthScaling, rc);
						scene.hudMaterialBackend.bindDiffuse(scene.healthColorTexture);
						scene.quad.render(rc);
					}
					if(obj.creatureStats.maxMana!=0.0f){
						auto manaScaling=hudScaling*Vector3f(2.0f,30.0f*obj.creatureStats.mana/obj.creatureStats.maxMana,0.0f);
						auto manaPos=cpos+Vector3f(hudScaling*34.0f,hudScaling*30.0f-manaScaling.y,0.0f);
						scene.hudMaterialBackend.setTransformationScaled(manaPos, Quaternionf.identity(), manaScaling, rc);
						scene.hudMaterialBackend.bindDiffuse(scene.manaColorTexture);
						scene.quad.render(rc);
					}
				}
			}
			state.current.movingObjectById!renderIcon(renderedSelection.creatureIds[i],i,Vector3f(position.x+34.0f*hudScaling,0.5*(height-scaling.y)+32.0f*hudScaling,0.0f),hudScaling,this,rc);
		}
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
		if(mouse.onMinimap) minimapTarget=Target.init;
		auto map=state.current.map;
		auto radius=minimapRadius;
		auto left=cast(int)(width-2.0f*radius), top=cast(int)(height-2.0f*radius);
		auto yOffset=eventManager.windowHeight-cast(int)(height*screenScaling);
		glScissor(cast(int)(left*screenScaling),0+yOffset,cast(int)((width-left)*screenScaling),cast(int)((height-top)*screenScaling));
		auto hudScaling=this.hudScaling;
		auto scaling=Vector3f(2.0f*radius,2.0f*radius,0f);
		auto position=Vector3f(width-scaling.x,height-scaling.y,0);
		auto material=minimapMaterial;
		minimapMaterialBackend.center=Vector2f(width-radius,height-radius);
		minimapMaterialBackend.radius=0.95f*radius;
		material.bind(rc);
		minimapMaterialBackend.setTransformationScaled(position, Quaternionf.identity(), scaling, rc);
		minimapMaterialBackend.setColor(Color4f(0.0f,65.0f/255.0f,66.0f/255.0f,1.0f));
		quad.render(rc);
		auto minimapFactor=hudScaling/camera.minimapZoom;
		auto camPos=fpview.camera.position;
		auto mapRotation=facingQuaternion(-degtorad(fpview.camera.turn));
		auto minimapCenter=Vector3f(camPos.x,camPos.y,0.0f)+rotate(mapRotation,Vector3f(0.0f,camera.distance*3.73f,0.0f));
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
		if(camera.target){
			import std.typecons: Tuple,tuple;
			auto facingPosition=state.current.movingObjectById!((obj)=>tuple(obj.creatureState.facing,obj.position), function Tuple!(float,Vector3f)(){ assert(0); })(camera.target);
			auto facing=facingPosition[0],targetPosition=facingPosition[1];
			auto relativePosition=targetPosition-minimapCenter;
			auto iconOffset=rotate(mapRotation,minimapFactor*Vector3f(relativePosition.x,-relativePosition.y,0));
			auto iconCenter=mapCenter+iconOffset;
			minimapMaterialBackend.bindDiffuse(whiteTexture);
			minimapMaterialBackend.setColor(Color4f(1.0f,1.0f,0.0f,1.0f));
			auto fovScaling=Vector3f(0.5f*hudScaling,2.0f*radius,0.0f);
			auto angle=2.0f*cast(float)PI*82.0f/360.0f;
			auto fovRotation1=mapRotation*facingQuaternion(-facing-0.5f*angle+cast(float)PI);
			minimapMaterialBackend.setTransformationScaled(iconCenter+rotate(fovRotation1,Vector3f(-0.5f*fovScaling.x,0.0f,0.0f)),fovRotation1,fovScaling,rc);
			quad.render(rc);
			auto fovRotation2=mapRotation*facingQuaternion(-facing+0.5f*angle+cast(float)PI);
			minimapMaterialBackend.setTransformationScaled(iconCenter+rotate(fovRotation2,Vector3f(-0.5f*fovScaling.x,0.0f,0.0f)),fovRotation2,fovScaling,rc);
			quad.render(rc);
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
						static if(isMoving) if(objects.creatureStates[j].mode==CreatureMode.dead) continue;
						static if(isMoving){
							auto side=objects.sides[j];
							auto flags=objects.creatureStatss[j].flags;
						}else{
							alias Tuple=std.typecons.Tuple;
							auto sideFlags=scene.state.current.buildingById!((ref b)=>tuple(b.side,b.flags),function Tuple!(int,int)(){ assert(0); })(objects.buildingIds[j]);
							auto side=sideFlags[0],flags=sideFlags[1];
						}
						import ntts: Flags;
						if(flags&Flags.notOnMinimap) continue;
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
								if(scene.isInRectangleSelect(iconCenter.xy)&&canSelect(scene.renderSide,objects.ids[j],scene.state.current))
									scene.rectangleSelection.addSorted(objects.ids[j]);
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
			}else static if(is(T==Effects!DagonBackend)){
				// do nothing
			}else static if(is(T==Particles!DagonBackend)){
				// do nothing
			}else static if(is(T==CommandCones!DagonBackend)){
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
		auto compassScaling=0.8f*hudScaling*Vector3f(21.0f,21.0f,0.0f);
		auto compassPosition=mapCenter+rotate(mapRotation,Vector3f(0.0f,radius-3.0f*hudScaling,0.0f)-0.5f*compassScaling);
		material.backend.setTransformationScaled(compassPosition, mapRotation, compassScaling, rc);
		glScissor(0,0+yOffset,cast(int)(width*screenScaling),cast(int)(height*screenScaling));
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
		if(!state.current.isValidId(camera.target,TargetType.creature)) camera.target=0;
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
	auto spellbookTab=SpellType.creature;
	void switchSpellbookTab(SpellType newTab){
		if(spellbookTab==newTab) return;
		if(audio) audio.playSound("okub");
		spellbookTab=newTab;
	}
	void selectSpell(SacSpell!DagonBackend newSpell,bool playAudio=true){
		if(mouse.status==Mouse.Status.icon&&playAudio&&audio) audio.playSound("kabI");
		import std.random:uniform; // TODO: put selected spells in game state?
		auto whichClick=uniform(0,2);
		if(playAudio&&audio) audio.playSound(commandAppliedSoundTags[whichClick]);
		// state.current.movingObjectById!((ref obj,castingTime,state){ obj.startCasting(cast(int)(castingTime*updateFPS),state); })(camera.target,newSpell.castingTime,state.current);
		if(newSpell.flags){
			mouse.status=Mouse.Status.icon;
			mouse.icon=MouseIcon.spell;
			mouse.spell=newSpell;
		}else{
			mouse.status=Mouse.Status.standard;
			// TODO: cast spell
		}
	}
	int numSpells=0;
	bool isOnSpellbook(Vector2f center){
		auto tabScaling=hudScaling*Vector2f(3*48.0f,48.0f);
		auto tabPosition=Vector2f(0.0f,height-hudScaling*80.0f);
		auto tabTopLeft=tabPosition;
		auto tabBottomRight=tabPosition+tabScaling;
		if(floor(tabTopLeft.x)<=center.x&&center.x<=ceil(tabBottomRight.x)&&
		   floor(tabTopLeft.y)<=center.y&&center.y<=ceil(tabBottomRight.y))
			return true;
		auto spellScaling=hudScaling*Vector2f(numSpells*32.0f+12.0f,36.0f);
		auto spellPosition=Vector2f(0.0f,height-spellScaling.y);
		auto spellTopLeft=spellPosition;
		auto spellBottomRight=spellPosition+spellScaling;
		if(floor(spellTopLeft.x)<=center.x&&center.x<=ceil(spellBottomRight.x)&&
		   floor(spellTopLeft.y)<=center.y&&center.y<=ceil(spellBottomRight.y))
			return true;

		return false;
	}
	void updateSpellbookTarget(Target target,SacSpell!DagonBackend targetSpell,Vector2f position,Vector2f scaling){
		if(!mouse.onSpellbook) return;
		auto topLeft=position;
		auto bottomRight=position+scaling;
		if(floor(topLeft.x)<=mouse.x&&mouse.x<=ceil(bottomRight.x)
		   && floor(topLeft.y)<=mouse.y&&mouse.y<=ceil(bottomRight.y)){
			spellbookTarget=target;
			spellbookTargetSpell=targetSpell;
		}
	}
	void renderSpellbook(RenderingContext* rc){
		if(mouse.onSpellbook){
			spellbookTarget=Target.init;
			spellbookTargetSpell=null;
		}
		auto hudScaling=this.hudScaling;
		auto spells=state.current.getSpells(camera.target).filter!(x=>x.spell.type==spellbookTab);
		numSpells=cast(int)spells.walkLength;
		auto material=sacHud.frameMaterial; // TODO: share material binding with other drawing commands (or at least the backend binding)
		material.bind(rc);
		auto position=Vector3f(0.0f,height-hudScaling*32.0f,0.0f);
		auto numFrameSegments=max(10,2*numSpells);
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
		auto tabsPosition=Vector3f(0.0f,height-hudScaling*80.0f,0.0f);
		auto tabScaling=hudScaling*Vector3f(48.0f,48.0f,0.0f);
		auto tabs=tuple(creatureTab,spellTab,structureTab);
		material=sacHud.tabsMaterial;
		material.bind(rc);
		foreach(i,tab;tabs){
			auto tabPosition=tabsPosition+hudScaling*Vector3f(48.0f,0.0f,0.0f)*i;
			auto target=Target(cast(TargetType)(TargetType.creatureTab+i),0,Vector3f.init,TargetLocation.spellbook);
			updateSpellbookTarget(target,null,tabPosition.xy,tabScaling.xy);
			material.backend.setTransformationScaled(tabPosition,Quaternionf.identity(),tabScaling,rc);
			tab.render(rc);
		}
		material.backend.setTransformationScaled(tabsPosition+hudScaling*Vector3f(48.0f,0.0f,0.0f)*spellbookTab,Quaternionf.identity(),tabScaling,rc);
		tabSelector.render(rc);
		material.unbind(rc);
		hudMaterialBackend.bind(null,rc);
		hudMaterialBackend.bindDiffuse(sacHud.pages);
		ShapeSubQuad[3] pages=[creaturePage,spellPage,structurePage];
		auto page=pages[spellbookTab];
		foreach(i,spell;enumerate(spells)){
			auto spellScaling=hudScaling*Vector3f(32.0f,32.0f,0.0f);
			auto spellPosition=Vector3f(i*spellScaling.x,height-spellScaling.y,0.0f);
			hudMaterialBackend.setTransformationScaled(spellPosition,Quaternionf.identity(),spellScaling,rc);
			page.render(rc);
		}
		foreach(i,spell;enumerate(spells)){
			auto spellScaling=hudScaling*Vector3f(32.0f,32.0f,0.0f);
			auto spellPosition=Vector3f(i*spellScaling.x,height-spellScaling.y,0.0f);
			auto target=Target(TargetType.spell,0,Vector3f.init,TargetLocation.spellbook);
			updateSpellbookTarget(target,spell.spell,spellPosition.xy,spellScaling.xy);
			hudMaterialBackend.setTransformationScaled(spellPosition,Quaternionf.identity(),spellScaling,rc);
			hudMaterialBackend.bindDiffuse(spell.spell.icon);
			quad.render(rc);
		}
		hudMaterialBackend.unbind(null,rc);
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
		renderCreatureStats(rc);
	}
	override void renderEntities2D(RenderingContext* rc){
		super.renderEntities2D(rc);
		if(!state) return;
		if(mouse.visible){
			renderTargetFrame(rc);
			renderHUD(rc);
			renderRectangleSelectFrame(rc);
			renderCursor(rc);
		}
	}

	void setState(GameState!DagonBackend state)in{
		assert(this.state is null);
	}do{
		this.state=state;
		setupEnvironment(state.current.map);
		createSky(state.current.map);
		if(audio&&state) audio.setTileset(state.current.map.tileset);
		createSouls();
		createEffects();
		createCommandCones();
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
	struct MovementState{ // to avoid sending too many commands. TODO: react to input events instead.
		MovementDirection movement;
		RotationDirection rotation;
	}
	MovementState targetMovementState;
	void focusCamera(int target){
		camera.target=target;
		targetMovementState=MovementState.init;
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
			auto focusHeightFactor=zoom>=0.125?1.0f:(0.75+0.25f*zoom/0.125f);
			camera.focusHeight*=focusHeightFactor;
			auto distance=camera.distance*distanceFactor;
			auto height=camera.height*heightFactor;
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
		if(!state.current.isValidId(camera.target,TargetType.creature)) camera.target=0;
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

	int[512] keyDown,keyUp;
	int[255] mouseButtonDown,mouseButtonUp;

	override void onKeyDown(int key){ keyDown[key]+=1; }
	override void onKeyUp(int key){ keyUp[key]+=1; }
	override void onMouseButtonDown(int button){ mouseButtonDown[button]+=1; }
	override void onMouseButtonUp(int button){ mouseButtonUp[button]+=1; }

	void control(double dt){
		auto oldMouseStatus=mouse.status;
		scope(success){
			keyDown[]=0;
			keyUp[]=0;
			mouseButtonDown[]=0;
			mouseButtonUp[]=0;
		}
		Vector3f forward = fpview.camera.worldTrans.forward;
		Vector3f right = fpview.camera.worldTrans.right;
		Vector3f dir = Vector3f(0, 0, 0);
		//if(eventManager.keyPressed[KEY_X]) dir += Vector3f(1,0,0);
		//if(eventManager.keyPressed[KEY_Y]) dir += Vector3f(0,1,0);
		//if(eventManager.keyPressed[KEY_Z]) dir += Vector3f(0,0,1);
		if(fpview.active){
			float turn_m =  (eventManager.mouseRelX) * fpview.mouseFactor;
			float pitch_m = (eventManager.mouseRelY) * fpview.mouseFactor;

			fpview.camera.pitch += pitch_m;
			fpview.camera.turn += turn_m;
		}
		if(mouse.status.among(Mouse.Status.standard,Mouse.Status.icon)){
			if(isOnSpellbook(Vector2f(mouse.x,mouse.y))) mouse.loc=Mouse.Location.spellbook;
			else if(isOnSelectionRoster(Vector2f(mouse.x,mouse.y))) mouse.loc=Mouse.Location.selectionRoster;
			else if(isOnMinimap(Vector2f(mouse.x,mouse.y))) mouse.loc=Mouse.Location.minimap;
			else mouse.loc=Mouse.Location.scene;
		}
		if(mouse.visible && mouse.status.among(Mouse.Status.standard,Mouse.Status.dragging)){
			if(((eventManager.keyPressed[KEY_LCTRL]||eventManager.keyPressed[KEY_CAPSLOCK])
			    && eventManager.mouseButtonPressed[MB_LEFT])||
			   eventManager.mouseButtonPressed[MB_MIDDLE]
			){
				if(eventManager.mouseRelX||eventManager.mouseRelY)
					mouse.status=Mouse.Status.dragging;
				if(!mouse.onMinimap){
					fpview.active=true;
					fpview.mouseFactor=-0.25f;
				}else{
					SDL_SetRelativeMouseMode(SDL_TRUE);
				}
				mouse.x+=eventManager.mouseRelX/screenScaling;
				mouse.y+=eventManager.mouseRelY/screenScaling;
				mouse.x=max(0,min(mouse.x,width-1));
				mouse.y=max(0,min(mouse.y,height-1));
			}else{
				mouse.status=Mouse.Status.standard;
				if(!mouse.onMinimap){
					if(fpview.active){
						fpview.active=false;
						fpview.mouseFactor=1.0f;
						eventManager.setMouse(cast(int)(mouse.x*screenScaling),cast(int)(mouse.y*screenScaling));
					}
				}else{
					SDL_SetRelativeMouseMode(SDL_FALSE);
				}
			}
			if(!mouse.onMinimap){
				camera.targetZoom-=0.04f*eventManager.mouseWheelY;
				camera.targetZoom=max(0.0f,min(camera.targetZoom,1.0f));
			}else{
				camera.minimapZoom*=exp(log(1.3)*(-0.4f*eventManager.mouseWheelY+0.04f*(mouse.status==Mouse.Status.dragging?eventManager.mouseRelY:0)/hudScaling));
				camera.minimapZoom=max(0.5f,min(camera.minimapZoom,15.0f));
			}
		}
		if(camera.target!=0&&(!state||!state.current.isValidId(camera.target,TargetType.creature))) camera.target=0;
		auto cameraFacing=-degtorad(fpview.camera.turn);
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
			if(!state) return;
			if(eventManager.keyPressed[KEY_E] && !eventManager.keyPressed[KEY_D]){
				if(targetMovementState.movement!=MovementDirection.forward){
					targetMovementState.movement=MovementDirection.forward;
					state.addCommand(Command(CommandType.moveForward,renderSide,camera.target,camera.target,Target.init,cameraFacing));
				}
			}else if(eventManager.keyPressed[KEY_D] && !eventManager.keyPressed[KEY_E]){
				if(targetMovementState.movement!=MovementDirection.backward){
					targetMovementState.movement=MovementDirection.backward;
					state.addCommand(Command(CommandType.moveBackward,renderSide,camera.target,camera.target,Target.init,cameraFacing));
				}
			}else{
				if(targetMovementState.movement!=MovementDirection.none){
					targetMovementState.movement=MovementDirection.none;
					state.addCommand(Command(CommandType.stopMoving,renderSide,camera.target,camera.target,Target.init,cameraFacing));
				}
			}
			if(eventManager.keyPressed[KEY_S] && !eventManager.keyPressed[KEY_F]){
				if(targetMovementState.rotation!=RotationDirection.left){
					targetMovementState.rotation=RotationDirection.left;
					state.addCommand(Command(CommandType.turnLeft,renderSide,camera.target,camera.target,Target.init,cameraFacing));
				}
			}else if(eventManager.keyPressed[KEY_F] && !eventManager.keyPressed[KEY_S]){
				if(targetMovementState.rotation!=RotationDirection.right){
					targetMovementState.rotation=RotationDirection.right;
					state.addCommand(Command(CommandType.turnRight,renderSide,camera.target,camera.target,Target.init,cameraFacing));
				}
			}else{
				if(targetMovementState.rotation!=RotationDirection.none){
					targetMovementState.rotation=RotationDirection.none;
					state.addCommand(Command(CommandType.stopTurning,renderSide,camera.target,camera.target,Target.init,cameraFacing));
				}
			}
			positionCamera();
		}
		if(!state) return;
		if(mouseButtonDown[MB_LEFT]!=0){
			if(mouse.loc.among(Mouse.Location.scene,Mouse.Location.minimap)){
				mouse.leftButtonX=mouse.x;
				mouse.leftButtonY=mouse.y;
			}else mouse.leftButtonX=mouse.leftButtonY=float.nan;
		}
		void finishRectangleSelect(){
			mouse.status=Mouse.Status.standard;
			TargetLocation loc;
			final switch(mouse.loc){
				case Mouse.Location.scene: loc=TargetLocation.scene; break;
				case Mouse.Location.minimap: loc=TargetLocation.minimap; break;
				case Mouse.Location.selectionRoster,Mouse.Location.spellbook: assert(0);
			}
			state.setSelection(renderSide,camera.target,renderedSelection,loc);
			selectionUpdated=true;
		}
		if(mouse.status.among(Mouse.Status.standard,Mouse.Status.rectangleSelect)){
			if(eventManager.mouseButtonPressed[MB_LEFT]){
				enum rectangleThreshold=3.0f;
				if(mouse.status==Mouse.Status.standard){
					if((abs(mouse.x-mouse.leftButtonX)>=rectangleThreshold||abs(mouse.y-mouse.leftButtonY)>=rectangleThreshold)&&
					   mouse.loc.among(Mouse.Location.scene,Mouse.Location.minimap))
						mouse.status=Mouse.Status.rectangleSelect;
				}
			}else if(mouse.status==Mouse.Status.rectangleSelect){
				finishRectangleSelect();
			}
		}
		mouse.additiveSelect=eventManager.keyPressed[KEY_LSHIFT];
		selectionUpdated=false;
		if(oldMouseStatus==mouse.status){
			foreach(_;0..mouseButtonUp[MB_LEFT]){
				bool done=true;
				if(mouse.status.among(Mouse.Status.standard,Mouse.Status.icon)){
					if(mouse.target.type==TargetType.creatureTab){
						switchSpellbookTab(SpellType.creature);
					}else if(mouse.target.type==TargetType.spellTab){
						switchSpellbookTab(SpellType.spell);
					}else if(mouse.target.type==TargetType.structureTab){
						switchSpellbookTab(SpellType.structure);
					}else if(mouse.target.type==TargetType.spell){
						selectSpell(mouse.targetSpell);
					}else done=false;
				}else done=false;
				if(!done) final switch(mouse.status){
					case Mouse.Status.standard:
						if(mouse.target.type==TargetType.creature&&canSelect(renderSide,mouse.target.id,state.current)){
							auto type=mouse.additiveSelect?CommandType.toggleSelection:CommandType.select;
							enum doubleClickDelay=0.3f; // in seconds
							enum delta=targetCacheDelta;
							if(eventManager.keyPressed[KEY_LCTRL]||eventManager.keyPressed[KEY_CAPSLOCK]){
								type=CommandType.selectAll;
							}else if(type==CommandType.select&&(lastSelectedId==mouse.target.id||
							                              abs(lastSelectedX-mouse.x)<delta &&
							                              abs(lastSelectedY-mouse.y)<delta) &&
							         state.current.frame-lastSelectedFrame<=doubleClickDelay*updateFPS){
								type=CommandType.automaticSelectAll;
							}
							state.addCommand(Command(type,renderSide,camera.target,mouse.target.id,Target.init,cameraFacing));
							if(type==CommandType.select){
								lastSelectedId=mouse.target.id;
								lastSelectedFrame=state.current.frame;
							}else{
								lastSelectedId=0;
								lastSelectedFrame=state.current.frame;
								lastSelectedX=mouse.x;
								lastSelectedY=mouse.y;
							}
						}
						break;
					case Mouse.Status.dragging:
						// do nothing
						break;
					case Mouse.Status.rectangleSelect:
						finishRectangleSelect();
						break;
					case Mouse.Status.icon:
						if(mouse.targetValid){
							auto summary=mouse.target.summarize(renderSide,state.current);
							final switch(mouse.icon){
								case MouseIcon.attack:
									if(summary&(TargetFlags.creature|TargetFlags.wizard|TargetFlags.building)&&!(summary&TargetFlags.corpse)){
										state.addCommand(Command(CommandType.attack,renderSide,camera.target,0,mouse.target,cameraFacing));
									}else{
										auto target=Target(TargetType.terrain,0,mouse.target.position,mouse.target.location);
										state.addCommand(Command(CommandType.advance,renderSide,camera.target,0,target,cameraFacing));
									}
									break;
								case MouseIcon.guard:
									if(summary&(TargetFlags.creature|TargetFlags.wizard|TargetFlags.building)&&!(summary&TargetFlags.corpse)){
										state.addCommand(Command(CommandType.guard,renderSide,camera.target,0,mouse.target,cameraFacing));
									}else{
										auto target=Target(TargetType.terrain,0,mouse.target.position,mouse.target.location);
										state.addCommand(Command(CommandType.guardArea,renderSide,camera.target,0,target,cameraFacing));
									}
									break;
								case MouseIcon.spell:
									// TODO
									break;
							}
							mouse.status=Mouse.Status.standard;
						}
						break;
				}
			}
			foreach(_;0..mouseButtonUp[MB_RIGHT]){
				final switch(mouse.status){
					case Mouse.Status.standard:
						switch(mouse.target.type) with(TargetType){
							case terrain: state.addCommand(Command(CommandType.move,renderSide,camera.target,0,mouse.target,cameraFacing)); break;
							case creature,building:
								auto summary=mouse.target.summarize(renderSide,state.current);
								if(!(summary&TargetFlags.untargettable)){
									if(summary&TargetFlags.corpse){
										auto target=Target(TargetType.terrain,0,mouse.target.position,mouse.target.location);
										state.addCommand(Command(CommandType.guardArea,renderSide,camera.target,0,target,cameraFacing)); break;
									}else if(summary&TargetFlags.enemy){
										state.addCommand(Command(CommandType.attack,renderSide,camera.target,0,mouse.target,cameraFacing)); break;
									}else{
										state.addCommand(Command(CommandType.guard,renderSide,camera.target,0,mouse.target,cameraFacing)); break;
									}
								}
								break;
							case soul:
								final switch(color(mouse.target.id,renderSide,state.current)){
									case SoulColor.blue:
										auto target=Target(TargetType.terrain,0,mouse.target.position,mouse.target.location);
										state.addCommand(Command(CommandType.move,renderSide,camera.target,0,target,cameraFacing));
										break;
									case SoulColor.red:
										// TODO: cast convert
										break;
								}
								break;
							default: break;
						}
						break;
					case Mouse.Status.dragging:
						// do nothing
						break;
					case Mouse.Status.rectangleSelect:
						// do nothing
						break;
					case Mouse.Status.icon:
						mouse.status=Mouse.Status.standard;
						updateCursor(0.0f);
						if(audio) audio.playSound("kabI");
						break;
				}
			}
		}
		foreach(key;KEY_1..KEY_0){
			foreach(_;0..keyDown[key]){
				bool lshift=eventManager.keyPressed[KEY_LSHIFT];
				bool lctrl=eventManager.keyPressed[KEY_LCTRL]||eventManager.keyPressed[KEY_CAPSLOCK];
				auto type=!lshift && lctrl ? CommandType.defineGroup:
					lshift && !lctrl ? CommandType.addToGroup :
					CommandType.selectGroup;
				int group = key==KEY_0?9:key-KEY_1;
				if(group>=numCreatureGroups) break;
				state.addCommand(Command(type,renderSide,camera.target,group));
				if(type==CommandType.addToGroup)
					state.addCommand(Command(CommandType.automaticSelectGroup,renderSide,camera.target,group));
			}
		}
		if(!(eventManager.keyPressed[KEY_LCTRL]||eventManager.keyPressed[KEY_CAPSLOCK]||eventManager.keyPressed[KEY_LSHIFT])){
			foreach(_;0..keyDown[KEY_TAB]){
				switchSpellbookTab(cast(SpellType)((spellbookTab+1)%(spellbookTab.max+1)));
			}
		}
		if(eventManager.keyPressed[KEY_LCTRL]||eventManager.keyPressed[KEY_CAPSLOCK]){
			foreach(_;0..keyDown[KEY_X]){
				state.addCommand(Command(renderSide,camera.target,Formation.phalanx));
			}
			foreach(_;0..keyDown[KEY_L]){
				state.addCommand(Command(renderSide,camera.target,Formation.line));
			}
			foreach(_;0..keyDown[KEY_Z]){
				state.addCommand(Command(renderSide,camera.target,Formation.flankLeft));
			}
			foreach(_;0..keyDown[KEY_V]){
				state.addCommand(Command(renderSide,camera.target,Formation.flankRight));
			}
			foreach(_;0..keyDown[KEY_W]){
				state.addCommand(Command(renderSide,camera.target,Formation.wedge));
			}
			foreach(_;0..keyDown[KEY_U]){
				state.addCommand(Command(renderSide,camera.target,Formation.semicircle));
			}
			foreach(_;0..keyDown[KEY_O]){
				state.addCommand(Command(renderSide,camera.target,Formation.circle));
			}
			foreach(_;0..keyDown[KEY_Y]){
				state.addCommand(Command(renderSide,camera.target,Formation.skirmish));
			}
			foreach(_;0..keyDown[KEY_R]){
				if(mouse.status==Mouse.Status.standard){
					mouse.status=Mouse.Status.icon;
					mouse.icon=MouseIcon.attack;
				}
			}
			foreach(_;0..keyDown[KEY_T]){
				auto target=Target(TargetType.terrain,0,mouse.target.position,mouse.target.location);
				target.position.z=state.current.getHeight(target.position);
				state.addCommand(Command(CommandType.move,renderSide,camera.target,0,target,cameraFacing));
			}
			foreach(_;0..keyDown[KEY_A]){
				if(mouse.status==Mouse.Status.standard){
					mouse.status=Mouse.Status.icon;
					mouse.icon=MouseIcon.guard;
				}
			}
		}
	}

	void stateTestControl()in{
		assert(!!state);
	}do{
		static void applyToMoving(alias f,B)(ObjectState!B state,Camera camera,Target target){
			if(!state.isValidId(camera.target,TargetType.creature)) camera.target=0;
			if(camera.target==0){
				if(!state.isValidId(target.id,target.type)) target=Target.init;
				if(target.type.among(TargetType.none,TargetType.terrain))
					state.eachMoving!f(state);
				else if(target.type==TargetType.creature)
					state.movingObjectById!f(target.id,state);
			}else state.movingObjectById!f(camera.target,state);
		}
		static void depleteMana(B)(ref MovingObject!B obj,ObjectState!B state){
			obj.creatureStats.mana=0.0f;
		}
		if(!eventManager.keyPressed[KEY_LSHIFT] && !eventManager.keyPressed[KEY_LCTRL] && !eventManager.keyPressed[KEY_CAPSLOCK]){
			foreach(_;0..keyDown[KEY_A]) applyToMoving!depleteMana(state.current,camera,mouse.target);
			foreach(_;0..keyDown[KEY_T]) applyToMoving!kill(state.current,camera,mouse.target);
			foreach(_;0..keyDown[KEY_R]) applyToMoving!stun(state.current,camera,mouse.target);
			static void catapultRandomly(B)(ref MovingObject!B object,ObjectState!B state){
				import std.random;
				auto velocity=Vector3f(uniform!"[]"(-20.0f,20.0f), uniform!"[]"(-20.0f,20.0f), uniform!"[]"(10.0f,25.0f));
				//auto velocity=Vector3f(0.0f,0.0f,25.0f);
				object.catapult(velocity,state);
			}
			foreach(_;0..keyDown[KEY_W]) applyToMoving!catapultRandomly(state.current,camera,mouse.target);
			foreach(_;0..keyDown[KEY_RETURN]) applyToMoving!immediateRevive(state.current,camera,mouse.target);
			foreach(_;0..keyDown[KEY_G]) applyToMoving!startFlying(state.current,camera,mouse.target);
			foreach(_;0..keyDown[KEY_V]) applyToMoving!land(state.current,camera,mouse.target);
			if(!eventManager.keyPressed[KEY_LSHIFT]) foreach(_;0..keyDown[KEY_SPACE]){
				//applyToMoving!startMeleeAttacking(state.current,camera,mouse.target);
				static void castingTest(B)(ref MovingObject!B object,ObjectState!B state){
					object.startCasting(3*updateFPS,state);
				}
				applyToMoving!castingTest(state.current,camera,mouse.target);
				/+if(camera.target){
					auto position=state.current.movingObjectById!((obj)=>obj.position,function Vector3f(){ return Vector3f.init; })(camera.target);
					destructionAnimation(position+Vector3f(0,0,5),state.current);
					//explosionAnimation(position+Vector3f(0,0,5),state.current);
				}+/
			}
		}
		foreach(_;0..keyDown[KEY_BACKSPACE]){
			if(eventManager.keyPressed[KEY_LCTRL]||eventManager.keyPressed[KEY_CAPSLOCK]){
				applyToMoving!fastRevive(state.current,camera,mouse.target);
			}else if(!eventManager.keyPressed[KEY_LSHIFT]) applyToMoving!revive(state.current,camera,mouse.target);
		}
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


		if(!eventManager.keyPressed[KEY_LSHIFT] && !eventManager.keyPressed[KEY_LCTRL] && !eventManager.keyPressed[KEY_CAPSLOCK]){
			foreach(_;0..keyDown[KEY_M])
				if(mouse.target.type==TargetType.creature&&mouse.target.id)
					focusCamera(mouse.target.id);
			foreach(_;0..keyDown[KEY_N]) camera.target=0;

			foreach(_;0..keyDown[KEY_Y]) showHitboxes=true;
			foreach(_;0..keyDown[KEY_U]) showHitboxes=false;

			foreach(_;0..keyDown[KEY_H]) state.commit();
			foreach(_;0..keyDown[KEY_B]) state.rollback();

			foreach(_;0..keyDown[KEY_COMMA]) if(audio) audio.switchTheme(cast(Theme)((audio.currentTheme+1)%Theme.max));
		}

		if(camera.target){
			auto creatures=creatureSpells[options.god];
			static immutable hotkeys=[KEY_Q,KEY_Q,KEY_W,KEY_R,KEY_T,KEY_A,KEY_Z,KEY_X,KEY_C,KEY_V,KEY_SPACE];
			if(!eventManager.keyPressed[KEY_LSHIFT] && !(eventManager.keyPressed[KEY_LCTRL]||eventManager.keyPressed[KEY_CAPSLOCK])){
				if(creatures.length)
				foreach(_;0..keyDown[hotkeys[0]]){
					auto id=spawn(camera.target,creatures[0],0,state.current);
					state.current.addToSelection(renderSide,id);
				}
			}
			if(eventManager.keyPressed[KEY_LSHIFT] && !(eventManager.keyPressed[KEY_LCTRL]||eventManager.keyPressed[KEY_CAPSLOCK])){
				foreach(i;1..min(hotkeys.length,creatures.length)){
					foreach(_;0..keyDown[hotkeys[i]]){
						auto id=spawn(camera.target,creatures[i],0,state.current);
						state.current.addToSelection(renderSide,id);
					}
				}
			}
		}
		if(!(eventManager.keyPressed[KEY_LCTRL]||eventManager.keyPressed[KEY_CAPSLOCK]||eventManager.keyPressed[KEY_LSHIFT])){
			if(keyDown[KEY_K]){
				fpview.active=false;
				mouse.visible=true;
			}
			if(keyDown[KEY_L]){
				fpview.active=true;
				mouse.visible=false;
				fpview.mouseFactor=2.0f;
			}
		}
	}

	override void onViewUpdate(double dt){
		if(options.scaleToFit) screenScaling=min(cast(float)eventManager.windowWidth/width,cast(float)eventManager.windowHeight/height);
		super.onViewUpdate(dt);
	}

	override void onLogicsUpdate(double dt){
		assert(dt==1.0f/updateFPS);
		//writeln(DagonBackend.getTotalGPUMemory()," ",DagonBackend.getAvailableGPUMemory());
		//writeln(eventManager.fps);
		if(state) stateTestControl();
		control(dt);
		if(state){
			playAudio=true;
			state.step();
			// state.commit();
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
				updateCameraPosition(dt,targetFacing!=camera.lastTargetFacing && mouse.status!=Mouse.Status.dragging);
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
	Texture whiteTexture;
	ShapeSacCreatureFrame border;
	SacHud!DagonBackend sacHud;
	ShapeSubQuad selectionRoster, minimapFrame, minimapCompass;
	Texture healthColorTexture,manaColorTexture;
	ShapeSacStatsFrame statsFrame;
	ShapeSubQuad creatureTab,spellTab,structureTab,tabSelector;
	ShapeSubQuad creaturePage,spellPage,structurePage;
	ShapeSubQuad spellbookFrame1,spellbookFrame2;
	GenericMaterial hudSoulMaterial;
	GenericMaterial minimapMaterial;
	ShapeSubQuad minimapQuad;
	ShapeSubQuad minimapAltarRing,minimapManalith,minimapWizard,minimapManafount,minimapShrine;
	ShapeSubQuad minimapCreatureArrow,minimapStructureArrow;
	void initializeHUD(){
		quad=New!ShapeQuad(assetManager);
		whiteTexture=DagonBackend.makeTexture(makeOnePixelImage(Color4f(1.0f,1.0f,1.0f)));
		border=New!ShapeSacCreatureFrame(assetManager);
		sacHud=new SacHud!DagonBackend();
		selectionRoster=New!ShapeSubQuad(assetManager,-0.5f,0.0f,0.5f,2.0f);
		healthColorTexture=DagonBackend.makeTexture(makeOnePixelImage(healthColor));
		manaColorTexture=DagonBackend.makeTexture(makeOnePixelImage(manaColor));
		minimapFrame=New!ShapeSubQuad(assetManager,0.5f,0.5f,1.5f,1.5f);
		minimapCompass=New!ShapeSubQuad(assetManager,101.0f/128.0f,24.0f/128.0f,122.0f/128.0f,3.0f/128.0f);
		statsFrame=New!ShapeSacStatsFrame(assetManager);
		creatureTab=New!ShapeSubQuad(assetManager,1.0f/128.0f,0.0f,47.0f/128,48.0f/128.0f);
		spellTab=New!ShapeSubQuad(assetManager,49.0f/128.0f,0.0f,95.0f/128.0f,48.0f/128.0f);
		structureTab=New!ShapeSubQuad(assetManager,1.0f/128.0f,48.0f/128.0f,47.0f/128,96.0f/128.0f);
		tabSelector=New!ShapeSubQuad(assetManager,49.0f/128.0f,48.0f/128.0f,95.0f/128,96.0f/128.0f);
		creaturePage=New!ShapeSubQuad(assetManager,0.0f,0.0f,0.5f,0.5f);
		spellPage=New!ShapeSubQuad(assetManager,0.5f,0.0f,1.0f,0.5f);
		structurePage=New!ShapeSubQuad(assetManager,0.0f,0.5f,0.5f,1.0f);
		spellbookFrame1=New!ShapeSubQuad(assetManager,0.5f,40.0f/128.0f,0.625f,48.0f/128.0f);
		spellbookFrame2=New!ShapeSubQuad(assetManager,80.5f/128.0f,32.5f/128.0f,1.0f,48.0f/128.0f);
		assert(!!sacSoul.texture);
		hudSoulMaterial=createMaterial(hudMaterialBackend2);
		hudSoulMaterial.blending=Transparent;
		hudSoulMaterial.diffuse=sacSoul.texture;
		// minimap
		minimapMaterial=createMaterial(minimapMaterialBackend);
		minimapMaterial.diffuse=Color4f(1.0f,1.0f,1.0f,1.0f);
		minimapMaterial.blending=Transparent;
		minimapQuad=New!ShapeSubQuad(assetManager,16.5f/64.0f,4.5f/65.0f,16.5f/64.0f,4.5f/64.0f);
		minimapAltarRing=New!ShapeSubQuad(assetManager,1.0f/64.0f,1.0/65.0f,11.0f/64.0f,11.0f/64.0f);
		minimapManalith=New!ShapeSubQuad(assetManager,12.0f/64.0f,0.0/65.0f,24.0f/64.0f,12.0f/64.0f);
		minimapWizard=New!ShapeSubQuad(assetManager,25.5f/64.0f,1.0/65.0f,35.5f/64.0f,12.0f/64.0f);
		minimapManafount=New!ShapeSubQuad(assetManager,36.5f/64.0f,1.0/65.0f,47.0f/64.0f,11.0f/64.0f);
		minimapShrine=New!ShapeSubQuad(assetManager,48.0f/64.0f,0.0/65.0f,60.0f/64.0f,12.0f/64.0f);
		minimapCreatureArrow=New!ShapeSubQuad(assetManager,0.0f/64.0f,13.0/65.0f,11.0f/64.0f,24.0f/64.0f);
		minimapStructureArrow=New!ShapeSubQuad(assetManager,12.0f/64.0f,13.0/65.0f,23.0f/64.0f,24.0f/64.0f);
	}
	struct Mouse{
		float x,y;
		float leftButtonX,leftButtonY;
		bool visible,showFrame;
		enum Status{
			standard,
			dragging,
			rectangleSelect,
			icon,
		}
		Status status;
		MouseIcon icon;
		SacSpell!DagonBackend spell;
		bool additiveSelect=false;
		auto cursor=Cursor.normal;
		Target target;
		SacSpell!DagonBackend targetSpell;
		bool targetValid;
		bool inHitbox=false;
		enum Location{
			scene,
			minimap,
			selectionRoster,
			spellbook,
		}
		Location loc;
		@property bool onMinimap(){ return loc==Location.minimap; }
		@property bool onSelectionRoster(){ return loc==Location.selectionRoster; }
		@property bool onSpellbook(){ return loc==Location.spellbook; }
	}
	Mouse mouse;
	bool mouseTargetValid(TargetFlags summary){
		if(mouse.status!=Mouse.Status.icon) return true;
		import spells:SpelFlags;
		enum orderSpelFlags=SpelFlags.targetWizards|SpelFlags.targetCreatures|SpelFlags.targetCorpses|SpelFlags.targetStructures|SpelFlags.targetGround;
		final switch(mouse.icon){
			case MouseIcon.guard: return isApplicable(orderSpelFlags,summary);
			case MouseIcon.attack: return isApplicable(orderSpelFlags,summary);
			case MouseIcon.spell: return mouse.spell.isApplicable(summary);
		}
	}
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
	auto spellbookTarget=Target.init;
	SacSpell!DagonBackend spellbookTargetSpell=null;
	auto selectionRosterTarget=Target.init;
	auto minimapTarget=Target.init;
	Target computeMouseTarget(){
		if(mouse.onSpellbook) return spellbookTarget;
		if(mouse.onSelectionRoster) return selectionRosterTarget;
		if(mouse.onMinimap) return minimapTarget;
		auto information=gbuffer.getInformation();
		auto cur=state.current;
		if(information.x==1){
			Vector3f position=2560.0f*information.yz;
			if(!cur.isOnGround(position)) return Target.init;
			position.z=cur.getGroundHeight(position);
			return Target(TargetType.terrain,0,position,TargetLocation.scene);
		}else if(information.x==2){
			auto id=(cast(int)information.y)<<16|cast(int)information.z;
			if(!state.current.isValidId(id,TargetType.creature)&&!state.current.isValidId(id,TargetType.building)) return Target.init;
			static Target handle(B,T)(T obj,int renderSide,ObjectState!B state){
				enum isMoving=is(T==MovingObject!B);
				static if(isMoving) enum type=TargetType.creature;
				else enum type=TargetType.building;
				return Target(type,obj.id,obj.position,TargetLocation.scene);
			}
			return cur.objectById!handle(id,renderSide,cur);
		}else if(information.x==3){
			auto id=(cast(int)information.y)<<16|cast(int)information.z;
			if(!cur.isValidId(id,TargetType.soul)) return Target.init;
			return Target(TargetType.soul,id,cur.soulById!((soul)=>soul.position,function Vector3f(){ assert(0); })(id),TargetLocation.scene);
		}else return Target.init;
	}
	Target cachedTarget;
	float cachedTargetX,cachedTargetY;
	int cachedTargetFrame;
	enum targetCacheDelta=10.0f;
	enum minimapTargetCacheDelta=2.0f;
	enum targetCacheDuration=0.6f*updateFPS;
	void updateMouseTarget(){
		auto target=computeMouseTarget();
		auto summary=target.summarize(renderSide,state.current);
		auto targetValid=mouseTargetValid(summary);
		static immutable importantTargets=[TargetType.creature,TargetType.soul];
		if(cachedTarget.id!=0&&!state.current.isValidId(cachedTarget.id,cachedTarget.type)) cachedTarget=Target.init;
		if(target.location.among(TargetLocation.scene,TargetLocation.minimap)){
			if(!importantTargets.canFind(target.type)&&!(target.location==TargetLocation.minimap&&target.type==TargetType.building)){
				auto delta=cachedTarget.location!=TargetLocation.minimap?targetCacheDelta:minimapTargetCacheDelta;
				if(cachedTarget.type!=TargetType.none){
					if((mouse.inHitbox || abs(cachedTargetX-mouse.x)<delta &&
					    abs(cachedTargetY-mouse.y)<delta)&&
					   cachedTargetFrame+(mouse.inHitbox?2:1)*targetCacheDuration>state.current.frame){
						target=cachedTarget;
						summary=target.summarize(renderSide,state.current);
						targetValid=mouseTargetValid(summary);
					}else cachedTarget=Target.init;
				}
			}else if(targetValid){
				cachedTarget=target;
				cachedTargetX=mouse.x;
				cachedTargetY=mouse.y;
				cachedTargetFrame=state.current.frame;
			}
		}
		mouse.target=target;
		if(mouse.target.type==TargetType.spell)
			mouse.targetSpell=spellbookTargetSpell;
		mouse.targetValid=targetValid;
		with(Cursor)
			mouse.showFrame=targetValid && target.location==TargetLocation.scene &&
				!(summary&TargetFlags.corpse) &&
				((mouse.status.among(Mouse.Status.standard,Mouse.Status.rectangleSelect) &&
				  summary&(TargetFlags.soul|TargetFlags.creature|TargetFlags.wizard)) ||
				 (mouse.status==Mouse.Status.icon&&!!target.type.among(TargetType.creature,TargetType.building,TargetType.soul)));

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
		updateMouseTarget();
		final switch(mouse.status){
			case Mouse.Status.standard:
				mouse.cursor=mouse.target.cursor(renderSide,false,state.current);
				break;
			case Mouse.Status.dragging:
				mouse.cursor=Cursor.drag;
				break;
			case Mouse.Status.rectangleSelect:
				mouse.cursor=Cursor.rectangleSelect;
				break;
			case Mouse.Status.icon:
				mouse.cursor=mouse.target.cursor(renderSide,true,state.current);
				break;
		}
	}
	override void startGBufferInformationDownload(){
		if(mouse.onMinimap) return;
		static int i=0;
		if(options.printFPS && ((++i)%=2)==0) writeln(eventManager.fps);
		mouse.x=eventManager.mouseX/screenScaling;
		mouse.y=eventManager.mouseY/screenScaling;
		mouse.x=max(0,min(mouse.x,width-1));
		mouse.y=max(0,min(mouse.y,height-1));
		auto x=cast(int)(mouse.x+0.5f), y=cast(int)(height-1-mouse.y+0.5f);
		x=max(0,min(x,width-1));
		y=max(0,min(y,height-1));
		gbuffer.startInformationDownload(x,y);
	}
	override void onUpdate(double dt){
		super.onUpdate(dt);
		if(audio&&state) audio.update(dt,fpview.viewMatrix,state.current);
		updateCursor(dt);
	}
	AudioBackend!DagonBackend audio;
	void initializeAudio(){
		audio=New!(AudioBackend!DagonBackend)(options.volume,options.musicVolume,options.soundVolume);
		audio.switchTheme(Theme.normal);
	}
	~this(){
		if(audio){
			Delete(audio);
			audio=null;
		}
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
		final switch(particle.type) with(ParticleType){
			case manafount, manalith, manahoar, shrine, firy, explosion, explosion2:
				auto mat=scene.createMaterial(scene.shadelessMaterialBackend);
				mat.depthWrite=false;
				mat.blending=Additive;
				mat.energy=particle.energy;
				mat.diffuse=particle.texture;
				mat.color=particle.color;
				return mat;
		}
	}

	std.typecons.Tuple!(Material[],Material[],Material) createMaterials(SacCursor!DagonBackend sacCursor){
		auto materials=new Material[](sacCursor.textures.length);
		foreach(i;0..materials.length){
			auto mat=scene.createMaterial(scene.hudMaterialBackend);
			mat.blending=Transparent;
			mat.diffuse=sacCursor.textures[i];
			materials[i]=mat;
		}
		auto iconMaterials=new Material[](sacCursor.iconTextures.length);
		foreach(i;0..iconMaterials.length){
			auto mat=scene.createMaterial(scene.hudMaterialBackend);
			mat.blending=Transparent;
			mat.diffuse=sacCursor.iconTextures[i];
			iconMaterials[i]=mat;
		}
		auto mat=scene.createMaterial(scene.hudMaterialBackend);
		mat.blending=Transparent;
		mat.diffuse=sacCursor.invalidTargetIconTexture;
		auto invalidTargetIconMaterial=mat;
		return tuple(materials,iconMaterials,invalidTargetIconMaterial);
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

	Material createMaterial(SacCommandCone!DagonBackend sacCommandCone){
		auto material=scene.createMaterial(scene.shadelessMaterialBackend);
		material.depthWrite=false;
		material.blending=Additive;
		material.energy=1.0f;
		//material.diffuse=sacCommandCone.texture;
		//material.diffuse=makeTexture(makeOnePixelImage(Color4f(1.0f,1.0f,1.0f)));
		return material;
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


	enum hasAudio=true;
	@property AudioBackend!DagonBackend audio(){
		return scene.audio;
	}
	void loopingSoundSetup(StaticObject!DagonBackend object){
		if(audio) audio.loopingSoundSetup(object);
	}
	void deleteLoopingSounds(){
		if(audio) audio.deleteLoopingSounds();
	}
	void updateAudioAfterRollback(){
		if(audio&&scene.state) audio.updateAudioAfterRollback(scene.state.current);
	}
	void queueDialogSound(int side,char[4] sound,DialogPriority priority){
		if(!audio||side!=-1&&side!=scene.renderSide) return;
		audio.queueDialogSound(sound,priority);
	}
	int getSoundDuration(char[4] sound){
		return AudioBackend!DagonBackend.getDuration(sound);
	}
	void playSound(int side,char[4] sound,float gain=1.0f){
		if(!audio||side!=-1&&side!=scene.renderSide) return;
		audio.playSound(sound,gain);
	}
	void playSoundAt(char[4] sound,Vector3f position,float gain=1.0f){
		if(!audio) return;
		audio.playSoundAt(sound,position,gain);
	}
	void playSoundAt(char[4] sound,int id,float gain=1.0f){
		if(!audio) return;
		audio.playSoundAt(sound,id,gain);
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

		texcoords[0] = Vector2f(0.5, 0.25-1.0/128);
		texcoords[1] = Vector2f(0.5, 0);
		texcoords[2] = Vector2f(0.75-1.0/128, 0);
		texcoords[3] = Vector2f(0.75-1.0/128, 0.25-1.0/128);

		texcoords[4] = Vector2f(0.5, 1.0/128);
		texcoords[5] = Vector2f(0.5, 0.25-0.5/128);
		texcoords[6] = Vector2f(0.75-1.0/128, 0.25-0.5/128);
		texcoords[7] = Vector2f(0.75-1.0/128, 1.0/128);

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

class ShapeSubSphere: Mesh
{
    DynamicArray!Vector3f daVertices;
    DynamicArray!Vector3f daNormals;
    DynamicArray!Vector2f daTexcoords;
    DynamicArray!(uint[3]) daIndices;

	this(float radius, int slices, int stacks, bool invNormals, Owner o,float left,float top,float right,float bottom)
    {
        super(o);

        float X1, Y1, X2, Y2, Z1, Z2;
        float inc1, inc2, inc3, inc4, inc5, radius1, radius2;
        uint[3] tri;
        uint i = 0;

        float cuts = stacks;
        float invCuts = 1.0f / cuts;
        float heightStep = 2.0f * invCuts;

        float invSlices = 1.0f / slices;
        float angleStep = (2.0f * PI) * invSlices;

        for(int h = 0; h < stacks; h++)
        {
            float h1Norm = cast(float)h * invCuts * 2.0f - 1.0f;
            float h2Norm = cast(float)(h+1) * invCuts * 2.0f - 1.0f;
            float y1 = sin(HALF_PI * h1Norm);
            float y2 = sin(HALF_PI * h2Norm);

            float circleRadius1 = cos(HALF_PI * y1);
            float circleRadius2 = cos(HALF_PI * y2);

            auto curBottom=bottom+(top-bottom)*h/stacks;
            auto curTop=bottom+(top-bottom)*(h+1)/stacks;

            for(int a = 0; a < slices; a++)
            {
	            auto curLeft=left+(right-left)*a/slices;
	            auto curRight=left+(right-left)*(a+1)/slices;
                float x1a = sin(angleStep * a) * circleRadius1;
                float z1a = cos(angleStep * a) * circleRadius1;
                float x2a = sin(angleStep * (a + 1)) * circleRadius1;
                float z2a = cos(angleStep * (a + 1)) * circleRadius1;

                float x1b = sin(angleStep * a) * circleRadius2;
                float z1b = cos(angleStep * a) * circleRadius2;
                float x2b = sin(angleStep * (a + 1)) * circleRadius2;
                float z2b = cos(angleStep * (a + 1)) * circleRadius2;

                Vector3f v1 = Vector3f(x1a, z1a, y1);
                Vector3f v2 = Vector3f(x2a, z2a, y1);
                Vector3f v3 = Vector3f(x1b, z1b, y2);
                Vector3f v4 = Vector3f(x2b, z2b, y2);

                Vector3f n1 = v1.normalized;
                Vector3f n2 = v2.normalized;
                Vector3f n3 = v3.normalized;
                Vector3f n4 = v4.normalized;

                daVertices.append(n1 * radius);
                daVertices.append(n2 * radius);
                daVertices.append(n3 * radius);

                daVertices.append(n3 * radius);
                daVertices.append(n2 * radius);
                daVertices.append(n4 * radius);

                float sign = invNormals? -1.0f : 1.0f;

                daNormals.append(n1 * sign);
                daNormals.append(n2 * sign);
                daNormals.append(n3 * sign);

                daNormals.append(n3 * sign);
                daNormals.append(n2 * sign);
                daNormals.append(n4 * sign);

                auto uv1 = Vector2f(curLeft,curBottom);
                auto uv2 = Vector2f(curRight,curBottom);
                auto uv3 = Vector2f(curLeft,curTop);
                auto uv4 = Vector2f(curRight,curTop);

                daTexcoords.append(uv1);
                daTexcoords.append(uv2);
                daTexcoords.append(uv3);

                daTexcoords.append(uv3);
                daTexcoords.append(uv2);
                daTexcoords.append(uv4);

                if (invNormals)
                {
                    tri[0] = i+2;
                    tri[1] = i+1;
                    tri[2] = i;
                    daIndices.append(tri);

                    tri[0] = i+5;
                    tri[1] = i+4;
                    tri[2] = i+3;
                    daIndices.append(tri);
                }
                else
                {
                    tri[0] = i;
                    tri[1] = i+1;
                    tri[2] = i+2;
                    daIndices.append(tri);

                    tri[0] = i+3;
                    tri[1] = i+4;
                    tri[2] = i+5;
                    daIndices.append(tri);
                }

                i += 6;
            }
        }

        /*
        for(int w = 0; w < resolution; w++)
        {


            for(int h = (-resolution/2); h < (resolution/2); h++)
            {
                inc1 = (w/cast(float)resolution)*2*PI;
                inc2 = ((w+1)/cast(float)resolution)*2*PI;

                inc3 = (h/cast(float)resolution)*PI;
                inc4 = ((h+1)/cast(float)resolution)*PI;

                X1 = sin(inc1);
                Y1 = cos(inc1);
                X2 = sin(inc2);
                Y2 = cos(inc2);

                radius1 = radius*cos(inc3);
                radius2 = radius*cos(inc4);

                Z1 = radius*sin(inc3);
                Z2 = radius*sin(inc4);

                daVertices.append(Vector3f(radius1*X1,Z1,radius1*Y1));
                daVertices.append(Vector3f(radius1*X2,Z1,radius1*Y2));
                daVertices.append(Vector3f(radius2*X2,Z2,radius2*Y2));

                daVertices.append(Vector3f(radius1*X1,Z1,radius1*Y1));
                daVertices.append(Vector3f(radius2*X2,Z2,radius2*Y2));
                daVertices.append(Vector3f(radius2*X1,Z2,radius2*Y1));

                auto uv1 = Vector2f(0, 0);
                auto uv2 = Vector2f(0, 1);
                auto uv3 = Vector2f(1, 1);
                auto uv4 = Vector2f(1, 0);

                daTexcoords.append(uv1);
                daTexcoords.append(uv2);
                daTexcoords.append(uv3);

                daTexcoords.append(uv1);
                daTexcoords.append(uv3);
                daTexcoords.append(uv4);

                float sign = invNormals? -1.0f : 1.0f;

                auto n1 = Vector3f(X1,Z1,Y1).normalized;
                auto n2 = Vector3f(X2,Z1,Y2).normalized;
                auto n3 = Vector3f(X2,Z2,Y2).normalized;
                auto n4 = Vector3f(X1,Z2,Y1).normalized;

                daNormals.append(n1 * sign);
                daNormals.append(n2 * sign);
                daNormals.append(n3 * sign);

                daNormals.append(n1 * sign);
                daNormals.append(n3 * sign);
                daNormals.append(n4 * sign);

                if (invNormals)
                {
                    tri[0] = i+2;
                    tri[1] = i+1;
                    tri[2] = i;
                    daIndices.append(tri);

                    tri[0] = i+5;
                    tri[1] = i+4;
                    tri[2] = i+3;
                    daIndices.append(tri);
                }
                else
                {
                    tri[0] = i;
                    tri[1] = i+1;
                    tri[2] = i+2;
                    daIndices.append(tri);

                    tri[0] = i+3;
                    tri[1] = i+4;
                    tri[2] = i+5;
                    daIndices.append(tri);
                }

                i += 6;
            }
        }
        */

        vertices = New!(Vector3f[])(daVertices.length);
        vertices[] = daVertices.data[];

        normals = New!(Vector3f[])(daNormals.length);
        normals[] = daNormals.data[];

        texcoords = New!(Vector2f[])(daTexcoords.length);
        texcoords[] = daTexcoords.data[];

        indices = New!(uint[3][])(daIndices.length);
        indices[] = daIndices.data[];

        daVertices.free();
        daNormals.free();
        daTexcoords.free();
        daIndices.free();

        dataReady = true;
        prepareVAO();
    }
}
