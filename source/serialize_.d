import nttData,bldg,sacobject,sacspell,stats,state,util;
import dlib.math;
import std.algorithm, std.range, std.container, std.traits, std.exception, std.conv, std.stdio;
import std.random;


void serializeStruct(alias sink,string[] noserialize=[],T)(ref T t)if(is(T==struct)){
	static foreach(member;__traits(allMembers,T)){
		static if(is(typeof(__traits(getMember,t,member).offsetof))){
			static if(!noserialize.canFind(member)){
				serialize!sink(__traits(getMember,t,member));
			}
		}
	}
}
void deserializeStruct(string[] noserialize=[],T,R,B)(ref T result,ObjectState!B state,ref R data){
	static foreach(member;__traits(allMembers,T)){
		static if(is(typeof(__traits(getMember,result,member).offsetof))){
			static if(!noserialize.canFind(member)){
				deserialize(__traits(getMember,result,member),state,data);
			}
		}
	}
}
void serializeClass(alias sink,string[] noserialize=[],T)(T t)if(is(T==class)){
	static foreach(member;__traits(allMembers,T)){
		static if(is(typeof(__traits(getMember,t,member).offsetof))){
			static if(!noserialize.canFind(member)){
				serialize!sink(__traits(getMember,t,member));
			}
		}
	}
}
void deserializeClass(string[] noserialize,T,R,B)(T object,ObjectState!B state,ref R data)if(is(T==class)){
	static foreach(member;__traits(allMembers,T)){
		static if(is(typeof(__traits(getMember,object,member).offsetof))){
			static if(!noserialize.canFind(member)){
				deserialize(__traits(getMember,object,member),state,data);
			}
		}
	}
}

void serialize(alias sink,T)(T t)if(is(T==int)||is(T==uint)||is(T==size_t)||is(T==float)||is(T==bool)||is(T==ubyte)||is(T==char)){
	sink((*cast(ubyte[t.sizeof]*)&t)[]);
}
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==int)||is(T==uint)||is(T==size_t)||is(T==float)||is(T==bool)||is(T==ubyte)||is(T==char)){
	enum n=T.sizeof;
	auto bytes=(cast(ubyte*)(&result))[0..n];
	data.take(n).copy(bytes);
	data.popFrontN(n);
}
void serialize(alias sink,T)(T t)if(is(T==enum)){
	serialize!sink(cast(OriginalType!T)t);
}
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==enum)){
	deserialize(*cast(OriginalType!T*)&result,state,data);
}
void serialize(alias sink)(ref MinstdRand0 rng){ serializeStruct!sink(rng); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==MinstdRand0)){ deserializeStruct(result,state,data); }

void serialize(alias sink,T,size_t n)(ref T[n] values)if(!(is(T==char)||is(T==ubyte)||is(T==int)||is(T==uint)||is(T==size_t)||is(T==float)||is(T==bool)||is(T==ubyte))){
	foreach(ref v;values) serialize!sink(v);
}
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==S[n],S,size_t n)&&!(is(S==char)||is(S==ubyte)||is(S==int)||is(S==uint)||is(S==size_t)||is(S==float)||is(S==bool)||is(S==ubyte))){
	foreach(ref v;result) deserialize(v,state,data);
}

void serialize(alias sink,T,size_t n)(ref T[n] values)if(is(T==char)||is(T==ubyte)||is(T==int)||is(T==uint)||is(T==size_t)||is(T==float)||is(T==bool)||is(T==ubyte)){
	sink(cast(ubyte[])values[]);
}
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==S[n],S,size_t n)&&(is(S==char)||is(S==ubyte)||is(S==int)||is(S==uint)||is(S==size_t)||is(S==float)||is(S==bool)||is(S==ubyte))){
	enum n=T.sizeof;
	auto bytes=(cast(ubyte*)(&result))[0..n];
	data.take(n).copy(bytes);
	data.popFrontN(n);
}
void serialize(alias sink,T)(Array!T values)if(!is(T==bool)){
	static assert(is(size_t==ulong));
	serialize!sink(values.length);
	foreach(ref v;values.data) serialize!sink(v);
}
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Array!S,S)&&!is(S==bool)){
	static assert(is(size_t==ulong));
	size_t len;
	deserialize(len,state,data);
	result.length=len;
	foreach(ref v;result.data) deserialize(v,state,data);
}
void serialize(alias sink,T)(Array!bool values){
	static assert(0,"TODO?");
}
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Array!S,S)&&is(S==bool)){
	static assert(0,"TODO?");
}

void serialize(alias sink,T)(T[] values){
	static assert(is(size_t==ulong));
	serialize!sink(values.length);
	foreach(ref v;values) serialize!sink(cast()v);
}
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==S[],S)){
	static assert(is(size_t==ulong));
	size_t len;
	deserialize(len,state,data);
	result.length=len;
	foreach(ref v;result) deserialize(*cast(Unqual!(typeof(v))*)&v,state,data);
}

void serialize(alias sink,T,size_t n)(ref Vector!(T,n) vector){
	static foreach(i;0..n) serialize!sink(vector[i]);
}
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Vector!(S,n),S,size_t n)){
	enum _=is(T==Vector!(S,n),S,size_t n);
	static foreach(i;0..n) deserialize(result[i],state,data);
}

void serialize(alias sink)(ref Quaternionf rotation){ foreach(ref x;rotation.tupleof) serialize!sink(x); }
void deserialize(T,R,B)(ref T rotation,ObjectState!B state,ref R data)if(is(T==Quaternionf)){
	foreach(ref x;rotation.tupleof) deserialize(x,state,data);
}

void serialize(alias sink,T)(ref Queue!T queue){ serializeStruct!sink(queue); } // TODO: compactify?
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Queue!S,S)){
	deserializeStruct(result,state,data);
}

void serialize(alias sink,B)(SacObject!B obj){ serialize!sink(obj?obj.nttTag:cast(char[4])"\0\0\0\0"); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SacObject!B)){
	char[4] tag;
	deserialize(tag,state,data);
	if(tag!="\0\0\0\0") result=T.get(tag);
	else result=null;
}

void serialize(alias sink)(ref OrderTarget orderTarget){ serializeStruct!sink(orderTarget); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==OrderTarget)){
	deserializeStruct(result,state,data);
}

void serialize(alias sink)(ref Order order){ serializeStruct!sink(order); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Order)){
	deserializeStruct(result,state,data);
}

void serialize(alias sink)(ref PositionPredictor locationPredictor){ serializeStruct!sink(locationPredictor); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==PositionPredictor)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref CreatureAI creatureAI){ serializeStruct!sink(creatureAI); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==CreatureAI)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref CreatureState creatureState){ serializeStruct!sink(creatureState); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==CreatureState)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref stats.Effects effects){ serializeStruct!sink(effects); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==stats.Effects)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref CreatureStats creatureStats){ serializeStruct!sink(creatureStats); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==CreatureStats)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B,RenderMode mode)(ref MovingObjects!(B,mode) objects){ serializeStruct!sink(objects); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==MovingObjects!(B,mode),RenderMode mode)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B,RenderMode mode)(ref StaticObjects!(B,mode) objects){ serializeStruct!sink(objects); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==StaticObjects!(B,mode),RenderMode mode)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Soul!B soul){ serializeStruct!sink(soul); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Soul!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Souls!B souls){ serializeStruct!sink(souls); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Souls!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(immutable(Bldg)* bldg){ auto tag=cast(char[4])bldgTags[bldg]; serialize!sink(tag); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==immutable(Bldg)*)){ char[4] tag; deserialize(tag,state,data); result=&bldgs[tag]; }

void serialize(alias sink,B)(ref Building!B building){ serializeStruct!sink(building); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Building!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Buildings!B buildings){ serializeStruct!sink(buildings); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Buildings!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(SacSpell!B spell){ serialize!sink(spell?spell.tag:cast(char[4])"\0\0\0\0"); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SacSpell!B)){
	char[4] tag;
	deserialize(tag,state,data);
	if(tag!="\0\0\0\0") result=T.get(tag);
	else result=null;
}

void serialize(alias sink,B)(ref SpellInfo!B spell){ serializeStruct!sink(spell); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SpellInfo!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Spellbook!B spellbook){ serializeStruct!sink(spellbook); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Spellbook!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref WizardInfo!B wizard){ serializeStruct!sink(wizard); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==WizardInfo!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref WizardInfos!B wizards){ serializeStruct!sink(wizards); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==WizardInfos!B)){ deserializeStruct(result,state,data); }


void serialize(alias sink,B)(SacParticle!B particle)in{
	assert(!!particle);
}do{
	serialize!sink(particle.type);
	serialize!sink(particle.side);
}
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SacParticle!B)){
	ParticleType type;
	deserialize(type,state,data);
	int side;
	deserialize(side,state,data);
	if(side!=-1){
		switch(type){
			case ParticleType.manalith: result=state.sides.manaParticle(side); break;
			case ParticleType.shrine: result=state.sides.shrineParticle(side); break;
			case ParticleType.manahoar: result=state.sides.manahoarParticle(side); break;
			default: enforce(0,text("invalid particle type ",type," with side ",side)); assert(0);
		}
	}else result=T.get(type);
}

void serialize(alias sink,B,bool relative)(ref Particles!(B,relative) particles){ serializeStruct!sink(particles); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Particles!(B,relative),bool relative)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Debris!B debris){ serializeStruct!sink(debris); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Debris!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Explosion!B explosion){ serializeStruct!sink(explosion); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Explosion!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref ManaDrain!B manaDrain){ serializeStruct!sink(manaDrain); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==ManaDrain!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref CreatureCasting!B creatureCast){ serializeStruct!sink(creatureCast); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==CreatureCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref StructureCasting!B structureCast){ serializeStruct!sink(structureCast); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==StructureCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref BlueRing!B blueRing){ serializeStruct!sink(blueRing); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==BlueRing!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref SpeedUp!B speedUp){ serializeStruct!sink(speedUp); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SpeedUp!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref SpeedUpShadow!B speedUpShadow){ serializeStruct!sink(speedUpShadow); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SpeedUpShadow!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref HealCasting!B healCasting){ serializeStruct!sink(healCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==HealCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Heal!B heal){ serializeStruct!sink(heal); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Heal!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref LightningCasting!B lightningCasting){ serializeStruct!sink(lightningCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==LightningCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref LightningBolt!B lightningBolt){ serializeStruct!sink(lightningBolt); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==LightningBolt!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Lightning!B lightning){ serializeStruct!sink(lightning); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Lightning!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref WrathCasting!B wrathCasting){ serializeStruct!sink(wrathCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==WrathCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Wrath!B wrath){ serializeStruct!sink(wrath); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Wrath!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref FireballCasting!B fireballCasting){ serializeStruct!sink(fireballCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==FireballCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Fireball!B fireball){ serializeStruct!sink(fireball); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Fireball!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref RockCasting!B rockCasting){ serializeStruct!sink(rockCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==RockCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Rock!B rock){ serializeStruct!sink(rock); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Rock!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref SwarmCasting!B swarmCasting){ serializeStruct!sink(swarmCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SwarmCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Bug!B bug){ serializeStruct!sink(bug); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Bug!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Swarm!B swarm){ serializeStruct!sink(swarm); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Swarm!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref BrainiacProjectile!B brainiacProjectile){ serializeStruct!sink(brainiacProjectile); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==BrainiacProjectile!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref BrainiacEffect brainiacEffect){ serializeStruct!sink(brainiacEffect); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==BrainiacEffect)){ deserializeStruct(result,state,data); }

private alias Effects=state.Effects;
void serialize(alias sink,B)(ref Effects!B effects){ serializeStruct!sink(effects); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Effects!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref CommandCone!B commandCone){ serializeStruct!sink(commandCone); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==CommandCone!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref CommandCones!B.CommandConeElement commandConeElement){ serializeStruct!sink(commandConeElement); }
// void deserialize(T,R)(ref T result,ref R data)if(is(T==CommandCone!B.CommandConeElement,B)){ deserializeStruct(result,data); } // DMD bug
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(T.stringof=="CommandConeElement"){ deserializeStruct(result,state,data); } // DMD bug

void serialize(alias sink,B)(ref CommandCones!B commandCones){ serializeStruct!sink(commandCones); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==CommandCones!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B,RenderMode mode)(ref Objects!(B,mode) objects){ serializeStruct!(sink,["fixedObjects"])(objects); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Objects!(B,mode),RenderMode mode)){ deserializeStruct!(["fixedObjects"])(result,state,data); }

void serialize(alias sink)(ref Id id){ serializeStruct!sink(id); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Id)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref ObjectManager!B objects){ serializeStruct!sink(objects); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==ObjectManager!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref CreatureGroup creatures){ serializeStruct!sink(creatures); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==CreatureGroup)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref SideData!B side){ serializeStruct!sink(side); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SideData!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref SideManager!B sides){ serializeStruct!sink(sides); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SideManager!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ObjectState!B state){
	enum noserialize=["map","sides","proximity","toRemove"];
	assert(!state.proximity.active);
	assert(state.toRemove.length==0);
	serializeClass!(sink,noserialize)(state);
}
void deserialize(T,R)(T state,ref R data)if(is(T==ObjectState!B,B)){
	enum noserialize=["map","sides","proximity","toRemove"];
	assert(!state.proximity.active);
	assert(state.toRemove.length==0);
	deserializeClass!noserialize(state,state,data);
}

void serialize(alias sink)(ref Target target){ serializeStruct!sink(target); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Target)){ deserializeStruct(result,state,data); }
void serialize(alias sink,B)(ref Command!B command){ serializeStruct!sink(command); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Command!B)){ deserializeStruct(result,state,data); }

import sids;
void serialize(alias sink)(ref Side side){ serializeStruct!sink(side); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Side)){ deserializeStruct(result,state,data); }

import recording_;

void serialize(alias sink,B)(Event!B event){ serializeStruct!sink(event); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Event!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(Recording!B recording)in{
	assert(recording.finalized);
}do{
	serialize!sink(recording.mapName);
	serializeClass!(sink,["manaParticles","shrineParticles","manahoarParticles"])(recording.sides);
	serialize!sink(recording.committed);
	serialize!sink(recording.commands);
	serialize!sink(recording.events);
}
void deserialize(T,R)(T recording,ref R data)if(is(T==Recording!B,B)){
	enum _=is(T==Recording!B,B);
	deserialize(recording.mapName,ObjectState!B.init,data);
	import sacmap;
	auto map=new SacMap!B(getHmap(recording.mapName));
	auto sides=new Sides!B();
	deserializeClass!(["manaParticles","shrineParticles","manahoarParticles"])(sides,ObjectState!B.init,data);
	auto proximity=new Proximity!B();
	size_t len;
	deserialize(len,ObjectState!B.init,data);
	enforce(len!=0);
	foreach(i;0..len){
		auto state=new ObjectState!B(map,sides,proximity);
		deserialize(state,data);
		recording.committed~=state;
	}
	deserialize(recording.commands,ObjectState!B.init,data);
	deserialize(recording.events,ObjectState!B.init,data);
}
