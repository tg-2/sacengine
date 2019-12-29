import nttData,bldg,sacobject,sacspell,stats,state,util;
import dlib.math;
import std.algorithm, std.range, std.container, std.traits;
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
T deserializeStruct(T,string[] noserialize=[],R)(ref R data){
	auto result=T.init;
	static foreach(member;__traits(allMembers,T)){
		static if(is(typeof(__traits(getMember,result,member).offsetof))){
			static if(!noserialize.canFind(member)){
				__traits(getMember,result,member)=deserialize!(typeof(__traits(getMember,result,member)))(data);
			}
		}
	}
	return result;
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
void deserializeClass(string[] noserialize,T,R)(T object,ref R data)if(is(T==class)){
	static foreach(member;__traits(allMembers,T)){
		static if(is(typeof(__traits(getMember,object,member).offsetof))){
			static if(!noserialize.canFind(member)){
				__traits(getMember,object,member)=deserialize!(typeof(__traits(getMember,object,member)))(data);
			}
		}
	}
}

void serialize(alias sink,T)(T t)if(is(T==int)||is(T==uint)||is(T==size_t)||is(T==float)||is(T==bool)||is(T==ubyte)){
	sink((*cast(ubyte[t.sizeof]*)&t)[]);
}
T deserialize(T,R)(ref R data)if(is(T==int)||is(T==uint)||is(T==size_t)||is(T==float)||is(T==bool)||is(T==ubyte)){
	enum n=T.sizeof;
	ubyte[n] result;
	data.take(n).copy(result[]);
	data.popFrontN(n);
	return *cast(T*)result.ptr;
}
void serialize(alias sink,T)(T t)if(is(T==enum)){
	return serialize!sink(cast(OriginalType!T)t);
}
T deserialize(T,R)(ref R data)if(is(T==enum)){
	return cast(T)deserialize!(OriginalType!T)(data);
}
void serialize(alias sink)(ref MinstdRand0 rng){ return serializeStruct!sink(rng); }
T deserialize(T,R)(ref R data)if(is(T==MinstdRand0)){ return deserializeStruct!T(data); }

void serialize(alias sink,T,size_t n)(ref T[n] values)if(!(is(T==char)||is(T==ubyte)||is(T==int)||is(T==uint)||is(T==size_t)||is(T==float)||is(T==bool)||is(T==ubyte))){
	foreach(ref v;values) serialize!sink(v);
}
T deserialize(T,R)(ref R data)if(is(T==S[n],S,size_t n)&&!(is(S==char)||is(S==ubyte)||is(S==int)||is(S==uint)||is(S==size_t)||is(S==float)||is(S==bool)||is(S==ubyte))){
	T result;
	foreach(ref v;result) v=deserialize!(typeof(v))(data);
	return result;
}

void serialize(alias sink,T,size_t n)(ref T[n] values)if(is(T==char)||is(T==ubyte)||is(T==int)||is(T==uint)||is(T==size_t)||is(T==float)||is(T==bool)||is(T==ubyte)){
	sink(cast(ubyte[])values[]);
}
T deserialize(T,R)(ref R data)if(is(T==S[n],S,size_t n)&&(is(S==char)||is(S==ubyte)||is(S==int)||is(S==uint)||is(S==size_t)||is(S==float)||is(S==bool)||is(S==ubyte))){
	enum n=T.sizeof;
	ubyte[n] result;
	data.take(n).copy(result[]);
	data.popFrontN(n);
	return *cast(T*)&result;
}

void serialize(alias sink,T)(Array!T values)if(!is(T==bool)){
	static assert(is(size_t==ulong));
	serialize!sink(values.length);
	foreach(ref v;values.data) serialize!sink(v);
}
T deserialize(T,R)(ref R data)if(is(T==Array!S,S)&&!is(S==bool)){
	T result;
	static assert(is(size_t==ulong));
	result.length=deserialize!size_t(data);
	foreach(ref v;result.data) v=deserialize!(typeof(v))(data);
	return result;
}
void serialize(alias sink,T)(Array!bool values){
	static assert(0,"TODO?");
}
T deserialize(T,R)(ref R data)if(is(T==Array!S,S)&&is(S==bool)){
	static assert(0,"TODO?");
}

void serialize(alias sink,T,size_t n)(ref Vector!(T,n) vector){
	static foreach(i;0..n) serialize!sink(vector[i]);
}
T deserialize(T,R)(ref R data)if(is(T==Vector!(S,n),S,size_t n)){
	enum _=is(T==Vector!(S,n),S,size_t n);
	T result;
	static foreach(i;0..n) result[i]=deserialize!S(data);
	return result;
}

void serialize(alias sink)(ref Quaternionf rotation){ foreach(ref x;rotation.tupleof) serialize!sink(x); }
T deserialize(T,R)(ref R data)if(is(T==Quaternionf)){
	T rotation;
	foreach(ref x;rotation.tupleof) x=deserialize!(typeof(x))(data);
	return rotation;
}

void serialize(alias sink,T)(ref Queue!T queue){ return serializeStruct!sink(queue); } // TODO: compactify?
T deserialize(T,R)(ref R data)if(is(T==Queue!S,S)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(SacObject!B obj){ return serialize!sink(obj.tag); }
T deserialize(T,R)(ref R data)if(is(T==SacObject!B,B)){ return T.get(deserialize!(char[4])(data)); }

void serialize(alias sink)(ref OrderTarget orderTarget){ return serializeStruct!sink(orderTarget); }
T deserialize(T,R)(ref R data)if(is(T==OrderTarget)){ return deserializeStruct!T(data); }

void serialize(alias sink)(ref Order order){ return serializeStruct!sink(order); }
T deserialize(T,R)(ref R data)if(is(T==Order)){ return deserializeStruct!T(data); }

void serialize(alias sink)(ref CreatureAI creatureAI){ return serializeStruct!sink(creatureAI); }
T deserialize(T,R)(ref R data)if(is(T==CreatureAI)){ return deserializeStruct!T(data); }

void serialize(alias sink)(ref CreatureState creatureState){ return serializeStruct!sink(creatureState); }
T deserialize(T,R)(ref R data)if(is(T==CreatureState)){ return deserializeStruct!T(data); }

void serialize(alias sink)(ref stats.Effects effects){ return serializeStruct!sink(effects); }
T deserialize(T,R)(ref R data)if(is(T==stats.Effects)){ return deserializeStruct!T(data); }

void serialize(alias sink)(ref CreatureStats creatureStats){ return serializeStruct!sink(creatureStats); }
T deserialize(T,R)(ref R data)if(is(T==CreatureStats)){ return deserializeStruct!T(data); }

void serialize(alias sink,B,RenderMode mode)(ref MovingObjects!(B,mode) objects){ return serializeStruct!sink(objects); }
T deserialize(T,R)(ref R data)if(is(T==MovingObjects!(B,mode),B,RenderMode mode)){ return deserializeStruct!T(data); }

void serialize(alias sink,B,RenderMode mode)(ref StaticObjects!(B,mode) objects){ return serializeStruct!sink(objects); }
T deserialize(T,R)(ref R data)if(is(T==StaticObjects!(B,mode),B,RenderMode mode)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref Soul!B soul){ return serializeStruct!sink(soul); }
T deserialize(T,R)(ref R data)if(is(T==Soul!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref Souls!B souls){ return serializeStruct!sink(souls); }
T deserialize(T,R)(ref R data)if(is(T==Souls!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink)(immutable(Bldg)* bldg){ auto tag=cast(char[4])bldgTags[bldg]; return serialize!sink(tag); }
T deserialize(T,R)(ref R data)if(is(T==immutable(Bldg)*)){ auto tag=deserialize!(char[4])(data); return &bldgs[tag]; }

void serialize(alias sink,B)(ref Building!B building){ return serializeStruct!sink(building); }
T deserialize(T,R)(ref R data)if(is(T==Building!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref Buildings!B buildings){ return serializeStruct!sink(buildings); }
T deserialize(T,R)(ref R data)if(is(T==Buildings!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(SacSpell!B spell){ return serialize!sink(spell.tag); }
T deserialize(T,R)(ref R data)if(is(T==SacSpell!B,B)){ return T.get(deserialize!(char[4])(data)); }

void serialize(alias sink,B)(ref SpellInfo!B spell){ return serializeStruct!sink(spell); }
T deserialize(T,R)(ref R data)if(is(T==SpellInfo!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref Spellbook!B spellbook){ return serializeStruct!sink(spellbook); }
T deserialize(T,R)(ref R data)if(is(T==Spellbook!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref WizardInfo!B wizard){ return serializeStruct!sink(wizard); }
T deserialize(T,R)(ref R data)if(is(T==WizardInfo!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref WizardInfos!B wizards){ return serializeStruct!sink(wizards); }
T deserialize(T,R)(ref R data)if(is(T==WizardInfos!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(SacParticle!B particle){ return serialize!sink(particle.type); }
T deserialize(T,R)(ref R data)if(is(T==SacParticle!B,B)){ return T.get(deserialize!(ParticleType)(data)); }

void serialize(alias sink,B,bool relative)(ref Particles!(B,relative) particles){ return serializeStruct!sink(particles); }
T deserialize(T,R)(ref R data)if(is(T==Particles!(B,relative),B,bool relative)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref Debris!B debris){ return serializeStruct!sink(debris); }
T deserialize(T,R)(ref R data)if(is(T==Debris!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref Explosion!B explosion){ return serializeStruct!sink(explosion); }
T deserialize(T,R)(ref R data)if(is(T==Explosion!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref ManaDrain!B manaDrain){ return serializeStruct!sink(manaDrain); }
T deserialize(T,R)(ref R data)if(is(T==ManaDrain!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref CreatureCasting!B creatureCast){ return serializeStruct!sink(creatureCast); }
T deserialize(T,R)(ref R data)if(is(T==CreatureCasting!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref StructureCasting!B structureCast){ return serializeStruct!sink(structureCast); }
T deserialize(T,R)(ref R data)if(is(T==StructureCasting!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref BlueRing!B blueRing){ return serializeStruct!sink(blueRing); }
T deserialize(T,R)(ref R data)if(is(T==BlueRing!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref SpeedUp!B speedUp){ return serializeStruct!sink(speedUp); }
T deserialize(T,R)(ref R data)if(is(T==SpeedUp!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref SpeedUpShadow!B speedUpShadow){ return serializeStruct!sink(speedUpShadow); }
T deserialize(T,R)(ref R data)if(is(T==SpeedUpShadow!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref HealCasting!B healCasting){ return serializeStruct!sink(healCasting); }
T deserialize(T,R)(ref R data)if(is(T==HealCasting!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref Heal!B heal){ return serializeStruct!sink(heal); }
T deserialize(T,R)(ref R data)if(is(T==Heal!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref LightningCasting!B lightningCasting){ return serializeStruct!sink(lightningCasting); }
T deserialize(T,R)(ref R data)if(is(T==LightningCasting!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref LightningBolt!B lightningBolt){ return serializeStruct!sink(lightningBolt); }
T deserialize(T,R)(ref R data)if(is(T==LightningBolt!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref Lightning!B lightning){ return serializeStruct!sink(lightning); }
T deserialize(T,R)(ref R data)if(is(T==Lightning!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref WrathCasting!B wrathCasting){ return serializeStruct!sink(wrathCasting); }
T deserialize(T,R)(ref R data)if(is(T==WrathCasting!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref Wrath!B wrath){ return serializeStruct!sink(wrath); }
T deserialize(T,R)(ref R data)if(is(T==Wrath!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref FireballCasting!B fireballCasting){ return serializeStruct!sink(fireballCasting); }
T deserialize(T,R)(ref R data)if(is(T==FireballCasting!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref Fireball!B fireball){ return serializeStruct!sink(fireball); }
T deserialize(T,R)(ref R data)if(is(T==Fireball!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref RockCasting!B rockCasting){ return serializeStruct!sink(rockCasting); }
T deserialize(T,R)(ref R data)if(is(T==RockCasting!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref Rock!B rock){ return serializeStruct!sink(rock); }
T deserialize(T,R)(ref R data)if(is(T==Rock!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref SwarmCasting!B swarmCasting){ return serializeStruct!sink(swarmCasting); }
T deserialize(T,R)(ref R data)if(is(T==SwarmCasting!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref Bug!B bug){ return serializeStruct!sink(bug); }
T deserialize(T,R)(ref R data)if(is(T==Bug!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref Swarm!B swarm){ return serializeStruct!sink(swarm); }
T deserialize(T,R)(ref R data)if(is(T==Swarm!B,B)){ return deserializeStruct!T(data); }

private alias Effects=state.Effects;
void serialize(alias sink,B)(ref Effects!B effects){ return serializeStruct!sink(effects); }
T deserialize(T,R)(ref R data)if(is(T==Effects!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref CommandCone!B commandCone){ return serializeStruct!sink(commandCone); }
T deserialize(T,R)(ref R data)if(is(T==CommandCone!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref CommandCones!B.CommandConeElement commandConeElement){ return serializeStruct!sink(commandConeElement); }
// T deserialize(T,R)(ref R data)if(is(T==CommandCone!B.CommandConeElement,B)){ return deserializeStruct!T(data); } // DMD bug
T deserialize(T,R)(ref R data)if(T.stringof=="CommandConeElement"){ return deserializeStruct!T(data); } // DMD bug

void serialize(alias sink,B)(ref CommandCones!B commandCones){ return serializeStruct!sink(commandCones); }
T deserialize(T,R)(ref R data)if(is(T==CommandCones!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B,RenderMode mode)(ref Objects!(B,mode) objects){ return serializeStruct!(sink,["fixedObjects"])(objects); }
T deserialize(T,R)(ref R data)if(is(T==Objects!(B,mode),B,RenderMode mode)){ return deserializeStruct!(T,["fixedObjects"])(data); }

void serialize(alias sink)(ref Id id){ return serializeStruct!sink(id); }
T deserialize(T,R)(ref R data)if(is(T==Id)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref ObjectManager!B objects){ return serializeStruct!sink(objects); }
T deserialize(T,R)(ref R data)if(is(T==ObjectManager!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink)(ref CreatureGroup creatures){ return serializeStruct!sink(creatures); }
T deserialize(T,R)(ref R data)if(is(T==CreatureGroup)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref SideData!B side){ return serializeStruct!sink(side); }
T deserialize(T,R)(ref R data)if(is(T==SideData!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ref SideManager!B sides){ return serializeStruct!sink(sides); }
T deserialize(T,R)(ref R data)if(is(T==SideManager!B,B)){ return deserializeStruct!T(data); }

void serialize(alias sink,B)(ObjectState!B state){
	enum noserialize=["map","sides","proximity","toRemove"];
	assert(!state.proximity.active);
	assert(state.toRemove.length==0);
	return serializeClass!(sink,noserialize)(state);
}
void deserialize(T,R)(T state,ref R data)if(is(T==ObjectState!B,B)){
	enum noserialize=["map","sides","proximity","toRemove"];
	assert(!state.proximity.active);
	assert(state.toRemove.length==0);
	deserializeClass!noserialize(state,data);
}
