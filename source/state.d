// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import std.algorithm, std.range;
import std.exception, std.stdio, std.conv;
import dlib.math, dlib.math.portable, dlib.image.color;
import std.typecons;
import util, options: SpellSpec;
import sids, trig, ntts, nttData, bldg, sset;
import sacmap, sacobject, animations, sacspell;
import stats;
enum int updateFPS=60;
static assert(updateFPS%animFPS==0);
enum updateAnimFactor=updateFPS/animFPS;

struct Id{
	RenderMode mode;
	int type;
	int index=-1;
}

enum CreatureMode{
	idle,
	moving,
	dying,
	dead,
	deadToGhost,
	idleGhost,
	movingGhost,
	ghostToIdle,
	dissolving,
	preSpawning,
	spawning,
	reviving,
	fastReviving,
	takeoff,
	landing,
	meleeMoving,
	meleeAttacking,
	stunned,
	cower,
	casting,
	stationaryCasting,
	castingMoving,
	shooting,
	usingAbility,
	pulling,
	pumping,
	torturing,
	convertReviving,
	thrashing,
	pretendingToDie,
	playingDead,
	pretendingToRevive,
	rockForm,
}

bool isMoving(CreatureMode mode){
	with(CreatureMode) return !!mode.among(moving,movingGhost,meleeMoving,castingMoving);
}
bool isGhost(CreatureMode mode){
	with(CreatureMode) return !!mode.among(idleGhost,movingGhost);
}
bool isDying(CreatureMode mode){
	with(CreatureMode) return !!mode.among(dying,deadToGhost);
}
bool isAlive(CreatureMode mode){
	final switch(mode) with(CreatureMode){
		case idle,moving,idleGhost,movingGhost,ghostToIdle,spawning,takeoff,landing,meleeMoving,meleeAttacking,stunned,cower,casting,stationaryCasting,castingMoving,
			shooting,usingAbility,pulling,pumping,torturing,pretendingToDie,playingDead,pretendingToRevive,rockForm: return true;
		case dying,dead,deadToGhost,dissolving,preSpawning,reviving,fastReviving,convertReviving,thrashing: return false;
	}
}
bool isCasting(CreatureMode mode){
	with(CreatureMode) return !!mode.among(casting,stationaryCasting,castingMoving);
}
bool isShooting(CreatureMode mode){
	with(CreatureMode) return mode==shooting;
}
bool isUsingAbility(CreatureMode mode){
	with(CreatureMode) return mode==usingAbility;
}
bool isPulling(CreatureMode mode){
	with(CreatureMode) return mode==pulling;
}
bool isHidden(CreatureMode mode){
	with(CreatureMode) return !!mode.among(pretendingToDie,playingDead,rockForm);
}
bool isVisibleToAI(CreatureMode mode){
	final switch(mode) with(CreatureMode){
		case idle,moving,spawning,takeoff,landing,meleeMoving,meleeAttacking,stunned,cower,casting,stationaryCasting,castingMoving,shooting,usingAbility,pulling,pumping,torturing: return true;
		case dying,dead,deadToGhost,idleGhost,movingGhost,ghostToIdle,dissolving,preSpawning,reviving,fastReviving,pretendingToDie,playingDead,pretendingToRevive,rockForm,convertReviving,thrashing: return false;
	}
}
bool isVisibleToOtherSides(CreatureMode mode){
	final switch(mode) with(CreatureMode){
		case idle,moving,spawning,takeoff,landing,meleeMoving,meleeAttacking,stunned,cower,casting,stationaryCasting,castingMoving,
			shooting,usingAbility,pulling,pumping,torturing,convertReviving,thrashing: return true;
		case dying,dead,deadToGhost,idleGhost,movingGhost,ghostToIdle,dissolving,preSpawning,reviving,fastReviving,pretendingToDie,playingDead,pretendingToRevive,rockForm: return false;
	}
}
bool isObstacle(CreatureMode mode){
	final switch(mode) with(CreatureMode){
		case idle,moving,dying,spawning,reviving,fastReviving,takeoff,landing,meleeMoving,meleeAttacking,stunned,cower,casting,stationaryCasting,castingMoving,
			shooting,usingAbility,pulling,pumping,torturing,pretendingToDie,playingDead,pretendingToRevive,rockForm,convertReviving,thrashing: return true;
		case dead,dissolving,preSpawning: return false;
		case deadToGhost,idleGhost,movingGhost,ghostToIdle: return true; // ghost has interacting hitbox in original
	}
}
bool isProjectileObstacle(CreatureMode mode){
	final switch(mode) with(CreatureMode){
		case idle,moving,dying,spawning,reviving,fastReviving,takeoff,landing,meleeMoving,meleeAttacking,stunned,cower,casting,stationaryCasting,castingMoving,
			shooting,usingAbility,pulling,pumping,torturing,pretendingToDie,playingDead,pretendingToRevive,rockForm: return true;
		case convertReviving,thrashing: return false; // TODO: correct?
		case dead,dissolving,preSpawning: return false;
		case deadToGhost,idleGhost,movingGhost,ghostToIdle: return false;
	}
}
bool isValidAttackTarget(CreatureMode mode){
	final switch(mode) with(CreatureMode){
		case idle,moving,spawning,takeoff,landing,meleeMoving,meleeAttacking,stunned,cower,casting,stationaryCasting,castingMoving,shooting,usingAbility,pulling,pumping,torturing: return true;
		case dying,dead,dissolving,preSpawning,reviving,fastReviving,pretendingToDie,playingDead,pretendingToRevive,rockForm,convertReviving,thrashing: return false;
		case deadToGhost,idleGhost,movingGhost,ghostToIdle: return false;
	}
}
bool isValidGuardTarget(CreatureMode mode){
	final switch(mode) with(CreatureMode){
		case idle,moving,spawning,takeoff,landing,meleeMoving,meleeAttacking,stunned,cower,casting,stationaryCasting,castingMoving,
			shooting,usingAbility,pulling,rockForm,convertReviving,pumping,torturing,thrashing: return true;
		case dying,dead,dissolving,preSpawning,reviving,fastReviving,pretendingToDie,playingDead,pretendingToRevive: return false;
		case deadToGhost,idleGhost,movingGhost,ghostToIdle: return true;
	}
}
bool canKill(CreatureMode mode){
	final switch(mode) with(CreatureMode){
		case idle,moving,deadToGhost,idleGhost,movingGhost,ghostToIdle,spawning,takeoff,landing,meleeMoving,meleeAttacking,stunned,cower,casting,stationaryCasting,
			castingMoving,shooting,usingAbility,pulling,pumping,torturing,convertReviving,pretendingToDie,playingDead,pretendingToRevive,rockForm: return true;
		case dying,dead,dissolving,preSpawning,reviving,fastReviving,thrashing: return false; // TODO: check if reviving creatures die when owner surrenders
	}
}
bool canHeal(CreatureMode mode){
	final switch(mode) with(CreatureMode){
		case idle,moving,spawning,takeoff,landing,meleeMoving,meleeAttacking,stunned,cower,casting,stationaryCasting,castingMoving,
			shooting,usingAbility,pulling,pumping,torturing,pretendingToDie,playingDead,pretendingToRevive,rockForm: return true;
		case dying,dead,dissolving,preSpawning,reviving,fastReviving,convertReviving,thrashing: return false;
		case deadToGhost,idleGhost,movingGhost,ghostToIdle: return false;
	}
}
bool canRegenerateMana(CreatureMode mode){
	final switch(mode) with(CreatureMode){
		case idle,moving,spawning,takeoff,landing,meleeMoving,meleeAttacking,stunned,cower,casting,stationaryCasting,castingMoving,
			shooting,usingAbility,pulling,pumping,torturing,pretendingToDie,playingDead,pretendingToRevive,rockForm: return true;
		case dying,dead,dissolving,preSpawning,reviving,fastReviving,convertReviving,thrashing: return false;
		case deadToGhost: return false;
		case idleGhost,movingGhost,ghostToIdle: return true;
	}
}
bool canBePoisoned(CreatureMode mode){
	final switch(mode) with(CreatureMode){
		case idle,moving,spawning,takeoff,landing,meleeMoving,meleeAttacking,stunned,cower,casting,stationaryCasting,castingMoving,
			shooting,usingAbility,pulling,pumping,torturing,pretendingToDie,playingDead,pretendingToRevive,rockForm: return true;
		case dying,dead,dissolving,preSpawning,reviving,fastReviving,convertReviving,thrashing: return false;
		case deadToGhost,idleGhost,movingGhost,ghostToIdle: return false;
	}
}
bool canBeInfectedByMites(CreatureMode mode){ return canBePoisoned(mode); }
bool canBeStickyBombed(CreatureMode mode){ return canBePoisoned(mode); }
bool canBeOiled(CreatureMode mode){ return canBePoisoned(mode); }
bool canBeInfectedByFrogs(CreatureMode mode){ return canBePoisoned(mode); }
bool canBePetrified(CreatureMode mode){
	final switch(mode) with(CreatureMode){
		case idle,moving,spawning,takeoff,landing,meleeMoving,meleeAttacking,stunned,cower,casting,stationaryCasting,castingMoving,
			shooting,usingAbility,pulling,pumping,torturing,pretendingToDie,playingDead,pretendingToRevive,rockForm: return true;
		case dying,dead,dissolving,preSpawning,reviving,fastReviving,convertReviving,thrashing: return false;
		case deadToGhost,idleGhost,movingGhost,ghostToIdle: return false;
	}
}
bool canShield(CreatureMode mode){
	final switch(mode) with(CreatureMode){
		case idle,moving,spawning,takeoff,landing,meleeMoving,meleeAttacking,stunned,cower,casting,stationaryCasting,castingMoving,
			shooting,usingAbility,pulling,pumping,torturing,pretendingToDie,playingDead,pretendingToRevive,rockForm: return true;
		case dying,dead,dissolving,preSpawning,reviving,fastReviving,convertReviving,thrashing: return false;
		case deadToGhost,idleGhost,movingGhost,ghostToIdle: return false;
	}
}
bool canCC(CreatureMode mode){
	final switch(mode) with(CreatureMode){
		case idle,moving,spawning,takeoff,landing,meleeMoving,meleeAttacking,stunned,cower,casting,stationaryCasting,castingMoving,
			shooting,usingAbility,pulling,pumping,torturing,pretendingToDie,playingDead,pretendingToRevive,rockForm: return true;
		case dying,dead,dissolving,preSpawning,reviving,fastReviving,convertReviving,thrashing: return false;
		case deadToGhost,idleGhost,movingGhost,ghostToIdle: return false;
	}
}
bool canCollectSouls(CreatureMode mode){
	final switch(mode) with(CreatureMode){
		case idle,moving,ghostToIdle,spawning,takeoff,landing,meleeMoving,meleeAttacking,stunned,cower,casting,stationaryCasting,castingMoving,
			shooting,usingAbility,pulling,pumping,torturing,pretendingToDie,playingDead,pretendingToRevive,rockForm: return true;
		case dying,dead,deadToGhost,idleGhost,movingGhost,dissolving,preSpawning,reviving,fastReviving,convertReviving,thrashing: return false;
	}
}
bool canCatapult(CreatureMode mode){
	final switch(mode) with(CreatureMode){
		case idle,moving,dying,spawning,takeoff,meleeMoving,meleeAttacking,stunned,cower,casting,stationaryCasting,castingMoving,
			shooting,usingAbility,pulling,pumping,torturing,pretendingToDie,playingDead,pretendingToRevive,rockForm: return true;
		case ghostToIdle,landing,dead,deadToGhost,idleGhost,movingGhost,dissolving,preSpawning,reviving,fastReviving,convertReviving,thrashing: return false;
	}
}
bool canPush(CreatureMode mode){
	final switch(mode) with(CreatureMode){
		case idle,moving,dying,spawning,takeoff,landing,meleeMoving,meleeAttacking,stunned,cower,casting,stationaryCasting,castingMoving,
			shooting,usingAbility,pulling,pumping,torturing,pretendingToDie,playingDead,pretendingToRevive,rockForm: return true;
		case ghostToIdle,dead,deadToGhost,idleGhost,movingGhost,dissolving,preSpawning,reviving,fastReviving,convertReviving,thrashing: return false;
	}
}


enum CreatureMovement{
	onGround,
	flying,
	tumbling,
}

enum MovementDirection{
	none,
	forward,
	backward,
}

enum RotationDirection:ubyte{
	none,
	left,
	right,
}
enum PitchingDirection:ubyte{
	none,
	up,
	down,
}

struct CreatureState{
	auto mode=CreatureMode.idle;
	auto movement=CreatureMovement.onGround;
	float facing=0.0f, targetFlyingHeight=float.nan, flyingPitch=0.0f;
	auto movementDirection=MovementDirection.none;
	auto rotationDirection=RotationDirection.none;
	auto pitchingDirection=PitchingDirection.none;
	auto fallingVelocity=Vector3f(0.0f,0.0f,0.0f);
	auto speed=0.0f;
	auto rotationSpeedLimit=float.infinity; // for xy-plane only, in radians _per frame_
	auto pitchingSpeedLimit=float.infinity; // _in radians _per frame_
	int timer; // used for: constraining revive time to be at least 5s, time until casting finished
	int timer2; // used for: time until incantation finished
}

struct OrderTarget{
	TargetType type;
	int id;
	Vector3f position;
	this(TargetType type,int id,Vector3f position){
		this.type=type;
		this.id=id;
		this.position=position;
	}
	this(Target target){
		this(target.type,target.id,target.position);
	}
}
Vector3f center(B)(ref OrderTarget target,ObjectState!B state){
	if(target.type==TargetType.terrain||!state.isValidTarget(target.id)) return target.position;
	return state.objectById!((obj)=>obj.center)(target.id);
}
Vector3f lowCenter(B)(ref OrderTarget target,ObjectState!B state){
	if(target.type==TargetType.terrain||!state.isValidTarget(target.id)) return target.position;
	return state.objectById!((obj)=>obj.lowCenter)(target.id);
}
OrderTarget centerTarget(B)(int id,ObjectState!B state)in{
	assert(state.isValidTarget(id));
}do{
	auto position=state.objectById!((ref obj)=>obj.center)(id);
	return OrderTarget(state.targetTypeFromId(id),id,position);
}
OrderTarget positionTarget(B)(Vector3f position,ObjectState!B state){
	return OrderTarget(TargetType.terrain,0,position);
}

Vector3f[2] hitbox(B)(ref OrderTarget target,ObjectState!B state){
	if(target.type==TargetType.terrain||!state.isValidTarget(target.id)) return [target.position,target.position];
	return state.objectById!((obj)=>obj.hitbox)(target.id);
}

struct Order{
	CommandType command;
	OrderTarget target; // TODO: don't store TargetLocation in creature state
	float targetFacing=0.0f;
	auto formationOffset=Vector2f(0.0f,0.0f);
}

Vector3f getTargetPosition(B)(ref Order order,ObjectState!B state){
	auto targetPosition=order.target.position;
	auto targetFacing=order.targetFacing;
	auto formationOffset=order.formationOffset;
	return getTargetPosition(targetPosition,targetFacing,formationOffset,state);
}

Vector3f getTargetPosition(B)(ref Command!B command,Vector2f formationOffset,ObjectState!B state){
	auto targetPosition=command.target.position;
	auto targetFacing=command.targetFacing;
	return getTargetPosition(targetPosition,targetFacing,formationOffset,state);
}

Vector3f getTargetPosition(B)(Vector3f targetPosition,float targetFacing,Vector2f formationOffset,ObjectState!B state){
	targetPosition+=rotate(facingQuaternion(targetFacing), Vector3f(formationOffset.x,formationOffset.y,0.0f));
	targetPosition.z=state.getHeight(targetPosition);
	return targetPosition;
}

enum Formation{
	line,
	flankLeft,
	flankRight,
	phalanx,
	semicircle,
	circle,
	wedge,
	skirmish,
}

static getScale(T)(ref T obj){
	static if(is(T==MovingObject!B,B)){
		auto hitbox=obj.sacObject.largeHitbox(Quaternionf.identity(),AnimationState.stance1,0);
		return 0.5f*(hitbox[1].xy-hitbox[0].xy);
	}else static if(is(T==StaticObject!B,B)){
		auto hitbox=obj.hitbox;
		return 0.5f*(hitbox[1].xy-hitbox[0].xy);
	}else return 0.0f;
}
Vector2f[numCreaturesInGroup] getFormationOffsets(R)(R ids,CommandType commandType,Formation formation,Vector2f formationScale,Vector2f targetScale){
	auto unitDistance=1.75f*max(formationScale.x,formationScale.y);
	auto targetDistance=0.5f*(1.25f*unitDistance+max(targetScale.x,targetScale.y));
	if(targetDistance!=0.0f) targetDistance=max(targetDistance, unitDistance);
	auto numCreatures=ids.until(0).walkLength;
	Vector2f[numCreaturesInGroup] result=Vector2f(0,0);
	static immutable float sqrt2=sqrt(2.0f);
	final switch(formation){
		case Formation.line:
			auto offset=-0.5f*(numCreatures-1)*unitDistance;
			foreach(i;0..numCreatures) result[i]=Vector2f(offset+unitDistance*i,0.0f);
			if(targetDistance!=0.0f && commandType==commandType.guard){
				if(numCreatures&1){
					foreach(i;0..numCreatures){
						if(i<(numCreatures+1)/2) result[i].x-=targetDistance;
						else result[i].x+=targetDistance-unitDistance;
					}
				}else{
					foreach(i;0..numCreatures){
						if(i<numCreatures/2) result[i].x-=targetDistance-0.5f*unitDistance;
						else result[i].x+=targetDistance-0.5f*unitDistance;
					}
				}
			}
			break;
		case Formation.flankLeft:
			auto offset=-(numCreatures*unitDistance);
			foreach(i;0..numCreatures) result[i]=Vector2f(offset+unitDistance*i,0.0f);
			if(targetDistance!=0.0f && commandType!=commandType.attack){
				foreach(i;0..numCreatures)
					result[i].x-=targetDistance-unitDistance;
			}
			break;
		case Formation.flankRight:
			auto offset=unitDistance;
			foreach(i;0..numCreatures) result[i]=Vector2f(offset+unitDistance*i,0.0f);
			if(targetDistance!=0.0f && commandType!=commandType.attack){
				foreach(i;0..numCreatures)
					result[i].x+=targetDistance-unitDistance;
			}
			break;
		case Formation.phalanx:
			foreach(row;0..3){
				auto numCreaturesInRow=min(max(0,numCreatures-row*4),4);
				auto offset=Vector2f(-0.5f*(numCreaturesInRow-1)*unitDistance,-row*unitDistance);
				foreach(i;0..numCreaturesInRow) result[4*row+i]=offset+Vector2f(unitDistance*i,0.0f);
			}
			if(targetDistance!=0.0f && commandType==commandType.guard){
				foreach(i;0..numCreatures) result[i].y-=6.0f+targetDistance;
			}
			break;
		case Formation.semicircle:
			auto radius=max(targetDistance,0.5f*unitDistance,(numCreatures-1)*unitDistance/pi!float);
			foreach(i;0..numCreatures){
				auto angle=numCreatures==1?0.5f*pi!float:pi!float*i/(numCreatures-1);
				result[i]=radius*Vector2f(-cos(angle),-sin(angle));
			}
			break;
		case Formation.circle:
			auto radius=max(targetDistance,numCreatures*unitDistance/(2.0f*pi!float));
			foreach(i;0..numCreatures){
				auto angle=2.0f*pi!float*i/numCreatures;
				result[i]=radius*Vector2f(-cos(angle),-sin(angle));
			}
			break;
		case Formation.wedge:
			auto scale=max(unitDistance,targetDistance/1.5f);
			auto offset=Vector2f(0.0f,commandType==CommandType.attack?0.0f:3.0f*0.5f*sqrt2*scale);
			foreach(i;0..numCreatures/2+1)
				result[i]=offset-(numCreatures/2-i)*0.5f*Vector2f(sqrt2,sqrt2)*scale;
			foreach(i;numCreatures/2+1..numCreatures)
				result[i]=offset+(i-numCreatures/2)*0.5f*Vector2f(sqrt2,-sqrt2)*scale;
			break;
		case Formation.skirmish:
			auto offset=-0.5f*(numCreatures-1)*unitDistance;
			auto dist=0.5f*sqrt2*unitDistance;
			foreach(i;0..numCreatures) result[i]=Vector2f(offset+unitDistance*i,(i&1)?-dist:0.0f);
			if(targetDistance!=0.0f && commandType==commandType.guard){
				foreach(i;0..numCreatures) result[i].y+=targetDistance+dist;
			}
			break;
	}
	return result;
}

struct PositionPredictor{
	Vector3f lastPosition;
	void reset(){ lastPosition=Vector3f.init; }
	Vector3f predictAtTime(float timeToImpact,Vector3f targetPosition){
		if(isNaN(lastPosition.x)){
			lastPosition=targetPosition;
			return targetPosition;
		}
		auto velocity=updateFPS*(targetPosition-lastPosition);
		lastPosition=targetPosition;
		return targetPosition+velocity*timeToImpact;
	}
	Vector3f predictCenterAtTime(B)(float timeToImpact,OrderTarget target,ObjectState!B state){
		if(target.type==TargetType.terrain||!state.isValidTarget(target.id)) return target.position;
		return predictCenterAtTime(timeToImpact,target.id,state);
	}
	Vector3f predictCenterAtTime(B)(float timeToImpact,int targetId,ObjectState!B state)in{
		assert(state.isValidTarget(targetId));
	}do{
		static handle(T)(ref T obj,float timeToImpact,ObjectState!B state,PositionPredictor* self){
			auto hitboxCenter=boxCenter(obj.relativeHitbox);
			auto predictedPosition=self.predictAtTime(timeToImpact,obj.position);
			return predictedPosition+hitboxCenter;
		}
		return state.objectById!handle(targetId,timeToImpact,state,&this);
	}
	Vector3f predict(Vector3f position,float projectileSpeed,Vector3f targetPosition){
		if(isNaN(lastPosition.x)){
			lastPosition=targetPosition;
			return targetPosition;
		}
		auto velocity=updateFPS*(targetPosition-lastPosition);
		lastPosition=targetPosition;
		if(velocity==Vector3f(0.0f,0.0f,0.0f)) return targetPosition;
		auto remainingSpeedSqr=projectileSpeed^^2-velocity.lengthsqr;
		if(remainingSpeedSqr<=0) return targetPosition; // TODO: what does original do here?
		auto timeToImpact=sqrt((targetPosition-position).lengthsqr/remainingSpeedSqr);
		return targetPosition+velocity*timeToImpact;
	}
	Vector3f predictCenter(B)(Vector3f position,float projectileSpeed,ref OrderTarget target,ObjectState!B state){
		if(target.type==TargetType.terrain||!state.isValidTarget(target.id)) return target.position;
		return predictCenter(position,projectileSpeed,target.id,state);
	}
	Vector3f predictCenter(B)(Vector3f position,float projectileSpeed,int targetId,ObjectState!B state)in{
		assert(state.isValidTarget(targetId));
	}do{
		static handle(T)(ref T obj,Vector3f position,float projectileSpeed,ObjectState!B state,PositionPredictor* self){
			auto hitboxCenter=boxCenter(obj.relativeHitbox);
			auto predictedPosition=self.predict(position,projectileSpeed,obj.position);
			return predictedPosition+hitboxCenter;
		}
		return state.objectById!handle(targetId,position,projectileSpeed,state,&this);
	}
}

enum directWalkDistance=5.0f;
struct Path{
	Vector3f targetPosition;
	int age=0;
	private Array!Vector3f path;
	mixin Assign;
	void reset(){
		age=0;
		path.length=0;
		targetPosition=Vector3f.init;
	}
	Vector3f nextTarget(B)(Vector3f currentPosition,Vector3f[2] hitbox,Vector3f newTarget,float radius,bool frontOfAIQueue,ObjectState!B state){
		if((newTarget-targetPosition).lengthsqr>directWalkDistance^^2)
			reset();
		++age;
		if(frontOfAIQueue){
			if(targetPosition!=newTarget||age>2*updateFPS){
				if(state.findPath(path,currentPosition,newTarget,radius))
					targetPosition=newTarget;
				age=0;
			}
		}
		bool blocked(Vector3f position){
			bool collision=false;
			void handleCollision(ProximityEntry entry){ collision=true; }
			auto movedHitbox=hitbox;
			foreach(ref x;movedHitbox) x+=position;
			state.proximity.collide!handleCollision(movedHitbox);
			return collision;
		}
		while(path.length&&((path.back()-currentPosition).lengthsqr<2.0f*directWalkDistance^^2||blocked(path.back())))
			path.removeBack(1);
		if(path.length) return path.back();
		return newTarget;
	}
}
class PathFinder(B){
	bool[512][512] free;
	private static bool isFree(int x,int y,bool[][] edges){
		if(x<=0||y<=0||x+1>=xlen||y+1>=ylen) return false;
		int nx=x/2, ny=y/2;
		if(!(x&1)&&!(y&1)) return !edges[ny][nx]&&!edges[ny][nx-1]&&!edges[ny-1][nx]&&!edges[ny][nx+1]&&!edges[ny+1][nx];
		if((x&1)&&(y&1)) return !edges[ny][nx]&&!edges[ny][nx+1]&&!edges[ny+1][nx]&&!edges[ny+1][nx+1];
		if(x&1&&!(y&1)){
			if(edges[ny][nx]||edges[ny][nx+1]) return false;
			if((!ny||edges[ny-1][nx])&&(!ny||edges[ny-1][nx+1])) return false;
			if(edges[ny+1][nx]&&edges[ny+1][nx+1]) return false;
		}else{
			if(edges[ny][nx]||edges[ny+1][nx]) return false;
			if(edges[ny][nx-1]&&edges[ny+1][nx-1]) return false;
			if(edges[ny][nx+1]&&(ny+1>=256||edges[ny+1][nx+1])) return false;
		}
		return true;
	}
	float[512][512] heights;
	int numComponents=0;
	int[512][512] componentIds;

	void determineComponents(){
		foreach(ref c;componentIds) c[]=-1;
		static struct Entry{ short x,y; }
		Queue!Entry q;
		foreach(x;0..xlen){
			foreach(y;0..ylen){
				if(~componentIds[x][y]) continue;
				void fill(short x,short y,int id){
					if(~componentIds[x][y]||!free[x][y]) return;
					componentIds[x][y]=id;
					q.clear();
					q.push(Entry(x,y));
					while(!q.empty){
						auto xy=q.front;
						q.popFront();
						x=xy.x,y=xy.y;
						foreach(nx;max(0,x-1)..min(x+2,xlen)){
							foreach(ny;max(0,y-1)..min(y+2,ylen)){
								if(~componentIds[nx][ny]||!free[nx][ny]) continue;
								componentIds[nx][ny]=id;
								q.push(Entry(cast(short)nx,cast(short)ny));
							}
						}
					}
				}
				fill(cast(short)x,cast(short)y,numComponents++);
			}
		}
	}

	this(SacMap!B map){
		auto edges=map.edges;
		foreach(x;0..xlen){
			foreach(y;0..ylen){
				free[x][y]=isFree(x,y,edges);
			}
		}
		enum scale=directWalkDistance;
		foreach(x;0..xlen){
			foreach(y;0..ylen){
				heights[x][y]=map.getHeight(Vector3f(scale*x,scale*y,0.0f),ZeroDisplacement());
				// TODO: take into account dynamic heights
			}
		}
		determineComponents();
	}

	int getComponentId(Vector3f position,ObjectState!B state){
		auto xy=closestUnblocked(roundToGrid(position,state).expand,1,state),x=xy[0],y=xy[1];
		if(x<0||x>=xlen||y<0||y>=ylen) return -1;
		return componentIds[x][y];
	}

	static struct Entry{
		float heuristic;
		float distance;
		short x,y;
		bool less(ref Entry rhs){ return heuristic<rhs.heuristic; }
		//bool less(ref Entry rhs){ return distance<rhs.distance; }
	}
	ubyte[512][512] pred;
	float[512][512] dist;
	enum xlen=cast(int)dist.length, ylen=cast(int)dist[0].length;
	static Tuple!(short,"x",short,"y") roundToGrid(Vector3f position,ObjectState!B state){
		enum scale=1.0f/directWalkDistance;
		//int x=cast(int)round(scale*(position.x+position.y)-0.5f);
		//int y=cast(int)round(scale*(-position.x+position.y)+255.5f);
		short x=cast(short)round(scale*position.x);
		short y=cast(short)round(scale*position.y);
		x=max(cast(short)0,min(x,cast(short)(xlen-1)));
		y=max(cast(short)0,min(y,cast(short)(ylen-1)));
		return tuple!("x","y")(x,y);
	}
	Vector3f position(short x,short y,ObjectState!B state){
		enum scale=directWalkDistance;
		//auto a=scale*(0.5f*(x-y)+128.0f);
		//auto b=scale*(0.5f*(x+y)-127.5f);
		auto a=scale*x;
		auto b=scale*y;
		auto p=Vector3f(a,b,heights[x][y]);
		//p.z=state.getHeight(p);
		return p;
	}
	static bool unblocked(Vector3f position,ObjectState!B state){
		enum eps=1.0f;
		static immutable Vector3f[3] offsets=[Vector3f(-0.5f*eps,eps,0.0f),Vector3f(0.5f*eps,eps,0.0f),Vector3f(0.0f,-eps,0.0f)];
		foreach(ref off;offsets) if(!state.isOnGround(position+off)) return false;
		return true;
	}
	bool unblocked(short x,short y,ObjectState!B state){
		return free[x][y];
	}
	Tuple!(short,"x",short,"y") closestUnblocked(short x,short y,short limit,ObjectState!B state){
		int dist=int.max;
		short cx=x, cy=y;
		foreach(short nx;max(cast(short)0,cast(short)(x-limit))..min(cast(short)(x+limit+1),cast(short)xlen)){
			foreach(short ny;max(cast(short)0,cast(short)(y-limit))..min(cast(short)(y+limit+1),cast(short)ylen)){
				int cand=(nx-x)^^2+(ny-y)^^2;
				if(unblocked(nx,ny,state)&&cand<dist){
					cx=nx, cy=ny;
					dist=cand;
				}
			}
		}
		return tuple!("x","y")(cx,cy);
	}
	Heap!Entry heap;
	bool findPath(ref Array!Vector3f path,Vector3f start,Vector3f end,float radius,ObjectState!B state){
		if(path.length){ // check validity of existing path
			if((path.back-start).lengthsqr<8.0f*directWalkDistance^^2){
				bool ok=true;
				foreach(p;path.data){
					if(!unblocked(p,state)){
						ok=false;
						break;
					}
				}
				if(ok) return false;
			}
		}
		auto nstart=roundToGrid(start,state);
		auto nend=roundToGrid(end,state);
		if(!unblocked(nend.expand,state)){
			auto cand=closestUnblocked(nend.expand,2,state);
			if(nend==cand) return false; // TODO
			nend=cand;
		}
		auto endpos=position(nend.expand,state);
		if((start-end).lengthsqr<(end-endpos).lengthsqr){
			path.length=0;
			return true;
		}
		import std.datetime.stopwatch;
		/+auto sw=StopWatch(AutoStart.yes);
		scope(success){ writeln(sw.peek.total!"hnsecs"*1e-7*1e3,"ms"); }+/
		import core.stdc.string: memset;
		memset(&pred,0,pred.sizeof);
		foreach(ref d;dist) d[]=float.infinity;
		//writeln("memset: ",sw.peek.total!"hnsecs"*1e-7*1e3,"ms");
		heap.clear();
		heap.push(Entry(max(0.0f,(endpos-position(nstart.expand,state)).length-radius),0.0f,nstart.expand));
		pred[nstart.x][nstart.y]=0x7f;
		auto x=nstart.x,y=nstart.y;
		dist[x][y]=0.0f;
		enum limit=11000;
		for(int i=0;!heap.empty()&&i<limit;){
			auto cur=heap.pop();
			if(pred[cur.x][cur.y]&(1<<7)) continue;
			i++;
			pred[cur.x][cur.y]|=(1<<7);
			x=cur.x,y=cur.y;
			if(cur.x==nend.x&&cur.y==nend.y) break;
			auto pos=position(cur.x,cur.y,state);
			if(radius!=0.0f&&(pos-endpos).lengthsqr<radius^^2) break;
			foreach(nx;max(cast(short)0,cast(short)(cur.x-1))..min(cast(short)(cur.x+2),cast(short)xlen)){
				foreach(ny;max(cast(short)0,cast(short)(cur.y-1))..min(cast(short)(cur.y+2),cast(short)ylen)){
					if(cur.x==nx&&cur.y==ny) continue;
					if(pred[nx][ny]&(1<<7)) continue;
					if(!unblocked(nx,ny,state)) continue;
					auto npos=position(nx,ny,state);
					//if(!unblocked(npos,state)) continue;
					auto distance=cur.distance+(pos-npos).length;
					//auto distance=cur.heuristic-max(0.0f,(endpos-pos).length-radius)+(pos-npos).length;
					auto heuristic=distance+max(0.0f,(endpos-npos).length-radius);
					if(heuristic>=dist[nx][ny]) continue;
					dist[nx][ny]=heuristic;
					pred[nx][ny]=cast(ubyte)(((x-nx+1)<<2)+(y-ny+1));
					heap.push(Entry(heuristic,distance,nx,ny));
				}
			}
		}
		heap.clear();
		path.length=0;
		for(;;){
			path~=position(x,y,state);
			if(x==nstart.x&&y==nstart.y) break;
			if(!(pred[x][y]&(1<<7))) break;
			auto dx=((pred[x][y]&((1<<7)-1))>>2)-1;
			auto dy=((pred[x][y]&((1<<7)-1))&3)-1;
			x+=dx,y+=dy;
		}
		return true;
	}
}

struct CreatureAI{
	Order order;
	Queue!Order orderQueue;
	Formation formation;
	bool isColliding=false;
	RotationDirection evasion;
	int evasionTimer=0;
	int targetId=0;
	PositionPredictor predictor;
	bool isOnAIQueue=false;
	Path path;
	mixin Assign;
}

struct MovingObject(B){
	SacObject!B sacObject;
	int id=0;
	Vector3f position;
	Quaternionf rotation;
	AnimationState animationState;
	int frame;
	CreatureAI creatureAI;
	CreatureState creatureState;
	CreatureStats creatureStats;
	int side=0;
	int soulId=0;
	mixin Assign;

	this(SacObject!B sacObject,Vector3f position,Quaternionf rotation,AnimationState animationState,int frame,CreatureState creatureState,CreatureStats creatureStats,int side){
		this.sacObject=sacObject;
		this.position=position;
		this.rotation=rotation;
		this.animationState=animationState;
		this.frame=frame;
		this.creatureState=creatureState;
		this.creatureStats=creatureStats;
		this.side=side;
	}
	this(SacObject!B sacObject,int id,Vector3f position,Quaternionf rotation,AnimationState animationState,int frame,CreatureState creatureState,CreatureStats creatureStats,int side){
		this.id=id;
		this(sacObject,position,rotation,animationState,frame,creatureState,creatureStats,side);
	}
	this(SacObject!B sacObject,int id,Vector3f position,Quaternionf rotation,AnimationState animationState,int frame,CreatureAI creatureAI,CreatureState creatureState,CreatureStats creatureStats,int side,int soulId){
		this.creatureAI=move(creatureAI);
		this.soulId=soulId;
		this(sacObject,id,position,rotation,animationState,frame,creatureState,creatureStats,side);
	}
}
int side(B)(ref MovingObject!B object,ObjectState!B state){
	return object.side;
}
float health(B)(ref MovingObject!B object){
	return object.creatureStats.health;
}
float health(B)(ref MovingObject!B object,ObjectState!B state){
	return object.health;
}
void health(B)(ref MovingObject!B object,float value){
	object.creatureStats.health=value;
}
enum ghostSpeedFactor=1.75f;
float speedOnGround(B)(ref MovingObject!B object,ObjectState!B state){
	return (object.isGhost?ghostSpeedFactor:1.0f)*object.creatureStats.movementSpeed(false);
}
float speedInAir(B)(ref MovingObject!B object,ObjectState!B state){
	return object.creatureStats.movementSpeed(true);
}
float speed(B)(ref MovingObject!B object,ObjectState!B state){
	return object.creatureState.movement==CreatureMovement.flying?object.speedInAir(state):object.speedOnGround(state);
}
float takeoffTime(B)(ref MovingObject!B object,ObjectState!B state){
	return object.sacObject.takeoffTime;
}
float accelerationOnGround(B)(ref MovingObject!B object,ObjectState!B state){
	return object.creatureStats.movementAcceleration(false);
}
float accelerationInAir(B)(ref MovingObject!B object,ObjectState!B state){
	return object.creatureStats.movementAcceleration(true);
}
float acceleration(B)(ref MovingObject!B object,ObjectState!B state){
	return object.creatureState.movement==CreatureMovement.flying?object.accelerationInAir(state):object.accelerationOnGround(state);
}

bool isWizard(B)(ref MovingObject!B obj){ return obj.sacObject.isWizard; }
bool isPeasant(B)(ref MovingObject!B obj){ return obj.sacObject.isPeasant; }
bool isSacDoctor(B)(ref MovingObject!B obj){ return obj.sacObject.isSacDoctor; }
bool isHero(B)(ref MovingObject!B obj){ return obj.sacObject.isHero; }
bool isFamiliar(B)(ref MovingObject!B obj){ return obj.sacObject.isFamiliar; }

bool isShielded(B)(ref MovingObject!B obj){ return obj.creatureStats.effects.shielded; }
bool isCCProtected(B)(ref MovingObject!B obj){ return obj.creatureStats.effects.ccProtected; }
bool isHealBlocked(B)(ref MovingObject!B obj){ return obj.creatureStats.effects.healBlocked; }
bool isGuardian(B)(ref MovingObject!B obj){ return obj.creatureStats.effects.isGuardian; }

bool canSelect(B)(ref MovingObject!B obj,int side,ObjectState!B state){
	return obj.side==side&&!obj.isWizard&&!obj.isPeasant&&!obj.isSacDoctor&&!obj.creatureState.mode.among(CreatureMode.dead,CreatureMode.dissolving,CreatureMode.convertReviving,CreatureMode.thrashing);
}
bool canSelect(B)(int side,int id,ObjectState!B state){
	return state.movingObjectById!(canSelect,()=>false)(id,side,state);
}
bool canOrder(B)(ref MovingObject!B obj,int side,ObjectState!B state){
	return (side==-1||obj.side==side&&!obj.isSacDoctor)&&!obj.creatureState.mode.among(CreatureMode.dead,CreatureMode.dissolving);
}
bool isPacifist(B)(ref MovingObject!B obj,ObjectState!B state){
	return obj.sacObject.isPacifist;
}
bool isAggressive(B)(ref MovingObject!B obj,ObjectState!B state){
	if(obj.isPacifist(state)) return false;
	if(obj.creatureStats.effects.stealth) return false;
	return true;
}
float aggressiveRange(B)(ref MovingObject!B obj,ObjectState!B state){
	return obj.sacObject.aggressiveRange;
}
float guardAggressiveRange(B)(ref MovingObject!B obj,ObjectState!B state){
	return obj.sacObject.guardAggressiveRange;
}
float advanceAggressiveRange(B)(ref MovingObject!B obj,ObjectState!B state){
	return obj.sacObject.advanceAggressiveRange;
}
float guardRange(B)(ref MovingObject!B obj,ObjectState!B state){
	return obj.sacObject.guardRange;
}

bool isMeleeAttacking(B)(ref MovingObject!B obj,ObjectState!B state){
	return !!obj.creatureState.mode.among(CreatureMode.meleeAttacking,CreatureMode.meleeMoving);
}
void select(B)(MovingObject!B obj,ObjectState!B state){
	state.addToSelection(obj.side,obj.id);
}
void unselect(B)(MovingObject!B obj,ObjectState!B state){
	state.removeFromSelection(obj.side,obj.id);
}
void removeFromGroups(B)(MovingObject!B obj,ObjectState!B state){
	state.removeFromGroups(obj.side,obj.id);
}
Vector3f[2] relativeHitbox(B)(ref MovingObject!B object){
	return object.sacObject.hitbox(object.rotation,object.animationState,object.frame/updateAnimFactor);
}
Vector3f[2] hitbox(B)(ref MovingObject!B object){
	auto hitbox=object.relativeHitbox;
	hitbox[0]+=object.position;
	hitbox[1]+=object.position;
	return hitbox;
}
Vector3f[2] closestHitbox(B)(ref MovingObject!B object,Vector3f position){
	return object.hitbox;
}
Vector3f[2] hitbox2d(B)(ref MovingObject!B object,Matrix4f modelViewProjectionMatrix){
	return object.sacObject.hitbox2d(object.animationState,object.frame/updateAnimFactor,modelViewProjectionMatrix);
}

Vector3f relativeCenter(T)(ref T object){
	auto hbox=object.relativeHitbox;
	return 0.5f*(hbox[0]+hbox[1]);
}

Vector3f center(T)(ref T object){
	static if(is(T==Soul!B,B)){
		return object.position+0.5f*object.scaling;
	}else{
		auto hbox=object.hitbox;
		return 0.5f*(hbox[0]+hbox[1]);
	}
}
Vector3f lowCenter(T)(ref T object){
	auto hbox=object.hitbox;
	return Vector3f(0.5f*(hbox[0].x+hbox[1].x),0.5f*(hbox[0].y+hbox[1].y),0.25f*(3.0f*hbox[0].z+hbox[1].z));
}
Vector3f[2] relativeMeleeHitbox(B)(ref MovingObject!B object){
	return object.sacObject.meleeHitbox(object.rotation,object.animationState,object.frame/updateAnimFactor);
}
Vector3f[2] meleeHitbox(B)(ref MovingObject!B object){
	auto hitbox=object.relativeMeleeHitbox;
	hitbox[0]+=object.position;
	hitbox[1]+=object.position;
	return hitbox;
}

Vector3f soulPosition(B)(ref MovingObject!B object){
	return object.center+rotate(object.rotation,object.sacObject.soulDisplacement);
}

float meleeStrength(B)(ref MovingObject!B object){
	return object.sacObject.meleeStrength;
}

Vector3f[2] hands(B)(ref MovingObject!B object){
	auto hands=object.sacObject.hands(object.animationState,object.frame/updateAnimFactor);
	foreach(ref hand;hands) hand=object.position+rotate(object.rotation,hand);
	return hands;
}

Vector3f randomHand(B)(Vector3f[2] hands,ObjectState!B state){
	if(isNaN(hands[0].x)) return hands[1];
	if(isNaN(hands[1].x)) return hands[0];
	return hands[state.uniform(2)];
}

Vector3f[2] needle(B)(ref MovingObject!B object){
	auto needle=object.sacObject.needle(object.animationState,object.frame/updateAnimFactor);
	needle[0]=object.position+rotate(object.rotation,needle[0]);
	needle[1]=rotate(object.rotation,needle[1]);
	return needle;
}

Vector3f shotPosition(B)(ref MovingObject!B object){
	auto loc=object.sacObject.shotPosition(object.animationState,object.frame/updateAnimFactor);
	return object.position+rotate(object.rotation,loc);
}
Vector3f[2] basiliskShotPositions(B)(ref MovingObject!B object){ return object.hands; }

SacObject!B.LoadedArrow loadedArrow(B)(ref MovingObject!B object){
	auto result=object.sacObject.loadedArrow(object.animationState,object.frame/updateAnimFactor);
	foreach(ref pos;result.tupleof) pos=object.position+rotate(object.rotation,pos);
	return result;
}
AnimationState shootAnimation(B)(ref MovingObject!B object,bool isAbility){
	final switch(object.creatureState.movement) with(CreatureMovement){
		case onGround:
			return isAbility?AnimationState.shoot1:AnimationState.shoot0;
		case flying:
			if(object.sacObject.mustFly)
				goto case onGround;
			return AnimationState.flyShoot;
		case tumbling:
			goto case onGround;
	}
}
Vector3f firstShotPosition(B)(ref MovingObject!B object,bool isAbility){
	auto loc=object.sacObject.firstShotPosition(object.shootAnimation(isAbility));
	return object.position+rotate(object.rotation,loc);
}

int numAttackTicks(B)(ref MovingObject!B object){
	return object.sacObject.numAttackTicks(object.animationState);
}

int slowdownFactor(B)(ref MovingObject!B object){
	return 4^^min(10,object.creatureStats.effects.numSlimes);
}

bool hasAttackTick(B)(ref MovingObject!B object,ObjectState!B state){
	if(state.frame%object.slowdownFactor) return false;
	return object.frame%updateAnimFactor==0 && object.sacObject.hasAttackTick(object.animationState,object.frame/updateAnimFactor);
}

SacSpell!B rangedAttack(B)(ref MovingObject!B object){ return object.sacObject.rangedAttack; }

bool hasLoadTick(B)(ref MovingObject!B object,ObjectState!B state){
	if(state.frame%object.slowdownFactor) return false;
	return object.frame%updateAnimFactor==0 && object.sacObject.hasLoadTick(object.animationState,object.frame/updateAnimFactor);
}

int numShootTicks(B)(ref MovingObject!B object){
	return object.sacObject.numShootTicks(object.animationState);
}

bool hasShootTick(B)(ref MovingObject!B object,ObjectState!B state){
	if(state.frame%object.slowdownFactor) return false;
	return object.frame%updateAnimFactor==0 && object.sacObject.hasShootTick(object.animationState,object.frame/updateAnimFactor);
}

SacSpell!B ability(B)(ref MovingObject!B object){
	if(object.isGuardian||object.isDying) return null;
	return object.sacObject.ability;
}
SacSpell!B passiveAbility(B)(ref MovingObject!B object){ return object.sacObject.passiveAbility; }

StunnedBehavior stunnedBehavior(B)(ref MovingObject!B object){
	return object.sacObject.stunnedBehavior;
}

bool isRegenerating(B)(ref MovingObject!B object){
	return (object.creatureState.mode.among(CreatureMode.idle,CreatureMode.playingDead,CreatureMode.rockForm)
	        ||object.creatureState.mode==CreatureMode.moving&&object.creatureState.movement==CreatureMovement.flying
	        ||object.sacObject.continuousRegeneration&&object.creatureState.mode.canHeal)
		&& !object.creatureStats.effects.regenerationBlocked;
}

bool isDamaged(B)(ref MovingObject!B object){
	return object.health<=0.25f*object.creatureStats.maxHealth;
}

bool isHidden(B)(ref MovingObject!B object){
	if(object.creatureState.mode.isHidden) return true;
	if(object.creatureStats.effects.stealth) return true;
	return false;
}

enum StaticObjectFlags{
	none=0,
	hovering=1<<0,
}

struct StaticObject(B){
	SacObject!B sacObject;
	int id=0;
	int buildingId=0;
	Vector3f position;
	Quaternionf rotation;
	float scale;
	int flags;
	this(SacObject!B sacObject,int buildingId,Vector3f position,Quaternionf rotation,float scale,int flags){
		this.sacObject=sacObject;
		this.buildingId=buildingId;
		this.position=position;
		this.rotation=rotation;
		this.scale=scale;
		this.flags=flags;
	}
	this(SacObject!B sacObject,int id,int buildingId,Vector3f position,Quaternionf rotation,float scale,int flags){
		this.id=id;
		this(sacObject,buildingId,position,rotation,scale,flags);
	}
}
float healthFromBuildingId(B)(int buildingId,ObjectState!B state){
	return state.buildingById!((ref b)=>b.health,()=>0.0f)(buildingId);
}
float health(B)(ref StaticObject!B object,ObjectState!B state){
	return healthFromBuildingId(object.buildingId,state);
}
int sideFromBuildingId(B)(int buildingId,ObjectState!B state){
	return state.buildingById!((ref b)=>b.side,()=>-1)(buildingId);
}
int flagsFromBuildingId(B)(int buildingId,ObjectState!B state){
	return state.buildingById!((ref b)=>b.flags,()=>0)(buildingId);
}
bool isActive(B)(ref StaticObject!B object,ObjectState!B state){
	return !(flagsFromBuildingId(object.buildingId,state)&AdditionalBuildingFlags.inactive);
}
int side(B)(ref StaticObject!B object,ObjectState!B state){
	return sideFromBuildingId(object.buildingId,state);
}
auto relativeHitboxes(B)(ref StaticObject!B object){
	return object.sacObject.hitboxes(object.rotation);
}
auto hitboxes(B)(ref StaticObject!B object){
	return object.sacObject.hitboxes(object.rotation).zip(repeat(object.position)).map!(function Vector3f[2](x)=>[x[0][0]+x[1],x[0][1]+x[1]]);
}

Vector3f[2] relativeHitbox(B)(ref StaticObject!B object){
	Vector3f[2] result=[Vector3f(float.max,float.max,float.max),Vector3f(-float.max,-float.max,-float.max)];
	foreach(hitbox;object.relativeHitboxes){
		foreach(i;0..3){
			result[0][i]=min(result[0][i],hitbox[0][i]);
			result[1][i]=max(result[1][i],hitbox[1][i]);
		}
	}
	if(result[1].z>=0) result[0].z=max(result[0].z,0.0f);
	return result;
}
Vector3f[2] closestHitbox(B)(ref StaticObject!B object,Vector3f position){
	Vector3f[2] result;
	auto resultDistSqr=float.infinity;
	foreach(hitbox;object.hitboxes){
		if(hitbox[1].z>=0) hitbox[0].z=max(hitbox[0].z,object.position.z);
		auto candDistSqr=(boxCenter(hitbox)-position).lengthsqr;
		if(candDistSqr<resultDistSqr){
			result=hitbox;
			resultDistSqr=candDistSqr;
		}
	}
	return result;
}
Vector3f[2] hitbox(B)(ref StaticObject!B object){
	auto hitbox=object.relativeHitbox;
	hitbox[0]+=object.position;
	hitbox[1]+=object.position;
	return hitbox;
}
Vector3f[2] hitbox2d(B)(ref StaticObject!B object,Matrix4f modelViewProjectionMatrix){
	return object.sacObject.hitbox2d(object.rotation,modelViewProjectionMatrix);
}

struct FixedObject(B){
	SacObject!B sacObject;
	Vector3f position;
	Quaternionf rotation;

	this(SacObject!B sacObject,Vector3f position,Quaternionf rotation){
		this.sacObject=sacObject;
		this.position=position;
		this.rotation=rotation;
	}
}


enum SoulState{
	normal,
	emerging,
	reviving,
	collecting,
	devouring,
}

struct Soul(B){
	int id=0;
	int creatureId=0;
	int preferredSide=-1;
	int collectorId=0;
	int number;
	Vector3f position;
	SoulState state;
	uint convertSideMask=-1;
	int frame=0;
	float facing=0.0f;
	float scaling=1.0f;

	this(int number,Vector3f position,SoulState state){
		this.number=number;
		this.position=position;
		this.state=state;
		if(state==SoulState.emerging) scaling=0.0f;
	}
	this(int creatureId,int preferredSide,int number,Vector3f position,SoulState state){
		this.creatureId=creatureId;
		this.preferredSide=preferredSide;
		this(number,position,state);
	}
	this(int id,int creatureId,int preferredSide,int number,Vector3f position,SoulState state){
		this.id=id;
		this.preferredSide=preferredSide;
		this(creatureId,preferredSide,number,position,state);
	}
}

int side(B)(ref Soul!B soul,ObjectState!B state){
	if(soul.creatureId==0&&soul.collectorId==0) return -1;
	return soul.preferredSide;
}
int soulSide(B)(int id,ObjectState!B state){
	return state.soulById!(side,()=>-1)(id,state);
}
SoulColor color(B)(ref Soul!B soul,int side,ObjectState!B state){
	auto soulSide=soul.side(state);
	return soulSide==-1||soulSide==side?SoulColor.blue:SoulColor.red;
}
SoulColor color(B)(int id,int side,ObjectState!B state){
	return state.soulById!(color,()=>SoulColor.red)(id,side,state);
}

Vector3f[2] hitbox2d(B)(ref Soul!B soul,Matrix4f modelViewProjectionMatrix){
	auto topLeft=Vector3f(-SacSoul!B.soulWidth/2,-SacSoul!B.soulHeight/2,0.0f)*soul.scaling;
	auto bottomRight=-topLeft;
	return [transform(modelViewProjectionMatrix,topLeft),transform(modelViewProjectionMatrix,bottomRight)];
}

enum AdditionalBuildingFlags{
	none=0,
	inactive=32, // TODO: make sure this doesn't clash with anything
	occupied=64, // TODO: make sure this doesn't clash with anything
}
struct Building(B){
	immutable(Bldg)* bldg; // TODO: replace by SacBuilding class
	int id=0;
	int side;
	Array!int componentIds;
	int flags=0;
	float facing=0.0f;
	int top=0;
	int base=0;
	float health=0.0f;
	enum regeneration=80.0f;
	enum meleeResistance=1.5f;
	enum directSpellResistance=1.0f;
	enum splashSpellResistance=1.0f;
	enum directRangedResistance=1.0f;
	enum splashRangedResistance=1.0f;
	Array!int guardianIds;
	mixin Assign;
	this(immutable(Bldg)* bldg,int side,int flags,float facing){
		this.bldg=bldg;
		this.side=side;
		this.flags=flags;
		this.facing=facing;
		this.health=bldg.maxHealth;
	}
}
int maxHealth(B)(ref Building!B building,ObjectState!B state){
	return building.bldg.maxHealth;
}
Vector3f position(B)(ref Building!B building,ObjectState!B state){
	return state.staticObjectById!((obj)=>obj.position,()=>Vector3f.init)(building.componentIds[0]);
}
float height(B)(ref Building!B building,ObjectState!B state){
	float maxZ=0.0f;
	foreach(cid;building.componentIds){
		state.staticObjectById!((obj,state){
			auto hitbox=obj.hitbox;
			maxZ=max(maxZ,hitbox[1].z-obj.position.z);
		},(){})(cid,state);
	}
	return maxZ;
}
// TODO: the following functionality is duplicated in SacObject
bool isManafount(immutable(Bldg)* bldg){ // TODO: store in SacBuilding class
	return bldg.header.numComponents==1&&manafountTags.canFind(bldg.components[0].tag);
}
bool isManafount(B)(ref Building!B building){
	return building.bldg.isManafount;
}
bool isManalith(immutable(Bldg)* bldg){ // TODO: store in SacBuilding class
	return bldg.header.numComponents==1&&manalithTags.canFind(bldg.components[0].tag);
}
bool isManalith(B)(ref Building!B building){
	return building.bldg.isManalith;
}
bool isShrine(immutable(Bldg)* bldg){ // TODO: store in SacBuilding class
	return bldg.header.numComponents==1&&shrineTags.canFind(bldg.components[0].tag);
}
bool isShrine(B)(ref Building!B building){
	return building.bldg.isShrine;
}
bool isAltar(immutable(Bldg)* bldg){ // TODO: store in SacBuilding class
	return bldg.header.numComponents>=1&&altarBaseTags.canFind(bldg.components[0].tag);
}
bool isAltar(B)(ref Building!B building){
	return building.bldg.isAltar;
}
bool isStratosAltar(immutable(Bldg)* bldg){ // TODO: store in SacBuilding class
	return bldg.header.numComponents>=1&&bldg.components[0].tag=="tprc";
}
bool isStratosAltar(B)(ref Building!B building){
	return building.bldg.isStratosAltar;
}
bool isEtherealAltar(immutable(Bldg)* bldg){ // TODO: store in SacBuilding class
	return bldg.header.numComponents>=1&&bldg.components[0].tag=="b_ae";
}
bool isEtherealAltar(B)(ref Building!B building){
	return building.bldg.isEtherealAltar;
}
bool isPeasantShelter(immutable(Bldg)* bldg){
	return !!(bldg.header.flags&BldgFlags.shelter)||bldg.isAltar;
}
bool isPeasantShelter(B)(ref Building!B building){
	return building.bldg.isPeasantShelter;
}

void putOnManafount(B)(ref Building!B building,ref Building!B manafount,ObjectState!B state)in{
	assert(manafount.isManafount);
	assert(building.base==0);
}do{
	if(manafount.top!=0) freeManafount(manafount,state); // original engine associates last building with the fountain
	manafount.top=building.id;
	building.base=manafount.id;
	manafount.deactivate(state);
}
void freeManafount(B)(ref Building!B manafount,ObjectState!B state)in{
	assert(manafount.isManafount);
	assert(manafount.top!=0);
}do{
	state.buildingById!((ref obj){ assert(obj.base==manafount.id); obj.base=0; },(){})(manafount.top);
	manafount.top=0;
	manafount.activate(state);
}
void loopingSoundSetup(B)(ref Building!B building,ObjectState!B state){
	static if(B.hasAudio){
		if(building.flags&AdditionalBuildingFlags.inactive) return;
		if(playAudio){
			foreach(cid;building.componentIds)
				state.staticObjectById!(B.loopingSoundSetup,(){})(cid);
		}
	}
}
void stopSounds(B)(ref Building!B building,ObjectState!B state){
	static if(B.hasAudio){
		if(playAudio){
			foreach(cid;building.componentIds)
				stopSoundsAt(cid,state);
		}
	}
}
void activate(B)(ref Building!B building,ObjectState!B state){
	if(!(building.flags&AdditionalBuildingFlags.inactive)) return;
	building.flags&=~AdditionalBuildingFlags.inactive;
	loopingSoundSetup(building,state);
}
void deactivate(B)(ref Building!B building,ObjectState!B state){
	if(building.flags&AdditionalBuildingFlags.inactive) return;
	building.flags|=AdditionalBuildingFlags.inactive;
	building.stopSounds(state);
}

struct Particle(B,bool relative=false,bool sideFiltered=false){ // TODO: some particles don't need some fields. Optimize?
	SacParticle!B sacParticle;
	static if(relative){
		int baseId;
		bool rotate;
	}
	Vector3f position;
	Vector3f velocity;
	float scale;
	int lifetime;
	int frame;
	static if(sideFiltered) int sideFilter; // TODO: spread into one array per side?
	static if(relative){
		this(SacParticle!B sacParticle,int baseId,bool rotate,Vector3f position,Vector3f velocity,float scale,int lifetime,int frame){
			this.sacParticle=sacParticle;
			this.baseId=baseId;
			this.rotate=rotate;
			this.position=position;
			this.velocity=velocity;
			this.scale=scale;
			this.lifetime=lifetime;
			this.frame=frame;
		}
	}else{
		this(SacParticle!B sacParticle,Vector3f position,Vector3f velocity,float scale,int lifetime,int frame){
			this.sacParticle=sacParticle;
			this.position=position;
			this.velocity=velocity;
			this.scale=scale;
			this.lifetime=lifetime;
			this.frame=frame;
		}
	}
}

struct MovingObjects(B,RenderMode mode){
	enum renderMode=mode;
	SacObject!B sacObject;
	Array!int ids;
	Array!Vector3f positions;
	Array!Quaternionf rotations;
	Array!AnimationState animationStates;
	Array!int frames;
	Array!CreatureAI creatureAIs;
	Array!CreatureState creatureStates;
	Array!CreatureStats creatureStatss;
	Array!int sides;
	Array!int soulIds;
	static if(mode==RenderMode.transparent){
		Array!float alphas;
		Array!float energies;
	}
	mixin Assign;

	@property int length(){ assert(ids.length<=int.max); return cast(int)ids.length; }
	@property void length(int l){
		ids.length=l;
		positions.length=l;
		rotations.length=l;
		animationStates.length=l;
		frames.length=l;
		creatureAIs.length=l;
		creatureStates.length=l;
		creatureStatss.length=l;
		sides.length=l;
		soulIds.length=l;
		static if(mode==RenderMode.transparent){
			alphas.length=l;
			energies.length=l;
		}
	}

	void reserve(int reserveSize){
		ids.reserve(reserveSize);
		positions.reserve(reserveSize);
		rotations.reserve(reserveSize);
		animationStates.reserve(reserveSize);
		frames.reserve(reserveSize);
		creatureAIs.reserve(reserveSize);
		creatureStates.reserve(reserveSize);
		creatureStatss.reserve(reserveSize);
		sides.reserve(reserveSize);
		soulIds.reserve(reserveSize);
		static if(mode==RenderMode.transparent){
			alphas.reserve(reserveSize);
			energies.reserve(reserveSize);
		}
	}

	void addObject(MovingObject!B object)in{
		assert(object.id!=0);
		assert(!sacObject||sacObject is object.sacObject);
	}do{
		sacObject=object.sacObject;
		ids~=object.id;
		positions~=object.position;
		rotations~=object.rotation;
		animationStates~=object.animationState;
		frames~=object.frame;
		creatureAIs~=object.creatureAI;
		creatureStates~=object.creatureState;
		creatureStatss~=object.creatureStats;
		sides~=object.side;
		soulIds~=object.soulId;
		static if(mode==RenderMode.transparent){
			alphas~=1.0f;
			energies~=1.0f;
		}
	}
	void removeObject(int index, ref ObjectManager!B manager){
		manager.ids[ids[index]-1]=Id.init;
		if(index+1<length){
			this[index]=this.fetch(length-1); // TODO: swap?
			static if(mode==RenderMode.transparent)
				alphas[index]=alphas[length-1];
			manager.ids[ids[index]-1].index=index;
		}
		length=length-1;
	}
	MovingObject!B fetch(int i){
		return MovingObject!B(sacObject,ids[i],positions[i],rotations[i],animationStates[i],frames[i],move(creatureAIs[i]),creatureStates[i],creatureStatss[i],sides[i],soulIds[i]);
	}
	void opIndexAssign(MovingObject!B obj,int i)in{
		assert(obj.sacObject is sacObject);
	}do{
		ids[i]=obj.id;
		positions[i]=obj.position;
		rotations[i]=obj.rotation;
		animationStates[i]=obj.animationState;
		frames[i]=obj.frame;
		creatureAIs[i]=move(obj.creatureAI);
		creatureStates[i]=obj.creatureState;
		creatureStatss[i]=obj.creatureStats; // TODO: this might be a bit wasteful
		sides[i]=obj.side;
		soulIds[i]=obj.soulId;
	}
	static if(mode==RenderMode.transparent){
		void setAlpha(int i,float alpha,float energy){
			alphas[i]=alpha;
			energies[i]=energy;
		}
	}
}
auto each(alias f,B,RenderMode mode,T...)(ref MovingObjects!(B,mode) movingObjects,T args){
	foreach(i;0..movingObjects.length){
		auto obj=movingObjects.fetch(i);
		f(obj,args);
		movingObjects[i]=move(obj);
	}
}

struct StaticObjects(B,RenderMode mode){
	enum renderMode=mode;
	SacObject!B sacObject;
	Array!int ids;
	Array!int buildingIds;
	Array!Vector3f positions;
	Array!Quaternionf rotations;
	Array!float scales;
	Array!int flagss;
	static if(mode==RenderMode.transparent){
		Array!float thresholdZs;
	}
	mixin Assign;
	@property int length(){ assert(ids.length<=int.max); return cast(int)ids.length; }
	@property void length(int l){
		ids.length=l;
		buildingIds.length=l;
		positions.length=l;
		rotations.length=l;
		scales.length=l;
		static if(mode==RenderMode.transparent)
			thresholdZs.length=l;
	}
	void addObject(StaticObject!B object)in{
		assert(object.id!=0);
		assert(!sacObject||sacObject is object.sacObject);
	}do{
		sacObject=object.sacObject;
		ids~=object.id;
		buildingIds~=object.buildingId;
		positions~=object.position;
		rotations~=object.rotation;
		scales~=object.scale;
		flagss~=object.flags;
		static if(mode==RenderMode.transparent)
			thresholdZs~=0.0f;
	}
	void removeObject(int index, ref ObjectManager!B manager){
		manager.ids[ids[index]-1]=Id.init;
		if(index+1<length){
			this[index]=this[length-1];
			static if(mode==RenderMode.transparent)
				thresholdZs[index]=thresholdZs[length-1];
			manager.ids[ids[index]-1].index=index;
		}
		length=length-1;
	}
	StaticObject!B fetch(int i){
		return StaticObject!B(sacObject,ids[i],buildingIds[i],positions[i],rotations[i],scales[i],flagss[i]);
	}
	StaticObject!B opIndex(int i){
		return StaticObject!B(sacObject,ids[i],buildingIds[i],positions[i],rotations[i],scales[i],flagss[i]);
	}
	void opIndexAssign(StaticObject!B obj,int i){
		assert(sacObject is obj.sacObject);
		ids[i]=obj.id;
		buildingIds[i]=obj.buildingId;
		positions[i]=obj.position;
		rotations[i]=obj.rotation;
		scales[i]=obj.scale;
		flagss[i]=obj.flags;
	}
	static if(mode==RenderMode.transparent){
		void setThresholdZ(int i,float thresholdZ){
			thresholdZs[i]=thresholdZ;
		}
	}
}
auto each(alias f,B,RenderMode mode,T...)(ref StaticObjects!(B,mode) staticObjects,T args){
	foreach(i;0..staticObjects.length){
		auto obj=staticObjects.fetch(i);
		f(obj,args);
		staticObjects[i]=move(obj);
	}
}

struct FixedObjects(B){
	enum renderMode=RenderMode.opaque;
	SacObject!B sacObject;
	Array!Vector3f positions;
	Array!Quaternionf rotations;
	mixin Assign;
	@property int length(){ assert(positions.length<=int.max); return cast(int)positions.length; }

	void addFixed(FixedObject!B object)in{
		assert(sacObject==object.sacObject);
	}do{
		positions~=object.position;
		rotations~=object.rotation;
	}
	FixedObject!B opIndex(int i){
		return FixedObject!B(sacObject,positions[i],rotations[i]);
	}
}
auto each(alias f,B,T...)(ref FixedObjects!B fixedObjects,T args){
	foreach(i;0..length)
		f(fixedObjects[i],args);
}

struct Souls(B){
	Array!(Soul!B) souls;
	mixin Assign;
	@property int length(){ return cast(int)souls.length; }
	@property void length(int l){ souls.length=l; }
	void addObject(Soul!B soul){
		souls~=soul;
	}
	void removeObject(int index, ref ObjectManager!B manager){
		manager.ids[souls[index].id-1]=Id.init;
		if(index+1<length){
			this[index]=move(this[length-1]);
			manager.ids[souls[index].id-1].index=index;
		}
		length=length-1;
	}
	ref Soul!B opIndex(int i){
		return souls[i];
	}
}
auto each(alias f,B,T...)(ref Souls!B souls,T args){
	foreach(i;0..souls.length)
		f(souls[i],args);
}

struct Buildings(B){
	Array!(Building!B) buildings;
	mixin Assign;
	@property int length(){ return cast(int)buildings.length; }
	@property void length(int l){ buildings.length=l; }
	void addObject(Building!B building){
		buildings~=move(building);
	}
	void removeObject(int index, ref ObjectManager!B manager){
		manager.ids[buildings[index].id-1]=Id.init;
		if(index+1<length){
			swap(this[index],this[length-1]); // TODO: reuse memory?
			manager.ids[buildings[index].id-1].index=index;
		}
		length=length-1;
	}
	ref Building!B opIndex(int i){
		return buildings[i];
	}
}
auto each(alias f,B,T...)(ref Buildings!B buildings,T args){
	foreach(i;0..buildings.length){
		static if(!is(typeof(f(Building.init,args)))){
			// TODO: find a better way to check whether argument taken by reference
			f(buildings[i],args);
		}else static assert(false);
	}
}

enum maxLevel=9;

struct SpellInfo(B){
	SacSpell!B spell;
	int level;
	float cooldown;
	float maxCooldown;
	bool ready=true;
	int readyFrame=16*updateAnimFactor;
	void setCooldown(float newCooldown){
		if(cooldown==0.0f||newCooldown>maxCooldown) maxCooldown=newCooldown;
		if(newCooldown>cooldown) cooldown=newCooldown;
	}
}
struct Spellbook(B){
	Array!(SpellInfo!B) spells;
	mixin Assign;
	void addSpell(int level,SacSpell!B spell){
		spells~=SpellInfo!B(spell,level,0.0f,0.0f);
		if(spells.length>=2&&spells[$-1].spell.spellOrder<spells[$-2].spell.spellOrder) sort();
	}
	void sort(){
		.sort!"a.spell.spellOrder<b.spell.spellOrder"(spells.data);
	}
	SpellInfo!B[] getSpells(){
		return spells.data;
	}
}
enum SpellStatus{
	inexistent,
	disabled,
	invalidTarget,
	lowOnMana,
	mustBeNearBuilding,
	mustBeNearEnemyAltar,
	mustBeConnectedToConversion,
	needMoreSouls,
	outOfRange,
	notReady,
	ready,
}

immutable(SpellSpec)[][God.max+1] computeDefaultSpells(){
	import std.traits:EnumMembers;
	typeof(return) result;
	foreach(god;[EnumMembers!God]){
		char[4] workaround(SpellTag tag){ return [tag[0],tag[1],tag[2],tag[3]]; } // ???
		foreach(tag;neutralCreatures)
			result[god]~=SpellSpec(0,workaround(tag));
		foreach(tag;neutralSpells)
			result[god]~=SpellSpec(0,workaround(tag));
		foreach(tag;structureSpells[0..$-1])
			result[god]~=SpellSpec(0,workaround(tag));
		if(god==God.none){
			result[god]~=SpellSpec(3,workaround(structureSpells[$-1]));
			continue;
		}
		enforce(creatureSpells[god].length==11);
		enforce(normalSpells[god].length==11);
		foreach(lv;1..9+1){
			if(lv==3) result[god]~=SpellSpec(3,workaround(structureSpells[$-1]));
			if(lv==1){
				foreach(tag;creatureSpells[god][1..4])
					result[god]~=SpellSpec(lv,workaround(tag));
				result[god]~=SpellSpec(lv,workaround(normalSpells[god][lv+1]));
			}else if(lv<8){
				result[god]~=SpellSpec(lv,workaround(creatureSpells[god][lv+2]));
				result[god]~=SpellSpec(lv,workaround(normalSpells[god][lv+1]));
			}else if(lv==8){
				foreach(tag;normalSpells[god][9..11])
					result[god]~=SpellSpec(lv,workaround(tag));
			}else if(lv==9){
				result[god]~=SpellSpec(lv,workaround(creatureSpells[god][lv+1]));
			}
		}
	}
	return result;
}

immutable defaultSpells=computeDefaultSpells();

immutable(SpellSpec)[] randomSpells(){
	import std.random;
	char[4] workaround(SpellTag tag){ return [tag[0],tag[1],tag[2],tag[3]]; } // ???
	God god(){ return cast(God)uniform!"[]"(1,cast(int)God.max); }
	typeof(return) result;
	foreach(tag;neutralCreatures)
		result~=SpellSpec(0,workaround(tag));
	foreach(tag;neutralSpells)
		result~=SpellSpec(0,workaround(tag));
	foreach(tag;structureSpells[0..$-1])
		result~=SpellSpec(0,workaround(tag));
	enforce(creatureSpells[god].length==11);
	enforce(normalSpells[god].length==11);
	foreach(lv;1..9+1){
		if(lv==3) result~=SpellSpec(3,workaround(structureSpells[$-1]));
		if(lv==1){
			foreach(i;1..4){
				auto tag=creatureSpells[god][i];
				result~=SpellSpec(lv,workaround(tag));
			}
			result~=SpellSpec(lv,workaround(normalSpells[god][lv+1]));
		}else if(lv<8){
			result~=SpellSpec(lv,workaround(creatureSpells[god][lv+2]));
			result~=SpellSpec(lv,workaround(normalSpells[god][lv+1]));
		}else if(lv==8){
			foreach(i;9..11){
				auto tag=normalSpells[god][i];
				result~=SpellSpec(lv,workaround(tag));
			}
		}else if(lv==9){
			result~=SpellSpec(lv,workaround(creatureSpells[god][lv+1]));
		}
	}
	return result;
}

Spellbook!B getSpellbook(B)(const(SpellSpec)[] spells){
	Spellbook!B result;
	foreach(spec;spells) result.addSpell(spec.level,SacSpell!B.get(spec.tag));
	return result;
}

Spellbook!B getDefaultSpellbook(B)(God god){
	return getSpellbook!B(defaultSpells[god]);
}

struct WizardInfo(B){
	int id;
	string name=null;
	int level;
	int souls;
	float experience;
	Spellbook!B spellbook;
	int closestBuilding=0;
	int closestShrine=0;
	int closestAltar=0;
	int closestEnemyAltar=0;
	mixin Assign;

	void addSpell(int level,SacSpell!B spell){
		spellbook.addSpell(level,spell);
	}
	auto getSpells(){
		return spellbook.getSpells();
	}
}
void applyCooldown(B)(ref WizardInfo!B wizard,SacSpell!B spell,ObjectState!B state){
	enum spellGenericCooldown=1.0f;
	enum buildingGenericCooldown=1.0f;
	enum spellAdditionalCooldown=1.5f;
	enum buildingAdditionalCooldown=0.5f;
	auto genericCooldown=spell.isBuilding?buildingGenericCooldown:spellGenericCooldown;
	auto additionalCooldown=spell.isBuilding?buildingAdditionalCooldown:spellAdditionalCooldown;
	auto spellCooldown=spell.castingTime(wizard.level)+spell.cooldown+additionalCooldown;
	auto otherCooldown=spell.castingTime(wizard.level)+genericCooldown+additionalCooldown;
	foreach(ref entry;wizard.spellbook.spells.data){
		if(entry.spell is spell) entry.setCooldown(spellCooldown);
		else entry.setCooldown(otherCooldown);
	}
}
WizardInfo!B makeWizard(B)(int id,string name,int level,int souls,Spellbook!B spellbook,ObjectState!B state){
	state.movingObjectById!((ref wizard,level,state){
		wizard.creatureStats.maxHealth+=50.0f*level;
		wizard.creatureStats.health+=50.0f*level;
		wizard.creatureStats.mana+=100*level;
		wizard.creatureStats.maxMana+=100*level;
		// TODO: boons
	},(){ assert(0); })(id,level,state);
	return WizardInfo!B(id,name,level,souls,0.0f,move(spellbook));
}

int placeCreature(B)(ObjectState!B state,SacObject!B sacObject,int flags,int side,Vector3f position,float facing){
	bool onGround=state.isOnGround(position);
	if(onGround)
		position.z=state.getGroundHeight(position);
	auto mode=CreatureMode.idle;
	auto movement=CreatureMovement.onGround;
	if(movement==CreatureMovement.onGround && !onGround)
		movement=sacObject.canFly?CreatureMovement.flying:CreatureMovement.tumbling;
	if(movement==CreatureMovement.onGround&&sacObject.mustFly)
		movement=CreatureMovement.flying;
	auto creatureState=CreatureState(mode, movement, facing);
	import animations;
	auto rotation=facingQuaternion(facing);
	auto obj=MovingObject!B(sacObject,position,rotation,AnimationState.stance1,0,creatureState,sacObject.creatureStats(flags),side);
	obj.setCreatureState(state);
	obj.updateCreaturePosition(state);
	return state.addObject(obj);
}

int placeCreature(T=Creature,B)(ObjectState!B state,char[4] tag,int flags,int side,Vector3f position,float facing){
	return state.placeCreature(SacObject!B.getSAXS!T(tag),flags,side,position,facing);
}

int placeWizard(B)(ObjectState!B state,SacObject!B wizard,string name,int flags,int side,int level,int souls,Spellbook!B spellbook,Vector3f position,float facing){
	auto id=state.placeCreature(wizard,flags,side,position,facing);
	state.addWizard(makeWizard(id,name,level,souls,move(spellbook),state));
	return id;
}

enum wizardAltarDistance=15.0f;
int placeWizard(B)(ObjectState!B state,SacObject!B wizard,string name,int flags,int side,int level,int souls,Spellbook!B spellbook)in{
	assert(wizard.isWizard);
}do{
	bool flag=false;
	int id=0;
	state.eachBuilding!((ref bldg,state,id,wizard,name,flags,side,level,souls,spellbook){
		if(*id||bldg.componentIds.length==0) return;
		if(bldg.side==side && bldg.isAltar){
			auto altar=state.staticObjectById!((obj)=>obj, function StaticObject!B(){ assert(0); })(bldg.componentIds[0]);
			int closestManafount=0;
			Vector3f manafountPosition;
			state.eachBuilding!((bldg,altarPos,closest,manaPos,state){
				if(bldg.componentIds.length==0||!bldg.isManafount) return;
				auto pos=bldg.position(state);
				if(*closest==0||(altarPos-pos).length<(altarPos-*manaPos).length){
					*closest=bldg.id;
					*manaPos=pos;
				}
			})(altar.position,&closestManafount,&manafountPosition,state);
			enum distance=wizardAltarDistance;
			float facing;
			Vector3f position;
			if(closestManafount){
				auto dir2d=(manafountPosition-altar.position).xy.normalized*distance;
				if(dir2d.x==0.0f&&dir2d.y==0.0f) dir2d=Vector2f(0.0f,1.0f);
				facing=atan2(-dir2d.x,dir2d.y);
				position=altar.position+Vector3f(dir2d.x,dir2d.y,0.0f);
			}else{
				auto facingOffset=(bldg.isStratosAltar?pi!float/4.0f:0.0f)+pi!float;
				facing=bldg.facing+facingOffset;
				position=altar.position+rotate(facingQuaternion(facing),Vector3f(0.0f,distance,0.0f));
			}
			*id=state.placeWizard(wizard,name,flags,side,level,souls,move(spellbook),position,facing);
		}
	})(state,&id,wizard,name,flags,side,level,souls,move(spellbook));
	return id;
}

struct WizardInfos(B){
	Array!(WizardInfo!B) wizards;
	mixin Assign;
	@property int length(){ assert(wizards.length<=int.max); return cast(int)wizards.length; }
	@property void length(int l){
		wizards.length=l;
	}
	void addWizard(ref WizardInfo!B wizard){
		wizards~=wizard;
	}
	void addWizard(WizardInfo!B wizard){
		wizards~=move(wizard);
	}
	void removeWizard(int id){
		auto index=indexForId(id);
		if(index!=-1){
			if(index+1<wizards.length)
				swap(wizards[index],wizards[$-1]); // TODO: reuse memory?
			wizards.length=wizards.length-1;
		}
	}
	ref WizardInfo!B opIndex(int i){
		return wizards[i];
	}
	int indexForId(int id){
		foreach(i;0..wizards.length) if(wizards[i].id==id) return cast(int)i;
		return -1;
	}
	int indexForSide(int side,ObjectState!B state){
		foreach(i;0..wizards.length){
			if(state.movingObjectById!(.side,()=>-1)(wizards[i].id,state)==side)
			   return cast(int)i;
		}
		return -1;
	}
	WizardInfo!B* getWizard(int id){
		auto index=indexForId(id);
		if(index==-1) return null;
		return &wizards[index];
	}
	WizardInfo!B* getWizardForSide(int side,ObjectState!B state){
		auto index=indexForSide(side,state);
		if(index==-1) return null;
		return &wizards[index];
	}
}
auto each(alias f,B,T...)(ref WizardInfos!B wizards,T args){
	foreach(i;0..wizards.length)
		f(wizards[i],args);
}

struct Particles(B,bool relative,bool sideFiltered=false){
	SacParticle!B sacParticle;
	static if(relative){
		Array!int baseIds;
		//Array!bool rotates; // TODO: support Array!bool serialization?
		Array!ubyte rotates; // TODO: store as a bit in baseId?
	}
	Array!Vector3f positions;
	Array!Vector3f velocities;
	Array!float scales;
	Array!int lifetimes;
	Array!int frames;
	static if(sideFiltered) Array!int sideFilters;
	mixin Assign;
	@property int length(){ assert(positions.length<=int.max); return cast(int)positions.length; }
	@property void length(int l){
		static if(relative){
			baseIds.length=l;
			rotates.length=l;
		}
		positions.length=l;
		velocities.length=l;
		scales.length=l;
		lifetimes.length=l;
		frames.length=l;
		static if(sideFiltered) sideFilters.length=l;
	}
	void reserve(int reserveSize){
		static if(relative){
			baseIds.reserve(reserveSize);
			rotates.reserve(reserveSize);
		}
		positions.reserve(reserveSize);
		velocities.reserve(reserveSize);
		scales.reserve(reserveSize);
		lifetimes.reserve(reserveSize);
		frames.reserve(reserveSize);
		static if(sideFiltered) sideFilters.reserve(reserveSize);
	}
	void addParticle(Particle!(B,relative,sideFiltered) particle){
		assert(sacParticle is null && particle.sacParticle.relative==relative || sacParticle is particle.sacParticle);
		sacParticle=particle.sacParticle; // TODO: get rid of this?
		static if(relative){
			baseIds~=particle.baseId;
			rotates~=particle.rotate;
		}
		positions~=particle.position;
		velocities~=particle.velocity;
		scales~=particle.scale;
		lifetimes~=particle.lifetime;
		frames~=particle.frame;
		static if(sideFiltered) sideFilters~=particle.sideFilter;
	}
	void removeParticle(int index){
		if(index+1<length) this[index]=this[length-1];
		length=length-1;
	}
	Particle!(B,relative,sideFiltered) opIndex(int i){
		static if(sideFiltered){
			static if(relative) return Particle!(B,true,true)(sacParticle,baseIds[i],!!rotates[i],positions[i],velocities[i],scales[i],lifetimes[i],frames[i],sideFilters[i]);
			else{ auto r=Particle!(B,false,true)(sacParticle,positions[i],velocities[i],scales[i],lifetimes[i],frames[i]); r.sideFilter=sideFilters[i]; return r; }
		}else{
			static if(relative) return Particle!(B,true)(sacParticle,baseIds[i],!!rotates[i],positions[i],velocities[i],scales[i],lifetimes[i],frames[i]);
			else return Particle!(B,false)(sacParticle,positions[i],velocities[i],scales[i],lifetimes[i],frames[i]);
		}
	}
	void opIndexAssign(Particle!(B,relative,sideFiltered) particle,int i){
		assert(particle.sacParticle is sacParticle);
		static if(relative){
			baseIds[i]=particle.baseId;
			rotates[i]=particle.rotate;
		}
		positions[i]=particle.position;
		velocities[i]=particle.velocity;
		scales[i]=particle.scale;
		lifetimes[i]=particle.lifetime;
		frames[i]=particle.frame;
		static if(sideFiltered) sideFilters[i]=particle.sideFilter;
	}
}

struct Debris(B){
	Vector3f position; // TODO: better representation?
	Vector3f velocity;
	Quaternionf rotationUpdate;
	Quaternionf rotation;
}
struct Explosion(B){
	Vector3f position;
	float scale,maxScale,expansionSpeed;
	int frame;
}
struct Fire(B){
	int target;
	int lifetime;
	float rangedDamagePerFrame=0.0f;
	float spellDamagePerFrame=0.0f;
	float manaDrainPerFrame=0.0f;
	int attacker=0;
	int side=-1;
	DamageMod damageMod;
}
struct ManaDrain(B){
	int wizard;
	float manaCostPerFrame;
	int timer;
}
struct BuildingDestruction{ int id; }
struct GhostKill{ int id; }
struct CreatureCasting(B){
	ManaDrain!B manaDrain;
	SacSpell!B spell;
	int creature;
}
struct StructureCasting(B){
	God god;
	ManaDrain!B manaDrain;
	SacSpell!B spell;
	int building;
	float buildingHeight;
	int castingTime;
	int currentFrame;
}
struct BlueRing(B){
	Vector3f position;
	float scale=1.0f;
	int frame=0;
}

struct RedVortex{
	Vector3f position;
	float scale=0.0f;
	int frame=0;
	enum radius=2.5f;
	static assert(updateFPS==60);
	enum numFramesToEmerge=120;
	enum numFrames=120;
	enum numFramesToDisappear=60;
	enum convertHeight=15.0f;
	enum convertDistance=20.0f;
	enum desecrateHeight=15.0f;
	enum desecrateDistance=12.5f;
}

enum RitualType{
	convert,
	desecrate,
}

struct SacDocCasting(B){
	RitualType type;
	int side;
	ManaDrain!B manaDrain;
	SacSpell!B spell;
	int target;
	int targetShrine;
	Vector3f landingPosition;
	RedVortex vortex;
	bool underway=true;
	bool interrupted=false;
}

struct SacDocTether{
	enum m=5;
	Vector3f[m] locations;
	Vector3f[m] velocities;
	Vector3f[2] get(float t){ return cintp(locations[],t); }
}

enum SacDocCarryStatus{
	fall,
	bounce,
	walkToTarget,
	pump,
	move,
	shrinking,
}

struct SacDocCarry(B){
	RitualType type;
	int side;
	SacSpell!B spell;
	int caster;
	int sacDoctor;
	int soul;
	int creature;
	int targetShrine;
	SacDocTether tether;
	SacDocCarryStatus status;
	int timer;
	int frame=0;
	float vortexScale=0.0f;
	static assert(updateFPS==60);
	enum numFramesToEmerge=60;
	enum numFramesToDisappear=45;
}

struct Ritual(B){
	RitualType type;
	Vector3f start;
	int side;
	SacSpell!B spell;
	int caster;
	int shrine;
	int[4] sacDoctors;
	int creature;
	RedVortex vortex;
	int targetWizard;
	SacDocTether[4] tethers;
	LightningBolt[2] altarBolts;
	LightningBolt[3] desecrateBolts;
	enum setupTime=5*updateFPS;
	int frame=0;
	bool stopped=false;
	Vector3f shrinePosition;
}

struct TeleportCasting(B){
	ManaDrain!B manaDrain;
	SacSpell!B spell;
	int target;
	Vector3f targetPosition;
}
struct TeleportEffect(B){
	bool isTeleportOut;
	Vector3f position;
	float scale;
	float height;
	int frame=0;
}
struct TeleportRing(B){
	Vector3f position;
	float scale;
	int frame=0;
}
struct GuardianCasting(B){
	ManaDrain!B manaDrain;
	SacSpell!B spell;
	int creature;
}
enum GuardianStatus{
	appearing,
	steady,
	disappearingAtBuilding,
	disappearingAtCreature,
}
struct Guardian{
	int creature;
	int building;
	GuardianStatus status;
	int frame=0;
	enum numFramesToEmerge=updateFPS;
	enum numFramesToDisappear=updateFPS;
	enum numFramesToChangeShape=updateFPS;
	enum pulseFrames=updateFPS/2;
	Vector3f start, end;
	enum m=5;
	Vector3f[m] locations, prevLocs, nextLocs;
	enum locRadius=0.75f;
	Vector3f[2] get(float t){ return cintp(locations[],t); }
}
struct SpeedUp(B){
	int creature;
	int framesLeft;
}
struct SpeedUpShadow(B){
	int creature;
	Vector3f position;
	Quaternionf rotation;
	AnimationState animationState;
	int frame;
	int age=0;
}
struct HealCasting(B){
	ManaDrain!B manaDrain;
	SacSpell!B spell;
	int creature;
}
struct Heal(B){
	int creature;
	float healthRegenerationPerFrame;
	int timer;
}
struct LightningCasting(B){
	ManaDrain!B manaDrain;
	SacSpell!B spell;
	OrderTarget target;
}
enum numLightningSegments=10;
struct LightningBolt{
	Vector3f[numLightningSegments+1] displacement;
	void changeShape(float size=2.5f,B,T...)(ObjectState!B state,T sizeFactor) if(T.length<=1){
		foreach(k,ref disp;displacement){
			static immutable Vector3f[2] box=[-0.5f*size*Vector3f(1.0f,1.0f,1.0f),0.5f*size*Vector3f(1.0f,1.0f,1.0f)];
			disp=Vector3f(0.0f,0.0f,10.0f*k/numLightningSegments);
			static if(!sizeFactor.length) enum factor=1.0f;
			else auto factor=sizeFactor[0];
			if(0<k&&k<numLightningSegments) disp+=factor*state.uniform(box);
		}
	}
	Vector3f get(float t){
		return lintp(displacement[],t)[0];
	}
}
struct Lightning(B){
	enum totalFrames=64;
	enum changeShapeDelay=6;
	enum travelDelay=12;
	int wizard;
	int side;
	OrderTarget start,end;
	SacSpell!B spell;
	DamageMod damageMod;
	int frame;
	this(int wizard,int side,OrderTarget start,OrderTarget end,SacSpell!B spell,DamageMod damageMod,int frame){
		this.wizard=wizard;
		this.side=side;
		this.start=start;
		this.end=end;
		this.spell=spell;
		this.damageMod=damageMod;
		this.frame=frame;
	}
	LightningBolt[2] bolts;
}
struct WrathCasting(B){
	ManaDrain!B manaDrain;
	SacSpell!B spell;
	OrderTarget target;
}
enum WrathStatus{
	flying,
	exploding,
}
struct Wrath(B){
	int wizard;
	int side;
	Vector3f position;
	Vector3f velocity;
	OrderTarget target;
	SacSpell!B spell;
	auto status=WrathStatus.flying;
	int frame=0;
	PositionPredictor predictor;
}
struct FireballCasting(B){
	ManaDrain!B manaDrain;
	Fireball!B fireball;
	int frame=0;
}
struct Fireball(B){
	int wizard;
	int side;
	Vector3f position; // TODO: better representation?
	Vector3f velocity;
	OrderTarget target;
	SacSpell!B spell;
	Quaternionf rotationUpdate;
	Quaternionf rotation;
	PositionPredictor predictor;
}
struct RockCasting(B){
	ManaDrain!B manaDrain;
	SacSpell!B spell;
	Rock!B rock;
	int frame;
	int castingTime;
}
struct Rock(B){
	int wizard;
	int side;
	Vector3f position; // TODO: better representation?
	Vector3f velocity;
	OrderTarget target;
	SacSpell!B spell;
	Quaternionf rotationUpdate;
	Quaternionf rotation;
	int frame=0;
}
struct SwarmCasting(B){
	ManaDrain!B manaDrain;
	SacSpell!B spell;
	Swarm!B swarm;
}
struct Bug(B){
	Vector3f position;
	Vector3f velocity;
	Vector3f targetPosition;
	enum scale=1.0f; // TODO
	enum alpha=1.0f; // TODO
}
enum SwarmStatus{
	casting,
	flying,
	dispersing,
}
struct Swarm(B){
	int wizard;
	int side;
	Vector3f position;
	Vector3f velocity;
	OrderTarget target;
	SacSpell!B spell;
	int frame;
	auto status=SwarmStatus.casting;
	PositionPredictor predictor;
	Array!(Bug!B) bugs; // TODO: pull out bugs into separate array?
}

struct SkinOfStoneCasting(B){
	ManaDrain!B manaDrain;
	SacSpell!B spell;
	int frame;
	int castingTime;
	float scale;
}

struct SkinOfStone(B){
	int target;
	SacSpell!B spell;
	int frame=0;
}

enum EtherealFormStatus{ fadingOut, stationary, fadingIn }
struct EtherealFormCasting(B){
	ManaDrain!B manaDrain;
	SacSpell!B spell;
}

struct EtherealForm(B){
	int target;
	SacSpell!B spell;
	int frame=0;
	enum targetAlpha=0.36f;
	enum targetEnergy=10.0f;
	float progress=0.0f;
	EtherealFormStatus status;
	enum numFrames=30;
}

struct FireformCasting(B){
	ManaDrain!B manaDrain;
	SacSpell!B spell;
	int frame;
	int castingTime;
	int soundTimer;
}
struct Fireform(B){
	int target;
	SacSpell!B spell;
	int frame;
	int soundTimer;
}

struct ProtectiveSwarmCasting(B){
	ManaDrain!B manaDrain;
	SacSpell!B spell;
	ProtectiveSwarm!B protectiveSwarm;
}
struct ProtectiveBug(B){
	Vector3f position;
	Vector3f startPosition;
	Vector3f targetPosition;
	float scale=1.0f;
	int frame;
	float progress=0.0f;
	enum alpha=1.0f; // TODO?
}
enum ProtectiveSwarmStatus{
	casting,
	steady,
	dispersing,
}
struct ProtectiveSwarm(B){
	int target;
	SacSpell!B spell;
	int castingTime;
	int soundTimer;
	int frame=0;
	float alpha=1.0f;
	auto status=ProtectiveSwarmStatus.casting;
	Array!(ProtectiveBug!B) bugs; // TODO: pull out bugs into separate array?
}

struct AirShieldCasting(B){
	ManaDrain!B manaDrain;
	int castingTime;
	AirShield!B airShield;
}
enum AirShieldStatus{ growing, stationary, shrinking }
struct AirShield(B){
	int target;
	SacSpell!B spell;
	int frame=0;
	float scale=0.0f;
	AirShieldStatus status;
	struct Particle{
		float height;
		float radius;
		float θ;
		int frame=0;
	}
	Array!Particle particles;
}

struct FreezeCasting(B){
	ManaDrain!B manaDrain;
	SacSpell!B spell;
	int creature;
}
struct Freeze(B){
	int creature;
	SacSpell!B spell;
	int wizard;
	int side;
	int timer;
	float scale=0.0f;
	enum numFramesToAppear=updateFPS/2;
}

struct RingsOfFireCasting(B){
	ManaDrain!B manaDrain;
	SacSpell!B spell;
	int creature;
}
struct RingsOfFire(B){
	int creature;
	SacSpell!B spell;
	int wizard;
	int side;
	int timer;
	int soundTimer=0;
}

struct SlimeCasting(B){
	ManaDrain!B manaDrain;
	SacSpell!B spell;
	int creature;
	int castingTime;
	bool finishedCasting=false;
	float progress=0.0f;
	enum heightOffset=10.0f;
	enum progressThreshold=0.85f;
}
struct Slime(B){
	int creature;
	SacSpell!B spell;
	int timer;
}

struct GraspingVinesCasting(B){
	ManaDrain!B manaDrain;
	SacSpell!B spell;
	int creature;
}
struct Vine{
	enum m=4;
	Vector3f base,target;
	float scale;
	static import std.math;
	enum growthFactor=std.math.exp(std.math.log(0.7f)/updateFPS);
	Vector3f[m] locations;
	Vector3f[m] velocities;
	Vector3f[2] get(float t){ return cintp(locations[],t); }
}
struct GraspingVines(B){
	int creature;
	SacSpell!B spell;
	int timer;
	Vine[16] vines;
	bool active=true;
	float lengthFactor=0.1f;
	enum growthTime=updateFPS;
	enum vanishTime=updateFPS;
}

struct SoulMoleCasting(B){
	ManaDrain!B manaDrain;
	SoulMole!B soulMole;
}
struct SoulMole(B){
	int soul;
	int wizard;
	SacSpell!B spell;
	Vector3f position;
	Vector3f startPosition;
	Vector3f targetVelocity;
	PositionPredictor positionPredictor;
	//Vector3f velocity=Vector3f(0.0f,0.0f,0.0f);
	int frame=0;
	enum roundtripTime=9*updateFPS;
	int soundTimer;
}

struct RainbowCasting(B){
	int side;
	OrderTarget target;
	ManaDrain!B manaDrain;
	SacSpell!B spell;
}
struct Rainbow(B){
	int side;
	OrderTarget last,current;
	SacSpell!B spell;
	PositionPredictor predictor;
	int numTargets=0;
	int frame=0;
	enum totTargets=6;
	int[totTargets] targets=0;
	bool addTarget(int id){
		if(!id) return false;
		foreach(ref x;targets){
			if(!x){
				x=id;
				return true;
			}
		}
		return false;
	}
	bool hasTarget(int id){ return id&&targets[].canFind(id); }

	enum travelFrames=64;
}
struct RainbowEffect(B){
	OrderTarget start,end;
	SacSpell!B spell;
	PositionPredictor predictor;
	enum travelFrames=Rainbow!B.travelFrames;
	enum delay=32;
	enum totalFrames=travelFrames+delay+travelFrames;
	int frame=0;
	int soundTimer;
}

struct ChainLightningCasting(B){
	int side;
	OrderTarget target;
	ManaDrain!B manaDrain;
	SacSpell!B spell;
}
struct ChainLightningCastingEffect(B){
	Vector3f start,end;
	int frame;
	LightningBolt bolt;
	enum totalFrames=32;
	enum changeShapeDelay=6;
	enum travelDelay=24;
}
struct ChainLightning(B){
	int wizard;
	int side;
	OrderTarget last,current;
	SacSpell!B spell;
	PositionPredictor predictor;
	int numTargets=0;
	int frame=0;
	enum totTargets=7;
	int[totTargets] targets=0;
	bool addTarget(int id){
		if(!id) return false;
		foreach(ref x;targets){
			if(!x){
				x=id;
				return true;
			}
		}
		return false;
	}
	bool hasTarget(int id){ return id&&targets[].canFind(id); }
	enum travelFrames=20;
}

struct AnimateDeadCasting(B){
	ManaDrain!B manaDrain;
	SacSpell!B spell;
}
struct AnimateDead(B){
	OrderTarget caster,creature;
	int lifetime;
	SacSpell!B spell;
	int frame=0;
	int soundTimer;
}
struct AnimateDeadEffect(B){
	OrderTarget start;
	Vector3f startDirection;
	OrderTarget end;
	Vector3f endDirection;
	float relativeLength;
	SacSpell!B spell;
	int frame=0;
	enum totalFrames=128;
}

struct EruptCasting(B){
	ManaDrain!B manaDrain;
	Erupt!B erupt;

	enum castingLimit=4*updateFPS;
}
struct Erupt(B){
	int wizard;
	int side;
	Vector3f position;
	SacSpell!B spell;
	int frame=0;

	int soundTimer0=0,soundTimer1=0;

	enum range=50.0f, height=15.0f, growDur=4.2f, fallDur=0.15f;
	enum waveRange=90.0f, waveDur=1.0f, reboundHeight=2.0f;
	//enum throwRange=30.0f, fallRange=45.0f;
	enum throwRange=42.5f;
	enum stunMinRange=50.0f,stunMaxRange=75.0f;
	// TODO: immunity ranges

	enum totalFrames=cast(int)((growDur+waveDur)*updateFPS+0.5f);

	float displacement(float x,float y){
		enum pi=pi!float;
		auto time=float(frame)/updateFPS;
		auto epos=position.xy, pos=Vector2f(x,y);
		auto dist=(pos-epos).length;
		float displacement=0.0f;
		if(dist<range){
			float scale=0.0f;
			if(time<growDur){
				scale=time/growDur;
			}else if(time<growDur+fallDur){
				scale=1.0f-(time-growDur)/fallDur;
			}
			float shape=0.6f*(1.0f-dist/range);
			if(dist<0.8f*range && time<=growDur){
				shape+=0.5f*0.4f*(1.0f+cos(pi*dist/(0.8f*range)));
			}
			displacement+=shape*height*scale;
		}
		if(growDur<time&&time<growDur+waveDur){
			float progress=(time-growDur)/waveDur;
			float waveLoc=waveRange*progress;
			float waveSize=(0.8f*range)*(1.0f-0.8f*progress);
			float wavePos=abs(dist-waveLoc)/waveSize;
			float waveHeight=height*(1.0f-progress);
			if(wavePos<1.0f) displacement+=0.5f*0.4f*(1.0f+cos(pi*wavePos))*waveHeight;
			if(dist<waveRange) displacement-=(1.0f+cos(pi*dist/waveRange))*sin(pi*progress)*reboundHeight;
		}
		return displacement;
		/*auto shape=0.6f*(1.0f-dist/range);
		if(dist<0.8f*range){
			shape+=0.5f*0.4f*(1.0f+cos(pi!float*dist/(0.8f*range)));
		}
		return shape*height*scale;*/
		//return 0.5f*(1.0f+cos(pi!float*dist/range))*height*scale;
		//return (0.25f*0.5f*(1.0f+cos(pi!float*dist/range))+0.75f*(1.0f-dist/range))*height*scale;
		//static import std.math;
		//return std.math.exp(-3.0f*(dist/range)^^2)*height*scale; // !!!
		//return (0.5f*std.math.exp(-5.0f*(dist/range)^^2)+0.5f*(1.0f-dist/range))*height*scale; // !!!
	}
}
struct EruptDebris(B){
	Vector3f position; // TODO: better representation?
	Vector3f velocity;
	Quaternionf rotationUpdate;
	Quaternionf rotation;
	int frame=0;
}

struct DragonfireCasting(B){
	int castingTime;
	ManaDrain!B manaDrain;
	Dragonfire!B dragonfire;

	float scale(){ return float(dragonfire.frame)/castingTime; }
}
struct Dragonfire(B){
	int wizard;
	int side;
	Vector3f position;
	Vector3f direction;
	OrderTarget target;
	SacSpell!B spell;
	int frame=0;
	float scale=1.0f;
	PositionPredictor predictor;

	int unsuccessfulTries=0;
	enum maxUnsuccessful=1;
	enum shrinkTime=1.0f;

	enum rotationSpeed=pi!float;
	enum totTargets=6;
	int[totTargets] targets=0;
	bool addTarget(int id){
		if(!id) return false;
		foreach(ref x;targets){
			if(!x){
				x=id;
				return true;
			}
		}
		return false;
	}
	bool hasTarget(int id){ return id&&targets[].canFind(id); }
}

struct SoulWindCasting(B){
	ManaDrain!B manaDrain;
	SoulWind!B soulWind;
}
struct SoulWind(B){
	int soul;
	int wizard;
	SacSpell!B spell;
	Vector3f position;
	Vector3f startPosition;
	Vector3f targetVelocity;
	PositionPredictor positionPredictor;
	int frame=0;
	enum roundtripTime=9*updateFPS;

	SmallArray!(int,24) targets;
	bool hasTarget(int id){ return id&&targets[].canFind(id); }
	bool addTarget(int id){
		if(!id||hasTarget(id)) return false;
		targets~=id;
		return true;
	}
}
struct SoulWindEffect{
	enum totalFrames=32;
	enum changeShapeDelay=4;
	OrderTarget start,end;
	int frame;
	LightningBolt[2] bolts;
}

struct ExplosionEffect{
	Vector3f position;
	float scale=0.0f;
	int frame=0;
	int soundTimer;
	enum maxRadius=1.0f;
	enum rotationSpeed=0.5f*2*pi!float;
	enum shrinkSpeed=2.0f;
}
struct ExplosionCasting(B){
	int side;
	ManaDrain!B manaDrain;
	SacSpell!B spell;
	int castingTime;
	enum numEffecs=5;
	ExplosionEffect[5] effects;
	bool failed=false;
}

struct HaloOfEarthCasting(B){
	ManaDrain!B manaDrain;
	int castingTime;
	HaloOfEarth!B haloOfEarth;
	int frame=0;
}
struct HaloRock(B){
	int wizard;
	int side;
	Vector3f position; // TODO: better representation?
	Vector3f velocity;
	OrderTarget target;
	SacSpell!B spell;
	Quaternionf rotationUpdate;
	Quaternionf rotation;
	Vector3f[2] lastPosition,nextPosition;
	enum centerHeight=3.0f;
	enum radius=2.0f;
	enum speedRadius=3.0f;
	enum interpolationSpeed=1.75f;
	float progress=0.0f;
	int frame=0;
}
struct HaloOfEarth(B){
	int wizard;
	int side;
	SacSpell!B spell;
	bool isAbility=false;
	enum numRocks=6;
	HaloRock!B[numRocks] rocks;
	int numSpawned=0;
	int numDespawned=0;
	int frame=0;
}

struct RainOfFrogsCasting(B){
	ManaDrain!B manaDrain;
	RainOfFrogs!B rainOfFrogs;
	bool interrupted=false;
}
struct RainOfFrogs(B){
	int wizard;
	int side;
	Vector3f position;
	SacSpell!B spell;
	float cloudScale=0.0f;
	int cloudFrame=0;
	int frame=0;
	enum cloudHeight=90.0f;
	enum cloudGrowSpeed=0.5f;
	enum cloudShrinkSpeed=1.0f;
	enum frogRate=15;
	enum fallDuration=2.0f;
	enum jumpRange=25.0f, shortJumpRange=10.0f; // TODO: correct?
}
enum FrogStatus{
	falling,
	sitting,
	jumping,
	infecting,
}
struct RainFrog(B){
	int wizard;
	int side;
	//int intendedTarget;
	Vector3f position;
	Vector3f velocity;
	SacSpell!B spell;
	int target=0;
	int infectionTime=0;
	enum infectTime=5*updateFPS;
	// int bone; // TODO: stick on bones
	int animationFrame=11*updateAnimFactor;
	enum maxAnimationFrame=16*updateAnimFactor-1;
	int frame=0;
	int sitTimer=0;
	enum sitTime=updateFPS/2;
	int numJumps=0;
	auto status=FrogStatus.falling;
}

struct DemonicRiftCasting(B){
	ManaDrain!B manaDrain;
	DemonicRift!B demonicRift;
}
enum DemonicRiftSpiritStatus{
	targeting,
	rising,
	movingAway,
	movingBack,
	vanishing,
}
struct DemonicRiftSpirit(B){
	int wizard;
	int side;
	Vector3f position;
	Vector3f velocity;
	SacSpell!B spell;
	OrderTarget target;
	enum numSpiritFrames=120;
	Vector3f[numSpiritFrames] locations;
	Vector3f[2] get(float t){ return cintp(locations[].stride(3),t); }
	int frame=0;
	DemonicRiftSpiritStatus status;
	int risingTimer=0;
	float scale=1.0f;
	enum vanishSpeed=1.0f;
	enum risingFrames=4*updateFPS;
	enum numRotations=5;
	enum risingHeight=7.5f;
	enum targetingCooldown=updateFPS/3;
	enum movingAwayHeight=20.0f;
	PositionPredictor predictor;
}
enum DemonicRiftStatus{
	emerging,
	active,
	shrinking,
}
struct DemonicRift(B){
	int wizard;
	int side;
	Vector3f position;
	OrderTarget target;
	SacSpell!B spell;
	int frame=0;
	DemonicRiftStatus status;
	float heightScale=0.0f;
	int numSpawned=0, numDespawned;
	enum maxNumSpirits=24;
	DemonicRiftSpirit!B[maxNumSpirits] spirits;
	enum effectRate=6;
	int lastEffectTime=0;
	enum maxEffectDelay=updateFPS/2;
	enum radius=2.0f;
	enum emergenceSpeed=0.5f;
	enum vanishSpeed=1.0f;
	enum spiritCooldown=updateFPS/3;
	enum unsuccessfulSpiritCooldown=updateFPS;
	int spiritTimer=0;

	bool hasTarget(int id){ return spirits[0..numSpawned].any!((ref spirit)=>spirit.target.id==id); }
}
struct DemonicRiftEffect(B){
	Vector3f position;
	float scale=1.0f;
	int frame=0;
	enum shrinkSpeed=0.5f;
	enum lifetime=1.0f/shrinkSpeed;
	enum startHoverHeight=0.25f;
	enum endHoverHeight=1.5f;
	enum upwardsVelocity=shrinkSpeed*(endHoverHeight-startHoverHeight);
}

struct BrainiacProjectile(B){
	int attacker;
	int side;
	int intendedTarget;
	Vector3f position;
	Vector3f direction;
	SacSpell!B rangedAttack;
	float remainingDistance;
}
struct BrainiacEffect{
	Vector3f position;
	Vector3f direction;
	int frame=0;
}

struct ShrikeProjectile(B){
	int attacker;
	int side;
	int intendedTarget;
	Vector3f position;
	Vector3f direction;
	SacSpell!B rangedAttack;
	float remainingDistance;
}
struct ShrikeEffect{
	Vector3f position;
	Vector3f direction;
	float scale;
	int frame=0;
}

struct LocustProjectile(B){
	SacSpell!B rangedAttack;
	Vector3f position;
	Vector3f target;
	bool blood;
}

struct SpitfireProjectile(B){
	int attacker;
	int side;
	int intendedTarget;
	Vector3f position;
	Vector3f direction;
	SacSpell!B rangedAttack;
	float remainingDistance;
	int frame=0;
	SmallArray!(int,16) damagedTargets;
}
struct SpitfireEffect{
	Vector3f position;
	Vector3f velocity;
	int lifetime;
	float scale=0.0f;
	int frame=0;
}

struct GargoyleProjectile(B){
	int attacker;
	int side;
	int intendedTarget;
	Vector3f position;
	Vector3f direction;
	SacSpell!B rangedAttack;
	float remainingDistance;
	int frame=0;
	SmallArray!(int,16) damagedTargets;
}
struct GargoyleEffect{
	Vector3f position;
	Vector3f velocity;
	int lifetime;
	float scale=0.0f;
	int frame=0;
}

struct EarthflingProjectile(B){
	int attacker;
	int side;
	int intendedTarget;
	Vector3f position;
	Vector3f velocity;
	SacSpell!B rangedAttack;
	Quaternionf rotationUpdate;
	Quaternionf rotation;
}

struct FlameMinionProjectile(B){
	int attacker;
	int side;
	int intendedTarget;
	Vector3f position;
	Vector3f velocity;
	SacSpell!B rangedAttack;
}

struct FallenProjectile(B){
	int attacker;
	int side;
	int intendedTarget;
	Vector3f position;
	Vector3f velocity;
	SacSpell!B rangedAttack;
	int frame;
	auto status=SwarmStatus.flying;
	Array!(Bug!B) bugs; // TODO: pull out bugs into separate array?
}

struct SylphEffect(B){
	int attacker;
	int frame=0;
}
struct SylphProjectile(B){
	int attacker;
	int side;
	int intendedTarget;
	Vector3f position;
	Vector3f velocity;
	SacSpell!B rangedAttack;
	int frame=0;
}

struct RangerEffect(B){
	int attacker;
	int frame=0;
}
struct RangerProjectile(B){
	int attacker;
	int side;
	int intendedTarget;
	Vector3f position;
	Vector3f velocity;
	SacSpell!B rangedAttack;
	int frame=0;
}

struct NecrylProjectile(B){
	int attacker;
	int side;
	int intendedTarget;
	Vector3f position;
	Vector3f direction;
	SacSpell!B rangedAttack;
	float remainingDistance;
}

struct Poison{
	int creature;
	float poisonDamage;
	int lifetime;
	bool infectuous;
	int attacker;
	int attackerSide;
	DamageMod damageMod;
	int frame=0;
	enum manaBlockDelay=2*updateFPS;
}

struct ScarabProjectile(B){
	int attacker;
	int side;
	int intendedTarget;
	Vector3f position;
	Vector3f direction;
	SacSpell!B rangedAttack;
	float remainingDistance;
}

struct BasiliskProjectile(B){
	int attacker;
	int side;
	int intendedTarget;
	Vector3f[2] positions;
	Vector3f direction;
	SacSpell!B rangedAttack;
	float remainingDistance;
}
struct BasiliskEffect{
	Vector3f position;
	Vector3f direction;
	int frame=0;
}

struct Petrification{
	int creature;
	int lifetime;
	Vector3f attackDirection;
	int frame=0;
}

struct TickfernoProjectile(B){
	int attacker;
	int side;
	int intendedTarget;
	Vector3f position;
	Vector3f direction;
	SacSpell!B rangedAttack;
	float remainingDistance;
	Vector3f startPosition;
	int frame=0;
	int hitframe=-1;
}
struct TickfernoEffect{
	Vector3f position;
	Vector3f direction;
	int frame=0;
}

struct VortickProjectile(B){
	int attacker;
	int side;
	int intendedTarget;
	Vector3f position;
	Vector3f direction;
	SacSpell!B rangedAttack;
	float remainingDistance;
}
struct VortickEffect{
	Vector3f position;
	Vector3f direction;
	int frame=0;
}

struct VortexEffect(B){
	Vector3f position;
	SacSpell!B rangedAttack;
	int frame=0;
	struct Particle{
		Vector3f position;
		Vector3f velocity;
		float scale=1.0f;
		int frame=0;
	}
	Array!Particle particles;
	enum duration=2.0f;
	enum radiusFactor=1;
	enum maxHeight=4.0f;
}

struct SquallProjectile(B){
	int attacker;
	int side;
	int intendedTarget;
	Vector3f position;
	Vector3f direction;
	SacSpell!B rangedAttack;
	float remainingDistance;
}
struct SquallEffect{
	Vector3f position;
	Vector3f direction;
	int frame=0;
}

struct Pushback(B){
	int creature;
	Vector3f direction;
	SacSpell!B rangedAttack;
	int frame=0;
	enum pushDuration=2.0f/3.0f;
	enum pushDistance=15.0f;
	enum pushVelocity=pushDistance/pushDuration;
}

struct FlummoxProjectile(B){
	int attacker;
	int side;
	int intendedTarget;
	Vector3f position;
	Vector3f velocity;
	SacSpell!B rangedAttack;
	Quaternionf rotationUpdate;
	Quaternionf rotation;
}

struct PyromaniacRocket(B){
	int attacker;
	int side;
	int intendedTarget;
	Vector3f position;
	Vector3f direction;
	SacSpell!B rangedAttack;
	float remainingDistance;
	int frame=0;
}

struct GnomeEffect(B){
	Vector3f position;
	Vector3f direction;
	SacSpell!B rangedAttack;
	int frame=0;
	enum animationDelay=2;
	enum numFrames=4*animationDelay*updateAnimFactor;
}

struct PoisonDart(B){
	int attacker;
	int side;
	int intendedTarget;
	Vector3f position;
	Vector3f direction;
	SacSpell!B rangedAttack;
	float remainingDistance;
}

struct MutantProjectile(B){
	int attacker;
	int side;
	int intendedTarget;
	Vector3f position;
	Vector3f velocity;
	SacSpell!B rangedAttack;
	int frame=0;
}

enum RockFormStatus{ growing, stationary, shrinking }
struct RockForm(B){
	int target;
	float scale;
	float relativeScale=0.0f;
	RockFormStatus status;
	enum numFrames=30;
}

enum StealthStatus{ fadingOut, stationary, fadingIn }
struct Stealth(B){
	int target;
	enum targetAlpha=0.06f;
	enum targetEnergy=10.0f;
	float progress=0.0f;
	StealthStatus status;
	enum numFrames=30;
}

enum LifeShieldStatus{ growing, stationary, shrinking }
struct LifeShield(B){
	int target;
	SacSpell!B ability;
	int soundEffectTimer;
	int frame=0;
	float scale=0.0f;
	LifeShieldStatus status;
	enum scaleFrames=15;
}

struct DivineSight(B){
	int side;
	int creature;
	Vector3f position;
	Vector3f velocity;
	SacSpell!B ability;
	int frame=0;
	float scale=0.0f;
	int target=0;
}

struct SteamCloud(B){
	int id;
	int side;
	Vector3f[2] hitbox;
	SacSpell!B ability;
}

struct PoisonCloud(B){
	int id;
	int side;
	Vector3f[2] hitbox;
	SacSpell!B ability;
}

struct BlightMite(B){
	int creature;
	int intendedTarget;
	Vector3f position;
	Vector3f velocity;
	SacSpell!B ability;
	int target=0;
	int infectionTime=0;
	// int bone; // TODO: stick on bones
	int frame=0;
	int numJumps=0;
	float alpha=1.0f;
	enum fadeTime=0.5f;
}

struct LightningCharge(B){
	int creature;
	int side;
	SacSpell!B spell;

	enum totalFrames=12*updateFPS; // TODO: correct?
	enum sparkRate=2.0f;
	enum lightningRate=0.65f;
	enum range=25.0f; // TODO: correct?
	enum shortJumpRange=10.0f;
	enum jumpRange=15.0f; // TODO: correct?
}

enum PullType{
	webPull,
	cagePull,
}
struct Pull(PullType which,B){
	int creature;
	int target;
	SacSpell!B ability;
	enum numShootFrames=20;
	enum numGrowFrames=20;
	int frame=0;
	int numPulls=0;
	float radius=float.infinity;
	enum pullSpeed=16.5f;
	enum numPullFrames=25;
	enum minThreadLength=3.0f;
	int pullFrames=0;

	static if(which==PullType.cagePull){
		enum maxBoltScale=1.0f;
		float boltScale=maxBoltScale;
		enum boltScaleGrowth=2.0f;
		enum totalFrames=64;
		enum changeShapeDelay=6;
		LightningBolt bolt;
		void changeShape(ObjectState!B state){
			bolt.changeShape!(2.5f)(state,boltScale);
		}
	}
}
alias WebPull(B)=Pull!(PullType.webPull,B);
alias CagePull(B)=Pull!(PullType.cagePull,B);

struct StickyBomb(B){
	int creature;
	int side;
	Vector3f position;
	Vector3f velocity;
	SacSpell!B ability;
	int target=0;
	int infectionTime=0;
	// int bone; // TODO: stick on bones
	int frame=0;
	float scale=1.0f;
	enum fadeTime=0.5f;
}

struct OilProjectile(B){
	int creature;
	int side;
	Vector3f position;
	Vector3f velocity;
	SacSpell!B ability;
	int frame=0;
}
struct Oil(B){
	int creature;
	int attacker;
	int attackerSide;
	SacSpell!B ability;
	// TODO: add data to render oil particles
	// int bone; // TODO: stick on bones
	int frame=0;
	float alpha=1.0f;
	enum fadeTime=0.5f;
}

struct HealingShower(B){
	int id;
	int side;
	Vector3f[2] hitbox;
	SacSpell!B ability;
}

struct Protector(B){
	int id;
	SacSpell!B ability;
}

struct Appearance{
	int id;
	int lifetime;
	int frame=0;
}

struct Disappearance{
	int id;
	int lifetime;
	int frame=0;
}

struct AltarDestruction{
	int ring;
	Vector3f position;
	Quaternionf oldRotation;
	Quaternionf newRotation;
	int shrine;
	float shrineHeight;
	int[4] pillars;
	float pillarHeight;
	int[4] stalks;
	float stalkHeight;
	int manafount=0;
	int frame=0;
	enum wiggleFrames=updateFPS/60;
	static assert(updateFPS%wiggleFrames==0);
	enum disappearDuration=4*updateFPS;
	enum floatDuration=4*updateFPS;
	enum explodeDuration=3*updateFPS;
}

struct ScreenShake{
	Vector3f position;
	int lifetime;
	float strength=1.0f;
	float range=100.0f;
	Vector3f displacement=Vector3f(0.0f,0.0f,0.0f);
	Vector3f target;
	int frame=0;
	enum shakes=30;
	static assert(updateFPS%shakes==0);
	enum shakeFrames=updateFPS/shakes;

	Vector3f getDisplacement(Vector3f camPos){
		return (max(0.0f,range-(camPos-position).length)/range)^^2*displacement;
	}
}

struct TestDisplacement{
	int frame=0;
	float displacement(float x,float y){
		float time=float(frame)/updateFPS;
		return 2.5f*(sin(0.1f*x+time)+sin(0.1f*y+time));
	}
}

struct Effects(B){
	// misc
	Array!(Debris!B) debris;
	void addEffect(Debris!B debris){
		this.debris~=debris;
	}
	void removeDebris(int i){
		if(i+1<debris.length) debris[i]=move(debris[$-1]);
		debris.length=debris.length-1;
	}
	Array!(Explosion!B) explosions;
	void addEffect(Explosion!B explosion){
		explosions~=explosion;
	}
	void removeExplosion(int i){
		if(i+1<explosions.length) explosions[i]=move(explosions[$-1]);
		explosions.length=explosions.length-1;
	}
	Array!(Fire!B) fires;
	void addEffect(Fire!B fire){
		fires~=fire;
	}
	void removeFire(int i){
		if(i+1<fires.length) fires[i]=move(fires[$-1]);
		fires.length=fires.length-1;
	}
	Array!(ManaDrain!B) manaDrains;
	void addEffect(ManaDrain!B manaDrain){
		manaDrains~=manaDrain;
	}
	void removeManaDrain(int i){
		if(i+1<manaDrains.length) manaDrains[i]=move(manaDrains[$-1]);
		manaDrains.length=manaDrains.length-1;
	}
	Array!BuildingDestruction buildingDestructions;
	void addEffect(BuildingDestruction buildingDestruction){
		buildingDestructions~=buildingDestruction;
	}
	void removeBuildingDestruction(int i){
		if(i+1<buildingDestructions.length) buildingDestructions[i]=move(buildingDestructions[$-1]);
		buildingDestructions.length=buildingDestructions.length-1;
	}
	Array!GhostKill ghostKills;
	void addEffect(GhostKill ghostKill){
		ghostKills~=ghostKill;
	}
	void removeGhostKill(int i){
		if(i+1<ghostKills.length) ghostKills[i]=move(ghostKills[$-1]);
		ghostKills.length=ghostKills.length-1;
	}
	// creature spells
	Array!(CreatureCasting!B) creatureCasts;
	void addEffect(CreatureCasting!B creatureCast){
		creatureCasts~=creatureCast;
	}
	void removeCreatureCasting(int i){
		if(i+1<creatureCasts.length) creatureCasts[i]=move(creatureCasts[$-1]);
		creatureCasts.length=creatureCasts.length-1;
	}
	// structure spells
	Array!(StructureCasting!B) structureCasts;
	void addEffect(StructureCasting!B structureCast){
		structureCasts~=structureCast;
	}
	void removeStructureCasting(int i){
		if(i+1<structureCasts.length) structureCasts[i]=move(structureCasts[$-1]);
		structureCasts.length=structureCasts.length-1;
	}
	Array!(BlueRing!B) blueRings;
	void addEffect(BlueRing!B blueRing){
		blueRings~=blueRing;
	}
	void removeBlueRing(int i){
		if(i+1<blueRings.length) blueRings[i]=move(blueRings[$-1]);
		blueRings.length=blueRings.length-1;
	}
	Array!(SacDocCasting!B) sacDocCastings;
	void addEffect(SacDocCasting!B sacDocCasting){
		sacDocCastings~=sacDocCasting;
	}
	void removeSacDocCasting(int i){
		if(i+1<sacDocCastings.length) sacDocCastings[i]=move(sacDocCastings[$-1]);
		sacDocCastings.length=sacDocCastings.length-1;
	}
	Array!(SacDocCarry!B) sacDocCarries;
	void addEffect(SacDocCarry!B sacDocCarry){
		sacDocCarries~=sacDocCarry;
	}
	void removeSacDocCarry(int i){
		if(i+1<sacDocCarries.length) sacDocCarries[i]=move(sacDocCarries[$-1]);
		sacDocCarries.length=sacDocCarries.length-1;
	}
	Array!(Ritual!B) rituals;
	void addEffect(Ritual!B ritual){
		rituals~=ritual;
	}
	void removeRitual(int i){
		if(i+1<rituals.length) rituals[i]=move(rituals[$-1]);
		rituals.length=rituals.length-1;
	}
	Array!(TeleportCasting!B) teleportCastings;
	void addEffect(TeleportCasting!B teleportCasting){
		teleportCastings~=teleportCasting;
	}
	void removeTeleportCasting(int i){
		if(i+1<teleportCastings.length) teleportCastings[i]=move(teleportCastings[$-1]);
		teleportCastings.length=teleportCastings.length-1;
	}
	Array!(TeleportEffect!B) teleportEffects;
	void addEffect(TeleportEffect!B teleportEffect){
		teleportEffects~=teleportEffect;
	}
	void removeTeleportEffect(int i){
		if(i+1<teleportEffects.length) teleportEffects[i]=move(teleportEffects[$-1]);
		teleportEffects.length=teleportEffects.length-1;
	}
	Array!(TeleportRing!B) teleportRings;
	void addEffect(TeleportRing!B teleportRing){
		teleportRings~=teleportRing;
	}
	void removeTeleportRing(int i){
		if(i+1<teleportRings.length) teleportRings[i]=move(teleportRings[$-1]);
		teleportRings.length=teleportRings.length-1;
	}
	Array!(GuardianCasting!B) guardianCastings;
	void addEffect(GuardianCasting!B guardianCasting){
		guardianCastings~=guardianCasting;
	}
	void removeGuardianCasting(int i){
		if(i+1<guardianCastings.length) guardianCastings[i]=move(guardianCastings[$-1]);
		guardianCastings.length=guardianCastings.length-1;
	}
	Array!Guardian guardians;
	void addEffect(Guardian guardian){
		guardians~=guardian;
	}
	void removeGuardian(int i){
		if(i+1<guardians.length) guardians[i]=move(guardians[$-1]);
		guardians.length=guardians.length-1;
	}
	// ordinary spells
	Array!(SpeedUp!B) speedUps;
	void addEffect(SpeedUp!B speedUp){
		speedUps~=speedUp;
	}
	void removeSpeedUp(int i){
		if(i+1<speedUps.length) speedUps[i]=move(speedUps[$-1]);
		speedUps.length=speedUps.length-1;
	}
	Array!(SpeedUpShadow!B) speedUpShadows;
	void addEffect(SpeedUpShadow!B speedUpShadow){
		speedUpShadows~=speedUpShadow;
	}
	void removeSpeedUpShadow(int i){
		if(i+1<speedUpShadows.length) speedUpShadows[i]=move(speedUpShadows[$-1]);
		speedUpShadows.length=speedUpShadows.length-1;
	}
	Array!(HealCasting!B) healCastings;
	void addEffect(HealCasting!B healCasting){
		healCastings~=healCasting;
	}
	void removeHealCasting(int i){
		if(i+1<healCastings.length) healCastings[i]=move(healCastings[$-1]);
		healCastings.length=healCastings.length-1;
	}
	Array!(Heal!B) heals;
	void addEffect(Heal!B heal){
		heals~=heal;
	}
	void removeHeal(int i){
		if(i+1<heals.length) heals[i]=move(heals[$-1]);
		heals.length=heals.length-1;
	}
	Array!(LightningCasting!B) lightningCastings;
	void addEffect(LightningCasting!B lightningCasting){
		lightningCastings~=lightningCasting;
	}
	void removeLightningCasting(int i){
		if(i+1<lightningCastings.length) lightningCastings[i]=move(lightningCastings[$-1]);
		lightningCastings.length=lightningCastings.length-1;
	}
	Array!(Lightning!B) lightnings;
	void addEffect(Lightning!B lightning){
		lightnings~=lightning;
	}
	void removeLightning(int i){
		if(i+1<lightnings.length) lightnings[i]=move(lightnings[$-1]);
		lightnings.length=lightnings.length-1;
	}
	Array!(WrathCasting!B) wrathCastings;
	void addEffect(WrathCasting!B wrathCasting){
		wrathCastings~=wrathCasting;
	}
	void removeWrathCasting(int i){
		if(i+1<wrathCastings.length) wrathCastings[i]=move(wrathCastings[$-1]);
		wrathCastings.length=wrathCastings.length-1;
	}
	Array!(Wrath!B) wraths;
	void addEffect(Wrath!B wrath){
		wraths~=wrath;
	}
	void removeWrath(int i){
		if(i+1<wraths.length) wraths[i]=move(wraths[$-1]);
		wraths.length=wraths.length-1;
	}
	Array!(FireballCasting!B) fireballCastings;
	void addEffect(FireballCasting!B fireballCasting){
		fireballCastings~=fireballCasting;
	}
	void removeFireballCasting(int i){
		if(i+1<fireballCastings.length) fireballCastings[i]=move(fireballCastings[$-1]);
		fireballCastings.length=fireballCastings.length-1;
	}
	Array!(Fireball!B) fireballs;
	void addEffect(Fireball!B fireball){
		fireballs~=fireball;
	}
	void removeFireball(int i){
		if(i+1<fireballs.length) fireballs[i]=move(fireballs[$-1]);
		fireballs.length=fireballs.length-1;
	}
	Array!(RockCasting!B) rockCastings;
	void addEffect(RockCasting!B rockCasting){
		rockCastings~=rockCasting;
	}
	void removeRockCasting(int i){
		if(i+1<rockCastings.length) rockCastings[i]=move(rockCastings[$-1]);
		rockCastings.length=rockCastings.length-1;
	}
	Array!(Rock!B) rocks;
	void addEffect(Rock!B rock){
		rocks~=rock;
	}
	void removeRock(int i){
		if(i+1<rocks.length) rocks[i]=move(rocks[$-1]);
		rocks.length=rocks.length-1;
	}
	Array!(SwarmCasting!B) swarmCastings;
	void addEffect(SwarmCasting!B swarmCasting){
		swarmCastings~=move(swarmCasting);
	}
	void removeSwarmCasting(int i){
		if(i+1<swarmCastings.length) swarmCastings[i]=move(swarmCastings[$-1]);
		swarmCastings.length=swarmCastings.length-1;
	}
	Array!(Swarm!B) swarms;
	void addEffect(Swarm!B swarm){
		swarms~=move(swarm);
	}
	void removeSwarm(int i){
		if(i+1<swarms.length) swap(swarms[i],swarms[$-1]);
		swarms.length=swarms.length-1; // TODO: reuse memory?
	}
	Array!(SkinOfStoneCasting!B) skinOfStoneCastings;
	void addEffect(SkinOfStoneCasting!B skinOfStoneCasting){
		skinOfStoneCastings~=skinOfStoneCasting;
	}
	void removeSkinOfStoneCasting(int i){
		if(i+1<skinOfStoneCastings.length) skinOfStoneCastings[i]=move(skinOfStoneCastings[$-1]);
		skinOfStoneCastings.length=skinOfStoneCastings.length-1;
	}
	Array!(SkinOfStone!B) skinOfStones;
	void addEffect(SkinOfStone!B skinOfStone){
		skinOfStones~=skinOfStone;
	}
	void removeSkinOfStone(int i){
		if(i+1<skinOfStones.length) skinOfStones[i]=move(skinOfStones[$-1]);
		skinOfStones.length=skinOfStones.length-1;
	}
	Array!(EtherealFormCasting!B) etherealFormCastings;
	void addEffect(EtherealFormCasting!B etherealFormCasting){
		etherealFormCastings~=etherealFormCasting;
	}
	void removeEtherealFormCasting(int i){
		if(i+1<etherealFormCastings.length) etherealFormCastings[i]=move(etherealFormCastings[$-1]);
		etherealFormCastings.length=etherealFormCastings.length-1;
	}
	Array!(EtherealForm!B) etherealForms;
	void addEffect(EtherealForm!B etherealForm){
		etherealForms~=etherealForm;
	}
	void removeEtherealForm(int i){
		if(i+1<etherealForms.length) etherealForms[i]=move(etherealForms[$-1]);
		etherealForms.length=etherealForms.length-1;
	}
	Array!(FireformCasting!B) fireformCastings;
	void addEffect(FireformCasting!B fireformCasting){
		fireformCastings~=fireformCasting;
	}
	void removeFireformCasting(int i){
		if(i+1<fireformCastings.length) fireformCastings[i]=move(fireformCastings[$-1]);
		fireformCastings.length=fireformCastings.length-1;
	}
	Array!(Fireform!B) fireforms;
	void addEffect(Fireform!B fireform){
		fireforms~=fireform;
	}
	void removeFireform(int i){
		if(i+1<fireforms.length) fireforms[i]=move(fireforms[$-1]);
		fireforms.length=fireforms.length-1;
	}
	Array!(ProtectiveSwarmCasting!B) protectiveSwarmCastings;
	void addEffect(ProtectiveSwarmCasting!B protectiveSwarmCasting){
		protectiveSwarmCastings~=move(protectiveSwarmCasting);
	}
	void removeProtectiveSwarmCasting(int i){
		if(i+1<protectiveSwarmCastings.length) protectiveSwarmCastings[i]=move(protectiveSwarmCastings[$-1]);
		protectiveSwarmCastings.length=protectiveSwarmCastings.length-1;
	}
	Array!(ProtectiveSwarm!B) protectiveSwarms;
	void addEffect(ProtectiveSwarm!B protectiveSwarm){
		protectiveSwarms~=move(protectiveSwarm);
	}
	void removeProtectiveSwarm(int i){
		if(i+1<protectiveSwarms.length) swap(protectiveSwarms[i],protectiveSwarms[$-1]);
		protectiveSwarms.length=protectiveSwarms.length-1; // TODO: reuse memory?
	}
	Array!(AirShieldCasting!B) airShieldCastings;
	void addEffect(AirShieldCasting!B airShieldCasting){
		airShieldCastings~=move(airShieldCasting);
	}
	void removeAirShieldCasting(int i){
		if(i+1<airShieldCastings.length) airShieldCastings[i]=move(airShieldCastings[$-1]);
		airShieldCastings.length=airShieldCastings.length-1;
	}
	Array!(AirShield!B) airShields;
	void addEffect(AirShield!B airShield){
		airShields~=move(airShield);
	}
	void removeAirShield(int i){
		if(i+1<airShields.length) airShields[i]=move(airShields[$-1]);
		airShields.length=airShields.length-1;
	}
	Array!(FreezeCasting!B) freezeCastings;
	void addEffect(FreezeCasting!B freezeCasting){
		freezeCastings~=move(freezeCasting);
	}
	void removeFreezeCasting(int i){
		if(i+1<freezeCastings.length) freezeCastings[i]=move(freezeCastings[$-1]);
		freezeCastings.length=freezeCastings.length-1;
	}
	Array!(Freeze!B) freezes;
	void addEffect(Freeze!B freeze){
		freezes~=move(freeze);
	}
	void removeFreeze(int i){
		if(i+1<freezes.length) freezes[i]=move(freezes[$-1]);
		freezes.length=freezes.length-1;
	}
	Array!(RingsOfFireCasting!B) ringsOfFireCastings;
	void addEffect(RingsOfFireCasting!B ringsOfFireCasting){
		ringsOfFireCastings~=move(ringsOfFireCasting);
	}
	void removeRingsOfFireCasting(int i){
		if(i+1<ringsOfFireCastings.length) ringsOfFireCastings[i]=move(ringsOfFireCastings[$-1]);
		ringsOfFireCastings.length=ringsOfFireCastings.length-1;
	}
	Array!(RingsOfFire!B) ringsOfFires;
	void addEffect(RingsOfFire!B ringsOfFire){
		ringsOfFires~=move(ringsOfFire);
	}
	void removeRingsOfFire(int i){
		if(i+1<ringsOfFires.length) ringsOfFires[i]=move(ringsOfFires[$-1]);
		ringsOfFires.length=ringsOfFires.length-1;
	}
	Array!(SlimeCasting!B) slimeCastings;
	void addEffect(SlimeCasting!B slimeCasting){
		slimeCastings~=move(slimeCasting);
	}
	void removeSlimeCasting(int i){
		if(i+1<slimeCastings.length) slimeCastings[i]=move(slimeCastings[$-1]);
		slimeCastings.length=slimeCastings.length-1;
	}
	Array!(Slime!B) slimes;
	void addEffect(Slime!B slime){
		slimes~=move(slime);
	}
	void removeSlime(int i){
		if(i+1<slimes.length) slimes[i]=move(slimes[$-1]);
		slimes.length=slimes.length-1;
	}
	Array!(GraspingVinesCasting!B) graspingVinesCastings;
	void addEffect(GraspingVinesCasting!B graspingVinesCasting){
		graspingVinesCastings~=move(graspingVinesCasting);
	}
	void removeGraspingVinesCasting(int i){
		if(i+1<graspingVinesCastings.length) graspingVinesCastings[i]=move(graspingVinesCastings[$-1]);
		graspingVinesCastings.length=graspingVinesCastings.length-1;
	}
	Array!(GraspingVines!B) graspingViness;
	void addEffect(GraspingVines!B graspingVines){
		graspingViness~=move(graspingVines);
	}
	void removeGraspingVines(int i){
		if(i+1<graspingViness.length) graspingViness[i]=move(graspingViness[$-1]);
		graspingViness.length=graspingViness.length-1;
	}
	Array!(SoulMoleCasting!B) soulMoleCastings;
	void addEffect(SoulMoleCasting!B soulMoleCasting){
		soulMoleCastings~=move(soulMoleCasting);
	}
	void removeSoulMoleCasting(int i){
		if(i+1<soulMoleCastings.length) soulMoleCastings[i]=move(soulMoleCastings[$-1]);
		soulMoleCastings.length=soulMoleCastings.length-1;
	}
	Array!(SoulMole!B) soulMoles;
	void addEffect(SoulMole!B soulMole){
		soulMoles~=move(soulMole);
	}
	void removeSoulMole(int i){
		if(i+1<soulMoles.length) soulMoles[i]=move(soulMoles[$-1]);
		soulMoles.length=soulMoles.length-1;
	}
	Array!(RainbowCasting!B) rainbowCastings;
	void addEffect(RainbowCasting!B rainbowCasting){
		rainbowCastings~=move(rainbowCasting);
	}
	void removeRainbowCasting(int i){
		if(i+1<rainbowCastings.length) rainbowCastings[i]=move(rainbowCastings[$-1]);
		rainbowCastings.length=rainbowCastings.length-1;
	}
	Array!(Rainbow!B) rainbows;
	void addEffect(Rainbow!B rainbow){
		rainbows~=move(rainbow);
	}
	void removeRainbow(int i){
		if(i+1<rainbows.length) rainbows[i]=move(rainbows[$-1]);
		rainbows.length=rainbows.length-1;
	}
	Array!(RainbowEffect!B) rainbowEffects;
	void addEffect(RainbowEffect!B rainbowEffect){
		rainbowEffects~=move(rainbowEffect);
	}
	void removeRainbowEffect(int i){
		if(i+1<rainbowEffects.length) rainbowEffects[i]=move(rainbowEffects[$-1]);
		rainbowEffects.length=rainbowEffects.length-1;
	}
	Array!(ChainLightningCasting!B) chainLightningCastings;
	void addEffect(ChainLightningCasting!B chainLightningCasting){
		chainLightningCastings~=move(chainLightningCasting);
	}
	void removeChainLightningCasting(int i){
		if(i+1<chainLightningCastings.length) chainLightningCastings[i]=move(chainLightningCastings[$-1]);
		chainLightningCastings.length=chainLightningCastings.length-1;
	}
	Array!(ChainLightningCastingEffect!B) chainLightningCastingEffects;
	void addEffect(ChainLightningCastingEffect!B chainLightningCastingEffect){
		chainLightningCastingEffects~=move(chainLightningCastingEffect);
	}
	void removeChainLightningCastingEffect(int i){
		if(i+1<chainLightningCastingEffects.length) chainLightningCastingEffects[i]=move(chainLightningCastingEffects[$-1]);
		chainLightningCastingEffects.length=chainLightningCastingEffects.length-1;
	}
	Array!(ChainLightning!B) chainLightnings;
	void addEffect(ChainLightning!B chainLightning){
		chainLightnings~=move(chainLightning);
	}
	void removeChainLightning(int i){
		if(i+1<chainLightnings.length) chainLightnings[i]=move(chainLightnings[$-1]);
		chainLightnings.length=chainLightnings.length-1;
	}
	Array!(AnimateDeadCasting!B) animateDeadCastings;
	void addEffect(AnimateDeadCasting!B animateDeadCasting){
		animateDeadCastings~=move(animateDeadCasting);
	}
	void removeAnimateDeadCasting(int i){
		if(i+1<animateDeadCastings.length) animateDeadCastings[i]=move(animateDeadCastings[$-1]);
		animateDeadCastings.length=animateDeadCastings.length-1;
	}
	Array!(AnimateDead!B) animateDeads;
	void addEffect(AnimateDead!B animateDead){
		animateDeads~=move(animateDead);
	}
	void removeAnimateDead(int i){
		if(i+1<animateDeads.length) animateDeads[i]=move(animateDeads[$-1]);
		animateDeads.length=animateDeads.length-1;
	}
	Array!(AnimateDeadEffect!B) animateDeadEffects;
	void addEffect(AnimateDeadEffect!B animateDeadEffect){
		animateDeadEffects~=move(animateDeadEffect);
	}
	void removeAnimateDeadEffect(int i){
		if(i+1<animateDeadEffects.length) animateDeadEffects[i]=move(animateDeadEffects[$-1]);
		animateDeadEffects.length=animateDeadEffects.length-1;
	}
	Array!(EruptCasting!B) eruptCastings;
	void addEffect(EruptCasting!B eruptCasting){
		eruptCastings~=move(eruptCasting);
	}
	void removeEruptCasting(int i){
		if(i+1<eruptCastings.length) eruptCastings[i]=move(eruptCastings[$-1]);
		eruptCastings.length=eruptCastings.length-1;
	}
	Array!(Erupt!B) erupts;
	void addEffect(Erupt!B erupt){
		erupts~=move(erupt);
	}
	void removeErupt(int i){
		if(i+1<erupts.length) erupts[i]=move(erupts[$-1]);
		erupts.length=erupts.length-1;
	}
	Array!(EruptDebris!B) eruptDebris;
	void addEffect(EruptDebris!B eruptDebris){
		this.eruptDebris~=eruptDebris;
	}
	void removeEruptDebris(int i){
		if(i+1<eruptDebris.length) eruptDebris[i]=move(eruptDebris[$-1]);
		eruptDebris.length=eruptDebris.length-1;
	}
	Array!(DragonfireCasting!B) dragonfireCastings;
	void addEffect(DragonfireCasting!B dragonfireCasting){
		dragonfireCastings~=move(dragonfireCasting);
	}
	void removeDragonfireCasting(int i){
		if(i+1<dragonfireCastings.length) dragonfireCastings[i]=move(dragonfireCastings[$-1]);
		dragonfireCastings.length=dragonfireCastings.length-1;
	}
	Array!(Dragonfire!B) dragonfires;
	void addEffect(Dragonfire!B dragonfire){
		dragonfires~=dragonfire;
	}
	void removeDragonfire(int i){
		if(i+1<dragonfires.length) dragonfires[i]=move(dragonfires[$-1]);
		dragonfires.length=dragonfires.length-1;
	}
	Array!(SoulWindCasting!B) soulWindCastings;
	void addEffect(SoulWindCasting!B soulWindCasting){
		soulWindCastings~=move(soulWindCasting);
	}
	void removeSoulWindCasting(int i){
		if(i+1<soulWindCastings.length) soulWindCastings[i]=move(soulWindCastings[$-1]);
		soulWindCastings.length=soulWindCastings.length-1;
	}
	Array!(SoulWind!B) soulWinds;
	void addEffect(SoulWind!B soulWind){
		soulWinds~=move(soulWind);
	}
	void removeSoulWind(int i){
		if(i+1<soulWinds.length) soulWinds[i]=move(soulWinds[$-1]);
		soulWinds.length=soulWinds.length-1;
	}
	Array!SoulWindEffect soulWindEffects;
	void addEffect(SoulWindEffect soulWindEffect){
		soulWindEffects~=move(soulWindEffect);
	}
	void removeSoulWindEffect(int i){
		if(i+1<soulWindEffects.length) soulWindEffects[i]=move(soulWindEffects[$-1]);
		soulWindEffects.length=soulWindEffects.length-1;
	}
	Array!(ExplosionCasting!B) explosionCastings;
	void addEffect(ExplosionCasting!B explosionCasting){
		explosionCastings~=move(explosionCasting);
	}
	void removeExplosionCasting(int i){
		if(i+1<explosionCastings.length) explosionCastings[i]=move(explosionCastings[$-1]);
		explosionCastings.length=explosionCastings.length-1;
	}
	Array!(HaloOfEarthCasting!B) haloOfEarthCastings;
	void addEffect(HaloOfEarthCasting!B haloOfEarthCasting){
		haloOfEarthCastings~=move(haloOfEarthCasting);
	}
	void removeHaloOfEarthCasting(int i){
		if(i+1<haloOfEarthCastings.length) haloOfEarthCastings[i]=move(haloOfEarthCastings[$-1]);
		haloOfEarthCastings.length=haloOfEarthCastings.length-1;
	}
	Array!(HaloOfEarth!B) haloOfEarths;
	void addEffect(HaloOfEarth!B haloOfEarth){
		haloOfEarths~=move(haloOfEarth);
	}
	void removeHaloOfEarth(int i){
		if(i+1<haloOfEarths.length) haloOfEarths[i]=move(haloOfEarths[$-1]);
		haloOfEarths.length=haloOfEarths.length-1;
	}
	Array!(RainOfFrogsCasting!B) rainOfFrogsCastings;
	void addEffect(RainOfFrogsCasting!B RainOfFrogsCasting){
		rainOfFrogsCastings~=move(RainOfFrogsCasting);
	}
	void removeRainOfFrogsCasting(int i){
		if(i+1<rainOfFrogsCastings.length) rainOfFrogsCastings[i]=move(rainOfFrogsCastings[$-1]);
		rainOfFrogsCastings.length=rainOfFrogsCastings.length-1;
	}
	Array!(RainOfFrogs!B) rainOfFrogss;
	void addEffect(RainOfFrogs!B RainOfFrogs){
		rainOfFrogss~=move(RainOfFrogs);
	}
	void removeRainOfFrogs(int i){
		if(i+1<rainOfFrogss.length) rainOfFrogss[i]=move(rainOfFrogss[$-1]);
		rainOfFrogss.length=rainOfFrogss.length-1;
	}
	Array!(RainFrog!B) rainFrogs;
	void addEffect(RainFrog!B rainFrog){
		rainFrogs~=move(rainFrog);
	}
	void removeRainFrog(int i){
		if(i+1<rainFrogs.length) rainFrogs[i]=move(rainFrogs[$-1]);
		rainFrogs.length=rainFrogs.length-1;
	}
	Array!(DemonicRiftCasting!B) demonicRiftCastings;
	void addEffect(DemonicRiftCasting!B demonicRiftCasting){
		demonicRiftCastings~=move(demonicRiftCasting);
	}
	void removeDemonicRiftCasting(int i){
		if(i+1<demonicRiftCastings.length) demonicRiftCastings[i]=move(demonicRiftCastings[$-1]);
		demonicRiftCastings.length=demonicRiftCastings.length-1;
	}
	Array!(DemonicRift!B) demonicRifts;
	void addEffect(DemonicRift!B demonicRift){
		demonicRifts~=move(demonicRift);
	}
	void removeDemonicRift(int i){
		if(i+1<demonicRifts.length) demonicRifts[i]=move(demonicRifts[$-1]);
		demonicRifts.length=demonicRifts.length-1;
	}
	Array!(DemonicRiftEffect!B) demonicRiftEffects;
	void addEffect(DemonicRiftEffect!B demonicRiftEffect){
		demonicRiftEffects~=move(demonicRiftEffect);
	}
	void removeDemonicRiftEffect(int i){
		if(i+1<demonicRiftEffects.length) demonicRiftEffects[i]=move(demonicRiftEffects[$-1]);
		demonicRiftEffects.length=demonicRiftEffects.length-1;
	}
	// projectiles
	Array!(BrainiacProjectile!B) brainiacProjectiles;
	void addEffect(BrainiacProjectile!B brainiacProjectile){
		brainiacProjectiles~=brainiacProjectile;
	}
	void removeBrainiacProjectile(int i){
		if(i+1<brainiacProjectiles.length) brainiacProjectiles[i]=move(brainiacProjectiles[$-1]);
		brainiacProjectiles.length=brainiacProjectiles.length-1;
	}
	Array!BrainiacEffect brainiacEffects;
	void addEffect(BrainiacEffect brainiacEffect){
		brainiacEffects~=brainiacEffect;
	}
	void removeBrainiacEffect(int i){
		if(i+1<brainiacEffects.length) brainiacEffects[i]=move(brainiacEffects[$-1]);
		brainiacEffects.length=brainiacEffects.length-1;
	}
	Array!(ShrikeProjectile!B) shrikeProjectiles;
	void addEffect(ShrikeProjectile!B shrikeProjectile){
		shrikeProjectiles~=shrikeProjectile;
	}
	void removeShrikeProjectile(int i){
		if(i+1<shrikeProjectiles.length) shrikeProjectiles[i]=move(shrikeProjectiles[$-1]);
		shrikeProjectiles.length=shrikeProjectiles.length-1;
	}
	Array!ShrikeEffect shrikeEffects;
	void addEffect(ShrikeEffect shrikeEffect){
		shrikeEffects~=shrikeEffect;
	}
	void removeShrikeEffect(int i){
		if(i+1<shrikeEffects.length) shrikeEffects[i]=move(shrikeEffects[$-1]);
		shrikeEffects.length=shrikeEffects.length-1;
	}
	Array!(LocustProjectile!B) locustProjectiles;
	void addEffect(LocustProjectile!B locustProjectile){
		locustProjectiles~=locustProjectile;
	}
	void removeLocustProjectile(int i){
		if(i+1<locustProjectiles.length) locustProjectiles[i]=move(locustProjectiles[$-1]);
		locustProjectiles.length=locustProjectiles.length-1;
	}
	Array!(SpitfireProjectile!B) spitfireProjectiles;
	void addEffect(SpitfireProjectile!B spitfireProjectile){
		spitfireProjectiles~=spitfireProjectile;
	}
	void removeSpitfireProjectile(int i){
		if(i+1<spitfireProjectiles.length) swap(spitfireProjectiles[i],spitfireProjectiles[$-1]);
		spitfireProjectiles.length=spitfireProjectiles.length-1; // TODO: reuse memory?
	}
	Array!SpitfireEffect spitfireEffects;
	void addEffect(SpitfireEffect spitfireEffect){
		spitfireEffects~=spitfireEffect;
	}
	void removeSpitfireEffect(int i){
		if(i+1<spitfireEffects.length) spitfireEffects[i]=move(spitfireEffects[$-1]);
		spitfireEffects.length=spitfireEffects.length-1;
	}
	Array!(GargoyleProjectile!B) gargoyleProjectiles;
	void addEffect(GargoyleProjectile!B gargoyleProjectile){
		gargoyleProjectiles~=gargoyleProjectile;
	}
	void removeGargoyleProjectile(int i){
		if(i+1<gargoyleProjectiles.length) swap(gargoyleProjectiles[i],gargoyleProjectiles[$-1]);
		gargoyleProjectiles.length=gargoyleProjectiles.length-1; // TODO: reuse memory?
	}
	Array!GargoyleEffect gargoyleEffects;
	void addEffect(GargoyleEffect gargoyleEffect){
		gargoyleEffects~=gargoyleEffect;
	}
	void removeGargoyleEffect(int i){
		if(i+1<gargoyleEffects.length) gargoyleEffects[i]=move(gargoyleEffects[$-1]);
		gargoyleEffects.length=gargoyleEffects.length-1;
	}
	Array!(EarthflingProjectile!B) earthflingProjectiles;
	void addEffect(EarthflingProjectile!B earthflingProjectile){
		earthflingProjectiles~=earthflingProjectile;
	}
	void removeEarthflingProjectile(int i){
		if(i+1<earthflingProjectiles.length) swap(earthflingProjectiles[i],earthflingProjectiles[$-1]);
		earthflingProjectiles.length=earthflingProjectiles.length-1; // TODO: reuse memory?
	}
	Array!(FlameMinionProjectile!B) flameMinionProjectiles;
	void addEffect(FlameMinionProjectile!B flameMinionProjectile){
		flameMinionProjectiles~=flameMinionProjectile;
	}
	void removeFlameMinionProjectile(int i){
		if(i+1<flameMinionProjectiles.length) flameMinionProjectiles[i]=move(flameMinionProjectiles[$-1]);
		flameMinionProjectiles.length=flameMinionProjectiles.length-1;
	}
	Array!(FallenProjectile!B) fallenProjectiles;
	void addEffect(FallenProjectile!B fallenProjectile){
		fallenProjectiles~=move(fallenProjectile);
	}
	void removeFallenProjectile(int i){
		if(i+1<fallenProjectiles.length) swap(fallenProjectiles[i],fallenProjectiles[$-1]);
		fallenProjectiles.length=fallenProjectiles.length-1; // TODO: reuse memory?
	}
	Array!(SylphEffect!B) sylphEffects;
	void addEffect(SylphEffect!B sylphEffect){
		sylphEffects~=move(sylphEffect);
	}
	void removeSylphEffect(int i){
		if(i+1<sylphEffects.length) sylphEffects[i]=move(sylphEffects[$-1]);
		sylphEffects.length=sylphEffects.length-1;
	}
	Array!(SylphProjectile!B) sylphProjectiles;
	void addEffect(SylphProjectile!B sylphProjectile){
		sylphProjectiles~=move(sylphProjectile);
	}
	void removeSylphProjectile(int i){
		if(i+1<sylphProjectiles.length) sylphProjectiles[i]=move(sylphProjectiles[$-1]);
		sylphProjectiles.length=sylphProjectiles.length-1;
	}
	Array!(RangerEffect!B) rangerEffects;
	void addEffect(RangerEffect!B rangerEffect){
		rangerEffects~=move(rangerEffect);
	}
	void removeRangerEffect(int i){
		if(i+1<rangerEffects.length) rangerEffects[i]=move(rangerEffects[$-1]);
		rangerEffects.length=rangerEffects.length-1;
	}
	Array!(RangerProjectile!B) rangerProjectiles;
	void addEffect(RangerProjectile!B rangerProjectile){
		rangerProjectiles~=move(rangerProjectile);
	}
	void removeRangerProjectile(int i){
		if(i+1<rangerProjectiles.length) rangerProjectiles[i]=move(rangerProjectiles[$-1]);
		rangerProjectiles.length=rangerProjectiles.length-1;
	}
	Array!(NecrylProjectile!B) necrylProjectiles;
	void addEffect(NecrylProjectile!B necrylProjectile){
		necrylProjectiles~=necrylProjectile;
	}
	void removeNecrylProjectile(int i){
		if(i+1<necrylProjectiles.length) necrylProjectiles[i]=move(necrylProjectiles[$-1]);
		necrylProjectiles.length=necrylProjectiles.length-1;
	}
	Array!Poison poisons;
	void addEffect(Poison poison){
		poisons~=poison;
	}
	void removePoison(int i){
		if(i+1<poisons.length) poisons[i]=move(poisons[$-1]);
		poisons.length=poisons.length-1;
	}
	Array!(ScarabProjectile!B) scarabProjectiles;
	void addEffect(ScarabProjectile!B scarabProjectile){
		scarabProjectiles~=scarabProjectile;
	}
	void removeScarabProjectile(int i){
		if(i+1<scarabProjectiles.length) scarabProjectiles[i]=move(scarabProjectiles[$-1]);
		scarabProjectiles.length=scarabProjectiles.length-1;
	}
	Array!(BasiliskProjectile!B) basiliskProjectiles;
	void addEffect(BasiliskProjectile!B basiliskProjectile){
		basiliskProjectiles~=basiliskProjectile;
	}
	void removeBasiliskProjectile(int i){
		if(i+1<basiliskProjectiles.length) basiliskProjectiles[i]=move(basiliskProjectiles[$-1]);
		basiliskProjectiles.length=basiliskProjectiles.length-1;
	}
	Array!BasiliskEffect basiliskEffects;
	void addEffect(BasiliskEffect basiliskEffect){
		basiliskEffects~=basiliskEffect;
	}
	void removeBasiliskEffect(int i){
		if(i+1<basiliskEffects.length) basiliskEffects[i]=move(basiliskEffects[$-1]);
		basiliskEffects.length=basiliskEffects.length-1;
	}
	Array!Petrification petrifications;
	void addEffect(Petrification petrification){
		petrifications~=petrification;
	}
	void removePetrification(int i){
		if(i+1<petrifications.length) petrifications[i]=move(petrifications[$-1]);
		petrifications.length=petrifications.length-1;
	}
	Array!(TickfernoProjectile!B) tickfernoProjectiles;
	void addEffect(TickfernoProjectile!B tickfernoProjectile){
		tickfernoProjectiles~=tickfernoProjectile;
	}
	void removeTickfernoProjectile(int i){
		if(i+1<tickfernoProjectiles.length) tickfernoProjectiles[i]=move(tickfernoProjectiles[$-1]);
		tickfernoProjectiles.length=tickfernoProjectiles.length-1;
	}
	Array!TickfernoEffect tickfernoEffects;
	void addEffect(TickfernoEffect tickfernoEffect){
		tickfernoEffects~=tickfernoEffect;
	}
	void removeTickfernoEffect(int i){
		if(i+1<tickfernoEffects.length) tickfernoEffects[i]=move(tickfernoEffects[$-1]);
		tickfernoEffects.length=tickfernoEffects.length-1;
	}
	Array!(VortickProjectile!B) vortickProjectiles;
	void addEffect(VortickProjectile!B vortickProjectile){
		vortickProjectiles~=vortickProjectile;
	}
	void removeVortickProjectile(int i){
		if(i+1<vortickProjectiles.length) vortickProjectiles[i]=move(vortickProjectiles[$-1]);
		vortickProjectiles.length=vortickProjectiles.length-1;
	}
	Array!VortickEffect vortickEffects;
	void addEffect(VortickEffect vortickEffect){
		vortickEffects~=vortickEffect;
	}
	void removeVortickEffect(int i){
		if(i+1<vortickEffects.length) vortickEffects[i]=move(vortickEffects[$-1]);
		vortickEffects.length=vortickEffects.length-1;
	}
	Array!(VortexEffect!B) vortexEffects;
	void addEffect(VortexEffect!B vortexEffect){
		vortexEffects~=move(vortexEffect);
	}
	void removeVortexEffect(int i){
		if(i+1<vortexEffects.length) swap(vortexEffects[i],vortexEffects[$-1]);
		vortexEffects.length=vortexEffects.length-1; // TODO: reuse memory?
	}
	Array!(SquallProjectile!B) squallProjectiles;
	void addEffect(SquallProjectile!B squallProjectile){
		squallProjectiles~=squallProjectile;
	}
	void removeSquallProjectile(int i){
		if(i+1<squallProjectiles.length) squallProjectiles[i]=move(squallProjectiles[$-1]);
		squallProjectiles.length=squallProjectiles.length-1;
	}
	Array!SquallEffect squallEffects;
	void addEffect(SquallEffect squallEffect){
		squallEffects~=squallEffect;
	}
	void removeSquallEffect(int i){
		if(i+1<squallEffects.length) squallEffects[i]=move(squallEffects[$-1]);
		squallEffects.length=squallEffects.length-1;
	}
	Array!(Pushback!B) pushbacks;
	void addEffect(Pushback!B pushback){
		pushbacks~=move(pushback);
	}
	void removePushback(int i){
		if(i+1<pushbacks.length) swap(pushbacks[i],pushbacks[$-1]);
		pushbacks.length=pushbacks.length-1; // TODO: reuse memory?
	}
	Array!(FlummoxProjectile!B) flummoxProjectiles;
	void addEffect(FlummoxProjectile!B flummoxProjectile){
		flummoxProjectiles~=flummoxProjectile;
	}
	void removeFlummoxProjectile(int i){
		if(i+1<flummoxProjectiles.length) swap(flummoxProjectiles[i],flummoxProjectiles[$-1]);
		flummoxProjectiles.length=flummoxProjectiles.length-1; // TODO: reuse memory?
	}
	Array!(PyromaniacRocket!B) pyromaniacRockets;
	void addEffect(PyromaniacRocket!B pyromaniacRocket){
		pyromaniacRockets~=pyromaniacRocket;
	}
	void removePyromaniacRocket(int i){
		if(i+1<pyromaniacRockets.length) pyromaniacRockets[i]=move(pyromaniacRockets[$-1]);
		pyromaniacRockets.length=pyromaniacRockets.length-1;
	}
	Array!(GnomeEffect!B) gnomeEffects;
	void addEffect(GnomeEffect!B gnomeEffect){
		gnomeEffects~=gnomeEffect;
	}
	void removeGnomeEffect(int i){
		if(i+1<gnomeEffects.length) gnomeEffects[i]=move(gnomeEffects[$-1]);
		gnomeEffects.length=gnomeEffects.length-1;
	}
	Array!(PoisonDart!B) poisonDarts;
	void addEffect(PoisonDart!B poisonDart){
		poisonDarts~=poisonDart;
	}
	void removePoisonDart(int i){
		if(i+1<poisonDarts.length) poisonDarts[i]=move(poisonDarts[$-1]);
		poisonDarts.length=poisonDarts.length-1;
	}
	Array!(MutantProjectile!B) mutantProjectiles;
	void addEffect(MutantProjectile!B mutantProjectile){
		mutantProjectiles~=mutantProjectile;
	}
	void removeMutantProjectile(int i){
		if(i+1<mutantProjectiles.length) swap(mutantProjectiles[i],mutantProjectiles[$-1]);
		mutantProjectiles.length=mutantProjectiles.length-1; // TODO: reuse memory?
	}
	// abilities
	Array!(RockForm!B) rockForms;
	void addEffect(RockForm!B rockForm){
		rockForms~=move(rockForm);
	}
	void removeRockForm(int i){
		if(i+1<rockForms.length) rockForms[i]=move(rockForms[$-1]);
		rockForms.length=rockForms.length-1;
	}
	Array!(Stealth!B) stealths;
	void addEffect(Stealth!B stealth){
		stealths~=move(stealth);
	}
	void removeStealth(int i){
		if(i+1<stealths.length) stealths[i]=move(stealths[$-1]);
		stealths.length=stealths.length-1;
	}
	Array!(LifeShield!B) lifeShields;
	void addEffect(LifeShield!B lifeShield){
		lifeShields~=move(lifeShield);
	}
	void removeLifeShield(int i){
		if(i+1<lifeShields.length) lifeShields[i]=move(lifeShields[$-1]);
		lifeShields.length=lifeShields.length-1;
	}
	Array!(DivineSight!B) divineSights;
	void addEffect(DivineSight!B divineSight){
		divineSights~=divineSight;
	}
	void removeDivineSight(int i){
		if(i+1<divineSights.length) divineSights[i]=move(divineSights[$-1]);
		divineSights.length=divineSights.length-1;
	}
	Array!(SteamCloud!B) steamClouds;
	void addEffect(SteamCloud!B steamCloud){
		steamClouds~=steamCloud;
	}
	void removeSteamCloud(int i){
		if(i+1<steamClouds.length) steamClouds[i]=move(steamClouds[$-1]);
		steamClouds.length=steamClouds.length-1;
	}
	Array!(PoisonCloud!B) poisonClouds;
	void addEffect(PoisonCloud!B poisonCloud){
		poisonClouds~=poisonCloud;
	}
	void removePoisonCloud(int i){
		if(i+1<poisonClouds.length) poisonClouds[i]=move(poisonClouds[$-1]);
		poisonClouds.length=poisonClouds.length-1;
	}
	Array!(BlightMite!B) blightMites;
	void addEffect(BlightMite!B blightMite){
		blightMites~=blightMite;
	}
	void removeBlightMite(int i){
		if(i+1<blightMites.length) blightMites[i]=move(blightMites[$-1]);
		blightMites.length=blightMites.length-1;
	}
	Array!(LightningCharge!B) lightningCharges;
	void addEffect(LightningCharge!B lightningCharge){
		lightningCharges~=lightningCharge;
	}
	void removeLightningCharge(int i){
		if(i+1<lightningCharges.length) lightningCharges[i]=move(lightningCharges[$-1]);
		lightningCharges.length=lightningCharges.length-1;
	}
	Array!(WebPull!B) webPulls;
	void addEffect(WebPull!B webPull){
		webPulls~=webPull;
	}
	void removeWebPull(int i){
		if(i+1<webPulls.length) webPulls[i]=move(webPulls[$-1]);
		webPulls.length=webPulls.length-1;
	}
	Array!(CagePull!B) cagePulls;
	void addEffect(CagePull!B cagePull){
		cagePulls~=cagePull;
	}
	void removeCagePull(int i){
		if(i+1<cagePulls.length) cagePulls[i]=move(cagePulls[$-1]);
		cagePulls.length=cagePulls.length-1;
	}
	Array!(StickyBomb!B) stickyBombs;
	void addEffect(StickyBomb!B stickyBomb){
		stickyBombs~=stickyBomb;
	}
	void removeStickyBomb(int i){
		if(i+1<stickyBombs.length) stickyBombs[i]=move(stickyBombs[$-1]);
		stickyBombs.length=stickyBombs.length-1;
	}
	Array!(OilProjectile!B) oilProjectiles;
	void addEffect(OilProjectile!B oilProjectile){
		oilProjectiles~=oilProjectile;
	}
	void removeOilProjectile(int i){
		if(i+1<oilProjectiles.length) oilProjectiles[i]=move(oilProjectiles[$-1]);
		oilProjectiles.length=oilProjectiles.length-1;
	}
	Array!(Oil!B) oils;
	void addEffect(Oil!B oil){
		oils~=oil;
	}
	void removeOil(int i){
		if(i+1<oils.length) oils[i]=move(oils[$-1]);
		oils.length=oils.length-1;
	}
	Array!(HealingShower!B) healingShowers;
	void addEffect(HealingShower!B healingShower){
		healingShowers~=healingShower;
	}
	void removeHealingShower(int i){
		if(i+1<healingShowers.length) healingShowers[i]=move(healingShowers[$-1]);
		healingShowers.length=healingShowers.length-1;
	}
	Array!(Protector!B) protectors;
	void addEffect(Protector!B protector){
		protectors~=protector;
	}
	void removeProtector(int i){
		if(i+1<protectors.length) protectors[i]=move(protectors[$-1]);
		protectors.length=protectors.length-1;
	}
	// special effects
	Array!Appearance appearances;
	void addEffect(Appearance appearance){
		appearances~=appearance;
	}
	void removeAppearance(int i){
		if(i+1<appearances.length) appearances[i]=move(appearances[$-1]);
		appearances.length=appearances.length-1;
	}
	Array!Disappearance disappearances;
	void addEffect(Disappearance disappearance){
		disappearances~=disappearance;
	}
	void removeDisappearance(int i){
		if(i+1<disappearances.length) disappearances[i]=move(disappearances[$-1]);
		disappearances.length=disappearances.length-1;
	}
	Array!AltarDestruction altarDestructions;
	void addEffect(AltarDestruction altarDestruction){
		altarDestructions~=altarDestruction;
	}
	void removeAltarDestruction(int i){
		if(i+1<altarDestructions.length) altarDestructions[i]=move(altarDestructions[$-1]);
		altarDestructions.length=altarDestructions.length-1;
	}
	Array!ScreenShake screenShakes;
	void addEffect(ScreenShake screenShake){
		screenShakes~=screenShake;
	}
	void removeScreenShake(int i){
		if(i+1<screenShakes.length) screenShakes[i]=move(screenShakes[$-1]);
		screenShakes.length=screenShakes.length-1;
	}
	Array!TestDisplacement testDisplacements;
	void addEffect(TestDisplacement testDisplacement){
		testDisplacements~=testDisplacement;
	}
	void removeTestDisplacement(int i){
		if(i+1<testDisplacements.length) testDisplacements[i]=move(testDisplacements[$-1]);
		testDisplacements.length=testDisplacements.length-1;
	}
	mixin Assign;
}

struct CommandCone(B){
	int side;
	CommandConeColor color;
	Vector3f position;
	int lifetime=cast(int)(SacCommandCone!B.lifetime*updateFPS);
}
struct CommandCones(B){
	struct CommandConeElement{
		Vector3f position;
		int lifetime;
		this(CommandCone!B rhs){
			position=rhs.position;
			lifetime=rhs.lifetime;
		}
	}
	Array!(Array!(CommandConeElement)[CommandConeColor.max+1]) cones;
	mixin Assign;
	this(int numSides){
		initialize(numSides);
	}
	void initialize(int numSides){
		cones.length=numSides;
	}
	void addCommandCone(CommandCone!B cone){
		cones[cone.side][cone.color]~=CommandConeElement(cone);
	}
	void removeCommandCone(int side,CommandConeColor color,int index){
		if(index+1<cones[side][color].length) cones[side][color][index]=cones[side][color][$-1];
		cones[side][color].length=cones[side][color].length-1;
	}
}

struct Objects(B,RenderMode mode){
	Array!(MovingObjects!(B,mode)) movingObjects;
	Array!(StaticObjects!(B,mode)) staticObjects;
	static if(mode == RenderMode.opaque){
		FixedObjects!B[] fixedObjects;
		Souls!B souls;
		Buildings!B buildings;
		WizardInfos!B wizards;
		Array!(Particles!(B,false)) particles;
		Array!(Particles!(B,true)) relativeParticles;
		Array!(Particles!(B,false,true)) filteredParticles;
		Effects!B effects;
		CommandCones!B commandCones;
	}
	mixin Assign;
	int getIndex(T)(SacObject!B sacObject,bool insert) if(is(T==MovingObject!B)||is(T==StaticObject!B)){
		static if(is(T==MovingObject!B)){
			// cache, does not change semantics
			auto cand=sacObject.stateIndex[mode];
			if(0<=cand&&cand<movingObjects.length)
				if(movingObjects[cand].sacObject is sacObject)
					return cand;
			foreach(i,ref obj;movingObjects.data)
				if(obj.sacObject is sacObject)
					return sacObject.stateIndex[mode]=cast(int)i;
			if(insert){
				movingObjects.length=movingObjects.length+1;
				movingObjects[$-1].sacObject=sacObject;
				return sacObject.stateIndex[mode]=cast(int)movingObjects.length-1;
			}
			return sacObject.stateIndex[mode]=-1;
		}else{
			auto cand=sacObject.stateIndex[mode];
			if(0<=cand&&cand<staticObjects.length)
				if(staticObjects[cand].sacObject is sacObject)
					return cand;
			foreach(i,ref obj;staticObjects.data)
				if(obj.sacObject is sacObject)
					return sacObject.stateIndex[mode]=cast(int)i;
			if(insert){
				staticObjects.length=staticObjects.length+1;
				staticObjects[$-1].sacObject=sacObject;
				return sacObject.stateIndex[mode]=cast(int)staticObjects.length-1;
			}
			return sacObject.stateIndex[mode]=-1;
		}
	}
	Id addObject(T)(T object) if(is(T==MovingObject!B)||is(T==StaticObject!B))in{
		assert(object.id!=0);
	}do{
		Id result;
		auto index=getIndex!T(object.sacObject,true);
		static if(is(T==MovingObject!B)){
			enforce(0<=index && index<numMoving);
			enforce(index<movingObjects.length);
			result=Id(mode,index,movingObjects[index].length);
			movingObjects[index].addObject(object);
		}else{
			enforce(0<=index && index<numStatic);
			enforce(index<staticObjects.length);
			result=Id(mode,index+numMoving,staticObjects[index].length);
			staticObjects[index].addObject(object);
		}
		return result;
	}
	void removeObject(int type, int index, ref ObjectManager!B manager){
		if(type<numMoving){
			movingObjects[type].removeObject(index,manager);
		}else if(type<numMoving+numStatic){
			staticObjects[type-numMoving].removeObject(index,manager);
		}else static if(mode==RenderMode.opaque){
			final switch(cast(ObjectType)type){
				case ObjectType.soul: souls.removeObject(index,manager); break;
				case ObjectType.building: buildings.removeObject(index,manager); break;
			}
		}else enforce(0);
	}
	static if(mode==RenderMode.transparent){
		void setAlpha(int type, int index, float alpha, float energy){
			enforce(0<=type&&type<numMoving);
			movingObjects[type].setAlpha(index, alpha, energy);
		}
		void setThresholdZ(int type, int index, float thresholdZ){
			enforce(numMoving<=type&&type<numMoving+numStatic);
			staticObjects[type-numMoving].setThresholdZ(index, thresholdZ);
		}
	}
	static if(mode==RenderMode.opaque){
		int getIndexFixed(SacObject!B sacObject,bool insert){
			// cache, does not change semantics
			auto cand=sacObject.stateIndex[mode];
			if(0<=cand&&cand<fixedObjects.length)
				if(fixedObjects[cand].sacObject is sacObject)
					return cand;
			foreach(i,ref obj;fixedObjects)
				if(obj.sacObject is sacObject)
					return sacObject.stateIndex[mode]=cast(int)i;
			if(insert){
				fixedObjects.length=fixedObjects.length+1;
				fixedObjects[$-1].sacObject=sacObject;
				return sacObject.stateIndex[mode]=cast(int)fixedObjects.length-1;
			}
			return sacObject.stateIndex[mode]=-1;
		}
		void addFixed(FixedObject!B object){
			auto index=getIndexFixed(object.sacObject,true);
			enforce(0<=index&&index<fixedObjects.length);
			fixedObjects[index].addFixed(object);
		}
		Id addObject(Soul!B object){
			auto result=Id(mode,ObjectType.soul,souls.length);
			souls.addObject(object);
			return result;
		}
		Id addObject(Building!B object){
			auto result=Id(mode,ObjectType.building,buildings.length);
			buildings.addObject(move(object));
			return result;
		}
		void addWizard(WizardInfo!B wizard){
			wizards.addWizard(move(wizard));
		}
		WizardInfo!B* getWizard(int id){
			return wizards.getWizard(id);
		}
		WizardInfo!B* getWizardForSide(int side,ObjectState!B state){
			return wizards.getWizardForSide(side,state);
		}
		void removeWizard(int id){
			wizards.removeWizard(id);
		}
		void addEffect(T)(T proj){
			effects.addEffect(move(proj));
		}
		int getIndexParticle(bool relative,bool sideFiltered)(SacParticle!B sacParticle,bool insert){
			static if(sideFiltered){
				static assert(!relative);
				alias particles=filteredParticles;
			}else static if(relative) alias particles=relativeParticles;
			// cache, does not change semantics
			auto cand=sacParticle.stateIndex;
			if(0<=cand&&cand<particles.length)
				if(particles[cand].sacParticle is sacParticle)
					return cand;
			foreach(i,ref par;particles.data)
				if(par.sacParticle is sacParticle)
					return sacParticle.stateIndex=cast(int)i;
			if(insert){
				particles.length=particles.length+1;
				particles[$-1].sacParticle=sacParticle;
				return sacParticle.stateIndex=cast(int)particles.length-1;
			}
			return sacParticle.stateIndex=-1;
		}
		void addParticle(bool relative,bool sideFiltered)(Particle!(B,relative,sideFiltered) particle){
			auto index=getIndexParticle!(relative,sideFiltered)(particle.sacParticle,true);
			static if(sideFiltered){
				static assert(!relative);
				alias particles=filteredParticles;
			}else static if(relative) alias particles=relativeParticles;
			enforce(0<=index && index<particles.length);
			particles[index].addParticle(particle);
		}
		void addCommandCone(CommandCone!B cone){
			if(!commandCones.cones.length) commandCones.initialize(32); // TODO: do this eagerly?
			commandCones.addCommandCone(cone);
		}
	}
}
auto each(alias f,B,RenderMode mode,T...)(ref Objects!(B,mode) objects,T args){
	with(objects){
		static if(mode == RenderMode.opaque){
			foreach(ref staticObject;staticObjects)
				staticObject.each!f(args);
			foreach(ref fixedObject;fixedObjects)
				fixedObject.each!f(args);
			souls.each!f(args);
		}
		foreach(ref movingObject;movingObjects)
			movingObject.each!f(args);
	}
}
auto eachMoving(alias f,B,RenderMode mode,T...)(ref Objects!(B,mode) objects,T args){
	with(objects){
		foreach(ref movingObject;movingObjects)
			movingObject.each!f(args);
	}
}
auto eachStatic(alias f,B,RenderMode mode,T...)(ref Objects!(B,mode) objects,T args){
	with(objects){
		foreach(ref staticObject;staticObjects)
			staticObject.each!f(args);
	}
}
auto eachSoul(alias f,B,T...)(ref Objects!(B,RenderMode.opaque) objects,T args){
	objects.souls.each!f(args);
}
auto eachBuilding(alias f,B,T...)(ref Objects!(B,RenderMode.opaque) objects,T args){
	objects.buildings.each!f(args);
}
auto eachWizard(alias f,B,T...)(ref Objects!(B,RenderMode.opaque) objects,T args){
	objects.wizards.each!f(args);
}
auto eachEffects(alias f,B,T...)(ref Objects!(B,RenderMode.opaque) objects,T args){
	f(objects.effects,args);
}
auto eachParticles(alias f,B,T...)(ref Objects!(B,RenderMode.opaque) objects,T args){
	with(objects){
		foreach(ref particle;particles)
			f(particle,args);
		foreach(ref particle;relativeParticles)
			f(particle,args);
		foreach(ref particle;filteredParticles)
			f(particle,args);
	}
}
auto eachCommandCones(alias f,B,T...)(ref Objects!(B,RenderMode.opaque) objects,T args){
	f(objects.commandCones,args);
}
auto eachByType(alias f,bool movingFirst=true,bool particlesBeforeEffects=false,B,RenderMode mode,T...)(ref Objects!(B,mode) objects,T args){
	with(objects){
		static if(movingFirst)
			foreach(ref movingObject;movingObjects)
				f(movingObject,args);
		foreach(ref staticObject;staticObjects)
			f(staticObject,args);
		static if(mode == RenderMode.opaque){
			foreach(ref fixedObject;fixedObjects)
				f(fixedObject,args);
			f(souls,args);
			f(buildings,args);
			static if(!particlesBeforeEffects) f(effects,args);
			foreach(ref particle;particles)
				f(particle,args);
			foreach(ref particle;relativeParticles)
				f(particle,args);
			foreach(ref particle;filteredParticles)
				f(particle,args);
			static if(particlesBeforeEffects) f(effects,args);
			f(commandCones,args);
		}
		static if(!movingFirst)
			foreach(ref movingObject;movingObjects)
				f(movingObject,args);
	}
}
auto eachMovingOf(alias f,B,RenderMode mode,T...)(ref Objects!(B,mode) objects,SacObject!B sacObject,T args){
	with(objects){
		auto index=objects.getIndex!(MovingObject!B)(sacObject,false);
		if(index==-1||index>=movingObjects.length) return;
		each!f(movingObjects[index],args);
	}
}

enum numMoving=100;
enum numStatic=300;
enum ObjectType{
	soul=numMoving+numStatic,
	building,
}

struct ObjectManager(B){
	Array!Id ids;
	Objects!(B,RenderMode.opaque) opaqueObjects;
	Objects!(B,RenderMode.transparent) transparentObjects;
	mixin Assign;
	int addObject(T)(T object) if(is(T==MovingObject!B)||is(T==StaticObject!B)||is(T==Soul!B)||is(T==Building!B))in{
		assert(object.id==0);
	}do{
		if(ids.length>=int.max) return 0;
		auto id=object.id=cast(int)ids.length+1;
		ids~=opaqueObjects.addObject(move(object));
		return id;
	}
	void removeObject(int id)in{
		assert(0<id && id<=ids.length);
	}do{
		auto tid=ids[id-1];
		if(tid==Id.init) return; // already deleted
		scope(success) assert(ids[id-1]==Id.init);
		final switch(tid.mode){
			case RenderMode.opaque: opaqueObjects.removeObject(tid.type,tid.index,this); break;
			case RenderMode.transparent: transparentObjects.removeObject(tid.type,tid.index,this); break;
		}
	}
	void setAlpha(int id,float alpha, float energy)in{
		assert(0<id && id<=ids.length);
	}do{
		auto tid=ids[id-1];
		enforce(tid.mode==RenderMode.transparent);
		transparentObjects.setAlpha(tid.type,tid.index,alpha,energy);
	}
	void setThresholdZ(int id,float thresholdZ)in{
		assert(0<id && id<=ids.length);
	}do{
		auto tid=ids[id-1];
		enforce(tid.mode==RenderMode.transparent);
		transparentObjects.setThresholdZ(tid.type,tid.index,thresholdZ);
	}
	void setRenderMode(T,RenderMode mode)(int id)if(is(T==MovingObject!B)||is(T==StaticObject!B)){
		auto tid=ids[id-1];
		if(tid.mode==mode) return;
		static if(mode==RenderMode.opaque){
			alias old=transparentObjects;
			alias new_=opaqueObjects;
		}else static if(mode==RenderMode.transparent){
			alias old=opaqueObjects;
			alias new_=transparentObjects;
		}else static assert(0);
		static if(is(T==MovingObject!B)){
			auto obj=this.movingObjectById!((obj)=>move(obj),function MovingObject!B(){ assert(0); })(id);
		}else{
			auto obj=this.staticObjectById!((obj)=>move(obj),function StaticObject!B(){ assert(0); })(id);
		}
		old.removeObject(tid.type,tid.index,this);
		ids[id-1]=new_.addObject(obj);
	}
	bool isValidId(int id){
		if(0<id && id<=ids.length)
			return ids[id-1]!=Id.init;
		return false;
	}
	bool isValidBuilding(int id){
		if(0<id && id<=ids.length)
			return ids[id-1].type==ObjectType.building;
		return false;
	}
	bool isValidTarget(int id){
		if(0<id && id<=ids.length){
			if(ids[id-1]==Id.init) return false;
			return ids[id-1].type<numMoving+numStatic||ids[id-1].type==ObjectType.soul;
		}
		return false;
	}
	bool isValidTarget(int id,TargetType type){
		if(0<id && id<=ids.length){
			if(ids[id-1]==Id.init) return false;
			auto objType=ids[id-1].type;
			if(objType<numMoving) return type==TargetType.creature;
			if(objType<numMoving+numStatic) return type==TargetType.building;
			if(objType==ObjectType.soul) return type==TargetType.soul;
		}
		return false;
	}
	TargetType targetTypeFromId(int id){
		if(0<id && id<=ids.length){
			if(ids[id-1]==Id.init) return TargetType.none;
			auto objType=ids[id-1].type;
			if(objType<numMoving) return TargetType.creature;
			if(objType<numMoving+numStatic) return TargetType.building;
			if(objType==ObjectType.soul) return TargetType.soul;
		}
		return TargetType.none;
	}
	void addWizard(WizardInfo!B wizard){
		opaqueObjects.addWizard(wizard);
	}
	WizardInfo!B* getWizard(int id){
		return opaqueObjects.getWizard(id);
	}
	WizardInfo!B* getWizardForSide(int side,ObjectState!B state){
		return opaqueObjects.getWizardForSide(side,state);
	}
	void removeWizard(int id){
		opaqueObjects.removeWizard(id);
	}
	void addFixed(FixedObject!B object){
		opaqueObjects.addFixed(object);
	}
	void addEffect(T)(T proj){
		opaqueObjects.addEffect(proj);
	}
	void addParticle(bool relative,bool sideFiltered)(Particle!(B,relative,sideFiltered) particle){
		opaqueObjects.addParticle(particle);
	}
	void addCommandCone(CommandCone!B cone){
		opaqueObjects.addCommandCone(cone);
	}
}
auto each(alias f,B,T...)(ref ObjectManager!B objectManager,T args){
	with(objectManager){
		opaqueObjects.each!f(args);
		transparentObjects.each!f(args);
	}
}
auto eachMoving(alias f,B,T...)(ref ObjectManager!B objectManager,T args){
	with(objectManager){
		opaqueObjects.eachMoving!f(args);
		transparentObjects.eachMoving!f(args);
	}
}
auto eachStatic(alias f,B,T...)(ref ObjectManager!B objectManager,T args){
	with(objectManager){
		opaqueObjects.eachStatic!f(args);
		transparentObjects.eachStatic!f(args);
	}
}
auto eachSoul(alias f,B,T...)(ref ObjectManager!B objectManager,T args){
	with(objectManager) opaqueObjects.eachSoul!f(args);
}
auto eachBuilding(alias f,B,T...)(ref ObjectManager!B objectManager,T args){
	with(objectManager) opaqueObjects.eachBuilding!f(args);
}
auto eachWizard(alias f,B,T...)(ref ObjectManager!B objectManager,T args){
	with(objectManager) opaqueObjects.eachWizard!f(args);
}
auto eachEffects(alias f,B,T...)(ref ObjectManager!B objectManager,T args){
	with(objectManager) opaqueObjects.eachEffects!f(args);
}
auto eachParticles(alias f,B,T...)(ref ObjectManager!B objectManager,T args){
	with(objectManager) opaqueObjects.eachParticles!f(args);
}
auto eachCommandCones(alias f,B,T...)(ref ObjectManager!B objectManager,T args){
	with(objectManager) opaqueObjects.eachCommandCones!f(args);
}
auto eachByType(alias f,bool movingFirst=true,bool particlesBeforeEffects=false,B,T...)(ref ObjectManager!B objectManager,T args){
	with(objectManager){
		opaqueObjects.eachByType!(f,movingFirst,particlesBeforeEffects)(args);
		transparentObjects.eachByType!(f,movingFirst,particlesBeforeEffects)(args);
	}
}
auto eachMovingOf(alias f,B,T...)(ref ObjectManager!B objectManager,SacObject!B sacObject,T args){
	with(objectManager){
		opaqueObjects.eachMovingOf!f(sacObject,args);
		transparentObjects.eachMovingOf!f(sacObject,args);
	}
}
auto ref objectById(alias f,B,T...)(ref ObjectManager!B objectManager,int id,T args)in{
	assert(id>0);
}do{
	auto nid=objectManager.ids[id-1];
	assert(nid!=Id.init);
	if(nid.type<numMoving){
		enum byRef=!is(typeof(f(MovingObject!B.init,args))); // TODO: find a better way to check whether argument taken by reference!
		final switch(nid.mode){
			case RenderMode.opaque:
				auto obj=objectManager.opaqueObjects.movingObjects[nid.type].fetch(nid.index);
				scope(success) objectManager.opaqueObjects.movingObjects[nid.type][nid.index]=move(obj);
				return f(obj,args);
			case RenderMode.transparent:
				auto obj=objectManager.transparentObjects.movingObjects[nid.type].fetch(nid.index);
				scope(success) objectManager.transparentObjects.movingObjects[nid.type][nid.index]=move(obj);
				return f(obj,args);
		}
	}else{
		enum byRef=!is(typeof(f(StaticObject!B.init,args))); // TODO: find a better way to check whether argument taken by reference!
		enforce(nid.type<numMoving+numStatic,text(nid.type));
		final switch(nid.mode){
			case RenderMode.opaque:
				static if(byRef){
					auto obj=objectManager.opaqueObjects.staticObjects[nid.type-numMoving][nid.index];
					scope(success) objectManager.opaqueObjects.staticObjects[nid.type-numMoving][nid.index]=obj;
					return f(obj,args);
				}else return f(objectManager.opaqueObjects.staticObjects[nid.type-numMoving][nid.index],args);
			case RenderMode.transparent:
				static if(byRef){
					auto obj=objectManager.transparentObjects.staticObjects[nid.type-numMoving][nid.index];
					scope(success) objectManager.transparentObjects.staticObjects[nid.type-numMoving][nid.index]=obj;
					return f(obj,args);
				}else return f(objectManager.transparentObjects.staticObjects[nid.type-numMoving][nid.index],args);
		}
	}
}
auto ref movingObjectById(alias f,alias nonMoving,B,T...)(ref ObjectManager!B objectManager,int id,T args)in{
	assert(id>0);
}do{
	auto nid=objectManager.ids[id-1];
	enum byRef=!is(typeof(f(MovingObject!B.init,args))); // TODO: find a better way to check whether argument taken by reference!
	if(nid.type<numMoving&&nid.index!=-1){
		final switch(nid.mode){ // TODO: get rid of code duplication
			case RenderMode.opaque:
				auto obj=objectManager.opaqueObjects.movingObjects[nid.type].fetch(nid.index);
				scope(success) objectManager.opaqueObjects.movingObjects[nid.type][nid.index]=move(obj);
				return f(obj,args);
			case RenderMode.transparent:
				auto obj=objectManager.transparentObjects.movingObjects[nid.type].fetch(nid.index);
				scope(success) objectManager.transparentObjects.movingObjects[nid.type][nid.index]=move(obj);
				return f(obj,args);
		}
	}else return nonMoving();
}
auto ref staticObjectById(alias f,alias nonStatic,B,T...)(ref ObjectManager!B objectManager,int id,T args)in{
	assert(id>0);
}do{
	auto nid=objectManager.ids[id-1];
	enum byRef=!is(typeof(f(StaticObject!B.init,args))); // TODO: find a better way to check whether argument taken by reference!
	if(nid.type<numMoving||nid.index==-1) return nonStatic();
	else if(nid.type<numMoving+numStatic){
		final switch(nid.mode){
			case RenderMode.opaque:
				static if(byRef){
					auto obj=objectManager.opaqueObjects.staticObjects[nid.type-numMoving].fetch(nid.index);
					scope(success) objectManager.opaqueObjects.staticObjects[nid.type-numMoving][nid.index]=obj;
					return f(obj,args);
				}else return f(objectManager.opaqueObjects.staticObjects[nid.type-numMoving][nid.index],args);
			case RenderMode.transparent:
				static if(byRef){
					auto obj=objectManager.transparentObjects.staticObjects[nid.type-numMoving].fetch(nid.index);
					scope(success) objectManager.transparentObjects.staticObjects[nid.type-numMoving][nid.index]=obj;
					return f(obj,args);
				}else return f(objectManager.transparentObjects.staticObjects[nid.type-numMoving][nid.index],args);
		}
	}else return nonStatic();
}
auto ref soulById(alias f,alias noSoul,B,T...)(ref ObjectManager!B objectManager,int id,T args)in{
	assert(id>0);
}do{
	auto nid=objectManager.ids[id-1];
	if(nid.type!=ObjectType.soul||nid.index==-1) return noSoul();
	return f(objectManager.opaqueObjects.souls[nid.index],args);
}
auto ref buildingById(alias f,alias noBuilding,B,T...)(ref ObjectManager!B objectManager,int id,T args)in{
	assert(id>0);
}do{
	auto nid=objectManager.ids[id-1];
	if(nid.type!=ObjectType.building||nid.index==-1) return noBuilding();
	enum byRef=!is(typeof(f(Building!B.init,args))); // TODO: find a better way to check whether argument taken by reference!
	static assert(byRef);
	return f(objectManager.opaqueObjects.buildings[nid.index],args);
}

void setCreatureState(B)(ref MovingObject!B object,ObjectState!B state){
	if(object.creatureStats.effects.immobilized) object.creatureState.mode=CreatureMode.stunned;
	auto sacObject=object.sacObject;
	final switch(object.creatureState.mode){
		case CreatureMode.idle, CreatureMode.rockForm:
			bool isDamaged=object.isDamaged;
			if(object.creatureState.movement!=CreatureMovement.flying){
				if(object.animationState.among(AnimationState.run,AnimationState.walk) && object.creatureState.timer<0.1f*updateFPS)
					break;
				object.frame=0;
			}
			object.creatureState.timer=0;
			if(object.frame==0){
				if(isDamaged&&sacObject.hasAnimationState(AnimationState.stance2))
					object.animationState=AnimationState.stance2;
				else object.animationState=AnimationState.stance1;
			}
			if(sacObject.mustFly) object.creatureState.movement=CreatureMovement.flying;
			final switch(object.creatureState.movement){
				case CreatureMovement.onGround:
					break;
				case CreatureMovement.flying:
					assert(sacObject.canFly);
					if(!sacObject.mustFly && (object.frame==0||object.animationState==AnimationState.fly&&sacObject.seamlessFlyAndHover))
						object.animationState=AnimationState.hover;
					break;
				case CreatureMovement.tumbling:
					object.creatureState.mode=CreatureMode.stunned;
					break;
			}
			if(object.creatureState.mode==CreatureMode.stunned)
				goto case CreatureMode.stunned;
			if(object.frame==0&&!state.uniform(5)){ // TODO: figure out the original rule for this
				with(AnimationState) if(sacObject.mustFly){
					if(isDamaged&&sacObject.hasAnimationState(idle2)){
						object.animationState=idle2;
					}else{
						static immutable idleCandidatesFlying=[hover,idle0,idle1,idle3]; // TODO: maybe idle3 has a special precondition, like idle2?
						object.pickRandomAnimation(idleCandidatesFlying,state);
					}
				}else if(object.creatureState.movement==CreatureMovement.onGround){
					if(isDamaged&&sacObject.hasAnimationState(idle2)){
						object.animationState=idle2;
					}else{
						static immutable idleCandidatesOnGround=[idle0,idle1,idle3]; // TODO: maybe idle3 has a special precondition, like idle2 ?
						object.pickRandomAnimation(idleCandidatesOnGround,state);
					}
				}
			}
			if(object.id&&object.frame==0&&!state.uniform(5)) // TODO: figure out the original rule for this
				playSoundTypeAt(sacObject,object.id,SoundType.idleTalk,state);
			break;
		case CreatureMode.moving:
			final switch(object.creatureState.movement) with(CreatureMovement){
				case onGround:
					if(!sacObject.canRun){
						if(sacObject.canFly) object.startFlying(state);
						else object.startIdling(state);
						return;
					}
					object.creatureState.timer=0;
					if(!object.animationState.among(AnimationState.run,cast(AnimationState)SacDoctorAnimationState.pickUpCorpse)){
						object.frame=0;
						if(object.isSacDoctor&&object.creatureStats.effects.carrying>0)
							object.animationState=cast(AnimationState)SacDoctorAnimationState.walk;
						else object.animationState=AnimationState.run;
					}
					break;
				case flying:
					if(object.frame==0||object.animationState==AnimationState.hover&&sacObject.seamlessFlyAndHover)
						object.animationState=AnimationState.fly;
					break;
				case tumbling:
					object.creatureState.mode=CreatureMode.stunned;
					break;
			}
			if(object.creatureState.mode==CreatureMode.stunned)
				goto case CreatureMode.stunned;
			break;
		case CreatureMode.dying, CreatureMode.pretendingToDie:
			with(AnimationState){
				static immutable deathCandidatesOnGround=[death0,death1,death2];
				static immutable deathCandidatesFlying=[flyDeath,death0,death1,death2];
				if(sacObject.mustFly||!deathCandidatesOnGround.canFind(object.animationState)){
					object.frame=0;
					final switch(object.creatureState.movement) with(CreatureMovement){
						case onGround:
							assert(!sacObject.mustFly);
							if(object.creatureState.mode!=CreatureMode.pretendingToDie){
								object.pickRandomAnimation(deathCandidatesOnGround,state);
							}else object.animationState=death0;
							break;
						case flying:
							if(sacObject.mustFly&&object.creatureState.mode!=CreatureMode.pretendingToDie){
								object.pickRandomAnimation(deathCandidatesFlying,state);
							}else object.animationState=flyDeath;
							break;
						case tumbling:
							object.animationState=sacObject.hasFalling?falling:sacObject.canTumble?tumble:stance1;
							break;
					}
				}
			}
			break;
		case CreatureMode.preSpawning,CreatureMode.spawning:
			object.frame=0;
			if(sacObject.hasAnimationState(AnimationState.disoriented))
				object.animationState=AnimationState.disoriented;
			else object.animationState=AnimationState.stance1;
			break;
		case CreatureMode.dead, CreatureMode.playingDead:
			object.animationState=AnimationState.death0;
			if(sacObject.mustFly)
				object.animationState=AnimationState.hitFloor;
			object.frame=sacObject.numFrames(object.animationState)*updateAnimFactor-1;
			break;
		case CreatureMode.dissolving:
			object.creatureState.timer=0;
			break;
		case CreatureMode.deadToGhost:
			object.creatureStats.mana=0.0f;
			object.frame=0;
			object.animationState=AnimationState.corpseRise;
			state.updateRenderModeLater(object.id);
			break;
		case CreatureMode.idleGhost:
			if(object.animationState!=AnimationState.floatMove||object.frame>=sacObject.numFrames(AnimationState.floatStatic)*updateAnimFactor)
				object.frame=0;
			object.animationState=AnimationState.floatStatic;
			break;
		case CreatureMode.movingGhost:
			if(object.animationState!=AnimationState.floatStatic||object.frame>=sacObject.numFrames(AnimationState.floatMove)*updateAnimFactor)
				object.frame=0;
			object.animationState=AnimationState.floatMove;
			break;
		case CreatureMode.ghostToIdle:
			object.frame=0;
			object.animationState=AnimationState.float2Stance;
			break;
		case CreatureMode.reviving, CreatureMode.fastReviving, CreatureMode.pretendingToRevive:
			assert(object.frame==sacObject.numFrames(object.animationState)*updateAnimFactor-1);
			static immutable reviveSequence=[AnimationState.corpse,AnimationState.float_];
			object.creatureState.timer=0;
			if(sacObject.hasAnimationState(AnimationState.corpse)){
				object.frame=0;
				object.animationState=AnimationState.corpse;
			}else if(sacObject.hasAnimationState(AnimationState.float_)){
				object.frame=0;
				object.animationState=AnimationState.float_;
			}
			break;
		case CreatureMode.takeoff:
			assert(sacObject.canFly && object.creatureState.movement==CreatureMovement.onGround);
			if(!sacObject.hasAnimationState(AnimationState.takeoff)){
				object.creatureState.movement=CreatureMovement.flying;
				if(sacObject.movingAfterTakeoff){
					object.creatureState.mode=CreatureMode.moving;
					goto case CreatureMode.moving;
				}else{
					object.creatureState.mode=CreatureMode.idle;
					goto case CreatureMode.idle;
				}
			}
			object.frame=0;
			object.animationState=AnimationState.takeoff;
			break;
		case CreatureMode.landing:
			if(object.frame==0){
				if(object.creatureState.movement==CreatureMovement.onGround){
					object.creatureState.mode=CreatureMode.idle;
					goto case CreatureMode.idle;
				}else if(object.position.z<=state.getGroundHeight(object.position)){
					object.creatureState.movement=CreatureMovement.onGround;
					if(!sacObject.hasAnimationState(AnimationState.land)){
						object.creatureState.mode=CreatureMode.idle;
						goto case CreatureMode.idle;
					}
					object.animationState=AnimationState.land;
				}else object.animationState=AnimationState.hover;
			}
			break;
		case CreatureMode.meleeMoving,CreatureMode.meleeAttacking:
			with(AnimationState)
			if(object.frame!=0
			   ||!object.animationState.among(attack0,attack1,attack2,flyAttack)
			   ||object.creatureState.movement==CreatureMovement.tumbling
			){
				object.startIdling(state);
				goto case CreatureMode.idle;
			}
			break;
		case CreatureMode.stunned:
			if(object.creatureStats.effects.immobilized) break;
			final switch(object.creatureState.movement){
				case CreatureMovement.onGround:
					object.frame=0;
					object.animationState=sacObject.hasKnockdown?AnimationState.knocked2Floor
						:sacObject.hasGetUp?AnimationState.getUp:AnimationState.stance1;
					break;
				case CreatureMovement.flying:
					object.frame=0;
					assert(sacObject.canFly);
					object.animationState=sacObject.hasFlyDamage?AnimationState.flyDamage:AnimationState.hover;
					break;
				case CreatureMovement.tumbling:
					if(!object.animationState.among(AnimationState.knocked2Floor,AnimationState.getUp) && !object.isSacDoctor){
						object.frame=0;
						object.animationState=AnimationState.stance1;
						bool hasFalling=sacObject.hasFalling;
						if(hasFalling&&object.creatureState.fallingVelocity.xy==Vector2f(0.0f,0.0f)) object.animationState=AnimationState.falling;
						else if(sacObject.canTumble) object.animationState=AnimationState.tumble;
						else if(hasFalling) object.animationState=AnimationState.falling;
					}
					break;
			}
			break;
		case CreatureMode.cower:
			object.frame=0;
			object.animationState=sacObject.hasAnimationState(AnimationState.cower)?AnimationState.cower:AnimationState.idle1;
			if(!state.uniform(5)){ // TODO: figure out the original rule for this
				playSoundTypeAt(sacObject,object.id,SoundType.cower,state);
				object.animationState=sacObject.hasAnimationState(AnimationState.talkCower)?AnimationState.talkCower:AnimationState.idle1;
			}
			break;
		case CreatureMode.casting,CreatureMode.stationaryCasting,CreatureMode.castingMoving:
			object.frame=0;
			object.animationState=object.creatureState.mode==CreatureMode.castingMoving?AnimationState.runSpellcastStart:AnimationState.spellcastStart;
			break;
		case CreatureMode.shooting:
			object.frame=0;
			object.animationState=object.shootAnimation(false);
			break;
		case CreatureMode.usingAbility:
			object.frame=0;
			object.animationState=object.shootAnimation(true);
			break;
		case CreatureMode.pulling:
			object.frame=0;
			object.animationState=object.pullAnimation;
			break;
		case CreatureMode.pumping:
			assert(object.isSacDoctor);
			object.frame=0;
			object.animationState=cast(AnimationState)SacDoctorAnimationState.stab;
			break;
		case CreatureMode.torturing:
			assert(object.isSacDoctor);
			object.frame=0;
			object.animationState=cast(AnimationState)SacDoctorAnimationState.torture;
			break;
		case CreatureMode.convertReviving:
			break;
		case CreatureMode.thrashing:
			if(object.animationState.among(AnimationState.death0,AnimationState.death1,AnimationState.death2)){
				if(sacObject.hasAnimationState(AnimationState.corpseRise)){
					object.frame=0;
					object.animationState=AnimationState.corpseRise;
					break;
				}
			}else{
				if(sacObject.hasAnimationState(AnimationState.rise)){
					object.frame=0;
					object.animationState=AnimationState.rise;
					break;
				}
			}
			if(sacObject.hasAnimationState(AnimationState.float2Thrash)){
				object.frame=0;
				object.animationState=AnimationState.float2Thrash;
				break;
			}
			if(sacObject.hasAnimationState(AnimationState.thrash)){
				object.frame=0;
				object.animationState=AnimationState.thrash;
				break;
			}
			break;
	}
}

void pickRandomAnimation(B)(ref MovingObject!B object,immutable(AnimationState)[] candidates,ObjectState!B state){
	auto filtered=candidates.filter!(x=>object.sacObject.hasAnimationState(x));
	int len=cast(int)filtered.walkLength;
	assert(!!len&&object.frame==0);
	object.animationState=filtered.drop(state.uniform(len)).front;
}

bool pickNextAnimation(B)(ref MovingObject!B object,immutable(AnimationState)[] sequence,ObjectState!B state){
	auto filtered=sequence.filter!(x=>object.sacObject.hasAnimationState(x)).find!(x=>x==object.animationState);
	if(filtered.empty) return false;
	filtered.popFront();
	if(filtered.empty) return false;
	object.animationState=filtered.front;
	return true;
}

bool startIdling(B)(ref MovingObject!B object, ObjectState!B state){
	if(object.creatureState.mode==CreatureMode.idle) return true;
	with(CreatureMode) if(!object.creatureState.mode.among(moving,spawning,reviving,fastReviving,takeoff,landing,meleeMoving,meleeAttacking,stunned,cower,casting,stationaryCasting,castingMoving,shooting,usingAbility,pulling,pumping,torturing,rockForm))
		return false;
	object.creatureState.mode=CreatureMode.idle;
	object.setCreatureState(state);
	return true;
}

bool kill(B,bool pretending=false)(ref MovingObject!B object, ObjectState!B state){
	if(!object.creatureState.mode.canKill) return false;
	object.unfreeze(state);
	if(object.isGhost){ state.addEffect(GhostKill(object.id)); return true; }
	static if(!pretending){
		if(!object.sacObject.canDie()) return false;
		if(object.creatureState.mode!=CreatureMode.convertReviving){
			object.creatureState.mode=CreatureMode.dying;
			playSoundTypeAt(object.sacObject,object.id,SoundType.death,state);
			if(auto ability=object.passiveAbility){
				switch(ability.tag){
					case SpellTag.steamCloud: object.steamCloud(ability,state); break;
					case SpellTag.poisonCloud: object.poisonCloud(ability,state); break;
					case SpellTag.healingShower: object.healingShower(ability,state); break;
					default: break;
				}
			}
		}else{
			object.creatureState.mode=CreatureMode.dead;
			object.spawnSoul(state);
		}
		object.unselect(state);
		object.removeFromGroups(state);
		if(!object.isSacDoctor) object.health=0.0f;
	}else{
		with(CreatureMode) if(object.creatureState.mode.among(stunned,pretendingToDie,playingDead)) return false;
		object.creatureState.mode=CreatureMode.pretendingToDie;
	}
	object.setCreatureState(state);
	return true;
}
void killAll(B)(int side, ObjectState!B state){
	void perform(ref MovingObject!B obj,int side,ObjectState!B state){
		if(obj.side==side && obj.creatureState.mode!=CreatureMode.convertReviving)
			obj.kill(state);
	}
	state.eachMoving!perform(side,state);
}

bool playDead(B)(ref MovingObject!B object, ObjectState!B state){
	return object.kill!(B,true)(state);
}

bool gib(B)(ref MovingObject!B object, ObjectState!B state,int giveSoulsTo=-1){ // giveSoulsTo=-2: don't spawn soul
	object.unselect(state);
	object.removeFromGroups(state);
	int numSouls=object.sacObject.numSouls;
	if(numSouls){
		if(giveSoulsTo>=0){
			if(auto wizard=state.getWizard(giveSoulsTo)){
				wizard.souls+=numSouls;
			}else giveSoulsTo=-1;
		}
		if(giveSoulsTo==-1 && !object.soulId)
			object.soulId=state.addObject(Soul!B(object.id,object.side,object.sacObject.numSouls,object.soulPosition,SoulState.emerging));
		if(object.soulId){
			state.soulById!((ref soul){
				if(soul.state==SoulState.reviving)
					soul.state=SoulState.emerging;
				soul.creatureId=0;
			},(){})(object.soulId);
			object.soulId=0;
		}
	}
	state.removeLater(object.id);
	playSpellSoundTypeAt(SoundType.gib,object.position,state,4.0f);
	// TODO: gib animation
	return true;
}

enum dissolutionTime=cast(int)(2.5f*updateFPS);
enum dissolutionDelay=updateFPS;
void startDissolving(B)(ref MovingObject!B object,ObjectState!B state){
	if(!object.creatureState.mode.among(CreatureMode.dead,CreatureMode.dissolving)||object.soulId) return;
	object.creatureState.mode=CreatureMode.dissolving;
	object.setCreatureState(state);
}

void destroy(B)(ref Building!B building, ObjectState!B state){
	if(building.flags&Flags.cannotDestroyKill) return;
	if(building.maxHealth(state)==0.0f) return;
	state.addEffect(BuildingDestruction(building.id));
}

void spawnSoul(B)(ref MovingObject!B object, ObjectState!B state){
	with(CreatureMode) if(object.creatureState.mode!=CreatureMode.dead) return;
	if(object.soulId){
		if(state.soulById!((ref soul){
			if(soul.state==SoulState.reviving)
			   soul.state=SoulState.emerging;
			return true;
		},()=>false)(object.soulId))
			return;
		object.soulId=0;
	}
	int numSouls=object.sacObject.numSouls;
	if(!numSouls) return;
	object.soulId=state.addObject(Soul!B(object.id,object.side,object.sacObject.numSouls,object.soulPosition,SoulState.emerging));
}

void createSoul(B)(ref MovingObject!B object, ObjectState!B state){
	with(CreatureMode) if(object.creatureState.mode!=CreatureMode.dead||object.soulId!=0) return;
	int numSouls=object.sacObject.numSouls;
	if(!numSouls) return;
	object.soulId=state.addObject(Soul!B(object.id,object.side,object.sacObject.numSouls,object.soulPosition,SoulState.normal));
}

int spawn(T=Creature,B)(int wizard,char[4] tag,int flags,ObjectState!B state,bool pre=true){
	auto positionFacingSide=state.movingObjectById!((ref caster)=>tuple(caster.position,caster.creatureState.facing,caster.side),()=>tuple(Vector3f.init,float.init,-1))(wizard);
	auto position=positionFacingSide[0],facing=positionFacingSide[1],side=positionFacingSide[2];
	if(side==-1) return 0;
	auto curObj=SacObject!B.getSAXS!T(tag);
	auto mode=pre?CreatureMode.preSpawning:CreatureMode.spawning;
	auto newPosition=position+rotate(facingQuaternion(facing),Vector3f(0.0f,6.0f,0.0f));
	if(state.isOnGround(newPosition)||!state.isOnGround(position)) position=newPosition; // TODO: find closest ground to newPosition instead
	auto movement=state.isOnGround(position)?CreatureMovement.onGround:CreatureMovement.flying;
	position.z=state.getHeight(position);
	auto creatureState=CreatureState(mode, movement, facing);
	auto rotation=facingQuaternion(facing);
	auto obj=MovingObject!B(curObj,position,rotation,AnimationState.disoriented,0,creatureState,curObj.creatureStats(flags),side);
	obj.setCreatureState(state);
	obj.updateCreaturePosition(state);
	auto ord=Order(CommandType.retreat,OrderTarget(TargetType.creature,wizard,position));
	obj.order(ord,state,side);
	return state.addObject(obj);
}

int makeBuilding(B)(ref MovingObject!B caster,char[4] tag,int flags,int base,ObjectState!B state)in{
	assert(base>0);
}do{
	auto data=tag in bldgs;
	enforce(!!data&&!(data.flags&BldgFlags.ground));
	auto position=state.buildingById!(
		(ref bldg,state)=>state.staticObjectById!(
			(obj)=>obj.position,
			function Vector3f(){ assert(0); })(bldg.componentIds[0]),
		function Vector3f(){ assert(0); })(base,state);
	float facing=0.0f; // TODO: ok?
	auto buildingId=state.addObject(Building!B(data,caster.side,flags,facing));
	state.buildingById!((ref Building!B building){
		if(flags&Flags.damaged) building.health/=10.0f;
		if(flags&Flags.destroyed) building.health=0.0f;
		foreach(ref component;data.components){
			auto curObj=SacObject!B.getBLDG(flags&Flags.destroyed&&component.destroyed!="\0\0\0\0"?component.destroyed:component.tag);
			auto offset=Vector3f(component.x,component.y,component.z);
			offset=rotate(facingQuaternion(building.facing), offset);
			auto cposition=position+offset;
			if(!state.isOnGround(cposition)) continue;
			cposition.z=state.getGroundHeight(cposition);
			float facing=0.0f; // TODO: ok?
			auto rotation=facingQuaternion(2*pi!float/360.0f*(facing+component.facing));
			building.componentIds~=state.addObject(StaticObject!B(curObj,building.id,cposition,rotation,1.0f,0));
		}
		if(base) state.buildingById!((ref manafount,state){ putOnManafount(building,manafount,state); },(){})(base,state);
	},(){ assert(0); })(buildingId);
	return buildingId;
}
int makeBuilding(B)(int casterId,char[4] tag,int flags,int base,ObjectState!B state)in{
	assert(base>0);
}do{
	return state.movingObjectById!(.makeBuilding,function int(){ assert(0); })(casterId,tag,flags,base,state);
}

int makeBuilding(B)(int side,char[4] tag,Vector3f position,int flags,ObjectState!B state){
	auto data=tag in bldgs;
	enforce(!!data);
	float facing=0.0f; // TODO: ok?
	auto buildingId=state.addObject(Building!B(data,side,flags,facing));
	state.buildingById!((ref Building!B building){
		if(flags&Flags.damaged) building.health/=10.0f;
		if(flags&Flags.destroyed) building.health=0.0f;
		foreach(ref component;data.components){
			auto curObj=SacObject!B.getBLDG(flags&Flags.destroyed&&component.destroyed!="\0\0\0\0"?component.destroyed:component.tag);
			auto offset=Vector3f(component.x,component.y,component.z);
			offset=rotate(facingQuaternion(building.facing), offset);
			auto cposition=position+offset;
			if(!state.isOnGround(cposition)) continue;
			cposition.z=state.getGroundHeight(cposition);
			float facing=0.0f; // TODO: ok?
			auto rotation=facingQuaternion(2*pi!float/360.0f*(facing+component.facing));
			building.componentIds~=state.addObject(StaticObject!B(curObj,building.id,cposition,rotation,1.0f,0));
		}
	},(){ assert(0); })(buildingId);
	return buildingId;
}

bool canStun(B)(ref MovingObject!B object,ObjectState!B state){
	if(object.isSacDoctor) return false;
	if(object.creatureStats.effects.stunCooldown!=0) return false;
	final switch(object.creatureState.mode) with(CreatureMode){
		case idle,moving,spawning,takeoff,landing,meleeMoving,meleeAttacking,cower,casting,stationaryCasting,castingMoving,shooting,usingAbility,pulling: return true;
		case dying,dead,deadToGhost,idleGhost,movingGhost,ghostToIdle,dissolving,preSpawning,reviving,fastReviving,stunned,pretendingToDie,playingDead,pretendingToRevive,rockForm,pumping,torturing,convertReviving,thrashing: return false;
	}
}

bool stun(B)(ref MovingObject!B object, ObjectState!B state){
	if(!object.canStun(state)) return false;
	object.creatureState.mode=CreatureMode.stunned;
	object.setCreatureState(state);
	return true;
}
enum stunCooldownFrames=8*updateFPS;
bool stunWithCooldown(B)(ref MovingObject!B object, int cooldownFrames, ObjectState!B state){
	if(object.stun(state)){
		object.creatureStats.effects.stunCooldown=cooldownFrames;
		return true;
	}
	return false;
}
enum damageStunCooldownFrames=4*updateFPS; // TODO
bool damageStun(B)(ref MovingObject!B object, Vector3f attackDirection, ObjectState!B state){
	if(!object.canStun(state)) return false;
	object.creatureState.mode=CreatureMode.stunned;
	object.setCreatureState(state);
	object.damageAnimation(attackDirection,state,false);
	object.creatureStats.effects.stunCooldown=damageStunCooldownFrames;
	return true;
}

bool canCatapult(B)(ref MovingObject!B object){
	return object.creatureState.mode.canCatapult;
}
void catapult(B)(ref MovingObject!B object, Vector3f velocity, ObjectState!B state){
	if(!object.canCatapult) return;
	if(object.creatureState.movement==CreatureMovement.flying) return;
	if(object.creatureState.mode==CreatureMode.pumping) object.kill(state);
	if(object.creatureState.mode!=CreatureMode.dying)
		object.creatureState.mode=CreatureMode.stunned;
	if(object.creatureState.movement!=CreatureMovement.tumbling){
		object.creatureState.movement=CreatureMovement.tumbling;
		if(!object.creatureStats.effects.fixed)
			object.creatureState.fallingVelocity=velocity;
		object.setCreatureState(state);
	}else if(!object.creatureStats.effects.fixed)
		object.creatureState.fallingVelocity+=velocity;
}

bool canPush(B)(ref MovingObject!B object){
	return object.creatureState.mode.canPush;
}
void push(B)(ref MovingObject!B object, Vector3f velocity, ObjectState!B state){
	if(object.creatureStats.effects.fixed) return;
	auto newPosition=object.position+velocity/updateFPS;
	if(object.creatureState.movement==CreatureMovement.onGround){
		if(!state.isOnGround(newPosition)) return;
		newPosition.z=state.getGroundHeight(newPosition);
	}
	object.position=newPosition;
}

void pushAll(alias filter=None,bool sacDoctorSuperPush=false,B,T...)(Vector3f position,float innerRadius,float radius,float innerStrength,ObjectState!B state,T args){
	Vector3f[2] hitbox=[position-radius,position+radius];
	void doPush(ref ProximityEntry entry,ObjectState!B state,T args){
		if(!state.isValidTarget(entry.id,TargetType.creature)) return;
		state.movingObjectById!((ref obj){
			auto direction=obj.center-position;
			auto distance=direction.length;
			if(distance==0.0f||distance>=radius) return;
			auto strength=(1.0f-(distance-innerRadius)/(radius-innerRadius))*innerStrength;
			static if(sacDoctorSuperPush){
				if(obj.isSacDoctor){
					if(obj.isDying) return;
					if(distance<radius-0.1f) strength=1.1f*obj.speedOnGround(state);
				}
			}
			obj.push(strength*direction/distance,state);
		},(){})(entry.id);
	}
	collisionTargets!(doPush,filter,false,true)(hitbox,state,args);
}

void immediateRevive(B)(ref MovingObject!B object,ObjectState!B state){
	with(CreatureMode) if(!object.creatureState.mode.among(dying,dead)) return;
	if(object.soulId!=0){
		state.removeObject(object.soulId);
		object.soulId=0;
	}
	object.health=object.creatureStats.maxHealth;
	object.creatureState.mode=CreatureMode.idle;
	object.setCreatureState(state);
}

void fastRevive(B)(ref MovingObject!B object,ObjectState!B state){
	object.revive(state,true);
}

void revive(B)(ref MovingObject!B object,ObjectState!B state,bool fast=false){
	with(CreatureMode) if(object.creatureState.mode!=dead) return;
	if(object.soulId==0) return;
	if(!state.soulById!((ref Soul!B s){
		if(s.state.among(SoulState.normal,SoulState.emerging)){
			s.state=SoulState.reviving;
			return true;
		}
		return false;
	},()=>false)(object.soulId))
		return;
	object.health=object.creatureStats.maxHealth;
	object.creatureState.mode=fast?CreatureMode.fastReviving:CreatureMode.reviving;
	object.setCreatureState(state);
}

bool convertRevive(B)(ref MovingObject!B object,ObjectState!B state){
	with(CreatureMode) if(!object.creatureState.mode==dead) return false;
	if(object.soulId==0) return false;
	if(!state.soulById!((ref Soul!B s){
		if(s.state.among(SoulState.normal,SoulState.emerging)){
			s.state=SoulState.reviving;
			return true;
		}
		return false;
	},()=>false)(object.soulId))
		return false;
	object.health=min(max(300.0f,0.5f*object.creatureStats.maxHealth),object.creatureStats.maxHealth); // TODO: ok?
	object.creatureState.mode=CreatureMode.convertReviving;
	object.setCreatureState(state);
	return true;
}

void pretendToRevive(B)(ref MovingObject!B object,ObjectState!B state){
	with(CreatureMode) if(object.creatureState.mode!=playingDead) return;
	object.creatureState.mode=CreatureMode.pretendingToRevive;
	object.setCreatureState(state);
}

void startFlying(B)(ref MovingObject!B object,ObjectState!B state){
	with(CreatureMode){
		if(object.creatureState.mode==landing){
			object.startIdling(state);
			return;
		}
		if(!object.sacObject.canFly||!object.creatureState.mode.among(idle,moving)||
		   object.creatureState.movement!=CreatureMovement.onGround)
			return;
	}
	object.creatureState.mode=CreatureMode.takeoff;
	object.setCreatureState(state);
}

void land(B)(ref MovingObject!B object,ObjectState!B state){
	with(CreatureMode)
		if(object.sacObject.mustFly||!object.creatureState.mode.among(idle,moving)||
		   object.creatureState.movement!=CreatureMovement.flying)
			return;
	if(!state.isOnGround(object.position))
		return;
	object.creatureState.mode=CreatureMode.landing;
	object.setCreatureState(state);
}

void startTumbling(B)(ref MovingObject!B object,ObjectState!B state){
	if(object.creatureState.movement!=CreatureMovement.flying) return;
	auto direction=rotate(object.rotation,Vector3f(0.0f,1.0f,0.0f));
	object.creatureState.fallingVelocity=object.creatureState.speed*direction; // TODO: have consistent "velocity" instead?
	object.creatureState.movement=CreatureMovement.tumbling;
}

void startMeleeAttacking(B)(ref MovingObject!B object,bool downward,ObjectState!B state){
	with(CreatureMode) with(CreatureMovement)
		if(!object.creatureState.mode.among(idle,moving)||
		   !object.creatureState.movement.among(onGround,flying)||
		   !object.sacObject.canAttack)
			return;
	object.creatureState.mode=CreatureMode.meleeMoving;
	auto sacObject=object.sacObject;
	playSoundTypeAt(sacObject,object.id,SoundType.melee,state);
	object.frame=0;
	final switch(object.creatureState.movement) with(CreatureMovement) with(AnimationState){
		case onGround:
			static immutable attackCandidatesOnGround=[attack0,attack1,attack2];
			if(downward&&sacObject.hasAnimationState(attack2)) object.animationState=attack2;
			else object.pickRandomAnimation(attackCandidatesOnGround[0..2],state);
			break;
		case flying:
			if(sacObject.mustFly)
				goto case onGround; // (bug in original engine: it fails to do this.)
			object.animationState=flyAttack;
			break;
		case tumbling:
			assert(0);
	}
	object.setCreatureState(state);
}

float rangedMeleeAttackDistance(B)(ref MovingObject!B object,ObjectState!B state){
	return 0.5f;
}

enum DamageDirection{
	front,
	right,
	back,
	left,
	top
}
DamageDirection getDamageDirection(B)(ref MovingObject!B object,Vector3f attackDirection,ObjectState!B state){
	auto fromFront=rotate(object.rotation,Vector3f(0.0f,-1.0f,0.0f));
	auto fromRight=rotate(object.rotation,Vector3f(-1.0f,0.0f,0.0f));
	auto fromBack=rotate(object.rotation,Vector3f(0.0f,1.0f,0.0f));
	auto fromLeft=rotate(object.rotation,Vector3f(1.0f,0.0f,0.0f));
	auto fromTop=rotate(object.rotation,Vector3f(0.0f,0.0f,-1.0f));
	auto best=dot(fromFront,attackDirection),bestDirection=DamageDirection.front;
	foreach(i,alias dir;Seq!(fromRight,fromBack,fromLeft,fromTop)){
		auto cand=dot(dir,attackDirection);
		if(best<cand){
			best=cand;
			bestDirection=cast(DamageDirection)(i+1);
		}
	}
	return bestDirection;
}

void damageAnimation(B)(ref MovingObject!B object,Vector3f attackDirection,ObjectState!B state,bool checkIdle=true){
	if(checkIdle&&!object.canDamage(state)) return;
	if(object.creatureStats.effects.immobilized) return;
	if(AnimationState.damageFront<=object.animationState&&object.animationState<=AnimationState.damageFront+DamageDirection.max)
		return;
	if(object.animationState==AnimationState.flyDamage)
		return;
	if(object.creatureStats.effects.yellCooldown==0)
		object.creatureStats.effects.yellCooldown=playSoundTypeAt!true(object.sacObject,object.id,SoundType.damaged,state)+updateFPS/2;
	if(checkIdle&&!object.creatureState.mode.among(CreatureMode.idle,CreatureMode.cower)||!checkIdle&&object.creatureState.mode!=CreatureMode.stunned) return;
	final switch(object.creatureState.movement){
		case CreatureMovement.onGround:
			break;
		case CreatureMovement.flying:
			object.animationState=AnimationState.flyDamage;
			object.frame=0;
			return;
		case CreatureMovement.tumbling:
			return;
	}
	if(object.creatureState.movement==CreatureMovement.tumbling) return;
	auto damageDirection=getDamageDirection(object,attackDirection,state);
	auto animationState=cast(AnimationState)(AnimationState.damageFront+damageDirection);
	if(!object.sacObject.hasAnimationState(animationState))
		animationState=animationState.stance1;
	object.animationState=animationState;
	object.frame=0;
}


bool canHeal(B)(ref MovingObject!B object,ObjectState!B state){
	if(object.health(state)==object.creatureStats.maxHealth) return false;
	if(object.health(state)==0.0f) return false;
	return object.creatureState.mode.canHeal;
}
void heal(B)(ref MovingObject!B object,float amount,ObjectState!B state){
	object.health=min(object.health+amount,object.creatureStats.maxHealth);
}
void heal(B)(ref Building!B building,float amount,ObjectState!B state){
	building.health=min(building.health+amount,building.maxHealth(state));
}

void drainMana(B)(ref MovingObject!B object,float amount,ObjectState!B state){
	object.creatureStats.mana=max(0.0f,object.creatureStats.mana-amount);
}

enum ghostHealthPerMana=4.2f;
void giveMana(B)(ref MovingObject!B object,float amount,ObjectState!B state){
	if(object.creatureStats.effects.manaBlocked) return;
	object.creatureStats.mana=min(object.creatureStats.mana+amount,object.creatureStats.maxMana);
	if(object.isWizard&&object.isGhost) object.heal(ghostHealthPerMana*amount,state);
}

void healFromDrain(B)(ref MovingObject!B attacker,float actualDamage,ObjectState!B state){
	if(actualDamage) attacker.heal(actualDamage*attacker.creatureStats.drain,state);
}
void healFromDrain(B)(int attacker,float actualDamage,ObjectState!B state){
	if(state.isValidTarget(attacker,TargetType.creature))
		return state.movingObjectById!(healFromDrain,(){})(attacker,actualDamage,state);
}


enum DamageMod{
	none=0,
	melee=1<<0,
	spell=1<<1,
	ranged=1<<2,
	splash=1<<3,
	fall=1<<4,
	lightning=1<<5,
	ignite=1<<6,
	desecration=1<<7,
	peirceShield=1<<8,
}

float attackDamageFactor(B)(ref MovingObject!B attacker,bool targetIsCreature,DamageMod damageMod,ObjectState!B state){
	float result=1.0f;
	if(attacker.isGuardian) result*=1.5f;
	if(!targetIsCreature&&damageMod&DamageMod.melee) result*=attacker.sacObject.buildingMeleeDamageMultiplier;
	if(auto passive=attacker.sacObject.passiveOnDamage){
		if(passive.tag==SpellTag.firefistPassive&&damageMod&DamageMod.melee){
			auto relativeHP=attacker.creatureStats.health/attacker.creatureStats.maxHealth;
			result*=1.0f+1.5f*(1.0f-relativeHP);
		}
	}
	return result;
}

float dealDamage(T,B)(ref T object,float damage,int attacker,int attackingSide,Vector3f attackDirection,DamageMod damageMod,ObjectState!B state,bool checkIdle=true)if(is(T==MovingObject!B)||is(T==Building!B)){
	auto actualDamage=dealDamage(object,damage,attacker,attackingSide,damageMod,state);
	static if(is(T==MovingObject!B)) if(actualDamage>0.0f) object.damageAnimation(attackDirection,state,checkIdle);
	return actualDamage;
}

float dealDamage(T,B)(ref T object,float damage,int attacker,int attackingSide,DamageMod damageMod,ObjectState!B state)if(is(T==MovingObject!B)||is(T==Building!B)){
	auto actualDamage=damage;
	static if(is(T==MovingObject!B)) if(object.id==attacker) actualDamage*=object.attackDamageFactor(true,damageMod,state);
	if(object.id!=attacker&&state.isValidTarget(attacker,TargetType.creature))
		return state.movingObjectById!((ref atk,obj,dmg,damageMod,state)=>dealDamage(*obj,dmg,atk,damageMod,state),()=>0.0f)(attacker,&object,actualDamage,damageMod,state);
	return dealDamage(object,actualDamage,attackingSide,damageMod,state);
}

bool canDamage(B)(ref MovingObject!B object,ObjectState!B state){
	if(object.creatureStats.flags&Flags.cannotDamage) return false;
	if(object.creatureStats.effects.etherealForm) return false;
	final switch(object.creatureState.mode) with(CreatureMode){
		case idle,moving,spawning,takeoff,landing,meleeMoving,meleeAttacking,stunned,cower,casting,stationaryCasting,castingMoving,
			shooting,usingAbility,pulling,pumping,torturing,playingDead,pretendingToRevive,rockForm: return true;
		case dying,dead,deadToGhost,idleGhost,movingGhost,ghostToIdle,dissolving,preSpawning,reviving,fastReviving,pretendingToDie,convertReviving,thrashing: return false;
	}
}

float dealDamage(B)(ref MovingObject!B object,float damage,ref MovingObject!B attacker,Vector3f attackDirection,DamageMod damageMod,ObjectState!B state,bool checkIdle=true){
	auto actualDamage=dealDamage(object,damage,attacker,damageMod,state,checkIdle);
	if(actualDamage>0.0f) object.damageAnimation(attackDirection,state,checkIdle);
	return actualDamage;

}

float dealDamage(B)(ref MovingObject!B object,float damage,ref MovingObject!B attacker,DamageMod damageMod,ObjectState!B state,bool checkIdle=true){
	auto actualDamage=damage*attacker.attackDamageFactor(true,damageMod,state);
	actualDamage=dealDamage(object,actualDamage,attacker.side,damageMod,state);
	attacker.healFromDrain(actualDamage,state);
	return actualDamage;
}
float dealDamage(B)(ref MovingObject!B object,float damage,int attackingSide,DamageMod damageMod,ObjectState!B state){
	auto damageMultiplier=1.0f;
	if(damageMod&DamageMod.melee) damageMultiplier*=object.creatureStats.meleeResistance;
	else if(damageMod&DamageMod.ranged){
		if(damageMod&DamageMod.splash) damageMultiplier*=object.creatureStats.splashRangedResistance;
		else damageMultiplier*=object.creatureStats.directRangedResistance;
	}else if(damageMod&DamageMod.spell){
		if(damageMod&DamageMod.splash) damageMultiplier*=object.creatureStats.splashSpellResistance;
		else damageMultiplier*=object.creatureStats.directSpellResistance;
	}
	if(!(damageMod&DamageMod.fall)){
		if(!object.canDamage(state)) return 0.0f;
		if(!(damageMod&DamageMod.peirceShield)){
			if(object.creatureStats.effects.lifeShield) damageMultiplier*=0.5f;
			if(object.creatureState.mode==CreatureMode.rockForm) damageMultiplier*=0.05f;
			if(object.creatureStats.effects.petrified) damageMultiplier*=0.2f;
			if(object.creatureStats.effects.skinOfStone) damageMultiplier*=0.25f;
			if(object.creatureStats.effects.airShield) damageMultiplier*=0.5f;
			if(object.creatureStats.effects.protectiveSwarm) damageMultiplier*=0.75f;
		}
		damageMultiplier*=1.2f^^object.creatureStats.effects.numSlimes;
	}
	// TODO: bleed, in case of petrification, bleed rocks instead
	return dealRawDamage(object,damage*damageMultiplier,attackingSide,damageMod,state);
}

float dealRawDamage(B)(ref MovingObject!B object,float damage,int attackingSide,DamageMod damageMod,ObjectState!B state){
	float actualDamage;
	if(!(damageMod&DamageMod.fall)||object.isSacDoctor){ // TODO: do sac doctors take fall damage at all?
		if(!object.canDamage(state)) return 0.0f;
		actualDamage=damage*state.sideDamageMultiplier(attackingSide,object.side);
		if(object.creatureStats.effects.isGuardian){
			if(damageMod&DamageMod.melee) actualDamage*=0.4f;
			else if(damageMod&DamageMod.spell) actualDamage*=0.5f;
			else if(damageMod&DamageMod.ranged) actualDamage*=0.25f;
		}
		if(auto passive=object.sacObject.passiveOnDamage){
			switch(passive.tag){
				case SpellTag.taurockPassive:
					auto relativeHP=object.creatureStats.health/object.creatureStats.maxHealth;
					auto damageFactor=0.25f+0.75f*relativeHP;
					actualDamage*=damageFactor;
					break;
				case SpellTag.lightningCharge:
					if(damageMod&DamageMod.lightning){
						object.lightningCharge(cast(int)((1.0f/30.0f)*actualDamage*updateFPS),passive,state); // TODO: duration ok?
						actualDamage*=0.3f;
					}
					break;
				default:
					break;
			}
		}
		if((damageMod&DamageMod.ignite)&&object.creatureStats.effects.oilStatus==OilStatus.oiled){
			object.igniteOil(state);
			actualDamage*=2.0f;
		}
	}else actualDamage=damage;
	actualDamage=min(object.health,actualDamage);
	if(actualDamage>0.0f) object.unfreeze(state);
	object.creatureStats.health-=actualDamage;
	if(object.creatureStats.flags&Flags.cannotDestroyKill)
		object.creatureStats.health=max(object.health,1.0f);
	// TODO: give xp to wizard of attacking side
	if(object.health==0.0f)
		object.kill(state);
	return actualDamage;
}

float dealDamage(B)(ref MovingObject!B object,float amount,float radius,int attacker,int attackerSide,Vector3f attackDirection,float distance,DamageMod damageMod,ObjectState!B state){
	auto damage=amount*(radius>0.0f?max(0.0f,1.0f-distance/radius):1.0f);
	object.damageAnimation(attackDirection,state);
	return object.dealDamage(damage,attacker,attackerSide,attackDirection,damageMod|DamageMod.splash,state);
}

float dealDamage(B)(ref StaticObject!B object,float amount,float radius,int attacker,int attackerSide,Vector3f attackDirection,float distance,DamageMod damageMod,ObjectState!B state){
	return state.buildingById!(dealDamage,()=>0.0f)(object.buildingId,amount,radius,attacker,attackerSide,attackDirection,distance,damageMod,state);
}

float dealDamage(B)(ref Building!B building,float amount,float radius,int attacker,int attackerSide,Vector3f attackDirection,float distance,DamageMod damageMod,ObjectState!B state){
	auto damage=amount*(radius>0.0f?max(0.0f,1.0f-distance/radius):1.0f);
	return building.dealDamage(damage,attacker,attackerSide,damageMod|DamageMod.splash,state);
}

float dealDamage(B)(int target,float amount,float radius,int attacker,int attackerSide,Vector3f attackDirection,float distance,DamageMod damageMod,ObjectState!B state){
	if(state.isValidBuilding(target))
		return state.buildingById!(dealDamage,()=>0.0f)(target,amount,radius,attacker,attackerSide,attackDirection,distance,damageMod,state);
	if(!state.isValidId(target)) return 0.0f;
	return state.objectById!dealDamage(target,amount,radius,attacker,attackerSide,attackDirection,distance,damageMod,state);
}

float dealDamageAt(alias callback=(id)=>true,B,T...)(int directTarget,float amount,float radius,int attacker,int attackerSide,Vector3f position,DamageMod damageMod,ObjectState!B state,T args){
	static void hit(ProximityEntry target,ObjectState!B state,int directTarget,float amount,int attacker,int attackerSide,Vector3f position,float* sum,float radius,DamageMod damageMod,T args){
		if(target.id==directTarget) return;
		auto distance=boxPointDistance(target.hitbox,position);
		if(distance>radius) return;
		auto attackDirection=state.objectById!((obj)=>obj.center)(target.id)-position;
		if(callback(target.id,args))
			*sum+=dealDamage(target.id,amount,radius,attacker,attackerSide,attackDirection,distance,damageMod,state);
	}
	auto offset=Vector3f(radius,radius,radius);
	Vector3f[2] hitbox=[position-offset,position+offset];
	float sum=0.0f;
	collisionTargets!(hit,None,true)(hitbox,state,directTarget,amount,attacker,attackerSide,position,&sum,radius,damageMod,args);
	return sum;
}

bool canDamage(B)(ref Building!B building,ObjectState!B state){
	if(building.flags&Flags.cannotDamage) return false;
	if(building.health==0.0f) return false;
	return true;
}

// TODO: get rid of code duplication in guardian damage procedures
float damageGuardians(B)(ref Building!B building,float damage,int attackingSide,DamageMod damageMod,ObjectState!B state){
	if(building.guardianIds.length){
		auto n=building.guardianIds.length;
		auto splitDamage=damage/min(n,0.5f*(n+3));
		float actualDamage=0.0f;
		auto attachPosition=building.guardianAttachPosition(state);
		bool ok=false;
		foreach(id;building.guardianIds.data){
			actualDamage+=state.movingObjectById!((ref obj,splitDamage,attackingSide,attachPosition,damageMod,state,ok){
				if(!obj.isValidGuard(state)) return 0.0f;
				auto attackDirection=obj.center-attachPosition;
				obj.damageAnimation(attackDirection,state,false);
				*ok=true;
				return dealDamage(obj,splitDamage,attackingSide,damageMod,state);
			},()=>0.0f)(id,splitDamage,attackingSide,attachPosition,damageMod,state,&ok);
		}
		if(ok) return actualDamage;
	}
	return float.nan;
}
float damageGuardians(B)(ref Building!B building,float damage,ref MovingObject!B attacker,DamageMod damageMod,ObjectState!B state){
	if(building.guardianIds.length){
		auto n=building.guardianIds.length;
		auto splitDamage=damage/min(n,0.5f*(n+3));
		float actualDamage=0.0f;
		auto attachPosition=building.guardianAttachPosition(state);
		bool ok=false;
		foreach(id;building.guardianIds.data){
			if(id==attacker.id){
				if(!attacker.isValidGuard(state))
					continue;
				auto attackDirection=attacker.center-attachPosition;
				attacker.damageAnimation(attackDirection,state,false);
				actualDamage+=attacker.dealDamage(splitDamage,attacker,damageMod,state);
				ok=true;
			}else{
				actualDamage+=state.movingObjectById!((ref obj,splitDamage,attacker,attachPosition,damageMod,state,ok){
					if(!obj.isValidGuard(state)) return 0.0f;
					auto attackDirection=obj.center-attachPosition;
					*ok=true;
					return dealDamage(obj,splitDamage,*attacker,attackDirection,damageMod,state,false);
				},()=>0.0f)(id,splitDamage,&attacker,attachPosition,damageMod,state,&ok);
			}
		}
		if(ok) return actualDamage;
	}
	return float.nan;
}

float dealDamageIgnoreGuardians(B)(ref Building!B building,float damage,int attackingSide,DamageMod damageMod,ObjectState!B state){
	if(!building.canDamage(state)) return 0.0f;
	auto damageMultiplier=1.0f;
	if(damageMod&DamageMod.melee) damageMultiplier*=building.meleeResistance;
	else if(damageMod&DamageMod.ranged){
		if(damageMod&DamageMod.splash) damageMultiplier*=building.splashRangedResistance;
		else damageMultiplier*=building.directRangedResistance;
	}else if(damageMod&DamageMod.spell){
		if(damageMod&DamageMod.splash) damageMultiplier*=building.splashSpellResistance;
		else damageMultiplier*=building.directSpellResistance;
	}
	auto actualDamage=min(building.health,damageMultiplier*damage*state.sideDamageMultiplier(attackingSide,building.side));
	building.health-=actualDamage;
	if(building.flags&Flags.cannotDestroyKill)
		building.health=max(building.health,1.0f);
	// TODO: give xp to attacker
	if(building.health==0.0f)
		building.destroy(state);
	return actualDamage;
}

float dealDamage(B)(ref Building!B building,float damage,ref MovingObject!B attacker,DamageMod damageMod,ObjectState!B state){
	auto guardianDamage=damageGuardians(building,damage,attacker,damageMod,state);
	if(!isNaN(guardianDamage)) return guardianDamage;
	if(!building.canDamage(state)) return 0.0f;
	damage*=attacker.attackDamageFactor(false,damageMod,state);
	return dealDamageIgnoreGuardians(building,damage,attacker.side,damageMod,state);
}

float dealDamage(B)(ref Building!B building,float damage,int attackingSide,DamageMod damageMod,ObjectState!B state){
	auto guardianDamage=damageGuardians(building,damage,attackingSide,damageMod,state);
	if(!isNaN(guardianDamage)) return guardianDamage;
	return dealDamageIgnoreGuardians(building,damage,attackingSide,damageMod,state);
}

float meleeDistanceSqr(Vector3f[2] objectHitbox,Vector3f[2] attackerHitbox){
	return boxBoxDistanceSqr(objectHitbox,attackerHitbox);
}

void dealMeleeDamage(B)(ref MovingObject!B object,ref MovingObject!B attacker,DamageMod damageMod,ObjectState!B state){
	auto damage=attacker.meleeStrength/attacker.numAttackTicks; // TODO: figure this out
	auto objectHitbox=object.hitbox, attackerHitbox=attacker.meleeHitbox, attackerSizeSqr=0.25f*boxSize(attackerHitbox).lengthsqr;
	auto distanceSqr=meleeDistanceSqr(objectHitbox,attackerHitbox);
	//auto damageMultiplier=max(0.0f,1.0f-max(0.0f,sqrt(distanceSqr/attackerSizeSqr)));
	auto damageMultiplier=max(0.0f,1.0f-max(0.0f,(sqrt(distanceSqr)+state.uniform(0.5f,1.0f))/sqrt(attackerSizeSqr)));
	auto attackDirection=object.center-attacker.center; // TODO: good?
	auto direction=getDamageDirection(object,attackDirection,state);
	bool fromBehind=direction==DamageDirection.back;
	bool fromSide=!!direction.among(DamageDirection.left,DamageDirection.right);
	if(fromBehind) damage*=2.0f;
	auto actualDamage=object.dealDamage(damage,attacker,damageMod|DamageMod.melee,state);
	bool stunned;
	final switch(object.stunnedBehavior){
		case StunnedBehavior.normal:
			stunned=actualDamage>=0.25f*object.creatureStats.maxHealth;
			break;
		case StunnedBehavior.onMeleeDamage,StunnedBehavior.onDamage:
			stunned=true;
			break;
	}
	if(stunned){
		playSoundTypeAt(attacker.sacObject,attacker.id,SoundType.stun,state);
		object.damageStun(attackDirection,state);
	}else{
		playSoundTypeAt(attacker.sacObject,attacker.id,SoundType.hit,state);
		object.damageAnimation(attackDirection,state);
	}
}

float dealMeleeDamage(B)(ref StaticObject!B object,ref MovingObject!B attacker,DamageMod damageMod,ObjectState!B state){
	return state.buildingById!((ref Building!B building,MovingObject!B* attacker,DamageMod damageMod,ObjectState!B state){
		return building.dealMeleeDamage(*attacker,damageMod,state);
	},()=>0.0f)(object.buildingId,&attacker,damageMod,state);
}

float dealMeleeDamage(B)(ref Building!B building,ref MovingObject!B attacker,DamageMod damageMod,ObjectState!B state){
	auto damage=attacker.meleeStrength/attacker.numAttackTicks;
	auto actualDamage=building.dealDamage(damage,attacker,damageMod|DamageMod.melee,state);
	if(actualDamage>0.0f) playSoundTypeAt(attacker.sacObject,attacker.id,SoundType.hitWall,state);
	return actualDamage;
}

float dealSpellDamage(B)(ref MovingObject!B object,SacSpell!B spell,int attacker,int attackerSide,Vector3f attackDirection,DamageMod damageMod,ObjectState!B state){
	return dealSpellDamage(object,spell.amount,attacker,attackerSide,attackDirection,damageMod,state);
}
float dealSpellDamage(B)(ref MovingObject!B object,float damage,int attacker,int attackerSide,Vector3f attackDirection,DamageMod damageMod,ObjectState!B state){
	return object.dealDamage(damage,attacker,attackerSide,attackDirection,damageMod|DamageMod.spell,state);
}
float dealSpellDamage(B)(ref MovingObject!B object,float damage,int attacker,int attackerSide,DamageMod damageMod, ObjectState!B state){
	return object.dealDamage(damage,attacker,attackerSide,damageMod|DamageMod.spell,state);
}

float dealSpellDamage(B)(ref StaticObject!B object,SacSpell!B spell,int attacker,int attackerSide,Vector3f attackDirection,DamageMod damageMod,ObjectState!B state){
	return dealSpellDamage(object,spell.amount,attacker,attackerSide,attackDirection,damageMod,state);
}
float dealSpellDamage(B)(ref StaticObject!B object,float damage,int attacker,int attackerSide,Vector3f attackDirection,DamageMod damageMod,ObjectState!B state){
	return state.buildingById!(dealSpellDamage,()=>0.0f)(object.buildingId,damage,attacker,attackerSide,attackDirection,damageMod,state);
}
float dealSpellDamage(B)(ref StaticObject!B object,float damage,int attacker,int attackerSide,DamageMod damageMod,ObjectState!B state){
	return state.buildingById!(dealSpellDamage,()=>0.0f)(object.buildingId,damage,attacker,attackerSide,damageMod,state);
}

float dealSpellDamage(B)(ref Building!B building,SacSpell!B spell,int attacker,int attackerSide,Vector3f attackDirection,DamageMod damageMod,ObjectState!B state){
	return dealSpellDamage(building,spell.amount,attacker,attackerSide,attackDirection,damageMod,state);
}
float dealSpellDamage(B)(ref Building!B building,float damage,int attacker,int attackerSide,Vector3f attackDirection,DamageMod damageMod,ObjectState!B state){
	return dealSpellDamage(building,damage,attacker,attackerSide,damageMod,state);
}
float dealSpellDamage(B)(ref Building!B building,float damage,int attacker,int attackerSide,DamageMod damageMod,ObjectState!B state){
	return building.dealDamage(damage,attacker,attackerSide,damageMod|DamageMod.spell,state);
}


float dealSpellDamage(B)(int target,SacSpell!B spell,int attacker,int attackerSide,Vector3f attackDirection,DamageMod damageMod,ObjectState!B state){
	if(!state.isValidTarget(target)) return 0.0f;
	return state.objectById!dealSpellDamage(target,spell,attacker,attackerSide,attackDirection,damageMod,state);
}

float dealSplashSpellDamage(B)(ref MovingObject!B object,SacSpell!B spell,int attacker,int attackerSide,Vector3f attackDirection,float distance,DamageMod damageMod,ObjectState!B state){
	return dealSplashDamage(object,spell,attacker,attackerSide,attackDirection,distance,damageMod|DamageMod.spell,state);
}

float dealSplashSpellDamage(B)(ref StaticObject!B object,SacSpell!B spell,int attacker,int attackerSide,Vector3f attackDirection,float distance,DamageMod damageMod,ObjectState!B state){
	return state.buildingById!(dealSplashSpellDamage,()=>0.0f)(object.buildingId,spell,attacker,attackerSide,attackDirection,distance,damageMod,state);
}

float dealSplashSpellDamage(B)(ref Building!B building,SacSpell!B spell,int attacker,int attackerSide,Vector3f attackDirection,float distance,DamageMod damageMod,ObjectState!B state){
	return dealSplashDamage(building,spell,attacker,attackerSide,attackDirection,distance,damageMod|DamageMod.spell,state);
}

float dealSplashSpellDamage(B)(int target,SacSpell!B spell,int attacker,int attackerSide,Vector3f attackDirection,float distance,DamageMod damageMod,ObjectState!B state){
	if(state.isValidBuilding(target))
		return state.buildingById!(dealSplashSpellDamage,()=>0.0f)(target,spell,attacker,attackerSide,attackDirection,distance,damageMod,state);
	if(!state.isValidTarget(target)) return 0.0f;
	return state.objectById!dealSplashSpellDamage(target,spell,attacker,attackerSide,attackDirection,distance,damageMod,state);
}

float dealSplashSpellDamageAt(alias callback=(id)=>true,B,T...)(int directTarget,SacSpell!B spell,float radius,int attacker,int attackerSide,Vector3f position,DamageMod damageMod,ObjectState!B state,T args){
	return dealSplashDamageAt!callback(directTarget,spell,radius,attacker,attackerSide,position,damageMod|DamageMod.spell,state,args);
}

float dealRangedDamage(B)(ref MovingObject!B object,SacSpell!B rangedAttack,int attacker,int attackerSide,Vector3f attackDirection,DamageMod damageMod,ObjectState!B state){
	return dealRangedDamage(object,rangedAttack.amount,attacker,attackerSide,attackDirection,damageMod,state);
}
float dealRangedDamage(B)(ref MovingObject!B object,float damage,int attacker,int attackerSide,Vector3f attackDirection,DamageMod damageMod,ObjectState!B state){
	return object.dealDamage(damage,attacker,attackerSide,attackDirection,damageMod|DamageMod.ranged,state);
}

float dealRangedDamage(B)(ref MovingObject!B object,float damage,int attacker,int attackerSide,DamageMod damageMod,ObjectState!B state){
	return object.dealDamage(damage,attacker,attackerSide,damageMod|DamageMod.ranged,state);
}

float dealRangedDamage(B)(ref StaticObject!B object,SacSpell!B rangedAttack,int attacker,int attackerSide,Vector3f attackDirection,DamageMod damageMod,ObjectState!B state){
	return dealRangedDamage(object,rangedAttack.amount,attacker,attackerSide,attackDirection,damageMod,state);
}
float dealRangedDamage(B)(ref StaticObject!B object,float damage,int attacker,int attackerSide,Vector3f attackDirection,DamageMod damageMod,ObjectState!B state){
	return state.buildingById!(dealRangedDamage,()=>0.0f)(object.buildingId,damage,attacker,attackerSide,attackDirection,damageMod,state);
}
float dealRangedDamage(B)(ref StaticObject!B object,float damage,int attacker,int attackerSide,DamageMod damageMod,ObjectState!B state){
	return state.buildingById!(dealRangedDamage,()=>0.0f)(object.buildingId,damage,attacker,attackerSide,damageMod,state);
}

float dealRangedDamage(B)(ref Building!B building,SacSpell!B rangedAttack,int attacker,int attackerSide,Vector3f attackDirection,DamageMod damageMod,ObjectState!B state){
	auto damage=rangedAttack.amount;
	return dealRangedDamage(building,damage,attacker,attackerSide,attackDirection,damageMod,state);
}

float dealRangedDamage(B)(ref Building!B building,float damage,int attacker,int attackerSide,Vector3f attackDirection,DamageMod damageMod,ObjectState!B state){
	return dealRangedDamage(building,damage,attacker,attackerSide,damageMod,state);
}
float dealRangedDamage(B)(ref Building!B building,float damage,int attacker,int attackerSide,DamageMod damageMod,ObjectState!B state){
	return dealDamage(building,damage,attacker,attackerSide,damageMod|DamageMod.ranged,state);
}

float dealRangedDamage(B)(int target,SacSpell!B rangedAttack,int attacker,int attackerSide,Vector3f attackDirection,DamageMod damageMod,ObjectState!B state){
	if(!state.isValidTarget(target)) return 0.0f;
	return state.objectById!dealRangedDamage(target,rangedAttack,attacker,attackerSide,attackDirection,damageMod,state);
}


float dealSplashDamage(B)(ref MovingObject!B object,SacSpell!B spell,int attacker,int attackerSide,Vector3f attackDirection,float distance,DamageMod damageMod,ObjectState!B state){
	return dealSplashDamage(object,spell.amount,spell.damageRange,attacker,attackerSide,attackDirection,distance,damageMod,state);
}

float dealSplashDamage(B)(ref MovingObject!B object,float amount,float damageRange,int attacker,int attackerSide,Vector3f attackDirection,float distance,DamageMod damageMod,ObjectState!B state){
	return object.dealDamage(amount,damageRange,attacker,attackerSide,attackDirection,distance,damageMod|DamageMod.splash,state);
}

float dealSplashDamage(B)(ref Building!B building,SacSpell!B spell,int attacker,int attackerSide,Vector3f attackDirection,float distance,DamageMod damageMod,ObjectState!B state){
	return building.dealDamage(spell.amount,spell.damageRange,attacker,attackerSide,attackDirection,distance,damageMod,state);
}

float dealSplashDamageAt(alias callback=(id)=>true,B,T...)(int directTarget,SacSpell!B spell,float radius,int attacker,int attackerSide,Vector3f position,DamageMod damageMod,ObjectState!B state,T args){
	return dealDamageAt!callback(directTarget,spell.amount,radius,attacker,attackerSide,position,damageMod|DamageMod.splash,state,args);
}

float dealSplashRangedDamageAt(alias callback=(id)=>true,B,T...)(int directTarget,SacSpell!B rangedAttack,float radius,int attacker,int attackerSide,Vector3f position,DamageMod damageMod,ObjectState!B state,T args){
	return dealSplashDamageAt!callback(directTarget,rangedAttack,radius,attacker,attackerSide,position,damageMod|DamageMod.ranged,state,args);
}

float dealDesecrationDamage(B)(ref MovingObject!B object,float damage,int attackingSide,ObjectState!B state){
	if(!object.canDamage(state)) return 0.0f;
	return dealRawDamage(object,damage,attackingSide,DamageMod.desecration,state);
}

float dealPoisonDamage(B)(ref MovingObject!B object,float damage,int attacker,int attackerSide,DamageMod damageMod,ObjectState!B state){
	if(object.id==attacker?object.isGuardian:state.movingObjectById!((ref attacker)=>attacker.isGuardian,()=>false)(attacker))
		damage*=1.5f;
	return object.dealDamage(damage,attacker,attackerSide,damageMod,state);
}

float dealFireDamage(T,B)(ref T object,float rangedDamage,float spellDamage,int attacker,int attackerSide,DamageMod damageMod,ObjectState!B state){
	auto actualRangedDamage=0.0f;
	if(rangedDamage>0.0f) actualRangedDamage=object.dealRangedDamage(rangedDamage,attacker,attackerSide,damageMod,state);
	auto actualSpellDamage=0.0f;
	if(spellDamage>0.0f) actualSpellDamage=object.dealSpellDamage(spellDamage,attacker,attackerSide,damageMod,state);
	return actualRangedDamage+actualSpellDamage;
}

float dealFallDamage(B)(ref MovingObject!B object,ObjectState!B state){
	enum fallDamageFactor=20.0f;
	//auto damage=sqrt(max(0.0f,-object.creatureState.fallingVelocity.z))*fallDamageFactor;
	auto damage=max(0.0f,-object.creatureState.fallingVelocity.z-5.0f)*60.0/55.0*fallDamageFactor; // TODO: correct?
	return object.dealDamage(damage,-1,DamageMod.fall,state); // TODO: properly attribute fall damage to sides
}


void setMovement(B)(ref MovingObject!B object,MovementDirection direction,ObjectState!B state,int side=-1){
	if(!object.canOrder(side,state)) return;
	if(object.creatureState.movement==CreatureMovement.flying &&
	   direction==MovementDirection.backward &&
	   !object.sacObject.canFlyBackward)
		return;
	if(object.creatureState.movementDirection==direction)
		return;
	object.creatureState.movementDirection=direction;
	if(object.creatureStats.effects.immobilized||object.creatureStats.effects.fixed) return;
	if(object.creatureState.mode.among(CreatureMode.idle,CreatureMode.moving))
		object.setCreatureState(state);
}
void stopMovement(B)(ref MovingObject!B object,ObjectState!B state,int side=-1){
	object.setMovement(MovementDirection.none,state,side);
}
void startMovingForward(B)(ref MovingObject!B object,ObjectState!B state,int side=-1){
	object.setMovement(MovementDirection.forward,state,side);
}
void startMovingBackward(B)(ref MovingObject!B object,ObjectState!B state,int side=-1){
	object.setMovement(MovementDirection.backward,state,side);
}

void setTurning(B)(ref MovingObject!B object,RotationDirection direction,ObjectState!B state,int side=-1){
	if(!object.canOrder(side,state)) return;
	object.creatureState.rotationDirection=direction;
	if(direction==RotationDirection.none) object.creatureState.rotationSpeedLimit=float.infinity;
}
void stopTurning(B)(ref MovingObject!B object,ObjectState!B state,int side=-1){
	object.setTurning(RotationDirection.none,state,side);
}
void startTurningLeft(B)(ref MovingObject!B object,ObjectState!B state,int side=-1){
	object.setTurning(RotationDirection.left,state,side);
}
void startTurningRight(B)(ref MovingObject!B object,ObjectState!B state,int side=-1){
	object.setTurning(RotationDirection.right,state,side);
}

void startCowering(B)(ref MovingObject!B object,ObjectState!B state){
	if(!object.isPeasant) return;
	object.stop(state);
	object.creatureState.mode=CreatureMode.cower;
	object.setCreatureState(state);
}

bool isGhost(B)(ref MovingObject!B object){
	return object.creatureState.mode.isGhost;
}
bool isDying(B)(ref MovingObject!B object){
	return object.creatureState.mode.isDying;
}
bool isDead(B)(ref MovingObject!B object){
	return object.creatureState.mode==CreatureMode.dead;
}
bool isAlive(B)(ref MovingObject!B object){
	return object.creatureState.mode.isAlive;
}

bool canCast(B)(ref MovingObject!B object,ObjectState!B state){
	if(!object.isWizard) return false;
	if(!object.creatureState.mode.among(CreatureMode.idle,CreatureMode.moving)&&object.castStatus(state)!=CastingStatus.finished)
		return false;
	return true;
}

bool startCasting(B)(ref MovingObject!B object,int numFrames,bool stationary,ObjectState!B state){
	if(!object.canCast(state)) return false;
	if(stationary) object.creatureState.mode=CreatureMode.stationaryCasting;
	else object.creatureState.mode=object.creatureState.mode==CreatureMode.idle?CreatureMode.casting:CreatureMode.castingMoving;
	object.creatureState.timer=numFrames;
	object.creatureState.timer2=playSoundTypeAt!true(object.sacObject,object.id,SoundType.incantation,state)+updateFPS/10;
	object.setCreatureState(state);
	return true;
}
int getCastingTime(B)(ref MovingObject!B object,int numFrames,bool stationary,ObjectState!B state){
	// TODO: "stationary" parameter is probably unnecessary
	auto sacObject=object.sacObject;
	auto start=sacObject.numFrames(stationary?AnimationState.spellcastStart:AnimationState.runSpellcastStart)*updateAnimFactor;
	auto mid=sacObject.numFrames(stationary?AnimationState.spellcast:AnimationState.runSpellcast)*updateAnimFactor;
	//auto end=sacObject.numFrames(stationary?AnimationState.spellcastEnd:AnimationState.runSpellcastEnd)*updateAnimFactor;
	auto castingTime=sacObject.castingTime(stationary?AnimationState.spellcastEnd:AnimationState.runSpellcastEnd)*updateAnimFactor;
	return start+max(0,numFrames-start-castingTime+mid-1)/mid*mid+castingTime;
}
int getCastingTime(B)(ref MovingObject!B object,SacSpell!B spell,bool stationary,ObjectState!B state){
	auto wizard=state.getWizard(object.id);
	int numFrames=cast(int)ceil(updateFPS*spell.castingTime(wizard.level));
	return getCastingTime(object,spell,stationary,state);
}

enum manaEpsilon=1e-2f;
enum summonSoundGain=2.0f;
bool startCasting(B)(int caster,SacSpell!B spell,OrderTarget target,ObjectState!B state){
	auto wizard=state.getWizard(caster);
	if(!wizard) return false;
	if(state.spellStatus!false(wizard,spell,target)!=SpellStatus.ready) return false;
	int numFrames=cast(int)ceil(updateFPS*spell.castingTime(wizard.level));
	if(!state.movingObjectById!((ref object,numFrames,spell,state)=>object.startCasting(numFrames,spell.stationary,state),()=>false)(caster,numFrames,spell,state))
		return false;
	auto drainSpeed=spell.isBuilding?125.0f:500.0f;
	auto numManaDrainFrames=min(numFrames,cast(int)ceil(spell.manaCost*(updateFPS/drainSpeed)));
	auto manaCostPerFrame=spell.manaCost/numManaDrainFrames;
	auto manaDrain=ManaDrain!B(caster,manaCostPerFrame,numManaDrainFrames);
	(*wizard).applyCooldown(spell,state);
	bool stun(bool ok=false){
		if(!ok) state.movingObjectById!((ref object){ object.damageStun(Vector3f(0.0f,0.0f,-1.0f),state); },(){})(caster);
		return ok;
	}
	final switch(spell.type){
		case SpellType.creature:
			assert(target is OrderTarget.init);
			auto creature=spawn(caster,spell.tag,0,state);
			if(!creature) return false;
			state.setRenderMode!(MovingObject!B,RenderMode.transparent)(creature);
			state.setAlpha(creature,0.36f,10.0f);
			playSoundAt("NMUS",creature,state,summonSoundGain);
			state.addEffect(CreatureCasting!B(manaDrain,spell,creature));
			return true;
		case SpellType.spell:
			bool ok=false;
			switch(spell.tag){
				case SpellTag.convert:
					auto sidePosition=state.movingObjectById!((ref object)=>tuple(object.side,object.position),()=>tuple(-1,Vector3f.init))(caster);
					auto side=sidePosition[0],position=sidePosition[1];
					if(side==-1) return false;
					return stun(castConvert(side,manaDrain,spell,position,target.id,wizard.closestShrine,state));
				case SpellTag.desecrate:
					auto sidePosition=state.movingObjectById!((ref object)=>tuple(object.side,object.position),()=>tuple(-1,Vector3f.init))(caster);
					auto side=sidePosition[0],position=sidePosition[1];
					if(side==-1) return false;
					return stun(castDesecrate(side,manaDrain,spell,position,target.id,wizard.closestEnemyAltar,state));
				case SpellTag.teleport:
					auto position=state.movingObjectById!((ref object)=>object.position,()=>Vector3f.init)(caster);
					if(isNaN(position.x)) return false;
					return stun(castTeleport(manaDrain,spell,position,target.id,state));
				case SpellTag.guardian:
					return stun(castGuardian(manaDrain,spell,target.id,state));
				case SpellTag.speedup:
					ok=speedUp(target.id,spell,state);
					goto default;
				case SpellTag.heal:
					return stun(castHeal(target.id,manaDrain,spell,state));
				case SpellTag.lightning:
					return stun(castLightning(target.id,manaDrain,spell,state));
				case SpellTag.wrath:
					return stun(castWrath(target.id,manaDrain,spell,state));
				case SpellTag.fireball:
					return stun(castFireball(target.id,manaDrain,spell,state));
				case SpellTag.rock:
					auto castingTime=state.movingObjectById!((ref object)=>object.getCastingTime(numFrames,spell.stationary,state),()=>-1)(caster);
					if(castingTime==-1) return false;
					return stun(castRock(caster,target.id,manaDrain,spell,castingTime,state));
				case SpellTag.insectSwarm:
					auto castingTime=state.movingObjectById!((ref object)=>object.getCastingTime(numFrames,spell.stationary,state),()=>-1)(caster);
					if(castingTime==-1) return false;
					return stun(castSwarm(target.id,manaDrain,spell,castingTime,state));
				case SpellTag.skinOfStone:
					auto castingTime=state.movingObjectById!((ref object)=>object.getCastingTime(numFrames,spell.stationary,state),()=>-1)(caster);
					if(castingTime==-1) return false;
					return stun(castSkinOfStone(manaDrain,spell,castingTime,state));
				case SpellTag.etherealForm:
					return stun(castEtherealForm(manaDrain,spell,state));
				case SpellTag.fireform:
					auto castingTime=state.movingObjectById!((ref object)=>object.getCastingTime(numFrames,spell.stationary,state),()=>-1)(caster);
					if(castingTime==-1) return false;
					return stun(castFireform(manaDrain,spell,castingTime,state));
				case SpellTag.protectiveSwarm:
					auto castingTime=state.movingObjectById!((ref object)=>object.getCastingTime(numFrames,spell.stationary,state),()=>-1)(caster);
					if(castingTime==-1) return false;
					return stun(castProtectiveSwarm(manaDrain,spell,castingTime,state));
				case SpellTag.airShield:
					auto castingTime=state.movingObjectById!((ref object)=>object.getCastingTime(numFrames,spell.stationary,state),()=>-1)(caster);
					if(castingTime==-1) return false;
					return stun(castAirShield(manaDrain,spell,castingTime,state));
				case SpellTag.freeze:
					return stun(castFreeze(target.id,manaDrain,spell,state));
				case SpellTag.ringsOfFire:
					return stun(castRingsOfFire(target.id,manaDrain,spell,state));
				case SpellTag.slime:
					auto castingTime=state.movingObjectById!((ref object)=>object.getCastingTime(numFrames,spell.stationary,state),()=>-1)(caster);
					return stun(castSlime(target.id,manaDrain,spell,castingTime,state));
				case SpellTag.graspingVines:
					return stun(castGraspingVines(target.id,manaDrain,spell,state));
				case SpellTag.soulMole:
					return stun(castSoulMole(target.id,manaDrain,spell,state));
				case SpellTag.rainbow:
					auto side=state.movingObjectById!((ref object)=>object.side,()=>-1)(caster);
					if(side==-1) return false;
					return stun(castRainbow(side,target.id,manaDrain,spell,state));
				case SpellTag.chainLightning:
					auto side=state.movingObjectById!((ref object)=>object.side,()=>-1)(caster);
					if(side==-1) return false;
					return stun(castChainLightning(side,target.id,manaDrain,spell,state));
				case SpellTag.animateDead:
					return stun(castAnimateDead(target.id,manaDrain,spell,state));
				case SpellTag.erupt:
					auto side=state.movingObjectById!((ref object)=>object.side,()=>-1)(caster);
					return stun(castErupt(side,target.position,manaDrain,spell,state));
				case SpellTag.dragonfire:
					auto castingTime=state.movingObjectById!((ref object)=>object.getCastingTime(numFrames,spell.stationary,state),()=>-1)(caster);
					return stun(castDragonfire(target.id,manaDrain,spell,castingTime,state));
				case SpellTag.soulWind:
					return stun(castSoulWind(target.id,manaDrain,spell,state));
				case SpellTag.explosion:
					auto side=state.movingObjectById!((ref object)=>object.side,()=>-1)(caster);
					auto castingTime=state.movingObjectById!((ref object)=>object.getCastingTime(numFrames,spell.stationary,state),()=>-1)(caster);
					if(side==-1||castingTime==-1) return false;

					auto position=target.type==TargetType.building?target.center(state):target.position;
					return stun(castExplosion(side,position,manaDrain,spell,castingTime,state));
				case SpellTag.haloOfEarth:
					auto side=state.movingObjectById!((ref object)=>object.side,()=>-1)(caster);
					auto castingTime=state.movingObjectById!((ref object)=>object.getCastingTime(numFrames,spell.stationary,state),()=>-1)(caster);
					if(side==-1||castingTime==-1) return false;
					return stun(castHaloOfEarth(caster,side,manaDrain,spell,castingTime,state));
				case SpellTag.rainOfFrogs:
					auto side=state.movingObjectById!((ref object)=>object.side,()=>-1)(caster);
					return stun(castRainOfFrogs(side,target.position,manaDrain,spell,state));
				case SpellTag.demonicRift:
					auto side=state.movingObjectById!((ref object)=>object.side,()=>-1)(caster);
					auto position=state.movingObjectById!((ref object)=>object.position,()=>Vector3f.init)(caster);
					if(isNaN(position.x)) return false;
					return stun(castDemonicRift(side,position,target,manaDrain,spell,state));
				default:
					if(ok) state.addEffect(manaDrain);
					return stun(ok);
			}
		case SpellType.structure:
			if(!spell.isBuilding) goto case SpellType.spell;
			auto base=state.staticObjectById!((obj)=>obj.buildingId,()=>0)(target.id);
			if(base){ // TODO: stun both wizards on simultaneous lith cast
				auto god=state.getCurrentGod(wizard);
				if(god==God.none) god=God.persephone;
				auto building=makeBuilding(caster,spell.buildingTag(god),AdditionalBuildingFlags.inactive|Flags.cannotDamage,base,state);
				state.setupStructureCasting(building);
				float buildingHeight=state.buildingById!((ref bldg,state)=>height(bldg,state),()=>0.0f)(building,state);
				auto castingTime=state.movingObjectById!((ref object)=>object.getCastingTime(numFrames,spell.stationary,state),()=>-1)(caster);
				if(castingTime==-1) return false;
				state.addEffect(StructureCasting!B(god,manaDrain,spell,building,buildingHeight,castingTime,0));
				return true;
			}else return stun();
	}
}

bool startShooting(B)(ref MovingObject!B object,ObjectState!B state){
	if(!object.creatureState.mode.among(CreatureMode.idle,CreatureMode.moving))
		return false;
	object.stopMovement(state);
	object.creatureState.mode=CreatureMode.shooting;
	object.setCreatureState(state);
	return true;
}

bool startUsingAbility(B)(ref MovingObject!B object,ObjectState!B state){
	if(!object.creatureState.mode.among(CreatureMode.idle,CreatureMode.moving))
		return false;
	object.stopMovement(state);
	object.creatureState.mode=CreatureMode.usingAbility;
	object.setCreatureState(state);
	return true;
}

bool startPulling(B)(ref MovingObject!B object,ObjectState!B state){
	if(object.creatureState.mode!=CreatureMode.usingAbility)
		return false;
	object.creatureState.mode=CreatureMode.pulling;
	object.clearOrderQueue(state);
	return true;
}

bool startPumping(B)(ref MovingObject!B object,ObjectState!B state){
	if(!object.isSacDoctor||!object.creatureState.mode.among(CreatureMode.idle,CreatureMode.moving,CreatureMode.stunned))
		return false;
	object.stopMovement(state);
	if(object.creatureState.mode!=CreatureMode.pumping){
		object.creatureState.mode=CreatureMode.pumping;
		object.setCreatureState(state);
	}
	return true;
}

bool startTorturing(B)(ref MovingObject!B object,ObjectState!B state){
	if(!object.isSacDoctor||!object.creatureState.mode.among(CreatureMode.idle,CreatureMode.moving))
		return false;
	object.creatureState.mode=CreatureMode.torturing;
	object.setCreatureState(state);
	return true;
}

bool startThrashing(B)(ref MovingObject!B object,ObjectState!B state){
	with(CreatureMode) if(object.creatureState.mode.among(dying,dead,dissolving,preSpawning,reviving,fastReviving,thrashing)) return false;
	object.stopMovement(state);
	object.creatureState.mode=CreatureMode.thrashing;
	object.creatureState.movement=CreatureMovement.flying;
	object.setCreatureState(state);
	object.unselect(state);
	object.removeFromGroups(state);
	return true;
}
bool freeCreature(B)(ref MovingObject!B object,Vector3f landingPosition,ObjectState!B state){
	if(object.creatureState.mode==CreatureMode.convertReviving){
		object.kill(state);
		return true;
	}
	if(object.creatureState.mode!=CreatureMode.thrashing) return false;
	object.creatureState.mode=CreatureMode.stunned;
	object.creatureState.movement=CreatureMovement.tumbling;
	if(isNaN(landingPosition.x)) object.creatureState.fallingVelocity=Vector3f(0.0f,0.0f,0.0f);
	else object.creatureState.fallingVelocity=getFallingVelocity(landingPosition-object.position,5.0f,state);
	object.setCreatureState(state);
	return true;
}

bool castConvert(B)(int side,ManaDrain!B manaDrain,SacSpell!B spell,Vector3f castPosition,int target,int targetShrine,ObjectState!B state){
	if(!targetShrine) return false;
	auto targetPosition=state.soulById!((ref soul,int side){
		static assert(is(typeof(soul.convertSideMask)==uint));
		if(0<=side&&side<32) soul.convertSideMask&=~(1u<<side);
		return soul.position;
	},function()=>Vector3f.init)(target,side);
	if(isNaN(targetPosition.x)) return false;
	auto direction=(targetPosition-castPosition).normalized;
	auto position=targetPosition+RedVortex.convertDistance*direction;
	auto landingPosition=0.5f*(position+targetPosition);
	position.z=state.getHeight(position)+RedVortex.convertHeight;
	state.addEffect(SacDocCasting!B(RitualType.convert,side,manaDrain,spell,target,targetShrine,landingPosition,RedVortex(position)));
	return true;
}

bool castDesecrate(B)(int side,ManaDrain!B manaDrain,SacSpell!B spell,Vector3f castPosition,int target,int targetShrine,ObjectState!B state){
	if(!targetShrine) return false;
	auto targetPosition=state.movingObjectById!((ref obj)=>obj.position,()=>Vector3f.init)(target);
	if(isNaN(targetPosition.x)) return false;
	auto direction=(targetPosition-castPosition).normalized;
	auto position=targetPosition-20.0f*direction; // TODO: ok?
	auto landingPosition=0.5f*(position+targetPosition);
	position.z=state.getHeight(position)+RedVortex.desecrateHeight;
	state.addEffect(SacDocCasting!B(RitualType.desecrate,side,manaDrain,spell,target,targetShrine,landingPosition,RedVortex(position)));
	return true;
}

Vector3f getTeleportPosition(B)(Vector3f startPosition,int target,float radius,ObjectState!B state){
	if(!state.isValidTarget(target)) return Vector3f.init;
	auto targetPositionTargetScale=state.objectById!((ref obj)=>tuple(obj.position,obj.getScale))(target);
	auto targetPosition=targetPositionTargetScale[0], targetScale=targetPositionTargetScale[1];
	auto teleportPosition=targetPosition+(startPosition-targetPosition).normalized*radius;
	if(!state.isOnGround(teleportPosition)){
		teleportPosition=targetPosition; // TODO: fix
	}
	return teleportPosition;
}

Vector3f getTeleportPosition(B)(SacSpell!B spell,Vector3f startPosition,int target,ObjectState!B state){
	return getTeleportPosition(startPosition,target,spell.effectRange,state);
}

bool castTeleport(B)(ManaDrain!B manaDrain,SacSpell!B spell,Vector3f startPosition,int target,ObjectState!B state){
	auto position=getTeleportPosition(spell,startPosition,target,state);
	if(isNaN(position.x)) return false;
	state.addEffect(TeleportCasting!B(manaDrain,spell,target,position));
	return true;
}

void animateTeleport(B)(bool isOut,Vector3f[2] hitbox,ObjectState!B state,bool soundEffect=true){
	auto position=boxCenter([hitbox[0],Vector3f(hitbox[1].x,hitbox[1].y,hitbox[0].z)]);
	auto size=boxSize(hitbox);
	auto scale=max(size.x,size.y);
	if(soundEffect) playSoundAt("elet",position,state,2.0f);
	state.addEffect(TeleportEffect!B(isOut,position,scale,size.z));
	auto sacParticle=SacParticle!B.get(ParticleType.heal);
	auto pscale=size.length;
	auto velocity=Vector3f(0.0f,0.0f,0.0f);
	auto lifetime=63;
	auto frame=0;
	foreach(i;0..50){
		auto pposition=state.uniform(scaleBox(hitbox,1.3f));
		auto npscale=pscale*state.uniform(0.5f,1.5f);
		state.addParticle(Particle!B(sacParticle,pposition,velocity,pscale,lifetime,frame));
	}
}

void animateWizardVoidTeleport(B)(bool isOut,Vector3f[2] hitbox,ObjectState!B state){
	return animateTeleport(isOut,hitbox,state,false);
}

bool teleport(B)(ref MovingObject!B obj,Vector3f newPosition,ObjectState!B state,bool wizardVoid=false){ // TODO: get rid of startPosition parameter
	if(!obj.isWizard&&!obj.isSacDoctor&&!obj.creatureAI.order.command.among(CommandType.guard,CommandType.retreat))
		obj.clearOrderQueue(state);
	auto oldHeight=obj.position.z-state.getHeight(obj.position);
	newPosition.z=state.getHeight(newPosition)+max(0.0f,oldHeight);
	auto startHitbox=obj.hitbox;
	obj.position=newPosition;
	auto newHitbox=obj.hitbox;
	if(wizardVoid){
		animateWizardVoidTeleport(true,startHitbox,state);
		animateWizardVoidTeleport(false,newHitbox,state);
	}else{
		animateTeleport(true,startHitbox,state);
		animateTeleport(false,newHitbox,state);
	}
	return true;
}

bool teleport(B)(int side,Vector3f startPosition,Vector3f targetPosition,SacSpell!B spell,ObjectState!B state){
	static void teleport(ref CenterProximityEntry entry,int side,Vector3f startPosition,Vector3f targetPosition,ObjectState!B state){
		static void doIt(ref MovingObject!B obj,Vector3f startPosition,Vector3f targetPosition,ObjectState!B state){
			if(obj.isSacDoctor||obj.isGuardian||obj.isDying||obj.isDead) return;
			auto newPosition=obj.position-startPosition+targetPosition;
			if(obj.creatureState.movement!=CreatureMovement.flying&&!state.isOnGround(newPosition)){
				newPosition=targetPosition; // TODO: fix
			}
			obj.teleport(newPosition,state);
		}
		if(entry.isStatic||!state.isValidTarget(entry.id,TargetType.creature)||side!=entry.side) return;
		state.movingObjectById!(doIt,(){})(entry.id,startPosition,targetPosition,state);
	}
	state.proximity.eachInRange!teleport(startPosition,spell.effectRange,side,startPosition,targetPosition,state);
	return true;
}

bool castGuardian(B)(ManaDrain!B manaDrain,SacSpell!B spell,int target,ObjectState!B state){
	state.addEffect(GuardianCasting!B(manaDrain,spell,target));
	return true;
}

int findClosestBuilding(B)(int side,Vector3f position,ObjectState!B state){
	static struct Result{
		int currentId=0;
		float currentDistance=float.infinity;
	}
	static void find(T)(ref T objects,int side,Vector3f position,ObjectState!B state,Result* result){
		static if(is(T==StaticObjects!(B,renderMode),RenderMode renderMode)){
			bool altar=objects.sacObject.isAltar;
			bool shrine=objects.sacObject.isShrine;
			if(altar||shrine||objects.sacObject.isManalith){ // TODO: use cached indices?
				foreach(j;0..objects.length){
					if(state.buildingById!((ref bldg,side)=>bldg.side!=side,()=>true)(objects.buildingIds[j],side))
						continue;
					auto candidateDistance=(position-objects.positions[j]).xy.lengthsqr;
					if(candidateDistance<result.currentDistance){ // TODO: is it really possible to guard over the void?
						result.currentId=objects.ids[j];
						result.currentDistance=candidateDistance;
					}
				}
			}
		}
	}
	Result result;
	state.eachByType!find(side,position,state,&result);
	return result.currentId;
}

bool guardian(B)(int side,SacSpell!B spell,int target,ObjectState!B state){
	if(side==-1) return false;
	return state.movingObjectById!((ref obj,side,state){
		if(obj.side!=side||obj.isWizard||obj.isHero||obj.isFamiliar||obj.isSacDoctor) return false;
		if(obj.creatureStats.effects.isGuardian) return false;
		int structure=findClosestBuilding(side,obj.position,state);
		if(!structure) return false;
		int buildingId=state.staticObjectById!((ref obj)=>obj.buildingId,()=>0)(structure);
		if(!buildingId) return false;
		if(!state.buildingById!((ref bldg,int id){ bldg.guardianIds~=id; return true; },()=>false)(buildingId,obj.id))
			return false;
		obj.unselect(state);
		obj.removeFromGroups(state);
		obj.clearOrderQueue(state);
		obj.creatureStats.effects.isGuardian=true;
		state.addEffect(Guardian(obj.id,buildingId));
		return true;
	},()=>false)(target,side,state);
}


enum doubleSpeedUpDelay=cast(int)(0.2f*updateFPS); // 200ms

bool speedUp(B)(ref MovingObject!B object,SacSpell!B spell,float duration,ObjectState!B state){
	playSoundAt("pups",object.id,state,2.0f);
	object.creatureStats.effects.numSpeedUps+=1;
	if(object.creatureStats.effects.speedUpFrame==-1)
		object.creatureStats.effects.speedUpFrame=state.frame;
	state.addEffect(SpeedUp!B(object.id,cast(int)(duration*updateFPS)));
	return true;
}
bool speedUp(B)(ref MovingObject!B object,SacSpell!B spell,ObjectState!B state){
	auto duration=(object.isWizard?spell.duration*0.2f:spell.duration*1000.0f/object.creatureStats.maxHealth)+0.5f;
	return speedUp(object,spell,duration,state);
}
bool speedUp(B)(int creature,SacSpell!B spell,ObjectState!B state){
	if(!state.isValidTarget(creature,TargetType.creature)) return false;
	return state.movingObjectById!(speedUp,()=>false)(creature,spell,state);
}

bool castHeal(B)(int creature,ManaDrain!B manaDrain,SacSpell!B spell,ObjectState!B state){
	if(!state.isValidTarget(creature,TargetType.creature)) return false;
	state.addEffect(HealCasting!B(manaDrain,spell,creature));
	return true;
}
enum healSpeed=250.0f;
bool heal(B)(int creature,SacSpell!B spell,ObjectState!B state){
	if(!state.movingObjectById!(canHeal,()=>false)(creature,state)) return false;
	playSoundAt("laeh",creature,state,2.0f);
	auto amount=spell.amount;
	auto duration=spell.amount==float.infinity?int.max:cast(int)ceil(amount/healSpeed*updateFPS);
	auto healthRegenerationPerFrame=spell.amount==float.infinity?healSpeed/updateFPS:amount/duration;
	state.addEffect(Heal!B(creature,healthRegenerationPerFrame,duration));
	return true;
}

bool castLightning(B)(int target,ManaDrain!B manaDrain,SacSpell!B spell,ObjectState!B state){
	if(!state.isValidTarget(target)) return false;
	auto orderTarget=state.objectById!((obj){
		enum type=is(typeof(obj)==MovingObject!B)?TargetType.creature:TargetType.building;
		return OrderTarget(type,obj.id,obj.center);
	})(target);
	state.addEffect(LightningCasting!B(manaDrain,spell,orderTarget));
	return true;
}

bool lightning(B)(int wizard,int side,OrderTarget start,OrderTarget end,SacSpell!B spell,ObjectState!B state,bool updateTargets=true,DamageMod damageMod=DamageMod.lightning){
	if(updateTargets){
		auto startCenter=start.center(state),endCenter=end.center(state);
		static bool filter(ref ProximityEntry entry,int id){ return entry.id!=id; }
		auto newEnd=state.collideRay!filter(startCenter,endCenter-startCenter,1.0f,wizard);
		if(newEnd.type!=TargetType.none){
			end=newEnd;
			endCenter=end.center(state);
		}
		end.position=endCenter;
	}
	playSpellSoundTypeAt(SoundType.lightning,0.5f*(start.position+end.position),state,4.0f);
	auto lightning=Lightning!B(wizard,side,start,end,spell,damageMod,0);
	foreach(ref bolt;lightning.bolts)
		bolt.changeShape(state);
	state.addEffect(lightning);
	return true;
}

bool castWrath(B)(int target,ManaDrain!B manaDrain,SacSpell!B spell,ObjectState!B state){
	if(!state.isValidTarget(target)) return false;
	state.addEffect(WrathCasting!B(manaDrain,spell,centerTarget(target,state)));
	return true;
}

bool wrath(B)(int wizard,int side,Vector3f position,OrderTarget target,SacSpell!B spell,ObjectState!B state){
	target.position=target.center(state);
	playSoundAt("shtr",position,state,4.0f); // TODO: move sound with wrath ball
	auto velocity=Vector3f(0.0f,0.0f,0.0f);
	auto wrath=Wrath!B(wizard,side,position,velocity,target,spell);
	state.addEffect(wrath);
	return true;
}

Fireball!B makeFireball(B)(int wizard,int side,Vector3f position,OrderTarget target,SacSpell!B spell,ObjectState!B state){
	auto rotationSpeed=2*pi!float*state.uniform(0.5f,2.0f)/updateFPS;
	auto velocity=Vector3f(0.0f,0.0f,0.0f);
	auto rotationAxis=state.uniformDirection();
	auto rotationUpdate=rotationQuaternion(rotationAxis,rotationSpeed);
	return Fireball!B(wizard,side,position,velocity,target,spell,rotationUpdate,Quaternionf.identity());
}
Vector3f fireballCastingPosition(B)(ref MovingObject!B obj,ObjectState!B state){
	auto hbox=obj.sacObject.hitbox(Quaternionf.identity(),AnimationState.stance1,0);
	return obj.position+rotate(obj.rotation,Vector3f(0.0f,hbox[1].y+0.75f,hbox[1].z+0.25f));
}
bool castFireball(B)(int target,ManaDrain!B manaDrain,SacSpell!B spell,ObjectState!B state){
	if(!state.isValidTarget(target)) return false;
	auto positionSide=state.movingObjectById!((obj,state)=>tuple(obj.fireballCastingPosition(state),obj.side),function Tuple!(Vector3f,int){ assert(0); })(manaDrain.wizard,state);
	auto position=positionSide[0],side=positionSide[1];
	auto fireball=makeFireball(manaDrain.wizard,side,position,centerTarget(target,state),spell,state);
	state.addEffect(FireballCasting!B(manaDrain,fireball));
	return true;
}

bool fireball(B)(Fireball!B fireball,ObjectState!B state){
	playSpellSoundTypeAt(SoundType.fireball,fireball.position,state,4.0f); // TODO: move sound with fireball
	state.addEffect(fireball);
	return true;
}

Rock!B makeRock(B)(int wizard,int side,Vector3f position,OrderTarget target,SacSpell!B spell,ObjectState!B state){
	auto rotationSpeed=2*pi!float*state.uniform(0.2f,0.8f)/updateFPS;
	auto velocity=Vector3f(0.0f,0.0f,0.0f);
	auto rotationAxis=state.uniformDirection();
	auto rotationUpdate=rotationQuaternion(rotationAxis,rotationSpeed);
	return Rock!B(wizard,side,position,velocity,target,spell,rotationUpdate,Quaternionf.identity());
}
enum rockBuryDepth=1.0f;
Vector3f rockCastingPosition(B)(ref MovingObject!B obj,ObjectState!B state){
	auto hbox=obj.sacObject.hitbox(Quaternionf.identity(),AnimationState.stance1,0);
	auto position=obj.position+rotate(obj.rotation,Vector3f(0.0f,hbox[1].y+1.5f,0.0f));
	position.z=state.getHeight(position)-rockBuryDepth;
	return position;
}
bool castRock(B)(int wizard,int target,ManaDrain!B manaDrain,SacSpell!B spell,int castingTime,ObjectState!B state){
	if(!state.isValidTarget(target)) return false;
	auto positionSide=state.movingObjectById!((obj,state)=>tuple(obj.rockCastingPosition(state),obj.side),function Tuple!(Vector3f,int){ assert(0); })(manaDrain.wizard,state);
	auto position=positionSide[0],side=positionSide[1];
	auto rock=makeRock(wizard,side,position,centerTarget(target,state),spell,state);
	state.addEffect(RockCasting!B(manaDrain,spell,rock,0,castingTime));
	return true;
}

bool rock(B)(Rock!B rock,ObjectState!B state){
	playSoundAt("tlep",rock.position,state,4.0f);
	animateEmergingRock(rock,state);
	state.addEffect(rock);
	return true;
}

Bug!B makeBug(B)(Vector3f position,Vector3f velocity,Vector3f targetPosition){
	return Bug!B(position,velocity,targetPosition);
}

Swarm!B makeSwarm(B)(int wizard,int side,Vector3f position,OrderTarget target,SacSpell!B spell,int frame,ObjectState!B state){
	auto velocity=Vector3f(0.0f,0.0f,0.0f);
	return Swarm!B(wizard,side,position,velocity,target,spell,frame);
}
Vector3f swarmCastingPosition(B)(ref MovingObject!B obj,ObjectState!B state){
	auto hbox=obj.sacObject.hitbox(Quaternionf.identity(),AnimationState.stance1,0);
	return obj.position+rotate(obj.rotation,Vector3f(0.0f,hbox[1].y+0.75f,hbox[1].z+1.75f));
}
bool castSwarm(B)(int target,ManaDrain!B manaDrain,SacSpell!B spell,int castingTime,ObjectState!B state){
	if(!state.isValidTarget(target)) return false;
	auto positionSide=state.movingObjectById!((obj,state)=>tuple(obj.swarmCastingPosition(state),obj.side),function Tuple!(Vector3f,int){ assert(0); })(manaDrain.wizard,state);
	auto position=positionSide[0],side=positionSide[1];
	auto swarm=makeSwarm(manaDrain.wizard,side,position,centerTarget(target,state),spell,castingTime,state);
	playSpellSoundTypeAt(SoundType.swarm,swarm.position,state,4.0f); // TODO: move sound with swarm
	state.addEffect(SwarmCasting!B(manaDrain,spell,move(swarm)));
	return true;
}

bool swarm(B)(Swarm!B swarm,ObjectState!B state){
	state.addEffect(move(swarm));
	return true;
}

bool castSkinOfStone(B)(ManaDrain!B manaDrain,SacSpell!B spell,int castingTime,ObjectState!B state){
	if(state.movingObjectById!((ref obj)=>obj.creatureStats.effects.shieldBlocked,()=>true)(manaDrain.wizard)) return false;
	auto scale=state.movingObjectById!((ref obj)=>getScale(obj).length,()=>float.init)(manaDrain.wizard);
	if(isNaN(scale)) return false;
	state.addEffect(SkinOfStoneCasting!B(manaDrain,spell,0,castingTime,scale));
	return true;
}

bool skinOfStone(B)(ref MovingObject!B object,SacSpell!B spell,ObjectState!B state){
	if(object.creatureStats.effects.skinOfStone) return false;
	object.creatureStats.effects.skinOfStone=true;
	state.addEffect(SkinOfStone!B(object.id,spell));
	return true;
}

bool castEtherealForm(B)(ManaDrain!B manaDrain,SacSpell!B spell,ObjectState!B state){
	if(state.movingObjectById!((ref obj)=>obj.creatureStats.effects.shieldBlocked,()=>true)(manaDrain.wizard)) return false;
	state.addEffect(EtherealFormCasting!B(manaDrain,spell));
	return true;
}

bool etherealForm(B)(ref MovingObject!B object,SacSpell!B spell,ObjectState!B state){
	if(object.creatureStats.effects.etherealForm) return false;
	object.creatureStats.effects.etherealForm=true;
	playSoundAt("vniw",object.id,state);
	object.animateEtherealFormTransition(state);
	state.addEffect(EtherealForm!B(object.id,spell));
	return true;
}

enum fireformGain=4.0f;
bool castFireform(B)(ManaDrain!B manaDrain,SacSpell!B spell,int castingTime,ObjectState!B state){
	if(!state.movingObjectById!((ref obj){
		if(obj.creatureStats.effects.shieldBlocked) return false;
		if(obj.creatureStats.effects.fireform) return false;
		obj.creatureStats.effects.fireform=true;
		return true;
	},()=>false)(manaDrain.wizard)) return false;
	playSoundAt("1ngi",manaDrain.wizard,state,fireformGain);
	auto soundTimer=playSoundAt!true("5plf",manaDrain.wizard,state,fireformGain);
	state.addEffect(FireformCasting!B(manaDrain,spell,0,castingTime,soundTimer));
	return true;
}

bool fireform(B)(ref MovingObject!B object,SacSpell!B spell,ObjectState!B state,int soundTimer=-1){
	if(!object.creatureStats.effects.fireform) return false;
	if(soundTimer==-1) soundTimer=playSoundAt!true("5plf",object.id,state,fireformGain);
	state.addEffect(Fireform!B(object.id,spell,0,soundTimer));
	return true;
}

enum protectiveSwarmGain=1.0f;
bool castProtectiveSwarm(B)(ManaDrain!B manaDrain,SacSpell!B spell,int castingTime,ObjectState!B state){
	if(!state.movingObjectById!((ref obj){
		if(obj.creatureStats.effects.shieldBlocked) return false;
		if(obj.creatureStats.effects.protectiveSwarm) return false;
		obj.creatureStats.effects.protectiveSwarm=true;
		return true;
	},()=>false)(manaDrain.wizard)) return false;
	auto soundTimer=playSoundAt!true("3rws",manaDrain.wizard,state,protectiveSwarmGain);
	auto pswarm=ProtectiveSwarm!B(manaDrain.wizard,spell,castingTime,soundTimer);
	state.addEffect(ProtectiveSwarmCasting!B(manaDrain,spell,move(pswarm)));
	return true;
}

bool protectiveSwarm(B)(ProtectiveSwarm!B protectiveSwarm,ObjectState!B state){
	if(!state.movingObjectById!((ref object)=>object.creatureStats.effects.protectiveSwarm,()=>false)(protectiveSwarm.target))
		return false;
	state.addEffect(move(protectiveSwarm));
	return true;
}

enum airShieldGain=2.0f;
bool castAirShield(B)(ManaDrain!B manaDrain,SacSpell!B spell,int castingTime,ObjectState!B state){
	if(!state.movingObjectById!((ref object){
		if(object.creatureStats.effects.shieldBlocked) return false;
		if(object.creatureStats.effects.airShield) return false;
		object.creatureStats.effects.airShield=true;
		return true;
	},()=>false)(manaDrain.wizard)) return false;
	auto airShield=AirShield!B(manaDrain.wizard,spell);
	playSoundAt("dhsa",manaDrain.wizard,state,airShieldGain);
	state.addEffect(AirShieldCasting!B(manaDrain,castingTime,move(airShield)));
	return true;
}

bool airShield(B)(AirShield!B airShield,ObjectState!B state){
	if(!state.movingObjectById!((ref object){
		if(object.creatureStats.effects.airShield) return false;
		object.creatureStats.effects.airShield=true;
		return true;
	},()=>false)(airShield.target)) return false;
	playSoundAt("dhsa",airShield.target,state,airShieldGain);
	state.addEffect(move(airShield));
	return true;
}

bool castFreeze(B)(int target,ManaDrain!B manaDrain,SacSpell!B spell,ObjectState!B state){
	if(state.movingObjectById!((ref obj)=>obj.creatureStats.effects.ccProtected||!obj.creatureState.mode.canCC,()=>true)(target)) return false;
	state.addEffect(FreezeCasting!B(manaDrain,spell,target));
	return true;
}
enum freezeGain=4.0f;
bool freeze(B)(int wizard,int side,int target,SacSpell!B spell,ObjectState!B state){
	auto duration=state.movingObjectById!((ref obj){
		if(obj.creatureStats.effects.frozen) return -1;
		assert(!obj.creatureStats.effects.frozen);
		obj.creatureStats.effects.frozen=true;
		obj.creatureState.mode=CreatureMode.stunned;
		obj.startTumbling(state);
		auto duration=(obj.isWizard?.25f:1000.0f/obj.health)*spell.duration;
		return cast(int)ceil(updateFPS*duration);
	},()=>-1)(target);
	if(duration==-1) return false;
	playSoundAt("3zrf",target,state,freezeGain);
	state.addEffect(Freeze!B(target,spell,wizard,side,duration));
	return true;
}

bool castRingsOfFire(B)(int target,ManaDrain!B manaDrain,SacSpell!B spell,ObjectState!B state){
	if(!state.movingObjectById!((ref obj){
		if(obj.creatureStats.effects.ccProtected||!obj.creatureState.mode.canCC) return false;
		obj.creatureStats.effects.ringsOfFire=true;
		return true;
	},()=>false)(target)) return false;
	state.addEffect(RingsOfFireCasting!B(manaDrain,spell,target));
	return true;
}
enum ringsOfFireGain=4.0f;
bool ringsOfFire(B)(int wizard,int side,int target,SacSpell!B spell,ObjectState!B state){
	if(!state.movingObjectById!((ref obj)=>obj.creatureStats.effects.ringsOfFire,()=>false)(target)) return false;
	auto duration=cast(int)ceil(updateFPS*spell.duration);
	playSoundAt("malf",target,state,ringsOfFireGain);
	state.addEffect(RingsOfFire!B(target,spell,wizard,side,duration));
	return true;
}

bool castSlime(B)(int target,ManaDrain!B manaDrain,SacSpell!B spell,int castingTime,ObjectState!B state){
	if(!state.movingObjectById!((ref obj){
		if(obj.creatureStats.effects.ccProtected||!obj.creatureState.mode.canCC) return false;
		return true;
	},()=>false)(target)) return false;
	state.addEffect(SlimeCasting!B(manaDrain,spell,target,castingTime));
	return true;
}
enum slimeGain=4.0f;
bool slime(B)(int target,SacSpell!B spell,ObjectState!B state){
	auto duration=state.movingObjectById!((ref obj,state){
		playSpellSoundTypeAt(SoundType.slime,target,state,slimeGain);
		obj.animateSlimeTransition(state);
		obj.creatureStats.effects.numSlimes+=1;
		auto duration=(obj.isWizard?0.25f:1000.0f/obj.health)*spell.duration;
		return cast(int)ceil(updateFPS*duration);
	},()=>-1)(target,state);
	if(duration==-1) return false;
	state.addEffect(Slime!B(target,spell,duration));
	return true;
}

bool castGraspingVines(B)(int target,ManaDrain!B manaDrain,SacSpell!B spell,ObjectState!B state){
	if(!state.movingObjectById!((ref obj){
		if(obj.creatureStats.effects.ccProtected||!obj.creatureState.mode.canCC) return false;
		return true;
	},()=>false)(target)) return false;
	state.addEffect(GraspingVinesCasting!B(manaDrain,spell,target));
	return true;
}
Vine spawnVine(B)(Vector3f[2] hitbox,ObjectState!B state){
	float scale=boxSize(hitbox).length/2.0f;
	Vector3f[2] nhitbox=[Vector3f(hitbox[0].x,hitbox[0].y,0.5f*(hitbox[0].z+hitbox[1].z)),hitbox[1]];
	auto target=state.uniform(nhitbox);
	enum displacement=1.0f;
	auto base=target+state.uniform(0.0f,displacement)*Vector3f(state.uniform(-1.0f,1.0f),state.uniform(-1.0f,1.0f),0.0f);
	// TODO: snap base to ground
	base.z=state.getHeight(base);
	target.z=max(target.z,base.z+displacement);
	base.z-=0.1f*scale;
	auto result=Vine(base,target,scale);
	foreach(i,ref x;result.locations){
		result.locations[i]=base;
		//result.velocities[i]=Vector3f(0.0f,0.0f,0.0f);
		result.velocities[i]=state.uniformDirection()*scale;
		result.velocities[i].z=0.1f;
	}
	return result;
}
enum graspingVinesGain=4.0f;
bool graspingVines(B)(int target,SacSpell!B spell,ObjectState!B state){
	auto durationHitbox=state.movingObjectById!((ref obj,state){
		playSoundAt("toor",obj.position,state,graspingVinesGain);
		obj.creatureStats.effects.numVines+=1;
		obj.creatureState.targetFlyingHeight=max(0.0f,obj.position.z-state.getGroundHeight(obj.position));
		auto duration=(obj.isWizard?0.25f:1000.0f/obj.health)*spell.duration;
		return tuple(cast(int)ceil(updateFPS*duration), obj.hitbox);
	},()=>tuple(-1,(Vector3f[2]).init))(target,state);
	auto duration=durationHitbox[0],hitbox=durationHitbox[1];
	if(duration==-1) return false;
	Vine[GraspingVines!B.vines.length] vines;
	foreach(ref vine;vines) vine=spawnVine(hitbox,state);
	state.addEffect(GraspingVines!B(target,spell,duration,vines));
	return true;
}

bool castSoulMole(B)(int target,ManaDrain!B manaDrain,SacSpell!B spell,ObjectState!B state){
	auto soulPosition=state.soulById!((ref soul)=>soul.position,()=>Vector3f.init)(target);
	if(isNaN(soulPosition.x)) return false;
	auto position=state.movingObjectById!((ref obj)=>obj.position,()=>Vector3f.init)(manaDrain.wizard);
	if(isNaN(position.x)) return false;
	auto direction=cross(Vector3f(0.0f,0.0f,1.0f),soulPosition-position).normalized;
	auto targetVelocity=0.75f*(soulPosition-position).length*direction;
	//auto targetVelocity=Vector3f(0.0f,0.0f,0.0f);
	auto soulMole=SoulMole!B(target,manaDrain.wizard,spell,position,position,targetVelocity);
	state.addEffect(SoulMoleCasting!B(manaDrain,soulMole));
	return true;
}
bool soulMole(B)(SoulMole!B soulMole,ObjectState!B state){
	state.addEffect(soulMole);
	return true;
}

bool castRainbow(B)(int side,int creature,ManaDrain!B manaDrain,SacSpell!B spell,ObjectState!B state){
	if(!state.isValidTarget(creature,TargetType.creature)) return false;
	auto target=OrderTarget(TargetType.creature,creature,state.movingObjectById!(center,()=>Vector3f.init)(creature));
	if(isNaN(target.position.x)) return false;
	state.addEffect(RainbowCasting!B(side,target,manaDrain,spell));
	return true;
}
bool rainbow(B)(int side,OrderTarget origin,OrderTarget target,SacSpell!B spell,ObjectState!B state){
	state.addEffect(Rainbow!B(side,origin,target,spell));
	return true;
}

bool castChainLightning(B)(int side,int target,ManaDrain!B manaDrain,SacSpell!B spell,ObjectState!B state){
	if(!state.isValidTarget(target)) return false;
	auto orderTarget=state.objectById!((ref obj){
		playSpellSoundTypeAt(SoundType.lightning,obj.center,state,4.0f);
		enum type=is(typeof(obj)==MovingObject!B)?TargetType.creature:TargetType.building;
		return OrderTarget(type,obj.id,obj.center);
	})(target);
	state.addEffect(ChainLightningCasting!B(side,orderTarget,manaDrain,spell));
	return true;
}
bool chainLightning(B)(int wizard,int side,OrderTarget origin,OrderTarget target,SacSpell!B spell,ObjectState!B state){
	state.addEffect(ChainLightning!B(wizard,side,origin,target,spell));
	return true;
}

bool castAnimateDead(B)(int creature,ManaDrain!B manaDrain,SacSpell!B spell,ObjectState!B state){
	if(!animateDead(manaDrain.wizard,creature,spell,state))
		return false;
	state.addEffect(AnimateDeadCasting!B(manaDrain,spell));
	return true;
}
void animateAnimateDead(B)(ref MovingObject!B obj,SacSpell!B spell,ObjectState!B state){
	enum numParticles=128;
	auto sacParticle=SacParticle!B.get(ParticleType.castCharnel2);
	auto hitbox=obj.hitbox;
	auto center=boxCenter(hitbox);
	foreach(i;0..numParticles){
		auto position=state.uniform(scaleBox(hitbox,1.2f));
		auto velocity=Vector3f(position.x-center.x,position.y-center.y,0.0f).normalized;
		velocity.z=state.uniform(0.0f,2.0f);
		auto scale=2.0f;
		int lifetime=31;
		int frame=0;
		state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
	}

}
bool animateDead(B)(int wizard,int creature,SacSpell!B spell,ObjectState!B state){
	if(state.isValidTarget(creature,TargetType.soul)){
		auto creatureId=state.soulById!((ref soul)=>soul.creatureId,()=>0)(creature);
		if(creatureId) creature=creatureId;
		else return true;
	}
	if(!state.isValidTarget(creature,TargetType.creature)) return false;
	auto start=OrderTarget(TargetType.creature,wizard,Vector3f.init);
	start.updateAnimateDeadTarget(state);
	if(isNaN(start.position.x)) return false;
	auto end=OrderTarget(TargetType.creature,creature,Vector3f.init);
	end.updateAnimateDeadTarget(state);
	if(isNaN(end.position.x)) return false;
	auto reviveTime=state.movingObjectById!((ref obj,spell,state){
		obj.animateAnimateDead(spell,state);
		obj.revive(state);
		return cast(int)(obj.creatureStats.reviveTime*updateFPS);
	},()=>-1)(creature,spell,state);
	if(reviveTime==-1) return false;
	playSoundAt("0cas",creature,state,animateDeadGain);
	state.addEffect(AnimateDead!B(start,end,reviveTime));
	return true;
}

bool castErupt(B)(int side,Vector3f position,ManaDrain!B manaDrain,SacSpell!B spell,ObjectState!B state){
	state.addEffect(EruptCasting!B(manaDrain,Erupt!B(manaDrain.wizard,side,position,spell)));
	return true;
}
bool erupt(B)(Erupt!B erupt,ObjectState!B state){
	state.addEffect(erupt);
	return true;
}

bool castDragonfire(B)(int target,ManaDrain!B manaDrain,SacSpell!B spell,int castingTime,ObjectState!B state){
	if(!state.isValidTarget(target)) return false;
	auto positionDirectionSide=state.movingObjectById!((obj,spell,castingTime,state)=>tuple(obj.dragonfireCastingPosition(spell,0,castingTime,state).expand,obj.side),function Tuple!(Vector3f,Vector3f,int){ assert(0); })(manaDrain.wizard,spell,castingTime,state);
	auto position=positionDirectionSide[0],direction=positionDirectionSide[1],side=positionDirectionSide[2];
	auto dragonfire=Dragonfire!B(manaDrain.wizard,side,position,direction,centerTarget(target,state),spell);
	state.addEffect(DragonfireCasting!B(castingTime,manaDrain,dragonfire));
	return true;
}
bool dragonfire(B)(Dragonfire!B dragonfire,ObjectState!B state){
	dragonfire.addTarget(dragonfire.target.id);
	playSoundAt("2ifd",dragonfire.position,state,dragonfireGain); // TODO: move sound with spell?
	state.addEffect(dragonfire);
	return true;
}

bool castSoulWind(B)(int target,ManaDrain!B manaDrain,SacSpell!B spell,ObjectState!B state){
	auto soulPosition=state.soulById!((ref soul)=>soul.position,()=>Vector3f.init)(target);
	if(isNaN(soulPosition.x)) return false;
	auto position=state.movingObjectById!((ref obj)=>obj.position,()=>Vector3f.init)(manaDrain.wizard);
	if(isNaN(position.x)) return false;
	auto direction=cross(Vector3f(0.0f,0.0f,1.0f),soulPosition-position).normalized;
	auto targetVelocity=0.75f*(soulPosition-position).length*direction;
	//auto targetVelocity=Vector3f(0.0f,0.0f,0.0f);
	playSpellSoundTypeAt(SoundType.fireball,position,state,soulWindGain); // TODO: move sound with soul wind?
	auto soulWind=SoulWind!B(target,manaDrain.wizard,spell,position,position,targetVelocity);
	state.addEffect(SoulWindCasting!B(manaDrain,soulWind));
	return true;
}
bool soulWind(B)(SoulWind!B soulWind,ObjectState!B state){
	state.addEffect(soulWind);
	return true;
}

bool castExplosion(B)(int side,Vector3f position,ManaDrain!B manaDrain,SacSpell!B spell,int castingTime,ObjectState!B state){
	ExplosionEffect[5] effects;
	effects[0].position=position;
	playSoundAt("malf",position,state,4.0f);
	foreach(ref effect;effects[1..$]){
		auto offset=state.uniformDisk(Vector2f(0.0f,0.0f),spell.effectRange);
		effect.position=position+Vector3f(offset.x,offset.y,0.0f);
		effect.position.z=state.getHeight(effect.position);
	}
	state.addEffect(ExplosionCasting!B(side,manaDrain,spell,castingTime,effects));
	return true;
}
bool explosion(B)(int attacker,int side,ref ExplosionEffect[5] effects,SacSpell!B spell,ObjectState!B state){
	foreach(ref effect;effects){
		animateAsh(effect.position,state,150);
		animateDebris(effect.position,state,15);
		explosionAnimation(effect.position+Vector3f(0.0f,0.0f,effect.maxRadius),state,1.75f);
		animateFireballExplosion!10(effect.position,state,2.0f);
		static bool callback(int target,int attacker,int side,ObjectState!B state){
			setAblaze(target,updateFPS,false,0.0f,attacker,side,DamageMod.none,state);
			return true;
		}
		dealSplashSpellDamageAt!callback(0,spell,spell.damageRange,attacker,side,effect.position,DamageMod.ignite,state,attacker,side,state);
	}
	static bool catapultCallback(int id,ExplosionEffect[5]* effects,SacSpell!B spell,ObjectState!B state){
		state.movingObjectById!((ref obj,effects,state){
			float best=float.infinity;
			Vector3f position;
			foreach(i,ref effect;(*effects)[]){
				auto cand=(effect.position-obj.position).lengthsqr;
				if(cand>spell.damageRange^^2) continue;
				if(cand<best){
					best=cand;
					position=effect.position;
					if(i==0) break;
				}
			}
			if(best>spell.damageRange^^2) return;
			best=sqrt(best);
			auto direction=(obj.position-(position+Vector3f(0.0f,0.0f,-5.0f))).normalized;
			auto strength=min(20.0f,5.0f+17.5f*(1.0f-best/spell.damageRange));
			obj.catapult(direction*strength,state);
		},(){})(id,effects,state);
		return false;
	}
	dealDamageAt!catapultCallback(0,0.0f,spell.effectRange+spell.damageRange,attacker,side,effects[0].position,DamageMod.none,state,&effects,spell,state);
	return true;
}

bool castHaloOfEarth(B)(int wizard,int side,ManaDrain!B manaDrain,SacSpell!B spell,int castingTime,ObjectState!B state){
	auto haloOfEarth=HaloOfEarth!B(wizard,side,spell,false);
	state.addEffect(HaloOfEarthCasting!B(manaDrain,castingTime,haloOfEarth));
	return true;
}
bool haloOfEarth(B)(HaloOfEarth!B haloOfEarth,ObjectState!B state){
	state.addEffect(move(haloOfEarth));
	return true;
}

bool castRainOfFrogs(B)(int side,Vector3f position,ManaDrain!B manaDrain,SacSpell!B spell,ObjectState!B state){
	position.z=state.getHeight(position)+RainOfFrogs!B.cloudHeight;
	state.addEffect(RainOfFrogsCasting!B(manaDrain,RainOfFrogs!B(manaDrain.wizard,side,position,spell)));
	return true;
}
bool rainOfFrogs(B)(RainOfFrogs!B rainOfFrogs,ObjectState!B state){
	state.addEffect(rainOfFrogs);
	return true;
}

bool castDemonicRift(B)(int side,Vector3f position,OrderTarget target,ManaDrain!B manaDrain,SacSpell!B spell,ObjectState!B state){
	position.z=state.getHeight(position);
	state.addEffect(DemonicRiftCasting!B(manaDrain,DemonicRift!B(manaDrain.wizard,side,position,target,spell)));
	return true;
}
bool demonicRift(B)(DemonicRift!B demonicRift,ObjectState!B state){
	state.addEffect(demonicRift);
	return true;
}

Vector3f getShotDirection(B)(float accuracy,Vector3f position,Vector3f target,SacSpell!B rangedAttack,ObjectState!B state){
	auto φ=2.0f*pi!float*accuracy*state.normal(); // TODO: ok?
	return rotate(facingQuaternion(φ),(target-position+Vector3f(0.0f,0.0f,5.0f*accuracy*state.normal())).normalized); // TODO: ok?
}

Vector3f getShotDirectionWithGravity(B)(float accuracy,Vector3f position,Vector3f target,SacSpell!B rangedAttack,ObjectState!B state){
	auto direction=getShotDirection(accuracy,position,target,rangedAttack,state);
	direction.z+=0.5f*rangedAttack.fallingAcceleration*(target-position).length/rangedAttack.speed^^2;
	return direction;
}

bool brainiacShoot(B)(int attacker,int side,int intendedTarget,float accuracy,Vector3f position,Vector3f target,SacSpell!B rangedAttack,ObjectState!B state){
	playSoundAt("snrb",position,state,4.0f); // TODO: move sound with projectile
	auto direction=getShotDirection(accuracy,position,target,rangedAttack,state);
	state.addEffect(BrainiacProjectile!B(attacker,side,intendedTarget,position,direction,rangedAttack,rangedAttack.range));
	return true;
}

bool shrikeShoot(B)(int attacker,int side,int intendedTarget,float accuracy,Vector3f position,Vector3f target,SacSpell!B rangedAttack,ObjectState!B state){
	playSoundAt("krhs",position,state,4.0f); // TODO: move sound with projectile
	auto direction=getShotDirection(accuracy,position,target,rangedAttack,state);
	state.addEffect(ShrikeProjectile!B(attacker,side,intendedTarget,position,direction,rangedAttack,rangedAttack.range));
	return true;
}

bool locustShoot(B)(int attacker,int side,int intendedTarget,float accuracy,Vector3f position,Vector3f target,SacSpell!B rangedAttack,ObjectState!B state){
	playSoundAt("tscl",position,state,4.0f);
	auto direction=getShotDirection(accuracy,position,target,rangedAttack,state);
	static bool filter(ref ProximityEntry entry,int id){ return entry.id!=id; }
	auto end=state.collideRay!filter(position,direction,rangedAttack.range,attacker);
	if(end.type==TargetType.none) end.position=position+0.5f*rangedAttack.range*direction;
	else end.position=end.lowCenter(state);
	if(end.type==TargetType.creature||end.type==TargetType.building)
		dealRangedDamage(end.id,rangedAttack,attacker,side,direction,DamageMod.none,state);
	state.addEffect(LocustProjectile!B(rangedAttack,end.position,position,end.type==TargetType.creature));
	return true;
}

bool spitfireShoot(B)(int attacker,int side,int intendedTarget,float accuracy,Vector3f position,Vector3f target,SacSpell!B rangedAttack,ObjectState!B state){
	playSoundAt("6abf",position,state,4.0f);
	auto direction=getShotDirection(accuracy,position,target,rangedAttack,state);
	state.addEffect(SpitfireProjectile!B(attacker,side,intendedTarget,position,direction,rangedAttack,rangedAttack.range));
	return true;
}

bool gargoyleShoot(B)(int attacker,int side,int intendedTarget,float accuracy,Vector3f position,Vector3f target,SacSpell!B rangedAttack,ObjectState!B state){
	playSoundAt("4tps",position,state,2.0f);
	playSoundAt("2tlp",position,state,2.0f); // TODO: move with projectile?
	auto direction=getShotDirection(accuracy,position,target,rangedAttack,state);
	state.addEffect(GargoyleProjectile!B(attacker,side,intendedTarget,position,direction,rangedAttack,rangedAttack.range));
	return true;
}

bool earthflingShoot(B)(int attacker,int side,int intendedTarget,float accuracy,Vector3f position,Vector3f target,SacSpell!B rangedAttack,ObjectState!B state){
	playSoundAt("4tps",position,state,4.0f);
	auto direction=getShotDirectionWithGravity(accuracy,position,target,rangedAttack,state);
	auto rotationSpeed=2*pi!float*state.uniform(0.2f,0.8f)/updateFPS;
	auto rotationAxis=state.uniformDirection();
	auto rotationUpdate=rotationQuaternion(rotationAxis,rotationSpeed);
	state.addEffect(EarthflingProjectile!B(attacker,side,intendedTarget,position,direction*rangedAttack.speed,rangedAttack,rotationUpdate,Quaternionf.identity()));
	return true;
}

bool flameMinionShoot(B)(int attacker,int side,int intendedTarget,float accuracy,Vector3f position,Vector3f target,SacSpell!B rangedAttack,ObjectState!B state){
	playSpellSoundTypeAt(SoundType.fireball,position,state,4.0f); // TODO: move with projectile
	auto direction=getShotDirectionWithGravity(accuracy,position,target,rangedAttack,state);
	state.addEffect(FlameMinionProjectile!B(attacker,side,intendedTarget,position,direction*rangedAttack.speed,rangedAttack));
	return true;
}

bool fallenShoot(B)(int attacker,int side,int intendedTarget,float accuracy,Vector3f position,Vector3f target,SacSpell!B rangedAttack,ObjectState!B state){
	playSoundAt("htim",position,state,2.0f); // TODO: move with projectile
	auto direction=getShotDirectionWithGravity(accuracy,position,target,rangedAttack,state);
	auto projectile=FallenProjectile!B(attacker,side,intendedTarget,position,direction*rangedAttack.speed,rangedAttack,0,SwarmStatus.flying);
	projectile.addBugs(state);
	state.addEffect(move(projectile));
	return true;
}

void sylphLoad(B)(int attacker,ObjectState!B state){
	state.addEffect(SylphEffect!B(attacker));
}
bool sylphShoot(B)(int attacker,int side,int intendedTarget,float accuracy,Vector3f position,Vector3f target,SacSpell!B rangedAttack,ObjectState!B state){
	playSpellSoundTypeAt(SoundType.bow,position,state,2.0f);
	auto direction=getShotDirectionWithGravity(accuracy,position,target,rangedAttack,state);
	state.addEffect(SylphProjectile!B(attacker,side,intendedTarget,position,direction*rangedAttack.speed,rangedAttack));
	return true;
}

void rangerLoad(B)(int attacker,ObjectState!B state){
	state.addEffect(RangerEffect!B(attacker));
}
bool rangerShoot(B)(int attacker,int side,int intendedTarget,float accuracy,Vector3f position,Vector3f target,SacSpell!B rangedAttack,ObjectState!B state){
	playSpellSoundTypeAt(SoundType.bow,position,state,2.0f);
	auto direction=getShotDirectionWithGravity(accuracy,position,target,rangedAttack,state);
	state.addEffect(RangerProjectile!B(attacker,side,intendedTarget,position,direction*rangedAttack.speed,rangedAttack));
	return true;
}

bool necrylShoot(B)(int attacker,int side,int intendedTarget,float accuracy,Vector3f position,Vector3f target,SacSpell!B rangedAttack,ObjectState!B state){
	playSoundAt("nlws",position,state,4.0f); // TODO: move sound with projectile
	auto direction=getShotDirection(accuracy,position,target,rangedAttack,state);
	state.addEffect(NecrylProjectile!B(attacker,side,intendedTarget,position,direction,rangedAttack,rangedAttack.range));
	return true;
}

bool poison(B)(ref MovingObject!B obj,float poisonDamage,int lifetime,bool infectuous,int attacker,int attackerSide,DamageMod damageMod,ObjectState!B state){
	obj.creatureStats.effects.poisonDamage+=cast(int)poisonDamage;
	state.addEffect(Poison(obj.id,poisonDamage,lifetime,infectuous,attacker,attackerSide,damageMod));
	return true;
}

bool poison(B)(ref MovingObject!B obj,SacSpell!B rangedAttack,bool infectuous,int attacker,int attackerSide,DamageMod damageMod,ObjectState!B state){
	return poison(obj,rangedAttack.amount/rangedAttack.duration,cast(int)(rangedAttack.duration*updateFPS),infectuous,attacker,attackerSide,damageMod,state);
}

bool scarabShoot(B)(int attacker,int side,int intendedTarget,float accuracy,Vector3f position,Vector3f target,SacSpell!B rangedAttack,ObjectState!B state){
	playSoundAt("srcs",position,state,4.0f); // TODO: move sound with projectile
	auto direction=getShotDirection(accuracy,position,target,rangedAttack,state);
	state.addEffect(ScarabProjectile!B(attacker,side,intendedTarget,position,direction,rangedAttack,rangedAttack.range));
	return true;
}

bool basiliskShoot(B)(int attacker,int side,int intendedTarget,float accuracy,Vector3f[2] positions,Vector3f target,SacSpell!B rangedAttack,ObjectState!B state){
	auto center=boxCenter(positions);
	playSoundAt("ssab",center,state,4.0f); // TODO: move sound with projectile?
	auto direction=getShotDirection(accuracy,positions[1],target,rangedAttack,state);
	state.addEffect(BasiliskProjectile!B(attacker,side,intendedTarget,positions,direction,rangedAttack,rangedAttack.range));
	return true;
}

bool petrify(B)(ref MovingObject!B obj,int lifetime,Vector3f attackDirection,ObjectState!B state){
	if(obj.creatureStats.effects.ccProtected) return false;
	assert(!obj.creatureStats.effects.petrified);
	obj.creatureStats.effects.petrified=true;
	obj.creatureState.mode=CreatureMode.stunned;
	obj.startTumbling(state);
	state.addEffect(Petrification(obj.id,lifetime,attackDirection));
	return true;
}

bool petrify(B)(ref MovingObject!B obj,SacSpell!B rangedAttack,Vector3f attackDirection,ObjectState!B state){
	auto duration=obj.isWizard?2.5f:min(10.0f,10000.0f/obj.creatureStats.maxHealth);
	auto lifetime=cast(int)(duration*updateFPS);
	return petrify(obj,lifetime,attackDirection,state);
}

bool tickfernoShoot(B)(int attacker,int side,int intendedTarget,float accuracy,Vector3f position,Vector3f target,SacSpell!B rangedAttack,ObjectState!B state){
	playSpellSoundTypeAt(SoundType.laser,position,state,4.0f);
	auto direction=getShotDirection(accuracy,position,target,rangedAttack,state);
	state.addEffect(TickfernoProjectile!B(attacker,side,intendedTarget,position,direction,rangedAttack,rangedAttack.range,position));
	return true;
}

bool vortickShoot(B)(int attacker,int side,int intendedTarget,float accuracy,Vector3f position,Vector3f target,SacSpell!B rangedAttack,ObjectState!B state){
	playSoundAt("2xtv",position,state,4.0f);
	auto direction=getShotDirection(accuracy,position,target,rangedAttack,state);
	state.addEffect(VortickProjectile!B(attacker,side,intendedTarget,position,direction,rangedAttack,rangedAttack.range));
	return true;
}

enum vortexGain=4.0f;
bool spawnVortex(B)(Vector3f position,SacSpell!B rangedAttack,ObjectState!B state){
	playSoundAt("gxtv",position,state,vortexGain);
	state.addEffect(VortexEffect!B(position,rangedAttack));
	return true;
}

enum pushbackGain=4.0f;
bool squallShoot(B)(int attacker,int side,int intendedTarget,float accuracy,Vector3f position,Vector3f target,SacSpell!B rangedAttack,ObjectState!B state){
	playSoundAt("slqs",position,state,4.0f);
	auto direction=getShotDirection(accuracy,position,target,rangedAttack,state);
	state.addEffect(SquallProjectile!B(attacker,side,intendedTarget,position,direction,rangedAttack,rangedAttack.range));
	return true;
}

bool pushback(B)(int creature, Vector3f direction,SacSpell!B rangedAttack,ObjectState!B state){
	if(!state.isValidTarget(creature,TargetType.creature)) return false;
	state.addEffect(Pushback!B(creature,direction,rangedAttack));
	return true;
}

void flummoxLoad(B)(int attacker,ObjectState!B state){
	playSoundAt("walc",attacker,state,2.0f);
}
bool flummoxShoot(B)(int attacker,int side,int intendedTarget,float accuracy,Vector3f position,Vector3f target,SacSpell!B rangedAttack,ObjectState!B state){
	playSoundAt("3tps",position,state,4.0f);
	auto direction=getShotDirectionWithGravity(accuracy,position,target,rangedAttack,state);
	auto rotationSpeed=2*pi!float*state.uniform(0.05f,0.2f)/updateFPS;
	auto rotationAxis=state.uniformDirection();
	auto rotationUpdate=rotationQuaternion(rotationAxis,rotationSpeed);
	state.addEffect(FlummoxProjectile!B(attacker,side,intendedTarget,position,direction*rangedAttack.speed,rangedAttack,rotationUpdate,Quaternionf.identity()));
	return true;
}

bool pyromaniacShoot(B)(int attacker,int side,int intendedTarget,float accuracy,Vector3f position,Vector3f target,SacSpell!B rangedAttack,ObjectState!B state){
	playSoundAt("5abf",position,state,2.0f);
	auto direction=getShotDirection(accuracy,position,target,rangedAttack,state);
	state.addEffect(PyromaniacRocket!B(attacker,side,intendedTarget,position,direction,rangedAttack,rangedAttack.range));
	return true;
}

void animateGnomeShot(B)(Vector3f position,Vector3f direction,SacSpell!B rangedAttack,ObjectState!B state){
	state.addEffect(GnomeEffect!B(position,direction,rangedAttack));
}
void animateGnomeHit(B)(Vector3f position,SacSpell!B rangedAttack,ObjectState!B state){
	playSoundAt("tihg",position,state,0.5f);
	enum numParticles3=200;
	auto sacParticle3=SacParticle!B.get(ParticleType.gnomeHit);
	foreach(i;0..numParticles3){
		auto direction=state.uniformDirection();
		auto velocity=state.uniform(2.0f,8.0f)*direction;
		auto scale=state.uniform(1.0f,2.5f);
		auto lifetime=63;
		auto frame=0;
		state.addParticle(Particle!B(sacParticle3,position,velocity,scale,lifetime,frame));
	}
}

bool gnomeShoot(B)(int attacker,int side,int intendedTarget,float accuracy,Vector3f position,Vector3f target,SacSpell!B rangedAttack,ObjectState!B state){
	playSoundAt("thsg",position,state,2.0f);
	auto direction=getShotDirection(accuracy,position,target,rangedAttack,state);
	static bool filter(ref ProximityEntry entry,int id){ return entry.id!=id; }
	auto end=state.collideRay!filter(position,direction,rangedAttack.range,attacker);
	if(end.type==TargetType.none) end.position=position+0.5f*rangedAttack.range*direction;
	if(end.type==TargetType.creature||end.type==TargetType.building)
		dealRangedDamage(end.id,rangedAttack,attacker,side,direction,DamageMod.none,state);
	animateGnomeShot(position,direction,rangedAttack,state);
	animateGnomeHit(end.position,rangedAttack,state);
	return true;
}

bool deadeyeShoot(B)(int attacker,int side,int intendedTarget,float accuracy,Vector3f position,Vector3f target,SacSpell!B rangedAttack,ObjectState!B state){
	playSoundAt("hsed",position,state,2.0f);
	auto direction=getShotDirection(accuracy,position,target,rangedAttack,state);
	state.addEffect(PoisonDart!B(attacker,side,intendedTarget,position,direction,rangedAttack,rangedAttack.range));
	return true;
}

enum mutantShootGain=4.0f;
void mutantLoad(B)(int attacker,ObjectState!B state){
	playSpellSoundTypeAt(SoundType.gut,attacker,state,mutantShootGain);
}
bool mutantShoot(B)(int attacker,int side,int intendedTarget,float accuracy,Vector3f position,Vector3f target,SacSpell!B rangedAttack,ObjectState!B state){
	playSpellSoundTypeAt(SoundType.mutant,position,state,mutantShootGain); // TODO: move sound with projectile
	auto direction=getShotDirectionWithGravity(accuracy,position,target,rangedAttack,state);
	state.addEffect(MutantProjectile!B(attacker,side,intendedTarget,position,direction*rangedAttack.speed,rangedAttack));
	return true;
}

enum defaultFaceThreshold=1e-3;
bool face(B)(ref MovingObject!B object,float facing,ObjectState!B state,float threshold=defaultFaceThreshold){
	auto angle=facing-object.creatureState.facing;
	while(angle<-pi!float) angle+=2*pi!float;
	while(angle>pi!float) angle-=2*pi!float;
	object.creatureState.rotationSpeedLimit=rotationSpeedLimitFactor*abs(angle);
	if(angle>threshold) object.startTurningLeft(state);
	else if(angle<-threshold) object.startTurningRight(state);
	else{
		object.stopTurning(state);
		return false;
	}
	return true;
}

float facingTowards(B)(ref MovingObject!B object,Vector3f position,ObjectState!B state){
	auto direction=position.xy-object.position.xy;
	auto result=atan2(-direction.x,direction.y);
	if(isNaN(result)) return 0.0f;
	return result;
}

bool turnToFaceTowards(B)(ref MovingObject!B object,Vector3f position,ObjectState!B state,float threshold=defaultFaceThreshold){
	return object.face(object.facingTowards(position,state),state,threshold);
}

void setPitching(B)(ref MovingObject!B object,PitchingDirection direction,ObjectState!B state,int side=-1){
	if(!object.canOrder(side,state)) return;
	if(!object.sacObject.canFly||object.creatureState.movement!=CreatureMovement.flying) return;
	object.creatureState.pitchingDirection=direction;
	if(direction==PitchingDirection.none) object.creatureState.pitchingSpeedLimit=float.infinity;
}
void stopPitching(B)(ref MovingObject!B object,ObjectState!B state,int side=-1){
	object.setPitching(PitchingDirection.none,state,side);
}
void startPitchingUp(B)(ref MovingObject!B object,ObjectState!B state,int side=-1){
	object.setPitching(PitchingDirection.up,state,side);
}
void startPitchingDown(B)(ref MovingObject!B object,ObjectState!B state,int side=-1){
	object.setPitching(PitchingDirection.down,state,side);
}

bool pitch(B)(ref MovingObject!B object,float pitch_,ObjectState!B state){
	auto angle=pitch_-object.creatureState.flyingPitch;
	while(angle<-pi!float) angle+=2*pi!float;
	while(angle>pi!float) angle-=2*pi!float;
	enum threshold=1e-3;
	object.creatureState.pitchingSpeedLimit=rotationSpeedLimitFactor*abs(angle);
	if(angle>threshold) object.startPitchingUp(state);
	else if(angle<-threshold) object.startPitchingDown(state);
	else{
		object.stopPitching(state);
		return false;
	}
	return true;
}

bool pitchToFaceTowards(B)(ref MovingObject!B object,Vector3f position,ObjectState!B state){
	auto direction=position-object.position;
	if(object.creatureState.targetFlyingHeight!is float.nan)
		direction.z+=object.creatureState.targetFlyingHeight;
	auto distance=direction.xy.length;
	auto pitch_=atan2(direction.z,distance);
	if(isNaN(pitch_)) pitch_=0.0f;
	return object.pitch(pitch_,state);
}

bool movingForwardGetsCloserTo(B)(ref MovingObject!B object,Vector3f position,float speed,float acceleration,ObjectState!B state){
	auto direction=position.xy-object.position.xy;
	auto facing=object.creatureState.facing;
	auto rotationSpeed=object.creatureStats.rotationSpeed(object.creatureState.movement==CreatureMovement.flying);
	auto forward=Vector2f(-sin(facing),cos(facing));
	auto angle=atan2(-direction.x,direction.y);
	if(isNaN(angle)) return false;
	angle-=object.creatureState.facing;
	while(angle<-pi!float) angle+=2*pi!float;
	while(angle>pi!float) angle-=2*pi!float;
	if(dot(direction,forward)<0.0f) return false;
	auto travelDist=0.5f*speed*speed/acceleration;
	auto r=speed/rotationSpeed,distsqr=direction.lengthsqr;
	auto θ=travelDist/r;
	travelDist=2.0f*r*sin(0.5f*θ);
	if(travelDist*travelDist>distsqr) return false;
	if(distsqr>=2.2f*r^^2) return true;
	if(abs(angle)<acos(1.0f-distsqr/(2.2f*r^^2))) return true;
	auto limit=rotationSpeedLimitFactor*abs(angle);
	return limit<1e-3;
}

bool order(B)(ref MovingObject!B object,Order order,ObjectState!B state,int side=-1){
	if(!object.canOrder(side,state)) return false;
	if(object.isPacifist(state)&&order.command.among(CommandType.attack,CommandType.advance)) return false;
	Order previousOrder;
	if(object.creatureState.mode==CreatureMode.usingAbility) // TODO: handle shooting the same way?
		previousOrder=object.creatureAI.order;
	object.clearOrderQueue(state);
	object.creatureAI.order=order;
	if(previousOrder.command!=CommandType.none){
		if(object.hasOrders(state)) object.creatureAI.orderQueue.pushFront(object.creatureAI.order);
		object.prequeueOrder(previousOrder,state);
	}
	return true;
}

bool queueOrder(B)(ref MovingObject!B object,Order order,ObjectState!B state,int side=-1){
	if(object.creatureAI.order.command==CommandType.none) return .order(object,order,state,side);
	if(!object.canOrder(side,state)) return false;
	object.creatureAI.orderQueue.push(order);
	return true;
}

bool prequeueOrder(B)(ref MovingObject!B object,Order order,ObjectState!B state,int side=-1){
	if(object.creatureAI.order.command==CommandType.none) return .order(object,order,state,side);
	if(!object.canOrder(side,state)) return false;
	if(object.creatureState.mode==CreatureMode.usingAbility && object.creatureAI.order.command==CommandType.useAbility){ // TODO: handle shooting the same way?
		if(!object.creatureAI.orderQueue.empty && object.creatureAI.orderQueue.front.command==CommandType.useAbility)
			object.creatureAI.orderQueue.front=order; // only one ability command can be queued at start
		else object.creatureAI.orderQueue.pushFront(order);
	}else{
		if(object.hasOrders(state)){
			if(!(order.command==CommandType.useAbility&&object.creatureAI.order.command==CommandType.useAbility)) // only one ability command can be queued at start
				object.creatureAI.orderQueue.pushFront(object.creatureAI.order);
		}
		object.creatureAI.order=order;
	}
	return true;
}

bool order(B)(ref MovingObject!B object,Order order,CommandQueueing queueing,ObjectState!B state,int side=-1){
	final switch(queueing) with(CommandQueueing){
		case none: return .order(object,order,state,side);
		case post: return queueOrder(object,order,state,side);
		case pre: return prequeueOrder(object,order,state,side);
	}
}

void stop(B)(ref MovingObject!B object,ObjectState!B state){
	if(object.creatureState.movementDirection==MovementDirection.none&&
	   object.creatureState.rotationDirection==RotationDirection.none&&
	   object.creatureState.pitchingDirection==PitchingDirection.none)
		return;
	object.stopMovement(state);
	object.stopTurning(state);
	object.stopPitching(state);
}

void clearOrder(B)(ref MovingObject!B object,ObjectState!B state){
	if(object.creatureState.mode==CreatureMode.usingAbility) return; // TODO: handle shooting the same way?
	object.stop(state);
	if(!object.creatureAI.orderQueue.empty){
		object.creatureAI.order=object.creatureAI.orderQueue.front;
		object.creatureAI.orderQueue.popFront();
	}else object.creatureAI.order=Order.init;
}

void clearOrderQueue(B)(ref MovingObject!B object,ObjectState!B state){
	object.creatureAI.orderQueue.clear();
	object.clearOrder(state);
}

bool hasOrders(B)(ref MovingObject!B object,ObjectState!B state){
	return object.creatureAI.order.command!=CommandType.none;
}

bool hasQueuedOrders(B)(ref MovingObject!B object,ObjectState!B state){
	return !object.creatureAI.orderQueue.empty;
}

void unqueueOrder(B)(ref MovingObject!B object,ObjectState!B state){
	if(!hasQueuedOrders(object,state)) return;
	if(object.creatureAI.orderQueue.front.command==CommandType.useAbility){
		object.stop(state);
		swap(object.creatureAI.order,object.creatureAI.orderQueue.front);
		return;
	}
	clearOrder(object,state);
}


bool turnToFaceTowardsEvading(B)(ref MovingObject!B object,Vector3f targetPosition,out bool evading,ObjectState!B state,float threshold=defaultFaceThreshold,bool aggressive=false,int targetId=0){
	auto hitbox=object.hitbox;
	auto rotation=facingQuaternion(object.creatureState.facing);
	auto distance=0.05f*((hitbox[1].x-hitbox[0].x)+(hitbox[1].y-hitbox[0].y)); // TODO: improve
	auto frontHitbox=moveBox(hitbox,rotate(rotation,distance*Vector3f(0.0f,1.0f,0.0f)));
	auto frontObstacleFrontObstacleHitbox=collisionTargetWithHitbox(object.id,hitbox,frontHitbox,state);
	auto frontObstacle=frontObstacleFrontObstacleHitbox[0];
	--object.creatureAI.evasionTimer;
	bool doNotEvade(int obstacle){
		if(obstacle==targetId) return true;
		if(!aggressive) return false;
		return state.objectById!isValidEnemyAttackTarget(obstacle,object.side,state);
	}
	if(frontObstacle&&!doNotEvade(frontObstacle)){
		auto frontObstacleHitbox=frontObstacleFrontObstacleHitbox[1];
		Vector2f[2] frontObstacleHitbox2d=[frontObstacleHitbox[0].xy,frontObstacleHitbox[1].xy];
		auto frontObstacleDirection=-closestBoxFaceNormal(frontObstacleHitbox2d,object.position.xy);
		auto facing=object.creatureState.facing;
		auto evasion=object.creatureAI.evasion;
		if(object.creatureAI.evasionTimer<=0){
			evasion=RotationDirection.none;
			if(state.isValidTarget(frontObstacle,TargetType.creature)){
				static RotationDirection adaptiveEvasion(ref MovingObject!B obj,ObjectState!B state){
					return obj.creatureAI.evasion!=RotationDirection.none?state.uniform(2)?RotationDirection.right:RotationDirection.left:RotationDirection.none; // TODO: ok?
				}
				evasion=object.creatureAI.evasion=state.movingObjectById!(adaptiveEvasion,()=>RotationDirection.none)(frontObstacle,state);
			}
			if(evasion==RotationDirection.none)
				evasion=object.creatureAI.evasion=dot(Vector2f(cos(facing),sin(facing)),frontObstacleDirection)<=0.0f?RotationDirection.right:RotationDirection.left;
			object.creatureAI.evasionTimer=updateFPS;
		}
		object.setTurning(evasion,state);
		object.startMovingForward(state);
		evading=true;
		return true;
	}
	auto result=object.turnToFaceTowards(targetPosition,state,threshold);
	auto rotationDirection=object.creatureState.rotationDirection;
	if(rotationDirection!=RotationDirection.none){
		enum sideHitboxFactor=1.1f;
		auto sideOffsetX=rotationDirection==RotationDirection.right?1.0f:-1.0f;
		auto sideHitbox=moveBox(scaleBox(hitbox,sideHitboxFactor),rotate(rotation,distance*Vector3f(sideOffsetX,0.0f,0.0f)));
		auto sideObstacle=collisionTarget(object.id,hitbox,sideHitbox,state);
		if(sideObstacle&&!doNotEvade(sideObstacle)){
			object.stopTurning(state);
			object.startMovingForward(state);
			evading=true;
			return true;
		}
	}
	return result;
}

bool stop(B)(ref MovingObject!B object,float targetFacing,ObjectState!B state,float threshold=defaultFaceThreshold){
	object.stopMovement(state);
	auto facingFinished=targetFacing is float.init||!object.face(targetFacing,state,threshold);
	if(facingFinished) object.stopTurning(state);
	auto pitchingFinished=true;
	if(object.creatureState.movement==CreatureMovement.flying){
		pitchingFinished=!object.pitch(0.0f,state);
		object.creatureState.targetFlyingHeight=0.0f;
	}
	return !(facingFinished && pitchingFinished);
}

bool stopAndFaceTowards(B)(ref MovingObject!B object,Vector3f position,ObjectState!B state){
	return object.stop(object.facingTowards(position,state),state);
}

void moveTowards(B)(ref MovingObject!B object,Vector3f ultimateTargetPosition,float acceptableRadius,ObjectState!B state,bool evade=true,bool maintainHeight=false,bool stayAboveGround=true,int targetId=0,bool disablePathfinding=false){
	auto distancesqr=(object.position.xy-ultimateTargetPosition.xy).lengthsqr;
	auto isFlying=object.creatureState.movement==CreatureMovement.flying;
	Vector3f targetPosition=ultimateTargetPosition;
	if(isFlying||disablePathfinding) object.creatureAI.path.reset();
	else targetPosition=object.creatureAI.path.nextTarget(object.position,object.relativeHitbox,ultimateTargetPosition,acceptableRadius,state.frontOfAIQueue(object.side,object.id),state);
	if(isFlying){
		if(distancesqr>(0.1f*object.speed(state))^^2){
			auto flyingHeight=object.position.z-state.getHeight(object.position);
			auto minimumFlyingHeight=stayAboveGround?object.creatureStats.flyingHeight:0.0f;
			if(flyingHeight<minimumFlyingHeight) object.creatureState.targetFlyingHeight=minimumFlyingHeight;
			else object.creatureState.targetFlyingHeight=float.nan;
			auto pitchingTarget=maintainHeight?
				targetPosition+Vector3f(0.0f,0.0f,min(flyingHeight,minimumFlyingHeight)):
				targetPosition;
			if(object.creatureAI.isColliding) object.startPitchingUp(state);
			else object.pitchToFaceTowards(pitchingTarget,state);
		}else{
			object.pitch(0.0f,state);
			object.creatureState.targetFlyingHeight=0.0f;
		}
	}else if(object.creatureState.mode!=CreatureMode.takeoff&&object.sacObject.canFly){
		auto distance=sqrt(distancesqr);
		auto walkingSpeed=object.speedOnGround(state),flyingSpeed=object.speedInAir(state);
		if(object.takeoffTime(state)+distance/flyingSpeed<distance/walkingSpeed)
			object.startFlying(state);
	}
	if(evade){
		bool evading;
		object.turnToFaceTowardsEvading(targetPosition,evading,state,defaultFaceThreshold,targetId!=0,targetId);
		if(evading) return;
	}else object.turnToFaceTowards(targetPosition,state);
	if(object.movingForwardGetsCloserTo(targetPosition,object.creatureState.speed,object.creatureStats.movementAcceleration(isFlying),state)){
		object.startMovingForward(state);
	}else object.stopMovement(state);
}

bool moveTo(B)(ref MovingObject!B object,Vector3f targetPosition,float targetFacing,ObjectState!B state,bool evade=true,bool maintainHeight=false,bool stayAboveGround=true,int targetId=0,bool disablePathfinding=false){
	auto speed=object.speed(state)/updateFPS;
	auto distancesqr=(object.position.xy-targetPosition.xy).lengthsqr;
	if(distancesqr>(2.0f*speed)^^2){
		object.moveTowards(targetPosition,0.0f,state,evade,maintainHeight,stayAboveGround,targetId,disablePathfinding);
		return true;
	}
	return object.stop(targetFacing,state);
}

bool moveWithinRange(B)(ref MovingObject!B object,Vector3f targetPosition,float range,ObjectState!B state,bool evade=true,bool maintainHeight=false,bool stayAboveGround=true,int targetId=0,bool disablePathfinding=false){
	auto speed=object.speed(state)/updateFPS;
	auto distancesqr=(object.position-targetPosition).lengthsqr;
	if(distancesqr<=range^^2)
		return false;
	object.moveTowards(targetPosition,range,state,evade,maintainHeight,stayAboveGround,targetId,disablePathfinding);
	return true;
}

bool moveWithinRange2D(B)(ref MovingObject!B object,Vector3f targetPosition,float range,ObjectState!B state,bool evade=true,bool maintainHeight=false,bool stayAboveGround=true,int targetId=0,bool disablePathfinding=false){
	auto speed=object.speed(state)/updateFPS;
	auto distancesqr=(object.position.xy-targetPosition.xy).lengthsqr;
	if(distancesqr<=(range-speed)^^2)
		return false;
	object.moveTowards(targetPosition,range,state,evade,maintainHeight,stayAboveGround,targetId,disablePathfinding);
	return true;
}

bool retreatTowards(B)(ref MovingObject!B object,Vector3f targetPosition,ObjectState!B state){
	return object.patrolAround(targetPosition,state) ||
		object.moveWithinRange(targetPosition,retreatDistance,state) ||
		object.stop(float.init,state);
}

bool isValidAttackTarget(B,T)(ref T obj,ObjectState!B state)if(is(T==MovingObject!B)||is(T==StaticObject!B)){
	// this needs to be kept in synch with addToProximity
	static if(is(T==MovingObject!B)){
		if(!obj.creatureState.mode.isValidAttackTarget) return false;
		if(obj.creatureStats.effects.stealth) return false;
	}
	return obj.health(state)!=0.0f;
}
bool isValidAttackTarget(B)(int targetId,ObjectState!B state){
	with(TargetType) return state.targetTypeFromId(targetId).among(creature,building)&&state.objectById!(.isValidAttackTarget)(targetId,state);
}
bool isValidEnemyAttackTarget(B,T)(ref T obj,int side,ObjectState!B state)if(is(T==MovingObject!B)||is(T==StaticObject!B)){
	if(!obj.isValidAttackTarget(state)) return false;
	return state.sides.getStance(side,.side(obj,state))==Stance.enemy;
}
bool isValidEnemyAttackTarget(B)(int targetId,int side,ObjectState!B state){
	return state.isValidTarget(targetId)&&state.objectById!(.isValidEnemyAttackTarget)(targetId,side,state);
}
bool isValidGuardTarget(B,T)(T obj,ObjectState!B state)if(is(T==MovingObject!B)||is(T==StaticObject!B)){
	static if(is(T==MovingObject!B)){
		return obj.creatureState.mode.isValidGuardTarget;
	}else return true;
}
bool isValidGuardTarget(B)(int targetId,ObjectState!B state){
	return state.isValidTarget(targetId)&&state.objectById!(.isValidGuardTarget)(targetId,state);
}

bool hasClearShot(B)(ref MovingObject!B object,bool isAbility,Vector3f targetPosition,OrderTarget target,ObjectState!B state){
	// TODO: use hasHitboxLineOfSightTo for this, with projectile hitbox
	auto offset=target.type==TargetType.terrain?Vector3f(0.0f,0.0f,0.2f):Vector3f(0.0f,0.0f,-0.2f);
	return state.hasLineOfSightTo(object.firstShotPosition(isAbility)+offset,targetPosition+offset,object.id,target.id);
	/+auto adjustedTarget=targetPosition;
	adjustedTarget.z=targetPosition.z-4.0f;
	if(state.isOnGround(adjustedTarget)) adjustedTarget.z=max(adjustedTarget.z,state.getGroundHeight(adjustedTarget)+0.2f);
	return state.hasLineOfSightTo(object.firstShotPosition(isAbility),targetPosition,object.id,target.id)&&
		state.hasLineOfSightTo(object.firstShotPosition(isAbility),adjustedTarget,object.id,target.id);+/
}
float shootRange(B)(ref MovingObject!B object,ObjectState!B state){
	if(auto ra=object.rangedAttack) return 0.8f*ra.range;
	return 0.0f;
}
float useAbilityDistance(B)(ref MovingObject!B object,ObjectState!B state){
	if(auto ab=object.ability){
		if(ab.tag==SpellTag.devour) return boxSize(object.hitbox).length;
		return ab.range;
	}
	return 0.0f;
}

Vector3f getShotTargetPosition(B)(ref MovingObject!B object,OrderTarget target,ObjectState!B state){
	switch(target.type){
		case TargetType.terrain: return target.position;
		case TargetType.creature,TargetType.building:
			auto center=object.center;
			auto targetHitbox=state.objectById!((obj,center)=>obj.closestHitbox(center))(target.id,center);
			return projectToBoxTowardsCenter(targetHitbox,center);
		case TargetType.soul:
			return state.soulById!((ref soul)=>soul.center,()=>Vector3f.init)(target.id);
		default: return Vector3f.init;
	}
}

Vector3f predictShotTargetPosition(B)(ref MovingObject!B object,SacSpell!B rangedAttack,bool isAbility,OrderTarget target,ObjectState!B state){
	switch(target.type){
		case TargetType.terrain: return target.position;
		case TargetType.creature,TargetType.building:
			return rangedAttack.needsPrediction?
				object.creatureAI.predictor.predictCenter(object.firstShotPosition(isAbility),rangedAttack.speed,target.id,state) : // TODO: use closest hitbox?
				state.objectById!center(target.id);
		case TargetType.soul: return state.soulById!((ref soul)=>soul.center,()=>Vector3f.init)(target.id); // TODO: predict?
		default: return Vector3f.init;
	}
}

bool aim(bool isAbility=false,B)(ref MovingObject!B object,SacSpell!B rangedAttack,OrderTarget target,Vector3f predicted,ObjectState!B state){
	// TODO: find a spot from where target can be shot
	static if(isAbility){
		auto notShooting=!object.creatureState.mode.isShooting;
	}else{
		auto notShooting=!object.creatureState.mode.isUsingAbility;
	}
	Vector3f targetPosition;
	if(notShooting){
		targetPosition=object.getShotTargetPosition(target,state);
		if(isNaN(targetPosition.x)) return false;
		static if(isAbility){
			auto distance=object.useAbilityDistance(state);
			if(rangedAttack.tag==SpellTag.devour){
				if(object.moveWithinRange2D(targetPosition,distance,state,true,true))
					return true;
			}else{
				if(object.moveWithinRange(targetPosition,distance,state))
					return true;
			}
		}else{
			auto range=object.shootRange(state);
			if(object.moveWithinRange(targetPosition,range,state))
				return true;
		}
	}
	bool isFlying=object.creatureState.movement==CreatureMovement.flying;
	auto flyingHeight=isFlying?object.position.z-state.getHeight(object.position):0.0f;
	auto minFlyingHeight=isFlying?object.creatureStats.flyingHeight:0.0f;
	auto targetFlyingHeight=max(flyingHeight,minFlyingHeight);
	bool stop(){
		object.creatureState.timer=updateFPS; // TODO: this is a bit hacky
		object.stopMovement(state);
		bool evading;
		object.turnToFaceTowardsEvading(predicted,evading,state);
		if(isFlying){
			object.pitch(0.0f,state);
			object.creatureState.targetFlyingHeight=targetFlyingHeight;
		}
		return object.creatureState.speed==0.0f;
	}
	if(notShooting){
		if(!object.hasClearShot(isAbility,predicted,target,state)){
			object.moveTowards(targetPosition,0.0f,state,true,true);
			if(isFlying) object.creatureState.targetFlyingHeight=targetFlyingHeight;
			return true;
		}
		if(stop()){
			auto rotationThreshold=4.0f*object.creatureStats.rotationSpeed(object.creatureState.movement==CreatureMovement.flying)/updateFPS;
			bool evading;
			auto facing=!object.turnToFaceTowardsEvading(predicted,evading,state,rotationThreshold);
			static if(isAbility) auto cooldown=object.creatureStats.effects.abilityCooldown;
			else auto cooldown=object.creatureStats.effects.rangedCooldown;
			if(facing&&cooldown==0&&object.creatureStats.mana>=rangedAttack.manaCost){
				object.creatureAI.targetId=target.id;
				static if(isAbility){
					object.startUsingAbility(state);
				}else{
					object.startShooting(state); // TODO: should this have a delay?
				}
			}
		}
	}else{
		stop();
	}
	return true;
}

void loadOnTick(B)(ref MovingObject!B object,OrderTarget target,SacSpell!B rangedAttack,ObjectState!B state){
	if(object.hasLoadTick(state)){
		switch(rangedAttack.tag){
			case SpellTag.sylphShoot:
				sylphLoad(object.id,state);
				break;
			case SpellTag.rangerShoot:
				rangerLoad(object.id,state);
				break;
			case SpellTag.flummoxShoot:
				flummoxLoad(object.id,state);
				break;
			case SpellTag.webPull:
				auto drainedMana=rangedAttack.manaCost;
				if(object.creatureStats.mana>=drainedMana){
					webPull(object,target.id,rangedAttack,state);
					object.drainMana(rangedAttack.manaCost,state);
				}
				break;
			case SpellTag.cagePull:
				auto drainedMana=rangedAttack.manaCost;
				if(object.creatureStats.mana>=drainedMana){
					cagePull(object,target.id,rangedAttack,state);
					object.drainMana(drainedMana,state);
				}
				break;
			case SpellTag.mutantShoot:
				mutantLoad(object.id,state);
				break;
			default: break;
		}
	}
}
bool shootOnTick(bool ability=false,B)(ref MovingObject!B object,OrderTarget target,Vector3f shotTarget,SacSpell!B rangedAttack,ObjectState!B state){
	if(object.hasShootTick(state)){
		if(!ability) if(object.shootAbilityBug(state)) return true;
		auto drainedMana=rangedAttack.manaCost/object.numShootTicks;
		if(object.creatureStats.mana>=drainedMana){
			auto accuracy=object.creatureStats.rangedAccuracy;
			switch(rangedAttack.tag){
				case SpellTag.brainiacShoot:
					brainiacShoot(object.id,object.side,target.id,accuracy,object.shotPosition,shotTarget,rangedAttack,state);
					break;
				case SpellTag.shrikeShoot:
					shrikeShoot(object.id,object.side,target.id,accuracy,object.shotPosition,shotTarget,rangedAttack,state);
					break;
				case SpellTag.locustShoot:
					locustShoot(object.id,object.side,target.id,accuracy,object.shotPosition,shotTarget,rangedAttack,state);
					// hack to ensure drain gets applied:
					object.creatureStats.health=state.movingObjectById!((obj)=>obj.creatureStats.health,()=>0.0f)(object.id);
					break;
				case SpellTag.spitfireShoot:
					spitfireShoot(object.id,object.side,target.id,accuracy,object.shotPosition,shotTarget,rangedAttack,state);
					break;
				case SpellTag.gargoyleShoot:
					gargoyleShoot(object.id,object.side,target.id,accuracy,object.shotPosition,shotTarget,rangedAttack,state);
					break;
				case SpellTag.earthflingShoot:
					earthflingShoot(object.id,object.side,target.id,accuracy,object.shotPosition,shotTarget,rangedAttack,state);
					break;
				case SpellTag.flameMinionShoot:
					flameMinionShoot(object.id,object.side,target.id,accuracy,object.shotPosition,shotTarget,rangedAttack,state);
					break;
				case SpellTag.fallenShoot:
					fallenShoot(object.id,object.side,target.id,accuracy,object.shotPosition,shotTarget,rangedAttack,state);
					break;
				case SpellTag.sylphShoot:
					sylphShoot(object.id,object.side,target.id,accuracy,object.shotPosition,shotTarget,rangedAttack,state);
					break;
				case SpellTag.rangerShoot:
					rangerShoot(object.id,object.side,target.id,accuracy,object.shotPosition,shotTarget,rangedAttack,state);
					break;
				case SpellTag.necrylShoot:
					necrylShoot(object.id,object.side,target.id,accuracy,object.shotPosition,shotTarget,rangedAttack,state);
					break;
				case SpellTag.scarabShoot:
					scarabShoot(object.id,object.side,target.id,accuracy,object.shotPosition,shotTarget,rangedAttack,state);
					break;
				case SpellTag.basiliskShoot:
					basiliskShoot(object.id,object.side,target.id,accuracy,object.basiliskShotPositions,shotTarget,rangedAttack,state);
					break;
				case SpellTag.tickfernoShoot:
					tickfernoShoot(object.id,object.side,target.id,accuracy,object.shotPosition,shotTarget,rangedAttack,state);
					break;
				case SpellTag.vortickShoot:
					vortickShoot(object.id,object.side,target.id,accuracy,object.shotPosition,shotTarget,rangedAttack,state);
					break;
				case SpellTag.squallShoot:
					squallShoot(object.id,object.side,target.id,accuracy,object.shotPosition,shotTarget,rangedAttack,state);
					break;
				case SpellTag.flummoxShoot:
					flummoxShoot(object.id,object.side,target.id,accuracy,object.shotPosition,shotTarget,rangedAttack,state);
					break;
				case SpellTag.pyromaniacShoot:
					pyromaniacShoot(object.id,object.side,target.id,accuracy,object.shotPosition,shotTarget,rangedAttack,state);
					break;
				case SpellTag.gnomeShoot:
					gnomeShoot(object.id,object.side,target.id,accuracy,object.shotPosition,shotTarget,rangedAttack,state);
					break;
				case SpellTag.deadeyeShoot:
					deadeyeShoot(object.id,object.side,target.id,accuracy,object.shotPosition,shotTarget,rangedAttack,state);
					break;
				case SpellTag.mutantShoot:
					mutantShoot(object.id,object.side,target.id,accuracy,object.shotPosition,shotTarget,rangedAttack,state);
					break;
				// abilities:
				case SpellTag.blightMites:
					blightMitesShoot(object.id,target.id,accuracy,object.shotPosition,shotTarget,rangedAttack,state);
					break;
				case SpellTag.devour:
					devourSoul(object,target.id,rangedAttack,state);
					break;
				case SpellTag.webPull,SpellTag.cagePull:
					return true;
				case SpellTag.stickyBomb:
					stickyBombShoot(object.id,object.side,accuracy,object.shotPosition,shotTarget,rangedAttack,state);
					break;
				case SpellTag.oil:
					oilShoot(object.id,object.side,accuracy,object.shotPosition,shotTarget,rangedAttack,state);
					break;
				default: goto case SpellTag.brainiacShoot;
			}
			object.drainMana(drainedMana,state);
			return true;
		}
	}
	return false;
}

bool shoot(B)(ref MovingObject!B object,SacSpell!B rangedAttack,int targetId,ObjectState!B state){
	if(!isValidAttackTarget(targetId,state)&&(object.creatureState.mode!=CreatureMode.shooting||!state.isValidTarget(targetId))) return false; // TODO
	if(object.rangedAttack !is rangedAttack) return false; // TODO: multiple ranged attacks?
	if(!isValidAttackTarget(targetId,state)) return false;
	auto target=OrderTarget(state.targetTypeFromId(targetId),targetId,Vector3f.init);
	auto predicted=object.predictShotTargetPosition(rangedAttack,false,target,state);
	if(isNaN(predicted.x)) return false;
	if(!object.aim(rangedAttack,target,predicted,state))
		return false;
	if(object.creatureState.mode.isShooting){
		object.loadOnTick(target,rangedAttack,state);
		if(object.shootOnTick(target,predicted,rangedAttack,state)){
			if(object.creatureStats.effects.rangedCooldown==0)
				object.creatureStats.effects.rangedCooldown=cast(int)(rangedAttack.cooldown*updateFPS);
		}
	}
	return true;
}

bool attack(B)(ref MovingObject!B object,int targetId,ObjectState!B state){
	if(!isValidAttackTarget(targetId,state)) return false;
	enum meleeHitboxFactor=0.8f;
	auto meleeHitbox=scaleBox(object.meleeHitbox,meleeHitboxFactor);
	auto meleeHitboxCenter=boxCenter(meleeHitbox);
	static bool intersects(T)(T obj,Vector3f[2] hitbox){
		static if(is(T==MovingObject!B)){
			return boxesIntersect(obj.hitbox,hitbox);
		}else{
			foreach(bhitb;obj.hitboxes)
				if(boxesIntersect(bhitb,hitbox))
					return true;
			return false;
		}
	}
	int target=0;
	if(state.objectById!intersects(targetId,meleeHitbox)){
		target=meleeAttackTarget(object,state); // TODO: share melee hitbox computation?
		if(target&&target!=targetId&&!isValidEnemyAttackTarget(targetId,object.side,state))
			target=0;
	}
	auto targetHitbox=state.objectById!((ref obj,meleeHitboxCenter)=>obj.closestHitbox(meleeHitboxCenter))(targetId,meleeHitboxCenter);
	auto targetPosition=boxCenter(targetHitbox);
	auto hitbox=object.hitbox;
	auto position=boxCenter(hitbox);
	auto flatTargetHitbox=targetHitbox;
	flatTargetHitbox[1].z=max(flatTargetHitbox[0].z,targetHitbox[1].z-boxSize(hitbox).z);
	auto movementPosition=projectToBoxTowardsCenter(flatTargetHitbox,object.position); // TODO: ranged creatures should move to a nearby location where they have a clear shot
	if(auto ra=object.rangedAttack){
		if(ra.tag==SpellTag.scarabShoot){
			if(target&&state.movingObjectById!((ref obj,side)=>obj.side==side,()=>false)(target,object.side))
				target=0;
		}
		if(!target||object.rangedMeleeAttackDistance(state)^^2<boxBoxDistanceSqr(hitbox,targetHitbox))
			return object.shoot(ra,targetId,state);
	}
	auto targetDistance=(position-meleeHitboxCenter).xy.length;
	if(target||!object.moveWithinRange(movementPosition,2.8f*targetDistance,state,!object.isMeleeAttacking(state),false,false,targetId)){
		bool evading;
		if(object.turnToFaceTowardsEvading(movementPosition,evading,state,0.2f*pi!float,true,targetId)&&!evading||
		   !object.moveWithinRange(movementPosition,0.8f*targetDistance,state,!object.isMeleeAttacking(state),false,false,targetId,true)){
			object.stopMovement(state);
			object.pitch(0.0f,state);
		}
	}
	if(target){
		enum downwardThreshold=0.25f;
		object.startMeleeAttacking(targetPosition.z+downwardThreshold<position.z,state);
		object.creatureState.targetFlyingHeight=float.nan;
	}else if(!object.rangedAttack){
		if(object.creatureState.movement==CreatureMovement.flying){
			auto minFlyingHeight=object.creatureStats.flyingHeight*min(1.0f,0.1f*targetDistance-0.5f);
			object.creatureState.targetFlyingHeight=max(minFlyingHeight,movementPosition.z-max(state.getHeight(movementPosition),state.getHeight(object.position)));
		}
	}
	return true;
}

float maxTargetHeight(B)(ref MovingObject!B object,ObjectState!B state){
	if(object.creatureState.movement==CreatureMovement.flying||object.rangedAttack) return float.infinity;
	return object.relativeMeleeHitbox[1].z;
}

int updateTarget(bool advance=false,B,T...)(ref MovingObject!B object,Vector3f position,float range,ObjectState!B state){
	auto newPosition=position;
	newPosition.z=state.getHeight(newPosition)+object.position.z-state.getHeight(object.position);
	if(state.frontOfAIQueue(object.side,object.id)){
		if(object.rangedAttack&&object.rangedAttack.tag==SpellTag.scarabShoot){
			static bool filter(ref CenterProximityEntry entry,ObjectState!B state){
				if(!entry.isVisibleToAI) return false;
				if(state.movingObjectById!((ref obj)=>obj.creatureStats.health==obj.creatureStats.maxHealth,()=>true)(entry.id))
					return false;
				return true;
			}
			auto targetId=state.proximity.lowestHealthCreatureInRange!filter(object.side,object.id,newPosition,object.rangedAttack.range,state,state);
			if(!targetId) targetId=state.proximity.lowestHealthCreatureInRange!filter(object.side,object.id,newPosition,range,state,state);
			object.creatureAI.targetId=targetId;
		}else{
			float maxHeight=object.maxTargetHeight(state);
			static if(advance) object.creatureAI.targetId=state.proximity.enemyInRangeAndClosestToPreferringAttackersOf(object.side,object.position,range,newPosition,object.id,EnemyType.all,state,maxHeight);
			else object.creatureAI.targetId=state.proximity.closestEnemyInRange(object.side,newPosition,range,EnemyType.all,state,maxHeight);
		}
	}
	if(!state.isValidTarget(object.creatureAI.targetId)) object.creatureAI.targetId=0;
	return object.creatureAI.targetId;
}

bool patrolAround(B)(ref MovingObject!B object,Vector3f position,ObjectState!B state){
	if(!object.isAggressive(state)) return false;
	auto guardRange=object.guardRange(state);
	if((object.position.xy-position.xy).lengthsqr>guardRange^^2) return false;
	auto aggressiveRange=object.guardAggressiveRange(state);
	if(auto targetId=object.updateTarget(position,aggressiveRange,state))
		if(object.attack(targetId,state))
			return true;
	return false;
}

bool guard(B)(ref MovingObject!B object,int targetId,ref bool idle,ObjectState!B state){
	if(!isValidGuardTarget(targetId,state)) return false;
	auto targetPositionTargetFacingTargetSpeedTargetMode=state.movingObjectById!((obj,state)=>tuple(obj.position,obj.creatureState.facing,obj.speed(state)/updateFPS,obj.creatureState.mode), ()=>tuple(object.creatureAI.order.target.position,object.creatureAI.order.targetFacing,0.0f,CreatureMode.idle))(targetId,state);
	auto targetPosition=targetPositionTargetFacingTargetSpeedTargetMode[0], targetFacing=targetPositionTargetFacingTargetSpeedTargetMode[1], targetSpeed=targetPositionTargetFacingTargetSpeedTargetMode[2],targetMode=targetPositionTargetFacingTargetSpeedTargetMode[3];
	object.creatureAI.order.target.position=targetPosition;
	object.creatureAI.order.targetFacing=targetFacing;
	auto formationOffset=object.creatureAI.order.formationOffset;
	targetPosition=getTargetPosition(targetPosition,targetFacing,formationOffset,state);
	if(!object.patrolAround(targetPosition,state)){ // TODO: prefer enemies that attack the guard target?
		idle&=!object.moveTo(targetPosition,targetFacing,state);
	}
	return true;
}

bool patrol(B)(ref MovingObject!B object,ObjectState!B state){
	if(!object.isAggressive(state)) return false;
	auto position=object.position;
	auto range=object.aggressiveRange(state);
	if(auto targetId=object.updateTarget(position,range,state))
		if(object.attack(targetId,state))
			return true;
	return false;
}

bool advance(B)(ref MovingObject!B object,Vector3f targetPosition,ObjectState!B state){
	if(object.isPacifist(state)) return false;
	auto range=object.advanceAggressiveRange(state);
	if(auto targetId=object.updateTarget!true(targetPosition,range,state))
		if(object.attack(object.creatureAI.targetId,state))
			return true;
	return false;
}

bool runAway(B)(ref MovingObject!B object,SacSpell!B ability,ObjectState!B state){
	return speedUp(object,ability,ability.duration,state);
}

bool rockForm(B)(ref MovingObject!B object,ObjectState!B state){
	if(object.creatureState.mode==CreatureMode.rockForm) return false;
	object.clearOrderQueue(state);
	object.frame=0;
	object.animationState=AnimationState.stance1;
	object.creatureState.mode=CreatureMode.rockForm;
	object.setCreatureState(state);
	if(object.animationState==AnimationState.stance2)
		object.animationState=AnimationState.stance1;
	playSoundAt("tlep",object.id,state,2.0f);
	auto hbox=object.sacObject.hitbox(Quaternionf.identity(),object.animationState,0);
	auto scale=0.55f*(object.hitbox[1]-object.hitbox[0]).length;
	state.addEffect(RockForm!B(object.id,scale));
	return true;
}

void updateRenderMode(B)(int target,ObjectState!B state){
	if(!state.isValidTarget(target,TargetType.creature)) return;
	static RenderMode targetMode(ref MovingObject!B object,ObjectState!B state){
		if(object.creatureStats.effects.stealth||object.creatureStats.effects.appearing||object.creatureStats.effects.disappearing||object.creatureStats.effects.etherealForm) return RenderMode.transparent;
		with(CreatureMode) if(object.creatureState.mode.among(deadToGhost,idleGhost,movingGhost,ghostToIdle)) return RenderMode.transparent;
		return RenderMode.opaque;
	}
	final switch(state.movingObjectById!(targetMode,()=>RenderMode.opaque)(target,state)){
		import std.traits: EnumMembers;
		static foreach(mode;EnumMembers!RenderMode){
			case mode: return state.setRenderMode!(MovingObject!B,mode)(target);
		}
	}
}

bool stealth(B)(ref MovingObject!B object,ObjectState!B state){
	if(object.creatureStats.effects.stealth) return false;
	object.clearOrderQueue(state);
	object.creatureStats.effects.stealth=true;
	playSoundAt("tlts",object.id,state,2.0f);
	state.addEffect(Stealth!B(object.id));
	return true;
}

bool lifeShield(B)(ref MovingObject!B object,SacSpell!B ability,ObjectState!B state){
	if(object.creatureStats.effects.lifeShield) return false;
	if(object.creatureStats.effects.shieldBlocked) return false;
	object.creatureStats.effects.lifeShield=true;
	auto duration=20;
	playSoundAt!true("ahsl",object.id,state,2.0f);
	state.addEffect(LifeShield!B(object.id,ability,duration));
	return true;
}

bool divineSight(B)(ref MovingObject!B object,SacSpell!B ability,ObjectState!B state){
	auto direction=rotate(facingQuaternion(object.creatureState.facing),Vector3f(0.0f,1.0f,0.0f));
	auto position=object.position+2.0f*direction;
	position.z=state.getHeight(position);
	auto velocity=ability.speed*direction;
	state.addEffect(DivineSight!B(object.side,object.id,position,velocity,ability));
	return true;
}

bool blightMitesShoot(B)(int creature,int intendedTarget,float accuracy,Vector3f position,Vector3f target,SacSpell!B ability,ObjectState!B state){
	playSoundAt("ltim",position,state,4.0f); // TODO: move sound with projectile
	foreach(i;0..10){
		auto direction=getShotDirectionWithGravity(accuracy,position,target,ability,state);
		direction+=0.2f*state.uniformDirection();
		state.addEffect(BlightMite!B(creature,intendedTarget,position,direction*ability.speed,ability));
	}
	return true;
}

bool callLightning(B)(ref MovingObject!B object,SacSpell!B spell,ObjectState!B state){
	auto center=object.center;
	auto direction=(state.uniformDirection()+Vector3f(0.0f,0.0f,4.0f)).normalized;
	auto position=center+100.0f*direction;
	auto end=OrderTarget(TargetType.creature,object.id,center);
	auto start=OrderTarget(TargetType.terrain,0,position);
	auto lightningSpell=SacSpell!B.get(SpellTag.lightning);
	return lightning(object.id,object.side,start,end,lightningSpell,state);
}

bool lightningCharge(B)(ref MovingObject!B object,int frames,SacSpell!B spell,ObjectState!B state){
	if(frames<=0) return true;
	if(object.creatureStats.effects.lightningChargeFrames==0) state.addEffect(LightningCharge!B(object.id,object.side,spell));
	object.creatureStats.effects.lightningChargeFrames+=frames;
	return true;
}

bool devourSoul(B)(ref MovingObject!B object,int soulId,SacSpell!B ability,ObjectState!B state){
	return state.soulById!((ref soul,obj,state){
		if(soul.state!=SoulState.normal) return false;
		soul.collectorId=obj.id;
		soul.state=SoulState.devouring;
		playSoundAt("ltss",obj.id,state,2.0f);
		soul.severSoul(state);
		auto rbow=SacSpell!B.get(SpellTag.rainbow);
		foreach(_;0..soul.number){
			obj.creatureStats.health+=500.0f;
			obj.creatureStats.maxHealth+=500.0f;
			if(isNaN(obj.creatureStats.effects.devourRegenerationIncrement)) // TODO: needed?
				obj.creatureStats.effects.devourRegenerationIncrement=0.25f*obj.creatureStats.maxHealth;
			else obj.creatureStats.effects.devourRegenerationIncrement=0.75*obj.creatureStats.effects.devourRegenerationIncrement+125.0f;
			obj.creatureStats.regeneration+=obj.creatureStats.effects.devourRegenerationIncrement/60.0f;
			obj.creatureStats.meleeResistance*=0.9f;
			obj.creatureStats.directSpellResistance*=0.9f;
			obj.creatureStats.splashSpellResistance*=0.9f;
			obj.creatureStats.directRangedResistance*=0.9f;
			obj.creatureStats.splashRangedResistance*=0.9f;
			obj.creatureStats.effects.numBulks+=1;
		}
		heal(obj.id,rbow,state);
		return true;
	},()=>false)(soulId,&object,state);
}

bool pull(PullType type,B)(ref MovingObject!B object,int target,SacSpell!B ability,ObjectState!B state){
	auto startPos=object.shotPosition,endPos=state.movingObjectById!((ref tobj)=>tobj.center,()=>Vector3f.init)(target);
	if(isNaN(endPos.x)) return false;
	static bool filter(ref ProximityEntry entry,int id){ return entry.id!=id; }
	auto newTarget=state.collideRay!filter(startPos,endPos-startPos,1.0f,object.id);
	if(newTarget.type!=TargetType.none) target=newTarget.id;
	object.startPulling(state);
	state.addEffect(Pull!(type,B)(object.id,target,ability));
	return true;
}
bool webPull(B)(ref MovingObject!B object,int target,SacSpell!B ability,ObjectState!B state){ return pull!(PullType.webPull)(object,target,ability,state); }
bool cagePull(B)(ref MovingObject!B object,int target,SacSpell!B ability,ObjectState!B state){ return pull!(PullType.cagePull)(object,target,ability,state); }

bool stickyBombShoot(B)(int creature,int side,float accuracy,Vector3f position,Vector3f target,SacSpell!B ability,ObjectState!B state){
	playSoundAt("klab",position,state,4.0f); // TODO: move sound with projectile
	foreach(i;0..10){
		auto direction=getShotDirectionWithGravity(accuracy,position,target,ability,state);
		direction+=0.2f*state.uniformDirection();
		state.addEffect(StickyBomb!B(creature,side,position,direction*ability.speed,ability));
	}
	return true;
}

bool oilShoot(B)(int creature,int side,float accuracy,Vector3f position,Vector3f target,SacSpell!B ability,ObjectState!B state){
	playSoundAt("slio",position,state,4.0f); // TODO: move sound with projectile
	auto direction=getShotDirectionWithGravity(accuracy,position,target,ability,state);
	state.addEffect(OilProjectile!B(creature,side,position,direction*ability.speed,ability));
	return true;
}

bool protector(B)(ref MovingObject!B object,SacSpell!B ability,ObjectState!B state){
	if(object.creatureStats.effects.lifeShield) return false;
	auto lifeShield=SacSpell!B.get(SpellTag.lifeShield);
	object.lifeShield(lifeShield,state);
	state.addEffect(Protector!B(object.id,ability));
	return true;
}

bool haloOfEarth(B)(ref MovingObject!B object,SacSpell!B ability,ObjectState!B state){
	playSoundAt("tlep",object.id,state,2.0f*haloOfEarthGain);
	state.addEffect(HaloOfEarth!B(object.id,object.side,ability,true));
	return true;
}

void appear(B)(int id,int lifetime,ObjectState!B state){
	if(!state.movingObjectById!((ref object){
		if(object.creatureStats.effects.appearing) return false;
		object.creatureStats.effects.appearing=true;
		return true;
	},()=>false)(id)) return;
	updateRenderMode(id,state);
	state.setAlpha(id,0.0f,1.0f);
	state.addEffect(Appearance(id,lifetime));
}

void disappear(B)(ref MovingObject!B object,int lifetime,ObjectState!B state){
	if(object.creatureStats.effects.disappearing) return;
	object.creatureStats.effects.disappearing=true;
	state.addEffect(Disappearance(object.id,lifetime));
}

int makeManafount(B)(Vector3f position,int flags,ObjectState!B state){
	return makeBuilding(neutralSide,"tnof",position,flags,state);
}

bool hasAltar(B)(int side,ObjectState!B state){
	static void find(T)(ref T objects,int side,ObjectState!B state,bool* found){
		if(*found) return;
		static if(is(T==StaticObjects!(B,renderMode),RenderMode renderMode)){
			if(objects.sacObject.isAltar){
				foreach(j;0..objects.length){
					if(state.buildingById!((ref bldg,side){
						if(bldg.side!=side) return false;
						if(!isAltar(bldg)) return false;
						if(bldg.flags&(AdditionalBuildingFlags.inactive|Flags.notOnMinimap)) return false;
						return true;
					},()=>false)(objects.buildingIds[j],side)){
						*found=true;
						break;
					}
				}
			}
		}
	}
	bool found=false;
	state.eachByType!find(side,state,&found);
	return found;
}

bool destroyAltar(B)(ref StaticObject!B shrine,ObjectState!B state){
	static bool destroy(ref Building!B building,StaticObject!B* shrine,ObjectState!B state){
		if(!isAltar(building)) return false;
		if(building.flags&AdditionalBuildingFlags.inactive) return false;
		building.deactivate(state);
		enforce(building.componentIds[0]==shrine.id);
		enforce(building.componentIds.length>=2);
		float shrineHeight=(*shrine).relativeHitbox[1].z;
		int ring=building.componentIds.length>=6?building.componentIds[5]:building.componentIds[1];
		int[4] pillars;
		if(building.componentIds.length>=6) pillars[]=building.componentIds.data[1..5];
		float pillarHeight=pillars[0]?state.staticObjectById!((ref pillar,state)=>pillar.relativeHitbox[1].z,()=>0.0f)(pillars[0],state):0.0f;
		int[4] stalks;
		if(building.componentIds.length>=10) stalks[]=building.componentIds.data[6..10];
		float stalkHeight=stalks[0]?state.staticObjectById!((ref pillar,state)=>pillar.relativeHitbox[1].z,()=>0.0f)(stalks[0],state):0.0f;
		state.addEffect(AltarDestruction(ring,shrine.position,Quaternionf.identity(),Quaternionf.identity(),shrine.id,shrineHeight,pillars,pillarHeight,stalks,stalkHeight));
		return true;
	}
	return state.buildingById!(destroy,()=>false)(shrine.buildingId,&shrine,state);
}

void destroyAltars(B)(int side,ObjectState!B state){
	static void destroy(T)(ref T objects,int side,ObjectState!B state){
		static if(is(T==StaticObjects!(B,renderMode),RenderMode renderMode)){
			if(objects.sacObject.isAltar){
				foreach(j;0..objects.length){
					if(state.buildingById!((ref bldg,side)=>bldg.side!=side,()=>true)(objects.buildingIds[j],side))
						continue;
					auto shrine=objects[j];
					destroyAltar(shrine,state);
				}
			}
		}
	}
	state.eachByType!destroy(side,state);
}

void lose(B)(int side,ObjectState!B state){
	destroyAltars(side,state);
	killAll(side,state);
}

bool surrender(B)(int side,ObjectState!B state){ lose(side,state); return true; }

void screenShake(B)(Vector3f position,int lifetime,float strength,float range,ObjectState!B state){
	state.addEffect(ScreenShake(position,lifetime,strength,range));
}

void testDisplacement(B)(ObjectState!B state){
	state.addEffect(TestDisplacement());
}

bool isRangedAbility(B)(SacSpell!B ability){ // TODO: put this directly in SacSpell!B ?
	switch(ability.tag){
		case SpellTag.blightMites: return true;
		case SpellTag.devour: return true;
		case SpellTag.webPull,SpellTag.cagePull: return true;
		case SpellTag.stickyBomb: return true;
		case SpellTag.oil: return true;
		default: return false;
	}
}

bool checkAbility(B)(ref MovingObject!B object,SacSpell!B ability,OrderTarget target,ObjectState!B state){
	if(ability.requiresTarget&&!ability.isApplicable(summarize(target,object.side,state))){
		target.id=0;
		target.type=TargetType.terrain;
		if(ability.requiresTarget&&!ability.isApplicable(summarize(target,object.side,state)))
			return false;
	}
	auto status=state.abilityStatus!false(object,ability,target);
	if(status.among(SpellStatus.notReady,SpellStatus.lowOnMana,SpellStatus.outOfRange)) return ability.isRangedAbility;
	return status==SpellStatus.ready;
}

bool useAbility(B)(ref MovingObject!B object,SacSpell!B ability,OrderTarget target,ObjectState!B state){
	if(object.ability!is ability) return false;
	if(!isRangedAbility(ability)&&!object.checkAbility(ability,target,state)) return false;
	void apply(){
		object.drainMana(ability.manaCost,state);
		object.creatureStats.effects.abilityCooldown=cast(int)(ability.cooldown*updateFPS);
	}
	bool shoot(){
		if(target.id&&!isValidAttackTarget(target.id,state)&&!state.isValidTarget(target.id,TargetType.soul)) return false;
		auto predicted=object.predictShotTargetPosition(ability,true,target,state);
		if(isNaN(predicted.x)) return false;
		if(!object.aim!true(ability,target,predicted,state))
			return false;
		if(object.creatureState.mode.isUsingAbility){
			object.loadOnTick(target,ability,state);
			if(object.shootOnTick!true(target,predicted,ability,state)){
				if(object.creatureStats.effects.abilityCooldown==0)
					object.creatureStats.effects.abilityCooldown=cast(int)(ability.cooldown*updateFPS);
				return false;
			}
		}
		return true;
	}
	switch(ability.tag){
		case SpellTag.runAway:
			if(object.runAway(ability,state)) apply();
			return false;
		case SpellTag.playDead:
			if(object.playDead(state)) apply();
			return false;
		case SpellTag.rockForm:
			if(object.rockForm(state)) apply();
			return false;
		case SpellTag.stealth:
			if(object.stealth(state)) apply();
			return false;
		case SpellTag.lifeShield:
			if(object.lifeShield(ability,state)) apply();
			return false;
		case SpellTag.divineSight:
			if(object.divineSight(ability,state)) apply();
			return false;
		case SpellTag.blightMites:
			return shoot();
		case SpellTag.callLightning:
			if(object.callLightning(ability,state)) apply();
			return false;
		case SpellTag.devour:
			return shoot();
		case SpellTag.webPull,SpellTag.cagePull:
			return shoot();
		case SpellTag.stickyBomb:
			return shoot();
		case SpellTag.oil:
			return shoot();
		case SpellTag.protector:
			if(object.protector(ability,state)) apply();
			return false;
		case SpellTag.haloOfEarthAbility:
			if(object.haloOfEarth(ability,state)) apply();
			return false;
		default:
			object.stun(state);
			object.clearOrder(state);
			return false;
	}
}

bool runAwayBug(B)(ref MovingObject!B object,ObjectState!B state){
	auto ability=object.ability;
	if(!ability||ability.tag!=SpellTag.runAway) return false;
	if(object.creatureAI.order.command!=CommandType.useAbility) return false;
	auto targetId=object.creatureAI.targetId;
	if(!state.isValidTarget(targetId,TargetType.creature)) return false;
	if(state.movingObjectById!((target)=>target.creatureStats.effects.numSpeedUps!=0,()=>true)(targetId)) return false;
	if(state.abilityStatus!true(object,ability)!=SpellStatus.ready) return false;
	object.creatureStats.effects.abilityCooldown=cast(int)(ability.cooldown*updateFPS);
	object.drainMana(ability.manaCost,state);
	object.clearOrder(state);
	state.movingObjectById!((ref target,ability,state){ target.runAway(ability,state); },(){})(targetId,ability,state);
	return true;
}

bool shootAbilityBug(B)(ref MovingObject!B object,ObjectState!B state){
	if(runAwayBug(object,state)) return true;
	auto ability=object.ability;
	if(!ability||object.creatureAI.order.command!=CommandType.useAbility) return false;
	auto id=object.creatureAI.targetId;
	auto targetType=state.targetTypeFromId(id);
	if(!targetType.among(TargetType.creature,TargetType.building)) return false;
	auto target=OrderTarget(targetType,id,state.objectById!((obj)=>obj.position)(id));
	if(!object.checkAbility(ability,target,state)) return false;
	if(!object.useAbility(ability,target,state))
		object.clearOrder(state);
	return true;
}

bool steamCloud(B)(ref MovingObject!B object,SacSpell!B ability,ObjectState!B state){
	state.addEffect(SteamCloud!B(object.id,object.side,object.hitbox,ability));
	return true;
}

bool poisonCloud(B)(ref MovingObject!B object,SacSpell!B ability,ObjectState!B state){
	state.addEffect(PoisonCloud!B(object.id,object.side,object.hitbox,ability));
	return true;
}

bool healingShower(B)(ref MovingObject!B object,SacSpell!B ability,ObjectState!B state){
	state.addEffect(HealingShower!B(object.id,object.side,object.hitbox,ability));
	return true;
}

enum retreatDistance=9.0f;
enum attackDistance=100.0f; // ok?
enum shelterDistance=50.0f;
enum scareDistance=50.0f;
enum speedLimitFactor=0.5f;
enum rotationSpeedLimitFactor=1.0f;

bool requiresAI(CreatureMode mode){
	with(CreatureMode) final switch(mode){
		case idle,moving,spawning,takeoff,landing,meleeMoving,meleeAttacking,cower,casting,stationaryCasting,castingMoving,shooting,usingAbility,pulling,playingDead,rockForm: return true;
		case dying,dead,dissolving,preSpawning,reviving,fastReviving,stunned,pretendingToDie,pretendingToRevive,pumping,torturing,convertReviving,thrashing: return false;
		case deadToGhost,ghostToIdle: return false;
		case idleGhost,movingGhost: return true;
	}
}

void updateCreatureAI(B)(ref MovingObject!B object,ObjectState!B state){
	if(!requiresAI(object.creatureState.mode)) return;
	if(object.creatureStats.effects.oiled) return;
	if(!object.creatureAI.isOnAIQueue) object.creatureAI.isOnAIQueue=state.pushToAIQueue(object.side,object.id);
	if(object.creatureState.mode.isShooting){
		if(!object.shoot(object.rangedAttack,object.creatureAI.targetId,state))
			object.creatureAI.targetId=0;
		return;
	}
	if(object.creatureState.mode.isUsingAbility){
		if(object.creatureAI.order.command==CommandType.useAbility) // TODO: fix
			object.useAbility(object.ability,object.creatureAI.order.target,state);
		return;
	}
	if(object.isHidden){
		if(object.creatureAI.order.command==CommandType.none)
			return;
		if(object.creatureState.mode==CreatureMode.playingDead)
			return object.pretendToRevive(state);
		if(object.creatureState.mode==CreatureMode.rockForm)
			object.startIdling(state);
	}
	switch(object.creatureAI.order.command){
		case CommandType.retreat:
			auto targetId=object.creatureAI.order.target.id;
			if(!state.isValidTarget(targetId)||!isValidGuardTarget(targetId,state))
				targetId=object.creatureAI.order.target.id=0;
			Vector3f targetPosition;
			if(targetId) targetPosition=state.movingObjectById!((obj)=>obj.position,()=>Vector3f.init)(targetId);
			if(targetPosition !is Vector3f.init){
				if(!object.retreatTowards(targetPosition,state))
					object.unqueueOrder(state);
			}else object.clearOrder(state);
			break;
		case CommandType.move:
			auto targetPosition=object.creatureAI.order.getTargetPosition(state);
			if(!object.moveTo(targetPosition,object.creatureAI.order.targetFacing,state))
				object.clearOrder(state);
			break;
		case CommandType.guard:
			auto targetId=object.creatureAI.order.target.id;
			bool idle=true;
			if(!state.isValidTarget(targetId)||!object.guard(targetId,idle,state)) targetId=object.creatureAI.order.target.id=0;
			if(targetId==0&&!object.patrol(state)) goto case CommandType.move;
			if(idle) object.unqueueOrder(state);
			break;
		case CommandType.guardArea:
			auto targetPosition=object.creatureAI.order.getTargetPosition(state);
			if(!object.patrolAround(targetPosition,state))
				if(!object.moveTo(targetPosition,object.creatureAI.order.targetFacing,state))
					object.unqueueOrder(state);
			break;
		case CommandType.attack:
			auto targetId=object.creatureAI.order.target.id;
			if(!state.isValidTarget(targetId)||!object.attack(targetId,state)) targetId=object.creatureAI.order.target.id=0;
			// TODO: unqueue order if targetId==0?
			if(targetId==0&&!object.patrol(state)) goto case CommandType.move;
			break;
		case CommandType.advance:
			auto targetPosition=object.creatureAI.order.getTargetPosition(state);
			if(!object.advance(targetPosition,state))
				if(!object.moveTo(targetPosition,object.creatureAI.order.targetFacing,state))
					object.unqueueOrder(state);
			break;
		case CommandType.none:
			if(object.isPeasant){
				if(auto shelter=state.proximity.closestPeasantShelterInRange(object.side,object.position,shelterDistance,state)){
					if(object.creatureState.mode==CreatureMode.cower){
						object.frame=0;
						object.startIdling(state);
					}
					if(state.frontOfAIQueue(object.side,object.id))
						object.creatureAI.targetId=state.proximity.closestEnemyInRange(object.side,object.position,scareDistance,EnemyType.creature,state);
					if(!state.isValidTarget(object.creatureAI.targetId,TargetType.creature)) object.creatureAI.targetId=0;
					if(auto enemy=object.creatureAI.targetId){
						auto enemyPosition=state.movingObjectById!((obj)=>obj.position,function Vector3f(){ assert(0); })(enemy);
						// TODO: figure out the original rule for this
						if(object.creatureState.mode==CreatureMode.idle&&object.creatureState.timer>=updateFPS
						   &&!object.creatureStats.effects.immobilized
						   &&!object.creatureStats.effects.fixed)
							playSoundTypeAt(object.sacObject,object.id,SoundType.run,state);
						object.moveTowards(object.position-(enemyPosition-object.position),0.0f,state);
					}else object.stop(state);
				}else if(object.creatureState.mode!=CreatureMode.cower)
					object.startCowering(state);
			}else if(object.isAggressive(state)){
				if(!object.patrol(state)){
					object.stopMovement(state);
					object.stopTurning(state);
					if(object.creatureState.movement==CreatureMovement.flying){
						object.creatureState.targetFlyingHeight=float.nan;
						object.pitch(0.0f,state);
					}
				}
			}
			break;
		case CommandType.useAbility:
			auto ability=object.ability;
			if(!ability||!object.useAbility(ability,object.creatureAI.order.target,state)){
				object.clearOrder(state);
				object.updateCreatureAI(state);
			}
			break;
		default: assert(0); // TODO: compilation error would be better
	}
}

bool isIdle(B)(ref MovingObject!B object, ObjectState!B state){
	return object.creatureState.mode==CreatureMode.idle && object.creatureAI.order.command==CommandType.none;
}

enum ghostAlpha=0.36f;
enum ghostEnergy=10.0f;

void animateGhostTransition(B)(ref MovingObject!B wizard,ObjectState!B state){
	playSpellSoundTypeAt(SoundType.lightning,wizard.id,state,2.0f);
	enum numParticles=100;
	auto sacParticle=SacParticle!B.get(ParticleType.ghostTransition);
	auto hitbox=wizard.hitbox;
	foreach(i;0..numParticles){
		auto position=state.uniform(hitbox);
		auto direction=(position-wizard.position).normalized;
		auto velocity=state.uniform(1.0f,2.0f)*direction;
		velocity.z*=2.5f;
		auto scale=state.uniform(0.25f,0.75f);
		auto lifetime=95;
		auto frame=0;
		state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
	}
}
void animateGhost(B)(ref MovingObject!B wizard,ObjectState!B state){
	auto hitbox=wizard.hitbox;
	auto sacParticle=SacParticle!B.get(ParticleType.ghost);
	auto scale=1.0f; // TODO: does this differ for different creatures?
	auto frame=state.uniform!"[)"(0,sacParticle.numFrames);
	auto particle=Particle!(B,false,true)(sacParticle,state.uniform(hitbox),Vector3f(0.0f,0.0f,0.0f),scale,sacParticle.numFrames,frame);
	particle.sideFilter=wizard.side;
	state.addParticle(particle);
}
bool unghost(B)(ref MovingObject!B wizard,ObjectState!B state){
	if(!wizard.creatureState.mode.among(CreatureMode.idleGhost,CreatureMode.movingGhost)) return false;
	wizard.creatureState.mode=CreatureMode.ghostToIdle;
	wizard.setCreatureState(state);
	wizard.animateGhostTransition(state);
	return true;
}

void updateCreatureState(B)(ref MovingObject!B object, ObjectState!B state){
	if(object.creatureStats.effects.stunCooldown!=0) --object.creatureStats.effects.stunCooldown;
	if(object.creatureStats.effects.rangedCooldown!=0) --object.creatureStats.effects.rangedCooldown;
	if(object.creatureStats.effects.abilityCooldown!=0) --object.creatureStats.effects.abilityCooldown;
	if(object.creatureStats.effects.infectionCooldown!=0) --object.creatureStats.effects.infectionCooldown;
	if(object.creatureStats.effects.yellCooldown!=0) --object.creatureStats.effects.yellCooldown;
	if(object.creatureStats.effects.numBulks!=0){
		float targetBulk=2.0f-0.75f^^object.creatureStats.effects.numBulks;
		static import std.math;
		static immutable float factor=1.0f-std.math.exp(std.math.log(0.1f)/updateFPS);
		object.creatureStats.effects.bulk=(1.0f-factor)*object.creatureStats.effects.bulk+factor*targetBulk;
	}
	int slowdownFactor=object.slowdownFactor;
	if(state.frame%slowdownFactor) return;
	auto sacObject=object.sacObject;
	final switch(object.creatureState.mode){
		case CreatureMode.idle, CreatureMode.moving, CreatureMode.idleGhost, CreatureMode.movingGhost:
			if(object.creatureState.movement==CreatureMovement.tumbling && state.isOnGround(object.position) && object.position.z+object.creatureState.fallingVelocity.z/updateFPS<=state.getGroundHeight(object.position))
			   object.creatureState.movement=CreatureMovement.onGround;
			auto oldMode=object.creatureState.mode;
			auto ghost=oldMode==CreatureMode.idleGhost||oldMode==CreatureMode.movingGhost;
			if(ghost) object.animateGhost(state);
			if(ghost&&(object.health==object.creatureStats.maxHealth||object.creatureStats.effects.numDesecrations)){
				if(object.creatureStats.effects.numDesecrations) object.creatureStats.health=max(1.0f,object.creatureStats.health);
				object.unghost(state);
				break;
			}
			auto idle=ghost?CreatureMode.idleGhost:CreatureMode.idle;
			auto moving=ghost?CreatureMode.movingGhost:CreatureMode.moving;
			auto newMode=object.creatureState.movementDirection==MovementDirection.none&&object.creatureState.speed==0.0f||object.creatureStats.effects.fixed?idle:moving;
			object.creatureState.timer+=1;
			object.frame+=1;
			if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor){
				object.frame=0;
				if(object.animationState==cast(AnimationState)SacDoctorAnimationState.pickUpCorpse) object.animationState=AnimationState.stance1;
				object.creatureState.mode=newMode;
				object.setCreatureState(state);
			}else if(newMode!=oldMode && object.creatureState.timer>=0.1f*updateFPS){
				object.creatureState.mode=newMode;
				object.setCreatureState(state);
			}
			if(oldMode==newMode&&newMode==idle && object.animationState.among(AnimationState.run,AnimationState.walk,cast(AnimationState)SacDoctorAnimationState.walk) && object.creatureState.timer>=0.1f*updateFPS){
				object.animationState=AnimationState.stance1;
				object.setCreatureState(state);
			}
			break;
		case CreatureMode.rockForm:
			break;
		case CreatureMode.dying, CreatureMode.pretendingToDie:
			with(AnimationState) assert(object.animationState.among(death0,death1,death2,flyDeath,falling,tumble,hitFloor),text(sacObject.tag," ",object.animationState));
			if(object.creatureState.movement==CreatureMovement.tumbling){
				if(state.isOnGround(object.position)){
					if(object.creatureState.fallingVelocity.z<=0.0f&&object.position.z+object.creatureState.fallingVelocity.z/updateFPS<=state.getGroundHeight(object.position)){
						object.creatureState.movement=CreatureMovement.onGround;
						with(AnimationState)
						if(sacObject.canFly && !object.animationState.among(hitFloor,death0,death1,death2)){
							object.frame=0;
							object.animationState=AnimationState.hitFloor;
						}else object.setCreatureState(state);
						break;
					}
				}
			}
			object.frame+=1;
			if(object.isSacDoctor&&object.frame==70) object.disappear(50,state);
			if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor){
				object.frame=0;
				final switch(object.creatureState.movement){
					case CreatureMovement.onGround:
						object.frame=sacObject.numFrames(object.animationState)*updateAnimFactor-1;
						if(object.creatureState.mode==CreatureMode.dying){
							object.creatureState.mode=CreatureMode.dead;
							if(object.isWizard){
								bool noAltar=!hasAltar(object.side,state);
								if(object.creatureStats.effects.numDesecrations||noAltar){
									object.disappear(object.creatureStats.effects.numDesecrations?4*updateFPS:updateFPS,state);
								}else{
									object.creatureState.mode=CreatureMode.deadToGhost;
									object.setCreatureState(state);
								}
							}else{
								object.spawnSoul(state);
								object.unselect(state);
								object.removeFromGroups(state);
							}
						}else{
							assert(object.creatureState.mode==CreatureMode.pretendingToDie);
							object.creatureState.mode=CreatureMode.playingDead;
							object.clearOrderQueue(state);
						}
						break;
					case CreatureMovement.flying:
						object.creatureState.movement=CreatureMovement.tumbling;
						object.creatureState.fallingVelocity=Vector3f(0.0f,0.0f,0.0f);
						object.setCreatureState(state);
						break;
					case CreatureMovement.tumbling:
						with(AnimationState)
						if(!sacObject.mustFly&&object.animationState.among(death0,death1,death2))
							goto case CreatureMovement.onGround;
						// continue tumbling
						break;
				}
			}
			break;
		case CreatureMode.preSpawning:
			break;
		case CreatureMode.spawning:
			assert(object.animationState==AnimationState.disoriented);
			// TODO: keep it stuck at frame 0 and make it transparent until casting finished.
			object.frame+=1;
			object.creatureState.movement=sacObject.mustFly?CreatureMovement.flying:CreatureMovement.onGround;
			if(!state.isOnGround(object.position)||state.getGroundHeight(object.position)<object.position.z){
				if(object.creatureState.movement!=CreatureMovement.flying){
					object.creatureState.movement=CreatureMovement.tumbling;
					object.frame=0;
					object.startIdling(state);
					break;
				}
			}else object.position.z=state.getGroundHeight(object.position);
			object.creatureState.mode=CreatureMode.idle;
			if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor){ // (just for robustness)
				object.frame=0;
				object.startIdling(state);
			}
			break;
		case CreatureMode.dead, CreatureMode.playingDead:
			with(AnimationState) assert(object.animationState.among(hitFloor,death0,death1,death2));
			assert(object.frame==sacObject.numFrames(object.animationState)*updateAnimFactor-1);
			if(object.creatureState.movement==CreatureMovement.tumbling&&object.creatureState.fallingVelocity.z<=0.0f){
				if(state.isOnGround(object.position)&&object.position.z+object.creatureState.fallingVelocity.z/updateFPS<=state.getGroundHeight(object.position))
					object.creatureState.movement=CreatureMovement.onGround;
			}
			if(object.creatureState.mode==CreatureMode.playingDead&&object.isGuardian)
				object.pretendToRevive(state);
			break;
		case CreatureMode.dissolving:
			object.creatureState.timer+=1;
			if(object.creatureState.timer==dissolutionDelay){
				playSoundAt("1ngi",object.id,state);
				// TODO: add particle effect
			}
			if(object.creatureState.timer>=dissolutionTime)
				state.removeLater(object.id);
			break;
		case CreatureMode.deadToGhost:
			object.frame+=1;
			auto progress=float(object.frame)/(sacObject.numFrames(object.animationState)*updateAnimFactor);
			state.setAlpha(object.id,(1.0f-progress)+ghostAlpha*progress,(1.0f-progress)+ghostEnergy*progress);
			if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor){
				object.creatureState.mode=CreatureMode.idleGhost;
				object.setCreatureState(state);
				object.animateGhostTransition(state);
			}
			break;
		case CreatureMode.ghostToIdle:
			object.frame+=1;
			auto progress=float(object.frame)/(sacObject.numFrames(object.animationState)*updateAnimFactor);
			state.setAlpha(object.id,ghostAlpha*(1.0f-progress)+progress,ghostEnergy*(1.0f-progress)+progress);
			if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor){
				object.creatureState.mode=CreatureMode.idle;
				object.setCreatureState(state);
				state.updateRenderModeLater(object.id);
			}
			break;
		case CreatureMode.reviving, CreatureMode.fastReviving:
			static immutable reviveSequence=[AnimationState.corpse,AnimationState.float_];
			auto reviveTime=cast(int)(object.creatureStats.reviveTime*updateFPS);
			auto fast=object.creatureState.mode!=CreatureMode.reviving;
			if(fast) reviveTime/=2;
			object.creatureState.timer+=1;
			object.creatureState.facing+=(fast?2.0f*pi!float:4.0f*pi!float)/reviveTime;
			while(object.creatureState.facing>pi!float) object.creatureState.facing-=2*pi!float;
			if(object.creatureState.timer<reviveTime/2){
				object.creatureState.movement=CreatureMovement.flying;
				object.position.z+=object.creatureStats.reviveHeight/(reviveTime/2);
			}
			object.rotation=facingQuaternion(object.creatureState.facing);
			if(object.creatureState.timer>=reviveTime){
				object.frame=0;
				if(object.soulId){
					state.removeLater(object.soulId);
					object.soulId=0;
				}
				if(sacObject.canFly) object.creatureState.targetFlyingHeight=0.0f;
				object.creatureState.movement=CreatureMovement.tumbling;
				object.creatureState.fallingVelocity=Vector3f(0.0f,0.0f,0.0f);
				object.startIdling(state);
				state.newCreatureAddToSelection(object.side,object.id);
			}else if(reviveSequence.canFind(object.animationState)){
				object.frame+=1;
				if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor){
					object.frame=0;
					object.pickNextAnimation(reviveSequence,state);
				}
			}
			break;
		case CreatureMode.pretendingToRevive:
			object.frame+=1;
			if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor){
				object.frame=0;
				object.creatureState.mode=CreatureMode.idle;
				object.setCreatureState(state);
			}
			break;
		case CreatureMode.takeoff:
			assert(sacObject.canFly);
			assert(object.creatureState.movement==CreatureMovement.onGround);
			object.frame+=1;
			if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor){
				object.frame=0;
				if(object.animationState==AnimationState.takeoff){
					object.creatureState.mode=sacObject.movingAfterTakeoff?CreatureMode.moving:CreatureMode.idle;
					object.creatureState.movement=CreatureMovement.flying;
				}
				object.setCreatureState(state);
			}
			break;
		case CreatureMode.landing:
			assert(sacObject.canFly&&!sacObject.mustFly);
			object.frame+=1;
			if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor){
				object.frame=0;
				object.setCreatureState(state);
			}
			break;
		case CreatureMode.meleeMoving,CreatureMode.meleeAttacking:
			object.frame+=1;
			if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor){
				object.frame=0;
				object.creatureState.mode=CreatureMode.idle;
				object.setCreatureState(state);
			}
			break;
		case CreatureMode.stunned:
			auto immobilized=object.creatureStats.effects.immobilized;
			with(AnimationState) assert(immobilized||object.isSacDoctor||object.animationState.among(stance1,knocked2Floor,falling,tumble,hitFloor,getUp,damageFront,damageRight,damageBack,damageLeft,damageTop,flyDamage));
			if(object.creatureState.movement==CreatureMovement.tumbling&&object.creatureState.fallingVelocity.z<=0.0f){
				if(sacObject.canFly && !immobilized){
					object.creatureState.movement=CreatureMovement.flying;
					object.frame=0;
					object.animationState=AnimationState.hover;
					object.startIdling(state);
					break;
				}else if(state.isOnGround(object.position)&&object.position.z+object.creatureState.fallingVelocity.z/updateFPS<=state.getGroundHeight(object.position)){
					object.creatureState.movement=CreatureMovement.onGround;
					if(object.animationState.among(AnimationState.falling,AnimationState.tumble)||immobilized){
						if(sacObject.hasHitFloor&&!immobilized&&
						   (!object.isSacDoctor||object.animationState==cast(AnimationState)SacDoctorAnimationState.expelled)
						){
							object.frame=0;
							object.animationState=AnimationState.hitFloor;
						}else object.startIdling(state);
						object.dealFallDamage(state);
					}else if(!object.animationState.among(AnimationState.knocked2Floor,AnimationState.getUp))
						object.startIdling(state);
					break;
				}
			}
			if(immobilized) break;
			object.frame+=1;
			if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor){
				object.frame=0;
				final switch(object.creatureState.movement){
					case CreatureMovement.onGround:
						if(object.animationState.among(AnimationState.knocked2Floor,AnimationState.hitFloor)&&sacObject.hasGetUp){
							object.animationState=AnimationState.getUp;
						}else if(!object.isSacDoctor||object.animationState==AnimationState.hitFloor)
							object.startIdling(state);
						break;
					case CreatureMovement.flying:
						object.startIdling(state);
						break;
					case CreatureMovement.tumbling:
						with(AnimationState)
							if(object.animationState.among(knocked2Floor,getUp,stance1,stance2,idle0,idle1,idle2,idle3))
								goto case CreatureMovement.onGround;
						// continue tumbling
						if(object.isSacDoctor){
							if(object.animationState==cast(AnimationState)SacDoctorAnimationState.expelled){
								object.frame=sacObject.numFrames(object.animationState)*updateAnimFactor-1;
							}
						}
						break;
				}
			}
			break;
		case CreatureMode.cower:
			object.frame+=1;
			if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor)
				object.setCreatureState(state);
			break;
		case CreatureMode.casting,CreatureMode.castingMoving:
			auto newMode=object.creatureState.movementDirection==MovementDirection.none||object.creatureStats.effects.fixed?CreatureMode.casting:CreatureMode.castingMoving;
			object.creatureState.mode=newMode;
			if(newMode==CreatureMode.castingMoving){
				if(object.animationState.among(AnimationState.spellcastStart,AnimationState.runSpellcastStart))
					object.animationState=AnimationState.runSpellcastStart;
				else if(object.animationState.among(AnimationState.spellcastEnd,AnimationState.runSpellcastEnd))
					object.animationState=AnimationState.runSpellcastEnd;
				else object.animationState=AnimationState.runSpellcast;
			}else{
				if(object.animationState.among(AnimationState.spellcastStart,AnimationState.runSpellcastStart))
					object.animationState=AnimationState.spellcastStart;
				else if(object.animationState.among(AnimationState.spellcastEnd,AnimationState.runSpellcastEnd))
					object.animationState=AnimationState.spellcastEnd;
				else object.animationState=AnimationState.spellcast;
			}
			goto Lcasting;
		case CreatureMode.stationaryCasting:
			if(object.animationState==AnimationState.spellcastEnd&&sacObject.castingTime(AnimationState.spellcastEnd)*updateAnimFactor<=object.frame){
				object.creatureState.mode=CreatureMode.casting;
				goto case CreatureMode.casting;
			}
		Lcasting:
			object.frame+=1;
			object.creatureState.timer-=slowdownFactor;
			object.creatureState.timer2-=1;
			if(object.creatureState.timer2<=0){
				if(object.animationState.among(AnimationState.spellcastEnd,AnimationState.runSpellcastEnd))
					object.creatureState.timer2=playSoundTypeAt!true(sacObject,object.id,SoundType.incantation,state,sacObject.castingTime(AnimationState.spellcastEnd)*updateAnimFactor-object.frame+updateFPS/2)+updateFPS/10;
				else object.creatureState.timer2=playSoundTypeAt!true(sacObject,object.id,SoundType.incantation,state)+updateFPS/10;
			}
			if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor){
				object.frame=0;
				if(object.animationState.among(AnimationState.spellcastEnd,AnimationState.runSpellcastEnd)){
					object.creatureState.mode=object.creatureState.mode==CreatureMode.castingMoving?CreatureMode.moving:CreatureMode.idle;
					object.setCreatureState(state);
					return;
				}
				if(object.animationState==AnimationState.spellcastStart)
					object.animationState=AnimationState.spellcast;
				else if(object.animationState==AnimationState.runSpellcastStart)
					object.animationState=AnimationState.runSpellcast;
				auto endAnimation=object.creatureState.mode==CreatureMode.castingMoving?AnimationState.runSpellcastEnd:AnimationState.spellcastEnd;
				if(sacObject.castingTime(endAnimation)*updateAnimFactor>=object.creatureState.timer)
					object.animationState=endAnimation;
			}
			break;
		case CreatureMode.shooting:
			object.frame+=1;
			if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor){
				object.frame=0;
				object.startIdling(state);
			}
			break;
		case CreatureMode.usingAbility:
			object.frame+=1;
			if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor){
				object.frame=0;
				object.startIdling(state);
				if(object.creatureAI.order.command==CommandType.useAbility) // TODO: handle shooting the same way?
					object.clearOrder(state);
			}
			break;
		case CreatureMode.pulling:
			object.frame+=1;
			if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor){
				object.frame=0;
				object.animationState=object.pullAnimation;
			}
			break;
		case CreatureMode.pumping:
			object.frame+=1;
			if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor){
				object.frame=0;
				object.animationState=cast(AnimationState)SacDoctorAnimationState.pumpCorpse;
			}
			break;
		case CreatureMode.torturing:
			object.frame+=1;
			if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor){
				object.frame=0;
				object.animationState=cast(AnimationState)SacDoctorAnimationState.torture;
			}
			break;
		case CreatureMode.convertReviving:
			break;
		case CreatureMode.thrashing:
			if(object.animationState.among(AnimationState.rise,AnimationState.corpseRise,AnimationState.thrash,AnimationState.float2Thrash,AnimationState.thrash))
				object.frame+=1;
			if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor){
				object.frame=0;
				if(object.animationState.among(AnimationState.rise,AnimationState.corpseRise)) object.animationState=AnimationState.float2Thrash;
				else if(object.animationState==AnimationState.float2Thrash) object.animationState=AnimationState.thrash;
				if(!object.sacObject.hasAnimationState(object.animationState)){
					object.animationState=AnimationState.thrash;
					if(!object.sacObject.hasAnimationState(object.animationState))
						object.animationState=AnimationState.stance1;
				}
			}
	}
}

alias CollisionTargetSide(bool active:true)=int;
alias CollisionTargetSide(bool active:false)=Seq!();
auto collisionTargetImpl(bool projectileFilter,bool attackFilter=false,bool returnHitbox=false,B)(int ownId,CollisionTargetSide!attackFilter side,Vector3f[2] hitbox,Vector3f[2] movedHitbox,ObjectState!B state){
	struct CollisionState{
		Vector3f[2] hitbox;
		int ownId;
		static if(attackFilter) int side;
		int target=0;
		static if(returnHitbox) Vector3f[2] targetHitbox;
		static if(attackFilter) int rank;
		float distanceSqr=float.infinity;
	}
	static void handleCollision(ProximityEntry entry,CollisionState* collisionState,ObjectState!B state){
		if(!entry.isObstacle) return;
		static if(projectileFilter) if(!entry.isProjectileObstacle) return;
		if(entry.id==collisionState.ownId) return;
		static if(attackFilter){
			auto validRank=state.objectById!((obj,state,side)=>tuple(obj.isValidAttackTarget(state),rank(state.sides.getStance(side,.side(obj,state)))))(entry.id,state,collisionState.side);
			auto valid=validRank[0], rank=validRank[1];
			if(!valid) return;
		}
		auto distanceSqr=meleeDistanceSqr(entry.hitbox,collisionState.hitbox);
		static if(attackFilter) auto pick=!collisionState.target||tuple(rank,distanceSqr)<tuple(collisionState.rank,collisionState.distanceSqr);
		else auto pick=!collisionState.target||distanceSqr<collisionState.distanceSqr;
		if(pick){
			collisionState.target=entry.id;
			static if(returnHitbox) collisionState.targetHitbox=entry.hitbox;
			static if(attackFilter) collisionState.rank=rank;
			collisionState.distanceSqr=distanceSqr;
		}
	}
	auto collisionState=CollisionState(hitbox,ownId,side);
	state.proximity.collide!handleCollision(movedHitbox,&collisionState,state);
	static if(returnHitbox) return tuple(collisionState.target,collisionState.targetHitbox);
	else return collisionState.target;
}
auto collisionTarget(bool projectileFilter=true,B)(int ownId,Vector3f[2] hitbox,Vector3f[2] movedHitbox,ObjectState!B state){
	return collisionTargetImpl!(projectileFilter,false,false,B)(ownId,hitbox,movedHitbox,state);
}
auto collisionTargetWithHitbox(bool projectileFilter=true,B)(int ownId,Vector3f[2] hitbox,Vector3f[2] movedHitbox,ObjectState!B state){
	return collisionTargetImpl!(projectileFilter,false,true,B)(ownId,hitbox,movedHitbox,state);
}
int meleeAttackTarget(bool projectileFilter=true,B)(int ownId,int side,Vector3f[2] hitbox,Vector3f[2] meleeHitbox,ObjectState!B state){
	return collisionTargetImpl!(projectileFilter,true,false,B)(ownId,side,hitbox,meleeHitbox,state);
}

int meleeAttackTarget(B)(ref MovingObject!B object,ObjectState!B state){
	auto hitbox=object.hitbox,meleeHitbox=object.meleeHitbox;
	return meleeAttackTarget(object.id,object.side,hitbox,meleeHitbox,state);
}

void updateCreatureStats(B)(ref MovingObject!B object, ObjectState!B state){
	if(object.isRegenerating) with(object.creatureStats){
		auto factor=maxMana==0.0f?1.0f:mana/maxMana;
		object.heal(factor*regeneration/updateFPS,state);
	}
	if(object.creatureState.mode==CreatureMode.playingDead)
		object.heal(30.0f/updateFPS,state); // TODO: ok?
	if(object.isGuardian)
		object.heal(1000.0f/(60*updateFPS),state);
	if(object.creatureState.mode.canRegenerateMana&&(object.creatureStats.mana<object.creatureStats.maxMana||object.isGhost))
		object.giveMana(state.manaRegenAt(object.side,object.position)/updateFPS,state);
	if(object.creatureState.mode.among(CreatureMode.meleeMoving,CreatureMode.meleeAttacking) && object.hasAttackTick(state)){
		object.creatureState.mode=CreatureMode.meleeAttacking;
		if(auto target=object.meleeAttackTarget(state)){ // TODO: factor this out into its own function?
			static void dealDamage(T)(ref T target,MovingObject!B* attacker,ObjectState!B state){
				target.dealMeleeDamage(*attacker,DamageMod.none,state); // TODO: maybe those functions should be local
			}
			state.objectById!dealDamage(target,&object,state);
			if(auto passive=object.sacObject.passiveAbility){
				if(passive.tag==SpellTag.graspingVines){
					auto tref=OrderTarget(state.targetTypeFromId(target),target,Vector3f.init);
					auto summary=summarize(tref,-1,state);
					if(passive.isApplicable(summary))
						graspingVines(target,passive,state);
				}
			}
		}
	}
}

enum gibDepth=0.5f*mapDepth;

void updateCreaturePosition(B)(ref MovingObject!B object, ObjectState!B state){
	auto newPosition=object.position;
	with(CreatureMode) if(object.creatureState.mode.among(idle,moving,idleGhost,movingGhost,stunned,landing,dying,meleeMoving,casting,castingMoving,shooting,usingAbility)){
		auto rotationSpeed=object.creatureStats.rotationSpeed(object.creatureState.movement==CreatureMovement.flying)/updateFPS;
		if(object.creatureStats.effects.slimed && object.creatureState.movementDirection!=MovementDirection.none)
			rotationSpeed*=0.25f^^object.creatureStats.effects.numSlimes;
		auto pitchingSpeed=object.creatureStats.pitchingSpeed/updateFPS;
		bool isRotating=false;
		if(object.creatureState.mode.among(idle,moving,idleGhost,movingGhost,meleeMoving,casting,castingMoving,torturing)&&
		   object.creatureState.movement!=CreatureMovement.tumbling&&!object.creatureStats.effects.immobilized&&!object.creatureStats.effects.fixed
		){
			final switch(object.creatureState.rotationDirection){
				case RotationDirection.none:
					break;
				case RotationDirection.left:
					isRotating=true;
					object.creatureState.facing+=min(rotationSpeed,object.creatureState.rotationSpeedLimit);
					while(object.creatureState.facing>pi!float) object.creatureState.facing-=2*pi!float;
					break;
				case RotationDirection.right:
					isRotating=true;
					object.creatureState.facing-=min(rotationSpeed,object.creatureState.rotationSpeedLimit);
					while(object.creatureState.facing<pi!float) object.creatureState.facing+=2*pi!float;
				break;
			}
			final switch(object.creatureState.pitchingDirection){
				case PitchingDirection.none:
					break;
				case PitchingDirection.up:
					isRotating=true;
					object.creatureState.flyingPitch+=min(pitchingSpeed,object.creatureState.pitchingSpeedLimit);
					object.creatureState.flyingPitch=min(object.creatureState.flyingPitch,object.creatureStats.pitchUpperLimit);
					break;
				case PitchingDirection.down:
					isRotating=true;
					object.creatureState.flyingPitch-=min(pitchingSpeed,object.creatureState.pitchingSpeedLimit);
					object.creatureState.flyingPitch=max(object.creatureState.flyingPitch,object.creatureStats.pitchLowerLimit);
				break;
			}
		}
		auto facing=facingQuaternion(object.creatureState.facing);
		auto newRotation=facing;
		if(object.creatureState.movement==CreatureMovement.onGround||
		   object.animationState.among(AnimationState.land,AnimationState.hitFloor)
		){
			final switch(object.sacObject.rotateOnGround){
				case RotateOnGround.no:
					break;
				case RotateOnGround.sideways:
					newRotation=newRotation*rotationQuaternion(Axis.y,-atan(state.getGroundHeightDerivative(object.position, rotate(facing, Vector3f(1.0f,0.0f,0.0f)))));
					break;
				case RotateOnGround.completely:
					newRotation=newRotation*rotationQuaternion(Axis.x,atan(state.getGroundHeightDerivative(object.position, rotate(facing, Vector3f(0.0f,1.0f,0.0f)))));
					newRotation=newRotation*rotationQuaternion(Axis.y,-atan(state.getGroundHeightDerivative(object.position, rotate(facing, Vector3f(1.0f,0.0f,0.0f)))));
					break;
			}
		}else newRotation=newRotation*pitchQuaternion(object.creatureState.flyingPitch);
		if(isRotating||object.creatureState.mode!=CreatureMode.idle||
		   object.creatureState.movement==CreatureMovement.flying||
		   object.creatureState.movement==CreatureMovement.tumbling){
			auto diff=newRotation*object.rotation.conj();
			if(!isRotating){
				if(object.creatureState.movement==CreatureMovement.flying){
					rotationSpeed/=5;
				}else rotationSpeed/=2;
			}else rotationSpeed*=1.1f; // TODO: make rotation along z direction independent of remaining rotations?
			object.rotation=(limitRotation(diff,rotationSpeed)*object.rotation).normalized;
		}
	}
	auto facing=facingQuaternion(object.creatureState.facing);
	final switch(object.creatureState.movement){
		case CreatureMovement.onGround:
			if(object.creatureStats.effects.immobilized||object.creatureStats.effects.fixed){
				if(state.isOnGround(newPosition)){
					auto height=state.getGroundHeight(newPosition);
					if(newPosition.z<=height)
						newPosition.z=height;
				}
				break;
			}
			auto groundSpeed=object.speedOnGround(state);
			auto groundAcceleration=object.accelerationOnGround(state);
			final switch(object.creatureState.mode.isMoving?object.creatureState.movementDirection:MovementDirection.none){
				case MovementDirection.none:
					object.creatureState.speed=sign(object.creatureState.speed)*(max(0.0f,abs(object.creatureState.speed)-groundAcceleration/updateFPS));
					break;
				case MovementDirection.forward:
					object.creatureState.speed=min(groundSpeed,object.creatureState.speed+groundAcceleration/updateFPS);
					break;
				case MovementDirection.backward:
					object.creatureState.speed=max(-groundSpeed,object.creatureState.speed-groundAcceleration/updateFPS);
					break;
			}
			auto direction=rotate(facingQuaternion(object.creatureState.facing), Vector3f(0.0f,1.0f,0.0f));
			auto speed=object.creatureState.speed/updateFPS;
			auto derivative=state.getGroundHeightDerivative(object.position,direction);
			Vector3f newDirection=direction;
			if(derivative>0.0f){
				newDirection=Vector3f(direction.x,direction.y,derivative).normalized;
			}else if(derivative<0.0f){
				newDirection=Vector3f(direction.x,direction.y,derivative);
				auto maxFactor=object.creatureStats.maxDownwardSpeedFactor;
				if(newDirection.lengthsqr>maxFactor*maxFactor) newDirection=maxFactor*newDirection.normalized;
			}
			auto velocity=newDirection*speed;
			newPosition=state.moveOnGround(object.position,velocity);
			break;
		case CreatureMovement.flying:
			if(object.creatureStats.effects.immobilized){
				object.startTumbling(state);
				goto case CreatureMovement.tumbling;
			}
			if(object.creatureStats.effects.fixed) break;
			auto targetFlyingHeight=object.creatureState.targetFlyingHeight;
			if(object.creatureState.mode.among(CreatureMode.landing,CreatureMode.idle)
			   ||object.creatureState.mode==CreatureMode.meleeAttacking&&object.position.z-state.getHeight(object.position)>targetFlyingHeight
			){
				auto height=state.getHeight(newPosition);
				if(newPosition.z>height+(isNaN(targetFlyingHeight)?0.0f:targetFlyingHeight)){
					auto downwardSpeed=object.creatureState.mode==CreatureMode.landing?object.creatureStats.landingSpeed/updateFPS:object.creatureStats.downwardHoverSpeed/updateFPS;
					newPosition.z-=downwardSpeed;
				}
				if(state.isOnGround(newPosition)){
					if(newPosition.z<=height)
						newPosition.z=height;
				}
				if(object.creatureState.mode==CreatureMode.idle&&!isNaN(targetFlyingHeight)){
					if(newPosition.z<height+targetFlyingHeight){
						auto upwardSpeed=object.creatureStats.upwardHoverSpeed/updateFPS;
						newPosition.z+=upwardSpeed;
					}
				}
				break;
			}
			auto airSpeed=object.speedInAir(state);
			auto airAcceleration=object.accelerationInAir(state);
			final switch(object.creatureState.mode.isMoving?object.creatureState.movementDirection:MovementDirection.none){
				case MovementDirection.none:
					object.creatureState.speed=sign(object.creatureState.speed)*(max(0.0f,abs(object.creatureState.speed)-airAcceleration/updateFPS));
					break;
				case MovementDirection.forward:
					object.creatureState.speed=min(airSpeed,object.creatureState.speed+airAcceleration/updateFPS);
					break;
				case MovementDirection.backward:
					assert(object.sacObject.canFlyBackward);
					object.creatureState.speed=max(-airSpeed,object.creatureState.speed-airAcceleration/updateFPS);
					break;
			}
			auto direction=rotate(object.rotation,Vector3f(0.0f,1.0f,0.0f));
			auto speed=object.creatureState.speed/updateFPS;
			newPosition=object.position+speed*direction;
			auto newHeight=state.getHeight(newPosition), upwardSpeed=0.0f;
			auto flyingHeight=newPosition.z-newHeight;
			if(targetFlyingHeight!is float.nan){
				if(flyingHeight<targetFlyingHeight){
					auto speedLimit=object.creatureStats.takeoffSpeed/updateFPS;
					upwardSpeed=min(targetFlyingHeight-flyingHeight,speedLimit);
				}else{
					auto speedLimit=object.creatureStats.downwardHoverSpeed/updateFPS;
					upwardSpeed=-min(flyingHeight-targetFlyingHeight,speedLimit);
				}
			}
			auto onGround=state.isOnGround(newPosition);
			if(onGround&&flyingHeight<0.0f) upwardSpeed=max(upwardSpeed,-flyingHeight);
			auto upwardFactor=object.creatureStats.upwardFlyingSpeedFactor;
			auto downwardFactor=object.creatureStats.downwardFlyingSpeedFactor;
			auto newDirection=Vector3f(direction.x,direction.y,direction.z+upwardSpeed).normalized;
			speed*=sqrt(newDirection.x^^2+newDirection.y^^2+(newDirection.z*(newDirection.z>0?upwardFactor:downwardFactor))^^2);
			auto velocity=speed*newDirection;
			newPosition=object.position+velocity;
			if(onGround){
				// TODO: improve? original engine does this, but it can cause ultrafast ascending for flying creatures
				newPosition.z=max(newPosition.z,newHeight);
			}
			break;
		case CreatureMovement.tumbling:
			if(object.creatureStats.effects.antiGravityTime<state.frame)
				object.creatureState.fallingVelocity.z-=object.creatureStats.fallingAcceleration/updateFPS;
			enum speedCap=20.0f; // TODO: figure out constant
			if(object.creatureState.fallingVelocity.lengthsqr>speedCap^^2) object.creatureState.fallingVelocity=object.creatureState.fallingVelocity.normalized*speedCap;
			if(object.creatureStats.effects.fixed) break;
			newPosition=object.position+object.creatureState.fallingVelocity/updateFPS;
			if(state.isOnGround(newPosition))
				newPosition.z=max(newPosition.z,state.getGroundHeight(newPosition));
			break;
	}
	auto proximity=state.proximity;
	auto relativeHitbox=object.relativeHitbox;
	Vector3f[2] hitbox=[relativeHitbox[0]+newPosition,relativeHitbox[1]+newPosition];
	bool posChanged=false, needsFixup=false, isColliding=false;
	auto fixupDirection=Vector3f(0.0f,0.0f,0.0f);
	void handleCollision(bool fixup)(ProximityEntry entry){
		if(!entry.isObstacle) return;
		if(entry.id==object.id) return;
		isColliding=true;
		enum CollisionDirection{ // which face of obstacle's hitbox was hit
			left,
			right,
			back,
			front,
			bottom,
			top,
		}
		auto collisionDirection=CollisionDirection.left;
		auto minOverlap=hitbox[1].x-entry.hitbox[0].x;
		auto cand=entry.hitbox[1].x-hitbox[0].x;
		if(cand<minOverlap||cand==minOverlap&&state.uniform(2)){
			minOverlap=cand;
			collisionDirection=CollisionDirection.right;
		}
		cand=hitbox[1].y-entry.hitbox[0].y;
		if(cand<minOverlap||cand==minOverlap&&state.uniform(2)){
			minOverlap=cand;
			collisionDirection=CollisionDirection.back;
		}
		cand=entry.hitbox[1].y-hitbox[0].y;
		if(cand<minOverlap||cand==minOverlap&&state.uniform(2)){
			minOverlap=cand;
			collisionDirection=CollisionDirection.front;
		}
		final switch(object.creatureState.movement){
			case CreatureMovement.onGround:
				break;
			case CreatureMovement.flying:
				if(object.creatureState.mode==CreatureMode.landing) break;
				cand=hitbox[1].z-entry.hitbox[0].z;
				if(cand<minOverlap||cand==minOverlap&&state.uniform(2)){
					minOverlap=cand;
					collisionDirection=CollisionDirection.bottom;
				}
				cand=entry.hitbox[1].z-hitbox[0].z;
				if(cand<minOverlap||cand==minOverlap&&state.uniform(2)){
					minOverlap=cand;
					collisionDirection=CollisionDirection.top;
				}
				break;
			case CreatureMovement.tumbling:
				static if(!fixup){
					cand=entry.hitbox[1].z-hitbox[0].z;
					if(cand<minOverlap||cand==minOverlap&&state.uniform(2))
						object.creatureState.fallingVelocity.z=0.0f;
				}
				object.creatureState.fallingVelocity.x=object.creatureState.fallingVelocity.y=0.0f;
				break;
		}
		final switch(collisionDirection){
			case CollisionDirection.left:
				static if(fixup) fixupDirection.x-=minOverlap;
				else newPosition.x=min(newPosition.x,object.position.x);
				break;
			case CollisionDirection.right:
				static if(fixup) fixupDirection.x+=minOverlap;
				else newPosition.x=max(newPosition.x,object.position.x);
				break;
			case CollisionDirection.back:
				static if(fixup) fixupDirection.y-=minOverlap;
				else newPosition.y=min(newPosition.y,object.position.y);
				break;
			case CollisionDirection.front:
				static if(fixup) fixupDirection.y+=minOverlap;
				else newPosition.y=max(newPosition.y,object.position.y);
				break;
			case CollisionDirection.bottom:
				static if(fixup) fixupDirection.z-=minOverlap;
				else newPosition.z=min(newPosition.z,object.position.z);
				break;
			case CollisionDirection.top:
				static if(fixup) fixupDirection.z+=minOverlap;
				else newPosition.z=max(newPosition.z,object.position.z);
				break;
		}
		static if(!fixup) posChanged=true;
		else needsFixup=true;
	}
	if(!object.creatureState.mode.among(CreatureMode.dead,CreatureMode.dissolving,CreatureMode.convertReviving,CreatureMode.thrashing)){ // dead creatures do not participate in collision handling
		proximity.collide!(handleCollision!false)(hitbox);
		object.creatureAI.isColliding=isColliding;
		hitbox=[relativeHitbox[0]+newPosition,relativeHitbox[1]+newPosition];
		proximity.collide!(handleCollision!true)(hitbox);
		if(needsFixup){
			auto fixupSpeed=object.creatureStats.collisionFixupSpeed/updateFPS;
			if(fixupDirection.length>fixupSpeed)
				fixupDirection=fixupDirection.normalized*object.creatureStats.collisionFixupSpeed/updateFPS;
			final switch(object.creatureState.movement){
				case CreatureMovement.onGround:
					if(state.isOnGround(newPosition)) newPosition=state.moveOnGround(newPosition,fixupDirection);
					break;
				case CreatureMovement.flying, CreatureMovement.tumbling:
					newPosition+=fixupDirection;
					break;
			}
			posChanged=true;
		}
	}
	bool onGround=state.isOnGround(newPosition);
	auto height=state.getHeight(newPosition);
	if(!onGround&&newPosition.z<height-gibDepth){
		auto tpId=0;
		if(object.isWizard)
			if(auto wiz=state.getWizard(object.id))
				tpId=wiz.closestAltar;
		if(tpId!=0){
			auto targetPosition=getTeleportPosition(newPosition,tpId,wizardAltarDistance,state);
			if(isNaN(targetPosition.x)) tpId=0;
			object.teleport(targetPosition,state,true);
			newPosition=object.position;
		}
		if(tpId==0) object.gib(state,-2);
	}			// TODO: improve? original engine does this, but it can cause ultrafast ascending for flying creatures
	if(object.creatureState.movement!=CreatureMovement.onGround||onGround){
		if(posChanged){
			final switch(object.creatureState.movement){
				case CreatureMovement.onGround:
					newPosition.z=height;
					break;
				case CreatureMovement.flying, CreatureMovement.tumbling:
					if(onGround) newPosition.z=max(newPosition.z,height);
					break;
			}
		}
		if(!object.creatureStats.effects.fixed) object.position=newPosition;
	}
	if(object.creatureStats.effects.fixed){
		height=state.getHeight(object.position);
		if(!isNaN(object.creatureState.targetFlyingHeight))
			object.position.z=max(object.position.z,height+object.creatureState.targetFlyingHeight); // TODO: ok?
		if(object.position.z>height && object.creatureState.movement==CreatureMovement.onGround){
			object.creatureState.fallingVelocity=Vector3f(0.0f,0.0f,0.0f);
			object.creatureState.movement=CreatureMovement.tumbling;
			object.setCreatureState(state);
		}
	}
}

void updateCreature(B)(ref MovingObject!B object, ObjectState!B state){
	object.updateCreatureAI(state);
	object.updateCreatureState(state);
	object.updateCreaturePosition(state);
	object.updateCreatureStats(state);
}

bool canCollectSouls(B)(ref MovingObject!B object){
	return object.isWizard&&object.creatureState.mode.canCollectSouls&&object.health!=0.0f;
}

enum soulVanishDepth=mapDepth;
enum soulFallSpeed=1.0f;
void updateSoul(B)(ref Soul!B soul, ObjectState!B state){
	soul.frame+=1;
	soul.facing+=2*pi!float/8.0f/updateFPS;
	while(soul.facing>pi!float) soul.facing-=2*pi!float;
	if(soul.frame==SacSoul!B.numFrames*updateAnimFactor)
		soul.frame=0;
	if(soul.state!=SoulState.collecting){
		if(!soul.creatureId){
			auto height=state.getHeight(soul.position);
			if(soul.position.z>height||!state.isOnGround(soul.position)){
				if(soul.position.z+soulVanishDepth<height+soulFallSpeed){
					if(soul.position.z+soulVanishDepth<height){
						state.removeLater(soul.id);
						return;
					}
				}
				soul.position.z-=soulFallSpeed/updateFPS;
			}else soul.position.z=height;
		}else soul.position=state.movingObjectById!(soulPosition,()=>Vector3f(float.nan,float.nan,float.nan))(soul.creatureId);
	}
	final switch(soul.state){
		case SoulState.normal:
			static struct State{
				int collector=0;
				int side=-1;
				float distancesqr=float.infinity;
				bool tied=false;
			}
			enum collectDistance=4.0f; // TODO: measure this
			enum preferredBonus=3.0f; // TODO: measure this?
			static void process(B)(ref WizardInfo!B wizard,Soul!B* soul,State* pstate,ObjectState!B state){ // TODO: use proximity data structure?
				auto sidePositionValid=state.movingObjectById!((obj)=>tuple(obj.side,obj.center,obj.canCollectSouls),()=>Tuple!(int,Vector3f,bool).init)(wizard.id);
				auto side=sidePositionValid[0],position=sidePositionValid[1],valid=sidePositionValid[2];
				if(!valid) return;
				if((soul.position.xy-position.xy).lengthsqr>collectDistance^^2) return;
				if(abs(soul.position.z-position.z)>collectDistance) return;
				auto distancesqr=(soul.position-position).lengthsqr;
				if(soul.preferredSide!=-1&&side!=soul.preferredSide){
					if(soul.creatureId) return;
					distancesqr+=preferredBonus;
				}
				if(distancesqr>pstate.distancesqr) return;
				if(distancesqr==pstate.distancesqr){ pstate.tied=true; return; }
				*pstate=State(wizard.id,side,distancesqr,false);
			}
			State pstate;
			state.eachWizard!process(&soul,&pstate,state);
			if(pstate.collector&&!pstate.tied){
				if(soul.creatureId==0) soul.preferredSide=-1;
				soul.collectorId=pstate.collector;
				soul.state=SoulState.collecting;
				playSoundAt("rips",soul.collectorId,state,2.0f);
				if(auto wizard=state.getWizard(soul.collectorId))
					wizard.souls+=soul.number;
				soul.severSoul(state);
			}
			break;
		case SoulState.emerging:
			soul.scaling+=(1.0f/3.0f)/updateFPS;
			if(soul.scaling>=1.0f){
				soul.scaling=1.0f;
				soul.state=SoulState.normal;
			}
			break;
		case SoulState.reviving:
			assert(soul.creatureId!=0);
			soul.scaling-=2.0f/updateFPS;
			if(soul.scaling<=0.0f)
				soul.scaling=0.0f;
			break;
		case SoulState.collecting,SoulState.devouring:
			assert(soul.collectorId!=0);
			auto previousScaling=soul.scaling;
			soul.scaling-=soul.state==SoulState.collecting?4.0f/updateFPS:3.0f/updateFPS;
			// TODO: how to do this more nicely?
			auto factor=soul.scaling/previousScaling;
			Vector3f targetPosition;
			if(soul.state==SoulState.collecting)
				targetPosition=state.movingObjectById!((wiz)=>wiz.center+Vector3f(0.0f,0.0f,0.5f),()=>soul.position)(soul.collectorId);
			else targetPosition=state.movingObjectById!((wiz)=>wiz.shotPosition,()=>soul.position)(soul.collectorId);
			soul.position=factor*soul.position+(1.0f-factor)*targetPosition;
			if(soul.scaling<=0.0f){
				soul.scaling=0.0f;
				state.removeLater(soul.id);
				soul.number=0;
			}
			break;
	}
}

void updateParticles(B,bool relative,bool sideFiltered)(ref Particles!(B,relative,sideFiltered) particles, ObjectState!B state){
	if(!particles.sacParticle) return;
	auto sacParticle=particles.sacParticle;
	auto gravity=sacParticle.gravity;
	for(int j=0;j<particles.length;){
		if(particles.lifetimes[j]<=0){
			particles.removeParticle(j);
			continue;
		}
		scope(success) j++;
		particles.lifetimes[j]-=1;
		particles.frames[j]+=1;
		if(particles.frames[j]>=sacParticle.numFrames){
			particles.frames[j]=0;
		}
		particles.positions[j]+=particles.velocities[j]/updateFPS;
		if(gravity) particles.velocities[j].z-=15.0f/updateFPS;
	}
	if(sacParticle.bumpOffGround){
		enum eps=1e-3f;
		for(int j=0;j<particles.length;j++){
			if(state.isOnGround(particles.positions[j])){
				auto height=state.getGroundHeight(particles.positions[j]);
				if(particles.positions[j].z<height){
					particles.positions[j].z=2.0f*height-particles.positions[j].z;
					particles.velocities[j].z*=-1.0f;
				}
			}
		}
	}
}

enum debrisFallLimit=1000.0f;
bool updateDebris(B)(ref Debris!B debris,ObjectState!B state){
	auto oldPosition=debris.position;
	debris.position+=debris.velocity/updateFPS;
	debris.velocity.z-=30.0f/updateFPS;
	debris.rotation=debris.rotationUpdate*debris.rotation;
	if(state.isOnGround(debris.position)){
		auto height=state.getGroundHeight(debris.position);
		if(height>debris.position.z){
			if(height>debris.position.z+5.0f)
				return false;
			debris.position.z=height;
			debris.velocity.z*=-0.2f;
			if(debris.velocity.z<1.0f)
				return false;
		}
	}else if(debris.position.z<state.getHeight(debris.position)-debrisFallLimit)
		return false;
	enum numParticles=3;
	auto sacParticle=SacParticle!B.get(ParticleType.firy);
	auto velocity=Vector3f(0.0f,0.0f,0.0f);
	auto scale=1.0f;
	auto lifetime=sacParticle.numFrames-1;
	auto frame=0;
	foreach(i;0..numParticles){
		auto position=oldPosition*((cast(float)numParticles-1-i)/(numParticles-1))+debris.position*(cast(float)i/(numParticles-1));
		position+=0.1f*state.uniformDirection();
		state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
	}
	return true;
}
bool updateExplosion(B)(ref Explosion!B explosion,ObjectState!B state){
	with(explosion){
		frame+=1;
		if(frame>=32) frame=0;
		scale+=expansionSpeed/updateFPS;
		return scale<maxScale;
	}
}

void spawnFireParticles(B,T)(ref T object,int numParticles,ObjectState!B state){
	enum isMoving=is(T==MovingObject!B);
	static if(isMoving) auto hitbox=object.relativeHitbox;
	else auto hitbox=object.hitbox;
	auto dim=hitbox[1]-hitbox[0];
	auto volume=dim.x*dim.y*dim.z;
	auto scale=2.0f*max(1.0f,cbrt(volume));
	auto sacParticle=SacParticle!B.get(ParticleType.fire);
	foreach(i;0..numParticles){
		auto position=state.uniform(scaleBox(hitbox,1.1f));
		auto distance=(state.uniform(3)?state.uniform(0.3f,0.6f):state.uniform(1.5f,2.5f))*(hitbox[1].z-hitbox[0].z);
		auto fullLifetime=sacParticle.numFrames/float(updateFPS);
		auto lifetime=cast(int)(sacParticle.numFrames*state.uniform(0.0f,1.0f));
		auto velocity=Vector3f(0.0f,0.0f,distance/fullLifetime);
		static if(isMoving) state.addParticle(Particle!(B,true)(sacParticle,object.id,true,position,velocity,scale,lifetime,0));
		else state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,0));
	}
}

bool updateFire(B)(ref Fire!B fire,ObjectState!B state){
	with(fire){
		if(!state.targetTypeFromId(target).among(TargetType.creature,TargetType.building))
			return false;
		if(rangedDamagePerFrame>0.0f||spellDamagePerFrame>0.0f)
			state.objectById!dealFireDamage(target,rangedDamagePerFrame,spellDamagePerFrame,attacker,side,damageMod,state);
		if(manaDrainPerFrame>0.0f) state.movingObjectById!(drainMana,(){})(target,manaDrainPerFrame,state);
		static assert(updateFPS==60);
		enum numParticles=5;
		state.objectById!spawnFireParticles(target,numParticles,state);
		return lifetime-->0;
	}
}
enum CastingStatus{
	underway,
	interrupted,
	finished,
}
CastingStatus castStatus(B)(ref MovingObject!B wizard,ObjectState!B state){
	with(wizard){
		if(!creatureState.mode.isCasting) return CastingStatus.interrupted;
		if(animationState.among(AnimationState.spellcastEnd,AnimationState.runSpellcastEnd)&&frame+1>=sacObject.castingTime(wizard.animationState)*updateAnimFactor)
			return CastingStatus.finished;
		return CastingStatus.underway;
	}
}
CastingStatus update(B)(ref ManaDrain!B manaDrain,ObjectState!B state){
	manaDrain.timer-=1;
	return state.movingObjectById!((ref wizard,manaDrain,state){
		if(manaDrain.timer>=0) wizard.creatureStats.mana=max(0.0f,wizard.creatureStats.mana-manaDrain.manaCostPerFrame);
		return wizard.castStatus(state);
	},function CastingStatus(){ return CastingStatus.interrupted; })(manaDrain.wizard,manaDrain,state);
}
bool updateManaDrain(B)(ref ManaDrain!B manaDrain,ObjectState!B state){
	final switch(manaDrain.update(state)){
		case CastingStatus.underway: return manaDrain.timer>0;
		case CastingStatus.interrupted, CastingStatus.finished: return false;
	}
}
bool updateBuildingDestruction(B)(ref BuildingDestruction buildingDestruction,ObjectState!B state){
	if(state.buildingById!((ref building,state){
		int newLength=0;
		foreach(i,id;building.componentIds.data){
			state.removeLater(id);
			auto destroyed=building.bldg.components[i].destroyed;
			if(destroyed!="\0\0\0\0"){
				auto destObj=SacObject!B.getBLDG(destroyed);
				auto positionRotationScaleFlags=state.staticObjectById!((ref StaticObject!B object)=>tuple(object.position,object.rotation,object.scale,object.flags),()=>Tuple!(Vector3f,Quaternionf,float,int).init)(id);
				if(!isNaN(positionRotationScaleFlags[2]))
					building.componentIds[newLength++]=state.addObject(StaticObject!B(destObj,building.id,positionRotationScaleFlags.expand));
			}
			state.staticObjectById!((ref StaticObject!B object,state){
				auto destruction=building.bldg.components[i].destruction;
				destructionAnimation(destruction,object.center,state);
			},(){})(id,state);
		}
		building.componentIds.length=newLength;
		if(building.base) state.buildingById!(freeManafount,(){})(building.base,state);
		return newLength==0;
	},()=>false)(buildingDestruction.id,state)){
		state.removeObject(buildingDestruction.id);
	}
	return false;
}
bool updateGhostKill(B)(ref GhostKill ghostKill,ObjectState!B state){
	return state.movingObjectById!((ref wizard,state){
		if(wizard.creatureState.mode.among(CreatureMode.idleGhost,CreatureMode.movingGhost))
			wizard.unghost(state);
		if(!wizard.isGhost) wizard.kill(state);
		return true;
	},()=>false)(ghostKill.id,state);
}

void animateCreatureCasting(B)(ref MovingObject!B wizard,SacSpell!B spell,ObjectState!B state){
	auto god=spell.god;
	if(god==God.none) god=state.getCurrentGod(state.getWizard(wizard.id));
	if(god==God.none) god=God.persephone;
	wizard.animateCastingForGod(god,state);
}

bool updateCreatureCasting(B)(ref CreatureCasting!B creatureCast,ObjectState!B state){
	with(creatureCast){
		final switch(manaDrain.update(state)){
			case CastingStatus.underway:
				state.movingObjectById!(animateCreatureCasting,(){})(manaDrain.wizard,spell,state);
				// TODO: add rotating particles around creature position
				return true;
			case CastingStatus.interrupted:
				stopSoundsAt(creature,state);
				state.removeObject(creatureCast.creature);
				return false;
			case CastingStatus.finished:
				stopSoundsAt(creature,state);
				state.setRenderMode!(MovingObject!B,RenderMode.opaque)(creature);
				auto wizard=state.getWizard(manaDrain.wizard);
				if(!wizard||wizard.souls<spell.soulCost) goto case CastingStatus.interrupted;
				wizard.souls-=spell.soulCost;
				state.movingObjectById!((ref obj,state){
					obj.creatureState.mode=CreatureMode.spawning;
					state.newCreatureAddToSelection(obj.side,obj.id);
				},function(){})(creature,state);
				return false;
		}
	}
}

void animateStructureCasting(B)(ref StructureCasting!B structureCast,ObjectState!B state){
	with(structureCast){
		auto thresholdZ=-structureCastingGradientSize+(buildingHeight+structureCastingGradientSize)*currentFrame/castingTime;
		state.buildingById!((ref bldg,thresholdZ,state){
			foreach(cid;bldg.componentIds){
				state.setThresholdZ(cid,thresholdZ);
				if(currentFrame+0.5f*updateFPS<castingTime){
					auto pos=state.staticObjectById!((obj)=>obj.position,function Vector3f(){ assert(0); })(cid);
					pos.z+=thresholdZ-0.5f*structureCastingGradientSize*currentFrame/castingTime;
					foreach(i;0..state.uniform(1,6)){
						auto position=pos;
						position.z+=state.uniform(0.0f,structureCastingGradientSize);
						auto scale=state.uniform(0.875f,1.125f);
						state.addEffect(BlueRing!B(position,scale,state.uniform(64)));
					}
				}
			}
			// TODO: add ground particle effects around building
		},(){})(building,thresholdZ,state);
		state.movingObjectById!(animateCastingForGod,(){})(manaDrain.wizard,god,state);
		// TODO: add ground particle effects around wizard
	}
}

enum structureCastingGradientSize=2.0f;
bool updateStructureCasting(B)(ref StructureCasting!B structureCast,ObjectState!B state){
	with(structureCast){
		final switch(manaDrain.update(state)){
			case CastingStatus.underway:
				currentFrame+=1;
				structureCast.animateStructureCasting(state);
				auto position=state.buildingById!((ref bldg,state)=>state.staticObjectById!((ref obj)=>obj.position,()=>Vector3f.init)(bldg.componentIds[0]),()=>Vector3f.init)(building,state);
				if(!isNaN(position.x)) pushAll(position,5.0f,15.0f,5.0f,state);
				return true;
			case CastingStatus.interrupted:
				state.buildingById!(destroy,(){})(building,state);
				return false;
			case CastingStatus.finished:
				state.setRenderMode!(Building!B,RenderMode.opaque)(building);
				auto wizard=state.getWizard(manaDrain.wizard);
				if(!wizard||wizard.souls<spell.soulCost) goto case CastingStatus.interrupted;
				wizard.souls-=spell.soulCost;
				state.buildingById!((ref building,state){
					building.activate(state);
					building.flags&=~Flags.cannotDamage;
			},function(){})(building,state); return false;
		}
	}
}
bool updateBlueRing(B)(ref BlueRing!B blueRing,ObjectState!B state){
	with(blueRing){
		frame+=1;
		scale-=1.0f/updateFPS;
		if(scale<=0) return false;
		return true;
	}
}

void animateGuardianCasting(B)(ref MovingObject!B wizard,ObjectState!B state){
	auto castParticle=SacParticle!B.get(ParticleType.heal);
	wizard.animateCasting!false(castParticle,state);
}
bool updateGuardianCasting(B)(ref GuardianCasting!B guardianCast,ObjectState!B state){
	with(guardianCast){
		final switch(manaDrain.update(state)){
			case CastingStatus.underway:
				state.movingObjectById!(animateGuardianCasting,(){})(manaDrain.wizard,state);
				return true;
			case CastingStatus.interrupted: return false;
			case CastingStatus.finished:
				int side=state.movingObjectById!(.side,()=>-1)(manaDrain.wizard,state);
				if(side!=-1) guardian(side,spell,creature,state);
				return false;
		}
	}
}
bool unguardian(B)(ref Guardian guardian,ObjectState!B state){
	return state.movingObjectById!((ref obj,state){
		if(!obj.creatureStats.effects.isGuardian) return false;
		obj.creatureStats.effects.isGuardian=false;
		return true;
	},()=>false)(guardian.creature,state)
		& state.buildingById!((ref bldg,creature,state){
		for(int j=0;j<bldg.guardianIds.length;j++){
			if(bldg.guardianIds[j]==creature){
				if(j+1<bldg.guardianIds.length)
					swap(bldg.guardianIds[j],bldg.guardianIds[$-1]);
				bldg.guardianIds.length=bldg.guardianIds.length-1;
				return true;
			}
		}
		return false;
	},()=>false)(guardian.building,guardian.creature,state);
}

bool updateGuardianShape(B)(ref Guardian guardian,ObjectState!B state){
	with(guardian){
		if(frame%numFramesToChangeShape==0){
			prevLocs=nextLocs;
			static immutable Vector3f[2] box=[-locRadius*0.5f*Vector3f(1.0f,1.0f,1.0f),locRadius*0.5f*Vector3f(1.0f,1.0f,1.0f)];
			foreach(i,ref x;nextLocs){
				x=state.uniform(box);
				if(i==0||i+1==nextLocs.length) x*=0.25f;
			}
			if(isNaN(prevLocs[0].x)) updateGuardianShape(guardian, state);
		}
		float progress=float(frame%numFramesToChangeShape)/numFramesToChangeShape;
		foreach(i,ref x;locations) x=(1.0f-progress)*prevLocs[i]+progress*nextLocs[i];
		frame+=1;
		return true;
	}
}

enum manalithGuardHeight=15.0f;
enum shrineGuardHeight=2.5f;
Vector3f guardianAttachPosition(B)(ref Building!B building,ObjectState!B state){
	if(building.componentIds.length==0) return Vector3f.init;
	if(building.isManalith) return state.staticObjectById!((ref obj)=>obj.position+Vector3f(0.0f,0.0f,manalithGuardHeight),()=>Vector3f.init)(building.componentIds[0]);
	return state.staticObjectById!((ref obj)=>obj.position+Vector3f(0.0f,0.0f,shrineGuardHeight),()=>Vector3f.init)(building.componentIds[0]);
}

bool isValidGuard(B)(ref MovingObject!B obj,ObjectState!B state){
	return !obj.isDying&&!obj.isDead&&obj.creatureState.mode!=CreatureMode.thrashing;
}

bool updateGuardian(B)(ref Guardian guardian,ObjectState!B state){
	with(guardian){
		if(!updateGuardianShape(guardian,state)) return false;
		auto creaturePosition=state.movingObjectById!(center,()=>Vector3f.init)(creature);
		auto buildingPosition=state.buildingById!(guardianAttachPosition,()=>Vector3f.init)(building,state);

		if(isNaN(creaturePosition.x)||isNaN(buildingPosition.x)){
			unguardian(guardian,state);
			return false;
		}
		if((creaturePosition.xy-buildingPosition.xy).lengthsqr>50.0f^^2){
			auto dir2d=(creaturePosition.xy-buildingPosition.xy).normalized;
			auto position2d=buildingPosition.xy+20.0f*dir2d;
			auto position=Vector3f(position2d.x,position2d.y,0.0f);
			position.z=state.getHeight(position);
			auto facing=atan2(dir2d.x,-dir2d.y);
			auto order=Order(CommandType.move,OrderTarget(TargetType.terrain,0,position),facing);
			state.movingObjectById!((ref obj,order,state){
				if(obj.creatureAI.order.command==CommandType.move&&(obj.creatureAI.order.target.position.xy-buildingPosition.xy).length<50.0f)
					return true;
				return obj.order(order,state);
			},()=>false)(creature,order,state);
		}
		with(GuardianStatus) if(status.among(disappearingAtBuilding,disappearingAtCreature)&&frame==numFramesToDisappear){
			unguardian(guardian,state);
			return false;
		}
		if(state.movingObjectById!((ref obj,state)=>!obj.isValidGuard(state),()=>true)(creature,state)){
			switch(status) with(GuardianStatus){
				case appearing:
					unguardian(guardian,state);
					return false;
				case steady:
					status=status.disappearingAtBuilding;
					frame=1;
					break;
				default: break;
			}
		}
		// TODO: bind creature to building
		final switch(status) with(GuardianStatus){
			case appearing:
				if(frame==numFramesToEmerge){
					status=steady;
					goto case steady;
				}
				float progress=(float(frame)/numFramesToEmerge)^^3;
				start=creaturePosition;
				end=(1.0f-progress)*creaturePosition+progress*buildingPosition;
				break;
			case steady:
				start=creaturePosition;
				end=buildingPosition;
				break;
			case disappearingAtBuilding:
				float progress=float(frame)/numFramesToDisappear;
				start=(1.0f-progress)*creaturePosition+progress*buildingPosition;
				end=buildingPosition;
				break;
			case disappearingAtCreature:
				float progress=float(frame)/numFramesToDisappear;
				start=creaturePosition;
				end=progress*creaturePosition+(1.0f-progress)*buildingPosition;
				break;
		}
		return true;
	}
}

bool updateSpeedUp(B)(ref SpeedUp!B speedUp,ObjectState!B state){
	with(speedUp){
		if(!state.isValidTarget(creature,TargetType.creature)) return false;
		framesLeft-=1;
		return state.movingObjectById!((ref obj,framesLeft,state){
			enum coolDownTime=(1.0f*updateFPS);
			if(obj.health==0.0f){
				if(framesLeft>=coolDownTime)
					obj.creatureStats.effects.numSpeedUps-=1;
				framesLeft=0;
			}
			if(obj.creatureStats.effects.speedUpUpdateFrame!=state.frame){
				obj.creatureStats.effects.speedUp=1.0f;
				obj.creatureStats.effects.speedUpUpdateFrame=state.frame;
			}
			if(!framesLeft){
				if(!obj.creatureStats.effects.speedUp)
					obj.creatureStats.effects.speedUpFrame=-1;
				return false;
			}
			//float speedUpFactor=1.75f^^min(1.0f,framesLeft*(1.0f/(0.5f*updateFPS)));
			float speedUpFactor=1.0f+0.75f*min(1.0f,framesLeft*(1.0f/coolDownTime));
			obj.creatureStats.effects.speedUp*=speedUpFactor;
			if(framesLeft<coolDownTime){
				if(framesLeft+1>=coolDownTime)
					obj.creatureStats.effects.numSpeedUps-=1;
				if(framesLeft) return true;
			}
			auto hitbox=obj.hitbox;
			auto sacParticle=SacParticle!B.get(ParticleType.speedUp);
			auto scale=1.0f; // TODO: does this differ for different creatures?
			auto frame=state.uniform!"[)"(0,sacParticle.numFrames);
			state.addParticle(Particle!B(sacParticle,state.uniform(hitbox),Vector3f(0.0f,0.0f,0.0f),scale,sacParticle.numFrames,frame));
			state.addEffect(SpeedUpShadow!B(obj.id,obj.position,obj.rotation,obj.animationState,obj.frame));
			return true;
		},()=>false)(creature,framesLeft,state);
	}
}

bool updateRedVortex(B)(ref RedVortex vortex,ObjectState!B state,float height=RedVortex.convertHeight){
	vortex.frame+=1;
	vortex.position.z=state.getHeight(vortex.position)+height;
	if(vortex.scale>0.3f){
		foreach(i;0..2){
			auto sacParticle=SacParticle!B.get(ParticleType.redVortexDroplet);
			auto velocity=0.1f*state.uniformDirection();
			velocity.z-=5.0f;
			auto position=vortex.position+vortex.scale*(Vector3f(0.0f,0.0f,-0.8f*vortex.radius)+0.35f*vortex.radius*Vector3f(state.uniform(-1.0f,1.0f),state.uniform(-1.0f,1.0f),0.0f));
			auto scale=1.0f;
			auto frame=0;
			state.addParticle(Particle!B(sacParticle,position,velocity,scale,sacParticle.numFrames,frame));
		}
	}
	return true;
}

Vector3f getFallingVelocity(B)(Vector3f direction,float upwardsVelocity,ObjectState!B state){
	enum g=10.0f;
	auto fallingHeight=-direction.z;
	auto fallingTime=upwardsVelocity/g+sqrt(max(0.0f,upwardsVelocity^^2+2.0f*g*fallingHeight))/g;
	return Vector3f(direction.x/fallingTime,direction.y/fallingTime,upwardsVelocity);
}

int spawnSacDoctor(B)(int side,Vector3f position,Vector3f landingPosition,ObjectState!B state){
	auto curObj=SacObject!B.getSAXS!Creature(SpellTag.sacDoctor);
	position.z=max(position.z-0.9f*RedVortex.radius,state.getHeight(position));
	auto direction=landingPosition-position;
	auto facing=atan2(-direction.x,direction.y);
	if(isNaN(facing)) facing=0.0f;
	auto mode=CreatureMode.stunned;
	auto movement=CreatureMovement.tumbling;
	auto creatureState=CreatureState(mode, movement, facing);
	enum jumpVelocity=10.0f;
	creatureState.fallingVelocity=getFallingVelocity(direction,jumpVelocity,state);
	auto rotation=facingQuaternion(facing);
	auto obj=MovingObject!B(curObj,position,rotation,AnimationState.stance1,0,creatureState,curObj.creatureStats(Flags.cannotDamage),side);
	obj.setCreatureState(state);
	obj.updateCreaturePosition(state);
	obj.animationState=cast(AnimationState)SacDoctorAnimationState.expelled;
	return state.addObject(obj);
}

bool updateSacDocCasting(B)(ref SacDocCasting!B sacDocCast,ObjectState!B state){
	with(sacDocCast){
		vortex.updateRedVortex(state);
		void freeSoulImpl(){
			state.soulById!((ref soul,side){
				static assert(is(typeof(soul.convertSideMask)==uint));
				soul.convertSideMask|=(1u<<side);
			},(){})(sacDocCast.target,sacDocCast.side);
		}
		if(!state.isValidTarget(targetShrine,TargetType.building)){
			underway=false;
			interrupted=true;
			freeSoulImpl();
		}
		if(underway){
			vortex.scale=min(1.0,vortex.scale+1.0f/vortex.numFramesToEmerge);
			final switch(manaDrain.update(state)){
				case CastingStatus.underway:
					return true;
				case CastingStatus.interrupted:
					underway=false;
					interrupted=true;
					freeSoulImpl();
					break;
				case CastingStatus.finished:
					underway=false;
					auto sacDoctor=spawnSacDoctor(side,vortex.position,landingPosition,state);
					if(!sacDoctor){ underway=false; interrupted=true; break; }
					final switch(type){
						case RitualType.convert:
							state.addEffect(SacDocCarry!B(type,side,spell,manaDrain.wizard,sacDoctor,target,0,targetShrine));
							break;
						case RitualType.desecrate:
							state.addEffect(SacDocCarry!B(type,side,spell,manaDrain.wizard,sacDoctor,0,target,targetShrine));
					}
					break;
			}
		}else{
			if(interrupted||vortex.frame>vortex.numFramesToEmerge+vortex.numFrames){
				vortex.scale=max(0.0,vortex.scale-1.0f/vortex.numFramesToDisappear);
				if(vortex.scale==0.0f) return false;
			}
		}
		return true;
	}
}

Vector3f[SacDocTether.m] getSacDocTetherTargetLocations(B)(ref MovingObject!B sacDoc,int target,ObjectState!B state,float needleExpansion=1.5f){
	Vector3f[SacDocTether.m] locations;
	auto needle = sacDoc.needle;
	auto center = state.movingObjectById!((ref obj)=>obj.center,()=>Vector3f.init)(target);
	if(isNaN(needle[0].x)||isNaN(center.x)) return locations;
	locations[0]=needle[0];
	auto start=isNaN(needleExpansion)?needle[0]:needle[0]+needleExpansion*needle[1];
	if(!isNaN(needleExpansion)) locations[1]=start;
	float intp=locations.length-2+isNaN(needleExpansion);
	foreach(i,ref p;locations[!isNaN(needleExpansion)..$]) p=i/intp*center+(intp-i)/intp*start;
	return locations;
}

SacDocTether makeSacDocTether(B)(ref MovingObject!B sacDoc,int target,ObjectState!B state,float needleExpansion=1.5f){
	SacDocTether tether;
	tether.locations=getSacDocTetherTargetLocations(sacDoc,target,state,needleExpansion);
	tether.velocities[]=Vector3f(0.0f,0.0f,0.0f);
	return tether;
}


void updateSacDocTether(B)(ref SacDocTether tether,ref MovingObject!B sacDoc,int target,ObjectState!B state,float needleExpansion=1.5f){
	auto targets=getSacDocTetherTargetLocations(sacDoc,target,state,needleExpansion);
	if(isNaN(targets[0].x)){
		tether=SacDocTether.init;
		return;
	}
	auto totalVelocity=0.5f*(updateFPS*((targets[0]-tether.locations[0])+targets[1]-tether.locations[1]));
	tether.locations[0]=targets[0];
	tether.locations[1]=targets[1];
	tether.locations[$-1]=targets[$-1];
	enum accelFactor=120.0f;
	static import std.math;
	enum dampFactor=std.math.exp(std.math.log(0.25f)/updateFPS);
	enum maxVelocity=20.0f;
	foreach(i;2..targets.length-1){
		auto acceleration=targets[i]-tether.locations[i];
		acceleration=accelFactor*acceleration.lengthsqr^^(1/7.0f)*acceleration;
		tether.velocities[i]+=acceleration/updateFPS;
		tether.velocities[i]*=dampFactor;
		auto relativeVelocity=tether.velocities[i]-totalVelocity;
		if(relativeVelocity.lengthsqr>maxVelocity^^2)
			tether.velocities[i]=totalVelocity+maxVelocity/relativeVelocity.length*relativeVelocity;
		tether.locations[i]+=tether.velocities[i]/updateFPS;
	}
	enum numParticles=2;
	auto needle=sacDoc.needle;
	auto sacParticle=SacParticle!B.get(ParticleType.needle);
	foreach(i;0..numParticles){
		auto direction=needle[1]+state.uniform(0.2f,1.0f)*state.uniformDirection();
		auto velocity=state.uniform(1.5f,2.0f)*direction;
		velocity.z*=2.5f;
		auto scale=state.uniform(0.5f,1.0f);
		auto lifetime=31+state.uniform(0,32);
		auto frame=0;
		state.addParticle(Particle!B(sacParticle,needle[0],velocity,scale,lifetime,frame));
	}
}

bool updateSacDocCarry(B)(ref SacDocCarry!B sacDocCarry,ObjectState!B state){
	static void freeSoulImpl(SacDocCarry!B* sacDocCarry,ObjectState!B state){
		state.soulById!((ref soul,side){
			static assert(is(typeof(soul.convertSideMask)==uint));
			soul.convertSideMask|=(1u<<side);
		},(){})(sacDocCarry.soul,sacDocCarry.side);
	}
	if(sacDocCarry.status==SacDocCarryStatus.shrinking){
		sacDocCarry.vortexScale=max(0.0f,sacDocCarry.vortexScale-1.0f/SacDocCarry!B.numFramesToDisappear);
		return sacDocCarry.vortexScale>0.0f;
	}
	if(!state.isValidTarget(sacDocCarry.sacDoctor,TargetType.creature)){
		if(sacDocCarry.soul) freeSoulImpl(&sacDocCarry,state);
		if(sacDocCarry.creature){
			state.movingObjectById!(freeCreature,()=>false)(sacDocCarry.creature,Vector3f.init,state);
			sacDocCarry.status=SacDocCarryStatus.shrinking;
			return true;
		}else return false;
	}
	static bool startMoving(ref MovingObject!B sacDoc,ref SacDocCarry!B sacDocCarry,ObjectState!B state){
		if(sacDoc.isDying) return false;
		with(sacDocCarry){
			sacDoc.clearOrderQueue(state);
			status=SacDocCarryStatus.move;
			tether=makeSacDocTether(sacDoc,creature,state);
			if(!sacDoc.startIdling(state)){
				if(soul) freeSoulImpl(&sacDocCarry,state);
				sacDoc.kill(state);
				return false;
			}
			sacDoc.animationState=cast(AnimationState)SacDoctorAnimationState.pickUpCorpse;
			if(!state.movingObjectById!(startThrashing,()=>false)(creature,state)){
				if(soul) freeSoulImpl(&sacDocCarry,state);
				sacDoc.kill(state);
				state.movingObjectById!(kill,()=>false)(creature,state);
				return false;
			}
			if(soul){
				state.removeLater(soul);
				soul=0;
				state.movingObjectById!((ref obj){ obj.soulId=0; },(){})(creature);
			}
			return true;
		}
	}
	static bool update(ref MovingObject!B sacDoc,SacDocCarry!B* sacDocCarry,ObjectState!B state){
		void freeSoul(){ freeSoulImpl(sacDocCarry,state); }
		with(sacDocCarry){
			bool shrineDestroyed=!state.isValidTarget(targetShrine,TargetType.building);
			final switch(status){
				case SacDocCarryStatus.fall:
					if(sacDoc.animationState==cast(AnimationState)SacDoctorAnimationState.bounce){
						status=SacDocCarryStatus.bounce;
						goto case;
					}
					break;
				case SacDocCarryStatus.bounce:
					if(sacDoc.animationState!=cast(AnimationState)SacDoctorAnimationState.bounce){
						sacDoc.creatureStats.flags&=~Flags.cannotDamage;
						status=SacDocCarryStatus.walkToTarget;
						goto case;
					}
					break;
				case SacDocCarryStatus.walkToTarget:
					final switch(type){
						case RitualType.convert:
							if(shrineDestroyed||!state.soulById!((ref soul)=>soul.state.among(SoulState.normal,SoulState.emerging)||!soul.creatureId,()=>false)(soul)){
								sacDoc.kill(state);
								freeSoul();
								return false;
							}
							auto soulPositionSoulNumber=state.soulById!((ref soul)=>tuple(soul.position,soul.number),()=>tuple(Vector3f.init,0))(soul);
							auto soulPosition=soulPositionSoulNumber[0], soulNumber=soulPositionSoulNumber[1];
							if(isNaN(soulPosition.x)){
								sacDoc.kill(state);
								return false;
							}
							if((sacDoc.position-soulPosition).xy.lengthsqr<4.0f){
								sacDoc.clearOrderQueue(state);
								status=SacDocCarryStatus.pump;
								sacDoc.startPumping(state);
								timer=(soulNumber+1)*5*updateFPS;
								sacDoc.creatureStats.effects.carrying=soulNumber;
							}else if(!sacDoc.hasOrders(state)){
								auto ord=Order(CommandType.move,OrderTarget(TargetType.soul,soul,soulPosition));
								sacDoc.order(ord,state);
							}else{
								sacDoc.creatureAI.order.target.position=soulPosition;
							}
							break;
						case RitualType.desecrate:
							auto creaturePositionScaleNumSouls=state.movingObjectById!((ref obj,spell,state)=>tuple(obj.position,obj.getScale,obj.sacObject.numSouls),()=>Tuple!(Vector3f,Vector2f,int).init)(creature,spell,state);
							auto creaturePosition=creaturePositionScaleNumSouls[0], scale=creaturePositionScaleNumSouls[1], numSouls=creaturePositionScaleNumSouls[2];
							auto creatureTarget=OrderTarget(TargetType.creature,creature,creaturePosition);
							if(!spell.isApplicable(summarize(creatureTarget,side,state))||isNaN(creaturePosition.x)){
								sacDoc.kill(state);
								return false;
							}
							enum desecratePickUpDistance=10.0f;
							if((sacDoc.position-creaturePosition).xy.lengthsqr<max((2.0f*scale+0.5f).lengthsqr,desecratePickUpDistance^^2)){
								if(!startMoving(sacDoc,*sacDocCarry,state)) return false;
								sacDoc.creatureStats.effects.carrying=numSouls;
							}else if(!sacDoc.hasOrders(state)){
								auto ord=Order(CommandType.move,OrderTarget(TargetType.creature,creature,creaturePosition));
								sacDoc.order(ord,state);
							}else{
								sacDoc.creatureAI.order.target.position=creaturePosition;
							}
							break;
					}
					break;
				case SacDocCarryStatus.pump:
					if(!sacDoc.creatureState.mode==CreatureMode.pumping)
						sacDoc.startPumping(state);
					if(shrineDestroyed) sacDoc.kill(state);
					if(sacDoc.creatureState.mode==CreatureMode.dying){
						freeSoul();
						if(creature) state.movingObjectById!(freeCreature,()=>false)(creature,Vector3f.init,state);
						return false;
					}
					if(sacDoc.animationState==cast(AnimationState)SacDoctorAnimationState.pumpCorpse){
						if(!creature){
							creature=state.soulById!((ref soul)=>soul.creatureId,()=>0)(soul);
							if(!creature){
								freeSoul();
								sacDoc.kill(state);
								return false;
							}
							if(!state.movingObjectById!(convertRevive,()=>false)(creature,state)){
								freeSoul();
								sacDoc.kill(state);
								return false;
							}
							playSpellSoundTypeAt(SoundType.convertRevive,sacDoc.id,state,2.0f);
						}
						if(--timer==0) if(!startMoving(sacDoc,*sacDocCarry,state)) return false;
					}
					break;
				case SacDocCarryStatus.move:
					++frame;
					vortexScale=min(1.0f,vortexScale+1.0f/SacDocCarry!B.numFramesToEmerge);
					tether.updateSacDocTether(sacDoc,creature,state);
					static bool update(ref MovingObject!B creature,MovingObject!B* sacDoc,SacDocCarry!B* sacDocCarry,ObjectState!B state){
						auto transportHeight=3.5f, transportDistance=2.0f+0.5f*creature.getScale.length;
						//auto targetPosition2d=transportDistance*(creature.position-sacDoc.position).xy.normalized;
						//auto targetPosition=sacDoc.position+Vector3f(targetPosition2d.x,targetPosition2d.y,transportHeight);
						auto targetPosition=sacDoc.position+rotate(facingQuaternion(sacDoc.creatureState.facing),Vector3f(0.0f,-transportDistance,transportHeight));
						auto targetDirection=targetPosition-creature.position;
						auto distance=targetDirection.length;
						if(distance>0.75f){
							auto transportVelocity=1.1f*(*sacDoc).speedOnGround(state)/updateFPS;
							if(distance<transportVelocity) creature.position=targetPosition;
							else creature.position+=transportVelocity/distance*targetDirection; // TODO: inertia?
						}
						return true;
					}
					auto shrinePosition=state.staticObjectById!((ref obj)=>obj.position,()=>Vector3f.init)(targetShrine);
					if(shrineDestroyed||isNaN(shrinePosition.x)||!state.movingObjectById!(update,()=>false)(creature,&sacDoc,sacDocCarry,state)){
						sacDoc.kill(state);
					}
					if(sacDoc.creatureState.mode==CreatureMode.dying){
						state.movingObjectById!(freeCreature,()=>false)(creature,sacDoc.position,state);
						status=SacDocCarryStatus.shrinking;
						tether=SacDocTether.init;
					}else if(sacDoc.creatureState.movement==CreatureMovement.onGround && (sacDoc.position-shrinePosition).lengthsqr<20.0f^^2 && startRitual(type,side,spell,caster,targetShrine,creature,state)){
						status=SacDocCarryStatus.shrinking;
						tether=SacDocTether.init;
						sacDoc.kill(state);
					}else if(!sacDoc.hasOrders(state)){
						auto ord=Order(CommandType.move,OrderTarget(TargetType.building,targetShrine,shrinePosition));
						sacDoc.order(ord,state);
					}else{
						sacDoc.creatureAI.order.target.position=shrinePosition;
					}
					break;
				case SacDocCarryStatus.shrinking:
					assert(0);
			}
			return true;
		}
	}
	return state.movingObjectById!(update,function bool(){ assert(0); })(sacDocCarry.sacDoctor,&sacDocCarry,state);
}

bool freeForRitual(B)(int targetShrine,ObjectState!B state){
	return state.staticObjectById!((ref shrine,state){
		return state.buildingById!((ref bldg){
			return !(bldg.flags&AdditionalBuildingFlags.occupied);
		},()=>false)(shrine.buildingId);
	},()=>false)(targetShrine,state);
}

void setOccupied(B)(int shrine,bool occupied,ObjectState!B state){
	return state.staticObjectById!((ref shrine,occupied,state){
		state.buildingById!((ref bldg,occupied){
			if(occupied) bldg.flags|=AdditionalBuildingFlags.occupied;
			else bldg.flags&=~AdditionalBuildingFlags.occupied;
		},(){})(shrine.buildingId,occupied);
	},(){})(shrine,occupied,state);
}

bool stopRitual(B)(ref Ritual!B ritual,ObjectState!B state,bool targetDead=false){
	with(ritual){
		stopped=true;
		if(creature) state.movingObjectById!(freeCreature,()=>false)(creature,start,state);
		foreach(id;sacDoctors) state.movingObjectById!(kill,()=>false)(id,state);
		tethers=typeof(tethers).init;
		altarBolts=typeof(altarBolts).init;
		if(!targetDead) desecrateBolts=typeof(desecrateBolts).init;
		setOccupied(shrine,false,state);
		if(targetWizard) state.movingObjectById!((ref obj){ obj.creatureStats.effects.numDesecrations-=1; },(){})(targetWizard);
		return vortex.scale>0.0f;
	}
}


int spawnRitualSacDoctor(B)(int side,Vector3f position,float facing,ObjectState!B state){
	auto curObj=SacObject!B.getSAXS!Creature(SpellTag.sacDoctor);
	if(isNaN(facing)) facing=0.0f;
	position.z=state.getHeight(position);
	auto mode=CreatureMode.idle;
	auto movement=CreatureMovement.onGround;
	auto creatureState=CreatureState(mode, movement, facing);
	auto rotation=facingQuaternion(facing);
	auto obj=MovingObject!B(curObj,position,rotation,AnimationState.stance1,0,creatureState,curObj.creatureStats(0),side);
	obj.setCreatureState(state);
	obj.updateCreaturePosition(state);
	obj.animationState=cast(AnimationState)SacDoctorAnimationState.dance;
	auto id=state.addObject(obj);
	appear(id,50,state);
	return id;
}

Tuple!(Vector3f,float)[4] ritualPositions(B)(Vector3f shrinePosition,ObjectState!B state,float progress=0.0f){
	typeof(return) result;
	foreach(k;0..4){
		auto radius=20.0f-3.0f*max(0.0f,5.0f*progress-4.0f);
		auto facing=(0.125f+0.25f*(k+min(1.1f*progress,0.7f+0.3f*progress)))%1.0f*2*pi!float;
		auto position=shrinePosition+Vector3f(cos(facing-0.5f*pi!float),sin(facing-0.5f*pi!float),0.0f)*radius;
		result[k]=tuple(position,facing);
	}
	return result;
}

bool startRitual(B)(RitualType type,int side,SacSpell!B spell,int caster,int shrine,int creature,ObjectState!B state){
	if(!freeForRitual(shrine,state)) return false;
	auto start=state.movingObjectById!((ref obj)=>obj.position,()=>Vector3f.init)(creature);
	if(isNaN(start.x)) return false;
	int[4] sacDoctors;
	auto shrinePositionShrineSide=state.staticObjectById!((ref obj,state)=>tuple(obj.position,obj.side(state)),()=>Tuple!(Vector3f,int).init)(shrine,state);
	auto shrinePosition=shrinePositionShrineSide[0], shrineSide=shrinePositionShrineSide[1];
	if(isNaN(shrinePosition.x)) return false;
	auto positions=ritualPositions(shrinePosition,state);
	foreach(k,ref id;sacDoctors) id=spawnRitualSacDoctor(side,positions[k].expand,state);
	RedVortex vortex;
	int targetWizard=0;
	auto vortexHeight=type==RitualType.desecrate?RedVortex.desecrateHeight:RedVortex.convertHeight;
	if(type==RitualType.desecrate){
		auto wizard=state.getWizardForSide(shrineSide);
		if(wizard){
			auto wizardPosition=state.movingObjectById!((ref obj)=>obj.position,()=>Vector3f.init)(wizard.id);
			if(!isNaN(wizardPosition.x)){
				vortex.position=wizardPosition+vortex.desecrateDistance*(shrinePosition-wizardPosition).normalized;
				if(isNaN(vortex.position.x)) vortex.position=wizardPosition;
				vortex.position.z=state.getHeight(vortex.position)+vortexHeight;
				targetWizard=wizard.id;
			}
		}
	}
	state.addEffect(Ritual!B(type,start,side,spell,caster,shrine,sacDoctors,creature,vortex,targetWizard));
	setOccupied(shrine,true,state);
	if(targetWizard) state.movingObjectById!((ref obj){ obj.creatureStats.effects.numDesecrations+=1; },(){})(targetWizard);
	return true;
}

bool updateRitual(B)(ref Ritual!B ritual,ObjectState!B state){
	with(ritual){
		++frame;
		if(!state.isValidTarget(targetWizard,TargetType.creature)) targetWizard=0;
		bool targetDead=!targetWizard||state.movingObjectById!(isDead,()=>true)(targetWizard);
		if(type==RitualType.desecrate&&targetWizard&&targetDead){
			state.staticObjectById!(destroyAltar,()=>false)(shrine,state);
			if(isNaN(desecrateBolts[0].displacement[0].x)||frame%6==0){
				if(!isNaN(vortex.position.x))
					foreach(ref bolt;desecrateBolts) bolt.changeShape(state);
			}
		}
		if(ritual.stopped){
			if(!targetWizard||!targetDead) vortex.scale=max(0.0f,vortex.scale-1.0f/vortex.numFramesToDisappear);
			return vortex.scale>0.0f;
		}
		auto shrinePositionIsAltar=state.staticObjectById!((ref obj)=>tuple(obj.position,obj.sacObject.isAltar),()=>tuple(Vector3f.init,false))(shrine);
		if(type==RitualType.convert||!targetDead||!isNaN(shrinePositionIsAltar[0].x)) shrinePosition=shrinePositionIsAltar[0];
		auto isAltar=shrinePositionIsAltar[1];
		if(isNaN(shrinePosition.x)) return ritual.stopRitual(state);
		foreach(id;sacDoctors){
			if(state.movingObjectById!((ref obj)=>obj.creatureState.mode==CreatureMode.dying,()=>false)(id))
				return ritual.stopRitual(state);
		}
		if(creature) state.movingObjectById!((ref obj,targetPosition,remainingTime,state){
			auto hitbox=obj.sacObject.largeHitbox(Quaternionf.identity(),AnimationState.stance1,0);
			obj.position=((remainingTime-1)*obj.position+targetPosition)/float(remainingTime);
		},(){})(creature,shrinePosition+Vector3f(0.0f,0.0f,15.0f),max(1,ritual.setupTime-frame),state);
		if(!isNaN(vortex.position.x)){
			if(targetWizard){
				vortex.scale=min(1.0f,vortex.scale+1.0f/vortex.numFramesToEmerge);
				auto targetPosition=state.movingObjectById!((ref obj)=>obj.position,()=>Vector3f.init)(targetWizard);
				if(!isNaN(targetPosition.x)){
					if((vortex.position-targetPosition).lengthsqr>vortex.desecrateDistance^^2){
						auto newPos=targetPosition.xy+vortex.desecrateDistance*(vortex.position.xy-targetPosition.xy).normalized;
						vortex.position.x=newPos.x;
						vortex.position.y=newPos.y;
					}
				}else targetWizard=0;
			}else{
				vortex.scale=max(0.0,vortex.scale-1.0f/vortex.numFramesToDisappear);
			}
			vortex.updateRedVortex(state,vortex.desecrateHeight);
		}
		if(frame>=ritual.setupTime){
			auto time=frame-ritual.setupTime;
			static assert(updateFPS==60);
			enum walkTime=4*updateFPS+updateFPS/2;
			enum shootTime=4*updateFPS+updateFPS/2;
			enum waitTime=4*updateFPS+updateFPS/2;
			enum roundTime=walkTime+shootTime+waitTime;
			auto nRounds=time/roundTime;
			auto progress=time%roundTime;
			if(progress<walkTime){
				auto positions=ritualPositions(shrinePosition,state,float(progress)/walkTime);
				foreach(k,id;sacDoctors){
					state.movingObjectById!((ref sacDoc,position,state){
						if(progress==0){
							sacDoc.creatureState.mode=CreatureMode.moving;
							sacDoc.setCreatureState(state);
						}
						if(!sacDoc.hasOrders(state)){
							auto ord=Order(CommandType.move,OrderTarget(TargetType.terrain,0,position));
							sacDoc.order(ord,state);
						}else{
							sacDoc.creatureAI.order.target.position=position;
						}
					},(){})(id,positions[k][0],state);
				}
			}else{
				if(progress==walkTime){
					foreach_reverse(k;1..sacDoctors.length)
						swap(sacDoctors[k],sacDoctors[k-1]);
				}
				enum tortureStart=updateAnimFactor*5, tortureEnd=updateAnimFactor*130;
				if(ritual.creature) foreach(k,id;sacDoctors){
					state.movingObjectById!((ref sacDoc,k,shrinePosition,ritual,state){
						sacDoc.clearOrderQueue(state);
						if(sacDoc.creatureState.mode!=CreatureMode.torturing){
							if(!sacDoc.turnToFaceTowards(shrinePosition,state)&&progress<walkTime+shootTime)
								sacDoc.startTorturing(state);
						}else{
							if(progress<walkTime+shootTime){
								if(sacDoc.frame==tortureStart){
									ritual.tethers[k]=sacDoc.makeSacDocTether(ritual.creature,state,float.nan);
									foreach(ref x;ritual.tethers[k].locations[1..$-1]) x+=3.0f*state.uniformDirection();
								}
							}
							if(!isNaN(ritual.tethers[k].locations[0].x)&&sacDoc.frame>tortureStart && sacDoc.frame<tortureEnd)
								ritual.tethers[k].updateSacDocTether(sacDoc,ritual.creature,state,float.nan);
						}
						if(sacDoc.frame==tortureEnd) ritual.tethers[k]=SacDocTether.init;
					},(){})(id,k,shrinePosition,&ritual,state);
				}
				enum boltDelay=updateAnimFactor*5;
				enum changeShapeDelay=9;
				if(progress>=walkTime+boltDelay+tortureStart&&progress<walkTime+boltDelay+tortureEnd){
					if(progress==walkTime+boltDelay+tortureStart||frame%changeShapeDelay==0){
						foreach(ref bolt;altarBolts) bolt.changeShape(state);
					}
					if(type==RitualType.desecrate&&!targetDead){
						if(progress==walkTime+boltDelay+tortureStart||frame%6==0)
							if(!isNaN(vortex.position.x))
								foreach(ref bolt;desecrateBolts) bolt.changeShape(state);
						auto numSouls=creature?state.movingObjectById!((ref obj)=>obj.sacObject.numSouls,()=>0)(creature):0;
						static void drain(ref MovingObject!B wizard,int side,int numSouls,ObjectState!B state){
							dealDesecrationDamage(wizard,(200.0f*(1+numSouls))/(tortureEnd-tortureStart),side,state);
							drainMana(wizard,(40.0f*(1+numSouls))/(tortureEnd-tortureStart),state);
							// TODO: desecration XP drain
						}
						state.movingObjectById!(drain,(){})(targetWizard,side,numSouls,state);
					}
				}else if(progress==walkTime+boltDelay+tortureEnd){
					altarBolts=(LightningBolt[2]).init;
					if(!targetDead) desecrateBolts=(LightningBolt[3]).init;
				}
				if(progress==walkTime+135*updateAnimFactor){
					tethers=(SacDocTether[4]).init;
					altarBolts=(LightningBolt[2]).init;
					bool finish=false;
					final switch(type){
						case RitualType.convert:
							if(!creature||state.movingObjectById!((ref obj,nRounds,caster,state){
								auto targetRounds=cast(int)obj.creatureStats.maxHealth/550;
								if(nRounds==targetRounds){
									obj.gib(state,caster);
									return true;
								}
								return false;
							},()=>true)(creature,nRounds,caster,state))
								return ritual.stopRitual(state);
							break;
						case RitualType.desecrate:
							if(targetDead){
								if(creature) state.movingObjectById!((ref obj,caster,state){ obj.gib(state,caster); },(){})(creature,caster,state);
								state.staticObjectById!(destroyAltar,()=>false)(shrine,state);
								return ritual.stopRitual(state,true);
							}
							break;
					}
				}
			}
		}
		static bool filter(ref ProximityEntry entry,ObjectState!B state,int[4] sacDoctors,int creature){
			return !sacDoctors[].canFind(entry.id) && entry.id!=creature;
		}
		pushAll!(filter,true)(shrinePosition,5.0f,20.0f,20.0f,state,sacDoctors,creature);
		return true;
	}
}

bool updateTeleportCasting(B)(ref TeleportCasting!B teleportCast,ObjectState!B state){
	with(teleportCast){
		auto sidePosition=state.movingObjectById!((ref obj)=>tuple(obj.side,obj.position),()=>tuple(-1,Vector3f.init))(manaDrain.wizard);
		auto side=sidePosition[0], startPosition=sidePosition[1];
		if(side==-1) return false;
		final switch(manaDrain.update(state)){
			case CastingStatus.underway:
				if(state.isValidTarget(target))
					targetPosition=getTeleportPosition(spell,startPosition,target,state);
				return true;
			case CastingStatus.interrupted: return false;
			case CastingStatus.finished:
				teleport(side,startPosition,targetPosition,spell,state);
				return false;
		}
	}
}

enum teleportEffectLifetime=32;
bool updateTeleportEffect(B)(ref TeleportEffect!B teleportEffect,ObjectState!B state){
	with(teleportEffect){
		if(isTeleportOut){
			if(frame==0) position.z+=4.0f/5.0f*height;
			if(frame==teleportEffectLifetime/5) position.z-=3.0f/5.0f*height;
			if(frame==3*teleportEffectLifetime/5) position.z-=4.0f/5.0f*height;
			position+=Vector3f(0.0f,0.0f,height)/teleportEffectLifetime;
			++frame;
		}else{
			if(frame==0) position.z+=2.0f/5.0f*height;
			if(frame==2*teleportEffectLifetime/5) position.z+=4.0f/5.0f*height;
			if(frame==4*teleportEffectLifetime/5) position.z+=3.0f/5.0f*height;
			position-=Vector3f(0.0f,0.0f,height)/teleportEffectLifetime;
			++frame;
		}
		state.addEffect(TeleportRing!B(position,scale));
		return frame<teleportEffectLifetime;
	}
}

enum teleportRingLifetime=48;
bool updateTeleportRing(B)(ref TeleportRing!B teleportRing,ObjectState!B state){
	with(teleportRing){
		++frame;
		position+=Vector3f(0.0f,0.0f,0.25f)/teleportRingLifetime;
		return frame<teleportRingLifetime;
	}
}

enum speedUpShadowLifetime=updateFPS/5;
enum speedUpShadowSpacing=speedUpShadowLifetime/3;
bool updateSpeedUpShadow(B)(ref SpeedUpShadow!B speedUpShadow,ObjectState!B state){
	with(speedUpShadow){
		if(++age>=speedUpShadowLifetime) return false;
		return true;
	}
}

void animateCasting(bool spread=true,int numParticles=-1,bool raise=false,B)(ref MovingObject!B wizard,SacParticle!B sacParticle,ObjectState!B state){
	auto hands=wizard.hands;
	static if(numParticles==-1){
		static if(spread) enum numParticles=2;
		else enum numParticles=1;
	}
	auto numFrames=sacParticle.numFrames;
	foreach(i;0..2){
		auto hposition=hands[i];
		if(isNaN(hposition.x)) continue;
		foreach(k;0..numParticles){
			static if(spread){
				auto position=hposition+0.125f*state.uniformDirection();
				auto direction=state.uniformDirection();
				auto velocity=state.uniform(0.5f,1.5f)*direction;
			}else{
				auto position=hposition;
				auto velocity=Vector3f(0.0f,0.0f,0.0f);
			}
			auto scale=1.0f;
			auto lifetime=numFrames-1;
			auto frame=0;
			static if(raise){
				auto distance=(state.uniform(3)?state.uniform(0.3f,0.6f):state.uniform(1.0f,2.0f));
				position+=0.125f*state.uniformDirection();
				velocity+=Vector3f(0.0f,0.0f,distance/(float(lifetime)/updateFPS));
			}
			state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
		}
	}
}
void animatePersephoneCasting(B)(ref MovingObject!B wizard,ObjectState!B state){
	auto castParticle=SacParticle!B.get(ParticleType.castPersephone);
	wizard.animateCasting(castParticle,state);
}
void animatePyroCasting(B)(ref MovingObject!B wizard,ObjectState!B state){
	auto castParticle=SacParticle!B.get(ParticleType.castPyro);
	wizard.animateCasting(castParticle,state);
}
void animateJamesCasting(B)(ref MovingObject!B wizard,ObjectState!B state){
	auto castParticle=SacParticle!B.get(ParticleType.castJames);
	wizard.animateCasting(castParticle,state);
}
void animateStratosCasting(B)(ref MovingObject!B wizard,ObjectState!B state){
	auto castParticle=SacParticle!B.get(ParticleType.castStratos);
	wizard.animateCasting(castParticle,state);
}
void animateCharnelCasting(B)(ref MovingObject!B wizard,ObjectState!B state){
	auto castParticle=SacParticle!B.get(ParticleType.castCharnel);
	wizard.animateCasting(castParticle,state);
}

void animateCastingForGod(B)(ref MovingObject!B wizard,God god,ObjectState!B state){
	final switch(god) with(God){
		import std.traits:EnumMembers;
		static foreach(sgod;EnumMembers!God){
			case sgod:
				static if(sgod!=none) mixin(`animate`~upperf(text(sgod))~`Casting`)(wizard,state);
				return;
		}
	}
}

void animateHealCasting(B)(ref MovingObject!B wizard,ObjectState!B state){
	auto castParticle=SacParticle!B.get(ParticleType.heal);
	wizard.animateCasting(castParticle,state);
}

bool updateHealCasting(B)(ref HealCasting!B healCast,ObjectState!B state){
	with(healCast){
		final switch(manaDrain.update(state)){
			case CastingStatus.underway:
				auto sacParticle=SacParticle!B.get(ParticleType.relativeHeal);
				static assert(updateFPS==60);
				enum numParticles=2;
				foreach(i;0..numParticles){
					state.movingObjectById!((obj,sacParticle,state){
						auto hitbox=obj.relativeHitbox;
						auto center=boxCenter(hitbox);
						auto position=state.uniform(hitbox);
						position.x*=3.0f;
						position.y*=3.0f;
						position.z*=2.0f;
						auto lifetime=sacParticle.numFrames/60.0f;
						auto velocity=(center-position)/lifetime;
						auto scale=1.0f;
						state.addParticle(Particle!(B,true)(sacParticle,obj.id,false,position,velocity,scale,sacParticle.numFrames,0));
					},(){})(creature,sacParticle,state);
					state.movingObjectById!((obj,sacParticle,state){
						auto hitbox=obj.relativeHitbox;
						auto center=boxCenter(hitbox);
						auto position=state.uniform(hitbox);
						position.x*=3.0f;
						position.y*=3.0f;
						position.z*=2.0f;
						auto lifetime=sacParticle.numFrames/60.0f;
						auto velocity=(position-center)/lifetime;
						auto scale=1.0f;
						state.addParticle(Particle!(B,true)(sacParticle,obj.id,false,center,velocity,scale,sacParticle.numFrames,0));
					},(){})(manaDrain.wizard,sacParticle,state);
				}
				state.movingObjectById!(animateHealCasting,(){})(manaDrain.wizard,state);
				return true;
			case CastingStatus.interrupted: return false;
			case CastingStatus.finished:
				heal(creature,spell,state);
				return false;
		}
	}
}

void animateHeal(B)(ref MovingObject!B obj,ObjectState!B state){
	static assert(updateFPS==60);
	auto hitbox=obj.relativeHitbox;
	auto dim=hitbox[1]-hitbox[0];
	auto volume=dim.x*dim.y*dim.z;
	auto scale=2.0f*max(1.0f,cbrt(volume));
	auto sacParticle=SacParticle!B.get(ParticleType.relativeHeal);
	enum numParticles=2;
	foreach(i;0..numParticles){
		auto position=1.1f*state.uniform(cast(Vector2f[2])[hitbox[0].xy,hitbox[1].xy]);
		auto distance=(state.uniform(3)?state.uniform(0.3f,0.6f):state.uniform(1.5f,2.5f))*(hitbox[1].z-hitbox[0].z);
		auto fullLifetime=sacParticle.numFrames/float(updateFPS);
		auto lifetime=cast(int)(sacParticle.numFrames*state.uniform(0.0f,1.0f));
		state.addParticle(Particle!(B,true)(sacParticle,obj.id,false,Vector3f(position.x,position.y,0.0f),Vector3f(0.0f,0.0f,distance/fullLifetime),scale,lifetime,0));
	}
}

bool updateHeal(B)(ref Heal!B heal,ObjectState!B state){
	heal.timer-=1;
	if(heal.timer<0) return false;
	return state.movingObjectById!((ref obj,heal,state){
		if(!obj.canHeal(state)) return false;
		obj.heal(heal.healthRegenerationPerFrame,state);
		if(obj.health(state)==obj.creatureStats.maxHealth) return false;
		obj.animateHeal(state);
		return true;
	},function bool(){ return false; })(heal.creature,heal,state);
}

void animateLightningCasting(B)(ref MovingObject!B wizard,ObjectState!B state){
	wizard.animateStratosCasting(state);
}

bool updateLightningCasting(B)(ref LightningCasting!B lightningCast,ObjectState!B state){
	with(lightningCast){
		target.position=target.center(state);
		auto status=manaDrain.update(state);
		return state.movingObjectById!((obj,status){
			auto hbox=obj.sacObject.hitbox(Quaternionf.identity(),AnimationState.stance1,0);
			auto offset=Vector3f(0.0f,hbox[1].y+0.75f,hbox[1].z+0.5f);
			final switch(status){
				case CastingStatus.underway:
					auto sacParticle=SacParticle!B.get(ParticleType.lightningCasting);
					enum numParticles=2;
					foreach(i;0..numParticles){
						enum uncertainty=0.25f;
						Vector3f[2] box=[offset-uncertainty*Vector3f(1.0f,1.0f,1.0f),offset+uncertainty*Vector3f(1.0f,1.0f,1.0f)];
						auto position=state.uniform(box);
						auto lifetime=sacParticle.numFrames/60.0f;
						auto velocity=Vector3f(0.0f,0.0f,0.0f);
						auto scale=1.0f;
						state.addParticle(Particle!(B,true)(sacParticle,obj.id,true,position,velocity,scale,sacParticle.numFrames,0));
					}
					obj.animateLightningCasting(state);
					return true;
				case CastingStatus.interrupted: return false;
				case CastingStatus.finished:
					auto start=OrderTarget(TargetType.terrain,0,rotate(obj.rotation,offset)+obj.position);
					auto end=lightningCast.target;
					lightning(obj.id,obj.side,start,end,spell,state);
					return false;
			}
		},()=>false)(manaDrain.wizard,status);
	}
}
void sparkAnimation(int numSparks=192,B)(Vector3f[2] hitbox,ObjectState!B state){
	auto sacParticle=SacParticle!B.get(ParticleType.spark);
	if(hitbox[0]==hitbox[1]){
		hitbox[0]-=0.5;
		hitbox[1]+=0.5f;
	}
	auto center=boxCenter(hitbox);
	foreach(i;0..numSparks){
		auto position=state.uniform(scaleBox(hitbox,1.2f));
		auto velocity=Vector3f(position.x-center.x,position.y-center.y,0.0f).normalized;
		velocity.z=state.uniform(2.0f,6.0f);
		auto scale=state.uniform(0.5f,1.5f);
		int lifetime=63;
		int frame=0;
		state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
	}
}
bool updateLightning(B)(ref Lightning!B lightning,ObjectState!B state){
	lightning.frame+=1;
	static assert(updateFPS==60);
	if(lightning.frame>=lightning.totalFrames) return false;
	if(lightning.frame%lightning.changeShapeDelay==0)
		foreach(ref bolt;lightning.bolts)
			bolt.changeShape(state);
	lightning.end.position=lightning.end.center(state);
	if(lightning.frame==lightning.travelDelay){
		auto hitbox=lightning.end.hitbox(state);
		sparkAnimation(hitbox,state);
		// TODO: scar
		auto target=lightning.end.id;
		if(state.isValidTarget(target)){
			auto direction=lightning.end.position-lightning.start.position;
			dealSpellDamage(target,lightning.spell,lightning.wizard,lightning.side,direction,lightning.damageMod,state);
		}
	}
	return true;
}

void animateWrathCasting(B)(ref MovingObject!B wizard,ObjectState!B state){
	auto castParticle=SacParticle!B.get(ParticleType.wrathCasting);
	wizard.animateCasting!false(castParticle,state);
}

bool updateWrathCasting(B)(ref WrathCasting!B wrathCast,ObjectState!B state){
	with(wrathCast){
		target.position=target.center(state);
		final switch(manaDrain.update(state)){
			case CastingStatus.underway:
				return state.movingObjectById!((obj){
					obj.animateWrathCasting(state);
					return true;
				},()=>false)(manaDrain.wizard);
			case CastingStatus.interrupted:
				return false;
			case CastingStatus.finished:
				return state.movingObjectById!((obj){
					auto hands=obj.hands;
					Vector3f start=isNaN(hands[0].x)?hands[1]:isNaN(hands[1].x)?hands[0]:0.5f*(hands[0]+hands[1]);
					if(isNaN(start.x)){
						auto hbox=obj.sacObject.hitbox(Quaternionf.identity(),AnimationState.stance1,0);
						auto offset=Vector3f(0.0f,hbox[1].y+0.75f,hbox[1].z+0.5f);
						start=rotate(obj.rotation,offset)+obj.position;
					}
					wrath(obj.id,obj.side,start,wrathCast.target,spell,state);
					return false;
				},()=>false)(manaDrain.wizard);
		}
	}
}
void animateWrath(B)(ref Wrath!B wrath,ObjectState!B state){
	enum numParticles=5;
	foreach(i;0..numParticles){
		auto sacParticle=SacParticle!B.get(ParticleType.wrathCasting);
		static immutable Vector3f[2] bounds=[-0.2f*Vector3f(1.0f,1.0f,1.0f),0.2f*Vector3f(1.0f,1.0f,1.0f)];
		auto position=wrath.position-state.uniform(0.0f,1.0f)*wrath.velocity/updateFPS+state.uniform(bounds);
		auto velocity=Vector3f(0.0f,0.0f,0.0f);
		auto scale=1.0f;
		auto lifetime=31;
		auto frame=0;
		state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
	}
}
int collisionTarget(alias hitbox,alias filter=None,B,T...)(int side,Vector3f position,ObjectState!B state,T args){
	static struct CollisionState{
		int target=0;
		int rank;
		double distanceSqr=float.infinity;
	}
	static void handleCollision(ProximityEntry entry,int side,Vector3f position,CollisionState* collisionState,ObjectState!B state,T args){
		if(!entry.isObstacle) return;
		static if(!is(filter==None)) if(!filter(entry,state,args)) return;
		auto distanceSqr=boxPointDistanceSqr(entry.hitbox,position);
		auto validRank=state.objectById!((obj,state,side)=>tuple(obj.isValidAttackTarget(state),rank(state.sides.getStance(side,.side(obj,state)))))(entry.id,state,side);
		auto valid=validRank[0], rank=validRank[1];
		if(!valid) rank+=3;
		if(!collisionState.target||tuple(rank,distanceSqr)<tuple(collisionState.rank,collisionState.distanceSqr)){
			collisionState.target=entry.id;
			collisionState.rank=rank;
			collisionState.distanceSqr=distanceSqr;
		}
	}
	auto collisionState=CollisionState();
	state.proximity.collide!handleCollision(moveBox(hitbox,position),side,position,&collisionState,state,args);
	return collisionState.target;
}
void collisionTargets(alias f,alias filter=None,bool uniqueBuildingIds=false,bool keepNonObstacles=false,B,T...)(Vector3f[2] hitbox,ObjectState!B state,T args){
	static struct CollisionState{ SmallArray!(ProximityEntry,32) targets; }
	static void handleCollision(ProximityEntry entry,CollisionState* collisionState,ObjectState!B state,T args){
		static if(!keepNonObstacles) if(!entry.isObstacle) return;
		static if(!is(filter==None)) if(!filter(entry,state,args)) return;
		collisionState.targets~=entry;
	}
	auto collisionState=CollisionState();
	state.proximity.collide!handleCollision(hitbox,&collisionState,state,args);
	auto id(ref ProximityEntry entry){ // TODO: only compute this once?
		static if(uniqueBuildingIds){
			if(state.isValidTarget(entry.id,TargetType.building)){
				auto cand=state.staticObjectById!((ref obj)=>obj.buildingId,()=>0)(entry.id);
				return cand?cand:entry.id;
			}
		}
		return entry.id;
	}
	auto center=boxCenter(hitbox); // TODO: pass this as argument?
	auto compare(string op)(ref ProximityEntry a,ref ProximityEntry b){
		static if(op=="==") return id(a)==id(b);
		static if(op=="<"){
			auto ida=id(a),idb=id(b);
			if(ida<idb) return true;
			if(ida>idb) return false;
			return boxPointDistanceSqr(a.hitbox,center)<boxPointDistanceSqr(b.hitbox,center);
		}
	}
	foreach(ref entry;collisionState.targets[].sort!(compare!"<").uniq!(compare!"==")) f(entry,state,args);
}
enum wrathSize=0.1f;
static immutable Vector3f[2] wrathHitbox=[-0.5f*wrathSize*Vector3f(1.0f,1.0f,1.0f),0.5f*wrathSize*Vector3f(1.0f,1.0f,1.0f)];
int wrathCollisionTarget(B)(int side,Vector3f position,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state,int side){
		return entry.isProjectileObstacle&&state.objectById!(.side)(entry.id,state)!=side;
	}
	return collisionTarget!(wrathHitbox,filter)(side,position,state,side);
}
void wrathExplosion(B)(ref Wrath!B wrath,int target,ObjectState!B state){
	wrath.status=WrathStatus.exploding;
	playSoundAt("hhtr",wrath.position,state,4.0f);
	if(state.isValidTarget(target)) dealSpellDamage(target,wrath.spell,wrath.wizard,wrath.side,wrath.velocity,DamageMod.splash,state);
	else target=0;
	dealSplashSpellDamageAt(target,wrath.spell,wrath.spell.damageRange,wrath.wizard,wrath.side,wrath.position,DamageMod.none,state);
	enum numParticles1=200;
	enum numParticles2=400;
	auto sacParticle1=SacParticle!B.get(ParticleType.wrathExplosion1);
	auto sacParticle2=SacParticle!B.get(ParticleType.wrathExplosion2);
	foreach(i;0..numParticles1+numParticles2){
		auto direction=state.uniformDirection();
		auto velocity=state.uniform(0.75f,3.0f)*direction;
		auto scale=i<numParticles1?2.25f:1.5f;
		auto lifetime=i<numParticles1?31:63;
		auto frame=0;
		auto position=wrath.position;
		if(i<numParticles1) position+=0.1f*velocity;
		state.addParticle(Particle!B(i<numParticles1?sacParticle1:sacParticle2,position,velocity,scale,lifetime,frame));
	}
	enum numParticles3=200;
	auto sacParticle3=SacParticle!B.get(ParticleType.wrathParticle);
	foreach(i;0..numParticles3){
		auto direction=state.uniformDirection();
		auto velocity=state.uniform(5.0f,15.0f)*direction;
		auto scale=state.uniform(0.75f,1.5f);
		auto lifetime=63;
		auto frame=0;
		state.addParticle(Particle!B(sacParticle3,wrath.position,velocity,scale,lifetime,frame));
	}
}
enum wrathFlyingHeight=0.5f;
bool accelerateTowards(T,B)(ref T spell_,Vector3f targetCenter,Vector3f predictedCenter,float targetFlyingHeight,ObjectState!B state){
	with(spell_){
		auto predictedDistance=predictedCenter-position;
		auto acceleration=predictedDistance.normalized*spell.acceleration;
		velocity+=acceleration;
		Vector3f capVelocity(Vector3f velocity){
			if(velocity.length>spell.speed) velocity=velocity.normalized*spell.speed;
			if(velocity.length>updateFPS*predictedDistance.length) velocity=velocity.normalized*predictedDistance.length*updateFPS;
			return velocity;
		}
		velocity=capVelocity(velocity);
		auto newPosition=position+velocity/updateFPS;
		if(state.isOnGround(position)){
			auto height=state.getGroundHeight(position);
			auto flyingHeight=min(targetFlyingHeight,0.75f*(targetCenter.xy-position.xy).length);
			if(newPosition.z<height+flyingHeight){
				auto nvel=velocity;
				nvel.z+=(height+flyingHeight-newPosition.z)*updateFPS;
				newPosition=position+capVelocity(nvel)/updateFPS;
			}
		}
		position=newPosition;
		return (targetCenter-position).lengthsqr<0.05f^^2;
	}
}
bool accelerateTowards(T,B)(ref T spell_,float targetFlyingHeight,ObjectState!B state){
	with(spell_){
		auto targetCenter=target.center(state);
		target.position=targetCenter;
		auto predictedCenter=predictor.predictCenter(position,spell.speed,target,state);
		return accelerateTowards(spell_,targetCenter,predictedCenter,targetFlyingHeight,state);
	}
}
bool updateWrath(B)(ref Wrath!B wrath,ObjectState!B state){
	with(wrath){
		final switch(wrath.status){
			case WrathStatus.flying:
				bool closeToTarget=wrath.accelerateTowards(wrathFlyingHeight,state);
				wrath.animateWrath(state);
				auto target=wrathCollisionTarget(side,position,state);
				if(state.isValidTarget(target)) wrath.wrathExplosion(target,state);
				else if(state.isOnGround(position)){
					if(position.z<state.getGroundHeight(position))
						wrath.wrathExplosion(0,state);
				}
				if(status!=WrathStatus.exploding && closeToTarget)
					wrath.wrathExplosion(wrath.target.id,state);
				return true;
			case WrathStatus.exploding:
				return ++frame<64;
		}
	}
}

bool updateFireballCasting(B)(ref FireballCasting!B fireballCast,ObjectState!B state){
	with(fireballCast){
		fireball.target.position=fireball.target.center(state);
			final switch(manaDrain.update(state)){
				case CastingStatus.underway:
					return state.movingObjectById!((obj){
						fireball.position=obj.fireballCastingPosition(state);
						fireball.rotation=fireball.rotationUpdate*fireball.rotation;
						obj.animatePyroCasting(state);
						frame+=1;
						return true;
					},()=>false)(manaDrain.wizard);
				case CastingStatus.interrupted:
					return false;
				case CastingStatus.finished:
					.fireball(fireball,state);
					return false;
			}
	}
}
void animateFireball(B)(ref Fireball!B fireball,Vector3f oldPosition,ObjectState!B state){
	with(fireball){
		rotation=rotationUpdate*rotation;
		enum numParticles=8;
		auto sacParticle1=SacParticle!B.get(ParticleType.firy);
		auto sacParticle2=SacParticle!B.get(ParticleType.fireball);
		auto velocity=Vector3f(0.0f,0.0f,0.0f);
		auto lifetime=31;
		auto scale=1.5f;
		auto frame=0;
		foreach(i;0..numParticles){
			auto sacParticle=i!=0?sacParticle1:sacParticle2;
			auto position=oldPosition*((cast(float)numParticles-1-i)/numParticles)+position*(cast(float)(i+1)/numParticles);
			position+=0.15f*state.uniformDirection();
			state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
		}
	}
}
enum fireballSize=0.5f; // TODO: use bounding box from sac object
static immutable Vector3f[2] fireballHitbox=[-0.5f*fireballSize*Vector3f(1.0f,1.0f,1.0f),0.5f*fireballSize*Vector3f(1.0f,1.0f,1.0f)];
int fireballCollisionTarget(B)(int side,Vector3f position,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state,int side){
		return entry.isProjectileObstacle&&state.objectById!(.side)(entry.id,state)!=side;
	}
	return collisionTarget!(fireballHitbox,filter)(side,position,state,side);
}

void animateFireballExplosion(int reduceParticles=1,B)(Vector3f position,ObjectState!B state,float scale_=1.0f){
	//explosionParticles(fireball.position,state);
	enum numParticles1=200/reduceParticles;
	enum numParticles2=800/reduceParticles;
	auto sacParticle1=SacParticle!B.get(ParticleType.explosion);
	auto sacParticle2=SacParticle!B.get(ParticleType.explosion2);
	foreach(i;0..numParticles1+numParticles2){
		auto direction=state.uniformDirection();
		auto velocity=scale_*(i<numParticles1?1.0f:1.5f)*state.uniform(1.5f,6.0f)*direction;
		auto scale=scale_;
		auto lifetime=31;
		auto frame=0;
		state.addParticle(Particle!B(i<numParticles1?sacParticle1:sacParticle2,position,velocity,scale,lifetime,frame));
	}
	enum numParticles3=300/reduceParticles;
	auto sacParticle3=SacParticle!B.get(ParticleType.ashParticle);
	foreach(i;0..numParticles3){
		auto direction=state.uniformDirection();
		auto velocity=scale_*state.uniform(7.5f,15.0f)*direction;
		auto scale=scale_*state.uniform(0.75f,1.5f);
		auto lifetime=95;
		auto frame=0;
		state.addParticle(Particle!B(sacParticle3,position,velocity,scale,lifetime,frame));
	}
	enum numParticles4=75;
	auto sacParticle4=SacParticle!B.get(ParticleType.smoke);
	foreach(i;0..numParticles4){
		auto direction=state.uniformDirection();
		auto velocity=scale_*state.uniform(0.5f,2.0f)*direction+Vector3f(0.0f,0.0f,0.5f);
		auto scale=scale_;
		auto lifetime=127;
		auto frame=0;
		state.addParticle(Particle!B(sacParticle4,position,velocity,scale,lifetime,frame));
	}
}

void fireballExplosion(B)(ref Fireball!B fireball,int target,ObjectState!B state){
	playSpellSoundTypeAt(SoundType.explodingFireball,fireball.position,state,8.0f);
	if(state.isValidTarget(target)){
		dealSpellDamage(target,fireball.spell,fireball.wizard,fireball.side,fireball.velocity,DamageMod.ignite|DamageMod.splash,state);
		setAblaze(target,updateFPS,false,0.0f,fireball.wizard,fireball.side,DamageMod.ignite,state);
	}else target=0;
	static bool callback(int target,int wizard,int side,ObjectState!B state){
		setAblaze(target,updateFPS,false,0.0f,wizard,side,DamageMod.none,state);
		return true;
	}
	dealSplashSpellDamageAt!callback(target,fireball.spell,fireball.spell.damageRange,fireball.wizard,fireball.side,fireball.position,DamageMod.ignite,state,fireball.wizard,fireball.side,state);
	animateFireballExplosion(fireball.position,state);
}

enum fireballFlyingHeight=0.5f;
bool updateFireball(B)(ref Fireball!B fireball,ObjectState!B state){
	with(fireball){
		auto oldPosition=position;
		bool closeToTarget=fireball.accelerateTowards(fireballFlyingHeight,state);
		rotation=rotationUpdate*rotation;
		fireball.animateFireball(oldPosition,state);
		auto target=fireballCollisionTarget(side,position,state);
		if(state.isValidTarget(target)){
			fireball.fireballExplosion(target,state);
			return false;
		}
		if(state.isOnGround(position)){
			if(position.z<state.getGroundHeight(position)){
				fireball.fireballExplosion(0,state);
				return false;
			}
		}
		if(closeToTarget){
			fireball.fireballExplosion(fireball.target.id,state);
			return false;
		}
		return true;
	}
}

void animateRockCasting(B)(ref MovingObject!B wizard,ObjectState!B state){
	auto castParticle=SacParticle!B.get(ParticleType.dirt);
	wizard.animateCasting!(true,1)(castParticle,state);
}

bool updateRockCasting(B)(ref RockCasting!B rockCast,ObjectState!B state){
	with(rockCast){
		rock.target.position=rock.target.center(state);
		final switch(manaDrain.update(state)){
			case CastingStatus.underway:
				return state.movingObjectById!((obj){
					rock.position=obj.rockCastingPosition(state);
					rock.position.z+=rockBuryDepth*min(1.0f,float(frame)/castingTime);
					obj.animateRockCasting(state);
					frame+=1;
					return true;
				},()=>false)(manaDrain.wizard);
			case CastingStatus.interrupted:
				return false;
			case CastingStatus.finished:
				rock.position.z=max(rock.position.z,state.getHeight(rock.position)); // for robustness
				.rock(rock,state);
				return false;
		}
	}
}
void animateEmergingRock(B)(ref Rock!B rock,ObjectState!B state){
	screenShake(rock.position,updateFPS/2,0.75f,25.0f,state);
	enum numParticles=50;
	auto sacParticle=SacParticle!B.get(ParticleType.rock);
	foreach(i;0..numParticles){
		auto direction=state.uniformDirection();
		auto velocity=state.uniform(3.0f,6.0f)*direction;
		velocity.z*=2.5f;
		auto scale=state.uniform(0.25f,0.75f);
		auto lifetime=159;
		auto frame=0;
		state.addParticle(Particle!B(sacParticle,rock.position,velocity,scale,lifetime,frame));
	}
	enum numParticles4=20;
	auto sacParticle4=SacParticle!B.get(ParticleType.dust);
	foreach(i;0..numParticles4){
		auto direction=state.uniformDirection();
		auto position=rock.position+0.75f*direction;
		auto velocity=0.2f*direction;
		auto scale=3.0f;
		auto frame=0;
		auto lifetime=31;
		state.addParticle(Particle!B(sacParticle4,position,velocity,scale,lifetime,frame));
	}

}
void animateRock(B)(ref Rock!B rock,Vector3f oldPosition,ObjectState!B state){
	with(rock){
		rotation=rotationUpdate*rotation;
		enum numParticles=2;
		auto sacParticle=SacParticle!B.get(ParticleType.dust);
		auto velocity=Vector3f(0.0f,0.0f,0.0f);
		auto lifetime=31;
		auto scale=1.5f;
		auto frame=0;
		foreach(i;0..numParticles){
			auto position=oldPosition*((cast(float)numParticles-1-i)/numParticles)+position*(cast(float)(i+1)/numParticles);
			position+=0.3f*state.uniformDirection();
			state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
		}
	}
}
enum rockSize=2.0f; // TODO: use bounding box from sac object
static immutable Vector3f[2] rockHitbox=[-0.5f*rockSize*Vector3f(1.0f,1.0f,1.0f),0.5f*rockSize*Vector3f(1.0f,1.0f,1.0f)];
int rockCollisionTarget(B)(int immuneId,int side,Vector3f position,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state,int immuneId){
		return entry.isProjectileObstacle&&entry.id!=immuneId;
	}
	return collisionTarget!(rockHitbox,filter)(side,position,state,immuneId);
}

void rockExplosion(B)(ref Rock!B rock,int target,ObjectState!B state){
	playSpellSoundTypeAt(SoundType.explodingRock,rock.position,state,8.0f);
	if(state.isValidTarget(target)) dealSpellDamage(target,rock.spell,rock.wizard,rock.side,rock.velocity,DamageMod.none,state);
	enum numParticles3=100;
	auto sacParticle3=SacParticle!B.get(ParticleType.rock);
	foreach(i;0..numParticles3){
		auto direction=state.uniformDirection();
		auto velocity=state.uniform(7.5f,15.0f)*direction;
		auto scale=state.uniform(1.0f,2.5f);
		auto lifetime=95;
		auto frame=0;
		state.addParticle(Particle!B(sacParticle3,rock.position,velocity,scale,lifetime,frame));
	}
	enum numParticles4=20;
	auto sacParticle4=SacParticle!B.get(ParticleType.dirt);
	foreach(i;0..numParticles4){
		auto direction=state.uniformDirection();
		auto position=rock.position+0.75f*direction;
		auto velocity=Vector3f(0.0f,0.0f,0.0f);
		auto scale=3.0f;
		auto frame=state.uniform(2)?0:state.uniform(24);
		auto lifetime=63-frame;
		state.addParticle(Particle!B(sacParticle4,position,velocity,scale,lifetime,frame));
	}
}

enum rockWarmupTime=updateFPS/4;
enum rockFloatingHeight=7.0f;
bool updateRock(B)(ref Rock!B rock,ObjectState!B state){
	with(rock){
		auto oldPosition=position;
		auto targetCenter=target.center(state);
		target.position=targetCenter;
		auto distance=targetCenter-position;
		auto acceleration=distance.normalized*spell.acceleration;
		velocity+=acceleration;
		Vector3f capVelocity(Vector3f velocity){
			if(velocity.length>spell.speed) velocity=velocity.normalized*spell.speed; // TODO: why?
			if(velocity.length>updateFPS*distance.length) velocity=velocity.normalized*distance.length*updateFPS;
			return velocity;
		}
		velocity=capVelocity(velocity);
		auto newPosition=position+velocity/updateFPS;
		auto height=state.getHeight(position);
		auto floatingHeight=min(rockFloatingHeight,rock.frame<rockWarmupTime?float.infinity:0.75f*(targetCenter.xy-position.xy).length);
		if(newPosition.z<height+floatingHeight){
			auto nvel=velocity;
			nvel.z+=(height+floatingHeight-newPosition.z)*updateFPS;
			newPosition=position+capVelocity(nvel)/updateFPS;
		}
		position=newPosition;
		rock.animateRock(oldPosition,state);
		if(++rock.frame<rockWarmupTime) return true;
		auto target=rockCollisionTarget(wizard,side,position,state);
		if(state.isValidTarget(target)){
			rock.rockExplosion(target,state);
			return false;
		}
		if(state.isOnGround(position)){
			if(position.z<state.getGroundHeight(position)){
				rock.rockExplosion(0,state);
				return false;
			}
		}
		if(distance.length<0.05f){
			rock.rockExplosion(rock.target.id,state);
			return false;
		}
		return true;
	}
}

void relocate(B)(ref Swarm!B swarm,Vector3f newPosition){
	auto diff=newPosition-swarm.position;
	swarm.position=newPosition;
	foreach(i;0..swarm.bugs.length){
		swarm.bugs[i].position+=diff;
		swarm.bugs[i].targetPosition+=diff;
	}
}

bool updateSwarmCasting(B)(ref SwarmCasting!B swarmCast,ObjectState!B state){
	with(swarmCast){
		swarm.target.position=swarm.target.center(state);
			final switch(manaDrain.update(state)){
				case CastingStatus.underway:
					if(!state.movingObjectById!((ref obj){
						swarm.relocate(obj.swarmCastingPosition(state));
						if(swarm.frame>0) swarm.addBugs(obj,state);
						return swarm.updateSwarm(state);
					},()=>false)(manaDrain.wizard))
						goto case CastingStatus.interrupted;
					return true;
				case CastingStatus.interrupted:
					swarm.status=SwarmStatus.dispersing;
					.swarm(swarm,state);
					return false;
				case CastingStatus.finished:
					swarm.status=SwarmStatus.flying;
					.swarm(move(swarm),state);
					return false;
			}
	}
}

enum swarmSize=0.3f;
static immutable Vector3f[2] swarmHitbox=[-0.5f*swarmSize*Vector3f(1.0f,1.0f,1.0f),0.5f*swarmSize*Vector3f(1.0f,1.0f,1.0f)];
int swarmCollisionTarget(B)(int side,Vector3f position,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state,int side){
		return entry.isProjectileObstacle&&state.objectById!(.side)(entry.id,state)!=side;
	}
	return collisionTarget!(swarmHitbox,filter)(side,position,state,side);
}

Vector3f makeTargetPosition(B)(ref Swarm!B swarm,float radius,ObjectState!B state){
	return swarm.position+state.uniform(0.0f,radius)*state.uniformDirection();
}

Vector3f[2] swarmHands(B)(ref MovingObject!B wizard){
	auto hands=wizard.hands;
	if(isNaN(hands[0].x)&&isNaN(hands[1].x)){
		auto hbox=wizard.sacObject.hitbox(Quaternionf.identity(),AnimationState.stance1,0);
		auto offset=Vector3f(0.0f,hbox[1].y,hbox[1].z);
		hands[0]=rotate(wizard.rotation,offset)+wizard.position;
	}
	return hands;
}

enum swarmFlyingHeight=1.25f;
enum swarmDispersingFrames=2*updateFPS;
bool addBugs(B)(ref Swarm!B swarm,ref MovingObject!B wizard,ObjectState!B state){
	enum totalBugs=250;
	auto num=(totalBugs-swarm.bugs.length+swarm.frame-1)/swarm.frame;
	auto hands=swarmHands(wizard);
	foreach(i;0..num){
		auto position=randomHand(hands,state);
		auto targetPosition=swarm.makeTargetPosition(1.0f,state);
		auto velocity=(targetPosition-position).normalized*0.01f*swarm.spell.speed;
		auto bug=makeBug!B(position,velocity,targetPosition);
		swarm.bugs~=bug;
	}
	return true;
}
void updateBug(B)(ref Swarm!B swarm,ref Bug!B bug,ObjectState!B state){
	bug.targetPosition+=swarm.velocity/updateFPS;
	auto spell=swarm.spell;
	auto bugAcceleration=1.0f*spell.acceleration;
	auto bugSpeed=1.5f*spell.speed;
	auto distance=bug.targetPosition-bug.position;
	auto acceleration=distance.normalized*min(2.0f*distance.length,1.0f)*bugAcceleration;
	bug.velocity+=acceleration;
	static import std.math;
	static immutable float zdamp=std.math.exp(std.math.log(0.01f)/updateFPS);
	bug.velocity.z=zdamp*bug.velocity.z+(1.0f-zdamp)*swarm.velocity.z;
	Vector3f capVelocity(Vector3f velocity){
		if(velocity.length>bugSpeed) velocity=velocity.normalized*bugSpeed;
		if(velocity.length>updateFPS*distance.length) velocity=velocity.normalized*distance.length*updateFPS;
		return velocity;
	}
	bug.velocity=capVelocity(bug.velocity);
	bug.position+=bug.velocity/updateFPS;
	auto dist=(bug.targetPosition-bug.position).lengthsqr;
	if(dist<1e-3^^2||!state.uniform(updateFPS/2)){
		bug.velocity*=0.25f;
		bug.targetPosition=swarm.makeTargetPosition(2.5f/max(2.0f,dist),state);
	}
	auto radius=bug.position-swarm.position;
	auto radialComponent=dot(bug.velocity,radius);
	if(radius.lengthsqr>1.0f){
		auto radialDir=radialComponent*radius.normalized;
		auto rest=bug.velocity-radialDir;
		static import std.math;
		static immutable float damp1=std.math.exp(std.math.log(0.01f)/updateFPS);
		static immutable float damp2=std.math.exp(std.math.log(7.0f)/updateFPS);
		auto factor=radialComponent>0.0f?damp1:damp2;
		bug.velocity=rest+factor*radialDir;
	}
}
bool updateBugs(B)(ref Swarm!B swarm,ObjectState!B state){
	foreach(i;0..swarm.bugs.length)
		swarm.updateBug(swarm.bugs[i],state);
	return true;
}
void disperseBug(B)(ref Swarm!B swarm,ref Bug!B bug,ObjectState!B state){
	if(swarm.frame%4==0){
		bug.targetPosition=bug.position+0.5f*(0.5f*(bug.position-swarm.position).normalized+state.uniformDirection()).normalized;
		bug.targetPosition.x+=cos(bug.targetPosition.y)/updateFPS;
		bug.targetPosition.y+=cos(bug.targetPosition.x)/updateFPS;
	}
	static import std.math;
	static immutable float damp=std.math.exp(std.math.log(0.01f)/updateFPS);
	bug.position=damp*bug.targetPosition+(1.0f-damp)*bug.position;
}
void disperseBugs(B)(ref Swarm!B swarm,ObjectState!B state){
	foreach(i;0..swarm.bugs.length)
		swarm.disperseBug(swarm.bugs[i],state);
}
void swarmHit(B)(ref Swarm!B swarm,int target,ObjectState!B state){
	swarm.status=SwarmStatus.dispersing;
	playSoundAt("zzub",swarm.position,state,4.0f);
	if(state.isValidTarget(target)){
		dealSpellDamage(target,swarm.spell,swarm.wizard,swarm.side,swarm.velocity,DamageMod.splash,state);
		static void hit(T)(ref T obj,Swarm!B *swarm,ObjectState!B state){
			static if(is(T==MovingObject!B)){
				obj.creatureStats.mana=max(0.0f,obj.creatureStats.mana-0.25f*obj.creatureStats.maxMana);
			}
			enum numParticles=128;
			auto sacParticle=SacParticle!B.get(ParticleType.swarmHit);
			auto hitbox=obj.hitbox;
			auto center=boxCenter(hitbox);
			(*swarm).relocate(center);
			swarm.velocity=Vector3f(0.0f,0.0f,0.0f);
			foreach(i;0..numParticles){
				auto position=state.uniform(scaleBox(hitbox,1.2f));
				auto velocity=Vector3f(position.x-center.x,position.y-center.y,0.0f).normalized;
				velocity.z=3.0f;
				auto scale=1.0f;
				int lifetime=63;
				int frame=0;
				state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
			}
		}
		state.objectById!hit(target,&swarm,state);
	}else target=0;
	dealSplashSpellDamageAt(target,swarm.spell,swarm.spell.damageRange,swarm.wizard,swarm.side,swarm.position,DamageMod.none,state);
}
bool updateSwarm(B)(ref Swarm!B swarm,ObjectState!B state){
	with(swarm){
		final switch(status){
			case SwarmStatus.casting:
				frame-=1;
				return swarm.updateBugs(state);
			case SwarmStatus.flying:
				bool closeToTarget=swarm.accelerateTowards(swarmFlyingHeight,state);
				auto target=swarmCollisionTarget(side,position,state);
				if(state.isValidTarget(target)) swarm.swarmHit(target,state);
				else if(state.isOnGround(position)){
					if(position.z<state.getGroundHeight(position))
						swarm.swarmHit(0,state);
				}
				if(status!=SwarmStatus.dispersing && closeToTarget)
					swarm.swarmHit(swarm.target.id,state);
				return swarm.updateBugs(state);
			case SwarmStatus.dispersing:
				swarm.disperseBugs(state);
				return ++frame<swarmDispersingFrames;
		}
	}
}

void animateSkinOfStoneCasting(B)(ref SkinOfStoneCasting!B skinOfStoneCast,ObjectState!B state,int lifetime=12){
	with(skinOfStoneCast){
		auto castParticle=SacParticle!B.get(ParticleType.dirt);
		auto positions=state.movingObjectById!((ref wizard,castParticle){
			wizard.animateCasting!(true,1)(castParticle,state);
			return tuple(wizard.position,wizard.center);
		},()=>Tuple!(Vector3f,Vector3f).init)(manaDrain.wizard,castParticle);
		auto position=positions[0], center=positions[1];
		enum numParticles=30;
		auto progress=min(float(frame)/castingTime,1.0f);
		foreach(k;0..numParticles){
			auto φ=state.uniform(-pi!float,pi!float);
			auto offset=2.0f*(scale+0.5f)*Vector3f(cos(φ),sin(φ),0.0f);
			auto pposition=(1.0f-0.9f*progress)*(position+offset)+0.9f*progress*center;
			pposition.z=(1.0f-progress)*(position.z+offset.z)+progress*center.z;
			auto pvelocity=Vector3f(0.0f,0.0f,0.0f);
			auto scale=2.0f*skinOfStoneCast.scale;
			auto frame=skinOfStoneCast.frame;
			state.addParticle(Particle!B(castParticle,pposition,pvelocity,scale,lifetime,frame));
		}
	}
}
bool updateSkinOfStoneCasting(B)(ref SkinOfStoneCasting!B skinOfStoneCast,ObjectState!B state){
	with(skinOfStoneCast){
		frame+=1;
		final switch(manaDrain.update(state)){
			case CastingStatus.underway:
				skinOfStoneCast.animateSkinOfStoneCasting(state);
				return true;
			case CastingStatus.interrupted:
				skinOfStoneCast.animateSkinOfStoneCasting(state,31);
				return false;
			case CastingStatus.finished:
				state.movingObjectById!(skinOfStone,()=>false)(manaDrain.wizard,spell,state);
				return false;
		}
	}
}

bool updateSkinOfStone(B)(ref SkinOfStone!B skinOfStone,ObjectState!B state){
	with(skinOfStone){
		if(!state.isValidTarget(target,TargetType.creature)) return false;
		++frame;
		static bool check(ref MovingObject!B obj){
			assert(obj.creatureStats.effects.skinOfStone);
			return obj.creatureState.mode.canShield;
		}
		if(!state.movingObjectById!(check,()=>false)(target)||frame>=spell.duration*updateFPS){
			static void removeSkinOfStone(B)(ref MovingObject!B object,ObjectState!B state){
				assert(object.creatureStats.effects.skinOfStone);
				object.creatureStats.effects.skinOfStone=false;
				auto hitbox=object.hitbox;
				auto center=boxCenter(hitbox);
				playSoundAt("ksts",center,state);
				enum numParticles=64;
				auto sacParticle=SacParticle!B.get(ParticleType.rock);
				foreach(i;0..numParticles){
					auto position=state.uniform(scaleBox(hitbox,0.9f));
					auto direction=state.uniformDirection();
					auto velocity=state.uniform(2.5f,3.0f)*direction;
					auto scale=state.uniform(1.0f,2.5f);
					auto lifetime=95;
					auto frame=0;
					state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
				}
			}
			state.movingObjectById!(removeSkinOfStone,(){})(target,state);
			return false;
		}
		return true;
	}
}

void animateEtherealFormCasting(B)(ref MovingObject!B wizard,ObjectState!B state){
	auto castParticle=SacParticle!B.get(ParticleType.heal);
	wizard.animateCasting!false(castParticle,state);
}
bool updateEtherealFormCasting(B)(ref EtherealFormCasting!B etherealFormCast,ObjectState!B state){
	with(etherealFormCast){
		final switch(manaDrain.update(state)){
			case CastingStatus.underway:
				state.movingObjectById!(animateEtherealFormCasting,(){})(manaDrain.wizard,state);
				return true;
			case CastingStatus.interrupted:
				return false;
			case CastingStatus.finished:
				state.movingObjectById!(etherealForm,()=>false)(manaDrain.wizard,spell,state);
				return false;
		}
	}
}
void animateEtherealFormTransition(B)(ref MovingObject!B wizard,ObjectState!B state){
	playSpellSoundTypeAt(SoundType.lightning,wizard.id,state,2.0f);
	enum numParticles=64;
	auto sacParticle=SacParticle!B.get(ParticleType.etherealFormSpark);
	auto hitbox=wizard.hitbox;
	foreach(i;0..numParticles){
		auto position=state.uniform(scaleBox(hitbox,0.9f));
		auto direction=state.uniformDirection();
		auto velocity=state.uniform(1.0,2.0f)*direction;
		velocity.z*=1.5f;
		velocity.z+=1.5f;
		auto scale=state.uniform(1.0f,2.5f);
		auto lifetime=63;
		auto frame=0;
		state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
	}
}
bool updateEtherealForm(B)(ref EtherealForm!B etherealForm,ObjectState!B state){
	with(etherealForm){
		if(!state.isValidTarget(target,TargetType.creature)) return false;
		updateRenderMode(target,state);
		++frame;
		if(status!=EtherealFormStatus.fadingIn){
			static bool check(ref MovingObject!B obj){
				assert(obj.creatureStats.effects.etherealForm);
				return obj.creatureState.mode.canShield;
			}
			if(!state.movingObjectById!(check,()=>false)(target)||frame>=spell.duration*updateFPS)
				status=EtherealFormStatus.fadingIn;
		}
		void updateAlpha(){
			state.setAlpha(target,1.0f+progress*(targetAlpha-1.0f),1.0f+progress*(targetEnergy-1.0f));
		}
		final switch(status){
			case EtherealFormStatus.fadingOut:
				progress=min(1.0f,progress+1.0f/numFrames);
				if(progress==1.0f) status=EtherealFormStatus.stationary;
				updateAlpha();
				break;
			case EtherealFormStatus.stationary:
				state.movingObjectById!(.animateGhost,(){})(target,state);
				break;
			case EtherealFormStatus.fadingIn:
				state.movingObjectById!(.animateGhost,(){})(target,state);
				progress=max(0.0f,progress-1.0f/numFrames);
				if(progress==0.0f){
					static void removeEtherealForm(B)(ref MovingObject!B object){
						assert(object.creatureStats.effects.etherealForm);
						object.creatureStats.effects.etherealForm=false;
					}
					state.movingObjectById!(removeEtherealForm,(){})(target);
					updateRenderMode(target,state);
					return false;
				}
				updateAlpha();
				break;
		}
		return true;
	}
}

void animateFireformCasting(B)(ref MovingObject!B wizard,ObjectState!B state){
	auto castParticle=SacParticle!B.get(ParticleType.firy);
	auto hands=wizard.hands;
	foreach(i;0..2){
		auto hposition=hands[i];
		if(isNaN(hposition.x)) continue;
		foreach(k;0..3){
			auto position=hposition;
			auto distance=state.uniform(0.5f,1.5f);
			auto fullLifetime=castParticle.numFrames/float(updateFPS);
			auto lifetime=cast(int)(castParticle.numFrames*state.uniform(0.0f,1.0f));
			auto velocity=Vector3f(0.0f,0.0f,distance/fullLifetime);
			auto scale=1.0f;
			auto frame=0;
			state.addParticle(Particle!B(castParticle,position,velocity,scale,lifetime,frame));
		}
	}
}

void spawnFireformParticles(B)(ref MovingObject!B wizard,int numParticles,ObjectState!B state){
	auto sacParticle=SacParticle!B.get(ParticleType.fire);
	auto hitbox=wizard.sacObject.hitbox(Quaternionf.identity(),wizard.animationState,wizard.frame/updateAnimFactor);
	auto center=boxCenter(hitbox);
	auto size=boxSize(hitbox);
	size.x=size.y=max(size.x,size.y)+1.0f;
	size.z+=0.5f;
	auto scale=0.5f*max(1.0f,cbrt(size.x*size.y*size.z));
	foreach(k;0..numParticles){
		auto φ=state.uniform(-pi!float,pi!float);
		auto pposition=center+state.uniformDirection()*0.5f*size;
		auto pvelocity=Vector3f(0.0f,0.0f,0.0f);
		auto lifetime=31;
		auto frame=0;
		state.addParticle(Particle!(B,true)(sacParticle,wizard.id,true,pposition,pvelocity,scale,lifetime,frame));
	}
}

enum fireformParticleRate=50;
void animateFireformCasting(B)(ref FireformCasting!B fireformCast,ObjectState!B state){
	with(fireformCast){
		auto progress=min(float(frame)/castingTime,1.0f);
		auto numParticlesF=fireformParticleRate*progress;
		auto numParticles=cast(int)floor(numParticlesF)+(state.uniform(0.0f,1.0f)<=numParticlesF-floor(numParticlesF));
		state.movingObjectById!((ref wizard,numParticles,state){
			wizard.animateFireformCasting(state);
			wizard.spawnFireformParticles(numParticles,state);
		},(){})(manaDrain.wizard,numParticles,state);
	}
}
bool updateFireformCasting(B)(ref FireformCasting!B fireformCast,ObjectState!B state){
	with(fireformCast){
		frame+=1;
		if(--soundTimer==0) soundTimer=playSoundAt!true("5plf",manaDrain.wizard,state,fireformGain);
		final switch(manaDrain.update(state)){
			case CastingStatus.underway:
				fireformCast.animateFireformCasting(state);
				return true;
			case CastingStatus.interrupted:
				state.movingObjectById!((ref obj){ obj.creatureStats.effects.fireform=false; },(){})(manaDrain.wizard);
				return false;
			case CastingStatus.finished:
				state.movingObjectById!(fireform,()=>false)(manaDrain.wizard,spell,state,soundTimer);
				return false;
		}
	}
}

void ignite(B)(ref MovingObject!B obj,float damage,int attacker,int side,ObjectState!B state){
	enum numParticles=5;
	obj.dealFireDamage(0.0f,damage,attacker,side,DamageMod.peirceShield,state);
	obj.spawnFireParticles(numParticles,state);
	if(obj.creatureStats.effects.ignitionTime+updateFPS/3<state.frame)
		playSoundAt("1ngi",obj.id,state,2.0f);
	obj.creatureStats.effects.ignitionTime=state.frame;
}

bool updateFireform(B)(ref Fireform!B fireform,ObjectState!B state){
	with(fireform){
		if(!state.isValidTarget(target,TargetType.creature)) return false;
		++frame;
		if(--soundTimer==0) soundTimer=playSoundAt!true("5plf",target,state,fireformGain);
		state.movingObjectById!((ref obj,fireform,state){
			auto hitbox=obj.hitbox;
			hitbox[0]-=Vector3f(2.0f,2.0f,1.0f), hitbox[1]+=Vector3f(2.0f,2.0f,1.0f);
			static void burn(ProximityEntry target,ObjectState!B state,SacSpell!B spell,int attacker,int side){
				if(target.id==attacker) return;
				state.movingObjectById!((ref obj,damage,attacker,side,state){
					if(state.sides.getStance(side,obj.side)!=Stance.ally)
						obj.ignite(damage,attacker,side,state);
				},(){})(target.id,spell.amount/updateFPS,attacker,side,state);
			}
			collisionTargets!burn(hitbox,state,fireform.spell,obj.id,obj.side);
		},(){})(fireform.target,&fireform,state);
		static bool check(ref MovingObject!B obj,ObjectState!B state){
			assert(obj.creatureStats.effects.fireform);
			obj.spawnFireformParticles(fireformParticleRate,state);
			return obj.creatureState.mode.canShield;
		}
		if(!state.movingObjectById!(check,()=>false)(target,state)||frame>=spell.duration*updateFPS){
			static void removeFireform(B)(ref MovingObject!B object){
				assert(object.creatureStats.effects.fireform);
				object.creatureStats.effects.fireform=false;
			}
			state.movingObjectById!(removeFireform,(){})(target);
			return false;
		}
		return true;
	}
}

bool updateProtectiveSwarmCasting(B)(ref ProtectiveSwarmCasting!B protectiveSwarmCast,ObjectState!B state){
	with(protectiveSwarmCast){
		final switch(manaDrain.update(state)){
			case CastingStatus.underway:
				protectiveSwarm.status=ProtectiveSwarmStatus.casting;
				return protectiveSwarm.updateProtectiveSwarm(state);
			case CastingStatus.interrupted:
				state.movingObjectById!((ref obj){ obj.creatureStats.effects.protectiveSwarm=false; },(){})(manaDrain.wizard);
				protectiveSwarm.status=ProtectiveSwarmStatus.dispersing;
				return protectiveSwarm.updateProtectiveSwarm(state);
			case CastingStatus.finished:
				protectiveSwarm.status=ProtectiveSwarmStatus.steady;
				.protectiveSwarm(move(protectiveSwarm),state);
				return false;
		}
	}
}
Vector3f protectiveBugNewPosition(B)(Vector3f position,ObjectState!B state){
	return (position+2.5f*state.uniformDirection()).normalized;
}
Vector3f protectiveSwarmSize(B)(ref MovingObject!B wizard){
	auto hitbox=wizard.sacObject.hitbox(Quaternionf.identity(),wizard.animationState,wizard.frame/updateAnimFactor);
	auto center=boxCenter(hitbox);
	auto size=boxSize(hitbox);
	size.x=size.y=max(size.x,size.y)+2.0f;
	size.z+=1.0f;
	return size;
}
void setPositions(B)(scope ProtectiveBug!B[] bugs){
	foreach(ref bug;bugs){
		with(bug) position=progress*targetPosition+(1.0f-progress)*startPosition;
	}
}
void addBugs(B)(ref ProtectiveSwarm!B protectiveSwarm,ref MovingObject!B wizard,ObjectState!B state){
	auto size=wizard.protectiveSwarmSize;
	Vector3f rescale(Vector3f p){ return 0.5f*p*size; }
	enum totalBugs=150;
	auto num=(totalBugs-protectiveSwarm.bugs.length+protectiveSwarm.castingTime-1)/protectiveSwarm.castingTime;
	auto hands=wizard.sacObject.hands(wizard.animationState,wizard.frame/updateAnimFactor);
	if(isNaN(hands[0].x)&&isNaN(hands[1].x)){
		auto hbox=wizard.sacObject.hitbox(Quaternionf.identity(),AnimationState.stance1,0);
		hands[0]=Vector3f(0.0f,hbox[1].y,hbox[1].z);
	}
	auto scale=0.25f*max(1.0f,cbrt(size.x*size.y*size.z));
	foreach(i;0..num){
		auto position=randomHand(hands,state)/size;
		auto targetPosition=rescale(protectiveBugNewPosition(position,state));
		auto frame=state.uniform(32);
		auto scale_=scale*state.uniform(0.5f,1.75f);
		auto bug=ProtectiveBug!B(Vector3f(0.0f,0.0f,0.0f),position,targetPosition,scale_,frame);
		protectiveSwarm.bugs~=bug;
	}
	setPositions(protectiveSwarm.bugs.data[$-num..$]);
}
void updateBugs(B)(ref ProtectiveSwarm!B protectiveSwarm,ref MovingObject!B wizard,ObjectState!B state){
	auto size=wizard.protectiveSwarmSize;
	Vector3f rescale(Vector3f p){ return 0.5f*p*size; }
	foreach(ref bug;protectiveSwarm.bugs){
		bug.progress+=3.0f/updateFPS;
		if(bug.progress>=1.0f){
			bug.startPosition=bug.targetPosition;
			bug.targetPosition=rescale(protectiveBugNewPosition(bug.startPosition,state));
			bug.progress=0.0f;
		}
		bug.frame+=1;
	}
	setPositions(protectiveSwarm.bugs.data);
}

float bugDamage(B)(ref MovingObject!B obj,float damage,int attacker,int side,Vector3f attackDirection,ObjectState!B state){
	auto actualDamage=obj.dealSpellDamage(damage,attacker,side,attackDirection,DamageMod.none,state);
	if(actualDamage){
		if(obj.creatureStats.effects.buzzTime+updateFPS/3<state.frame)
			playSpellSoundTypeAt(SoundType.swarm,obj.id,state,protectiveSwarmGain);
		obj.creatureStats.effects.buzzTime=state.frame;
	}
	return actualDamage;
}

bool updateProtectiveSwarm(B)(ref ProtectiveSwarm!B protectiveSwarm,ObjectState!B state){
	with(protectiveSwarm){
		if(!state.isValidTarget(target,TargetType.creature)) return false;
		if(protectiveSwarm.status!=ProtectiveSwarmStatus.dispersing){
			if(--soundTimer==0) soundTimer=playSoundAt!true("3rws",target,state,protectiveSwarmGain);
		}
		frame+=1;
		static bool check(ref MovingObject!B obj,ProtectiveSwarm!B* protectiveSwarm,ObjectState!B state){
			if(protectiveSwarm.status==ProtectiveSwarmStatus.steady){
				auto hitbox=obj.hitbox;
				hitbox[0]-=Vector3f(4.0f,4.0f,2.0f), hitbox[1]+=Vector3f(4.0f,4.0f,2.0f);
				float totalDamage=0.0f;
				static void damage(ProximityEntry target,ObjectState!B state,SacSpell!B spell,int attacker,int side,Vector3f center,float* totalDamage){
					if(target.id==attacker) return;
					state.movingObjectById!((ref obj,damage,attacker,side,state){
						if(state.sides.getStance(side,obj.side)!=Stance.ally){
							// TODO: limit distance between hitboxes to 4?
							*totalDamage+=obj.bugDamage(damage,attacker,side,obj.center-center,state);
						}
					},(){})(target.id,spell.amount/updateFPS,attacker,side,state);
				}
				collisionTargets!damage(hitbox,state,protectiveSwarm.spell,obj.id,obj.side,obj.center,&totalDamage);
				if(totalDamage) obj.heal(0.5f*totalDamage,state);
			}
			(*protectiveSwarm).updateBugs(obj,state);
			if(protectiveSwarm.status==ProtectiveSwarmStatus.casting){
				if(protectiveSwarm.castingTime>0){
					(*protectiveSwarm).addBugs(obj,state);
					protectiveSwarm.castingTime-=1;
				}
				return true;
			}
			if(protectiveSwarm.status==ProtectiveSwarmStatus.dispersing)
				return true;
			assert(obj.creatureStats.effects.protectiveSwarm);
			return obj.creatureState.mode.canShield;
		}
		bool valid=state.movingObjectById!(check,()=>false)(target,&protectiveSwarm,state);
		final switch(status){
			case ProtectiveSwarmStatus.casting,ProtectiveSwarmStatus.steady:
				if(!valid||frame>=spell.duration*updateFPS){
					static void removeProtectiveSwarm(B)(ref MovingObject!B object){
						assert(object.creatureStats.effects.protectiveSwarm);
						object.creatureStats.effects.protectiveSwarm=false;
					}
					state.movingObjectById!(removeProtectiveSwarm,(){})(target);
					status=ProtectiveSwarmStatus.dispersing;
				}
				return true;
			case ProtectiveSwarmStatus.dispersing:
				alpha-=0.5f/updateFPS;
				return alpha>0.0f;
		}
	}
}

void animateAirShieldCasting(B)(ref MovingObject!B wizard,ObjectState!B state){
	wizard.animateStratosCasting(state);
}
bool updateAirShieldCasting(B)(ref AirShieldCasting!B airShieldCast,ObjectState!B state){
	with(airShieldCast){
		airShield.frame+=1;
		final switch(manaDrain.update(state)){
			case CastingStatus.underway:
				state.movingObjectById!((ref obj,state){
					obj.animateAirShieldCasting(state);
					obj.animateFreezeCastingTarget(state);
				},(){})(manaDrain.wizard,state);
				return airShield.updateAirShield(state,castingTime);
			case CastingStatus.interrupted:
				airShield.status=AirShieldStatus.shrinking;
				state.addEffect(move(airShield));
				return false;
			case CastingStatus.finished:
				state.addEffect(move(airShield));
				return false;
		}
	}
}
bool updateAirShield(B)(ref AirShield!B airShield,ObjectState!B state,int scaleFrames=15){
	with(airShield){
		if(!state.isValidTarget(target,TargetType.creature)) return false;
		auto relHitbox=state.movingObjectById!(relativeHitbox,()=>(Vector3f[2]).init)(airShield.target);
		auto boxSize=.boxSize(relHitbox);
		auto boxCenter=.boxCenter(relHitbox);
		boxSize.x=boxSize.y=sqrt(0.5f*(boxSize.x^^2+boxSize.y^^2));
		auto dimensions=Vector3f(2.0f,2.0f,1.5f)*boxSize;
		enum T=0.75f;
		for(int i=0;i<particles.length;i++){
			with(particles[i]){
				θ+=2*pi!float/(T*updateFPS*(0.1f+radius));
				frame+=1;
				if(frame>=16*updateAnimFactor){
					if(i+1<particles.length)
						swap(particles[i],particles[$-1]);
					particles.length=particles.length-1;
				}
			}
		}
		auto numParticles=!state.uniform(2)+!state.uniform(2);
		foreach(i;0..numParticles){
			float height=state.uniform(-1.0f,1.0f);
			float radius=sqrt(1-height^^2)*state.uniform(0.05f,1.25f);
			float θ=state.uniform(-pi!float,pi!float);
			radius*=0.5f*dimensions.x;
			height=boxCenter.z+height*0.5f*dimensions.z;
			particles~=AirShield!B.Particle(height,radius,θ);
		}
		++frame;
		if(status!=AirShieldStatus.shrinking){
			static bool check(ref MovingObject!B obj){
				assert(obj.creatureStats.effects.airShield);
				return obj.creatureState.mode.canShield;
			}
			if(!state.movingObjectById!(check,()=>false)(target)||frame+scaleFrames>=spell.duration*updateFPS)
				status=AirShieldStatus.shrinking;
		}
		auto hitboxSide=state.movingObjectById!((ref obj)=>tuple(obj.hitbox,obj.side),()=>tuple((Vector3f[2]).init,-1))(airShield.target);
		auto hitbox=hitboxSide[0], side=hitboxSide[1];
		static bool filter(ref ProximityEntry entry,ObjectState!B state,int side){
			return state.movingObjectById!((ref obj,side)=>obj.side!=side&&obj.canPush,()=>false)(entry.id,side);
		}
		pushAll!filter(.boxCenter(hitbox),0.5f*(hitbox[1].xy-hitbox[0].xy).length,0.5f*spell.effectRange,20.0f,state,side);
		final switch(status){
			case AirShieldStatus.growing:
				scale=min(1.0f,scale+1.0f/scaleFrames);
				if(scale==1.0f) status=AirShieldStatus.stationary;
				break;
			case AirShieldStatus.stationary:
				break;
			case AirShieldStatus.shrinking:
				scale=max(0.0f,scale-1.0f/scaleFrames);
				if(scale==0.0f){
					static void removeAirShield(B)(ref MovingObject!B object){
						assert(object.creatureStats.effects.airShield);
						object.creatureStats.effects.airShield=false;
					}
					state.movingObjectById!(removeAirShield,(){})(target);
					playSoundAt("dhsa",target,state,airShieldGain);
					updateRenderMode(target,state);
					return false;
				}
				break;
		}
		return true;
	}
}

void animateFreezeCastingTarget(B)(ref MovingObject!B obj,ObjectState!B state){
	auto sacParticle=SacParticle!B.get(ParticleType.freeze);
	auto hitbox=obj.relativeHitbox;
	auto center=boxCenter(hitbox);
	enum numParticles=2;
	foreach(i;0..numParticles){
		auto position=state.uniform(hitbox)-center;
		position.x*=4.0f;
		position.y*=4.0f;
		position.z*=4.0f;
		position+=center;
		auto lifetime=sacParticle.numFrames/60.0f;
		auto velocity=(center-position)/lifetime;
		auto scale=1.0f;
		state.addParticle(Particle!(B,true)(sacParticle,obj.id,false,position,velocity,scale,sacParticle.numFrames,0));
	}
}

bool updateFreezeCasting(B)(ref FreezeCasting!B freezeCast,ObjectState!B state){
	with(freezeCast){
		final switch(manaDrain.update(state)){
			case CastingStatus.underway:
				auto sacParticle=SacParticle!B.get(ParticleType.freeze);
				state.movingObjectById!(animateFreezeCastingTarget,(){})(creature,state);
				static assert(updateFPS==60);
				state.movingObjectById!((obj,sacParticle,state){
					auto hitbox=obj.relativeHitbox;
					auto center=boxCenter(hitbox);
					enum numParticles=2;
					foreach(i;0..numParticles){
						auto position=state.uniform(hitbox)-center;
						position.x*=4.0f;
						position.y*=4.0f;
						position.z*=4.0f;
						position+=center;
						auto lifetime=sacParticle.numFrames/60.0f;
						auto velocity=(position-center)/lifetime;
						auto scale=1.0f;
						state.addParticle(Particle!(B,true)(sacParticle,obj.id,false,center,velocity,scale,sacParticle.numFrames,0));
					}
				},(){})(manaDrain.wizard,sacParticle,state);
				return true;
			case CastingStatus.interrupted: return false;
			case CastingStatus.finished:
				state.movingObjectById!((ref obj,creature,spell,state){
					freeze(obj.id,obj.side,creature,spell,state);
				},(){})(manaDrain.wizard,creature,spell,state);
				return false;
		}
	}
}

void unfreeze(B)(ref MovingObject!B obj,ObjectState!B state){
	if(!obj.creatureStats.effects.frozen) return;
	obj.creatureStats.effects.frozen=false;
	obj.startIdling(state);
}

bool updateFreeze(B)(ref Freeze!B freeze,ObjectState!B state){
	with(freeze){
		if(--timer<=0) state.movingObjectById!(unfreeze,(){})(creature,state);
		scale=min(1.0f,scale+1.0f/numFramesToAppear);
		bool frozen=state.movingObjectById!((ref obj)=>obj.creatureStats.effects.frozen,()=>false)(creature);
		if(!frozen){
			state.movingObjectById!((ref obj,state){
				playSpellSoundTypeAt(SoundType.breakingIce,creature,state,freezeGain);
				dealSpellDamage(obj,spell,wizard,side,Vector3f(0.0f,0.0f,1.0f),DamageMod.none,state);
				auto hitbox=obj.sacObject.largeHitbox(obj.rotation,obj.animationState,obj.frame/updateAnimFactor);
				hitbox[0]+=obj.position;
				hitbox[1]+=obj.position;
				auto center=boxCenter(hitbox);
				auto dim=boxSize(hitbox);
				auto volume=dim.x*dim.y*dim.z;
				auto scale=0.75f*max(1.0f,cbrt(volume));
				auto sacParticle=SacParticle!B.get(ParticleType.shard);
				enum numParticles=30;
				foreach(i;0..numParticles){
					auto position=state.uniform(scaleBox(hitbox,1.05f));
					auto velocity=Vector3f(position.x-center.x,position.y-center.y,0.0f).normalized;
					velocity.z=3.0f;
					int lifetime=31;
					int frame=0;
					state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
				}
			},(){})(creature,state);
		}
		return frozen;
	}
}

void animateRingsOfFireCastingTarget(B)(ref MovingObject!B obj,ObjectState!B state){
	auto sacParticle=SacParticle!B.get(ParticleType.firy);
	auto hitbox=obj.relativeHitbox;
	auto center=boxCenter(hitbox);
	auto dim=hitbox[1]-hitbox[0];
	auto volume=dim.x*dim.y*dim.z;
	auto scale=max(1.0f,cbrt(volume));
	enum numParticles=2;
	foreach(i;0..numParticles){
		auto position=state.uniform(hitbox)-center;
		position.x*=2.0f;
		position.y*=2.0f;
		position.z*=2.0f;
		position+=center;
		auto lifetime=sacParticle.numFrames/60.0f;
		auto velocity=(center-position)/lifetime;
		state.addParticle(Particle!(B,true)(sacParticle,obj.id,false,position,velocity,scale,sacParticle.numFrames,0));
	}
}

void animateRingsOfFireCasting(B)(ref MovingObject!B wizard,ObjectState!B state){
	auto castParticle=SacParticle!B.get(ParticleType.firy);
	wizard.animateCasting!false(castParticle,state);
}

bool updateRingsOfFireCasting(B)(ref RingsOfFireCasting!B ringsOfFireCast,ObjectState!B state){
	with(ringsOfFireCast){
		final switch(manaDrain.update(state)){
			case CastingStatus.underway:
				auto sacParticle=SacParticle!B.get(ParticleType.firy);
				state.movingObjectById!(animateRingsOfFireCastingTarget,(){})(creature,state);
				state.movingObjectById!(animateRingsOfFireCasting,(){})(manaDrain.wizard,state);
				return true;
			case CastingStatus.interrupted:
				state.movingObjectById!(removeRingsOfFire,(){})(creature,state);
				return false;
			case CastingStatus.finished:
				state.movingObjectById!((ref obj,creature,spell,state){
					ringsOfFire(obj.id,obj.side,creature,spell,state);
				},(){})(manaDrain.wizard,creature,spell,state);
				return false;
		}
	}
}

void animateRingsOfFire(bool relative=true,B)(ref MovingObject!B obj,ObjectState!B state){
	enum numParticles=30;
	auto sacParticle=SacParticle!B.get(ParticleType.firy);
	auto hitbox=obj.sacObject.largeHitbox(obj.rotation,obj.animationState,obj.frame/updateAnimFactor);
	auto height=state.uniform(0.4f,1.2f);
	auto duration=state.uniform(0.8f,1.2f);
	auto scale=state.uniform(1.2f,1.25f)*getScale(obj).length*height;
	foreach(k;0..numParticles){
		auto φ=state.uniform(-pi!float,pi!float);
		auto offset=Vector3f(scale*cos(φ),scale*sin(φ),hitbox[0].z+(hitbox[1].z-hitbox[0].z)*height);
		auto velocity=-offset/duration;
		auto lifetime=cast(int)ceil(updateFPS*duration);
		auto frame=0;
		static if(relative) state.addParticle(Particle!(B,true)(sacParticle,obj.id,true,offset,velocity,scale,lifetime,frame));
		else state.addParticle(Particle!B(sacParticle,obj.position+offset,velocity,scale,lifetime,frame));
	}
}

void removeRingsOfFire(B)(ref MovingObject!B obj,ObjectState!B state){
	if(!obj.creatureStats.effects.ringsOfFire) return;
	obj.creatureStats.effects.ringsOfFire=false;
	foreach(i;0..3) animateRingsOfFire!false(obj,state);
	playSpellSoundTypeAt!true(SoundType.disableRingsOfFire,obj.id,state,ringsOfFireGain);
}

bool updateRingsOfFire(B)(ref RingsOfFire!B ringsOfFire,ObjectState!B state){
	with(ringsOfFire){
		bool keep=state.movingObjectById!((ref obj,state){
			if(!obj.creatureState.mode.canCC) return false;
			static assert(updateFPS==60);
			if(ringsOfFire.timer%25==0||state.uniform(50)==0) obj.animateRingsOfFire(state);
			auto damagePerFrame=spell.amount/updateFPS;
			obj.dealFireDamage(0.0f,damagePerFrame,wizard,side,DamageMod.peirceShield,state);
			return true;
		},()=>false)(creature,state);
		if(!keep||--timer<=0){
			state.movingObjectById!(removeRingsOfFire,(){})(creature,state);
			return false;
		}
		if(--soundTimer<=0) soundTimer=playSoundAt!true("5plf",creature,state,ringsOfFireGain); // TODO: original picks one of multiple effects
		return true;
	}
}

void animateSlimeCasting(B)(ref MovingObject!B wizard,ObjectState!B state){
	auto castParticle=SacParticle!B.get(ParticleType.castCharnel2);
	wizard.animateCasting(castParticle,state);
}

bool updateSlimeCasting(B)(ref SlimeCasting!B slimeCast,ObjectState!B state){
	with(slimeCast){
		progress=min(1.0f,progress+1.0f/castingTime);
		if(progress==1.0f){
			slime(creature,spell,state);
			return false;
		}
		final switch(finishedCasting?CastingStatus.finished:manaDrain.update(state)){
			case CastingStatus.underway:
				state.movingObjectById!(animateSlimeCasting,(){})(manaDrain.wizard,state);
				return true;
			case CastingStatus.interrupted: return false;
			case CastingStatus.finished:
				finishedCasting=true;
				return progress<1.0f;
		}
	}
}

void animateSlimeTransition(B)(ref MovingObject!B obj,ObjectState!B state){
	enum numParticles=128;
	auto sacParticle=SacParticle!B.get(ParticleType.slime);
	auto hitbox=obj.hitbox;
	auto center=boxCenter(hitbox);
	auto scale=0.8f*getScale(obj).length;
	foreach(i;0..numParticles){
		auto position=state.uniform(scaleBox(hitbox,1.2f));
		auto velocity=Vector3f(position.x-center.x,position.y-center.y,0.0f).normalized;
		velocity.z=3.0f;
		int lifetime=63;
		int frame=0;
		state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
	}
}

void animateSlime(bool relative=true,B)(ref MovingObject!B obj,ObjectState!B state){
	enum numParticles=4;
	auto sacParticle=SacParticle!B.get(ParticleType.slime);
	auto hitbox=obj.sacObject.largeHitbox(obj.rotation,obj.animationState,obj.frame/updateAnimFactor);
	auto duration=state.uniform(0.8f,1.2f);
	auto scale=0.25*state.uniform(0.75f,1.0f)*getScale(obj).length;
	auto box=scaleBox(hitbox,0.8f);
	box[0].z=0.5f*(hitbox[0].z+hitbox[1].z);
	box[1].z=hitbox[1].z;
	foreach(k;0..numParticles){
		auto offset=state.uniform(box); // TODO: pick location close to bone?
		auto height=(offset.z-hitbox[0].z)/(hitbox[1].z-hitbox[0].z);
		auto velocity=Vector3f(0.0f,0.0f,0.0f,-height/duration);
		auto lifetime=cast(int)ceil(updateFPS*duration);
		auto frame=0;
		static if(relative) state.addParticle(Particle!(B,true)(sacParticle,obj.id,true,offset,velocity,scale,lifetime,frame));
		else state.addParticle(Particle!B(sacParticle,obj.position+offset,velocity,scale,lifetime,frame));
	}
}

void removeSlime(B)(ref MovingObject!B obj,ObjectState!B state){
	if(!obj.creatureStats.effects.slimed) return;
	obj.creatureStats.effects.numSlimes-=1;
	obj.animateSlimeTransition(state);
}

bool updateSlime(B)(ref Slime!B slime,ObjectState!B state){
	with(slime){
		bool keep=state.movingObjectById!((ref obj,state){
			if(!obj.creatureState.mode.canCC) return false;
			static assert(updateFPS==60);
			if(slime.timer%10==0||state.uniform(20)==0) obj.animateSlime(state);
			return true;
		},()=>false)(creature,state);
		if(!keep||--timer<=0){
			state.movingObjectById!(removeSlime,(){})(creature,state);
			return false;
		}
		return true;
	}
}

void animateGraspingVinesCasting(B)(ref MovingObject!B wizard,ObjectState!B state){
	auto castParticle=SacParticle!B.get(ParticleType.castPersephone2);
	wizard.animateCasting(castParticle,state);
}
void animateGraspingVinesCastingTarget(B)(ref MovingObject!B obj,ObjectState!B state){
	enum numParticles=16;
	auto sacParticle=SacParticle!B.get(ParticleType.dirt);
	auto hitbox=obj.hitbox;
	hitbox[1].z=0.1f*(hitbox[1].z-hitbox[0].z);
	hitbox[0].z=0.0f;
	auto center=boxCenter(hitbox);
	auto scale=0.6f*getScale(obj).length;
	foreach(i;0..numParticles){
		auto position=state.uniform(hitbox);
		position.z=position.z+state.getHeight(position);
		auto velocity=Vector3f(0.0f,0.0f,0.0f);
		int lifetime=31;
		int frame=0;
		state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
	}
}

bool updateGraspingVinesCasting(B)(ref GraspingVinesCasting!B graspingVinesCast,ObjectState!B state){
	with(graspingVinesCast){
		final switch(manaDrain.update(state)){
			case CastingStatus.underway:
				state.movingObjectById!(animateGraspingVinesCasting,(){})(manaDrain.wizard,state);
				state.movingObjectById!(animateGraspingVinesCastingTarget,(){})(creature,state);
				return true;
			case CastingStatus.interrupted: return false;
			case CastingStatus.finished:
				graspingVines(creature,spell,state);
				return false;
		}
	}
}

void updateVine(B)(ref Vine vine,float lengthFactor,ObjectState!B state){
	vine.locations[0]=vine.base;
	//vine.locations[$-1]=vine.locations[$-1]*(1.0f-vine.growthFactor)+vine.growthFactor*vine.target;
	enum accelFactor=90.0f;
	static import std.math;
	enum dampFactor=std.math.exp(std.math.log(0.5f)/updateFPS);
	enum maxVelocity=20.0f;
	vine.base.z=state.getHeight(vine.base);
	// TODO: track target creature with vine
	foreach(i;1..vine.m){
		auto realTarget=vine.base+lengthFactor*float(i)/(vine.m-1)*(vine.target-vine.base);
		auto target=vine.locations[$-1]*(1.0f-vine.growthFactor)+vine.growthFactor*realTarget;
		auto acceleration=target-vine.locations[i];
		acceleration=accelFactor/vine.scale*acceleration.lengthsqr^^(1/7.0f)*acceleration;
		vine.velocities[i]+=acceleration/updateFPS;
		vine.velocities[i]*=dampFactor;
		if(vine.velocities[i].lengthsqr<(0.2f*vine.scale)^^2) vine.velocities[i]=vine.scale*0.75f*state.uniformDirection();
		auto relativeVelocity=vine.velocities[i];
		if(relativeVelocity.lengthsqr>maxVelocity^^2)
			vine.velocities[i]=maxVelocity/relativeVelocity.length*relativeVelocity;
		vine.locations[i]+=vine.velocities[i]/updateFPS;
	}
	auto len=(vine.target-vine.base).length/(vine.m-1)*vine.growthFactor+(1.0f-vine.growthFactor)*(vine.locations[$-1]-vine.base).length;
	if(len>1.0f) foreach(i;1..vine.m) vine.locations[i]=vine.locations[i-1]+len*lengthFactor*(vine.locations[i]-vine.locations[i-1]).normalized;
}

bool updateGraspingVines(B)(ref GraspingVines!B graspingVines,ObjectState!B state){
	with(graspingVines){
		foreach(ref vine;vines) updateVine(vine,lengthFactor,state);
		if(active){
			bool keep=state.movingObjectById!((ref obj,state){
				if(!obj.creatureState.mode.canCC) return false;
				return true;
			},()=>false)(creature,state);
			if(!keep||--timer<=0){
				active=false;
				state.movingObjectById!((ref obj){
					obj.creatureStats.effects.numVines-=1;
					playSoundAt("dafr",obj.position,state,0.5f*graspingVinesGain);
				},(){})(creature);
			}
			lengthFactor=min(1.0f,lengthFactor+1.0f/float(growthTime));
		}else{
			lengthFactor=max(0.0f,lengthFactor-1.0f/float(vanishTime));
			if(lengthFactor==0.0f) return false;
		}
		return true;
	}
}

bool updateSoulMoleCasting(B)(ref SoulMoleCasting!B soulMoleCast,ObjectState!B state){
	with(soulMoleCast){
		final switch(manaDrain.update(state)){
			case CastingStatus.underway:
				if(!soulMole.updateSoulMolePosition(state))
					return false;
				return state.movingObjectById!((ref obj){
					obj.animateRockCasting(state);
					return true;
				},()=>false)(manaDrain.wizard);
			case CastingStatus.interrupted:
				return false;
			case CastingStatus.finished:
				.soulMole(soulMole,state);
				return false;
		}
	}
}

void animateSoulMole(B)(ref SoulMole!B soulMole,Vector3f oldPosition,ObjectState!B state){
	with(soulMole){
		if(state.isOnGround(soulMole.position)){
			enum numParticles=2;
			auto sacParticle=SacParticle!B.get(ParticleType.dust);
			foreach(i;0..numParticles){
				auto position=oldPosition*((cast(float)numParticles-1-i)/numParticles)+position*(cast(float)(i+1)/numParticles);
				auto velocity=Vector3f(0.0f,0.0f,0.0f);
				auto lifetime=31;
				auto scale=2.0f;
				auto frame=0;
				position+=0.6f*state.uniformDirection();
				state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
			}
		}
		enum numParticles3=2;
		auto sacParticle3=SacParticle!B.get(ParticleType.rock);
		foreach(i;0..numParticles3){
			auto position=soulMole.position;
			auto direction=state.uniformDirection();
			auto velocity=state.uniform(5f,10.0f)*direction;
			auto scale=state.uniform(0.5f,2.0f);
			auto lifetime=63;
			auto frame=0;
			state.addParticle(Particle!B(sacParticle3,position,velocity,scale,lifetime,frame));
		}
	}
}

void severSoul(B)(ref Soul!B soul,ObjectState!B state){
	if(soul.creatureId){
		if(soul.creatureId){
			state.movingObjectById!((ref creature,state){
				creature.soulId=0;
				creature.startDissolving(state);
			},(){})(soul.creatureId,state);
		}
		soul.creatureId=0;
	}
}

enum soulMoleGain=5.0f;
bool updateSoulMolePosition(B)(ref SoulMole!B soulMole,ObjectState!B state){
	static assert(soulMole.roundtripTime%4==0);
	enum soulFrame=soulMole.roundtripTime/2;
	enum backFrame=soulMole.roundtripTime;
	enum MolePhase{
		toSoul,
		back,
	}
	static MolePhase molePhase(int frame){
		if(frame<=soulFrame) return MolePhase.toSoul;
		return MolePhase.back;
	}
	static int nextTransitionFrame(int frame){
		final switch(molePhase(frame)){
			case MolePhase.toSoul: return soulFrame;
			case MolePhase.back: return backFrame;
		}
	}
	static int framesLeft(int frame){ return nextTransitionFrame(frame)-frame; }
	static float relativeProgress(int frame){
		if(frame<=soulFrame) return float(frame)/soulFrame;
		return float(frame-soulFrame)/(backFrame-soulFrame);
	}
	if(--soulMole.soundTimer<=0) soulMole.soundTimer=playSpellSoundTypeAt!true(SoundType.bore,soulMole.position,state,soulMoleGain); // TODO: sound should follow mole
	auto prevTargetPosition=soulMole.positionPredictor.lastPosition;
	auto oldPosition=soulMole.position;
	soulMole.frame+=1;
	auto soulPosition=state.soulById!((ref soul)=>soul.position,()=>Vector3f.init)(soulMole.soul);
	if(isNaN(soulPosition.x)) return false;
	auto wizardPosition=state.movingObjectById!((ref obj)=>obj.position,()=>Vector3f.init)(soulMole.wizard);
	Vector3f[2] moleOrigin(int frame){
		final switch(molePhase(frame)){
			case MolePhase.toSoul: return [soulMole.startPosition,Vector3f(0.0f,0.0f,0.0f)];
			case MolePhase.back: return [soulMole.startPosition,soulMole.targetVelocity];
		}
	}
	Vector3f[2] moleTarget(int frame){
		final switch(molePhase(frame)){
			case MolePhase.toSoul: return [soulPosition,soulMole.targetVelocity];
			case MolePhase.back: return [wizardPosition,0.75f*(wizardPosition-soulMole.startPosition)];
		}
	}
	auto targetLocation=moleTarget(soulMole.frame);
	auto targetPosition=targetLocation[0],targetVelocity=targetLocation[1];
	/*enum minSoulMoleSpeed=5.0f;
	if(molePhase(soulMole.frame)<MolePhase.back&&(oldPosition-targetPosition).xy.lengthsqr<(minSoulMoleSpeed/updateFPS)^^2){
		soulMole.frame=nextTransitionFrame(soulMole.frame);
		targetLocation=moleTarget(soulMole.frame);
		targetPosition=targetLocation[0], targetVelocity=targetLocation[1];
	}*/
	if(isNaN(targetPosition.x)) return false;
	if(soulMole.frame==soulFrame+1){
		playSoundAt("ltss",oldPosition,state,soulMoleGain); // TODO: sound should follow mole
		auto side=state.movingObjectById!((ref obj)=>obj.side,()=>-1)(soulMole.wizard);
		state.soulById!((ref soul,side,state){
			soul.severSoul(state);
			soul.preferredSide=side;
		},(){})(soulMole.soul,side,state);
		soulMole.startPosition=oldPosition;
		soulMole.positionPredictor.lastPosition=targetPosition;
	}
	auto curFramesLeft=framesLeft(soulMole.frame);
	auto predictedTargetPosition=soulMole.positionPredictor.predictAtTime(float(curFramesLeft)/updateFPS,targetPosition);
	auto relativePosition=1.0f/(curFramesLeft+1);
	//auto newPosition=(1.0f-relativePosition)*oldPosition+relativePosition*predictedTargetPosition;
	/*Vector3f[2][2] locations=[[oldPosition,soulMole.velocity],
	                          [predictedTargetPosition,targetVelocity]];
	Vector3f[2] newLocation=cintp2(locations,relativePosition);*/
	Vector3f[2] newLocation=cintp2([moleOrigin(soulMole.frame),moleTarget(soulMole.frame)],relativeProgress(soulMole.frame));
	auto newPosition=newLocation[0], newVelocity=newLocation[1];
	newPosition.z=state.getHeight(newPosition);
	/*auto speed=updateFPS*((targetPosition-oldPosition).length-(targetPosition-newPosition).length);
	if(speed<minSoulMoleSpeed){
		auto dist=max(0.0f,(targetPosition-oldPosition).length-minSoulMoleSpeed/updateFPS);
		newPosition=targetPosition+(newPosition-targetPosition).normalized*dist;
		newPosition.z=state.getHeight(newPosition);
	}*/
	if(molePhase(soulMole.frame)>MolePhase.toSoul){
		state.soulById!((ref soul,molePosition){
			if(!soul.collectorId) soul.position=molePosition;
		},(){})(soulMole.soul,newPosition);
	}
	soulMole.position=newPosition;
	//soulMole.velocity=newVelocity;
	soulMole.animateSoulMole(oldPosition,state);
	return soulMole.frame<backFrame;
}

bool updateSoulMole(B)(ref SoulMole!B soulMole,ObjectState!B state){
	if(!soulMole.updateSoulMolePosition(state))
		return false;
	static bool callback(int target,int wizard,int side,ObjectState!B state){
		state.movingObjectById!((ref obj,wizard,side,state){
			if(obj.id==wizard) return;
			//if(state.sides.getStance(side,obj.side)==Stance.ally) return;
			obj.stunWithCooldown(stunCooldownFrames,state);
		},(){})(target,wizard,side,state);
		return false;
	}
	auto side=state.movingObjectById!((ref obj)=>obj.side,()=>-1)(soulMole.wizard);
	if(side==-1) return false;
	with(soulMole) dealSplashSpellDamageAt!callback(0,spell,spell.effectRange,wizard,side,position,DamageMod.none,state,wizard,side,state);
	return true;
}

void animateRainbowCasting(B)(ref MovingObject!B wizard,ObjectState!B state){
	auto castParticle=SacParticle!B.get(ParticleType.heal);
	wizard.animateCasting(castParticle,state);
	static assert(updateFPS==60);
	auto hitbox=wizard.relativeHitbox;
	auto scale=2.0f;
	auto sacParticle=SacParticle!B.get(ParticleType.heal);
	enum numParticles=6;
	foreach(i;0..numParticles){
		auto position=1.1f*state.uniform(cast(Vector2f[2])[hitbox[0].xy,hitbox[1].xy]);
		auto distance=(state.uniform(3)?state.uniform(0.3f,0.6f):state.uniform(1.5f,2.5f))*(hitbox[1].z-hitbox[0].z);
		auto fullLifetime=2.0f*sacParticle.numFrames/float(updateFPS);
		auto lifetime=cast(int)(sacParticle.numFrames*state.uniform(0.0f,2.0f));
		// TODO: particles should accelerate upwards
		state.addParticle(Particle!B(sacParticle,wizard.position+rotate(wizard.rotation,Vector3f(position.x,position.y,state.uniform(0.0f,0.5f*distance))),Vector3f(0.0f,0.0f,distance/fullLifetime),scale,lifetime,0));
	}
}

bool updateRainbowCasting(B)(ref RainbowCasting!B rainbowCast,ObjectState!B state){
	with(rainbowCast){
		updateRainbowTarget(target,state);
		final switch(manaDrain.update(state)){
			case CastingStatus.underway:
				return state.movingObjectById!((ref obj){
					obj.animateRainbowCasting(state);
					return true;
				},()=>false)(manaDrain.wizard);
			case CastingStatus.interrupted:
				return false;
			case CastingStatus.finished:
				auto position=state.movingObjectById!((ref obj){
					auto hbox=obj.sacObject.hitbox(Quaternionf.identity(),AnimationState.stance1,0);
					auto offset=Vector3f(0.0f,hbox[1].y+0.75f,hbox[1].z+0.5f);
					return obj.position+rotate(obj.rotation,offset);
				},()=>Vector3f.init)(manaDrain.wizard);
				if(isNaN(position.x)) return false;
				auto origin=OrderTarget(TargetType.creature,manaDrain.wizard,position);
				rainbow(side,origin,target,spell,state);
				return false;
		}
	}
}

OrderTarget newRainbowTarget(B)(OrderTarget last,OrderTarget current,SacSpell!B spell,ObjectState!B state){
	auto position=2.0f*current.position-last.position;
	auto offset=state.uniform(0.0f,0.25f*spell.effectRange)*state.uniformDirection!(float,2)();
	position.x+=offset.x, position.y+=offset.y;
	if((position-current.position).lengthsqr>spell.effectRange^^2)
		position=current.position+(position-current.position).normalized*spell.effectRange;
	position.z=state.getHeight(position); // TODO: avoid void?
	return OrderTarget(TargetType.terrain,0,position);
}

void updateRainbowTarget(B)(ref OrderTarget target,ObjectState!B state){
	if(state.isValidTarget(target.id,TargetType.creature)){
		auto cand=state.movingObjectById!(center,()=>Vector3f.init)(target.id);
		if(!isNaN(cand.x)) target.position=cand;
	}
}
void predictRainbowTarget(B)(ref OrderTarget target,ref PositionPredictor predictor,float progress,ObjectState!B state){
	updateRainbowTarget(target,state);
	auto predicted=predictor.predictCenterAtTime((1.0f-progress)*Rainbow!B.travelFrames/updateFPS,target,state);
	target.position=(1.0f-progress)*target.position+progress*predicted;
}

void animateRainbowHit(B)(ref MovingObject!B obj,ObjectState!B state){
	auto hitbox=obj.hitbox;
	enum numParticles=128;
	auto sacParticle=SacParticle!B.get(ParticleType.rainbowParticle);
	auto center=boxCenter(hitbox);
	foreach(i;0..numParticles){
		auto position=state.uniform(scaleBox(hitbox,0.9f));
		//auto velocity=1.5f*state.uniform(0.5f,2.0f)*Vector3f(position.x-center.x,position.y-center.y,2.0f);
		auto velocity=1.5f*state.uniform(0.5f,2.0f)*Vector3f(state.uniform(hitbox[0].x,hitbox[1].x)-center.x,state.uniform(hitbox[0].y,hitbox[1].y)-center.y,2.5f); // TODO: add velocity of target?
		auto scale=state.uniform(0.5f,1.5f);
		int lifetime=63;
		int frame=0;
		state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
	}
}

enum rainbowGain=2.0f;
bool updateRainbow(B)(ref Rainbow!B rainbow,ObjectState!B state){
	with(rainbow){
		auto progress=float(frame+1)/travelFrames;
		predictRainbowTarget(current,predictor,progress,state);
		if(frame==0) state.addEffect(RainbowEffect!B(last,current,spell));
		if(++frame==travelFrames){
			if(current.id){
				state.movingObjectById!(animateRainbowHit,(){})(current.id,state);
				heal(current.id,spell,state);
				addTarget(current.id);
			}
			if(++numTargets>=totTargets)
				return false;
			static bool filter(ref CenterProximityEntry entry,ObjectState!B state,Rainbow!B* rainbow){
				if(state.movingObjectById!((ref obj,state)=>obj.health(state)==0.0f,()=>true)(entry.id,state)) return false;
				return !rainbow.hasTarget(entry.id);
			}
			int newTarget=state.proximity.lowestHealthCreatureInRange!filter(side,0,current.position,spell.effectRange,state,state,&rainbow);
			OrderTarget next;
			if(newTarget) next=OrderTarget(TargetType.creature,newTarget,state.movingObjectById!((ref obj)=>obj.position,()=>Vector3f.init)(newTarget));
			if(isNaN(next.position.x)) next=newRainbowTarget(last,current,spell,state);
			last=current;
			current=next;
			frame=0;
		}
		return true;
	}
}

bool updateRainbowEffect(B)(ref RainbowEffect!B rainbowEffect,ObjectState!B state){
	with(rainbowEffect){
		if(frame<=travelFrames){
			auto progress=float(frame+1)/travelFrames;
			predictRainbowTarget(end,predictor,progress,state);
			auto direction=(end.position-start.position).normalized;
			auto center=0.5f*(start.position+end.position);
			auto rotationAxis=cross(Vector3f(0.0f,0.0f,1.0f),end.position-start.position).normalized;
			if(isNaN(rotationAxis.x)) rotationAxis=Vector3f(0.0f,1.0f,0.0f);
			static Vector3f xy(Vector3f xyz){ return Vector3f(xyz.x,xyz.y,0.0f); }
			auto position=xy(center)+rotate(rotationQuaternion(rotationAxis,progress*pi!float),xy(start.position-center));
			auto dstart=(xy(position)-xy(start.position)).length, dend=(xy(end.position)-xy(position)).length;
			position.z+=dend/(dstart+dend)*start.position.z+dstart/(dstart+dend)*end.position.z;
			if(--soundTimer<=0) soundTimer=playSoundAt!true("wobr",position,state,rainbowGain); // TODO: move sound with rainbow
			auto sacParticle=SacParticle!B.get(ParticleType.heal);
			auto velocity=Vector3f(0.0f,0.0f,0.0f);
			auto lifetime=63;
			auto pframe=0;
			foreach(i;0..3){
				auto pposition=position+0.7f*state.uniformDirection();
				auto scale=state.uniform(0.5f,1.5f);
				state.addParticle(Particle!B(sacParticle,pposition,velocity,scale,lifetime,pframe));
			}
		}else if(--soundTimer<=0) soundTimer=playSoundAt!true("wobr",end.position,state,rainbowGain); // TODO: move sound with rainbow
		return ++frame<=totalFrames;
	}
}

void animateChainLightningCasting(B)(ref MovingObject!B wizard,ObjectState!B state){
	auto castParticle=SacParticle!B.get(ParticleType.chainLightningCasting);
	wizard.animateCasting(castParticle,state);
}

void chainLightningCastingEffect(B)(Vector3f start,Vector3f end,ObjectState!B state){
	if(!state.uniform(4)) playSpellSoundTypeAt(SoundType.lightning,0.5f*(start+end),state,4.0f);
	auto effect=ChainLightningCastingEffect!B(start,end);
	effect.bolt.changeShape!(0.5f)(state);
	state.addEffect(effect);
}

bool updateChainLightningCasting(B)(ref ChainLightningCasting!B chainLightningCast,ObjectState!B state){
	with(chainLightningCast){
		target.position=target.center(state);
		auto status=manaDrain.update(state);
		return state.movingObjectById!((obj,status){
			auto hbox=obj.sacObject.hitbox(Quaternionf.identity(),AnimationState.stance1,0);
			auto offset=Vector3f(0.0f,hbox[1].y+0.75f,hbox[1].z+0.5f);
			final switch(status){
				case CastingStatus.underway:
					auto sacParticle=SacParticle!B.get(ParticleType.lightningCasting);
					enum numParticles=2;
					foreach(i;0..numParticles){
						enum uncertainty=0.25f;
						Vector3f[2] box=[offset-uncertainty*Vector3f(1.0f,1.0f,1.0f),offset+uncertainty*Vector3f(1.0f,1.0f,1.0f)];
						auto position=state.uniform(box);
						auto lifetime=sacParticle.numFrames/60.0f;
						auto velocity=Vector3f(0.0f,0.0f,0.0f);
						auto scale=1.0f;
						state.addParticle(Particle!(B,true)(sacParticle,obj.id,true,position,velocity,scale,sacParticle.numFrames,0));
					}
					if(!state.uniform(2)){
						Vector3f[2] nhbox=scaleBox(hbox,1.5f);
						auto start=obj.position+rotate(obj.rotation,state.uniform(nhbox));
						auto end=start;
						end.z+=state.uniform(1.5f,3.25f);
						chainLightningCastingEffect(start,end,state);
					}
					obj.animateChainLightningCasting(state);
					return true;
				case CastingStatus.interrupted: return false;
				case CastingStatus.finished:
					auto start=OrderTarget(TargetType.terrain,0,rotate(obj.rotation,offset)+obj.position);
					auto end=chainLightningCast.target;
					chainLightning(obj.id,obj.side,start,end,spell,state);
					return false;
			}
		},()=>false)(manaDrain.wizard,status);
	}
}
bool updateChainLightningCastingEffect(B)(ref ChainLightningCastingEffect!B castingEffect,ObjectState!B state){
	with(castingEffect){
		++frame;
		if(frame%changeShapeDelay==0)
			bolt.changeShape!(0.5f)(state);
		return frame<totalFrames;
	}
}

OrderTarget newChainLightningTarget(B)(OrderTarget last,OrderTarget current,SacSpell!B spell,ObjectState!B state){
	auto position=2.0f*current.position-last.position;
	float limit=state.uniform(0.25f,1.0f)*spell.effectRange;
	auto offset=1.5f*limit*state.uniform(0.0f,1.0f)*state.uniformDirection!(float,2)();
	position.x+=offset.x, position.y+=offset.y;
	if((position-current.position).lengthsqr>limit^^2)
		position=current.position+(position-current.position).normalized*limit;
	position.z=state.getHeight(position); // TODO: avoid void?
	return OrderTarget(TargetType.terrain,0,position);
}

void updateChainLightningTarget(B)(ref OrderTarget target,ObjectState!B state){
	if(state.isValidTarget(target.id,TargetType.creature)){
		auto cand=state.movingObjectById!(center,()=>Vector3f.init)(target.id);
		if(!isNaN(cand.x)) target.position=cand;
	}
}
void predictChainLightningTarget(B)(ref OrderTarget target,ref PositionPredictor predictor,float progress,ObjectState!B state){
	updateChainLightningTarget(target,state);
	auto predicted=predictor.predictCenterAtTime((1.0f-progress)*ChainLightning!B.travelFrames/updateFPS,target,state);
	target.position=(1.0f-progress)*target.position+progress*predicted;
}

enum chainLightningGain=2.0f;
bool updateChainLightning(B)(ref ChainLightning!B chainLightning,ObjectState!B state){
	with(chainLightning){
		auto progress=float(frame+1)/travelFrames;
		predictChainLightningTarget(current,predictor,progress,state);
		if(frame==0) lightning(wizard,side,last,current,spell,state,false);
		if(++frame==travelFrames){
			if(current.id) addTarget(current.id);
			if(++numTargets>=totTargets)
				return false;
			static bool filter(ref CenterProximityEntry entry,ObjectState!B state,ChainLightning!B* chainLightning){
				if(state.movingObjectById!((ref obj,state)=>obj.health(state)==0.0f,()=>true)(entry.id,state)) return false;
				return !chainLightning.hasTarget(entry.id);
			}
			int newTarget=state.proximity.closestNonAllyInRange!filter(side,current.position,spell.effectRange,EnemyType.creature,state,float.infinity,state,&chainLightning);
			OrderTarget next;
			if(newTarget) next=OrderTarget(TargetType.creature,newTarget,state.movingObjectById!((ref obj)=>obj.position,()=>Vector3f.init)(newTarget));
			if(isNaN(next.position.x)) next=newChainLightningTarget(last,current,spell,state);
			last=current;
			current=next;
			frame=0;
		}
		return true;
	}
}


void animateAnimateDeadCasting(B)(ref MovingObject!B wizard,ObjectState!B state){
	auto castParticle=SacParticle!B.get(ParticleType.castCharnel2);
	wizard.animateCasting(castParticle,state);
}
bool updateAnimateDeadCasting(B)(ref AnimateDeadCasting!B animateDeadCasting,ObjectState!B state){
	with(animateDeadCasting){
		final switch(manaDrain.update(state)){
			case CastingStatus.underway:
				state.movingObjectById!(animateAnimateDeadCasting,(){})(manaDrain.wizard,state);
				return true;
			case CastingStatus.interrupted,CastingStatus.finished: return false;
		}
	}
}

enum animateDeadGain=2.0f;
void updateAnimateDeadCaster(B)(ref OrderTarget target,ObjectState!B state){
	if(state.isValidTarget(target.id,TargetType.creature)){
		auto cand=state.movingObjectById!((ref obj){
			auto hbox=obj.sacObject.hitbox(Quaternionf.identity(),AnimationState.stance1,0);
			auto offset=Vector3f(0.5f*(hbox[0].x+hbox[1].x),0.5f*(hbox[0].y+hbox[1].y),0.2f*hbox[0].z+0.8f*hbox[1].z);
			return obj.position+rotate(obj.rotation,offset);
		},()=>Vector3f.init)(target.id);
		if(!isNaN(cand.x)) target.position=cand;
	}
}
void updateAnimateDeadTarget(B)(ref OrderTarget target,ObjectState!B state){
	if(state.isValidTarget(target.id,TargetType.creature)){
		auto cand=state.movingObjectById!(center,()=>Vector3f.init)(target.id);
		if(!isNaN(cand.x)) target.position=cand;
	}
}
void animateDeadEffect(B)(OrderTarget start,OrderTarget end,SacSpell!B spell,ObjectState!B state){
	auto distance=(end.position-start.position).length;
	auto startDirection=2.0f*(Vector3f(0.0f,0.0f,3.0f)+2.0f*state.uniformDirection()).normalized*distance;
	auto endDirection=2.0f*(Vector3f(0.0f,0.0f,-3.0f)+2.0f*state.uniformDirection()).normalized*distance;
	float relativeLength=state.uniform(0.15f,0.5f);
	state.addEffect(AnimateDeadEffect!B(start,startDirection,end,endDirection,relativeLength,spell));
}
bool updateAnimateDead(B)(ref AnimateDead!B animateDead,ObjectState!B state){
	with(animateDead){
		caster.updateAnimateDeadCaster(state);
		creature.updateAnimateDeadTarget(state);
		if(frame<=lifetime){
			if(frame%(updateFPS/30)==0&&!state.uniform(2))
				animateDeadEffect(caster,creature,spell,state);
			if(--soundTimer<=0){
				if(state.isValidTarget(creature.id,TargetType.creature)){
					soundTimer=playSoundAt!true("9cas",creature.id,state,animateDeadGain);
				}else{
					soundTimer=playSoundAt!true("9cas",creature.position,state,animateDeadGain);
				}
				soundTimer=state.uniform(soundTimer/3,soundTimer);
			}
		}
		return ++frame<=lifetime;
	}
}
bool updateAnimateDeadEffect(B)(ref AnimateDeadEffect!B animateDeadEffect,ObjectState!B state){
	with(animateDeadEffect){
		end.updateAnimateDeadTarget(state);
		return ++frame<=totalFrames;
	}
}

void animateEruptCasting(B)(ref MovingObject!B wizard,ObjectState!B state){
	auto castParticle=SacParticle!B.get(ParticleType.dirt);
	wizard.animateCasting!(true,1)(castParticle,state);
	static assert(updateFPS==60);
	auto hitbox=wizard.relativeHitbox;
	auto scale=1.0f;
	enum numParticles=6;
	foreach(i;0..numParticles){
		auto position=1.1f*state.uniform(cast(Vector2f[2])[hitbox[0].xy,hitbox[1].xy]);
		auto distance=(state.uniform(3)?state.uniform(0.3f,0.6f):state.uniform(1.5f,2.5f))*(hitbox[1].z-hitbox[0].z);
		auto fullLifetime=2.0f*castParticle.numFrames/float(updateFPS);
		auto lifetime=cast(int)(castParticle.numFrames*state.uniform(0.0f,2.0f));
		// TODO: particles should accelerate upwards
		state.addParticle(Particle!B(castParticle,wizard.position+rotate(wizard.rotation,Vector3f(position.x,position.y,state.uniform(0.0f,0.5f*distance))),Vector3f(0.0f,0.0f,distance/fullLifetime),scale,lifetime,0));
	}
}
bool updateEruptCasting(B)(ref EruptCasting!B eruptCast,ObjectState!B state){
	with(eruptCast){
		final switch(manaDrain.update(state)){
			case CastingStatus.underway:
				state.movingObjectById!(animateEruptCasting,(){})(manaDrain.wizard,state);
				erupt.updateErupt(state);
				erupt.frame=min(castingLimit,erupt.frame);
				return true;
			case CastingStatus.interrupted:
				return false;
			case CastingStatus.finished:
				.erupt(erupt,state);
				return false;
		}
	}
}

void animateErupt(B)(ref Erupt!B erupt,ObjectState!B state){
	enum numParticles=24;
	auto sacParticle=SacParticle!B.get(ParticleType.dust);
	foreach(i;0..numParticles){
		auto dir=state.uniformDirection!(float,2)();
		auto dist=state.uniform(4)?erupt.range*(1.0f-state.uniform(0.0f,1.0f)*state.uniform(0.0f,1.0f)):erupt.spell.damageRange*state.uniform(0.0f,1.0f);
		auto position=erupt.position+dist*Vector3f(dir.x,dir.y,0.0f);
		if(state.isOnGround(position)){
			auto velocity=Vector3f(0.0f,0.0f,1.0f)+0.6f*state.uniformDirection();
			auto lifetime=31;
			auto scale=4.0f;
			auto frame=0;
			position.z=state.getGroundHeight(position)+1.0f;
			position+=0.6f*state.uniformDirection();
			state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
		}
	}
	if(state.uniform(3)==0){
		auto distance=(1.0f-state.uniform(0.0f,1.0f)*state.uniform(0.0f,1.0f));
		auto direction=state.uniformDirection!(float,2)();
		auto position=erupt.position+0.75f*erupt.range*distance*Vector3f(direction.x,direction.y,0.0f);
		if(state.isOnGround(position)){
			auto velocity=(1.0f-0.5f*distance)*(30.0f+state.uniform(-10.0f,10.0f))*Vector3f(direction.x,direction.y,state.uniform(0.5f,2.0f)).normalized;
			auto rotationSpeed=2*pi!float*state.uniform(0.5f,2.0f)/updateFPS;
			auto rotationAxis=state.uniformDirection();
			auto rotationUpdate=rotationQuaternion(rotationAxis,rotationSpeed);
			position.z=state.getGroundHeight(position);
			auto debris=EruptDebris!B(position,velocity,rotationUpdate,Quaternionf.identity());
			state.addEffect(debris);
			if(state.uniform(5)==0) playSoundAt("lpxe",position,state,eruptGain0);
			enum numParticles3=15;
			auto sacParticle3=SacParticle!B.get(ParticleType.rock);
			foreach(i;0..numParticles3){
				auto pdirection=state.uniformDirection();
				auto pvelocity=0.6f*state.uniform(7.5f,15.0f)*pdirection;
				auto scale=0.6f*state.uniform(1.0f,2.5f);
				auto lifetime=95;
				auto frame=0;
				state.addParticle(Particle!B(sacParticle3,position,pvelocity,scale,lifetime,frame));
			}
			// TODO: scar
		}
	}
}

void eruptExplosion(B)(ref Erupt!B erupt,ObjectState!B state){
	static bool callback(int target,Erupt!B* erupt,ObjectState!B state){
		if(!state.targetTypeFromId(target).among(TargetType.creature,TargetType.building))
			return false;
		state.objectById!((ref obj,erupt,state){
			auto diff=obj.position.xy-erupt.position.xy;
			auto difflen=diff.length;
			auto direction=Vector3f(diff.x,diff.y,20.0f).normalized;
			void dealDamage(){
				if(difflen<erupt.spell.damageRange)
					dealSplashSpellDamage(obj,erupt.spell,erupt.wizard,erupt.side,direction,difflen,DamageMod.none,state);
			}
			static if(is(typeof(obj)==MovingObject!B,B)){
				if(difflen<erupt.throwRange){
					auto strength=20.0f*(1.0f-difflen/erupt.throwRange);
					obj.catapult(direction*strength,state);
					dealDamage();
				}
			}else dealDamage();
		})(target,erupt,state);
		return false;
	}
	with(erupt){
		playSoundAt("tpre",position,state,eruptGain2);
		dealSplashSpellDamageAt!callback(0,spell,spell.effectRange,wizard,side,position,DamageMod.none,state,&erupt,state);
		state.addEffect(ScreenShake(position,updateFPS/3,4.0f,100.0f));
	}
	auto position=erupt.position;
	position.z=state.getHeight(position);
	enum numDebris=64;
	foreach(i;0..numDebris){
		auto angle=state.uniform(-pi!float,pi!float);
		auto velocity=(30.0f+state.uniform(-7.5f,7.5f))*Vector3f(cos(angle),sin(angle),state.uniform(-1.0f,2.0f)).normalized;
		auto rotationSpeed=2*pi!float*state.uniform(0.5f,2.0f)/updateFPS;
		auto rotationAxis=state.uniformDirection();
		auto rotationUpdate=rotationQuaternion(rotationAxis,rotationSpeed);
		auto debris=EruptDebris!B(position,velocity,rotationUpdate,Quaternionf.identity());
		state.addEffect(debris);
	}
	enum numParticles3=200;
	auto sacParticle3=SacParticle!B.get(ParticleType.rock);
	foreach(i;0..numParticles3){
		auto pdirection=(state.uniformDirection()+Vector3f(0.0f,0.0f,0.5f)).normalized;
		auto pvelocity=3.0f*state.uniform(7.5f,15.0f)*pdirection;
		auto scale=2.0f*state.uniform(1.0f,2.5f);
		auto lifetime=127;
		auto frame=0;
		state.addParticle(Particle!B(sacParticle3,position,pvelocity,scale,lifetime,frame));
	}
	// TODO: scar
}

enum eruptGain0=2.0f, eruptGain1=4.0f, eruptGain2=8.0f;
bool updateErupt(B)(ref Erupt!B erupt,ObjectState!B state){
	with(erupt){
		if(--soundTimer0<=0) soundTimer0=playSpellSoundTypeAt!true(SoundType.convertRevive,position,state,eruptGain0); // TODO: stop sound
		if(--soundTimer1<=0) soundTimer1=playSpellSoundTypeAt!true(SoundType.bore,position,state,eruptGain1); // TODO: stop sound
		if(frame%(updateFPS/10)==0) state.addEffect(ScreenShake(position,updateFPS/10,1.5f,200.0f));
		static assert(growDur==4.2f);
		enum eruptFrame=42*updateFPS/10;
		if(++frame<eruptFrame){
			animateErupt(erupt,state);
		}else if(frame==eruptFrame){
			eruptExplosion(erupt,state);
		}else{
			auto waveLoc=waveRange*(float(frame)/updateFPS-growDur)/waveDur;
			if(stunMinRange<waveLoc&&waveLoc<stunMaxRange){
				// TODO: more efficient method to query creatures currently on the ring
				static bool callback2(int target,Erupt!B* erupt,float waveLoc,ObjectState!B state){
					state.movingObjectById!((ref obj,erupt,waveLoc,state){
							auto diff=obj.position.xy-erupt.position.xy;
							auto difflen=diff.length;
							if(erupt.stunMinRange<difflen&&abs(difflen-waveLoc)<1.5f*erupt.waveRange/(erupt.waveDur*updateFPS))
								obj.stunWithCooldown(stunCooldownFrames,state);
						},(){})(target,erupt,waveLoc,state);
					return false;
				}
				dealSplashSpellDamageAt!callback2(0,spell,waveLoc+0.1f,wizard,side,position,DamageMod.none,state,&erupt,waveLoc,state);
			}
		}
		return frame<=totalFrames;
	}
}

enum eruptDebrisFallLimit=1000.0f;
bool updateEruptDebris(B)(ref EruptDebris!B eruptDebris,ObjectState!B state){
	auto oldPosition=eruptDebris.position;
	eruptDebris.position+=eruptDebris.velocity/updateFPS;
	eruptDebris.velocity.z-=30.0f/updateFPS;
	eruptDebris.rotation=eruptDebris.rotationUpdate*eruptDebris.rotation;
	if(++eruptDebris.frame>=updateFPS/2&&state.isOnGround(eruptDebris.position)){
		auto height=state.getGroundHeight(eruptDebris.position);
		if(height>eruptDebris.position.z){
			eruptDebris.position.z=height;
			enum numParticles3=15;
			auto sacParticle3=SacParticle!B.get(ParticleType.rock);
			foreach(i;0..numParticles3){
				auto direction=state.uniformDirection();
				auto velocity=0.6f*state.uniform(7.5f,15.0f)*direction;
				auto scale=0.6f*state.uniform(1.0f,2.5f);
				auto lifetime=95;
				auto frame=0;
				state.addParticle(Particle!B(sacParticle3,eruptDebris.position,velocity,scale,lifetime,frame));
			}
			enum numParticles4=4;
			auto sacParticle4=SacParticle!B.get(ParticleType.dirt);
			foreach(i;0..numParticles4){
				auto direction=state.uniformDirection();
				auto position=eruptDebris.position+0.25f*direction;
				auto velocity=Vector3f(0.0f,0.0f,0.0f);
				auto scale=1.0f;
				auto frame=state.uniform(2)?0:state.uniform(24);
				auto lifetime=63-frame;
				state.addParticle(Particle!B(sacParticle4,position,velocity,scale,lifetime,frame));
			}
			// TODO: scar
			if(state.uniform(5)==0) playSoundAt("pmir",eruptDebris.position,state,1.0f);
			return false;
		}
	}else if(eruptDebris.position.z<state.getHeight(eruptDebris.position)-eruptDebrisFallLimit)
		return false;
	enum numParticles=3;
	auto sacParticle=SacParticle!B.get(ParticleType.dirt);
	auto velocity=Vector3f(0.0f,0.0f,0.0f);
	auto scale=0.5f;
	auto lifetime=sacParticle.numFrames-1;
	auto frame=sacParticle.numFrames/2;
	foreach(i;0..numParticles){
		auto position=oldPosition*((cast(float)numParticles-1-i)/(numParticles-1))+eruptDebris.position*(cast(float)i/(numParticles-1));
		position+=0.1f*state.uniformDirection();
		state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
	}
	return true;
}

Tuple!(Vector3f,Vector3f) dragonfireCastingPosition(B)(ref MovingObject!B obj,SacSpell!B spell,int frame,int castingTime,ObjectState!B state){
	auto hbox=obj.sacObject.hitbox(Quaternionf.identity(),AnimationState.stance1,0);
	auto castingHeight=hbox[1].z+4.0f;
	auto radius=0.5f*float(castingTime)/updateFPS*spell.speed/(2.0f*pi!float)*(0.5f+0.5f*frame/castingTime);
	auto φ=2.0f*pi!float*frame/castingTime;
	auto offset=Vector3f(radius*cos(φ),radius*sin(φ),castingHeight*frame/castingTime);
	auto direction=Vector3f(radius*-2.0f*pi!float*sin(φ),radius*2.0f*pi!float*cos(φ),castingHeight).normalized;
	return tuple(obj.position+rotate(obj.rotation,offset),rotate(obj.rotation,direction));
}
void animateDragonfireCasting(B)(ref MovingObject!B obj,ObjectState!B state){
	obj.animatePyroCasting(state);
}
bool animateDragonfireCasting(B)(ref Dragonfire!B dragonfire,int wizard,int castingTime,ObjectState!B state,float scale_=1.0f){
	auto sacParticle=SacParticle!B.get(ParticleType.firy);
	auto frameOffset=sacParticle.numFrames;
	auto ncenter=state.movingObjectById!((ref obj,dragonfire,frameOffset,castingTime,state){
		obj.animateDragonfireCasting(state);
		return obj.dragonfireCastingPosition(dragonfire.spell,dragonfire.frame+frameOffset,castingTime,state)[0];
	},()=>Vector3f.init)(wizard,&dragonfire,frameOffset,castingTime,state);
	if(isNaN(ncenter.x)) return false;
	if(dragonfire.frame+frameOffset>castingTime) return true;
	auto radius=dragonfire.spell.damageRange;
	Vector3f[2] hitbox=[dragonfire.position-0.25f*radius*Vector3f(1.0f,1.0f,1.0f),dragonfire.position+0.25f*radius*Vector3f(1.0f,1.0f,1.0f)];
	auto center=dragonfire.position;
	auto scale=0.5f+0.5f*(scale_);
	enum numParticles=2;
	foreach(i;0..numParticles){
		auto position=state.uniform(hitbox)-center;
		position.x*=2.0f;
		position.y*=2.0f;
		position.z*=2.0f;
		position*=scale;
		position+=center;
		auto lifetime=sacParticle.numFrames/60.0f;
		auto velocity=(ncenter-position)/lifetime;
		state.addParticle(Particle!B(sacParticle,position,velocity,scale*0.5f*radius,sacParticle.numFrames,0));
	}
	return true;
}
bool updateDragonfireCasting(B)(ref DragonfireCasting!B dragonfireCast,ObjectState!B state){
	with(dragonfireCast){
		final switch(manaDrain.update(state)){
			case CastingStatus.underway:
				auto posDir=state.movingObjectById!(dragonfireCastingPosition,()=>Tuple!(Vector3f,Vector3f).init)(dragonfire.wizard,dragonfire.spell,dragonfire.frame,castingTime,state);
				if(isNaN(posDir[0].x)) return false;
				dragonfire.animateDragonfire(posDir.expand,state,scale);
				return dragonfire.animateDragonfireCasting(manaDrain.wizard,castingTime,state,scale);
			case CastingStatus.interrupted:
				return false;
			case CastingStatus.finished:
				.dragonfire(dragonfire,state);
				return false;
		}
	}
}

void animateDragonfire(B)(ref Dragonfire!B dragonfire,Vector3f newPosition,Vector3f newDirection,ObjectState!B state,float scale_=1.0f){
	with(dragonfire){
		auto oldPosition=position;
		position=newPosition;
		direction=newDirection;
		++frame;
		enum numParticles=8;
		auto sacParticle1=SacParticle!B.get(ParticleType.firy);
		auto sacParticle2=SacParticle!B.get(ParticleType.fireball);
		auto velocity=Vector3f(0.0f,0.0f,0.0f);
		auto lifetime=31;
		auto pscale=2.0f*scale_;
		auto frame=0;
		foreach(i;0..numParticles){
			auto sacParticle=i!=0?sacParticle1:sacParticle2;
			auto position=oldPosition*((cast(float)numParticles-1-i)/numParticles)+position*(cast(float)(i+1)/numParticles);
			position+=0.3f*scale_*state.uniformDirection();
			state.addParticle(Particle!B(sacParticle,position-0.7f*scale_*direction,velocity,pscale,lifetime,frame));
		}
	}
}

bool changeDirectionTowards(T,B)(ref T spell_,float targetFlyingHeight,ObjectState!B state){
	with(spell_){
		auto targetCenter=target.center(state);
		auto predictedCenter=predictor.predictCenter(position,spell.speed,target,state);
		auto targetRotation=rotationBetween(direction,(predictedCenter-position).normalized);
		auto actualRotationSpeed=rotationSpeed;
		auto distancesqr=(targetCenter-position).lengthsqr;
		if(distancesqr<4.0f^^2) actualRotationSpeed=4.0f*rotationSpeed/sqrt(distancesqr);
		direction=rotate(limitRotation(targetRotation,actualRotationSpeed/updateFPS),direction).normalized;
		auto newPosition=position+direction*spell.speed/updateFPS;
		if(state.isOnGround(newPosition)){
		   auto height=state.getGroundHeight(newPosition);
		   if(newPosition.z<height+targetFlyingHeight){
			   auto ndir=state.getGroundHeightDerivative(position,direction);
			   direction=Vector3f(direction.x,direction.y,ndir).normalized;
			   newPosition.z=height+targetFlyingHeight;
			}
		}
		position=newPosition;
		return (targetCenter-position).lengthsqr<0.75f^^2;
	}
}

bool updateDragonfireTarget(B)(ref Dragonfire!B dragonfire,ObjectState!B state){
	with(dragonfire){
		if(!target.id){
			static bool filter(ref CenterProximityEntry entry,ObjectState!B state,Dragonfire!B* dragonfire){
				if(state.movingObjectById!((ref obj,state)=>obj.health(state)==0.0f,()=>true)(entry.id,state)) return false;
				return !dragonfire.hasTarget(entry.id);
			}
			int newTarget=state.proximity.closestNonAllyInRange!filter(side,position,spell.effectRange,EnemyType.creature,state,float.infinity,state,&dragonfire);
			if(newTarget){
				target=OrderTarget(TargetType.creature,newTarget,state.movingObjectById!((ref obj)=>obj.position,()=>Vector3f.init)(newTarget));
				if(!dragonfire.addTarget(newTarget))
					return false;
				playSoundAt("2ifd",dragonfire.position,state,dragonfireGain); // TODO: move sound with spell?
				return true;
			}else{
				++unsuccessfulTries;
			}
		}
		target.id=0;
		target.position+=0.5f*spell.effectRange*state.uniformDirection();
		target.position.z=0.5f*spell.effectRange+state.getHeight(target.position);
		return unsuccessfulTries<=maxUnsuccessful;
	}
}

bool updateDragonfirePosition(B)(ref Dragonfire!B dragonfire,ObjectState!B state){
	with(dragonfire){
		if(target.id&&state.isValidTarget(target.id,TargetType.creature)){
			auto cand=state.movingObjectById!(center,()=>Vector3f.init)(target.id);
			if(!isNaN(cand.x)) target.position=cand;
		}
		auto radius=spell.damageRange;
		Vector3f[2] hitbox=[position-0.5f*radius*Vector3f(1.0f,1.0f,1.0f),position+0.5f*radius*Vector3f(1.0f,1.0f,1.0f)];
		static void burn(ProximityEntry target,ObjectState!B state,SacSpell!B spell,int attacker,int side){
			if(target.id==attacker) return;
			state.movingObjectById!((ref obj,damage,attacker,side,state){
				//if(state.sides.getStance(side,obj.side)!=Stance.ally)
				obj.ignite(damage,attacker,side,state);
			},(){})(target.id,spell.amount/updateFPS,attacker,side,state);
		}
		collisionTargets!burn(hitbox,state,spell,wizard,side);
		if(dragonfire.changeDirectionTowards(1.0f,state)){
			playSoundAt("2ifd",dragonfire.position,state,dragonfireGain); // TODO: move sound with spell?
			if(target.id){
				if(state.isValidTarget(target.id)){
					dealSpellDamage(target.id,spell,wizard,side,direction,DamageMod.ignite,state); // TODO: should this be splash spell?
					setAblaze(target.id,updateFPS,false,0.0f,wizard,side,DamageMod.ignite,state);
				}
				static bool callback(int target,int wizard,int side,ObjectState!B state){
					setAblaze(target,updateFPS,false,0.0f,wizard,side,DamageMod.none,state);
					return true;
				}
				dealSplashSpellDamageAt!callback(target.id,spell,spell.damageRange,wizard,side,position,DamageMod.ignite,state,wizard,side,state);
			}
			if(!dragonfire.updateDragonfireTarget(state))
				return false;
		}
		return true;
	}
}

enum dragonfireGain=4.0f;
bool updateDragonfire(B)(ref Dragonfire!B dragonfire,ObjectState!B state){
	with(dragonfire){
		dragonfire.animateDragonfire(dragonfire.position,dragonfire.direction,state,scale);
		bool shrinking=scale<1.0f;
		if(!dragonfire.updateDragonfirePosition(state))
			shrinking=true;
		if(shrinking){
			scale=max(0.0f,scale-(1.0f/shrinkTime)/updateFPS);
			if(scale==0.0f) return false;
		}
		return true;
	}
}

void animateSoulWindCasting(B)(ref MovingObject!B wizard,ObjectState!B state){
	auto castParticle=SacParticle!B.get(ParticleType.chainLightningCasting);
	wizard.animateCasting(castParticle,state);
}

bool updateSoulWindCasting(B)(ref SoulWindCasting!B soulWindCast,ObjectState!B state){
	with(soulWindCast){
		final switch(manaDrain.update(state)){
			case CastingStatus.underway:
				if(!soulWind.updateSoulWindPosition(state))
					return false;
				return state.movingObjectById!((ref obj){
					obj.animateSoulWindCasting(state);
					return true;
				},()=>false)(manaDrain.wizard);
			case CastingStatus.interrupted:
				return false;
			case CastingStatus.finished:
				.soulWind(soulWind,state);
				return false;
		}
	}
}

void animateSoulWind(B)(ref SoulWind!B soulWind,Vector3f oldPosition,ObjectState!B state){
	with(soulWind){
		if(state.isOnGround(soulWind.position)){
			enum numParticles=2;
			auto sacParticle=SacParticle!B.get(ParticleType.dust);
			foreach(i;0..numParticles){
				auto position=oldPosition*((cast(float)numParticles-1-i)/numParticles)+position*(cast(float)(i+1)/numParticles);
				auto velocity=Vector3f(0.0f,0.0f,0.0f);
				auto lifetime=31;
				auto scale=1.0f;
				auto frame=0;
				position+=0.3f*state.uniformDirection();
				state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
			}
		}
	}
}

enum soulWindGain=2.0f;
bool updateSoulWindPosition(B)(ref SoulWind!B soulWind,ObjectState!B state){
	static assert(soulWind.roundtripTime%4==0);
	enum soulFrame=soulWind.roundtripTime/2;
	enum backFrame=soulWind.roundtripTime;
	enum WindPhase{
		toSoul,
		back,
	}
	static WindPhase windPhase(int frame){
		if(frame<=soulFrame) return WindPhase.toSoul;
		return WindPhase.back;
	}
	static int nextTransitionFrame(int frame){
		final switch(windPhase(frame)){
			case WindPhase.toSoul: return soulFrame;
			case WindPhase.back: return backFrame;
		}
	}
	static int framesLeft(int frame){ return nextTransitionFrame(frame)-frame; }
	static float relativeProgress(int frame){
		if(frame<=soulFrame) return float(frame)/soulFrame;
		return float(frame-soulFrame)/(backFrame-soulFrame);
	}
	auto prevTargetPosition=soulWind.positionPredictor.lastPosition;
	auto oldPosition=soulWind.position;
	soulWind.frame+=1;
	auto soulPosition=state.soulById!((ref soul)=>soul.position,()=>Vector3f.init)(soulWind.soul);
	if(isNaN(soulPosition.x)) return false;
	auto wizardPosition=state.movingObjectById!((ref obj)=>obj.position,()=>Vector3f.init)(soulWind.wizard);
	Vector3f[2] windOrigin(int frame){
		final switch(windPhase(frame)){
			case WindPhase.toSoul: return [soulWind.startPosition,Vector3f(0.0f,0.0f,0.0f)];
			case WindPhase.back: return [soulWind.startPosition,soulWind.targetVelocity];
		}
	}
	Vector3f[2] windTarget(int frame){
		final switch(windPhase(frame)){
			case WindPhase.toSoul: return [soulPosition,soulWind.targetVelocity];
			case WindPhase.back: return [wizardPosition,0.75f*(wizardPosition-soulWind.startPosition)];
		}
	}
	auto targetLocation=windTarget(soulWind.frame);
	auto targetPosition=targetLocation[0],targetVelocity=targetLocation[1];
	if(isNaN(targetPosition.x)) return false;
	if(soulWind.frame==soulFrame+1){
		playSpellSoundTypeAt(SoundType.fireball,oldPosition,state,soulWindGain); // TODO: move sound with soul wind?
		auto side=state.movingObjectById!((ref obj)=>obj.side,()=>-1)(soulWind.wizard);
		state.soulById!((ref soul,side,state){
			soul.severSoul(state);
			soul.preferredSide=side;
		},(){})(soulWind.soul,side,state);
		soulWind.startPosition=oldPosition;
		soulWind.positionPredictor.lastPosition=targetPosition;
	}
	auto curFramesLeft=framesLeft(soulWind.frame);
	auto predictedTargetPosition=soulWind.positionPredictor.predictAtTime(float(curFramesLeft)/updateFPS,targetPosition);
	auto relativePosition=1.0f/(curFramesLeft+1);
	Vector3f[2] newLocation=cintp2([windOrigin(soulWind.frame),windTarget(soulWind.frame)],relativeProgress(soulWind.frame));
	auto newPosition=newLocation[0], newVelocity=newLocation[1];
	newPosition.z=state.getHeight(newPosition);
	if(windPhase(soulWind.frame)>WindPhase.toSoul){
		state.soulById!((ref soul,windPosition){
			if(!soul.collectorId) soul.position=windPosition;
		},(){})(soulWind.soul,newPosition);
	}
	soulWind.position=newPosition;
	soulWind.animateSoulWind(oldPosition,state);
	return soulWind.frame<backFrame;
}

bool soulWindEffect(B)(OrderTarget start,OrderTarget end,ObjectState!B state){
	playSpellSoundTypeAt(SoundType.lightning,0.5f*(start.position+end.position),state,4.0f);
	auto soulWindEffect=SoulWindEffect(start,end,0);
	foreach(ref bolt;soulWindEffect.bolts)
		bolt.changeShape(state);
	state.addEffect(soulWindEffect);
	return true;
}

bool updateSoulWind(B)(ref SoulWind!B soulWind,ObjectState!B state){
	if(!soulWind.updateSoulWindPosition(state))
		return false;
	static bool callback(int target,SacSpell!B spell,int wizard,int side,SoulWind!B* soulWind,ObjectState!B state){
		if(!soulWind.addTarget(target)) return false;
		return state.movingObjectById!((ref obj,spell,wizard,side,state){
			if(state.sides.getStance(side,obj.side)==Stance.ally) return false;
			obj.stunWithCooldown(stunCooldownFrames,state);
			auto start=positionTarget(soulWind.position+Vector3f(0.0f,0.0f,1.0f),state);
			auto end=centerTarget(target,state);
			soulWindEffect(start,end,state);
			obj.dealSpellDamage(spell,wizard,side,end.position-start.position,DamageMod.none,state);
			return false;
		},()=>false)(target,spell,wizard,side,state);
	}
	auto side=state.movingObjectById!((ref obj)=>obj.side,()=>-1)(soulWind.wizard);
	if(side==-1) return false;
	with(soulWind) dealSplashSpellDamageAt!callback(0,spell,spell.effectRange,wizard,side,position,DamageMod.none,state,spell,wizard,side,&soulWind,state);
	return true;
}

bool updateSoulWindEffect(B)(ref SoulWindEffect soulWindEffect,ObjectState!B state){
	soulWindEffect.frame+=1;
	static assert(updateFPS==60);
	if(soulWindEffect.frame>=soulWindEffect.totalFrames) return false;
	if(soulWindEffect.frame%soulWindEffect.changeShapeDelay==0)
		foreach(ref bolt;soulWindEffect.bolts)
			bolt.changeShape(state);
	//soulWindEffect.start.position=soulWindEffect.start.center(state);
	soulWindEffect.end.position=soulWindEffect.end.center(state);
	return true;
}

void animateExplosionCasting(B)(ref MovingObject!B wizard,ObjectState!B state){
	auto castParticle=SacParticle!B.get(ParticleType.firy);
	wizard.animateCasting!(false,4,true)(castParticle,state);
}

bool updateExplosionCasting(B)(ref ExplosionCasting!B explosionCast,ObjectState!B state){
	with(explosionCast){
		foreach(ref effect;effects){
			effect.frame+=1;
			if(!failed) effect.scale=min(effect.scale+1.0f/castingTime,1.0f);
			else effect.scale=max(0.0f,effect.scale-effect.shrinkSpeed/updateFPS);
			if(--effect.soundTimer<=0) effect.soundTimer=playSoundAt!true("5plf",effect.position,state,1.0f);
		}
		if(failed) return effects[].any!((ref effect)=>effect.scale!=0.0f);
		final switch(manaDrain.update(state)){
			case CastingStatus.underway:
				state.movingObjectById!(animateExplosionCasting,{})(manaDrain.wizard,state);
				return true;
			case CastingStatus.interrupted:
				return false;
			case CastingStatus.finished:
				explosion(manaDrain.wizard,side,effects,spell,state);
				return false;
		}
	}
}

enum haloRockSize=0.7f; // TODO: use bounding box from sac object
static immutable Vector3f[2] haloRockHitbox=[-0.5f*haloRockSize*Vector3f(1.0f,1.0f,1.0f),0.5f*haloRockSize*Vector3f(1.0f,1.0f,1.0f)];
int haloRockCollisionTarget(B)(int side,Vector3f position,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state,int side){
		return entry.isProjectileObstacle&&state.objectById!(.side)(entry.id,state)!=side;
	}
	return collisionTarget!(haloRockHitbox,filter)(side,position,state,side);
}

void haloRockExplosion(B)(ref HaloRock!B haloRock,int target,ObjectState!B state,bool isAbility){
	playSpellSoundTypeAt(isAbility?SoundType.bombardmentHit:SoundType.explodingRock,haloRock.position,state,2.0f);
	if(state.isValidTarget(target)) dealSpellDamage(target,haloRock.spell,haloRock.wizard,haloRock.side,haloRock.velocity,DamageMod.none,state);
	enum numParticles3=50;
	auto sacParticle3=SacParticle!B.get(ParticleType.rock);
	foreach(i;0..numParticles3){
		auto direction=state.uniformDirection();
		auto velocity=state.uniform(7.5f,15.0f)*haloRockSize/2.0f*direction;
		auto scale=state.uniform(1.0f,2.5f)*haloRockSize/2.0f;
		auto lifetime=95;
		auto frame=0;
		state.addParticle(Particle!B(sacParticle3,haloRock.position,velocity,scale,lifetime,frame));
	}
	enum numParticles4=10;
	auto sacParticle4=SacParticle!B.get(ParticleType.dirt);
	foreach(i;0..numParticles4){
		auto direction=state.uniformDirection();
		auto position=haloRock.position+0.75f*haloRockSize/2.0f*direction;
		auto velocity=Vector3f(0.0f,0.0f,0.0f);
		auto scale=3.0f*haloRockSize/2.0f;
		auto frame=state.uniform(2)?0:state.uniform(24);
		auto lifetime=63-frame;
		state.addParticle(Particle!B(sacParticle4,position,velocity,scale,lifetime,frame));
	}
}

bool updateHaloOfEarthCasting(B)(ref HaloOfEarthCasting!B haloOfEarthCast,ObjectState!B state){
	with(haloOfEarthCast){
		frame+=1;
		auto center=state.movingObjectById!(haloRockCenterPosition,()=>Vector3f.init)(haloOfEarth.wizard,state);
		foreach(ref haloRock;haloOfEarth.rocks[haloOfEarth.numDespawned..haloOfEarth.numSpawned]){
			haloRock.updateHaloRock(center,state,true,haloOfEarth.isAbility);
		}
		auto rockDelay=castingTime/(haloOfEarth.numRocks+2);
		if(haloOfEarth.numSpawned<haloOfEarth.numRocks&&!((frame-rockDelay/2)%rockDelay))
			if(!isNaN(center.x)) haloOfEarth.spawnHaloRock(state);
		final switch(manaDrain.update(state)){
			case CastingStatus.underway:
				return true;
			case CastingStatus.interrupted:
				haloOfEarth.despawnHaloOfEarth(state);
				if(haloOfEarth.numDespawned<haloOfEarth.numSpawned)
					.haloOfEarth(haloOfEarth,state);
				return false;
			case CastingStatus.finished:
				.haloOfEarth(haloOfEarth,state);
				return false;
		}
	}
}

enum haloRockBuryDepth=0.25f;
Vector3f haloRockSpawnPosition(B)(ref MovingObject!B obj,ObjectState!B state,bool isAbility){
	auto box=scaleBox(obj.hitbox,isAbility?1.25f:2.5f); // TODO: improve
	auto position=state.uniform(box);
	position.z=state.getHeight(position)-haloRockBuryDepth;
	return position;
}
Vector3f haloRockCenterPosition(B)(ref MovingObject!B obj,ObjectState!B state){
	auto hitbox=moveBox(obj.sacObject.hitbox(obj.rotation,AnimationState.stance1,0),obj.position);
	Vector2f[2] b2d=[Vector2f(hitbox[0].x,hitbox[0].y),Vector2f(hitbox[1].x,hitbox[1].y)];
	auto cpos=boxCenter(b2d);
	return Vector3f(cpos.x,cpos.y,hitbox[1].z+HaloRock!B.centerHeight);
}

HaloRock!B makeHaloRock(B)(int wizard,int side,SacSpell!B spell,ObjectState!B state,bool isAbility){
	auto position=state.movingObjectById!(haloRockSpawnPosition,()=>Vector3f.init)(wizard,state,isAbility);
	auto rotationSpeed=2*pi!float*state.uniform(0.2f,0.8f)/updateFPS;
	auto velocity=Vector3f(0.0f,0.0f,0.0f);
	auto rotationAxis=state.uniformDirection();
	auto rotationUpdate=rotationQuaternion(rotationAxis,rotationSpeed);
	return HaloRock!B(wizard,side,position,velocity,OrderTarget.init,spell,rotationUpdate,Quaternionf.identity());
}

void animateEmergingHaloRock(B)(ref HaloRock!B haloRock,ObjectState!B state){
	screenShake(haloRock.position,updateFPS/2,0.5f,25.0f,state);
	enum numParticles=20;
	auto sacParticle=SacParticle!B.get(ParticleType.rock);
	foreach(i;0..numParticles){
		auto direction=state.uniformDirection();
		auto velocity=state.uniform(3.0f,6.0f)*haloRockSize/2.0f*direction;
		velocity.z*=2.5f;
		auto scale=state.uniform(0.25f,0.75f);
		auto lifetime=159;
		auto frame=0;
		state.addParticle(Particle!B(sacParticle,haloRock.position,velocity,scale,lifetime,frame));
	}
	enum numParticles4=8;
	auto sacParticle4=SacParticle!B.get(ParticleType.dust);
	foreach(i;0..numParticles4){
		auto direction=state.uniformDirection();
		auto position=haloRock.position+0.75f*haloRockSize/2.0f*direction;
		auto velocity=0.2f*direction;
		auto scale=3.0f*haloRockSize/2.0f;
		auto frame=0;
		auto lifetime=31;
		state.addParticle(Particle!B(sacParticle4,position,velocity,scale,lifetime,frame));
	}
	enum numParticles5=24;
	auto sacParticle5=SacParticle!B.get(ParticleType.dirt);
	auto sizeScale=2.0f;
	foreach(i;0..numParticles5){
		auto direction=state.uniformDirection();
		auto pposition=haloRock.position+sizeScale*0.25f*direction-sizeScale*Vector3f(0.0f,0.0f,state.uniform(0.0f,1.0f));
		auto velocity=sizeScale*Vector3f(0.0f,0.0f,1.0f);
		auto frame=state.uniform(2)?0:state.uniform(24);
		auto lifetime=63-frame;
		auto scale=sizeScale*state.uniform(0.5f,1.0f);
		state.addParticle(Particle!B(sacParticle5,pposition,velocity,sizeScale,lifetime,frame));
	}
	// TODO: scar
}

void spawnHaloRock(B)(ref HaloOfEarth!B haloOfEarth,ObjectState!B state){
	with(haloOfEarth){
		rocks[numSpawned++]=makeHaloRock(wizard,side,spell,state,isAbility);
		animateEmergingHaloRock(rocks[numSpawned-1],state);
	}
}
void animateHaloRock(B)(ref HaloRock!B haloRock,Vector3f oldPosition,ObjectState!B state){
	with(haloRock){
		rotation=rotationUpdate*rotation;
		enum numParticles=2;
		auto sacParticle=SacParticle!B.get(ParticleType.dust);
		auto velocity=Vector3f(0.0f,0.0f,0.0f);
		auto lifetime=31;
		auto scale=1.5f*haloRockSize/2.0f;
		auto frame=0;
		foreach(i;0..numParticles){
			auto position=oldPosition*((cast(float)numParticles-1-i)/numParticles)+position*(cast(float)(i+1)/numParticles);
			position+=0.3f*haloRockSize/2.0f*state.uniformDirection();
			state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
		}
	}
}

bool updateHaloRock(B)(ref HaloRock!B haloRock,Vector3f centerPosition,ObjectState!B state,bool isCasting,bool isAbility){
	with(haloRock){
		if(!target.id){
			if(isNaN(lastPosition[0].x)){
				nextPosition=[position-centerPosition,Vector3f(0.0f,0.0f,0.0f)];
				progress=1.0f;
			}
			if(progress>=1.0f){
				progress-=1.0f;
				lastPosition=nextPosition;
				nextPosition[0]=state.uniformDisk(Vector3f(0.0f,0.0f,0.0f),radius);
				//nextPosition[1]=state.uniformDisk(Vector3f(0.0f,0.0f,0.0f),speedRadius);
				nextPosition[1]=state.uniformDirection()*speedRadius;
			}
			progress+=interpolationSpeed/updateFPS;
			position=cintp2([lastPosition,nextPosition],progress)[0]+centerPosition;
			rotation=rotationUpdate*rotation;
		}else{
			auto oldPosition=position;
			auto targetCenter=target.center(state);
			target.position=targetCenter;
			auto distance=targetCenter-position;
			auto acceleration=distance.normalized*spell.acceleration;
			velocity+=acceleration;
			Vector3f capVelocity(Vector3f velocity){
				if(velocity.length>spell.speed) velocity=velocity.normalized*spell.speed; // TODO: why?
				if(velocity.length>updateFPS*distance.length) velocity=velocity.normalized*distance.length*updateFPS;
				return velocity;
			}
			velocity=capVelocity(velocity);
			auto newPosition=position+velocity/updateFPS;
			position=newPosition;
			if(distance.length<0.05f){
				haloRock.haloRockExplosion(haloRock.target.id,state,isAbility);
				return false;
			}
			haloRock.animateHaloRock(oldPosition,state);
		}
		if(!isCasting){
			auto target=haloRockCollisionTarget(side,position,state);
			if(state.isValidTarget(target)){
				haloRock.haloRockExplosion(target,state,isAbility);
				return false;
			}
			if(!isAbility||frame>=updateFPS/interpolationSpeed){
				if(state.isOnGround(position)){
					if(position.z<state.getGroundHeight(position)){
						haloRock.haloRockExplosion(0,state,isAbility);
						return false;
					}
				}
			}
			if(++frame>spell.duration*updateFPS){
				haloRock.haloRockExplosion(0,state,isAbility);
				return false;
			}
		}
		return true;
	}
}
void despawnHaloOfEarth(B)(ref HaloOfEarth!B haloOfEarth,ObjectState!B state){
	with(haloOfEarth){
		for(int i=numDespawned;i<numSpawned;){
			if(!rocks[i].target.id){
				rocks[i].haloRockExplosion(0,state,isAbility);
				swap(rocks[i],rocks[numDespawned++]);
				i=max(i,numDespawned);
			}else i++;
		}
	}
}
enum haloOfEarthGain=2.0f;
bool updateHaloOfEarth(B)(ref HaloOfEarth!B haloOfEarth,ObjectState!B state){
	with(haloOfEarth){
		auto center=state.movingObjectById!(haloRockCenterPosition,()=>Vector3f.init)(wizard,state);
		if(!isNaN(center.x)) while(numSpawned<numRocks) haloOfEarth.spawnHaloRock(state);
		else haloOfEarth.despawnHaloOfEarth(state);
		for(int i=numDespawned;i<numSpawned;){
			if(!rocks[i].updateHaloRock(center,state,false,isAbility)){
				swap(rocks[i],rocks[numDespawned++]);
				i=max(i,numDespawned);
			}else{
				if(!rocks[i].target.id){
					static bool callback(int target,HaloRock!B[] rocks,int i,ObjectState!B state,bool isAbility){
						if(rocks.any!((ref rock)=>rock.target.id==target)) return false;
						return state.movingObjectById!((ref obj,rocks,i,state,isAbility){
							if(state.sides.getStance(rocks[i].side,obj.side)==Stance.ally) return false;
							if(!obj.isValidAttackTarget(state)) return false;
							auto position=obj.center;
							if(!state.hasHitboxLineOfSightTo(scaleBox(haloRockHitbox,1.25f),rocks[i].position,position,0,target)) return false;
							//if(!state.hasLineOfSightTo(rocks[i].position,position,0,target)) return false;
							if(isAbility) playSpellSoundTypeAt(SoundType.fireball,position,state,haloOfEarthGain);
							else playSoundAt("olah",rocks[i].position,state,haloOfEarthGain);
							rocks[i].target=OrderTarget(TargetType.creature,obj.id,position);
							return false;
						},()=>false)(target,rocks,i,state,isAbility);
					}
					dealSplashSpellDamageAt!callback(0,spell,spell.effectRange,wizard,side,rocks[i].position,DamageMod.none,state,rocks[numDespawned..numSpawned],i-numDespawned,state,isAbility);
				}
				i++;
			}
		}
		return !(numSpawned&&numDespawned==numSpawned);
	}
}


void animateRainOfFrogsCasting(B)(ref MovingObject!B wizard,ObjectState!B state){
	auto castParticle=SacParticle!B.get(ParticleType.rainOfFrogsCasting);
	static assert(updateFPS==60);
	auto hitbox=wizard.relativeHitbox;
	auto scale=1.0f;
	enum numParticles=6;
	foreach(i;0..numParticles){
		auto position=1.1f*state.uniform(cast(Vector2f[2])[hitbox[0].xy,hitbox[1].xy]);
		auto distance=(state.uniform(3)?state.uniform(0.3f,0.6f):state.uniform(1.5f,2.5f))*(hitbox[1].z-hitbox[0].z);
		auto fullLifetime=2.0f*castParticle.numFrames/float(updateFPS);
		auto lifetime=cast(int)(castParticle.numFrames*state.uniform(0.0f,2.0f));
		// TODO: particles should accelerate upwards
		state.addParticle(Particle!B(castParticle,wizard.position+rotate(wizard.rotation,Vector3f(position.x,position.y,state.uniform(0.0f,0.5f*distance))),Vector3f(0.0f,0.0f,distance/fullLifetime),scale,lifetime,0));
	}

}

bool updateRainOfFrogsCasting(B)(ref RainOfFrogsCasting!B rainOfFrogsCast,ObjectState!B state){
	with(rainOfFrogsCast){
		++rainOfFrogs.cloudFrame;
		if(!interrupted) final switch(manaDrain.update(state)){
			case CastingStatus.underway:
				if(!state.movingObjectById!((ref obj,state){
					obj.animateRainOfFrogsCasting(state);
					return true;
				},()=>false)(manaDrain.wizard,state))
					goto case CastingStatus.interrupted;
				break;
			case CastingStatus.interrupted:
				interrupted=true;
				break;
			case CastingStatus.finished:
				.rainOfFrogs(rainOfFrogs,state);
				return false;
		}
		if(interrupted){
			rainOfFrogs.cloudScale=max(0.0f,rainOfFrogs.cloudScale-rainOfFrogs.cloudShrinkSpeed/updateFPS);
			return rainOfFrogs.cloudScale!=0.0f;
		}else{
			rainOfFrogs.cloudScale=min(1.0f,rainOfFrogs.cloudScale+rainOfFrogs.cloudGrowSpeed/updateFPS);
			return true;
		}
	}
}
bool updateRainOfFrogs(B)(ref RainOfFrogs!B rainOfFrogs,ObjectState!B state){
	with(rainOfFrogs){
		++frame;
		++cloudFrame;
		if(frame<=spell.duration*updateFPS){
			auto gposition=position;
			gposition.z=state.getHeight(gposition);
			foreach(_;0..frogRate/updateFPS+(state.uniform!"[)"(0,updateFPS)<frogRate%updateFPS)){
				auto offset=state.uniformDisk!(float,2)(Vector2f(0.0f,0.0f),spell.effectRange);
				auto fposition=position+Vector3f(offset.x,offset.y,0.0f);
				auto fvelocity=Vector3f(0.0f,0.0f,-cloudHeight/fallDuration);
				// TODO: the following might be unnecessarily inefficient
				if(auto target=state.proximity.creatureInRangeAndClosestTo(gposition,spell.effectRange,fposition)){
					auto jumped=target?centerTarget(target,state):OrderTarget.init;
					auto jdistsqr=(fposition.xy-jumped.position.xy).lengthsqr;
					if(jdistsqr<shortJumpRange^^2||jdistsqr<jumpRange^^2&&state.uniform(3)!=0){
						fposition=jumped.position;
						fposition.z=position.z;
					}
				}
				state.addEffect(RainFrog!B(wizard,side,fposition,fvelocity,spell));
			}
			return true;
		}else{
			cloudScale=max(0.0f,cloudScale-cloudShrinkSpeed/updateFPS);
			return cloudScale!=0.0f;
		}
	}
}

enum rainFrogSize=0.5f;
static immutable Vector3f[2] rainFrogHitbox=[-0.5f*rainFrogSize*Vector3f(1.0f,1.0f,1.0f),0.5f*rainFrogSize*Vector3f(1.0f,1.0f,1.0f)];
int rainFrogCollisionTarget(B)(Vector3f position,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state){
		return entry.isProjectileObstacle&&state.movingObjectById!((ref obj)=>obj.creatureState.mode.canBeInfectedByMites,()=>false)(entry.id);
	}
	return collisionTarget!(rainFrogHitbox,filter)(-1,position,state);
}
void rainFrogExplosion(B)(ref RainFrog!B rainFrog,ObjectState!B state){
	with(rainFrog){
		if(state.isValidTarget(target)) dealSpellDamage(target,spell,wizard,side,velocity,DamageMod.splash,state);
		else target=0;
		dealSplashSpellDamageAt(target,spell,spell.damageRange,wizard,side,position,DamageMod.none,state);
		auto pposition=position;
		if(target){
			auto targetPositionTargetRotation=state.movingObjectById!((ref obj)=>tuple(obj.position,obj.rotation),()=>Tuple!(Vector3f,Quaternionf).init)(target);
			auto targetPosition=targetPositionTargetRotation[0], targetRotation=targetPositionTargetRotation[1];
			pposition=targetPosition+rotate(targetRotation,position);
		}
		enum numParticles3=200;
		auto sacParticle3=SacParticle!B.get(ParticleType.frogExplosion);
		foreach(i;0..numParticles3){
			auto direction=(state.uniformDirection()+Vector3f(0.0f,0.0f,0.5f)).normalized;
			auto pvelocity=velocity+state.uniform(2.5f,7.5f)*direction;
			auto scale=state.uniform(0.75f,1.5f);
			auto lifetime=31;
			auto frame=0;
			state.addParticle(Particle!B(sacParticle3,pposition,pvelocity,scale,lifetime,frame));
		}
	}
}
bool updateRainFrog(B)(ref RainFrog!B rainFrog,ObjectState!B state){
	with(rainFrog){
		++frame;
		final switch(status){
			case FrogStatus.falling: break;
			case FrogStatus.jumping,FrogStatus.sitting: if(animationFrame<maxAnimationFrame) animationFrame++; break;
			case FrogStatus.infecting: animationFrame=maxAnimationFrame; break;
		}
		bool explode(){
			rainFrogExplosion(rainFrog,state);
			if(target) state.movingObjectById!((ref obj){ obj.creatureStats.effects.numRainFrogs-=1; },(){})(target);
			return false;
		}
		if(target){
			auto keep=++infectionTime<=infectTime;
			if(!keep||state.movingObjectById!((ref obj)=>!obj.creatureState.mode.canBeInfectedByMites,()=>true)(target)){
				keep=false;
			}
			if(!keep) return explode();
			return true;
		}else{
			if(numJumps==7&&animationFrame==10*updateAnimFactor||numJumps>=8) return explode();
			position+=velocity/updateFPS;
			velocity.z-=spell.fallingAcceleration/updateFPS;
			if(state.isOnGround(position)){
				auto height=state.getGroundHeight(position);
				if(status.among(FrogStatus.falling,FrogStatus.jumping)){
					if(height>position.z){
						status=FrogStatus.sitting;
						velocity=Vector3f(0.0f,0.0f,0.0f);
					}
				}
				if(status==FrogStatus.sitting){
					position.z=height;
					if(++sitTimer>sitTime){
						sitTimer=0;
						status=FrogStatus.jumping;
						animationFrame=0;
						numJumps+=1;
						if(!state.uniform(5)) playSpellSoundTypeAt(SoundType.frog,position,state,1.0f);
						if(numJumps>=8){
							velocity=Vector3f(0.0f,0.0f,0.0f);
						}else{
							if(auto closeCreature=state.proximity.closestCreatureInRange(position,spell.effectRange,state,10.0f)){
								auto creaturePosition=state.movingObjectById!((ref obj)=>obj.center,()=>Vector3f.init)(closeCreature);
								if(!isNaN(creaturePosition.x)){
									auto direction=creaturePosition-position;
									velocity=4.5f*direction.normalized+0.5f*state.uniformDirection();
									velocity.z+=0.5f*spell.fallingAcceleration*direction.length/velocity.length;
									velocity.z=min(velocity.z,10.0f);
								}
							}else{
								velocity=5.0f*state.uniformDirection();
								velocity.z=10.0f;
							}
						}
					}
				}
			}
			if(auto collisionTarget=rainFrogCollisionTarget(position,state)){
				auto targetPositionTargetRotation=state.movingObjectById!((ref obj,velocity,state){
					obj.creatureStats.effects.numRainFrogs+=1;
					obj.damageAnimation(velocity,state);
					return tuple(obj.position,obj.rotation);
				},()=>Tuple!(Vector3f,Quaternionf).init)(collisionTarget,velocity,state);
				auto targetPosition=targetPositionTargetRotation[0], targetRotation=targetPositionTargetRotation[1];
				if(!isNaN(targetPosition.x)){
					position=rotate(targetRotation.conj(),position-targetPosition);
					target=collisionTarget;
					status=FrogStatus.infecting;
				}
			}
			return true;
		}
	}
}

enum demonicRiftGain=2.0f;
void animateDemonicRiftCasting(B)(ref MovingObject!B wizard,ObjectState!B state){
	auto castParticle=SacParticle!B.get(ParticleType.castCharnel2);
	wizard.animateCasting(castParticle,state);
}
bool updateDemonicRiftCasting(B)(ref DemonicRiftCasting!B demonicRiftCasting,ObjectState!B state){
	with(demonicRiftCasting){
		demonicRift.updateDemonicRift(state);
		final switch(manaDrain.update(state)){
			case CastingStatus.underway:
				state.movingObjectById!(animateDemonicRiftCasting,(){})(manaDrain.wizard,state);
				return true;
			case CastingStatus.interrupted:
				demonicRift.status=DemonicRiftStatus.shrinking;
				.demonicRift(demonicRift,state);
				return false;
			case CastingStatus.finished:
				demonicRift.status=DemonicRiftStatus.active;
				.demonicRift(demonicRift,state);
				return false;
		}
	}
}

OrderTarget demonicRiftTarget(B)(ref DemonicRift!B demonicRift,ObjectState!B state,bool targetCreature=true){
	auto spell=demonicRift.spell;
	auto offset=state.uniformDisk(Vector2f(0.0f,0.0f),spell.effectRange);
	auto position=demonicRift.target.position+Vector3f(offset.x,offset.y,0.0f);
	position.z=state.getHeight(position);
	static bool filter(ref CenterProximityEntry entry,ObjectState!B state,DemonicRift!B* demonicRift){
		if(state.movingObjectById!((ref obj,state)=>obj.health(state)==0.0f,()=>true)(entry.id,state)) return false;
		return !demonicRift.hasTarget(entry.id);
	}
	// TODO: look for target in original bounds?
	int newTarget=state.proximity.closestNonAllyInRange!filter(demonicRift.side,position,spell.effectRange,EnemyType.creature,state,float.infinity,state,&demonicRift);
	if(newTarget) return OrderTarget(TargetType.creature,newTarget,state.movingObjectById!(center,()=>position)(newTarget));
	else return OrderTarget(TargetType.terrain,0,position);
}

DemonicRiftSpirit!B makeDemonicRiftSpirit(B)(ref DemonicRift!B demonicRift,int wizard,int side,ObjectState!B state){
	auto target=demonicRiftTarget(demonicRift,state);
	auto offset=0.6f*demonicRift.radius*(target.position.xy-demonicRift.position.xy).normalized;
	if(isNaN(offset.x)||isNaN(offset.y)) offset=Vector2f(0.0f,0.0f);
	auto position=demonicRift.position+Vector3f(offset.x,offset.y,0.0f);
	position.z=state.getHeight(position);
	auto spell=demonicRift.spell;
	auto velocity=spell.speed*Vector3f(offset.x,offset.y,5.0f).normalized;
	auto result=DemonicRiftSpirit!B(wizard,side,position,velocity,spell,target);
	result.locations[]=result.position;
	return result;
}

bool spawnDemonicRiftSpirit(B)(ref DemonicRift!B demonicRift,ObjectState!B state){
	with(demonicRift){
		spirits[numSpawned++]=makeDemonicRiftSpirit(demonicRift,wizard,side,state);
		if(numSpawned==1||state.uniform(3)==0) playSoundAt("stfr",spirits[numSpawned-1].position,state,demonicRiftGain); // TODO: move with spirit?
		return spirits[numSpawned-1].target.type!=TargetType.terrain;
	}
}
enum riftFlyingHeight=0.3f;
bool updateDemonicRiftSpirit(B)(ref DemonicRiftSpirit!B spirit,ref DemonicRift!B demonicRift,ObjectState!B state){
	with(spirit){
		auto targetCenter=target.center(state);
		target.position=targetCenter;
		auto predictedCenter=predictor.predictCenter(position,spell.speed,target,state);
		if(status==DemonicRiftSpiritStatus.rising){
			if(risingTimer++<risingFrames){
				auto θ=2.0f*pi!float*numRotations*risingTimer/risingFrames;
				predictedCenter+=Vector3f(cos(θ),sin(θ),risingHeight*float(risingTimer)/risingFrames);
			}else{
				status=DemonicRiftSpiritStatus.movingAway;
				auto offset=state.uniformDisk(Vector2f(0.0f,0.0f),spell.effectRange);
				target.type=TargetType.terrain;
				target.position=position+Vector3f(offset.x,offset.y,0.0f);
				target.position.z=state.getHeight(target.position)+movingAwayHeight;
			}
		}
		if(frame++<targetingCooldown||status==DemonicRiftSpiritStatus.vanishing) position+=velocity/updateFPS;
		else if(spirit.accelerateTowards(targetCenter,predictedCenter,status==DemonicRiftSpiritStatus.rising?0.0f:riftFlyingHeight,state)||(target.position-position).lengthsqr<1.0f^^2){
			if(status!=DemonicRiftSpiritStatus.rising) playSoundAt("htfr",position,state,demonicRiftGain); // TODO: move with spirit?
			if(status==DemonicRiftSpiritStatus.targeting){
				status=DemonicRiftSpiritStatus.rising;
				if(target.id&&state.isValidTarget(target.id)) dealSpellDamage(target.id,spell,wizard,side,velocity,DamageMod.none,state);
				else risingTimer=risingFrames;
			}else if(status==DemonicRiftSpiritStatus.movingAway){
				status=DemonicRiftSpiritStatus.movingBack;
				target.position=demonicRift.position;
			}else if(status==DemonicRiftSpiritStatus.movingBack){
				status=DemonicRiftSpiritStatus.vanishing;
				velocity=spell.speed*Vector3f(0.0f,0.0f,-1.0f);
			}
		}
		foreach_reverse(i;1..numSpiritFrames) locations[i]=locations[i-1];
		locations[0]=position;
		if(status==DemonicRiftSpiritStatus.vanishing){
			scale-=vanishSpeed/updateFPS;
			return scale>=0.0f;
		}
		return true;
	}
}

bool updateDemonicRift(B)(ref DemonicRift!B demonicRift,ObjectState!B state){
	with(demonicRift){
		++frame;
		auto numEffects=effectRate/updateFPS+(state.uniform!"[)"(0,updateFPS)<effectRate%updateFPS);
		if(numEffects!=0) lastEffectTime=0;
		else ++lastEffectTime;
		foreach(_;0..numEffects) state.addEffect(DemonicRiftEffect!B(position));
		if(status==DemonicRiftStatus.emerging){
			heightScale=min(1.0f,heightScale+emergenceSpeed/updateFPS);
		}else if(status==DemonicRiftStatus.active){
			if(numSpawned<maxNumSpirits&&--spiritTimer<=0){
				if(spawnDemonicRiftSpirit(demonicRift,state)) spiritTimer=spiritCooldown;
				else spiritTimer=unsuccessfulSpiritCooldown;
			}
			for(int i=numDespawned;i<numSpawned;){
				if(!spirits[i].updateDemonicRiftSpirit(demonicRift,state)){
					swap(spirits[i],spirits[numDespawned++]);
					i=max(i,numDespawned);
				}else i++;
			}
			if(numSpawned&&numDespawned==numSpawned)
				status=DemonicRiftStatus.shrinking;
		}else if(status==DemonicRiftStatus.shrinking){
			heightScale-=vanishSpeed/updateFPS;
			if(heightScale<=0.0f) return false;
		}
		return true;
	}
}

bool updateDemonicRiftEffect(B)(ref DemonicRiftEffect!B demonicRiftEffect,ObjectState!B state){
	with(demonicRiftEffect){
		frame+=1;
		scale-=shrinkSpeed/updateFPS;
		position.z+=upwardsVelocity/updateFPS;
		if(scale<=0) return false;
		return true;
	}
}


enum brainiacProjectileHitGain=4.0f;
enum brainiacProjectileSize=0.45f; // TODO: ok?
enum brainiacProjectileSlidingDistance=1.5f;
static immutable Vector3f[2] brainiacProjectileHitbox=[-0.5f*brainiacProjectileSize*Vector3f(1.0f,1.0f,1.0f),0.5f*brainiacProjectileSize*Vector3f(1.0f,1.0f,1.0f)];
int brainiacProjectileCollisionTarget(B)(int side,int intendedTarget,Vector3f position,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state,int side,int intendedTarget){
		return entry.isProjectileObstacle&&(entry.id==intendedTarget||state.objectById!(.side)(entry.id,state)!=side);
	}
	return collisionTarget!(brainiacProjectileHitbox,filter)(side,position,state,side,intendedTarget);
}
bool updateBrainiacProjectile(B)(ref BrainiacProjectile!B brainiacProjectile,ObjectState!B state){
	with(brainiacProjectile){
		auto oldPosition=position;
		position+=rangedAttack.speed/updateFPS*direction;
		remainingDistance-=rangedAttack.speed/updateFPS;
		static assert(updateFPS==60);
		auto effectPosition=position, effectDirection=direction;
		if(state.isOnGround(effectPosition)){
			auto groundHeight=state.getGroundHeight(effectPosition);
			if(effectPosition.z<groundHeight+brainiacProjectileSize){
				effectPosition.z=groundHeight+brainiacProjectileSize;
				effectDirection=Vector3f(effectDirection.x,effectDirection.y,0.0f).normalized;
				effectDirection=Vector3f(effectDirection.x,effectDirection.y,state.getGroundHeightDerivative(effectPosition,effectDirection)).normalized;
			}
		}
		state.addEffect(BrainiacEffect(effectPosition,effectDirection));
		OrderTarget target;
		if(auto targetId=brainiacProjectileCollisionTarget(side,intendedTarget,position,state)){
			target.id=targetId;
			target.type=state.targetTypeFromId(targetId);
		}else{
			target=state.lineOfSightWithoutSide(oldPosition,position,side,intendedTarget);
		}
		bool terminate(){
			playSoundAt("hnrb",position,state,brainiacProjectileHitGain);
			return false;
		}
		if(remainingDistance<=0.0f) return terminate();
		switch(target.type){
			case TargetType.terrain:
				remainingDistance=min(remainingDistance,brainiacProjectileSlidingDistance);
				if(state.isOnGround(position)){
					position.z=max(position.z,state.getGroundHeight(position)+brainiacProjectileSize);
					direction=Vector3f(direction.x,direction.y,0.0f).normalized;
					direction=Vector3f(direction.x,direction.y,state.getGroundHeightDerivative(position,direction)).normalized;
				}
				break;
			case TargetType.creature:
				state.movingObjectById!((ref obj,state){ obj.stunWithCooldown(stunCooldownFrames,state); },(){})(target.id,state);
				goto case;
			case TargetType.building:
				dealRangedDamage(target.id,rangedAttack,attacker,side,direction,DamageMod.none,state);
				return terminate();
			default: break;
		}
		return true;
	}
}
bool updateBrainiacEffect(B)(ref BrainiacEffect effect,ObjectState!B state){
	with(effect){
		static assert(updateFPS==60);
		return ++frame<32; // TODO: fix timing on this
	}
}

enum shrikeProjectileHitGain=4.0f;
enum shrikeProjectileSize=0.9f; // TODO: ok?
enum shrikeProjectileSlidingDistance=0.0f;
static immutable Vector3f[2] shrikeProjectileHitbox=[-0.5f*shrikeProjectileSize*Vector3f(1.0f,1.0f,1.0f),0.5f*shrikeProjectileSize*Vector3f(1.0f,1.0f,1.0f)];
int shrikeProjectileCollisionTarget(B)(int side,int intendedTarget,Vector3f position,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state,int side,int intendedTarget){
		return entry.isProjectileObstacle&&(entry.id==intendedTarget||state.objectById!(.side)(entry.id,state)!=side);
	}
	return collisionTarget!(shrikeProjectileHitbox,filter)(side,position,state,side,intendedTarget);
}
bool updateShrikeProjectile(B)(ref ShrikeProjectile!B shrikeProjectile,ObjectState!B state){
	with(shrikeProjectile){
		auto oldPosition=position;
		position+=rangedAttack.speed/updateFPS*direction;
		remainingDistance-=rangedAttack.speed/updateFPS;
		static assert(updateFPS==60);
		auto effectPosition=position, effectDirection=direction;
		float effectScale=state.uniform(1.0f,1.5f);
		state.addEffect(ShrikeEffect(effectPosition,effectDirection,effectScale));
		OrderTarget target;
		if(auto targetId=shrikeProjectileCollisionTarget(side,intendedTarget,position,state)){
			target.id=targetId;
			target.type=state.targetTypeFromId(targetId);
		}else{
			target=state.lineOfSightWithoutSide(oldPosition,position,side,intendedTarget);
		}
		bool terminate(){
			playSoundAt("hkhs",position,state,shrikeProjectileHitGain);
			return false;
		}
		if(remainingDistance<=0) return terminate();
		switch(target.type){
			case TargetType.terrain:
				remainingDistance=min(remainingDistance,shrikeProjectileSlidingDistance);
				break;
			case TargetType.creature:
				state.movingObjectById!((ref obj,state){ obj.stunWithCooldown(stunCooldownFrames,state); },(){})(target.id,state);
				goto case;
			case TargetType.building:
				dealRangedDamage(target.id,rangedAttack,attacker,side,direction,DamageMod.none,state);
				return terminate();
			default: break;
		}
		return true;
	}
}
bool updateShrikeEffect(B)(ref ShrikeEffect effect,ObjectState!B state){
	with(effect){
		static assert(updateFPS==60);
		return ++frame<128; // TODO: fix timing on this
	}
}

bool updateLocustProjectile(B)(ref LocustProjectile!B locustProjectile,ObjectState!B state){
	with(locustProjectile){
		static assert(updateFPS==60);
		auto distance=target-position;
		auto velocity=rangedAttack.speed/updateFPS*distance.normalized;
		auto sacParticle=SacParticle!B.get(blood?ParticleType.locustBlood:ParticleType.locustDebris);
		auto pvelocity=Vector3f(0,0,0),scale=1.0f,lifetime=31,frame=0;
		enum nSteps=5;
		foreach(i;0..nSteps){
			if(!state.uniform(2)) continue;
			state.addParticle(Particle!B(sacParticle,position+i*velocity/nSteps,pvelocity,scale,lifetime,frame));
		}
		position+=velocity;
		return distance.lengthsqr>=(rangedAttack.speed/updateFPS)^^2;
	}
}

enum finalSpitfireProjectileSize=7.5f;
bool updateSpitfireProjectile(B)(ref SpitfireProjectile!B spitfireProjectile,ObjectState!B state){
	with(spitfireProjectile){
		auto oldPosition=position;
		position+=rangedAttack.speed/updateFPS*direction;
		remainingDistance-=rangedAttack.speed/updateFPS;
		static bool callback(T)(int id,T* targets,int attacker,int side,int intendedTarget,SacSpell!B rangedAttack,Vector3f attackDirection,ObjectState!B state){
			auto recordedId=id;
			if(state.isValidTarget(id,TargetType.building)){
				if(auto cand=state.staticObjectById!((ref obj)=>obj.buildingId,()=>0)(id))
					recordedId=cand;
			}
			if((*targets)[].canFind(recordedId)) return false;
			bool validTarget=!!state.targetTypeFromId(id).among(TargetType.creature,TargetType.building);
			*targets~=recordedId;
			if(validTarget&&id==intendedTarget){
				dealRangedDamage(intendedTarget,rangedAttack,attacker,side,attackDirection,DamageMod.ignite,state); // TODO: ok?
				setAblaze(id,updateFPS/2,true,0.0f,attacker,side,DamageMod.none,state);
				return false;
			}
			if(validTarget&&state.objectById!(.side)(id,state)==side)
				return false;
			if(validTarget) setAblaze(id,updateFPS/2,true,0.0f,attacker,side,DamageMod.none,state);
			return true;
		}
		auto radius=finalSpitfireProjectileSize*frame/(updateFPS*rangedAttack.range/rangedAttack.speed);
		dealDamageAt!callback(0,rangedAttack.amount,radius,attacker,side,position,DamageMod.ignite|DamageMod.ranged,state,&damagedTargets,attacker,side,intendedTarget,rangedAttack,direction,state);
		static assert(updateFPS==60);
		if(frame<12){
			enum numEffects=3;
			foreach(i;0..numEffects){
				auto effectPosition=position-frame*rangedAttack.speed/updateFPS*direction, effectDirection=direction+0.05f*state.uniformDirection(), effectScale=state.uniform(0.0f,1.0f);
				auto speed=rangedAttack.speed*state.uniform(0.9f,1.1f);
				auto lifetime=cast(int)(updateFPS*rangedAttack.range/rangedAttack.speed);
				state.addEffect(SpitfireEffect(effectPosition,effectDirection*speed,lifetime,effectScale));
			}
		}
		++frame;
		return remainingDistance>0.0f;
	}
}
bool updateSpitfireEffect(B)(ref SpitfireEffect effect,ObjectState!B state){
	with(effect){
		static assert(updateFPS==60);
		position+=velocity/updateFPS;
		enum numFrames=64;
		scale+=finalSpitfireProjectileSize/numFrames;
		return ++frame<min(lifetime,numFrames);
	}
}

enum finalGargoyleProjectileSize=6.0f;
bool updateGargoyleProjectile(B)(ref GargoyleProjectile!B gargoyleProjectile,ObjectState!B state){
	with(gargoyleProjectile){
		auto oldPosition=position;
		position+=rangedAttack.speed/updateFPS*direction;
		remainingDistance-=rangedAttack.speed/updateFPS;
		static bool callback(T)(int id,T* targets,int attacker,int side,int intendedTarget,SacSpell!B rangedAttack,Vector3f attackDirection,ObjectState!B state){
			auto recordedId=id;
			if(state.isValidTarget(id,TargetType.building)){
				if(auto cand=state.staticObjectById!((ref obj)=>obj.buildingId,()=>0)(id))
					recordedId=cand;
			}
			if((*targets)[].canFind(recordedId)) return false;
			bool validTarget=!!state.targetTypeFromId(id).among(TargetType.creature,TargetType.building);
			*targets~=recordedId;
			if(validTarget&&id==intendedTarget){
				dealRangedDamage(intendedTarget,rangedAttack,attacker,side,attackDirection,DamageMod.none,state); // TODO: ok?
				return false;
			}
			if(validTarget&&state.objectById!(.side)(id,state)==side)
				return false;
			return true;
		}
		auto radius=finalGargoyleProjectileSize*frame/(updateFPS*rangedAttack.range/rangedAttack.speed);
		dealDamageAt!callback(0,rangedAttack.amount,radius,attacker,side,position,DamageMod.ranged,state,&damagedTargets,attacker,side,intendedTarget,rangedAttack,direction,state);
		static assert(updateFPS==60);
		if(frame<12){
			enum numEffects=3;
			foreach(i;0..numEffects){
				auto effectPosition=position-frame*rangedAttack.speed/updateFPS*direction, effectDirection=direction+0.08f*state.uniformDirection(), effectScale=state.uniform(0.0f,1.0f);
				auto speed=rangedAttack.speed*state.uniform(0.9f,1.1f);
				auto lifetime=cast(int)(updateFPS*rangedAttack.range/rangedAttack.speed);
				state.addEffect(GargoyleEffect(effectPosition,effectDirection*speed,lifetime,effectScale));
			}
		}
		++frame;
		return remainingDistance>0.0f;
	}
}
bool updateGargoyleEffect(B)(ref GargoyleEffect effect,ObjectState!B state){
	with(effect){
		static assert(updateFPS==60);
		position+=velocity/updateFPS;
		enum numFrames=64;
		scale=min(0.75f,scale+finalGargoyleProjectileSize/numFrames);
		return ++frame<min(lifetime,numFrames);
	}
}

void animateEarthflingProjectile(B)(ref EarthflingProjectile!B earthflingProjectile,Vector3f oldPosition,ObjectState!B state){
	with(earthflingProjectile){
		rotation=rotationUpdate*rotation;
		enum numParticles=2;
		auto sacParticle=SacParticle!B.get(ParticleType.dust);
		auto velocity=Vector3f(0.0f,0.0f,0.0f);
		auto lifetime=31;
		auto scale=0.5f;
		auto frame=0;
		foreach(i;0..numParticles){
			auto position=oldPosition*((cast(float)numParticles-1-i)/numParticles)+position*(cast(float)(i+1)/numParticles);
			position+=0.3f*state.uniformDirection();
			state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
		}
	}
}

enum earthflingProjectileSize=0.7f; // TODO: ok?
enum earthflingProjectileSlidingDistance=0.0f;
static immutable Vector3f[2] earthflingProjectileHitbox=[-0.5f*earthflingProjectileSize*Vector3f(1.0f,1.0f,1.0f),0.5f*earthflingProjectileSize*Vector3f(1.0f,1.0f,1.0f)];
int earthflingProjectileCollisionTarget(B)(int side,int intendedTarget,Vector3f position,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state,int side,int intendedTarget){
		return entry.isProjectileObstacle&&(entry.id==intendedTarget||state.objectById!(.side)(entry.id,state)!=side);
	}
	return collisionTarget!(earthflingProjectileHitbox,filter)(side,position,state,side,intendedTarget);
}

void earthflingProjectileExplosion(B)(ref EarthflingProjectile!B earthflingProjectile,int target,ObjectState!B state){
	playSoundAt("pmir",earthflingProjectile.position,state,2.0f);
	if(state.isValidTarget(target)) dealRangedDamage(target,earthflingProjectile.rangedAttack,earthflingProjectile.attacker,earthflingProjectile.side,earthflingProjectile.velocity,DamageMod.none,state);
	enum numParticles3=20;
	auto sacParticle3=SacParticle!B.get(ParticleType.rock);
	foreach(i;0..numParticles3){
		auto direction=state.uniformDirection();
		auto velocity=0.3f*state.uniform(7.5f,15.0f)*direction;
		auto scale=0.3f*state.uniform(1.0f,2.5f);
		auto lifetime=95;
		auto frame=0;
		state.addParticle(Particle!B(sacParticle3,earthflingProjectile.position,velocity,scale,lifetime,frame));
	}
	enum numParticles4=4;
	auto sacParticle4=SacParticle!B.get(ParticleType.dirt);
	foreach(i;0..numParticles4){
		auto direction=state.uniformDirection();
		auto position=earthflingProjectile.position+0.25f*direction;
		auto velocity=Vector3f(0.0f,0.0f,0.0f);
		auto scale=1.0f;
		auto frame=state.uniform(2)?0:state.uniform(24);
		auto lifetime=63-frame;
		state.addParticle(Particle!B(sacParticle4,position,velocity,scale,lifetime,frame));
	}
}

bool updateEarthflingProjectile(B)(ref EarthflingProjectile!B earthflingProjectile,ObjectState!B state){
	with(earthflingProjectile){
		auto oldPosition=position;
		position+=velocity/updateFPS;
		velocity.z-=rangedAttack.fallingAcceleration/updateFPS;
		rotation=rotationUpdate*rotation;
		earthflingProjectile.animateEarthflingProjectile(oldPosition,state);
		auto target=earthflingProjectileCollisionTarget(side,intendedTarget,position,state);
		if(state.isValidTarget(target)){
			earthflingProjectile.earthflingProjectileExplosion(target,state);
			return false;
		}
		if(state.isOnGround(position)){
			if(position.z<state.getGroundHeight(position)){
				earthflingProjectile.earthflingProjectileExplosion(0,state);
				return false;
			}
		}else if(position.z<state.getHeight(position)-rangedAttack.fallLimit)
			return false;
		return true;
	}
}

void animateFlameMinionProjectile(B)(ref FlameMinionProjectile!B flameMinionProjectile,Vector3f oldPosition,ObjectState!B state){
	with(flameMinionProjectile){
		enum numParticles=4;
		auto sacParticle=SacParticle!B.get(ParticleType.firy);
		auto velocity=Vector3f(0.0f,0.0f,0.0f);
		auto lifetime=15;
		auto scale=0.75f;
		auto frame=15;
		foreach(i;0..numParticles){
			auto position=oldPosition*((cast(float)numParticles-1-i)/numParticles)+position*(cast(float)(i+1)/numParticles);
			position+=0.1f*state.uniformDirection();
			state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
		}
	}
}

enum flameMinionProjectileSize=0.7f; // TODO: ok?
enum flameMinionProjectileSlidingDistance=0.0f;
static immutable Vector3f[2] flameMinionProjectileHitbox=[-0.5f*flameMinionProjectileSize*Vector3f(1.0f,1.0f,1.0f),0.5f*flameMinionProjectileSize*Vector3f(1.0f,1.0f,1.0f)];
int flameMinionProjectileCollisionTarget(B)(int side,int intendedTarget,Vector3f position,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state,int side,int intendedTarget){
		return entry.isProjectileObstacle&&(entry.id==intendedTarget||state.objectById!(.side)(entry.id,state)!=side);
	}
	return collisionTarget!(flameMinionProjectileHitbox,filter)(side,position,state,side,intendedTarget);
}


void flameEffect(B)(Vector3f position,ObjectState!B state,float scale=1.0f){
	enum numParticles4=30;
	auto sacParticle4=SacParticle!B.get(ParticleType.fire);
	foreach(i;0..numParticles4){
		auto direction=state.uniformDirection();
		auto pposition=position+scale*0.25f*direction;
		auto velocity=scale*Vector3f(0.0f,0.0f,1.0f); // TODO: original uses vibrating particles
		auto frame=state.uniform(2)?0:state.uniform(24);
		auto lifetime=63-frame;
		state.addParticle(Particle!B(sacParticle4,pposition,velocity,scale,lifetime,frame));
	}
}

void flameMinionProjectileExplosion(B)(ref FlameMinionProjectile!B flameMinionProjectile,int target,ObjectState!B state){
	if(state.isValidTarget(target)){
		dealRangedDamage(target,flameMinionProjectile.rangedAttack,flameMinionProjectile.attacker,flameMinionProjectile.side,flameMinionProjectile.velocity,DamageMod.ignite,state);
		with(flameMinionProjectile) setAblaze(target,updateFPS/4,true,0.0f,attacker,side,DamageMod.none,state);
	}
	flameEffect(flameMinionProjectile.position,state);
}

bool updateFlameMinionProjectile(B)(ref FlameMinionProjectile!B flameMinionProjectile,ObjectState!B state){
	with(flameMinionProjectile){
		auto oldPosition=position;
		position+=velocity/updateFPS;
		velocity.z-=rangedAttack.fallingAcceleration/updateFPS;
		flameMinionProjectile.animateFlameMinionProjectile(oldPosition,state);
		auto target=flameMinionProjectileCollisionTarget(side,intendedTarget,position,state);
		if(state.isValidTarget(target)){
			flameMinionProjectile.flameMinionProjectileExplosion(target,state);
			return false;
		}
		if(state.isOnGround(position)){
			if(position.z<state.getGroundHeight(position)){
				flameMinionProjectile.flameMinionProjectileExplosion(0,state);
				return false;
			}
		}else if(position.z<state.getHeight(position)-rangedAttack.fallLimit)
			return false;
		return true;
	}
}

Vector3f makeTargetPosition(B)(ref FallenProjectile!B fallenProjectile,float radius,ObjectState!B state){
	return fallenProjectile.position+state.uniform(0.0f,radius)*state.uniformDirection();
}

enum fallenProjectileRadius=0.5f;
enum fallenProjectileDispersingFrames=2*updateFPS;
void addBugs(B)(ref FallenProjectile!B fallenProjectile,ObjectState!B state){
	enum totalBugs=75;
	foreach(i;0..totalBugs){
		auto position=fallenProjectile.makeTargetPosition(fallenProjectileRadius,state);
		auto targetPosition=fallenProjectile.makeTargetPosition(fallenProjectileRadius,state);
		auto velocity=fallenProjectile.velocity+(targetPosition-position).normalized*0.01f*fallenProjectile.rangedAttack.speed;
		auto bug=makeBug!B(position,velocity,targetPosition);
		fallenProjectile.bugs~=bug;
	}
}
void updateBug(B)(ref FallenProjectile!B fallenProjectile,ref Bug!B bug,ObjectState!B state){
	bug.targetPosition+=fallenProjectile.velocity/updateFPS;
	auto rangedAttack=fallenProjectile.rangedAttack;
	auto bugAcceleration=1.0f*rangedAttack.acceleration;
	auto bugSpeed=1.5f*rangedAttack.speed;
	auto distance=bug.targetPosition-bug.position;
	auto acceleration=distance.normalized*min(2.0f*distance.length,1.0f)*bugAcceleration;
	acceleration.z-=fallenProjectile.rangedAttack.fallingAcceleration/updateFPS;
	bug.velocity+=acceleration;
	static import std.math;
	static immutable float zdamp=std.math.exp(std.math.log(0.01f)/updateFPS);
	bug.position+=bug.velocity/updateFPS;
	auto dist=(bug.targetPosition-bug.position).lengthsqr;
	if(dist<1e-3^^2||!state.uniform(updateFPS/2)){
		bug.velocity=fallenProjectile.velocity+0.25f*(bug.velocity-fallenProjectile.velocity);
		bug.targetPosition=fallenProjectile.makeTargetPosition(fallenProjectileRadius*2.5f/max(2.0f,dist),state);
	}
	auto radius=bug.position-fallenProjectile.position;
	auto radialComponent=dot(bug.velocity,radius);
	if(radius.lengthsqr>1.0f){
		auto radialDir=radialComponent*radius.normalized;
		auto rest=bug.velocity-radialDir;
		static import std.math;
		static immutable float damp1=std.math.exp(std.math.log(0.01f)/updateFPS);
		static immutable float damp2=std.math.exp(std.math.log(7.0f)/updateFPS);
		auto factor=radialComponent>0.0f?damp1:damp2;
		bug.velocity=rest+factor*radialDir;
	}
}
bool updateBugs(B)(ref FallenProjectile!B fallenProjectile,ObjectState!B state){
	foreach(i;0..fallenProjectile.bugs.length)
		fallenProjectile.updateBug(fallenProjectile.bugs[i],state);
	return true;
}
void disperseBug(B)(ref FallenProjectile!B fallenProjectile,ref Bug!B bug,ObjectState!B state){
	if(fallenProjectile.frame%4==0){
		bug.targetPosition=bug.position+0.2f*(0.5f*(bug.position-fallenProjectile.position).normalized+state.uniformDirection()).normalized;
		bug.targetPosition.x+=cos(bug.targetPosition.y)/updateFPS;
		bug.targetPosition.y+=cos(bug.targetPosition.x)/updateFPS;
	}
	static import std.math;
	static immutable float damp=std.math.exp(std.math.log(0.01f)/updateFPS);
	bug.position=damp*bug.targetPosition+(1.0f-damp)*bug.position;
}
void disperseBugs(B)(ref FallenProjectile!B fallenProjectile,ObjectState!B state){
	foreach(i;0..fallenProjectile.bugs.length)
		fallenProjectile.disperseBug(fallenProjectile.bugs[i],state);
}
void fallenProjectileHit(B)(ref FallenProjectile!B fallenProjectile,int target,ObjectState!B state){
	fallenProjectile.status=SwarmStatus.dispersing;
	playSoundAt("2tim",fallenProjectile.position,state,4.0f);
	playSpellSoundTypeAt(SoundType.swarm,fallenProjectile.position,state,2.0f);
	if(state.isValidTarget(target))
		dealRangedDamage(target,fallenProjectile.rangedAttack,fallenProjectile.attacker,fallenProjectile.side,fallenProjectile.velocity,DamageMod.none,state);
	enum numParticles=32;
	auto sacParticle=SacParticle!B.get(ParticleType.swarmHit);
	fallenProjectile.velocity=Vector3f(0.0f,0.0f,0.0f);
	foreach(i;0..numParticles){
		auto position=fallenProjectile.position;
		auto velocity=state.uniformDirection();
		velocity.z+=3.0f;
		auto scale=0.5f;
		int lifetime=63;
		int frame=0;
		state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
	}
}

enum fallenProjectileSize=0.5f; // TODO: ok?
static immutable Vector3f[2] fallenProjectileHitbox=[-0.5f*fallenProjectileSize*Vector3f(1.0f,1.0f,1.0f),0.5f*fallenProjectileSize*Vector3f(1.0f,1.0f,1.0f)];
int fallenProjectileCollisionTarget(B)(int side,int intendedTarget,Vector3f position,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state,int side,int intendedTarget){
		return entry.isProjectileObstacle&&(entry.id==intendedTarget||state.objectById!(.side)(entry.id,state)!=side);
	}
	return collisionTarget!(fallenProjectileHitbox,filter)(side,position,state,side,intendedTarget);
}

bool updateFallenProjectile(B)(ref FallenProjectile!B fallenProjectile,ObjectState!B state){
	with(fallenProjectile){
		final switch(status){
			case SwarmStatus.casting,SwarmStatus.flying:
				auto oldPosition=position;
				position+=velocity/updateFPS;
				velocity.z-=rangedAttack.fallingAcceleration/updateFPS;
				auto target=fallenProjectileCollisionTarget(side,intendedTarget,position,state);
				if(state.isValidTarget(target)){
					fallenProjectile.fallenProjectileHit(target,state);
				}else if(state.isOnGround(position)){
					if(position.z<state.getGroundHeight(position))
						fallenProjectile.fallenProjectileHit(0,state);
				}else if(position.z<state.getHeight(position)-rangedAttack.fallLimit)
					return false;
				return fallenProjectile.updateBugs(state);
			case SwarmStatus.dispersing:
				fallenProjectile.disperseBugs(state);
				return ++frame<fallenProjectileDispersingFrames;
		}
	}
}

bool updateSylphEffect(B)(ref SylphEffect!B sylphEffect,ObjectState!B state){
	with(sylphEffect){
		frame+=1;
		static bool check(ref MovingObject!B attacker,ObjectState!B state){
			return attacker.creatureState.mode.isShooting&&!attacker.hasShootTick(state);
		}
		return state.movingObjectById!(check,()=>false)(attacker,state);
	}
}

enum sylphProjectileSize=0.1f; // TODO: ok?
static immutable Vector3f[2] sylphProjectileHitbox=[-0.5f*sylphProjectileSize*Vector3f(1.0f,1.0f,1.0f),0.5f*sylphProjectileSize*Vector3f(1.0f,1.0f,1.0f)];
int sylphProjectileCollisionTarget(B)(int side,int intendedTarget,Vector3f position,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state,int side,int intendedTarget){
		return entry.isProjectileObstacle&&(entry.id==intendedTarget||state.objectById!(.side)(entry.id,state)!=side);
	}
	return collisionTarget!(sylphProjectileHitbox,filter)(side,position,state,side,intendedTarget);
}

void sylphProjectileHit(B)(ref SylphProjectile!B sylphProjectile,int target,ObjectState!B state){
	playSpellSoundTypeAt(SoundType.arrow,sylphProjectile.position,state,2.0f);
	if(state.isValidTarget(target))
		dealRangedDamage(target,sylphProjectile.rangedAttack,sylphProjectile.attacker,sylphProjectile.side,sylphProjectile.velocity,DamageMod.none,state);
}

bool updateSylphProjectile(B)(ref SylphProjectile!B sylphProjectile,ObjectState!B state){
	with(sylphProjectile){
		frame+=1;
		auto oldPosition=position;
		position+=velocity/updateFPS;
		velocity.z-=rangedAttack.fallingAcceleration/updateFPS;
		auto target=sylphProjectileCollisionTarget(side,intendedTarget,position,state);
		if(state.isValidTarget(target)){
			sylphProjectile.sylphProjectileHit(target,state);
			return false;
		}
		if(state.isOnGround(position)){
			if(position.z<state.getGroundHeight(position)){
				sylphProjectile.sylphProjectileHit(0,state);
				return false;
			}
		}else if(position.z<state.getHeight(position)-rangedAttack.fallLimit)
			return false;
		return true;
	}
}

bool updateRangerEffect(B)(ref RangerEffect!B rangerEffect,ObjectState!B state){
	with(rangerEffect){
		frame+=1;
		static bool check(ref MovingObject!B attacker,ObjectState!B state){
			return attacker.creatureState.mode.isShooting&&!attacker.hasShootTick(state);
		}
		return state.movingObjectById!(check,()=>false)(attacker,state);
	}
}

enum rangerProjectileSize=0.1f; // TODO: ok?
static immutable Vector3f[2] rangerProjectileHitbox=[-0.5f*rangerProjectileSize*Vector3f(1.0f,1.0f,1.0f),0.5f*rangerProjectileSize*Vector3f(1.0f,1.0f,1.0f)];
int rangerProjectileCollisionTarget(B)(int side,int intendedTarget,Vector3f position,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state,int side,int intendedTarget){
		return entry.isProjectileObstacle&&(entry.id==intendedTarget||state.objectById!(.side)(entry.id,state)!=side);
	}
	return collisionTarget!(rangerProjectileHitbox,filter)(side,position,state,side,intendedTarget);
}

void rangerProjectileHit(B)(ref RangerProjectile!B rangerProjectile,int target,ObjectState!B state){
	playSpellSoundTypeAt(SoundType.arrow,rangerProjectile.position,state,2.0f);
	if(state.isValidTarget(target))
		dealRangedDamage(target,rangerProjectile.rangedAttack,rangerProjectile.attacker,rangerProjectile.side,rangerProjectile.velocity,DamageMod.none,state);
}

bool updateRangerProjectile(B)(ref RangerProjectile!B rangerProjectile,ObjectState!B state){
	with(rangerProjectile){
		frame+=1;
		auto oldPosition=position;
		position+=velocity/updateFPS;
		velocity.z-=rangedAttack.fallingAcceleration/updateFPS;
		auto target=rangerProjectileCollisionTarget(side,intendedTarget,position,state);
		if(state.isValidTarget(target)){
			rangerProjectile.rangerProjectileHit(target,state);
			return false;
		}
		if(state.isOnGround(position)){
			if(position.z<state.getGroundHeight(position)){
				rangerProjectile.rangerProjectileHit(0,state);
				return false;
			}
		}else if(position.z<state.getHeight(position)-rangedAttack.fallLimit)
			return false;
		return true;
	}
}

enum necrylProjectileSize=0.15f; // TODO: ok?
static immutable Vector3f[2] necrylProjectileHitbox=[-0.5f*necrylProjectileSize*Vector3f(1.0f,1.0f,1.0f),0.5f*necrylProjectileSize*Vector3f(1.0f,1.0f,1.0f)];
int necrylProjectileCollisionTarget(B)(int side,int intendedTarget,Vector3f position,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state,int side,int intendedTarget){
		return entry.isProjectileObstacle&&(entry.id==intendedTarget||state.objectById!(.side)(entry.id,state)!=side);
	}
	return collisionTarget!(necrylProjectileHitbox,filter)(side,position,state,side,intendedTarget);
}

bool updateNecrylProjectile(B)(ref NecrylProjectile!B necrylProjectile,ObjectState!B state){
	with(necrylProjectile){
		auto oldPosition=position;
		auto velocity=rangedAttack.speed*direction/updateFPS;
		position+=velocity;
		remainingDistance-=rangedAttack.speed/updateFPS;
		static assert(updateFPS==60);
		auto sacParticle=SacParticle!B.get(ParticleType.poison);
		auto pvelocity=Vector3f(0,0,0),scale=0.5f,lifetime=31,frame=0;
		enum size=0.25f;
		static immutable Vector3f[2] box=[-0.5f*size*Vector3f(1.0f,1.0f,1.0f),0.5f*size*Vector3f(1.0f,1.0f,1.0f)];
		enum nSteps=2;
		foreach(i;0..nSteps)
			foreach(j;0..4)
				state.addParticle(Particle!B(sacParticle,oldPosition+float(i+1)/nSteps*velocity+state.uniform(box),pvelocity,scale,lifetime,frame));
		OrderTarget target;
		if(auto targetId=necrylProjectileCollisionTarget(side,intendedTarget,position,state)){
			target.id=targetId;
			target.type=state.targetTypeFromId(targetId);
		}else{
			target=state.lineOfSightWithoutSide(oldPosition,position,side,intendedTarget);
		}
		bool terminate(){
			//playSoundAt("?",position,state,necrylProjectileHitGain);
			return false;
		}
		if(remainingDistance<=0.0f) return terminate();
		switch(target.type){
			case TargetType.terrain: return terminate();
			case TargetType.creature:
				state.movingObjectById!(poison,()=>false)(target.id,rangedAttack,true,attacker,side,DamageMod.ranged,state);
				return terminate();
			case TargetType.building:
				dealRangedDamage(target.id,rangedAttack,attacker,side,direction,DamageMod.none,state);
				return terminate();
			default: break;
		}
		return true;
	}
}

bool updatePoison(B)(ref Poison poison,ObjectState!B state){
	if(!state.isValidTarget(poison.creature,TargetType.creature)) return false;
	if(poison.infectuous){
		state.movingObjectById!((ref obj,poison,state){
			if(!obj.creatureAI.isOnAIQueue) obj.creatureAI.isOnAIQueue=state.pushToAIQueue(obj.side,obj.id);
			if(!state.frontOfAIQueue(obj.side,obj.id)) return;
			auto hitbox=obj.hitbox;
			hitbox[0]-=2.0f, hitbox[1]+=2.0f;
			auto poisonDamage=obj.creatureStats.effects.poisonDamage;
			static void infect(ProximityEntry target,ObjectState!B state,int creature,float poisonDamage,int lifetime,int attacker,int attackerSide,DamageMod damageMod){
				if(target.id==creature) return;
				state.movingObjectById!((ref next,creature,poisonDamage,lifetime,attacker,attackerSide,damageMod,state){
					if(next.creatureStats.effects.infectionCooldown) return;
					next.poison(poisonDamage,lifetime,true,attacker,attackerSide,damageMod,state);
					next.creatureStats.effects.infectionCooldown=lifetime+3*updateFPS;
				},(){})(target.id,creature,poisonDamage,lifetime,attacker,attackerSide,damageMod,state);
			}
			collisionTargets!infect(hitbox,state,obj.id,poisonDamage,poison.lifetime-poison.frame,poison.attacker,poison.attackerSide,poison.damageMod);
		},(){})(poison.creature,&poison,state);
	}
	return state.movingObjectById!((ref obj,poison,state){
		if(poison.frame==Poison.manaBlockDelay) obj.creatureStats.effects.numManaBlocks+=1;
		bool removePoison(){
			if(poison.frame>=Poison.manaBlockDelay) obj.creatureStats.effects.numManaBlocks-=1;
			obj.creatureStats.effects.poisonDamage-=cast(int)poison.poisonDamage;
			return false;
		}
		if(!obj.creatureState.mode.canBePoisoned)
			return removePoison;
		auto hitbox=obj.relativeHitbox;
		auto dim=hitbox[1]-hitbox[0];
		auto volume=dim.x*dim.y*dim.z;
		auto scale=2.0f*max(1.0f,cbrt(volume));
		auto sacParticle=SacParticle!B.get(ParticleType.relativePoison);
		static assert(updateFPS==60);
		if(state.frame%2==0){
			enum numParticles=1;
			foreach(i;0..numParticles){
				auto position=1.1f*state.uniform(hitbox);
				auto velocity=Vector3f(0.0f,0.0f,0.0f);
				auto lifetime=min(poison.lifetime-poison.frame,cast(int)(sacParticle.numFrames*state.uniform(0.0f,1.0f)));
				state.addParticle(Particle!(B,true)(sacParticle,obj.id,false,position,velocity,scale,lifetime,0));
			}
		}
		with(*poison){
			obj.dealPoisonDamage(poisonDamage/updateFPS,attacker,attackerSide,damageMod,state);
			if(frame++>=lifetime) return removePoison();
			return true;
		}
	},()=>false)(poison.creature,&poison,state);
}

void animateScarabProjectileHit(B)(ref ScarabProjectile!B scarabProjectile,Vector3f[2] hitbox,ObjectState!B state){
	if(isNaN(hitbox[0].x)) return;
	enum numParticles=64;
	auto sacParticle=SacParticle!B.get(ParticleType.scarabHit);
	auto center=boxCenter(hitbox);
	foreach(i;0..numParticles){
		auto position=state.uniform(scaleBox(hitbox,0.9f));
		//auto velocity=1.5f*state.uniform(0.5f,2.0f)*Vector3f(position.x-center.x,position.y-center.y,2.0f);
		auto velocity=1.5f*state.uniform(0.5f,2.0f)*Vector3f(state.uniform(hitbox[0].x,hitbox[1].x)-center.x,state.uniform(hitbox[0].y,hitbox[1].y)-center.y,2.5f);
		auto scale=state.uniform(0.5f,1.0f);
		int lifetime=79;
		int frame=0;
		state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
	}
}

void scarabProjectileHit(B)(ref ScarabProjectile!B scarabProjectile,int target,ObjectState!B state){
	playSoundAt("hrcs",scarabProjectile.position,state,scarabProjectileHitGain);
	Vector3f[2] hitbox;
	if(state.isValidTarget(target,TargetType.creature)){
		hitbox=state.movingObjectById!(.hitbox,()=>typeof(hitbox).init)(target);
		heal(target,scarabProjectile.rangedAttack,state);
	}else if(state.isValidTarget(target,TargetType.building)){
		hitbox=state.staticObjectById!(.hitbox,()=>typeof(hitbox).init)(target);
	}else{
		hitbox[0]=scarabProjectile.position-0.5f;
		hitbox[1]=scarabProjectile.position+0.5f;
	}
	static bool callback(int target,int side,SacSpell!B rangedAttack,ObjectState!B state){
		if(state.movingObjectById!((ref obj)=>obj.side,()=>-1)(target)==side)
			heal(target,rangedAttack,state);
		return false;
	}
	with(scarabProjectile) dealSplashSpellDamageAt!callback(target,rangedAttack,rangedAttack.effectRange,attacker,side,position,DamageMod.none,state,side,rangedAttack,state);
	scarabProjectile.animateScarabProjectileHit(hitbox,state);
}

enum scarabProjectileHitGain=2.0f;
enum scarabProjectileSize=0.15f; // TODO: ok?
static immutable Vector3f[2] scarabProjectileHitbox=[-0.5f*scarabProjectileSize*Vector3f(1.0f,1.0f,1.0f),0.5f*scarabProjectileSize*Vector3f(1.0f,1.0f,1.0f)];
int scarabProjectileCollisionTarget(B)(int attacker,int side,int intendedTarget,Vector3f position,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state,int attacker,int side,int intendedTarget){
		return entry.isProjectileObstacle&&entry.id!=attacker&&(entry.id==intendedTarget||state.objectById!(.side)(entry.id,state)==side);
	}
	return collisionTarget!(scarabProjectileHitbox,filter)(side,position,state,attacker,side,intendedTarget);
}

bool updateScarabProjectile(B)(ref ScarabProjectile!B scarabProjectile,ObjectState!B state){
	with(scarabProjectile){
		auto oldPosition=position;
		auto velocity=rangedAttack.speed*direction/updateFPS;
		position+=velocity;
		remainingDistance-=rangedAttack.speed/updateFPS;
		static assert(updateFPS==60);
		auto sacParticle=SacParticle!B.get(ParticleType.heal);
		auto pvelocity=Vector3f(0,0,0),scale=1.5f,lifetime=31,frame=0;
		enum size=0.25f;
		static immutable Vector3f[2] box=[-0.5f*size*Vector3f(1.0f,1.0f,1.0f),0.5f*size*Vector3f(1.0f,1.0f,1.0f)];
		enum nSteps=3;
		foreach(i;0..nSteps)
			foreach(j;0..4)
				state.addParticle(Particle!B(sacParticle,oldPosition+float(i+1)/nSteps*velocity+state.uniform(box),pvelocity,scale,lifetime,frame));
		OrderTarget target;
		if(auto targetId=scarabProjectileCollisionTarget(attacker,side,intendedTarget,position,state)){
			target.id=targetId;
			target.type=state.targetTypeFromId(targetId);
		}else{
			static bool filter(ref ProximityEntry entry,int attacker,int side,int intendedTarget,ObjectState!B state){
				if(!entry.isObstacle) return false;
				if(!entry.isProjectileObstacle) return false;
				if(entry.id==intendedTarget) return true;
				if(entry.id==attacker) return false;
				return state.objectById!((obj,side,state)=>.side(obj,state)==side)(entry.id,side,state);
			}
			target=state.lineOfSight!filter(oldPosition,position,attacker,side,intendedTarget,state);
		}
		if(target.type!=TargetType.none||remainingDistance<=0.0f){
			scarabProjectile.scarabProjectileHit(target.id,state);
			return false;
		}
		return true;
	}
}

enum basiliskProjectileHitGain=4.0f;
enum basiliskProjectileSize=0.35f; // TODO: ok?
enum basiliskProjectileSlidingDistance=1.5f;
static immutable Vector3f[2] basiliskProjectileHitbox=[-0.5f*basiliskProjectileSize*Vector3f(1.0f,1.0f,1.0f),0.5f*basiliskProjectileSize*Vector3f(1.0f,1.0f,1.0f)];
int basiliskProjectileCollisionTarget(B)(int side,int intendedTarget,Vector3f position,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state,int side,int intendedTarget){
		return entry.isProjectileObstacle&&(entry.id==intendedTarget||state.objectById!(.side)(entry.id,state)!=side);
	}
	return collisionTarget!(basiliskProjectileHitbox,filter)(side,position,state,side,intendedTarget);
}
bool updateBasiliskProjectile(B)(ref BasiliskProjectile!B basiliskProjectile,ObjectState!B state){
	with(basiliskProjectile){
		auto oldPositions=positions;
		auto velocity=rangedAttack.speed/updateFPS*direction;
		foreach(ref position;positions) position+=velocity;
		remainingDistance-=rangedAttack.speed/updateFPS;
		static assert(updateFPS==60);
		enum nSteps=2;
		foreach(k;0..nSteps){
			foreach(oldPosition;oldPositions)
				state.addEffect(BasiliskEffect(oldPosition+float(k+1)/nSteps*velocity,direction));
		}
		OrderTarget target;
		if(auto targetId=basiliskProjectileCollisionTarget(side,intendedTarget,positions[0],state)){
			target.id=targetId;
			target.type=state.targetTypeFromId(targetId);
		}else if(auto targetId=basiliskProjectileCollisionTarget(side,intendedTarget,positions[1],state)){
			target.id=targetId;
			target.type=state.targetTypeFromId(targetId);
		}else{
			target=state.lineOfSightWithoutSide(oldPositions[0],positions[0],side,intendedTarget);
			if(!target.type) target=state.lineOfSightWithoutSide(oldPositions[1],positions[1],side,intendedTarget);
		}
		bool terminate(){
			playSoundAt("mfkr",boxCenter(positions),state,basiliskProjectileHitGain);
			return false;
		}
		if(remainingDistance<=0.0f) return terminate();
		switch(target.type){
			case TargetType.terrain: return terminate();
			case TargetType.creature:
				state.movingObjectById!(petrify,()=>false)(target.id,rangedAttack,direction,state);
				return terminate();
			case TargetType.building: return terminate();
			default: break;
		}
		return true;
	}
}
bool updateBasiliskEffect(B)(ref BasiliskEffect effect,ObjectState!B state){
	with(effect){
		static assert(updateFPS==60);
		return ++frame<32; // TODO: fix timing on this
	}
}

bool updatePetrification(B)(ref Petrification petrification,ObjectState!B state){
	return state.movingObjectById!((ref obj,petrification,state){
		bool removePetrification(){
			obj.creatureStats.effects.petrified=false;
			obj.creatureStats.effects.stunCooldown=0;
			obj.startIdling(state);
			obj.damageStun(petrification.attackDirection,state);
			auto hitbox=obj.hitbox;
			enum numParticles=32;
			auto sacParticle=SacParticle!B.get(ParticleType.rock);
			auto center=boxCenter(hitbox);
			foreach(i;0..numParticles){
				auto position=state.uniform(scaleBox(hitbox,0.9f));
				//auto velocity=1.5f*state.uniform(0.5f,2.0f)*Vector3f(position.x-center.x,position.y-center.y,2.0f);
				auto velocity=1.5f*state.uniform(0.5f,2.0f)*Vector3f(state.uniform(hitbox[0].x,hitbox[1].x)-center.x,state.uniform(hitbox[0].y,hitbox[1].y)-center.y,2.0f);
				auto scale=state.uniform(0.25f,0.75f);
				int lifetime=159;
				int frame=0;
				state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
			}
			return false;
		}
		if(!obj.creatureState.mode.canBePetrified)
			return removePetrification();
		with(*petrification){
			if(frame++>=lifetime) return removePetrification();
			return true;
		}
	},()=>false)(petrification.creature,&petrification,state);
}


enum tickfernoProjectileHitGain=4.0f;
enum tickfernoProjectileSize=0.35f; // TODO: ok?
enum tickfernoProjectileSlidingDistance=1.5f;
static immutable Vector3f[2] tickfernoProjectileHitbox=[-0.5f*tickfernoProjectileSize*Vector3f(1.0f,1.0f,1.0f),0.5f*tickfernoProjectileSize*Vector3f(1.0f,1.0f,1.0f)];
int tickfernoProjectileCollisionTarget(B)(int side,int intendedTarget,Vector3f position,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state,int side,int intendedTarget){
		return entry.isProjectileObstacle&&(entry.id==intendedTarget||state.objectById!(.side)(entry.id,state)!=side);
	}
	return collisionTarget!(tickfernoProjectileHitbox,filter)(side,position,state,side,intendedTarget);
}
bool updateTickfernoProjectile(B)(ref TickfernoProjectile!B tickfernoProjectile,ObjectState!B state){
	with(tickfernoProjectile){
		++frame;
		auto velocity=rangedAttack.speed/updateFPS*direction;
		if(remainingDistance>0.0f){
			void terminate(){
				playSoundAt("malf",position,state,tickfernoProjectileHitGain);
				remainingDistance=0.0f;
				hitframe=frame;
			}
			auto oldPosition=position;
			position+=velocity;
			remainingDistance-=rangedAttack.speed/updateFPS;
			if(remainingDistance<0.0f) terminate();
			static assert(updateFPS==60);
			if(!state.uniform(4)) state.addEffect(TickfernoEffect(oldPosition,direction));
			OrderTarget target;
			if(auto targetId=tickfernoProjectileCollisionTarget(side,intendedTarget,position,state)){
				target.id=targetId;
				target.type=state.targetTypeFromId(targetId);
			}else{
				target=state.lineOfSightWithoutSide(oldPosition,position,side,intendedTarget);
			}
			float manaDrain=0.0f;
			switch(target.type){
				case TargetType.terrain:
					flameEffect(position,state,2.0f);
					terminate();
					break;
				case TargetType.creature:
					manaDrain=state.movingObjectById!((ref object)=>0.5f*object.creatureStats.maxMana,()=>0.0f)(target.id);
					goto case;
				case TargetType.building:
					// TODO: ignite oil?
					setAblazeWithManaDrain(target.id,cast(int)(updateFPS*rangedAttack.duration),rangedAttack.amount,manaDrain,attacker,side,DamageMod.none,state);
					terminate();
					break;
				default: break;
			}
		}
		if(hitframe!=-1&&frame>=hitframe+updateFPS/2||frame>=updateFPS){
			startPosition+=velocity;
			if(dot(position-startPosition,direction)<0.0f)
				return false;
		}
		return true;
	}
}
bool updateTickfernoEffect(B)(ref TickfernoEffect effect,ObjectState!B state){
	with(effect){
		static assert(updateFPS==60);
		return ++frame<64; // TODO: fix timing on this
	}
}

enum vortickProjectileSize=0.45f; // TODO: ok?
enum vortickProjectileSlidingDistance=1.5f;
static immutable Vector3f[2] vortickProjectileHitbox=[-0.5f*vortickProjectileSize*Vector3f(1.0f,1.0f,1.0f),0.5f*vortickProjectileSize*Vector3f(1.0f,1.0f,1.0f)];
int vortickProjectileCollisionTarget(B)(int side,int intendedTarget,Vector3f position,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state,int side,int intendedTarget){
		return entry.isProjectileObstacle&&(entry.id==intendedTarget||state.objectById!(.side)(entry.id,state)!=side);
	}
	return collisionTarget!(vortickProjectileHitbox,filter)(side,position,state,side,intendedTarget);
}
bool updateVortickProjectile(B)(ref VortickProjectile!B vortickProjectile,ObjectState!B state){
	with(vortickProjectile){
		auto oldPosition=position;
		auto velocity=rangedAttack.speed/updateFPS*direction;
		position+=velocity;
		remainingDistance-=rangedAttack.speed/updateFPS;
		static assert(updateFPS==60);
		enum nSteps=2;
		foreach(i;0..nSteps)
			state.addEffect(VortickEffect(oldPosition+float(i+1)/nSteps*velocity,direction));
		OrderTarget target;
		if(auto targetId=vortickProjectileCollisionTarget(side,intendedTarget,position,state)){
			target.id=targetId;
			target.type=state.targetTypeFromId(targetId);
		}else{
			target=state.lineOfSightWithoutSide(oldPosition,position,side,intendedTarget);
		}
		bool terminate(){
			spawnVortex(oldPosition,rangedAttack,state);
			return false;
		}
		if(remainingDistance<=0.0f) return terminate();
		switch(target.type){
			case TargetType.terrain:
				return terminate();
			case TargetType.creature:
				/+auto effectDirection=20.0f*Vector3f(-direction.x,-direction.y,2.0f).normalized;
				state.movingObjectById!((ref obj,state){
					obj.creatureState.fallingVelocity.z=0.0f;
					obj.catapult(effectDirection,state);
				},(){})(target.id,state);+/
				goto case;
			case TargetType.building:
				dealRangedDamage(target.id,rangedAttack,attacker,side,direction,DamageMod.none,state);
				return terminate();
			default: break;
		}
		return true;
	}
}
bool updateVortickEffect(B)(ref VortickEffect effect,ObjectState!B state){
	with(effect){
		static assert(updateFPS==60);
		return ++frame<64; // TODO: fix timing on this
	}
}

Vector3f vortexAnimationForceField(Vector3f position,float radius,float height){
	//return Vector3f(-3.75f*position.y-1.5f*position.x,3.75f*position.x-1.5f*position.y,30.0f*0.25f);
	return Vector3f(-3.75f*position.y-2.5f*position.x,3.75f*position.x-2.5f*position.y,30.0f*0.25f);
}
Vector3f vortexForceField(Vector3f position,float radius,float height){
	//if(position.xy.lengthsqr>radius*radius) return Vector3f(0.0f,0.0f,0.0f);
	if(position.z>height) return Vector3f(0.0f,0.0f,0.0f);
	//return Vector3f(-7.5f*position.y-7.5f*position.x,7.5f*position.x-7.5f*position.y,30.0f*0.35f);
	//return Vector3f(-7.0f*position.y-7.0f*position.x,7.0f*position.x-7.0f*position.y,30.0f*0.35f);
	//return Vector3f(-6.0f*position.y-6.0f*position.x,6.0f*position.x-6.0f*position.y,30.0f*0.4f);
	return Vector3f(5.5f*(-position.y-position.x),5.5f*(position.x-position.y),5.5f);
}

void addVortexParticles(B)(ref VortexEffect!B vortex,ObjectState!B state){
	with(vortex){
		auto radius=2.0f*radiusFactor*rangedAttack.effectRange;
		auto height=maxHeight;
		auto numParticles=5;
		foreach(i;0..numParticles){
			auto position=Vector3f(0.0f,0.0f,0.0f);
			auto directionXY=radius*state.uniformDirection!(float,2)();
			auto locationXY=state.uniform(0.0f,0.2f);
			auto endlocationXY=state.uniform(max(locationXY,0.95f),1.0f);
			auto velocityXY=(endlocationXY-locationXY)/duration*directionXY;
			position.x+=locationXY/duration*directionXY.x;
			position.y+=locationXY/duration*directionXY.y;
			auto velocityZ=state.uniform(0.8f,1.0f)*height/duration;
			auto velocity=Vector3f(velocityXY.x,velocityXY.y,velocityZ);
			auto scale=state.uniform(0.3f,1.0f);
			auto frame=0;
			vortex.particles~=Particle(position,velocity,scale,frame);
		}
	}
}

bool updateVortexEffect(B)(ref VortexEffect!B vortex,ObjectState!B state){
	with(vortex){
		if(frame<0.75f*duration*updateFPS) vortex.addVortexParticles(state);
		auto radius=radiusFactor*rangedAttack.effectRange;
		auto height=maxHeight;
		for(int i=0;i<particles.length;){
			with(particles[i]){
				auto velocityXY=vortexAnimationForceField(position,radius,height)/updateFPS;
				velocity.x+=velocityXY.x;
				velocity.y+=velocityXY.y;
				position+=velocity/updateFPS;
				if(++frame>2*updateFPS){
					if(i+1<particles.length) swap(particles[i],particles[$-1]);
					particles.length=particles.length-1;
					continue;
				}
				i++;
			}
		}
		auto diag=sqrt(2.0f)*radius;
		Vector3f[2] hitbox=[Vector3f(position.x-diag,position.y-diag,position.z-0.25f*height),Vector3f(position.x+diag,position.y+diag,position.z+height)];
		static void influence(ProximityEntry target,ObjectState!B state,VortexEffect!B *vortex,float radius,float height){
			state.movingObjectById!((ref obj,vortex,radius,height,state){
				if(obj.creatureState.movement!=CreatureMovement.tumbling){
					auto direction=(vortex.position.xy-obj.center.xy).normalized*1.5f;
					//obj.catapult(Vector3f(1.5f*direction.x,1.5f*direction.y,2.5f),state);
					//obj.catapult(Vector3f(1.5f*direction.y,-1.5f*direction.x,2.5f),state);
					obj.catapult(Vector3f(direction.y,-direction.x,2.5f),state);
				}
				if(obj.creatureState.movement==CreatureMovement.tumbling){
					auto acceleration=vortexForceField(obj.center-vortex.position,radius,height);
					obj.creatureState.fallingVelocity+=acceleration/updateFPS;
					obj.creatureState.fallingVelocity.z=max(obj.creatureState.fallingVelocity.z,1.0f);
					obj.creatureStats.effects.antiGravityTime=state.frame;
				}
			},(){})(target.id,vortex,radius,height,state);
		}
		if(frame<0.75f*duration*updateFPS) collisionTargets!influence(hitbox,state,&vortex,radius,height);
		return ++frame<=duration*updateFPS;
	}
}

enum squallProjectileHitGain=4.0f;
enum squallProjectileSize=0.45f; // TODO: ok?
enum squallProjectileSlidingDistance=1.5f;
static immutable Vector3f[2] squallProjectileHitbox=[-0.5f*squallProjectileSize*Vector3f(1.0f,1.0f,1.0f),0.5f*squallProjectileSize*Vector3f(1.0f,1.0f,1.0f)];
int squallProjectileCollisionTarget(B)(int side,int intendedTarget,Vector3f position,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state,int side,int intendedTarget){
		return entry.isProjectileObstacle&&(entry.id==intendedTarget||state.objectById!(.side)(entry.id,state)!=side);
	}
	return collisionTarget!(squallProjectileHitbox,filter)(side,position,state,side,intendedTarget);
}
bool updateSquallProjectile(B)(ref SquallProjectile!B squallProjectile,ObjectState!B state){
	with(squallProjectile){
		auto oldPosition=position;
		auto velocity=rangedAttack.speed/updateFPS*direction;
		position+=velocity;
		remainingDistance-=rangedAttack.speed/updateFPS;
		static assert(updateFPS==60);
		enum nSteps=1;
		foreach(i;0..nSteps)
			state.addEffect(SquallEffect(oldPosition+float(i+1)/nSteps*velocity,direction));
		OrderTarget target;
		if(auto targetId=squallProjectileCollisionTarget(side,intendedTarget,position,state)){
			target.id=targetId;
			target.type=state.targetTypeFromId(targetId);
		}else{
			target=state.lineOfSightWithoutSide(oldPosition,position,side,intendedTarget);
		}
		bool terminate(){
			playSoundAt("hlqs",position,state,squallProjectileHitGain);
			return false;
		}
		if(remainingDistance<=0.0f) return terminate();
		switch(target.type){
			case TargetType.terrain:
				return terminate();
			case TargetType.creature:
				pushback(target.id,direction,rangedAttack,state);
				goto case;
			case TargetType.building:
				dealRangedDamage(target.id,rangedAttack,attacker,side,direction,DamageMod.none,state);
				return terminate();
			default: break;
		}
		return true;
	}
}
bool updateSquallEffect(B)(ref SquallEffect effect,ObjectState!B state){
	with(effect){
		static assert(updateFPS==60);
		return ++frame<64; // TODO: fix timing on this
	}
}

bool updatePushback(B)(ref Pushback!B pushback,ObjectState!B state){
	with(pushback){
		return state.movingObjectById!((ref obj,vel,state){
			final switch(obj.creatureState.movement) with(CreatureMovement){
				case onGround,flying:
					obj.push(vel,state);
					return true;
				case tumbling:
					obj.creatureState.fallingVelocity+=vel;
					return false;
			}
		},()=>false)(creature,pushVelocity*direction,state) && ++frame<pushDuration*updateFPS;
	}
}

void animateFlummoxProjectile(B)(ref FlummoxProjectile!B flummoxProjectile,Vector3f oldPosition,ObjectState!B state){
	with(flummoxProjectile){
		rotation=rotationUpdate*rotation;
		enum numParticles=2;
		auto sacParticle=SacParticle!B.get(ParticleType.dust);
		auto velocity=Vector3f(0.0f,0.0f,0.0f);
		auto lifetime=31;
		auto scale=1.5f;
		auto frame=0;
		foreach(i;0..numParticles){
			auto position=oldPosition*((cast(float)numParticles-1-i)/numParticles)+position*(cast(float)(i+1)/numParticles);
			position+=0.3f*state.uniformDirection();
			state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
		}
	}
}

enum flummoxProjectileSize=2.0f; // TODO: ok?
enum flummoxProjectileSlidingDistance=0.0f;
static immutable Vector3f[2] flummoxProjectileHitbox=[-0.5f*flummoxProjectileSize*Vector3f(1.0f,1.0f,1.0f),0.5f*flummoxProjectileSize*Vector3f(1.0f,1.0f,1.0f)];
int flummoxProjectileCollisionTarget(B)(int side,int intendedTarget,Vector3f position,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state,int side,int intendedTarget){
		return entry.isProjectileObstacle&&(entry.id==intendedTarget||state.objectById!(.side)(entry.id,state)!=side);
	}
	return collisionTarget!(flummoxProjectileHitbox,filter)(side,position,state,side,intendedTarget);
}

void flummoxProjectileExplosion(B)(ref FlummoxProjectile!B flummoxProjectile,ObjectState!B state){
	playSoundAt("7sms",flummoxProjectile.position,state,4.0f);
	static bool callback(int target,ObjectState!B state){
		state.movingObjectById!(stunWithCooldown,()=>false)(target,stunCooldownFrames,state);
		return true;
	}
	with(flummoxProjectile)
		dealSplashRangedDamageAt!callback(0,rangedAttack,rangedAttack.effectRange,attacker,side,position,DamageMod.none,state,state);
	enum numParticles3=100;
	auto sacParticle3=SacParticle!B.get(ParticleType.rock);
	foreach(i;0..numParticles3){
		auto direction=state.uniformDirection();
		auto velocity=state.uniform(10.0f,20.0f)*direction;
		auto scale=state.uniform(1.0f,1.5f);
		auto lifetime=95;
		auto frame=0;
		state.addParticle(Particle!B(sacParticle3,flummoxProjectile.position,velocity,scale,lifetime,frame));
	}
	enum numParticles4=20;
	auto sacParticle4=SacParticle!B.get(ParticleType.dirt);
	foreach(i;0..numParticles4){
		auto direction=state.uniformDirection();
		auto position=flummoxProjectile.position+direction;
		auto velocity=Vector3f(0.0f,0.0f,0.0f);
		auto scale=3.75f;
		auto frame=state.uniform(2)?0:state.uniform(24);
		auto lifetime=63-frame;
		state.addParticle(Particle!B(sacParticle4,position,velocity,scale,lifetime,frame));
	}
	screenShake(flummoxProjectile.position,60,0.5f,100.0f,state);
	// TODO: add scar
}

bool updateFlummoxProjectile(B)(ref FlummoxProjectile!B flummoxProjectile,ObjectState!B state){
	with(flummoxProjectile){
		auto oldPosition=position;
		position+=velocity/updateFPS;
		velocity.z-=rangedAttack.fallingAcceleration/updateFPS;
		rotation=rotationUpdate*rotation;
		flummoxProjectile.animateFlummoxProjectile(oldPosition,state);
		auto target=flummoxProjectileCollisionTarget(side,intendedTarget,position,state);
		if(state.isValidTarget(target)){
			flummoxProjectile.flummoxProjectileExplosion(state);
			return false;
		}
		if(state.isOnGround(position)){
			if(position.z<state.getGroundHeight(position)){
				flummoxProjectile.flummoxProjectileExplosion(state);
				return false;
			}
		}else if(position.z<state.getHeight(position)-rangedAttack.fallLimit)
			return false;
		return true;
	}
}

bool updateGnomeEffect(B)(ref GnomeEffect!B gnomeEffect,ObjectState!B state){
	with(gnomeEffect){
		return ++frame<=numFrames;
	}
}

enum pyromaniacRocketHitGain=2.0f;
enum pyromaniacRocketSize=0.1; // TODO: ok?
enum pyromaniacRocketSlidingDistance=0.0f;

void animatePyromaniacRocket(B)(ref PyromaniacRocket!B pyromaniacRocket,Vector3f oldPosition,ObjectState!B state){
	with(pyromaniacRocket){
		enum numParticles=4;
		auto sacParticle=SacParticle!B.get(ParticleType.smoke);
		auto lifetime=47;
		auto scale=0.75f;
		auto frame=80;
		foreach(i;0..numParticles){
			auto position=oldPosition*((cast(float)numParticles-1-i)/numParticles)+position*(cast(float)(i+1)/numParticles)-2.5f*direction;
			position+=0.6f*state.uniformDirection();
			auto velocity=0.05f*state.uniformDirection();
			state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
		}
	}
}
static immutable Vector3f[2] pyromaniacRocketHitbox=[-0.5f*pyromaniacRocketSize*Vector3f(1.0f,1.0f,1.0f),0.5f*pyromaniacRocketSize*Vector3f(1.0f,1.0f,1.0f)];
int pyromaniacRocketCollisionTarget(B)(int side,int intendedTarget,Vector3f position,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state,int side,int intendedTarget){
		return entry.isProjectileObstacle&&(entry.id==intendedTarget||state.objectById!(.side)(entry.id,state)!=side);
	}
	return collisionTarget!(pyromaniacRocketHitbox,filter)(side,position,state,side,intendedTarget);
}
bool updatePyromaniacRocket(B)(ref PyromaniacRocket!B pyromaniacRocket,ObjectState!B state){
	with(pyromaniacRocket){
		++frame;
		auto oldPosition=position;
		auto velocity=rangedAttack.speed/updateFPS*direction;
		position+=velocity;
		remainingDistance-=rangedAttack.speed/updateFPS;
		static assert(updateFPS==60);
		pyromaniacRocket.animatePyromaniacRocket(oldPosition,state);
		OrderTarget target;
		if(auto targetId=pyromaniacRocketCollisionTarget(side,intendedTarget,position,state)){
			target.id=targetId;
			target.type=state.targetTypeFromId(targetId);
		}else{
			target=state.lineOfSightWithoutSide(oldPosition,position,side,intendedTarget);
		}
		bool terminate(){
			playSpellSoundTypeAt(SoundType.pyromaniacHit,position,state,pyromaniacRocketHitGain);
			return false;
		}
		if(remainingDistance<=0.0f) return terminate();
		switch(target.type){
			case TargetType.terrain:
				flameEffect(position,state,2.0f);
				return terminate();
			case TargetType.creature:
				goto case;
			case TargetType.building:
				//dealRangedDamage(target.id,rangedAttack,attacker,side,direction,state);
				setAblaze(target.id,cast(int)(rangedAttack.duration*updateFPS),true,rangedAttack.amount,attacker,side,DamageMod.peirceShield,state);
				return terminate();
			default: break;
		}
		return true;
	}
}

enum poisonDartHitGain=2.0f;
enum poisonDartSize=0.1; // TODO: ok?
enum poisonDartSlidingDistance=0.0f;

static immutable Vector3f[2] poisonDartHitbox=[-0.5f*poisonDartSize*Vector3f(1.0f,1.0f,1.0f),0.5f*poisonDartSize*Vector3f(1.0f,1.0f,1.0f)];
int poisonDartCollisionTarget(B)(int side,int intendedTarget,Vector3f position,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state,int side,int intendedTarget){
		return entry.isProjectileObstacle&&(entry.id==intendedTarget||state.objectById!(.side)(entry.id,state)!=side);
	}
	return collisionTarget!(poisonDartHitbox,filter)(side,position,state,side,intendedTarget);
}
bool updatePoisonDart(B)(ref PoisonDart!B poisonDart,ObjectState!B state){
	with(poisonDart){
		auto oldPosition=position;
		auto velocity=rangedAttack.speed/updateFPS*direction;
		position+=velocity;
		remainingDistance-=rangedAttack.speed/updateFPS;
		static assert(updateFPS==60);
		OrderTarget target;
		if(auto targetId=poisonDartCollisionTarget(side,intendedTarget,position,state)){
			target.id=targetId;
			target.type=state.targetTypeFromId(targetId);
		}else{
			target=state.lineOfSightWithoutSide(oldPosition,position,side,intendedTarget);
		}
		bool terminate(){
			playSoundAt("thed",position,state,poisonDartHitGain);
			return false;
		}
		if(remainingDistance<=0.0f) return terminate();
		switch(target.type){
			case TargetType.terrain: return terminate();
			case TargetType.creature:
				state.movingObjectById!(poison,()=>false)(target.id,rangedAttack,false,attacker,side,DamageMod.ranged,state);
				return terminate();
			case TargetType.building:
				dealRangedDamage(target.id,rangedAttack,attacker,side,direction,DamageMod.none,state);
				return terminate();
			default: break;
		}
		return true;
	}
}

enum mutantProjectileSize=1.25f; // TODO: ok?
enum mutantProjectileSlidingDistance=0.0f;
static immutable Vector3f[2] mutantProjectileHitbox=[-0.5f*mutantProjectileSize*Vector3f(1.0f,1.0f,1.0f),0.5f*mutantProjectileSize*Vector3f(1.0f,1.0f,1.0f)];
int mutantProjectileCollisionTarget(B)(int side,int intendedTarget,Vector3f position,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state,int side,int intendedTarget){
		return entry.isProjectileObstacle&&(entry.id==intendedTarget||state.objectById!(.side)(entry.id,state)!=side);
	}
	return collisionTarget!(mutantProjectileHitbox,filter)(side,position,state,side,intendedTarget);
}

void mutantProjectileExplosion(B)(ref MutantProjectile!B mutantProjectile,int target,ObjectState!B state){
	//playSpellSoundTypeAt(SoundType.gib,mutantProjectile.position,state,mutantShootGain);
	with(mutantProjectile){
		if(state.isValidTarget(target)) dealRangedDamage(target,rangedAttack,attacker,side,velocity,DamageMod.splash,state);
		dealSplashRangedDamageAt(target,rangedAttack,rangedAttack.damageRange,attacker,side,position,DamageMod.none,state);
	}
	enum numParticles4=20; // TODO: improve splat animation
	auto sacParticle4=SacParticle!B.get(ParticleType.splat);
	foreach(i;0..numParticles4){
		auto position=mutantProjectile.position;
		if(i) position+=1.75f*state.uniformDirection();
		auto velocity=Vector3f(0.0f,0.0f,-0.5f);
		auto scale=2.25f;
		auto frame=state.uniform(2)?0:state.uniform(24);
		auto lifetime=95-frame;
		state.addParticle(Particle!B(sacParticle4,position,velocity,scale,lifetime,frame));
	}
}

bool updateMutantProjectile(B)(ref MutantProjectile!B mutantProjectile,ObjectState!B state){
	with(mutantProjectile){
		++frame;
		auto oldPosition=position;
		position+=velocity/updateFPS;
		velocity.z-=rangedAttack.fallingAcceleration/updateFPS;
		auto target=mutantProjectileCollisionTarget(side,intendedTarget,position,state);
		if(state.isValidTarget(target)){
			mutantProjectile.mutantProjectileExplosion(target,state);
			return false;
		}
		if(state.isOnGround(position)){
			if(position.z<state.getGroundHeight(position)){
				mutantProjectile.mutantProjectileExplosion(0,state);
				return false;
			}
		}else if(position.z<state.getHeight(position)-rangedAttack.fallLimit)
			return false;
		return true;
	}
}


bool updateRockForm(B)(ref RockForm!B rockForm,ObjectState!B state){
	with(rockForm){
		if(!state.isValidTarget(target,TargetType.creature)) return false;
		if(status!=RockFormStatus.shrinking){
			static bool check(ref MovingObject!B obj,ObjectState!B state){
				if(obj.isGuardian) obj.startIdling(state);
				return obj.creatureState.mode==CreatureMode.rockForm;
			}
			if(!state.movingObjectById!(check,()=>false)(target,state)){
				status=RockFormStatus.shrinking;
				playSoundAt("tlep",target,state,2.0f);
			}
		}
		final switch(status){
			case RockFormStatus.growing:
				relativeScale=min(1.0f,relativeScale+1.0f/numFrames);
				if(relativeScale==1.0f) status=RockFormStatus.stationary;
				break;
			case RockFormStatus.stationary:
				break;
			case RockFormStatus.shrinking:
				relativeScale=max(0.0f,relativeScale-1.0f/numFrames);
				if(relativeScale==0.0f)
					return false;
				break;
		}
		return true;
	}
}

bool checkStealth(B)(ref MovingObject!B obj){
	if(obj.isGuardian) return false;
	final switch(obj.creatureState.mode) with(CreatureMode){
		case idle,moving,spawning,takeoff,landing,cower,pretendingToDie,playingDead,pretendingToRevive,rockForm: return true;
		case dying,dead,deadToGhost,idleGhost,movingGhost,ghostToIdle,dissolving,preSpawning,reviving,fastReviving,meleeMoving,meleeAttacking,stunned,casting,stationaryCasting,castingMoving,shooting,usingAbility,pulling,pumping,torturing,convertReviving,thrashing: return false;
	}
}

bool updateStealth(B)(ref Stealth!B stealth,ObjectState!B state){
	with(stealth){
		if(!state.isValidTarget(target,TargetType.creature)) return false;
		updateRenderMode(target,state);
		if(status!=StealthStatus.fadingIn){
			static bool check(ref MovingObject!B obj,ObjectState!B state){
				assert(obj.creatureStats.effects.stealth);
				if(obj.isGuardian) return false;
				return obj.checkStealth();
			}
			if(!state.movingObjectById!(check,()=>false)(target,state)){
				status=StealthStatus.fadingIn;
				playSoundAt("tlts",target,state,2.0f);
			}
		}
		void updateAlpha(){
			state.setAlpha(target,1.0f+progress*(targetAlpha-1.0f),1.0f+progress*(targetEnergy-1.0f));
		}
		final switch(status){
			case StealthStatus.fadingOut:
				progress=min(1.0f,progress+1.0f/numFrames);
				if(progress==1.0f) status=StealthStatus.stationary;
				updateAlpha();
				break;
			case StealthStatus.stationary:
				break;
			case StealthStatus.fadingIn:
				progress=max(0.0f,progress-1.0f/numFrames);
				if(progress==0.0f){
					static void removeStealth(B)(ref MovingObject!B object){
						assert(object.creatureStats.effects.stealth);
						object.creatureStats.effects.stealth=false;
					}
					state.movingObjectById!(removeStealth,(){})(target);
					updateRenderMode(target,state);
					return false;
				}
				updateAlpha();
				break;
		}
		return true;
	}
}

bool updateLifeShield(B)(ref LifeShield!B lifeShield,ObjectState!B state){
	with(lifeShield){
		if(!state.isValidTarget(target,TargetType.creature)) return false;
		++frame;
		if(--soundEffectTimer<=0) soundEffectTimer=playSoundAt!true("lhsl",target,state,2.0f);
		if(status!=LifeShieldStatus.shrinking){
			static bool check(ref MovingObject!B obj){
				assert(obj.creatureStats.effects.lifeShield);
				return obj.creatureState.mode.canShield;
			}
			if(!state.movingObjectById!(check,()=>false)(target)||frame+scaleFrames>=ability.duration*updateFPS)
				status=LifeShieldStatus.shrinking;
		}
		final switch(status){
			case LifeShieldStatus.growing:
				scale=min(1.0f,scale+1.0f/scaleFrames);
				if(scale==1.0f) status=LifeShieldStatus.stationary;
				break;
			case LifeShieldStatus.stationary:
				break;
			case LifeShieldStatus.shrinking:
				scale=max(0.0f,scale-1.0f/scaleFrames);
				if(scale==0.0f){
					static void removeLifeShield(B)(ref MovingObject!B object){
						assert(object.creatureStats.effects.lifeShield);
						object.creatureStats.effects.lifeShield=false;
					}
					state.movingObjectById!(removeLifeShield,(){})(target);
					updateRenderMode(target,state);
					return false;
				}
				break;
		}
		return true;
	}
}

enum divineSightFlyingHeight=4.0f;
enum divineSightNumRisingFrames=45;
bool updateDivineSight(B)(ref DivineSight!B divineSight,ObjectState!B state){
	with(divineSight){
		++frame;
		auto lifetime=divineSightNumRisingFrames+ability.duration*updateFPS;
		scale=min(1.0f,min(float(frame),lifetime-float(frame))/(divineSightNumRisingFrames-1));
		if(frame<divineSightNumRisingFrames){
			position.z=state.getHeight(position)+0.5f*divineSightFlyingHeight+frame*(0.5f*divineSightFlyingHeight)/(divineSightNumRisingFrames-1);
			return true;
		}
		auto flyingHeight=divineSightFlyingHeight;
		if(target==0){
			auto travelFrames=frame-divineSightNumRisingFrames;
			if(travelFrames*ability.speed<updateFPS*ability.range){
				velocity=velocity.normalized*ability.speed;
			}else if((travelFrames-1)*ability.speed<updateFPS*ability.range)
				velocity=Vector3f(0.0f,0.0f,0.0f);
			if(state.frontOfAIQueue(side,creature)) // TODO: what happens in original if creature dies?
			   target=state.proximity.closestEnemyInRange(side,position,ability.range,EnemyType.creature,state);
		}else if(target!=-1&&state.isValidTarget(target,TargetType.creature)){
			static getHitbox(B)(ref MovingObject!B obj){
				auto hbox=obj.sacObject.hitbox(obj.rotation,AnimationState.stance1,0);
				hbox[0]+=obj.position;
				hbox[1]+=obj.position;
				return hbox;
			}
			alias VT=Vector3f[2]; // workaround for DMD bug
			auto targetHitbox=state.movingObjectById!(getHitbox,()=>VT.init)(target);
			auto targetCenter=boxCenter(targetHitbox);
			if(!isNaN(targetCenter.x)){
				flyingHeight=targetHitbox[1].z-state.getHeight(targetCenter)+0.5f*divineSightFlyingHeight;
				auto distance=targetCenter-position;
				auto acceleration=distance.normalized*ability.acceleration;
				velocity+=acceleration;
				Vector3f capVelocity(Vector3f velocity){
					if(velocity.length>ability.speed) velocity=velocity.normalized*ability.speed;
					if(velocity.length>updateFPS*distance.length) velocity=velocity.normalized*distance.length*updateFPS;
					return velocity;
				}
				velocity=capVelocity(velocity);
			}
		}else target=-1;
		auto newPosition=position+velocity/updateFPS;
		auto height=state.getHeight(position);
		if(newPosition.z<height+flyingHeight){
			auto nvel=velocity;
			nvel.z+=(height+flyingHeight-newPosition.z)*updateFPS;
			if(nvel.length>ability.speed) nvel=nvel.normalized*ability.speed;
			newPosition=position+nvel/updateFPS;
		}
		position=newPosition;
		// TODO: clear fog of war
		return frame<lifetime;
	}
}

bool updateSteamCloud(B)(ref SteamCloud!B steamCloud,ObjectState!B state){
	with(steamCloud){
		dealSplashSpellDamageAt(id,ability,ability.damageRange,id,side,boxCenter(hitbox),DamageMod.ignite,state);
		enum numParticles2=100;
		auto sacParticle2=SacParticle!B.get(ParticleType.steam);
		auto scale=0.3f*boxSize(hitbox).length;
		foreach(i;0..numParticles2){
			auto position=state.uniform(scaleBox(hitbox,1.2f));
			//auto direction=state.uniformDirection();
			auto direction=(position-boxCenter(hitbox)).normalized;
			auto velocity=scale*state.uniform(0.25f,0.75f)*direction;
			auto lifetime=63;
			auto frame=0;
			state.addParticle(Particle!B(sacParticle2,position,velocity,scale,lifetime,frame));
		}
		return false;
	}
}

bool updatePoisonCloud(B)(ref PoisonCloud!B poisonCloud,ObjectState!B state){
	with(poisonCloud){
		static void process(ProximityEntry target,ObjectState!B state,int directTarget,SacSpell!B ability,int attacker,int attackerSide,Vector3f position,float radius){
			if(target.id==attacker) return;
			auto distance=boxPointDistance(target.hitbox,position);
			if(distance>radius) return;
			state.movingObjectById!(poison,()=>false)(target.id,ability,false,attacker,attackerSide,DamageMod.splash|DamageMod.spell,state); // TODO: poison from cloud should be completely independent of other poison
		}
		auto position=boxCenter(hitbox);
		auto radius=ability.effectRange;
		auto offset=Vector3f(radius,radius,radius);
		Vector3f[2] phitbox=[position-offset,position+offset];
		collisionTargets!process(phitbox,state,id,ability,id,side,position,radius);
		enum numParticles2=50;
		auto sacParticle2=SacParticle!B.get(ParticleType.poison);
		auto scale=boxSize(hitbox).length;
		foreach(i;0..numParticles2){
			auto pposition=state.uniform(scaleBox(hitbox,2.0f));
			auto direction=(position-boxCenter(hitbox)).normalized;
			auto velocity=scale*state.uniform(0.25f,0.75f)*direction;
			auto lifetime=state.uniform(95,127);
			auto frame=0;
			state.addParticle(Particle!B(sacParticle2,pposition,velocity,scale,lifetime,frame));
		}
		return false;
	}
}

enum blightMiteSize=0.5f;
static immutable Vector3f[2] blightMiteHitbox=[-0.5f*blightMiteSize*Vector3f(1.0f,1.0f,1.0f),0.5f*blightMiteSize*Vector3f(1.0f,1.0f,1.0f)];
int blightMiteCollisionTarget(B)(Vector3f position,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state){
		return entry.isProjectileObstacle&&state.movingObjectById!((ref obj)=>obj.creatureState.mode.canBeInfectedByMites,()=>false)(entry.id);
	}
	return collisionTarget!(blightMiteHitbox,filter)(-1,position,state);
}
bool updateBlightMite(B)(ref BlightMite!B blightMite,ObjectState!B state){
	with(blightMite){
		++frame;
		bool vanish(){
			alpha-=1.0f/(fadeTime*updateFPS);
			if(alpha<=0.0f)
				return false;
			return true;
		}
		if(target){
			auto keep=++infectionTime<=updateFPS*ability.duration;
			if(!keep||state.movingObjectById!((ref obj)=>!obj.creatureState.mode.canBeInfectedByMites,()=>true)(target)){
				keep=false;
				if(alpha==1.0f) state.movingObjectById!((ref obj){ obj.creatureStats.effects.numBlightMites-=1; },(){})(target);
			}
			if(!keep) return vanish();
			return true;
		}else{
			if(numJumps>=5) return vanish();
			position+=velocity/updateFPS;
			velocity.z-=ability.fallingAcceleration/updateFPS;
			if(state.isOnGround(position)){
				auto height=state.getGroundHeight(position);
				if(height>position.z){
					position.z=height;
					numJumps+=1;
					if(state.uniform(2)) playSpellSoundTypeAt(SoundType.mites,position,state,1.0f);
					if(numJumps>=5){
						velocity=Vector3f(0.0f,0.0f,0.0f);
					}else{
						if(auto closeCreature=state.proximity.closestCreatureInRange(position,ability.effectRange,state,10.0f)){
							auto creaturePosition=state.movingObjectById!((ref obj)=>obj.center,()=>Vector3f.init)(closeCreature);
							if(intendedTarget&&closeCreature!=intendedTarget){
								auto intendedPosition=state.movingObjectById!((ref obj)=>obj.center,()=>Vector3f.init)(intendedTarget);
								if(!isNaN(intendedPosition.x)&&(intendedPosition-position).lengthsqr<=ability.effectRange^^2){
									closeCreature=intendedTarget;
									creaturePosition=intendedPosition;
								}
							}
							if(!isNaN(creaturePosition.x)){
								auto direction=creaturePosition-position;
								velocity=4.5f*direction.normalized+0.5f*state.uniformDirection();
								velocity.z+=0.5f*ability.fallingAcceleration*direction.length/velocity.length;
								velocity.z=min(velocity.z,10.0f);
							}
						}else{
							velocity=5.0f*state.uniformDirection();
							velocity.z=10.0f;
						}
					}
				}
			}
			if(auto collisionTarget=blightMiteCollisionTarget(position,state)){
				if(frame>updateFPS/2||collisionTarget!=creature){
					auto targetPositionTargetRotation=state.movingObjectById!((ref obj){
						obj.creatureStats.effects.numBlightMites+=1;
						return tuple(obj.position,obj.rotation);
					},()=>Tuple!(Vector3f,Quaternionf).init)(collisionTarget);
					auto targetPosition=targetPositionTargetRotation[0], targetRotation=targetPositionTargetRotation[1];
					if(!isNaN(targetPosition.x)){
						playSoundAt("htim",position,state,1.0f); // TODO: move sound with projectile
						position=rotate(targetRotation.conj(),position-targetPosition);
						target=collisionTarget;
					}
				}
			}
			return true;
		}
	}
}

bool updateLightningCharge(B)(ref LightningCharge!B lightningCharge,ObjectState!B state){
	with(lightningCharge){
		static import std.math;
		enum sparkProb=(1.0f-std.math.exp(-sparkRate/updateFPS));
		enum lightningProb=(1.0f-std.math.exp(-lightningRate/updateFPS));
		auto hitbox=state.movingObjectById!(hitbox,()=>(Vector3f[2]).init)(creature);
		if(isNaN(hitbox[0].x)) return false;
		auto center=boxCenter(hitbox);
		if(state.uniform(0.0f,1.0f)<=sparkProb)
			sparkAnimation!48(hitbox,state);
		if(state.uniform(0.0f,1.0f)<=lightningProb){
			auto start=OrderTarget(TargetType.creature,creature,center);
			OrderTarget end;
			if(end.type==TargetType.none){
				auto direction=state.uniformDirection!(float,2)();
				auto distance=state.uniform(range/5.0f,range);
				auto offset=direction*distance;
				auto position=center+Vector3f(offset.x,offset.y,0.0f);
				position.z=state.getHeight(position);
				end=OrderTarget(TargetType.terrain,0,position);
			}
			if(auto target=state.proximity.anyInRangeAndClosestTo(start.position,range,end.position,creature)){
				auto jumped=target?centerTarget(target,state):OrderTarget.init;
				auto jdistsqr=(end.position-jumped.position).lengthsqr;
				if(jdistsqr<shortJumpRange^^2||jdistsqr<jumpRange^^2&&state.uniform(3)!=0)
					end=jumped;
			}
			lightning(creature,side,start,end,spell,state,true,DamageMod.none);
		}
		return state.movingObjectById!((ref obj)=>--obj.creatureStats.effects.lightningChargeFrames>0,()=>false)(creature);
	}
}

AnimationState pullAnimation(B)(ref MovingObject!B object){
	final switch(object.creatureState.movement) with(CreatureMovement){
		case onGround:
			return AnimationState.shoot1;
		case flying:
			if(object.sacObject.mustFly)
				goto case onGround;
			return AnimationState.carried;
		case tumbling:
			goto case onGround;
	}
}

void animateWebPullBreaking(B)(Vector3f[2] hitbox,ObjectState!B state){
	if(isNaN(hitbox[0].x)) return;
	enum numParticles=64;
	auto sacParticle=SacParticle!B.get(ParticleType.webDebris);
	auto center=boxCenter(hitbox);
	foreach(i;0..numParticles){
		auto position=state.uniform(scaleBox(hitbox,0.9f));
		auto direction=state.uniformDirection();
		auto velocity=state.uniform(7.5f,15.0f)*direction;
		auto scale=state.uniform(1.0f,1.5f)*boxSize(hitbox).length;
		int lifetime=95;
		int frame=0;
		state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
	}
}

void animateCagePullBreaking(B)(Vector3f[2] hitbox,ObjectState!B state){
	if(isNaN(hitbox[0].x)) return;
	enum numParticles=64;
	auto sacParticle=SacParticle!B.get(ParticleType.spark);
	auto center=boxCenter(hitbox);
	foreach(i;0..numParticles){
		auto position=state.uniform(scaleBox(hitbox,0.9f));
		auto direction=state.uniformDirection();
		auto velocity=state.uniform(7.5f,15.0f)*direction;
		auto scale=state.uniform(0.5f,1.0f)*boxSize(hitbox).length;
		int lifetime=95;
		int frame=0;
		state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
	}
}

enum webGain=4.0f, cageGain=4.0f;
bool updatePull(PullType type,B)(ref Pull!(type,B) pull,ObjectState!B state){
	with(pull){
		++frame;
		if(frame==numShootFrames&&target){
			static if(type==PullType.webPull) playSoundAt("hbew",target,state,webGain);
			else static if(type==PullType.cagePull) playSoundAt("hgac",target,state,cageGain);
			else static assert(0);
		}
		static if(type==PullType.cagePull){
			if(pullFrames<=0){
				boltScale=min(maxBoltScale,boltScale+boltScaleGrowth/updateFPS);
				if(frame%changeShapeDelay==0) changeShape(state);
			}
		}
		auto keep=frame<numShootFrames||state.movingObjectById!((ref obj,state){
			if(!obj.creatureState.mode.isPulling) return false;
			if(!isValidAttackTarget(target,state)) return false;
			bool pullNow=obj.hasShootTick(state) && obj.animationState==obj.pullAnimation;
			if(pullNow&&!checkAbility(obj,ability,centerTarget(target,state),state)) return false;
			return state.movingObjectById!((ref tobj,obj,pullNow,state){
				auto forwardDir=rotate(facingQuaternion(obj.creatureState.facing),Vector3f(0.0f,1.0f,0.0f));
				auto thread=tobj.center-((*obj).center+0.5f*forwardDir);
				auto threadDir=thread.normalized;
				auto velocity=-pullSpeed*threadDir;
				if(numPulls>=1 && boxPointDistance(tobj.hitbox,(*obj).center)<minThreadLength && (pullFrames<=0||thread.z>=-0.5f*minThreadLength))
					return false;
				if(tobj.creatureState.movement==CreatureMovement.tumbling){
					auto dist=thread.length;
					if(!tobj.creatureStats.effects.fixed && dist>1.05f*radius){
						/+auto diff=radius*threadDir-thread;
						 if(diff.lengthsqr>1.0f) diff.normalize;
						 tobj.position+=0.5f*diff;+/
						//tobj.catapult(-pullSpeed*threadDir/updateFPS,state);
						auto badSpeed=dot(threadDir,tobj.creatureState.fallingVelocity);
						/+if(badSpeed>0) tobj.creatureState.fallingVelocity-=0.5f*threadDir*badSpeed;
						 static if(type==PullType.cagePull){
							 static assert(updateFPS==60);
							 boltScale*=0.9f;
						 }+/
						if(badSpeed>1.5f) pullNow=true;
					}
					auto forwardDist=dot(forwardDir,thread);
					if(forwardDist<-0.2f*thread.z){
						auto backwardSpeed=dot(-forwardDir,tobj.creatureState.fallingVelocity);
						if(backwardSpeed>0.2f*tobj.creatureState.fallingVelocity.z) pullNow=true;
					}
				}
				radius=min(radius,(tobj.center-(*obj).center).length);
				if(pullNow){
					numPulls++;
					velocity.z+=5.0f*tobj.creatureStats.fallingAcceleration/updateFPS;
					//velocity.z+=0.7f*thread.length/pullSpeed*tobj.creatureStats.fallingAcceleration;
					//if(velocity.lengthsqr>pullSpeed^^2) velocity=pullSpeed*velocity.normalized;
					tobj.stunWithCooldown(stunCooldownFrames,state);
					tobj.catapult(velocity,state);
					pullFrames=numPullFrames;
					static if(type==PullType.cagePull){
						boltScale=0.0f;
						changeShape(state);
					}
				}else if(--pullFrames>0){
					//tobj.creatureState.fallingVelocity=-pullSpeed*threadDir+Vector3f(0.0f,0.0f,1.5f*tobj.creatureStats.fallingAcceleration/updateFPS);
					//tobj.creatureState.fallingVelocity.z+=tobj.creatureStats.fallingAcceleration/updateFPS;
					if(tobj.creatureState.movement==CreatureMovement.tumbling) tobj.creatureState.fallingVelocity=velocity;
					else tobj.push(velocity,state);
				}
				if(numPulls>=4 && (*obj).frame+1>=obj.sacObject.numFrames(obj.animationState)*updateAnimFactor)
					return false;
				return true;
			},()=>false)(target,&obj,pullNow,state);
		},()=>false)(creature,state);
		if(!keep){
			state.movingObjectById!((ref obj,state){
				obj.frame=0;
				obj.startIdling(state);
			},(){})(creature,state);
			if(target) state.movingObjectById!((ref tobj,state){
				static if(type==PullType.webPull) animateWebPullBreaking(tobj.hitbox,state);
				else animateCagePullBreaking(tobj.hitbox,state);
			},(){})(target,state);
			return false;
		}
		return keep;
	}
}
bool updateWebPull(B)(ref WebPull!B webPull,ObjectState!B state){ return updatePull(webPull,state); }
bool updateCagePull(B)(ref CagePull!B cagePull,ObjectState!B state){ return updatePull(cagePull,state); }

enum stickyBombSize=0.25f;
static immutable Vector3f[2] stickyBombHitbox=[-0.5f*stickyBombSize*Vector3f(1.0f,1.0f,1.0f),0.5f*stickyBombSize*Vector3f(1.0f,1.0f,1.0f)];
int stickyBombCollisionTarget(B)(Vector3f position,int side,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state,int side){
		return entry.isProjectileObstacle&&state.isValidTarget(entry.id,TargetType.building)&&state.staticObjectById!((ref obj,side)=>obj.side(state)!=side,()=>false)(entry.id,side)||
			state.isValidTarget(entry.id,TargetType.creature)&&state.movingObjectById!((ref obj,side)=>obj.side!=side&&obj.creatureState.mode.canBeStickyBombed,()=>false)(entry.id,side);
	}
	return collisionTarget!(stickyBombHitbox,filter)(side,position,state,side);
}
bool updateStickyBomb(B)(ref StickyBomb!B stickyBomb,ObjectState!B state){
	with(stickyBomb){
		++frame;
		bool vanish(){
			velocity=Vector3f(0.0f,0.0f,0.0f);
			scale-=1.0f/(fadeTime*updateFPS);
			if(scale<=0.0f)
				return false;
			return true;
		}
		if(target){
			auto keep=++infectionTime<=updateFPS*ability.duration;
			if(!keep||state.movingObjectById!((ref obj,side)=>!obj.creatureState.mode.canBeStickyBombed,()=>true)(target,side)){
				keep=false;
				if(scale==1.0f) state.movingObjectById!((ref obj){ obj.creatureStats.effects.numStickyBombs-=1; },(){})(target);
			}
			if(!keep) return vanish();
			return true;
		}else{
			if(scale==1.0f){
				position+=velocity/updateFPS;
				velocity.z-=ability.fallingAcceleration/updateFPS;
			}else return vanish();
			if(state.isOnGround(position)){
				auto height=state.getGroundHeight(position);
				if(height>=position.z){
					position.z=height;
					return vanish();
				}
			}
			if(auto collisionTarget=stickyBombCollisionTarget(position,side,state)){
				auto targetPositionTargetRotation=state.movingObjectById!((ref obj){
						obj.creatureStats.effects.numStickyBombs+=1;
						return tuple(obj.position,obj.rotation);
					},()=>Tuple!(Vector3f,Quaternionf).init)(collisionTarget);
				auto targetPosition=targetPositionTargetRotation[0], targetRotation=targetPositionTargetRotation[1];
				if(!isNaN(targetPosition.x)){
					playSoundAt("hlab",position,state,1.0f); // TODO: move sound with projectile
					position=rotate(targetRotation.conj(),position-targetPosition);
					target=collisionTarget;
				}else return vanish();
			}
			return true;
		}
	}
}

enum oilProjectileSize=1.0f;
static immutable Vector3f[2] oilProjectileHitbox=[-0.5f*oilProjectileSize*Vector3f(1.0f,1.0f,1.0f),0.5f*oilProjectileSize*Vector3f(1.0f,1.0f,1.0f)];
int oilProjectileCollisionTarget(B)(Vector3f position,int creature,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state,int creature){
		if(entry.id==creature) return false;
		return entry.isProjectileObstacle&&state.movingObjectById!((ref obj)=>obj.creatureState.mode.canBeOiled,()=>false)(entry.id);
	}
	return collisionTarget!(oilProjectileHitbox,filter)(-1,position,state,creature);
}

void oilExplosion(B)(ref OilProjectile!B oilProjectile,ObjectState!B state){
	with(oilProjectile){
		static bool callback(int target,int attacker,int attackerSide,SacSpell!B ability,ObjectState!B state){
			auto canOil=state.movingObjectById!((ref obj){
				auto ok=!obj.creatureStats.effects.oiled&&obj.creatureState.mode.canBeOiled;
				if(ok) obj.creatureStats.effects.oiled=true;
				return ok;
			},()=>false)(target);
			if(canOil) state.addEffect(Oil!B(target,attacker,attackerSide,ability));
			return false;
		}
		dealDamageAt!callback(0,0.0f,ability.effectRange,creature,side,position,DamageMod.none,state,creature,side,ability,state);
		// TODO: scar
		enum numParticles3=100;
		auto sacParticle3=SacParticle!B.get(ParticleType.oil);
		foreach(i;0..numParticles3){
			auto direction=state.uniformDirection();
			auto velocity=state.uniform(5.0f,10.0f)*direction;
			auto scale=state.uniform(1.0f,2.5f);
			auto lifetime=95;
			auto frame=0;
			state.addParticle(Particle!B(sacParticle3,position,velocity,scale,lifetime,frame));
		}
	}
}

bool updateOilProjectile(B)(ref OilProjectile!B oilProjectile,ObjectState!B state){
	with(oilProjectile){
		++frame;
		position+=velocity/updateFPS;
		velocity.z-=ability.fallingAcceleration/updateFPS;
		if(state.isOnGround(position)){
			auto height=state.getGroundHeight(position);
			if(height>=position.z){
				position.z=height;
				oilExplosion(oilProjectile,state);
				return false;
			}
		}
		if(oilProjectileCollisionTarget(position,creature,state)){
			oilExplosion(oilProjectile,state);
			return false;
		}
		return true;
	}
}

void igniteOil(B)(ref MovingObject!B object,ObjectState!B state){
	if(object.creatureStats.effects.oiled)
		object.creatureStats.effects.oilStatus=OilStatus.ignited;
}
void igniteOil(B)(ref Oil!B oil,ObjectState!B state){
	with(oil){
		static bool callback(int target,int attacker,int attackerSide,ObjectState!B state){
			setAblaze(target,updateFPS,false,0.0f,attacker,attackerSide,DamageMod.none,state);
			return true;
		}
		auto positionScale=state.movingObjectById!((ref obj)=>tuple(obj.center,obj.getScale.length),()=>Tuple!(Vector3f,float).init)(creature);
		auto position=positionScale[0], scale=positionScale[1];
		if(isNaN(position.x)) return;
		dealSplashRangedDamageAt!callback(0,ability,ability.damageRange,attacker,attackerSide,position,DamageMod.ignite,state,attacker,attackerSide,state);
		animateFireballExplosion(position,state,scale);
	}
}

bool updateOil(B)(ref Oil!B oil,ObjectState!B state){
	with(oil){
		auto status=++frame<=updateFPS*ability.duration?state.movingObjectById!((ref obj,state){
			if(!obj.isWizard) obj.clearOrderQueue(state);
			return obj.creatureState.mode.canBeOiled?obj.creatureStats.effects.oilStatus:OilStatus.none;
		},()=>OilStatus.none)(creature,state):OilStatus.none;
		if(status==OilStatus.ignited){
			igniteOil(oil,state);
			state.movingObjectById!((ref obj){ obj.creatureStats.effects.oiled=false; },(){})(creature);
			return false;
		}
		if(status!=OilStatus.oiled){
			if(alpha==1.0f) state.movingObjectById!((ref obj){ obj.creatureStats.effects.oiled=false; },(){})(creature);
			alpha-=1.0f/(fadeTime*updateFPS);
			if(alpha<=0.0f)
				return false;
		}
		return true;
	}
}

bool updateHealingShower(B)(ref HealingShower!B healingShower,ObjectState!B state){
	with(healingShower){
		static bool callback(int target,int side,SacSpell!B ability,ObjectState!B state){
			if(state.movingObjectById!((ref obj)=>obj.side,()=>-1)(target)==side)
				heal(target,ability,state);
			return false;
		}
		dealSplashSpellDamageAt!callback(0,ability,ability.effectRange,id,side,boxCenter(hitbox),DamageMod.none,state,side,ability,state);
		enum numParticles=128;
		auto sacParticle=SacParticle!B.get(ParticleType.rainbowParticle);
		auto center=boxCenter(hitbox);
		foreach(i;0..numParticles){
			auto position=state.uniform(scaleBox(hitbox,0.9f));
			//auto velocity=1.5f*state.uniform(0.5f,2.0f)*Vector3f(position.x-center.x,position.y-center.y,2.0f);
			auto velocity=1.5f*state.uniform(0.5f,2.0f)*Vector3f(state.uniform(hitbox[0].x,hitbox[1].x)-center.x,state.uniform(hitbox[0].y,hitbox[1].y)-center.y,2.5f);
			auto scale=state.uniform(0.5f,1.5f);
			int lifetime=63;
			int frame=0;
			state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
		}
		return false;
	}
}

bool updateProtector(B)(ref Protector!B protector,ObjectState!B state){
	if(!state.isValidTarget(protector.id,TargetType.creature)) return false;
	static void applyProtector(ref MovingObject!B object,SacSpell!B ability,ObjectState!B state){
		auto lifeShield=SacSpell!B.get(SpellTag.lifeShield);
		static void applyShield(ref CenterProximityEntry entry,int id,int side,SacSpell!B lifeShield,ObjectState!B state){
			if(entry.isStatic||side!=entry.side||id==entry.id||!state.isValidTarget(entry.id,TargetType.creature)) return;
			static void doIt(ref MovingObject!B object,SacSpell!B lifeShield,ObjectState!B state){
				if(object.isWizard) return;
				object.lifeShield(lifeShield,state);
			}
			state.movingObjectById!(doIt,(){})(entry.id,lifeShield,state);
		}
		state.proximity.eachInRange!applyShield(object.center,ability.effectRange,object.id,object.side,lifeShield,state);
	}
	state.movingObjectById!(applyProtector,(){})(protector.id,protector.ability,state);
	return false;
}

bool updateAppearance(B)(ref Appearance appearance,ObjectState!B state){
	with(appearance){
		if(!state.isValidTarget(id,TargetType.creature)) return false;
		updateRenderMode(id,state);
		++frame;
		state.setAlpha(id,(float(frame)/lifetime),1.0f);
		if(frame>=lifetime){
			state.movingObjectById!((ref object){
				object.creatureStats.effects.appearing=false;
			},(){})(id);
			updateRenderMode(id,state);
			return false;
		}
		return true;
	}
}

bool updateDisappearance(B)(ref Disappearance disappearance,ObjectState!B state){
	with(disappearance){
		if(!state.isValidTarget(id,TargetType.creature)) return false;
		updateRenderMode(id,state);
		++frame;
		state.setAlpha(id,(float(lifetime-frame)/lifetime),1.0f);
		if(frame>=lifetime){
			state.movingObjectById!((ref object,state){ if(object.isWizard) lose(object.side,state); },(){})(id,state);
			state.removeLater(id);
			return false;
		}
		return true;
	}
}

bool updateAltarDestruction(B)(ref AltarDestruction altarDestruction,ObjectState!B state){
	with(altarDestruction){
		if(frame==0){
			if(!manafount) manafount=makeManafount(position,AdditionalBuildingFlags.inactive,state);
			foreach(id;chain(pillars[],stalks[])) if(id) state.setRenderMode!(StaticObject!B,RenderMode.transparent)(id);
			if(shrine) state.setRenderMode!(StaticObject!B,RenderMode.transparent)(shrine);
			state.addEffect(ScreenShake(position,disappearDuration+2*updateFPS,2.0f,100.0f));
		}
		++frame;
		if(frame<=disappearDuration+floatDuration){
			if(ring) state.staticObjectById!((ref ring,altarDestruction,state){
				if(frame%wiggleFrames==0){
					auto frame=altarDestruction.frame;
					float progress=float(frame)/(disappearDuration+floatDuration);
					altarDestruction.oldRotation=altarDestruction.newRotation;
					altarDestruction.newRotation=facingQuaternion(2.0f*pi!float*progress)*rotationBetween(Vector3f(0.0f,0.0f,1.0f),(Vector3f(0.0f,0.0f,1.0f)+0.4f*(0.4f+0.6f*progress)^^2*state.uniformDirection()).normalized);
				}
				static if(wiggleFrames==1) ring.rotation=newRotation;
				else ring.rotation=slerp(altarDestruction.oldRotation,altarDestruction.newRotation,float(frame%wiggleFrames)/wiggleFrames);
			},(){})(ring,&altarDestruction,state);
		}
		if(frame<=disappearDuration){
			float progress=float(frame)/disappearDuration;
			foreach(id;pillars) if(id) state.setThresholdZ(id,(pillarHeight+structureCastingGradientSize)*(1.0f-progress)+-structureCastingGradientSize*progress);
			foreach(id;stalks) if(id) state.setThresholdZ(id,(stalkHeight+structureCastingGradientSize)*(1.0f-progress)+-structureCastingGradientSize*progress);
			if(shrine) state.setThresholdZ(shrine,(shrineHeight+structureCastingGradientSize)*(1.0f-progress)+-structureCastingGradientSize*progress);
			if(frame==disappearDuration){
				state.buildingById!((ref mfnt,state){ if(!mfnt.top) mfnt.activate(state); },(){})(manafount,state);
				state.staticObjectById!((ref ring,state)=>state.buildingById!((ref altar){ swap(altar.componentIds[0],altar.componentIds[$-1]); altar.componentIds.length=1; },(){})(ring.buildingId),(){})(ring,state);
				foreach(id;pillars) if(id) state.removeObject(id);
				foreach(id;stalks) if(id) state.removeObject(id);
				if(shrine) state.removeObject(shrine);
				shrine=0;
				pillars[]=0;
				stalks[]=0;
			}
		}else if(frame<=disappearDuration+floatDuration){
			float progress=float(frame-disappearDuration)/floatDuration;
			enum finalHeight=1e3f;
			if(ring) state.staticObjectById!((ref ring,position,progress){
				ring.position=position+Vector3f(0.0f,0.0f,finalHeight*progress^^2);
				ring.scale=1.0f-progress;
				ring.flags|=StaticObjectFlags.hovering;
			},(){})(ring,position,progress);
			if(frame==disappearDuration+floatDuration){
				if(ring){
					auto buildingId=state.staticObjectById!((ref ring)=>ring.buildingId,()=>0)(ring);
					state.removeObject(ring);
					ring=0;
					state.removeObject(buildingId);
				}
				position=position+Vector3f(0.0f,0.0f,finalHeight);
				animateFireballExplosion(position,state,20.0f);
			}
		}
		return frame<=disappearDuration+floatDuration+explodeDuration;
	}
}

bool updateScreenShake(B)(ref ScreenShake screenShake,ObjectState!B state){
	with(screenShake){
		auto rem=frame%shakeFrames;
		if(rem==0){
			if(frame+shakeFrames>=lifetime){
				target=Vector3f(0.0f,0.0f,0.0f);
			}else{
				auto oldDirection=target.normalized;
				auto newDirection=state.uniformDirection();
				if((oldDirection-newDirection).lengthsqr<0.25f) newDirection=-oldDirection;
				auto decay=min(1.0f,4.0f*(1.0f-(float(frame)/lifetime)^^2));
				target=strength*decay*newDirection;
			}
		}
		float relativeProgress=1.0f/(shakeFrames-rem);
		displacement=relativeProgress*target+(1.0f-relativeProgress)*displacement;
		return ++frame<lifetime;
	}
}

bool updateTestDisplacement(B)(ref TestDisplacement testDisplacement,ObjectState!B state){
	with(testDisplacement){
		++frame;
		return true;
	}
}

void updateEffects(B)(ref Effects!B effects,ObjectState!B state){
	for(int i=0;i<effects.debris.length;){
		if(!updateDebris(effects.debris[i],state)){
			effects.removeDebris(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.explosions.length;){
		if(!updateExplosion(effects.explosions[i],state)){
			effects.removeExplosion(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.fires.length;){
		if(!updateFire(effects.fires[i],state)){
			effects.removeFire(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.manaDrains.length;){
		if(!updateManaDrain(effects.manaDrains[i],state)){
			effects.removeManaDrain(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.buildingDestructions.length;){
		if(!updateBuildingDestruction(effects.buildingDestructions[i],state)){
			effects.removeBuildingDestruction(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.ghostKills.length;){
		if(!updateGhostKill(effects.ghostKills[i],state)){
			effects.removeGhostKill(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.creatureCasts.length;){
		if(!updateCreatureCasting(effects.creatureCasts[i],state)){
			effects.removeCreatureCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.structureCasts.length;){
		if(!updateStructureCasting(effects.structureCasts[i],state)){
			effects.removeStructureCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.blueRings.length;){
		if(!updateBlueRing(effects.blueRings[i],state)){
			effects.removeBlueRing(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.sacDocCastings.length;){
		if(!updateSacDocCasting(effects.sacDocCastings[i],state)){
			effects.removeSacDocCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.sacDocCarries.length;){
		if(!updateSacDocCarry(effects.sacDocCarries[i],state)){
			effects.removeSacDocCarry(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.rituals.length;){
		if(!updateRitual(effects.rituals[i],state)){
			effects.removeRitual(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.teleportCastings.length;){
		if(!updateTeleportCasting(effects.teleportCastings[i],state)){
			effects.removeTeleportCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.teleportEffects.length;){
		if(!updateTeleportEffect(effects.teleportEffects[i],state)){
			effects.removeTeleportEffect(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.teleportRings.length;){
		if(!updateTeleportRing(effects.teleportRings[i],state)){
			effects.removeTeleportRing(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.guardianCastings.length;){
		if(!updateGuardianCasting(effects.guardianCastings[i],state)){
			effects.removeGuardianCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.guardians.length;){
		if(!updateGuardian(effects.guardians[i],state)){
			effects.removeGuardian(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.speedUps.length;){
		if(!updateSpeedUp(effects.speedUps[i],state)){
			effects.removeSpeedUp(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.speedUpShadows.length;){
		if(!updateSpeedUpShadow(effects.speedUpShadows[i],state)){
			effects.removeSpeedUpShadow(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.healCastings.length;){
		if(!updateHealCasting(effects.healCastings[i],state)){
			effects.removeHealCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.heals.length;){
		if(!updateHeal(effects.heals[i],state)){
			effects.removeHeal(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.lightningCastings.length;){
		if(!updateLightningCasting(effects.lightningCastings[i],state)){
			effects.removeLightningCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.lightnings.length;){
		if(!updateLightning(effects.lightnings[i],state)){
			effects.removeLightning(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.wrathCastings.length;){
		if(!updateWrathCasting(effects.wrathCastings[i],state)){
			effects.removeWrathCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.wraths.length;){
		if(!updateWrath(effects.wraths[i],state)){
			effects.removeWrath(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.fireballCastings.length;){
		if(!updateFireballCasting(effects.fireballCastings[i],state)){
			effects.removeFireballCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.fireballs.length;){
		if(!updateFireball(effects.fireballs[i],state)){
			effects.removeFireball(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.rockCastings.length;){
		if(!updateRockCasting(effects.rockCastings[i],state)){
			effects.removeRockCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.rocks.length;){
		if(!updateRock(effects.rocks[i],state)){
			effects.removeRock(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.swarmCastings.length;){
		if(!updateSwarmCasting(effects.swarmCastings[i],state)){
			effects.removeSwarmCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.swarms.length;){
		if(!updateSwarm(effects.swarms[i],state)){
			effects.removeSwarm(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.skinOfStoneCastings.length;){
		if(!updateSkinOfStoneCasting(effects.skinOfStoneCastings[i],state)){
			effects.removeSkinOfStoneCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.skinOfStones.length;){
		if(!updateSkinOfStone(effects.skinOfStones[i],state)){
			effects.removeSkinOfStone(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.etherealFormCastings.length;){
		if(!updateEtherealFormCasting(effects.etherealFormCastings[i],state)){
			effects.removeEtherealFormCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.etherealForms.length;){
		if(!updateEtherealForm(effects.etherealForms[i],state)){
			effects.removeEtherealForm(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.fireformCastings.length;){
		if(!updateFireformCasting(effects.fireformCastings[i],state)){
			effects.removeFireformCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.fireforms.length;){
		if(!updateFireform(effects.fireforms[i],state)){
			effects.removeFireform(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.protectiveSwarmCastings.length;){
		if(!updateProtectiveSwarmCasting(effects.protectiveSwarmCastings[i],state)){
			effects.removeProtectiveSwarmCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.protectiveSwarms.length;){
		if(!updateProtectiveSwarm(effects.protectiveSwarms[i],state)){
			effects.removeProtectiveSwarm(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.airShieldCastings.length;){
		if(!updateAirShieldCasting(effects.airShieldCastings[i],state)){
			effects.removeAirShieldCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.airShields.length;){
		if(!updateAirShield(effects.airShields[i],state)){
			effects.removeAirShield(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.freezeCastings.length;){
		if(!updateFreezeCasting(effects.freezeCastings[i],state)){
			effects.removeFreezeCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.freezes.length;){
		if(!updateFreeze(effects.freezes[i],state)){
			effects.removeFreeze(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.ringsOfFireCastings.length;){
		if(!updateRingsOfFireCasting(effects.ringsOfFireCastings[i],state)){
			effects.removeRingsOfFireCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.ringsOfFires.length;){
		if(!updateRingsOfFire(effects.ringsOfFires[i],state)){
			effects.removeRingsOfFire(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.slimeCastings.length;){
		if(!updateSlimeCasting(effects.slimeCastings[i],state)){
			effects.removeSlimeCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.slimes.length;){
		if(!updateSlime(effects.slimes[i],state)){
			effects.removeSlime(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.graspingVinesCastings.length;){
		if(!updateGraspingVinesCasting(effects.graspingVinesCastings[i],state)){
			effects.removeGraspingVinesCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.graspingViness.length;){
		if(!updateGraspingVines(effects.graspingViness[i],state)){
			effects.removeGraspingVines(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.soulMoleCastings.length;){
		if(!updateSoulMoleCasting(effects.soulMoleCastings[i],state)){
			effects.removeSoulMoleCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.soulMoles.length;){
		if(!updateSoulMole(effects.soulMoles[i],state)){
			effects.removeSoulMole(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.rainbowCastings.length;){
		if(!updateRainbowCasting(effects.rainbowCastings[i],state)){
			effects.removeRainbowCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.rainbows.length;){
		if(!updateRainbow(effects.rainbows[i],state)){
			effects.removeRainbow(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.rainbowEffects.length;){
		if(!updateRainbowEffect(effects.rainbowEffects[i],state)){
			effects.removeRainbowEffect(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.chainLightningCastings.length;){
		if(!updateChainLightningCasting(effects.chainLightningCastings[i],state)){
			effects.removeChainLightningCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.chainLightningCastingEffects.length;){
		if(!updateChainLightningCastingEffect(effects.chainLightningCastingEffects[i],state)){
			effects.removeChainLightningCastingEffect(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.chainLightnings.length;){
		if(!updateChainLightning(effects.chainLightnings[i],state)){
			effects.removeChainLightning(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.animateDeadCastings.length;){
		if(!updateAnimateDeadCasting(effects.animateDeadCastings[i],state)){
			effects.removeAnimateDeadCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.animateDeads.length;){
		if(!updateAnimateDead(effects.animateDeads[i],state)){
			effects.removeAnimateDead(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.animateDeadEffects.length;){
		if(!updateAnimateDeadEffect(effects.animateDeadEffects[i],state)){
			effects.removeAnimateDeadEffect(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.eruptCastings.length;){
		if(!updateEruptCasting(effects.eruptCastings[i],state)){
			effects.removeEruptCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.erupts.length;){
		if(!updateErupt(effects.erupts[i],state)){
			effects.removeErupt(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.eruptDebris.length;){
		if(!updateEruptDebris(effects.eruptDebris[i],state)){
			effects.removeEruptDebris(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.dragonfireCastings.length;){
		if(!updateDragonfireCasting(effects.dragonfireCastings[i],state)){
			effects.removeDragonfireCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.dragonfires.length;){
		if(!updateDragonfire(effects.dragonfires[i],state)){
			effects.removeDragonfire(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.soulWindCastings.length;){
		if(!updateSoulWindCasting(effects.soulWindCastings[i],state)){
			effects.removeSoulWindCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.soulWinds.length;){
		if(!updateSoulWind(effects.soulWinds[i],state)){
			effects.removeSoulWind(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.soulWindEffects.length;){
		if(!updateSoulWindEffect(effects.soulWindEffects[i],state)){
			effects.removeSoulWindEffect(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.explosionCastings.length;){
		if(!updateExplosionCasting(effects.explosionCastings[i],state)){
			effects.removeExplosionCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.haloOfEarthCastings.length;){
		if(!updateHaloOfEarthCasting(effects.haloOfEarthCastings[i],state)){
			effects.removeHaloOfEarthCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.haloOfEarths.length;){
		if(!updateHaloOfEarth(effects.haloOfEarths[i],state)){
			effects.removeHaloOfEarth(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.rainOfFrogsCastings.length;){
		if(!updateRainOfFrogsCasting(effects.rainOfFrogsCastings[i],state)){
			effects.removeRainOfFrogsCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.rainOfFrogss.length;){
		if(!updateRainOfFrogs(effects.rainOfFrogss[i],state)){
			effects.removeRainOfFrogs(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.rainFrogs.length;){
		if(!updateRainFrog(effects.rainFrogs[i],state)){
			effects.removeRainFrog(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.demonicRiftCastings.length;){
		if(!updateDemonicRiftCasting(effects.demonicRiftCastings[i],state)){
			effects.removeDemonicRiftCasting(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.demonicRifts.length;){
		if(!updateDemonicRift(effects.demonicRifts[i],state)){
			effects.removeDemonicRift(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.demonicRiftEffects.length;){
		if(!updateDemonicRiftEffect(effects.demonicRiftEffects[i],state)){
			effects.removeDemonicRiftEffect(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.brainiacProjectiles.length;){
		if(!updateBrainiacProjectile(effects.brainiacProjectiles[i],state)){
			effects.removeBrainiacProjectile(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.brainiacEffects.length;){
		if(!updateBrainiacEffect(effects.brainiacEffects[i],state)){
			effects.removeBrainiacEffect(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.shrikeProjectiles.length;){
		if(!updateShrikeProjectile(effects.shrikeProjectiles[i],state)){
			effects.removeShrikeProjectile(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.shrikeEffects.length;){
		if(!updateShrikeEffect(effects.shrikeEffects[i],state)){
			effects.removeShrikeEffect(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.locustProjectiles.length;){
		if(!updateLocustProjectile(effects.locustProjectiles[i],state)){
			effects.removeLocustProjectile(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.spitfireProjectiles.length;){
		if(!updateSpitfireProjectile(effects.spitfireProjectiles[i],state)){
			effects.removeSpitfireProjectile(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.spitfireEffects.length;){
		if(!updateSpitfireEffect(effects.spitfireEffects[i],state)){
			effects.removeSpitfireEffect(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.gargoyleProjectiles.length;){
		if(!updateGargoyleProjectile(effects.gargoyleProjectiles[i],state)){
			effects.removeGargoyleProjectile(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.gargoyleEffects.length;){
		if(!updateGargoyleEffect(effects.gargoyleEffects[i],state)){
			effects.removeGargoyleEffect(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.earthflingProjectiles.length;){
		if(!updateEarthflingProjectile(effects.earthflingProjectiles[i],state)){
			effects.removeEarthflingProjectile(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.flameMinionProjectiles.length;){
		if(!updateFlameMinionProjectile(effects.flameMinionProjectiles[i],state)){
			effects.removeFlameMinionProjectile(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.fallenProjectiles.length;){
		if(!updateFallenProjectile(effects.fallenProjectiles[i],state)){
			effects.removeFallenProjectile(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.sylphEffects.length;){
		if(!updateSylphEffect(effects.sylphEffects[i],state)){
			effects.removeSylphEffect(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.sylphProjectiles.length;){
		if(!updateSylphProjectile(effects.sylphProjectiles[i],state)){
			effects.removeSylphProjectile(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.rangerEffects.length;){
		if(!updateRangerEffect(effects.rangerEffects[i],state)){
			effects.removeRangerEffect(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.rangerProjectiles.length;){
		if(!updateRangerProjectile(effects.rangerProjectiles[i],state)){
			effects.removeRangerProjectile(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.necrylProjectiles.length;){
		if(!updateNecrylProjectile(effects.necrylProjectiles[i],state)){
			effects.removeNecrylProjectile(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.poisons.length;){
		auto poison=effects.poisons[i];
		if(!updatePoison(poison,state)){ // careful: may append to poisons
			effects.removePoison(i);
			continue;
		}else effects.poisons[i]=poison;
		i++;
	}
	for(int i=0;i<effects.scarabProjectiles.length;){
		if(!updateScarabProjectile(effects.scarabProjectiles[i],state)){
			effects.removeScarabProjectile(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.basiliskProjectiles.length;){
		if(!updateBasiliskProjectile(effects.basiliskProjectiles[i],state)){
			effects.removeBasiliskProjectile(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.basiliskEffects.length;){
		if(!updateBasiliskEffect(effects.basiliskEffects[i],state)){
			effects.removeBasiliskEffect(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.petrifications.length;){
		if(!updatePetrification(effects.petrifications[i],state)){
			effects.removePetrification(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.tickfernoProjectiles.length;){
		if(!updateTickfernoProjectile(effects.tickfernoProjectiles[i],state)){
			effects.removeTickfernoProjectile(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.tickfernoEffects.length;){
		if(!updateTickfernoEffect(effects.tickfernoEffects[i],state)){
			effects.removeTickfernoEffect(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.vortickProjectiles.length;){
		if(!updateVortickProjectile(effects.vortickProjectiles[i],state)){
			effects.removeVortickProjectile(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.vortickEffects.length;){
		if(!updateVortickEffect(effects.vortickEffects[i],state)){
			effects.removeVortickEffect(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.vortexEffects.length;){
		if(!updateVortexEffect(effects.vortexEffects[i],state)){
			effects.removeVortexEffect(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.squallProjectiles.length;){
		if(!updateSquallProjectile(effects.squallProjectiles[i],state)){
			effects.removeSquallProjectile(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.squallEffects.length;){
		if(!updateSquallEffect(effects.squallEffects[i],state)){
			effects.removeSquallEffect(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.pushbacks.length;){
		if(!updatePushback(effects.pushbacks[i],state)){
			effects.removePushback(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.flummoxProjectiles.length;){
		if(!updateFlummoxProjectile(effects.flummoxProjectiles[i],state)){
			effects.removeFlummoxProjectile(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.pyromaniacRockets.length;){
		if(!updatePyromaniacRocket(effects.pyromaniacRockets[i],state)){
			effects.removePyromaniacRocket(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.gnomeEffects.length;){
		if(!updateGnomeEffect(effects.gnomeEffects[i],state)){
			effects.removeGnomeEffect(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.poisonDarts.length;){
		if(!updatePoisonDart(effects.poisonDarts[i],state)){
			effects.removePoisonDart(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.mutantProjectiles.length;){
		if(!updateMutantProjectile(effects.mutantProjectiles[i],state)){
			effects.removeMutantProjectile(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.rockForms.length;){
		if(!updateRockForm(effects.rockForms[i],state)){
			effects.removeRockForm(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.stealths.length;){
		if(!updateStealth(effects.stealths[i],state)){
			effects.removeStealth(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.lifeShields.length;){
		if(!updateLifeShield(effects.lifeShields[i],state)){
			effects.removeLifeShield(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.divineSights.length;){
		if(!updateDivineSight(effects.divineSights[i],state)){
			effects.removeDivineSight(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.steamClouds.length;){
		if(!updateSteamCloud(effects.steamClouds[i],state)){
			effects.removeSteamCloud(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.poisonClouds.length;){
		if(!updatePoisonCloud(effects.poisonClouds[i],state)){
			effects.removePoisonCloud(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.blightMites.length;){
		if(!updateBlightMite(effects.blightMites[i],state)){
			effects.removeBlightMite(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.lightningCharges.length;){
		if(!updateLightningCharge(effects.lightningCharges[i],state)){
			effects.removeLightningCharge(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.webPulls.length;){
		if(!updateWebPull!B(effects.webPulls[i],state)){
			effects.removeWebPull(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.cagePulls.length;){
		if(!updateCagePull!B(effects.cagePulls[i],state)){
			effects.removeCagePull(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.stickyBombs.length;){
		if(!updateStickyBomb(effects.stickyBombs[i],state)){
			effects.removeStickyBomb(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.oilProjectiles.length;){
		if(!updateOilProjectile(effects.oilProjectiles[i],state)){
			effects.removeOilProjectile(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.oils.length;){
		if(!updateOil(effects.oils[i],state)){
			effects.removeOil(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.healingShowers.length;){
		if(!updateHealingShower(effects.healingShowers[i],state)){
			effects.removeHealingShower(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.protectors.length;){
		if(!updateProtector(effects.protectors[i],state)){
			effects.removeProtector(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.appearances.length;){
		if(!updateAppearance(effects.appearances[i],state)){
			effects.removeAppearance(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.disappearances.length;){
		if(!updateDisappearance(effects.disappearances[i],state)){
			effects.removeDisappearance(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.altarDestructions.length;){
		if(!updateAltarDestruction(effects.altarDestructions[i],state)){
			effects.removeAltarDestruction(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.screenShakes.length;){
		if(!updateScreenShake(effects.screenShakes[i],state)){
			effects.removeScreenShake(i);
			continue;
		}
		i++;
	}
	for(int i=0;i<effects.testDisplacements.length;){
		if(!updateTestDisplacement(effects.testDisplacements[i],state)){
			effects.removeTestDisplacement(i);
			continue;
		}
		i++;
	}
}

void explosionParticles(B)(Vector3f position,ObjectState!B state){
	enum numParticles=200;
	auto sacParticle1=SacParticle!B.get(ParticleType.explosion);
	auto sacParticle2=SacParticle!B.get(ParticleType.explosion2);
	foreach(i;0..numParticles){
		auto direction=state.uniformDirection();
		auto velocity=state.uniform(1.5f,6.0f)*direction;
		auto scale=1.0f;
		auto lifetime=31;
		auto frame=0;
		state.addParticle(Particle!B(i<numParticles/2?sacParticle1:sacParticle2,position,velocity,scale,lifetime,frame));
	}
}

void explosionAnimation(B)(Vector3f position,ObjectState!B state,float gain=10.0f){
	playSoundAt("pxbf",position,state,gain);
	state.addEffect(Explosion!B(position,0.0f,30.0f,40.0f,0));
	state.addEffect(Explosion!B(position,0.0f,5.0f,10.0f,0));
	explosionParticles(position,state);
}

void animateDebris(B)(Vector3f position,ObjectState!B state,int numDebris=35){
	foreach(i;0..numDebris){
		auto angle=state.uniform(-pi!float,pi!float);
		auto velocity=(20.0f+state.uniform(-5.0f,5.0f))*Vector3f(cos(angle),sin(angle),state.uniform(0.5f,2.0f)).normalized;
		auto rotationSpeed=2*pi!float*state.uniform(0.5f,2.0f)/updateFPS;
		auto rotationAxis=state.uniformDirection();
		auto rotationUpdate=rotationQuaternion(rotationAxis,rotationSpeed);
		auto debris=Debris!B(position,velocity,rotationUpdate,Quaternionf.identity());
		state.addEffect(debris);
	}
}

void animateAsh(B)(Vector3f position,ObjectState!B state,int numParticles=300){
	auto sacParticle=SacParticle!B.get(ParticleType.ashParticle);
	foreach(i;0..numParticles){
		auto direction=state.uniformDirection();
		auto velocity=state.uniform(15.0f,30.0f)*direction;
		//auto scale=state.uniform(1.5f,3.0f);
		auto scale=state.uniform(1.75f,4.0f);
		auto lifetime=95;
		auto frame=0;
		state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
	}
}

void destructionAnimation(B)(char[4] animation,Vector3f position,ObjectState!B state){
	switch(animation){
		case "1tuh":
			animateAsh(position,state);
			explosionAnimation(position,state);
			break;
		default:
			animateDebris(position,state);
			explosionAnimation(position,state);
			break;
	}
}

void setAblaze(B)(int target,int lifetime,bool ranged,float damage,int attacker,int side,DamageMod damageMod,ObjectState!B state){
	state.addEffect(Fire!B(target,lifetime,ranged?damage/lifetime:0.0f,!ranged?damage/lifetime:0.0f,0.0f,attacker,side,damageMod));
}
void setAblazeWithManaDrain(B)(int target,int lifetime,float damage,float manaDrain,int attacker,int side,DamageMod damageMod,ObjectState!B state){
	state.addEffect(Fire!B(target,lifetime,damage/lifetime,0.0f,manaDrain/lifetime,attacker,side,damageMod));
}

void updateCommandCones(B)(ref CommandCones!B commandCones, ObjectState!B state){
	with(commandCones) foreach(i;0..cast(int)cones.length){
		foreach(j;0..cast(int)cones[i].length){
			for(int k=0;k<cones[i][j].length;){
				if(cones[i][j][k].lifetime<=0){
					removeCommandCone(i,cast(CommandConeColor)j,k);
					continue;
				}
				scope(success) k++;
				cones[i][j][k].lifetime-=1;
			}
		}
	}
}

void animateManafount(B)(Vector3f location, ObjectState!B state){
	auto sacParticle=SacParticle!B.get(ParticleType.manafount);
	auto globalAngle=1.5f*2*pi!float/updateFPS*(state.frame+1000*location.x+location.y);
	auto globalMagnitude=0.25f;
	auto globalDisplacement=globalMagnitude*Vector3f(cos(globalAngle),sin(globalAngle),0.0f);
	auto center=location+globalDisplacement;
	static assert(updateFPS==60); // TODO: fix
	foreach(j;0..2){
		auto displacementAngle=state.uniform(-pi!float,pi!float);
		auto displacementMagnitude=state.uniform(0.0f,0.5f);
		auto displacement=displacementMagnitude*Vector3f(cos(displacementAngle),sin(displacementAngle),0.0f);
		foreach(k;0..2){
			auto position=center+displacement;
			auto angle=state.uniform(-pi!float,pi!float);
			auto velocity=(20.0f+state.uniform(-5.0f,5.0f))*Vector3f(cos(angle),sin(angle),state.uniform(2.0f,4.0f)).normalized;
			auto lifetime=cast(int)(sqrt(sacParticle.numFrames*5.0f)*state.uniform(0.0f,1.0f))^^2;
			auto scale=1.0f;
			auto frame=0;
			state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
		}
	}
}

void animateManalith(B)(Vector3f location, int side, ObjectState!B state){
	auto sacParticle=state.sides.manaParticle(side);
	auto globalAngle=2*pi!float/updateFPS*(state.frame+1000*location.x+location.y);
	auto globalMagnitude=0.5f;
	auto globalDisplacement=globalMagnitude*Vector3f(cos(globalAngle),sin(globalAngle),0.0f);
	auto center=location+globalDisplacement;
	static assert(updateFPS==60); // TODO: fix
	foreach(j;0..4){
		auto displacementAngle=state.uniform(-pi!float,pi!float);
		auto displacementMagnitude=3.5f*state.uniform(0.0f,1.0f)^^2;
		auto displacement=displacementMagnitude*Vector3f(cos(displacementAngle),sin(displacementAngle),0.0f);
		auto position=center+displacement;
		auto velocity=(15.0f+state.uniform(-5.0f,5.0f))*Vector3f(0.0f,0.0f,state.uniform(2.0f,4.0f)).normalized;
		auto scale=1.0f;
		auto lifetime=cast(int)(sacParticle.numFrames*5.0f-0.7*sacParticle.numFrames*displacementMagnitude*state.uniform(0.0f,1.0f)^^2);
		auto frame=0;
		state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
	}
}

void animateShrine(B)(bool active,Vector3f location, int side, ObjectState!B state){
	auto sacParticle=state.sides.shrineParticle(side);
	auto globalAngle=2*pi!float/updateFPS*(state.frame+1000*location.x+location.y);
	auto globalMagnitude=0.1f;
	auto globalDisplacement=globalMagnitude*Vector3f(cos(globalAngle),sin(globalAngle),0.0f);
	auto center=location+globalDisplacement;
	static assert(updateFPS==60); // TODO: fix
	foreach(j;0..2){
		auto displacementAngle=state.uniform(-pi!float,pi!float);
		auto displacementMagnitude=1.0f*state.uniform(0.0f,1.0f)^^2;
		auto displacement=displacementMagnitude*Vector3f(cos(displacementAngle),sin(displacementAngle),0.0f);
		auto position=center+displacement;
		auto velocity=(active?2.5f:1.0f)*(1.5f+state.uniform(-0.5f,0.5f))*Vector3f(0.0f,0.0f,state.uniform(2.0f,4.0f)).normalized;
		auto scale=1.0f;
		auto lifetime=cast(int)((sacParticle.numFrames*5.0f)*(1.0f+state.uniform(0.0f,1.0f)^^10));
		auto frame=0;
		state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
	}
}

void updateBuilding(B)(ref Building!B building, ObjectState!B state){
	if(building.componentIds.length==0) return;
	if(building.health!=0.0f) building.heal(building.regeneration/updateFPS,state);
	if(!(building.flags&AdditionalBuildingFlags.inactive)){
		if(building.isManafount){
			Vector3f getManafountTop(StaticObject!B obj){
				auto hitbox=obj.hitboxes[0];
				auto center=0.5f*(hitbox[0]+hitbox[1]);
				return center+Vector3f(0.0f,0.0f,0.75f);
			}
			auto position=state.staticObjectById!(getManafountTop,function Vector3f(){ assert(0); })(building.componentIds[0]);
			animateManafount(position,state);
		}else if(building.isManalith){
			Vector3f getCenter(StaticObject!B obj){
				return obj.position+Vector3f(0.0f,0.0f,15.0f);
			}
			auto position=state.staticObjectById!(getCenter,function Vector3f(){ assert(0); })(building.componentIds[0]);
			animateManalith(position,building.side,state);
		}else if(building.isShrine||building.isAltar){
			Vector3f getShrineTop(StaticObject!B obj){
				return obj.position+Vector3f(0.0f,0.0f,3.0f);
			}
			auto position=state.staticObjectById!(getShrineTop,function Vector3f(){ assert(0); })(building.componentIds[0]);
			if(building.isEtherealAltar) position.z+=95.0f;
			animateShrine(!!(building.flags&AdditionalBuildingFlags.occupied),position,building.side,state);
		}
	}
}

void updateStructure(B)(ref StaticObject!B structure, ObjectState!B state){
	if(!(structure.flags&StaticObjectFlags.hovering))
		structure.position.z=state.getGroundHeight(structure.position);
}

void animateManahoar(B)(Vector3f location, int side, float rate, ObjectState!B state){
	auto sacParticle=state.sides.manahoarParticle(side);
	auto globalAngle=2*pi!float/updateFPS*state.frame;
	auto globalMagnitude=0.05f;
	auto globalDisplacement=globalMagnitude*Vector3f(cos(globalAngle),sin(globalAngle),0.0f);
	auto center=location+globalDisplacement;
	auto noisyRate=rate*state.uniform(0.91f,1.09f);
	auto perFrame=noisyRate/updateFPS;
	auto fractional=cast(int)(1.0f/fmod(perFrame,1.0f));
	auto numParticles=cast(int)perFrame+(fractional!=0&&state.frame%fractional==0?1:0);
	foreach(j;0..numParticles){
		auto displacementAngle=state.uniform(-pi!float,pi!float);
		auto displacementMagnitude=0.15f*state.uniform(0.0f,1.0f)^^2;
		auto displacement=displacementMagnitude*Vector3f(cos(displacementAngle),sin(displacementAngle),0.0f);
		auto position=center+displacement;
		auto velocity=(1.5f+state.uniform(-0.5f,0.5f))*Vector3f(0.0f,0.0f,state.uniform(2.0f,4.0f)).normalized;
		auto scale=1.0f;
		auto lifetime=cast(int)(0.7f*(sacParticle.numFrames*5.0f-7.0f*sacParticle.numFrames*displacementMagnitude*state.uniform(0.0f,1.0f)^^2));
		auto frame=0;
		state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
	}
}


int[4] findClosestBuildings(B)(int side,Vector3f position,ObjectState!B state){ // TODO: do a single pass for all wizards?
	// [building for guardian,shrine for convert,own altar for teleport from void,enemy altar for desecrate]
	enum RType{
		building,
		shrine,
		altar,
		enemyAltar,
	}
	static struct Result{
		int[4] currentIds=0;
		float[4] currentDistances=float.infinity;
	}
	static void find(T)(ref T objects,int side,Vector3f position,int componentId,ObjectState!B state,Result* result){
		static if(is(T==StaticObjects!(B,renderMode),RenderMode renderMode)){
			bool altar=objects.sacObject.isAltar;
			bool shrine=objects.sacObject.isShrine;
			if(altar||shrine||objects.sacObject.isManalith){ // TODO: use cached indices?
				foreach(j;0..objects.length){
					import std.traits:EnumMembers;
					static foreach(k;EnumMembers!RType){{
						static if(k==RType.building){
							if(state.buildingById!((ref bldg,side)=>bldg.side!=side,()=>true)(objects.buildingIds[j],side))
								mixin(text(`goto Lnext`,k,`;`));
						}else static if(k==RType.shrine){
							if(!altar&&!shrine||componentId==-1||state.buildingById!((ref bldg,side)=>bldg.side!=side||bldg.flags&AdditionalBuildingFlags.inactive,()=>true)(objects.buildingIds[j],side))
								mixin(text(`goto Lnext`,k,`;`));
						}else static if(k==RType.altar){
							if(!altar||state.buildingById!((ref bldg,side)=>bldg.side!=side||bldg.flags&AdditionalBuildingFlags.inactive,()=>true)(objects.buildingIds[j],side))
								mixin(text(`goto Lnext`,k,`;`));
						}else{
							if(!altar||componentId==-1||state.buildingById!((ref bldg,side,state)=>state.sides.getStance(side,bldg.side)!=Stance.enemy||bldg.flags&AdditionalBuildingFlags.inactive,()=>true)(objects.buildingIds[j],side,state))
								mixin(text(`goto Lnext`,k,`;`));
						}
						auto candidateDistance=(position-objects.positions[j]).xy.lengthsqr;
						if(k==RType.building && candidateDistance>50.0f^^2) mixin(text(`goto Lnext`,k,`;`));
						if(k==RType.enemyAltar && candidateDistance>75.0f^^2) mixin(text(`goto Lnext`,k,`;`));
						if(candidateDistance<result.currentDistances[k] && (k.among(RType.building,RType.altar)||componentId==state.pathFinder.getComponentId(objects.positions[j],state))){ // TODO: is it really possible to guard over the void?
							result.currentIds[k]=objects.ids[j];
							result.currentDistances[k]=candidateDistance;
						}
					}mixin(text(`Lnext`,k,`:;`));}
				}
			}
		}
	}
	auto componentId=state.pathFinder.getComponentId(position,state);
	Result result;
	state.eachByType!find(side,position,componentId,state,&result);
	return result.currentIds;
}

bool spellbookVisible(B)(int wizardId,ObjectState!B state){
	return state.movingObjectById!((ref obj)=>!obj.isDying&&!obj.isGhost&&!obj.isDead,()=>false)(wizardId);
}
bool statsVisible(B)(int wizardId,ObjectState!B state){
	with(CreatureMode)
		return state.movingObjectById!((ref obj)=>!obj.isDying&&!obj.isDead,()=>false)(wizardId);
}

enum SpellbookSoundFlags{
	none,
	creatureTab=1,
	spellTab=2,
	structureTab=4,
}
void playSpellbookSound(B)(int side,SpellbookSoundFlags flags,char[4] tag,ObjectState!B state,float gain=1.0f){
	static if(B.hasAudio) if(playAudio) B.playSpellbookSound(side,flags,tag,gain);
}
void updateWizard(B)(ref WizardInfo!B wizard,ObjectState!B state){
	auto sidePosition=state.movingObjectById!((ref obj)=>tuple(obj.side,obj.position),()=>tuple(-1,Vector3f.init))(wizard.id);
	auto side=sidePosition[0], position=sidePosition[1];
	auto ids=side==-1?(int[4]).init:findClosestBuildings(side,position,state);
	wizard.closestBuilding=ids[0];
	wizard.closestShrine=ids[1];
	wizard.closestAltar=ids[2];
	wizard.closestEnemyAltar=ids[3];
	SpellbookSoundFlags flags;
	foreach(ref entry;wizard.spellbook.spells.data){
		bool oldReady=entry.ready;
		entry.cooldown=max(0.0f,entry.cooldown-1.0f/updateFPS);
		entry.ready=state.spellStatus!true(wizard.id,entry.spell)==SpellStatus.ready;
		if(entry.readyFrame<16*updateAnimFactor) entry.readyFrame+=1;
		if(!oldReady&&entry.ready){
			final switch(entry.spell.type){
				case SpellType.creature: flags|=SpellbookSoundFlags.creatureTab; break;
				case SpellType.spell: flags|=SpellbookSoundFlags.spellTab; break;
				case SpellType.structure: flags|=SpellbookSoundFlags.structureTab; break;
			}
			entry.readyFrame=0;
		}
	}
	if(spellbookVisible(wizard.id,state)) playSpellbookSound(side,flags,"vaps",state);
}

void addToProximity(T,B)(ref T objects, ObjectState!B state){
	auto proximity=state.proximity;
	enum isMoving=is(T==MovingObjects!(B, renderMode), RenderMode renderMode);
	enum isStatic=is(T==StaticObjects!(B, renderMode), RenderMode renderMode);
	static if(isMoving){
		foreach(j;0..objects.length){
			bool isObstacle=objects.creatureStates[j].mode.isObstacle;
			bool isVisibleToAI=objects.creatureStates[j].mode.isVisibleToAI&&!(objects.creatureStatss[j].flags&Flags.notOnMinimap)&&!objects.creatureStatss[j].effects.stealth;
			auto hitbox=objects.sacObject.hitbox(objects.rotations[j],objects.animationStates[j],objects.frames[j]/updateAnimFactor);
			auto position=objects.positions[j];
			hitbox[0]+=position;
			hitbox[1]+=position;
			bool isProjectileObstacle=objects.creatureStates[j].mode.isProjectileObstacle;
			proximity.insert(ProximityEntry(objects.ids[j],hitbox,isObstacle,isProjectileObstacle));
			int attackTargetId=0;
			if(objects.creatureAIs[j].order.command==CommandType.attack)
				attackTargetId=objects.creatureAIs[j].order.target.id;
			proximity.insertCenter(CenterProximityEntry(false,isVisibleToAI,objects.ids[j],objects.sides[j],boxCenter(hitbox),hitbox[0].z,attackTargetId));
		}
		if(objects.sacObject.isManahoar){
			static bool manahoarAbilityEnabled(CreatureMode mode){
				final switch(mode) with(CreatureMode){
					case idle,moving,spawning,takeoff,landing,meleeMoving,meleeAttacking,stunned,cower,rockForm: return true;
					case dying,dead,dissolving,preSpawning,reviving,fastReviving,pretendingToDie,playingDead,pretendingToRevive,convertReviving,thrashing: return false;
					case deadToGhost,idleGhost,movingGhost,ghostToIdle,casting,stationaryCasting,castingMoving,shooting,usingAbility,pulling,pumping,torturing: assert(0);
				}
			}
			foreach(j;0..objects.length){
				auto mode=objects.creatureStates[j].mode;
				if(!manahoarAbilityEnabled(mode)) continue;
				auto flamePosition=objects.positions[j]+rotate(objects.rotations[j],objects.sacObject.manahoarManaOffset(objects.animationStates[j],objects.frames[j]/updateAnimFactor));
				auto rate=proximity.addManahoar(objects.sides[j],objects.ids[j],objects.positions[j],state);
				animateManahoar(flamePosition,objects.sides[j],rate,state);
			}
		}
	}else static if(isStatic){ // TODO: cache those?
		foreach(j;0..objects.length){
			foreach(hitbox;objects.sacObject.hitboxes(objects.rotations[j])){
				auto position=objects.positions[j];
				hitbox[0]+=position;
				hitbox[1]+=position;
				proximity.insert(ProximityEntry(objects.ids[j],hitbox));
				auto buildingId=objects.buildingIds[j];
				// this needs to be kept in synch with isValidAttackTarget
				auto healthFlags=state.buildingById!((ref b)=>tuple(b.health,b.flags),function Tuple!(float,int){ assert(0); })(buildingId);
				auto health=healthFlags[0],flags=healthFlags[1];
				proximity.insertCenter(CenterProximityEntry(true,!(flags&Flags.notOnMinimap),objects.ids[j],sideFromBuildingId(buildingId,state),boxCenter(hitbox),hitbox[0].z,0,health==0.0f));
			}
		}
		// TODO: get rid of duplication here
		if(objects.sacObject.isManafount){
			foreach(j;0..objects.length)
				if(!(flagsFromBuildingId(objects.buildingIds[j],state)&AdditionalBuildingFlags.inactive))
					proximity.addManafount(objects.positions[j]);
		}else if(objects.sacObject.isManalith){
			foreach(j;0..objects.length)
				if(!(flagsFromBuildingId(objects.buildingIds[j],state)&AdditionalBuildingFlags.inactive))
					proximity.addManalith(sideFromBuildingId(objects.buildingIds[j],state),objects.positions[j]);
		}else if(objects.sacObject.isShrine){
			foreach(j;0..objects.length)
				if(!(flagsFromBuildingId(objects.buildingIds[j],state)&AdditionalBuildingFlags.inactive))
					proximity.addShrine(sideFromBuildingId(objects.buildingIds[j],state),objects.positions[j]);
		}else if(objects.sacObject.isAltar){
			foreach(j;0..objects.length)
				if(!(flagsFromBuildingId(objects.buildingIds[j],state)&AdditionalBuildingFlags.inactive))
					proximity.addAltar(sideFromBuildingId(objects.buildingIds[j],state),objects.positions[j]);
		}
	}else static if(is(T==Souls!B)||is(T==Buildings!B)||is(T==FixedObjects!B)||is(T==Effects!B)||is(T==Particles!(B,relative),bool relative)||is(T==CommandCones!B)){
		// do nothing
	}else static assert(0);
}

struct ProximityEntry{
	int id;
	Vector3f[2] hitbox;
	bool isObstacle=true;
	bool isProjectileObstacle=true;
}
struct ProximityEntries{
	int version_=0;
	Array!ProximityEntry entries; // TODO: be more clever here if many entries
	void insert(int version_,ProximityEntry entry){
		if(this.version_!=version_){
			entries.length=0;
			this.version_=version_;
		}
		entries~=entry;
	}
}
auto collide(alias f,T...)(ref ProximityEntries proximityEntries,int version_,Vector3f[2] hitbox,T args){
	if(proximityEntries.version_!=version_){
		proximityEntries.entries.length=0;
		proximityEntries.version_=version_;
	}
	foreach(i;0..proximityEntries.entries.length){
		if(boxesIntersect(proximityEntries.entries[i].hitbox,hitbox))
			f(proximityEntries.entries[i],args);
	}
}
Tuple!(float,ProximityEntry) collideRay(alias filter=None,T...)(ref ProximityEntries proximityEntries,int version_,Vector3f start,Vector3f direction,float limit,T args){
	if(proximityEntries.version_!=version_){
		proximityEntries.entries.length=0;
		proximityEntries.version_=version_;
	}
	auto result=tuple(float.infinity,ProximityEntry.init);
	foreach(i;0..proximityEntries.entries.length){
		static if(!is(filter==None))
			if(!filter(proximityEntries.entries[i],args))
				continue;
		auto cand=rayBoxIntersect(start,direction,proximityEntries.entries[i].hitbox,limit);
		if(cand<result[0]) result=tuple(cand,proximityEntries.entries[i]);
	}
	return result;
}

struct HitboxProximity(B){
	enum resolution=10;
	enum offMapSlack=100/resolution;
	enum size=(2560+resolution-1)/resolution+2*offMapSlack;
	static Tuple!(int,"j",int,"i") getTile(Vector3f position){
		return tuple!("j","i")(cast(int)(position.y/resolution),cast(int)(position.x/resolution)); // TODO: good resolution?
	}
	static Vector2f getVertex(int j,int i){
		return Vector2f(i*resolution,j*resolution);
	}
	ProximityEntries[size][size] data;
	ProximityEntries offMap;
	void insert(int version_,ProximityEntry entry){
		auto lowTile=getTile(entry.hitbox[0]), highTile=getTile(entry.hitbox[1]);
		if(lowTile.j+offMapSlack<0||lowTile.i+offMapSlack<0||highTile.j+offMapSlack>=size||highTile.i+offMapSlack>=size)
			offMap.insert(version_,entry);
		foreach(j;max(0,lowTile.j+offMapSlack)..min(highTile.j+offMapSlack+1,size))
			foreach(i;max(0,lowTile.i+offMapSlack)..min(highTile.i+offMapSlack+1,size))
				data[j][i].insert(version_,entry);
	}
}
auto collide(alias f,B,T...)(ref HitboxProximity!B proximity,int version_,Vector3f[2] hitbox,T args){
	with(proximity){
		auto lowTile=getTile(hitbox[0]), highTile=getTile(hitbox[1]);
		if(lowTile.j+offMapSlack<0||lowTile.i+offMapSlack<0||highTile.j+offMapSlack>=size||highTile.i+offMapSlack>=size)
			offMap.collide!f(version_,hitbox,args);
		foreach(j;max(0,lowTile.j+offMapSlack)..min(highTile.j+offMapSlack+1,size))
			foreach(i;max(0,lowTile.i+offMapSlack)..min(highTile.i+offMapSlack+1,size))
				data[j][i].collide!f(version_,hitbox,args);
	}
}
auto collideRay(alias filter=None,B,T...)(ref HitboxProximity!B proximity,int version_,Vector3f start,Vector3f direction,float limit,T args){
	with(proximity){
		auto result=tuple(float.infinity,ProximityEntry.init);
		bool updateResult(ref ProximityEntries entries){
			auto cand=entries.collideRay!filter(version_,start,direction,limit,args);
			if(cand[0]<result[0]&&cand[0]<limit){
				result=cand;
				return true;
			}
			return false;
		}
		auto tile=getTile(start);
		int dj=direction.y<0?-1:1, di=direction.x<0?-1:1;
		float current=0.0f;
		bool testOffMap=false;
		while(current<1.1f*limit&&current<result[0]&&(dj<0?tile.j+offMapSlack>=0:tile.j+offMapSlack<size)&&(di<0?tile.i+offMapSlack>=0:tile.i+offMapSlack<size)){
			if(tile.j+offMapSlack>=0&&tile.i+offMapSlack>=0&&tile.j+offMapSlack<size&&tile.i+offMapSlack<size){
				updateResult(data[tile.j+offMapSlack][tile.i+offMapSlack]);
			}else testOffMap=true;
			auto next=getVertex(tile.j+(dj==1),tile.i+(di==1));
			auto tj=(next.y-start.y)/direction.y;
			auto ti=(next.x-start.x)/direction.x;
			if(isNaN(ti)||tj<ti){
				current=tj;
				tile.j+=dj;
			}else{
				current=ti;
				tile.i+=di;
			}
		}
		if(testOffMap) updateResult(offMap);
		return result;
	}
}

struct ManaEntry{
	bool allies;
	int side;
	Vector3f position;
	float radius;
	float rate;
}
struct ManaEntries{
	int version_=0;
	Array!ManaEntry entries; // TODO: be more clever here if many entries
	mixin Assign;
	void insert(int version_,ManaEntry entry){
		if(this.version_!=version_){
			entries.length=0;
			this.version_=version_;
		}
		entries~=entry;
	}
	float manaRegenAt(B)(int version_,int side,Vector3f position,ObjectState!B state){
		if(this.version_!=version_){
			entries.length=0;
			this.version_=version_;
		}
		auto sides=state.sides;
		float rate=0.0f;
		foreach(ref entry;entries){
			auto distance=(position-entry.position).length;
			if(distance>=entry.radius) continue;
			if(entry.side!=-1&&(!entry.allies?entry.side!=side:sides.getStance(entry.side,side)!=Stance.ally)) continue;
			rate+=entry.rate;
		}
		return rate;
	}
}


struct ManaProximity(B){
	enum resolution=50;
	enum offMapSlack=100/resolution;
	enum size=(2560+resolution-1)/resolution+2*offMapSlack;
	static Tuple!(int,"j",int,"i") getTile(Vector3f position){
		return tuple!("j","i")(cast(int)(position.y/resolution),cast(int)(position.x/resolution)); // TODO: good resolution?
	}
	ManaEntries[size][size] data;
	ManaEntries offMap;
	struct ManalithEntry{
		int side;
		Vector3f position;
	}
	int manalithVersion;
	Array!ManalithEntry manaliths;
	mixin Assign;
	void addEntry(int version_,ManaEntry entry){
		auto tile=getTile(entry.position);
		if(tile.j+offMapSlack<0||tile.i+offMapSlack<0||tile.j+offMapSlack>=size||tile.i+offMapSlack>=size) offMap.insert(version_,entry);
		else data[tile.j+offMapSlack][tile.i+offMapSlack].insert(version_,entry);
	}
	void addManafount(int version_,Vector3f position){
		addEntry(version_,ManaEntry(true,-1,position,50.0f,1000.0f/30.0f));
	}
	void addManalith(int version_,int side,Vector3f position){
		if(manalithVersion!=version_){
			manaliths.length=0;
			manalithVersion=version_;
		}
		manaliths~=ManalithEntry(side,position);
		addEntry(version_,ManaEntry(true,side,position,50.0f,1000.0f/30.0f));
	}
	void addAltar(int version_,int side,Vector3f position){
		addEntry(version_,ManaEntry(true,side,position,50.0f,1000.0f/60.0f));
	}
	void addShrine(int version_,int side,Vector3f position){
		addEntry(version_,ManaEntry(true,side,position,50.0f,1000.0f/120.0f));
	}
	float addManahoar(int version_,int side,Vector3f position,ObjectState!B state){
		if(manalithVersion!=version_){
			manaliths.length=0;
			manalithVersion=version_;
		}
		float rate=0.0f;
		auto sides=state.sides;
		foreach(ref manalith;manaliths){
			if(sides.getStance(manalith.side,side)!=Stance.ally) continue;
			auto distance=(position-manalith.position).length;
			rate+=max(0.0f,min((20.0f/50.0f)*distance,(20.0f/(1000.0f-50.0f))*(1000.0f-distance)));
		}
		addEntry(version_,ManaEntry(false,side,position,40.0f,rate));
		return rate;
	}
	float manaRegenAt(int version_,int side,Vector3f position,ObjectState!B state){
		auto offset=Vector3f(50.0f,50.0f,0.0f);
		auto lowTile=getTile(position-offset), highTile=getTile(position+offset);
		float rate=0.0f;
		if(lowTile.j+offMapSlack<0||lowTile.i+offMapSlack<0||highTile.j+offMapSlack>=size||highTile.i+offMapSlack>=size)
			rate+=offMap.manaRegenAt(version_,side,position,state);
		foreach(j;max(0,lowTile.j+offMapSlack)..min(highTile.j+offMapSlack+1,size))
			foreach(i;max(0,lowTile.i+offMapSlack)..min(highTile.i+offMapSlack+1,size))
				rate+=data[j][i].manaRegenAt(version_,side,position,state);
		return rate;
	}
}

struct CenterProximityEntry{
	bool isStatic;
	bool isVisibleToAI;
	int id;
	int side;
	Vector3f position;
	float height;
	int attackTargetId=0;
	bool zeroHealth; // this information only computed for buildings at the moment
}

struct CenterProximityEntries{
	int version_=0;
	Array!CenterProximityEntry entries; // TODO: be more clever here?
	void insert(int version_,CenterProximityEntry entry){
		if(this.version_!=version_){
			entries.length=0;
			this.version_=version_;
		}
		entries~=entry;
	}
}
auto eachInRange(alias f,T...)(ref CenterProximityEntries proximity,int version_,Vector3f position,float range,T args){
	if(proximity.version_!=version_){
		proximity.entries.length=0;
		proximity.version_=version_;
	}
	foreach(ref entry;proximity.entries){
		if((entry.position-position).lengthsqr>range^^2) continue;
		f(entry,args);
	}
}

struct CenterProximity(B){
	enum resolution=50;
	enum offMapSlack=100/resolution;
	enum size=(2560+resolution-1)/resolution+2*offMapSlack;
	static Tuple!(int,"j",int,"i") getTile(Vector3f position){
		return tuple!("j","i")(cast(int)(position.y/resolution),cast(int)(position.x/resolution)); // TODO: good resolution?
	}
	CenterProximityEntries[size][size] data;
	CenterProximityEntries offMap;
	void insert(int version_,CenterProximityEntry entry){
		auto tile=getTile(entry.position);
		if(tile.j+offMapSlack<0||tile.i+offMapSlack<0||tile.j+offMapSlack>=size||tile.i+offMapSlack>=size) offMap.insert(version_,entry);
		else data[tile.j+offMapSlack][tile.i+offMapSlack].insert(version_,entry);
	}
}
auto eachInRange(alias f,B,T...)(ref CenterProximity!B proximity,int version_,Vector3f position,float range,T args){
	with(proximity){
		auto offset=Vector3f(0.5f*range,0.5f*range,0.0f);
		auto lowTile=getTile(position-offset), highTile=getTile(position+offset);
		float rate=0.0f;
		if(lowTile.j+offMapSlack<0||lowTile.i+offMapSlack<0||highTile.j+offMapSlack>=size||highTile.i+offMapSlack>=size)
			offMap.eachInRange!f(version_,position,range,args);
		foreach(j;max(0,lowTile.j+offMapSlack)..min(highTile.j+offMapSlack+1,size))
			foreach(i;max(0,lowTile.i+offMapSlack)..min(highTile.i+offMapSlack+1,size))
				data[j][i].eachInRange!f(version_,position,range,args);
		return rate;
	}
}
private static struct None;
CenterProximityEntry inRangeAndClosestTo(alias f,alias priority=None,B,T...)(ref CenterProximity!B proximity,int version_,Vector3f position,float range,Vector3f targetPosition,T args){
	enum hasPriority=!is(priority==None);
	import std.traits:ReturnType;
	struct State{
		auto entry=CenterProximityEntry.init;
		static if(hasPriority) ReturnType!((ref CenterProximityEntry entry,T args)=>priority(entry,args)) prio;
		auto distancesqr=double.infinity;
	}
	static void process(ref CenterProximityEntry entry,Vector3f targetPosition,State* state,T args){
		if(!f(entry,args)) return;
		auto distancesqr=(entry.position-targetPosition).lengthsqr;
		bool better=distancesqr<state.distancesqr;
		static if(hasPriority){
			auto prio=priority(entry,args);
			better=prio>state.prio||prio==state.prio&&better;
		}
		if(better){
			state.entry=entry;
			static if(hasPriority) state.prio=prio;
			state.distancesqr=distancesqr;
		}
	}
	State state;
	static if(is(typeof(state.prio)==float)) state.prio=-float.infinity;
	static if(is(typeof(state.prio)==double)) state.prio=-double.infinity;
	proximity.eachInRange!process(version_,position,range,targetPosition,&state,args);
	return state.entry;
}
CenterProximityEntry closestInRange(alias f,alias priority=None,B,T...)(ref CenterProximity!B proximity,int version_,Vector3f position,float range,T args){
	return proximity.inRangeAndClosestTo!(f,priority)(version_,position,range,position,args);
}


enum EnemyType{
	all,
	creature,
	building,
}

final class Proximity(B){
	int version_=0;
	bool active=false;
	void start()in{
		assert(!active);
	}do{
		active=true;
	}
	void end()in{
		assert(active);
	}do{
		active=false;
		++version_;
	}
	HitboxProximity!B hitboxes;
	void insert(ProximityEntry entry)in{
		assert(active);
	}do{
		hitboxes.insert(version_,entry);
	}
	ManaProximity!B mana;
	void addManafount(Vector3f position){
		mana.addManafount(version_,position);
	}
	void addManalith(int side,Vector3f position){
		mana.addManalith(version_,side,position);
	}
	void addShrine(int side,Vector3f position){
		mana.addShrine(version_,side,position);
	}
	void addAltar(int side,Vector3f position){
		mana.addAltar(version_,side,position);
	}
	float addManahoar(int side,int id,Vector3f position,ObjectState!B state){
		return mana.addManahoar(version_,side,position,state);
	}
	float manaRegenAt(int side,Vector3f position,ObjectState!B state){
		return mana.manaRegenAt(version_,side,position,state);
	}
	CenterProximity!B centers;
	void insertCenter(CenterProximityEntry entry)in{
		assert(active);
	}do{
		centers.insert(version_,entry);
	}
	private static bool isOfType(T...)(ref CenterProximityEntry entry,EnemyType type,ObjectState!B state,float maxHeight=float.infinity,T ignored=T.init){
		if(!entry.isVisibleToAI) return false;
		if(type==EnemyType.creature&&entry.isStatic) return false;
		if(type==EnemyType.building&&!entry.isStatic) return false;
		if(entry.zeroHealth) return false;
		if(maxHeight<float.infinity && entry.height>state.getHeight(entry.position)+maxHeight) return false;
		return true;
	}
	int closestCreatureInRange(Vector3f position,float range,ObjectState!B state,float maxHeight=float.infinity){
		return centers.closestInRange!isOfType(version_,position,range,EnemyType.creature,state,maxHeight).id;
	}
	private static bool isEnemy(alias filter=None,T...)(ref CenterProximityEntry entry,int side,EnemyType type,ObjectState!B state,float maxHeight=float.infinity,T args=T.init){
		if(!isOfType(entry,type,state,maxHeight,args)) return false;
		static if(!is(filter==None)) if(!filter(entry,args)) return false;
		return state.sides.getStance(side,entry.side)==Stance.enemy;
	}
	int closestEnemyInRange(alias filter=None,T...)(int side,Vector3f position,float range,EnemyType type,ObjectState!B state,float maxHeight=float.infinity,T args=T.init){
		return centers.closestInRange!(isEnemy!(filter,T))(version_,position,range,side,type,state,maxHeight).id;
	}
	private static bool isNonAlly(alias filter=None,T...)(ref CenterProximityEntry entry,int side,EnemyType type,ObjectState!B state,float maxHeight=float.infinity,T args=T.init){
		if(!isOfType(entry,type,state,maxHeight,args)) return false;
		static if(!is(filter==None)) if(!filter(entry,args)) return false;
		return state.sides.getStance(side,entry.side)!=Stance.ally;
	}
	int closestNonAllyInRange(alias filter=None,T...)(int side,Vector3f position,float range,EnemyType type,ObjectState!B state,float maxHeight=float.infinity,T args=T.init){
		return centers.closestInRange!(isNonAlly!(filter,T))(version_,position,range,side,type,state,maxHeight,args).id;
	}
	int lowestHealthCreatureInRange(alias filter=None,T...)(int side,int ignoredId,Vector3f position,float range,ObjectState!B state,T args){
		static bool isCreatureOfSide(ref CenterProximityEntry entry,int side,int ignoredId,ObjectState!B state,T args){
			if(entry.isStatic) return false;
			//if(entry.zeroHealth) return false;
			if(entry.id==ignoredId) return false;
			if(side!=-1&&entry.side!=side) return false;
			static if(!is(filter==None)) if(!filter(entry,args)) return false;
			return true;
		}
		static float priority(ref CenterProximityEntry entry,int side,int ignoredId,ObjectState!B state,T args){
			auto result=-state.movingObjectById!((ref obj)=>obj.creatureStats.health/obj.creatureStats.maxHealth,()=>float.infinity)(entry.id);
			return result;
		}
		return centers.closestInRange!(isCreatureOfSide,priority)(version_,position,range,side,ignoredId,state,args).id;
	}
	private static bool isPeasantShelter(ref CenterProximityEntry entry,int side,ObjectState!B state){
		if(!entry.isStatic) return false;
		if(state.sides.getStance(entry.side,side)==Stance.enemy) return false;
		return state.staticObjectById!((obj,state)=>state.buildingById!((ref bldg)=>bldg.isPeasantShelter,()=>false)(obj.buildingId),()=>false)(entry.id,state);
	}
	int closestPeasantShelterInRange(int side,Vector3f position,float range,ObjectState!B state){
		return centers.closestInRange!isPeasantShelter(version_,position,range,side,state).id;
	}
	private static int advancePriority(ref CenterProximityEntry entry,int side,EnemyType type,ObjectState!B state,float maxHeight,int id){
		if(entry.attackTargetId==id) return 1;
		return 0;
	}
	int enemyInRangeAndClosestToPreferringAttackersOf(int side,Vector3f position,float range,Vector3f targetPosition,int id,EnemyType type,ObjectState!B state,float maxHeight=float.infinity){
		return centers.inRangeAndClosestTo!(isEnemy,advancePriority)(version_,position,range,targetPosition,side,type,state,maxHeight,id).id;
	}
	int anyInRangeAndClosestTo(Vector3f position,float range,Vector3f targetPosition,int ignoredId=0){
		return centers.inRangeAndClosestTo!((ref entry,int ignoredId)=>entry.id!=ignoredId)(version_,position,range,targetPosition,ignoredId).id;
	}
	int creatureInRangeAndClosestTo(Vector3f position,float range,Vector3f targetPosition,int ignoredId=0){
		return centers.inRangeAndClosestTo!((ref entry,int ignoredId)=>!entry.isStatic&&entry.id!=ignoredId)(version_,position,range,targetPosition,ignoredId).id;
	}
}
auto collide(alias f,B,T...)(Proximity!B proximity,Vector3f[2] hitbox,T args){
	return proximity.hitboxes.collide!(f,B,T)(proximity.version_,hitbox,args);
}
auto collideRay(alias filter=None,B,T...)(Proximity!B proximity,Vector3f start,Vector3f direction,float limit,T args){
	return proximity.hitboxes.collideRay!filter(proximity.version_,start,direction,limit,args);
}
auto eachInRange(alias f,B,T...)(ref Proximity!B proximity,Vector3f position,float range,T args){
	return proximity.centers.eachInRange!(f,B,T)(proximity.version_,position,range,args);
}


import std.random: MinstdRand0;
final class ObjectState(B){ // (update logic)
	SacMap!B map;
	Sides!B sides;
	Proximity!B proximity;
	PathFinder!B pathFinder;
	Triggers!B triggers;
	float manaRegenAt(int side,Vector3f position){
		return proximity.manaRegenAt(side,position,this);
	}
	float sideDamageMultiplier(int attackerSide,int defenderSide){
		if(attackerSide==-1) return 1.0f;
		switch(sides.getStance(attackerSide,defenderSide)){
			case Stance.ally: return 0.5f; // TODO: option
			default: return 1.0f;
		}
	}
	this(SacMap!B map,Sides!B sides,Proximity!B proximity,PathFinder!B pathFinder,Triggers!B triggers){
		this.map=map;
		this.sides=sides;
		this.proximity=proximity;
		this.pathFinder=pathFinder;
		this.triggers=triggers;
		sid=SideManager!B(32);
	}
	static struct Displacement{
		ObjectState!B state;
		static Displacement opCall(ObjectState!B state){
			Displacement r;
			r.state=state;
			return r;
		}
		float opCall(float x,float y){
			float result=0.0f;
			foreach(ref td;state.obj.opaqueObjects.effects.testDisplacements){
				result+=td.displacement(x,y);
			}
			foreach(ref ec;state.obj.opaqueObjects.effects.eruptCastings){
				result+=ec.erupt.displacement(x,y);
			}
			foreach(ref e;state.obj.opaqueObjects.effects.erupts){
				result+=e.displacement(x,y);
			}
			return result;
		}
	}
	bool isOnGround(Vector3f position){
		return map.isOnGround(position);
	}
	Vector3f moveOnGround(Vector3f position,Vector3f direction){
		return map.moveOnGround(position,direction,Displacement(this));
	}
	float getGroundHeight(Vector3f position){
		return map.getGroundHeight(position,Displacement(this));
	}
	float getHeight(Vector3f position){
		return map.getHeight(position,Displacement(this));
	}
	float getGroundHeightDerivative(Vector3f position,Vector3f direction){
		return map.getGroundHeightDerivative(position,direction,Displacement(this));
	}
	OrderTarget collideRay(alias filter=None,T...)(Vector3f start,Vector3f direction,float limit,T args){
		auto landscape=map.rayIntersection(start,direction,Displacement(this),limit);
		auto tEntry=proximity.collideRay!filter(start,direction,min(limit,landscape),args);
		if(landscape<tEntry[0]) return OrderTarget(TargetType.terrain,0,start+landscape*direction);
		auto targetType=targetTypeFromId(tEntry[1].id);
		if(targetType.among(TargetType.creature,TargetType.building))
			return OrderTarget(targetType,tEntry[1].id,start+tEntry[0]*direction);
		return OrderTarget.init;
	}
	OrderTarget lineOfSight(alias filter=None,T...)(Vector3f start,Vector3f target,T args){
		return collideRay!filter(start,target-start,1.0f,args);
	}
	OrderTarget lineOfSightWithoutSide(Vector3f start,Vector3f target,int side,int intendedTarget=0){
		static bool filter(ref ProximityEntry entry,int side,int intendedTarget,ObjectState!B state){
			if(!entry.isObstacle) return false;
			if(!entry.isProjectileObstacle) return false;
			if(entry.id==intendedTarget) return true;
			return state.objectById!((obj,side,state)=>.side(obj,state)!=side)(entry.id,side,state);
		}
		return lineOfSight!filter(start,target,side,intendedTarget,this);
	}
	bool hasLineOfSightTo(Vector3f start,Vector3f target,int ignoredId,int targetId){
		static bool filter(ref ProximityEntry entry,int id){ return entry.isObstacle&&entry.isProjectileObstacle&&entry.id!=id; }
		auto result=lineOfSight!filter(start,target,ignoredId);
		return result.type==TargetType.none||result.type.among(TargetType.creature,TargetType.building,TargetType.soul)&&result.id==targetId;
	}
	bool hasHitboxLineOfSightTo(Vector3f[2] hitbox,Vector3f start,Vector3f target,int ignoredId,int targetId){
		bool hasLineOfSight=true;
		foreach(i;0..2){
			foreach(j;0..2){
				foreach(k;0..2){
					auto offset=Vector3f(hitbox[i].x,hitbox[j].y,hitbox[k].z);
					hasLineOfSight&=hasLineOfSightTo(start+offset,target+offset,ignoredId,targetId);
				}
			}
		}
		return hasLineOfSight;
	}
	bool findPath(ref Array!Vector3f path,Vector3f start,Vector3f target,float radius){
		return pathFinder.findPath(path,start,target,radius,this);
	}
	int frame=0;
	auto rng=MinstdRand0(1); // TODO: figure out what rng to use
	// @property uint hash(){ return rng.tupleof[0]; } // rng seed as proxy for state hash.
	@property uint hash(){
		import serialize_;
		return this.crc32;
	}
	int uniform(int n){
		import std.random: uniform;
		return uniform(0,n,rng);
	}
	T uniform(string bounds="[]",T)(T a,T b){
		import std.random: uniform;
		return uniform!bounds(min(a,b),max(a,b),rng);
	}
	T normal(T=float)(){
		enum n=10;
		T r=0;
		enum T sqrt3n=sqrt(3.0f)/n;
		foreach(i;0..n) r+=uniform(T(-sqrt3n),T(sqrt3n));
		return r;
	}
	Vector!(T,n) uniform(string bounds="[]",T,int n)(Vector!(T,n)[2] box){
		Vector!(T,n) r;
		foreach(i,ref x;r) x=this.uniform(box[0][i],box[1][i]);
		return r;
	}
	Vector!(T,n) uniformDirection(T=float,int n=3)(){
		// TODO: fix bias
		static if(n==2) return Vector2f(uniform(-1.0f,1.0f),uniform(-1.0f,1.0f)).normalized;
		else return Vector3f(uniform(-1.0f,1.0f),uniform(-1.0f,1.0f),uniform(-1.0f,1.0f)).normalized;
	}
	Vector!(T,n) uniformDisk(T=float,int n=3)(Vector!(T,n) position,float radius){
		Vector!(T,n)[2] box=[position-radius,position+radius];
		Vector!(T,n) r;
		do r=uniform!("[]")(box);
		while((r-position).lengthsqr>radius^^2);
		return r;
	}
	void copyFrom(ObjectState!B rhs){
		frame=rhs.frame;
		rng=rhs.rng;
		obj=rhs.obj;
		sid=rhs.sid;
	}
	void updateFrom(ObjectState!B rhs,Command!B[] frameCommands){
		copyFrom(rhs);
		update(frameCommands);
	}
	void applyCommand(Command!B command){
		if(!command.isApplicable(this)) return;
		bool success=true;
		scope(success) if(success){
			int whichClick=uniform(2);
			if(command.type.hasClickSound) playSound(command.side,commandAppliedSoundTags[whichClick],this);
			command.speakCommand(this);
		}
		static bool applyOrder(Command!B command,ObjectState!B state,bool updateFormation=false,Vector3f position=Vector3f.init,Vector2f formationOffset=Vector2f(0.0f,0.0f)){
			assert(command.type.among(CommandType.setFormation,CommandType.useAbility)||command.target.type.among(TargetType.terrain,TargetType.creature,TargetType.building));
			if(!command.creature){
				int[Formation.max+1] num;
				Vector2f formationScale=Vector2f(1.0f,1.0f);
				foreach(selectedId;state.getSelection(command.side).creatureIds){
					if(!selectedId) break;
					static get(ref MovingObject!B object,ObjectState!B state){
						auto hitbox=object.sacObject.largeHitbox(Quaternionf.identity(),AnimationState.stance1,0);
						auto scale=hitbox[1].xy-hitbox[0].xy;
						return tuple(object.creatureAI.formation,scale);
					}
					auto curFormationCurScale=state.movingObjectById!(get,()=>Tuple!(Formation,Vector2f).init)(selectedId,state);
					auto curFormation=curFormationCurScale[0],curScale=curFormationCurScale[1];
					if(isNaN(curScale.x)) return false;
					if(curScale.x>formationScale.x) formationScale.x=curScale.x;
					if(curScale.y>formationScale.y) formationScale.y=curScale.y;
					num[curFormation]+=1;
				}
				if(!updateFormation){
					// command.formation=cast(Formation)iota(0,Formation.max+1).maxElement!(f=>num[f]); // does not work. why?
					command.formation=Formation.line;
					int maxNum=0;
					foreach(i;0..Formation.max+1)
						if(num[i]>num[command.formation])
							command.formation=cast(Formation)i;
				}
				bool success=false;
				if(command.type==CommandType.retreat){
					static void retreat(ref MovingObject!B obj,Command!B command,ObjectState!B state,bool* success){
						if(obj.isWizard) return;
						command.creature=obj.id;
						Order ord;
						ord.command=command.type;
						ord.target=OrderTarget(command.target);
						obj.order(ord,command.queueing,state,command.side);
						*success|=true;
					}
					state.eachMovingOfSide!retreat(command.side,command,state,&success);
				}else{
					auto selection=state.getSelection(command.side);
					auto ids=selection.creatureIds[].filter!(x=>x!=command.target.id);
					Vector3f[numCreaturesInGroup] positions,targetPositions;
					Vector2f[numCreaturesInGroup] formationOffsets;
					if(!command.type.among(CommandType.setFormation,CommandType.useAbility)){
						auto targetScale=command.target.id!=0?state.objectById!((obj)=>getScale(obj))(command.target.id):Vector2f(0.0f,0.0f);
						formationOffsets=getFormationOffsets(ids,command.type,command.formation,formationScale,targetScale);
						int i=0;
						foreach(selectedId;ids){
							if(!selectedId) break;
							if(command.type==CommandType.guard && command.target.id){
								auto targetPositionTargetFacing=state.movingObjectById!((obj)=>tuple(obj.position,obj.creatureState.facing), ()=>tuple(command.target.position,command.targetFacing))(command.target.id);
								auto targetPosition=targetPositionTargetFacing[0], targetFacing=targetPositionTargetFacing[1];
								targetPositions[i]=getTargetPosition(targetPosition,targetFacing,formationOffsets[i],state);
							}else targetPositions[i]=command.getTargetPosition(formationOffsets[i],state);
							positions[i]=state.movingObjectById!((obj)=>obj.position,()=>Vector3f.init)(selectedId);
							i++;
						}
						int numCreatures=i;
						// greedily match creatures to offsets
						Tuple!(float,int,"pos",int,"tpos")[numCreaturesInGroup^^2] distances;
						foreach(j;0..numCreatures){
							foreach(k;0..numCreatures){
								auto distanceSqr=(positions[j]-targetPositions[k]).lengthsqr;
								assert(!isNaN(distanceSqr),text(command.type," ",j," ",k," ",positions," ",targetPositions));
								distances[j*numCreatures+k]=tuple(distanceSqr,j,k);
							}
						}
						sort(distances[0..numCreatures^^2]);
						bool[numCreaturesInGroup] matched,tmatched;
						i=0;
						auto origTargets=targetPositions;
						auto origOffsets=formationOffsets;
						for(int j=0;i<numCreatures;j++){
							if(matched[distances[j].pos]) continue;
							if(tmatched[distances[j].tpos]) continue;
							targetPositions[distances[j].pos]=origTargets[distances[j].tpos];
							formationOffsets[distances[j].pos]=origOffsets[distances[j].tpos];
							matched[distances[j].pos]=true;
							tmatched[distances[j].tpos]=true;
							i++;
						}
					}
					int i=0;
					foreach(selectedId;ids){
						if(!selectedId) break;
						command.creature=selectedId;
						if(command.type!=CommandType.useAbility) success|=applyOrder(command,state,true,targetPositions[i],formationOffsets[i]);
						else success|=applyOrder(command,state);
						i++;
					}
				}
				return success;
			}else{
				Order ord;
				ord.command=command.type;
				ord.target=OrderTarget(command.target);
				ord.targetFacing=command.targetFacing;
				ord.formationOffset=formationOffset;
				return state.movingObjectById!((ref obj,ord,ability,state,side,updateFormation,formation,position){
					if(ord.command==CommandType.attack&&ord.target.type==TargetType.creature){
						// TODO: check whether they stick to creatures of a specific side
						if(state.movingObjectById!((obj,side,state)=>state.sides.getStance(side,obj.side)==Stance.enemy,()=>false)(ord.target.id,side,state)){
							auto newPosition=position;
							newPosition.z=state.getHeight(newPosition)+obj.position.z-state.getHeight(obj.position);
							auto maxHeight=obj.maxTargetHeight(state);
							auto target=state.proximity.closestEnemyInRange(side,newPosition,attackDistance,EnemyType.creature,state,maxHeight);
							if(target) ord.target.id=target;
						}
					}
					if(ord.command==CommandType.useAbility && obj.ability !is ability) return false;
					if(updateFormation) obj.creatureAI.formation=formation;
					if(ord.command!=CommandType.setFormation){
						if(obj.order(ord,command.queueing,state,side)){
							if(command.type!=CommandType.useAbility){
								auto color=CommandConeColor.white;
								if(command.type.among(CommandType.guard,CommandType.guardArea)) color=CommandConeColor.blue;
								else if(command.type.among(CommandType.attack,CommandType.advance)) color=CommandConeColor.red;
								state.addCommandCone(CommandCone!B(side,color,position));
							}
						}
					}
					return true;
				},()=>false)(command.creature,ord,command.spell,state,command.side,updateFormation,command.formation,position);
			}
		}
		Lswitch:final switch(command.type) with(CommandType){
			case none: break; // TODO: maybe get rid of null commands

			case moveForward: this.movingObjectById!(startMovingForward,(){})(command.creature,this,command.side); break;
			case moveBackward: this.movingObjectById!(startMovingBackward,(){})(command.creature,this,command.side); break;
            case stopMoving: this.movingObjectById!(stopMovement,(){})(command.creature,this,command.side); break;
			case turnLeft: this.movingObjectById!(startTurningLeft,(){})(command.creature,this,command.side); break;
			case turnRight: this.movingObjectById!(startTurningRight,(){})(command.creature,this,command.side); break;
			case stopTurning: this.movingObjectById!(.stopTurning,(){})(command.creature,this,command.side); break;

			case clearSelection: this.clearSelection(command.side); break;
			static foreach(type;[select,selectAll,toggleSelection]){
				case type: mixin(`this.`~to!string(type))(command.side,command.creature); break Lswitch;
			}
			case automaticSelectAll: goto case selectAll;
			case automaticToggleSelection: goto case toggleSelection;
			static foreach(type;[defineGroup,addToGroup]){
			    case type: mixin(`this.`~to!string(type))(command.side,command.group); break Lswitch;
			}
			case selectGroup: success=this.selectGroup(command.side,command.group); break Lswitch;
			case automaticSelectGroup: goto case selectGroup;
			case setFormation: success=applyOrder(command,this,true); break;
			case retreat,move,guard,guardArea,attack,advance,useAbility: success=applyOrder(command,this); break;
			case castSpell: success=startCasting(command.wizard,command.spell,OrderTarget(command.target),this); break;
			case surrender: success=.surrender(command.side,this); break;
		}
	}
	void update(Command!B[] frameCommands){
		frame+=1;
		proximity.start();
		this.eachByType!(addToProximity,false)(this);
		this.eachEffects!updateEffects(this);
		this.eachParticles!updateParticles(this);
		this.eachCommandCones!updateCommandCones(this);
		foreach(command;frameCommands)
			applyCommand(command);
		this.eachStatic!updateStructure(this);
		this.eachMoving!updateCreature(this);
		foreach(side;0..cast(int)sid.sides.length) if(auto q=aiQueue(side)) if(!q.empty){
			this.movingObjectById!((ref obj){ obj.creatureAI.isOnAIQueue=false; },(){})(q.front);
			q.popFront();
		}
		this.eachSoul!updateSoul(this);
		this.eachBuilding!updateBuilding(this);
		this.eachWizard!updateWizard(this);
		this.performRenderModeUpdates();
		this.performRemovals();
		proximity.end();
	}
	ObjectManager!B obj;
	int addObject(T)(T object) if(is(T==MovingObject!B)||is(T==StaticObject!B)||is(T==Soul!B)||is(T==Building!B)){
		return obj.addObject(move(object));
	}
	void removeObject(int id)in{
		assert(id!=0);
	}do{
		obj.removeObject(id);
	}
	void setAlpha(int id,float alpha,float energy)in{
		assert(id!=0);
	}do{
		obj.setAlpha(id,alpha,energy);
	}
	void setThresholdZ(int id,float thresholdZ)in{
		assert(id!=0);
	}do{
		obj.setThresholdZ(id,thresholdZ);
	}
	void setRenderMode(T,RenderMode mode)(int id)if(is(T==MovingObject!B)||is(T==StaticObject!B))in{
		assert(id!=0);
	}do{
		obj.setRenderMode!(T,mode)(id);
	}
	void setRenderMode(T,RenderMode mode)(int id)if(is(T==Building!B))in{
		assert(id!=0);
	}do{
		this.buildingById!((ref bldg,state){
			foreach(cid;bldg.componentIds)
				state.setRenderMode!(StaticObject!B,mode)(cid);
		},(){})(id,this);
	}
	void setupStructureCasting(int buildingId){
		this.buildingById!((ref bldg,state){
			foreach(cid;bldg.componentIds){
				state.setRenderMode!(StaticObject!B,RenderMode.transparent)(cid);
				state.setThresholdZ(cid,-structureCastingGradientSize);
			}
		},(){})(buildingId,this);
	}
	Array!int toRemove;
	void removeLater(int id)in{
		assert(id!=0);
	}do{
		toRemove~=id;
	}
	void performRemovals(){
		foreach(id;toRemove.data) if(isValidId(id)) removeObject(id);
		toRemove.length=0;
	}
	Array!int toUpdateRenderMode;
	void updateRenderModeLater(int id)in{
		assert(id!=0);
	}do{
		toUpdateRenderMode~=id;
	}
	void performRenderModeUpdates(){
		foreach(id;toUpdateRenderMode.data) if(isValidId(id)) updateRenderMode(id,this);
		toUpdateRenderMode.length=0;
	}
	void addWizard(WizardInfo!B wizard){
		obj.addWizard(wizard);
	}
	WizardInfo!B* getWizard(int id){
		return obj.getWizard(id);
	}
	WizardInfo!B* getWizardForSide(int side){
		return obj.getWizardForSide(side,this);
	}
	auto getLevel(int id){
		auto wizard=getWizard(id);
		return wizard?wizard.level:0;
	}
	auto getSpells(int id){
		return getSpells(getWizard(id));
	}
	auto getSpells(bool retro=false)(WizardInfo!B* wizard){
		static bool pred(ref SpellInfo!B spell,int level){ return spell.level<=level; }
		static bool pred2(T)(T x){ return pred(x[]); }
		static first(T)(T x){ return x[0]; }
		if(!wizard) return zip(typeof(mixin(retro?q{ wizard.getSpells().retro }:q{ wizard.getSpells()})).init,repeat(0)).filter!pred2.map!first;
		return zip(mixin(retro?q{ wizard.getSpells().retro }:q{ wizard.getSpells()}),repeat(wizard.level)).filter!pred2.map!first;
	}
	God getCurrentGod(int id){
		return getCurrentGod(getWizard(id));
	}
	God getCurrentGod(WizardInfo!B* wizard){
		if(!wizard) return God.none;
		auto spells=getSpells!true(wizard).filter!(x=>x.spell.type.among(SpellType.creature,SpellType.spell)&&x.spell.god!=God.none);
		if(spells.empty) return God.none;
		return spells.front.spell.god;
	}
	private static alias spellStatusArgs(bool selectOnly:true)=Seq!();
	private static alias spellStatusArgs(bool selectOnly:false)=Seq!OrderTarget;
	SpellStatus spellStatus(bool selectOnly=false)(int id,SacSpell!B spell,spellStatusArgs!selectOnly target){ // DMD bug: default argument does not work
		auto wizard=getWizard(id);
		if(!wizard) return SpellStatus.inexistent;
		return spellStatus!selectOnly(wizard,spell,target);
	}
	SpellStatus spellStatus(bool selectOnly=false)(WizardInfo!B* wizard,SacSpell!B spell,spellStatusArgs!selectOnly target){ // DMD bug: default argument does not work
		foreach(entry;wizard.getSpells()){
			if(entry.spell!is spell) continue;
			if(entry.level>wizard.level) return SpellStatus.inexistent;
			if(spell.soulCost>wizard.souls) return SpellStatus.needMoreSouls;
			auto status=this.movingObjectById!((ref obj,spell,state,spellStatusArgs!selectOnly target){
				if(spell.manaCost>obj.creatureStats.mana+manaEpsilon) return SpellStatus.lowOnMana; // TODO: store mana as exact integer?
				static if(!selectOnly){
					if(spell.requiresTarget){
						if(!spell.isApplicable(summarize(target[0],obj.side,this))) return SpellStatus.invalidTarget;
						if(spell.tag==SpellTag.convert){
							auto side=state.movingObjectById!(.side,()=>-1)(wizard.id,state);
							if(0<=side&&side<32){
								auto convertSideMask=state.soulById!((ref soul)=>soul.convertSideMask,()=>0u)(target[0].id);
								static assert(is(typeof(convertSideMask)==uint));
								if(!(convertSideMask&(1u<<side))) return SpellStatus.invalidTarget;
							}
						}
						if((obj.position-target[0].position).lengthsqr>spell.range^^2) return SpellStatus.outOfRange;
					}
				}
				import spells:SpelFlags1;
				if(obj.creatureStats.effects.shieldBlocked && spell.flags1&SpelFlags1.shield)
					return SpellStatus.disabled;
				return SpellStatus.ready;
			},function()=>SpellStatus.inexistent)(wizard.id,spell,this,target);
			if(status==SpellStatus.ready){
				if(spell.tag==SpellTag.guardian) if(!wizard.closestBuilding) return SpellStatus.mustBeNearBuilding;
				if(spell.tag==SpellTag.desecrate) if(!wizard.closestEnemyAltar) return SpellStatus.mustBeNearEnemyAltar;
				if(spell.tag==SpellTag.convert) if(!wizard.closestShrine) return SpellStatus.mustBeConnectedToConversion;
			}
			if(entry.cooldown>0.0f) return SpellStatus.notReady;
			return status;
		}
		return SpellStatus.inexistent;
	}
	SpellStatus abilityStatus(bool selectOnly=false)(int side,SacSpell!B ability,spellStatusArgs!selectOnly target){
		static if(!selectOnly){
			if(ability.requiresTarget&&!ability.isApplicable(summarize(target[0],side,this))) return SpellStatus.invalidTarget;
		}
		return SpellStatus.ready;
	}
	SpellStatus abilityStatus(bool selectOnly=false)(ref MovingObject!B obj,SacSpell!B ability,spellStatusArgs!selectOnly target){
		if(obj.creatureStats.effects.abilityCooldown!=0) return SpellStatus.notReady;
		if(ability.manaCost>obj.creatureStats.mana+manaEpsilon) return SpellStatus.lowOnMana; // TODO: store mana as exact integer?
		static if(!selectOnly){
			if(ability.requiresTarget){
				if(!ability.isApplicable(summarize(target[0],obj.side,this))) return SpellStatus.invalidTarget;
				if((obj.position-target[0].position).lengthsqr>ability.range^^2) return SpellStatus.outOfRange;
			}
		}
		switch(ability.tag){
			case SpellTag.runAway:
				if(obj.creatureStats.effects.numSpeedUps)
					return SpellStatus.invalidTarget;
				return SpellStatus.ready;
			case SpellTag.playDead:
				with(CreatureMode)
					if(obj.creatureState.mode.among(stunned,pretendingToDie,playingDead))
						return SpellStatus.invalidTarget;
				return SpellStatus.ready;
			case SpellTag.rockForm:
				if(obj.creatureState.mode==CreatureMode.rockForm)
					return SpellStatus.invalidTarget;
				return SpellStatus.ready;
			case SpellTag.stealth:
				if(obj.creatureStats.effects.stealth||!obj.checkStealth)
					return SpellStatus.invalidTarget;
				return SpellStatus.ready;
			case SpellTag.lifeShield:
				if(obj.creatureStats.effects.lifeShield)
					return SpellStatus.invalidTarget;
				return SpellStatus.ready;
			default: return SpellStatus.ready;
		}
	}
	void removeWizard(int id){
		obj.removeWizard(id);
	}
	bool isValidId(int id){
		return obj.isValidId(id);
	}
	bool isValidBuilding(int id){
		return obj.isValidBuilding(id);
	}
	bool isValidTarget(int id){
		return obj.isValidTarget(id);
	}
	bool isValidTarget(int id,TargetType type){
		return obj.isValidTarget(id,type);
	}
	TargetType targetTypeFromId(int id){
		return obj.targetTypeFromId(id);
	}
	void addFixed(FixedObject!B object){
		obj.addFixed(object);
	}
	void addEffect(T)(T proj){
		obj.addEffect(proj);
	}
	void addParticle(bool relative,bool sideFiltered)(Particle!(B,relative,sideFiltered) particle){
		obj.addParticle(particle);
	}
	void addCommandCone(CommandCone!B cone){
		obj.addCommandCone(cone);
	}
	SideManager!B sid;
	Queue!int* aiQueue(int side){
		return sid.aiQueue(side);
	}
	bool frontOfAIQueue(int side,int id){
		if(auto q=aiQueue(side)) return q.front==id;
		return false;
	}
	bool pushToAIQueue(int side,int id){
		if(auto q=aiQueue(side)){
			q.push(id);
			return true;
		}
		return false;
	}
	void clearSelection(int side){
		sid.clearSelection(side);
	}
	void select(int side,int id){
		if(!canSelect(side,id,this)) return;
		sid.select(side,id);
	}
	int buildingIdForGuardian(int creature){
		foreach(ref guardian;obj.opaqueObjects.effects.guardians){
			if(guardian.creature==creature)
				return guardian.building;
		}
		return 0;
	}
	void selectAll(int side,int id){
		if(!canSelect(side,id,this)) return;
		// TODO: use Proximity for this? (Not a bottleneck.)
		static void processObj(B)(ref MovingObject!B obj,int side,ObjectState!B state){
			struct MObj{ int id; Vector3f position; }
			alias Selection=MObj[numCreaturesInGroup];
			Selection selection;
			static void addToSelection(ref MObj[numCreaturesInGroup] selection,MObj obj,MObj nobj){
				if(selection[].map!"a.id".canFind(nobj.id)) return;
				int i=0;
				while(i<selection.length&&selection[i].id&&(selection[i].position-obj.position).lengthsqr<(nobj.position-obj.position).lengthsqr)
					i++;
				if(i>=selection.length||selection[i].id==nobj.id) return;
				foreach_reverse(j;i..selection.length-1)
					swap(selection[j],selection[j+1]);
				selection[i]=nobj;
			}
			static void process(B)(ref MovingObject!B nobj,bool guardian,int side,MObj mobj,Selection* selection,ObjectState!B state){
				if(!canSelect(nobj,side,state)) return;
				if(nobj.isGuardian!=guardian) return;
				if((mobj.position-nobj.position).lengthsqr>50.0f^^2) return;
				addToSelection(*selection,mobj,MObj(nobj.id,nobj.position));
			}
			auto mobj=MObj(obj.id,obj.position);
			if(obj.isGuardian){
				if(auto building=state.buildingIdForGuardian(obj.id)){
					state.buildingById!((ref bldg,side,mobj,selection,state){
						foreach(id;bldg.guardianIds)
							state.movingObjectById!(process,(){})(id,true,side,mobj,selection,state);
					},(){})(building,side,mobj,&selection,state);
				}
			}else state.eachMovingOf!process(obj.sacObject,false,side,mobj,&selection,state);
			if(selection[0].id!=0){
				state.clearSelection(side);
				foreach_reverse(i;0..selection.length)
					if(selection[i].id) state.sid.addToSelection(side,selection[i].id);
			}
		}
		this.movingObjectById!(processObj,(){})(id,side,this);
	}
	void addToSelection(int side,int id){
		if(!canSelect(side,id,this)) return;
		sid.addToSelection(side,id);
	}
	void removeFromSelection(int side,int id){
		if(!canSelect(side,id,this)) return;
		sid.removeFromSelection(side,id);
	}
	void toggleSelection(int side,int id){
		if(!canSelect(side,id,this)) return;
		sid.toggleSelection(side,id);
	}
	void defineGroup(int side,int groupId){
		sid.defineGroup(side,groupId);
	}
	void addToGroup(int side,int groupId){
		sid.addToGroup(side,groupId);
	}
	void addToGroup(int side,int groupId,int creatureId){
		sid.addToGroup(side,groupId,creatureId);
	}
	bool selectGroup(int side,int groupId){
		return sid.selectGroup(side,groupId);
	}
	void removeFromGroups(int side,int id){
		if(!canSelect(side,id,this)) return;
		sid.removeFromGroups(side,id);
	}
	CreatureGroup getSelection(int side){
		return sid.getSelection(side);
	}
	int[2] lastSelected(int side){
		return sid.lastSelected(side);
	}
	void resetSelectionCount(int side){
		return sid.resetSelectionCount(side);
	}
	void newCreatureAddToSelection(int side,int id){
		addToSelection(side,id);
		addToGroup(side,numCreatureGroups-1,id);
	}
}
auto each(alias f,B,T...)(ObjectState!B objectState,T args){
	return objectState.obj.each!f(args);
}
auto eachMoving(alias f,B,T...)(ObjectState!B objectState,T args){
	return objectState.obj.eachMoving!f(args);
}
auto eachStatic(alias f,B,T...)(ObjectState!B objectState,T args){
	return objectState.obj.eachStatic!f(args);
}
auto eachSoul(alias f,B,T...)(ObjectState!B objectState,T args){
	return objectState.obj.eachSoul!f(args);
}
auto eachBuilding(alias f,B,T...)(ObjectState!B objectState,T args){
	return objectState.obj.eachBuilding!f(args);
}
auto eachWizard(alias f,B,T...)(ObjectState!B objectState,T args){
	return objectState.obj.eachWizard!f(args);
}
auto eachEffects(alias f,B,T...)(ObjectState!B objectState,T args){
	return objectState.obj.eachEffects!f(args);
}
auto eachParticles(alias f,B,T...)(ObjectState!B objectState,T args){
	return objectState.obj.eachParticles!f(args);
}
auto eachCommandCones(alias f,B,T...)(ObjectState!B objectState,T args){
	return objectState.obj.eachCommandCones!f(args);
}
auto eachByType(alias f,bool movingFirst=true,bool particlesBeforeEffects=false,B,T...)(ObjectState!B objectState,T args){
	return objectState.obj.eachByType!(f,movingFirst,particlesBeforeEffects)(args);
}
auto eachMovingOf(alias f,B,T...)(ObjectState!B objectState,SacObject!B sacObject,T args){
	return objectState.obj.eachMovingOf!f(sacObject,args);
}
auto eachMovingOfSide(alias f,B,T...)(ObjectState!B objectState,int side,T args){
	static void doIt(ref MovingObject!B obj,int side,T args){
		if(obj.side!=side) return;
		f(obj,args);
	}
	return objectState.obj.eachMoving!doIt(side,args);
}

auto ref objectById(alias f,B,T...)(ObjectState!B objectState,int id,T args){
	return objectState.obj.objectById!f(id,args);
}
auto ref movingObjectById(alias f,alias nonMoving,B,T...)(ObjectState!B objectState,int id,T args){
	return objectState.obj.movingObjectById!(f,nonMoving)(id,args);
}
auto ref staticObjectById(alias f,alias nonStatic,B,T...)(ObjectState!B objectState,int id,T args){
	return objectState.obj.staticObjectById!(f,nonStatic)(id,args);
}
auto ref soulById(alias f,alias noSoul,B,T...)(ObjectState!B objectState,int id,T args){
	return objectState.obj.soulById!(f,noSoul)(id,args);
}
auto ref buildingById(alias f,alias noBuilding,B,T...)(ObjectState!B objectState,int id,T args){
	return objectState.obj.buildingById!(f,noBuilding)(id,args);
}


enum Stance{
	neutral,
	ally,
	enemy,
}
int rank(Stance stance){
	final switch(stance){
		case Stance.enemy: return 0;
		case Stance.neutral: return 1;
		case Stance.ally: return 2;
	}
}

enum neutralSide=31;
final class Sides(B){
	private Side[32] sides;
	private SacParticle!B[32] manaParticles;
	private SacParticle!B[32] shrineParticles;
	private SacParticle!B[32] manahoarParticles;
	this(Side[] sids...){
		static int num=0;
		foreach(ref side;sids){
			enforce(0<=side.id&&side.id<32);
			sides[side.id]=side;
		}
		foreach(i;0..32){
			sides[i].allies|=(1<<i); // allied to themselves
			sides[i].enemies&=~(1<<i); // not enemies of themselves
		}
	}
	int opApply(scope int delegate(ref Side) dg){
		foreach(side;sides) if(auto r=dg(side)) return r;
		return 0;
	}
	int opApply(scope int delegate(size_t,ref Side) dg){
		foreach(i,side;sides) if(auto r=dg(i,side)) return r;
		return 0;
	}
	Color4f sideColor(int side){
		auto c=sideColors[sides[side].color];
		if(side==31) static foreach(i;0..3) c[i]*=0.5f;
		return c;
	}
	Color4f manaColor(int side){
		auto color=0.8f*Vector3f(sideColor(side).rgb)+0.2f*Vector3f(1.0f,1.0f,1.0f);
		auto total=color.r+color.g+color.b;
		return Color4f((3.0f/total)*color);
	}
	float manaEnergy(int side){
		auto color=sideColor(side);
		if(color.g<0.15f) return 160.0f;
		return 20.0f;
	}
	SacParticle!B manaParticle(int side){
		if(!manaParticles[side]) manaParticles[side]=new SacParticle!B(ParticleType.manalith, manaColor(side), manaEnergy(side), side);
		return manaParticles[side];
	}
	SacParticle!B shrineParticle(int side){
		if(!shrineParticles[side]) shrineParticles[side]=new SacParticle!B(ParticleType.shrine, manaColor(side), manaEnergy(side), side);
		return shrineParticles[side];
	}
	SacParticle!B manahoarParticle(int side){
		if(!manahoarParticles[side]) manahoarParticles[side]=new SacParticle!B(ParticleType.manahoar, manaColor(side), manaEnergy(side), side);
		return manahoarParticles[side];
	}
	void setStance(int from,int towards,Stance stance){
		if(from<0||from>=sides.length||towards<0||towards>=sides.length) return;
		final switch(stance){
			case Stance.ally: sides[from].allies|=1<<towards; sides[from].enemies&=~(1<<towards); break;
			case Stance.enemy: sides[from].allies&=~(1<<towards); sides[from].enemies|=1<<towards; break;
			case Stance.neutral: sides[from].allies&=~(1<<towards); sides[from].enemies&=~(1<<towards); break;
		}
	}
	Stance getStance(int from,int towards){
		if(from<0||from>=sides.length||towards<0||towards>=sides.length) return Stance.neutral;
		if(sides[from].allies&(1<<towards)) return Stance.ally;
		if(sides[from].enemies&(1<<towards)) return Stance.enemy;
		return Stance.neutral;
	}
}

enum numCreatureGroups=10;
enum numCreaturesInGroup=12;
struct CreatureGroup{
	int[numCreaturesInGroup] creatureIds;
	int[] get()return{ return creatureIds[]; }
	bool has(int id){
		if(!id) return false;
		foreach(x;creatureIds) if(x==id) return true;
		return false;
	}
	void addFront(int id){ // for addToSelection
		if(!id) return;
		if(has(id)) return;
		foreach_reverse(i;0..creatureIds.length-1)
			swap(creatureIds[i],creatureIds[i+1]);
		creatureIds[0]=id;
	}
	void addBack(int id){ // for addToGroup
		if(!id) return;
		if(has(id)) return;
		if(creatureIds[$-1]){
			foreach(i;0..creatureIds.length-1)
				swap(creatureIds[i],creatureIds[i+1]);
			creatureIds[$-1]=id;
		}else{
			foreach_reverse(i;-1..cast(int)creatureIds.length-1){
				if(i==-1||creatureIds[i]){
					creatureIds[i+1]=id;
					break;
				}
			}
		}
	}
	void addSorted(int id){
		if(!id) return;
		if(has(id)) return;
		int i=0;
		while(i<creatureIds.length&&creatureIds[i]&&creatureIds[i]>id)
			i++;
		if(i>=creatureIds.length||creatureIds[i]==id) return;
		foreach_reverse(j;i..creatureIds.length-1)
			swap(creatureIds[j],creatureIds[j+1]);
		creatureIds[i]=id;
	}
	void addFront(int[] ids...){
		foreach_reverse(id;ids) addFront(id); // TODO: do more efficiently
	}
	void addBack(int[] ids...){
		foreach(id;ids) addBack(id); // TODO: do more efficiently
	}
	void remove(int id){
		if(!id) return;
		foreach(i,x;creatureIds){
			if(x==id){
				foreach(j;i..creatureIds.length-1){
					swap(creatureIds[j],creatureIds[j+1]);
				}
				assert(creatureIds[$-1]==id);
				creatureIds[$-1]=0;
			}
		}
	}
	bool toggle(int id){
		if(!id) return false;
		if(has(id)){
			remove(id);
			return false;
		}else{
			addFront(id);
			return true;
		}
	}
	void clear(){
		creatureIds[]=0;
	}

	int representative(B)(ObjectState!B state){
		int result=0,bestPriority=-1;
		foreach(id;creatureIds){
			if(id){
				int priority=state.movingObjectById!((obj)=>obj.sacObject.creaturePriority,()=>-1)(id);
				if(priority>bestPriority){
					result=id;
					bestPriority=priority;
				}
			}
		}
		return result;
	}
	SacSpell!B ability(B)(ObjectState!B state){
		SacSpell!B ability=null;
		int bestPriority=-1;
		foreach(id;creatureIds){
			if(id){
				auto prioritySpell=state.movingObjectById!((obj)=>tuple(obj.sacObject.creaturePriority,obj.ability),()=>tuple(-1,SacSpell!B.init))(id);
				auto priority=prioritySpell[0],spell=prioritySpell[1];
				if(spell&&priority>bestPriority){
					ability=spell;
					bestPriority=priority;
				}
			}
		}
		return ability;
	}
}

struct SideData(B){
	CreatureGroup selection;
	CreatureGroup[10] groups;
	int lastSelected=0;
	int selectionMultiplicity=0;
	Queue!int aiQueue;
	mixin Assign;
	void updateLastSelected(int id){
		if(lastSelected!=id){
			lastSelected=id;
			selectionMultiplicity=1;
		}else selectionMultiplicity++;
	}
	void clearSelection(){
		selection.clear();
	}
	void select(int id){
		clearSelection();
		selection.addFront(id);
		updateLastSelected(id);
	}
	void addToSelection(int id){
		if(selection.has(id)) return;
		selection.addFront(id);
	}
	void removeFromSelection(int id){
		selection.remove(id);
	}
	void toggleSelection(int id){
		if(selection.toggle(id))
			updateLastSelected(id);
	}
	void defineGroup(int groupId)in{
		assert(0<=groupId&&groupId<numCreatureGroups);
	}do{
		groups[groupId]=selection;
		foreach(id;selection.creatureIds) groups[$-1].remove(id);
	}
	void addToGroup(int groupId){
		groups[groupId].addBack(selection.creatureIds[]);
		foreach(id;selection.creatureIds) groups[$-1].remove(id);
	}
	void addToGroup(int groupId,int creatureId){
		groups[groupId].addBack(creatureId);
	}
	bool selectGroup(int groupId){
		if(groups[groupId].creatureIds[0]==0) return false;
		selection=groups[groupId];
		return true;
	}
	void removeFromGroups(int id){
		removeFromSelection(id);
		foreach(i;0..groups.length)
			groups[i].remove(id);
	}
	CreatureGroup getSelection(){
		return selection;
	}
	void resetSelectionCount(){
		selectionMultiplicity=0;
	}
}

struct SideManager(B){
	Array!(SideData!B) sides;
	mixin Assign;
	this(int numSides){
		sides.length=numSides;
	}
	Queue!int* aiQueue(int side){
		if(!(0<=side&&side<sides.length)) return null;
		return &sides[side].aiQueue;
	}
	void clearSelection(int side){
		if(!(0<=side&&side<sides.length)) return;
		sides[side].clearSelection();
	}
	void select(int side,int id){
		if(!(0<=side&&side<sides.length&&id)) return;
		sides[side].select(id);
	}
	void addToSelection(int side,int id){
		if(!(0<=side&&side<sides.length&&id)) return;
		sides[side].addToSelection(id);
	}
	void removeFromSelection(int side,int id){
		if(!(0<=side&&side<sides.length&&id)) return;
		sides[side].removeFromSelection(id);
	}
	void toggleSelection(int side,int id){
		if(!(0<=side&&side<sides.length&&id)) return;
		sides[side].toggleSelection(id);
	}
	void defineGroup(int side,int groupId){
		if(!(0<=side&&side<sides.length&&0<=groupId&&groupId<numCreatureGroups)) return;
		sides[side].defineGroup(groupId);
	}
	void addToGroup(int side,int groupId){
		if(!(0<=side&&side<sides.length&&0<=groupId&&groupId<numCreatureGroups)) return;
		sides[side].addToGroup(groupId);
	}
	void addToGroup(int side,int groupId,int creatureId){
		if(!(0<=side&&side<sides.length&&0<=groupId&&groupId<numCreatureGroups)) return;
		sides[side].addToGroup(groupId,creatureId);
	}
	bool selectGroup(int side,int groupId){
		if(!(0<=side&&side<sides.length&&0<=groupId&&groupId<numCreatureGroups)) return false;
		return sides[side].selectGroup(groupId);
	}
	void removeFromGroups(int side,int id){
		if(!(0<=side&&side<sides.length&&id)) return;
		sides[side].removeFromGroups(id);
	}
	CreatureGroup getSelection(int side){
		if(!(0<=side&&side<sides.length)) return CreatureGroup.init;
		return sides[side].getSelection();
	}
	int[2] lastSelected(int side){
		if(!(0<=side&&side<sides.length)) return [0,0];
		return [sides[side].lastSelected,sides[side].selectionMultiplicity];
	}
	void resetSelectionCount(int side){
		if(!(0<=side&&side<sides.length)) return;
		return sides[side].resetSelectionCount();
	}
}

final class Triggers(B){
	int[int] objectIds;
	void associateId(int triggerId,int objectId)in{
		assert(triggerId !in objectIds);
	}do{
		objectIds[triggerId]=objectId;
	}
	int associatedId(int triggerId){
		return objectIds.get(triggerId,0);
	}
	Trig trig;
	this(Trig trig){ this.trig=trig; }
}

enum TargetType{
	none,
	terrain,
	creature,
	building,
	soul,

	creatureTab,
	spellTab,
	structureTab,

	spell,
	ability,

	soulStat,
	manaStat,
	healthStat,
}

enum TargetLocation{
	none,
	scene,
	minimap,
	selectionRoster,
	spellbook,
	hud,
}

struct Target{
	TargetType type;
	int id;
	Vector3f position;
	auto location=TargetLocation.scene;
}
TargetFlags summarize(bool simplified=false,B)(ref OrderTarget target,int side,ObjectState!B state){
	final switch(target.type) with(TargetType){
		case none,creatureTab,spellTab,structureTab,spell,ability,soulStat,manaStat,healthStat: return TargetFlags.none;
		case terrain: return TargetFlags.ground;
		case creature,building:
			static TargetFlags handle(T)(T obj,int side,ObjectState!B state){
				enum isMoving=is(T==MovingObject!B);
				static if(isMoving){
					auto result=TargetFlags.creature;
					if(obj.creatureState.mode.among(CreatureMode.dead,CreatureMode.dissolving)) result|=TargetFlags.corpse;
					if(obj.creatureState.mode.among(CreatureMode.convertReviving,CreatureMode.thrashing)) result|=TargetFlags.beingSacrificed;
					auto objSide=obj.side;
				}else{
					auto result=TargetFlags.building;
					auto objSide=sideFromBuildingId(obj.buildingId,state);
					auto buildingInterestingIsManafountTop=state.buildingById!((ref bldg)=>tuple(bldg.health!=0||bldg.isAltar,bldg.isManafount,bldg.top),()=>tuple(false,false,0))(obj.buildingId);
					auto buildingInteresting=buildingInterestingIsManafountTop[0],isManafount=buildingInterestingIsManafountTop[1],top=buildingInterestingIsManafountTop[2];
					buildingInteresting|=isManafount;
					if(!buildingInteresting) result|=TargetFlags.untargetable; // TODO: there might be a flag for this
					if(isManafount&&!top) result|=TargetFlags.manafount;
				}
				if(objSide!=side){
					auto stance=state.sides.getStance(side,objSide);
					final switch(stance){
						case Stance.neutral: break;
						case Stance.ally: result|=TargetFlags.ally; break;
						case Stance.enemy: result|=TargetFlags.enemy; break;
					}
					static if(isMoving) if(stance!=Stance.enemy&&obj.creatureStats.flags&Flags.rescuable) result|=TargetFlags.rescuable;
				}else result|=TargetFlags.owned|TargetFlags.ally;
				static if(isMoving&&!simplified){
					enum flyingLimit=1.0f; // TODO: measure this.
					if(!state.isOnGround(obj.position)||obj.hitbox[0].z>=state.getGroundHeight(obj.position)+flyingLimit) result|=TargetFlags.flying;
					if(obj.isWizard){
						result&=~TargetFlags.creature;
						result|=TargetFlags.wizard;
					}
					if(obj.creatureStats.effects.numSpeedUps && obj.creatureStats.effects.speedUpFrame+doubleSpeedUpDelay<state.frame)
						result|=TargetFlags.spedUp;
					if(obj.isHero) result|=TargetFlags.hero;
					if(obj.isFamiliar) result|=TargetFlags.familiar;
					if(obj.isSacDoctor) result|=TargetFlags.sacDoctor;
					if(obj.isShielded) result|=TargetFlags.shielded;
					if(obj.isCCProtected) result|=TargetFlags.ccProtected;
					if(obj.isHealBlocked) result|=TargetFlags.healBlocked;
					if(obj.isGuardian) result|=TargetFlags.guardian;
				}
				return result;
			}
			if(!state.targetTypeFromId(target.id).among(TargetType.creature,TargetType.building)) return TargetFlags.none;
			return state.objectById!handle(target.id,side,state);
		case soul:
			auto result=TargetFlags.soul;
			auto objSide=soulSide(target.id,state);
			if(objSide==-1||objSide==side) result|=TargetFlags.owned|TargetFlags.ally; // TODO: ok? (not exactly what is going on with free souls.)
			else result|=TargetFlags.enemy;
			return result;
	}
}
Cursor cursor(B)(ref OrderTarget target,int renderSide,bool showIcon,ObjectState!B state){
	auto summary=summarize!true(target,renderSide,state);
	with(TargetFlags) with(Cursor){
		if(summary==none) return showIcon?iconNone:normal;
		if(summary&ground||summary&corpse||summary&untargetable) return showIcon?iconNeutral:normal;
		if(summary&owned){
			if(summary&creature) return showIcon?iconFriendly:friendlyUnit;
			if(summary&building) return showIcon?iconFriendly:friendlyBuilding;
		}
		bool isNeutral=!(summary&enemy);
		if(summary&creature){
			if(isNeutral) return showIcon?iconNeutral:(summary&rescuable?rescuableUnit:neutralUnit);
			return showIcon?iconEnemy:enemyUnit;
		}
		if(summary&building){
			if(isNeutral) return showIcon?iconNeutral:(summary&manafount?normal:neutralBuilding);
			return showIcon?iconEnemy:enemyBuilding;
		}
		if(summary&soul){
			if(summary&owned) return showIcon?iconNone:blueSoul;
			return showIcon?iconNone:normal;
		}
		return showIcon?iconNone:normal;
	}
}


enum CommandType{
	none,
	moveForward,
	moveBackward,
	stopMoving,
	turnLeft,
	turnRight,
	stopTurning,

	clearSelection,
	select,
	selectAll,
	automaticSelectAll,
	toggleSelection,
	automaticToggleSelection,

	defineGroup,
	addToGroup,
	selectGroup,
	automaticSelectGroup,

	setFormation,

	retreat,
	move,
	guard,
	guardArea,
	attack,
	advance,

	castSpell,
	useAbility,

	surrender,
}

bool hasClickSound(CommandType type){
	final switch(type) with(CommandType){
		case none,moveForward,moveBackward,stopMoving,turnLeft,turnRight,stopTurning,clearSelection,automaticToggleSelection,automaticSelectGroup,setFormation,retreat,surrender: return false;
		case select,selectAll,automaticSelectAll,toggleSelection,defineGroup,addToGroup,selectGroup,move,guard,guardArea,attack,advance,castSpell,useAbility: return true;
	}
}
SoundType soundType(B)(Command!B command){
	final switch(command.type) with(CommandType){
		case none,moveForward,moveBackward,stopMoving,turnLeft,turnRight,stopTurning,clearSelection,select,selectAll,automaticSelectAll,toggleSelection,automaticToggleSelection,automaticSelectGroup:
			return SoundType.none;
		case defineGroup,addToGroup:
			switch(command.group){
				static foreach(i;0..10) case i: return mixin(`SoundType.beGroup`~to!string(i+1));
				default: return SoundType.none;
			}
		case selectGroup:
			switch(command.group){
				static foreach(i;0..10) case i: return mixin(`SoundType.group`~to!string(i+1));
				default: return SoundType.none;
			}
		case setFormation:
			final switch(command.formation) with(Formation){
				case line: return SoundType.lineFormation;
				case flankLeft: return SoundType.none;
				case flankRight: return SoundType.none;
				case phalanx: return SoundType.phalanxFormation;
				case semicircle: return SoundType.semicircleFormation;
				case circle: return SoundType.circleFormation;
				case wedge: return SoundType.wedgeFormation;
				case skirmish: return SoundType.skirmishFormation;
			}
		case retreat: return SoundType.guardMe;
		case move: return SoundType.move;
		case guard: return command.target.type==TargetType.building?SoundType.guardBuilding:command.wizard==command.target.id?SoundType.guardMe:SoundType.guard;
		case guardArea: return SoundType.defendArea;
		case attack: return command.target.type==TargetType.building?SoundType.attackBuilding:SoundType.attack;
		case advance: return SoundType.advance;
		case castSpell,useAbility: return SoundType.none;
		case surrender: return SoundType.none;
	}
}
SoundType responseSoundType(B)(Command!B command){
	final switch(command.type) with(CommandType){
		case none,moveForward,moveBackward,stopMoving,turnLeft,turnRight,stopTurning,setFormation,clearSelection,automaticSelectAll,automaticToggleSelection,defineGroup,addToGroup,automaticSelectGroup,retreat,castSpell,useAbility,surrender:
			return SoundType.none;
		case select,selectAll,toggleSelection,selectGroup:
			return SoundType.selected;
		case move,guard,guardArea: return SoundType.moving;
		case attack,advance: return SoundType.attacking;
	}
}
void speakCommand(B)(Command!B command,ObjectState!B state){
	if(!command.wizard) return;
	auto soundType=command.soundType;
	if(soundType!=SoundType.none){
		auto sacObject=state.movingObjectById!((obj)=>obj.sacObject,()=>null)(command.wizard);
		if(sacObject) queueDialogSound(command.side,sacObject,soundType,DialogPriority.command,state);
	}
	auto responseSoundType=command.responseSoundType;
	if(responseSoundType!=SoundType.none){
		int responding=command.creature?command.creature:state.getSelection(command.side).representative(state);
		if(responding&&state.getSelection(command.side).creatureIds[].canFind(responding)){
			if(auto respondingSacObject=state.movingObjectById!((obj)=>obj.sacObject,()=>null)(responding)){
				if(responseSoundType==SoundType.selected){
					auto lastSelected=state.lastSelected(command.side);
					if(responding==lastSelected[0]&&lastSelected[1]>3){
						if(auto sset=respondingSacObject.sset){
							auto sounds=sset.getSounds(SoundType.annoyed);
							auto sound=sounds[(lastSelected[1]-4)%$];
							static if(B.hasAudio) if(playAudio)
								B.queueDialogSound(command.side,sound,DialogPriority.annoyedResponse);
							return;
						}
					}
				}else state.resetSelectionCount(command.side);
				queueDialogSound(command.side,respondingSacObject,responseSoundType,DialogPriority.response,state);
			}
		}
	}
}
// TODO: get rid of duplicated code
enum DialogPriority{
	response,
	annoyedResponse,
	command,
	advisorAnnoy,
	advisorImportant,
}
enum DialogPolicy{
	queue,
	interruptPrevious,
	ignorePrevious,
	ignoreCurrent,
}
DialogPolicy dialogPolicy(DialogPriority previous,DialogPriority current){
	with(DialogPriority) with(DialogPolicy){
		if(previous.among(response,annoyedResponse)) return previous<current?interruptPrevious:queue;
		if(previous==command) return previous==current?ignorePrevious:previous<current?interruptPrevious:queue;
		return previous<current?interruptPrevious:current==advisorAnnoy?ignoreCurrent:queue;
	}
}
void queueDialogSound(B)(int side,SacObject!B sacObject,SoundType soundType,DialogPriority priority,ObjectState!B state){
	void playSset(immutable(Sset)* sset){
		auto sounds=sset.getSounds(soundType);
		if(sounds.length){
			auto sound=sounds[state.uniform(cast(int)$)];
			static if(B.hasAudio) if(playAudio)
				B.queueDialogSound(side,sound,priority);
		}
	}
	if(auto sset=sacObject.sset) playSset(sset);
	if(auto sset=sacObject.meleeSset) playSset(sset);
}
int getSoundDuration(B)(char[4] sound,ObjectState!B state){
	return B.getSoundDuration(sound);
}
void playSound(B)(int side,char[4] sound,ObjectState!B state,float gain=1.0f){
	static if(B.hasAudio) if(playAudio) B.playSound(side,sound,gain);
}
void playSoundType(B)(int side,SacObject!B sacObject,SoundType soundType,ObjectState!B state){
	void playSset(immutable(Sset)* sset){
		auto sounds=sset.getSounds(soundType);
		if(sounds.length){
			auto sound=sounds[state.uniform(cast(int)$)];
			playSound(side,sound,state);
		}
	}
	if(auto sset=sacObject.sset) playSset(sset);
	if(auto sset=sacObject.meleeSset) playSset(sset);
}
auto playSoundAt(bool getDuration=false,B)(char[4] sound,Vector3f position,ObjectState!B state,float gain=1.0f){
	static if(B.hasAudio) if(playAudio) B.playSoundAt(sound,position,gain);
	static if(getDuration) return getSoundDuration(sound,state);
}
auto playSpellSoundTypeAt(bool getDuration=false,B,T,L...)(SoundType soundType,T target,ObjectState!B state,float gain=1.0f,L limit=L.init){
	auto sset=SacSpell!B.sset;
	if(!sset){
		static if(getDuration) return 0;
		else return;
	}
	auto sounds=sset.getSounds(soundType);
	if(sounds.length){
		auto sound=sounds[state.uniform(cast(int)$)];
		static if(getDuration){
			auto duration=getSoundDuration(sound,state);
			static if(limit.length) if(duration>limit[0]) return 0;
		}
		playSoundAt(sound,target,state,gain);
		static if(getDuration) return duration;
	}
	static if(getDuration) return 0;
}

auto playSoundAt(bool getDuration=false,B)(char[4] sound,int id,ObjectState!B state,float gain=1.0f){
	static if(B.hasAudio) if(playAudio) B.playSoundAt(sound,id,gain);
	static if(getDuration) return getSoundDuration(sound,state);
}
auto playSoundTypeAt(bool getDuration=false,B,T...)(SacObject!B sacObject,int id,SoundType soundType,ObjectState!B state,T limit)if(T.length<=(getDuration?1:0)){
	static if(getDuration) int duration=0;
	void playSset(immutable(Sset)* sset){
		if(!sset) return;
		auto sounds=sset.getSounds(soundType);
		if(sounds.length){
			auto sound=sounds[state.uniform(cast(int)$)];
			auto gain=sset.name=="wasb"?2.0f:soundType==SoundType.incantation?1.5f:1.0f;
			static if(getDuration){
				auto soundDuration=getSoundDuration(sound,state);
				static if(limit.length) if(soundDuration>limit[0]) return;
				duration=max(duration,soundDuration);
			}
			playSoundAt(sound,id,state,gain);
		}
	}
	if(auto sset=sacObject.sset) playSset(sset);
	if(auto sset=sacObject.meleeSset) playSset(sset);
	static if(getDuration) return duration;
}
auto stopSoundsAt(B)(int id,ObjectState!B state){
	static if(B.hasAudio) if(playAudio) B.stopSoundsAt(id);
}

enum CommandQueueing{
	none,
	post,
	pre,
}

struct Command(B){
	this(CommandType type,int side,int wizard,int creature,Target target,float targetFacing)in{
		final switch(type) with(CommandType){
			case none:
				assert(0);
			case moveForward,moveBackward,stopMoving,turnLeft,turnRight,stopTurning:
				assert(!!creature && target is Target.init);
				break;
			case clearSelection:
				assert(!creature && target is Target.init);
				break;
			case select,selectAll,automaticSelectAll,toggleSelection,automaticToggleSelection:
				assert(creature && target is Target.init);
				break;
			case move:
				assert(target.type==TargetType.terrain);
				break;
			case setFormation:
				assert(0);
			case retreat:
				assert(target.type==TargetType.creature);
				break;
			case guard,attack:
				assert(target.type.among(TargetType.creature,TargetType.building));
				break;
			case guardArea,advance:
				assert(target.type==TargetType.terrain);
				break;
				case defineGroup,addToGroup,selectGroup,automaticSelectGroup:
				assert(0);
			case castSpell,useAbility:
				assert(0);
			case surrender:
				assert(0);
		}
	}do{
		this.type=type;
		this.side=side;
		this.wizard=wizard;
		this.creature=creature;
		this.target=target;
		this.targetFacing=targetFacing;
	}

	this(CommandType type,int side,int wizard,int group)in{
		switch(type) with(CommandType){
			case defineGroup,addToGroup,selectGroup,automaticSelectGroup:
				assert(0<=group && group<10);
				break;
			default:
				assert(0);
		}
	}do{
		this.type=type;
		this.side=side;
		this.wizard=wizard;
		this.group=group;
	}

	this(int side,int wizard,Formation formation){
		this.type=CommandType.setFormation;
		this.side=side;
		this.wizard=wizard;
		this.formation=formation;
	}

	this(int side,int wizard,SacSpell!B spell,Target target){
		this.type=CommandType.castSpell;
		this.side=side;
		this.wizard=wizard;
		this.spell=spell;
		this.target=target;
	}

	this(int side,SacSpell!B ability,Target target){
		this.type=CommandType.useAbility;
		this.side=side;
		this.spell=ability;
		this.target=target;
	}

	this(int side){
		this.type=CommandType.surrender;
		this.side=side;
	}

	CommandType type;
	int side;
	int wizard;
	int creature;
	SacSpell!B spell;
	Target target;
	float targetFacing;
	Formation formation=Formation.init;
	int group=-1;

	bool isApplicable(B)(ObjectState!B state){
		return (wizard==0||state.isValidTarget(wizard,TargetType.creature)) &&
			(creature==0||state.isValidTarget(creature,TargetType.creature)) &&
			(target.id==0&&target.type.among(TargetType.none,TargetType.terrain)||state.isValidTarget(target.id,target.type));
	}

	int id=0;
	int opCmp(ref Command!B rhs){
		return tuple(side,id).opCmp(tuple(rhs.side,rhs.id));
	}
	auto queueing=CommandQueueing.none;
}

struct GameInit(B){
	struct Slot{
		int wizardIndex=-1;
	}
	Slot[] slots;
	struct Wizard{
		WizardTag tag;
		string name;
		int side=-1;
		int level=1;
		int souls=0;
		float experience=0.0f;
		Spellbook!B spellbook;
	}
	Wizard[] wizards;
	struct StanceSetting{
		int from, towards;
		Stance stance;
	}
	StanceSetting[] stanceSettings;
	int replicateCreatures=1;
	int protectManafounts=0;
}

bool playAudio=true;
final class GameState(B){
	ObjectState!B lastCommitted;
	ObjectState!B current;
	ObjectState!B next;
	Array!(Array!(Command!B)) commands;
	this(SacMap!B map)in{
		assert(!!map);
	}do{
		auto sides=new Sides!B(map.sids);
		auto proximity=new Proximity!B();
		auto pathFinder=new PathFinder!B(map);
		auto triggers=new Triggers!B(map.trig);
		this(map,sides,proximity,pathFinder,triggers);
	}
	this(SacMap!B map,Sides!B sides,Proximity!B proximity,PathFinder!B pathFinder,Triggers!B triggers){
		auto current=new ObjectState!B(map,sides,proximity,pathFinder,triggers);
		auto next=new ObjectState!B(map,sides,proximity,pathFinder,triggers);
		auto lastCommitted=new ObjectState!B(map,sides,proximity,pathFinder,triggers);
		this(current,next,lastCommitted);
	}
	this(ObjectState!B current,ObjectState!B next,ObjectState!B lastCommitted){
		this.current=current;
		this.next=next;
		this.lastCommitted=lastCommitted;
		commands.length=1;
	}
	void placeStructure(ref Structure ntt){
		import nttData;
		auto data=ntt.tag in bldgs;
		enforce(!!data);
		auto flags=ntt.flags&~Flags.damaged&~ntt.flags.destroyed;
		auto facing=2*pi!float/360.0f*ntt.facing;
		auto buildingId=current.addObject(Building!B(data,ntt.side,flags,facing));
		assert(!!buildingId);
		if(ntt.id !in current.triggers.objectIds) // e.g. for some reason, the two altars on ferry have the same id
			current.triggers.associateId(ntt.id,buildingId);
		auto position=Vector3f(ntt.x,ntt.y,ntt.z);
		auto ci=cast(int)(position.x/10+0.5);
		auto cj=cast(int)(position.y/10+0.5);
		import bldg;
		if(data.flags&BldgFlags.ground){
			auto ground=data.ground;
			auto n=current.map.n,m=current.map.m;
			foreach(j;max(0,cj-4)..min(n,cj+4)){
				foreach(i;max(0,ci-4)..min(m,ci+4)){
					auto dj=j-(cj-4), di=i-(ci-4);
					if(ground[dj][di])
						current.map.tiles[j][i]=ground[dj][di];
				}
			}
		}
		current.buildingById!((ref Building!B building){
			if(ntt.flags&Flags.damaged) building.health/=10.0f;
			if(ntt.flags&Flags.destroyed) building.health=0.0f;
			foreach(ref component;data.components){
				auto curObj=SacObject!B.getBLDG(ntt.flags&Flags.destroyed&&component.destroyed!="\0\0\0\0"?component.destroyed:component.tag);
				auto offset=Vector3f(component.x,component.y,component.z);
				offset=rotate(facingQuaternion(building.facing), offset);
				auto cposition=position+offset;
				if(!current.isOnGround(cposition)) continue;
				cposition.z=current.getGroundHeight(cposition);
				auto rotation=facingQuaternion(2*pi!float/360.0f*(ntt.facing+component.facing));
				building.componentIds~=current.addObject(StaticObject!B(curObj,building.id,cposition,rotation,1.0f,0));
			}
			if(ntt.base){
				enforce(ntt.base in current.triggers.objectIds);
				current.buildingById!((ref manafount,state){ putOnManafount(building,manafount,state); },(){})(current.triggers.objectIds[ntt.base],current);
			}
			building.loopingSoundSetup(current);
		},(){ assert(0); })(buildingId);
	}

	void placeNTT(T)(ref T ntt) if(is(T==Creature)||is(T==Wizard)){
		auto curObj=SacObject!B.getSAXS!T(ntt.tag);
		auto position=Vector3f(ntt.x,ntt.y,ntt.z);
		bool onGround=current.isOnGround(position);
		if(onGround)
			position.z=current.getGroundHeight(position);
		auto rotation=facingQuaternion(ntt.facing);
		auto mode=ntt.flags & Flags.corpse ? CreatureMode.dead : CreatureMode.idle;
		auto movement=curObj.mustFly?CreatureMovement.flying:CreatureMovement.onGround;
		if(movement==CreatureMovement.onGround && !onGround)
			movement=curObj.canFly?CreatureMovement.flying:CreatureMovement.tumbling;
		auto creatureState=CreatureState(mode, movement, ntt.facing);
		auto obj=MovingObject!B(curObj,position,rotation,AnimationState.stance1,0,creatureState,curObj.creatureStats(ntt.flags),ntt.side);
		obj.setCreatureState(current);
		obj.updateCreaturePosition(current);
		/+do{
			import std.random: uniform;
			state=cast(AnimationState)uniform(0,64);
		}while(!curObj.hasAnimationState(state));+/
		auto id=current.addObject(obj);
		if(ntt.id !in current.triggers.objectIds) // e.g. for some reason, the two altars on ferry have the same id
			current.triggers.associateId(ntt.id,id);
		static if(is(T==Wizard)){
			auto spellbook=getDefaultSpellbook!B(ntt.allegiance);
			string name=null; // unnamed wizard
			current.addWizard(makeWizard(id,name,ntt.level,ntt.souls,move(spellbook),current));
		}
	}
	void placeSpirit(ref Spirit spirit){
		auto position=Vector3f(spirit.x,spirit.y,spirit.z);
		bool onGround=current.isOnGround(position);
		if(onGround)
			position.z=current.getGroundHeight(position);
		current.addObject(Soul!B(1,position,SoulState.normal));
	}
	void placeWidgets(Widgets w){
		auto curObj=SacObject!B.getWIDG(w.tag);
		foreach(pos;w.positions){
			auto position=Vector3f(pos[0],pos[1],0);
			if(!current.isOnGround(position)) continue;
			position.z=current.getGroundHeight(position);
			// original engine screws up widget rotations
			// values look like angles in degrees, but they are actually radians
			auto rotation=facingQuaternion(-pos[2]);
			current.addFixed(FixedObject!B(curObj,position,rotation));
		}
	}

	struct SlotInfo{ int controlledSide=-1; int wizard=0; }
	Array!SlotInfo slots;
	void initGame(GameInit!B gameInit){ // returns id of controlled wizard
		foreach(ref structure;current.map.ntts.structures)
			placeStructure(structure);
		foreach(ref wizard;current.map.ntts.wizards)
			placeNTT(wizard);
		foreach(ref spirit;current.map.ntts.spirits)
			placeSpirit(spirit);
		foreach(ref creature;current.map.ntts.creatures)
			foreach(_;0..gameInit.replicateCreatures) placeNTT(creature);
		foreach(widgets;current.map.ntts.widgetss) // TODO: improve engine to be able to handle this
			placeWidgets(widgets);
		current.eachMoving!((ref MovingObject!B object, ObjectState!B state){
			if(object.creatureState.mode==CreatureMode.dead) object.createSoul(state);
		})(current);

		if(gameInit.protectManafounts){
			foreach(i;0..gameInit.protectManafounts) current.uniform(2);
			current.eachBuilding!((bldg,state){
				if(bldg.componentIds.length==0||!bldg.isManafount) return;
				auto bpos=bldg.position(state);
				import nttData;
				static immutable lv1Creatures=[persephoneCreatures[0..3],pyroCreatures[0..3],jamesCreatures[0..3],stratosCreatures[0..3],charnelCreatures[0..3]];
				auto tags=lv1Creatures[state.uniform(cast(int)$)];
				foreach(i;0..10){
					auto tag=tags[state.uniform(cast(int)$)];
					int flags=0;
					int side=1;
					auto position=bpos+10.0f*state.uniformDirection();
					import dlib.math.portable;
					auto facing=state.uniform(-pi!float,pi!float);
					state.placeCreature(tag,flags,side,position,facing);
				}
			})(current);
		}
		slots.length=gameInit.slots.length;
		slots.data[]=SlotInfo.init;
		Array!int slotForWiz;
		slotForWiz.length=gameInit.wizards.length;
		slotForWiz.data[]=-1;
		foreach(i,ref slot;gameInit.slots)
			if(slot.wizardIndex!=-1) slotForWiz[slot.wizardIndex]=cast(int)i;
		foreach(wizardIndex,ref wiz;gameInit.wizards){
			auto wizard=SacObject!B.getSAXS!Wizard(wiz.tag);
			//printWizardStats(wizard);
			auto flags=0;
			auto wizId=current.placeWizard(wizard,wiz.name,flags,wiz.side,wiz.level,wiz.souls,wiz.spellbook);
			auto slot=slotForWiz[wizardIndex];
			if(slot!=-1){
				slots[slot].controlledSide=wiz.side;
				slots[slot].wizard=wizId;
			}
		}
		foreach(ref stanceSetting;gameInit.stanceSettings)
			current.sides.setStance(stanceSetting.from,stanceSetting.towards,stanceSetting.stance);
	}

	void step(){
		current.update(commands[current.frame].data);
		//next.updateFrom(current,commands[current.frame].data);
		//swap(current,next);
		if(commands.length<=current.frame) commands~=Array!(Command!B)();
	}
	void stepCommitted()in{
		assert(lastCommitted.frame<current.frame);
	}do{
		lastCommitted.update(commands[lastCommitted.frame].data);
		//next.updateFrom(lastCommitted,commands[lastCommitted.frame].data);
		//swap(lastCommitted,next);
	}
	// may violate invariant lastCommitted.frame<=current.frame, should be restored
	// may go out of command bounds
	void stepCommittedUnsafe()in{
		assert(lastCommitted.frame<commands.length);
	}do{
		lastCommitted.update(commands[lastCommitted.frame].data);
	}
	void commit(){
		lastCommitted.copyFrom(current);
	}
	void rollback(){
		rollback(lastCommitted);
	}
	void rollback(ObjectState!B state)in{
		assert(state.frame<=current.frame);
	}do{
		current.copyFrom(state);
		static if(B.hasAudio) B.updateAudioAfterRollback();
	}
	void rollback(int frame)in{
		assert(frame>=lastCommitted.frame);
	}do{
		if(frame<current.frame) rollback(lastCommitted);
		playAudio=false;
		simulateTo(frame);
	}
	void simulateTo(int frame)in{
		assert(frame>=current.frame);
	}do{
		while(current.frame<frame)
			step();
	}
	void simulateCommittedTo(int frame)in{
		assert(frame<=current.frame);
	}do{
		while(lastCommitted.frame<frame)
			stepCommitted();
	}
	void addCommandInconsistent(int frame,Command!B command)in{
		assert(frame>=lastCommitted.frame);
	}do{
		if(command.side==-1) return;
		if(commands.length<=frame) commands.length=frame+1;
		commands[frame]~=command;
		if(!isSorted(commands[frame].data))
			sort(commands[frame].data);
	}
	void addCommand(int frame,Command!B command)in{
		assert(frame<=current.frame);
		assert(command.id!=0);
		assert(frame>=lastCommitted.frame);
	}do{
		if(command.side==-1) return;
		assert(frame<commands.length);
		auto currentFrame=current.frame;
		commands[frame]~=command;
		if(!isSorted(commands[frame].data))
			sort(commands[frame].data);
		if(frame<currentFrame) rollback(frame);
		playAudio=false;
		simulateTo(currentFrame);
	}

}
