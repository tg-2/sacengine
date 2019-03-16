import dlib.math, dlib.image.color;
import util;
import mrmm, _3dsm, txtr, saxs, sxsk, widg;
import animations, ntts, nttData, spells, bldg;
import stats;
import std.typecons: Tuple, tuple;
import std.stdio, std.conv;
alias Tuple=std.typecons.Tuple;

import std.exception, std.algorithm, std.range, std.math, std.path;
import state:updateAnimFactor;

enum animFPS=30;

final class SacObject(B){
	char[4] tag;
	char[4] nttTag;
	int stateIndex=-1;
	B.Mesh[] meshes;
	B.Texture[] textures;
	Vector3f[2][] hitboxes_;
	bool isSaxs=false;
	SaxsInstance!B saxsi;
	B.Material[] materials;
	B.Material[] shadowMaterials;
	Animation[] animations;
	immutable(Cre8)* cre8;
	immutable(CreatureData)* data;
	immutable(Wizd)* wizd;
	immutable(Strc)* strc;

	@property bool isWizard(){
		return !!wizd;
	}
	@property bool mustFly(){
		return cre8&&cre8.creatureType=="ylfo";
	}
	@property bool canRun(){
		return hasAnimationState(AnimationState.run);
	}
	@property bool canDie(){
		return hasAnimationState(AnimationState.death0);
	}
	@property bool canFly(){
		return hasAnimationState(AnimationState.fly);
	}
	@property bool canFlyBackward(){
		return tag=="zgub";
	}
	@property bool seamlessFlyAndHover(){
		return tag=="zgub";
	}
	@property bool movingAfterTakeoff(){
		return tag=="nmdd";
	}
	@property bool canAttack(){
		return hasAnimationState(AnimationState.attack0);
	}
	@property RotateOnGround rotateOnGround(){
		if(!data) return RotateOnGround.no;
		return data.rotateOnGround;
	}

	@property CreatureStats creatureStats(int flags){
		int souls;
		float maxHealth=0.0f,regeneration=0.0f,drain=0.0f,maxMana=0.0f;
		float runningSpeed=0.0f,flyingSpeed=0.0f,rangedAccuracy=0.0f,meleeResistance=0.0f;
		float directSpellResistance=0.0f,splashSpellResistance=0.0f;
		float directRangedResistance=0.0f,splashRangedResistance=0.0f;
		static foreach(name;["cre8","wizd"]){{
			mixin(`alias ntt=`~name~`;`);
			if(ntt){
				maxHealth=ntt.health;
				regeneration=ntt.regeneration*1e-3f*35.0f;
				drain=ntt.drain*1e-3f;
				maxMana=ntt.mana;
				runningSpeed=ntt.runningSpeed;
				flyingSpeed=ntt.flyingSpeed;
				rangedAccuracy=ntt.rangedAccuracy;
				meleeResistance=ntt.meleeResistance*1e-3f;
				directSpellResistance=ntt.directSpellResistance*1e-3f;
				splashRangedResistance=ntt.splashRangedResistance*1e-3f;
				directRangedResistance=ntt.directRangedResistance*1e-3f;
			}
		}}
		auto health=maxHealth;
		auto mana=maxMana;
		if(flags & Flags.corpse) health=0.0f;
		else if(flags & Flags.damaged) health/=10.0f;
		flags&=~Flags.corpse&~Flags.damaged;
		return CreatureStats(flags,health,mana,souls,maxHealth,regeneration,drain,maxMana,
		                     runningSpeed,flyingSpeed,rangedAccuracy,meleeResistance,
		                     directSpellResistance,splashSpellResistance,
		                     directRangedResistance,splashRangedResistance);
	}
	@property int numSouls(){
		if(!cre8) return 0;
		return cre8.souls;
	}

	@property Vector3f soulDisplacement(){
		if(!data) return Vector3f(0.0f,0.0f,0.0f);
		return data.soulDisplacement;
	}

	@property float meleeStrength(){
		if(cre8) return cre8.meleeStrength;
		return 0.0f;
	}
	@property float buildingMeleeDamageMultiplier(){
		if(data) return data.buildingMeleeDamageMultiplier;
		return 1.0f;
	}

	@property StunBehavior stunBehavior(){
		if(!data) return StunBehavior.none;
		return data.stunBehavior;
	}

	@property StunnedBehavior stunnedBehavior(){
		if(!data) return StunnedBehavior.normal;
		return data.stunnedBehavior;
	}

	@property bool continuousRegeneration(){
		if(!data) return false;
		return data.continuousRegeneration;
	}

	@property bool hasKnockdown(){
		return hasAnimationState(AnimationState.knocked2Floor);
	}
	@property bool hasFalling(){
		return hasAnimationState(AnimationState.falling);
	}
	@property bool hasHitFloor(){
		return hasAnimationState(AnimationState.hitFloor);
	}
	@property bool hasGetUp(){
		return hasAnimationState(AnimationState.getUp);
	}
	@property bool hasFlyDamage(){
		return hasAnimationState(AnimationState.flyDamage);
	}
	@property bool canTumble(){
		return hasAnimationState(AnimationState.tumble);
	}

	@property bool isManahoar(){
		return tag=="oham";
	}
	@property Vector3f manahoarManaOffset(AnimationState animationState,int frame)in{
		assert(isManahoar);
	}do{
		return saxsi.saxs.positions[0].offset*animations[animationState].frames[frame].matrices[saxsi.saxs.positions[0].bone];
	}
	// TODO: the following logic is duplicated for buildings
	@property bool isManafount(){
		return manafountTags.canFind(tag);
	}
	@property bool isManalith(){
		return manalithTags.canFind(tag);
	}
	@property bool isShrine(){
		return shrineTags.canFind(tag);
	}
	@property bool isAltar(){
		return altarBaseTags.canFind(tag);
	}
	@property bool isAltarRing(){
		return altarRingTags.canFind(tag);
	}

	Vector3f[2] smallHitbox(Quaternionf rotation,AnimationState animationState,int frame)in{
		assert(isSaxs);
	}do{
		auto transforms=animations[animationState].frames[frame].matrices;
		return saxsi.saxs.hitboxBones
			.map!(i=>Vector3f(0,0,0)*transforms[i])
			.map!(v=>rotate(rotation,v)).bbox;
	}

	Vector3f[2] largeHitbox(Quaternionf rotation,AnimationState animationState,int frame)in{
		assert(isSaxs);
	}do{
		auto transforms=animations[animationState].frames[frame].matrices;
		return saxsi.saxs.hitboxBones
			.map!(i=>saxsi.saxs.bones[i].hitbox[].map!(x=>x*transforms[i]))
			.joiner.map!(v=>rotate(rotation,v)).bbox;
	}

	Vector3f[2] hitbox(Quaternionf rotation,AnimationState animationState,int frame)in{
		assert(isSaxs);
	}do{
		if(!data) return largeHitbox(rotation,animationState,frame);
		final switch(data.hitboxType){
			case HitboxType.small:
				return smallHitbox(rotation,animationState,frame);
			case HitboxType.large:
				return largeHitbox(rotation,animationState,frame);
			case HitboxType.largeZ:
				auto sl=smallHitbox(rotation,animationState,frame);
				auto sll=largeHitbox(rotation,animationState,frame);
				sl[0][2]=sll[0][2];
				sl[1][2]=sll[1][2];
				return sl;
			case HitboxType.largeZbot:
				auto sl=smallHitbox(rotation,animationState,frame);
				auto sll=largeHitbox(rotation,animationState,frame);
				sl[0][2]=sll[0][2];
				return sl;
		}
	}

	Vector3f[2] hitbox2d(AnimationState animationState,int frame,Matrix4f modelViewProjectionMatrix)in{
		assert(isSaxs);
	}do{
		auto transforms=animations[animationState].frames[frame].matrices;
		return iota(saxsi.saxs.bones.length)
			.map!(i=>saxsi.saxs.bones[i].hitbox[].map!(x=>x*transforms[i]))
			.joiner.map!(v=>transform(modelViewProjectionMatrix,v)).bbox;
	}

	Vector3f[2] hitbox2d(Quaternionf rotation,Matrix4f modelViewProjectionMatrix)in{
		assert(!isSaxs);
	}do{
		return hitboxes(rotation).map!(hbox=>cartesianProduct(only(0,1),only(0,1),only(0,1)).map!(x=>Vector3f(hbox[x[0]].x,hbox[x[1]].y,hbox[x[2]].z)))
			.joiner.map!(v=>transform(modelViewProjectionMatrix,v)).bbox;
	}

	int numAttackTicks(AnimationState animationState){
		return max(1,animations[animationState].numAttackTicks);
	}

	bool hasAttackTick(AnimationState animationState,int frame){
		if(animations[animationState].numAttackTicks==0) return frame+1==animations[animationState].frames.length;
		return animations[animationState].frames[frame].event==AnimEvent.attack;
	}

	Vector3f[2] meleeHitbox(Quaternionf rotation,AnimationState animationState,int frame)in{
		assert(isSaxs);
	}do{
		// TODO: this is a guess. what does the game actually do?
		auto hbox=hitbox(rotation,animationState,frame);
		auto center=0.5f*(hbox[0]+hbox[1]);
		auto width=hbox[1].x-hbox[0].x;
		auto depth=hbox[1].y-hbox[0].y;
		auto height=hbox[1].z-hbox[0].z;
		auto size=0.25f*(width+depth);
		auto hitboxCenter=size*rotate(rotation,Vector3f(0.0f,1.0f,0.0f));
		if(tag=="raeb") hitboxCenter*=3.0f;
		else if(tag=="elab") hitboxCenter*=2.0f;
		else hitboxCenter*=1.3f;
		hitboxCenter+=center;
		auto hitboxDimensions=Vector3f(width,depth,height*1.5f);
		return [hitboxCenter-0.5f*hitboxDimensions,hitboxCenter+0.5f*hitboxDimensions];
	}

	auto hitboxes(Quaternionf rotation)/+@nogc+/ in{
		assert(!isSaxs);
	}do{
		auto len=rotation.xyz.length;
		auto angle=2*atan2(len,rotation.w);
		if(angle>PI) angle-=2*PI;
		else if(angle<-PI) angle+=2*PI;
		if(rotation.z<0) angle=-angle;
		auto aangle=abs(angle);
		static enum HitboxRotation{
			deg0,
			deg90,
			deg180,
			deg270,
		}
		auto hitboxRotation=HitboxRotation.deg0;
		if(aangle>2*PI/360.0f*45.0f){
			if(aangle<2*PI/360.0f*135.0f){
				if(angle>0) hitboxRotation=HitboxRotation.deg90;
				else hitboxRotation=HitboxRotation.deg270;
			}else hitboxRotation=HitboxRotation.deg180;
		}
		static Vector3f[2] rotateHitbox(HitboxRotation rotation,Vector3f[2] hitbox){
			final switch(rotation){
				case HitboxRotation.deg0:
					return hitbox;
				case HitboxRotation.deg90:
					// [x,y,z] ↦ [-y,x,z]
					return [Vector3f(-hitbox[1].y,hitbox[0].x,hitbox[0].z),
					        Vector3f(-hitbox[0].y,hitbox[1].x,hitbox[1].z)];
				case HitboxRotation.deg180:
					// [x,y,z] ↦ [-x,-y,z]
					return [Vector3f(-hitbox[1].x,-hitbox[1].y,hitbox[0].z),
					        Vector3f(-hitbox[0].x,-hitbox[0].y,hitbox[1].z)];
				case HitboxRotation.deg270:
					// [x,y,z] ↦ [y,-x,z]
					return [Vector3f(hitbox[0].y,-hitbox[1].x,hitbox[0].z),
					        Vector3f(hitbox[1].y,-hitbox[0].x,hitbox[1].z)];
			}
		}
		return zip(hitboxRotation.repeat,hitboxes_).map!(x=>rotateHitbox(x.expand));
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
		if(cre8||wizd) data=creatureDataByTag(nttTag);
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
		saxsi=SaxsInstance!B(loadSaxs!B(model,alphaFlags(dat2.saxsModel)));
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
				if(exists(anim)&&(!(&animID !is &dat2.animations.stance1 && animID==dat2.animations.stance1)
				                  ||i==AnimationState.hover)
				){
					auto animation=loadSXSK(anim,saxsi.saxs.scaling);
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
		hitboxes_=mt[2];
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

	this(string filename, float zfactorOverride=float.nan,string animation=""){
		enforce(filename.endsWith(".MRMM")||filename.endsWith(".3DSM")||filename.endsWith(".WIDG")||filename.endsWith(".SXMD"));
		switch(filename[$-4..$]){
			case "MRMM":
				auto mt=loadMRMM!B(filename, 1.0f);
				meshes=mt[0];
				textures=mt[1];
				hitboxes_=mt[2];
				break;
			case "3DSM":
				auto mt=load3DSM!B(filename, 1.0f);
				meshes=mt[0];
				textures=mt[1];
				break;
			case "WIDG":
				auto mt=loadWIDG!B(filename);
				meshes=[mt[0]];
				textures=[mt[1]];
				break;
			case "SXMD":
				isSaxs=true;
				saxsi=SaxsInstance!B(loadSaxs!B(filename,alphaFlags(tag)));
				if(!isNaN(zfactorOverride)) saxsi.saxs.zfactor=zfactorOverride;
				import std.range, std.array;
				if(animation.length)
					loadAnimation(animation);
				if(!animations.length){
					auto anim=Animation(0,[Pose(Vector3f(0,0,0),AnimEvent.none,facingQuaternion(0).repeat(saxsi.saxs.bones.length).array)]);
					static if(gpuSkinning)
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

	void loadAnimation(string animation){ // (just for testing)
		enforce(animations.length<=1);
		auto anim=loadSXSK(animation,saxsi.saxs.scaling);
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
		assert(frame<numFrames(animationState),text(tag," ",animationState," ",frame," ",numFrames(animationState)));
	}body{
		saxsi.setPose(animations[animationState].frames[frame]);
	}
}

enum SoulColor{
	blue,
	red,
	//green,
}

B.Mesh[] makeSpriteMeshes(B)(int nU,int nV,float width,float height){ // TODO: replace with shader
	auto meshes=new B.Mesh[](nU*nV);
	foreach(int i,ref mesh;meshes){
		mesh=B.makeMesh(4,2);
		int u=i%nU,v=i/nU;
		foreach(k;0..4) mesh.vertices[k]=Vector3f(-0.5f*width+width*(k==1||k==2),-0.5f*height+height*(k==2||k==3),0.0f);
		foreach(k;0..4) mesh.texcoords[k]=Vector2f(1.0f/nU*(u+(k==1||k==2)),1.0f/nV*(v+(k==0||k==1)));
		static immutable uint[3][] indices=[[0,1,2],[2,3,0]];
		mesh.indices[]=indices[];
		mesh.generateNormals();
		B.finalizeMesh(mesh);
	}
	return meshes;
}

auto blueSoulFrameColor=Color4f(0,182.0f/256.0f,1.0f);
auto redSoulFrameColor=Color4f(1.0f,0.0f,0.0f);

auto blueSoulMinimapColor=Color4f(0,165.0f/256.0f,1.0f);
auto redSoulMinimapColor=Color4f(1.0f,0.0f,0.0f);

final class SacSoul(B){
	B.Mesh[] meshes;
	B.Texture texture;
	B.Material material;

	enum soulWidth=1.0f;
	enum soulHeight=1.6f*soulWidth;
	enum soulRadius=0.3f;

	this(){
		// TODO: extract soul meshes at all different frames from original game
		meshes=makeSpriteMeshes!B(4,4,soulWidth,soulHeight);
		texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/spir.TXTR"));
		material=B.createMaterial(this);
	}
	enum numFrames=16;
	B.Mesh getMesh(SoulColor color,int frame){
		return meshes[(color==SoulColor.red?8:0)+frame/2];
	}
}

enum ParticleType{
	manafount,
	manalith,
	shrine,
	manahoar,
}

final class SacParticle(B){
	int stateIndex=-1;
	B.Mesh[] meshes;
	B.Texture texture;
	B.Material material;
	ParticleType type;
	Color4f color;
	float energy=20.0f;
	float width,height;
	@property bool gravity(){
		final switch(type){
			case ParticleType.manafount:
				return true;
			case ParticleType.manalith,ParticleType.shrine,ParticleType.manahoar:
				return false;
		}
	}
	this(ParticleType type,Color4f color=Color4f(1.0f,1.0f,1.0f,1.0f),float energy=20.0f){
		this.type=type;
		this.color=color;
		this.energy=energy;
		// TODO: extract soul meshes at all different frames from original game
		final switch(type){
			case ParticleType.manafount:
				width=height=6.0f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/elec.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case ParticleType.manalith:
				width=height=12.0f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/fb_g.TXTR"));
				meshes=makeSpriteMeshes!B(3,3,width,height);
				break;
			case ParticleType.shrine:
				width=height=4.0f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/fb_g.TXTR"));
				meshes=makeSpriteMeshes!B(3,3,width,height);
				break;
			case ParticleType.manahoar:
				width=height=1.2f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/fb_g.TXTR"));
				meshes=makeSpriteMeshes!B(3,3,width,height);
				break;
		}
		material=B.createMaterial(this);
	}
	static SacParticle!B[ParticleType.max+1] particles;
	static SacParticle!B get(ParticleType type){
		if(!particles[type]) particles[type]=new SacParticle(type);
		return particles[type];
	}
	@property int numFrames(){
		return cast(int)meshes.length*updateAnimFactor;
	}
	B.Mesh getMesh(int frame){
		return meshes[frame/updateAnimFactor];
	}
	float getAlpha(int lifetime){
		final switch(type){
			case ParticleType.manafount:
				return min(1.0f,(lifetime/(3.0f*numFrames))^^2);
			case ParticleType.manalith,ParticleType.shrine,ParticleType.manahoar:
				return min(0.07f,(lifetime/(4.0f*numFrames))^^2);
		}
	}
	float getScale(int lifetime){
		final switch(type){
			case ParticleType.manafount:
				return 1.0f;
			case ParticleType.manalith,ParticleType.manahoar:
				return min(1.0f,lifetime/(4.0f*numFrames));
			case ParticleType.shrine:
				return min(1.0f,lifetime/(3.0f*numFrames));
		}
	}
}

enum Cursor{
	normal,
	friendlyUnit,
	neutralUnit,
	rescuableUnit,
	talkingUnit,
	enemyUnit,
	friendlyBuilding,
	neutralBuilding,
	enemyBuilding,
	blueSoul,
	rectangleSelect,
	drag,
	slide,

	iconFriendly,
	iconNeutral,
	iconEnemy,
	iconNone,
}

final class SacCursor(B){
	B.Texture[Cursor.max+1] textures;
	B.Material[] materials;
	this(){
		textures[Cursor.normal]=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/curs.FLDR/Cnor.ICON"));
		textures[Cursor.friendlyUnit]=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/curs.FLDR/Cfun.ICON"));
		textures[Cursor.neutralUnit]=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/curs.FLDR/Cnun.ICON"));
		textures[Cursor.rescuableUnit]=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/curs.FLDR/Crun.ICON"));
		textures[Cursor.talkingUnit]=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/curs.FLDR/Ctlk.ICON"));
		textures[Cursor.enemyUnit]=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/curs.FLDR/Ceun.ICON"));
		textures[Cursor.friendlyBuilding]=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/curs.FLDR/Cfbg.ICON"));
		textures[Cursor.neutralBuilding]=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/curs.FLDR/Cnbg.ICON"));
		textures[Cursor.enemyBuilding]=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/curs.FLDR/Cebg.ICON"));
		textures[Cursor.blueSoul]=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/curs.FLDR/Cspr.ICON"));
		textures[Cursor.rectangleSelect]=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/curs.FLDR/Cdbx.ICON"));
		textures[Cursor.drag]=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/curs.FLDR/Cdrg.ICON"));
		textures[Cursor.slide]=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/curs.FLDR/Csld.ICON"));

		textures[Cursor.iconFriendly]=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/curs.FLDR/Tfrn.ICON"));
		textures[Cursor.iconNeutral]=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/curs.FLDR/Tntr.ICON"));
		textures[Cursor.iconEnemy]=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/curs.FLDR/Tnme.ICON"));
		textures[Cursor.iconNone]=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/curs.FLDR/Tnon.ICON"));
		assert(textures[].all!(t=>t!is null));
		materials=B.createMaterials(this);
	}
}

final class SacHud(B){
	union{
		B.Texture[11] textures;
		struct{
			B.Texture frames;
			B.Texture pages;
			B.Texture arrows;
			B.Texture tabs;
			B.Texture[3] mana;
			B.Texture[3] health;
			B.Texture minimapIcons;
		}
	}
	B.Material[] materials;
	@property B.Material frameMaterial(){ return materials[0]; }
	@property B.Material tabsMaterial(){ return materials[3]; }
	@property B.Material manaTopMaterial(){ return materials[4]; }
	@property B.Material manaMaterial(){ return materials[5]; }
	@property B.Material manaBottomMaterial(){ return materials[6]; }
	@property B.Material healthTopMaterial(){ return materials[7]; }
	@property B.Material healthMaterial(){ return materials[8]; }
	@property B.Material healthBottomMaterial(){ return materials[9]; }
	@property B.Material minimapIconsMaterial(){ return materials[10]; }
	this(){
		frames=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/huds.FLDR/fram.TXTR"));
		pages=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/huds.FLDR/page.TXTR"));
		arrows=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/huds.FLDR/sarr.TXTR"));
		tabs=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/huds.FLDR/tabs.TXTR"));
		import dlib.image;
		static immutable ubyte[] manaTopData=[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 46, 70, 22, 0, 42, 66, 43, 0, 42, 66, 43, 0, 42, 66, 43, 0, 42, 66, 43, 0, 42, 66, 43, 0, 64, 68, 64, 0, 86, 67, 85, 0, 86, 67, 85, 0, 86, 67, 85, 0, 86, 67, 85, 0, 84, 67, 85, 0, 64, 68, 64, 0, 42, 66, 43, 0, 42, 66, 43, 0, 42, 66, 43, 0, 42, 66, 43, 0, 42, 69, 43, 0, 36, 67, 21, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 105, 22, 0, 65, 101, 43, 0, 64, 100, 64, 0, 64, 100, 64, 0, 64, 100, 64, 0, 62, 100, 64, 0, 85, 101, 86, 0, 107, 101, 107, 0, 128, 100, 128, 0, 128, 100, 128, 0, 128, 100, 128, 0, 128, 101, 127, 0, 106, 100, 106, 0, 84, 100, 85, 0, 64, 100, 64, 0, 64, 100, 64, 0, 64, 100, 64, 0, 64, 100, 64, 0, 62, 101, 43, 0, 61, 98, 21, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 81, 134, 22, 0, 83, 137, 43, 0, 84, 134, 64, 0, 83, 134, 86, 0, 83, 134, 86, 0, 83, 134, 86, 0, 105, 134, 107, 0, 128, 134, 128, 0, 149, 134, 149, 0, 170, 134, 170, 0, 170, 134, 170, 0, 170, 134, 170, 0, 149, 134, 149, 0, 127, 134, 128, 0, 105, 134, 107, 0, 83, 134, 86, 0, 83, 134, 86, 0, 84, 134, 85, 0, 84, 134, 64, 0, 83, 134, 43, 0, 85, 134, 21, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 104, 169, 22, 0, 107, 167, 43, 0, 104, 168, 64, 0, 104, 167, 86, 0, 105, 167, 107, 0, 105, 167, 107, 0, 127, 168, 128, 0, 148, 167, 149, 0, 170, 168, 171, 0, 191, 168, 192, 0, 213, 167, 213, 0, 213, 168, 212, 0, 191, 167, 191, 0, 170, 167, 170, 0, 147, 168, 149, 0, 126, 168, 128, 0, 105, 167, 107, 0, 105, 168, 106, 0, 105, 169, 85, 0, 104, 168, 64, 0, 104, 167, 43, 0, 103, 171, 21, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
		mana[0]=B.makeTexture(imageFromData(manaTopData,32,4,4));
		static immutable ubyte[] manaData=[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 198, 22, 0, 125, 202, 43, 0, 124, 200, 64, 0, 125, 201, 86, 0, 125, 201, 107, 0, 126, 201, 128, 0, 147, 201, 149, 0, 169, 201, 170, 0, 190, 200, 192, 0, 212, 200, 213, 0, 233, 201, 234, 0, 255, 201, 255, 0, 233, 200, 234, 0, 212, 201, 212, 0, 190, 201, 191, 0, 168, 200, 170, 0, 147, 201, 149, 0, 126, 200, 128, 0, 125, 201, 106, 0, 126, 202, 85, 0, 124, 200, 64, 0, 125, 199, 43, 0, 121, 201, 21, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
		mana[1]=B.makeTexture(imageFromData(manaData,32,1,4));
		static immutable ubyte[] manaBottomData=[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 198, 22, 0, 125, 202, 43, 0, 124, 200, 64, 0, 125, 199, 86, 0, 124, 201, 107, 0, 126, 200, 128, 0, 147, 201, 149, 0, 168, 200, 170, 0, 190, 200, 191, 0, 212, 200, 213, 0, 233, 200, 234, 0, 254, 200, 255, 0, 233, 200, 233, 0, 212, 200, 212, 0, 190, 201, 191, 0, 168, 200, 170, 0, 146, 200, 149, 0, 125, 200, 128, 0, 125, 200, 106, 0, 126, 202, 85, 0, 124, 200, 64, 0, 124, 201, 42, 0, 121, 195, 21, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 104, 169, 22, 0, 104, 167, 43, 0, 104, 168, 64, 0, 104, 167, 86, 0, 103, 166, 106, 0, 105, 167, 107, 0, 126, 167, 128, 0, 147, 167, 149, 0, 170, 167, 170, 0, 191, 167, 191, 0, 212, 166, 212, 0, 212, 166, 212, 0, 190, 167, 191, 0, 169, 167, 170, 0, 147, 167, 148, 0, 125, 167, 127, 0, 103, 166, 106, 0, 103, 166, 106, 0, 105, 166, 85, 0, 104, 168, 64, 0, 103, 167, 42, 0, 109, 171, 21, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 87, 134, 22, 0, 83, 134, 43, 0, 84, 132, 64, 0, 84, 133, 85, 0, 84, 133, 85, 0, 84, 134, 85, 0, 105, 134, 106, 0, 127, 134, 128, 0, 149, 134, 149, 0, 170, 134, 170, 0, 170, 134, 170, 0, 170, 133, 169, 0, 148, 133, 148, 0, 126, 133, 127, 0, 103, 133, 106, 0, 84, 133, 85, 0, 84, 133, 85, 0, 84, 133, 85, 0, 84, 134, 64, 0, 82, 134, 42, 0, 85, 134, 21, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 99, 22, 0, 62, 101, 43, 0, 64, 100, 64, 0, 64, 100, 64, 0, 64, 100, 64, 0, 64, 100, 64, 0, 84, 100, 85, 0, 106, 100, 106, 0, 126, 101, 127, 0, 126, 101, 127, 0, 126, 101, 127, 0, 126, 101, 127, 0, 106, 100, 106, 0, 84, 100, 85, 0, 64, 100, 64, 0, 64, 100, 64, 0, 64, 100, 64, 0, 64, 100, 64, 0, 61, 101, 42, 0, 61, 98, 21, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 41, 70, 22, 0, 42, 69, 43, 0, 42, 69, 43, 0, 42, 69, 43, 0, 42, 69, 43, 0, 42, 66, 43, 0, 64, 68, 64, 0, 84, 67, 85, 0, 84, 67, 85, 0, 84, 67, 85, 0, 84, 67, 85, 0, 84, 68, 85, 0, 63, 65, 63, 0, 42, 69, 43, 0, 42, 69, 43, 0, 42, 69, 43, 0, 42, 69, 43, 0, 43, 67, 42, 0, 36, 61, 21, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 24, 37, 21, 0, 24, 37, 21, 0, 24, 37, 21, 0, 24, 37, 21, 0, 24, 37, 21, 0, 18, 31, 21, 0, 43, 31, 42, 0, 43, 31, 42, 0, 43, 31, 42, 0, 43, 31, 42, 0, 43, 31, 42, 0, 43, 31, 42, 0, 24, 37, 21, 0, 24, 37, 21, 0, 24, 37, 21, 0, 24, 37, 21, 0, 24, 37, 21, 0, 24, 37, 21, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
		mana[2]=B.makeTexture(imageFromData(manaBottomData,32,6,4));
		static immutable ubyte[] healthTopData=[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 23, 0, 1, 22, 42, 0, 1, 43, 42, 0, 1, 43, 42, 0, 1, 43, 42, 0, 1, 43, 42, 0, 1, 43, 64, 20, 20, 64, 86, 43, 43, 86, 86, 43, 43, 86, 86, 43, 43, 86, 86, 43, 43, 86, 84, 42, 43, 85, 64, 20, 20, 64, 42, 0, 1, 43, 42, 0, 1, 43, 42, 0, 1, 43, 42, 0, 1, 43, 43, 0, 0, 42, 24, 0, 1, 21, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 23, 0, 1, 22, 42, 0, 1, 43, 64, 0, 1, 64, 64, 0, 1, 64, 64, 0, 1, 64, 64, 0, 1, 64, 86, 22, 23, 86, 107, 43, 43, 107, 128, 64, 64, 128, 128, 64, 64, 128, 128, 64, 64, 128, 128, 64, 64, 128, 106, 42, 43, 106, 84, 21, 22, 85, 64, 0, 1, 64, 64, 0, 1, 64, 64, 0, 1, 64, 64, 0, 1, 64, 43, 0, 0, 42, 24, 0, 1, 21, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 23, 0, 1, 22, 42, 0, 1, 43, 64, 0, 1, 64, 86, 0, 1, 86, 86, 0, 1, 86, 86, 0, 1, 86, 107, 21, 22, 107, 128, 43, 43, 128, 149, 64, 65, 149, 170, 86, 86, 171, 170, 86, 86, 171, 170, 86, 86, 170, 149, 63, 64, 149, 128, 43, 43, 128, 106, 20, 21, 106, 86, 0, 1, 86, 86, 0, 1, 86, 84, 0, 1, 85, 64, 0, 1, 64, 43, 0, 0, 42, 24, 0, 1, 21, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 23, 0, 1, 22, 42, 0, 1, 43, 64, 0, 1, 64, 86, 0, 1, 86, 107, 0, 1, 107, 107, 0, 1, 107, 128, 23, 23, 129, 150, 43, 44, 150, 171, 64, 64, 170, 191, 86, 86, 192, 213, 107, 107, 213, 213, 106, 107, 212, 191, 86, 86, 192, 170, 64, 65, 171, 149, 43, 43, 149, 128, 22, 22, 128, 107, 0, 1, 107, 106, 0, 1, 106, 84, 0, 1, 85, 64, 0, 1, 64, 43, 0, 0, 42, 24, 0, 1, 21, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
		health[0]=B.makeTexture(imageFromData(healthTopData,32,4,4));
		static immutable ubyte[] healthData=[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 23, 0, 1, 22, 42, 0, 1, 43, 64, 0, 1, 64, 86, 0, 1, 86, 107, 0, 1, 107, 128, 0, 1, 128, 149, 21, 22, 149, 171, 43, 43, 170, 191, 64, 65, 192, 213, 86, 86, 213, 234, 107, 107, 234, 255, 128, 129, 255, 233, 107, 107, 234, 213, 85, 85, 212, 191, 64, 65, 192, 170, 43, 43, 171, 149, 21, 21, 149, 128, 0, 1, 128, 106, 0, 1, 106, 84, 0, 1, 85, 64, 0, 1, 64, 43, 0, 0, 42, 24, 0, 1, 21, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
		health[1]=B.makeTexture(imageFromData(healthData,32,1,4));
		static immutable ubyte[] healthBottomData=[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 23, 0, 1, 22, 42, 0, 1, 43, 64, 0, 1, 64, 86, 0, 1, 86, 107, 0, 1, 107, 128, 0, 1, 128, 149, 21, 22, 149, 171, 43, 43, 170, 191, 64, 65, 192, 213, 85, 86, 212, 234, 107, 107, 234, 255, 128, 129, 254, 233, 106, 107, 234, 213, 85, 86, 212, 191, 64, 65, 191, 170, 42, 43, 170, 149, 21, 22, 149, 128, 0, 1, 128, 106, 0, 1, 106, 84, 0, 1, 85, 64, 0, 1, 64, 43, 0, 1, 42, 24, 0, 1, 21, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 23, 0, 1, 22, 42, 0, 1, 43, 64, 0, 1, 64, 86, 0, 1, 86, 107, 1, 2, 107, 129, 0, 1, 107, 149, 22, 22, 128, 171, 43, 43, 149, 192, 65, 65, 170, 213, 86, 86, 192, 235, 107, 108, 212, 255, 128, 128, 212, 234, 107, 107, 191, 213, 85, 86, 169, 191, 64, 64, 148, 171, 42, 43, 127, 149, 20, 21, 106, 128, 0, 1, 106, 105, 0, 1, 85, 85, 0, 0, 63, 65, 3, 3, 43, 36, 0, 1, 21, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 23, 0, 1, 22, 42, 0, 1, 43, 64, 0, 1, 64, 86, 1, 2, 86, 108, 0, 1, 85, 129, 0, 1, 85, 149, 20, 21, 106, 171, 42, 43, 127, 192, 64, 65, 149, 213, 86, 86, 170, 234, 107, 107, 170, 255, 128, 128, 169, 234, 107, 107, 148, 213, 84, 85, 127, 192, 65, 65, 106, 171, 42, 43, 85, 150, 21, 22, 85, 129, 0, 1, 85, 108, 0, 1, 64, 85, 0, 1, 42, 61, 0, 1, 21, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 23, 0, 1, 22, 42, 0, 1, 43, 64, 0, 1, 64, 85, 0, 0, 63, 108, 0, 1, 64, 128, 0, 1, 64, 150, 21, 22, 85, 171, 43, 44, 106, 191, 65, 65, 128, 213, 85, 86, 127, 235, 106, 107, 127, 255, 129, 129, 127, 233, 106, 106, 106, 213, 86, 86, 85, 191, 64, 64, 64, 171, 44, 44, 64, 147, 20, 20, 64, 128, 0, 1, 64, 107, 3, 3, 43, 85, 0, 1, 21, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 23, 0, 1, 22, 43, 0, 0, 42, 65, 0, 1, 43, 85, 0, 0, 42, 107, 0, 1, 43, 128, 0, 0, 42, 150, 20, 21, 63, 171, 44, 44, 85, 192, 65, 65, 85, 213, 86, 86, 85, 234, 107, 107, 85, 255, 128, 128, 84, 235, 105, 106, 63, 213, 85, 86, 42, 190, 65, 66, 43, 170, 43, 43, 42, 148, 24, 24, 43, 128, 0, 1, 42, 109, 0, 1, 21, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 24, 0, 1, 21, 46, 6, 6, 22, 61, 0, 1, 21, 85, 0, 1, 21, 109, 0, 1, 21, 128, 6, 6, 22, 152, 21, 22, 42, 170, 43, 43, 42, 194, 64, 64, 42, 213, 85, 86, 42, 237, 106, 107, 42, 255, 128, 128, 42, 231, 109, 110, 21, 209, 87, 87, 22, 194, 61, 61, 21, 170, 43, 43, 21, 146, 24, 25, 21, 134, 0, 1, 21, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
		health[2]=B.makeTexture(imageFromData(healthBottomData,32,6,4));
		minimapIcons=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/icon.FLDR/mmic.TXTR"));
		materials=B.createMaterials(this);
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
