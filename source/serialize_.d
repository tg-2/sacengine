// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import nttData,bldg,sacmap,sacobject,sacspell,stats,state,util;
import dlib.math;
import std.algorithm, std.range, std.traits, std.exception, std.conv, std.stdio, std.typecons: Tuple;
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

void serialize(alias sink,T)(T t)if(is(T==int)||is(T==uint)||is(T==ulong)||is(T==float)||is(T==bool)||is(T==ubyte)||is(T==char)){
	sink((*cast(ubyte[t.sizeof]*)&t)[]);
}
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==int)||is(T==uint)||is(T==ulong)||is(T==float)||is(T==bool)||is(T==ubyte)||is(T==char)){
	enum n=T.sizeof;
	auto bytes=(cast(ubyte*)(&result))[0..n];
	enforce(n<=data.length,"not enough data");
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

void serialize(alias sink,T,size_t n)(ref T[n] values)if(!(is(T==char)||is(T==ubyte)||is(T==int)||is(T==uint)||is(T==ulong)||is(T==float)||is(T==bool)||is(T==ubyte))){
	foreach(ref v;values) serialize!sink(v);
}
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==S[n],S,size_t n)&&!(is(S==char)||is(S==ubyte)||is(S==int)||is(S==uint)||is(S==ulong)||is(S==float)||is(S==bool)||is(S==ubyte))){
	foreach(ref v;result) deserialize(v,state,data);
}

void serialize(alias sink,T,size_t n)(ref T[n] values)if(is(T==char)||is(T==ubyte)||is(T==int)||is(T==uint)||is(T==ulong)||is(T==float)||is(T==bool)||is(T==ubyte)){
	sink(cast(ubyte[])values[]);
}
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==S[n],S,size_t n)&&(is(S==char)||is(S==ubyte)||is(S==int)||is(S==uint)||is(S==ulong)||is(S==float)||is(S==bool)||is(S==ubyte))){
	enum n=T.sizeof;
	auto bytes=(cast(ubyte*)(&result))[0..n];
	enforce(n<=data.length,"not enough data");
	data.take(n).copy(bytes);
	data.popFrontN(n);
}
void serialize(alias sink,T)(ref Array!T values)if(!is(T==bool)){
	static assert(is(size_t:ulong));
	serialize!sink(cast(ulong)values.length);
	foreach(ref v;values.data) serialize!sink(v);
}
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Array!S,S)&&!is(S==bool)){
	ulong len;
	deserialize(len,state,data);
	enforce(len<=data.length,"not enough data");
	result.length=cast(size_t)len;
	foreach(ref v;result.data) deserialize(v,state,data);
}
void serialize(alias sink,T)(ref Array!bool values){
	static assert(0,"TODO?");
}
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Array!S,S)&&is(S==bool)){
	static assert(0,"TODO?");
}

void serialize(alias sink,T)(T[] values){
	static assert(is(size_t:ulong));
	serialize!sink(cast(ulong)values.length);
	foreach(ref v;values) serialize!sink(cast()v);
}
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==S[],S)){
	ulong len;
	deserialize(len,state,data);
	enforce(len<=data.length,"not enough data");
	result.length=cast(size_t)len;
	foreach(ref v;result) deserialize(*cast(Unqual!(typeof(v))*)&v,state,data);
}

void serialize(alias sink,T...)(ref Tuple!T values){ foreach(ref x;values.expand) serialize!sink(x); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Tuple!S,S...)){ foreach(ref x;result.expand) deserialize(x,state,data); }

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

void serialize(alias sink,T,size_t n)(ref SmallArray!(T,n) values)if(!is(T==bool)){ return serializeStruct!sink(values); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SmallArray!(S,n),S,size_t n)){
	deserializeStruct(result,state,data);
}

void serialize(alias sink,T)(ref Queue!T queue){
	queue.compactify();
	serializeStruct!sink(queue);
}
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

void serialize(alias sink,B)(SacBuilding!B obj){ serialize!sink(obj?obj.tag:cast(char[4])"\0\0\0\0"); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SacBuilding!B)){
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

void serialize(alias sink)(ref Path path){ serializeStruct!sink(path); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Path)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref CreatureAI creatureAI){ serializeStruct!sink(creatureAI); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==CreatureAI)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref CreatureState creatureState){ serializeStruct!sink(creatureState); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==CreatureState)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref stats.Effects effects){ serializeStruct!sink(effects); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==stats.Effects)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref CreatureStats creatureStats){ serializeStruct!sink(creatureStats); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==CreatureStats)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref CreatureStatistics creatureStatistics){ serializeStruct!sink(creatureStatistics); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==CreatureStatistics)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B,RenderMode mode)(ref MovingObjects!(B,mode) objects){ serializeStruct!sink(objects); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==MovingObjects!(B,mode),RenderMode mode)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B,RenderMode mode)(ref StaticObjects!(B,mode) objects){ serializeStruct!sink(objects); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==StaticObjects!(B,mode),RenderMode mode)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Soul!B soul){ serializeStruct!sink(soul); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Soul!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Souls!B souls){ serializeStruct!sink(souls); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Souls!B)){ deserializeStruct(result,state,data); }

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

void serialize(alias sink)(ref WizardStatistics wizardStatistics){ serializeStruct!sink(wizardStatistics); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==WizardStatistics)){ deserializeStruct(result,state,data); }

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
	enforce(ParticleType.min<=type&&type<=ParticleType.max,text("invalid particle type ",type));
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

void serialize(alias sink,B,bool relative,bool sideFiltered)(ref Particles!(B,relative,sideFiltered) particles){ serializeStruct!sink(particles); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Particles!(B,relative,sideFiltered),bool relative,bool sideFiltered)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Debris!B debris){ serializeStruct!sink(debris); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Debris!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Explosion!B explosion){ serializeStruct!sink(explosion); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Explosion!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Fire!B fire){ serializeStruct!sink(fire); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Fire!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref ManaDrain!B manaDrain){ serializeStruct!sink(manaDrain); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==ManaDrain!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref BuildingDestruction buildingDestruction){ serializeStruct!sink(buildingDestruction); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==BuildingDestruction)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref GhostKill ghostKill){ serializeStruct!sink(ghostKill); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==GhostKill)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref CreatureCasting!B creatureCast){ serializeStruct!sink(creatureCast); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==CreatureCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref StructureCasting!B structureCast){ serializeStruct!sink(structureCast); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==StructureCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref BlueRing!B blueRing){ serializeStruct!sink(blueRing); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==BlueRing!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref RedVortex vortex){ serializeStruct!sink(vortex); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==RedVortex)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref SacDocCasting!B convertCasting){ serializeStruct!sink(convertCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SacDocCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref SacDocTether sacDocTether){ serializeStruct!sink(sacDocTether); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SacDocTether)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref SacDocCarry!B sacDocCarry){ serializeStruct!sink(sacDocCarry); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SacDocCarry!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Ritual!B ritual){ serializeStruct!sink(ritual); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Ritual!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref TeleportCasting!B teleportCasting){ serializeStruct!sink(teleportCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==TeleportCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref TeleportEffect!B teleportEffect){ serializeStruct!sink(teleportEffect); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==TeleportEffect!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref TeleportRing!B teleportRing){ serializeStruct!sink(teleportRing); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==TeleportRing!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref LevelUpEffect!B levelUpEffect){ serializeStruct!sink(levelUpEffect); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==LevelUpEffect!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref LevelUpRing!B levelUpRing){ serializeStruct!sink(levelUpRing); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==LevelUpRing!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref LevelDownEffect!B levelDownEffect){ serializeStruct!sink(levelDownEffect); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==LevelDownEffect!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref LevelDownRing!B levelDownRing){ serializeStruct!sink(levelDownRing); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==LevelDownRing!B)){ deserializeStruct(result,state,data); }


void serialize(alias sink,B)(ref GuardianCasting!B guardianCasting){ serializeStruct!sink(guardianCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==GuardianCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref Guardian guardian){ serializeStruct!sink(guardian); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Guardian)){ deserializeStruct(result,state,data); }

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

void serialize(alias sink)(ref LightningBolt lightningBolt){ serializeStruct!sink(lightningBolt); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==LightningBolt)){ deserializeStruct(result,state,data); }

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

void serialize(alias sink,B)(ref SkinOfStoneCasting!B skinOfStoneCasting){ serializeStruct!sink(skinOfStoneCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SkinOfStoneCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref SkinOfStone!B skinOfStone){ serializeStruct!sink(skinOfStone); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SkinOfStone!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref EtherealFormCasting!B etherealFormCasting){ serializeStruct!sink(etherealFormCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==EtherealFormCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref EtherealForm!B etherealForm){ serializeStruct!sink(etherealForm); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==EtherealForm!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref FireformCasting!B fireformCasting){ serializeStruct!sink(fireformCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==FireformCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Fireform!B fireform){ serializeStruct!sink(fireform); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Fireform!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref ProtectiveSwarmCasting!B protectiveSwarmCasting){ serializeStruct!sink(protectiveSwarmCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==ProtectiveSwarmCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref ProtectiveBug!B protectiveBug){ serializeStruct!sink(protectiveBug); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==ProtectiveBug!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref ProtectiveSwarm!B protectiveSwarm){ serializeStruct!sink(protectiveSwarm); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==ProtectiveSwarm!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref AirShieldCasting!B airShieldCasting){ serializeStruct!sink(airShieldCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==AirShieldCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref AirShield!B.Particle particle){ serializeStruct!sink(particle); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==AirShield!B.Particle)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref AirShield!B airShield){ serializeStruct!sink(airShield); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==AirShield!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref FreezeCasting!B freezeCasting){ serializeStruct!sink(freezeCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==FreezeCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Freeze!B freeze){ serializeStruct!sink(freeze); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Freeze!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref RingsOfFireCasting!B ringsOfFireCasting){ serializeStruct!sink(ringsOfFireCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==RingsOfFireCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref RingsOfFire!B ringsOfFire){ serializeStruct!sink(ringsOfFire); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==RingsOfFire!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref SlimeCasting!B slimeCasting){ serializeStruct!sink(slimeCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SlimeCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Slime!B slime){ serializeStruct!sink(slime); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Slime!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref GraspingVinesCasting!B graspingVinesCasting){ serializeStruct!sink(graspingVinesCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==GraspingVinesCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref Vine vine){ serializeStruct!sink(vine); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Vine)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref GraspingVines!B graspingVines){ serializeStruct!sink(graspingVines); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==GraspingVines!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref SoulMoleCasting!B soulMoleCasting){ serializeStruct!sink(soulMoleCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SoulMoleCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref SoulMole!B soulMole){ serializeStruct!sink(soulMole); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SoulMole!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref RainbowCasting!B rainbowCasting){ serializeStruct!sink(rainbowCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==RainbowCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Rainbow!B rainbow){ serializeStruct!sink(rainbow); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Rainbow!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref RainbowEffect!B rainbowEffect){ serializeStruct!sink(rainbowEffect); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==RainbowEffect!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref ChainLightningCasting!B chainLightningCasting){ serializeStruct!sink(chainLightningCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==ChainLightningCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref ChainLightningCastingEffect!B chainLightningCastingEffect){ serializeStruct!sink(chainLightningCastingEffect); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==ChainLightningCastingEffect!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref ChainLightning!B chainLightning){ serializeStruct!sink(chainLightning); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==ChainLightning!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref AnimateDeadCasting!B animateDeadCasting){ serializeStruct!sink(animateDeadCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==AnimateDeadCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref AnimateDead!B animateDead){ serializeStruct!sink(animateDead); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==AnimateDead!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref AnimateDeadEffect!B animateDeadEffect){ serializeStruct!sink(animateDeadEffect); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==AnimateDeadEffect!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref EruptCasting!B eruptCasting){ serializeStruct!sink(eruptCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==EruptCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Erupt!B erupt){ serializeStruct!sink(erupt); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Erupt!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref EruptDebris!B eruptDebris){ serializeStruct!sink(eruptDebris); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==EruptDebris!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref DragonfireCasting!B dragonfireCasting){ serializeStruct!sink(dragonfireCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==DragonfireCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Dragonfire!B dragonfire){ serializeStruct!sink(dragonfire); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Dragonfire!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref SoulWindCasting!B soulWindCasting){ serializeStruct!sink(soulWindCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SoulWindCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref SoulWind!B soulWind){ serializeStruct!sink(soulWind); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SoulWind!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref SoulWindEffect soulWindEffect){ serializeStruct!sink(soulWindEffect); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SoulWindEffect)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref ExplosionEffect explosionEffect){ serializeStruct!sink(explosionEffect); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==ExplosionEffect)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref ExplosionCasting!B explosionCasting){ serializeStruct!sink(explosionCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==ExplosionCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref HaloOfEarthCasting!B haloOfEarthCasting){ serializeStruct!sink(haloOfEarthCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==HaloOfEarthCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref HaloRock!B haloRock){ serializeStruct!sink(haloRock); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==HaloRock!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref HaloOfEarth!B haloOfEarth){ serializeStruct!sink(haloOfEarth); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==HaloOfEarth!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref RainOfFrogsCasting!B rainOfFrogsCasting){ serializeStruct!sink(rainOfFrogsCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==RainOfFrogsCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref RainOfFrogs!B rainOfFrogs){ serializeStruct!sink(rainOfFrogs); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==RainOfFrogs!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref RainFrog!B rainFrog){ serializeStruct!sink(rainFrog); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==RainFrog!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref DemonicRiftCasting!B demonicRiftCasting){ serializeStruct!sink(demonicRiftCasting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==DemonicRiftCasting!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref DemonicRiftSpirit!B demonicRiftSpirit){ serializeStruct!sink(demonicRiftSpirit); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==DemonicRiftSpirit!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref DemonicRift!B demonicRift){ serializeStruct!sink(demonicRift); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==DemonicRift!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref DemonicRiftEffect!B demonicRiftEffect){ serializeStruct!sink(demonicRiftEffect); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==DemonicRiftEffect!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Spike!B spike){ serializeStruct!sink(spike); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Spike!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref BrainiacProjectile!B brainiacProjectile){ serializeStruct!sink(brainiacProjectile); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==BrainiacProjectile!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref BrainiacEffect brainiacEffect){ serializeStruct!sink(brainiacEffect); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==BrainiacEffect)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref ShrikeProjectile!B shrikeProjectile){ serializeStruct!sink(shrikeProjectile); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==ShrikeProjectile!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref ShrikeEffect shrikeEffect){ serializeStruct!sink(shrikeEffect); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==ShrikeEffect)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref LocustShoot!B locustShoot){ serializeStruct!sink(locustShoot); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==LocustShoot!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref LocustProjectile!B locustProjectile){ serializeStruct!sink(locustProjectile); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==LocustProjectile!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref SpitfireProjectile!B spitfireProjectile){ serializeStruct!sink(spitfireProjectile); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SpitfireProjectile!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref SpitfireEffect spitfireEffect){ serializeStruct!sink(spitfireEffect); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SpitfireEffect)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref GargoyleProjectile!B gargoyleProjectile){ serializeStruct!sink(gargoyleProjectile); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==GargoyleProjectile!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref GargoyleEffect gargoyleEffect){ serializeStruct!sink(gargoyleEffect); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==GargoyleEffect)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref EarthflingProjectile!B earthflingProjectile){ serializeStruct!sink(earthflingProjectile); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==EarthflingProjectile!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref FlameMinionProjectile!B flameMinionProjectile){ serializeStruct!sink(flameMinionProjectile); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==FlameMinionProjectile!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref FallenProjectile!B fallenProjectile){ serializeStruct!sink(fallenProjectile); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==FallenProjectile!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref SylphEffect!B sylphEffect){ serializeStruct!sink(sylphEffect); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SylphEffect!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref SylphProjectile!B sylphProjectile){ serializeStruct!sink(sylphProjectile); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SylphProjectile!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref RangerEffect!B rangerEffect){ serializeStruct!sink(rangerEffect); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==RangerEffect!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref RangerProjectile!B rangerProjectile){ serializeStruct!sink(rangerProjectile); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==RangerProjectile!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref NecrylProjectile!B necrylProjectile){ serializeStruct!sink(necrylProjectile); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==NecrylProjectile!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref Poison poison){ serializeStruct!sink(poison); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Poison)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref ScarabProjectile!B scarabProjectile){ serializeStruct!sink(scarabProjectile); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==ScarabProjectile!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref BasiliskProjectile!B basiliskProjectile){ serializeStruct!sink(basiliskProjectile); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==BasiliskProjectile!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref BasiliskEffect basiliskEffect){ serializeStruct!sink(basiliskEffect); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==BasiliskEffect)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref Petrification petrification){ serializeStruct!sink(petrification); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Petrification)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref TickfernoProjectile!B tickfernoProjectile){ serializeStruct!sink(tickfernoProjectile); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==TickfernoProjectile!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref TickfernoEffect tickfernoEffect){ serializeStruct!sink(tickfernoEffect); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==TickfernoEffect)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref VortickProjectile!B vortickProjectile){ serializeStruct!sink(vortickProjectile); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==VortickProjectile!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref VortickEffect vortickEffect){ serializeStruct!sink(vortickEffect); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==VortickEffect)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref VortexEffect!B vortexEffect){ serializeStruct!sink(vortexEffect); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==VortexEffect!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref VortexEffect!B.Particle particle){ serializeStruct!sink(particle); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==VortexEffect!B.Particle)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref SquallProjectile!B squallProjectile){ serializeStruct!sink(squallProjectile); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SquallProjectile!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref SquallEffect squallEffect){ serializeStruct!sink(squallEffect); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SquallEffect)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Pushback!B pushback){ serializeStruct!sink(pushback); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Pushback!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref FlummoxProjectile!B flummoxProjectile){ serializeStruct!sink(flummoxProjectile); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==FlummoxProjectile!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref PyromaniacRocket!B pyromaniacRocket){ serializeStruct!sink(pyromaniacRocket); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==PyromaniacRocket!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref GnomeEffect!B gnomeEffect){ serializeStruct!sink(gnomeEffect); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==GnomeEffect!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref PoisonDart!B poisonDart){ serializeStruct!sink(poisonDart); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==PoisonDart!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref RockForm!B rockForm){ serializeStruct!sink(rockForm); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==RockForm!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Stealth!B stealth){ serializeStruct!sink(stealth); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Stealth!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref LifeShield!B lifeShield){ serializeStruct!sink(lifeShield); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==LifeShield!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref DivineSight!B divineSight){ serializeStruct!sink(divineSight); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==DivineSight!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref SteamCloud!B steamCloud){ serializeStruct!sink(steamCloud); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SteamCloud!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref PoisonCloud!B poisonCloud){ serializeStruct!sink(poisonCloud); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==PoisonCloud!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref BlightMite!B blightMite){ serializeStruct!sink(blightMite); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==BlightMite!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref LightningCharge!B lightningCharge){ serializeStruct!sink(lightningCharge); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==LightningCharge!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B,PullType type)(ref Pull!(type,B) pull){ serializeStruct!sink(pull); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Pull!(type,B),PullType type)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref StickyBomb!B stickyBomb){ serializeStruct!sink(stickyBomb); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==StickyBomb!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref OilProjectile!B oilProjectile){ serializeStruct!sink(oilProjectile); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==OilProjectile!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Oil!B oil){ serializeStruct!sink(oil); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Oil!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref HealingShower!B healingShower){ serializeStruct!sink(healingShower); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==HealingShower!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref MutantProjectile!B mutantProjectile){ serializeStruct!sink(mutantProjectile); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==MutantProjectile!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref AbominationProjectile!B abominationProjectile){ serializeStruct!sink(abominationProjectile); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==AbominationProjectile!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref AbominationDroplet!B abominationDroplet){ serializeStruct!sink(abominationDroplet); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==AbominationDroplet!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref BombardProjectile!B bombardProjectile){ serializeStruct!sink(bombardProjectile); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==BombardProjectile!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref FlurryProjectile!B flurryProjectile){ serializeStruct!sink(flurryProjectile); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==FlurryProjectile!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref FlurryImplosion!B flurryImplosion){ serializeStruct!sink(flurryImplosion); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==FlurryImplosion!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref BoulderdashProjectile!B boulderdashProjectile){ serializeStruct!sink(boulderdashProjectile); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==BoulderdashProjectile!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref WarmongerGun!B warmongerGun){ serializeStruct!sink(warmongerGun); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==WarmongerGun!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref StyxShoot!B styxShoot){ serializeStruct!sink(styxShoot); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==StyxShoot!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref StyxExplosion!B styxExplosion){ serializeStruct!sink(styxExplosion); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==StyxExplosion!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref StyxBolt!B styxBolt){ serializeStruct!sink(styxBolt); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==StyxBolt!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref PhoenixProjectile!B phoenixProjectile){ serializeStruct!sink(phoenixProjectile); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==PhoenixProjectile!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref PhoenixEffect phoenixEffect){ serializeStruct!sink(phoenixEffect); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==PhoenixEffect)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref SilverbackProjectile!B silverbackProjectile){ serializeStruct!sink(silverbackProjectile); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SilverbackProjectile!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref SilverbackEffect silverbackEffect){ serializeStruct!sink(silverbackEffect); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SilverbackEffect)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref HellmouthProjectile!B hellmouthProjectile){ serializeStruct!sink(hellmouthProjectile); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==HellmouthProjectile!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref RhinokProjectile!B rhinokProjectile){ serializeStruct!sink(rhinokProjectile); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==RhinokProjectile!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Protector!B protector){ serializeStruct!sink(protector); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Protector!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Quake!B quake){ serializeStruct!sink(quake); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Quake!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref FirewalkEffect firewalkEffect){ serializeStruct!sink(firewalkEffect); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==FirewalkEffect)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref Firewalk!B firewalk){ serializeStruct!sink(firewalk); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Firewalk!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref RendShoot!B rend){ serializeStruct!sink(rend); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==RendShoot!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref BreathOfLife!B rend){ serializeStruct!sink(rend); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==BreathOfLife!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref Appearance appearance){ serializeStruct!sink(appearance); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Appearance)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref Disappearance disappearance){ serializeStruct!sink(disappearance); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Disappearance)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref AltarDestruction altarDestruction){ serializeStruct!sink(altarDestruction); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==AltarDestruction)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref ScreenShake screenShake){ serializeStruct!sink(screenShake); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==ScreenShake)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref TestDisplacement testDisplacement){ serializeStruct!sink(testDisplacement); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==TestDisplacement)){ deserializeStruct(result,state,data); }

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


void serialize(alias sink,B)(ref ChatMessageContent!B chatMessage){ serializeStruct!sink(chatMessage); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==ChatMessageContent!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref ChatMessage!B chatMessage){ serializeStruct!sink(chatMessage); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==ChatMessage!B)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ref ChatMessages!B chatMessages){ serializeStruct!sink(chatMessages); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==ChatMessages!B)){ deserializeStruct(result,state,data); }

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

void serialize(alias sink,B)(ref ObjectState!B.Settings settings){ serializeStruct!sink(settings); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==ObjectState!B.Settings)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(ObjectState!B state){
	enum noserialize=["map","sides","proximity","pathFinder","triggers","toRemove"];
	if(state.proximity.active) stderr.writeln("warning: serialize: proximity active");
	if(state.toRemove.length!=0) stderr.writeln("warning: serialize: toRemove not empty");
	serializeClass!(sink,noserialize)(state);
}
void deserialize(T,R)(T state,ref R data)if(is(T==ObjectState!B,B)){
	enum noserialize=["map","sides","proximity","pathFinder","triggers","toRemove"];
	if(state.proximity.active) stderr.writeln("warning: deserialize: proximity active");
	if(state.toRemove.length!=0) stderr.writeln("warning: deserialize: toRemove not empty");
	deserializeClass!noserialize(state,state,data);
}
ObjectState!B deserializeObjectState(B,R)(SacMap!B map,Sides!B sides,Proximity!B proximity,PathFinder!B pathFinder,Triggers!B triggers,ref R data){
	auto state=new ObjectState!B(map,sides,proximity,pathFinder,triggers);
	foreach(w;map.ntts.widgetss){ // TODO: get rid of code duplication
		auto curObj=SacObject!B.getWIDG(w.tag);
		foreach(pos;w.positions){
			auto position=Vector3f(pos[0],pos[1],0);
			if(!state.isOnGround(position)) continue;
			position.z=state.getGroundHeight(position);
			auto rotation=facingQuaternion(-pos[2]);
			state.addFixed(FixedObject!B(curObj,position,rotation));
		}
	}
	deserialize(state,data);
	return state;
}

void serialize(alias sink,B)(ref GameInit!B gameInit){ serializeStruct!sink(gameInit); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==GameInit!B)){ deserializeStruct(result,state,data); }
void serialize(alias sink,B)(ref GameInit!B.Slot slot){ serializeStruct!sink(slot); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==GameInit!B.Slot)){ deserializeStruct(result,state,data); }
void serialize(alias sink,B)(ref GameInit!B.Wizard wizard){ serializeStruct!sink(wizard); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==GameInit!B.Wizard)){ deserializeStruct(result,state,data); }
void serialize(alias sink,B)(ref GameInit!B.StanceSetting stanceSetting){ serializeStruct!sink(stanceSetting); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==GameInit!B.StanceSetting)){ deserializeStruct(result,state,data); }

void serialize(alias sink)(ref Target target){ serializeStruct!sink(target); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Target)){ deserializeStruct(result,state,data); }
void serialize(alias sink,B)(ref Command!B command){ serializeStruct!sink(command); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Command!B)){ deserializeStruct(result,state,data); }

import sids;
void serialize(alias sink)(ref Side side){ serializeStruct!sink(side); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Side)){ deserializeStruct(result,state,data); }

import options;
void serialize(alias sink)(ref SpellSpec spellSpec){ serializeStruct!sink(spellSpec); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==SpellSpec)){ deserializeStruct(result,state,data); }
void serialize(alias sink)(ref Settings settings){ serializeStruct!sink(settings); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Settings)){ deserializeStruct(result,state,data); }

import recording_;

void serialize(alias sink,B)(Recording!B.Event event){ serializeStruct!sink(event); }
void deserialize(T,R,B)(ref T result,ObjectState!B state,ref R data)if(is(T==Recording!B.Event)){ deserializeStruct(result,state,data); }

void serialize(alias sink,B)(Recording!B.Desynch desynch){ serializeStruct!sink(desynch); }

void serialize(alias sink,B)(Recording!B recording)in{
	assert(recording.finalized);
}do{
	serialize!sink(recording.mapName);
	serialize!sink(recording.map?recording.map.crc32:0);
	serialize!sink(recording.gameInit);

	serialize!sink(recording.finalized);
	serialize!sink(recording.commands);
	serialize!sink(recording.events);

	serialize!sink(recording.logCore);
	serialize!sink(recording.coreIndex);
	serialize!sink(recording.core);

	serialize!sink(recording.stateReplacements);

	serialize!sink(recording.desynchs);
}
void deserialize(T,R)(T recording,ref R data)if(is(T==Recording!B,B)){
	enum _=is(T==Recording!B,B);
	deserialize(recording.mapName,ObjectState!B.init,data);
	uint crc32;
	deserialize(crc32,ObjectState!B.init,data);
	deserialize(recording.gameInit,ObjectState!B.init,data);

	import sacmap;
	auto map=loadSacMap!B(recording.mapName);
	auto sides=new Sides!B(map.sids);
	auto proximity=new Proximity!B();
	auto pathFinder=new PathFinder!B(map);
	auto triggers=new Triggers!B(map.trig);
	recording.map=map;
	if(crc32!=map.crc32){
		stderr.writeln("warning: recording was saved with map version:");
		stderr.writeln(crc32);
		stderr.writeln("this may be incompatible with the current version:");
		stderr.writeln(map.crc32);
	}
	recording.sides=sides;
	recording.proximity=proximity;
	recording.pathFinder=pathFinder;
	recording.triggers=triggers;

	deserialize(recording.finalized,ObjectState!B.init,data);
	deserialize(recording.commands,ObjectState!B.init,data);
	deserialize(recording.events,ObjectState!B.init,data);

	deserialize(recording.logCore,ObjectState!B.init,data);
	deserialize(recording.coreIndex,ObjectState!B.init,data);
	ulong len;
	deserialize(len,ObjectState!B.init,data);
	enforce(len<=data.length,"not enough data");
	foreach(i;0..len) recording.core~=deserializeObjectState!B(map,sides,proximity,pathFinder,triggers,data);

	deserialize(len,ObjectState!B.init,data);
	foreach(i;0..len)
		recording.stateReplacements~=deserializeObjectState!B(map,sides,proximity,pathFinder,triggers,data);

	deserialize(len,ObjectState!B.init,data);
	foreach(i;0..len){
		int side;
		deserialize(side,ObjectState!B.init,data);
		auto state=deserializeObjectState!B(map,sides,proximity,pathFinder,triggers,data);
		recording.desynchs~=Recording!B.Desynch(side,state);
	}
}


void serialized(T)(ref T value,scope void delegate(scope ubyte[] data) dg)if(!is(T==class)){
	Array!ubyte data;
	serialize!((scope ubyte[] part){ data~=part; })(value);
	dg(data.data);
}
void serialized(T)(T value,scope void delegate(scope ubyte[] data) dg)if(is(T==class)){ // TODO: get rid of code duplication
	Array!ubyte data;
	serialize!((scope ubyte[] part){ data~=part; })(value);
	dg(data.data);
}

uint crc32(T)(ref T value)if(!is(T==class)){
	import std.digest.crc;
	CRC32 crc;
	crc.start();
	serialize!((scope ubyte[] data){ copy(data,&crc); })(value);
	auto result=crc.finish();
	static assert(result.sizeof==uint.sizeof);
	return *cast(uint*)&result;
}

uint crc32(T)(T value)if(is(T==class)){ // TODO: get rid of code duplication
	import std.digest.crc;
	CRC32 crc;
	crc.start();
	serialize!((scope ubyte[] data){ copy(data,&crc); })(value);
	auto result=crc.finish();
	static assert(result.sizeof==uint.sizeof);
	return *cast(uint*)&result;
}
