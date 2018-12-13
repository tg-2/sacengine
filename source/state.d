import std.algorithm;
import std.container.array: Array;
import dlib.math;
import ntts;
import sacmap, sacobject, animations;

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

struct MovingObject{
	int type;
	Vector3f position;
	Quaternionf rotation;
	AnimationState animationState;
	int frame;
}

struct FixedObject(B){
	SacObject!B sacObject;
	Vector3f position;
	Quaternionf rotation;
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

	void reserve(int reserveSize){
		ids.reserve(reserveSize);
		positions.reserve(reserveSize);
		rotations.reserve(reserveSize);
		animationStates.reserve(reserveSize);
		frames.reserve(reserveSize);
	}

	void addObject(int id,MovingObject object){
		ids~=id;
		positions~=object.position;
		rotations~=object.rotation;
		animationStates~=object.animationState;
		frames~=object.frame;
	}
	void opAssign(ref MovingObjects rhs){
		assert(sacObject is null || sacObject is rhs.sacObject);
		sacObject = rhs.sacObject;
		assignArray(ids,rhs.ids);
		assignArray(positions,rhs.positions);
		assignArray(rotations,rhs.rotations);
		assignArray(animationStates,rhs.animationStates);
		assignArray(frames,rhs.frames);
	}
}

struct StaticObject(B){
	int type;
	Vector3f position;
	Quaternionf rotation;
}

struct StaticObjects(B){
	SacObject!B sacObject;
	Array!int ids;
	Array!Vector3f positions;
	Array!Quaternionf rotations;

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

struct FixedObjects(B){
	SacObject!B sacObject;
	Array!Vector3f positions;
	Array!Quaternionf rotations;

	void addObject(FixedObject!B object)in{
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

enum numMoving=50; // TODO: fix
enum numStatic=20;

struct Objects(B,RenderMode mode){
	MovingObjects!(B,mode)[numMoving] movingObjects;
	static if(mode == mode.opaque){
		StaticObjects!B[numStatic] staticObjects;
		FixedObjects!B[] fixedObjects;
	}
}

struct ObjectManager(B){
	Objects!(B,RenderMode.opaque) opaqueObjects;
	Objects!(B,RenderMode.transparent) transparentObjects;
	void addObject(T)(int id, T object) if(is(T==MovingObject)||is(T==StaticObject)){
		static if(is(T==MovingObjects)){
			enforce(type<numMoving);
			ids~=Id(type,movingObjects[type].length);
			opaqueObjects.movingObjects[type].addObject(id,object);
		}else{
			enforce(numMoving<=type && type<numMoving+numStatic);
			ids~=Id(type,movingObjects[type-numMoving].length);
			opaqueObjects.staticObjects[type-numMoving].addObject(id,object);
		}
	}
	void addTransparent(T)(int id, float alpha){
		assert(0,"TODO");
	}
	void addFixed(FixedObject!B object){
		foreach(ref objs;opaqueObjects.fixedObjects){
			if(objs.sacObject is object.sacObject){
				objs.addObject(object);
				return;
			}
		}
		opaqueObjects.fixedObjects~=FixedObjects!B(object.sacObject);
		opaqueObjects.fixedObjects[$-1].addObject(object);
	}
}

final class ObjectState(B){
	int frame=0;
	void copyFrom(ObjectState!B rhs){
		frame=rhs.frame;
		assignArray(ids,rhs.ids);
		obj=rhs.obj;
	}
	void updateFrom(ObjectState!B rhs,ref Array!Command frameCommands){
		copyFrom(rhs);
		update();
	}
	void update(){
		frame+=1;
	}
	Array!Id ids;
	ObjectManager!B obj;
	private this(int reserveSize){
		ids.reserve(reserveSize);
	}
	int addObject(T)(T object) if(is(T==MovingObject)||is(T==StaticObject)){
		if(ids.length>=int.max) return 0;
		int id=cast(int)ids.length+1;
		obj.addObject(id,t);
		return id;
	}
	void addFixed(FixedObject!B object){
		obj.addFixed(object);
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
		foreach(ref structure;ntts.structures)
			map.placeStructure(structure);
		foreach(ref wizard;ntts.wizards)
			map.placeNTT(wizard);
		foreach(ref creature;ntts.creatures)
			map.placeNTT(creature);
		foreach(widgets;ntts.widgetss) // TODO: improve engine to be able to handle this
			map.placeWidgets(widgets);
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

