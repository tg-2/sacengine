import std.algorithm;
import std.container.array: Array;
import std.exception, std.stdio;
import dlib.math, std.math;
import ntts;
import sacmap, sacobject, animations;
import util;
enum int updateFPS=30;

enum RenderMode{
	opaque,
	transparent,
}

struct Id{
	RenderMode mode;
	int type;
	int index=-1;
}

struct MovingObject(B){
	SacObject!B sacObject;
	Vector3f position;
	Quaternionf rotation;
	AnimationState animationState;
	int frame;

	this(SacObject!B sacObject,Vector3f position,Quaternionf rotation,AnimationState animationState,int frame){
		this.sacObject=sacObject;
		this.position=position;
		this.rotation=rotation;
		this.animationState=animationState;
		this.frame=frame;
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
	SacObject!B sacObject;
	Array!int ids;
	Array!Vector3f positions;
	Array!Quaternionf rotations;
	Array!AnimationState animationStates;
	Array!int frames;

	@property int length(){ assert(ids.length<=int.max); return cast(int)ids.length; }

	void reserve(int reserveSize){
		ids.reserve(reserveSize);
		positions.reserve(reserveSize);
		rotations.reserve(reserveSize);
		animationStates.reserve(reserveSize);
		frames.reserve(reserveSize);
	}

	void addObject(int id,MovingObject!B object){
		ids~=id;
		positions~=object.position;
		rotations~=object.rotation;
		animationStates~=object.animationState;
		frames~=object.frame;
	}
	void opAssign(ref MovingObjects!(B,mode) rhs){
		assert(sacObject is null || sacObject is rhs.sacObject);
		sacObject = rhs.sacObject;
		assignArray(ids,rhs.ids);
		assignArray(positions,rhs.positions);
		assignArray(rotations,rhs.rotations);
		assignArray(animationStates,rhs.animationStates);
		assignArray(frames,rhs.frames);
	}
}
auto each(alias f,B,RenderMode mode)(ref MovingObjects!(B,mode) movingObjects){
	with(movingObjects)
		foreach(i;0..length)
			f(MovingObject!B(sacObject,positions[i],rotations[i],animationStates[i],frames[i]));
}


struct StaticObjects(B){
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
}
auto each(alias f,B)(ref StaticObjects!B staticObjects){
	with(staticObjects)
	foreach(i;0..length)
		f(StaticObject!B(sacObject,positions[i],rotations[i]));
}

struct FixedObjects(B){
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
}
auto each(alias f,B)(ref FixedObjects!B fixedObjects){
	with(fixedObjects)
		foreach(i;0..length)
			f(FixedObject!B(sacObject,positions[i],rotations[i]));
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
auto each(alias f,B,RenderMode mode)(ref Objects!(B,mode) objects){
	with(objects){
		foreach(ref movingObject;movingObjects)
			movingObject.each!f;
		static if(mode == RenderMode.opaque){
			foreach(ref staticObject;staticObjects)
				staticObject.each!f;
			foreach(ref fixedObject;fixedObjects)
				fixedObject.each!f;
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
auto each(alias f,B)(ref ObjectManager!B objectManager){
	with(objectManager){
		opaqueObjects.each!f;
		transparentObjects.each!f;
	}
}

final class ObjectState(B){ // (update logic)
	int frame=0;
	void copyFrom(ObjectState!B rhs){
		frame=rhs.frame;
		obj=rhs.obj;
	}
	void updateFrom(ObjectState!B rhs,ref Array!Command frameCommands){
		copyFrom(rhs);
		update();
	}
	void update(){
		frame+=1;
	}
	ObjectManager!B obj;
	int addObject(T)(T object) if(is(T==MovingObject!B)||is(T==StaticObject!B)){
		return obj.addObject(object);
	}
	void addFixed(FixedObject!B object){
		obj.addFixed(object);
	}
}
auto each(alias f,B)(ref ObjectState!B objectState){
	return objectState.obj.each!f;
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
		foreach(ref structure;ntts.structures)
			placeStructure(structure);
		foreach(ref wizard;ntts.wizards)
			placeNTT(wizard);
		foreach(ref creature;ntts.creatures)
			placeNTT(creature);
		/+foreach(widgets;ntts.widgetss) // TODO: improve engine to be able to handle this
			placeWidgets(widgets);+/
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
		if(isOnGround(position))
			position.z=getGroundHeight(position);
		auto rotation=facingQuaternion(ntt.facing);
		auto state=AnimationState.stance1, frame=0;
		/+import animations;
		do{
			import std.random: uniform;
			state=cast(AnimationState)uniform(0,64);
		}while(!curObj.hasAnimationState(state));
		curObj.setAnimationState(state);+/
		current.addObject(MovingObject!B(curObj,position,rotation,state,frame));
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
		next.updateFrom(current,commands[current.frame]);
		if(commands.length<=next.frame) commands~=Array!Command();
		swap(current,next);
		assert(current.frame<commands.length);
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
	void addCommand(int frame,Command command){
		auto currentFrame=current.frame;
		commands[frame]~=command;
		rollback(frame);
		simulateTo(currentFrame);
	}
}

State makeState(B)(int reserveSize){
	return new State!B(reserveSize);
}

