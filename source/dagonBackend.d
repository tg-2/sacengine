import dagon;
import dlib.math.portable;
import options,util;
import std.stdio;
import std.algorithm, std.range, std.exception, std.typecons, std.conv;

import sacobject, sacspell, mrmm, nttData, sacmap, maps, state, controller, network;
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
	Controller!DagonBackend controller;
	DynamicArray!(SacObject!DagonBackend) sacs;
	Entity[] skyEntities;
	alias createSky=typeof(super).createSky;
	SacSky!DagonBackend sacSky;
	void createSky(){
		sacSky=new SacSky!DagonBackend();
	}
	SacSoul!DagonBackend sacSoul;
	void createSouls(){
		sacSoul=new SacSoul!DagonBackend();
	}
	SacObject!DagonBackend sacDebris;
	SacExplosion!DagonBackend createExplosion(){
		enum nU=4,nV=4;
		auto texture=typeof(return).loadTexture();
		auto mat=createMaterial(shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=Additive;
		mat.energy=1.0f;
		mat.diffuse=texture;
		ShapeSubSphere[16] frames;
		foreach(i,ref frame;frames){
			int u=cast(int)i%nU,v=cast(int)i/nU;
			frame=new ShapeSubSphere(1.0f,25,25,true,null,1.0f/nU*u,1.0f/nV*v,1.0f/nU*(u+1),1.0f/nV*(v+1));
		}
		return SacExplosion!DagonBackend(texture,mat,frames);
	}
	SacExplosion!DagonBackend explosion;
	SacBlueRing!DagonBackend createBlueRing(){
		auto texture=typeof(return).loadTexture();
		auto mat=createMaterial(shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=Additive;
		mat.energy=20.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacBlueRing!DagonBackend(texture,mat,frames);
	}
	SacBlueRing!DagonBackend blueRing;
	SacVortex!DagonBackend createVortex(){
		SacVortex!DagonBackend result;
		result.loadTextures();
		result.rimMeshes=typeof(return).createRimMeshes();
		result.redRimMat=createMaterial(shadelessMaterialBackend);
		result.redRimMat.depthWrite=false;
		result.redRimMat.blending=Additive;
		result.redRimMat.energy=10.0f;
		result.redRimMat.diffuse=result.redRim;
		result.blueRimMat=createMaterial(shadelessMaterialBackend);
		result.blueRimMat.depthWrite=false;
		result.blueRimMat.blending=Additive;
		result.blueRimMat.energy=10.0f;
		result.blueRimMat.diffuse=result.blueRim;
		result.centerMeshes=typeof(return).createCenterMeshes();
		result.redCenterMat=createMaterial(shadelessMaterialBackend);
		result.redCenterMat.depthWrite=false;
		result.redCenterMat.blending=Additive;
		result.redCenterMat.energy=1.0f;
		result.redCenterMat.diffuse=result.redCenter;
		result.blueCenterMat=createMaterial(shadelessMaterialBackend);
		result.blueCenterMat.depthWrite=false;
		result.blueCenterMat.blending=Additive;
		result.blueCenterMat.energy=1.0f;
		result.blueCenterMat.diffuse=result.blueCenter;
		return result;
	}
	SacVortex!DagonBackend vortex;
	SacTether!DagonBackend createTether(){
		auto texture=typeof(return).loadTexture();
		auto mat=createMaterial(shadelessBoneMaterialBackend);
		mat.depthWrite=false;
		mat.blending=Additive;
		mat.energy=15.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacTether!DagonBackend(texture,mat,frames);
	}
	SacTether!DagonBackend tether;
	SacGuardianTether!DagonBackend createGuardianTether(){
		auto texture=typeof(return).loadTexture();
		auto mat=createMaterial(shadelessBoneMaterialBackend);
		mat.depthWrite=false;
		mat.blending=Additive;
		mat.energy=5.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacGuardianTether!DagonBackend(texture,mat,frames);
	}
	SacGuardianTether!DagonBackend guardianTether;
	SacLightning!DagonBackend createLightning(){
		auto texture=typeof(return).loadTexture();
		auto mat=createMaterial(shadelessBoneMaterialBackend);
		mat.depthWrite=false;
		mat.blending=Additive;
		mat.energy=15.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacLightning!DagonBackend(texture,mat,frames);
	}
	SacLightning!DagonBackend lightning;
	SacWrath!DagonBackend createWrath(){
		auto texture=typeof(return).loadTexture();
		auto mat=createMaterial(shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=Additive;
		mat.energy=20.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacWrath!DagonBackend(texture,mat,frames);
	}
	SacWrath!DagonBackend wrath;
	SacCommandCone!DagonBackend sacCommandCone;
	SacObject!DagonBackend rock;
	SacBug!DagonBackend bug;
	SacBug!DagonBackend createBug(){
		auto texture=typeof(return).loadTexture();
		auto mat=createMaterial(shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=Transparent;
		mat.energy=1.0f;
		mat.diffuse=texture;
		auto mesh=typeof(return).createMesh();
		return SacBug!DagonBackend(texture,mat,mesh);
	}
	SacBrainiacEffect!DagonBackend brainiacEffect;
	SacBrainiacEffect!DagonBackend createBrainiacEffect(){
		auto texture=typeof(return).loadTexture();
		auto mat=createMaterial(shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=Transparent;
		mat.energy=20.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacBrainiacEffect!DagonBackend(texture,mat,frames);
	}
	SacShrikeEffect!DagonBackend shrikeEffect;
	SacShrikeEffect!DagonBackend createShrikeEffect(){
		auto texture=typeof(return).loadTexture();
		auto mat=createMaterial(shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=Additive;
		mat.energy=15.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacShrikeEffect!DagonBackend(texture,mat,frames);
	}
	SacArrow!DagonBackend arrow;
	SacArrow!DagonBackend createArrow(){
		auto sylphTexture=typeof(return).loadSylphTexture();
		auto smat=createMaterial(shadelessMaterialBackend);
		smat.depthWrite=false;
		smat.blending=Additive;
		smat.energy=30.0f;
		smat.diffuse=sylphTexture;
		auto rangerTexture=typeof(return).loadRangerTexture();
		auto rmat=createMaterial(shadelessMaterialBackend);
		rmat.depthWrite=false;
		rmat.blending=Additive;
		rmat.energy=45.0f;
		rmat.diffuse=rangerTexture;
		auto frames=typeof(return).createMeshes();
		return SacArrow!DagonBackend(sylphTexture,smat,rangerTexture,rmat,frames);
	}
	SacLifeShield!DagonBackend lifeShield;
	SacLifeShield!DagonBackend createLifeShield(){
		enum nU=4,nV=4;
		import txtr;
		auto texture=typeof(return).loadTexture();
		auto mat=createMaterial(shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=Additive;
		mat.energy=10.0f;
		mat.diffuse=texture;
		ShapeSubSphere[16] frames;
		foreach(i,ref frame;frames){
			int u=cast(int)i%nU,v=cast(int)i/nU;
			frame=new ShapeSubSphere(0.5f,25,25,true,null,1.0f/nU*u,1.0f/nV*v,1.0f/nU*(u+1),1.0f/nV*(v+1),true);
		}
		return SacLifeShield!DagonBackend(texture,mat,frames);
	}
	SacDivineSight!DagonBackend divineSight;
	SacDivineSight!DagonBackend createDivineSight(){
		auto texture=typeof(return).loadTexture();
		auto mat=createMaterial(shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=Transparent;
		mat.energy=3.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacDivineSight!DagonBackend(texture,mat,frames);
	}
	void createEffects(){
		sacCommandCone=new SacCommandCone!DagonBackend();
		sacDebris=new SacObject!DagonBackend("extracted/models/MODL.WAD!/bold.MRMC/bold.MRMM");
		explosion=createExplosion();
		blueRing=createBlueRing();
		vortex=createVortex();
		tether=createTether();
		guardianTether=createGuardianTether();
		lightning=createLightning();
		wrath=createWrath();
		rock=new SacObject!DagonBackend("extracted/models/MODL.WAD!/rock.MRMC/rock.MRMM");
		bug=createBug();
		brainiacEffect=createBrainiacEffect();
		shrikeEffect=createShrikeEffect();
		arrow=createArrow();
		lifeShield=createLifeShield();
		divineSight=createDivineSight();
	}

	void setupEnvironment(SacMap!DagonBackend map){
		auto env=environment;
		auto envi=&map.envi;
		//writeln(envi.sunDirectStrength," ",envi.sunAmbientStrength);
		float sunStrength;
		final switch(map.tileset) with(Tileset){
			case ethereal: sunStrength=6.0f; break;
			case persephone: sunStrength=6.0f; break;
			case pyro: sunStrength=2.0f; break;
			case james: sunStrength=14.0f; break;
			case stratos: sunStrength=12.0f; break;
			case charnel: sunStrength=4.0f; break;
		}
		env.sunEnergy=min(sunStrength*envi.sunDirectStrength,30.0f)*options.sunFactor;
		Color4f fixColor(Color4f sacColor){
			return Color4f(0,0.3,1,1)*0.2+sacColor*0.8;
		}
		//env.ambientConstant = fixColor(Color4f(envi.ambientRed*ambi,envi.ambientGreen*ambi,envi.ambientBlue*ambi,1.0f));
		auto ambi=min(envi.sunAmbientStrength,2.0f)*options.ambientFactor;
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

	final void renderSky(RenderingContext* rc){
		auto totalTime=state.current.frame*1.0f/updateFPS;
		sacSkyMaterialBackend.sunLoc = sacSky.sunSkyRelLoc(fpview.camera.position);
		sacSkyMaterialBackend.cloudOffset=state.current.frame%(64*updateFPS)*1.0f/(64*updateFPS)*Vector2f(1.0f,-1.0f);
		auto skyRotation=rotationQuaternion(Axis.z,2*pi!float/512.0f*totalTime);
		auto map=state.current.map;
		auto x=10.0f*map.n/2, y=10.0f*map.m/2;
		auto skyPosition=Vector3f(x,y,sacSky.dZ*sacSky.scaling+1);
		auto envi=&map.envi;
		auto backend0=shadelessMaterialBackend;
		backend0.bind(null,rc);
		glDepthMask(GL_TRUE); // TODO: avoid setting this twice?
		backend0.setInformation(Vector4f(0.0f,0.0f,0.0f,0.0f));
		backend0.setEnergy(sacSky.energy);
		backend0.setTransformation(skyPosition,skyRotation,rc);
		backend0.bindDiffuse(map.textures[skybIndex]);
		sacSky.skyb.render(rc);
		backend0.bindDiffuse(map.textures[skytIndex]);
		sacSky.skyt.render(rc);
		backend0.bindDiffuse(map.textures[undrIndex]);
		sacSky.undr.render(rc);
		auto backend1=sacSunMaterialBackend;
		backend1.bind(null,rc);
		backend1.setAlpha(1.0f);
		backend1.setEnergy(25.0f*sacSky.energy);
		backend1.bindDiffuse(map.textures[sunIndex]);
		backend1.setTransformation(skyPosition,Quaternionf.identity(),rc); // TODO: don't create rotation matrix
		sacSky.sun.render(rc);
		auto backend2=sacSkyMaterialBackend;
		backend2.bind(null,rc);
		backend2.setAlpha(min(map.envi.maxAlphaFloat,1.0f));
		backend2.setEnergy(sacSky.energy);
		backend2.bindDiffuse(map.textures[skyIndex]);
		backend2.setTransformation(skyPosition,Quaternionf.identity(),rc); // TODO: don't create rotation matrix
		sacSky.sky.render(rc);
	}

	final void renderMap(RenderingContext* rc){
		auto map=state.current.map;
		rc.layer=1;
		rc.modelMatrix=Matrix4x4f.identity();
		rc.invModelMatrix=Matrix4x4f.identity();
		rc.prevModelViewProjMatrix=Matrix4x4f.identity(); // TODO: get rid of this?
		rc.modelViewMatrix=rc.viewMatrix*rc.modelMatrix;
		rc.blurModelViewProjMatrix=rc.projectionMatrix*rc.modelViewMatrix; // TODO: get rid of this
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
		/+auto pathFinder=state.current.pathFinder;
		foreach(y;0..511){
			foreach(x;0..511){
				if(!pathFinder.unblocked(x,y,state.current)) continue;
				auto p=pathFinder.position(x,y,state.current);
				renderBox([p-Vector3f(1.0f,1.0f,1.0f),p+Vector3f(1.0f,1.0f,1.0f)],false,rc);
			}
		}+/
	}

	final void renderNTTs(RenderMode mode)(RenderingContext* rc){
		static void render(T)(ref T objects,bool enableWidgets,SacScene scene,RenderingContext* rc){ // TODO: why does this need to be static? DMD bug?
			static if(is(typeof(objects.sacObject))){
				auto sacObject=objects.sacObject;
				enum isMoving=is(T==MovingObjects!(DagonBackend, renderMode), RenderMode renderMode);
				enum isStatic=is(T==StaticObjects!(DagonBackend, renderMode), RenderMode renderMode);
				static if(is(T==FixedObjects!DagonBackend)) if(!enableWidgets) return;

				static if(objects.renderMode==RenderMode.opaque){
					enum prepareMaterials=RenderMode.opaque;
				}else{
					static if(isStatic){
						enum prepareMaterials=mode;
					}else{
						enum prepareMaterials=RenderMode.transparent;
					}
				}
				static if(prepareMaterials==RenderMode.opaque){
					auto materials=rc.shadowMode?sacObject.shadowMaterials:sacObject.materials;
				}else static if(prepareMaterials==RenderMode.transparent){
					auto opaqueMaterials=rc.shadowMode?sacObject.shadowMaterials:sacObject.materials;
					auto materials=rc.shadowMode?sacObject.shadowMaterials:sacObject.transparentMaterials;
				}else static assert(0);
				foreach(i;0..materials.length){
					auto material=materials[i];
					if(!material) continue;
					auto blending=("blending" in material.inputs).asInteger;
					if((mode==RenderMode.transparent)!=(blending==Additive||blending==Transparent)) continue;
					if(rc.shadowMode&&blending==Additive) continue;
					static if(isStatic&&objects.renderMode==RenderMode.transparent){
						auto originalBackend=material.backend;
						static if(mode==RenderMode.opaque) material.backend=scene.buildingSummonMaterialBackend1;
						else material.backend=scene.buildingSummonMaterialBackend2;
						scope(success) material.backend=originalBackend;
					}
					material.bind(rc);
					scope(success) material.unbind(rc);
					static if(isMoving){
						auto mesh=sacObject.saxsi.meshes[i];
						foreach(j;0..objects.length){ // TODO: use instanced rendering instead
							if(rc.shadowMode&&objects.creatureStatss[j].effects.stealth) continue;
							material.backend.setTransformation(objects.positions[j], objects.rotations[j], rc);
							auto id=objects.ids[j];
							Vector4f information;
							if(scene.renderSide!=objects.sides[j]&&objects.creatureStates[j].mode.isGhost) continue;
							if(scene.renderSide!=objects.sides[j]&&(!objects.creatureStates[j].mode.isVisibleToOtherSides||objects.creatureStatss[j].effects.stealth)){
								information=Vector4f(0.0f,0.0f,0.0f,0.0f);
							}else information=Vector4f(2.0f,id>>16,id&((1<<16)-1),1.0f);
							material.backend.setInformation(information);
							static if(prepareMaterials==RenderMode.transparent){
								scene.shadelessBoneMaterialBackend.setAlpha(objects.alphas[j]);
								scene.shadelessBoneMaterialBackend.setEnergy(objects.energies[j]);
							}
							// TODO: interpolate animations to get 60 FPS?
							sacObject.setFrame(objects.animationStates[j],objects.frames[j]/updateAnimFactor);
							mesh.render(rc);
						}
					}else{
						material.backend.setInformation(Vector4f(0.0f,0.0f,0.0f,0.0f));
						auto mesh=sacObject.meshes[i];
						static if(isStatic&&objects.renderMode==RenderMode.transparent&&mode==RenderMode.transparent){
							auto opaqueMaterial=opaqueMaterials[i];
							auto opaqueBlending=("blending" in opaqueMaterial.inputs).asInteger;
							bool enableDiscard=opaqueBlending!=Transparent;
							if(!enableDiscard) scene.buildingSummonMaterialBackend2.setEnableDiscard(false);
							scope(success) if(!enableDiscard) scene.buildingSummonMaterialBackend2.setEnableDiscard(true);
						}
						foreach(j;0..objects.length){
							static if(isStatic&&objects.renderMode==RenderMode.transparent){
								auto thresholdZ=objects.thresholdZs[j];
								static if(mode==RenderMode.opaque){
									scene.buildingSummonMaterialBackend1.setThresholdZ(thresholdZ);
								}else static if(mode==RenderMode.transparent){
									scene.buildingSummonMaterialBackend2.setThresholdZ(thresholdZ,thresholdZ+structureCastingGradientSize);
								}else static assert(0);
							}
							static if(isStatic){
								material.backend.setTransformationScaled(objects.positions[j], objects.rotations[j], objects.scales[j]*Vector3f(1.0f,1.0f,1.0f), rc);
							}else material.backend.setTransformation(objects.positions[j], objects.rotations[j], rc);
							static if(isStatic){
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
								auto position=soul.position+rotate(facingQuaternion(objects[j].facing+2*pi!float*k/number), Vector3f(0.0f,radius,0.0f));
								material.backend.setSpriteTransformationScaled(position+soul.scaling*Vector3f(0.0f,0.0f,1.25f*sacSoul.soulHeight),soul.scaling*soulScaling,rc);
								mesh.render(rc);
							}
						}
					}
				}
			}else static if(is(T==Buildings!DagonBackend)){
				// do nothing
			}else static if(is(T==Effects!DagonBackend)){
				static if(mode==RenderMode.opaque) if(objects.debris.length||objects.fireballCastings.length||objects.fireballs.length){
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
						foreach(j;0..objects.fireballCastings.length){
							auto scale=0.25f*min(1.0f,objects.fireballCastings[j].frame/(objects.fireballCastings[j].fireball.spell.castingTime(9)*updateFPS));
							material.backend.setTransformationScaled(objects.fireballCastings[j].fireball.position,objects.fireballCastings[j].fireball.rotation,scale*Vector3f(1.0f,1.0f,1.0f),rc);
							mesh.render(rc);
						}
						foreach(j;0..objects.fireballs.length){
							material.backend.setTransformationScaled(objects.fireballs[j].position,objects.fireballs[j].rotation,0.25f*Vector3f(1.0f,1.0f,1.0f),rc);
							mesh.render(rc);
						}
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.explosions.length){
					auto material=scene.explosion.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					foreach(j;0..objects.explosions.length){
						auto mesh=scene.explosion.getFrame(objects.explosions[j].frame);
						material.backend.setTransformationScaled(objects.explosions[j].position,Quaternionf.identity(),objects.explosions[j].scale*Vector3f(1.1f,1.1f,0.9f),rc);
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&(objects.sacDocCastings.length||objects.rituals.length)){
					auto centerMat=scene.vortex.redCenterMat;
					void renderRedCenter(ref RedVortex vortex){
						centerMat.backend.setSpriteTransformationScaled(vortex.position,vortex.scale*vortex.radius,rc);
						auto mesh=scene.vortex.getCenterFrame(vortex.frame%scene.vortex.numRimFrames);
						mesh.render(rc);
					}
					auto rimMat=scene.vortex.redRimMat;
					void renderRedRim(ref RedVortex vortex){
						rimMat.backend.setSpriteTransformationScaled(vortex.position,vortex.scale*vortex.radius,rc);
						auto mesh=scene.vortex.getRimFrame(vortex.frame%scene.vortex.numRimFrames);
						mesh.render(rc);
					}
					centerMat.bind(rc);
					foreach(j;0..objects.sacDocCastings.length) renderRedCenter(objects.sacDocCastings[j].vortex);
					foreach(j;0..objects.rituals.length) if(!isNaN(objects.rituals[j].vortex.position.x)) renderRedCenter(objects.rituals[j].vortex);
					centerMat.unbind(rc);
					rimMat.bind(rc);
					foreach(j;0..objects.sacDocCastings.length) renderRedRim(objects.sacDocCastings[j].vortex);
					foreach(j;0..objects.rituals.length) if(!isNaN(objects.rituals[j].vortex.position.x)) renderRedRim(objects.rituals[j].vortex);
					rimMat.unbind(rc);
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.sacDocCarries.length){
					auto getPositionAndScaleForId(int id,float scale){
						alias H=Vector3f[2];
						auto hitbox=scene.state.current.movingObjectById!((ref obj)=>obj.hitbox,()=>H.init)(id);
						auto size=boxSize(hitbox);
						return tuple(boxCenter(hitbox),scale*0.65f*Vector3f(1.1f*size.length,0.9f*size.length,0.0f)); // TODO
					}
					auto centerMat=scene.vortex.blueCenterMat;
					void renderBlueCenter(Vector3f position,Vector3f scale,int frame){
						if(isNaN(position.x)) return;
						centerMat.backend.setSpriteTransformationScaled(position,scale,rc);
						auto mesh=scene.vortex.getCenterFrame(frame%scene.vortex.numRimFrames);
						mesh.render(rc);
					}
					void renderBlueCenterForId(int id,float scale,int frame){
						if(!id) return;
						return renderBlueCenter(getPositionAndScaleForId(id,scale).expand,frame);
					}
					auto rimMat=scene.vortex.blueRimMat;
					void renderBlueRim(Vector3f position,Vector3f scale,int frame){
						if(isNaN(position.x)) return;
						rimMat.backend.setSpriteTransformationScaled(position,scale,rc);
						auto mesh=scene.vortex.getRimFrame(frame%scene.vortex.numRimFrames);
						mesh.render(rc);
					}
					void renderBlueRimForId(int id,float scale,int frame){
						if(!id) return;
						return renderBlueRim(getPositionAndScaleForId(id,scale).expand,frame);
					}
					centerMat.bind(rc);
					foreach(j;0..objects.sacDocCarries.length)
						if(objects.sacDocCarries[j].status.among(SacDocCarryStatus.move,SacDocCarryStatus.shrinking))
							renderBlueCenterForId(objects.sacDocCarries[j].creature,objects.sacDocCarries[j].vortexScale,objects.sacDocCarries[j].frame);
					centerMat.unbind(rc);
					rimMat.bind(rc);
					foreach(j;0..objects.sacDocCarries.length)
						if(objects.sacDocCarries[j].status.among(SacDocCarryStatus.move,SacDocCarryStatus.shrinking))
							renderBlueRimForId(objects.sacDocCarries[j].creature,objects.sacDocCarries[j].vortexScale,objects.sacDocCarries[j].frame);
					rimMat.unbind(rc);
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&(objects.sacDocCarries.length||objects.rituals.length)){
					auto material=scene.tether.material;
					material.bind(rc);
					glDisable(GL_CULL_FACE);
					scope(success){
						glEnable(GL_CULL_FACE);
						material.unbind(rc);
					}
					scene.shadelessBoneMaterialBackend.setTransformation(Vector3f(0.0f,0.0f,0.0f),Quaternionf.identity(),rc);
					void renderTether(ref SacDocTether tether,int frame){
						if(isNaN(tether.locations[0].x)) return;
						auto alpha=pi!float*frame/updateFPS;
						auto energy=0.375f+14.625f*(0.5f+0.25f*cos(7.0f*alpha)+0.25f*sin(11.0f*alpha));
						scene.shadelessBoneMaterialBackend.setEnergy(energy);
						auto mesh=scene.tether.getFrame(frame%scene.tether.numFrames);
						Matrix4x4f[scene.tether.numSegments+1] pose;
						foreach(i,ref x;pose){
							auto curve = tether.get(i/float(pose.length-1));
							auto rotation=rotationBetween(Vector3f(0.0f,0.0f,1.0f),curve[1].normalized);
							x=Transformation(rotation,curve[0]).getMatrix4f;
						}
						mesh.pose=pose[];
						scope(exit) mesh.pose=[];
						mesh.render(rc);
					}
					foreach(j;0..objects.sacDocCarries.length) renderTether(objects.sacDocCarries[j].tether,objects.sacDocCarries[j].frame);
					foreach(j;0..objects.rituals.length) foreach(k;0..4) renderTether(objects.rituals[j].tethers[k],objects.rituals[j].frame);
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.guardians.length){
					auto material=scene.guardianTether.material;
					material.bind(rc);
					glDisable(GL_CULL_FACE);
					scope(success){
						glEnable(GL_CULL_FACE);
						material.unbind(rc);
					}
					void renderGuardianTether(ref Guardian guardian){
						with(guardian){
							auto diff=end-start;
							auto len=diff.length;
							auto rotation=rotationBetween(Vector3f(0.0f,0.0f,1.0f),diff/len);
							auto pulse=0.75f+0.25f*0.5f*(1.0f+sin(2.0f*pi!float*(frame%pulseFrames)/(pulseFrames-1)));
							scene.shadelessBoneMaterialBackend.setTransformationScaled(start,rotation,Vector3f(pulse,pulse,(1.0f/1.5f)*len),rc);
							auto mesh=scene.guardianTether.getFrame(frame%scene.guardianTether.numFrames);
							Matrix4x4f[scene.guardianTether.numSegments+1] pose;
							pose[0]=pose[scene.guardianTether.numSegments]=Matrix4f.identity();
							foreach(i,ref x;pose[1..$-1]){
								auto curve=get(i/float(pose.length-1));
								x=Transformation(Quaternionf.identity(),curve[0]).getMatrix4f;
							}
							mesh.pose=pose[];
							scope(exit) mesh.pose=[];
							mesh.render(rc);
						}
					}
					foreach(ref guardian;objects.guardians) renderGuardianTether(guardian);
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&(objects.blueRings.length||objects.teleportRings.length)){
					auto material=scene.blueRing.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					foreach(j;0..objects.blueRings.length){
						auto position=objects.blueRings[j].position;
						auto scale=objects.blueRings[j].scale;
						scene.shadelessMaterialBackend.setTransformationScaled(position,Quaternionf.identity(),scale*Vector3f(1.0f,1.0f,1.0f),rc);
						scene.shadelessMaterialBackend.setEnergy(20.0f*scale^^4);
						auto mesh=scene.blueRing.getFrame(objects.blueRings[j].frame%scene.blueRing.numFrames);
						mesh.render(rc);
					}
					foreach(j;0..objects.teleportRings.length){
						auto position=objects.teleportRings[j].position;
						auto scale=objects.teleportRings[j].scale*sqrt(1.0f-float(objects.teleportRings[j].frame)/teleportRingLifetime);
						scene.shadelessMaterialBackend.setTransformationScaled(position,Quaternionf.identity(),0.08f*scale*Vector3f(1.0f,1.0f,1.0f),rc);
						scene.shadelessMaterialBackend.setEnergy(20.0f*scale^^2);
						auto mesh=scene.blueRing.getFrame(objects.teleportRings[j].frame%scene.blueRing.numFrames);
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode){
					foreach(j;0..objects.speedUpShadows.length){
						if((objects.speedUpShadows[j].age+1)%speedUpShadowSpacing!=0) continue;
						auto id=objects.speedUpShadows[j].creature;
						auto state=scene.state.current;
						if(!state.isValidTarget(id,TargetType.creature)) continue;
						auto sacObject=state.movingObjectById!((obj)=>obj.sacObject,()=>null)(id); // TODO: store within SpeedUpShadow?
						if(!sacObject) continue;
						auto materials=sacObject.transparentMaterials;
						foreach(i;0..materials.length){
							auto mesh=sacObject.saxsi.meshes[i];
							auto material=materials[i];
							material.bind(rc);
							scope(success) material.unbind(rc);
							material.backend.setTransformation(objects.speedUpShadows[j].position,objects.speedUpShadows[j].rotation,rc);
							scene.shadelessBoneMaterialBackend.setAlpha(0.3f);
							scene.shadelessBoneMaterialBackend.setEnergy(10.0f);
							sacObject.setFrame(objects.speedUpShadows[j].animationState,objects.speedUpShadows[j].frame/updateAnimFactor);
							mesh.render(rc);
						}
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&(objects.lightnings.length||objects.rituals.length)){
					auto material=scene.lightning.material;
					material.bind(rc);
					glDisable(GL_CULL_FACE);
					scope(success){
						glEnable(GL_CULL_FACE);
						material.unbind(rc);
					}
					enum totalFrames=Lightning!DagonBackend.totalFrames;
					void renderBolts(LightningBolt[] bolts,Vector3f start,Vector3f end,int frame){
						auto diff=end-start;
						auto len=diff.length;
						auto rotation=rotationBetween(Vector3f(0.0f,0.0f,1.0f),diff/len);
						scene.shadelessBoneMaterialBackend.setTransformationScaled(start,rotation,Vector3f(1.0f,1.0f,0.1f*len),rc);
						auto alpha=pi!float*frame/float(totalFrames);
						auto energy=0.375f+14.625f*(0.5f+0.25f*cos(7.0f*alpha)+0.25f*sin(11.0f*alpha));
						scene.shadelessBoneMaterialBackend.setEnergy(energy);
						auto mesh=scene.lightning.getFrame(frame%scene.lightning.numFrames);
						foreach(ref bolt;bolts){
							Matrix4x4f[numLightningSegments+1] pose;
							pose[0]=pose[numLightningSegments]=Matrix4f.identity();
							foreach(k,ref x;pose[1..$-1]) x=Transformation(Quaternionf.identity(),bolt.displacement[k]).getMatrix4f;
							mesh.pose=pose[];
							scope(exit) mesh.pose=[];
							mesh.render(rc);
						}
					}
					foreach(j;0..objects.lightnings.length){
						auto start=objects.lightnings[j].start.center(scene.state.current);
						auto end=objects.lightnings[j].end.center(scene.state.current);
						auto frame=objects.lightnings[j].frame;
						enum travelDelay=Lightning!DagonBackend.travelDelay;
						if(frame<travelDelay){
							auto α=frame/float(travelDelay);
							end=α*end+start*(1.0f-α);
						}else if(frame>totalFrames-travelDelay){
							auto α=(frame-(totalFrames-travelDelay))/float(travelDelay);
							start=α*end+start*(1.0f-α);
						}
						renderBolts(objects.lightnings[j].bolts[],start,end,frame);
					}
					foreach(j;0..objects.rituals.length){
						auto frame=objects.rituals[j].frame;
						if(!isNaN(objects.rituals[j].altarBolts[0].displacement[0].x)){
							auto start=scene.state.current.staticObjectById!((ref obj)=>obj.position+Vector3f(0.0f,0.0f,60.0f),()=>Vector3f.init)(objects.rituals[j].shrine);
							auto end=scene.state.current.movingObjectById!(center,()=>Vector3f.init)(objects.rituals[j].creature);
							if(!isNaN(end.x)&&!isNaN(start.x)) renderBolts(objects.rituals[j].altarBolts[],start,end,frame);
						}
						if(objects.rituals[j].targetWizard){
							auto start=objects.rituals[j].vortex.position;
							auto end=scene.state.current.movingObjectById!(center,()=>Vector3f.init)(objects.rituals[j].targetWizard);
							if(!isNaN(end.x)&&!isNaN(start.x)) renderBolts(objects.rituals[j].desecrateBolts[],start,end,frame);
						}
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&(objects.wraths.length||objects.altarDestructions.length)){
					auto material=scene.wrath.material;
					material.bind(rc);
					glDisable(GL_CULL_FACE);
					scope(success){
						glEnable(GL_CULL_FACE);
						material.unbind(rc);
					}
					void renderWrath(int frame,Vector3f position,float scale_=1.0f){
						auto mesh=scene.wrath.getFrame(frame);
						auto scale=scale_*scene.wrath.maxScale/scene.wrath.numFrames*frame;
						scene.shadelessMaterialBackend.setTransformationScaled(position,Quaternionf.identity(),Vector3f(scale,scale,1.0f),rc);
						mesh.render(rc);
					}
					foreach(j;0..objects.wraths.length){
						if(objects.wraths[j].status!=WrathStatus.exploding) continue;
						auto frame=objects.wraths[j].frame;
						auto position=objects.wraths[j].position+Vector3f(0.0f,0.0f,scene.wrath.maxOffset/scene.wrath.numFrames*objects.wraths[j].frame);
						renderWrath(frame,position);
					}
					foreach(j;0..objects.altarDestructions.length){
						enum delay=AltarDestruction.disappearDuration+AltarDestruction.floatDuration;
						if(objects.altarDestructions[j].frame<delay) continue;
						auto frame=(objects.altarDestructions[j].frame-delay)*(scene.wrath.numFrames-1)/AltarDestruction.explodeDuration;
						auto position=objects.altarDestructions[j].position;
						renderWrath(frame,position,20.0f);
					}
				}
				static if(mode==RenderMode.opaque) if(objects.rockCastings.length||objects.rocks.length||objects.earthflingProjectiles.length||objects.rockForms.length){
					auto materials=scene.rock.materials;
					foreach(i;0..materials.length){
						auto material=materials[i];
						material.bind(rc);
						scope(success) material.unbind(rc);
						auto mesh=scene.rock.meshes[i];
						foreach(j;0..objects.rockCastings.length){
							auto scale=1.0f*Vector3f(1.0f,1.0f,1.0f);
							material.backend.setTransformationScaled(objects.rockCastings[j].rock.position,objects.rockCastings[j].rock.rotation,scale,rc);
							mesh.render(rc);
						}
						foreach(j;0..objects.rocks.length){
							material.backend.setTransformationScaled(objects.rocks[j].position,objects.rocks[j].rotation,1.0f*Vector3f(1.0f,1.0f,1.0f),rc);
							mesh.render(rc);
						}
						foreach(j;0..objects.earthflingProjectiles.length){
							material.backend.setTransformationScaled(objects.earthflingProjectiles[j].position,objects.earthflingProjectiles[j].rotation,0.3f*Vector3f(1.0f,1.0f,1.0f),rc);
							mesh.render(rc);
						}
						foreach(j;0..objects.rockForms.length){
							auto target=objects.rockForms[j].target;
							alias Tuple=std.typecons.Tuple;
							auto positionRotation=scene.state.current.movingObjectById!((ref obj)=>tuple(center(obj),obj.rotation), function Tuple!(Vector3f,Quaternionf)(){ return typeof(return).init; })(target);
							auto position=positionRotation[0], rotation=positionRotation[1];
							if(isNaN(position.x)) continue;
							auto scale=objects.rockForms[j].scale*objects.rockForms[j].relativeScale;
							material.backend.setTransformationScaled(position,rotation,scale*Vector3f(1.0f,1.0f,1.0f),rc);
							mesh.render(rc);
						}
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&(objects.swarmCastings.length||objects.swarms.length||objects.fallenProjectiles.length)){
					// TODO: render bug shadows?
					auto material=scene.bug.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					auto mesh=scene.bug.mesh;
					void renderBug(bool fallen=false)(ref Bug!DagonBackend bug){
						material.backend.setSpriteTransformationScaled(bug.position,fallen?0.5f*bug.scale:bug.scale,rc);
						mesh.render(rc);
					}
					foreach(j;0..objects.swarmCastings.length)
						foreach(k;0..objects.swarmCastings[j].swarm.bugs.length)
							renderBug(objects.swarmCastings[j].swarm.bugs[k]);
					foreach(j;0..objects.swarms.length){
						if(objects.swarms[j].status==SwarmStatus.dispersing){
							material.backend.setAlpha(Bug!DagonBackend.alpha/64.0f*(swarmDispersingFrames-objects.swarms[j].frame));
						}else material.backend.setAlpha(Bug!DagonBackend.alpha);
						foreach(k;0..objects.swarms[j].bugs.length)
							renderBug(objects.swarms[j].bugs[k]);
					}
					foreach(j;0..objects.fallenProjectiles.length){
						if(objects.fallenProjectiles[j].status==SwarmStatus.dispersing){
							material.backend.setAlpha(Bug!DagonBackend.alpha/64.0f*(fallenProjectileDispersingFrames-objects.fallenProjectiles[j].frame));
						}else material.backend.setAlpha(Bug!DagonBackend.alpha);
						foreach(k;0..objects.fallenProjectiles[j].bugs.length)
							renderBug!true(objects.fallenProjectiles[j].bugs[k]);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.brainiacEffects.length){
					auto material=scene.brainiacEffect.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					foreach(j;0..objects.brainiacEffects.length){
						auto position=objects.brainiacEffects[j].position;
						auto rotation=rotationBetween(Vector3f(0.0f,0.0f,1.0f),objects.brainiacEffects[j].direction); // TODO: precompute this?
						auto frame=objects.brainiacEffects[j].frame;
						auto relativeProgress=float(frame)/scene.brainiacEffect.numFrames;
						auto scale=1.0f+0.6f*relativeProgress^^2.5f;
						scene.shadelessMaterialBackend.setTransformationScaled(position,rotation,scale*Vector3f(1.0f,1.0f,1.0f),rc);
						scene.shadelessMaterialBackend.setAlpha(0.95f*(1.0f-relativeProgress)^^1.5f);
						auto mesh=scene.brainiacEffect.getFrame(objects.brainiacEffects[j].frame%scene.brainiacEffect.numFrames);
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.shrikeEffects.length){
					auto material=scene.shrikeEffect.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					foreach(j;0..objects.shrikeEffects.length){
						auto position=objects.shrikeEffects[j].position;
						auto rotation=rotationBetween(Vector3f(0.0f,0.0f,1.0f),objects.shrikeEffects[j].direction); // TODO: precompute this?
						auto frame=objects.shrikeEffects[j].frame;
						auto relativeProgress=float(frame)/scene.shrikeEffect.numFrames;
						auto scale=(1.0f+0.6f*relativeProgress^^2.5f)*objects.shrikeEffects[j].scale;
						scene.shadelessMaterialBackend.setTransformationScaled(position,rotation,scale*Vector3f(1.0f,1.0f,1.0f),rc);
						scene.shadelessMaterialBackend.setAlpha(0.95f*(1.0f-relativeProgress)^^2.0f);
						auto mesh=scene.shrikeEffect.getFrame(objects.shrikeEffects[j].frame%scene.shrikeEffect.numFrames);
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.spitfireEffects.length){
					auto fire=SacParticle!DagonBackend.get(ParticleType.fire);
					auto material=fire.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					foreach(j;0..objects.spitfireEffects.length){
						auto position=objects.spitfireEffects[j].position;
						auto frame=objects.spitfireEffects[j].frame;
						auto scale=objects.spitfireEffects[j].scale;
						material.backend.setSpriteTransformationScaled(position,scale,rc);
						auto mesh=fire.getMesh(objects.spitfireEffects[j].frame%fire.numFrames);
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.gargoyleEffects.length){
					auto rock=SacParticle!DagonBackend.get(ParticleType.rock);
					auto material=rock.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					foreach(j;0..objects.gargoyleEffects.length){
						auto position=objects.gargoyleEffects[j].position;
						auto frame=objects.gargoyleEffects[j].frame;
						auto scale=objects.gargoyleEffects[j].scale;
						material.backend.setSpriteTransformationScaled(position,scale,rc);
						auto mesh=rock.getMesh(objects.gargoyleEffects[j].frame%rock.numFrames);
						mesh.render(rc);
					}
				}
				static foreach(arrow;["sylph","ranger"])
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&(mixin(`objects.`~arrow~`Effects`).length||mixin(`objects.`~arrow,`Projectiles`).length)){
					auto material=mixin(`scene.arrow.`~arrow~`Material`);
					material.bind(rc);
					glDisable(GL_CULL_FACE);
					scope(success){
						glEnable(GL_CULL_FACE);
						material.unbind(rc);
					}
					foreach(j;0..mixin(`objects.`~arrow~`Effects`).length){
						auto id=mixin(`objects.`~arrow~`Effects`)[j].attacker;
						auto state=scene.state.current;
						if(!state.isValidTarget(id,TargetType.creature)) continue;
						auto mesh=scene.arrow.getFrame(mixin(`objects.`~arrow~`Effects`)[j].frame%(16*updateAnimFactor));
						static void renderLoadedArrow(B)(ref MovingObject!B object,SacScene scene,Mesh mesh,RenderingContext* rc){
							auto loadedArrow=object.loadedArrow;
							if(loadedArrow!=loadedArrow) return;
							void renderArrow(Vector3f start,Vector3f end,float scale=1.0f){
								auto direction=end-start;
								auto len=direction.length;
								auto rotation=rotationBetween(Vector3f(0.0f,0.0f,1.0f),direction/len);
								scene.shadelessMaterialBackend.setTransformationScaled(start,rotation,Vector3f(scale,scale,len),rc);
								mesh.render(rc);
							}
							with(loadedArrow){
								renderArrow(hand,top,0.5f);
								renderArrow(hand,bottom,0.5f);
								renderArrow(hand,front);
							}
						}
						state.movingObjectById!renderLoadedArrow(id,scene,mesh,rc);
					}
					foreach(j;0..mixin(`objects.`~arrow,`Projectiles`).length){
						auto position=mixin(`objects.`~arrow,`Projectiles`)[j].position;
						auto velocity=mixin(`objects.`~arrow,`Projectiles`)[j].velocity;
						auto direction=velocity.normalized;
						auto rotation=rotationBetween(Vector3f(0.0f,0.0f,1.0f),direction);
						scene.shadelessMaterialBackend.setTransformationScaled(position,rotation,Vector3f(1.0f,1.0f,1.6f),rc);
						auto mesh=scene.arrow.getFrame(mixin(`objects.`~arrow,`Projectiles`)[j].frame%(16*updateAnimFactor));
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.lifeShields.length){
					auto material=scene.lifeShield.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					foreach(j;0..objects.lifeShields.length){
						auto target=objects.lifeShields[j].target;
						alias Tuple=std.typecons.Tuple;
						auto positionRotationBoxSize=scene.state.current.movingObjectById!((ref obj)=>tuple(center(obj),obj.rotation,boxSize(obj.sacObject.largeHitbox(Quaternionf.identity(),obj.animationState,obj.frame/updateAnimFactor))), function Tuple!(Vector3f,Quaternionf,Vector3f)(){ return typeof(return).init; })(target);
						auto position=positionRotationBoxSize[0], rotation=positionRotationBoxSize[1], boxSize=positionRotationBoxSize[2];
						if(isNaN(position.x)) continue;
						auto scale=objects.lifeShields[j].scale;
						material.backend.setTransformationScaled(position,rotation,scale*1.4f*boxSize,rc);
						auto mesh=scene.lifeShield.getFrame(objects.lifeShields[j].frame%scene.lifeShield.numFrames);
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.divineSights.length){
					auto material=scene.divineSight.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					foreach(j;0..objects.divineSights.length){
						auto position=objects.divineSights[j].position;
						auto frame=objects.divineSights[j].frame;
						auto mesh=scene.divineSight.getFrame(frame%scene.divineSight.numFrames);
						auto scale=objects.divineSights[j].scale;
						auto alpha=scale^^2;
						material.backend.setSpriteTransformationScaled(position,scale,rc);
						material.backend.setAlpha(alpha);
						mesh.render(rc);
					}
				}
			}else static if(is(T==Particles!(DagonBackend,relative,sideFiltered),bool relative,bool sideFiltered)){
				static if(mode==RenderMode.transparent){
					if(rc.shadowMode) return; // TODO: particle shadows?
					auto sacParticle=objects.sacParticle;
					if(!sacParticle) return; // TODO: get rid of this?
					auto material=sacParticle.material;
					material.bind(rc);
					material.backend.setInformation(Vector4f(0.0f,0.0f,0.0f,0.0f));
					scope(success) material.unbind(rc);
					static if(relative) auto state=scene.state.current;
					foreach(j;0..objects.length){
						static if(sideFiltered){
							if(objects.sideFilters[j]!=scene.renderSide)
								continue;
						}
						auto mesh=sacParticle.getMesh(objects.frames[j]); // TODO: do in shader?
						static if(relative){
							auto position=objects.rotates[j]?state.movingObjectById!((obj,particlePosition)=>rotate(obj.rotation,particlePosition)+obj.position,()=>Vector3f(0.0f,0.0f,0.0f))(objects.baseIds[j],objects.positions[j])
								: objects.positions[j]+state.movingObjectById!((obj)=>obj.position,()=>Vector3f(0.0f,0.0f,0.0f))(objects.baseIds[j]);
						}
						else auto position=objects.positions[j];
						material.backend.setSpriteTransformationScaled(position,objects.scales[j]*sacParticle.getScale(objects.lifetimes[j]),rc);
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
								rotation=facingQuaternion((k&1?-1.0f:1.0f)*2.0f*pi!float*fraction*(k+1));
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
		state.current.eachByType!(render,true,true)(options.enableWidgets,this,rc);
	}

	bool selectionUpdated=false;
	int lastSelectedId=0,lastSelectedFrame=0;
	float lastSelectedX,lastSelectedY;
	CreatureGroup renderedSelection;
	CreatureGroup rectangleSelection;
	void renderCreatureStats(RenderingContext* rc){
		bool updateRectangleSelect=false;
		if(renderSide!=-1){
			updateRectangleSelect=!selectionUpdated&&mouse.status==Mouse.Status.rectangleSelect&&!mouse.dragging;
			if(updateRectangleSelect){
				rectangleSelection=CreatureGroup.init;
				if(mouse.additiveSelect) renderedSelection=state.current.getSelection(renderSide);
				else renderedSelection=CreatureGroup.init;
			}else if(!selectionUpdated) renderedSelection=state.current.getSelection(renderSide);
		}else renderedSelection=CreatureGroup.init;
		rc.information=Vector4f(0.0f,0.0f,0.0f,0.0f);
		shadelessMaterialBackend.bind(null,rc);
		scope(success) shadelessMaterialBackend.unbind(null,rc);
		static void renderCreatureStat(B)(ref MovingObject!B obj,SacScene scene,bool healthAndMana,RenderingContext* rc){
			if(obj.creatureState.mode.among(CreatureMode.dying,CreatureMode.dead,CreatureMode.dissolving)) return;
			if(scene.renderSide!=obj.side&&(!obj.creatureState.mode.isVisibleToAI||obj.creatureStats.effects.stealth)) return;
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
			enum isMoving=is(T==MovingObjects!(DagonBackend, renderMode), RenderMode renderMode);
			enum isStatic=is(T==StaticObjects!(DagonBackend, renderMode), RenderMode renderMode);
			static if(isMoving){
				auto sacObject=objects.sacObject;
				foreach(j;0..objects.length){
					material.backend.setTransformation(objects.positions[j], Quaternionf.identity(), rc);
					auto hitbox=sacObject.hitbox(objects.rotations[j],objects.animationStates[j],objects.frames[j]/updateAnimFactor);
					renderBox(hitbox,true,rc);
					auto meleeHitbox=sacObject.meleeHitbox(objects.rotations[j],objects.animationStates[j],objects.frames[j]/updateAnimFactor);
					renderBox(meleeHitbox,true,rc);
					/+auto hands=sacObject.hands(objects.animationStates[j],objects.frames[j]/updateAnimFactor);
					foreach(i;0..2){
						if(hands[i] is Vector3f.init) continue;
						hands[i]=rotate(objects.rotations[j],hands[i]);
						Vector3f[2] nbox;
						nbox=[hands[i]-(0.2*Vector3f(1,1,1)),hands[i]+(0.2*Vector3f(1,1,1))];
						renderBox(nbox,false,rc);
					}+/
					/+foreach(i;1..sacObject.saxsi.saxs.bones.length){
						auto bhitbox=sacObject.saxsi.saxs.bones[i].hitbox;
						foreach(ref x;bhitbox){
							x=rotate(objects.rotations[j],x*sacObject.animations[objects.animationStates[j]].frames[objects.frames[j]/updateAnimFactor].matrices[i]);
						}
						if(i!=23&&i!=26) continue;
						//Vector3f[8] box=[Vector3f(-1,-1,-1),Vector3f(1,-1,-1),Vector3f(1,1,-1),Vector3f(-1,1,-1),Vector3f(-1,-1,1),Vector3f(1,-1,1),Vector3f(1,1,1),Vector3f(-1,1,1)];
						foreach(curVert;0..8){
							foreach(k;0..8){
								Vector3f[2] nbox;
								nbox=[bhitbox[curVert]-(0.05*Vector3f(1,1,1)),bhitbox[curVert]+(0.05*Vector3f(1,1,1))];
								renderBox(nbox,false,rc);
							}
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
			}else static if(isStatic){
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
		if(mouse.target.id&&!state.current.isValidTarget(mouse.target.id,mouse.target.type)) mouse.target=Target.init;
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
		if(mouse.status!=Mouse.Status.rectangleSelect||mouse.dragging) return false;
		auto x1=min(mouse.leftButtonX,mouse.x), x2=max(mouse.leftButtonX,mouse.x);
		auto y1=min(mouse.leftButtonY,mouse.y), y2=max(mouse.leftButtonY,mouse.y);
		return x1<=position.x&&position.x<=x2 && y1<=position.y&&position.y<=y2;
	}
	void renderRectangleSelectFrame(RenderingContext* rc){
		if(mouse.status!=Mouse.Status.rectangleSelect||mouse.dragging) return;
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
		if(mouse.target.id&&!state.current.isValidTarget(mouse.target.id,mouse.target.type)) mouse.target=Target.init;
		mouse.x=eventManager.mouseX/screenScaling;
		mouse.y=eventManager.mouseY/screenScaling;
		mouse.x=max(0,min(mouse.x,width-1));
		mouse.y=max(0,min(mouse.y,height-1));
		auto size=options.cursorSize;
		auto position=Vector3f(mouse.x-0.5f*size,mouse.y,0);
		if(mouse.status==Mouse.Status.rectangleSelect&&!mouse.dragging) position.y-=1.0f;
		auto scaling=Vector3f(size,size,1.0f);
		if(mouse.status==Mouse.Status.icon&&!mouse.dragging){
			auto iconPosition=position+Vector3f(0.0f,4.0f/32.0f*size,0.0f);
			if(!mouse.icon.among(MouseIcon.spell,MouseIcon.ability)){
				auto material=sacCursor.iconMaterials[mouse.icon];
				material.bind(rc);
				material.backend.setTransformationScaled(iconPosition, Quaternionf.identity(), scaling, rc);
				quad.render(rc);
				material.unbind(rc);
			}else{
				hudMaterialBackend.bind(null,rc);
				hudMaterialBackend.bindDiffuse(sacHud.pages);
				hudMaterialBackend.setTransformationScaled(iconPosition, Quaternionf.identity(), scaling, rc);
				/+ShapeSubQuad[3] pages=[creaturePage,spellPage,structurePage];
				auto page=pages[mouse.spell.type];
				page.render(rc);+/
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
	void updateSelectionRosterTargetAbility(Target target,SacSpell!DagonBackend targetAbility,Vector2f position,Vector2f scaling){
		if(!mouse.onSelectionRoster) return;
		auto topLeft=position;
		auto bottomRight=position+scaling;
		if(floor(topLeft.x)<=mouse.x&&mouse.x<=ceil(bottomRight.x)
		   && floor(topLeft.y)<=mouse.y&&mouse.y<=ceil(bottomRight.y)){
			selectionRosterTarget=target;
			selectionRosterTargetAbility=targetAbility;
		}
	}
	void renderSelectionRoster(RenderingContext* rc){
		if(mouse.onSelectionRoster){
			selectionRosterTarget=Target.init;
			selectionRosterTargetAbility=null;
		}
		auto material=sacHud.frameMaterial;
		material.bind(rc);
		scope(success) material.unbind(rc);
		auto hudScaling=this.hudScaling;
		auto scaling=hudScaling*Vector3f(138.0f,256.0f,1.0f);
		auto position=Vector3f(-34.0f*hudScaling,0.5f*(height-scaling.y),0);
		material.backend.setTransformationScaled(position, Quaternionf.identity(), scaling, rc);
		selectionRoster.render(rc);
		int i=0; // idiotic deprecation of foreach(int i,x;selection)
		foreach(x;renderedSelection.creatureIds){
			scope(success) i++;
			if(!renderedSelection.creatureIds[i]) continue;
			static void renderIcon(B)(MovingObject!B obj,int i,Vector3f position,float hudScaling,SacScene scene,RenderingContext* rc){
				if(obj.sacObject.icon){
					auto cpos=position+hudScaling*Vector3f(i>=6?35.0f:-1.0f,(i%6)*32.0f,0.0f);
					auto scaling=hudScaling*Vector3f(34.0f,32.0f,0.0f);
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
		auto ability=renderedSelection.ability(state.current);
		if(ability&&ability.icon){
			auto ascaling=hudScaling*Vector3f(34.0f,34.0f,0.0f);
			auto apos=position+Vector3f(hudScaling*105.0f,0.5f*scaling.y-hudScaling*17.0f,0.0f);
			hudMaterialBackend.setTransformationScaled(apos, Quaternionf.identity(), ascaling, rc);
			hudMaterialBackend.bindDiffuse(ability.icon);
			quad.render(rc);
			if(mouse.onSelectionRoster){
				auto target=Target(TargetType.ability,0,Vector3f.init,TargetLocation.selectionRoster);
				updateSelectionRosterTargetAbility(target,ability,apos.xy,ascaling.xy);
			}
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
		if(!state.current.isValidTarget(camera.target,TargetType.creature)) camera.target=0;
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
			auto angle=2.0f*pi!float*82.0f/360.0f;
			auto fovRotation1=mapRotation*facingQuaternion(-facing-0.5f*angle+pi!float);
			minimapMaterialBackend.setTransformationScaled(iconCenter+rotate(fovRotation1,Vector3f(-0.5f*fovScaling.x,0.0f,0.0f)),fovRotation1,fovScaling,rc);
			quad.render(rc);
			auto fovRotation2=mapRotation*facingQuaternion(-facing+0.5f*angle+pi!float);
			minimapMaterialBackend.setTransformationScaled(iconCenter+rotate(fovRotation2,Vector3f(-0.5f*fovScaling.x,0.0f,0.0f)),fovRotation2,fovScaling,rc);
			quad.render(rc);
		}
		if(mouse.onMinimap){
			auto mouseOffset=Vector3f(mouse.x,mouse.y,0.0f)-mapCenter;
			auto minimapPosition=minimapCenter+rotate(mapRotation,Vector3f(mouseOffset.x,-mouseOffset.y,0.0f)/minimapFactor);
			minimapPosition.z=state.current.getHeight(minimapPosition);
			auto target=Target(TargetType.terrain,0,minimapPosition,TargetLocation.minimap);
			minimapTarget=target;
		}
		minimapMaterialBackend.bindDiffuse(sacHud.minimapIcons);
		 // temporary scratch space. TODO: maybe share memory with other temporary scratch spaces
		import std.container: Array;
		static Array!uint creatureArrowIndices;
		static Array!uint structureArrowIndices;
		static void render(T)(ref T objects,float hudScaling,float minimapFactor,Vector3f minimapCenter,Vector3f mapCenter,float radius,Quaternionf mapRotation,SacScene scene,RenderingContext* rc){ // TODO: why does this need to be static? DMD bug?
			enum isMoving=is(T==MovingObjects!(DagonBackend, renderMode), RenderMode renderMode);
			enum isStatic=is(T==StaticObjects!(DagonBackend, renderMode), RenderMode renderMode);
			static if((is(typeof(objects.sacObject))||is(T==Souls!(DagonBackend)))&&!is(T==FixedObjects!DagonBackend)){
				auto quad=scene.minimapQuad;
				auto iconScaling=hudScaling*Vector3f(2.0f,2.0f,0.0f);
				static if(is(typeof(objects.sacObject))){
					auto sacObject=objects.sacObject;
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
						static if(isMoving){
							if(objects.creatureStates[j].mode.among(CreatureMode.dead,CreatureMode.dissolving)) continue;
							if(scene.renderSide!=objects.sides[j]&&(!objects.creatureStates[j].mode.isVisibleToOtherSides||objects.creatureStatss[j].effects.stealth))
								continue;
						}
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
					static if(isStatic){
						if(scene.state.current.buildingById!((ref bldg,isManafount)=>!isManafount&&!bldg.isAltar&&bldg.health==0.0f||bldg.top,()=>true)(objects.buildingIds[j],isManafount)) // TODO: merge with side lookup!
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
							if(!soul.state.among(SoulState.normal,SoulState.emerging)) continue;
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
			}else static if(is(T==Particles!(DagonBackend,relative),bool relative)){
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
				auto rotation=rotationQuaternion(Axis.z,pi!float/2+atan2(iconOffset.y,iconOffset.x));
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
		if(!state.current.isValidTarget(camera.target,TargetType.creature)) camera.target=0;
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
	void spellAdvisorHelpSpeech(SpellStatus status){
		auto priority=DialogPriority.advisorAnnoy;
		char[4] tag;
		final switch(status) with(AdvisorHelpSound){
			case SpellStatus.inexistent: return;
			case SpellStatus.invalidTarget: tag=invalidTarget; break;
			case SpellStatus.lowOnMana: tag=lowOnMana; break;
			case SpellStatus.mustBeNearBuilding: return; // (missing)
			case SpellStatus.mustBeNearEnemyAltar: tag=mustBeNearEnemyAltar; break;
			case SpellStatus.mustBeConnectedToConversion: return; // (missing)
			case SpellStatus.needMoreSouls: tag=needMoreSouls; break;
			case SpellStatus.outOfRange: tag=outOfRange; break;
			case SpellStatus.notReady: tag=notReady; break;
			case SpellStatus.ready: return;
		}
		if(audio) audio.queueDialogSound(tag,DialogPriority.advisorAnnoy);
	}
	bool castSpell(SacSpell!DagonBackend spell,Target target,bool playAudio=true){
		switchSpellbookTab(spell.type);
		if(!spellbookVisible(camera.target)) return false;
		auto status=state.current.spellStatus!false(camera.target,spell,target);
		if(status!=SpellStatus.ready){
			if(playAudio) spellAdvisorHelpSpeech(status);
			return false;
		}
		controller.addCommand(Command!DagonBackend(renderSide,camera.target,spell,target));
		return true;
	}
	bool castSpell(char[4] tag,Target target,bool playAudio=true){
		return castSpell(SacSpell!DagonBackend.get(tag),target,playAudio);
	}
	bool selectSpell(SacSpell!DagonBackend newSpell,bool playAudio=true){
		switchSpellbookTab(newSpell.type);
		if(!spellbookVisible(camera.target)) return false;
		if(mouse.status==Mouse.Status.icon){
			if(mouse.icon==MouseIcon.spell&&mouse.spell is newSpell) return false;
			if(playAudio&&audio) audio.playSound("kabI");
		}
		auto status=state.current.spellStatus!true(camera.target,newSpell);
		if(status!=SpellStatus.ready){
			if(playAudio) spellAdvisorHelpSpeech(status);
			return false;
		}
		if(newSpell.requiresTarget){
			import std.random:uniform; // TODO: put selected spells in game state?
			auto whichClick=uniform(0,2);
			if(playAudio&&audio) audio.playSound(commandAppliedSoundTags[whichClick]);
			mouse.status=Mouse.Status.icon;
			mouse.icon=MouseIcon.spell;
			mouse.spell=newSpell;
			return true;
		}else{
			mouse.status=Mouse.Status.standard;
			return castSpell(newSpell,Target.init);
		}
	}
	bool selectSpell(char[4] tag,bool playAudio=true){
		return selectSpell(SacSpell!DagonBackend.get(tag),playAudio);
	}
	bool selectSpell(SpellType tab,int index,bool playAudio=true){
		if(!spellbookVisible(camera.target)) return false;
		auto spells=state.current.getSpells(camera.target).filter!(x=>x.spell.type==tab);
		foreach(i,entry;enumerate(spells)) if(i==index) return selectSpell(entry.spell,playAudio);
		return false;
	}
	bool useAbility(SacSpell!DagonBackend ability,Target target,CommandQueueing queueing,bool playAudio=true){
		auto status=state.current.abilityStatus!false(renderSide,ability,target);
		if(status!=SpellStatus.ready){
			if(playAudio) spellAdvisorHelpSpeech(status);
			return false;
		}
		if(queueing==CommandQueueing.none) queueing=CommandQueueing.pre;
		controller.addCommand(Command!DagonBackend(renderSide,ability,target),queueing);
		return true;
	}
	bool useAbility(char[4] tag,Target target,CommandQueueing queueing,bool playAudio=true){
		return useAbility(SacSpell!DagonBackend.get(tag),target,queueing,playAudio);
	}
	bool selectAbility(SacSpell!DagonBackend newAbility,CommandQueueing queueing,bool playAudio=true){
		if(renderSide==-1) return false;
		if(mouse.status==Mouse.Status.icon){
			if(mouse.icon==MouseIcon.ability&&mouse.spell is newAbility) return false;
			if(playAudio&&audio) audio.playSound("kabI");
		}
		auto status=state.current.abilityStatus!true(renderSide,newAbility);
		if(status!=SpellStatus.ready){
			if(playAudio) spellAdvisorHelpSpeech(status);
			return false;
		}
		if(newAbility.requiresTarget){
			import std.random:uniform; // TODO: put selected spells in game state?
			auto whichClick=uniform(0,2);
			if(playAudio&&audio) audio.playSound(commandAppliedSoundTags[whichClick]);
			mouse.status=Mouse.Status.icon;
			mouse.icon=MouseIcon.ability;
			mouse.spell=newAbility;
			return true;
		}else{
			mouse.status=Mouse.Status.standard;
			return useAbility(newAbility,Target.init,queueing);
		}
	}
	void selectAbility(CommandQueueing queueing,bool playAudio=true){
		auto ability=renderedSelection.ability(state.current);
		if(!ability) return;
		selectAbility(ability,queueing,playAudio);
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
		auto wizard=state.current.getWizard(camera.target);
		auto spells=state.current.getSpells(wizard).filter!(x=>x.spell.type==spellbookTab);
		numSpells=cast(int)spells.walkLength;
		auto material=sacHud.frameMaterial; // TODO: share material binding with other drawing commands (or at least the backend binding)
		material.bind(rc);
		auto position=Vector3f(0.0f,height-hudScaling*32.0f,0.0f);
		auto numFrameSegments=max(10,2*numSpells);
		auto scaling=hudScaling*Vector3f(16.0f,8.0f,0.0f);
		auto scaling2=hudScaling*Vector3f(48.0f,16.0f,0.0f);
		auto position2=Vector3f(hudScaling*16.0f*numFrameSegments-4.0f+scaling2.y,height-hudScaling*48.0f,0.0f);
		material.backend.setTransformationScaled(position2,facingQuaternion(pi!float/2),scaling2,rc);
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
		auto pageScaling=hudScaling*Vector3f(32.0f,32.0f,0.0f);
		foreach(i,entry;enumerate(spells)){
			auto pagePosition=Vector3f(i*pageScaling.x,height-pageScaling.y,0.0f);
			auto target=Target(TargetType.spell,0,Vector3f.init,TargetLocation.spellbook);
			updateSpellbookTarget(target,entry.spell,pagePosition.xy,pageScaling.xy);
			hudMaterialBackend.setTransformationScaled(pagePosition,Quaternionf.identity(),pageScaling,rc);
			page.render(rc);
		}
		auto mana=camera.target?state.current.movingObjectById!((obj)=>obj.creatureStats.mana,function float()=>0.0f)(camera.target):0.0f;
		auto souls=wizard?wizard.souls:0;
		foreach(i,entry;enumerate(spells)){
			auto factor=min(1.0f,mana/entry.spell.manaCost);
			auto spellScaling=factor*pageScaling;
			auto spellPosition=Vector3f((i+0.5f)*pageScaling.x-0.5f*spellScaling.x,height-0.5f*pageScaling.y-0.5f*spellScaling.y,0.0f);
			hudMaterialBackend.setTransformationScaled(spellPosition,Quaternionf.identity(),spellScaling,rc);
			hudMaterialBackend.bindDiffuse(entry.spell.icon);
			hudMaterialBackend.setAlpha(factor);
			quad.render(rc);
			bool active=true;
			if(entry.spell.tag==SpellTag.guardian&&!wizard.closestBuilding) active=false;
			if(entry.spell.tag==SpellTag.desecrate&&!wizard.closestEnemyAltar) active=false;
			if(entry.spell.tag==SpellTag.convert&&!wizard.closestShrine) active=false;
			if(!active){
				auto inactivePosition=Vector3f(i*pageScaling.x,height-pageScaling.y,0.0f);
				hudMaterialBackend.setTransformationScaled(inactivePosition,Quaternionf.identity(),pageScaling,rc);
				hudMaterialBackend.bindDiffuse(sacCursor.invalidTargetIconTexture);
				hudMaterialBackend.setAlpha(1.0f);
				quad.render(rc);
			}
			if(entry.spell.soulCost>souls){
				auto spiritPosition=Vector3f(i*pageScaling.x,height-pageScaling.y,0.0f);
				auto spiritScaling=hudScaling*Vector3f(16.0f,16.0f,0.0f);
				hudMaterialBackend.setTransformationScaled(spiritPosition,Quaternionf.identity(),spiritScaling,rc);
				hudMaterialBackend.bindDiffuse(sacHud.spirit);
				hudMaterialBackend.setAlpha(1.0f);
				quad.render(rc);
			}
		}
		hudMaterialBackend.unbind(null,rc);
		bool bound=false;
		foreach(i,entry;enumerate(spells)){
			if(entry.cooldown==0.0f) continue;
			if(!bound){ cooldownMaterialBackend.bind(null,rc); bound=true; }
			auto pagePosition=Vector3f((i+0.5f)*pageScaling.x,height-0.5f*pageScaling.y,0.0f);
			cooldownMaterialBackend.setTransformationScaled(pagePosition,Quaternionf.identity(),pageScaling,rc);
			float progress=1.0f-entry.cooldown/entry.maxCooldown;
			cooldownMaterialBackend.setProgress(progress);
			cooldown.render(rc);
		}
		cooldownMaterialBackend.unbind(null,rc);
		bound=false;
		material=sacHud.spellReadyMaterial;
		foreach(i,entry;enumerate(spells)){
			if(entry.readyFrame>=16*updateAnimFactor) continue;
			if(!bound){ material.bind(rc); bound=true; }
			auto flarePosition=Vector3f((i+0.5f)*pageScaling.x,height-0.5f*pageScaling.y,0.0f);
			auto flareScaling=hudScaling*Vector3f(48.0f,48.0f,0.0f);
			flareScaling.y*=-1.0f;
			material.backend.setTransformationScaled(flarePosition,Quaternionf.identity(),flareScaling,rc);
			sacHud.getSpellReadyMesh(entry.readyFrame).render(rc);
		}
		if(bound) material.unbind(rc);
	}
	bool statsVisible(int target){
		if(!camera.target) return false;
		with(CreatureMode)
			return state.current.movingObjectById!((ref obj)=>!obj.isDying&&!obj.isDead,()=>false)(camera.target);
	}
	bool spellbookVisible(int target){
		if(!camera.target) return false;
		return state.current.movingObjectById!((ref obj)=>!obj.isDying&&!obj.isGhost&&!obj.isDead,()=>false)(camera.target);
	}
	void renderHUD(RenderingContext* rc){
		renderMinimap(rc);
		if(renderSide!=-1){
			if(statsVisible(camera.target)) renderStats(rc);
			renderSelectionRoster(rc);
			if(spellbookVisible(camera.target)) renderSpellbook(rc);
		}
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
		renderSky(rc);
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
		if(state){
			setupEnvironment(state.current.map);
			if(audio) audio.setTileset(state.current.map.tileset);
		}
		createSky();
		createSouls();
		createEffects();
		initializeHUD();
		initializeMouse();
	}

	int renderSide=-1;
	void setController(Controller!DagonBackend controller)in{
		assert(this.controller is null);
		assert(this.state!is null&&this.state is controller.state);
	}do{
		renderSide=controller.controlledSide;
		this.controller=controller;
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
		mouse.visible=false;
		fpview.mouseFactor=0.25f;
		//auto mat = createMaterial();
		//mat.diffuse = Color4f(0.2, 0.2, 0.2, 0.2);
		//mat.diffuse=txta;

		/+auto obj = createEntity3D();
		 obj.drawable = aOBJ.mesh;
		 obj.material = mat;
		 obj.position = Vector3f(0, 1, 0);
		 obj.rotation = rotationQuaternion(Axis.x,-pi!float/2);+/

		/+if(!state){
			auto sky=createSky();
			sky.rotation=rotationQuaternion(Axis.z,pi!float)*
				rotationQuaternion(Axis.x,pi!float/2);
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
		enum rotationSpeed=0.95f*pi!float;
		float lastTargetFacing;
	}
	Camera camera;
	struct MovementState{ // to avoid sending too many commands. TODO: react to input events instead.
		MovementDirection movement;
		RotationDirection rotation;
	}
	MovementState targetMovementState;
	void focusCamera(int target){
		fpview.active=false;
		mouse.visible=true;
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
		if(!state.current.isValidTarget(camera.target,TargetType.creature)) camera.target=0;
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
			static import std.math;
			static immutable float factor=std.math.exp(2.0f*std.math.log(0.01f)/updateFPS);
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
		if(mouse.status.among(Mouse.Status.standard,Mouse.Status.icon)&&!mouse.dragging){
			if(isOnSpellbook(Vector2f(mouse.x,mouse.y))) mouse.loc=Mouse.Location.spellbook;
			else if(isOnSelectionRoster(Vector2f(mouse.x,mouse.y))) mouse.loc=Mouse.Location.selectionRoster;
			else if(isOnMinimap(Vector2f(mouse.x,mouse.y))) mouse.loc=Mouse.Location.minimap;
			else mouse.loc=Mouse.Location.scene;
		}
		if(options.observer||!controller) return;
		if(camera.target!=0&&(!state||!state.current.isValidTarget(camera.target,TargetType.creature))) camera.target=0;
		auto cameraFacing=-degtorad(fpview.camera.turn);
		import hotkeys_;
		Modifiers modifiers;
		if(eventManager.keyPressed[KEY_LCTRL]||options.hotkeys.capsIsCtrl&&eventManager.keyPressed[KEY_CAPSLOCK]) modifiers|=Modifiers.ctrl;
		if(eventManager.keyPressed[KEY_LSHIFT]) modifiers|=Modifiers.shift;
		bool ctrl=!!(modifiers&Modifiers.ctrl);
		bool shift=!!(modifiers&Modifiers.shift);
		bool pressed(int[] keyCodes){ return keyCodes.any!(key=>eventManager.keyPressed[key]);}
		if(camera.target){
			if(!state) return;
			if(pressed(options.hotkeys.moveForward) && !pressed(options.hotkeys.moveBackward)){
				if(targetMovementState.movement!=MovementDirection.forward){
					targetMovementState.movement=MovementDirection.forward;
					controller.addCommand(Command!DagonBackend(CommandType.moveForward,renderSide,camera.target,camera.target,Target.init,cameraFacing));
				}
			}else if(pressed(options.hotkeys.moveBackward) && !pressed(options.hotkeys.moveForward)){
				if(targetMovementState.movement!=MovementDirection.backward){
					targetMovementState.movement=MovementDirection.backward;
					controller.addCommand(Command!DagonBackend(CommandType.moveBackward,renderSide,camera.target,camera.target,Target.init,cameraFacing));
				}
			}else{
				if(targetMovementState.movement!=MovementDirection.none){
					targetMovementState.movement=MovementDirection.none;
					controller.addCommand(Command!DagonBackend(CommandType.stopMoving,renderSide,camera.target,camera.target,Target.init,cameraFacing));
				}
			}
			if(pressed(options.hotkeys.turnLeft) && !pressed(options.hotkeys.turnRight)){
				if(targetMovementState.rotation!=RotationDirection.left){
					targetMovementState.rotation=RotationDirection.left;
					controller.addCommand(Command!DagonBackend(CommandType.turnLeft,renderSide,camera.target,camera.target,Target.init,cameraFacing));
				}
			}else if(pressed(options.hotkeys.turnRight) && !pressed(options.hotkeys.turnLeft)){
				if(targetMovementState.rotation!=RotationDirection.right){
					targetMovementState.rotation=RotationDirection.right;
					controller.addCommand(Command!DagonBackend(CommandType.turnRight,renderSide,camera.target,camera.target,Target.init,cameraFacing));
				}
			}else{
				if(targetMovementState.rotation!=RotationDirection.none){
					targetMovementState.rotation=RotationDirection.none;
					controller.addCommand(Command!DagonBackend(CommandType.stopTurning,renderSide,camera.target,camera.target,Target.init,cameraFacing));
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
			if(renderSide==-1) return;
			TargetLocation loc;
			final switch(mouse.loc){
				case Mouse.Location.scene: loc=TargetLocation.scene; break;
				case Mouse.Location.minimap: loc=TargetLocation.minimap; break;
				case Mouse.Location.selectionRoster,Mouse.Location.spellbook: assert(0);
			}
			controller.setSelection(renderSide,camera.target,renderedSelection,loc);
			selectionUpdated=true;
		}
		if(mouse.status.among(Mouse.Status.standard,Mouse.Status.rectangleSelect)&&!mouse.dragging){
			if(eventManager.mouseButtonPressed[MB_LEFT]){
				enum rectangleThreshold=3.0f;
				if(mouse.status==Mouse.Status.standard&&!mouse.dragging){
					if((abs(mouse.x-mouse.leftButtonX)>=rectangleThreshold||abs(mouse.y-mouse.leftButtonY)>=rectangleThreshold)&&
					   mouse.loc.among(Mouse.Location.scene,Mouse.Location.minimap))
						mouse.status=Mouse.Status.rectangleSelect;
				}
			}else if(mouse.status==Mouse.Status.rectangleSelect){
				finishRectangleSelect();
			}
		}
		foreach(key;KEY_1..KEY_0+1){
			foreach(_;0..keyDown[key]){
				auto type=!shift && ctrl ? CommandType.defineGroup:
					shift && !ctrl ? CommandType.addToGroup :
					CommandType.selectGroup;
				int group = key==KEY_0?9:key-KEY_1;
				if(group>=numCreatureGroups) break;
				controller.addCommand(Command!DagonBackend(type,renderSide,camera.target,group));
				if(type==CommandType.addToGroup)
					controller.addCommand(Command!DagonBackend(CommandType.automaticSelectGroup,renderSide,camera.target,group));
			}
		}
		auto queueing=shift?CommandQueueing.post:CommandQueueing.none;
		void triggerBindable(Bindable command){
			void unsupported(){
				stderr.writeln("bindable command not yet supported: ",defaultName(command));
			}
			Lswitch: final switch(command) with(Bindable){
				case unknown: break;
				// control keys
				case moveForward,moveBackward,turnLeft,turnRight,cameraZoomIn,cameraZoomOut: enforce(0,"bad hotkeys"); break;
				// orders
				case attack:
					if(mouse.status==Mouse.Status.standard&&!mouse.dragging){
						mouse.status=Mouse.Status.icon;
						mouse.icon=MouseIcon.attack;
					}
					break;
				case guard:
					if(mouse.status==Mouse.Status.standard&&!mouse.dragging){
						mouse.status=Mouse.Status.icon;
						mouse.icon=MouseIcon.guard;
					}
					break;
				case retreat:
					auto target=Target(TargetType.creature,camera.target);
					controller.addCommand(Command!DagonBackend(CommandType.retreat,renderSide,camera.target,0,target,float.init));
					break;
				case move:
					with(TargetType) if(mouse.target.type.among(terrain,creature,building,soul)){ // TODO: sky
						auto target=Target(terrain,0,mouse.target.position,mouse.target.location);
						target.position.z=state.current.getHeight(target.position);
						controller.addCommand(Command!DagonBackend(CommandType.move,renderSide,camera.target,0,target,cameraFacing),queueing);
					}
					break;
				case useAbility:
					selectAbility(CommandQueueing.none);
					break;
				case dropSoul: unsupported(); break;
				// miscellanneous
				case optionsMenu,skipSpeech: unsupported(); break;
				case openNextSpellTab:
					switchSpellbookTab(cast(SpellType)((spellbookTab+1)%(spellbookTab.max+1)));
					break;
				case openCreationSpells:
					switchSpellbookTab(SpellType.creature);
					break;
				case openSpells:
					switchSpellbookTab(SpellType.spell);
					break;
				case openStructureSpells:
					switchSpellbookTab(SpellType.structure);
					break;
				case quickSave,quickLoad,pause,changeCamera,sendChatMessage,gammaCorrectionPlus,gammaCorrectionMinus,screenShot: unsupported(); break;
				// formations
				case semicircleFormation:
					controller.addCommand(Command!DagonBackend(renderSide,camera.target,Formation.semicircle));
					break;
				case circleFormation:
					controller.addCommand(Command!DagonBackend(renderSide,camera.target,Formation.circle));
					break;
				case phalanxFormation:
					controller.addCommand(Command!DagonBackend(renderSide,camera.target,Formation.phalanx));
					break;
				case wedgeFormation:
					controller.addCommand(Command!DagonBackend(renderSide,camera.target,Formation.wedge));
					break;
				case skirmishFormation:
					controller.addCommand(Command!DagonBackend(renderSide,camera.target,Formation.skirmish));
					break;
				case lineFormation:
					controller.addCommand(Command!DagonBackend(renderSide,camera.target,Formation.line));
					break;
				case flankLeftFormation:
					controller.addCommand(Command!DagonBackend(renderSide,camera.target,Formation.flankLeft));
					break;
				case flankRightFormation:
					controller.addCommand(Command!DagonBackend(renderSide,camera.target,Formation.flankRight));
					break;
				// taunts
				case randomTaunt: unsupported(); break;
				static foreach(i;1..4+1){
					case mixin(text(`taunt`,i)):
						unsupported();
						break Lswitch;
				}
				// spells
				static foreach(i;1..11+1){
					case mixin(text(`castCreationSpell`,i)):
						selectSpell(SpellType.creature,i-1);
						break Lswitch;
				}
				static foreach(i;1..11+1){
					case mixin(text(`castSpell`,i)):
						selectSpell(SpellType.spell,i-1);
						break Lswitch;
				}
				/+static foreach(i;1..11+1){
					case mixin(text(`castStructureSpell`,i)):
						selectSpell(SpellType.structure,i-1);
						break Lswitch;
				}+/
				case castManalith,castManahoar,castSpeedUp,castGuardian,castConvert,castDesecrate,castTeleport,castHeal,castShrine:
					selectSpell(command);
			}
		}
		foreach(ref hotkey;options.hotkeys[modifiers]){
			foreach(_;0..keyDown[hotkey.keycode])
				triggerBindable(hotkey.action);
		}
		mouse.additiveSelect=shift;
		selectionUpdated=false;
		if(mouse.status.among(oldMouseStatus,Mouse.Status.icon)){
			foreach(_;0..mouseButtonUp[MB_LEFT]){
				bool done=true;
				if(mouse.status.among(Mouse.Status.standard,Mouse.Status.icon)&&!mouse.dragging){
					if(mouse.target.type==TargetType.creatureTab){
						switchSpellbookTab(SpellType.creature);
					}else if(mouse.target.type==TargetType.spellTab){
						switchSpellbookTab(SpellType.spell);
					}else if(mouse.target.type==TargetType.structureTab){
						switchSpellbookTab(SpellType.structure);
					}else if(mouse.target.type==TargetType.spell){
						selectSpell(mouse.targetSpell);
					}else if(mouse.target.type==TargetType.ability){
						selectAbility(mouse.targetSpell,queueing);
					}else done=false;
				}else done=false;
				if(!done&&!mouse.dragging) final switch(mouse.status){
					case Mouse.Status.standard:
						if(mouse.target.type==TargetType.creature&&canSelect(renderSide,mouse.target.id,state.current)){
							auto type=mouse.additiveSelect?CommandType.toggleSelection:CommandType.select;
							enum doubleClickDelay=0.3f; // in seconds
							enum delta=targetCacheDelta;
							if(ctrl){
								type=CommandType.selectAll;
							}else if(type==CommandType.select&&(lastSelectedId==mouse.target.id||
							                              abs(lastSelectedX-mouse.x)<delta &&
							                              abs(lastSelectedY-mouse.y)<delta) &&
							         state.current.frame-lastSelectedFrame<=doubleClickDelay*updateFPS){
								type=CommandType.automaticSelectAll;
							}
							controller.addCommand(Command!DagonBackend(type,renderSide,camera.target,mouse.target.id,Target.init,cameraFacing));
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
					case Mouse.Status.rectangleSelect:
						finishRectangleSelect();
						break;
					case Mouse.Status.icon:
						if(mouse.targetValid){
							auto summary=mouse.target.summarize(renderSide,state.current);
							final switch(mouse.icon){
								case MouseIcon.attack:
									if(summary&(TargetFlags.creature|TargetFlags.wizard|TargetFlags.building)&&!(summary&TargetFlags.corpse)){
										controller.addCommand(Command!DagonBackend(CommandType.attack,renderSide,camera.target,0,mouse.target,cameraFacing),queueing);
									}else{
										auto target=Target(TargetType.terrain,0,mouse.target.position,mouse.target.location);
										controller.addCommand(Command!DagonBackend(CommandType.advance,renderSide,camera.target,0,target,cameraFacing),queueing);
									}
									mouse.status=Mouse.Status.standard;
									break;
								case MouseIcon.guard:
									if(summary&(TargetFlags.creature|TargetFlags.wizard|TargetFlags.building)&&!(summary&TargetFlags.corpse)){
										controller.addCommand(Command!DagonBackend(CommandType.guard,renderSide,camera.target,0,mouse.target,cameraFacing),queueing);
									}else{
										auto target=Target(TargetType.terrain,0,mouse.target.position,mouse.target.location);
										controller.addCommand(Command!DagonBackend(CommandType.guardArea,renderSide,camera.target,0,target,cameraFacing),queueing);
									}
									mouse.status=Mouse.Status.standard;
									break;
								case MouseIcon.spell:
									if(castSpell(mouse.spell,mouse.target))
										mouse.status=Mouse.Status.standard;
									break;
								case MouseIcon.ability:
									if(useAbility(mouse.spell,mouse.target,queueing))
										mouse.status=Mouse.Status.standard;
									break;
							}
						}else{
							auto status=mouse.icon==MouseIcon.spell?state.current.spellStatus!false(camera.target,mouse.spell,mouse.target):
								mouse.icon==MouseIcon.ability?state.current.abilityStatus!false(renderSide,mouse.spell,mouse.target):SpellStatus.invalidTarget;
							spellAdvisorHelpSpeech(status);
						}
						break;
				}
			}
			foreach(_;0..mouseButtonUp[MB_RIGHT]){
				if(!mouse.dragging) final switch(mouse.status){
					case Mouse.Status.standard:
						switch(mouse.target.type) with(TargetType){
							case terrain: controller.addCommand(Command!DagonBackend(CommandType.move,renderSide,camera.target,0,mouse.target,cameraFacing),queueing); break;
							case creature,building:
								auto summary=mouse.target.summarize(renderSide,state.current);
								if(!(summary&TargetFlags.untargetable)){
									if(summary&TargetFlags.corpse){
										auto target=Target(TargetType.terrain,0,mouse.target.position,mouse.target.location);
										controller.addCommand(Command!DagonBackend(CommandType.guardArea,renderSide,camera.target,0,target,cameraFacing),queueing); break;
									}else if(summary&TargetFlags.enemy){
										controller.addCommand(Command!DagonBackend(CommandType.attack,renderSide,camera.target,0,mouse.target,cameraFacing),queueing); break;
									}else if(summary&TargetFlags.manafount){
										castSpell("htlm",mouse.target);
									}else{
										controller.addCommand(Command!DagonBackend(CommandType.guard,renderSide,camera.target,0,mouse.target,cameraFacing),queueing); break;
									}
								}
								break;
							case soul:
								final switch(color(mouse.target.id,renderSide,state.current)){
									case SoulColor.blue:
										auto target=Target(TargetType.terrain,0,mouse.target.position,mouse.target.location);
										controller.addCommand(Command!DagonBackend(CommandType.move,renderSide,camera.target,0,target,cameraFacing),queueing);
										break;
									case SoulColor.red:
										castSpell("ccas",mouse.target);
										break;
								}
								break;
							default: break;
						}
						break;
					case Mouse.Status.rectangleSelect:
						// do nothing
						break;
					case Mouse.Status.icon:
						mouse.status=Mouse.Status.standard;
						if(audio) audio.playSound("kabI");
						updateCursor(0.0f);
						break;
				}
			}
		}
	}

	void cameraControl(double dt){
		if(fpview.active){
			float turn_m =  (eventManager.mouseRelX) * fpview.mouseFactor;
			float pitch_m = (eventManager.mouseRelY) * fpview.mouseFactor;

			fpview.camera.pitch += pitch_m;
			fpview.camera.turn += turn_m;
		}
		if(mouse.visible){
			if(!mouse.onMinimap){
				camera.targetZoom-=0.04f*eventManager.mouseWheelY;
				camera.targetZoom=max(0.0f,min(camera.targetZoom,1.0f));
			}else{
				import std.math:exp,log;
				camera.minimapZoom*=exp(log(1.3)*(-0.4f*eventManager.mouseWheelY+0.04f*(mouse.dragging?eventManager.mouseRelY:0)/hudScaling));
				camera.minimapZoom=max(0.5f,min(camera.minimapZoom,15.0f));
			}
		}
		bool ctrl=eventManager.keyPressed[KEY_LCTRL]||options.hotkeys.capsIsCtrl&&eventManager.keyPressed[KEY_CAPSLOCK];
		if(mouse.visible && mouse.status.among(Mouse.Status.standard,Mouse.Status.icon)){
			if(ctrl && eventManager.mouseButtonPressed[MB_LEFT]||
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
				mouse.x+=eventManager.mouseRelX/screenScaling;
				mouse.y+=eventManager.mouseRelY/screenScaling;
				mouse.x=max(0,min(mouse.x,width-1));
				mouse.y=max(0,min(mouse.y,height-1));
			}else{
				mouse.dragging=false;
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
		}
	}


	void observerControl(double dt)in{
		assert(!!state);
	}do{
	Vector3f forward = fpview.camera.worldTrans.forward;
		Vector3f right = fpview.camera.worldTrans.right;
		Vector3f dir = Vector3f(0, 0, 0);
		//if(eventManager.keyPressed[KEY_X]) dir += Vector3f(1,0,0);
		//if(eventManager.keyPressed[KEY_Y]) dir += Vector3f(0,1,0);
		//if(eventManager.keyPressed[KEY_Z]) dir += Vector3f(0,0,1);
		bool pressed(int[] keyCodes){ return keyCodes.any!(key=>eventManager.keyPressed[key]);}
		if(camera.target!=0&&(!state||!state.current.isValidTarget(camera.target,TargetType.creature))) camera.target=0;
		if(camera.target==0){
			if(pressed(options.hotkeys.moveForward)) dir += -forward;
			if(pressed(options.hotkeys.moveBackward)) dir += forward;
			if(pressed(options.hotkeys.turnLeft)) dir += -right;
			if(pressed(options.hotkeys.turnRight)) dir += right;
			if(eventManager.keyPressed[KEY_I]) speed = 10.0f;
			if(eventManager.keyPressed[KEY_O]) speed = 100.0f;
			if(eventManager.keyPressed[KEY_P]) speed = 1000.0f;
			fpview.camera.position += dir.normalized * speed * dt;
			if(state) fpview.camera.position.z=max(fpview.camera.position.z, state.current.getHeight(fpview.camera.position));
		}else positionCamera();
		if(!eventManager.keyPressed[KEY_LSHIFT] && !eventManager.keyPressed[KEY_LCTRL] && !eventManager.keyPressed[KEY_CAPSLOCK]){
			foreach(_;0..keyDown[KEY_M]){
				if(mouse.target.type==TargetType.creature&&mouse.target.id){
					renderSide=state.current.movingObjectById!(side,()=>-1)(mouse.target.id,state.current);
					focusCamera(mouse.target.id);
				}
			}
			foreach(_;0..keyDown[KEY_N]){
				renderSide=-1;
				camera.target=0;
			}
			if(keyDown[KEY_K]){
				fpview.active=false;
				mouse.visible=true;
			}
			if(keyDown[KEY_L]){
				fpview.active=true;
				mouse.visible=false;
				fpview.mouseFactor=0.25f;
			}
		}
	}

	void stateTestControl()in{
		assert(!!state);
	}do{
		static void applyToMoving(alias f,B)(ObjectState!B state,Camera camera,Target target){
			if(!state.isValidTarget(camera.target,TargetType.creature)) camera.target=0;
			static void perform(T)(ref T obj,ObjectState!B state){ f(obj,state); }
			if(camera.target==0){
				if(!state.isValidTarget(target.id,target.type)) target=Target.init;
				if(target.type.among(TargetType.none,TargetType.terrain))
					state.eachMoving!perform(state);
				else if(target.type==TargetType.creature)
					state.movingObjectById!perform(target.id,state);
			}else state.movingObjectById!perform(camera.target,state);
		}
		static void depleteMana(B)(ref MovingObject!B obj,ObjectState!B state){
			obj.creatureStats.mana=0.0f;
		}
		if(!eventManager.keyPressed[KEY_LSHIFT] && !eventManager.keyPressed[KEY_LCTRL] && !eventManager.keyPressed[KEY_CAPSLOCK]){
			//foreach(_;0..keyDown[KEY_A]) applyToMoving!depleteMana(state.current,camera,mouse.target);
			foreach(_;0..keyDown[KEY_PERIOD]) applyToMoving!kill(state.current,camera,mouse.target);
			foreach(_;0..keyDown[KEY_J]) applyToMoving!stun(state.current,camera,mouse.target);
			static void catapultRandomly(B)(ref MovingObject!B object,ObjectState!B state){
				import std.random;
				auto velocity=Vector3f(uniform!"[]"(-20.0f,20.0f), uniform!"[]"(-20.0f,20.0f), uniform!"[]"(10.0f,25.0f));
				//auto velocity=Vector3f(0.0f,0.0f,25.0f);
				object.catapult(velocity,state);
			}
			foreach(_;0..keyDown[KEY_RSHIFT]) applyToMoving!catapultRandomly(state.current,camera,mouse.target);
			foreach(_;0..keyDown[KEY_RETURN]) applyToMoving!immediateRevive(state.current,camera,mouse.target);
			//foreach(_;0..keyDown[KEY_G]) applyToMoving!startFlying(state.current,camera,mouse.target);
			//foreach(_;0..keyDown[KEY_V]) applyToMoving!land(state.current,camera,mouse.target);
			/+if(!eventManager.keyPressed[KEY_LSHIFT]) foreach(_;0..keyDown[KEY_SPACE]){
				//applyToMoving!startMeleeAttacking(state.current,camera,mouse.target);
				static void castingTest(B)(ref MovingObject!B object,ObjectState!B state){
					object.startCasting(3*updateFPS,true,state);
				}
				applyToMoving!castingTest(state.current,camera,mouse.target);
				/+if(camera.target){
					auto position=state.current.movingObjectById!((obj)=>obj.position,function Vector3f(){ return Vector3f.init; })(camera.target);
					destructionAnimation(position+Vector3f(0,0,5),state.current);
					//explosionAnimation(position+Vector3f(0,0,5),state.current);
				}+/
			}+/
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
			foreach(_;0..keyDown[KEY_U]) showHitboxes=true;
			foreach(_;0..keyDown[KEY_I]) showHitboxes=false;

			//foreach(_;0..keyDown[KEY_H]) state.commit();
			//foreach(_;0..keyDown[KEY_B]) state.rollback();

			foreach(_;0..keyDown[KEY_COMMA]) if(audio) audio.switchTheme(cast(Theme)((audio.currentTheme+1)%Theme.max));
		}

		/+if(camera.target){
			auto creatures=creatureSpells[options.god];
			static immutable hotkeys=[KEY_Q,KEY_Q,KEY_W,KEY_R,KEY_T,KEY_A,KEY_Z,KEY_X,KEY_C,KEY_V,KEY_SPACE];
			if(!eventManager.keyPressed[KEY_LSHIFT] && !(eventManager.keyPressed[KEY_LCTRL]||eventManager.keyPressed[KEY_CAPSLOCK])){
				if(creatures.length)
				foreach(_;0..keyDown[hotkeys[0]]){
					auto id=spawn(camera.target,creatures[0],0,state.current,false);
					state.current.addToSelection(renderSide,id);
				}
			}
			if(eventManager.keyPressed[KEY_LSHIFT] && !(eventManager.keyPressed[KEY_LCTRL]||eventManager.keyPressed[KEY_CAPSLOCK])){
				foreach(i;1..min(hotkeys.length,creatures.length)){
					foreach(_;0..keyDown[hotkeys[i]]){
						auto id=spawn(camera.target,creatures[i],0,state.current,false);
						state.current.addToSelection(renderSide,id);
					}
				}
			}
		}+/
	}

	override void onViewUpdate(double dt){
		if(options.scaleToFit) screenScaling=min(cast(float)eventManager.windowWidth/width,cast(float)eventManager.windowHeight/height);
		super.onViewUpdate(dt);
	}

	override void onLogicsUpdate(double dt){
		assert(dt==1.0f/updateFPS);
		//writeln(DagonBackend.getTotalGPUMemory()," ",DagonBackend.getAvailableGPUMemory());
		//writeln(eventManager.fps);
		if(state&&(options.observer||!controller.network)) observerControl(dt);
		if(state&&!controller.network) stateTestControl();
		control(dt);
		cameraControl(dt);
		if(state){
			if(controller){
				if(controller.step()) eventManager.update();
				if(options.testLag){
					if(controller.network){
						if(controller.network.isHost&&controller.network.playing){
							static bool delayed=false;
							if(!delayed){
								delayed=true;
								import core.thread;
								Thread.sleep(1.seconds);
								eventManager.update();
								eventManager.update();
							}
						}
					}
				}
			}else state.step();
			// state.commit();
			if(!state.current.isValidTarget(camera.target,TargetType.creature)) camera.target=0;
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
	Texture whiteTexture;
	ShapeSacCreatureFrame border;
	SacHud!DagonBackend sacHud;
	ShapeSubQuad selectionRoster, minimapFrame, minimapCompass;
	Texture healthColorTexture,manaColorTexture;
	ShapeSacStatsFrame statsFrame;
	ShapeSubQuad creatureTab,spellTab,structureTab,tabSelector;
	ShapeSubQuad creaturePage,spellPage,structurePage;
	ShapeCooldown cooldown;
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
		selectionRoster=New!ShapeSubQuad(assetManager,-63.5f/128.0f,0.0f,63.5f/128.0f,2.0f);
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
		cooldown=New!ShapeCooldown(assetManager);
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
			rectangleSelect,
			icon,
		}
		bool dragging;
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
	bool mouseTargetValid(Target target){
		if(mouse.status!=Mouse.Status.icon||mouse.dragging) return true;
		import spells:SpelFlags;
		enum orderSpelFlags=SpelFlags.targetWizards|SpelFlags.targetCreatures|SpelFlags.targetCorpses|SpelFlags.targetStructures|SpelFlags.targetGround|AdditionalSpelFlags.targetSacrificed;
		final switch(mouse.icon){
			case MouseIcon.guard: return isApplicable(orderSpelFlags,target.summarize(renderSide,state.current));
			case MouseIcon.attack: return isApplicable(orderSpelFlags,target.summarize(renderSide,state.current));
			case MouseIcon.spell: return !!state.current.spellStatus!false(camera.target,mouse.spell,target).among(SpellStatus.ready,SpellStatus.mustBeNearBuilding,SpellStatus.mustBeNearEnemyAltar,SpellStatus.mustBeConnectedToConversion);
			case MouseIcon.ability: return state.current.abilityStatus!false(renderSide,mouse.spell,target)==SpellStatus.ready;
		}
	}
	SacCursor!DagonBackend sacCursor;
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
	SacSpell!DagonBackend selectionRosterTargetAbility=null;
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
			if(!state.current.isValidTarget(id,TargetType.creature)&&!state.current.isValidTarget(id,TargetType.building)) return Target.init;
			static Target handle(B,T)(T obj,int renderSide,ObjectState!B state){
				enum isMoving=is(T==MovingObject!B);
				static if(isMoving) enum type=TargetType.creature;
				else enum type=TargetType.building;
				return Target(type,obj.id,obj.position,TargetLocation.scene);
			}
			return cur.objectById!handle(id,renderSide,cur);
		}else if(information.x==3){
			auto id=(cast(int)information.y)<<16|cast(int)information.z;
			if(!cur.isValidTarget(id,TargetType.soul)) return Target.init;
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
		if(target.id!=0&&!state.current.isValidTarget(target.id,target.type)) target=Target.init;
		auto targetValid=mouseTargetValid(target);
		static immutable importantTargets=[TargetType.creature,TargetType.soul];
		if(cachedTarget.id!=0&&!state.current.isValidTarget(cachedTarget.id,cachedTarget.type)) cachedTarget=Target.init;
		if(target.location.among(TargetLocation.scene,TargetLocation.minimap)){
			if(!importantTargets.canFind(target.type)&&!(target.location==TargetLocation.minimap&&target.type==TargetType.building)){
				auto delta=cachedTarget.location!=TargetLocation.minimap?targetCacheDelta:minimapTargetCacheDelta;
				if(cachedTarget.type!=TargetType.none){
					if((mouse.inHitbox || abs(cachedTargetX-mouse.x)<delta &&
					    abs(cachedTargetY-mouse.y)<delta)&&
					   cachedTargetFrame+(mouse.inHitbox?2:1)*targetCacheDuration>state.current.frame){
						target=cachedTarget;
						targetValid=mouseTargetValid(target);
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
		if(mouse.target.type==TargetType.ability)
			mouse.targetSpell=selectionRosterTargetAbility;
		mouse.targetValid=targetValid;
		auto summary=summarize!true(mouse.target,renderSide,state.current);
		with(Cursor)
			mouse.showFrame=targetValid && target.location==TargetLocation.scene &&
				!(summary&TargetFlags.corpse) &&
				((mouse.status.among(Mouse.Status.standard,Mouse.Status.rectangleSelect)&&!mouse.dragging &&
				  summary&(TargetFlags.soul|TargetFlags.creature|TargetFlags.wizard)) ||
				 (mouse.status==Mouse.Status.icon&&!mouse.dragging&&!!target.type.among(TargetType.creature,TargetType.building,TargetType.soul)));

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
		if(mouse.dragging) mouse.cursor=Cursor.drag;
		else final switch(mouse.status){
			case Mouse.Status.standard:
				mouse.cursor=mouse.target.cursor(renderSide,false,state.current);
				break;
			case Mouse.Status.rectangleSelect:
				mouse.cursor=Cursor.rectangleSelect;
				break;
			case Mouse.Status.icon:
				if(!spellbookVisible(camera.target)){
					mouse.status=Mouse.Status.standard;
					if(audio) audio.playSound("kabI");
					goto case Mouse.Status.standard;
				}
				mouse.cursor=mouse.target.cursor(renderSide,true,state.current);
				break;
		}
	}
	override void startGBufferInformationDownload(){
		if(mouse.onMinimap) return;
		static int i=0;
		if(options.printFps && ((++i)%=2)==0) writeln(eventManager.fps);
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
		auto width=cast(int)(options.width*options.scale);
		auto height=cast(int)(options.height*options.scale);
		super(width, height, options.enableFullscreen, "SacEngine", []);
		if(options.width==0||options.height==0){
			options.width=width;
			options.height=height;
		}
		scene = New!SacScene(sceneManager, options);
		sceneManager.addScene(scene, "Sacrifice");
		scene.load();
	}
}

struct DagonBackend{
	static MyApplication app;
	static @property SacScene scene(){
		if(!app) return null;
		return app.scene;
	}
	static @property GameState!DagonBackend state(){
		if(!app) return null;
		if(!app.scene) return null;
		return app.scene.state;
	}
	static @property Controller!DagonBackend controller(){
		if(!app) return null;
		if(!app.scene) return null;
		return app.scene.controller;
	}
	static @property Network!DagonBackend network(){
		if(!app) return null;
		if(!app.scene) return null;
		if(!app.scene.controller) return null;
		return app.scene.controller.network;
	}
	this(Options options){
		enforce(!app,"can only have one DagonBackend"); // TODO: fix?
		app = New!MyApplication(options);
	}
	void setState(GameState!DagonBackend state){
		scene.setState(state);
	}
	void focusCamera(int id){
		scene.focusCamera(id);
	}
	void setController(Controller!DagonBackend controller){
		scene.setController(controller);
	}
	void addObject(SacObject!DagonBackend obj,Vector3f position,Quaternionf rotation){
		scene.addObject(obj,position,rotation);
	}
	bool processEvents(){
		app.eventManager.update();
		app.processEvents();
		return app.eventManager.running;
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
	alias SubSphereMesh=.ShapeSubSphere;
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
			mat.roughness=1.0f;
			mat.metallic=0.5f;
			if(i==config.shinyPart){
				mat.emission=diffuse;
				mat.energy=0.5f;
			}
			materials~=mat;
		}
		return materials;
	}

	Material[] createTransparentMaterials(SacObject!DagonBackend sobj){
		GenericMaterial[] materials;
		foreach(i;0..sobj.isSaxs?sobj.saxsi.meshes.length:sobj.meshes.length){
			if(("blending" in sobj.materials[i].inputs).asInteger==Transparent){
				materials~=sobj.materials[i];
				continue;
			}
			auto mat=scene.createMaterial(gpuSkinning&&sobj.isSaxs?scene.shadelessBoneMaterialBackend:scene.shadelessMaterialBackend);
			mat.depthWrite=false;
			mat.blending=Transparent;
			auto diffuse=sobj.isSaxs?sobj.saxsi.saxs.bodyParts[i].texture:sobj.textures[i];
			if(diffuse !is null) mat.diffuse=diffuse;
			mat.specular=sobj.isSaxs?Color4f(1,1,1,1):Color4f(0,0,0,1);
			mat.roughness=1.0f;
			mat.metallic=0.5f;
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
		auto specu=0.1f*map.envi.landscapeSpecularity;
		mat.specular=Color4f(specu*map.envi.specularityRed/255.0f,specu*map.envi.specularityGreen/255.0f,specu*map.envi.specularityBlue/255.0f);
		//mat.roughness=1.0f-map.envi.landscapeGlossiness;
		mat.roughness=1.0f;
		mat.metallic=0.1f;
		mat.energy=0.05;
		if(map.tileset==Tileset.james) mat.detailFactor=0.0f;
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
			case manafount, manalith, manahoar, shrine, firy, fire, fireball, explosion, explosion2, speedUp, heal, relativeHeal, ghostTransition, ghost, lightningCasting, needle, redVortexDroplet, blueVortexDroplet, spark, castPersephone, castPyro, castJames, castStratos, castCharnel, wrathCasting, wrathExplosion1, wrathExplosion2, wrathParticle, steam, ashParticle, smoke, dirt, dust, rock, swarmHit, locustBlood, locustDebris:
				auto mat=scene.createMaterial(scene.shadelessMaterialBackend);
				mat.depthWrite=false;
				mat.blending=particle.type.among(ashParticle,smoke,dirt,dust,rock,swarmHit,locustBlood)?Transparent:Additive;
				if(particle.type==dust) mat.alpha=0.25f;
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
			bool spellReady=i==SacHud!DagonBackend.spellReadyIndex;
			auto mat=scene.createMaterial(spellReady?scene.hudMaterialBackend2:scene.hudMaterialBackend);
			mat.blending=spellReady?Additive:Transparent;
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

	uint ticks(){ return SDL_GetTicks(); }

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
	void playSpellbookSound(int side,SpellbookSoundFlags flags,char[4] sound,float gain=1.0f){
		if(!audio||side!=-1&&side!=scene.renderSide) return;
		final switch(scene.spellbookTab){
			case SpellType.creature: if(flags&SpellbookSoundFlags.creatureTab) break; return;
			case SpellType.spell: if(flags&SpellbookSoundFlags.spellTab) break; return;
			case SpellType.structure: if(flags&SpellbookSoundFlags.structureTab) break; return;
		}
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
	void stopSoundsAt(int id){
		if(!audio) return;
		audio.stopSoundsAt(id);
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

class ShapeSubSphere: Mesh{
	DynamicArray!Vector3f daVertices;
	DynamicArray!Vector3f daNormals;
	DynamicArray!Vector2f daTexcoords;
	DynamicArray!(uint[3]) daIndices;

	this(float radius, int slices, int stacks, bool invNormals, Owner o,float left,float top,float right,float bottom,bool rep=false){
		super(o);

		float X1, Y1, X2, Y2, Z1, Z2;
		float inc1, inc2, inc3, inc4, inc5, radius1, radius2;
		uint[3] tri;
		uint i = 0;

		float cuts = stacks;
		float invCuts = 1.0f / cuts;
		float heightStep = 2.0f * invCuts;

		float invSlices = 1.0f / slices;
		float angleStep = (2.0f * pi!float) * invSlices;

		for(int h = 0; h < stacks; h++){
			float h1Norm = cast(float)h * invCuts * 2.0f - 1.0f;
			float h2Norm = cast(float)(h+1) * invCuts * 2.0f - 1.0f;
			float y1 = sin(0.5f*pi!float * h1Norm);
			float y2 = sin(0.5f*pi!float * h2Norm);

			float circleRadius1 = cos(0.5f*pi!float * y1);
			float circleRadius2 = cos(0.5f*pi!float * y2);

			auto curBottom=bottom+(top-bottom)*h/stacks;
			auto curTop=bottom+(top-bottom)*(h+1)/stacks;

			for(int a = 0; a < slices*(rep?2:1); a++){
				auto curLeft=left+(right-left)*a/slices;
				auto curRight=left+(right-left)*(a+1)/slices;
				if(rep&&a>=slices){
					curLeft=left+(right-left)*(2*slices-a)/slices;
					curRight=left+(right-left)*(2*slices-1-a)/slices;
				}
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

				if(invNormals){
					tri[0] = i+2;
					tri[1] = i+1;
					tri[2] = i;
					daIndices.append(tri);

					tri[0] = i+5;
					tri[1] = i+4;
					tri[2] = i+3;
					daIndices.append(tri);
				}else{
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

class ShapeCooldown: Owner, Drawable{
	Vector2f[6] vertices;
	float[6] index;
	uint[3][4] indices;

	GLuint vao = 0;
	GLuint vbo = 0;
	GLuint vio = 0;
	GLuint eao = 0;

	this(Owner o){
		super(o);
		auto unit = sqrt(0.5f);
		vertices[0] = Vector2f(0, 0);
		vertices[1] = Vector2f(0, -unit);
		vertices[2] = Vector2f(unit, 0);
		vertices[3] = Vector2f(0, unit);
		vertices[4] = Vector2f(-unit, 0);
		vertices[5] = vertices[1];

		index=[0,1,2,3,4,5];

		indices[0] = [0,2,1];
		indices[1] = [0,3,2];
		indices[2] = [0,4,3];
		indices[3] = [0,5,4];

		glGenBuffers(1, &vbo);
		glBindBuffer(GL_ARRAY_BUFFER, vbo);
		glBufferData(GL_ARRAY_BUFFER, vertices.length * float.sizeof * 2, vertices.ptr, GL_STATIC_DRAW);

		glGenBuffers(1, &vio);
		glBindBuffer(GL_ARRAY_BUFFER, vio);
		glBufferData(GL_ARRAY_BUFFER, index.length * int.sizeof, index.ptr, GL_STATIC_DRAW);

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
		glBindBuffer(GL_ARRAY_BUFFER, vio);
		glVertexAttribPointer(1, 1, GL_FLOAT, GL_FALSE, 0, null);

		glBindVertexArray(0);
	}

	~this(){
		glDeleteVertexArrays(1, &vao);
		glDeleteBuffers(1, &vbo);
		glDeleteBuffers(1, &vio);
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
