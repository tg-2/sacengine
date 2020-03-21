import std.algorithm, std.range;
import std.container.array: Array;
import std.exception, std.stdio, std.conv;
import dlib.math, dlib.math.portable, dlib.image.color;
import std.typecons;
import sids, ntts, nttData, bldg, sset;
import sacmap, sacobject, animations, sacspell;
import stats;
import util,options;
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
	pretendingToDie,
	playingDead,
	pretendingToRevive,
	rockForm,
}

bool isMoving(CreatureMode mode){
	with(CreatureMode) return !!mode.among(moving,meleeMoving,castingMoving);
}
bool isCasting(CreatureMode mode){
	with(CreatureMode) return !!mode.among(casting,stationaryCasting,castingMoving);
}
bool isShooting(CreatureMode mode){
	with(CreatureMode) return mode==shooting;
}
bool isHidden(CreatureMode mode){
	with(CreatureMode) return !!mode.among(pretendingToDie,playingDead,rockForm);
}
bool isVisibleToAI(CreatureMode mode){
	final switch(mode) with(CreatureMode){
		case idle,moving,spawning,takeoff,landing,meleeMoving,meleeAttacking,stunned,cower,casting,stationaryCasting,castingMoving,shooting: return true;
		case dying,dead,dissolving,preSpawning,reviving,fastReviving,pretendingToDie,playingDead,pretendingToRevive,rockForm: return false;
	}
}
bool isObstacle(CreatureMode mode){
	final switch(mode) with(CreatureMode){
		case idle,moving,dying,spawning,reviving,fastReviving,takeoff,landing,meleeMoving,meleeAttacking,stunned,cower,casting,stationaryCasting,castingMoving,shooting,
			pretendingToDie,playingDead,pretendingToRevive,rockForm: return true;
		case dead,dissolving,preSpawning: return false;
	}
}
bool isValidAttackTarget(CreatureMode mode){
	final switch(mode) with(CreatureMode){
		case idle,moving,dying,spawning,takeoff,landing,meleeMoving,meleeAttacking,stunned,cower,casting,stationaryCasting,castingMoving,shooting: return true;
		case dead,dissolving,preSpawning,reviving,fastReviving,pretendingToDie,playingDead,pretendingToRevive,rockForm: return false;
	}
}
bool canHeal(CreatureMode mode){
	final switch(mode) with(CreatureMode){
		case idle,moving,spawning,takeoff,landing,meleeMoving,meleeAttacking,stunned,cower,casting,stationaryCasting,castingMoving,shooting,
			pretendingToDie,playingDead,pretendingToRevive,rockForm: return true;
		case dying,dead,dissolving,preSpawning,reviving,fastReviving: return false;
	}
}
bool canShield(CreatureMode mode){
	final switch(mode) with(CreatureMode){
		case idle,moving,spawning,takeoff,landing,meleeMoving,meleeAttacking,stunned,cower,casting,stationaryCasting,castingMoving,shooting,pretendingToDie,playingDead,pretendingToRevive,rockForm: return true;
		case dying,dead,dissolving,preSpawning,reviving,fastReviving: return false;
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
	if(!state.isValidTarget(target.id)) return target.position;
	return state.objectById!((obj)=>obj.center)(target.id);
}
Vector3f lowCenter(B)(ref OrderTarget target,ObjectState!B state){
	if(!state.isValidTarget(target.id)) return target.position;
	return state.objectById!((obj)=>obj.lowCenter)(target.id);
}
OrderTarget centerTarget(B)(int id,ObjectState!B state)in{
	assert(state.isValidTarget(id));
}do{
	auto position=state.objectById!((obj)=>obj.center)(id);
	return OrderTarget(state.targetTypeFromId(id),id,position);
}

Vector3f[2] hitbox(B)(ref OrderTarget target,ObjectState!B state){
	if(!state.isValidTarget(target.id)) return [target.position,target.position];
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

Vector3f getTargetPosition(B)(Vector3f targetPosition,float targetFacing,Vector2f formationOffset,ObjectState!B state){
	targetPosition+=rotate(facingQuaternion(targetFacing), Vector3f(formationOffset.x,formationOffset.y,0));
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
		if(!state.isValidTarget(target.id)) return target.position;
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

struct CreatureAI{
	Order order;
	Queue!Order orderQueue;
	Formation formation;
	bool isColliding=false;
	RotationDirection evasion;
	int evasionTimer=0;
	int rangedAttackTarget=0;
	PositionPredictor predictor;
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
float speedOnGround(B)(ref MovingObject!B object,ObjectState!B state){
	return object.creatureStats.movementSpeed(false);
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
bool canSelect(B)(ref MovingObject!B obj,int side,ObjectState!B state){
	return obj.side==side&&!obj.isWizard&&!obj.isPeasant&&!obj.creatureState.mode.among(CreatureMode.dead,CreatureMode.dissolving);
}
bool canOrder(B)(ref MovingObject!B obj,int side,ObjectState!B state){
	return (side==-1||obj.side==side)&&!obj.creatureState.mode.among(CreatureMode.dead,CreatureMode.dissolving);
}
bool canSelect(B)(int side,int id,ObjectState!B state){
	return state.movingObjectById!(canSelect,()=>false)(id,side,state);
}
bool isPacifist(B)(ref MovingObject!B obj,ObjectState!B state){
	return obj.sacObject.isPacifist;
}
bool isAggressive(B)(ref MovingObject!B obj,ObjectState!B state){
	if(obj.isPacifist(state)) return false;
	if(obj.creatureStats.effects.stealth) return false;
	return true;
}
float aggressiveRange(B)(ref MovingObject!B obj,CommandType type,ObjectState!B state){
	return obj.sacObject.aggressiveRange;
}
float advanceRange(B)(ref MovingObject!B obj,CommandType type,ObjectState!B state){
	return obj.sacObject.aggressiveRange;
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
	auto hbox=object.hitbox;
	return 0.5f*(hbox[0]+hbox[1]);
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

Vector3f shotPosition(B)(ref MovingObject!B object){
	auto loc=object.sacObject.shotPosition(object.animationState,object.frame/updateAnimFactor);
	return object.position+rotate(object.rotation,loc);
}
SacObject!B.LoadedArrow loadedArrow(B)(ref MovingObject!B object){
	auto result=object.sacObject.loadedArrow(object.animationState,object.frame/updateAnimFactor);
	foreach(ref pos;result.tupleof) pos=object.position+rotate(object.rotation,pos);
	return result;
}
AnimationState shootAnimation(B)(ref MovingObject!B object){
	final switch(object.creatureState.movement) with(CreatureMovement){
		case onGround:
			return AnimationState.shoot0;
		case flying:
			if(object.sacObject.mustFly)
				goto case onGround;
			return AnimationState.flyShoot;
		case tumbling:
			goto case onGround;
	}
}
Vector3f firstShotPosition(B)(ref MovingObject!B object){
	auto loc=object.sacObject.firstShotPosition(object.shootAnimation);
	return object.position+rotate(object.rotation,loc);
}

int numAttackTicks(B)(ref MovingObject!B object){
	return object.sacObject.numAttackTicks(object.animationState);
}

bool hasAttackTick(B)(ref MovingObject!B object){
	return object.frame%updateAnimFactor==0 && object.sacObject.hasAttackTick(object.animationState,object.frame/updateAnimFactor);
}

SacSpell!B rangedAttack(B)(ref MovingObject!B object){ return object.sacObject.rangedAttack; }

bool hasLoadTick(B)(ref MovingObject!B object){
	return object.frame%updateAnimFactor==0 && object.sacObject.hasLoadTick(object.animationState,object.frame/updateAnimFactor);
}

int numShootTicks(B)(ref MovingObject!B object){
	return object.sacObject.numShootTicks(object.animationState);
}

bool hasShootTick(B)(ref MovingObject!B object){
	return object.frame%updateAnimFactor==0 && object.sacObject.hasShootTick(object.animationState,object.frame/updateAnimFactor);
}

SacSpell!B ability(B)(ref MovingObject!B object){ return object.sacObject.ability; }
SacSpell!B passiveAbility(B)(ref MovingObject!B object){ return object.sacObject.passiveAbility; }

StunBehavior stunBehavior(B)(ref MovingObject!B object){
	return object.sacObject.stunBehavior;
}

StunnedBehavior stunnedBehavior(B)(ref MovingObject!B object){
	return object.sacObject.stunnedBehavior;
}

bool isRegenerating(B)(ref MovingObject!B object){
	return object.creatureState.mode.among(CreatureMode.idle,CreatureMode.playingDead,CreatureMode.rockForm)||object.sacObject.continuousRegeneration&&!object.creatureState.mode.among(CreatureMode.dying,CreatureMode.dead,CreatureMode.dissolving);
}

bool isDamaged(B)(ref MovingObject!B object){
	return object.health<=0.25f*object.creatureStats.maxHealth;
}

bool isHidden(B)(ref MovingObject!B object){
	if(object.creatureState.mode.isHidden) return true;
	if(object.creatureStats.effects.stealth) return true;
	return false;
}

struct StaticObject(B){
	SacObject!B sacObject;
	int id=0;
	int buildingId=0;
	Vector3f position;
	Quaternionf rotation;
	this(SacObject!B sacObject,int buildingId,Vector3f position,Quaternionf rotation){
		this.sacObject=sacObject;
		this.buildingId=buildingId;
		this.position=position;
		this.rotation=rotation;
	}
	this(SacObject!B sacObject,int id,int buildingId,Vector3f position,Quaternionf rotation){
		this.id=id;
		this(sacObject,buildingId,position,rotation);
	}
}
float healthFromBuildingId(B)(int buildingId,ObjectState!B state){
	return state.buildingById!((ref b)=>b.health,function int(){ assert(0); })(buildingId);
}
float health(B)(ref StaticObject!B object,ObjectState!B state){
	return healthFromBuildingId(object.buildingId,state);
}
int sideFromBuildingId(B)(int buildingId,ObjectState!B state){
	return state.buildingById!((ref b)=>b.side,function int(){ assert(0); })(buildingId);
}
int flagsFromBuildingId(B)(int buildingId,ObjectState!B state){
	return state.buildingById!((ref b)=>b.flags,function int(){ assert(0); })(buildingId);
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
}

struct Soul(B){
	int id=0;
	int creatureId=0;
	int preferredSide=-1;
	int collectorId=0;
	int number;
	Vector3f position;
	SoulState state;
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
	if(soul.creatureId==0) return -1;
	return soul.preferredSide;
}
int soulSide(B)(int id,ObjectState!B state){
	return state.soulById!(side,function int(){ assert(0); })(id,state);
}
SoulColor color(B)(ref Soul!B soul,int side,ObjectState!B state){
	auto soulSide=soul.side(state);
	return soulSide==-1||soulSide==side?SoulColor.blue:SoulColor.red;
}
SoulColor color(B)(int id,int side,ObjectState!B state){
	return state.soulById!(color,function SoulColor(){ assert(0); })(id,side,state);
}

Vector3f[2] hitbox2d(B)(ref Soul!B soul,Matrix4f modelViewProjectionMatrix){
	auto topLeft=Vector3f(-SacSoul!B.soulWidth/2,-SacSoul!B.soulHeight/2,0.0f)*soul.scaling;
	auto bottomRight=-topLeft;
	return [transform(modelViewProjectionMatrix,topLeft),transform(modelViewProjectionMatrix,bottomRight)];
}

enum AdditionalBuildingFlags{
	none=0,
	inactive=32, // TODO: make sure this doesn't clash with anything
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
	this(immutable(Bldg)* bldg,int side,int flags,float facing){
		this.bldg=bldg;
		this.side=side;
		this.flags=flags;
		this.facing=facing;
		this.health=bldg.maxHealth;
	}
	void opAssign(ref Building!B rhs){
		this.bldg=rhs.bldg;
		this.id=rhs.id;
		this.side=rhs.side;
		assignArray(componentIds,rhs.componentIds);
		health=rhs.health;
		flags=rhs.flags;
		facing=rhs.facing;
		top=rhs.top;
		base=rhs.base;
	}
	void opAssign(Building!B rhs){ this.tupleof=move(rhs).tupleof; }
	this(this){ componentIds=componentIds.dup; } // TODO: needed?
}
int maxHealth(B)(ref Building!B building,ObjectState!B state){
	return building.bldg.maxHealth;
}
Vector3f position(B)(ref Building!B building,ObjectState!B state){
	return state.staticObjectById!((obj)=>obj.position,function Vector3f(){ assert(0); })(building.componentIds[0]);
}
float height(B)(ref Building!B building,ObjectState!B state){
	float maxZ=0.0f;
	foreach(cid;building.componentIds){
		state.staticObjectById!((obj,state){
			auto hitbox=obj.hitbox;
			maxZ=max(maxZ,hitbox[1].z-obj.position.z);
		})(cid,state);
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
	state.buildingById!((ref obj){ assert(obj.base==manafount.id); obj.base=0; })(manafount.top);
	manafount.top=0;
	manafount.activate(state);
}
void loopingSoundSetup(B)(ref Building!B building,ObjectState!B state){
	static if(B.hasAudio){
		if(building.flags&AdditionalBuildingFlags.inactive) return;
		if(playAudio){
			foreach(cid;building.componentIds)
				state.staticObjectById!(B.loopingSoundSetup)(cid);
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

struct Particle(B,bool relative=false){ // TODO: some particles don't need some fields. Optimize?
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
	}

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
		static if(mode==RenderMode.transparent)
			alphas.length=l;
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
		static if(mode==RenderMode.transparent)
			alphas.reserve(reserveSize);
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
		static if(mode==RenderMode.transparent)
			alphas~=1.0f;
	}
	void removeObject(int index, ObjectManager!B manager){
		manager.ids[ids[index]-1]=Id.init;
		if(index+1<length){
			this[index]=this.fetch(length-1); // TODO: swap?
			static if(mode==RenderMode.transparent)
				alphas[index]=alphas[length-1];
			manager.ids[ids[index]-1].index=index;
		}
		length=length-1;
	}
	void opAssign(ref MovingObjects!(B,mode) rhs){
		sacObject = rhs.sacObject;
		assignArray(ids,rhs.ids);
		assignArray(positions,rhs.positions);
		assignArray(rotations,rhs.rotations);
		assignArray(animationStates,rhs.animationStates);
		assignArray(frames,rhs.frames);
		assignArray(creatureAIs,rhs.creatureAIs);
		assignArray(creatureStates,rhs.creatureStates);
		assignArray(creatureStatss,rhs.creatureStatss);
		assignArray(sides,rhs.sides);
		assignArray(soulIds,rhs.soulIds);
		static if(mode==RenderMode.transparent)
			assignArray(alphas,rhs.alphas);
	}
	void opAssign(MovingObjects!(B,mode) rhs){ this.tupleof=rhs.tupleof; }
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
		// TODO: alphas ok?
	}
	static if(mode==RenderMode.transparent){
		void setAlpha(int i,float alpha){
			alphas[i]=alpha;
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

	static if(mode==RenderMode.transparent){
		Array!float thresholdZs;
	}
	@property int length(){ assert(ids.length<=int.max); return cast(int)ids.length; }
	@property void length(int l){
		ids.length=l;
		buildingIds.length=l;
		positions.length=l;
		rotations.length=l;
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
		static if(mode==RenderMode.transparent)
			thresholdZs~=0.0f;
	}
	void removeObject(int index, ObjectManager!B manager){
		manager.ids[ids[index]-1]=Id.init;
		if(index+1<length){
			this[index]=this[length-1];
			static if(mode==RenderMode.transparent)
				thresholdZs[index]=thresholdZs[length-1];
			manager.ids[ids[index]-1].index=index;
		}
		length=length-1;
	}
	void opAssign(ref StaticObjects!(B,mode) rhs){
		sacObject=rhs.sacObject;
		assignArray(ids,rhs.ids);
		assignArray(buildingIds,rhs.buildingIds);
		assignArray(positions,rhs.positions);
		assignArray(rotations,rhs.rotations);
		static if(mode==RenderMode.transparent)
			assignArray(thresholdZs,rhs.thresholdZs);
	}
	void opAssign(StaticObjects!(B,mode) rhs){ this.tupleof=rhs.tupleof; }
	StaticObject!B opIndex(int i){
		return StaticObject!B(sacObject,ids[i],buildingIds[i],positions[i],rotations[i]);
	}
	void opIndexAssign(StaticObject!B obj,int i){
		assert(sacObject is obj.sacObject);
		ids[i]=obj.id;
		buildingIds[i]=obj.buildingId;
		positions[i]=obj.position;
		rotations[i]=obj.rotation;
		// TODO: thresholdZ ok?
	}
	static if(mode==RenderMode.transparent){
		void setThresholdZ(int i,float thresholdZ){
			thresholdZs[i]=thresholdZ;
		}
	}
}
auto each(alias f,B,RenderMode mode,T...)(ref StaticObjects!(B,mode) staticObjects,T args){
	foreach(i;0..staticObjects.length)
		f(staticObjects[i],args);
}

struct FixedObjects(B){
	enum renderMode=RenderMode.opaque;
	SacObject!B sacObject;
	Array!Vector3f positions;
	Array!Quaternionf rotations;
	@property int length(){ assert(positions.length<=int.max); return cast(int)positions.length; }

	void addFixed(FixedObject!B object)in{
		assert(sacObject==object.sacObject);
	}body{
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
	@property int length(){ return cast(int)souls.length; }
	@property void length(int l){ souls.length=l; }
	void addObject(Soul!B soul){
		souls~=soul;
	}
	void removeObject(int index, ObjectManager!B manager){
		manager.ids[souls[index].id-1]=Id.init;
		if(index+1<length){
			this[index]=move(this[length-1]);
			manager.ids[souls[index].id-1].index=index;
		}
		length=length-1;
	}
	void opAssign(ref Souls!B rhs){ assignArray(souls,rhs.souls); }
	void opAssign(Souls!B rhs){ this.tupleof=rhs.tupleof; }
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
	@property int length(){ return cast(int)buildings.length; }
	@property void length(int l){ buildings.length=l; }
	void addObject(Building!B building){
		buildings~=move(building);
	}
	void removeObject(int index, ObjectManager!B manager){
		manager.ids[buildings[index].id-1]=Id.init;
		if(index+1<length){
			swap(this[index],this[length-1]); // TODO: reuse memory?
			manager.ids[buildings[index].id-1].index=index;
		}
		length=length-1;
	}
	void opAssign(ref Buildings!B rhs){
		buildings.length=rhs.buildings.length;
		foreach(i;0..buildings.length)
			buildings[i]=rhs.buildings[i];
	}
	void opAssign(Buildings!B rhs){ this.tupleof=rhs.tupleof; }
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
	void opAssign(ref Spellbook!B rhs){ assignArray(spells,rhs.spells); }
	void opAssign(Spellbook!B rhs){ this.tupleof=rhs.tupleof; }
	this(this){ spells=spells.dup; }
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

Spellbook!B getDefaultSpellbook(B)(God god){
	Spellbook!B result;
	foreach(tag;neutralCreatures)
		result.addSpell(0,SacSpell!B.get(tag));
	foreach(tag;neutralSpells)
		result.addSpell(0,SacSpell!B.get(tag));
	foreach(tag;structureSpells[0..$-1])
		result.addSpell(0,SacSpell!B.get(tag));
	if(god==God.none){
		result.addSpell(3,SacSpell!B.get(structureSpells[$-1]));
		return result;
	}
	enforce(creatureSpells[god].length==11);
	enforce(normalSpells[god].length==11);
	foreach(lv;1..9+1){
		if(lv==3) result.addSpell(3,SacSpell!B.get(structureSpells[$-1]));
		if(lv==1){
			foreach(tag;creatureSpells[god][1..4])
				result.addSpell(lv,SacSpell!B.get(tag));
			result.addSpell(lv,SacSpell!B.get(normalSpells[god][lv+1]));
		}else if(lv<8){
			result.addSpell(lv,SacSpell!B.get(creatureSpells[god][lv+2]));
			result.addSpell(lv,SacSpell!B.get(normalSpells[god][lv+1]));
		}else if(lv==8){
			foreach(tag;normalSpells[god][9..11])
				result.addSpell(lv,SacSpell!B.get(tag));
		}else if(lv==9){
			result.addSpell(lv,SacSpell!B.get(creatureSpells[god][lv+1]));
		}
	}
	return result;
}

struct WizardInfo(B){
	int id;
	int level;
	int souls;
	float experience;
	Spellbook!B spellbook;

	void opAssign(ref WizardInfo!B rhs){
		id=rhs.id;
		level=rhs.level;
		souls=rhs.souls;
		experience=rhs.experience;
		spellbook=rhs.spellbook;
	}
	void opAssign(WizardInfo!B rhs){ this.tupleof=rhs.tupleof; }
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
WizardInfo!B makeWizard(B)(int id,int level,int souls,Spellbook!B spellbook,ObjectState!B state){
	state.movingObjectById!((ref wizard,level,state){
		wizard.creatureStats.maxHealth+=50.0f*level;
		wizard.creatureStats.health+=50.0f*level;
		wizard.creatureStats.mana+=100*level;
		wizard.creatureStats.maxMana+=100*level;
		// TODO: boons
	})(id,level,state);
	return WizardInfo!B(id,level,souls,0.0f,move(spellbook));
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

int placeWizard(B)(ObjectState!B state,SacObject!B wizard,int flags,int side,int level,int souls,Spellbook!B spellbook,Vector3f position,float facing){
	auto id=state.placeCreature(wizard,flags,side,position,facing);
	state.addWizard(makeWizard(id,level,souls,move(spellbook),state));
	return id;
}

int placeWizard(B)(ObjectState!B state,SacObject!B wizard,int flags,int side,int level,int souls,Spellbook!B spellbook)in{
	assert(wizard.isWizard);
}do{
	bool flag=false;
	int id=0;
	state.eachBuilding!((ref bldg,state,id,wizard,flags,side,level,souls,spellbook){
		if(*id||bldg.componentIds.length==0) return;
		if(bldg.side==side && bldg.isAltar){
			auto altar=state.staticObjectById!((obj)=>obj, function StaticObject!B(){ assert(0); })(bldg.componentIds[0]);
			int closestManafount=0;
			Vector3f manafountPosition;
			state.eachBuilding!((bldg,altarPos,closest,manaPos,state){
				if(bldg.componentIds.length==0||!bldg.isManafount) return;
				auto pos=bldg.position(state);
				if(*closest==0||(altarPos.xy-pos.xy).length<(altarPos.xy-manaPos.xy).length){
					*closest=bldg.id;
					*manaPos=pos;
				}
			})(altar.position,&closestManafount,&manafountPosition,state);
			enum distance=15.0f;
			float facing;
			Vector3f position;
			if(closestManafount){
				auto dir2d=(manafountPosition-altar.position).xy.normalized*distance;
				facing=atan2(dir2d.y,dir2d.x)-pi!float/2.0f;
				position=altar.position+Vector3f(dir2d.x,dir2d.y,0.0f);
			}else{
				auto facingOffset=(bldg.isStratosAltar?pi!float/4.0f:0.0f)+pi!float;
				facing=bldg.facing+facingOffset;
				position=altar.position+rotate(facingQuaternion(facing),Vector3f(0.0f,distance,0.0f));
			}
			*id=state.placeWizard(wizard,flags,side,level,souls,move(spellbook),position,facing);
		}
	})(state,&id,wizard,flags,side,level,souls,move(spellbook));
	return id;
}

struct WizardInfos(B){
	Array!(WizardInfo!B) wizards;
	@property int length(){ assert(wizards.length<=int.max); return cast(int)wizards.length; }
	@property void length(int l){
		wizards.length=l;
	}
	void addWizard(WizardInfo!B wizard){
		wizards~=wizard;
	}
	void removeWizard(int id){
		auto index=indexForId(id);
		if(index!=-1){
			if(index+1<wizards.length)
				swap(wizards[index],wizards[$-1]); // TODO: reuse memory?
			wizards.length=wizards.length-1;
		}
	}
	void opAssign(ref WizardInfos!B rhs){
		assignArray(wizards,rhs.wizards);
	}
	void opAssign(WizardInfos!B rhs){ this.tupleof=rhs.tupleof; }
	ref WizardInfo!B opIndex(int i){
		return wizards[i];
	}
	int indexForId(int id){
		foreach(i;0..wizards.length) if(wizards[i].id==id) return cast(int)i;
		return -1;
	}
	WizardInfo!B* getWizard(int id){
		auto index=indexForId(id);
		if(index==-1) return null;
		return &wizards[index];
	}
}
auto each(alias f,B,T...)(ref WizardInfos!B wizards,T args){
	foreach(i;0..wizards.length)
		f(wizards[i],args);
}

struct Particles(B,bool relative){
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
	}
	void addParticle(Particle!(B,relative) particle){
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
	}
	void removeParticle(int index){
		if(index+1<length) this[index]=this[length-1];
		length=length-1;
	}
	void opAssign(ref Particles!(B,relative) rhs){
		sacParticle = rhs.sacParticle;
		static if(relative){
			assignArray(baseIds,rhs.baseIds);
			assignArray(rotates,rhs.rotates);
		}
		assignArray(positions,rhs.positions);
		assignArray(velocities,rhs.velocities);
		assignArray(scales,rhs.scales);
		assignArray(lifetimes,rhs.lifetimes);
		assignArray(frames,rhs.frames);
	}
	void opAssign(Particles!(B,relative) rhs){ this.tupleof=rhs.tupleof; }
	Particle!(B,relative) opIndex(int i){
		static if(relative) return Particle!(B,true)(sacParticle,baseIds[i],!!rotates[i],positions[i],velocities[i],scales[i],lifetimes[i],frames[i]);
		else return Particle!(B,false)(sacParticle,positions[i],velocities[i],scales[i],lifetimes[i],frames[i]);
	}
	void opIndexAssign(Particle!(B,relative) particle,int i){
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
	int attacker=0;
	int side=-1;
}
struct ManaDrain(B){
	int wizard;
	float manaCostPerFrame;
	int timer;
}
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
struct LightningBolt(B){
	Vector3f[numLightningSegments-1] displacement;
	void changeShape(ObjectState!B state){
		foreach(ref disp;displacement){
			enum size=2.5f;
			static immutable Vector3f[2] box=[-0.5f*size*Vector3f(1.0f,1.0f,1.0f),0.5f*size*Vector3f(1.0f,1.0f,1.0f)];
			disp=state.uniform(box);
		}
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
	int frame;
	this(int wizard,int side,OrderTarget start,OrderTarget end,SacSpell!B spell,int frame){
		this.wizard=wizard;
		this.side=side;
		this.start=start;
		this.end=end;
		this.spell=spell;
		this.frame=frame;
	}
	LightningBolt!B[2] bolts;
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
	SacSpell!B spell;
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

	void opAssign(ref Swarm!B rhs){
		this.tupleof[0..$-1]=rhs.tupleof[0..$-1];
		static assert(__traits(isSame,this.tupleof[$-1],this.bugs));
		assignArray(bugs,rhs.bugs);
	}
	void opAssign(Swarm!B rhs){ this.tupleof=rhs.tupleof; }
	this(this){ bugs=bugs.dup; } // TODO: needed?
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

	void opAssign(ref FallenProjectile!B rhs){
		this.tupleof[0..$-1]=rhs.tupleof[0..$-1];
		static assert(__traits(isSame,this.tupleof[$-1],this.bugs));
		assignArray(bugs,rhs.bugs);
	}
	void opAssign(FallenProjectile!B rhs){ this.tupleof=rhs.tupleof; }
	this(this){ bugs=bugs.dup; } // TODO: needed?
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
	enum targetAlpha=0.1f;
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
	Vector3f position;
	Vector3f velocity;
	SacSpell!B ability;
	int frame=0;
	float scale=0.0f;
	int target=0;
}

struct Protector(B){
	int id;
	SacSpell!B ability;
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
	// ordinary spells
	Array!(SpeedUp!B) speedUps;
	void addEffect(SpeedUp!B speedUp){
		speedUps~=speedUp;
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
	Array!(Protector!B) protectors;
	void addEffect(Protector!B protector){
		protectors~=protector;
	}
	void removeProtector(int i){
		if(i+1<protectors.length) protectors[i]=move(protectors[$-1]);
		protectors.length=protectors.length-1;
	}
	void opAssign(ref Effects!B rhs){
		assignArray(debris,rhs.debris);
		assignArray(explosions,rhs.explosions);
		assignArray(fires,rhs.fires);
		assignArray(manaDrains,rhs.manaDrains);
		assignArray(creatureCasts,rhs.creatureCasts);
		assignArray(structureCasts,rhs.structureCasts);
		assignArray(blueRings,rhs.blueRings);
		assignArray(teleportCastings,rhs.teleportCastings);
		assignArray(teleportEffects,rhs.teleportEffects);
		assignArray(teleportRings,rhs.teleportRings);
		assignArray(speedUps,rhs.speedUps);
		assignArray(speedUpShadows,rhs.speedUpShadows);
		assignArray(healCastings,rhs.healCastings);
		assignArray(heals,rhs.heals);
		assignArray(lightningCastings,rhs.lightningCastings);
		assignArray(lightnings,rhs.lightnings);
		assignArray(wrathCastings,rhs.wrathCastings);
		assignArray(wraths,rhs.wraths);
		assignArray(fireballCastings,rhs.fireballCastings);
		assignArray(fireballs,rhs.fireballs);
		assignArray(rockCastings,rhs.rockCastings);
		assignArray(rocks,rhs.rocks);
		assignArray(swarmCastings,rhs.swarmCastings);
		assignArray(swarms,rhs.swarms);
		assignArray(brainiacProjectiles,rhs.brainiacProjectiles);
		assignArray(brainiacEffects,rhs.brainiacEffects);
		assignArray(shrikeProjectiles,rhs.shrikeProjectiles);
		assignArray(shrikeEffects,rhs.shrikeEffects);
		assignArray(locustProjectiles,rhs.locustProjectiles);
		assignArray(spitfireProjectiles,rhs.spitfireProjectiles);
		assignArray(spitfireEffects,rhs.spitfireEffects);
		assignArray(gargoyleProjectiles,rhs.gargoyleProjectiles);
		assignArray(gargoyleEffects,rhs.gargoyleEffects);
		assignArray(earthflingProjectiles,rhs.earthflingProjectiles);
		assignArray(flameMinionProjectiles,rhs.flameMinionProjectiles);
		assignArray(fallenProjectiles,rhs.fallenProjectiles);
		assignArray(sylphEffects,rhs.sylphEffects);
		assignArray(sylphProjectiles,rhs.sylphProjectiles);
		assignArray(rangerEffects,rhs.rangerEffects);
		assignArray(rangerProjectiles,rhs.rangerProjectiles);
		assignArray(rockForms,rhs.rockForms);
		assignArray(stealths,rhs.stealths);
		assignArray(lifeShields,rhs.lifeShields);
		assignArray(protectors,rhs.protectors);
	}
	void opAssign(Effects!B rhs){ this.tupleof=rhs.tupleof; }
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
	void opAssign(ref CommandCones!B rhs){ assignArray(cones,rhs.cones); }
	void opAssign(CommandCones!B rhs){ this.tupleof=rhs.tupleof; }
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
		Effects!B effects;
		CommandCones!B commandCones;
	}
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
		void setAlpha(int type, int index, float alpha){
			enforce(0<=type&&type<numMoving);
			movingObjects[type].setAlpha(index, alpha);
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
		void removeWizard(int id){
			wizards.removeWizard(id);
		}
		void addEffect(T)(T proj){
			effects.addEffect(move(proj));
		}
		int getIndexParticle(bool relative)(SacParticle!B sacParticle,bool insert){
			static if(relative) alias particles=relativeParticles;
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
		void addParticle(bool relative)(Particle!(B,relative) particle){
			auto index=getIndexParticle!relative(particle.sacParticle,true);
			static if(relative) alias particles=relativeParticles;
			enforce(0<=index && index<particles.length);
			particles[index].addParticle(particle);
		}
		void addCommandCone(CommandCone!B cone){
			if(!commandCones.cones.length) commandCones.initialize(32); // TODO: do this eagerly?
			commandCones.addCommandCone(cone);
		}
	}
	void opAssign(Objects!(B,mode) rhs){
		assignArray(movingObjects,rhs.movingObjects);
		assignArray(staticObjects,rhs.staticObjects);
		static if(mode == RenderMode.opaque){
			fixedObjects=rhs.fixedObjects; // by reference
			souls=rhs.souls;
			buildings=rhs.buildings;
			wizards=rhs.wizards;
			effects=rhs.effects;
			assignArray(particles,rhs.particles);
			assignArray(relativeParticles,rhs.relativeParticles);
			commandCones=rhs.commandCones;
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
	static if(mode==RenderMode.opaque) with(objects){
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
	void setAlpha(int id,float alpha)in{
		assert(0<id && id<=ids.length);
	}do{
		auto tid=ids[id-1];
		enforce(tid.mode==RenderMode.transparent);
		transparentObjects.setAlpha(tid.type,tid.index,alpha);
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
			auto obj=this.movingObjectById!((obj)=>obj,function MovingObject!B(){ assert(0); })(id);
		}else{
			auto obj=this.staticObjectById!((obj)=>obj,function StaticObject!B(){ assert(0); })(id);
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
	void addTransparent(T)(T object, float alpha){
		assert(0,"TODO");
	}
	void addWizard(WizardInfo!B wizard){
		opaqueObjects.addWizard(wizard);
	}
	WizardInfo!B* getWizard(int id){
		return opaqueObjects.getWizard(id);
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
	void addParticle(bool relative)(Particle!(B,relative) particle){
		opaqueObjects.addParticle(particle);
	}
	void addCommandCone(CommandCone!B cone){
		opaqueObjects.addCommandCone(cone);
	}

	void opAssign(ObjectManager!B rhs){
		assignArray(ids,rhs.ids);
		opaqueObjects=rhs.opaqueObjects;
		transparentObjects=rhs.transparentObjects;
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
auto ref movingObjectById(alias f,alias nonMoving=fail,B,T...)(ref ObjectManager!B objectManager,int id,T args)in{
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
auto ref staticObjectById(alias f,alias nonStatic=fail,B,T...)(ref ObjectManager!B objectManager,int id,T args)in{
	assert(id>0);
}do{
	auto nid=objectManager.ids[id-1];
	enum byRef=!is(typeof(f(StaticObject!B.init,args))); // TODO: find a better way to check whether argument taken by reference!
	if(nid.type<numMoving||nid.index==-1) return nonStatic();
	else if(nid.type<numMoving+numStatic){
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
	}else return nonStatic();
}
auto ref soulById(alias f,alias noSoul=fail,B,T...)(ref ObjectManager!B objectManager,int id,T args)in{
	assert(id>0);
}do{
	auto nid=objectManager.ids[id-1];
	if(nid.type!=ObjectType.soul||nid.index==-1) return noSoul();
	return f(objectManager.opaqueObjects.souls[nid.index],args);
}
auto ref buildingById(alias f,alias noBuilding=fail,B,T...)(ref ObjectManager!B objectManager,int id,T args)in{
	assert(id>0);
}do{
	auto nid=objectManager.ids[id-1];
	if(nid.type!=ObjectType.building||nid.index==-1) return noBuilding();
	enum byRef=!is(typeof(f(Building!B.init,args))); // TODO: find a better way to check whether argument taken by reference!
	static assert(byRef);
	return f(objectManager.opaqueObjects.buildings[nid.index],args);
}
auto ref buildingByStaticObjectId(alias f,alias nonStatic=fail,B,T...)(ref ObjectManager!B objectManager,int id,T args)in{
	assert(id>0);
}do{
	auto nid=objectManager.ids[id-1];
	enum byRef=!is(typeof(f(StaticObject!B.init,args))); // TODO: find a better way to check whether argument taken by reference!
	if(nid.type<numMoving||nid.index==-1) return nonStatic();
	else if(nid.type<numMoving+numStatic){
		assert(nid.mode==RenderMode.opaque);
		assert(nid.type<numMoving+numStatic);
		static if(byRef){
			auto obj=objectManager.opaqueObjects.staticObjects[nid.type-numMoving][nid.index];
			scope(success) objectManager.opaqueObjects.staticObjects[nid.type-numMoving][nid.index]=obj;
			assert(obj.buildingId);
			return objectManager.buildingById!(f,nonStatic)(obj.buildingId,args);
		}else return f(objectManager.opaqueObjects.staticObjects[nid.type-numMoving][nid.index],args);
	}else return nonStatic();
}

void setCreatureState(B)(ref MovingObject!B object,ObjectState!B state){
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
					if(object.animationState!=AnimationState.run){
						object.frame=0;
						object.animationState=AnimationState.run;
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
				enforce(object.frame==0&&object.animationState.among(attack0,attack1,attack2,flyAttack));
			break;
		case CreatureMode.stunned:
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
					if(object.animationState!=AnimationState.knocked2Floor){
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
			object.animationState=object.shootAnimation;
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

void startIdling(B)(ref MovingObject!B object, ObjectState!B state){
	if(!object.creatureState.mode.among(CreatureMode.moving,CreatureMode.spawning,CreatureMode.reviving,CreatureMode.fastReviving,CreatureMode.takeoff,CreatureMode.landing,CreatureMode.meleeMoving,CreatureMode.meleeAttacking,CreatureMode.stunned,CreatureMode.casting,CreatureMode.stationaryCasting,CreatureMode.castingMoving,CreatureMode.shooting,CreatureMode.rockForm))
		return;
	object.creatureState.mode=CreatureMode.idle;
	object.setCreatureState(state);
}

bool kill(B,bool pretending=false)(ref MovingObject!B object, ObjectState!B state){
	with(CreatureMode) if(object.creatureState.mode.among(dying,dead,dissolving,reviving,fastReviving)) return false;
	static if(!pretending){
		if(object.creatureStats.flags&Flags.cannotDestroyKill) return false;
		if(!object.sacObject.canDie()) return false;
		object.unselect(state);
		object.removeFromGroups(state);
		object.health=0.0f;
		object.creatureState.mode=CreatureMode.dying;
		playSoundTypeAt(object.sacObject,object.id,SoundType.death,state);
		if(auto ability=object.passiveAbility){
			if(ability.tag==SpellTag.steamCloud)
				object.steamCloud(ability,state);
		}
	}else{
		with(CreatureMode) if(object.creatureState.mode.among(stunned,pretendingToDie,playingDead)) return false;
		object.creatureState.mode=CreatureMode.pretendingToDie;
	}
	object.setCreatureState(state);
	return true;
}
bool playDead(B)(ref MovingObject!B object, ObjectState!B state){
	return object.kill!(B,true)(state);
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
	int newLength=0;
	foreach(i,id;building.componentIds.data){
		state.removeLater(id);
		auto destroyed=building.bldg.components[i].destroyed;
		if(destroyed!="\0\0\0\0"){
			auto destObj=SacObject!B.getBLDG(destroyed);
			state.staticObjectById!((ref StaticObject!B object){
				building.componentIds[newLength++]=state.addObject(StaticObject!B(destObj,building.id,object.position,object.rotation));
			})(id);
		}
		state.staticObjectById!((ref StaticObject!B object,state){
			auto destruction=building.bldg.components[i].destruction;
			destructionAnimation(destruction,object.center,state);
		})(id,state);
	}
	building.componentIds.length=newLength;
	if(building.base){
		state.buildingById!freeManafount(building.base,state);
	}
	if(newLength==0)
		state.removeLater(building.id);
}

void spawnSoul(B)(ref MovingObject!B object, ObjectState!B state){
	with(CreatureMode) if(object.creatureState.mode!=CreatureMode.dead||object.soulId!=0) return;
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

int spawn(T=Creature,B)(ref MovingObject!B caster,char[4] tag,int flags,ObjectState!B state,bool pre){
	auto curObj=SacObject!B.getSAXS!T(tag);
	auto position=caster.position;
	auto mode=pre?CreatureMode.preSpawning:CreatureMode.spawning;
	auto movement=CreatureMovement.flying;
	auto facing=caster.creatureState.facing;
	auto newPosition=position+rotate(facingQuaternion(facing),Vector3f(0.0f,6.0f,0.0f));
	if(!state.isOnGround(position)||state.isOnGround(newPosition)) position=newPosition; // TODO: find closet ground to newPosition instead
	position.z=state.getHeight(position);
	auto creatureState=CreatureState(mode, movement, facing);
	auto rotation=facingQuaternion(facing);
	auto obj=MovingObject!B(curObj,position,rotation,AnimationState.disoriented,0,creatureState,curObj.creatureStats(flags),caster.side);
	obj.setCreatureState(state);
	obj.updateCreaturePosition(state);
	auto ord=Order(CommandType.retreat,OrderTarget(TargetType.creature,caster.id,caster.position));
	obj.order(ord,state,caster.side);
	return state.addObject(obj);
}
int spawn(T=Creature,B)(int casterId,char[4] tag,int flags,ObjectState!B state,bool pre=true){
	return state.movingObjectById!(.spawn,function int(){ assert(0); })(casterId,tag,flags,state,pre);
}

int makeBuilding(B)(ref MovingObject!B caster,char[4] tag,int flags,int base,ObjectState!B state,bool pre=true)in{
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
			building.componentIds~=state.addObject(StaticObject!B(curObj,building.id,cposition,rotation));
		}
		if(base) state.buildingById!((ref manafount,state){ putOnManafount(building,manafount,state); })(base,state);
	})(buildingId);
	return buildingId;
}
int makeBuilding(B)(int casterId,char[4] tag,int flags,int base,ObjectState!B state,bool pre=true)in{
	assert(base>0);
}do{
	return state.movingObjectById!(.makeBuilding,function int(){ assert(0); })(casterId,tag,flags,base,state,pre);
}

bool canStun(B)(ref MovingObject!B object,ObjectState!B state){
	if(object.creatureStats.effects.stunCooldown!=0) return false;
	final switch(object.creatureState.mode) with(CreatureMode){
		case idle,moving,spawning,takeoff,landing,meleeMoving,meleeAttacking,cower,casting,stationaryCasting,castingMoving,shooting: return true;
		case dying,dead,dissolving,preSpawning,reviving,fastReviving,stunned,pretendingToDie,playingDead,pretendingToRevive,rockForm: return false;
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

void catapult(B)(ref MovingObject!B object, Vector3f velocity, ObjectState!B state){
	with(CreatureMode) if(object.creatureState.mode.among(dead,dissolving)) return;
	if(object.creatureState.movement==CreatureMovement.flying) return;
	if(object.creatureState.mode!=CreatureMode.dying)
		object.creatureState.mode=CreatureMode.stunned;
	// TODO: in original engine, stunned creatures don't switch to the tumbling animation
	object.creatureState.fallingVelocity=velocity;
	if(object.creatureState.movement!=CreatureMovement.tumbling){
		object.creatureState.movement=CreatureMovement.tumbling;
		object.setCreatureState(state);
	}
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
	playSoundTypeAt(object.sacObject,object.id,SoundType.damaged,state);
	if(checkIdle&&object.creatureState.mode!=CreatureMode.idle||!checkIdle&&object.creatureState.mode!=CreatureMode.stunned) return;
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


void healFromDrain(B)(ref MovingObject!B attacker,float actualDamage,ObjectState!B state){
	if(actualDamage) attacker.heal(actualDamage*attacker.creatureStats.drain,state);
}
void healFromDrain(B)(int attacker,float actualDamage,ObjectState!B state){
	if(state.isValidTarget(attacker,TargetType.creature))
		return state.movingObjectById!healFromDrain(attacker,actualDamage,state);
}

float dealDamage(T)(ref T object,float damage,int attacker,int attackingSide,ObjectState!B state)if(is(T==MovingObject!B,B)||is(T==Building!B,B)){
	if(state.isValidTarget(attacker,TargetType.creature))
		return state.movingObjectById!((ref atk,obj,dmg,state)=>dealDamage(*obj,dmg,atk,state))(attacker,&object,damage,state);
	return dealDamage(object,damage,attackingSide,state);
}

bool canDamage(B)(ref MovingObject!B object,ObjectState!B state){
	if(object.creatureStats.flags&Flags.cannotDamage) return false;
	if(object.creatureStats.effects.stealth) return false;
	final switch(object.creatureState.mode) with(CreatureMode){
		case idle,moving,spawning,takeoff,landing,meleeMoving,meleeAttacking,stunned,cower,casting,stationaryCasting,castingMoving,shooting: return true;
		case dying,dead,dissolving,preSpawning,reviving,fastReviving,pretendingToDie,playingDead,pretendingToRevive,rockForm: return false;
	}
}

float dealDamage(B)(ref MovingObject!B object,float damage,ref MovingObject!B attacker,ObjectState!B state){
	auto actualDamage=dealDamage(object,damage,attacker.side,state);
	attacker.healFromDrain(actualDamage,state);
	return actualDamage;
}
float dealDamage(B)(ref MovingObject!B object,float damage,int attackingSide,ObjectState!B state){
	if(!object.canDamage(state)) return 0.0f;
	auto shieldDamageMultiplier=object.creatureStats.effects.lifeShield?0.5f:1.0f;
	auto actualDamage=min(object.health,damage*state.sideDamageMultiplier(attackingSide,object.side)*shieldDamageMultiplier);
	object.health=object.health-actualDamage;
	if(object.creatureStats.flags&Flags.cannotDestroyKill)
		object.health=max(object.health,1.0f);
	// TODO: give xp to wizard of attacking side
	if(object.health==0.0f)
		object.kill(state);
	return actualDamage;
}

bool canDamage(B)(ref Building!B building,ObjectState!B state){
	if(building.flags&Flags.cannotDamage) return false;
	if(building.health==0.0f) return false;
	return true;
}

float dealDamage(B)(ref Building!B building,float damage,ref MovingObject!B attacker,ObjectState!B state){
	auto actualDamage=dealDamage(building,damage,attacker.side,state);
	return actualDamage;
}
float dealDamage(B)(ref Building!B building,float damage,int attackingSide,ObjectState!B state){
	if(!building.canDamage(state)) return 0.0f;
	auto actualDamage=min(building.health,damage*state.sideDamageMultiplier(attackingSide,building.side));
	building.health-=actualDamage;
	if(building.flags&Flags.cannotDestroyKill)
		building.health=max(building.health,1.0f);
	// TODO: give xp to attacker
	if(building.health==0.0f)
		building.destroy(state);
	return actualDamage;
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
void giveMana(B)(ref MovingObject!B object,float amount,ObjectState!B state){
	object.creatureStats.mana=min(object.creatureStats.mana+amount,object.creatureStats.maxMana);
}

float meleeDistanceSqr(Vector3f[2] objectHitbox,Vector3f[2] attackerHitbox){
	return boxBoxDistanceSqr(objectHitbox,attackerHitbox);
}

void dealMeleeDamage(B)(ref MovingObject!B object,ref MovingObject!B attacker,ObjectState!B state){
	auto damage=attacker.meleeStrength/attacker.numAttackTicks; // TODO: figure this out
	auto objectHitbox=object.hitbox, attackerHitbox=attacker.meleeHitbox, attackerSizeSqr=0.25f*boxSize(attackerHitbox).lengthsqr;
	auto distanceSqr=meleeDistanceSqr(objectHitbox,attackerHitbox);
	auto damageMultiplier=max(0.0f,1.0f-max(0.0f,sqrt(distanceSqr/attackerSizeSqr)));
	auto actualDamage=damageMultiplier*damage*object.creatureStats.meleeResistance;
	auto attackDirection=object.center-attacker.center; // TODO: good?
	auto stunBehavior=attacker.stunBehavior;
	auto direction=getDamageDirection(object,attackDirection,state);
	bool fromBehind=direction==DamageDirection.back;
	bool fromSide=!!direction.among(DamageDirection.left,DamageDirection.right);
	if(fromBehind) actualDamage*=2.0f;
	else if(fromSide) actualDamage*=1.5f;
	object.dealDamage(actualDamage,attacker,state);
	if(stunBehavior==StunBehavior.always || fromBehind && stunBehavior==StunBehavior.fromBehind){
		if(actualDamage>=0.5f*damage){
			playSoundTypeAt(attacker.sacObject,attacker.id,SoundType.stun,state);
			object.damageStun(attackDirection,state);
			return;
		}
	}
	object.damageAnimation(attackDirection,state);
	final switch(object.stunnedBehavior){
		case StunnedBehavior.normal:
			break;
		case StunnedBehavior.onMeleeDamage,StunnedBehavior.onDamage:
			playSoundTypeAt(attacker.sacObject,attacker.id,SoundType.stun,state);
			object.damageStun(attackDirection,state);
			return;
	}
	playSoundTypeAt(attacker.sacObject,attacker.id,SoundType.hit,state);
}

float dealMeleeDamage(B)(ref StaticObject!B object,ref MovingObject!B attacker,ObjectState!B state){
	return state.buildingById!((ref Building!B building,MovingObject!B* attacker,ObjectState!B state){
		return building.dealMeleeDamage(*attacker,state);
	},()=>0.0f)(object.buildingId,&attacker,state);
}

float dealMeleeDamage(B)(ref Building!B building,ref MovingObject!B attacker,ObjectState!B state){
	auto damage=attacker.meleeStrength;
	auto actualDamage=damage*building.meleeResistance*attacker.sacObject.buildingMeleeDamageMultiplier/attacker.numAttackTicks;
	actualDamage=building.dealDamage(actualDamage,attacker,state);
	playSoundTypeAt(attacker.sacObject,attacker.id,SoundType.hitWall,state);
	return actualDamage;
}

float dealSpellDamage(B)(ref MovingObject!B object,SacSpell!B spell,int attacker,int attackerSide,Vector3f attackDirection,ObjectState!B state){
	auto damage=spell.amount;
	auto actualDamage=damage*object.creatureStats.directSpellResistance;
	object.damageAnimation(attackDirection,state);
	actualDamage=object.dealDamage(actualDamage,attackerSide,state);
	healFromDrain(attacker,actualDamage,state);
	return actualDamage;
}
float dealSpellDamage(B)(ref StaticObject!B object,SacSpell!B spell,int attacker,int attackerSide,Vector3f attackDirection,ObjectState!B state){
	return state.buildingById!(dealSpellDamage,()=>0.0f)(object.buildingId,spell,attacker,attackerSide,attackDirection,state);
}
float dealSpellDamage(B)(ref Building!B building,SacSpell!B spell,int attacker,int attackerSide,Vector3f attackDirection,ObjectState!B state){
	auto damage=spell.amount;
	auto actualDamage=damage*building.directSpellResistance;
	return building.dealDamage(actualDamage,attackerSide,state);
}
float dealSpellDamage(B)(int target,SacSpell!B spell,int attacker,int attackerSide,Vector3f attackDirection,ObjectState!B state){
	if(!state.isValidTarget(target)) return 0.0f;
	return state.objectById!dealSpellDamage(target,spell,attacker,attackerSide,attackDirection,state);
}

float dealSplashSpellDamage(B)(ref MovingObject!B object,SacSpell!B spell,int attacker,int attackerSide,Vector3f attackDirection,float distance,ObjectState!B state){
	auto damage=spell.amount*(spell.effectRange>0.0f?max(0.0f,1.0f-distance/spell.effectRange):1.0f);
	auto actualDamage=damage*object.creatureStats.splashSpellResistance;
	object.damageAnimation(attackDirection,state);
	actualDamage=object.dealDamage(actualDamage,attackerSide,state);
	healFromDrain(attacker,actualDamage,state);
	return actualDamage;
}

float dealSplashSpellDamage(B)(ref StaticObject!B object,SacSpell!B spell,int attacker,int attackerSide,Vector3f attackDirection,float distance,ObjectState!B state){
	return state.buildingById!(dealSplashSpellDamage,()=>0.0f)(object.buildingId,spell,attacker,attackerSide,attackDirection,distance,state);
}

float dealSplashSpellDamage(B)(ref Building!B building,SacSpell!B spell,int attacker,int attackerSide,Vector3f attackDirection,float distance,ObjectState!B state){
	auto damage=spell.amount*(spell.effectRange>0.0f?max(0.0f,1.0f-distance/spell.effectRange):1.0f);
	auto actualDamage=damage*building.splashSpellResistance;
	return building.dealDamage(actualDamage,attackerSide,state);
}

float dealSplashSpellDamage(B)(int target,SacSpell!B spell,int attacker,int attackerSide,Vector3f attackDirection,float distance,ObjectState!B state){
	if(state.isValidBuilding(target))
		return state.buildingById!(dealSplashSpellDamage,()=>0.0f)(target,spell,attacker,attackerSide,attackDirection,distance,state);
	if(!state.isValidTarget(target)) return 0.0f;
	return state.objectById!dealSplashSpellDamage(target,spell,attacker,attackerSide,attackDirection,distance,state);
}

float dealSplashSpellDamageAt(alias callback=(id)=>true,B,T...)(int directTarget,SacSpell!B spell,float radius,int attacker,int attackerSide,Vector3f position,ObjectState!B state,T args){
	static void dealDamage(ProximityEntry target,ObjectState!B state,int directTarget,SacSpell!B spell,int attacker,int attackerSide,Vector3f position,float* sum,float radius,T args){
		if(target.id==directTarget) return;
		auto distance=boxPointDistance(target.hitbox,position);
		if(distance>radius) return;
		auto attackDirection=state.objectById!((obj)=>obj.center)(target.id)-position;
		if(callback(target.id,args))
			*sum+=dealSplashSpellDamage(target.id,spell,attacker,attackerSide,attackDirection,distance,state);
	}
	auto offset=Vector3f(radius,radius,radius);
	Vector3f[2] hitbox=[position-offset,position+offset];
	float sum=0.0f;
	collisionTargets!(dealDamage,None,true)(hitbox,state,directTarget,spell,attacker,attackerSide,position,&sum,radius,args);
	return sum;
}

float dealRangedDamage(B)(ref MovingObject!B object,SacSpell!B rangedAttack,int attacker,int attackerSide,Vector3f attackDirection,ObjectState!B state){
	auto damage=rangedAttack.amount;
	auto actualDamage=damage*object.creatureStats.directRangedResistance;
	object.damageAnimation(attackDirection,state);
	actualDamage=object.dealDamage(actualDamage,attackerSide,state);
	healFromDrain(attacker,actualDamage,state);
	return actualDamage;
}

float dealRangedDamage(B)(ref StaticObject!B object,SacSpell!B rangedAttack,int attacker,int attackerSide,Vector3f attackDirection,ObjectState!B state){
	return state.buildingById!(dealRangedDamage,()=>0.0f)(object.buildingId,rangedAttack,attacker,attackerSide,attackDirection,state);

}

float dealRangedDamage(B)(ref Building!B building,SacSpell!B rangedAttack,int attacker,int attackerSide,Vector3f attackDirection,ObjectState!B state){
	auto damage=rangedAttack.amount;
	auto actualDamage=damage*building.directRangedResistance;
	return building.dealDamage(actualDamage,attackerSide,state);
}

float dealRangedDamage(B)(int target,SacSpell!B rangedAttack,int attacker,int attackerSide,Vector3f attackDirection,ObjectState!B state){
	if(!state.isValidTarget(target)) return 0.0f;
	return state.objectById!dealRangedDamage(target,rangedAttack,attacker,attackerSide,attackDirection,state);
}

float dealSplashRangedDamage(B)(ref MovingObject!B object,SacSpell!B rangedAttack,int attacker,int attackerSide,Vector3f attackDirection,float distance,ObjectState!B state){
	auto damage=rangedAttack.amount*(rangedAttack.effectRange>0.0f?max(0.0f,1.0f-distance/rangedAttack.effectRange):1.0f);
	auto actualDamage=damage*object.creatureStats.splashRangedResistance;
	object.damageAnimation(attackDirection,state);
	actualDamage=object.dealDamage(actualDamage,attackerSide,state);
	healFromDrain(attacker,actualDamage,state);
	return actualDamage;
}

float dealSplashRangedDamage(B)(ref StaticObject!B object,SacSpell!B rangedAttack,int attacker,int attackerSide,Vector3f attackDirection,float distance,ObjectState!B state){
	return state.buildingById!(dealSplashRangedDamage,()=>0.0f)(object.buildingId,rangedAttack,attacker,attackerSide,attackDirection,distance,state);
}

float dealSplashRangedDamage(B)(ref Building!B building,SacSpell!B rangedAttack,int attacker,int attackerSide,Vector3f attackDirection,float distance,ObjectState!B state){
	auto damage=rangedAttack.amount*(rangedAttack.effectRange>0.0f?max(0.0f,1.0f-distance/rangedAttack.effectRange):1.0f);
	auto actualDamage=damage*building.splashRangedResistance;
	return building.dealDamage(actualDamage,attackerSide,state);
}

float dealSplashRangedDamage(B)(int target,SacSpell!B rangedAttack,int attacker,int attackerSide,Vector3f attackDirection,float distance,ObjectState!B state){
	if(state.isValidBuilding(target))
		return state.buildingById!(dealSplashRangedDamage,()=>0.0f)(target,rangedAttack,attacker,attackerSide,attackDirection,distance,state);
	if(!state.isValidId(target)) return 0.0f;
	return state.objectById!dealSplashRangedDamage(target,rangedAttack,attacker,attackerSide,attackDirection,distance,state);
}

float dealSplashRangedDamageAt(alias callback=(id)=>true,B,T...)(int directTarget,SacSpell!B rangedAttack,float radius,int attacker,int attackerSide,Vector3f position,ObjectState!B state,T args){
	static void dealDamage(ProximityEntry target,ObjectState!B state,int directTarget,SacSpell!B rangedAttack,int attacker,int attackerSide,Vector3f position,float* sum,float radius,T args){
		if(target.id==directTarget) return;
		auto distance=boxPointDistance(target.hitbox,position);
		if(distance>radius) return;
		auto attackDirection=state.objectById!((obj)=>obj.center)(target.id)-position;
		if(callback(target.id,args))
			*sum+=dealSplashRangedDamage(target.id,rangedAttack,attacker,attackerSide,attackDirection,distance,state);
	}
	auto offset=Vector3f(radius,radius,radius);
	Vector3f[2] hitbox=[position-offset,position+offset];
	float sum=0.0f;
	collisionTargets!(dealDamage,None,true)(hitbox,state,directTarget,rangedAttack,attacker,attackerSide,position,&sum,radius,args);
	return sum;
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

bool startCasting(B)(ref MovingObject!B object,int numFrames,bool stationary,ObjectState!B state){
	if(!object.isWizard) return false;
	if(!object.creatureState.mode.among(CreatureMode.idle,CreatureMode.moving)&&object.castStatus(state)!=CastingStatus.finished)
		return false;
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
bool startCasting(B)(ref MovingObject!B object,SacSpell!B spell,Target target,ObjectState!B state){
	auto wizard=state.getWizard(object.id);
	if(!wizard) return false;
	if(state.spellStatus!false(wizard,spell,target)!=SpellStatus.ready) return false;
	int numFrames=cast(int)ceil(updateFPS*spell.castingTime(wizard.level));
	if(!object.startCasting(numFrames,spell.stationary,state))
		return false;
	auto drainSpeed=spell.isBuilding?125.0f:500.0f;
	auto numManaDrainFrames=min(numFrames,cast(int)ceil(spell.manaCost*(updateFPS/drainSpeed)));
	auto manaCostPerFrame=spell.manaCost/numManaDrainFrames;
	auto manaDrain=ManaDrain!B(object.id,manaCostPerFrame,numManaDrainFrames);
	(*wizard).applyCooldown(spell,state);
	bool stun(){
		object.damageStun(Vector3f(0.0f,0.0f,-1.0f),state);
		return false;
	}
	final switch(spell.type){
		case SpellType.creature:
			assert(target==Target.init);
			auto creature=spawn(object.id,spell.tag,0,state);
			state.setRenderMode!(MovingObject!B,RenderMode.transparent)(creature);
			state.setAlpha(creature,0.6f);
			playSoundAt("NMUS",creature,state,summonSoundGain);
			state.addEffect(CreatureCasting!B(manaDrain,spell,creature));
			return true;
		case SpellType.spell:
			bool ok=false;
			switch(spell.tag){
				case SpellTag.teleport:
					return castTeleport(manaDrain,spell,object.position,target.id,state);
				case SpellTag.speedup:
					ok=target.id==object.id?speedUp(object,spell,state):speedUp(target.id,spell,state);
					goto default;
				case SpellTag.heal:
					return target.id==object.id?castHeal(object,manaDrain,spell,state):castHeal(target.id,manaDrain,spell,state);
				case SpellTag.lightning:
					return target.id==object.id?castLightning(object,manaDrain,spell,state):castLightning(target.id,manaDrain,spell,state);
				case SpellTag.wrath:
					return target.id==object.id?castWrath(object,manaDrain,spell,state):castWrath(target.id,manaDrain,spell,state);
				case SpellTag.fireball:
					return target.id==object.id?castFireball(object,manaDrain,spell,state):castFireball(target.id,manaDrain,spell,state);
				case SpellTag.rock:
					auto castingTime=object.getCastingTime(numFrames,spell.stationary,state);
					return target.id==object.id?castRock(object.id,object,manaDrain,spell,castingTime,state):castRock(object.id,target.id,manaDrain,spell,castingTime,state);
				case SpellTag.insectSwarm:
					auto castingTime=object.getCastingTime(numFrames,spell.stationary,state);
					return target.id==object.id?castSwarm(object,manaDrain,spell,castingTime,state):castSwarm(target.id,manaDrain,spell,castingTime,state);
				default:
					if(ok) state.addEffect(manaDrain);
					else stun();
					return ok;
			}
		case SpellType.structure:
			if(!spell.isBuilding) goto case SpellType.spell;
			auto base=state.staticObjectById!((obj)=>obj.buildingId,()=>0)(target.id);
			if(base){ // TODO: stun both wizards on simultaneous lith cast
				auto god=state.getCurrentGod(wizard);
				if(god==God.none) god=God.persephone;
				auto building=makeBuilding(object.id,spell.buildingTag(god),AdditionalBuildingFlags.inactive|Flags.cannotDamage,base,state);
				state.setupStructureCasting(building);
				float buildingHeight=state.buildingById!((ref bldg,state)=>height(bldg,state),()=>0.0f)(building,state);
				auto castingTime=object.getCastingTime(numFrames,spell.stationary,state);
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

Vector3f getTeleportPosition(B)(SacSpell!B spell,Vector3f startPosition,int target,ObjectState!B state){
	if(!state.isValidTarget(target)) return Vector3f.init;
	auto targetPositionTargetScale=state.objectById!((ref obj)=>tuple(obj.position,obj.getScale))(target);
	auto targetPosition=targetPositionTargetScale[0], targetScale=targetPositionTargetScale[1];
	auto teleportPosition=targetPosition+(startPosition-targetPosition).normalized*spell.effectRange;
	if(!state.isOnGround(teleportPosition)){
		teleportPosition=targetPosition; // TODO: fix
	}
	return teleportPosition;
}

bool castTeleport(B)(ManaDrain!B manaDrain,SacSpell!B spell,Vector3f startPosition,int target,ObjectState!B state){
	auto position=getTeleportPosition(spell,startPosition,target,state);
	if(isNaN(position.x)) return false;
	state.addEffect(TeleportCasting!B(manaDrain,spell,target,position));
	return true;
}

void animateTeleport(B)(bool isOut,Vector3f[2] hitbox,ObjectState!B state){
	auto position=boxCenter([hitbox[0],Vector3f(hitbox[1].x,hitbox[1].y,hitbox[0].z)]);
	auto size=boxSize(hitbox);
	auto scale=max(size.x,size.y);
	playSoundAt("elet",position,state,2.0f);
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

bool teleport(B)(int side,Vector3f startPosition,Vector3f targetPosition,SacSpell!B spell,ObjectState!B state){
	static void teleport(ref CenterProximityEntry entry,int side,Vector3f startPosition,Vector3f targetPosition,ObjectState!B state){
		static void doIt(ref MovingObject!B obj,Vector3f startPosition,Vector3f targetPosition,ObjectState!B state){
			auto oldHeight=obj.position.z-state.getHeight(obj.position);
			auto newPosition=obj.position-startPosition+targetPosition;
			if(obj.creatureState.movement!=CreatureMovement.flying&&!state.isOnGround(newPosition)){
				newPosition=targetPosition; // TODO: fix
			}
			newPosition.z=state.getHeight(newPosition)+max(0.0f,oldHeight);
			auto startHitbox=obj.hitbox;
			obj.position=newPosition;
			auto newHitbox=obj.hitbox;
			animateTeleport(true,startHitbox,state);
			animateTeleport(false,newHitbox,state);
		}
		if(entry.isStatic||!state.isValidTarget(entry.id,TargetType.creature)||side!=entry.side) return;
		state.movingObjectById!doIt(entry.id,startPosition,targetPosition,state);
	}
	state.proximity.eachInRange!teleport(startPosition,spell.effectRange,side,startPosition,targetPosition,state);
	return true;
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

bool castHeal(B)(ref MovingObject!B object,ManaDrain!B manaDrain,SacSpell!B spell,ObjectState!B state){
	state.addEffect(HealCasting!B(manaDrain,spell,object.id));
	return true;
}
bool castHeal(B)(int creature,ManaDrain!B manaDrain,SacSpell!B spell,ObjectState!B state){
	if(!state.isValidTarget(creature,TargetType.creature)) return false;
	return state.movingObjectById!(castHeal,()=>false)(creature,manaDrain,spell,state);
}
enum healSpeed=250.0f;
bool heal(B)(int creature,SacSpell!B spell,ObjectState!B state){
	if(!state.movingObjectById!(canHeal,()=>false)(creature,state)) return false;
	playSoundAt("laeh",creature,state,2.0f);
	auto amount=spell.amount;
	auto duration=cast(int)ceil(amount/healSpeed*updateFPS);
	auto healthRegenerationPerFrame=amount/duration;
	state.addEffect(Heal!B(creature,healthRegenerationPerFrame,duration));
	return true;
}

bool castLightning(B,T)(ref T object,ManaDrain!B manaDrain,SacSpell!B spell,ObjectState!B state)if(!is(T==int)){
	return castLightning(object.id,manaDrain,spell,state);
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

bool lightning(B)(int wizard,int side,OrderTarget start,OrderTarget end,SacSpell!B spell,ObjectState!B state){
	auto startCenter=start.center(state),endCenter=end.center(state);
	static bool filter(ref ProximityEntry entry,int id){ return entry.id!=id; }
	auto newEnd=state.collideRay!filter(startCenter,endCenter-startCenter,1.0f,wizard);
	if(newEnd.type!=TargetType.none){
		end=newEnd;
		endCenter=end.center(state);
	}
	end.position=endCenter;
	playSpellSoundTypeAt(SoundType.lightning,0.5f*(startCenter+endCenter),state,4.0f);
	auto lightning=Lightning!B(wizard,side,start,end,spell,0);
	foreach(ref bolt;lightning.bolts)
		bolt.changeShape(state);
	state.addEffect(lightning);
	return true;
}

bool castWrath(B,T)(ref T object,ManaDrain!B manaDrain,SacSpell!B spell,ObjectState!B state)if(!is(T==int)){
	return castWrath(object.id,manaDrain,spell,state);
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
bool castFireball(B,T)(ref T object,ManaDrain!B manaDrain,SacSpell!B spell,ObjectState!B state)if(!is(T==int)){
	return castFireball(object.id,manaDrain,spell,state);
}
bool castFireball(B)(int target,ManaDrain!B manaDrain,SacSpell!B spell,ObjectState!B state){
	if(!state.isValidTarget(target)) return false;
	auto positionSide=state.movingObjectById!((obj,state)=>tuple(obj.fireballCastingPosition(state),obj.side),function Tuple!(Vector3f,int){ assert(0); })(manaDrain.wizard,state);
	auto position=positionSide[0],side=positionSide[1];
	auto fireball=makeFireball(manaDrain.wizard,side,position,centerTarget(target,state),spell,state);
	state.addEffect(FireballCasting!B(manaDrain,spell,fireball));
	return true;
}

bool fireball(B)(Fireball!B fireball,ObjectState!B state){
	playSpellSoundTypeAt(SoundType.fireball,fireball.position,state,4.0f); // TODO: move sound with fireball
	state.addEffect(fireball);
	return true;
}

Rock!B makeRock(B)(int wizard,int side,Vector3f position,OrderTarget target,SacSpell!B spell,ObjectState!B state){
	auto rotationSpeed=2*pi!float*state.uniform(0.1f,0.4f)/updateFPS;
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
bool castRock(B,T)(int wizard,ref T object,ManaDrain!B manaDrain,SacSpell!B spell,int castingTime,ObjectState!B state)if(!is(T==int)){
	return castRock(wizard,object.id,manaDrain,spell,castingTime,state);
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
bool castSwarm(B,T)(ref T object,ManaDrain!B manaDrain,SacSpell!B spell,int castingTime,ObjectState!B state)if(!is(T==int)){
	return castSwarm(object.id,manaDrain,spell,castingTime,state);
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

Vector3f getShotDirection(B)(float accuracy,Vector3f position,Vector3f target,SacSpell!B rangedAttack,ObjectState!B state){
	auto φ=2.0f*pi!float*accuracy*state.normal(); // TODO: ok?
	return rotate(facingQuaternion(φ),(target-position+5.0f*accuracy*state.normal()).normalized); // TODO: ok?
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
		dealRangedDamage(end.id,rangedAttack,attacker,side,direction,state);
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
	auto rotationSpeed=2*pi!float*state.uniform(0.1f,0.4f)/updateFPS;
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
	return atan2(-direction.x,direction.y);
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
	return object.pitch(pitch_,state);
}

bool movingForwardGetsCloserTo(B)(ref MovingObject!B object,Vector3f position,float speed,float acceleration,ObjectState!B state){
	auto direction=position.xy-object.position.xy;
	auto facing=object.creatureState.facing;
	auto rotationSpeed=object.creatureStats.rotationSpeed(object.creatureState.movement==CreatureMovement.flying);
	auto forward=Vector2f(-sin(facing),cos(facing));
	auto angle=atan2(-direction.x,direction.y);
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
	object.clearOrderQueue(state);
	object.creatureAI.order=order;
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
	if(hasOrders(object,state)) object.creatureAI.orderQueue.pushFront(object.creatureAI.order);
	object.creatureAI.order=order;
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
	object.stopMovement(state);
	object.stopTurning(state);
	object.stopPitching(state);
}

void clearOrder(B)(ref MovingObject!B object,ObjectState!B state){
	object.stop(state);
	if(!object.creatureAI.orderQueue.empty){
		object.creatureAI.order=object.creatureAI.orderQueue.front;
		object.creatureAI.orderQueue.popFront();
	}else object.creatureAI.order=Order.init;
}

void clearOrderQueue(B)(ref MovingObject!B object,ObjectState!B state){
	object.creatureAI.orderQueue.clear();
	clearOrder(object,state);
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

void moveTowards(B)(ref MovingObject!B object,Vector3f targetPosition,ObjectState!B state,bool evade=true,bool maintainHeight=false,bool stayAboveGround=true,int targetId=0){
	auto distancesqr=(object.position.xy-targetPosition.xy).lengthsqr;
	auto isFlying=object.creatureState.movement==CreatureMovement.flying;
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

bool moveTo(B)(ref MovingObject!B object,Vector3f targetPosition,float targetFacing,ObjectState!B state,bool evade=true,bool maintainHeight=false,bool stayAboveGround=true,int targetId=0){
	auto speed=object.speed(state)/updateFPS;
	auto distancesqr=(object.position.xy-targetPosition.xy).lengthsqr;
	if(distancesqr>(2.0f*speed)^^2){
		object.moveTowards(targetPosition,state,evade,maintainHeight,stayAboveGround,targetId);
		return true;
	}
	return object.stop(targetFacing,state);
}

bool moveWithinRange(B)(ref MovingObject!B object,Vector3f targetPosition,float range,ObjectState!B state,bool evade=true,bool maintainHeight=false,bool stayAboveGround=true,int targetId=0){
	auto speed=object.speed(state)/updateFPS;
	auto distancesqr=(object.position.xy-targetPosition.xy).lengthsqr;
	if(distancesqr<=(range-speed)^^2)
		return false;
	object.moveTowards(targetPosition,state,evade,maintainHeight,stayAboveGround,targetId);
	return true;
}

bool retreatTowards(B)(ref MovingObject!B object,Vector3f targetPosition,ObjectState!B state){
	return object.patrolAround(targetPosition,guardDistance,state) ||
		object.moveWithinRange(targetPosition,retreatDistance,state) ||
		object.stop(float.init,state);
}

bool isValidAttackTarget(B,T)(ref T obj,ObjectState!B state)if(is(T==MovingObject!B)||is(T==StaticObject!B)){
	// this needs to be kept in synch with addToProximity
	static if(is(T==MovingObject!B)) if(!obj.creatureState.mode.isValidAttackTarget) return false;
	return obj.health(state)!=0.0f;
}
bool isValidAttackTarget(B)(int targetId,ObjectState!B state){
	return state.isValidTarget(targetId)&&state.objectById!(.isValidAttackTarget)(targetId,state);
}
bool isValidEnemyAttackTarget(B,T)(ref T obj,int side,ObjectState!B state)if(is(T==MovingObject!B)||is(T==StaticObject!B)){
	if(!obj.isValidAttackTarget(state)) return false;
	return state.sides.getStance(side,.side(obj,state))==Stance.enemy;
}
bool isValidEnemyAttackTarget(B)(int targetId,int side,ObjectState!B state){
	return state.isValidTarget(targetId)&&state.objectById!(.isValidEnemyAttackTarget)(targetId,side,state);
}
bool isValidGuardTarget(B,T)(T obj,ObjectState!B state)if(is(T==MovingObject!B)||is(T==StaticObject!B)){
	static if(is(T==StaticObject!B)) return true;
	return isValidAttackTarget(obj,state); // TODO: dead wizards
}
bool isValidGuardTarget(B)(int targetId,ObjectState!B state){
	return state.isValidTarget(targetId)&&state.objectById!(.isValidGuardTarget)(targetId,state);
}

bool hasClearShot(B)(ref MovingObject!B object,Vector3f target,int targetId,ObjectState!B state){
	auto offset=Vector3f(0.0f,0.0f,-0.2f); // TODO: do some sort of cylinder cast instead
	return state.hasLineOfSightTo(object.firstShotPosition+offset,target+offset,object.id,targetId);
}
float shootDistance(B)(ref MovingObject!B object,ObjectState!B state){
	if(auto ra=object.rangedAttack) return 0.5f*ra.range; // TODO: figure out the range limit for AI
	return -1.0f;
}
bool shoot(B)(ref MovingObject!B object,SacSpell!B rangedAttack,int targetId,ObjectState!B state){
	if(!isValidAttackTarget(targetId,state)) return true; // TODO
	if(object.rangedAttack !is rangedAttack) return false; // TODO: multiple ranged attacks?
	auto predicted=rangedAttack.needsPrediction?
		object.creatureAI.predictor.predictCenter(object.firstShotPosition,rangedAttack.speed,targetId,state) :
		state.objectById!center(targetId);
	// TODO: find a spot from where target can be shot
	auto notShooting=!object.creatureState.mode.isShooting;
	auto targetPosition=notShooting?state.objectById!((obj)=>obj.position)(targetId):Vector3f.init;
	if(notShooting){
		if(object.moveWithinRange(targetPosition,object.shootDistance(state),state))
			return true;
	}
	bool isFlying=object.creatureState.movement==CreatureMovement.flying;
	auto flyingHeight=isFlying?object.position.z-state.getHeight(object.position):0.0f;
	auto minFlyingHeight=isFlying?object.creatureStats.flyingHeight:0.0f;
	auto targetFlyingHeight=max(flyingHeight,minFlyingHeight);
	bool moveCloser(){
		object.moveTowards(targetPosition,state,true,true);
		if(isFlying) object.creatureState.targetFlyingHeight=targetFlyingHeight;
		return true;
	}
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
		if(!object.hasClearShot(predicted,targetId,state)) return moveCloser();
		if(stop()){
			auto rotationThreshold=4.0f*object.creatureStats.rotationSpeed(object.creatureState.movement==CreatureMovement.flying)/updateFPS;
			bool evading;
			auto facing=!object.turnToFaceTowardsEvading(predicted,evading,state,rotationThreshold);
			if(facing&&object.creatureStats.effects.rangedCooldown==0&&object.creatureStats.mana>=rangedAttack.manaCost){
				object.creatureAI.rangedAttackTarget=targetId;
				object.startShooting(state); // TODO: should this have a delay?
			}
		}
	}else{
		stop();
		if(object.hasLoadTick()){
			switch(rangedAttack.tag){
				case SpellTag.sylphShoot:
					sylphLoad(object.id,state);
					break;
				case SpellTag.rangerShoot:
					rangerLoad(object.id,state);
					break;
				default: break;
			}
		}
		if(object.hasShootTick){
			if(object.shootAbilityBug(state)) return true;
			auto drainedMana=rangedAttack.manaCost/object.numShootTicks;
			if(object.creatureStats.mana>=drainedMana){
				auto ability=object.ability;
				auto accuracy=object.creatureStats.rangedAccuracy;
				switch(rangedAttack.tag){
					case SpellTag.brainiacShoot:
						brainiacShoot(object.id,object.side,targetId,accuracy,object.shotPosition,predicted,rangedAttack,state);
						break;
					case SpellTag.shrikeShoot:
						shrikeShoot(object.id,object.side,targetId,accuracy,object.shotPosition,predicted,rangedAttack,state);
						break;
					case SpellTag.locustShoot:
						locustShoot(object.id,object.side,targetId,accuracy,object.shotPosition,predicted,rangedAttack,state);
						// hack to ensure drain gets applied:
						object.creatureStats.health=state.movingObjectById!((obj)=>obj.creatureStats.health,()=>0.0f)(object.id);
						break;
					case SpellTag.spitfireShoot:
						spitfireShoot(object.id,object.side,targetId,accuracy,object.shotPosition,predicted,rangedAttack,state);
						break;
					case SpellTag.gargoyleShoot:
						gargoyleShoot(object.id,object.side,targetId,accuracy,object.shotPosition,predicted,rangedAttack,state);
						break;
					case SpellTag.earthflingShoot:
						earthflingShoot(object.id,object.side,targetId,accuracy,object.shotPosition,predicted,rangedAttack,state);
						break;
					case SpellTag.flameMinionShoot:
						flameMinionShoot(object.id,object.side,targetId,accuracy,object.shotPosition,predicted,rangedAttack,state);
						break;
					case SpellTag.fallenShoot:
						fallenShoot(object.id,object.side,targetId,accuracy,object.shotPosition,predicted,rangedAttack,state);
						break;
					case SpellTag.sylphShoot:
						sylphShoot(object.id,object.side,targetId,accuracy,object.shotPosition,predicted,rangedAttack,state);
						break;
					case SpellTag.rangerShoot:
						rangerShoot(object.id,object.side,targetId,accuracy,object.shotPosition,predicted,rangedAttack,state);
						break;
					default: goto case SpellTag.brainiacShoot;
				}
				object.drainMana(drainedMana,state);
				if(object.creatureStats.effects.rangedCooldown==0)
					object.creatureStats.effects.rangedCooldown=cast(int)(rangedAttack.cooldown*updateFPS);
			}
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
		if(target&&target!=targetId&&isValidEnemyAttackTarget(targetId,object.side,state))
			target=0;
	}
	auto targetHitbox=state.objectById!((obj,meleeHitboxCenter)=>obj.closestHitbox(meleeHitboxCenter))(targetId,meleeHitboxCenter);
	auto targetPosition=boxCenter(targetHitbox);
	auto hitbox=object.hitbox;
	auto position=boxCenter(hitbox);
	auto flatTargetHitbox=targetHitbox;
	flatTargetHitbox[1].z=max(flatTargetHitbox[0].z,targetHitbox[1].z-(meleeHitboxCenter.z-position.z));
	auto movementPosition=projectToBoxTowardsCenter(flatTargetHitbox,object.position); // TODO: ranged creatures should move to a nearby location where they have a clear shot
	if(auto ra=object.rangedAttack){
		if(!target||object.rangedMeleeAttackDistance(state)^^2<boxBoxDistanceSqr(hitbox,targetHitbox))
			return object.shoot(ra,targetId,state);
	}
	auto targetDistance=0.8f*(position-meleeHitboxCenter).xy.length;
	if(target||!object.moveWithinRange(movementPosition,3.5f*targetDistance,state,!object.isMeleeAttacking(state),false,false,targetId)){
		bool evading;
		if(object.turnToFaceTowardsEvading(movementPosition,evading,state,10.0f*defaultFaceThreshold,true,targetId)&&!evading||
		   !object.moveWithinRange(movementPosition,targetDistance,state,!object.isMeleeAttacking(state),false,false,targetId)){
			object.stopMovement(state);
			object.pitch(0.0f,state);
		}
	}
	if(target){
		enum downwardThreshold=0.25f;
		object.startMeleeAttacking(targetPosition.z+downwardThreshold<position.z,state);
		object.creatureState.targetFlyingHeight=float.nan;
	}else if(!object.rangedAttack){
		if(object.creatureState.movement==CreatureMovement.flying)
			object.creatureState.targetFlyingHeight=movementPosition.z-state.getHeight(movementPosition);
	}
	return true;
}

bool patrolAround(B)(ref MovingObject!B object,Vector3f position,float range,ObjectState!B state){
	if(!object.isAggressive(state)) return false;
	auto targetId=state.proximity.closestEnemyInRange(object.side,position,range,EnemyType.all,state);
	if(targetId)
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
	if(!object.patrolAround(targetPosition,guardDistance,state)){ // TODO: prefer enemies that attack the guard target?
		idle&=!object.moveTo(targetPosition,targetFacing,state);
	}
	return true;
}

bool patrol(B)(ref MovingObject!B object,ObjectState!B state){
	if(!object.isAggressive(state)) return false;
	auto position=object.position;
	auto range=object.aggressiveRange(CommandType.none,state);
	auto targetId=state.proximity.closestEnemyInRange(object.side,position,range,EnemyType.all,state);
	if(targetId)
		if(object.attack(targetId,state))
			return true;
	return false;
}

bool advance(B)(ref MovingObject!B object,Vector3f targetPosition,ObjectState!B state){
	if(object.isPacifist(state)) return false;
	auto position=object.position;
	auto range=object.advanceRange(CommandType.none,state);
	auto targetId=state.proximity.closestEnemyInRangeAndClosestToPreferringAttackersOf(object.side,object.position,range,targetPosition,object.id,EnemyType.all,state);
	if(targetId)
		if(object.attack(targetId,state))
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
		if(object.creatureStats.effects.stealth) return RenderMode.transparent;
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
	state.addEffect(DivineSight!B(object.side,position,velocity,ability));
	return true;
}

bool protector(B)(ref MovingObject!B object,SacSpell!B ability,ObjectState!B state){
	auto lifeShield=SacSpell!B.get(SpellTag.lifeShield);
	if(!object.lifeShield(lifeShield,state)) return false;
	state.addEffect(Protector!B(object.id,ability));
	return true;
}

bool checkAbility(B)(ref MovingObject!B object,SacSpell!B ability,Target target,ObjectState!B state){
	if(ability.requiresTarget&&!ability.isApplicable(summarize(target,object.side,state))){
		target.id=0;
		target.type=TargetType.terrain;
		if(ability.requiresTarget&&!ability.isApplicable(summarize(target,object.side,state)))
			return false;
	}
	if(state.abilityStatus!false(object,ability,target)!=SpellStatus.ready) return false;
	return true;
}

bool useAbility(B)(ref MovingObject!B object,SacSpell!B ability,Target target,ObjectState!B state){
	if(object.sacObject.ability!is ability) return false;
	if(!object.checkAbility(ability,target,state)) return false;
	void apply(){
		object.drainMana(ability.manaCost,state);
		object.creatureStats.effects.abilityCooldown=cast(int)(ability.cooldown*updateFPS);
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
		case SpellTag.protector:
			if(object.protector(ability,state)) apply();
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
	auto targetId=object.creatureAI.rangedAttackTarget;
	if(!state.isValidTarget(targetId,TargetType.creature)) return false;
	if(state.movingObjectById!((target)=>target.creatureStats.effects.numSpeedUps!=0,()=>true)(targetId)) return false;
	if(state.abilityStatus!true(object,ability)!=SpellStatus.ready) return false;
	object.creatureStats.effects.abilityCooldown=cast(int)(ability.cooldown*updateFPS);
	object.drainMana(ability.manaCost,state);
	object.clearOrder(state);
	state.movingObjectById!((ref target,ability,state){ target.runAway(ability,state); })(targetId,ability,state);
	return true;
}

bool shootAbilityBug(B)(ref MovingObject!B object,ObjectState!B state){
	if(runAwayBug(object,state)) return true;
	auto ability=object.ability;
	if(!ability||object.creatureAI.order.command!=CommandType.useAbility) return false;
	auto id=object.creatureAI.rangedAttackTarget;
	auto targetType=state.targetTypeFromId(id);
	if(!targetType.among(TargetType.creature,TargetType.building)) return false;
	auto target=Target(targetType,id,state.objectById!((obj)=>obj.position)(id));
	if(!object.checkAbility(ability,target,state)) return false;
	if(!object.useAbility(ability,target,state))
		object.clearOrder(state);
	return true;
}

bool steamCloud(B)(ref MovingObject!B object,SacSpell!B ability,ObjectState!B state){
	dealSplashRangedDamageAt(object.id,ability,ability.effectRange,object.id,object.side,object.position,state);
	enum numParticles2=100;
	auto sacParticle2=SacParticle!B.get(ParticleType.steam);
	auto hitbox=object.hitbox;
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
	return true;
}

enum retreatDistance=9.0f;
enum guardDistance=18.0f; // ok?
enum attackDistance=100.0f; // ok?
enum shelterDistance=50.0f;
enum scareDistance=50.0f;
enum speedLimitFactor=0.5f;
enum rotationSpeedLimitFactor=1.0f;

bool requiresAI(CreatureMode mode){
	with(CreatureMode) final switch(mode){
		case idle,moving,spawning,takeoff,landing,meleeMoving,meleeAttacking,casting,stationaryCasting,castingMoving,shooting,playingDead,rockForm: return true;
		case dying,dead,dissolving,preSpawning,reviving,fastReviving,stunned,cower,pretendingToDie,pretendingToRevive: return false;
	}
}

void updateCreatureAI(B)(ref MovingObject!B object,ObjectState!B state){
	if(!requiresAI(object.creatureState.mode)) return;
	if(object.creatureState.mode.isShooting){
		if(!object.shoot(object.rangedAttack,object.creatureAI.rangedAttackTarget,state))
			object.creatureAI.rangedAttackTarget=0;
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
			if(!object.patrolAround(targetPosition,guardDistance,state))
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
				if(object.creatureState.mode!=CreatureMode.cower){
					auto shelter=state.proximity.closestPeasantShelterInRange(object.side,object.position,shelterDistance,state);
					if(shelter){
						if(auto enemy=state.proximity.closestEnemyInRange(object.side,object.position,scareDistance,EnemyType.creature,state)){
							auto enemyPosition=state.movingObjectById!((obj)=>obj.position,function Vector3f(){ assert(0); })(enemy);
							// TODO: figure out the original rule for this
							if(object.creatureState.mode==CreatureMode.idle&&object.creatureState.timer>=updateFPS)
								playSoundTypeAt(object.sacObject,object.id,SoundType.run,state);
							object.moveTowards(object.position-(enemyPosition-object.position),state);
						}else object.stop(state);
					}else object.startCowering(state);
				}
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
			auto target=Target(object.creatureAI.order.target.type,object.creatureAI.order.target.id,object.creatureAI.order.target.position);
			if(!ability||!object.useAbility(ability,target,state)){
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

void updateCreatureState(B)(ref MovingObject!B object, ObjectState!B state){
	if(object.creatureStats.effects.stunCooldown!=0) --object.creatureStats.effects.stunCooldown;
	if(object.creatureStats.effects.rangedCooldown!=0) --object.creatureStats.effects.rangedCooldown;
	if(object.creatureStats.effects.abilityCooldown!=0) --object.creatureStats.effects.abilityCooldown;
	auto sacObject=object.sacObject;
	final switch(object.creatureState.mode){
		case CreatureMode.idle, CreatureMode.moving:
			auto oldMode=object.creatureState.mode;
			auto newMode=object.creatureState.movementDirection==MovementDirection.none&&object.creatureState.speed==0.0f?CreatureMode.idle:CreatureMode.moving;
			object.creatureState.timer+=1;
			object.frame+=1;
			if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor){
				object.frame=0;
				object.creatureState.mode=newMode;
				object.setCreatureState(state);
			}else if(newMode!=oldMode && object.creatureState.timer>=0.1f*updateFPS){
				object.creatureState.mode=newMode;
				object.setCreatureState(state);
			}
			if(oldMode==newMode&&newMode==CreatureMode.idle && object.animationState.among(AnimationState.run,AnimationState.walk) && object.creatureState.timer>=0.1f*updateFPS){
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
					if(object.creatureState.fallingVelocity.z<=0.0f&&object.position.z<=state.getGroundHeight(object.position)){
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
			if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor){
				object.frame=0;
				final switch(object.creatureState.movement){
					case CreatureMovement.onGround:
						object.frame=sacObject.numFrames(object.animationState)*updateAnimFactor-1;
						if(object.creatureState.mode==CreatureMode.dying){
							object.creatureState.mode=CreatureMode.dead;
							object.spawnSoul(state);
							object.unselect(state);
							object.removeFromGroups(state);
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
				if(state.isOnGround(object.position)&&object.position.z<=state.getGroundHeight(object.position))
					object.creatureState.movement=CreatureMovement.onGround;
			}
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

		case CreatureMode.reviving, CreatureMode.fastReviving:
			static immutable reviveSequence=[AnimationState.corpse,AnimationState.float_];
			auto reviveTime=cast(int)(object.creatureStats.reviveTime*updateFPS);
			auto fast=object.creatureState.mode!=CreatureMode.reviving;
			if(fast) reviveTime/=2;
			auto totalNumFrames=0;
			foreach(i,animationState;reviveSequence)
				if(sacObject.hasAnimationState(animationState))
					while(totalNumFrames<reviveTime){
						totalNumFrames+=sacObject.numFrames(animationState)*updateAnimFactor;
						if(i+1!=reviveSequence.length) break;
					}

			if(totalNumFrames==0) totalNumFrames=reviveTime;
			assert(totalNumFrames!=0);
			object.creatureState.timer+=1;
			object.creatureState.facing+=(fast?2.0f*pi!float:4.0f*pi!float)/totalNumFrames;
			while(object.creatureState.facing>pi!float) object.creatureState.facing-=2*pi!float;
			if(object.creatureState.timer<totalNumFrames/2){
				object.creatureState.movement=CreatureMovement.flying;
				object.position.z+=object.creatureStats.reviveHeight/(totalNumFrames/2);
			}
			object.rotation=facingQuaternion(object.creatureState.facing);
			void finish(){
				if(object.soulId){
					state.removeLater(object.soulId);
					object.soulId=0;
				}
				if(sacObject.canFly) object.creatureState.targetFlyingHeight=0.0f;
				object.creatureState.movement=CreatureMovement.tumbling;
				object.creatureState.fallingVelocity=Vector3f(0.0f,0.0f,0.0f);
				object.startIdling(state);
				state.newCreatureAddToSelection(object.side,object.id);
			}
			if(reviveSequence.canFind(object.animationState)){
				object.frame+=1;
				if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor){
					object.frame=0;
					if(object.creatureState.timer<totalNumFrames) object.pickNextAnimation(reviveSequence,state);
					else finish();
				}
			}else if(object.creatureState.timer>=totalNumFrames){
				object.frame=0;
				finish();
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
			with(AnimationState) assert(object.animationState.among(stance1,knocked2Floor,falling,tumble,hitFloor,getUp,damageFront,damageRight,damageBack,damageLeft,damageTop,flyDamage));
			if(object.creatureState.movement==CreatureMovement.tumbling&&object.creatureState.fallingVelocity.z<=0.0f){
				if(sacObject.canFly){
					object.creatureState.movement=CreatureMovement.flying;
					object.frame=0;
					object.animationState=AnimationState.hover;
					object.startIdling(state);
					break;
				}else if(state.isOnGround(object.position)&&object.position.z<=state.getGroundHeight(object.position)){
					object.creatureState.movement=CreatureMovement.onGround;
					if(object.animationState.among(AnimationState.falling,AnimationState.tumble)){
						if(sacObject.hasHitFloor){
							object.frame=0;
							object.animationState=AnimationState.hitFloor;
						}else object.startIdling(state);
					}
					break;
				}
			}
			object.frame+=1;
			if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor){
				object.frame=0;
				final switch(object.creatureState.movement){
					case CreatureMovement.onGround:
						if(object.animationState.among(AnimationState.knocked2Floor,AnimationState.hitFloor)&&sacObject.hasGetUp){
							object.animationState=AnimationState.getUp;
						}else object.startIdling(state);
						break;
					case CreatureMovement.flying:
						object.startIdling(state);
						break;
					case CreatureMovement.tumbling:
						if(object.animationState.among(AnimationState.knocked2Floor,AnimationState.getUp))
							goto case CreatureMovement.onGround;
						// continue tumbling
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
			auto newMode=object.creatureState.movementDirection==MovementDirection.none?CreatureMode.casting:CreatureMode.castingMoving;
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
			object.creatureState.timer-=1;
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
				return;
			}
			break;
	}
}

alias CollisionTargetSide(bool active:true)=int;
alias CollisionTargetSide(bool active:false)=Seq!();
auto collisionTargetImpl(bool attackFilter=false,bool returnHitbox=false,B)(int ownId,CollisionTargetSide!attackFilter side,Vector3f[2] hitbox,Vector3f[2] movedHitbox,ObjectState!B state){
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
auto collisionTarget(B)(int ownId,Vector3f[2] hitbox,Vector3f[2] movedHitbox,ObjectState!B state){
	return collisionTargetImpl!(false,false,B)(ownId,hitbox,movedHitbox,state);
}
auto collisionTargetWithHitbox(B)(int ownId,Vector3f[2] hitbox,Vector3f[2] movedHitbox,ObjectState!B state){
	return collisionTargetImpl!(false,true,B)(ownId,hitbox,movedHitbox,state);
}
int meleeAttackTarget(B)(int ownId,int side,Vector3f[2] hitbox,Vector3f[2] meleeHitbox,ObjectState!B state){
	return collisionTargetImpl!(true,false,B)(ownId,side,hitbox,meleeHitbox,state);
}

int meleeAttackTarget(B)(ref MovingObject!B object,ObjectState!B state){
	auto hitbox=object.hitbox,meleeHitbox=object.meleeHitbox;
	return meleeAttackTarget(object.id,object.side,hitbox,meleeHitbox,state);
}

void updateCreatureStats(B)(ref MovingObject!B object, ObjectState!B state){
	if(object.isRegenerating)
		object.heal(object.creatureStats.regeneration/updateFPS,state);
	if(object.creatureState.mode==CreatureMode.playingDead)
		object.heal(30.0f/updateFPS,state); // TODO: ok?
	if(object.creatureStats.mana<object.creatureStats.maxMana)
		object.giveMana(state.manaRegenAt(object.side,object.position)/updateFPS,state);
	if(object.creatureState.mode.among(CreatureMode.meleeMoving,CreatureMode.meleeAttacking) && object.hasAttackTick){
		object.creatureState.mode=CreatureMode.meleeAttacking;
		if(auto target=object.meleeAttackTarget(state)){
			static void dealDamage(T)(ref T target,MovingObject!B* attacker,ObjectState!B state){
				target.dealMeleeDamage(*attacker,state);
			}
			state.objectById!dealDamage(target,&object,state);
		}
	}
}

void updateCreaturePosition(B)(ref MovingObject!B object, ObjectState!B state){
	auto newPosition=object.position;
	with(CreatureMode) if(object.creatureState.mode.among(idle,moving,stunned,landing,dying,meleeMoving,casting,castingMoving,shooting)){
		auto rotationSpeed=object.creatureStats.rotationSpeed(object.creatureState.movement==CreatureMovement.flying)/updateFPS;
		auto pitchingSpeed=object.creatureStats.pitchingSpeed/updateFPS;
		bool isRotating=false;
		if(object.creatureState.mode.among(idle,moving,meleeMoving,casting,castingMoving,shooting)&&
		   object.creatureState.movement!=CreatureMovement.tumbling
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
			auto targetFlyingHeight=object.creatureState.targetFlyingHeight;
			if(object.creatureState.mode.among(CreatureMode.landing,CreatureMode.idle)
			   ||object.creatureState.mode==CreatureMode.meleeAttacking&&object.position.z-state.getHeight(object.position)>targetFlyingHeight
			){
				auto height=state.getHeight(newPosition);
				if(newPosition.z>height+(isNaN(targetFlyingHeight)?0.0f:targetFlyingHeight)){
					auto downwardSpeed=object.creatureState.mode==CreatureMode.landing?object.creatureStats.landingSpeed/updateFPS:object.creatureStats.downwardHoverSpeed/updateFPS;
					newPosition.z-=downwardSpeed;
					if(state.isOnGround(newPosition)){
						if(newPosition.z<=height)
							newPosition.z=height;
					}
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
			object.creatureState.fallingVelocity.z-=object.creatureStats.fallingAcceleration/updateFPS;
			newPosition=object.position+object.creatureState.fallingVelocity/updateFPS;
			if(object.creatureState.fallingVelocity.z<=0.0f && state.isOnGround(newPosition))
				newPosition.z=max(newPosition.z,state.getGroundHeight(newPosition));
			break;
	}
	auto proximity=state.proximity;
	auto relativeHitbox=object.relativeHitbox;
	Vector3f[2] hitbox=[relativeHitbox[0]+newPosition,relativeHitbox[1]+newPosition];
	bool posChanged=false, needsFixup=false, isColliding=false;
	auto fixupDirection=Vector3f(0.0f,0.0f,0.0f);
	void handleCollision(bool fixup)(ProximityEntry entry){
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
	if(!object.creatureState.mode.among(CreatureMode.dead,CreatureMode.dissolving)){ // dead creatures do not participate in collision handling
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
	if(object.creatureState.movement!=CreatureMovement.onGround||onGround){
		if(posChanged){
			// TODO: improve? original engine does this, but it can cause ultrafast ascending for flying creatures
			final switch(object.creatureState.movement){
				case CreatureMovement.onGround:
					newPosition.z=state.getGroundHeight(newPosition);
					break;
				case CreatureMovement.flying, CreatureMovement.tumbling:
					if(onGround) newPosition.z=max(newPosition.z,state.getGroundHeight(newPosition));
					break;
			}
		}
		object.position=newPosition;
	}
}

void updateCreature(B)(ref MovingObject!B object, ObjectState!B state){
	object.updateCreatureAI(state);
	object.updateCreatureState(state);
	object.updateCreaturePosition(state);
	object.updateCreatureStats(state);
}

void updateSoul(B)(ref Soul!B soul, ObjectState!B state){
	soul.frame+=1;
	soul.facing+=2*pi!float/8.0f/updateFPS;
	while(soul.facing>pi!float) soul.facing-=2*pi!float;
	if(soul.frame==SacSoul!B.numFrames*updateAnimFactor)
		soul.frame=0;
	if(soul.creatureId&&soul.state!=SoulState.collecting)
		soul.position=state.movingObjectById!(soulPosition,()=>Vector3f(float.nan,float.nan,float.nan))(soul.creatureId);
	final switch(soul.state){
		case SoulState.normal:
			static struct State{
				int collector=0;
				int side=-1;
				float distancesqr=float.infinity;
				bool tied=false;
			}
			enum collectDistance=4.0f; // TODO: measure this
			static void process(B)(ref WizardInfo!B wizard,Soul!B* soul,State* pstate,ObjectState!B state){ // TODO: use proximity data structure?
				auto sidePosition=state.movingObjectById!((obj)=>tuple(obj.side,obj.center),function Tuple!(int,Vector3f)(){ assert(0); })(wizard.id);
				auto side=sidePosition[0],position=sidePosition[1];
				if((soul.position.xy-position.xy).lengthsqr>collectDistance^^2) return;
				if(abs(soul.position.z-position.z)>collectDistance) return;
				auto distancesqr=(soul.position-position).lengthsqr;
				if(soul.creatureId&&side!=soul.preferredSide) return;
				if(soul.preferredSide!=-1&&pstate.side==soul.preferredSide&&side!=soul.preferredSide) return;
				if(distancesqr>pstate.distancesqr) return;
				if(distancesqr==pstate.distancesqr){ pstate.tied=true; return; }
				*pstate=State(wizard.id,side,distancesqr,false);
			}
			State pstate;
			state.eachWizard!process(&soul,&pstate,state);
			if(pstate.collector&&!pstate.tied){
				soul.collectorId=pstate.collector;
				soul.state=SoulState.collecting;
				playSoundAt("rips",soul.collectorId,state,2.0f);
				auto wizard=state.getWizard(soul.collectorId);
				if(wizard) wizard.souls+=soul.number;
				if(soul.creatureId){
					state.movingObjectById!((ref creature,state){
						creature.soulId=0;
						creature.startDissolving(state);
					})(soul.creatureId,state);
				}
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
		case SoulState.collecting:
			assert(soul.collectorId!=0);
			auto previousScaling=soul.scaling;
			soul.scaling-=4.0f/updateFPS;
			// TODO: how to do this more nicely?
			auto factor=soul.scaling/previousScaling;
			soul.position=factor*soul.position+(1.0f-factor)*state.movingObjectById!((wiz)=>wiz.center+Vector3f(0.0f,0.0f,0.5f),()=>soul.position)(soul.collectorId);
			if(soul.scaling<=0.0f){
				soul.scaling=0.0f;
				state.removeLater(soul.id);
				soul.number=0;
			}
			break;
	}
}

void updateParticles(B,bool relative)(ref Particles!(B,relative) particles, ObjectState!B state){
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
bool updateFire(B)(ref Fire!B fire,ObjectState!B state){
	with(fire){
		if(!state.targetTypeFromId(target).among(TargetType.creature,TargetType.building))
			return false;
		static assert(updateFPS==60);
		auto hitbox=state.objectById!hitbox(target);
		auto dim=hitbox[1]-hitbox[0];
		auto volume=dim.x*dim.y*dim.z;
		auto scale=2.0f*max(1.0f,cbrt(volume));
		auto sacParticle=SacParticle!B.get(ParticleType.fire);
		enum numParticles=5;
		foreach(i;0..numParticles){
			auto position=state.uniform(scaleBox(hitbox,1.1f));
			auto distance=(state.uniform(3)?state.uniform(0.3f,0.6f):state.uniform(1.5f,2.5f))*(hitbox[1].z-hitbox[0].z);
			auto fullLifetime=sacParticle.numFrames/float(updateFPS);
			auto lifetime=cast(int)(sacParticle.numFrames*state.uniform(0.0f,1.0f));
			auto velocity=Vector3f(0.0f,0.0f,distance/fullLifetime);
			state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,0));
		}
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
				state.movingObjectById!animateCreatureCasting(manaDrain.wizard,spell,state);
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
		})(building,thresholdZ,state);
		state.movingObjectById!animateCastingForGod(manaDrain.wizard,god,state);
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
				return true;
			case CastingStatus.interrupted:
				state.buildingById!destroy(building,state);
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

void animateCasting(bool spread=true,int numParticles=-1,B)(ref MovingObject!B wizard,SacParticle!B sacParticle,ObjectState!B state){
	auto hands=wizard.hands;
	static if(numParticles==-1){
		static if(spread) enum numParticles=2;
		else enum numParticles=1;
	}
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
			auto lifetime=31;
			auto frame=0;
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
					})(creature,sacParticle,state);
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
					})(manaDrain.wizard,sacParticle,state);
				}
				state.movingObjectById!animateHealCasting(manaDrain.wizard,state);
				return true;
			case CastingStatus.interrupted: return false;
			case CastingStatus.finished:
				heal(creature,spell,state);
				return false;
		}
	}
}
bool updateHeal(B)(ref Heal!B heal,ObjectState!B state){
	heal.timer-=1;
	if(heal.timer<0) return false;
	return state.movingObjectById!((ref obj,heal,state){
		if(!obj.canHeal(state)) return false;
		obj.heal(heal.healthRegenerationPerFrame,state);
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
bool updateLightning(B)(ref Lightning!B lightning,ObjectState!B state){
	lightning.frame+=1;
	static assert(updateFPS==60);
	if(lightning.frame>=lightning.totalFrames) return false;
	if(lightning.frame%lightning.changeShapeDelay==0)
		foreach(ref bolt;lightning.bolts)
			bolt.changeShape(state);
	lightning.end.position=lightning.end.center(state);
	if(lightning.frame==lightning.travelDelay){
		enum numSparks=128;
		auto sacParticle=SacParticle!B.get(ParticleType.spark);
		auto hitbox=lightning.end.hitbox(state);
		auto center=boxCenter(hitbox);
		foreach(i;0..numSparks){
			auto position=state.uniform(scaleBox(hitbox,1.2f));
			auto velocity=Vector3f(position.x-center.x,position.y-center.y,0.0f).normalized;
			velocity.z=2.0f;
			auto scale=1.0f;
			int lifetime=31;
			int frame=0;
			state.addParticle(Particle!B(sacParticle,position,velocity,scale,lifetime,frame));
		}
		// TODO: scar
		auto target=lightning.end.id;
		if(state.isValidTarget(target)){
			auto direction=lightning.end.position-lightning.start.position;
			dealSpellDamage(target,lightning.spell,lightning.wizard,lightning.side,direction,state);
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
		return state.movingObjectById!((obj){
			final switch(manaDrain.update(state)){
				case CastingStatus.underway:
					obj.animateWrathCasting(state);
					return true;
				case CastingStatus.interrupted:
					return false;
				case CastingStatus.finished:
					auto hands=obj.hands;
					Vector3f start=isNaN(hands[0].x)?hands[1]:isNaN(hands[1].x)?hands[0]:0.5f*(hands[0]+hands[1]);
					if(isNaN(start.x)){
						auto hbox=obj.sacObject.hitbox(Quaternionf.identity(),AnimationState.stance1,0);
						auto offset=Vector3f(0.0f,hbox[1].y+0.75f,hbox[1].z+0.5f);
						start=rotate(obj.rotation,offset)+obj.position;
					}
					wrath(obj.id,obj.side,start,wrathCast.target,spell,state);
					return false;
			}
		},()=>false)(manaDrain.wizard);
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
void collisionTargets(alias f,alias filter=None,bool uniqueBuildingIds=false,B,T...)(Vector3f[2] hitbox,ObjectState!B state,T args){
	static struct CollisionState{ SmallArray!(ProximityEntry,32) targets; }
	static void handleCollision(ProximityEntry entry,CollisionState* collisionState,ObjectState!B state,T args){
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
		return state.objectById!(.side)(entry.id,state)!=side;
	}
	return collisionTarget!(wrathHitbox,filter)(side,position,state,side);
}
void wrathExplosion(B)(ref Wrath!B wrath,int target,ObjectState!B state){
	wrath.status=WrathStatus.exploding;
	playSoundAt("hhtr",wrath.position,state,4.0f);
	if(state.isValidTarget(target)) dealSpellDamage(target,wrath.spell,wrath.wizard,wrath.side,wrath.velocity,state);
	else target=0;
	dealSplashSpellDamageAt(target,wrath.spell,wrath.spell.effectRange,wrath.wizard,wrath.side,wrath.position,state);
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
bool updateWrath(B)(ref Wrath!B wrath,ObjectState!B state){
	with(wrath){
		final switch(wrath.status){
			case WrathStatus.flying:
				auto targetCenter=target.center(state);
				auto predictedCenter=predictor.predictCenter(position,spell.speed,target,state);
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
					auto flyingHeight=min(wrathFlyingHeight,0.75f*(targetCenter.xy-position.xy).length);
					if(newPosition.z<height+flyingHeight){
						auto nvel=velocity;
						nvel.z+=(height+flyingHeight-newPosition.z)*updateFPS;
						newPosition=position+capVelocity(nvel)/updateFPS;
					}
				}
				position=newPosition;
				wrath.animateWrath(state);
				auto target=wrathCollisionTarget(side,position,state);
				if(state.isValidTarget(target)) wrath.wrathExplosion(target,state);
				else if(state.isOnGround(position)){
					if(position.z<state.getGroundHeight(position))
						wrath.wrathExplosion(0,state);
				}
				if(status!=WrathStatus.exploding){
					if((targetCenter-position).lengthsqr<0.05f^^2)
						wrath.wrathExplosion(wrath.target.id,state);
				}
				return true;
			case WrathStatus.exploding:
				return ++frame<64;
		}
	}
}

bool updateFireballCasting(B)(ref FireballCasting!B fireballCast,ObjectState!B state){
	with(fireballCast){
		fireball.target.position=fireball.target.center(state);
		return state.movingObjectById!((obj){
			final switch(manaDrain.update(state)){
				case CastingStatus.underway:
					fireball.position=obj.fireballCastingPosition(state);
					fireball.rotation=fireball.rotationUpdate*fireball.rotation;
					obj.animatePyroCasting(state);
					frame+=1;
					return true;
				case CastingStatus.interrupted:
					return false;
				case CastingStatus.finished:
					.fireball(fireball,state);
					return false;
			}
		},()=>false)(manaDrain.wizard);
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
		return state.objectById!(.side)(entry.id,state)!=side;
	}
	return collisionTarget!(fireballHitbox,filter)(side,position,state,side);
}

void fireballExplosion(B)(ref Fireball!B fireball,int target,ObjectState!B state){
	playSpellSoundTypeAt(SoundType.explodingFireball,fireball.position,state,8.0f);
	if(state.isValidTarget(target)){
		dealSpellDamage(target,fireball.spell,fireball.wizard,fireball.side,fireball.velocity,state);
		setAblaze(target,updateFPS,false,0.0f,fireball.wizard,fireball.side,state);
	}else target=0;
	static bool callback(int target,int wizard,int side,ObjectState!B state){
		setAblaze(target,updateFPS,false,0.0f,wizard,side,state);
		return true;
	}
	dealSplashSpellDamageAt!callback(target,fireball.spell,fireball.spell.effectRange,fireball.wizard,fireball.side,fireball.position,state,fireball.wizard,fireball.side,state);
	//explosionParticles(fireball.position,state);
	enum numParticles1=200;
	enum numParticles2=800;
	auto sacParticle1=SacParticle!B.get(ParticleType.explosion);
	auto sacParticle2=SacParticle!B.get(ParticleType.explosion2);
	foreach(i;0..numParticles1+numParticles2){
		auto position=fireball.position;
		auto direction=state.uniformDirection();
		auto velocity=(i<numParticles1?1.0f:1.5f)*state.uniform(1.5f,6.0f)*direction;
		auto scale=1.0f;
		auto lifetime=31;
		auto frame=0;
		state.addParticle(Particle!B(i<numParticles1?sacParticle1:sacParticle2,position,velocity,scale,lifetime,frame));
	}
	enum numParticles3=300;
	auto sacParticle3=SacParticle!B.get(ParticleType.ashParticle);
	foreach(i;0..numParticles3){
		auto direction=state.uniformDirection();
		auto velocity=state.uniform(7.5f,15.0f)*direction;
		auto scale=state.uniform(0.75f,1.5f);
		auto lifetime=95;
		auto frame=0;
		state.addParticle(Particle!B(sacParticle3,fireball.position,velocity,scale,lifetime,frame));
	}
	enum numParticles4=75;
	auto sacParticle4=SacParticle!B.get(ParticleType.smoke);
	foreach(i;0..numParticles4){
		auto position=fireball.position;
		auto direction=state.uniformDirection();
		auto velocity=state.uniform(0.5f,2.0f)*direction+Vector3f(0.0f,0.0f,0.5f);
		auto scale=1.0f;
		auto lifetime=127;
		auto frame=0;
		state.addParticle(Particle!B(sacParticle4,position,velocity,scale,lifetime,frame));
	}
}

enum fireballFlyingHeight=0.5f;
bool updateFireball(B)(ref Fireball!B fireball,ObjectState!B state){
	with(fireball){
		auto oldPosition=position;
		auto targetCenter=target.center(state);
		auto predictedCenter=predictor.predictCenter(position,spell.speed,target,state);
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
			auto flyingHeight=min(fireballFlyingHeight,0.75f*(targetCenter.xy-position.xy).length);
			if(newPosition.z<height+flyingHeight){
				auto nvel=velocity;
				nvel.z+=(height+flyingHeight-newPosition.z)*updateFPS;
				newPosition=position+capVelocity(nvel)/updateFPS;
			}
		}
		position=newPosition;
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
		if((targetCenter-position).lengthsqr<0.05f^^2){
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
		return state.movingObjectById!((obj){
			final switch(manaDrain.update(state)){
				case CastingStatus.underway:
					rock.position=obj.rockCastingPosition(state);
					rock.position.z+=rockBuryDepth*min(1.0f,float(frame)/castingTime);
					obj.animateRockCasting(state);
					frame+=1;
					return true;
				case CastingStatus.interrupted:
					return false;
				case CastingStatus.finished:
					rock.position.z=max(rock.position.z,state.getHeight(rock.position)); // for robustness
					.rock(rock,state);
					return false;
			}
		},()=>false)(manaDrain.wizard);
	}
}
void animateEmergingRock(B)(ref Rock!B rock,ObjectState!B state){
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
		return entry.id!=immuneId;
	}
	return collisionTarget!(rockHitbox,filter)(side,position,state,immuneId);
}

void rockExplosion(B)(ref Rock!B rock,int target,ObjectState!B state){
	playSpellSoundTypeAt(SoundType.explodingRock,rock.position,state,8.0f);
	if(state.isValidTarget(target)) dealSpellDamage(target,rock.spell,rock.wizard,rock.side,rock.velocity,state);
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

enum rockFloatingHeight=7.0f;
bool updateRock(B)(ref Rock!B rock,ObjectState!B state){
	with(rock){
		auto oldPosition=position;
		auto targetCenter=target.center(state);
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
		auto floatingHeight=min(rockFloatingHeight,0.75f*(targetCenter.xy-position.xy).length);
		if(newPosition.z<height+floatingHeight){
			auto nvel=velocity;
			nvel.z+=(height+floatingHeight-newPosition.z)*updateFPS;
			newPosition=position+capVelocity(nvel)/updateFPS;
		}
		position=newPosition;
		rotation=rotationUpdate*rotation;
		rock.animateRock(oldPosition,state);
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
		return state.movingObjectById!((obj){
			final switch(manaDrain.update(state)){
				case CastingStatus.underway:
					swarm.relocate(obj.swarmCastingPosition(state));
					if(swarm.frame>0) swarm.addBugs(obj,state);
					return swarm.updateSwarm(state);
				case CastingStatus.interrupted:
					swarm.status=SwarmStatus.dispersing;
					.swarm(swarm,state);
					return false;
				case CastingStatus.finished:
					swarm.status=SwarmStatus.flying;
					.swarm(move(swarm),state);
					return false;
			}
		},()=>false)(manaDrain.wizard);
	}
}

enum swarmSize=0.3f;
static immutable Vector3f[2] swarmHitbox=[-0.5f*swarmSize*Vector3f(1.0f,1.0f,1.0f),0.5f*swarmSize*Vector3f(1.0f,1.0f,1.0f)];
int swarmCollisionTarget(B)(int side,Vector3f position,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state,int side){
		return state.objectById!(.side)(entry.id,state)!=side;
	}
	return collisionTarget!(swarmHitbox,filter)(side,position,state,side);
}

Vector3f makeTargetPosition(B)(ref Swarm!B swarm,float radius,ObjectState!B state){
	return swarm.position+state.uniform(0.0f,radius)*state.uniformDirection();
}

enum swarmFlyingHeight=1.25f;
enum swarmDispersingFrames=2*updateFPS;
bool addBugs(B)(ref Swarm!B swarm,ref MovingObject!B wizard,ObjectState!B state){
	enum totalBugs=250;
	auto num=(totalBugs-swarm.bugs.length+swarm.frame-1)/swarm.frame;
	auto hands=wizard.hands;
	if(isNaN(hands[0].x)&&isNaN(hands[1].x)){
		auto hbox=wizard.sacObject.hitbox(Quaternionf.identity(),AnimationState.stance1,0);
		auto offset=Vector3f(0.0f,hbox[1].y,hbox[1].z);
		hands[0]=rotate(wizard.rotation,offset)+wizard.position;
	}
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
		dealSpellDamage(target,swarm.spell,swarm.wizard,swarm.side,swarm.velocity,state);
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
	dealSplashSpellDamageAt(target,swarm.spell,swarm.spell.effectRange,swarm.wizard,swarm.side,swarm.position,state);
}
bool updateSwarm(B)(ref Swarm!B swarm,ObjectState!B state){
	with(swarm){
		final switch(status){
			case SwarmStatus.casting:
				frame-=1;
				return swarm.updateBugs(state);
			case SwarmStatus.flying:
				auto targetCenter=target.center(state);
				auto predictedCenter=predictor.predictCenter(position,spell.speed,target,state);
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
					auto flyingHeight=min(swarmFlyingHeight,0.75f*(targetCenter.xy-position.xy).length);
					if(newPosition.z<height+flyingHeight){
						auto nvel=velocity;
						nvel.z+=(height+flyingHeight-newPosition.z)*updateFPS;
						newPosition=position+capVelocity(nvel)/updateFPS;
					}
				}
				swarm.position=newPosition;
				auto target=swarmCollisionTarget(side,position,state);
				if(state.isValidTarget(target)) swarm.swarmHit(target,state);
				else if(state.isOnGround(position)){
					if(position.z<state.getGroundHeight(position))
						swarm.swarmHit(0,state);
				}
				if(status!=SwarmStatus.dispersing){
					if((targetCenter-position).length<0.05f^^2)
						swarm.swarmHit(swarm.target.id,state);
				}
				return swarm.updateBugs(state);
			case SwarmStatus.dispersing:
				swarm.disperseBugs(state);
				return ++frame<swarmDispersingFrames;
		}
	}
}
enum brainiacProjectileHitGain=4.0f;
enum brainiacProjectileSize=0.45f; // TODO: ok?
enum brainiacProjectileSlidingDistance=1.5f;
static immutable Vector3f[2] brainiacProjectileHitbox=[-0.5f*brainiacProjectileSize*Vector3f(1.0f,1.0f,1.0f),0.5f*brainiacProjectileSize*Vector3f(1.0f,1.0f,1.0f)];
int brainiacProjectileCollisionTarget(B)(int side,int intendedTarget,Vector3f position,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state,int side,int intendedTarget){
		return entry.id==intendedTarget||state.objectById!(.side)(entry.id,state)!=side;
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
				dealRangedDamage(target.id,rangedAttack,attacker,side,direction,state);
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
		return entry.id==intendedTarget||state.objectById!(.side)(entry.id,state)!=side;
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
				dealRangedDamage(target.id,rangedAttack,attacker,side,direction,state);
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
				dealRangedDamage(intendedTarget,rangedAttack,attacker,side,attackDirection,state); // TODO: ok?
				setAblaze(id,updateFPS/2,true,0.0f,attacker,side,state);
				return false;
			}
			if(validTarget&&state.objectById!(.side)(id,state)==side)
				return false;
			if(validTarget) setAblaze(id,updateFPS/2,true,0.0f,attacker,side,state);
			return true;
		}
		auto radius=finalSpitfireProjectileSize*frame/(updateFPS*rangedAttack.range/rangedAttack.speed);
		dealSplashRangedDamageAt!callback(0,rangedAttack,radius,attacker,side,position,state,&damagedTargets,attacker,side,intendedTarget,rangedAttack,direction,state);
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
				dealRangedDamage(intendedTarget,rangedAttack,attacker,side,attackDirection,state); // TODO: ok?
				return false;
			}
			if(validTarget&&state.objectById!(.side)(id,state)==side)
				return false;
			return true;
		}
		auto radius=finalGargoyleProjectileSize*frame/(updateFPS*rangedAttack.range/rangedAttack.speed);
		dealSplashRangedDamageAt!callback(0,rangedAttack,radius,attacker,side,position,state,&damagedTargets,attacker,side,intendedTarget,rangedAttack,direction,state);
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
		return entry.id==intendedTarget||state.objectById!(.side)(entry.id,state)!=side;
	}
	return collisionTarget!(earthflingProjectileHitbox,filter)(side,position,state,side,intendedTarget);
}

void earthflingProjectileExplosion(B)(ref EarthflingProjectile!B earthflingProjectile,int target,ObjectState!B state){
	playSoundAt("pmir",earthflingProjectile.position,state,2.0f);
	if(state.isValidTarget(target)) dealRangedDamage(target,earthflingProjectile.rangedAttack,earthflingProjectile.attacker,earthflingProjectile.side,earthflingProjectile.velocity,state);
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
		return entry.id==intendedTarget||state.objectById!(.side)(entry.id,state)!=side;
	}
	return collisionTarget!(flameMinionProjectileHitbox,filter)(side,position,state,side,intendedTarget);
}

void flameMinionProjectileExplosion(B)(ref FlameMinionProjectile!B flameMinionProjectile,int target,ObjectState!B state){
	if(state.isValidTarget(target)){
		dealRangedDamage(target,flameMinionProjectile.rangedAttack,flameMinionProjectile.attacker,flameMinionProjectile.side,flameMinionProjectile.velocity,state);
		with(flameMinionProjectile) setAblaze(target,updateFPS/4,true,0.0f,attacker,side,state);
	}
	enum numParticles4=30;
	auto sacParticle4=SacParticle!B.get(ParticleType.fire);
	foreach(i;0..numParticles4){
		auto direction=state.uniformDirection();
		auto position=flameMinionProjectile.position+0.25f*direction;
		auto velocity=Vector3f(0.0f,0.0f,1.0f); // TODO: original uses vibrating particles
		auto scale=1.0f;
		auto frame=state.uniform(2)?0:state.uniform(24);
		auto lifetime=63-frame;
		state.addParticle(Particle!B(sacParticle4,position,velocity,scale,lifetime,frame));
	}
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
		dealRangedDamage(target,fallenProjectile.rangedAttack,fallenProjectile.attacker,fallenProjectile.side,fallenProjectile.velocity,state);
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
		return entry.id==intendedTarget||state.objectById!(.side)(entry.id,state)!=side;
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
		static bool check(ref MovingObject!B attacker){
			return attacker.creatureState.mode.isShooting&&!attacker.hasShootTick;
		}
		return state.movingObjectById!(check,()=>false)(attacker);
	}
}

enum sylphProjectileSize=0.1f; // TODO: ok?
static immutable Vector3f[2] sylphProjectileHitbox=[-0.5f*sylphProjectileSize*Vector3f(1.0f,1.0f,1.0f),0.5f*sylphProjectileSize*Vector3f(1.0f,1.0f,1.0f)];
int sylphProjectileCollisionTarget(B)(int side,int intendedTarget,Vector3f position,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state,int side,int intendedTarget){
		return entry.id==intendedTarget||state.objectById!(.side)(entry.id,state)!=side;
	}
	return collisionTarget!(sylphProjectileHitbox,filter)(side,position,state,side,intendedTarget);
}

void sylphProjectileHit(B)(ref SylphProjectile!B sylphProjectile,int target,ObjectState!B state){
	playSpellSoundTypeAt(SoundType.arrow,sylphProjectile.position,state,2.0f);
	if(state.isValidTarget(target))
		dealRangedDamage(target,sylphProjectile.rangedAttack,sylphProjectile.attacker,sylphProjectile.side,sylphProjectile.velocity,state);
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
		static bool check(ref MovingObject!B attacker){
			return attacker.creatureState.mode.isShooting&&!attacker.hasShootTick;
		}
		return state.movingObjectById!(check,()=>false)(attacker);
	}
}

enum rangerProjectileSize=0.1f; // TODO: ok?
static immutable Vector3f[2] rangerProjectileHitbox=[-0.5f*rangerProjectileSize*Vector3f(1.0f,1.0f,1.0f),0.5f*rangerProjectileSize*Vector3f(1.0f,1.0f,1.0f)];
int rangerProjectileCollisionTarget(B)(int side,int intendedTarget,Vector3f position,ObjectState!B state){
	static bool filter(ProximityEntry entry,ObjectState!B state,int side,int intendedTarget){
		return entry.id==intendedTarget||state.objectById!(.side)(entry.id,state)!=side;
	}
	return collisionTarget!(rangerProjectileHitbox,filter)(side,position,state,side,intendedTarget);
}

void rangerProjectileHit(B)(ref RangerProjectile!B rangerProjectile,int target,ObjectState!B state){
	playSpellSoundTypeAt(SoundType.arrow,rangerProjectile.position,state,2.0f);
	if(state.isValidTarget(target))
		dealRangedDamage(target,rangerProjectile.rangedAttack,rangerProjectile.attacker,rangerProjectile.side,rangerProjectile.velocity,state);
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

bool updateRockForm(B)(ref RockForm!B rockForm,ObjectState!B state){
	with(rockForm){
		if(!state.isValidTarget(target,TargetType.creature)) return false;
		if(status!=RockFormStatus.shrinking){
			static bool check(ref MovingObject!B obj){
				return obj.creatureState.mode==CreatureMode.rockForm;
			}
			if(!state.movingObjectById!(check,()=>false)(target)){
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
	final switch(obj.creatureState.mode) with(CreatureMode){
		case idle,moving,spawning,takeoff,landing,cower,pretendingToDie,playingDead,pretendingToRevive,rockForm: return true;
		case dying,dead,dissolving,preSpawning,reviving,fastReviving,meleeMoving,meleeAttacking,stunned,casting,stationaryCasting,castingMoving,shooting: return false;
	}
}

bool updateStealth(B)(ref Stealth!B stealth,ObjectState!B state){
	with(stealth){
		if(!state.isValidTarget(target,TargetType.creature)) return false;
		updateRenderMode(target,state);
		if(status!=StealthStatus.fadingIn){
			static bool check(ref MovingObject!B obj){
				assert(obj.creatureStats.effects.stealth);
				return obj.checkStealth();
			}
			if(!state.movingObjectById!(check,()=>false)(target)){
				status=StealthStatus.fadingIn;
				playSoundAt("tlts",target,state,2.0f);
			}
		}
		void updateAlpha(){
			state.setAlpha(target,1.0f+progress*(targetAlpha-1.0f));
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
					state.movingObjectById!removeStealth(target);
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
		if(--soundEffectTimer==0) soundEffectTimer=playSoundAt!true("lhsl",target,state,2.0f);
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
					state.movingObjectById!removeLifeShield(target);
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
			state.movingObjectById!doIt(entry.id,lifeShield,state);
		}
		state.proximity.eachInRange!applyShield(object.center,ability.effectRange,object.id,object.side,lifeShield,state);
	}
	state.movingObjectById!applyProtector(protector.id,protector.ability,state);
	return false;
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
	for(int i=0;i<effects.protectors.length;){
		if(!updateProtector(effects.protectors[i],state)){
			effects.removeProtector(i);
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

void explosionAnimation(B)(Vector3f position,ObjectState!B state){
	playSoundAt("pxbf",position,state,10.0f);
	state.addEffect(Explosion!B(position,0.0f,30.0f,40.0f,0));
	state.addEffect(Explosion!B(position,0.0f,5.0f,10.0f,0));
	explosionParticles(position,state);
}

void animateDebris(B)(Vector3f position,ObjectState!B state){
	enum numDebris=35;
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

void animateAsh(B)(Vector3f position,ObjectState!B state){
	enum numParticles=300;
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

void setAblaze(B)(int target,int lifetime,bool ranged,float damage,int attacker,int side,ObjectState!B state){
	state.addEffect(Fire!B(target,lifetime,ranged?damage/lifetime:0.0f,!ranged?damage/lifetime:0.0f,attacker,side));
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

void animateShrine(B)(Vector3f location, int side, ObjectState!B state){
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
		auto velocity=(1.5f+state.uniform(-0.5f,0.5f))*Vector3f(0.0f,0.0f,state.uniform(2.0f,4.0f)).normalized;
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
			animateShrine(position,building.side,state);
		}
	}
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
	int side=state.movingObjectById!((ref obj)=>obj.side,()=>-1)(wizard.id);
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
	playSpellbookSound(side,flags,"vaps",state);
}


void addToProximity(T,B)(ref T objects, ObjectState!B state){
	auto proximity=state.proximity;
	enum isMoving=is(T==MovingObjects!(B, renderMode), RenderMode renderMode);
	enum isStatic=is(T==StaticObjects!(B, renderMode), RenderMode renderMode);
	static if(isMoving){
		foreach(j;0..objects.length){
			bool isObstacle=objects.creatureStates[j].mode.isObstacle;
			bool isVisibleToAI=objects.creatureStates[j].mode.isVisibleToAI&&!(objects.creatureStatss[j].flags&Flags.notOnMinimap)&&!objects.creatureStatss[j].effects.stealth;
			if(!isObstacle&&!isVisibleToAI) continue;
			auto hitbox=objects.sacObject.hitbox(objects.rotations[j],objects.animationStates[j],objects.frames[j]/updateAnimFactor);
			auto position=objects.positions[j];
			hitbox[0]+=position;
			hitbox[1]+=position;
			if(isObstacle){
				proximity.insert(ProximityEntry(objects.ids[j],hitbox));
			}
			if(isVisibleToAI){
				int attackTargetId=0;
				if(objects.creatureAIs[j].order.command==CommandType.attack)
					attackTargetId=objects.creatureAIs[j].order.target.id;
				proximity.insertCenter(CenterProximityEntry(false,objects.ids[j],objects.sides[j],boxCenter(hitbox),attackTargetId));
			}
		}
		if(objects.sacObject.isManahoar){
			static bool manahoarAbilityEnabled(CreatureMode mode){
				final switch(mode) with(CreatureMode){
					case idle,moving,dying,spawning,takeoff,landing,meleeMoving,meleeAttacking,stunned,cower,pretendingToDie,rockForm: return true;
					case dead,dissolving,preSpawning,reviving,fastReviving,playingDead,pretendingToRevive: return false;
					case casting,stationaryCasting,castingMoving,shooting: assert(0);
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
				if(!(flags&Flags.notOnMinimap))
					proximity.insertCenter(CenterProximityEntry(true,objects.ids[j],sideFromBuildingId(buildingId,state),boxCenter(hitbox),0,health==0.0f));
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
			auto distance=(position.xy-entry.position.xy).length;
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
			auto distance=(position.xy-manalith.position.xy).length;
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
	int id;
	int side;
	Vector3f position;
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
	struct State{
		auto entry=CenterProximityEntry.init;
		static if(hasPriority) int prio;
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
			state.distancesqr=distancesqr;
		}
	}
	State state;
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
	private static bool isEnemy(T...)(ref CenterProximityEntry entry,int side,EnemyType type,ObjectState!B state,T ignored){
		if(type==EnemyType.creature&&entry.isStatic) return false;
		if(type==EnemyType.building&&!entry.isStatic) return false;
		if(entry.zeroHealth) return false;
		return state.sides.getStance(side,entry.side)==Stance.enemy;
	}
	int closestEnemyInRange(int side,Vector3f position,float range,EnemyType type,ObjectState!B state){
		return centers.closestInRange!isEnemy(version_,position,range,side,type,state).id;
	}
	private static bool isPeasantShelter(ref CenterProximityEntry entry,int side,ObjectState!B state){
		if(!entry.isStatic) return false;
		if(state.sides.getStance(entry.side,side)==Stance.enemy) return false;
		return state.staticObjectById!((obj,state)=>state.buildingById!((ref bldg)=>bldg.isPeasantShelter,()=>false)(obj.buildingId),()=>false)(entry.id,state);
	}
	int closestPeasantShelterInRange(int side,Vector3f position,float range,ObjectState!B state){
		return centers.closestInRange!isPeasantShelter(version_,position,range,side,state).id;
	}
	private static int advancePriority(ref CenterProximityEntry entry,int side,EnemyType type,ObjectState!B state,int id){
		if(entry.attackTargetId==id) return 1;
		return 0;
	}
	int closestEnemyInRangeAndClosestToPreferringAttackersOf(int side,Vector3f position,float range,Vector3f targetPosition,int id,EnemyType type,ObjectState!B state){
		return centers.inRangeAndClosestTo!(isEnemy,advancePriority)(version_,position,range,targetPosition,side,type,state,id).id;
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
	float manaRegenAt(int side,Vector3f position){
		return proximity.manaRegenAt(side,position,this);
	}
	float sideDamageMultiplier(int attackerSide,int defenderSide){
		switch(sides.getStance(attackerSide,defenderSide)){
			case Stance.ally: return 0.5f; // TODO: option
			default: return 1.0f;
		}
	}
	this(SacMap!B map, Sides!B sides, Proximity!B proximity){
		this.map=map;
		this.sides=sides;
		this.proximity=proximity;
		sid=SideManager!B(32);
	}
	bool isOnGround(Vector3f position){
		return map.isOnGround(position);
	}
	Vector3f moveOnGround(Vector3f position,Vector3f direction){
		return map.moveOnGround(position,direction);
	}
	float getGroundHeight(Vector3f position){
		return map.getGroundHeight(position);
	}
	float getHeight(Vector3f position){
		return map.getHeight(position);
	}
	float getGroundHeightDerivative(Vector3f position,Vector3f direction){
		return map.getGroundHeightDerivative(position,direction);
	}
	OrderTarget collideRay(alias filter=None,T...)(Vector3f start,Vector3f direction,float limit,T args){
		auto landscape=map.rayIntersection(start,direction,limit);
		auto tEntry=proximity.collideRay!filter(start,direction,min(limit,landscape),args);
		if(landscape<tEntry[0]) return OrderTarget(TargetType.terrain,0,start+landscape*direction);
		auto targetType=targetTypeFromId(tEntry[1].id);
		if(targetType.among(TargetType.creature,TargetType.building))
			return OrderTarget(targetType,tEntry[1].id,objectById!((obj)=>obj.position)(this,tEntry[1].id));
		return OrderTarget.init;
	}
	OrderTarget lineOfSight(alias filter=None,T...)(Vector3f start,Vector3f target,T args){
		return collideRay!filter(start,target-start,1.0f,args);
	}
	OrderTarget lineOfSightWithoutSide(Vector3f start,Vector3f target,int side,int intendedTarget=0){
		static bool filter(ref ProximityEntry entry,int side,int intendedTarget,ObjectState!B state){
			if(entry.id==intendedTarget) return true;
			return state.objectById!((obj,side,state)=>.side(obj,state)!=side)(entry.id,side,state);
		}
		return lineOfSight!filter(start,target,side,intendedTarget,this);
	}
	bool hasLineOfSightTo(Vector3f start,Vector3f target,int ignoredId,int targetId){
		static bool filter(ref ProximityEntry entry,int id){ return entry.id!=id; }
		auto result=lineOfSight!filter(start,target,ignoredId);
		return result.type==TargetType.none||result.type.among(TargetType.creature,TargetType.building,TargetType.soul)&&result.id==targetId;
	}
	int frame=0;
	auto rng=MinstdRand0(1); // TODO: figure out what rng to use
	// @property int hash(){ return rng.tupleof[0]; } // rng seed as proxy for state hash.
	@property int hash(){
		import std.digest.crc;
		CRC32 crc;
		crc.start();
		void sink(scope ubyte[] data){ copy(data,&crc); }
		import serialize_;
		serialize!sink(this);
		auto result=crc.finish();
		static assert(result.sizeof==int.sizeof);
		return *cast(int*)&result;
	}
	int uniform(int n){
		import std.random: uniform;
		return uniform(0,n,rng);
	}
	T uniform(string bounds="[]",T)(T a,T b){
		import std.random: uniform;
		return uniform!bounds(a,b,rng);
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
		return Vector3f(uniform(-1.0f,1.0f),uniform(-1.0f,1.0f),uniform(-1.0f,1.0f)).normalized;
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
		static bool applyOrder(Command!B command,ObjectState!B state,bool updateFormation=false,Vector2f formationOffset=Vector2f(0.0f,0.0f)){
			assert(command.type.among(CommandType.setFormation,CommandType.useAbility)||command.target.type.among(TargetType.terrain,TargetType.creature,TargetType.building));
			if(!command.creature){
				int[Formation.max+1] num;
				int numCreatures=0;
				Vector2f formationScale=Vector2f(1.0f,1.0f);
				foreach(selectedId;state.getSelection(command.side).creatureIds){
					if(!selectedId) break;
					static get(ref MovingObject!B object,ObjectState!B state){
						auto hitbox=object.sacObject.largeHitbox(Quaternionf.identity(),AnimationState.stance1,0);
						auto scale=hitbox[1].xy-hitbox[0].xy;
						return tuple(object.creatureAI.formation,scale);
					}
					auto curFormationCurScale=state.movingObjectById!(get,function Tuple!(Formation,Vector2f)(){ assert(0); })(selectedId,state);
					auto curFormation=curFormationCurScale[0],curScale=curFormationCurScale[1];
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
				auto selection=state.getSelection(command.side);
				auto targetScale=Vector2f(0.0f,0.0f);
				if(!command.type.among(CommandType.setFormation,CommandType.useAbility)&&command.target.id!=0){
					targetScale=state.objectById!((obj)=>getScale(obj))(command.target.id);
				}
				auto ids=selection.creatureIds[].filter!(x=>x!=command.target.id);
				auto formationOffsets=getFormationOffsets(ids,command.type,command.formation,formationScale,targetScale);
				bool success=false;
				int i=0;
				foreach(selectedId;ids){ // TODO: for retreat command, need to loop over all creatures of that side
					scope(success) i++;
					if(!selectedId) break;
					command.creature=selectedId;
					if(command.type!=CommandType.useAbility) success|=applyOrder(command,state,true,formationOffsets[i]);
					else success|=applyOrder(command,state);
				}
				return success;
			}else{
				// TODO: add command indicators to scene
				Order ord;
				ord.command=command.type;
				ord.target=OrderTarget(command.target);
				ord.targetFacing=command.targetFacing;
				ord.formationOffset=formationOffset;
				Vector3f position;
				if(ord.command==CommandType.guard && ord.target.id){
					auto targetPositionTargetFacing=state.movingObjectById!((obj)=>tuple(obj.position,obj.creatureState.facing), ()=>tuple(ord.target.position,ord.targetFacing))(ord.target.id);
					auto targetPosition=targetPositionTargetFacing[0], targetFacing=targetPositionTargetFacing[1];
					position=getTargetPosition(targetPosition,targetFacing,formationOffset,state);
				}else position=ord.getTargetPosition(state);
				return state.movingObjectById!((ref obj,ord,ability,state,side,updateFormation,formation,position){
					if(ord.command==CommandType.attack&&ord.target.type==TargetType.creature){
						// TODO: check whether they stick to creatures of a specific side
						if(state.movingObjectById!((obj,side,state)=>state.sides.getStance(side,obj.side)==Stance.enemy,()=>false)(ord.target.id,side,state)){
							auto newPosition=position;
							newPosition.z=state.getHeight(newPosition)+newPosition.z-state.getHeight(obj.position);
							auto target=state.proximity.closestEnemyInRange(side,newPosition,attackDistance,EnemyType.creature,state);
							if(target) ord.target.id=target;
						}
					}
					if(ord.command==CommandType.useAbility && obj.sacObject.ability !is ability) return false;
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

			case moveForward: this.movingObjectById!startMovingForward(command.creature,this,command.side); break;
			case moveBackward: this.movingObjectById!startMovingBackward(command.creature,this,command.side); break;
			case stopMoving: this.movingObjectById!stopMovement(command.creature,this,command.side); break;
			case turnLeft: this.movingObjectById!startTurningLeft(command.creature,this,command.side); break;
			case turnRight: this.movingObjectById!startTurningRight(command.creature,this,command.side); break;
			case stopTurning: this.movingObjectById!(.stopTurning)(command.creature,this,command.side); break;

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
			case castSpell: success=this.movingObjectById!((ref obj,spell,target,state)=>obj.startCasting(spell,target,state),function()=>false)(command.wizard,command.spell,command.target,this);
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
		this.eachMoving!updateCreature(this);
		this.eachSoul!updateSoul(this);
		this.eachBuilding!updateBuilding(this);
		this.eachWizard!updateWizard(this);
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
	void setAlpha(int id,float alpha)in{
		assert(id!=0);
	}do{
		obj.setAlpha(id,alpha);
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
		})(id,this);
	}
	void setupStructureCasting(int buildingId){
		this.buildingById!((ref bldg,state){
			foreach(cid;bldg.componentIds){
				state.setRenderMode!(StaticObject!B,RenderMode.transparent)(cid);
				state.setThresholdZ(cid,-structureCastingGradientSize);
			}
		})(buildingId,this);
	}
	Array!int toRemove;
	void removeLater(int id)in{
		assert(id!=0);
	}do{
		toRemove~=id;
	}
	void performRemovals(){
		foreach(id;toRemove.data) removeObject(id);
		toRemove.length=0;
	}
	void addWizard(WizardInfo!B wizard){
		obj.addWizard(wizard);
	}
	WizardInfo!B* getWizard(int id){
		return obj.getWizard(id);
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
	private static alias spellStatusArgs(bool selectOnly:false)=Seq!Target;
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
			if(entry.cooldown>0.0f) return SpellStatus.notReady;
			return this.movingObjectById!((obj,spell,state,spellStatusArgs!selectOnly target){
				if(spell.manaCost>obj.creatureStats.mana+manaEpsilon) return SpellStatus.lowOnMana; // TODO: store mana as exact integer?
				// if(spell.nearBuilding&&...) return SpellStatus.mustBeNearBuilding; // TODO
				// if(spell.nearEnemyAltar&&...) return SpellStatus.mustBeNearEnemyAltar; // TODO
				// if(spell.connectedToConversion&&....) return SpellStatus.mustBeConnectedToConversion; // TODO
				static if(!selectOnly){
					if(spell.requiresTarget){
						if(!spell.isApplicable(summarize(target[0],obj.side,this))) return SpellStatus.invalidTarget;
						if((obj.position-target[0].position).lengthsqr>spell.range^^2) return SpellStatus.outOfRange;
					}
				}
				return SpellStatus.ready;
			},function()=>SpellStatus.inexistent)(wizard.id,spell,this,target);
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
	void addParticle(bool relative)(Particle!(B,relative) particle){
		obj.addParticle(particle);
	}
	void addCommandCone(CommandCone!B cone){
		obj.addCommandCone(cone);
	}
	SideManager!B sid;
	void clearSelection(int side){
		sid.clearSelection(side);
	}
	void select(int side,int id){
		if(!canSelect(side,id,this)) return;
		sid.select(side,id);
	}
	void selectAll(int side,int id){
		if(!canSelect(side,id,this)) return;
		// TODO: use Proximity for this? (Not a bottleneck.)
		static void processObj(B)(MovingObject!B obj,int side,ObjectState!B state){
			struct MObj{ int id; Vector3f position; }
			alias Selection=MObj[numCreaturesInGroup];
			Selection selection;
			static void addToSelection(ref MObj[numCreaturesInGroup] selection,MObj obj,MObj nobj){
				if(selection[].map!"a.id".canFind(nobj.id)) return;
				int i=0;
				while(i<selection.length&&selection[i].id&&(selection[i].position.xy-obj.position.xy).lengthsqr<(nobj.position.xy-obj.position.xy).lengthsqr)
					i++;
				if(i>=selection.length||selection[i].id==nobj.id) return;
				foreach_reverse(j;i..selection.length-1)
					swap(selection[j],selection[j+1]);
				selection[i]=nobj;
			}
			static void process(B)(MovingObject!B nobj,int side,MObj obj,Selection* selection,ObjectState!B state){
				if(!canSelect(nobj,side,state)) return;
				if((obj.position.xy-nobj.position.xy).lengthsqr>50.0f^^2) return;
				addToSelection(*selection,obj,MObj(nobj.id,nobj.position));
			}
			state.eachMovingOf!process(obj.sacObject,side,MObj(obj.id,obj.position),&selection,state);
			if(selection[0].id!=0){
				state.clearSelection(side);
				foreach_reverse(i;0..selection.length)
					if(selection[i].id) state.sid.addToSelection(side,selection[i].id);
			}
		}
		this.movingObjectById!processObj(id,side,this);
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

auto ref objectById(alias f,B,T...)(ObjectState!B objectState,int id,T args){
	return objectState.obj.objectById!f(id,args);
}
auto ref movingObjectById(alias f,alias nonMoving=fail,B,T...)(ObjectState!B objectState,int id,T args){
	return objectState.obj.movingObjectById!(f,nonMoving)(id,args);
}
auto ref staticObjectById(alias f,alias nonStatic=fail,B,T...)(ObjectState!B objectState,int id,T args){
	return objectState.obj.staticObjectById!(f,nonStatic)(id,args);
}
auto ref soulById(alias f,alias noSoul=fail,B,T...)(ObjectState!B objectState,int id,T args){
	return objectState.obj.soulById!(f,noSoul)(id,args);
}
auto ref buildingById(alias f,alias noBuilding=fail,B,T...)(ObjectState!B objectState,int id,T args){
	return objectState.obj.buildingById!(f,noBuilding)(id,args);
}
auto ref buildingByStaticObjectId(alias f,alias noStatic=fail,B,T...)(ObjectState!B objectState,int id,T args){
	return objectState.obj.buildingByStaticObjectId!(f,noStatic)(id,args);
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

final class Sides(B){
	private Side[32] sides;
	private SacParticle!B[32] manaParticles;
	private SacParticle!B[32] shrineParticles;
	private SacParticle!B[32] manahoarParticles;
	this(Side[] sids...){
		foreach(ref side;sids){
			enforce(0<=side.id&&side.id<32);
			sides[side.id]=side;
		}
		foreach(i;0..32){
			sides[i].allies|=(1<<i); // allied to themselves
			sides[i].enemies&=~(1<<i); // not enemies of themselves
		}
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
	int[] get(){ return creatureIds[]; }
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
				auto prioritySpell=state.movingObjectById!((obj)=>tuple(obj.sacObject.creaturePriority,obj.sacObject.ability),()=>tuple(-1,SacSpell!B.init))(id);
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
	this(int numSides){
		sides.length=numSides;
	}
	void opAssign(SideManager!B rhs){
		assignArray(sides,rhs.sides);
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
TargetFlags summarize(bool simplified=false,B)(ref Target target,int side,ObjectState!B state){
	final switch(target.type) with(TargetType){
		case none,creatureTab,spellTab,structureTab,spell,ability,soulStat,manaStat,healthStat: return TargetFlags.none;
		case terrain: return TargetFlags.ground;
		case creature,building:
			static TargetFlags handle(T)(T obj,int side,ObjectState!B state){
				enum isMoving=is(T==MovingObject!B);
				static if(isMoving){
					auto result=TargetFlags.creature;
					if(obj.creatureState.mode==CreatureMode.dead) result|=TargetFlags.corpse;
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
					// TODO: shield/hero
				}
				return result;
			}
			return state.objectById!handle(target.id,side,state);
		case soul:
			auto result=TargetFlags.soul;
			auto objSide=soulSide(target.id,state);
			if(objSide==-1||objSide==side) result|=TargetFlags.owned|TargetFlags.ally; // TODO: ok? (not exactly what is going on with free souls.)
			else result|=TargetFlags.enemy;
			return result;
	}
}
Cursor cursor(B)(ref Target target,int renderSide,bool showIcon,ObjectState!B state){
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
}

bool hasClickSound(CommandType type){
	final switch(type) with(CommandType){
		case none,moveForward,moveBackward,stopMoving,turnLeft,turnRight,stopTurning,clearSelection,automaticToggleSelection,automaticSelectGroup,setFormation,retreat: return false;
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
	}
}
SoundType responseSoundType(B)(Command!B command){
	final switch(command.type) with(CommandType){
		case none,moveForward,moveBackward,stopMoving,turnLeft,turnRight,stopTurning,setFormation,clearSelection,automaticSelectAll,automaticToggleSelection,defineGroup,addToGroup,automaticSelectGroup,retreat,castSpell,useAbility:
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
void playSoundAt(B)(char[4] sound,Vector3f position,ObjectState!B state,float gain=1.0f){
	static if(B.hasAudio) if(playAudio) B.playSoundAt(sound,position,gain);
}
void playSpellSoundTypeAt(B)(SoundType soundType,Vector3f position,ObjectState!B state,float gain=1.0f){
	auto sset=SacSpell!B.sset;
	if(!sset) return;
	auto sounds=sset.getSounds(soundType);
	if(sounds.length){
		auto sound=sounds[state.uniform(cast(int)$)];
		playSoundAt(sound,position,state,gain);
	}
}
auto playSoundAt(bool getDuration=false,B,T...)(char[4] sound,int id,ObjectState!B state,float gain=1.0f){
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

bool playAudio=true;
final class GameState(B){
	ObjectState!B lastCommitted;
	ObjectState!B current;
	ObjectState!B next;
	Triggers!B triggers;
	Array!(Array!(Command!B)) commands;
	this(SacMap!B map,Side[] sids,NTTs ntts,Options options)in{
		assert(!!map);
	}body{
		auto sides=new Sides!B(sids);
		auto proximity=new Proximity!B();
		current=new ObjectState!B(map,sides,proximity);
		next=new ObjectState!B(map,sides,proximity);
		lastCommitted=new ObjectState!B(map,sides,proximity);
		triggers=new Triggers!B();
		commands.length=1;
		foreach(ref structure;ntts.structures)
			placeStructure(structure);
		foreach(ref wizard;ntts.wizards)
			placeNTT(wizard);
		foreach(ref spirit;ntts.spirits)
			placeSpirit(spirit);
		foreach(ref creature;ntts.creatures)
			foreach(k;0..options.replicateCreatures) placeNTT(creature);
		foreach(widgets;ntts.widgetss) // TODO: improve engine to be able to handle this
			placeWidgets(widgets);
		current.eachMoving!((ref MovingObject!B object, ObjectState!B state){
			if(object.creatureState.mode==CreatureMode.dead) object.createSoul(state);
		})(current);
		map.meshes=createMeshes!B(map.edges,map.heights,map.tiles,options.enableMapBottom); // TODO: allow dynamic retexturing
		map.minimapMeshes=createMinimapMeshes!B(map.edges,map.tiles);
		commit();
	}
	void placeStructure(ref Structure ntt){
		import nttData;
		auto data=ntt.tag in bldgs;
		enforce(!!data);
		auto flags=ntt.flags&~Flags.damaged&~ntt.flags.destroyed;
		auto facing=2*pi!float/360.0f*ntt.facing;
		auto buildingId=current.addObject(Building!B(data,ntt.side,flags,facing));
		assert(!!buildingId);
		if(ntt.id !in triggers.objectIds) // e.g. for some reason, the two altars on ferry have the same id
			triggers.associateId(ntt.id,buildingId);
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
				building.componentIds~=current.addObject(StaticObject!B(curObj,building.id,cposition,rotation));
			}
			if(ntt.base){
				enforce(ntt.base in triggers.objectIds);
				current.buildingById!((ref manafount,state){ putOnManafount(building,manafount,state); })(triggers.objectIds[ntt.base],current);
			}
			building.loopingSoundSetup(current);
		})(buildingId);
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
		if(ntt.id !in triggers.objectIds) // e.g. for some reason, the two altars on ferry have the same id
			triggers.associateId(ntt.id,id);
		static if(is(T==Wizard)){
			auto spellbook=getDefaultSpellbook!B(ntt.allegiance);
			current.addWizard(makeWizard(id,ntt.level,ntt.souls,move(spellbook),current));
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
	}body{
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
