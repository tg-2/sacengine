// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import dlib.math, dlib.image.color;
import util;
import mrmm, _3dsm, txtr, saxs, sxsk, widg;
import animations, ntts, nttData, spells, sacspell, bldg, sset;
import stats;
import std.typecons: Tuple, tuple;
import std.stdio, std.conv;
static import std.typecons;
alias Tuple=std.typecons.Tuple;

import dlib.math.portable;
import std.exception, std.algorithm, std.range, std.path;
import state:updateFPS,updateAnimFactor;

enum animFPS=30;

enum RenderMode{
	opaque,
	transparent,
}

final class SacObject(B){
	char[4] tag;
	char[4] nttTag;
	string name;
	int[RenderMode.max+1] stateIndex=-1;
	B.Mesh[][] meshes;
	B.Texture[] textures;
	B.Texture icon;
	Vector3f[2][] hitboxes_;
	bool isSaxs=false;
	SaxsInstance!B saxsi;
	size_t numParts(){ return isSaxs?saxsi.meshes.length:meshes[0].length; }
	B.Material[] materials;
	B.Material[] transparentMaterials;
	B.Material[] shadowMaterials;
	Animation[] animations;
	SacSpell!B[3] abilities;
	SacSpell!B passiveAbility;
	SacSpell!B passiveAbility2;
	immutable(Cre8)* cre8;
	immutable(CreatureData)* data;
	immutable(Wizd)* wizd;
	immutable(Strc)* strc;

	immutable(Sset)* sset;
	immutable(Sset)* meleeSset;

	@property bool isWizard(){
		return !!wizd;
	}
	private bool isPeasant_;
	@property bool isPeasant(){
		return isPeasant_;
	}
	@property bool isSacDoctor(){
		return nttTag==SpellTag.sacDoctor;
	}
	@property bool isHero(){
		return heroCreatures.canFind(nttTag);
	}
	@property bool isFamiliar(){
		return familiarCreatures.canFind(nttTag);
	}
	@property int creaturePriority(){
		return cre8?cre8.spellOrder:0;
	}
	@property bool mustFly(){
		return cre8&&cre8.creatureType=="ylfo";
	}
	@property bool isPacifist(){
		return !cre8||cre8.aggressiveness==0||isSacDoctor||isFamiliar;
	}
	@property float aggressiveRange(){
		if(auto ra=rangedAttack) return ra.range; // TODO: ok?
		enum aggressiveDistance=65.0f; // ok?
		return aggressiveDistance;
	}
	@property float guardAggressiveRange(){
		return aggressiveRange()+10.0f; // ok?
	}
	@property float advanceAggressiveRange(){
		return aggressiveRange()+25.0f; // ok?
	}
	@property float guardRange(){
		enum guardDistance=60.0f; // ok?
		if(auto ra=rangedAttack) return max(guardDistance,0.75f*ra.range); // TODO: ok?
		return guardDistance;
	}
	@property bool canRun(){
		return hasAnimationState(AnimationState.run,false);
	}
	@property bool canDie(){
		return hasAnimationState(AnimationState.death0,false);
	}
	@property bool canFly(){
		return hasAnimationState(AnimationState.fly,false);
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
	@property float takeoffTime(){
		if(!hasAnimationState(AnimationState.takeoff)) return 0.0f;
		return cast(float)animations[AnimationState.takeoff].frames.length/animFPS;
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
				regeneration=ntt.regeneration/60.0f; // convert from amount per minute to amount per second
				drain=ntt.drain*1e-3f;
				maxMana=ntt.mana;
				runningSpeed=ntt.runningSpeed*1e-2f;
				flyingSpeed=ntt.flyingSpeed*1e-2f;
				rangedAccuracy=ntt.rangedAccuracy*(1.0f/ushort.max);
				if(nttTag==SpellTag.tickferno) rangedAccuracy/=1.6f; // TODO: make configurable
				meleeResistance=ntt.meleeResistance*1e-3f;
				splashSpellResistance=ntt.splashSpellResistance*1e-3f;
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

	@property StunnedBehavior stunnedBehavior(){
		if(!data) return StunnedBehavior.normal;
		return data.stunnedBehavior;
	}

	@property bool continuousRegeneration(){
		if(!data) return false;
		return data.continuousRegeneration;
	}

	@property float xpOnKill(){ // TODO: correct?
		// estimated from XP bar screenshots:
		if(isPeasant) return 250.0f;
		if(isManahoar) return 300.0f;
		if(isSacDoctor) return 500.0f;
		// sac wiki (rafradek):
		if(cre8){
			auto level=cre8.spellOrder/100;
			switch(level){
				case 1: return 1500;
				case 2: return 3000;
				case 3: return 3500;
				case 4: return 5000;
				case 5: return 5000;
				case 6: return 5500;
				case 7: return 6500;
				case 9: return 10000;
				default: break;
			}
		}
		if(isWizard) return 5000.0f;
		return 500; // ?
	}

	@property bool hasKnockdown(bool fasterStandupTimes){
		return hasAnimationState(AnimationState.knocked2Floor,fasterStandupTimes);
	}
	@property bool hasFalling(){
		return hasAnimationState(AnimationState.falling,false);
	}
	@property bool hasHitFloor(bool fasterStandupTimes){
		return hasAnimationState(AnimationState.hitFloor,fasterStandupTimes);
	}
	@property bool hasGetUp(bool fasterStandupTimes){
		return hasAnimationState(AnimationState.getUp,fasterStandupTimes);
	}
	@property bool hasFlyDamage(){
		return hasAnimationState(AnimationState.flyDamage,false);
	}
	@property bool canTumble(){
		return hasAnimationState(AnimationState.tumble,false);
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

	@property char[4] loopingSound(){
		// TODO: precompute
		if(isManafount) return "tnof";
		if(isManalith) return "htlm";
		if(isAltar||isShrine) return "rifa";
		return "\0\0\0\0";
	}

	Vector3f[2] smallHitbox(Quaternionf rotation,float scale,AnimationState animationState,int frame)@nogc in{
		assert(isSaxs);
	}do{
		auto transforms=animations[animationState].frames[frame].matrices;
		/+return saxsi.saxs.hitboxBones
			.map!(i=>Vector3f(0,0,0)*transforms[i])
			.map!(v=>rotate(rotation,v)).bbox;+/
		return saxsi.saxs.hitboxBones
			.mapf(closure!((i,transforms)=>Vector3f(0,0,0)*transforms[i])(transforms))
			.mapf(closure!((v,rotation)=>rotate(rotation,v))(rotation)).bbox.scaleBox(scale);
	}

	Vector3f[2] largeHitbox(Quaternionf rotation,float scale,AnimationState animationState,int frame)@nogc in{
		assert(isSaxs);
	}do{
		auto transforms=animations[animationState].frames[frame].matrices;
		/+return saxsi.saxs.hitboxBones
			.map!(i=>saxsi.saxs.bones[i].hitbox[].map!(x=>x*transforms[i]))
			.joiner.map!(v=>rotate(rotation,v)).bbox;+/
		return saxsi.saxs.hitboxBones
			.mapf(closure!((i,saxsi,transforms)=>saxsi.saxs.bones[i].hitbox[].mapf(closure!((x,i,transforms)=>x*transforms[i])(i,transforms)))(saxsi,transforms))
			.joiner.mapf(closure!((v,rotation)=>rotate(rotation,v))(rotation)).bbox.scaleBox(scale);
	}

	Vector3f[2] hitbox(Quaternionf rotation,float scale,AnimationState animationState,int frame)@nogc in{
		assert(isSaxs);
	}do{
		if(!data) return largeHitbox(rotation,scale,animationState,frame);
		final switch(data.hitboxType){
			case HitboxType.small:
				return smallHitbox(rotation,scale,animationState,frame);
			case HitboxType.large:
				return largeHitbox(rotation,scale,animationState,frame);
			case HitboxType.largeZ:
				auto sl=smallHitbox(rotation,scale,animationState,frame);
				auto sll=largeHitbox(rotation,scale,animationState,frame);
				sl[0][2]=sll[0][2];
				sl[1][2]=sll[1][2];
				return sl;
			case HitboxType.largeZbot:
				auto sl=smallHitbox(rotation,scale,animationState,frame);
				auto sll=largeHitbox(rotation,scale,animationState,frame);
				sl[0][2]=sll[0][2];
				return sl;
		}
	}

	Vector3f[2] hitbox2d(AnimationState animationState,int frame,Matrix4f modelViewProjectionMatrix)@nogc in{
		assert(isSaxs);
	}do{
		auto transforms=animations[animationState].frames[frame].matrices;
		/+return iota(saxsi.saxs.bones.length)
			.map!(i=>saxsi.saxs.bones[i].hitbox[].map!(x=>x*transforms[i]))
			.joiner.map!(v=>transform(modelViewProjectionMatrix,v)).bbox;+/
		return iota(saxsi.saxs.bones.length)
			.mapf(closure!((i,saxsi,transforms)=>saxsi.saxs.bones[i].hitbox[].mapf(closure!((x,i,transforms)=>x*transforms[i])(i,transforms)))(saxsi,transforms))
			.joiner.mapf(closure!((v,modelViewProjectionMatrix)=>transform(modelViewProjectionMatrix,v))(modelViewProjectionMatrix)).bbox;
	}

	Vector3f[2] hitbox2d(Quaternionf rotation,Matrix4f modelViewProjectionMatrix)@nogc in{
		assert(!isSaxs);
	}do{
		static Vector3f[2] fix(Vector3f[2] hitbox)@nogc {
			hitbox[0].z=max(0,hitbox[0].z);
			return hitbox;
		}
		/+return hitboxes(rotation).map!fix.map!(hbox=>cartesianProduct(only(0,1),only(0,1),only(0,1)).map!(x=>Vector3f(hbox[x[0]].x,hbox[x[1]].y,hbox[x[2]].z)))
			.joiner.map!(v=>transform(modelViewProjectionMatrix,v)).bbox;+/
			float scale=1.0f;
			return hitboxes(rotation,scale).map!fix.map!(hbox=>cartesianProduct(only(0,1),only(0,1),only(0,1)).mapf(closure!((x,hbox)=>Vector3f(hbox[x[0]].x,hbox[x[1]].y,hbox[x[2]].z))(hbox)))
			.joiner.mapf(closure!((v,modelViewProjectionMatrix)=>transform(modelViewProjectionMatrix,v))(modelViewProjectionMatrix)).bbox;
	}

	Vector3f[2] handsFromAnimation(float scale,AnimationState from,AnimationState animationState,int frame)@nogc{
		Vector3f[2] result;
		foreach(i;0..2){
			auto hand=animations[from].hands[i];
			if(hand.bone==0) continue;
			result[i]=scale*(hand.position*animations[animationState].frames[frame].matrices[hand.bone]);
		}
		return result;
	}

	Vector3f[2] hands(float scale,AnimationState animationState,int frame){
		return handsFromAnimation(scale,animationState,animationState,frame);
	}
	Vector3f[2] needle(float scale,AnimationState animationState,int frame){
		Vector3f[2] result;
		if(!isSacDoctor) return result;
		auto hand=Hand(16,Vector3f(0.0f,0.0f,2.2f));
		result[0]=scale*(hand.position*animations[animationState].frames[frame].matrices[hand.bone]);
		result[1]=scale*(animations[animationState].frames[frame].matrices[hand.bone].rotate(Vector3f(0.0f,0.0f,1.0f)));
		return result;
	}
	struct LoadedArrow{
		Vector3f top;
		Vector3f bottom;
		Vector3f front;
		Vector3f hand;
	}
	LoadedArrow loadedArrow(float scale,AnimationState animationState,int frame){
		LoadedArrow result;
		if(!(nttTag==SpellTag.sylph||nttTag==SpellTag.ranger)) return result;
		auto front=animations[animationState].hands[0];
		if(front.bone==0) return result;
		auto matrices=animations[animationState].frames[frame].matrices;
		auto topBone=16;
		auto bottomBone=17;
		auto handBone=11;
		result.top=scale*(Vector3f(0.0f,0.65f,0.0f)*matrices[topBone]);
		result.bottom=scale*(Vector3f(0.0f,-0.60f,0.0f)*matrices[bottomBone]);
		result.front=scale*((front.position+Vector3f(-0.1f,0.4f,0.0f))*matrices[front.bone]);
		result.hand=scale*(Vector3f(0.0f,0.1f,0.05f)*matrices[handBone]);
		return result;
	}
	Vector3f warmongerFlame(float scale,AnimationState animationState,int frame){
		auto hand=Hand(6,Vector3f(-0.1f,1.35f,0.0f));
		return scale*(hand.position*animations[animationState].frames[frame].matrices[hand.bone]);
	}
	Vector3f styxFlame(float scale,AnimationState animationState,int frame){
		auto hand=Hand(6,Vector3f(0.0f,1.1f,0.0f));
		return scale*(hand.position*animations[animationState].frames[frame].matrices[hand.bone]);
	}
	Vector3f shotPosition(float scale,AnimationState animationState,int frame,bool fix=false){
		auto hand=animations[fix?AnimationState.shoot0:animationState].hands[0];
		if(hand.bone<0||hand.bone>=animations[animationState].frames[frame].matrices.length) return Vector3f(0.0f,0.0f,0.0f);
		return scale*(hand.position*animations[animationState].frames[frame].matrices[hand.bone]);
	}
	Vector3f firstShotPosition(float scale,AnimationState animationState){
		return shotPosition(scale,animationState,firstShootTick(animationState));
	}
	int castingTime(AnimationState animationState){
		return max(0,min(numFrames(animationState)-1,animations[animationState].castingTime));
	}

	int numAttackTicks(AnimationState animationState){
		return max(1,animations[animationState].numAttackTicks);
	}
	int firstAttackTick(AnimationState animationState){
		return max(0,min(numFrames(animationState)-1,animations[animationState].firstAttackTick));
	}

	bool hasAttackTick(AnimationState animationState,int frame){
		if(animations[animationState].numAttackTicks==0) return frame+1==animations[animationState].frames.length;
		return animations[animationState].frames[frame].event==AnimEvent.attack;
	}

	@property bool isRanged(){ return data && data.ranged; }
	@property SacSpell!B rangedAttack(){ return isRanged?abilities[0]:null; }
	@property SacSpell!B passiveOnDamage(){ return abilities[2]; } // TODO: rename (e.g., has phoenix shield)

	bool hasLoadTick(AnimationState animationState,int frame){
		return animations[animationState].frames[frame].event==AnimEvent.load;
	}

	int numShootTicks(AnimationState animationState){
		return max(1,animations[animationState].numShootTicks);
	}
	int firstShootTick(AnimationState animationState){
		return max(0,min(numFrames(animationState)-1,animations[animationState].firstShootTick));
	}

	bool hasShootTick(AnimationState animationState,int frame){
		if(animations[animationState].numShootTicks==0) return frame+1==animations[animationState].frames.length;
		return animations[animationState].frames[frame].event==AnimEvent.shoot;
	}

	@property SacSpell!B ability(){ return isRanged?abilities[1]:abilities[0]; }

	Vector3f[2] defaultMeleeHitbox(Quaternionf rotation,float scale,AnimationState animationState,int frame)in{
		assert(isSaxs);
	}do{
		// TODO: this is a guess. what does the game actually do?
		auto hbox=hitbox(rotation,scale,animationState.stance1,0);
		auto center=0.5f*(hbox[0]+hbox[1]);
		auto width=hbox[1].x-hbox[0].x;
		auto depth=hbox[1].y-hbox[0].y;
		auto height=hbox[1].z-hbox[0].z;
		auto size=0.25f*(width+depth);
		auto hitboxCenter=size*rotate(rotation,Vector3f(0.0f,1.0f,0.0f));
		if(nttTag==SpellTag.taurock) hitboxCenter*=3.0f;
		if(nttTag==SpellTag.netherfiend) hitboxCenter*=3.0f;
		else if(nttTag==SpellTag.boulderdash) hitboxCenter*=2.0f;
		else if(nttTag==SpellTag.phoenix) hitboxCenter*=1.5f;
		else if(nttTag==SpellTag.hellmouth) hitboxCenter*=1.5f;
		else hitboxCenter*=1.3f;
		hitboxCenter+=center;
		auto hitboxDimensions=Vector3f(width,depth,height*1.5f);
		if(nttTag==SpellTag.phoenix){
			hitboxCenter.z-=5.0f;
			hitboxDimensions.z*=1.2f;
		}
		return [hitboxCenter-0.5f*hitboxDimensions,hitboxCenter+0.5f*hitboxDimensions];
	}

	Vector3f[2] meleeHitbox(bool isFlying,Quaternionf rotation,float scale,AnimationState animationState,int frame)in{
		assert(isSaxs);
	}do{
		// TODO: do we even want this at all?
		/+auto hbox=hitbox(rotation,animationState.stance1,0);
		if(nttTag!=SpellTag.dragon){
			auto size=0.5f*boxSize(hbox).length;
			Vector3f[6] fistLoc;
			int nFistLoc=0;
			AnimationState[1] currentAnimation=animationState;
			scope const(AnimationState)[] attackAnimations;
			with(AnimationState){
				static immutable attackCandidatesOnGround=[attack0,attack1,attack2];
				static immutable attackCandidatesInAir=[flyAttack];
				immutable const(AnimationState)[] animations;
				if(isFlying) attackAnimations=attackCandidatesInAir;
				else attackAnimations=attackCandidatesOnGround;
			}
			foreach(attackAnimation;attackAnimations)
				if(animationState==attackAnimation)
					attackAnimations=currentAnimation[];
			foreach(attackAnimation;attackAnimations){
				if(!hasAnimationState(attackAnimation)) continue;
				auto hands=hands(attackAnimation,firstAttackTick(attackAnimation));
				foreach(i;0..2){
					fistLoc[nFistLoc++]=hands[i];
					if(!isNaN(fistLoc[nFistLoc-1].x)){
						fistLoc[nFistLoc-1]=rotate(rotation,fistLoc[nFistLoc-1]);
					}else nFistLoc--;
				}
			}
			if(nFistLoc>0){
				Vector3f[2] hitbox=[fistLoc[0],fistLoc[0]];
				foreach(i;1..nFistLoc){
					hitbox[0].x=min(hitbox[0].x,fistLoc[i].x);
					hitbox[0].y=min(hitbox[0].y,fistLoc[i].y);
					hitbox[0].z=min(hitbox[0].z,fistLoc[i].z);
					hitbox[1].x=max(hitbox[1].x,fistLoc[i].x);
					hitbox[1].y=max(hitbox[1].y,fistLoc[i].y);
					hitbox[1].z=max(hitbox[1].z,fistLoc[i].z);
				}
				hitbox[0]-=0.5f*size;
				hitbox[1]+=0.5f*size;
				return hitbox;
			}
		}+/
		return defaultMeleeHitbox(rotation,scale,animationState,frame);
	}

	auto hitboxes(Quaternionf rotation,float scale)/+@nogc+/ in{
		assert(!isSaxs);
	}do{
		auto len=rotation.xyz.length;
		auto angle=2*atan2(len,rotation.w);
		if(angle>pi!float) angle-=2*pi!float;
		else if(angle<-pi!float) angle+=2*pi!float;
		if(rotation.z<0) angle=-angle;
		auto aangle=abs(angle);
		static enum HitboxRotation{
			deg0,
			deg90,
			deg180,
			deg270,
		}
		auto hitboxRotation=HitboxRotation.deg0;
		if(aangle>2*pi!float/360.0f*45.0f){
			if(aangle<2*pi!float/360.0f*135.0f){
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
		static Vector3f[2] scaleHitbox(float scale,Vector3f[2] hitbox){
			hitbox[0]*=scale;
			hitbox[1]*=scale;
			return hitbox;
		}
		return zip(scale.repeat,zip(hitboxRotation.repeat,hitboxes_).map!(x=>rotateHitbox(x.expand))).map!(x=>scaleHitbox(x.expand));
	}

	struct MaterialConfig{
		int sunBeamPart=-1;
		int locustWingPart=-1;
		int transparentShinyParts=0;
		int shinyPart=-1;
	}

	private void initializeNTTData(char[4] tag,char[4] nttTag){
		this.tag=tag;
		this.nttTag=nttTag;
		this.name=texts.get(nttTag,"");
		cre8=nttTag in cre8s;
		wizd=nttTag in wizds;
		strc=nttTag in strcs;
		if(cre8){
			sset=cre8.creatureSSET in ssets;
			meleeSset=cre8.meleeSSET in ssets;
		}else if(wizd) sset=wizd.wizardSSET in ssets;
		if(cre8||wizd) data=creatureDataByTag(nttTag);
		enforce((cre8 !is null)+(wizd !is null)+(strc !is null)<=1);
		auto iconTag=cre8?cre8.icon:wizd?wizd.icon:strc?strc.icon:cast(char[4])"\0\0\0\0";
		if(iconTag!="\0\0\0\0"){
			enforce(iconTag in icons,text(iconTag," ",icons));
			icon=B.makeTexture(loadTXTR(icons[iconTag]));
		}
		if(cre8){
			static foreach(i;0..3){
				if(mixin(text(`cre8.ability`,i))!="\0\0\0\0")
					abilities[i]=SacSpell!B.get(mixin(text(`cre8.ability`,i)));
			}
			if(cre8.passiveAbility!="\0\0\0\0")
				passiveAbility=SacSpell!B.get(cre8.passiveAbility);
			if(cre8.passiveAbility2!="\0\0\0\0")
				passiveAbility2=SacSpell!B.get(cre8.passiveAbility2);
		}
		MaterialConfig conf;
		// TODO: this is a hack:
		auto kind=tag;
		reverse(kind[]);
		// sunbeams
		if(kind.among("pcsb","casb")) conf.sunBeamPart=0;
		// manaliths
		if(kind.among("mana","cama")) conf.transparentShinyParts=1<<0;
		if(kind.among("jman","stam","pyma")) conf.transparentShinyParts=1<<1;
		// crystals
		if(kind.among("crpt","stc1","stc2","stc3","sfir","stst")) conf.transparentShinyParts=1<<0;
		if(kind.among("sfor")) conf.transparentShinyParts=1<<0;
		if(kind.among("SAW1","SAW2","SAW3","SAW4","SAW5")) conf.transparentShinyParts=1<<0;
		if(kind.among("ST01","ST02","ST03")) conf.transparentShinyParts=1<<0;
		// ethereal altar, ethereal sunbeams
		if(kind.among("ea_b","ea_r","esb1","esb2","esb_","etfn")) conf.sunBeamPart=0;
		// "eis1","eis2", "eis3", "eis4" ?
		if(kind.among("st4a")){
			conf.transparentShinyParts=1<<0;
			conf.sunBeamPart=1;
		}
		// locust wings
		if(kind.among("bugz")) conf.locustWingPart=3;
		if(kind.among("bold")) conf.shinyPart=0;
		// dragon fire
		if(kind.among("dfir")) conf.transparentShinyParts=1<<0|1<<1;
		if(!materials.length) materials=B.createMaterials(this,conf);
		if(!transparentMaterials.length) transparentMaterials=B.createTransparentMaterials(this);
		if(!shadowMaterials.length) shadowMaterials=B.createShadowMaterials(this);
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
	static SacObject!B[char[4]] overrides;
	void setOverride(){ // (uses GC)
		overrides[tag]=this;
		foreach(obj;objects) if(obj.tag==tag){
			enforce(obj.isSaxs==isSaxs,"unsupported override");
			obj.isSaxs=isSaxs;
			obj.saxsi=saxsi;
			obj.meshes=meshes;
			obj.textures=textures;
			obj.materials=materials;
			obj.transparentMaterials=transparentMaterials;
			obj.shadowMaterials=shadowMaterials;
		}
	}
	private this(T)(char[4] tag,T* hack) if(is(T==Creature)||is(T==Wizard)){
		isSaxs=true;
		auto data=creatureDataByTag(tag);
		enforce(!!data, tag[]);
		static if(is(T==Creature)){
			enforce(!!(tag in cre8s),text("unknown creature tag '",tag,"'"));
			auto dat2=&cre8s[tag];
		}else static if(is(T==Wizard)){
			enforce(!!(tag in wizds),text("unknown wizard tag '",tag,"'"));
			auto dat2=&wizds[tag];
		}
		else static assert(0);
		auto model=saxsModls[dat2.saxsModel];
		saxsi=SaxsInstance!B(loadSaxs!B(model,alphaFlags(dat2.saxsModel)));
		if(!isNaN(data.zfactorOverride)) saxsi.saxs.zfactor=data.zfactorOverride;
		auto anims=&dat2.animations;
		auto animIDs=dat2.animations.animations[];
		isPeasant_=peasantTags.canFind(tag);
		animations=new Animation[](animIDs.length+(isPeasant?4:0));
		foreach(i,ref animID;animIDs){
			static immutable string[2][] bad=[["2fwc","oppx"],["pezH","tsZB"],["glsd","tsGB"],["ycrp","tsTS"],
			                                  ["bobs","tsZB"],["guls","tsGB"],["craa","tsGB"],["crpd","tsTS"]];
			if(!(animID=="rezW"||animID[0..2]=="00"||bad.any!(x=>x[0]==tag&&x[1]==animID))){
				auto anim=getSaxsAnim(model,animID);
				if(fileExists(anim)&&(!(&animID !is &dat2.animations.stance1 && animID==dat2.animations.stance1)
				                  ||i==AnimationState.hover)
				){
					auto animation=loadSXSK(anim,saxsi.saxs.scaling);
					auto ok=animation.compile(saxsi.saxs);
					if(!ok) writeln("warning: ",animID," is bad for ",tag);
					animations[i]=animation;
				}
			}
		}
		if(isPeasant){
			with(AnimationState){
				animations[fly]=animations[land]=Animation.init;
				static foreach(i,state;[flyDeath/+pullDown+/,flyDamage/+dig+/,takeoff/+cower+/,flyAttack/+talkCower+/]){
					animations[pullDown+i]=animations[state];
					animations[state]=Animation.init;
				}
			}
		}
		if(tag.among(SpellTag.gremlin,SpellTag.seraph))
			with(AnimationState) swap(animations[shoot0],animations[shoot1]);
		if(dat2.saxsModel in overrides){
			auto sac=overrides[dat2.saxsModel];
			enforce(sac.isSaxs,"unsupported override");
			saxsi=sac.saxsi;
			this.textures=sac.textures;
			this.materials=sac.materials;
			this.transparentMaterials=sac.transparentMaterials;
			this.shadowMaterials=sac.shadowMaterials;
		}else saxsi.createMeshes(animations[AnimationState.stance1].frames[0]);
		initializeNTTData(dat2.saxsModel,tag);
		if(isSacDoctor){
			animations[AnimationState.death0]=animations[cast(AnimationState)SacDoctorAnimationState.dance];
		}
		//if(isWizard) printWizardStats(this,false);
	}
	static SacObject!B[char[4]] objects;
	static void resetStateIndex(){
		foreach(tag,obj;objects) obj.stateIndex[]=-1;
	}
	static SacObject!B getSAXS(T)(char[4] tag)if(is(T==Creature)||is(T==Wizard)){ // (uses GC)
		if(auto r=tag in objects) return *r;
		return objects[tag]=new SacObject!B(tag,(T*).init); // hack
	}

	private this(T)(char[4] tag, T* hack) if(is(T==Structure)){
		enforce(!!(tag in bldgModls),text("unknown structure tag '",tag,"'"));
		auto mt=loadMRMM!B(bldgModls[tag],1.0f);
		meshes=mt[0];
		textures=mt[1];
		hitboxes_=mt[2];
		initializeNTTData(tag,tag);
	}
	static SacObject!B getBLDG(char[4] tag){ // (uses GC)
		if(auto r=tag in objects) return *r;
		return objects[tag]=new SacObject!B(tag,(Structure*).init); // hack
	}

	private this(T)(char[4] tag, T* hack) if(is(T==Widgets)){ // (uses GC)
		enforce(!!(tag in widgModls),text("unknown widget tag '",tag,"'"));
		auto mt=loadWIDG!B(widgModls[tag]);
		meshes=[[mt[0]]];
		textures=[mt[1]];
		initializeNTTData(tag,tag);
	}
	static SacObject!B getWIDG(char[4] tag){ // (uses GC)
		if(auto r=tag in objects) return *r;
		return objects[tag]=new SacObject!B(tag,(Widgets*).init); // hack
	}

	static SacObject!B get(char[4] tag){
		if(auto r=tag in objects) return *r;
		if(tag in wizds) return getSAXS!Wizard(tag);
		if(tag in cre8s) return getSAXS!Creature(tag);
		if(tag in bldgModls) return getBLDG(tag);
		if(tag in widgModls) return getWIDG(tag);
		enforce(0,text("bad tag: ",tag));
		assert(0);
	}

	this(string filename, float zfactorOverride=float.nan,string animation=""){ // (uses GC)
		enforce(filename.endsWith(".MRMM")||filename.endsWith(".3DSM")||filename.endsWith(".WIDG")||filename.endsWith(".SXMD"),filename);
		char[4] tag=filename[$-9..$-5][0..4];
		reverse(tag[]);
		switch(filename[$-4..$]){
			case "MRMM":
				auto mt=loadMRMM!B(filename, 1.0f);
				meshes=mt[0];
				textures=mt[1];
				hitboxes_=mt[2];
				break;
			case "3DSM":
				auto mt=load3DSM!B(filename, 1.0f);
				meshes=[mt[0]];
				textures=mt[1];
				break;
			case "WIDG":
				auto mt=loadWIDG!B(filename);
				meshes=[[mt[0]]];
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
					auto anim=Animation(0,int.max,0,int.max,int.max,(Hand[2]).init,[Pose(Vector3f(0,0,0),AnimEvent.none,facingQuaternion(0).repeat(saxsi.saxs.bones.length).array)]);
					static if(gpuSkinning)
						anim.compile(saxsi.saxs);
					animations=[anim];
				}
				saxsi.createMeshes(animations[0].frames[0]);
				break;
			default:
				assert(0);
		}
		initializeNTTData(tag,tag in tagsFromModel?tagsFromModel[tag]:tag);
	}

	void setMeshes(B.Mesh[] meshes,Pose pose=Pose.init){ // (uses GC)
		if(isSaxs){ // TODO: transfer to BoneMesh using the pose
			/*isSaxs=false;
			enforce(meshes.length<=meshes.length);
			this.meshes=meshes;
			this.textures=saxsi.saxs.bodyParts.map!((ref p)=>p.texture).array[0..meshes.length];*/
			import saxs2obj;
			auto transferred=transferModel!B(meshes,saxsi.saxs,pose);
			if(transferred.length>saxsi.meshes.length){ // TODO: handle
				stderr.writeln("warning: ",transferred.length," body parts given, taking first ",saxsi.meshes.length);
				transferred=transferred[0..saxsi.meshes.length];
			}
			enforce(transferred.length<=saxsi.meshes.length);
			while(transferred.length<saxsi.meshes.length){
				auto emptyMesh=B.makeBoneMesh(1,1);
				B.finalizeBoneMesh(emptyMesh);
				transferred~=emptyMesh;
			}
			saxsi.meshes=transferred;
		}else{
			this.meshes=[meshes];
		}
	}
	void setNormal(B.Texture[] normals){
		foreach(i,t;normals)
			materials[i].normal=t;
	}
	void setDiffuse(B.Texture[] textures){
		this.textures=textures;
		foreach(i,t;textures){
			materials[i].diffuse=t;
			transparentMaterials[i].diffuse=t;
		}
	}

	void loadAnimation(string animation){ // (just for testing) (uses GC)
		enforce(animations.length<=1);
		auto anim=loadSXSK(animation,saxsi.saxs.scaling);
		static if(gpuSkinning)
			anim.compile(saxsi.saxs);
		animations=[anim];
	}

	private bool needsAnimationFix(AnimationState state,bool fasterStandupTimes){
		if(!fasterStandupTimes) return false;
		switch(nttTag)with(WizardTag){
			default: return false;
			case yogo,seerix,acheron,ambassadorButa,charlotte,shakti,marduk:
				switch(state)with(AnimationState){
					default: return false;
					case hitFloor: return true;
				}
			/+case abraxus:
				switch(state)with(AnimationState){
					default: return false;
					case hitFloor,knocked2Floor: return true;
				}+/
		}
	}
	private AnimationState fixAnimation(AnimationState state){
		switch(nttTag)with(WizardTag){
			default: return state;
			case yogo,seerix,acheron,ambassadorButa,charlotte,shakti,marduk:
				switch(state)with(AnimationState){
					default: return state;
					case hitFloor: return knocked2Floor;
				}
			/+case abraxus:
				switch(state)with(AnimationState){
					default: return state;
					case hitFloor,knocked2Floor: return cast(AnimationState)(AnimationState.max+1);
				}+/
		}
	}
	final bool hasAnimationState(AnimationState state)in{
		assert(!needsAnimationFix(state,true));
	}do{
		return state<animations.length&&animations[state].frames.length;
	}
	final bool hasAnimationState(AnimationState state,bool fasterStandupTimes){
		if(!needsAnimationFix(state,fasterStandupTimes)) return state<animations.length&&animations[state].frames.length;
		auto fixed=fixAnimation(state);
		return fixed<animations.length&&animations[fixed].frames.length;
	}
	final int numFrames(AnimationState state)in{
		assert(!needsAnimationFix(state,true));
	}do{
		return isSaxs?cast(int)animations[state].frames.length:0;
	}
	final int numFrames(AnimationState state,bool fasterStandupTimes){
		if(!isSaxs) return 0;
		if(!needsAnimationFix(state,fasterStandupTimes)) return cast(int)animations[state].frames.length;
		return cast(int)animations[fixAnimation(state)].frames.length;
	}

	Matrix4x4f[] getFrame(AnimationState state,size_t frame,bool fasterStandupTimes)in{
		if(!needsAnimationFix(state,fasterStandupTimes)) assert(frame<numFrames(state,fasterStandupTimes),text(tag," ",state," ",frame," ",numFrames(state)));
		else assert(frame<numFrames(fixAnimation(state),fasterStandupTimes));
	}do{
		// enforce(saxsi.saxs.bodyParts.length==meshes.length); // TODO: why can this fail?
		if(!needsAnimationFix(state,fasterStandupTimes)) return animations[state].frames[frame].matrices;
		return animations[fixAnimation(state)].frames[frame].matrices;
	}
}

void printWizardStats(B)(SacObject!B wizard,bool fasterStandupTimes){
	import animations;
	writeln(wizard.name);
	writeln("casting:");
	foreach(stationary;[true,false]){
		writeln(stationary?"stationary:":"walking:");
		auto start=wizard.numFrames(stationary?AnimationState.spellcastStart:AnimationState.runSpellcastStart)*updateAnimFactor;
		auto mid=wizard.numFrames(stationary?AnimationState.spellcast:AnimationState.runSpellcast)*updateAnimFactor;
		//auto end=wizard.numFrames(stationary?AnimationState.spellcastEnd:AnimationState.runSpellcastEnd)*updateAnimFactor;
		auto castingTime=wizard.castingTime(stationary?AnimationState.spellcastEnd:AnimationState.runSpellcastEnd)*updateAnimFactor;
		writeln("start: ",start,"\t\tmid: ",mid,"\t\tend: ",castingTime);
	}
	auto d0=wizard.numFrames(AnimationState.death0)*updateAnimFactor;
	auto d1=wizard.numFrames(AnimationState.death1)*updateAnimFactor;
	auto d2=wizard.numFrames(AnimationState.death2)*updateAnimFactor;
	writeln("deaths: ",d0," ",d1," ",d2);
	auto cr=wizard.numFrames(AnimationState.corpseRise)*updateAnimFactor;
	writeln("corpse rise: ",cr);
	writeln("death with rise: ",d0+cr," ",d1+cr," ",d2+cr);
	auto rv=wizard.numFrames(AnimationState.float2Stance)*updateAnimFactor;
	writeln("revive: ",rv);
	writeln("death with rise and revive: ",d0+cr+rv," ",d1+cr+rv," ",d2+cr+rv);
	auto kd=(wizard.hasAnimationState(AnimationState.knocked2Floor,fasterStandupTimes)?wizard.numFrames(AnimationState.knocked2Floor,fasterStandupTimes):0)*updateAnimFactor;
	auto fd=(wizard.hasAnimationState(AnimationState.hitFloor,fasterStandupTimes)?wizard.numFrames(AnimationState.hitFloor,fasterStandupTimes):0)*updateAnimFactor;
	auto gu=(wizard.hasAnimationState(AnimationState.getUp,fasterStandupTimes)?wizard.numFrames(AnimationState.getUp):0)*updateAnimFactor;
	writeln("fall down and get up: ",fd,"+",gu,"=",fd+gu);
	writeln("knockdown and get up: ",kd,"+",gu,"=",kd+gu);
	auto ds=wizard.numFrames(AnimationState.damageBack)*updateAnimFactor;
	writeln("damage stun: ",ds);
	auto hb=wizard.hitbox(Quaternionf.identity(),AnimationState.stance1,0);
	writeln("hitbox: ",boxSize(hb)[].map!text.join("×"));
}

final class SacBuilding(B){
	char[4] tag;
	B.Texture icon;
	string name;
	immutable(Bldg)* bldg;
	@property int flags(){ return bldg.flags; }
	@property int maxHealth(){ return bldg.maxHealth; }
	@property immutable(BldgComponent)[] components(){ return bldg.components; }
	@property ref immutable(ubyte[8][8]) ground(){ return bldg.ground; }
	// TODO: some of the following functionality is duplicated in SacObject
	bool isManafount(){
		return bldg.header.numComponents==1&&manafountTags.canFind(bldg.components[0].tag);
	}
	bool isManalith(){
		return bldg.header.numComponents==1&&manalithTags.canFind(bldg.components[0].tag);
	}
	bool isShrine(){
		return bldg.header.numComponents==1&&shrineTags.canFind(bldg.components[0].tag);
	}
	bool isAltar(){
		return bldg.header.numComponents>=1&&altarBaseTags.canFind(bldg.components[0].tag);
	}
	bool isStratosAltar(){
		return bldg.header.numComponents>=1&&bldg.components[0].tag=="tprc";
	}
	bool isEtherealAltar(){
		return bldg.header.numComponents>=1&&bldg.components[0].tag=="b_ae";
	}
	bool isPeasantShelter(){
		return !!(bldg.header.flags&BldgFlags.shelter)||isAltar;
	}

	float xpOnDestruction(){ return 5000.0f; } // TODO: ok?

	static SacBuilding!B[char[4]] buildings;
	static SacBuilding!B get(char[4] tag){ // (uses GC)
		if(auto r=tag in buildings) return *r;
		return buildings[tag]=new SacBuilding!B(tag);
	}
	this(char[4] tag){
		this.tag=tag;
		this.bldg=tag in bldgs;
		enforce(!!bldg,text("bad tag: ",tag));
		if(isAltar){
			icon=B.makeTexture(loadTXTR(icons["1tla"])); // SacEngine extension: original has altar icons only for persephone altar
			name=texts.get("1tla","Altar"); // TODO: ultimate altars
		}else if(isManalith){
			icon=B.makeTexture(loadTXTR(icons["anam"])); // SacEngine extension: original does not have manalith icons
		}else if(isManafount){
			name=texts.get("tnof","Mana Fountain");
		}
	}
}

final class SacSky(B){
	enum scaling=4*10.0f*256.0f;
	enum dZ=-0.05, undrZ=-0.25, skyZ=0.25, relCloudLoc=0.7;
	enum numSegs=64, numTextureRepeats=8;
	enum energy=1.7f;

	Vector2f sunSkyRelLoc(Vector3f cameraPos){
		auto sunPos=Vector3f(0,0,skyZ*scaling);
		auto adjCamPos=cameraPos-Vector3f(1280.0f,1280.0f,dZ*scaling+1);
		float zDiff=sunPos.z-adjCamPos.z;
		float tZDiff=scaling*skyZ*(1-relCloudLoc);
		auto intersection=sunPos+(adjCamPos-sunPos)*tZDiff/zDiff;
		return intersection.xy/(scaling/2);
	}

	union{
		B.Mesh[5] meshes;
		struct{
			B.Mesh skyb;
			B.Mesh skyt;
			B.Mesh sun;
			B.Mesh sky;
			B.Mesh undr;
		}
	}

	this(){
		skyb=B.makeMesh(2*(numSegs+1),2*numSegs);
		foreach(i;0..numSegs+1){
			auto angle=2*pi!float*i/numSegs, ca=cos(angle), sa=sin(angle);
			skyb.vertices[2*i]=Vector3f(0.5*ca*0.8,0.5*sa*0.8,undrZ)*scaling;
			skyb.vertices[2*i+1]=Vector3f(0.5*ca,0.5*sa,0)*scaling;
			auto txc=cast(float)i*numTextureRepeats/numSegs;
			skyb.texcoords[2*i]=Vector2f(txc,0);
			skyb.texcoords[2*i+1]=Vector2f(txc,1);
		}
		foreach(i;0..numSegs){
			skyb.indices[2*i]=[2*i,2*i+1,2*(i+1)];
			skyb.indices[2*i+1]=[2*(i+1),2*i+1,2*(i+1)+1];
		}
		skyb.generateNormals();
		B.finalizeMesh(skyb);

		skyt=B.makeMesh(2*(numSegs+1),2*numSegs);
		foreach(i;0..numSegs+1){
			auto angle=2*pi!float*i/numSegs, ca=cos(angle), sa=sin(angle);
			skyt.vertices[2*i]=Vector3f(0.5*ca,0.5*sa,0)*scaling;
			skyt.vertices[2*i+1]=Vector3f(0.5*ca,0.5*sa,skyZ)*scaling;
			auto txc=cast(float)i*numTextureRepeats/numSegs;
			skyt.texcoords[2*i]=Vector2f(txc,1);
			skyt.texcoords[2*i+1]=Vector2f(txc,0);
		}
		foreach(i;0..numSegs){
			skyt.indices[2*i]=[2*i,2*i+1,2*(i+1)];
			skyt.indices[2*i+1]=[2*(i+1),2*i+1,2*(i+1)+1];
		}
		skyt.generateNormals();
		B.finalizeMesh(skyt);

		sun=B.makeMesh(4,2);
		copy(iota(4).map!(i=>Vector3f((-0.5+(i==1||i==2))*0.25,(-0.5+(i==2||i==3))*0.25,skyZ)*scaling),sun.vertices);
		copy(iota(4).map!(i=>Vector2f((i==1||i==2),(i==2||i==3))),sun.texcoords);
		sun.indices[0]=[0,2,1];
		sun.indices[1]=[0,3,2];
		sun.generateNormals();
		B.finalizeMesh(sun);

		sky=B.makeMesh(4,2);
		copy(iota(4).map!(i=>Vector3f(-0.5+(i==1||i==2),-0.5+(i==2||i==3),skyZ*relCloudLoc)*scaling),sky.vertices);
		copy(iota(4).map!(i=>Vector2f(4*(i==1||i==2),4*(i==2||i==3))),sky.texcoords);
		sky.indices[0]=[0,2,1];
		sky.indices[1]=[0,3,2];
		sky.generateNormals();
		B.finalizeMesh(sky);

		undr=B.makeMesh(4,2);
		copy(iota(4).map!(i=>Vector3f((-0.5+(i==1||i==2)),(-0.5+(i==2||i==3)),undrZ)*scaling),undr.vertices);
		copy(iota(4).map!(i=>Vector2f((i==1||i==2),(i==2||i==3))),undr.texcoords);
		undr.indices[0]=[0,1,2];
		undr.indices[1]=[0,2,3];
		undr.generateNormals();
		B.finalizeMesh(undr);
	}
}

enum SoulColor{
	blue,
	red,
	green,
}

B.Mesh[] makeSpriteMeshes(B,bool doubleSided=false,bool reverseOrder=false)(int nU,int nV,float width,float height,float texWidth=1.0f,float texHeight=1.0f){ // TODO: replace with shader
	auto meshes=new B.Mesh[](nU*nV);
	foreach(i,ref mesh;meshes){
		mesh=B.makeMesh(4,doubleSided?4:2);
		static if(reverseOrder) int u=cast(int)(meshes.length-1-i)%nU,v=cast(int)(meshes.length-1-i)/nU;
		else int u=cast(int)i%nU,v=cast(int)i/nU;
		foreach(k;0..4) mesh.vertices[k]=Vector3f(-0.5f*width+width*(k==1||k==2),-0.5f*height+height*(k==2||k==3),0.0f);
		foreach(k;0..4) mesh.texcoords[k]=Vector2f(texWidth/nU*(u+(k==1||k==2)),texHeight/nV*(v+(k==0||k==1)));
		static if(doubleSided) static immutable uint[3][] indices=[[0,1,2],[2,3,0],[0,2,1],[2,0,3]];
		else static immutable uint[3][] indices=[[0,1,2],[2,3,0]];
		mesh.indices[]=indices[];
		mesh.generateNormals();
		B.finalizeMesh(mesh);
	}
	return meshes;
}

B.SubQuad[] makeSpriteMeshes2d(B)(int nU,int nV,float width,float height,float texWidth=1.0f,float texHeight=1.0f){ // TODO: replace with shader
	auto meshes=new B.SubQuad[](nU*nV);
	foreach(i,ref mesh;meshes){
		int u=cast(int)i%nU,v=cast(int)i/nU;
		mesh=B.makeSubQuad(texWidth/nU*u,texHeight/nV*v,texWidth/nU*(u+1),texHeight/nV*(v+1));
	}
	return meshes;
}

Color4f[3] soulFrameColor=[
	SoulColor.blue: Color4f(0,182.0f/255.0f,1.0f),
	SoulColor.red: Color4f(1.0f,0.0f,0.0f),
	SoulColor.green: Color4f(0,1.0f,182.0f/255.0f),
];

Color4f[3] soulMinimapColor=[
	SoulColor.blue: Color4f(0,165.0f/255.0f,1.0f),
	SoulColor.red: Color4f(1.0f,0.0f,0.0f),
	SoulColor.green: Color4f(0.0f,1.0f,165.0f/255.0f),
];

auto healthColor=Color4f(192.0f/255.0f,0.0f,0.0f);
auto manaColor=Color4f(0.0f,96.0f/255.0f,192.0f);

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
		return meshes[(color==SoulColor.blue?0:8)+frame/2];
	}
}

final class SacGreenSoul(B){
	B.Mesh[] meshes;
	B.Texture texture;
	B.Material material;

	enum soulWidth=1.0f;
	enum soulHeight=1.6f*soulWidth;
	enum soulRadius=0.3f;

	this(){
		// TODO: extract soul meshes at all different frames from original game
		meshes=makeSpriteMeshes!B(4,4,soulWidth,soulHeight);
		auto img=loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/spir.TXTR");
		auto data=img.data;
		auto channels=img.channels;
		enforce(channels==4);
		foreach(i;0..data.length/channels)
			swap(data[channels*i],data[channels*i+1]);
		texture=B.makeTexture(img);
		material=B.createMaterial(this);
	}
	enum numFrames=16;
	B.Mesh getMesh(SoulColor color,int frame){
		return meshes[(color==SoulColor.green?8:0)+frame/2];
	}
}

enum ParticleType{
	manafount,
	manalith,
	shrine,
	manahoar,
	firy,
	fire,
	fireball,
	firewall,
	cold,
	explosion,
	explosion2,
	speedUp,
	heal,
	scarabHit,
	relativeHeal,
	ghostTransition,
	ghost,
	lightningCasting,
	chainLightningCasting,
	needle,
	freeze,
	redVortexDroplet,
	blueVortexDroplet,
	spark,
	etherealFormSpark,
	styxSpark,
	rend,
	shard,
	snowballShard,
	flurryShard,
	castPersephone,
	castPersephone2,
	castPyro,
	castJames,
	castStratos,
	castCharnel,
	castCharnel2,
	breathOfLife,
	wrathCasting,
	wrathExplosion1,
	wrathExplosion2,
	wrathParticle,
	rainbowParticle,
	rainOfFrogsCasting,
	frogExplosion,
	gnomeHit,
	warmongerHit,
	ashParticle,
	dirt,
	dust,
	splat,
	rock,
	bombardmentCasting,
	webDebris,
	oil,
	steam,
	smoke,
	poison,
	relativePoison,
	swarmHit,
	slime,
	hoverBlood,
	blood,
	locustBlood,
	locustDebris,
}

final class SacParticle(B){
	int stateIndex=-1;
	B.Mesh[] meshes;
	B.Texture texture;
	B.Material material;
	ParticleType type;
	int side=-1;
	Color4f color;
	float energy=20.0f;
	float width,height;
	@property bool gravity(){
		final switch(type) with(ParticleType){
			case manafount,spark,styxSpark,rend:
				return true;
			case manalith,shrine,manahoar,firy,fire,fireball,firewall,cold,explosion,explosion2,speedUp,ghost,heal:
				return false;
			case scarabHit:
				return true;
			case relativeHeal,lightningCasting,chainLightningCasting:
				return false;
			case ghostTransition:
				return true;
			case needle,etherealFormSpark,shard,snowballShard:
				return true;
			case flurryShard:
				return false;
			case freeze:
				return false;
			case redVortexDroplet,blueVortexDroplet:
				return true;
			case castPersephone,castPersephone2,castPyro,castJames,castStratos,castCharnel,castCharnel2:
				return false;
			case breathOfLife,wrathCasting,wrathExplosion1,wrathExplosion2,rainOfFrogsCasting,steam:
				return false;
			case wrathParticle,rainbowParticle,frogExplosion,gnomeHit,warmongerHit,ashParticle:
				return true;
			case smoke,dirt,dust,splat:
				return false;
			case rock:
				return true;
			case bombardmentCasting:
				return false;
			case webDebris,oil:
				return true;
			case poison,relativePoison:
				return false;
			case swarmHit,slime:
				return true;
			case hoverBlood:
				return false;
			case blood:
				return true;
			case locustBlood,locustDebris:
				return false;
		}
	}
	@property bool relative(){
		final switch(type) with(ParticleType){
			case manafount,manalith,shrine,manahoar,firy,fire,fireball,firewall,cold,explosion,explosion2,speedUp,ghost,heal,scarabHit,ghostTransition,spark,styxSpark,rend:
				return false;
			case relativeHeal,lightningCasting:
				return true;
			case chainLightningCasting:
				return false;
			case needle,etherealFormSpark,shard,snowballShard,flurryShard:
				return false;
			case freeze:
				return true;
			case redVortexDroplet,blueVortexDroplet:
				return false;
			case castPersephone,castPersephone2,castPyro,castJames,castStratos,castCharnel,castCharnel2:
				return false;
			case breathOfLife,wrathCasting,wrathExplosion1,wrathExplosion2,wrathParticle,rainbowParticle,rainOfFrogsCasting,frogExplosion,gnomeHit,warmongerHit,ashParticle,steam,smoke,dirt,dust,splat,rock,bombardmentCasting,webDebris,oil,poison,swarmHit,slime:
				return false;
			case relativePoison:
				return true;
			case hoverBlood,blood,locustBlood,locustDebris:
				return false;
		}
	}
	@property bool bumpOffGround(){
		switch(type) with(ParticleType){
			case scarabHit,ghostTransition,wrathParticle,rainbowParticle,gnomeHit,warmongerHit,ashParticle,rock,webDebris,oil,swarmHit,slime,needle,redVortexDroplet,blueVortexDroplet,spark,styxSpark,rend: return true;
			default: return false;
		}
	}
	this(ParticleType type,Color4f color=Color4f(1.0f,1.0f,1.0f,1.0f),float energy=20.0f,int side=-1){
		this.type=type;
		this.side=side;
		this.color=color;
		this.energy=energy;
		// TODO: extract soul meshes at all different frames from original game
		final switch(type) with(ParticleType){
			case manafount:
				width=height=6.0f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/elec.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case manalith:
				width=height=12.0f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/fb_g.TXTR"));
				meshes=makeSpriteMeshes!B(3,3,width,height);
				break;
			case shrine:
				width=height=4.0f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/fb_g.TXTR"));
				meshes=makeSpriteMeshes!B(3,3,width,height);
				break;
			case manahoar:
				width=height=1.2f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/fb_g.TXTR"));
				meshes=makeSpriteMeshes!B(3,3,width,height);
				break;
			case firy:
				width=height=0.5f;
				this.energy=8.0f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/firy.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case fire:
				width=height=1.0f;
				this.energy=8.0f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/firy.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case fireball:
				width=height=0.5f;
				this.energy=8.0f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/fbal.TXTR"));
				meshes=makeSpriteMeshes!B(3,3,width,height);
				break;
			case firewall:
				width=height=1.0f;
				this.energy=8.0f;
				texture=B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pyro.FLDR/txtr.FLDR/fwpt.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case cold:
				width=height=1.0f;
				this.energy=8.0f;
				texture=B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Stra.FLDR/txtr.FLDR/cold.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case explosion:
				width=height=3.0f;
				this.energy=8.0f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/xplo.TXTR"));
				meshes=makeSpriteMeshes!B(5,5,width,height,239.5f/256.0f,239.5f/256.0f);
				break;
			case explosion2:
				width=height=3.0f;
				this.energy=8.0f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/exp2.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case speedUp:
				width=height=1.0f;
				this.energy=4.0f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/spd6.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case heal,scarabHit,relativeHeal,ghostTransition,ghost: // TODO: load texture only once
				width=height=1.0f;
				this.energy=4.0f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/glo2.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case lightningCasting:
				width=height=1.0f;
				this.energy=3.0f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/cst0.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case chainLightningCasting:
				width=height=1.0f;
				this.energy=3.0f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/cst0.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case needle,etherealFormSpark,freeze:
				width=height=1.0f;
				this.energy=3.0f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/cst0.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case shard:
				width=height=1.0f;
				this.energy=3.0f;
				texture=B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Stra.FLDR/txtr.FLDR/shrd.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case snowballShard:
				width=height=1.0f;
				this.energy=3.0f;
				texture=B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Stra.FLDR/txtr.FLDR/shrd.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case flurryShard:
				width=height=1.0f;
				this.energy=3.0f;
				texture=B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Stra.FLDR/txtr.FLDR/shrd.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case redVortexDroplet:
				width=height=1.0f;
				this.energy=3.0f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/vtx2.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case blueVortexDroplet:
				width=height=1.0f;
				this.energy=3.0f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/cst0.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case spark:
				width=height=2.0f;
				this.energy=15.0f;
				texture=B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Stra.FLDR/txtr.FLDR/sprk.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case styxSpark:
				width=height=1.0f;
				this.energy=15.0f;
				texture=B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Char.FLDR/tex_ZERO_.FLDR/styx.TXTR"));
				meshes=makeSpriteMeshes!B(1,1,width,height);
				break;
			case rend:
				width=height=2.0f;
				this.energy=15.0f;
				texture=B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Char.FLDR/tex_ZERO_.FLDR/rend.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case castPersephone:
				width=height=1.0f;
				this.energy=5.0f;
				texture=B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pers.FLDR/tex_ZERO_.FLDR/cstl.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case castPersephone2:
				width=height=1.0f;
				this.energy=5.0f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/cst1.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case castPyro:
				width=height=1.0f;
				this.energy=15.0f;
				texture=B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pyro.FLDR/txtr.FLDR/cstp.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case castJames:
				width=height=1.0f;
				this.energy=2.0f;
				texture=B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Jame.FLDR/tex_ZERO_.FLDR/cstj.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case castStratos:
				width=height=1.0f;
				this.energy=2.0f;
				texture=B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Stra.FLDR/txtr.FLDR/csts.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case castCharnel:
				width=height=0.5f;
				this.energy=-0.5f;
				//texture=B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Char.FLDR/tex_ZERO_.FLDR/cstc.TXTR"));
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/firy.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case castCharnel2:
				width=height=1.0f;
				this.energy=5.0f;
				texture=B.makeTexture(loadTXTR("extracted/Daniel/DanC.WAD!/char.FLDR/cfx1.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case breathOfLife:
				width=height=3.0f;
				this.energy=7.5f;
				texture=B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pers.FLDR/tex_ZERO_.FLDR/brth.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case wrathCasting,wrathExplosion1:
				width=height=1.0f;
				this.energy=7.5f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/flao.TXTR"));
				meshes=makeSpriteMeshes!B(3,3,width,height,252.5f/256.0f,252.5f/256.0f);
				break;
			case wrathExplosion2:
				width=height=1.0f;
				this.energy=20.0f;
				texture=B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pers.FLDR/tex_ZERO_.FLDR/wrth.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case wrathParticle:
				width=height=0.3f;
				this.energy=5.0f;
				texture=B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pers.FLDR/tex_ZERO_.FLDR/prth.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case rainbowParticle:
				width=height=1.0f;
				this.energy=5.0f;
				texture=B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pers.FLDR/tex_ZERO_.FLDR/prbw.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case rainOfFrogsCasting:
				width=height=1.0f;
				this.energy=7.5f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/frgl.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case frogExplosion:
				width=height=1.0f;
				this.energy=5.0f;
				texture=B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pers.FLDR/tex_ZERO_.FLDR/brst.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case gnomeHit:
				width=height=0.5f;
				this.energy=5.0f;
				texture=B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pers.FLDR/tex_ZERO_.FLDR/gsqb.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case warmongerHit:
				width=height=0.5f;
				this.energy=5.0f;
				texture=B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pyro.FLDR/txtr.FLDR/wsqb.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case steam:
				width=height=2.0f;
				this.energy=0.25f;
				texture=B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pers.FLDR/tex_ZERO_.FLDR/stem.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case ashParticle:
				width=height=0.3f;
				this.energy=10.0f;
				texture=B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pyro.FLDR/txtr.FLDR/frck.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case smoke:
				width=height=1.5f;
				this.energy=1.0f;
				texture=B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pyro.FLDR/txtr.FLDR/smok.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case dirt:
				width=height=1.0f;
				this.energy=1.0f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/dirt.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case dust:
				width=height=1.0f;
				this.energy=1.0f;
				texture=B.makeTexture(loadTXTR("extracted/shawn/shwn.WAD!/jams.FLDR/text.FLDR/dust.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case splat:
				width=height=1.0f;
				this.energy=1.0f;
				texture=B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pers.FLDR/tex_ZERO_.FLDR/splt.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case rock:
				width=height=1.0f;
				this.energy=1.0f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/rock.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case bombardmentCasting:
				width=height=1.5f;
				this.energy=1.0f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/rock.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case webDebris:
				width=height=1.0f;
				this.energy=1.0f;
				texture=B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pers.FLDR/tex_ZERO_.FLDR/gend.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case oil:
				width=height=1.0f;
				this.energy=1.0f;
				texture=B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pyro.FLDR/txtr.FLDR/oile.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case poison,relativePoison:
				width=height=1.0f;
				this.energy=1.0f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/pois.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case swarmHit:
				width=height=5.0f;
				this.energy=1.0f;
				texture=B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Char.FLDR/tex_ZERO_.FLDR/puss.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case slime:
				width=height=1.0f;
				this.energy=1.0f;
				texture=B.makeTexture(loadTXTR("extracted/Daniel/DanC.WAD!/char.FLDR/lth2.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case hoverBlood,blood:
				width=height=0.75f;
				this.energy=8.0f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/blud.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case locustBlood:
				width=height=0.4f;
				this.energy=8.0f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/blud.TXTR"));
				meshes=makeSpriteMeshes!B(4,4,width,height);
				break;
			case locustDebris:
				width=height=0.4f;
				this.energy=20.0f;
				texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/firy.TXTR"));
				meshes=makeSpriteMeshes!(B,false,true)(4,4,width,height);
				break;
		}
		material=B.createMaterial(this);
	}
	static SacParticle!B[ParticleType.max+1] particles;
	static void resetStateIndex(){
		foreach(tag,obj;particles) if(obj) obj.stateIndex=-1;
	}
	static SacParticle!B get(ParticleType type){
		if(!particles[type]) particles[type]=new SacParticle!B(type);
		return particles[type];
	}
	@property int delay(){
		switch(type) with(ParticleType){
			case firewall: return 2;
			case ghostTransition,ghost: return 2;
			case speedUp: return 2;
			case chainLightningCasting: return 2;
			case redVortexDroplet: return 2;
			case spark: return 2;
			case etherealFormSpark: return 2;
			case styxSpark: return 2;
			case rend: return 2;
			case snowballShard: return 2;
			case flurryShard: return 2;
			case breathOfLife: return 2;
			case rainbowParticle: return 2;
			case gnomeHit: return 2;
			case warmongerHit: return 1;
			case ashParticle: return 3;
			case smoke: return 4;
			case fire: return 2;
			case cold: return 2;
			case dirt,splat: return 2;
			case poison, relativePoison: return 2;
			case scarabHit: return 2;
			case swarmHit: return 2;
			case slime: return 2;
			case hoverBlood: return 2;
			case blood: return 4;
			case locustBlood, locustDebris: return 1;
			default: return 1;
		}
	}
	@property int numFrames(){
		return cast(int)meshes.length*updateAnimFactor*delay;
	}
	B.Mesh getMesh(int frame){
		return meshes[frame/(updateAnimFactor*delay)];
	}
	float getAlpha(int lifetime){
		final switch(type) with(ParticleType){
			case manafount:
				return min(1.0f,(lifetime/(3.0f*numFrames))^^2);
			case manalith,shrine,manahoar:
				return min(0.07f,(lifetime/(4.0f*numFrames))^^2);
			case firy,fireball,firewall,cold,explosion,explosion2,wrathExplosion1,wrathExplosion2:
				return 1.0f;
			case fire:
				return min(1.0f,(float(lifetime)/numFrames)^^2);
			case speedUp,ghost,wrathParticle,rainbowParticle,frogExplosion,gnomeHit,warmongerHit:
				return min(1.0f,(lifetime/(0.5f*numFrames))^^2);
			case ashParticle:
				return 1.0f;
			case heal,relativeHeal,ghostTransition:
				return min(1.0f,(lifetime/(0.75f*numFrames))^^2);
			case lightningCasting:
				return 1.0;
			case chainLightningCasting,needle,freeze,etherealFormSpark,spark,styxSpark,rend:
				return min(1.0f,(lifetime/(0.5f*numFrames))^^2);
			case shard,snowballShard:
				return 1.0f;
			case flurryShard:
				return 0.5f;
			case redVortexDroplet,blueVortexDroplet:
				return min(1.0f,(lifetime/(0.75f*numFrames))^^2);
			case castPersephone,castPersephone2,castPyro,castJames,castStratos,castCharnel,castCharnel2:
				return 1.0f;
			case breathOfLife:
				return min(1.0f,lifetime/(1.5f*numFrames));
			case wrathCasting:
				return min(1.0f,lifetime/(1.5f*numFrames));
			case rainOfFrogsCasting:
				return min(1.0f,lifetime/(1.5f*numFrames));
			case steam:
				return 1.0f;
			case smoke:
				enum delay=64;
				return 0.75f*(lifetime>=numFrames-(delay-1)?(numFrames-lifetime)/float(delay):(lifetime/float(numFrames-delay)))^^2;
			case rock,bombardmentCasting:
				return min(1.0f,(lifetime/(1.5f*numFrames)));
			case webDebris:
				return min(1.0f,(lifetime/(1.5f*numFrames)));
			case oil:
				return 1.0f;
			case dirt,splat:
				return min(1.0f,(lifetime/(0.25f*numFrames)));
			case dust:
				return 1.0f;
			case poison:
				return min(1.0f,(lifetime/(0.5f*numFrames)));
			case relativePoison:
				return 0.5f*min(1.0f,(lifetime/(0.5f*numFrames)));
			case swarmHit,scarabHit,slime:
				return min(1.0f,(lifetime/(0.75f*numFrames)));
			case hoverBlood,blood:
				return 1.0f;
			case locustBlood,locustDebris:
				return min(1.0f,(lifetime/(0.5f*numFrames)));
		}
	}
	float getScale(int lifetime){
		final switch(type) with(ParticleType){
			case manafount:
				return 1.0f;
			case manalith,manahoar:
				return min(1.0f,lifetime/(4.0f*numFrames));
			case shrine:
				return min(1.0f,lifetime/(3.0f*numFrames));
			case firy,fire,fireball,firewall,cold,explosion,explosion2,wrathExplosion1,wrathExplosion2:
				return 1.0f;
			case speedUp:
				return 1.0f;
			case heal,relativeHeal,ghostTransition,ghost:
				return 1.0f;
			case lightningCasting:
				return 1.0f;
			case chainLightningCasting,needle,freeze,etherealFormSpark,spark,styxSpark,rend:
				return min(1.0f,lifetime/(0.5f*numFrames));
			case shard,snowballShard,flurryShard:
				return 1.0f;
			case redVortexDroplet,blueVortexDroplet:
				return min(1.0f,(lifetime/(0.75f*numFrames)));
			case castPersephone,castPersephone2,castPyro,castJames,castStratos,castCharnel,castCharnel2:
				return 1.0f;
			case breathOfLife:
				return min(1.0f,0.4f+0.6f*lifetime/(1.5f*numFrames));
			case wrathCasting:
				return min(1.0f,0.4f+0.6f*lifetime/(1.5f*numFrames));
			case wrathParticle,rainbowParticle,frogExplosion,gnomeHit,warmongerHit:
				return min(1.0f,lifetime/(0.5f*numFrames));
			case rainOfFrogsCasting:
				return min(1.0f,0.4f+0.6f*lifetime/(1.5f*numFrames));
			case steam:
				return 1.0f;
			case ashParticle:
				return 1.0f;
			case smoke:
				return 1.0f/(lifetime/float(numFrames)+0.2f);
			case rock,bombardmentCasting:
				return min(1.0f,lifetime/(3.0f*numFrames));
			case webDebris:
				return min(1.0f,lifetime/(3.0f*numFrames));
			case oil:
				return min(1.0f,lifetime/(3.0f*numFrames));
			case dirt,dust,splat:
				return 1.0f;
			case poison,relativePoison:
				return 1.0f;
			case swarmHit,scarabHit,slime:
				return min(1.0f,(lifetime/(0.75f*numFrames)));
			case hoverBlood,blood,locustBlood,locustDebris:
				return 1.0f;
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
enum MouseIcon{
	attack,
	guard,
	move,
	spell,
	ability,
}

final class SacCursor(B){
	B.Texture[Cursor.max+1] textures;
	B.Material[] materials;
	B.Texture[MouseIcon.move+1] iconTextures;
	B.Material[] iconMaterials;
	B.Texture invalidTargetIconTexture;
	B.Material invalidTargetIconMaterial;
	B.Texture sparkleTexture;
	B.Material sparkleMaterial;
	B.Mesh[] sparkleMeshes;
	enum numSparkleFrames=updateAnimFactor*2*4*4;
	B.Mesh getSparkleMesh(int frame){
		return sparkleMeshes[frame/(2*updateAnimFactor)];
	}
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

		iconTextures[MouseIcon.attack]=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/icon.FLDR/Matt.ICON"));
		iconTextures[MouseIcon.guard]=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/icon.FLDR/Mgua.ICON"));
		iconTextures[MouseIcon.move]=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/icon.FLDR/Mgot.ICON"));
		assert(iconTextures[].all!(t=>t!is null));

		invalidTargetIconTexture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/icon.FLDR/ncst.ICON"));
		sparkleTexture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/curs.FLDR/Ctrl.TXTR"));

		auto materialsIconMaterials=B.createMaterials(this);
		materials=materialsIconMaterials[0], iconMaterials=materialsIconMaterials[1];
		invalidTargetIconMaterial=materialsIconMaterials[2];
		sparkleMaterial=materialsIconMaterials[3];
		sparkleMeshes=makeSpriteMeshes!B(4,4,1.0f,1.0f);
	}
}

class SacXmenu(B){
	import xmnu;
	static struct Entry{
		Xmnu xmnu;
		string name;
		B.Texture icon;
		int[4] next=-1;
	}
	Array!Entry entries;
	private int load(char[4] tag){
		foreach(i,ref entry;entries.data)
			if(entry.xmnu.tag==tag)
				return to!int(i);
		char[4] rev=tag;
		reverse(rev[]);
		auto xmnu=loadXmnu(text("extracted/xmenu/XMNU.WAD!/",rev[],".XMNU"));
		auto name=texts.get(xmnu.name,null);
		auto icon=B.makeTexture(loadTXTR(icons[xmnu.icon]));
		entries~=Entry(xmnu,name,icon);
		return to!int(entries.length)-1;
	}
	ref Entry get(char[4] tag){ return entries[load(tag)]; }
	static immutable centerTags=[imported!"std.traits".EnumMembers!XmnuCenterTag];
	B.Texture sparkleTexture;
	B.SubQuad[] sparkleMeshes; // TODO: do in shader instead
	this(){
		auto xmnl=loadXmnl("extracted/xmenu/XMNU.WAD!/lnk1.XMNL");
		int center=load(XmnuTag.center);
		foreach(ref entry;xmnl.entries){
			auto parent=load(entry.entries[0]);
			auto child=load(entry.entries[1]);
			enforce(entries[parent].next[entry.dir]==-1);
			enforce(entries[child].next[entry.dir^1]==-1);
			entries[parent].next[entry.dir]=child;
			entries[child].next[entry.dir^1]=parent;
		}
		foreach(i,e;centerTags){
			int entry=load(e);
			entries[entry].next=entries[center].next;
		}
		sparkleTexture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/iglo.TXTR"));
		sparkleMeshes=makeSpriteMeshes2d!B(3,3,1.0f,1.0f,120.0f/128.0f,120.0f/128.0f);
	}
}


final class SacHud(B){
	union{
		B.Texture[12] textures;
		struct{
			B.Texture frames;
			B.Texture pages;
			B.Texture arrows;
			B.Texture tabs;
			B.Texture spirit;
			B.Texture spellReady;
			B.Texture[3] mana;
			B.Texture[3] health;
		}
	}
	enum spellReadyIndex=5;
	B.Texture statusArrows;
	B.Mesh[] statusArrowMeshes; // TODO: use a single triangle instead of a quad with alpha channel
	B.Texture minimapIcons;
	B.Material[] materials;
	@property B.Material frameMaterial(){ return materials[0]; }
	@property B.Material tabsMaterial(){ return materials[3]; }
	@property B.Material spellReadyMaterial(){ return materials[5]; }
	@property B.Material manaTopMaterial(){ return materials[6]; }
	@property B.Material manaMaterial(){ return materials[7]; }
	@property B.Material manaBottomMaterial(){ return materials[8]; }
	@property B.Material healthTopMaterial(){ return materials[9]; }
	@property B.Material healthMaterial(){ return materials[10]; }
	@property B.Material healthBottomMaterial(){ return materials[11]; }
	B.Mesh[] spellReadyMeshes;
	B.Mesh getSpellReadyMesh(int i){
		return spellReadyMeshes[i/updateAnimFactor];
	}
	this(){
		frames=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/huds.FLDR/fram.TXTR"));
		pages=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/huds.FLDR/page.TXTR"));
		arrows=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/huds.FLDR/sarr.TXTR"));
		tabs=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/huds.FLDR/tabs.TXTR"));
		spirit=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/spi2.TXTR"));
		spellReady=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/icon.FLDR/Ifls.TXTR"));
		spellReadyMeshes=makeSpriteMeshes!B(4,4,1.0f,1.0f);
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
		statusArrows=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/huds.FLDR/sarr.TXTR"));
		statusArrowMeshes=makeSpriteMeshes!B(2,2,1.25f,1.0f);
		minimapIcons=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/icon.FLDR/mmic.TXTR"));
		materials=B.createMaterials(this);
	}
}

struct SacExplosion(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pyro.FLDR/txtr.FLDR/exeg.TXTR"));
	}
	B.Material material;
	enum numFrames=16;
	B.Mesh[numFrames] frames;
	auto getFrame(int i){ return frames[i/updateAnimFactor]; }
	static B.Mesh[numFrames] createMeshes(){
		enum nU=4,nV=4;
		return makeSphereMeshes!B(24,25,nU,nV,1.0f)[0..16];
	}
}

struct SacBlueRing(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/brng.TXTR"));
	}
	B.Material material;
	B.Mesh[] frames;
	enum ringAnimationDelay=4;
	enum numFrames=16*ringAnimationDelay*updateAnimFactor;
	auto getFrame(int i){ return frames[i/(ringAnimationDelay*updateAnimFactor)]; }
	static B.Mesh[] createMeshes(){
		return makeSpriteMeshes!B(4,4,28,28);
	}
}

struct SacLevelUpRing(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Misc.FLDR/txtr.FLDR/lvlp.TXTR"));
	}
	B.Material material;
	B.Mesh[] frames;
	enum ringAnimationDelay=4;
	enum numFrames=16*ringAnimationDelay*updateAnimFactor;
	auto getFrame(int i){ return frames[i/(ringAnimationDelay*updateAnimFactor)]; }
	static B.Mesh[] createMeshes(){
		return makeSpriteMeshes!B(4,4,28,28);
	}
}
struct SacLevelDownRing(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Misc.FLDR/txtr.FLDR/lvld.TXTR"));
	}
	B.Material material;
	B.Mesh[] frames;
	enum ringAnimationDelay=4;
	enum numFrames=16*ringAnimationDelay*updateAnimFactor;
	auto getFrame(int i){ return frames[i/(ringAnimationDelay*updateAnimFactor)]; }
	static B.Mesh[] createMeshes(){
		return makeSpriteMeshes!B(4,4,28,28);
	}
}

B.BoneMesh makeLineMesh(B)(int numSegments,float length,float size,bool pointy,bool flip=true,bool repeat=true,int nU=1,int nV=1,int u=0,int v=0){
	auto mesh=B.makeBoneMesh(3*4*numSegments,3*2*numSegments);
	enum sqrt34=sqrt(0.75f);
	immutable Vector3f[3] offsets=[size*Vector3f(0.0f,-1.0f,0.0f),size*Vector3f(sqrt34,0.5f,0.0f),size*Vector3f(-sqrt34,0.5f,0.0f)];
	int numFaces=0;
	void addFace(uint[3] face...){
		mesh.indices[numFaces++]=face;
	}
	foreach(i;0..numSegments){
		Vector3f getCenter(int i){
			return Vector3f(0.0f,0.0f,length*float(i)/numSegments);
		}
		foreach(j;0..3){
			foreach(k;0..4){
				int vertex=3*4*i+4*j+k;
				auto center=((k==1||k==2)?i+1:i);
				auto position=getCenter(center)+((k==2||k==3)&&(!pointy||center!=0&&center!=numSegments)?offsets[j]:Vector3f(0.0f,0.0f,0.0f));
				foreach(l;0..3){
					mesh.vertices[l][vertex]=position;
					mesh.boneIndices[vertex][l]=center;
				}
				mesh.weights[vertex]=Vector3f(1.0f,0.0f,0.0f);
				if(repeat){
					mesh.texcoords[vertex]=Vector2f(1.0f/nU*(u+((flip?i&1:0)^(k==1||k==2)?1.0f-0.5f/(256/nU):0.5f/(256/nU))),1.0f/nV*(v+((k==0||k==1)?1.0f-0.5f/(256/nV):0.5f/(256/nV))));
				}else{
					auto progress=float(i+((k==1)||(k==2)))/numSegments;
					mesh.texcoords[vertex]=Vector2f(1.0f/nU*(u+(progress*(1.0f-0.5f/(256/nU))+(1.0f-progress)*(0.5f/(256/nU)))),1.0f/nV*(v+((k==0||k==1)?1.0f-0.5f/(256/nV):0.5f/(256/nV))));
				}
			}
			int b=3*4*i+4*j;
			addFace([b+0,b+1,b+2]);
			addFace([b+2,b+3,b+0]);
		}
	}
	assert(numFaces==2*3*numSegments);
	mesh.normals[]=Vector3f(0.0f, 0.0f, 0.0f);
	B.finalizeBoneMesh(mesh);
	return mesh;
}

B.BoneMesh[] makeLineMeshes(B)(int numSegments,int nU,int nV,float length,float size,bool pointy,bool flip=true,bool repeat=true){
	auto meshes=new B.BoneMesh[](nU*nV);
	foreach(t,ref mesh;meshes){
		int u=cast(int)t%nU,v=cast(int)t/nU;
		mesh=makeLineMesh!B(numSegments,length,size,pointy,flip,repeat,nU,nV,u,v);
	}
	return meshes;
}

struct SacLightning(B){
	B.Texture texture;
	B.Material material;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/ltn2.TXTR"));
	}
	B.BoneMesh[] frames;
	enum numFrames=16*updateAnimFactor;
	auto getFrame(int i){ return frames[i/updateAnimFactor]; }
	static B.BoneMesh[] createMeshes(){
		enum numSegments=10;
		enum nU=4,nV=4;
		return makeLineMeshes!B(numSegments,nU,nV,0.0f,0.3f,true);
	}
}

struct SacWrath(B){
	B.Texture texture;
	B.Material material;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/forb.TXTR"));
	}
	B.Mesh[] frames;
	enum numFrames=16*2*updateAnimFactor;
	enum maxScale=30.0f;
	enum maxOffset=4.0f;
	auto getFrame(int i){ return frames[i/(2*updateAnimFactor)]; }
	static B.Mesh[] createMeshes(){
		enum nU=4,nV=4;
		auto meshes=new B.Mesh[](nU*nV);
		foreach(t,ref mesh;meshes){
			enum resolution=32;
			enum numSegments=16*resolution;
			enum textureMultiplier=1.0f/resolution;
			auto numVertices=3*numSegments,numFaces=2*2*numSegments;
			mesh=B.makeMesh(numVertices,numFaces);
			int u=cast(int)t%nU,v=cast(int)t/nU;
			int curNumFaces=0;
			void addFace(uint[3] face...){
				mesh.indices[curNumFaces++]=face;
			}
			enum height=0.4f, depth=0.1f;
			foreach(i;0..numSegments){
				auto top=3*i,outer=3*i+1,bottom=3*i+2;
				auto alpha=2*pi!float*i/numSegments;
				auto direction=Vector2f(cos(alpha),sin(alpha));
				mesh.vertices[top]=Vector3f((1.0f-depth)*direction.x,(1.0f-depth)*direction.y,0.5f*height);
				mesh.vertices[bottom]=mesh.vertices[top];
				mesh.vertices[bottom].z*=-1.0f;
				mesh.vertices[outer]=Vector3f(direction.x,direction.y,0.0f);
				float zigzag(float x,float a,float b){
					auto α=fmod(x,1);
					if(cast(int)x&1) α=1-α;
					return (1-α)*a+α*b;
				}
				enum offset=1.0f/64.0f;
				auto x=zigzag(i*textureMultiplier,1.0f/nU*(u+offset),1.0f/nU*(u+1.0f-offset));
				mesh.texcoords[top]=Vector2f(x,1.0f/nV*(v+offset));
				mesh.texcoords[bottom]=mesh.texcoords[top];
				mesh.texcoords[outer]=Vector2f(x,1.0f/nV*(v+1.0f-offset));
				int next(int id){ return (id+3)%numVertices; }
				addFace(top,outer,next(top));
				addFace(next(top),outer,next(outer));
				addFace(bottom,next(bottom),outer);
				addFace(next(bottom),next(outer),outer);
			}
			assert(numFaces==2*2*numSegments);
			mesh.normals[]=Vector3f(0.0f, 0.0f, 0.0f);
			B.finalizeMesh(mesh);
		}
		return meshes;
	}
}

struct SacBug(B){
	B.Texture texture;
	B.Material material;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Char.FLDR/tex_ZERO_.FLDR/bugs.TXTR"));
	}
	B.Mesh mesh;
	static B.Mesh createMesh(){ // TODO: use particle shader instead
		enum width=0.5f,height=0.5f;
		enum texWidth=1.0f,texHeight=1.0f;
		enum nU=1,nV=1;
		enum u=0,v=0;
		auto mesh=B.makeMesh(4,2);
		foreach(k;0..4) mesh.vertices[k]=Vector3f(-0.5f*width+width*(k==1||k==2),-0.5f*height+height*(k==2||k==3),0.0f);
		foreach(k;0..4) mesh.texcoords[k]=Vector2f(texWidth/nU*(u+(k==1||k==2)),texHeight/nV*(v+(k==0||k==1)));
		static immutable uint[3][] indices=[[0,1,2],[2,3,0]];
		mesh.indices[]=indices[];
		mesh.generateNormals();
		B.finalizeMesh(mesh);
		return mesh;
	}
}

struct SacProtectiveBug(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Char.FLDR/tex_ZERO_.FLDR/pswm.TXTR"));
	}
	B.Material material;
	B.Mesh[] frames;
	enum animationDelay=2;
	enum numFrames=16*animationDelay*updateAnimFactor;
	auto getFrame(int i){ return frames[i/(animationDelay*updateAnimFactor)]; }
	static B.Mesh[] createMeshes(){
		return makeSpriteMeshes!(B,true)(4,4,0.5f,0.5f);
	}
}

B.Mesh makeSphereMesh(B)(int numU,int numV,float radius,float u1=0.0f,float v1=0.0f,float u2=1.0f,float v2=1.0f){
	auto mesh=B.makeMesh(2+numU*numV,2*numU*numV);
	int numFaces=0;
	void addFace(uint[3] face...){
		mesh.indices[numFaces++]=face;
	}
	mesh.vertices[0]=Vector3f(0.0f,0.0f,radius);
	mesh.texcoords[0]=Vector2f(0.5f*(u1+u2),0.5f*(v1+v2));
	mesh.vertices[$-1]=Vector3f(0.0f,0.0f,-radius);
	mesh.texcoords[$-1]=Vector2f(0.5f*(u1+u2),0.5f*(v1+v2));
	int idx(int i,int j){
		if(i==-1) return 0;
		if(i==numU) return 1+numU*numV;
		return 1+numV*i+j%numV;
	}
	foreach(i;0..numU){
		foreach(j;0..numV){
			auto θ=pi!float*(1+i)/(numU+1);
			auto φ=2.0f*pi!float*j/numV;
			mesh.vertices[idx(i,j)]=radius*Vector3f(cos(φ)*sin(θ),sin(φ)*sin(θ),cos(θ));
			auto texRadius=2*i<=numU?2.0f*i/numU:2.0f-2.0f*i/numU;
			mesh.texcoords[idx(i,j)]=Vector3f(u1+(u2-u1)*0.5f*(1.0f+cos(φ)*texRadius),v1+(v2-v1)*0.5f*(1.0f+sin(φ)*texRadius));
			if(i!=0){
				addFace([idx(i,j),idx(i,j+1),idx(i-1,j)]);
				addFace([idx(i,j+1),idx(i-1,j+1),idx(i-1,j)]);
				if(i+1==numU) addFace([idx(i,j),idx(i+1,j),idx(i,j+1)]);
			}else addFace([idx(i,j),idx(i,j+1),idx(-1,j)]);
		}
	}
	assert(numFaces==2*numU*numV);
	mesh.generateNormals();
	B.finalizeMesh(mesh);
	return mesh;
}

B.Mesh[] makeSphereMeshes(B)(int numU,int numV,int nU,int nV,float radius,float texWidth=1.0f,float texHeight=1.0f){
	auto meshes=new B.Mesh[](nU*nV);
	foreach(t,ref mesh;meshes){
		int u=cast(int)t%nU,v=cast(int)t/nU;
		mesh=B.makeMesh(2+numU*numV,2*numU*numV); // TODO: reuse makeSphereMesh here
		int numFaces=0;
		void addFace(uint[3] face...){
			mesh.indices[numFaces++]=face;
		}
		mesh.vertices[0]=Vector3f(0.0f,0.0f,radius);
		mesh.texcoords[0]=Vector2f(texWidth/nU*(u+0.5f),texHeight/nV*(v+0.5f));
		mesh.vertices[$-1]=Vector3f(0.0f,0.0f,-radius);
		mesh.texcoords[$-1]=Vector2f(texWidth/nU*(u+0.5f),texHeight/nV*(v+0.5f));
		int idx(int i,int j){
			if(i==-1) return 0;
			if(i==numU) return 1+numU*numV;
			return 1+numV*i+j;
		}
		foreach(i;0..numU){
			foreach(j;0..numV){
				auto θ=pi!float*(1+i)/(numU+1);
				auto φ=2.0f*pi!float*j/numV;
				mesh.vertices[idx(i,j)]=radius*Vector3f(cos(φ)*sin(θ),sin(φ)*sin(θ),cos(θ));
				auto texRadius=2*i<=numU?2.0f*i/numU:2.0f-2.0f*i/numU;
				mesh.texcoords[idx(i,j)]=Vector3f(texWidth/nU*(u+0.5f*(1.0f+cos(φ)*texRadius)),texHeight/nV*(v+0.5f*(1.0f+sin(φ)*texRadius)));
				if(i!=0){
					addFace([idx(i,j),idx(i,j+1),idx(i-1,j)]);
					addFace([idx(i,j+1),idx(i-1,j+1),idx(i-1,j)]);
					if(i+1==numU) addFace([idx(i,j),idx(i+1,j),idx(i,j+1)]);
				}else addFace([idx(i,j),idx(i,j+1),idx(-1,j)]);
			}
		}
		assert(numFaces==2*numU*numV);
		mesh.generateNormals();
		B.finalizeMesh(mesh);
	}
	return meshes;
}

B.Mesh[][] makeNoisySphereMeshes(B)(int numU,int numV,int nU,int nV,float radius,float noiseRadius,int numOffsets,float texWidth=1.0f,float texHeight=1.0f){ // (uses GC)
	auto meshes=new B.Mesh[][](numOffsets,nU*nV);
	import std.random;
	Mt19937 gen;
	foreach(offset;0..numOffsets){
		auto offsets=iota(2+numU*numV).map!(_=>Vector3f(uniform(-1.0f,1.0f,gen),uniform(-1.0f,1.0f,gen),uniform(-1.0f,1.0f,gen))).array;
		foreach(t,ref mesh;meshes[offset]){
			int u=cast(int)t%nU,v=cast(int)t/nV;
			mesh=B.makeMesh(2+numU*numV,2*numU*numV); // TODO: reuse makeSphereMesh here
			int numFaces=0;
			void addFace(uint[3] face...){
				mesh.indices[numFaces++]=face;
			}
			mesh.vertices[0]=Vector3f(0.0f,0.0f,radius)+noiseRadius*offsets[0];
			mesh.texcoords[0]=Vector2f(texWidth/nU*(u+0.5f),texHeight/nV*(v+0.5f));
			mesh.vertices[$-1]=Vector3f(0.0f,0.0f,-radius)+noiseRadius*offsets[$-1];
			mesh.texcoords[$-1]=Vector2f(texWidth/nU*(u+0.5f),texHeight/nV*(v+0.5f));
			int idx(int i,int j){
				if(i<0) return 0;
				if(i>=numU) return 1+numU*numV;
				return 1+numV*i+j;
			}
			foreach(i;0..numU){
				foreach(j;0..numV){
					auto θ=pi!float*(1+i)/(numU+1);
					auto φ=2.0f*pi!float*j/numV;
					auto noise=0.5f*offsets[idx(i,j)];
					foreach(k;0..4) noise+=1.0f/8*offsets[idx(i-(k==0)+(k==1),j-(k==2)+(k==3))];
					mesh.vertices[idx(i,j)]=radius*Vector3f(cos(φ)*sin(θ),sin(φ)*sin(θ),cos(θ))+noiseRadius*noise;
					auto texRadius=2*i<=numU?2.0f*i/numU:2.0f-2.0f*i/numU;
					mesh.texcoords[idx(i,j)]=Vector3f(texWidth/nU*(u+0.5f*(1.0f+cos(φ)*texRadius)),texHeight/nV*(v+0.5f*(1.0f+sin(φ)*texRadius)));
					if(i!=0){
						addFace([idx(i,j),idx(i,j+1),idx(i-1,j)]);
						addFace([idx(i,j+1),idx(i-1,j+1),idx(i-1,j)]);
						if(i+1==numU) addFace([idx(i,j),idx(i+1,j),idx(i,j+1)]);
					}else addFace([idx(i,j),idx(i,j+1),idx(-1,j)]);
				}
			}
			assert(numFaces==2*numU*numV);
			mesh.generateNormals();
			B.finalizeMesh(mesh);
		}
	}
	return meshes;
}

struct SacAirShield(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Stra.FLDR/txtr.FLDR/shld.TXTR"));
	}
	B.Material material;
	B.Mesh[][] meshes;
	static B.Mesh[][] createMeshes(){
		return makeNoisySphereMeshes!B(24,25,nU,nV,0.5f,0.12f,numDistortions);
	}
	enum animationDelay=4;
	enum nU=4,nV=2;
	enum numTextureFrames=nU*nV*updateAnimFactor*animationDelay;
	enum numDistortions=16;
	enum numFrames=updateFPS*numDistortions/2;
	Tuple!(B.Mesh,B.Mesh,float) getFrame(int frame,int texture){
		auto textureFrame=(texture/(animationDelay*updateAnimFactor))%(nU*nV);
		auto indices=iota(0,meshes.length);
		auto numIndices=indices.length;
		auto i=frame*numIndices/numFrames, j=i+1;
		float progress=float(frame*numIndices%numFrames)/numFrames;
		auto all=cycle(indices);
		return tuple(meshes[all[i]][textureFrame],meshes[all[j]][textureFrame],progress);
	}
}

struct SacAirShieldEffect(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Stra.FLDR/txtr.FLDR/pash.TXTR"));
	}
	B.Material material;
	B.Mesh[] frames;
	enum animationDelay=1;
	enum numFrames=16*animationDelay*updateAnimFactor;
	auto getFrame(int i){ return frames[i/(animationDelay*updateAnimFactor)]; }
	static B.Mesh[] createMeshes(){
		return makeSpriteMeshes!(B,true)(4,4,0.75f,0.75f);
	}
}

B.Mesh makeBoxMesh(B)(float width,float depth,float height){
	static Vector3f[8] box=[Vector3f(-0.5f,-0.5f,-0.5f),Vector3f(0.5f,-0.5f,-0.5f),
	                        Vector3f(0.5f,0.5f,-0.5f),Vector3f(-0.5f,0.5f,-0.5f),
	                        Vector3f(-0.5f,-0.5f,0.5f),Vector3f(0.5f,-0.5f,0.5f),
	                        Vector3f(0.5f,0.5f,0.5f),Vector3f(-0.5f,0.5f,0.5f)];
	auto mesh=B.makeMesh(24,6*2);
	mesh.vertices[0..8]=box[];
	foreach(ref p;mesh.vertices[0..8]){
		p.x*=width;
		p.y*=depth;
		p.z*=height;
	}
	mesh.vertices[8..16]=mesh.vertices[0..8];
	mesh.vertices[16..24]=mesh.vertices[0..8];
	//foreach(ref x;mesh.vertices) x*=10;
	int curFace=0;
	int offset=0;
	void face(int[] ccw...){
		ccw[]+=offset;
		mesh.indices[curFace++]=[ccw[0],ccw[1],ccw[3]];
		mesh.indices[curFace++]=[ccw[1],ccw[2],ccw[3]];
		foreach(i;0..4) mesh.texcoords[ccw[i]]=Vector3f(0.0f+(i==1||i==2),0.0f+!(i==2||i==3));
	}
	face(0,3,2,1);
	face(4,5,6,7);
	offset+=8;
	face(0,1,5,4);
	face(2,3,7,6);
	offset+=8;
	face(1,2,6,5);
	face(3,0,4,7);
	mesh.generateNormals();
	B.finalizeMesh(mesh);
	return mesh;
}

struct SacFreeze(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Stra.FLDR/txtr.FLDR/frez.TXTR"));
	}
	B.Material material;
	B.Mesh mesh;
	static B.Mesh createMesh(){
		return makeBoxMesh!B(1.0f,1.0f,1.0f);
	}
}

struct SacSlime(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/Daniel/DanC.WAD!/char.FLDR/lthg.TXTR"),false);
	}
	B.Material material;
	B.Mesh mesh;
	static B.Mesh createMesh(){
		return makeSphereMesh!B(24,25,0.5f);
	}
}

B.BoneMesh makeVineMesh(B)(int numSegments,int numVertices,float length,float size){
	auto mesh=B.makeBoneMesh(numVertices*(numSegments+1),2*(numVertices-1)*numSegments);
	int numFaces=0;
	void addFace(uint[3] face...){
		mesh.indices[numFaces++]=face;
	}
	foreach(i;0..numSegments+1){
		auto center=Vector3f(0.0f,0.0f,length*float(i)/numSegments);
		float sizeFactor=float(numSegments-i)/numSegments;
		foreach(j;0..numVertices){
			auto φ=2.0f*pi!float*j/(numVertices-1);
			auto position=center+size*sizeFactor*Vector3f(cos(φ),sin(φ),0.0f);
			int vertex=numVertices*i+j;
			foreach(l;0..3){
				mesh.vertices[l][vertex]=position;
				mesh.boneIndices[vertex][l]=i;
			}
			mesh.weights[vertex]=Vector3f(1.0f,0.0f,0.0f);
			mesh.texcoords[vertex]=Vector2f(float(j)/(numVertices-1),float(numSegments-i)/numSegments);
			if(i&&j){
				int du=1, dv=numVertices;
				addFace([vertex-du-dv,vertex-dv,vertex]);
				addFace([vertex,vertex-du,vertex-du-dv]);
			}
		}
	}
	assert(numFaces==2*(numVertices-1)*numSegments);
	Matrix4x4f[32] pose=Matrix4f.identity();
	mesh.generateNormals(pose); // TODO: this will create a seam at the texture boundary
	B.finalizeBoneMesh(mesh);
	return mesh;
}

struct SacVine(B){
	B.Texture texture;
	B.Material material;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pers.FLDR/tex_ZERO_.FLDR/vine.TXTR"));
	}
	B.BoneMesh mesh;
	enum numSegments=19;
	static B.BoneMesh createMesh(){
		enum numVertices=25;
		return makeVineMesh!B(numSegments,numVertices,0.0f,0.1f);
	}
}

struct SacRainbow(B){
	B.Texture texture;
	B.Material material;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/rnbw.TXTR"));
	}
	B.BoneMesh mesh;
	enum numSegments=31;
	static B.BoneMesh createMesh(){
		return makeLineMesh!B(numSegments,0.0f,0.7f,false);
	}
}

struct SacAnimateDead(B){
	B.Texture texture;
	B.Material material;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/Daniel/DanC.WAD!/char.FLDR/and2.TXTR"));
	}
	B.BoneMesh[] frames;
	enum numSegments=31;
	enum animationDelay=2;
	enum numFrames=8*animationDelay*updateAnimFactor;
	auto getFrame(int i){ return frames[i/(animationDelay*updateAnimFactor)]; }
	static B.BoneMesh[] createMeshes(){
		return makeLineMeshes!B(numSegments,1,8,0.0f,0.6f,false,true,false);
	}
}

struct SacDragonfire(B){
	SacObject!B obj;
	static SacObject!B create(){
		auto dragonfire=new SacObject!B("extracted/models/MODL.WAD!/dfir.MRMC/dfir.MRMM");
		swap(dragonfire.meshes[$-2],dragonfire.meshes[$-1]);
		return dragonfire;
	}
	enum numFrames=3*updateFPS/2;
	Tuple!(B.Mesh[],B.Mesh[],float) getFrame(int frame)in{
		assert(frame<numFrames);
	}do{
		auto meshes=obj.meshes;
		auto indices=chain(iota(0,meshes.length),retro(iota(1,meshes.length-1)));
		auto numIndices=indices.length;
		auto i=frame*numIndices/numFrames, j=i+1;
		float progress=float(frame*numIndices%numFrames)/numFrames;
		auto all=cycle(indices);
		return tuple(obj.meshes[all[i]],obj.meshes[all[j]],progress);
	}
}

struct SacSoulWind(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Stra.FLDR/txtr.FLDR/swnd.TXTR"),false);
	}
	B.Material material;
	B.Mesh[] frames; // TODO: do in shader instead
	enum numFrames=32;
	auto getFrame(int i){ return frames[i]; }
	enum numFaces=32;
	enum numSegments=32;
	enum height=3.0f;
	enum radius=1.5f;
	enum texrep=2.0f;
	static B.Mesh[] createMeshes(){
		auto meshes=new B.Mesh[](numFrames);
		foreach(frame,ref mesh;meshes){
			mesh=B.makeMesh((numFaces+1)*(numSegments+1),2*numFaces*numSegments);
			foreach(i;0..numSegments+1){
				foreach(j;0..numFaces+1){
					auto wradius=radius*(float(i)/numSegments+0.05f*sin(2.0f*pi!float*i/numSegments));
					auto cradius=wradius+0.5f*radius*(float(i)/numSegments)^^4;
					auto φ=2.0f*pi!float*j/numFaces;
					auto θ=pi!float*i/numSegments;
					mesh.vertices[i*(numFaces+1)+j]=Vector3f(cradius*cos(φ),cradius*sin(φ),height*i/numSegments)+0.5f*wradius*Vector3f(cos(θ),sin(θ),0.0f);
					mesh.texcoords[i*(numFaces+1)+j]=Vector2f(texrep*float(j)/numFaces,-texrep*(float(i)/numSegments-0.5f*float(frame)/numFrames));
				}
			}
			foreach(i;0..numSegments){
				foreach(j;0..numFaces){
					mesh.indices[2*(i*numFaces+j)]=[i*(numFaces+1)+j,(i+1)*(numFaces+1)+j+1,(i+1)*(numFaces+1)+j];
					mesh.indices[2*(i*numFaces+j)+1]=[i*(numFaces+1)+j,i*(numFaces+1)+j+1,(i+1)*(numFaces+1)+j+1];
				}
			}
			mesh.generateNormals(); // (doesn't actually need normals)
			B.finalizeMesh(mesh);
		}
		return meshes;
	}
}

struct SacExplosionEffect(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pyro.FLDR/txtr.FLDR/exeg.TXTR"));
	}
	B.Material material;
	B.Mesh[][] meshes;
	static B.Mesh[][] createMeshes(){
		return makeNoisySphereMeshes!B(24,25,nU,nV,1.0f,0.24f,numDistortions,2.0f,2.0f);
	}
	enum animationDelay=1;
	enum nU=4,nV=4;
	enum numTextureFrames=nU*nV*updateAnimFactor*animationDelay;
	enum numDistortions=16;
	enum numFrames=updateFPS*numDistortions/2;
	Tuple!(B.Mesh,B.Mesh,float) getFrame(int frame,int texture){
		auto textureFrame=(texture/(animationDelay*updateAnimFactor))%(nU*nV);
		auto indices=iota(0,meshes.length);
		auto numIndices=indices.length;
		auto i=frame*numIndices/numFrames, j=i+1;
		float progress=float(frame*numIndices%numFrames)/numFrames;
		auto all=cycle(indices);
		return tuple(meshes[all[i]][textureFrame],meshes[all[j]][textureFrame],progress);
	}
}

struct SacCloud(B){
	B.Material material;
	B.Mesh[] meshes;
	static B.Mesh[] createMeshes(){
		return makeNoisySphereMeshes!B(24,25,1,1,1.0f/1.48f,0.48f/1.48f,numDistortions,2.0f,2.0f).map!(m=>m[0]).array;
	}
	enum numDistortions=20;
	enum numFrames=8*updateFPS*numDistortions;
	Tuple!(B.Mesh,B.Mesh,float) getFrame(int frame){
		auto indices=iota(0,meshes.length);
		auto numIndices=indices.length;
		auto i=frame*numIndices/numFrames, j=i+1;
		float progress=float(frame*numIndices%numFrames)/numFrames;
		auto all=cycle(indices);
		return tuple(meshes[all[i]],meshes[all[j]],progress);
	}
}

struct SacRainFrog(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pers.FLDR/tex_ZERO_.FLDR/fhop.TXTR"));
	}
	B.Material material;
	B.Mesh[] frames;
	enum animationDelay=1;
	enum numFrames=16*animationDelay*updateAnimFactor;
	auto getFrame(int i){ return frames[i/(animationDelay*updateAnimFactor)]; }
	enum size=0.75f;
	static B.Mesh[] createMeshes(){
		return makeSpriteMeshes!B(4,4,size,size);
	}
}

struct SacDemonicRiftSpirit(B){
	B.Texture texture;
	B.Material material;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/Daniel/DanC.WAD!/char.FLDR/rift.TXTR"));
	}
	B.BoneMesh[] frames;
	enum numSegments=31;
	enum animationDelay=2;
	enum numFrames=8*animationDelay*updateAnimFactor;
	auto getFrame(int i){ return frames[i/(animationDelay*updateAnimFactor)]; }
	static B.BoneMesh[] createMeshes(){
		return makeLineMeshes!B(numSegments,1,8,0.0f,0.6f,false,true,false);
	}
}

struct SacDemonicRiftBorder(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/Daniel/DanC.WAD!/char.FLDR/rif2.TXTR"));
	}
	B.Material material;
	B.Mesh[] frames; // TODO: do in shader instead
	enum animationDelay=2;
	enum numFrames=8*animationDelay*updateAnimFactor;
	auto getFrame(int i){ return frames[i/(animationDelay*updateAnimFactor)]; }
	enum numFaces=128;
	enum radius=1.0f;
	enum height=0.5f;
	enum texrep=1.0f;
	static B.Mesh[] createMeshes(){
		auto meshes=new B.Mesh[](numFrames);
		foreach(frame,ref mesh;meshes){
			mesh=B.makeMesh(2*(numFaces+1),4*numFaces);
			foreach(i;0..2){
				foreach(j;0..numFaces+1){
					auto φ=2.0f*pi!float*j/numFaces;
					mesh.vertices[i*(numFaces+1)+j]=Vector3f(radius*cos(φ),radius*sin(φ),height*i);
					mesh.texcoords[i*(numFaces+1)+j]=Vector2f(texrep*float(j)/numFaces,1.0f/8.0f*(frame+1-i));
				}
			}
			foreach(j;0..numFaces){
				mesh.indices[2*(numFaces+j)]=[j,(numFaces+1)+j+1,(numFaces+1)+j];
				mesh.indices[2*(numFaces+j)+1]=[j,j+1,(numFaces+1)+j+1];
			}
			mesh.generateNormals(); // (doesn't actually need normals)
			B.finalizeMesh(mesh);
		}
		return meshes;
	}
}

struct SacDemonicRiftEffect(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/Daniel/DanC.WAD!/char.FLDR/rif3.TXTR"));
	}
	B.Material material;
	B.Mesh[] frames;
	enum ringAnimationDelay=4;
	enum numFrames=16*ringAnimationDelay*updateAnimFactor;
	auto getFrame(int i){ return frames[i/(ringAnimationDelay*updateAnimFactor)]; }
	static B.Mesh[] createMeshes(){
		return makeSpriteMeshes!(B,true)(4,4,2.5f,2.5f);
	}
}

struct SacHealingAura(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pers.FLDR/tex_ZERO_.FLDR/haur.TXTR"));
	}
	B.Material material;
	B.Mesh[][] meshes;
	static B.Mesh[][] createMeshes(){
		return makeNoisySphereMeshes!B(24,25,nU,nV,0.5f,0.06f,numDistortions);
	}
	enum animationDelay=2;
	enum nU=4,nV=4;
	enum numTextureFrames=nU*nV*updateAnimFactor*animationDelay;
	enum numDistortions=16;
	enum numFrames=updateFPS*numDistortions/2;
	Tuple!(B.Mesh,B.Mesh,float) getFrame(int frame,int texture){
		auto textureFrame=(texture/(animationDelay*updateAnimFactor))%(nU*nV);
		auto indices=iota(0,meshes.length);
		auto numIndices=indices.length;
		auto i=frame*numIndices/numFrames, j=i+1;
		float progress=float(frame*numIndices%numFrames)/numFrames;
		auto all=cycle(indices);
		return tuple(meshes[all[i]][textureFrame],meshes[all[j]][textureFrame],progress);
	}
}

struct SacFrozenGround(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Stra.FLDR/txtr.FLDR/icec.TXTR"));
	}
	B.Material material;
	B.GroundPatch mesh;
	enum numSegmentsU=32;
	enum numSegmentsV=32;
	enum numRepetitionsU=12;
	enum numRepetitionsV=6;
	static B.GroundPatch createMesh(){
		return B.makeGroundPatch(numSegmentsU,numSegmentsV,numRepetitionsU,numRepetitionsV);
	}
}

B.Mesh makeSpikeMesh(B)(int numV,float texBase,float base,float baseRadius,float topRadius){
	enum numU=2;
	auto mesh=B.makeMesh((numU+1)*numV,2*numU*numV);
	int numFaces=0;
	void addFace(uint[3] face...){
		mesh.indices[numFaces++]=face;
	}
	int idx(int i,int j){
		return numV*i+j%numV;
	}
	foreach(j;0..numV){
		mesh.vertices[idx(numU,j)]=Vector3f(0.0f,0.0f,1.0f);
		mesh.texcoords[idx(numU,j)]=Vector2f(0.5f,0.5f);
	}
	foreach(i;0..numU){
		foreach(j;0..numV){
			auto θ=pi!float*(1+i)/(numU+1);
			auto φ=2.0f*pi!float*j/numV;
			auto radius=i?topRadius:baseRadius;
			mesh.vertices[idx(i,j)]=Vector3f(radius*cos(φ),radius*sin(φ),i*base/(numU-1));
			auto texDir=Vector2f(cos(φ),sin(φ));
			texDir/=max(abs(texDir.x),abs(texDir.y));
			auto texRadius=0.5f*(1.0f-texBase*i/(numU-1));
			auto texCoord=Vector2f(0.5f,0.5f)+texDir*texRadius;
			mesh.texcoords[idx(i,j)]=texCoord;
			if(i!=0){
				addFace([idx(i,j),idx(i-1,j),idx(i,j+1)]);
				addFace([idx(i,j+1),idx(i-1,j),idx(i-1,j+1)]);
			}
			if(i+1==numU) addFace([idx(i,j),idx(i,j+1),idx(i+1,j)]);
		}
	}
	assert(numFaces==2*(numU-1)*numV+numV);
	mesh.generateNormals();
	B.finalizeMesh(mesh);
	return mesh;
}

struct SacSpike(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/shawn/shwn.WAD!/jams.FLDR/text.FLDR/jspk.TXTR"));
	}
	B.Material material;
	B.Mesh mesh;
	static B.Mesh createMesh(){
		return makeSpikeMesh!B(32,0.6f,0.75f,0.3f,0.25f);
	}
}

B.BoneMesh makeWallMesh(B)(int numSegments,bool flip=false,int nU=1,int nV=1,int u=0,int v=0){
	enum segmentLength=1.0f;
	enum size=0.5f;
	auto mesh=B.makeBoneMesh(2*3*2*numSegments,2*2*2*numSegments);
	immutable Vector3f[3][2] offsets=[
		[Vector3f(-size,0.0f,0.0f),Vector3f(-0.4f*size,0.0f,0.4f),Vector3f(0.0f,0.0f,1.0f)],
		[Vector3f( size,0.0f,0.0f),Vector3f( 0.4f*size,0.0f,0.4f),Vector3f(0.0f,0.0f,1.0f)],
	];
	int numFaces=0;
	void addFace(bool swap,uint[3] face...){
		mesh.indices[numFaces++]=face;
		if(swap) .swap(mesh.indices[numFaces-1][1],mesh.indices[numFaces-1][2]);
	}
	void addQuad(bool swap,uint[4] face...){
		addFace(swap,face[0],face[1],face[2]);
		addFace(swap,face[0],face[2],face[3]);
	}
	foreach(i;0..numSegments){
		foreach(s;0..2){
			foreach(j;0..3){
				foreach(k;0..2){
					int vertex=2*3*2*i+3*2*s+2*j+k;
					auto center=i+k;
					auto position=offsets[s][j];
					foreach(l;0..3){
						mesh.vertices[l][vertex]=position;
						mesh.boneIndices[vertex][l]=center;
					}
					mesh.weights[vertex]=Vector3f(1.0f,0.0f,0.0f);
					float[3] texOffsets=[1.0f-0.5f/(256/nV),0.6f,0.5f/(256/nV)];
					mesh.texcoords[vertex]=Vector2f(1.0f/nU*(u+((flip?i&1:0)^k?1.0f-0.5f/(256/nU):0.5f/(256/nU))),
					                                1.0f/nV*(v+texOffsets[j]));
				}
			}
			int b=2*3*2*i+3*2*s;
			foreach(j;0..2) addQuad(!!s,[b+2*j,b+2*(j+1),b+2*(j+1)+1,b+2*j+1]);
		}
	}
	assert(numFaces==2*2*2*numSegments);
	mesh.normals[]=Vector3f(0.0f, 0.0f, 0.0f);
	B.finalizeBoneMesh(mesh);
	return mesh;
}

B.BoneMesh[] makeWallMeshes(B)(int numSegments,int nU,int nV,bool flip=false){
	auto meshes=new B.BoneMesh[](nU*nV);
	foreach(t,ref mesh;meshes){
		int u=cast(int)t%nU,v=cast(int)t/nU;
		mesh=makeWallMesh!B(numSegments,flip,nU,nV,u,v);
	}
	return meshes;
}

struct SacFirewall(B){
	B.Texture texture;
	B.Material material;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pyro.FLDR/txtr.FLDR/fwal.TXTR"));
	}
	B.BoneMesh[] frames;
	enum numFrames=16*2*updateAnimFactor;
	auto getFrame(int i){ return frames[i/(2*updateAnimFactor)]; }
	enum numSegments=16;
	static B.BoneMesh[] createMeshes(){
		enum nU=4,nV=4;
		return makeWallMeshes!B(numSegments,nU,nV,true);
	}
}

struct SacWailingWallSpirit(B){
	B.Texture texture;
	B.Material material;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Char.FLDR/tex_ZERO_.FLDR/wlsp.TXTR"));
	}
	B.BoneMesh[] frames;
	enum numSegments=31;
	enum animationDelay=2;
	enum numFrames=8*animationDelay*updateAnimFactor;
	auto getFrame(int i){ return frames[i/(animationDelay*updateAnimFactor)]; }
	static B.BoneMesh[] createMeshes(){
		return makeLineMeshes!B(numSegments,1,8,0.0f,0.6f,false,true,false);
	}
}

struct SacWailingWall(B){
	B.Texture texture;
	B.Material material;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/wwal.TXTR"));
	}
	B.BoneMesh[] frames;
	enum numFrames=16*2*updateAnimFactor;
	auto getFrame(int i){ return frames[i/(2*updateAnimFactor)]; }
	enum numSegments=16;
	static B.BoneMesh[] createMeshes(){
		enum nU=4,nV=4;
		return makeWallMeshes!B(numSegments,nU,nV,true);
	}
}

struct SacFence(B){
	B.Texture[2] textures; // [bubble, sparks]
	static B.Texture[2] loadTextures(){
		return [B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pers.FLDR/tex_ZERO_.FLDR/scri.TXTR")),
		        B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/cst0.TXTR"))];
	}
	B.Material[2] materials;
	B.Mesh[] frames;
	enum animationDelay=2;
	enum numFrames=16*updateAnimFactor*animationDelay;
	auto getFrame(int i){ return frames[i/(animationDelay*updateAnimFactor)]; }
	enum size=3.0f;
	static B.Mesh[] createMeshes(){
		return makeSpriteMeshes!B(4,4,1.0f,1.0f); // To be scaled by `size`
	}
}

struct SacBrainiacEffect(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Stra.FLDR/txtr.FLDR/mind.TXTR"));
	}
	B.Material material;
	B.Mesh[] frames;
	enum animationDelay=1;
	enum numFrames=16*animationDelay*updateAnimFactor;
	auto getFrame(int i){ return frames[i/(animationDelay*updateAnimFactor)]; }
	static B.Mesh[] createMeshes(){
		return makeSpriteMeshes!(B,true)(4,4,0.9f,0.9f);
	}
}

struct SacShrikeEffect(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pers.FLDR/tex_ZERO_.FLDR/sonc.TXTR"));
	}
	B.Material material;
	B.Mesh[] frames;
	enum animationDelay=1;
	enum numFrames=64*animationDelay*updateAnimFactor;
	auto getFrame(int i){ return frames[i/(animationDelay*updateAnimFactor)]; }
	static B.Mesh[] createMeshes(){
		return makeSpriteMeshes!(B,true)(8,8,1.75f,1.75f);
	}
}

struct SacArrow(B){
	B.Texture sylphTexture;
	B.Material sylphMaterial;
	static B.Texture loadSylphTexture(){
		return B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/ltn2.TXTR"));
	}
	B.Texture rangerTexture;
	B.Material rangerMaterial;
	static B.Texture loadRangerTexture(){
		return B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/wzrg.TXTR"));
	}
	B.Mesh[] frames;
	enum numFrames=16*updateAnimFactor;
	auto getFrame(int i){ return frames[i/updateAnimFactor]; }
	static B.Mesh[] createMeshes(){
		enum nU=4,nV=4;
		auto meshes=new B.Mesh[](nU*nV);
		foreach(t,ref mesh;meshes){
			mesh=B.makeMesh(3*4,3*2);
			int u=cast(int)t%nU,v=cast(int)t/nU;
			enum length=1.0f;
			enum size=0.1f;
			enum sqrt34=sqrt(0.75f);
			static immutable Vector3f[3] offsets=[size*Vector3f(0.0f,-1.0f,0.0f),size*Vector3f(sqrt34,0.5f,0.0f),size*Vector3f(-sqrt34,0.5f,0.0f)];
			int numFaces=0;
			void addFace(uint[3] face...){
				mesh.indices[numFaces++]=face;
			}
			static Vector3f getCenter(int i){
				return Vector3f(0.0f,0.0f,length*i);
			}
			foreach(j;0..3){
				foreach(k;0..4){
					int vertex=4*j+k;
					auto center=((k==1||k==2)?1:0);
					auto position=getCenter(center)+((k==2||k==3)&&center!=1?offsets[j]:Vector3f(0.0f,0.0f,0.0f));
					mesh.vertices[vertex]=position;
					mesh.texcoords[vertex]=Vector2f(1.0f/nU*(u+((k==1||k==2)?1.0f-0.5f/64:0.5f/64)),1.0f/nV*(v+((k==0||k==1)?1.0f-0.5f/64:0.5f/64)));
				}
				int b=4*j;
				addFace([b+0,b+1,b+2]);
				addFace([b+2,b+3,b+0]);
			}
			assert(numFaces==2*3);
			mesh.normals[]=Vector3f(0.0f,0.0f,0.0f);
			B.finalizeMesh(mesh);
		}
		return meshes;
	}
}

struct SacBasiliskEffect(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Jame.FLDR/tex_ZERO_.FLDR/gaze.TXTR"));
	}
	B.Material material;
	B.Mesh[] frames;
	enum animationDelay=1;
	enum numFrames=16*animationDelay*updateAnimFactor;
	auto getFrame(int i){ return frames[i/(animationDelay*updateAnimFactor)]; }
	static B.Mesh[] createMeshes(){
		return makeSpriteMeshes!(B,true)(4,4,0.6f,0.6f);
	}
}

struct SacLifeShield(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pers.FLDR/tex_ZERO_.FLDR/ent1.TXTR"));
	}
	B.Material material;
	B.Mesh[16] frames;
	enum animationDelay=2;
	enum numFrames=16*updateAnimFactor*animationDelay;
	auto getFrame(int i){ return frames[i/(animationDelay*updateAnimFactor)]; }
	static B.Mesh[16] createMeshes(){
		enum nU=4,nV=4;
		return makeSphereMeshes!B(24,25,nU,nV,0.5f)[0..16];
	}
}

struct SacDivineSight(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pers.FLDR/tex_ZERO_.FLDR/scri.TXTR"));
	}
	B.Material material;
	B.Mesh[] frames;
	enum animationDelay=4;
	enum numFrames=16*updateAnimFactor*animationDelay;
	auto getFrame(int i){ return frames[i/(animationDelay*updateAnimFactor)]; }
	static B.Mesh[] createMeshes(){
		return makeSpriteMeshes!B(4,4,2.5f,2.25f);
	}
}

struct SacBlightMite(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Char.FLDR/tex_ZERO_.FLDR/mite.TXTR"));
	}
	B.Material material;
	B.Mesh[] frames;
	enum animationDelay=2;
	enum numFrames=16*animationDelay*updateAnimFactor;
	auto getFrame(int i){ return frames[i/(animationDelay*updateAnimFactor)]; }
	static B.Mesh[] createMeshes(){
		return makeSpriteMeshes!B(4,4,1.0f,1.0f);
	}
}

struct SacCord(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pers.FLDR/tex_ZERO_.FLDR/cord.TXTR"));
	}
	B.Material material;
	B.Mesh mesh;
	static B.Mesh createMesh(){
		auto mesh=B.makeMesh(3*4,3*2);
		enum length=1.0f;
		enum size=1.0f;
		enum sqrt34=sqrt(0.75f);
		static immutable Vector3f[3] offsets=[size*Vector3f(0.0f,-1.0f,0.0f),size*Vector3f(sqrt34,0.5f,0.0f),size*Vector3f(-sqrt34,0.5f,0.0f)];
		int numFaces=0;
		void addFace(uint[3] face...){
			mesh.indices[numFaces++]=face;
		}
		static Vector3f getCenter(int i){
			return Vector3f(0.0f,0.0f,length*i);
		}
		foreach(j;0..3){
			foreach(k;0..4){
				int vertex=4*j+k;
				auto center=((k==1||k==2)?1:0);
				auto position=getCenter(center)+((k==2||k==3)?offsets[j]:Vector3f(0.0f,0.0f,0.0f));
				mesh.vertices[vertex]=position;
				mesh.texcoords[vertex]=Vector2f((k==1||k==2)?1.0f-0.5f/32:0.5f/32,(k==0||k==1)?1.0f-0.5f/32:0.5f/32);
			}
			int b=4*j;
			addFace([b+0,b+1,b+2]);
			addFace([b+2,b+3,b+0]);
		}
		assert(numFaces==2*3);
		mesh.normals[]=Vector3f(0.0f,0.0f,0.0f);
		B.finalizeMesh(mesh);
		return mesh;
	}
}

struct SacWeb(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pers.FLDR/tex_ZERO_.FLDR/webc.TXTR"));
	}
	B.Material material;
	B.Mesh mesh;
	static B.Mesh createMesh(){
		return makeSphereMesh!B(24,25,0.5f);
	}
}

struct SacCage(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Stra.FLDR/txtr.FLDR/eweb.TXTR"));
	}
	B.Material material;
	B.Mesh[8] frames;
	enum animationDelay=2;
	enum numFrames=8*updateAnimFactor*animationDelay;
	auto getFrame(int i){ return frames[i/(animationDelay*updateAnimFactor)]; }
	static B.Mesh[8] createMeshes(){
		enum nU=4,nV=2;
		return makeSphereMeshes!B(24,25,nU,nV,0.5f)[0..8];
	}
}

struct SacStickyBomb(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Jame.FLDR/tex_ZERO_.FLDR/stky.TXTR"));
	}
	B.Material material;
	B.Mesh[] frames;
	enum animationDelay=2;
	enum numFrames=16*animationDelay*updateAnimFactor;
	auto getFrame(int i){ return frames[i/(animationDelay*updateAnimFactor)]; }
	static B.Mesh[] createMeshes(){
		return makeSpriteMeshes!B(4,4,0.5f,0.5f);
	}
}

struct SacOil(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pyro.FLDR/txtr.FLDR/oile.TXTR"));
	}
	B.Material material;
	B.Mesh[] frames;
	enum animationDelay=2;
	enum numFrames=16*animationDelay*updateAnimFactor;
	auto getFrame(int i){ return frames[i/(animationDelay*updateAnimFactor)]; }
	static B.Mesh[] createMeshes(){
		return makeSpriteMeshes!B(4,4,2.0f,2.0f);
	}
}

struct SacLaser(B){
	B.Texture texture;
	B.Material material;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/wzrg.TXTR"));
	}
	B.BoneMesh[] frames;
	enum numFrames=16*updateAnimFactor;
	auto getFrame(int i){ return frames[i/updateAnimFactor]; }
	enum numSegments=3;
	static B.BoneMesh[] createMeshes(){
		enum nU=4,nV=4;
		return makeLineMeshes!B(numSegments,nU,nV,1.0f,1.0f,true);
	}
}

struct SacTube(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/tube.TXTR"));
	}
	B.Material material;
	B.Mesh[] frames;
	enum animationDelay=1;
	enum numFrames=16*animationDelay*updateAnimFactor;
	auto getFrame(int i){ return frames[i/(animationDelay*updateAnimFactor)]; }
	static B.Mesh[] createMeshes(){
		return makeSpriteMeshes!(B,true)(4,4,1.0f,1.0f);
	}
}

struct SacVortexEffect(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/cst0.TXTR"));
	}
	B.Material material;
	B.Mesh[] frames;
	enum animationDelay=4;
	enum numFrames=16*updateAnimFactor*animationDelay;
	auto getFrame(int i){ return frames[i/(animationDelay*updateAnimFactor)]; }
	//auto getFrame(int i){ return frames[9]; }
	static B.Mesh[] createMeshes(){
		return makeSpriteMeshes!B(4,4,1.0f,1.0f);
	}
}


struct SacVortex(B){
	B.Texture redRim,redCenter;
	B.Texture blueRim,blueCenter;
	B.Material redRimMat,redCenterMat;
	B.Material blueRimMat,blueCenterMat;
	void loadTextures(){
		redRim=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/vtx1.TXTR"));
		redCenter=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/vtx2.TXTR"));
		blueRim=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/ltn2.TXTR"));
		blueCenter=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/vtx3.TXTR"));
	}
	B.Mesh[] rimMeshes;
	static B.Mesh[] createRimMeshes(){
		enum nU=4,nV=4;
		auto meshes=new B.Mesh[](nU*nV);
		foreach(t,ref mesh;meshes){
			enum resolution=32;
			enum numSegments=16*resolution;
			enum textureMultiplier=1.0f/resolution;
			auto numVertices=3*numSegments,numFaces=2*2*numSegments;
			mesh=B.makeMesh(numVertices,numFaces);
			int u=cast(int)t%nU,v=cast(int)t/nU;
			int curNumFaces=0;
			void addFace(uint[3] face...){
				mesh.indices[curNumFaces++]=face;
			}
			enum thickness=0.35f;
			foreach(i;0..numSegments){
				auto top=3*i,middle=3*i+1,bottom=3*i+2;
				auto alpha=2*pi!float*i/numSegments;
				auto direction=Vector2f(cos(alpha),sin(alpha));
				mesh.vertices[top]=Vector3f(direction.x,direction.y,0.0f);
				mesh.vertices[middle]=Vector3f((1.0f-0.5f*thickness)*direction.x,(1.0f-0.5f*thickness)*direction.y,0.0f);
				mesh.vertices[bottom]=Vector3f((1.0f-thickness)*direction.x,(1.0f-thickness)*direction.y,0.0f);
				float zigzag(float x,float a,float b){
					auto α=fmod(x,1);
					if(cast(int)x&1) α=1-α;
					return (1-α)*a+α*b;
				}
				enum offset=1.0f/64.0f;
				auto x=zigzag(i*textureMultiplier,1.0f/nU*(u+offset),1.0f/nU*(u+1.0f-offset));
				mesh.texcoords[top]=Vector2f(x,1.0f/nV*(v+offset));
				mesh.texcoords[bottom]=mesh.texcoords[top];
				mesh.texcoords[middle]=Vector2f(x,1.0f/nV*(v+1.0f-offset));
				int next(int id){ return (id+3)%numVertices; }
				addFace(top,next(top),middle);
				addFace(next(top),next(middle),middle);
				addFace(bottom,middle,next(bottom));
				addFace(next(bottom),middle,next(middle));
			}
			assert(numFaces==2*2*numSegments);
			mesh.normals[]=Vector3f(0.0f, 0.0f, 0.0f);
			B.finalizeMesh(mesh);
		}
		return meshes;
	}
	enum numRimFrames=16*updateAnimFactor;
	B.Mesh getRimFrame(int i){ return rimMeshes[i/updateAnimFactor]; }
	B.Mesh[] centerMeshes;
	static B.Mesh[] createCenterMeshes(){
		return makeSpriteMeshes!B(4,4,2.0f,2.0f);
	}
	enum numCenterFrames=16*updateAnimFactor;
	B.Mesh getCenterFrame(int i){ return centerMeshes[i/updateAnimFactor]; }
}

struct SacSquallEffect(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Stra.FLDR/txtr.FLDR/sqll.TXTR"));
	}
	B.Material material;
	B.Mesh[] frames;
	enum animationDelay=2;
	enum numFrames=16*animationDelay*updateAnimFactor;
	auto getFrame(int i){ return frames[i/(animationDelay*updateAnimFactor)]; }
	static B.Mesh[] createMeshes(){
		return makeSpriteMeshes!(B,true)(4,4,2.5f,2.5f);
	}
}

struct SacPyromaniacRocket(B){
	B.Texture texture;
	B.Material material;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pyro.FLDR/txtr.FLDR/rckt.TXTR"));
	}
	B.Mesh[] frames;
	enum animationDelay=2;
	enum numFrames=4*animationDelay*updateAnimFactor;
	auto getFrame(int i){ return frames[i/(updateAnimFactor*animationDelay)]; }
	static B.Mesh[] createMeshes(){
		enum nU=1,nV=4;
		auto meshes=new B.Mesh[](nU*nV);
		foreach(t,ref mesh;meshes){
			mesh=B.makeMesh(3*4,3*2);
			int u=cast(int)t%nU,v=cast(int)t/nU;
			enum length=2.0f;
			enum size=0.4f;
			enum sqrt34=sqrt(0.75f);
			static immutable Vector3f[3] offsets=[size*Vector3f(0.0f,-1.0f,0.0f),size*Vector3f(sqrt34,0.5f,0.0f),size*Vector3f(-sqrt34,0.5f,0.0f)];
			int numFaces=0;
			void addFace(uint[3] face...){
				mesh.indices[numFaces++]=face;
			}
			static Vector3f getCenter(int i){
				return Vector3f(0.0f,0.0f,length*(i-1));
			}
			foreach(j;0..3){
				foreach(k;0..4){
					int vertex=4*j+k;
					int center=(k==1||k==2);
					auto position=getCenter(center)+((k==2||k==3)?offsets[j]:Vector3f(0.0f,0.0f,0.0f));
					mesh.vertices[vertex]=position;
					mesh.texcoords[vertex]=Vector2f(1.0f/nU*(u+((k==1||k==2)?1.0f-0.5f/256:0.5f/256)),1.0f/nV*(v+((k==0||k==1)?1.0f-0.5f/64:0.5f/64)));
				}
				int b=4*j;
				addFace([b+0,b+1,b+2]);
				addFace([b+2,b+3,b+0]);
			}
			assert(numFaces==2*3);
			mesh.normals[]=Vector3f(0.0f,0.0f,0.0f);
			B.finalizeMesh(mesh);
		}
		return meshes;
	}
}

struct SacPoisonDart(B){
	B.Texture texture;
	B.Material material;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Char.FLDR/tex_ZERO_.FLDR/hypo.TXTR"));
	}
	B.Mesh mesh;
	static B.Mesh createMesh(){
		enum nU=1,nV=1;
		enum t=0;
		auto mesh=B.makeMesh(3*4,3*2);
		int u=cast(int)t%nU,v=cast(int)t/nU;
		enum length=2.0f;
		enum size=0.8f;
		enum sqrt34=sqrt(0.75f);
		static immutable Vector3f[3] offsets=[size*Vector3f(0.0f,-1.0f,0.0f),size*Vector3f(sqrt34,0.5f,0.0f),size*Vector3f(-sqrt34,0.5f,0.0f)];
		int numFaces=0;
		void addFace(uint[3] face...){
			mesh.indices[numFaces++]=face;
		}
		static Vector3f getCenter(int i){
			return Vector3f(0.0f,0.0f,length*(i-1));
		}
		foreach(j;0..3){
			foreach(k;0..4){
				int vertex=4*j+k;
				int center=(k==1||k==2);
				auto position=getCenter(center)+((k==2||k==3)?offsets[j]:Vector3f(0.0f,0.0f,0.0f));
				mesh.vertices[vertex]=position;
				mesh.texcoords[vertex]=Vector2f(1.0f/nU*(u+((k==1||k==2)?1.0f-0.5f/256:0.5f/256)),1.0f/nV*(v+((k==0||k==1)?1.0f-0.5f/256:0.5f/256)));
			}
			int b=4*j;
			addFace([b+0,b+1,b+2]);
			addFace([b+2,b+3,b+0]);
		}
		assert(numFaces==2*3);
		mesh.normals[]=Vector3f(0.0f,0.0f,0.0f);
		B.finalizeMesh(mesh);
		return mesh;
	}
}

B.Mesh[] createGunFlameMeshes(B)(int nU,int nV,float length,float size){
	auto meshes=new B.Mesh[](nU*nV);
	foreach(t,ref mesh;meshes){
		mesh=B.makeMesh(3*4*2+4*4,3*2*2+4*2);
		int u=cast(int)t%nU,v=cast(int)t/nU;
		enum sqrt34=sqrt(0.75f);
		immutable Vector3f[3] offsets=[size*Vector3f(0.0f,-1.0f,0.0f),size*Vector3f(sqrt34,0.5f,0.0f),size*Vector3f(-sqrt34,0.5f,0.0f)];
		int numFaces=0;
		void addFace(uint[3] face...){
			mesh.indices[numFaces++]=face;
		}
		foreach(i;0..2){
			Vector3f getCenter(int i){
				return Vector3f(0.0f,0.0f,i==0?0.0f:i==1?0.25f:length);
			}
			foreach(j;0..3){
				foreach(k;0..4){
					int vertex=3*4*i+4*j+k;
					int center=((k==1||k==2)?i+1:i);
					auto position=getCenter(center)+((k==2||k==3)?offsets[j]:Vector3f(0.0f,0.0f,0.0f));
					mesh.vertices[vertex]=position;
					mesh.texcoords[vertex]=Vector2f(1.0f/nU*(u+((!(i&1))^(k==1||k==2)?1.0f-0.5f/64:0.5f/64)),1.0f/nV*(v+((k==0||k==1)?0.5f/64:1.0f-0.5f/64)));
				}
				int b=3*4*i+4*j;
				addFace([b+0,b+1,b+2]);
				addFace([b+2,b+3,b+0]);
			}
		}
		assert(numFaces==2*3*2);
		foreach(i;0..2){
			foreach(j;0..2){
				Vector3f getPos(int i,int j){
					return Vector3f(size*(i-1),size*(j-1),0.25f);
				}
				foreach(k;0..4){
					int vertex=3*4*2+2*4*i+4*j+k;
					int ci=((k==1||k==2)?i+1:i),cj=((k==0||k==1)?j:j+1);
					auto position=getPos(ci,cj);
					mesh.vertices[vertex]=position;
					mesh.texcoords[vertex]=Vector2f(1.0f/nU*(u+((!(i&1))^(k==1||k==2)?1.0f-0.5f/64:0.5f/64)),1.0f/nV*(v+((!(j&1))^(k==0||k==1)?0.5f/64:1.0f-0.5f/64)));
				}
				int b=3*4*2+2*4*i+4*j;
				addFace([b+0,b+1,b+2]);
				addFace([b+2,b+3,b+0]);
			}
		}
		assert(numFaces==2*3*2+4*2);
		mesh.normals[]=Vector3f(0.0f,0.0f,0.0f);
		B.finalizeMesh(mesh);
	}
	return meshes;
}

struct SacGnomeEffect(B){
	B.Texture texture;
	B.Material material;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pers.FLDR/tex_ZERO_.FLDR/gmfl.TXTR"));
	}
	B.Mesh[] frames;
	enum animationDelay=2;
	enum numFrames=4*animationDelay*updateAnimFactor;
	auto getFrame(int i){ return frames[i/(updateAnimFactor*animationDelay)]; }
	static B.Mesh[] createMeshes(){
		enum nU=2,nV=2;
		enum length=1.7f;
		enum size=0.7f;
		return createGunFlameMeshes!B(nU,nV,length,size);
	}
}


struct SacMutantProjectile(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pers.FLDR/tex_ZERO_.FLDR/mbry.TXTR"));
	}
	B.Material material;
	B.Mesh[] frames;
	enum animationDelay=2;
	enum numFrames=16*updateAnimFactor*animationDelay;
	auto getFrame(int i){ return frames[i/(animationDelay*updateAnimFactor)]; }
	static B.Mesh[] createMeshes(){
		return makeSpriteMeshes!B(4,4,2.25f,2.25f);
	}
}

struct SacAbominationProjectile(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Char.FLDR/tex_ZERO_.FLDR/guts.TXTR"));
	}
	B.Material material;
	B.Mesh[] frames;
	enum animationDelay=2;
	enum numFrames=16*updateAnimFactor*animationDelay;
	auto getFrame(int i){ return frames[i/(animationDelay*updateAnimFactor)]; }
	static B.Mesh[] createMeshes(){
		return makeSpriteMeshes!B(4,4,1.75f,1.75f);
	}
}

struct SacBombardProjectile(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pyro.FLDR/txtr.FLDR/bbrd.TXTR"));
	}
	B.Material material;
	B.Mesh[] frames;
	enum animationDelay=2;
	enum numFrames=16*updateAnimFactor*animationDelay;
	auto getFrame(int i){ return frames[i/(animationDelay*updateAnimFactor)]; }
	static B.Mesh[] createMeshes(){
		return makeSpriteMeshes!B(4,4,2.75f,2.75f);
	}
}


B.Mesh makeCrystalMesh(B)(int numSpikes, float spikeWidth, float spikeLength){
	auto mesh=B.makeMesh(3*4*numSpikes, 3*2*numSpikes);
	enum sqrt34=sqrt(0.75f);
	immutable Vector3f[3] offsets=[spikeWidth*Vector3f(0.0f,-1.0f,0.0f),spikeWidth*Vector3f(sqrt34,0.5f,0.0f),spikeWidth*Vector3f(-sqrt34,0.5f,0.0f)];
	int numFaces=0;
	void addFace(uint[3] face...){
		mesh.indices[numFaces++]=face;
	}
	Vector3f getCenter(int i){
		return Vector3f(0.0f,0.0f,spikeLength*i);
	}
	import std.random: MinstdRand0;
	auto rng=MinstdRand0(1);
	T normal(T=float)(){
		enum n=10;
		T r=0;
		enum T sqrt3n=sqrt(3.0f)/n;
		import std.random: uniform;
		foreach(i;0..n) r+=uniform(T(-sqrt3n),T(sqrt3n),rng);
		return r;
	}
	Vector3f randomDirection(){
		return Vector3f(normal(),normal(),normal()).normalized;
	}
	foreach(i;0..numSpikes){
		auto rotation=rotationBetween(Vector3f(0.0f,0.0f,1.0f),randomDirection());
		foreach(j;0..3){
			foreach(k;0..4){
				int vertex=3*4*i+4*j+k;
				auto center=((k==1||k==2)?1:0);
				auto position=rotate(rotation, getCenter(center)+((k==2||k==3)?offsets[j]:Vector3f(0.0f,0.0f,0.0f)));
				mesh.vertices[vertex]=position;
				mesh.texcoords[vertex]=Vector2f((!(k==0||k==1)?1.0f-0.5f/64:0.5f/64),((k==1||k==2)?1.0f-0.5f/64:0.5f/64.0f));
			}
			int b=3*4*i+4*j;
			addFace([b+0,b+1,b+2]);
			addFace([b+2,b+3,b+0]);
		}
	}
	assert(numFaces==2*3*numSpikes);
	mesh.normals[]=Vector3f(0.0f, 0.0f, 0.0f);
	B.finalizeMesh(mesh);
	return mesh;
}

struct SacFlurryProjectile(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/iplt.TXTR"));
	}
	B.Material material;
	B.Mesh mesh;
	static B.Mesh createMesh(){
		return makeCrystalMesh!B(64, 0.175f, 1.75f);
	}
}
struct SacFlurryImplosion(B){
	B.Texture texture;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Stra.FLDR/txtr.FLDR/icec.TXTR"));
	}
	B.Material material;
	B.Mesh mesh;
	static B.Mesh createMesh(){
		return makeSphereMesh!B(24,25,1.0f);
	}
}

struct SacWarmongerEffect(B){
	B.Texture texture;
	B.Material material;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Pyro.FLDR/txtr.FLDR/wmfl.TXTR"));
	}
	B.Mesh[] frames;
	enum animationDelay=1;
	enum numFrames=4*animationDelay*updateAnimFactor/2;
	auto getFrame(int i){ return frames[i/(updateAnimFactor*animationDelay)]; }
	static B.Mesh[] createMeshes(){
		enum nU=2,nV=2;
		enum length=3.6f;
		enum size=0.5f;
		return createGunFlameMeshes!B(nU,nV,length,size);
	}
}

struct SacHellmouthProjectile(B){
	B.Texture texture;
	B.Material material;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Char.FLDR/tex_ZERO_.FLDR/mssg.TXTR"));
	}
	B.BoneMesh mesh;
	enum numSegments=31;
	static B.BoneMesh createMesh(){
		return makeLineMesh!B(numSegments,0.0f,0.85f,false,false,false);
	}
}

struct SacTether(B){
	B.Texture texture;
	B.Material material;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/ltn2.TXTR"));
	}
	B.BoneMesh[] frames;
	enum numFrames=16*updateAnimFactor;
	auto getFrame(int i){ return frames[i/updateAnimFactor]; }
	enum numSegments=19;
	static B.BoneMesh[] createMeshes(){
		enum nU=4,nV=4;
		return makeLineMeshes!B(numSegments,nU,nV,0.0f,0.3f,true);
	}
}

struct SacGuardianTether(B){
	B.Texture texture;
	B.Material material;
	static B.Texture loadTexture(){
		return B.makeTexture(loadTXTR("extracted/charlie/Bloo.WAD!/Misc.FLDR/txtr.FLDR/grdn.TXTR"));
	}
	B.BoneMesh[] frames;
	enum numFrames=16*updateAnimFactor;
	auto getFrame(int i){ return frames[i/updateAnimFactor]; }
	enum numSegments=19;
	static B.BoneMesh[] createMeshes(){
		enum nU=4,nV=4;
		return makeLineMeshes!B(numSegments,nU,nV,1.5f,1.0f,true);
	}
}

enum CommandConeColor{
	white,
	red,
	blue,
}
final class SacCommandCone(B){
	B.Mesh mesh;
	B.Texture texture;
	B.Material material;
	enum numFaces=8;
	enum height=10.0f;
	enum radius=0.7f;
	enum lifetime=0.5f;
	static immutable colors=[Color4f(1.0f,1.0f,1.0f),Color4f(1.0f,0.05f,0.05f),Color4f(0.05f,0.05f,1.0f)];
	this(){
		mesh=B.makeMesh(numFaces+1,numFaces);
		foreach(i;0..numFaces){
			auto φ=2.0f*pi!float*i/numFaces;
			mesh.vertices[i]=Vector3f(0.01f,0.0f,0.0f)+Vector3f(radius*cos(φ),radius*sin(φ),height);
			mesh.texcoords[i]=Vector2f(0.5f,0.5f)+0.5f*Vector2f(cos(φ),sin(φ));
		}
		mesh.vertices[numFaces]=Vector3f(0,0,0);
		mesh.texcoords[numFaces]=Vector2f(0.5f,0.5f);
		foreach(i;0..numFaces) mesh.indices[i]=[i,numFaces,(i+1)%numFaces];
		mesh.generateNormals(); // (doesn't actually need normals)
		B.finalizeMesh(mesh);
		texture=B.makeTexture(loadTXTR("extracted/main/MAIN.WAD!/bits.FLDR/aura.TXTR"));
		material=B.createMaterial(this);
	}

	float getAlpha(float lifetimeFraction){
		return 1.0f-lifetimeFraction;
	}
}

auto convertModel(B,Model)(string dir, Model model, float scaling){ // (uses GC)
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
		void setVertices(B.Mesh mesh,size_t frame){
			foreach(i,ref vertex;model.vertices[frame]){
				mesh.vertices[i] = fromSac(Vector3f(vertex.pos))*scaling;
			}
			foreach(i,ref vertex;model.vertices[frame]){
				mesh.texcoords[i] = Vector2f(vertex.uv);
			}
			foreach(i,ref vertex;model.vertices[frame]){
				mesh.normals[i] = fromSac(Vector3f(vertex.normal));
			}
		}
		enforce(model.vertices.length>=1);
		foreach(k,ref mesh;meshes){
			auto nvertices=model.vertices[0].length;
			mesh=B.makeMesh(nvertices,sizes[k]);
			setVertices(mesh,0);
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
	static if(is(typeof(model.vertices))){
		void setFaces(B.Mesh mesh,size_t k){
			mesh.indices[]=meshes[k].indices[];
		}
		auto frames=new B.Mesh[][](model.vertices.length);
		frames[0]=meshes;
		foreach(i;1..frames.length){
			frames[i]=new B.Mesh[](meshes.length);
			foreach(k;0..meshes.length){
				auto nvertices=model.vertices[i].length;
				frames[i][k]=B.makeMesh(nvertices,sizes[k]);
				setVertices(frames[i][k],i);
				setFaces(frames[i][k],k);
				B.finalizeMesh(frames[i][k]);
			}
		}
		return tuple(frames, textures);
	}else{
		return tuple(meshes, textures);
	}
}
