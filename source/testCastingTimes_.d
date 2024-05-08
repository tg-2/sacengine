// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import state,sacobject,sacspell,ntts,nttData,animations;
import std.traits, std.range, std.algorithm, std.stdio, std.typecons, std.array, std.conv;
import dlib.math, dlib.math.portable;

void testCastingTimes(B)(){
	auto state=B.state.current;
	Spellbook!B spellbook;
	foreach(wtag;[EnumMembers!WizardTag]){
		auto obj=SacObject!B.getSAXS!Wizard(wtag);
		writeln("Casting cycles for ",obj.name,":");
		writeln("spell\tlevel\tcycles");
		auto flags=0;
		foreach(stag;[EnumMembers!SpellTag]){
			if(stag==SpellTag.runAway) break;
			if(chain(specialCreatures,heroCreatures,familiarCreatures).canFind(stag)) continue;
			auto spell=SacSpell!B.get(stag);
			int[][int][2] levelsForCycles;
			foreach(stationary;0..2){
				if(spell.stationary&&!stationary) continue;
				foreach(level;1..9+1){
					auto wiz=placeWizard!B(state,obj,obj.name,0,0,level,100,0.0f,0,0,0.0f,spellbook,Vector3f(1280.0f,1280.0f,0.0f),0.0f);
					if(!stationary) state.movingObjectById!(startMovingForward,(){})(wiz,state,0);
					auto wizInfo=state.getWizard(wiz);
					int numFrames=cast(int)floor(updateFPS*spell.castingTime(level));
					auto ok=state.movingObjectById!((ref object,numFrames,stationary,state)=>object.startCasting(numFrames,stationary,state),()=>false)(wiz,numFrames,!!stationary,state);
					assert(ok);
					int frame=0;
					int cycles=0;
					while(state.movingObjectById!((ref object)=>object.creatureState.mode.isCasting,()=>false)(wiz)){
						state.movingObjectById!(updateCreatureState,(){})(wiz,state);
						frame+=1;
						if(state.movingObjectById!((ref object)=>object.animationState.among(AnimationState.spellcast,AnimationState.runSpellcast)&&object.frame==0,()=>false)(wiz)){
							cycles+=1;
						}
					}
					levelsForCycles[stationary][cycles]~=level;
				}
				auto kv=levelsForCycles[stationary].byKeyValue.map!(x=>tuple(x.key,x.value)).array.sort!"a[0]>b[0]".release;
				foreach(cycles,level;kv.map!(x=>x)){
					writeln(spell.name," ",stationary?"(stationary)":"(walking)","\t",level.map!(to!string).join(","),"\t",cycles);
				}
			}
		}
	}
	stdout.flush();
	import std.exception;
	enforce(0);
}
