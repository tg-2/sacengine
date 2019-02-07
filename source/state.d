import std.algorithm, std.range;
import std.container.array: Array;
import std.exception, std.stdio, std.conv, std.math;
import dlib.math, dlib.image.color;
import std.typecons;
import sids, ntts, nttData, bldg;
import sacmap, sacobject, animations;
import stats;
import util,options;
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
	moving,
	dying,
	dead,
	reviving,
	takeoff,
	landing,
	meleeMoving,
	meleeAttacking,
	stunned,
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

enum RotationDirection{
	none,
	left,
	right,
}

struct CreatureState{
	auto mode=CreatureMode.idle;
	auto movement=CreatureMovement.onGround;
	float facing=0.0f, flyingDisplacement=0.0f;
	auto movementDirection=MovementDirection.none;
	auto rotationDirection=RotationDirection.none;
	auto fallingVelocity=Vector3f(0.0f,0.0f,0.0f);
}

struct MovingObject(B){
	SacObject!B sacObject;
	int id=0;
	Vector3f position;
	Quaternionf rotation;
	AnimationState animationState;
	int frame;
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
	this(SacObject!B sacObject,int id,Vector3f position,Quaternionf rotation,AnimationState animationState,int frame,CreatureState creatureState,CreatureStats creatureStats,int side,int soulId){
		this.soulId=soulId;
		this(sacObject,id,position,rotation,animationState,frame,creatureState,creatureStats,side);
	}
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

Vector3f center(B)(ref MovingObject!B object){
	auto hbox=object.hitbox;
	return 0.5f*(hbox[0]+hbox[1]);
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

int numAttackTicks(B)(ref MovingObject!B object,AnimationState animationState){
	return object.sacObject.numAttackTicks(animationState);
}

bool hasAttackTick(B)(ref MovingObject!B object){
	return object.frame%updateAnimFactor==0 && object.sacObject.hasAttackTick(object.animationState,object.frame/updateAnimFactor);
}

StunBehavior stunBehavior(B)(ref MovingObject!B object){
	return object.sacObject.stunBehavior;
}

StunnedBehavior stunnedBehavior(B)(ref MovingObject!B object){
	return object.sacObject.stunnedBehavior;
}

bool isRegenerating(B)(ref MovingObject!B object){
	return object.creatureState.mode==CreatureMode.idle||object.sacObject.continuousRegeneration;
}

bool isDamaged(B)(ref MovingObject!B object){
	return object.creatureStats.health<=0.25f*object.creatureStats.maxHealth;
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
	this(int creatureId,int number,Vector3f position,SoulState state){
		this.creatureId=creatureId;
		this(number,position,state);
	}
	this(int id,int creatureId,int number,Vector3f position,SoulState state){
		this.id=id;
		this(creatureId,number,position,state);
	}
}

enum BuildingFlags{
	none=0,
}

struct Building(B){
	immutable(Bldg)* bldg; // TODO: replace by SacBuilding class
	int id=0;
	int side;
	Array!int componentIds;
	int flags=0;
	int top=0;
	int base=0;
	float health=0.0f;
	enum regeneration=80.0f;
	enum meleeResistance=1.5f;
	enum directSpellResistance=1.0f;
	enum splashSpellResistance=1.0f;
	enum directRangedResistance=1.0f;
	enum splashRangedResistance=1.0f;
	this(immutable(Bldg)* bldg,int side,int flags){
		this.bldg=bldg;
		this.side=side;
		this.flags=flags;
		this.health=bldg.maxHealth;
	}
	void opAssign(ref Building!B rhs){
		this.bldg=rhs.bldg;
		this.id=rhs.id;
		this.side=rhs.side;
		assignArray(componentIds,rhs.componentIds);
		health=rhs.health;
		flags=rhs.flags;
		top=rhs.top;
		base=rhs.base;
	}
}
int maxHealth(B)(ref Building!B building,ObjectState!B state){
	return building.bldg.maxHealth;
}
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
void putOnManafount(B)(ref Building!B building,ref Building!B manafount,ObjectState!B state)in{
	assert(manafount.isManafount);
	assert(manafount.top==0 && building.base==0);
}do{
	manafount.top=building.id;
	building.base=manafount.id;
}
void freeManafount(B)(ref Building!B manafount,ObjectState!B state)in{
	assert(manafount.isManafount);
	assert(manafount.top!=0);
}do{
	state.buildingById!((ref obj){ assert(obj.base==manafount.id); obj.base=0; })(manafount.top);
	manafount.top=0;
}


struct Particle(B){
	SacParticle!B sacParticle;
	Vector3f position;
	Vector3f velocity;
	int lifetime;
	int frame;
	this(SacParticle!B sacParticle,Vector3f position,Vector3f velocity,int lifetime,int frame){
		this.sacParticle=sacParticle;
		this.position=position;
		this.velocity=velocity;
		this.lifetime=lifetime;
		this.frame=frame;
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
	Array!CreatureStats creatureStatss;
	Array!int sides;
	Array!int soulIds;
	@property int length(){ assert(ids.length<=int.max); return cast(int)ids.length; }
	@property void length(int l){
		ids.length=l;
		positions.length=l;
		rotations.length=l;
		animationStates.length=l;
		frames.length=l;
		creatureStates.length=l;
		creatureStatss.length=l;
		sides.length=l;
		soulIds.length=l;
	}

	void reserve(int reserveSize){
		ids.reserve(reserveSize);
		positions.reserve(reserveSize);
		rotations.reserve(reserveSize);
		animationStates.reserve(reserveSize);
		frames.reserve(reserveSize);
		creatureStates.reserve(reserveSize);
		creatureStatss.reserve(reserveSize);
		sides.reserve(reserveSize);
		soulIds.reserve(reserveSize);
	}

	void addObject(MovingObject!B object)in{
		assert(object.id!=0);
	}do{
		ids~=object.id;
		positions~=object.position;
		rotations~=object.rotation;
		animationStates~=object.animationState;
		frames~=object.frame;
		creatureStates~=object.creatureState;
		creatureStatss~=object.creatureStats;
		sides~=object.side;
		soulIds~=object.soulId;
	}
	void removeObject(int index, ObjectManager!B manager){
		manager.ids[ids[index]-1]=Id.init;
		if(length>1){
			this[index]=this[length-1];
			manager.ids[ids[index]-1].index=index;
		}
		length=length-1;
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
		assignArray(creatureStatss,rhs.creatureStatss);
		assignArray(sides,rhs.sides);
		assignArray(soulIds,rhs.soulIds);
	}
	MovingObject!B opIndex(int i){
		return MovingObject!B(sacObject,ids[i],positions[i],rotations[i],animationStates[i],frames[i],creatureStates[i],creatureStatss[i],sides[i],soulIds[i]);
	}
	void opIndexAssign(MovingObject!B obj,int i){
		assert(obj.sacObject is sacObject);
		assert(ids[i]==obj.id);
		positions[i]=obj.position;
		rotations[i]=obj.rotation;
		animationStates[i]=obj.animationState;
		frames[i]=obj.frame;
		creatureStates[i]=obj.creatureState;
		creatureStatss[i]=obj.creatureStats; // TODO: this might be a bit wasteful
		sides[i]=obj.side;
		soulIds[i]=obj.soulId;
	}
}
auto each(alias f,B,RenderMode mode,T...)(ref MovingObjects!(B,mode) movingObjects,T args){
	foreach(i;0..movingObjects.length){
		static if(!is(typeof(f(MovingObject.init,args)))){
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
	Array!int buildingIds;
	Array!Vector3f positions;
	Array!Quaternionf rotations;

	@property int length(){ assert(ids.length<=int.max); return cast(int)ids.length; }
	@property void length(int l){
		ids.length=l;
		buildingIds.length=l;
		positions.length=l;
		rotations.length=l;
	}
	void addObject(StaticObject!B object)in{
		assert(object.id!=0);
	}do{
		ids~=object.id;
		buildingIds~=object.buildingId;
		positions~=object.position;
		rotations~=object.rotation;
	}
	void removeObject(int index, ObjectManager!B manager){
		manager.ids[ids[index]-1]=Id.init;
		if(length>1){
			this[index]=this[length-1];
			manager.ids[ids[index]-1].index=index;
		}
		length=length-1;
	}
	void opAssign(ref StaticObjects!B rhs){
		assert(sacObject is null || sacObject is rhs.sacObject);
		sacObject=rhs.sacObject;
		assignArray(ids,rhs.ids);
		assignArray(buildingIds,rhs.buildingIds);
		assignArray(positions,rhs.positions);
		assignArray(rotations,rhs.rotations);
	}
	StaticObject!B opIndex(int i){
		return StaticObject!B(sacObject,ids[i],buildingIds[i],positions[i],rotations[i]);
	}
	void opIndexAssign(StaticObject!B obj,int i){
		assert(sacObject is obj.sacObject);
		ids[i]=obj.id;
		buildingIds[i]=obj.buildingId;
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

struct Souls(B){
	Array!(Soul!B) souls;
	@property int length(){ return cast(int)souls.length; }
	@property void length(int l){ souls.length=l; }
	void addObject(Soul!B soul){
		souls~=soul;
	}
	void removeObject(int index, ObjectManager!B manager){
		manager.ids[souls[index].id-1]=Id.init;
		if(length>1){
			this[index]=this[length-1];
			manager.ids[souls[index].id-1].index=index;
		}
		length=length-1;
	}
	void opAssign(ref Souls!B rhs){
		assignArray(souls,rhs.souls);
	}
	Soul!B opIndex(int i){
		return souls[i];
	}
	void opIndexAssign(Soul!B soul,int i){
		souls[i]=soul;
	}
}
auto each(alias f,B,T...)(ref Souls!B souls,T args){
	foreach(i;0..souls.length){
		static if(!is(typeof(f(Soul.init,args)))){
			// TODO: find a better way to check whether argument taken by reference
			auto soul=souls[i];
			f(soul,args);
			souls[i]=soul;
		}else f(souls[i],args);
	}
}

struct Buildings(B){
	Array!(Building!B) buildings;
	@property int length(){ return cast(int)buildings.length; }
	@property void length(int l){ buildings.length=l; }
	void addObject(Building!B building){
		buildings~=building;
	}
	void removeObject(int index, ObjectManager!B manager){
		manager.ids[buildings[index].id-1]=Id.init;
		if(length>1){
			this[index]=this[length-1];
			manager.ids[buildings[index].id-1].index=index;
		}
		length=length-1;
	}
	void opAssign(ref Buildings!B rhs){
		buildings.length=rhs.buildings.length;
		foreach(i;0..buildings.length)
			buildings[i]=rhs.buildings[i];
	}
	Building!B opIndex(int i){
		return buildings[i];
	}
	void opIndexAssign(Building!B building,int i){
		buildings[i]=building;
	}
}
auto each(alias f,B,T...)(ref Buildings!B buildings,T args){
	foreach(i;0..buildings.length){
		static if(!is(typeof(f(Soul.init,args)))){
			// TODO: find a better way to check whether argument taken by reference
			auto soul=buildings[i];
			f(soul,args);
			buildings[i]=soul;
		}else f(buildings[i],args);
	}
}

struct Particles(B){
	SacParticle!B sacParticle;
	Array!Vector3f positions;
	Array!Vector3f velocities;
	Array!int lifetimes;
	Array!int frames;
	@property int length(){ assert(positions.length<=int.max); return cast(int)positions.length; }
	@property void length(int l){
		positions.length=l;
		velocities.length=l;
		lifetimes.length=l;
		frames.length=l;
	}
	void reserve(int reserveSize){
		positions.reserve(reserveSize);
		velocities.reserve(reserveSize);
		lifetimes.reserve(reserveSize);
		frames.reserve(reserveSize);
	}
	void addParticle(Particle!B particle){
		assert(sacParticle is null || sacParticle is particle.sacParticle);
		sacParticle=particle.sacParticle; // TODO: get rid of this?
		positions~=particle.position;
		velocities~=particle.velocity;
		lifetimes~=particle.lifetime;
		frames~=particle.frame;
	}
	void removeParticle(int index){
		if(length>1) this[index]=this[length-1];
		length=length-1;
	}
	void opAssign(ref Particles!B rhs){
		assert(sacParticle is null || sacParticle is rhs.sacParticle);
		sacParticle = rhs.sacParticle;
		assignArray(positions,rhs.positions);
		assignArray(velocities,rhs.velocities);
		assignArray(lifetimes,rhs.lifetimes);
		assignArray(frames,rhs.frames);
	}
	Particle!B opIndex(int i){
		return Particle!B(sacParticle,positions[i],velocities[i],lifetimes[i],frames[i]);
	}
	void opIndexAssign(Particle!B particle,int i){
		assert(particle.sacParticle is sacParticle);
		positions[i]=particle.position;
		velocities[i]=particle.velocity;
		lifetimes[i]=particle.lifetime;
		frames[i]=particle.frame;
	}
}

struct Objects(B,RenderMode mode){
	Array!(MovingObjects!(B,mode)) movingObjects;
	static if(mode == RenderMode.opaque){
		Array!(StaticObjects!B) staticObjects;
		FixedObjects!B[] fixedObjects;
		Souls!B souls;
		Buildings!B buildings;
		Array!(Particles!B) particles;
	}
	static if(mode==RenderMode.opaque){
		Id addObject(T)(T object) if(is(T==MovingObject!B)||is(T==StaticObject!B))in{
			assert(object.id!=0);
		}do{
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
				movingObjects[type].addObject(object);
			}else{
				enforce(numMoving<=type && type<numMoving+numStatic);
				result=Id(mode,type,staticObjects[type-numMoving].length);
				staticObjects[type-numMoving].addObject(object);
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
		Id addObject(Soul!B object){
			auto result=Id(mode,ObjectType.soul,souls.length);
			souls.addObject(object);
			return result;
		}
		Id addObject(Building!B object){
			auto result=Id(mode,ObjectType.building,buildings.length);
			buildings.addObject(object);
			return result;
		}
		void addParticle(Particle!B particle){
			auto type=particle.sacParticle.stateIndex;
			if(type==-1){
				type=particle.sacParticle.stateIndex=cast(int)particles.length;
				particles.length=particles.length+1;
				particles[$-1].sacParticle=particle.sacParticle;
			}
			particles[type].addParticle(particle);
		}
		void removeObject(int type, int index, ref ObjectManager!B manager){
			if(type<numMoving){
				movingObjects[type].removeObject(index,manager);
			}else if(type<numMoving+numStatic){
				staticObjects[type-numMoving].removeObject(index,manager);
			}else final switch(cast(ObjectType)type){
				case ObjectType.soul: souls.removeObject(index,manager); break;
				case ObjectType.building: buildings.removeObject(index,manager); break;
			}
		}
	}
	void opAssign(Objects!(B,mode) rhs){
		assignArray(movingObjects,rhs.movingObjects);
		static if(mode == RenderMode.opaque){
			assignArray(staticObjects,rhs.staticObjects);
			fixedObjects=rhs.fixedObjects; // by reference
			souls=rhs.souls;
			buildings=rhs.buildings;
			assignArray(particles,rhs.particles);
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
			souls.each!f(args);
		}
	}
}
auto eachMoving(alias f,B,RenderMode mode,T...)(ref Objects!(B,mode) objects,T args){
	with(objects){
		foreach(ref movingObject;movingObjects)
			movingObject.each!f(args);
	}
}
auto eachSoul(alias f,B,T...)(ref Objects!(B,RenderMode.opaque) objects,T args){
	objects.souls.each!f(args);
}
auto eachBuilding(alias f,B,T...)(ref Objects!(B,RenderMode.opaque) objects,T args){
	objects.buildings.each!f(args);
}
auto eachParticles(alias f,B,T...)(ref Objects!(B,RenderMode.opaque) objects,T args){
	with(objects){
		foreach(ref particle;particles)
			f(particle,args);
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
			f(souls,args);
			f(buildings,args);
			foreach(ref particle;particles)
				f(particle,args);
		}
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
		object.id=cast(int)ids.length+1;
		ids~=opaqueObjects.addObject(object);
		return object.id;
	}
	void removeObject(int id)in{
		assert(0<id && id<=ids.length);
	}do{
		auto tid=ids[id-1];
		if(tid==Id.init) return; // already deleted
		final switch(tid.mode){
			case RenderMode.opaque: opaqueObjects.removeObject(tid.type,tid.index,this); break;
			case RenderMode.transparent: assert(0,"TODO");//transparentObjects.removeObject(tid.type,tid.index);
		}
	}
	void addTransparent(T)(T object, float alpha){
		assert(0,"TODO");
	}
	void addFixed(FixedObject!B object){
		opaqueObjects.addFixed(object);
	}
	void addParticle(Particle!B particle){
		opaqueObjects.addParticle(particle);
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
auto eachSoul(alias f,B,T...)(ref ObjectManager!B objectManager,T args){
	with(objectManager) opaqueObjects.eachSoul!f(args);
}
auto eachBuilding(alias f,B,T...)(ref ObjectManager!B objectManager,T args){
	with(objectManager) opaqueObjects.eachBuilding!f(args);
}
auto eachParticles(alias f,B,T...)(ref ObjectManager!B objectManager,T args){
	with(objectManager) opaqueObjects.eachParticles!f(args);
}
auto eachByType(alias f,B,T...)(ref ObjectManager!B objectManager,T args){
	with(objectManager){
		opaqueObjects.eachByType!f(args);
		transparentObjects.eachByType!f(args);
	}
}
auto ref objectById(alias f,B,T...)(ref ObjectManager!B objectManager,int id,T args)in{
	assert(id>0);
}do{
	auto nid=objectManager.ids[id-1];
	if(nid.type<numMoving){
		enum byRef=!is(typeof(f(MovingObject!B.init,args))); // TODO: find a better way to check whether argument taken by reference!
		final switch(nid.mode){
			case RenderMode.opaque:
				static if(byRef){
					auto obj=objectManager.opaqueObjects.movingObjects[nid.type][nid.index];
					scope(success) objectManager.opaqueObjects.movingObjects[nid.type][nid.index]=obj;
					return f(obj,args);
				}else return f(objectManager.opaqueObjects.movingObjects[nid.type][nid.index],args);
			case RenderMode.transparent:
				static if(byRef){
					auto obj=objectManager.transparentObjects.movingObjects[nid.type][nid.index];
					scope(success) objectManager.transparentObjects.movingObjects[nid.type][nid.index]=obj;
					return f(obj,args);
				}else return f(objectManager.transparentObjects.movingObjects[nid.type][nid.index],args);
		}
	}else{
		enum byRef=!is(typeof(f(StaticObject!B.init,args))); // TODO: find a better way to check whether argument taken by reference!
		assert(nid.mode==RenderMode.opaque);
		assert(nid.type<numMoving+numStatic);
		static if(byRef){
			auto obj=objectManager.opaqueObjects.staticObjects[nid.type-numMoving][nid.index];
			scope(success) objectManager.opaqueObjects.staticObjects[nid.type-numMoving][nid.index]=obj;
			return f(obj,args);
		}else return f(objectManager.opaqueObjects.staticObjects[nid.type-numMoving][nid.index],args);
	}
}
auto ref movingObjectById(alias f,alias nonMoving=(){assert(0);},B,T...)(ref ObjectManager!B objectManager,int id,T args)in{
	assert(id>0);
}do{
	auto nid=objectManager.ids[id-1];
	enum byRef=!is(typeof(f(MovingObject!B.init,args))); // TODO: find a better way to check whether argument taken by reference!
	if(nid.type<numMoving){
		final switch(nid.mode){ // TODO: get rid of code duplication
			case RenderMode.opaque:
				static if(byRef){
					auto obj=objectManager.opaqueObjects.movingObjects[nid.type][nid.index];
					scope(success) objectManager.opaqueObjects.movingObjects[nid.type][nid.index]=obj;
					return f(obj,args);
				}else return f(objectManager.opaqueObjects.movingObjects[nid.type][nid.index],args);
			case RenderMode.transparent:
				static if(byRef){
					auto obj=objectManager.transparentObjects.movingObjects[nid.type][nid.index];
					scope(success) objectManager.transparentObjects.movingObjects[nid.type][nid.index]=obj;
					return f(obj,args);
				}else return f(objectManager.transparentObjects.movingObjects[nid.type][nid.index],args);
		}
	}else return nonMoving();
}
auto ref staticObjectById(alias f,alias nonStatic=(){assert(0);},B,T...)(ref ObjectManager!B objectManager,int id,T args)in{
	assert(id>0);
}do{
	auto nid=objectManager.ids[id-1];
	enum byRef=!is(typeof(f(StaticObject!B.init,args))); // TODO: find a better way to check whether argument taken by reference!
	if(nid.type<numMoving) return nonStatic();
	else if(nid.type<numMoving+numStatic){
		assert(nid.mode==RenderMode.opaque);
		assert(nid.type<numMoving+numStatic);
		static if(byRef){
			auto obj=objectManager.opaqueObjects.staticObjects[nid.type-numMoving][nid.index];
			scope(success) objectManager.opaqueObjects.staticObjects[nid.type-numMoving][nid.index]=obj;
			return f(obj,args);
		}else return f(objectManager.opaqueObjects.staticObjects[nid.type-numMoving][nid.index],args);
	}else return nonStatic();
}
auto ref soulById(alias f,alias noSoul=(){assert(0);},B,T...)(ref ObjectManager!B objectManager,int id,T args)in{
	assert(id>0);
}do{
	auto nid=objectManager.ids[id-1];
	if(nid.type!=ObjectType.soul) return noSoul();
	enum byRef=!is(typeof(f(Soul!B.init,args))); // TODO: find a better way to check whether argument taken by reference!
	static if(byRef){
		auto soul=objectManager.opaqueObjects.souls[nid.index];
		scope(success) objectManager.opaqueObjects.souls[nid.index]=soul;
		return f(soul,args);
	}else return f(objectManager.opaqueObjects.souls[nid.index],args);
}
auto ref buildingById(alias f,alias noBuilding=(){assert(0);},B,T...)(ref ObjectManager!B objectManager,int id,T args)in{
	assert(id>0);
}do{
	auto nid=objectManager.ids[id-1];
	if(nid.type!=ObjectType.building) return noBuilding();
	enum byRef=!is(typeof(f(Building!B.init,args))); // TODO: find a better way to check whether argument taken by reference!
	static if(byRef){
		auto building=objectManager.opaqueObjects.buildings[nid.index];
		scope(success) objectManager.opaqueObjects.buildings[nid.index]=building;
		return f(building,args);
	}else return f(objectManager.opaqueObjects.buildings[nid.index],args);
}
auto ref buildingByStaticObjectId(alias f,alias nonStatic=(){assert(0);},B,T...)(ref ObjectManager!B objectManager,int id,T args)in{
	assert(id>0);
}do{
	auto nid=objectManager.ids[id-1];
	enum byRef=!is(typeof(f(StaticObject!B.init,args))); // TODO: find a better way to check whether argument taken by reference!
	if(nid.type<numMoving) return nonStatic();
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
		case CreatureMode.idle:
			bool isDamaged=object.isDamaged;
			if(object.creatureState.movement!=CreatureMovement.flying) object.frame=0;
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
					if(!sacObject.mustFly && (object.frame==0||object.animationState==AnimationState.fly&&object.sacObject.seamlessFlyAndHover))
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
			break;
		case CreatureMode.moving:
			final switch(object.creatureState.movement) with(CreatureMovement){
				case onGround:
					if(!object.sacObject.canRun){
						if(object.sacObject.canFly) object.startFlying(state);
						else object.startIdling(state);
						return;
					}
					object.frame=0;
					object.animationState=AnimationState.run;
					break;
				case flying:
					if(object.frame==0||object.animationState==AnimationState.hover&&object.sacObject.seamlessFlyAndHover)
						object.animationState=AnimationState.fly;
					break;
				case tumbling:
					object.creatureState.mode=CreatureMode.stunned;
					break;
			}
			if(object.creatureState.mode==CreatureMode.stunned)
				goto case CreatureMode.stunned;
			break;
		case CreatureMode.dying:
			object.frame=0;
			final switch(object.creatureState.movement) with(CreatureMovement) with(AnimationState){
				case onGround:
					assert(!object.sacObject.mustFly);
					static immutable deathCandidatesOnGround=[death0,death1,death2];
					object.pickRandomAnimation(deathCandidatesOnGround,state);
					break;
				case flying:
					if(object.sacObject.mustFly){
						static immutable deathCandidatesFlying=[flyDeath,death0,death1,death2];
						object.pickRandomAnimation(deathCandidatesFlying,state);
					}else object.animationState=flyDeath;
					break;
				case tumbling:
					object.animationState=object.sacObject.hasFalling?falling:object.sacObject.canTumble?tumble:stance1;
					break;
			}
			break;
		case CreatureMode.dead:
			object.animationState=AnimationState.death0;
			if(sacObject.mustFly)
				object.animationState=AnimationState.hitFloor;
			object.frame=sacObject.numFrames(object.animationState)*updateAnimFactor-1;
			break;
		case CreatureMode.reviving:
			assert(object.frame==sacObject.numFrames(object.animationState)*updateAnimFactor-1);
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
					if(!object.sacObject.hasAnimationState(AnimationState.land)){
						object.creatureState.mode=CreatureMode.idle;
						goto case CreatureMode.idle;
					}
					object.animationState=AnimationState.land;
				}else object.animationState=AnimationState.hover;
			}
			break;
		case CreatureMode.meleeMoving,CreatureMode.meleeAttacking:
			final switch(object.creatureState.movement) with(CreatureMovement) with(AnimationState){
				case onGround:
					object.frame=0;
					static immutable attackCandidatesOnGround=[attack0,attack1,attack2];
					object.pickRandomAnimation(attackCandidatesOnGround,state);
					break;
				case flying:
					if(object.sacObject.mustFly)
						goto case onGround; // (bug in original engine: it fails to do this.)
					object.frame=0;
					object.animationState=flyAttack;
					break;
				case tumbling:
					assert(0);
			}
			break;
		case CreatureMode.stunned:
			object.frame=0;
			final switch(object.creatureState.movement){
				case CreatureMovement.onGround:
					object.animationState=object.sacObject.hasKnockdown?AnimationState.knocked2Floor
						:object.sacObject.hasGetUp?AnimationState.getUp:AnimationState.stance1;
					break;
				case CreatureMovement.flying:
					assert(sacObject.canFly);
					object.animationState=object.sacObject.hasFlyDamage?AnimationState.flyDamage:AnimationState.hover;
					break;
				case CreatureMovement.tumbling:
					object.animationState=object.sacObject.canTumble?AnimationState.tumble:AnimationState.stance1;
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

void startIdling(B)(ref MovingObject!B object, ObjectState!B state){
	if(!object.creatureState.mode.among(CreatureMode.moving,CreatureMode.reviving,CreatureMode.takeoff,CreatureMode.landing,CreatureMode.meleeMoving,CreatureMode.meleeAttacking,CreatureMode.stunned))
		return;
	object.creatureState.mode=CreatureMode.idle;
	object.setCreatureState(state);
}

void kill(B)(ref MovingObject!B object, ObjectState!B state){
	with(CreatureMode) if(object.creatureState.mode.among(dying,dead,reviving)) return;
	if(!object.sacObject.canDie()) return;
	object.creatureStats.health=0.0f;
	object.creatureState.mode=CreatureMode.dying;
	object.setCreatureState(state);
}

void destroy(B)(ref Building!B building, ObjectState!B state){
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
	object.soulId=state.addObject(Soul!B(object.id,object.sacObject.numSouls,object.soulPosition,SoulState.emerging));
}

void createSoul(B)(ref MovingObject!B object, ObjectState!B state){
	with(CreatureMode) if(object.creatureState.mode!=CreatureMode.dead||object.soulId!=0) return;
	int numSouls=object.sacObject.numSouls;
	if(!numSouls) return;
	object.soulId=state.addObject(Soul!B(object.id,object.sacObject.numSouls,object.soulPosition,SoulState.normal));
}

void stun(B)(ref MovingObject!B object, ObjectState!B state){
	with(CreatureMode) if(!object.creatureState.mode.among(idle,moving,takeoff,landing,meleeMoving,meleeAttacking)) return;
	object.creatureState.mode=CreatureMode.stunned;
	object.setCreatureState(state);
}
void damageStun(B)(ref MovingObject!B object, Vector3f attackDirection, ObjectState!B state){
	with(CreatureMode) if(!object.creatureState.mode.among(idle,moving,takeoff,landing,meleeMoving,meleeAttacking)) return;
	object.creatureState.mode=CreatureMode.stunned;
	object.setCreatureState(state);
	object.damageAnimation(attackDirection,state,false);
}

void catapult(B)(ref MovingObject!B object, Vector3f velocity, ObjectState!B state){
	with(CreatureMode) if(object.creatureState.mode==dead) return;
	if(object.creatureState.movement==CreatureMovement.flying) return;
	if(object.creatureState.mode!=CreatureMode.dying)
		object.creatureState.mode=CreatureMode.stunned;
	// TODO: in original engine, stunned creatures don't switch to the tumbling animation
	// TODO: in original engine, dying creatures don't switch to the tumbling animation
	object.creatureState.movement=CreatureMovement.tumbling;
	object.creatureState.fallingVelocity=velocity;
	object.setCreatureState(state);
}

void immediateRevive(B)(ref MovingObject!B object,ObjectState!B state){
	with(CreatureMode) if(!object.creatureState.mode.among(dying,dead)) return;
	if(object.soulId!=0){
		state.removeObject(object.soulId);
		object.soulId=0;
	}
	object.creatureStats.health=object.creatureStats.maxHealth;
	object.creatureState.mode=CreatureMode.idle;
	object.setCreatureState(state);
}

void revive(B)(ref MovingObject!B object,ObjectState!B state){
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
	object.creatureStats.health=object.creatureStats.maxHealth;
	object.creatureState.mode=CreatureMode.reviving;
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

void startMeleeAttacking(B)(ref MovingObject!B object,ObjectState!B state){
	with(CreatureMode) with(CreatureMovement)
		if(!object.creatureState.mode.among(idle,moving)||
		   !object.creatureState.movement.among(onGround,flying)||
		   !object.sacObject.canAttack)
			return;
	object.creatureState.mode=CreatureMode.meleeMoving;
	object.setCreatureState(state);
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

void dealDamage(B)(ref MovingObject!B object,float damage,ref MovingObject!B attacker,ObjectState!B state){
	object.creatureStats.health-=damage;
	// TODO: give xp to attacker
	if(object.creatureStats.health<=0)
		object.kill(state);
	attacker.heal(damage*attacker.creatureStats.drain,state);
}

void dealDamage(B)(ref Building!B building,float damage,ref MovingObject!B attacker,ObjectState!B state){
	if(building.maxHealth(state)==0.0f) return;
	building.health-=damage;
	// TODO: give xp to attacker
	if(building.health<=0)
		building.destroy(state);
}

void heal(B)(ref MovingObject!B object,float amount,ObjectState!B state){
	object.creatureStats.health=min(object.creatureStats.health+amount,object.creatureStats.maxHealth);
}
void heal(B)(ref Building!B building,float amount,ObjectState!B state){
	building.health=min(building.health+amount,building.maxHealth(state));
}

void dealMeleeDamage(B)(ref MovingObject!B object,ref MovingObject!B attacker,ObjectState!B state){
	auto damage=state.uniform(0.8f*attacker.meleeStrength,1.2f*attacker.meleeStrength)/attacker.numAttackTicks(attacker.animationState); // TODO: figure this out
	auto actualDamage=damage*object.creatureStats.meleeResistance;
	auto attackDirection=object.center-attacker.center; // TODO: good?
	auto stunBehavior=attacker.stunBehavior;
	auto direction=getDamageDirection(object,attackDirection,state);
	bool fromBehind=direction==DamageDirection.back;
	bool fromSide=!!direction.among(DamageDirection.left,DamageDirection.right);
	if(fromBehind) actualDamage*=2.0f;
	else if(fromSide) actualDamage*=1.5f;
	object.dealDamage(actualDamage,attacker,state);
	if(stunBehavior==StunBehavior.always || fromBehind && stunBehavior==StunBehavior.fromBehind){
		object.damageStun(attackDirection,state);
		return;
	}
	object.damageAnimation(attackDirection,state);
	final switch(object.stunnedBehavior){
		case StunnedBehavior.normal:
			break;
		case StunnedBehavior.onMeleeDamage,StunnedBehavior.onDamage:
			object.damageStun(attackDirection,state);
			break;
	}
}

void dealMeleeDamage(B)(ref Building!B building,ref MovingObject!B attacker,ObjectState!B state){
	auto damage=attacker.meleeStrength;
	auto actualDamage=damage*building.meleeResistance*attacker.sacObject.buildingMeleeDamageMultiplier/attacker.numAttackTicks(attacker.animationState);
	building.dealDamage(actualDamage,attacker,state);
}


void setMovement(B)(ref MovingObject!B object,MovementDirection direction,ObjectState!B state){
	// TODO: also check for conditions that immobilze a creature, such as vines or spell casting
	with(CreatureMode)
		if(!object.creatureState.mode.among(idle,moving,meleeMoving))
			return;
	if(object.creatureState.movement==CreatureMovement.flying &&
	   direction==MovementDirection.backward &&
	   !object.sacObject.canFlyBackward)
		return;
	if(object.creatureState.movementDirection==direction)
		return;
	object.creatureState.movementDirection=direction;
	if(object.creatureState.mode!=CreatureMode.meleeMoving)
		object.setCreatureState(state);
}
void stopMovement(B)(ref MovingObject!B object,ObjectState!B state){
	object.setMovement(MovementDirection.none,state);
}
void startMovingForward(B)(ref MovingObject!B object,ObjectState!B state){
	object.setMovement(MovementDirection.forward,state);
}
void startMovingBackward(B)(ref MovingObject!B object,ObjectState!B state){
	object.setMovement(MovementDirection.backward,state);
}

void setTurning(B)(ref MovingObject!B object,RotationDirection direction,ObjectState!B state){
	with(CreatureMode)
		if(!object.creatureState.mode.among(idle,moving,meleeMoving))
			return;
	// TODO: also check for conditions that immobilze a creature, such as vines or spell casting
	object.creatureState.rotationDirection=direction;
}
void stopTurning(B)(ref MovingObject!B object,ObjectState!B state){
	object.setTurning(RotationDirection.none,state);
}
void startTurningLeft(B)(ref MovingObject!B object,ObjectState!B state){
	object.setTurning(RotationDirection.left,state);
}
void startTurningRight(B)(ref MovingObject!B object,ObjectState!B state){
	object.setTurning(RotationDirection.right,state);
}

void updateCreatureState(B)(ref MovingObject!B object, ObjectState!B state){
	auto sacObject=object.sacObject;
	final switch(object.creatureState.mode){
		case CreatureMode.idle, CreatureMode.moving:
			object.frame+=1;
			auto oldMode=object.creatureState.mode;
			object.creatureState.mode=object.creatureState.movementDirection==MovementDirection.none?CreatureMode.idle:CreatureMode.moving;
			if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor){
				object.frame=0;
				object.setCreatureState(state);
			}else if(object.creatureState.mode!=oldMode){
				object.setCreatureState(state);
			}
			break;
		case CreatureMode.dying:
			with(AnimationState) assert(object.animationState.among(death0,death1,death2,flyDeath,falling,tumble,hitFloor),text(object.sacObject.tag," ",object.animationState));
			if(object.creatureState.movement==CreatureMovement.tumbling){
				if(state.isOnGround(object.position)){
					if(object.creatureState.fallingVelocity.z<=0.0f&&object.position.z<=state.getGroundHeight(object.position)){
						object.creatureState.movement=CreatureMovement.onGround;
						object.frame=0;
						if(object.sacObject.canFly) object.animationState=AnimationState.hitFloor;
						else object.setCreatureState(state);
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
						object.creatureState.mode=CreatureMode.dead;
						object.spawnSoul(state);
						break;
					case CreatureMovement.flying:
						object.creatureState.movement=CreatureMovement.tumbling;
						object.creatureState.fallingVelocity=Vector3f(0.0f,0.0f,0.0f);
						object.setCreatureState(state);
						break;
					case CreatureMovement.tumbling:
						// continue tumbling
						break;
				}
			}
			break;
		case CreatureMode.dead:
			with(AnimationState) assert(object.animationState.among(hitFloor,death0,death1,death2));
			assert(object.frame==sacObject.numFrames(object.animationState)*updateAnimFactor-1);
			break;
		case CreatureMode.reviving:
			// TODO: figure out how the revive sequence works in detail
			static immutable reviveSequence=[AnimationState.corpse,AnimationState.float_];
			if(object.soulId){
				if(state.soulById!((Soul!B s)=>s.scaling==0.0f,()=>false)(object.soulId)){
					state.removeLater(object.soulId);
					object.soulId=0;
					object.frame=0;
					object.animationState=AnimationState.corpse;
					if(!object.sacObject.hasAnimationState(AnimationState.corpse)){
						if(!object.pickNextAnimation(reviveSequence,state))
						   object.startIdling(state);
					}
				}
			}else{
				object.frame+=1;
				if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor){
					object.frame=0;
					if(!object.pickNextAnimation(reviveSequence,state))
						object.startIdling(state);
				}
			}
			break;
		case CreatureMode.takeoff:
			assert(object.sacObject.canFly);
			assert(object.creatureState.movement==CreatureMovement.onGround);
			object.frame+=1;
			if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor){
				object.frame=0;
				if(object.animationState==AnimationState.takeoff){
					object.creatureState.mode=object.sacObject.movingAfterTakeoff?CreatureMode.moving:CreatureMode.idle;
					object.creatureState.movement=CreatureMovement.flying;
				}
				object.setCreatureState(state);
			}
			break;
		case CreatureMode.landing:
			assert(object.sacObject.canFly&&!object.sacObject.mustFly);
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
			with(AnimationState) assert(object.animationState.among(stance1,knocked2Floor,tumble,hitFloor,getUp,damageFront,damageRight,damageBack,damageLeft,damageTop,flyDamage));
			if(object.creatureState.movement==CreatureMovement.tumbling&&object.creatureState.fallingVelocity.z<=0.0f){
				if(object.sacObject.canFly){
					object.creatureState.movement=CreatureMovement.flying;
					object.frame=0;
					object.animationState=AnimationState.hover;
					object.startIdling(state);
					break;
				}else if(state.isOnGround(object.position)&&object.position.z<=state.getGroundHeight(object.position)){
					object.creatureState.movement=CreatureMovement.onGround;
					if(object.sacObject.hasHitFloor){
						object.frame=0;
						object.animationState=AnimationState.hitFloor;
					}else object.startIdling(state);
					break;
				}
			}
			object.frame+=1;
			if(object.frame>=sacObject.numFrames(object.animationState)*updateAnimFactor){
				object.frame=0;
				final switch(object.creatureState.movement){
					case CreatureMovement.onGround:
						if(object.animationState.among(AnimationState.knocked2Floor,AnimationState.hitFloor)&&object.sacObject.hasGetUp){
							object.animationState=AnimationState.getUp;
						}else object.startIdling(state);
						break;
					case CreatureMovement.flying:
						object.startIdling(state);
						break;
					case CreatureMovement.tumbling:
						// continue tumbling
						break;
				}
			}
			break;
	}
}

void updateCreatureStats(B)(ref MovingObject!B object, ObjectState!B state){
	if(object.isRegenerating)
		object.heal(object.creatureStats.regeneration/updateFPS,state);
	if(object.creatureState.mode.among(CreatureMode.meleeMoving,CreatureMode.meleeAttacking) && object.hasAttackTick){
		object.creatureState.mode=CreatureMode.meleeAttacking;
		struct CollisionState{
			Vector3f[2] hitbox;
			int ownId;
			int target=0;
			float distance=float.infinity;
		}
		static void handleCollision(ProximityEntry entry,CollisionState *collisionState,ObjectState!B state){
			if(entry.id==collisionState.ownId) return;
			if(state.buildingByStaticObjectId!((ref Building!B building,ObjectState!B state)=>building.maxHealth(state)==0,()=>false)(entry.id,state))
				return;
			if(!collisionState.target){
				collisionState.target=entry.id;
				return;
			}
			auto center=0.5f*(entry.hitbox[0]+entry.hitbox[1]);
			auto attackCenter=0.5f*(collisionState.hitbox[0]+collisionState.hitbox[1]);
			auto distance=(center-attackCenter).length; // TODO: improve this calculation
			if(distance<collisionState.distance){
				collisionState.target=entry.id;
				collisionState.distance=distance;
			}
		}
		auto hitbox=object.hitbox,meleeHitbox=object.meleeHitbox;
		auto collisionState=CollisionState(hitbox,object.id);
		state.proximity.collide!handleCollision(meleeHitbox,&collisionState,state);
		if(collisionState.target){
			static void dealDamage(T)(ref T target,MovingObject!B* attacker,ObjectState!B state){
				static if(is(T==MovingObject!B)){
					target.dealMeleeDamage(*attacker,state);
				}else static if(is(T==StaticObject!B)){
					assert(target.buildingId);
					state.buildingById!((ref Building!B building,MovingObject!B* attacker,ObjectState!B state){
						building.dealMeleeDamage(*attacker,state);
					})(target.buildingId,attacker,state);
				}
			}
			state.objectById!dealDamage(collisionState.target,&object,state);
		}
	}
}

void updateCreaturePosition(B)(ref MovingObject!B object, ObjectState!B state){
	auto newPosition=object.position;
	if(object.creatureState.mode.among(CreatureMode.idle,CreatureMode.moving,CreatureMode.landing,CreatureMode.dying,CreatureMode.meleeMoving)){
		auto rotationSpeed=object.creatureStats.rotationSpeed/updateFPS;
		bool isRotating=false;
		if(object.creatureState.mode.among(CreatureMode.idle,CreatureMode.moving,CreatureMode.meleeMoving)&&
		   object.creatureState.movement!=CreatureMovement.tumbling
		){
			final switch(object.creatureState.rotationDirection){
				case RotationDirection.none:
					break;
				case RotationDirection.left:
					isRotating=true;
					object.creatureState.facing+=rotationSpeed;
					break;
				case RotationDirection.right:
					isRotating=true;
					object.creatureState.facing-=rotationSpeed;
				break;
			}
		}
		auto facing=facingQuaternion(object.creatureState.facing);
		auto newRotation=facing;
		if(object.creatureState.movement==CreatureMovement.onGround||
		   object.animationState==AnimationState.land
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
		}
		if(isRotating||object.creatureState.mode!=CreatureMode.idle||
		   object.creatureState.movement==CreatureMovement.flying){
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
			if(!object.creatureState.mode.among(CreatureMode.moving,CreatureMode.meleeMoving)) break;
			void applyMovementOnGround(Vector3f direction){
				auto speed=object.creatureStats.movementSpeed(false)/updateFPS;
				auto derivative=state.getGroundHeightDerivative(object.position,direction);
				Vector3f newDirection=direction;
				if(derivative>0.0f){
					newDirection=Vector3f(direction.x,direction.y,derivative).normalized;
				}else if(derivative<0.0f){
					newDirection=Vector3f(direction.x,direction.y,derivative);
					auto maxFactor=object.creatureStats.maxDownwardSpeedFactor;
					if(newDirection.lengthsqr>maxFactor*maxFactor) newDirection=maxFactor*newDirection.normalized;
				}
				newPosition=state.moveOnGround(object.position,speed*newDirection);
			}
			final switch(object.creatureState.movementDirection){
				case MovementDirection.none:
					break;
				case MovementDirection.forward:
					applyMovementOnGround(rotate(facingQuaternion(object.creatureState.facing), Vector3f(0.0f,1.0f,0.0f)));
					break;
				case MovementDirection.backward:
					applyMovementOnGround(rotate(facingQuaternion(object.creatureState.facing), Vector3f(0.0f,-1.0f,0.0f)));
					break;
			}
			break;
		case CreatureMovement.flying:
			if(object.creatureState.mode==CreatureMode.landing ||
			   object.creatureState.mode==CreatureMode.idle&&object.animationState!=AnimationState.fly&&object.creatureState.flyingDisplacement>0.0f
			){
				auto downwardSpeed=object.creatureState.mode==CreatureMode.landing?object.creatureStats.landingSpeed/updateFPS:object.creatureStats.downwardHoverSpeed/updateFPS;
				newPosition.z-=downwardSpeed;
				object.creatureState.flyingDisplacement=max(0.0f,object.creatureState.flyingDisplacement-downwardSpeed);
				if(state.isOnGround(object.position)){
					auto height=state.getGroundHeight(newPosition);
					if(newPosition.z<=height)
						newPosition.z=height;
					object.creatureState.flyingDisplacement=min(object.creatureState.flyingDisplacement,newPosition.z-height);
				}
				break;
			}
			if(!object.creatureState.mode.among(CreatureMode.moving,CreatureMode.meleeMoving)) break;
			void applyMovementInAir(Vector3f direction){
				auto speed=object.creatureStats.movementSpeed(true)/updateFPS;
				newPosition=object.position+speed*direction;
				auto upwardSpeed=max(0.0f,min(object.creatureStats.takeoffSpeed/updateFPS,object.creatureStats.flyingHeight-object.creatureState.flyingDisplacement));
				auto onGround=state.isOnGround(newPosition), newHeight=float.nan;
				if(onGround){
					newHeight=state.getGroundHeight(newPosition);
					if(newHeight>newPosition.z)
						upwardSpeed+=newHeight-newPosition.z;
				}
				auto upwardFactor=object.creatureStats.upwardFlyingSpeedFactor;
				auto downwardFactor=object.creatureStats.downwardFlyingSpeedFactor;
				auto newDirection=Vector3f(direction.x,direction.y,direction.z+upwardSpeed).normalized;
				speed*=sqrt(newDirection.x^^2+newDirection.y^^2+(newDirection.z*(newDirection.z>0?upwardFactor:downwardFactor))^^2);
				auto velocity=speed*newDirection;
				newPosition=object.position+velocity;
				object.creatureState.flyingDisplacement+=velocity.z;
				if(onGround){
					// TODO: improve? original engine does this, but it can cause ultrafast ascending for flying creatures
					newPosition.z=max(newPosition.z,newHeight);
					object.creatureState.flyingDisplacement=max(0.0f,min(object.creatureState.flyingDisplacement,newPosition.z-newHeight));
				}
			}
			final switch(object.creatureState.movementDirection){
				case MovementDirection.none:
					break;
				case MovementDirection.forward:
					applyMovementInAir(rotate(object.rotation,Vector3f(0.0f,1.0f,0.0f)));
					break;
				case MovementDirection.backward:
					assert(object.sacObject.canFlyBackward);
					applyMovementInAir(rotate(object.rotation,Vector3f(0.0f,-1.0f,0.0f)));
					break;
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
	bool posChanged=false, needsFixup=false;
	auto fixupDirection=Vector3f(0.0f,0.0f,0.0f);
	void handleCollision(bool fixup)(ProximityEntry entry){
		if(entry.id==object.id) return;
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
		if(cand<minOverlap){
			minOverlap=cand;
			collisionDirection=CollisionDirection.right;
		}
		cand=hitbox[1].y-entry.hitbox[0].y;
		if(cand<minOverlap){
			minOverlap=cand;
			collisionDirection=CollisionDirection.back;
		}
		cand=entry.hitbox[1].y-hitbox[0].y;
		if(cand<minOverlap){
			minOverlap=cand;
			collisionDirection=CollisionDirection.front;
		}
		final switch(object.creatureState.movement){
			case CreatureMovement.onGround:
				break;
			case CreatureMovement.flying:
				if(object.creatureState.mode==CreatureMode.landing) break;
				cand=hitbox[1].z-entry.hitbox[0].z;
				if(cand<minOverlap){
					minOverlap=cand;
					collisionDirection=CollisionDirection.bottom;
				}
				cand=entry.hitbox[1].z-hitbox[0].z;
				if(cand<minOverlap){
					minOverlap=cand;
					collisionDirection=CollisionDirection.top;
				}
				break;
			case CreatureMovement.tumbling:
				static if(!fixup){
					cand=entry.hitbox[1].z-hitbox[0].z;
					if(cand<minOverlap)
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
	if(object.creatureState.mode==CreatureMode.dead) return; // dead creatures do not participate in collision handling
	proximity.collide!(handleCollision!false)(hitbox);
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
	object.updateCreatureState(state);
	object.updateCreaturePosition(state);
	object.updateCreatureStats(state);
}

void updateSoul(B)(ref Soul!B soul, ObjectState!B state){
	soul.frame+=1;
	soul.facing+=2*PI/8.0f/updateFPS;
	if(soul.frame==SacSoul!B.numFrames*updateAnimFactor)
		soul.frame=0;
	if(soul.creatureId)
		soul.position=state.movingObjectById!(soulPosition,()=>Vector3f(float.nan,float.nan,float.nan))(soul.creatureId);
	final switch(soul.state){
		case SoulState.normal:
			// TODO: add soul collecting
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
			soul.scaling-=1.0f/updateFPS;
			if(soul.scaling<=0.0f){
				soul.scaling=0.0f;
				// TODO: delete the soul
			}
			break;
		case SoulState.collecting:
			assert(soul.collectorId!=0);
			soul.scaling-=1.0f/updateFPS;
			if(soul.scaling<=0.0f){
				soul.scaling=0.0f;
				// TODO: delete the soul
				// TODO: increase collector's soul count
			}
			break;
	}
}

void updateParticles(B)(ref Particles!B particles, ObjectState!B state){
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
}

void animateManafount(B)(Vector3f location, ObjectState!B state){
	auto sacParticle=SacParticle!B.get(ParticleType.manafount);
	auto globalAngle=1.5f*2*PI/updateFPS*(state.frame+1000*location.x+location.y);
	auto globalMagnitude=0.25f;
	auto globalDisplacement=globalMagnitude*Vector3f(cos(globalAngle),sin(globalAngle),0.0f);
	auto center=location+globalDisplacement;
	static assert(updateFPS==60); // TODO: fix
	foreach(j;0..2){
		auto displacementAngle=state.uniform(-PI,PI);
		auto displacementMagnitude=state.uniform(0.0f,0.5f);
		auto displacement=displacementMagnitude*Vector3f(cos(displacementAngle),sin(displacementAngle),0.0f);
		foreach(k;0..2){
			auto position=center+displacement;
			auto angle=state.uniform(-PI,PI);
			auto velocity=(20.0f+state.uniform(-5.0f,5.0f))*Vector3f(cos(angle),sin(angle),state.uniform(2.0f,4.0f)).normalized;
			auto lifetime=cast(int)(sqrt(sacParticle.numFrames*5.0f)*state.uniform(0.0f,1.0f))^^2;
			auto frame=0;
			state.addParticle(Particle!B(sacParticle,position,velocity,lifetime,frame));
		}
	}
}

void animateManalith(B)(Vector3f location, int side, ObjectState!B state){
	auto sacParticle=state.sides.manaParticle(side);
	auto globalAngle=2*PI/updateFPS*(state.frame+1000*location.x+location.y);
	auto globalMagnitude=0.5f;
	auto globalDisplacement=globalMagnitude*Vector3f(cos(globalAngle),sin(globalAngle),0.0f);
	auto center=location+globalDisplacement;
	static assert(updateFPS==60); // TODO: fix
	foreach(j;0..4){
		auto displacementAngle=state.uniform(-PI,PI);
		auto displacementMagnitude=3.5f*state.uniform(0.0f,1.0f)^^2;
		auto displacement=displacementMagnitude*Vector3f(cos(displacementAngle),sin(displacementAngle),0.0f);
		auto position=center+displacement;
		auto angle=state.uniform(-PI,PI);
		auto velocity=(15.0f+state.uniform(-5.0f,5.0f))*Vector3f(0.0f,0.0f,state.uniform(2.0f,4.0f)).normalized;
		auto lifetime=cast(int)(sacParticle.numFrames*5.0f-0.7*sacParticle.numFrames*displacement.length*state.uniform(0.0f,1.0f)^^2);
		auto frame=0;
		state.addParticle(Particle!B(sacParticle,position,velocity,lifetime,frame));
	}
}

void animateShrine(B)(Vector3f location, int side, ObjectState!B state){
	auto sacParticle=state.sides.shrineParticle(side);
	auto globalAngle=2*PI/updateFPS*(state.frame+1000*location.x+location.y);
	auto globalMagnitude=0.1f;
	auto globalDisplacement=globalMagnitude*Vector3f(cos(globalAngle),sin(globalAngle),0.0f);
	auto center=location+globalDisplacement;
	static assert(updateFPS==60); // TODO: fix
	foreach(j;0..2){
		auto displacementAngle=state.uniform(-PI,PI);
		auto displacementMagnitude=1.0f*state.uniform(0.0f,1.0f)^^2;
		auto displacement=displacementMagnitude*Vector3f(cos(displacementAngle),sin(displacementAngle),0.0f);
		auto position=center+displacement;
		auto angle=state.uniform(-PI,PI);
		auto velocity=(1.5f+state.uniform(-0.5f,0.5f))*Vector3f(0.0f,0.0f,state.uniform(2.0f,4.0f)).normalized;
		auto lifetime=cast(int)((sacParticle.numFrames*5.0f)*(1.0f+state.uniform(0.0f,1.0f)^^10));
		auto frame=0;
		state.addParticle(Particle!B(sacParticle,position,velocity,lifetime,frame));
	}
}

void updateBuilding(B)(ref Building!B building, ObjectState!B state){
	if(building.componentIds.length==0) return;
	building.heal(building.regeneration/updateFPS,state);
	if(building.isManafount && building.top==0){
		Vector3f getManafountTop(StaticObject!B obj){
			auto hitbox=obj.sacObject.hitboxes(obj.rotation)[0];
			auto center=0.5f*(hitbox[0]+hitbox[1]);
			return obj.position+center+Vector3f(0.0f,0.0f,0.75f);
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
		animateShrine(position,building.side,state);
	}
}

void addToProximity(T,B)(ref T objects, ObjectState!B state){
	auto proximity=state.proximity;
	enum isMoving=is(T==MovingObjects!(B, RenderMode.opaque))||is(T==MovingObjects!(B, RenderMode.transparent));
	static if(isMoving){
		foreach(j;0..objects.length){
			if(objects.creatureStates[j].mode==CreatureMode.dead) continue; // dead creatures are not obstacles (bad cache locality)
			auto hitbox=objects.sacObject.hitbox(objects.rotations[j],objects.animationStates[j],objects.frames[j]/updateAnimFactor);
			auto position=objects.positions[j];
			hitbox[0]+=position;
			hitbox[1]+=position;
			proximity.insert(ProximityEntry(objects.ids[j],hitbox));
		}
	}else static if(is(T==StaticObjects!B)){ // TODO: cache those?
		foreach(j;0..objects.length){
			foreach(hitbox;objects.sacObject.hitboxes(objects.rotations[j])){
				auto position=objects.positions[j];
				hitbox[0]+=position;
				hitbox[1]+=position;
				proximity.insert(ProximityEntry(objects.ids[j],hitbox));
			}
		}
	}else static if(is(T==Souls!B)||is(T==Buildings!B)||is(T==Particles!B)){
		// do nothing
	}else static assert(is(T==FixedObjects!B));
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
final class Proximity(B){
	int version_=0;
	bool active=false;
	enum resolution=10;
	enum offMapSlack=100/resolution;
	enum size=(2560+resolution-1)/resolution+2*offMapSlack;
	static Tuple!(int,"j",int,"i") getTile(Vector3f position){
		return tuple!("j","i")(cast(int)(position.y/resolution),cast(int)(position.x/resolution)); // TODO: good resolution?
	}
	ProximityEntries[size][size] data;
	ProximityEntries offMap;
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
	void insert(ProximityEntry entry)in{
		assert(active);
	}do{
		auto lowTile=getTile(entry.hitbox[0]), highTile=getTile(entry.hitbox[1]);
		if(lowTile.j+offMapSlack<0||lowTile.i+offMapSlack<0||highTile.j+offMapSlack>=size||highTile.i+offMapSlack>=size)
			offMap.insert(version_,entry);
		foreach(j;max(0,lowTile.j+offMapSlack)..min(highTile.j+offMapSlack+1,size))
			foreach(i;max(0,lowTile.i+offMapSlack)..min(highTile.i+offMapSlack+1,size))
				data[j][i].insert(version_,entry);
	}
}
auto collide(alias f,B,T...)(Proximity!B proximity,Vector3f[2] hitbox,T args){
	auto lowTile=proximity.getTile(hitbox[0]), highTile=proximity.getTile(hitbox[1]);
	if(lowTile.j+Proximity!B.offMapSlack<0||lowTile.i+Proximity!B.offMapSlack<0||highTile.j+Proximity!B.offMapSlack>=Proximity!B.size||highTile.i+Proximity!B.offMapSlack>=Proximity!B.size)
		proximity.offMap.collide!f(proximity.version_,hitbox,args);
	foreach(j;max(0,lowTile.j+Proximity!B.offMapSlack)..min(highTile.j+Proximity!B.offMapSlack+1,Proximity!B.size))
		foreach(i;max(0,lowTile.i+Proximity!B.offMapSlack)..min(highTile.i+Proximity!B.offMapSlack+1,Proximity!B.size))
			proximity.data[j][i].collide!f(proximity.version_,hitbox,args);
}

import std.random: MinstdRand0;
final class ObjectState(B){ // (update logic)
	SacMap!B map;
	Sides!B sides;
	Proximity!B proximity;
	this(SacMap!B map, Sides!B sides, Proximity!B proximity){
		this.map=map;
		this.sides=sides;
		this.proximity=proximity;
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
	float getGroundHeightDerivative(Vector3f position,Vector3f direction){
		return map.getGroundHeightDerivative(position,direction);
	}
	Vector2f sunSkyRelLoc(Vector3f cameraPos){
		return map.sunSkyRelLoc(cameraPos);
	}
	int frame=0;
	auto rng=MinstdRand0(1); // TODO: figure out what rng to use
	int uniform(int n){
		import std.random: uniform;
		return uniform(0,n,rng);
	}
	float uniform(string bounds="[]",T)(T a,T b){
		import std.random: uniform;
		return uniform!bounds(a,b,rng);
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
	void update(){
		frame+=1;
		proximity.start();
		this.eachByType!addToProximity(this);
		this.eachMoving!updateCreature(this);
		this.eachSoul!updateSoul(this);
		this.eachBuilding!updateBuilding(this);
		this.eachParticles!updateParticles(this);
		this.performRemovals();
		proximity.end();
	}
	ObjectManager!B obj;
	int addObject(T)(T object) if(is(T==MovingObject!B)||is(T==StaticObject!B)||is(T==Soul!B)||is(T==Building!B)){
		return obj.addObject(object);
	}
	void removeObject(int id)in{
		assert(id!=0);
	}do{
		obj.removeObject(id);
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
	void addFixed(FixedObject!B object){
		obj.addFixed(object);
	}
	void addParticle(Particle!B particle){
		obj.addParticle(particle);
	}
}
auto each(alias f,B,T...)(ObjectState!B objectState,T args){
	return objectState.obj.each!f(args);
}
auto eachMoving(alias f,B,T...)(ObjectState!B objectState,T args){
	return objectState.obj.eachMoving!f(args);
}
auto eachSoul(alias f,B,T...)(ObjectState!B objectState,T args){
	return objectState.obj.eachSoul!f(args);
}
auto eachBuilding(alias f,B,T...)(ObjectState!B objectState,T args){
	return objectState.obj.eachBuilding!f(args);
}
auto eachParticles(alias f,B,T...)(ObjectState!B objectState,T args){
	return objectState.obj.eachParticles!f(args);
}
auto eachByType(alias f,B,T...)(ObjectState!B objectState,T args){
	return objectState.obj.eachByType!f(args);
}

auto ref objectById(alias f,B,T...)(ObjectState!B objectState,int id,T args){
	return objectState.obj.objectById!f(id,args);
}
auto ref movingObjectById(alias f,alias nonMoving=(){assert(0);},B,T...)(ObjectState!B objectState,int id,T args){
	return objectState.obj.movingObjectById!(f,nonMoving)(id,args);
}
auto ref staticObjectById(alias f,alias nonStatic=(){assert(0);},B,T...)(ObjectState!B objectState,int id,T args){
	return objectState.obj.staticObjectById!(f,nonStatic)(id,args);
}
auto ref soulById(alias f,alias noSoul=(){assert(0);},B,T...)(ObjectState!B objectState,int id,T args){
	return objectState.obj.soulById!(f,noSoul)(id,args);
}
auto ref buildingById(alias f,alias noBuilding=(){assert(0);},B,T...)(ObjectState!B objectState,int id,T args){
	return objectState.obj.buildingById!(f,noBuilding)(id,args);
}
auto ref buildingByStaticObjectId(alias f,alias noStatic=(){assert(0);},B,T...)(ObjectState!B objectState,int id,T args){
	return objectState.obj.buildingByStaticObjectId!(f,noStatic)(id,args);
}

//void addBuilding(immutable(Bldg)* data,

enum Stance{
	neutral,
	ally,
	enemy,
}

final class Sides(B){
	private Side[32] sides;
	private SacParticle!B[32] manaParticles;
	private SacParticle!B[32] shrineParticles;;
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
		return sideColors[sides[side].color];
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
		if(!manaParticles[side]) manaParticles[side]=new SacParticle!B(ParticleType.manalith, manaColor(side), manaEnergy(side));
		return manaParticles[side];
	}
	SacParticle!B shrineParticle(int side){
		if(!shrineParticles[side]) shrineParticles[side]=new SacParticle!B(ParticleType.shrine, manaColor(side), manaEnergy(side));
		return shrineParticles[side];
	}
	Stance getStance(int from,int towards){
		if(sides[from].allies&(1<<towards)) return Stance.ally;
		if(sides[from].enemies&(1<<towards)) return Stance.enemy;
		return Stance.neutral;
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
	ObjectState!B lastCommitted;
	ObjectState!B current;
	ObjectState!B next;
	Triggers!B triggers;
	Array!(Array!Command) commands;
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
			placeNTT(creature);
		foreach(widgets;ntts.widgetss) // TODO: improve engine to be able to handle this
			placeWidgets(widgets);
		current.eachMoving!((ref MovingObject!B object, ObjectState!B state){
			if(object.creatureState.mode==CreatureMode.dead) object.createSoul(state);
		})(current);
		map.meshes=createMeshes!B(map.edges,map.heights,map.tiles,options.enableMapBottom); // TODO: allow dynamic retexuring
		commit();
	}
	void placeStructure(ref Structure ntt){
		import nttData;
		auto data=ntt.tag in bldgs;
		enforce(!!data);
		int flags=0; // TODO
		auto buildingId=current.addObject(Building!B(data,ntt.side,flags));
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
				offset=rotate(facingQuaternion(2*PI/360.0f*ntt.facing), offset);
				auto cposition=position+offset;
				if(!current.isOnGround(cposition)) continue;
				cposition.z=current.getGroundHeight(cposition);
				auto rotation=facingQuaternion(2*PI/360.0f*(ntt.facing+component.facing));
				building.componentIds~=current.addObject(StaticObject!B(curObj,building.id,cposition,rotation));
			}
			if(ntt.base){
				enforce(ntt.base in triggers.objectIds);
				current.buildingById!((ref manafount,state){ putOnManafount(building,manafount,state); })(triggers.objectIds[ntt.base],current);
			}
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
		auto obj=MovingObject!B(curObj,position,rotation,AnimationState.stance1,0,creatureState,curObj.creatureStats,ntt.side);
		if(ntt.flags & Flags.corpse) obj.creatureStats.health=0.0f;
		else if(ntt.flags & Flags.damaged) obj.creatureStats.health/=10.0f;
		obj.setCreatureState(current);
		obj.updateCreaturePosition(current);
		/+do{
			import std.random: uniform;
			state=cast(AnimationState)uniform(0,64);
		}while(!curObj.hasAnimationState(state));+/
		auto id=current.addObject(obj);
		triggers.associateId(ntt.id,id);
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

