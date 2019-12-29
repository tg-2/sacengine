import nttData,bldg,sacobject,sacspell,stats,state,util;
import dlib.math;
import std.algorithm, std.container, std.traits;
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
void serializeClass(alias sink,string[] noserialize=[],T)(T t)if(is(T==class)){
	static foreach(member;__traits(allMembers,T)){
		static if(is(typeof(__traits(getMember,t,member).offsetof))){
			static if(!noserialize.canFind(member)){
				serialize!sink(__traits(getMember,t,member));
			}
		}
	}	
}


void serialize(alias sink,T)(T t)if(is(T==int)||is(T==uint)||is(T==size_t)||is(T==float)||is(T==bool)||is(T==ubyte)){
	sink((*cast(ubyte[t.sizeof]*)&t)[]);
}
void serialize(alias sink,T)(T t)if(is(T==enum)){
	return serialize!sink(cast(OriginalType!T)t);
}
void serialize(alias sink)(ref MinstdRand0 rng){
	foreach(ref x;rng.tupleof) serialize!sink(x);
}
void serialize(alias sink,T,size_t n)(ref T[n] values)if(!(is(T==char)||is(T==ubyte)||is(T==int)||is(T==uint)||is(T==size_t)||is(T==float)||is(T==bool)||is(T==ubyte))){
	foreach(ref v;values) serialize!sink(v);
}
void serialize(alias sink,T,size_t n)(ref T[n] values)if(is(T==char)||is(T==ubyte)||is(T==int)||is(T==uint)||is(T==size_t)||is(T==float)||is(T==bool)||is(T==ubyte)){
	sink(cast(ubyte[])values[]);
}
void serialize(alias sink,T)(Array!T values)if(!is(T==bool)){
	static assert(is(size_t==ulong));
	serialize!sink(values.length);
	foreach(ref v;values.data) serialize!sink(v);
}
void serialize(alias sink,T)(Array!bool values){
	static assert(0,"TODO?");
}

void serialize(alias sink,T,size_t n)(ref Vector!(T,n) vector){ static foreach(i;0..n) serialize!sink(vector[i]); }
void serialize(alias sink)(ref Quaternionf rotation){ foreach(ref x;rotation.tupleof) serialize!sink(x); }
void serialize(alias sink,T)(ref Queue!T queue){ return serializeStruct!sink(queue); } // TODO: compactify?

void serialize(alias sink,B)(SacObject!B obj){ return serialize!sink(obj.tag); }
void serialize(alias sink)(ref OrderTarget orderTarget){ return serializeStruct!sink(orderTarget); }
void serialize(alias sink)(ref Order order){ return serializeStruct!sink(order); }
void serialize(alias sink)(ref CreatureAI creatureAI){ return serializeStruct!sink(creatureAI); }
void serialize(alias sink)(ref CreatureState creatureState){ return serializeStruct!sink(creatureState); }
void serialize(alias sink)(ref stats.Effects effects){ return serializeStruct!sink(effects); }
void serialize(alias sink)(ref CreatureStats creatureStats){ return serializeStruct!sink(creatureStats); }
void serialize(alias sink,B,RenderMode mode)(ref MovingObjects!(B,mode) objects){ return serializeStruct!sink(objects); }
void serialize(alias sink,B,RenderMode mode)(ref StaticObjects!(B,mode) objects){ return serializeStruct!sink(objects); }
void serialize(alias sink,B)(ref Soul!B soul){ return serializeStruct!sink(soul); }
void serialize(alias sink,B)(ref Souls!B souls){ return serializeStruct!sink(souls); }
void serialize(alias sink)(immutable(Bldg)* bldg){ auto tag=cast(char[4])bldgTags[bldg]; return serialize!sink(tag); }
void serialize(alias sink,B)(ref Building!B building){ return serializeStruct!sink(building); }
void serialize(alias sink,B)(ref Buildings!B buildings){ return serializeStruct!sink(buildings); }
void serialize(alias sink,B)(SacSpell!B spell){ return serialize!sink(spell.tag); }
void serialize(alias sink,B)(ref SpellInfo!B spell){ return serializeStruct!sink(spell); }
void serialize(alias sink,B)(ref Spellbook!B spellbook){ return serializeStruct!sink(spellbook); }
void serialize(alias sink,B)(ref WizardInfo!B wizard){ return serializeStruct!sink(wizard); }
void serialize(alias sink,B)(ref WizardInfos!B wizards){ return serializeStruct!sink(wizards); }
void serialize(alias sink,B)(SacParticle!B particle){ return serialize!sink(particle.type); }
void serialize(alias sink,B,bool relative)(ref Particles!(B,relative) particles){ return serializeStruct!sink(particles); }

void serialize(alias sink,B)(ref Debris!B debris){ return serializeStruct!sink(debris); }
void serialize(alias sink,B)(ref Explosion!B explosion){ return serializeStruct!sink(explosion); }
void serialize(alias sink,B)(ref ManaDrain!B manaDrain){ return serializeStruct!sink(manaDrain); }
void serialize(alias sink,B)(ref CreatureCasting!B creatureCast){ return serializeStruct!sink(creatureCast); }
void serialize(alias sink,B)(ref StructureCasting!B structureCast){ return serializeStruct!sink(structureCast); }
void serialize(alias sink,B)(ref BlueRing!B blueRing){ return serializeStruct!sink(blueRing); }
void serialize(alias sink,B)(ref SpeedUp!B speedUp){ return serializeStruct!sink(speedUp); }
void serialize(alias sink,B)(ref SpeedUpShadow!B speedUpShadow){ return serializeStruct!sink(speedUpShadow); }
void serialize(alias sink,B)(ref HealCasting!B healCasting){ return serializeStruct!sink(healCasting); }
void serialize(alias sink,B)(ref Heal!B heal){ return serializeStruct!sink(heal); }
void serialize(alias sink,B)(ref LightningCasting!B lightningCasting){ return serializeStruct!sink(lightningCasting); }
void serialize(alias sink,B)(ref LightningBolt!B lightningBolt){ return serializeStruct!sink(lightningBolt); }
void serialize(alias sink,B)(ref Lightning!B lightning){ return serializeStruct!sink(lightning); }
void serialize(alias sink,B)(ref WrathCasting!B wrathCasting){ return serializeStruct!sink(wrathCasting); }
void serialize(alias sink,B)(ref Wrath!B wrath){ return serializeStruct!sink(wrath); }
void serialize(alias sink,B)(ref FireballCasting!B fireballCasting){ return serializeStruct!sink(fireballCasting); }
void serialize(alias sink,B)(ref Fireball!B fireball){ return serializeStruct!sink(fireball); }
void serialize(alias sink,B)(ref RockCasting!B rockCasting){ return serializeStruct!sink(rockCasting); }
void serialize(alias sink,B)(ref Rock!B rock){ return serializeStruct!sink(rock); }
void serialize(alias sink,B)(ref SwarmCasting!B swarmCasting){ return serializeStruct!sink(swarmCasting); }
void serialize(alias sink,B)(ref Bug!B bug){ return serializeStruct!sink(bug); }
void serialize(alias sink,B)(ref Swarm!B swarm){ return serializeStruct!sink(swarm); }
private alias Effects=state.Effects;
void serialize(alias sink,B)(ref Effects!B effects){ return serializeStruct!sink(effects); }
void serialize(alias sink,B)(ref CommandCone!B commandCone){ return serializeStruct!sink(commandCone); }
void serialize(alias sink,B)(ref CommandCones!B.CommandConeElement commandConeElement){ return serializeStruct!sink(commandConeElement); }
void serialize(alias sink,B)(ref CommandCones!B commandCones){ return serializeStruct!sink(commandCones); }

void serialize(alias sink,B,RenderMode mode)(ref Objects!(B,mode) objects){ return serializeStruct!(sink,["fixedObjects"])(objects); }
void serialize(alias sink)(ref Id id){ return serializeStruct!sink(id); }
void serialize(alias sink,B)(ref ObjectManager!B objects){ return serializeStruct!sink(objects); }

void serialize(alias sink)(ref CreatureGroup creatures){ return serializeStruct!sink(creatures); }
void serialize(alias sink,B)(ref SideData!B side){ return serializeStruct!sink(side); }
void serialize(alias sink,B)(ref SideManager!B sides){ return serializeStruct!sink(sides); }

void serialize(alias sink,B)(ObjectState!B state){
	enum noserialize=["map","sides","proximity","toRemove"];
	assert(!state.proximity.active);
	assert(state.toRemove.length==0);
	return serializeClass!(sink,noserialize)(state);
}
