import std.algorithm, std.range;
import std.container.array: Array;
import std.exception, std.stdio;
import dlib.math, std.math;
import std.typecons;
import ntts;
import sacmap, sacobject, animations;
import util;
enum int updateFPS=60;
static assert(updateFPS%animFPS==0);
enum updateAnimFactor=updateFPS/animFPS;

enum RenderMode{
	opaque,
	transparent,
}

struct Id{
	RenderMode mode;
	int type;
	int index=-1;
}

enum CreatureMode{
	idle,
	dying,
	dead,
}

enum CreatureMovement{
	onGround,
	flying,
	tumbling,
}

struct CreatureState{
	auto mode=CreatureMode.idle;
	auto movement=CreatureMovement.onGround;
}

struct MovingObject(B){
	SacObject!B sacObject;
	Vector3f position;
	Quaternionf rotation;
	AnimationState animationState;
	int frame;
	CreatureState creatureState;

	this(SacObject!B sacObject,Vector3f position,Quaternionf rotation,AnimationState animationState,int frame,CreatureState creatureState){
		this.sacObject=sacObject;
		this.position=position;
		this.rotation=rotation;
		this.animationState=animationState;
		this.frame=frame;
		this.creatureState=creatureState;
	}
}


struct StaticObject(B){
	SacObject!B sacObject;
	Vector3f position;
	Quaternionf rotation;

	this(SacObject!B sacObject,Vector3f position,Quaternionf rotation){
		this.sacObject=sacObject;
		this.position=position;
		this.rotation=rotation;
	}
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

void assignArray(T)(ref Array!T to, ref Array!T from){
	to.length=from.length;
	foreach(i;0..from.length){ // TODO: this is slow!
		static if(is(T:Array!S,S))
			assignArray(to[i],from[i]);
		else to[i]=from[i];
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
	Array!CreatureState creatureStates;
	@property int length(){ assert(ids.length<=int.max); return cast(int)ids.length; }

	void reserve(int reserveSize){
		ids.reserve(reserveSize);
		positions.reserve(reserveSize);
		rotations.reserve(reserveSize);
		animationStates.reserve(reserveSize);
		frames.reserve(reserveSize);
		creatureStates.reserve(reserveSize);
	}

	void addObject(int id,MovingObject!B object){
		ids~=id;
		positions~=object.position;
		rotations~=object.rotation;
		animationStates~=object.animationState;
		frames~=object.frame;
		creatureStates~=object.creatureState;
	}
	void opAssign(ref MovingObjects!(B,mode) rhs){
		assert(sacObject is null || sacObject is rhs.sacObject);
		sacObject = rhs.sacObject;
		assignArray(ids,rhs.ids);
		assignArray(positions,rhs.positions);
		assignArray(rotations,rhs.rotations);
		assignArray(animationStates,rhs.animationStates);
		assignArray(frames,rhs.frames);
		assignArray(creatureStates,rhs.creatureStates);
	}
	MovingObject!B opIndex(int i){
		return MovingObject!B(sacObject,positions[i],rotations[i],animationStates[i],frames[i],creatureStates[i]);
	}
	void opIndexAssign(MovingObject!B obj,int i){
		assert(obj.sacObject is sacObject);
		positions[i]=obj.position;
		rotations[i]=obj.rotation;
		animationStates[i]=obj.animationState;
		frames[i]=obj.frame;
		creatureStates[i]=obj.creatureState;
	}
}
auto each(alias f,B,RenderMode mode,T...)(ref MovingObjects!(B,mode) movingObjects,T args){
	foreach(i;0..movingObjects.length){
		static if(!is(typeof(f(movingObjects[i],args)))){
			// TODO: find a better way to check whether argument taken by reference
			auto obj=movingObjects[i];
			f(obj,args);
			movingObjects[i]=obj;
		}else f(movingObjects[i],args);
	}
}


struct StaticObjects(B){
	enum renderMode=RenderMode.opaque;
	SacObject!B sacObject;
	Array!int ids;
	Array!Vector3f positions;
	Array!Quaternionf rotations;

	@property int length(){ assert(ids.length<=int.max); return cast(int)ids.length; }
	void addObject(int id,StaticObject!B object){
		ids~=id;
		positions~=object.position;
		rotations~=object.rotation;
	}
	void opAssign(ref StaticObjects!B rhs){
		assert(sacObject is null || sacObject is rhs.sacObject);
		sacObject=rhs.sacObject;
		assignArray(ids,rhs.ids);
		assignArray(positions,rhs.positions);
		assignArray(rotations,rhs.rotations);
	}
	StaticObject!B opIndex(int i){
		return StaticObject!B(sacObject,positions[i],rotations[i]);
	}
	void opIndexAssign(StaticObject!B obj,int i){
		positions[i]=obj.position;
		rotations[i]=obj.rotation;
	}
}
auto each(alias f,B,T...)(ref StaticObjects!B staticObjects,T args){
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
	void opAssign(ref FixedObjects!B rhs){
		assert(sacObject is null || sacObject is rhs.sacObject);
		sacObject=rhs.sacObject;
		assignArray(positions,rhs.positions);
		assignArray(rotations,rhs.rotations);
	}
	FixedObject!B opIndex(int i){
		return FixedObject!B(sacObject,positions[i],rotations[i]);
	}
	void opIndexAssign(StaticObject!B obj,int i){
		positions[i]=obj.position;
		rotations[i]=obj.rotation;
	}
}
auto each(alias f,B,T...)(ref FixedObjects!B fixedObjects,T args){
	foreach(i;0..length)
		f(fixedObjects[i],args);
}


struct Objects(B,RenderMode mode){
	Array!(MovingObjects!(B,mode)) movingObjects;
	static if(mode == RenderMode.opaque){
		Array!(StaticObjects!B) staticObjects;
		FixedObjects!B[] fixedObjects;
	}
	static if(mode==RenderMode.opaque){
		Id addObject(T)(int id,T object) if(is(T==MovingObject!B)||is(T==StaticObject!B)){
			Id result;
			auto type=object.sacObject.stateIndex; // TODO: support RenderMode.transparent
			if(type==-1){
				static if(is(T==MovingObject!B)){
					type=object.sacObject.stateIndex=cast(int)movingObjects.length;
					movingObjects.length=movingObjects.length+1;
					movingObjects[$-1].sacObject=object.sacObject;
				}else{
					type=object.sacObject.stateIndex=cast(int)staticObjects.length+numMoving;
					staticObjects.length=staticObjects.length+1;
					staticObjects[$-1].sacObject=object.sacObject;
				}
			}
			static if(is(T==MovingObject!B)){
				enforce(type<numMoving);
				result=Id(mode,type,movingObjects[type].length);
				movingObjects[type].addObject(id,object);
			}else{
				enforce(numMoving<=type && type<numMoving+numStatic);
				result=Id(mode,type,staticObjects[type-numMoving].length);
				staticObjects[type-numMoving].addObject(id,object);
			}
			return result;
		}
		void addFixed(FixedObject!B object){
			auto type=object.sacObject.stateIndex;
			if(type==-1){
				type=object.sacObject.stateIndex=cast(int)fixedObjects.length+numMoving+numStatic;
				fixedObjects.length=fixedObjects.length+1;
				fixedObjects[$-1].sacObject=object.sacObject;
			}
			enforce(numMoving+numStatic<=type);
			fixedObjects[type-(numMoving+numStatic)].addFixed(object);
		}
	}
	void opAssign(Objects!(B,mode) rhs){
		assignArray(movingObjects,rhs.movingObjects);
		static if(mode == RenderMode.opaque){
			assignArray(staticObjects,rhs.staticObjects);
			fixedObjects=rhs.fixedObjects; // by reference
		}
	}
}
auto each(alias f,B,RenderMode mode,T...)(ref Objects!(B,mode) objects,T args){
	with(objects){
		foreach(ref movingObject;movingObjects)
			movingObject.each!f(args);
		static if(mode == RenderMode.opaque){
			foreach(ref staticObject;staticObjects)
				staticObject.each!f(args);
			foreach(ref fixedObject;fixedObjects)
				fixedObject.each!f(args);
		}
	}
}
auto eachMoving(alias f,B,RenderMode mode,T...)(ref Objects!(B,mode) objects,T args){
	with(objects){
		foreach(ref movingObject;movingObjects)
			movingObject.each!f(args);
	}
}

auto eachByType(alias f,B,RenderMode mode,T...)(ref Objects!(B,mode) objects,T args){
	with(objects){
		foreach(ref movingObject;movingObjects)
			f(movingObject,args);
		static if(mode == RenderMode.opaque){
			foreach(ref staticObject;staticObjects)
				f(staticObject,args);
			foreach(ref fixedObject;fixedObjects)
				f(fixedObject,args);
		}
	}
}

enum numMoving=100;
enum numStatic=300;

struct ObjectManager(B){
	Array!Id ids;
	Objects!(B,RenderMode.opaque) opaqueObjects;
	Objects!(B,RenderMode.transparent) transparentObjects;
	int addObject(T)(T object) if(is(T==MovingObject!B)||is(T==StaticObject!B)){
		if(ids.length>=int.max) return 0;
		int id=cast(int)ids.length+1;
		ids~=opaqueObjects.addObject(id,object);
		return id;
	}
	void addTransparent(T)(T object, float alpha){
		assert(0,"TODO");
	}
	void addFixed(FixedObject!B object){
		opaqueObjects.addFixed(object);
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
auto eachByType(alias f,B,T...)(ref ObjectManager!B objectManager,T args){
	with(objectManager){
		opaqueObjects.eachByType!f(args);
		transparentObjects.eachByType!f(args);
	}
}

void setInitialAnimation(B)(ref MovingObject!B object,ObjectState!B state){
	auto sacObject=object.sacObject;
	object.animationState=AnimationState.stance1; // TODO: check health, maybe put stance2
	object.frame=0;
	final switch(object.creatureState.mode){
		case CreatureMode.idle:
			object.animationState=AnimationState.stance1; // TODO: check health, maybe put stance2
			if(object.creatureState.movement==CreatureMovement.flying){
				assert(sacObject.canFly);
				if(!sacObject.mustFly)
					object.animationState=AnimationState.hover;
			}
			if(!state.uniform(5)){ // TODO: figure out the original rule for this
				with(AnimationState) if(sacObject.mustFly){
					static immutable candidates0=[hover,idle0,idle1,idle2,idle3]; // TODO: probably idleness animations depend on health
					object.pickRandomAnimation(candidates0,state);
				}else if(object.creatureState.movement!=CreatureMovement.flying){
					static immutable candidates1=[idle0,idle1,idle2,idle3]; // TODO: probably idleness animations depend on health
					object.pickRandomAnimation(candidates1,state);
				}
			}
			break;
		case CreatureMode.dying:
			final switch(object.creatureState.movement) with(CreatureMovement) with(AnimationState){
				case onGround:
					assert(!object.sacObject.mustFly);
					static immutable candidates2=[death0,death1,death2];
					object.pickRandomAnimation(candidates2,state);
					break;
				case flying:
					if(object.sacObject.mustFly){
						static immutable candidates3=[flyDeath,death0,death1,death2];
						object.pickRandomAnimation(candidates3,state);
					}else object.animationState=flyDeath;
					break;
				case tumbling:
					object.animationState=falling;
					break;
			}
			break;
		case CreatureMode.dead:
			object.animationState=AnimationState.death0;
			if(sacObject.mustFly)
				object.animationState=AnimationState.hitFloor;
			object.frame=sacObject.numFrames(object.animationState)*updateAnimFactor-1;
			break;
	}
}

void pickRandomAnimation(B)(ref MovingObject!B object,immutable(AnimationState)[] candidates,ObjectState!B state){
	auto filtered=candidates.filter!(x=>object.sacObject.hasAnimationState(x));
	object.animationState=filtered.drop(state.uniform(cast(int)filtered.walkLength)).front;
}

void kill(B)(ref MovingObject!B object, ObjectState!B state){
	with(CreatureMode) if(object.creatureState.mode.among(dying,dead)) return;
	object.creatureState.mode=CreatureMode.dying;
	object.setInitialAnimation(state);
}

void immediateResurrect(B)(ref MovingObject!B object,ObjectState!B state){
	with(CreatureMode) if(!object.creatureState.mode.among(dying,dead)) return;
	object.creatureState.mode=CreatureMode.idle;
	object.setInitialAnimation(state);
}


import std.random: MinstdRand0;
final class ObjectState(B){ // (update logic)
	int frame=0;
	auto rng=MinstdRand0(1); // TODO: figure out what rng to use
	int uniform(int n){
		import std.random: uniform;
		return uniform(0,n,rng);
	}
	void copyFrom(ObjectState!B rhs){
		frame=rhs.frame;
		rng=rhs.rng;
		obj=rhs.obj;
	}
	void updateFrom(ObjectState!B rhs,Command[] frameCommands){
		copyFrom(rhs);
		update();
	}

	static void updateCreature(ref MovingObject!B object, ObjectState!B state){
		auto sacObject=object.sacObject;
		final switch(object.creatureState.mode){
			case CreatureMode.idle:
				object.frame+=1;
				if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor){
					object.frame=0;
					object.setInitialAnimation(state);
				}
				break;
			case CreatureMode.dying:
				with(AnimationState) assert(object.animationState.among(flyDeath,death0,death1,death2,falling));
				object.frame+=1;
				if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor){
					final switch(object.creatureState.movement){
						object.frame=0;
						case CreatureMovement.onGround:
							object.frame=sacObject.numFrames(object.animationState)*updateAnimFactor-1;
							object.creatureState.mode=CreatureMode.dead;
							break;
						case CreatureMovement.flying:
							object.creatureState.movement=CreatureMovement.tumbling;
							object.animationState=AnimationState.falling;
							break;
						case CreatureMovement.tumbling:
							// TODO: add falling down
							object.creatureState.movement=CreatureMovement.onGround;
							object.animationState=AnimationState.hitFloor;
							break;
					}
				}
				break;
			case CreatureMode.dead:
				with(AnimationState) assert(object.animationState.among(hitFloor,death0,death1,death2));
				assert(object.frame==sacObject.numFrames(object.animationState)*updateAnimFactor-1);
				break;
		}
	}
	void update(){
		frame+=1;
		this.eachMoving!updateCreature(this);
	}
	ObjectManager!B obj;
	int addObject(T)(T object) if(is(T==MovingObject!B)||is(T==StaticObject!B)){
		return obj.addObject(object);
	}
	void addFixed(FixedObject!B object){
		obj.addFixed(object);
	}
}
auto each(alias f,B,T...)(ObjectState!B objectState,T args){
	return objectState.obj.each!f(args);
}
auto eachMoving(alias f,B,T...)(ObjectState!B objectState,T args){
	return objectState.obj.eachMoving!f(args);
}
auto eachByType(alias f,B,T...)(ObjectState!B objectState,T args){
	return objectState.obj.eachByType!f(args);
}

enum TargetType{
	floor,
	creature,
	structure,
}

struct Target{
	TargetType type;
	int targetId;

}

enum CommandType{
	moveForward,
	moveBack,
	turnLeft,
	turnRight,
}

struct Command{
	CommandType type;
	int creature;
	Target target;
}

final class GameState(B){
	SacMap!B map;
	bool isOnGround(Vector3f position){
		return map.isOnGround(position);
	}
	float getGroundHeight(Vector3f position){
		return map.getGroundHeight(position);
	}
	Vector2f sunSkyRelLoc(Vector3f cameraPos){
		return map.sunSkyRelLoc(cameraPos);
	}
	ObjectState!B lastCommitted;
	ObjectState!B current;
	ObjectState!B next;
	Array!(Array!Command) commands;
	this(SacMap!B map,NTTs ntts)in{
		assert(!!map);
	}body{
		this.map=map;
		current=new ObjectState!B;
		next=new ObjectState!B;
		lastCommitted=new ObjectState!B;
		commands.length=1;
		foreach(ref structure;ntts.structures)
			placeStructure(structure);
		foreach(ref wizard;ntts.wizards)
			placeNTT(wizard);
		foreach(ref creature;ntts.creatures)
			placeNTT(creature);
		foreach(widgets;ntts.widgetss) // TODO: improve engine to be able to handle this
			placeWidgets(widgets);
		map.meshes=createMeshes!B(map.edges,map.heights,map.tiles); // TODO: allow dynamic retexuring
		commit();
	}
	void placeStructure(ref Structure ntt){
		import nttData;
		auto data=ntt.tag in bldgs;
		enforce(!!data);
		auto position=Vector3f(ntt.x,ntt.y,ntt.z);
		auto ci=cast(int)(position.x/10+0.5);
		auto cj=cast(int)(position.y/10+0.5);
		import bldg;
		if(data.flags&BldgFlags.ground){
			auto ground=data.ground;
			auto n=map.n,m=map.m;
			foreach(j;max(0,cj-4)..min(n,cj+4)){
				foreach(i;max(0,ci-4)..min(m,ci+4)){
					auto dj=j-(cj-4), di=i-(ci-4);
					if(ground[dj][di])
						map.tiles[j][i]=ground[dj][di];
				}
			}
		}
		foreach(ref component;data.components){
			auto curObj=SacObject!B.getBLDG(component.tag);
			auto offset=Vector3f(component.x,component.y,component.z);
			offset=rotate(facingQuaternion(ntt.facing), offset);
			auto cposition=position+offset;
			if(!isOnGround(cposition)) continue;
			cposition.z=getGroundHeight(cposition);
			auto rotation=facingQuaternion(ntt.facing+component.facing);
			current.addObject(StaticObject!B(curObj,cposition,rotation));
		}
	}

	void placeNTT(T)(ref T ntt) if(is(T==Creature)||is(T==Wizard)){
		auto curObj=SacObject!B.getSAXS!T(ntt.tag);
		auto position=Vector3f(ntt.x,ntt.y,ntt.z);
		bool onGround=isOnGround(position);
		if(onGround)
			position.z=getGroundHeight(position);
		auto rotation=facingQuaternion(ntt.facing);
		auto mode=ntt.flags & Flags.corpse ? CreatureMode.dead : CreatureMode.idle;
		auto movement=curObj.mustFly?CreatureMovement.flying:CreatureMovement.onGround;
		if(movement==CreatureMovement.onGround && !onGround)
			movement=curObj.canFly?CreatureMovement.flying:CreatureMovement.tumbling;
		if(curObj.canFly) movement=CreatureMovement.flying;
		auto creatureState=CreatureState(mode, movement);
		auto obj=MovingObject!B(curObj,position,rotation,AnimationState.stance1,0,creatureState);
		obj.setInitialAnimation(current);
		/+do{
			import std.random: uniform;
			state=cast(AnimationState)uniform(0,64);
		}while(!curObj.hasAnimationState(state));+/
		current.addObject(obj);
	}
	void placeWidgets(Widgets w){
		auto curObj=SacObject!B.getWIDG(w.tag);
		foreach(pos;w.positions){
			auto position=Vector3f(pos[0],pos[1],0);
			if(!isOnGround(position)) continue;
			position.z=getGroundHeight(position);
			// original engine screws up widget rotations
			// values look like angles in degrees, but they are actually radians
			auto rotation=rotationQuaternion(Axis.z,cast(float)(-pos[2]));
			current.addFixed(FixedObject!B(curObj,position,rotation));
		}
	}

	void step(){
		next.updateFrom(current,commands[current.frame].data);
		swap(current,next);
		if(commands.length<=current.frame) commands~=Array!Command();
	}
	void commit(){
		lastCommitted.copyFrom(current);
	}
	void rollback(int frame)in{
		assert(frame>=lastCommitted.frame);
	}body{
		if(frame!=current.frame) current.copyFrom(lastCommitted);
	}
	void simulateTo(int frame)in{
		assert(frame>=current.frame);
	}body{
		while(current.frame<frame)
			step();
	}
	void addCommand(int frame,Command command)in{
		assert(frame<=current.frame);
	}body{
		assert(frame<commands.length);
		auto currentFrame=current.frame;
		commands[frame]~=command;
		rollback(frame);
		simulateTo(currentFrame);
	}
}

State makeState(B)(int reserveSize){
	return new State!B(reserveSize);
}

