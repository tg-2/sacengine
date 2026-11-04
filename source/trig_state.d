// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

// runtime trigger interpreter, ported from Sacrifice.exe
// (trigger system RE notes: TRIGGER::Run 0x7c2c0, RunActions 0x7ada0, SetTimer 0x7d540)
module trig_state;

import std.algorithm, std.range;
import std.stdio, std.conv;
import std.path: buildPath;
import dlib.math, dlib.math.portable;
import util, options: GameMode;
import trig, ntts;
import sacobject, sacspell, stats;
import bots.shiny: SideType, botSideChanged;
import nttData: texts, samps, tipTags, spels;
import text_, samp;
import state;

// a trigger run is deleted when its active flag is cleared (retail: TRIGGER::Error 0x76320 clears
// run+0x4 bit0, which makes the run get deleted instead of rescheduled)
void runError(ref TriggerRun run,string message){
	stderr.writeln("trigger error (trigger ",run.trigger,", side ",run.side,"): ",message);
	run.flags&=~TriggerRunFlags.active;
}

// retail: SetTimer 0x7d540, wake=globalTick+delta
void setTimer(B)(ref TriggerRun run,ref TriggerState!B triggerState,int numFrames){
	run.wakeTick=triggerState.tick+numFrames;
}

TriggerRun* findTriggerRun(B)(ref TriggerState!B triggerState,int id){
	foreach(ref run;triggerState.runs) if(run.id==id) return &run;
	return null;
}

void releaseTriggerRunWait(B)(ref TriggerRun run,ref TriggerState!B triggerState){
	run.flags&=~TriggerRunFlags.frozen;
	run.waitKind=TriggerRunWait.none;
	run.waitId=0;
	run.wakeTick=triggerState.tick;
}

void releaseTriggerSpeechRun(B)(ref TriggerState!B triggerState,ref TriggerSpeech speech){
	if(speech.runId==0) return;
	auto run=findTriggerRun(triggerState,speech.runId);
	if(run!is null&&run.waitId==speech.id) releaseTriggerRunWait(*run,triggerState);
}

void eraseTriggerSpeech(B)(ref TriggerState!B triggerState,size_t index){
	releaseTriggerSpeechRun(triggerState,triggerState.speeches[index]);
	if(triggerState.skipSpeechId==triggerState.speeches[index].id){
		triggerState.skipSpeechId=0;
		triggerState.skipSpeechVotes=0;
	}
	foreach(i;index+1..triggerState.speeches.length)
		triggerState.speeches[i-1]=triggerState.speeches[i];
	triggerState.speeches.length=triggerState.speeches.length-1;
}

void clearTriggerSpeeches(B)(ref TriggerState!B triggerState){
	// Retail clear-text destroys the whole speech list and releases attached runs.
	while(triggerState.speeches.length) eraseTriggerSpeech(triggerState,0);
}

void startTriggerSpeech(B)(ref TriggerState!B triggerState,ref TriggerSpeech speech){
	speech.startTick=triggerState.tick;
	if(speech.runId==0||speech.pauseForInput||speech.duration<0) return;
	auto run=findTriggerRun(triggerState,speech.runId);
	if(run!is null&&run.waitId==speech.id) setTimer(*run,triggerState,speech.duration);
}

int addTriggerSpeech(B)(ref TriggerRun run,ref TriggerState!B triggerState,TriggerSpeech speech){
	speech.id=++triggerState.nextSpeechId;
	speech.startTick=-1; // queued behind the current retail speech, if any
	triggerState.speeches~=speech;
	if(speech.runId!=0){
		run.flags|=TriggerRunFlags.frozen;
		run.waitId=speech.id;
		run.wakeTick=int.max;
		if(speech.pauseForInput) run.waitKind=TriggerRunWait.speechInput;
		else if(speech.duration<0) run.waitKind=TriggerRunWait.speechPersistent;
		else run.waitKind=TriggerRunWait.none;
	}
	if(triggerState.speeches.length==1) startTriggerSpeech(triggerState,triggerState.speeches[0]);
	return speech.id;
}

void addTriggerAudioEvent(B)(ref TriggerState!B triggerState,int side,char[4] sample,int duration){
	TriggerAudioEvent event;
	event.id=++triggerState.nextAudioEventId;
	event.side=side;
	event.sample=sample;
	event.startTick=triggerState.tick;
	event.duration=max(1,duration);
	triggerState.audioEvents~=event;
}

void updateTriggerPresentation(B)(ref TriggerState!B triggerState){
	bool canStart=true;
	for(size_t i=0;i<triggerState.speeches.length;){
		auto speech=&triggerState.speeches[i];
		if(speech.startTick<0){
			if(!canStart){
				++i;
				continue;
			}
			startTriggerSpeech(triggerState,*speech);
		}
		if(speech.duration>=0&&triggerState.tick-speech.startTick>=speech.duration){
			eraseTriggerSpeech(triggerState,i);
			continue;
		}
		canStart=false;
		++i;
	}
	for(size_t i=0;i<triggerState.audioEvents.length;){
		if(triggerState.tick-triggerState.audioEvents[i].startTick>=triggerState.audioEvents[i].duration){
			foreach(j;i+1..triggerState.audioEvents.length)
				triggerState.audioEvents[j-1]=triggerState.audioEvents[j];
			triggerState.audioEvents.length=triggerState.audioEvents.length-1;
			continue;
		}
		++i;
	}
	for(size_t i=0;i<triggerState.shakes.length;){
		if(triggerState.tick-triggerState.shakes[i].startTick>=2*updateFPS){
			foreach(j;i+1..triggerState.shakes.length)
				triggerState.shakes[j-1]=triggerState.shakes[j];
			triggerState.shakes.length=triggerState.shakes.length-1;
			continue;
		}
		++i;
	}
	if(triggerState.fade.step>0.0f){
		auto target=triggerState.fade.color==TrigColor.clear?0.0f:1.0f;
		if(triggerState.fade.amount<target)
			triggerState.fade.amount=min(target,triggerState.fade.amount+triggerState.fade.step);
		else if(triggerState.fade.amount>target)
			triggerState.fade.amount=max(target,triggerState.fade.amount-triggerState.fade.step);
		if(triggerState.fade.amount==target) triggerState.fade.step=0.0f;
	}
}

// Trigger responses use the ordinary command/recording/network path. Ids identify the exact wait;
// stale, duplicated, misdirected, and otherwise invalid responses have no effect.
bool applyTriggerResponseImpl(B)(int side,int triggerId,int triggerChoice,ref TriggerState!B triggerState,Triggers!B triggers){
	if(triggerId<0){
		if(triggerChoice!=0||triggerId==int.min) return false;
		auto speechId=-triggerId;
		foreach(i,ref speech;triggerState.speeches){
			if(speech.id!=speechId||speech.startTick<0||speech.runId!=0||!speech.pauseForInput||speech.side!=side) continue;
			eraseTriggerSpeech(triggerState,i);
			return true;
		}
		return false;
	}
	auto run=findTriggerRun(triggerState,triggerId);
	if(run is null||run.side!=side||!(run.flags&TriggerRunFlags.active)) return false;
	if(run.waitKind==TriggerRunWait.speechInput){
		if(triggerChoice!=0) return false;
		foreach(i,ref speech;triggerState.speeches){
			if(speech.id!=run.waitId||speech.startTick<0||speech.runId!=run.id||!speech.pauseForInput) continue;
			eraseTriggerSpeech(triggerState,i);
			return true;
		}
		return false;
	}
	if(run.waitKind!=TriggerRunWait.ask||run.waitId!=run.id||!triggerChoice.among(1,2)) return false;
	foreach(i,ref ask;triggerState.asks){
		if(ask.runId!=run.id||ask.side!=side) continue;
		setVariable(ask.variable,triggerChoice,*run,triggerState,triggers);
		foreach(j;i+1..triggerState.asks.length)
			triggerState.asks[j-1]=triggerState.asks[j];
		triggerState.asks.length=triggerState.asks.length-1;
		releaseTriggerRunWait(*run,triggerState);
		return true;
	}
	return false;
}

bool applyTriggerSkip(B)(int side,int triggerChoice,ObjectState!B state){
	if(triggerChoice!=0||!(0<=side&&side<32)) return false;
	uint requiredVotes=0;
	foreach(voterSide;0..min(32,state.sid.sides.length)){
		if(state.sid.sides[voterSide].sideType!=SideType.human||state.isDefeated(voterSide)) continue;
		requiredVotes|=1u<<voterSide;
	}
	if(!(requiredVotes&(1u<<side))) return false; // AI sides and observers cannot vote.
	foreach(i,ref speech;state.trig.speeches){
		if(speech.startTick<0) continue;
		if(state.trig.skipSpeechId!=speech.id){
			state.trig.skipSpeechId=speech.id;
			state.trig.skipSpeechVotes=0;
		}
		state.trig.skipSpeechVotes|=1u<<side;
		if((state.trig.skipSpeechVotes&requiredVotes)==requiredVotes)
			eraseTriggerSpeech(state.trig,i);
		return true;
	}
	state.trig.skipSpeechId=0;
	state.trig.skipSpeechVotes=0;
	return false;
}

bool applyTriggerResponse(B)(Command!B command,ObjectState!B state){
	// int.min is reserved for collective speech-skip attempts, not an ordinary response ID.
	if(command.triggerId==int.min) return applyTriggerSkip(command.side,command.triggerChoice,state);
	return applyTriggerResponseImpl(command.side,command.triggerId,command.triggerChoice,state.trig,state.triggers);
}

void initializeTriggers(B)(ref TriggerState!B triggerState,ObjectState!B state){
	triggerState.initialized=true;
	auto triggers=state.triggers;
	foreach(i,perSide;triggers.variablePerSide)
		triggerState.variableValues.length+=perSide?32:1;
	triggerState.variableValues[]=0;
	triggerState.objectiveFlags.length=triggers.objectives.length;
	foreach(i,objective;triggers.objectives)
		triggerState.objectiveFlags[i]=objective.flags;
	triggerState.variableDisplayFlags.length=triggers.variableOffsets.length;
	triggerState.variableDisplayFlags[]=0;
	foreach(ti,ref trigger;triggers.trig.triggers){
		foreach(side;0..32){
			if(!(trigger.sides&(1u<<side))) continue;
			TriggerRun run;
			run.id=++triggerState.nextRunId;
			run.trigger=cast(int)ti;
			run.side=side;
			run.flags=TriggerRunFlags.active;
			if(trigger.flags&TriggerFlags.runOnce) run.flags|=TriggerRunFlags.runOnce;
			run.wakeTick=0;
			triggerState.runs~=run;
		}
	}
}

// retail: TRIGGER::Run 0x7c2c0
void processRun(B)(ref TriggerRun run,ref TriggerState!B triggerState,ObjectState!B state){
	if(!(run.flags&TriggerRunFlags.active)) return;
	if(!(0<=run.trigger&&run.trigger<state.triggers.trig.triggers.length)){
		run.flags&=~TriggerRunFlags.active;
		return;
	}
	auto trigger=&state.triggers.trig.triggers[run.trigger];
	if(run.flags&TriggerRunFlags.frozen){
		// External waits are released only by their owning speech or ask response.
		if(run.waitKind!=TriggerRunWait.none) return;
		if(run.wakeTick>triggerState.tick) return;
		run.flags&=~TriggerRunFlags.frozen;
		run.waitId=0;
	}
	if(run.wakeTick>triggerState.tick) return;
	if(!(run.flags&TriggerRunFlags.actionsPhase)){
		// condition phase
		bool passed=true;
		foreach(condition;trigger.conditions){
			if(!checkCondition(condition,run,triggerState,state)){
				passed=false;
				break;
			}
		}
		if(!passed){
			// retail: failed conditions rechecked after 30 ticks; runs with cleared active flag are deleted
			if(run.flags&TriggerRunFlags.active) setTimer(run,triggerState,updateFPS/2);
			return;
		}
		run.flags|=TriggerRunFlags.actionsPhase;
		run.actionIndex=0;
		run.locals[]=0;
		// retail: RunActions is entered on the same tick the conditions pass
		runActions(run,trigger,triggerState,state);
	}else runActions(run,trigger,triggerState,state);
}

// retail: RunActions 0x7ada0
// the action index is advanced before the action runs; an action returning false means
// "continue with the next action on the next tick", not "retry this action"
void runActions(B)(ref TriggerRun run,Trigger* trigger,ref TriggerState!B triggerState,ObjectState!B state){
	while(run.actionIndex<trigger.actions.length&&(run.flags&TriggerRunFlags.active)){
		auto action=trigger.actions[run.actionIndex];
		run.actionIndex+=1;
		if(!runAction(action,run,triggerState,state))
			return;
	}
	if(run.flags&TriggerRunFlags.runOnce||!(run.flags&TriggerRunFlags.active)){
		run.flags&=~TriggerRunFlags.active; // completed runOnce run, or run aborted by an error
	}else if(run.actionIndex>=trigger.actions.length){
		// completed looping run: re-arm conditions for the next tick
		run.flags&=~TriggerRunFlags.actionsPhase;
		setTimer(run,triggerState,0);
	}
}

void deleteInactiveRuns(B)(ref TriggerState!B triggerState){
	// in-place compaction, no allocation
	auto runs=triggerState.runs;
	size_t w=0;
	foreach(r;0..runs.length){
		if(!(runs[r].flags&TriggerRunFlags.active)) continue;
		if(w!=r) runs[w]=runs[r];
		++w;
	}
	triggerState.runs.length=w;
}

void updateTriggers(B)(ref TriggerState!B triggerState,ObjectState!B state){
	if(state.settings.gameMode==GameMode.skirmish) return; // retail: trigger system does not run in skirmish
	if(!triggerState.initialized) initializeTriggers(triggerState,state);
	if(triggerState.gameTimer>0){
		triggerState.gameTimer-=1;
		if(triggerState.gameTimer==0) triggerState.gameTimerVisible=false; // retail: deferred callback hides the timer
	}
	triggerState.tick+=1;
	updateTriggerPresentation(triggerState);
	foreach(ref run;triggerState.runs)
		processRun(run,triggerState,state);
	deleteInactiveRuns(triggerState);
}

// trigger variables. retail: .TVAR variables, [SIDE] variables hold one value per side.
int getVariable(B)(uint variable,ref TriggerRun run,ref TriggerState!B triggerState,ObjectState!B state){
	auto triggers=state.triggers;
	if(variable>=triggers.variableOffsets.length){
		runError(run,text("invalid variable ",variable));
		return 0;
	}
	return triggerState.variableValues[triggers.variableOffsets[variable]+(triggers.variablePerSide[variable]?run.side:0)];
}

void setVariable(B)(uint variable,int value,ref TriggerRun run,ref TriggerState!B triggerState,Triggers!B triggers){
	if(variable>=triggers.variableOffsets.length){
		runError(run,text("invalid variable ",variable));
		return;
	}
	triggerState.variableValues[triggers.variableOffsets[variable]+(triggers.variablePerSide[variable]?run.side:0)]=value;
}

void setVariable(B)(uint variable,int value,ref TriggerRun run,ref TriggerState!B triggerState,ObjectState!B state){
	setVariable(variable,value,run,triggerState,state.triggers);
}

// retail: quantity evaluation is integer arithmetic, division truncates
int evalQuantity(B)(TrigQuantity quantity,ref TriggerRun run,ref TriggerState!B triggerState,ObjectState!B state){
	if(cast(TrigQuantityTrue)quantity) return 1;
	if(cast(TrigQuantityFalse)quantity) return 0;
	if(auto integer=cast(TrigQuantityInteger)quantity) return integer.value;
	if(auto variable=cast(TrigQuantityVariable)quantity) return getVariable(variable.variable,run,triggerState,state);
	if(auto add=cast(TrigQuantityAdd)quantity)
		return evalQuantity(add.a,run,triggerState,state)+evalQuantity(add.b,run,triggerState,state);
	if(auto sub=cast(TrigQuantitySub)quantity)
		return evalQuantity(sub.a,run,triggerState,state)-evalQuantity(sub.b,run,triggerState,state);
	if(auto mul=cast(TrigQuantityMul)quantity)
		return evalQuantity(mul.a,run,triggerState,state)*evalQuantity(mul.b,run,triggerState,state);
	if(auto div=cast(TrigQuantityDiv)quantity){
		auto b=evalQuantity(div.b,run,triggerState,state);
		if(b==0) return 0;
		return evalQuantity(div.a,run,triggerState,state)/b;
	}
	if(auto stat=cast(TrigQuantityCreatureStat)quantity){
		auto id=resolveNtt(stat.creature,run.side,state);
		if(id==0||state.isValidBuilding(id)){
			runError(run,text("quantity: cannot resolve creature ",stat.creature.id));
			return 0;
		}
		return state.movingObjectById!((ref obj,stat)=>creatureStat(obj,stat),()=>0)(id,stat.stat);
	}
	runError(run,text("unsupported quantity ",typeid(quantity)));
	return 0;
}

// maxOr0 is the maximum possible value where applicable (0 otherwise), used by TrigAll
bool checkConstraint(B)(TrigConstraint constraint,int current,int maxOr0,ref TriggerRun run,ref TriggerState!B triggerState,ObjectState!B state){
	if(auto atLeast=cast(TrigAtLeast)constraint)
		return current>=evalQuantity(atLeast.quantity,run,triggerState,state);
	if(auto atMost=cast(TrigAtMost)constraint)
		return current<=evalQuantity(atMost.quantity,run,triggerState,state);
	if(auto exactly=cast(TrigExactly)constraint)
		return current==evalQuantity(exactly.quantity,run,triggerState,state);
	if(cast(TrigAll)constraint) return current==maxOr0;
	if(cast(TrigNone)constraint) return current==0;
	if(cast(TrigTrue)constraint) return current!=0;
	if(cast(TrigFalse)constraint) return current==0;
	runError(run,text("unsupported constraint ",typeid(constraint)));
	return false;
}

// creature stats accessible to triggers (retail: stat codes 219-232)
// retail stores and transfers these stats as integers in raw data units (int16 for codes
// 219-229, int32 for 230-232, see the stat reader at 0x476f70 and setter at 0x4770a0), so
// convert between runtime units and raw units at this boundary; rounding recovers the raw
// integer from the scaled runtime float
int statToRetailUnits(float value,float factor){
	auto scaled=value*factor;
	return cast(int)(scaled+(scaled>=0.0f?0.5f:-0.5f));
}
int creatureStat(B)(ref MovingObject!B obj,TrigCreatureStat stat){
	with(TrigCreatureStat) final switch(stat){
		case speed: return statToRetailUnits(obj.creatureStats.runningSpeed,1e2f);
		case flyingSpeed: return statToRetailUnits(obj.creatureStats.flyingSpeed,1e2f);
		case maxHealth: return statToRetailUnits(obj.creatureStats.maxHealth,1.0f);
		case regeneration: return statToRetailUnits(obj.creatureStats.regeneration,60.0f);
		case drain: return statToRetailUnits(obj.creatureStats.drain,1e3f);
		case rangedAccuracy: return statToRetailUnits(obj.creatureStats.rangedAccuracy,1.0f);
		case resistanceToMelee: return statToRetailUnits(obj.creatureStats.meleeResistance,1e3f);
		case resistanceToDirectSpell: return statToRetailUnits(obj.creatureStats.directSpellResistance,1e3f);
		case resistanceToSplashSpell: return statToRetailUnits(obj.creatureStats.splashSpellResistance,1e3f);
		case resistanceToDirectRanged: return statToRetailUnits(obj.creatureStats.directRangedResistance,1e3f);
		case resistanceToSplashRanged: return statToRetailUnits(obj.creatureStats.splashRangedResistance,1e3f);
		case maxMana: return statToRetailUnits(obj.creatureStats.maxMana,1.0f);
		case kills,gibs: return 0; // not tracked in sacengine
	}
}

void setCreatureStat(B)(ref MovingObject!B obj,TrigCreatureStat stat,int value){
	// retail: codes 219-229 store into int16 fields, codes 230-232 into int32 fields
	with(TrigCreatureStat) final switch(stat){
		case speed: obj.creatureStats.runningSpeed=cast(short)value*1e-2f; break;
		case flyingSpeed: obj.creatureStats.flyingSpeed=cast(short)value*1e-2f; break;
		case maxHealth: obj.creatureStats.maxHealth=cast(short)value; break;
		case regeneration: obj.creatureStats.regeneration=cast(short)value/60.0f; break;
		case drain: obj.creatureStats.drain=cast(short)value*1e-3f; break;
		case rangedAccuracy: obj.creatureStats.rangedAccuracy=cast(short)value; break;
		case resistanceToMelee: obj.creatureStats.meleeResistance=cast(short)value*1e-3f; break;
		case resistanceToDirectSpell: obj.creatureStats.directSpellResistance=cast(short)value*1e-3f; break;
		case resistanceToSplashSpell: obj.creatureStats.splashSpellResistance=cast(short)value*1e-3f; break;
		case resistanceToDirectRanged: obj.creatureStats.directRangedResistance=cast(short)value*1e-3f; break;
		case resistanceToSplashRanged: obj.creatureStats.splashRangedResistance=cast(short)value*1e-3f; break;
		case maxMana: obj.creatureStats.maxMana=value; break;
		case kills,gibs: break; // not tracked in sacengine
	}
}

// resolves a trigger ntt reference to a runtime object id (0: unresolvable)
// creature/wizard/structure ids are map-file ids, translated via the association table
int resolveNttId(B)(uint id,int side,bool wantStructure,ObjectState!B state){
	auto cwct=*cast(uint*)"cwct".ptr; // current side's wizard (tag as little-endian dword)
	auto swct=*cast(uint*)"swct".ptr; // local (singleplayer) side's wizard
	if(id==cwct){
		// retail: wizard of the side this trigger run belongs to
		if(0<=side&&side<state.sid.sides.length)
			if(auto wiz=state.getWizardForSide(side)) return wiz.id;
		return 0;
	}
	if(id==swct){
		// retail: wizard of the local player's side (the singleplayer side in scenario maps)
		auto localSide=state.sides.scenarioSide(0);
		if(0<=localSide&&localSide<state.sid.sides.length)
			if(auto wiz=state.getWizardForSide(localSide)) return wiz.id;
		return 0;
	}
	auto objectId=state.triggers.associatedId(cast(int)id);
	if(objectId==0||!state.isValidId(objectId)) return 0;
	if(wantStructure!=!!state.isValidBuilding(objectId)) return 0;
	return objectId;
}

int resolveNtt(B)(TrigNtt ntt,int side,ObjectState!B state){
	uint id;
	bool wantStructure=false;
	if(auto creature=cast(TrigCreature)ntt) id=creature.id;
	else if(auto wizard=cast(TrigWizard)ntt) id=wizard.id;
	else if(auto structure=cast(TrigStructure)ntt){ id=structure.id; wantStructure=true; }
	else return 0;
	return resolveNttId(id,side,wantStructure,state);
}

bool objectPosition(B)(int id,out Vector3f position,ObjectState!B state){
	if(state.isValidBuilding(id))
		return state.buildingById!((ref building,pos,state){
			if(!building.componentIds.length) return false;
			*pos=building.position(state);
			return true;
		},()=>false)(id,&position,state);
	return state.movingObjectById!((ref obj,pos){ *pos=obj.position; return true; },()=>false)(id,&position);
}

// creature type tags (trig.d): rctt generic creature, zwtt wizard, cwtt wizard or creature,
// lstt controllable creature, pctt corpse; anything else is an exact creature tag
bool matchesCreatureType(B)(char[4] ctype,ref MovingObject!B obj){
	switch(ctype){
		case "rctt": return !obj.isWizard;
		case "zwtt": return obj.isWizard;
		case "cwtt": return true;
		case "lstt": return !obj.isWizard&&obj.isAlive;
		case "pctt": return obj.creatureState.mode==CreatureMode.dead;
		default: return obj.sacObject.nttTag==ctype;
	}
}

// structure type tags: nmtt manalith, fmtt manafount, latt altar; anything else is an exact building tag
bool matchesStructureType(B)(char[4] stype,ref Building!B building){
	switch(stype){
		case "nmtt": return building.isManalith;
		case "fmtt": return building.isManafount;
		case "latt": return building.isAltar;
		default: return building.sacBuilding.tag==stype;
	}
}

// structure tags for the all-of-type actions (creature tags do not match buildings)
bool matchesNttTypeStructure(B)(char[4] nttType,ref Building!B building){
	switch(nttType){
		case "rctt","zwtt","cwtt","lstt","pctt": return false;
		default: return matchesStructureType(nttType,building);
	}
}

// trigger locations. retail: SetupLocation/IsAtLocation (0x7d410 AddLocation, marker kinds 0x04000000/0x08000000)
struct CheckLocation{
	int type=0; // 0: none, 1: at ntt, 2: marker
	int objectId=0;
	float radius=-1.0f;
	const(TriggerMarker)* marker;
}

bool setupLocation(B)(TrigLocation location,int side,out CheckLocation result,ObjectState!B state){
	result=CheckLocation.init;
	if(location is null) return true;
	if(auto atNtt=cast(TrigAtNtt)location){
		auto id=resolveNtt(atNtt.ntt,side,state);
		if(id==0) return false;
		result.type=1;
		result.objectId=id;
		// retail: 10m radius for creatures, 25m for structures
		result.radius=cast(TrigStructure)atNtt.ntt?25.0f:10.0f;
		return true;
	}
	uint markerId;
	if(auto marker=cast(TrigMarker)location) markerId=marker.id;
	else if(auto markerAtHeight=cast(TrigMarkerAtHeight)location) markerId=markerAtHeight.id; // height does not affect location tests
	else return false;
	auto marker=state.triggers.findMarker(cast(int)markerId);
	if(marker is null) return false;
	result.type=2;
	result.marker=marker;
	return true;
}

bool isAtLocation(B)(Vector3f position,ref CheckLocation location,ObjectState!B state){
	if(location.type==0) return true;
	if(location.type==1){
		if(location.radius<0.0f) return true;
		Vector3f center;
		if(!objectPosition(location.objectId,center,state)) return false;
		auto delta=position-center;
		return delta.lengthsqr<=location.radius^^2; // retail: 3d distance
	}
	auto marker=location.marker;
	if(marker is null) return false;
	if(marker.kind==0x04000000){ // cylinder
		auto delta=position.xy-marker.position.xy;
		return delta.lengthsqr<=marker.radius^^2;
	}
	if(marker.kind==0x08000000){ // oriented box
		auto delta=position.xy-marker.position.xy;
		auto angle=-marker.yawDegrees*(pi!float/180.0f);
		auto c=cos(angle),s=sin(angle);
		auto x=c*delta.x-s*delta.y,y=s*delta.x+c*delta.y;
		return abs(x)<=marker.radius&&abs(y)<=marker.halfLength;
	}
	return false;
}

// position of a location, for teleports, orders and creature creation
bool locationPosition(B)(TrigLocation location,int side,out Vector3f position,ObjectState!B state){
	position=Vector3f(0.0f,0.0f,0.0f);
	if(location is null) return false;
	if(auto atNtt=cast(TrigAtNtt)location){
		auto id=resolveNtt(atNtt.ntt,side,state);
		if(id==0) return false;
		return objectPosition(id,position,state);
	}
	uint markerId;
	if(auto marker=cast(TrigMarker)location) markerId=marker.id;
	else if(auto markerAtHeight=cast(TrigMarkerAtHeight)location) markerId=markerAtHeight.id;
	else return false;
	auto marker=state.triggers.findMarker(cast(int)markerId);
	if(marker is null) return false;
	position=marker.position;
	return true;
}

// side specs. retail: CheckSideCommandsNtts 0x7b3b0
// enemy: hostile in either direction, excluding self
// friendly: allied in either direction, including self
// neutral: neither hostile nor allied in either direction, excluding self
uint sideSpecSides(B)(TrigSideSpec sideSpec,int side,ObjectState!B state){
	if(cast(TrigCurrentSide)sideSpec) return 0<=side&&side<32?1u<<side:0u;
	if(auto trigSide=cast(TrigSide)sideSpec) return trigSide.side<32?1u<<trigSide.side:0u;
	uint mask=0;
	bool enemy=cast(TrigEnemySides)sideSpec!is null;
	bool friendly=!enemy&&cast(TrigFriendlySides)sideSpec!is null;
	if(!enemy&&!friendly&&!cast(TrigNeutralSides)sideSpec) return 0;
	foreach(other;0..min(cast(int)state.sid.sides.length,32)){
		if(other==side){
			if(friendly) mask|=1u<<other;
			continue;
		}
		auto isEnemy=state.getStance(side,other)==Stance.enemy||state.getStance(other,side)==Stance.enemy;
		auto isAlly=state.getStance(side,other)==Stance.ally||state.getStance(other,side)==Stance.ally;
		if(enemy&&isEnemy||friendly&&isAlly||!enemy&&!friendly&&!isEnemy&&!isAlly)
			mask|=1u<<other;
	}
	return mask;
}

// per-ntt filters for counting and visibility tests
struct NttFilter{
	int ownerSide=-1; // -1: any side
	CheckLocation location; // type 0: no restriction
	int viewerSide=-1; // -1: no fog-of-war visibility test (retail: sees conditions)
	// geometric viewer (retail: ntt sees ntts, 0x8c050)
	bool hasViewer=false;
	Vector3f viewerPosition=Vector3f(0.0f,0.0f,0.0f);
	float viewerEyeHeight=0.0f;
	float viewerFacing=0.0f;
	float viewerAlertness=0.0f;
	float viewerSightRange=0.0f;
	float viewerSightFov=0.0f;
}

bool setupViewer(B)(ref NttFilter filter,int viewerId,ObjectState!B state){
	return state.movingObjectById!((ref viewer,filter){
		filter.hasViewer=true;
		filter.viewerPosition=viewer.position;
		filter.viewerEyeHeight=viewer.relativeHitbox[1].z;
		filter.viewerFacing=viewer.creatureState.facing;
		filter.viewerAlertness=viewer.creatureAI.alertness;
		filter.viewerSightRange=viewer.sacObject.sightRange;
		filter.viewerSightFov=viewer.sacObject.sightFov;
		return true;
	},()=>false)(viewerId,&filter);
}

bool passesFilter(B)(ref MovingObject!B obj,const(NttFilter)* filter,ObjectState!B state){
	if(filter.ownerSide>=0&&obj.side!=filter.ownerSide) return false;
	if(filter.location.type!=0&&!isAtLocation(obj.position,*cast(CheckLocation*)&filter.location,state)) return false;
	if(filter.viewerSide>=0&&!state.isVisibleToSide(filter.viewerSide,obj.id,obj.side)) return false;
	if(filter.hasViewer){
		auto aimOffset=Vector3f(0.0f,0.0f,obj.relativeHitbox[1].z);
		if(!canSee(state,filter.viewerPosition,filter.viewerEyeHeight,filter.viewerFacing,filter.viewerAlertness,filter.viewerSightRange,filter.viewerSightFov,obj.position,aimOffset))
			return false;
	}
	return true;
}

int countCreatureType(B)(char[4] ctype,const(NttFilter)* filter,ObjectState!B state,int* maximum=null){
	int count=0;
	if(maximum) *maximum=0;
	bool corpses=ctype=="pctt";
	state.obj.eachMoving!((ref obj,ctype,filter,corpses,state,count,maximum){
		if(!corpses&&!obj.isAlive&&obj.creatureState.mode!=CreatureMode.dying) return;
		if(filter.ownerSide>=0&&obj.side!=filter.ownerSide) return;
		if(maximum) *maximum+=1;
		if(!matchesCreatureType(ctype,obj)) return;
		if(!passesFilter(obj,filter,state)) return;
		*count+=1;
	})(ctype,filter,corpses,state,&count,maximum);
	return count;
}

int countStructureType(B)(char[4] stype,const(NttFilter)* filter,ObjectState!B state,int* maximum=null){
	int count=0;
	if(maximum) *maximum=0;
	state.obj.eachBuilding!((ref building,filter,stype,state,count,maximum){
		if(filter.ownerSide>=0&&building.side!=filter.ownerSide) return;
		if(maximum) *maximum+=1;
		if(!matchesStructureType(stype,building)) return;
		if(filter.location.type!=0){
			if(!building.componentIds.length) return;
			if(!isAtLocation(building.position(state),*cast(CheckLocation*)&filter.location,state)) return;
		}
		if(filter.viewerSide>=0&&!state.isVisibleToSide(filter.viewerSide,building.id,building.side)) return;
		*count+=1;
	})(filter,stype,state,&count,maximum);
	return count;
}

// retail: CheckNtts 0x7b260
// ownerSide<0: any owner. returns false (without error) for unresolvable specific ntts.
bool checkNtts(B)(TrigNtts ntts,int ownerSide,const(NttFilter)* filter,ref TriggerRun run,ref TriggerState!B triggerState,ObjectState!B state){
	if(auto quantity=cast(TrigQuantityCreatureType)ntts){
		int maximum;
		auto count=countCreatureType(quantity.ctype,filter,state,&maximum);
		return checkConstraint(quantity.constraint,count,maximum,run,triggerState,state);
	}
	if(auto quantity=cast(TrigQuantityStructureType)ntts){
		int maximum;
		auto count=countStructureType(quantity.stype,filter,state,&maximum);
		return checkConstraint(quantity.constraint,count,maximum,run,triggerState,state);
	}
	int id;
	if(auto specific=cast(TrigNttsCreature)ntts) id=resolveNtt(specific.creature,run.side,state);
	else if(auto specific=cast(TrigNttsStructure)ntts) id=resolveNtt(specific.structure,run.side,state);
	if(id==0) return false;
	if(state.isValidBuilding(id)){
		if(cast(TrigNttsCreature)ntts) return false;
		return state.buildingById!((ref building,filter,state){
			if(filter.ownerSide>=0&&building.side!=filter.ownerSide) return false;
			if(filter.location.type!=0){
				if(!building.componentIds.length) return false;
				if(!isAtLocation(building.position(state),*cast(CheckLocation*)&filter.location,state)) return false;
			}
			if(filter.viewerSide>=0&&!state.isVisibleToSide(filter.viewerSide,building.id,building.side)) return false;
			return true;
		},()=>false)(id,filter,state);
	}
	return state.movingObjectById!((ref obj,filter,state){
		if(!obj.isAlive) return false;
		return passesFilter(obj,filter,state);
	},()=>false)(id,filter,state);
}

// retail: multi-side specs are checked per side and aggregated with AND
// (vacuously true for an empty set of sides), negation is per side for doesNotCommand
bool checkCommands(B)(TrigSideSpec sideSpec,TrigNtts ntts,CheckLocation* location,bool negate,ref TriggerRun run,ref TriggerState!B triggerState,ObjectState!B state){
	auto mask=sideSpecSides(sideSpec,run.side,state);
	foreach(candidate;0..32){
		if(!(mask&(1u<<candidate))) continue;
		NttFilter filter;
		filter.ownerSide=candidate;
		if(location !is null) filter.location=*location;
		bool result=checkNtts(ntts,candidate,&filter,run,triggerState,state);
		if(negate) result=!result;
		if(!result) return false;
	}
	return true;
}

// retail: order comparison compares command type and target (fcomps for positions)
bool ordersMatch(B)(ref Order order,ref Order trigOrder,ObjectState!B state){
	if(order.command!=trigOrder.command) return false;
	if(order.command==CommandType.castSpell&&order.spellTag!=trigOrder.spellTag) return false;
	if(order.target.type!=trigOrder.target.type) return false;
	if(order.target.type==TargetType.terrain){
		auto delta=order.target.position-trigOrder.target.position;
		return delta.lengthsqr<=1e-4f;
	}
	return order.target.id==trigOrder.target.id;
}

bool creatureHasOrders(B)(int id,TrigOrder trigOrderSpec,ref TriggerRun run,ref TriggerState!B triggerState,ObjectState!B state){
	Order trigOrder;
	if(!convertOrder(trigOrderSpec,run.side,trigOrder,run,triggerState,state)) return false;
	return state.movingObjectById!((ref obj,trigOrder,state){
		if(ordersMatch(obj.creatureAI.order,*trigOrder,state)) return true;
		auto queue=&obj.creatureAI.orderQueue;
		foreach(i;queue.first..queue.last){
			if(ordersMatch(queue.payload[i%$],*trigOrder,state)) return true;
		}
		return false;
	},()=>false)(id,&trigOrder,state);
}

// retail: CheckConditions dispatches over the condition blob
bool checkCondition(B)(TrigCondition condition,ref TriggerRun run,ref TriggerState!B triggerState,ObjectState!B state){
	if(cast(TrigAlways)condition) return true;
	if(auto orCondition=cast(TrigOrCondition)condition)
		return checkCondition(orCondition.condition1,run,triggerState,state)||checkCondition(orCondition.condition2,run,triggerState,state);
	if(auto andCondition=cast(TrigAndCondition)condition)
		return checkCondition(andCondition.condition1,run,triggerState,state)&&checkCondition(andCondition.condition2,run,triggerState,state);
	if(auto notCondition=cast(TrigNotCondition)condition)
		return !checkCondition(notCondition.condition,run,triggerState,state);
	if(auto commands=cast(TrigIfSideSpecCommandsNttsCondition)condition)
		return checkCommands(commands.sideSpec,commands.ntts,null,false,run,triggerState,state);
	if(auto commands=cast(TrigIfSideSpecCommandsNttsAtLocationCondition)condition){
		CheckLocation location;
		if(!setupLocation(commands.location,run.side,location,state)) return false;
		return checkCommands(commands.sideSpec,commands.ntts,&location,false,run,triggerState,state);
	}
	if(auto commands=cast(TrigIfSideSpecCommandsNttsWithinMetersOfNttCondition)condition){
		CheckLocation location;
		location.objectId=resolveNtt(commands.ntt,run.side,state);
		if(location.objectId==0) return false;
		location.type=1;
		location.radius=cast(float)evalQuantity(commands.quantity,run,triggerState,state);
		return checkCommands(commands.sideSpec,commands.ntts,&location,false,run,triggerState,state);
	}
	if(auto commands=cast(TrigIfSideSpecDoesNotCommandNttsCondition)condition)
		return checkCommands(commands.sideSpec,commands.ntts,null,true,run,triggerState,state);
	if(auto commands=cast(TrigIfSideSpecDoesNotCommandNttsAtLocationCondition)condition){
		CheckLocation location;
		if(!setupLocation(commands.location,run.side,location,state)) return true; // no such location: nothing commanded there
		return checkCommands(commands.sideSpec,commands.ntts,&location,true,run,triggerState,state);
	}
	if(auto elapsed=cast(TrigIfElapsedGameTimeIsFramesCondition)condition)
		return checkConstraint(elapsed.constraint,triggerState.tick,0,run,triggerState,state);
	if(auto gameTimer=cast(TrigIfGameTimerIsFramesCondition)condition)
		return checkConstraint(gameTimer.constraint,triggerState.gameTimer,0,run,triggerState,state);
	if(auto sees=cast(TrigIfSideSpecSeesNttsCondition)condition){
		auto mask=sideSpecSides(sees.sideSpec,run.side,state);
		foreach(candidate;0..32){
			if(!(mask&(1u<<candidate))) continue;
			NttFilter filter;
			filter.viewerSide=candidate;
			if(!checkNtts(sees.ntts,-1,&filter,run,triggerState,state)) return false;
		}
		return true;
	}
	if(auto sees=cast(TrigIfNttSeesNttsCondition)condition){
		auto viewerId=resolveNtt(sees.ntt,run.side,state);
		if(viewerId==0||state.isValidBuilding(viewerId)) return false;
		NttFilter filter;
		if(!setupViewer(filter,viewerId,state)) return false;
		return checkNtts(sees.ntts,-1,&filter,run,triggerState,state);
	}
	if(auto attacked=cast(TrigIfSideSpecIsAttackedBySideCondition)condition){
		if(attacked.sideId>=32) return false;
		auto mask=sideSpecSides(attacked.sideSpec,run.side,state);
		foreach(candidate;0..32){
			if(!(mask&(1u<<candidate))) continue;
			if(!(triggerState.sideAttackedBySides[candidate]&(1u<<attacked.sideId))) return false;
		}
		return true;
	}
	if(auto attacked=cast(TrigIfCreatureIsAttackedBySideSpecCondition)condition){
		auto id=resolveNtt(attacked.creature,run.side,state);
		if(id==0||state.isValidBuilding(id)) return false;
		auto mask=sideSpecSides(attacked.sideSpec,run.side,state);
		return state.movingObjectById!((ref obj,mask)=>!!(obj.creatureAI.attackedBySides&mask),()=>false)(id,mask);
	}
	if(auto variable=cast(TrigIfVariableCondition)condition)
		return checkConstraint(variable.constraint,getVariable(variable.variable,run,triggerState,state),0,run,triggerState,state);
	if(auto hasResource=cast(TrigIfNttHasResourceCondition)condition){
		int value,maxValue;
		if(!resourceOfNtt(hasResource.resource,hasResource.ntt,run.side,value,maxValue,state)) return false;
		return checkConstraint(hasResource.constraint,value,maxValue,run,triggerState,state);
	}
	if(auto hasStat=cast(TrigIfCreatureHasStatCondition)condition){
		auto id=resolveNtt(hasStat.creature,run.side,state);
		if(id==0||state.isValidBuilding(id)) return false;
		auto value=state.movingObjectById!((ref obj,stat)=>cast(int)creatureStat(obj,stat),()=>0)(id,hasStat.creatureStat);
		return checkConstraint(hasStat.constraint,value,value,run,triggerState,state);
	}
	if(auto selected=cast(TrigIfPlayerHasCreaturesSelectedCondition)condition){
		int playerSide=-1;
		foreach(s;0..cast(int)state.sid.sides.length){
			if(state.sid.sides[s].sideType==SideType.human){ playerSide=s; break; }
		}
		if(playerSide<0) return false;
		foreach(creature;selected.creatures){
			auto id=resolveNtt(creature,run.side,state);
			if(id==0||state.isValidBuilding(id)) return false;
			if(!state.sid.sides[playerSide].selection.has(id)) return false;
		}
		return true;
	}
	if(auto hasOrders=cast(TrigIfCreatureHasOrdersCondition)condition){
		auto id=resolveNtt(hasOrders.creature,run.side,state);
		if(id==0||state.isValidBuilding(id)) return false;
		return creatureHasOrders(id,hasOrders.order,run,triggerState,state);
	}
	if(auto activeValue=cast(TrigIfStructureActiveValueCondition)condition){
		auto id=resolveNtt(activeValue.structure,run.side,state);
		if(id==0||!state.isValidBuilding(id)) return false;
		auto value=state.buildingById!((ref building)=>building.activeValue,()=>0)(id);
		return checkConstraint(activeValue.constraint,value,0,run,triggerState,state);
	}
	if(cast(TrigIfCurrentSideIsAnAiSide)condition){
		if(!(0<=run.side&&run.side<state.sid.sides.length)) return false;
		return state.sid.sides[run.side].sideType==SideType.shinyBot;
	}
	if(cast(TrigIfCurrentSideIsAPlayerSide)condition){
		if(!(0<=run.side&&run.side<state.sid.sides.length)) return false;
		return state.sid.sides[run.side].sideType==SideType.human;
	}
	if(auto exists=cast(TrigIfNttExistsCondition)condition)
		return resolveNtt(exists.ntt,run.side,state)!=0;
	if(auto exists=cast(TrigIfNttExistsOnTheCurrentSideCondition)condition){
		auto id=resolveNtt(exists.ntt,run.side,state);
		if(id==0) return false;
		if(state.isValidBuilding(id))
			return state.buildingById!((ref building,side)=>building.side==side,()=>false)(id,run.side);
		return state.movingObjectById!((ref obj,side)=>obj.side==side,()=>false)(id,run.side);
	}
	if(auto alive=cast(TrigIfCreatureIsAliveCondition)condition){
		auto id=resolveNtt(alive.creature,run.side,state);
		if(id==0||state.isValidBuilding(id)) return false;
		return state.movingObjectById!((ref obj)=>obj.isAlive,()=>false)(id);
	}
	runError(run,text("unsupported condition ",typeid(condition)));
	return false;
}

// mana/health/souls of a creature or wizard (retail: resource codes 130-132)
bool resourceOfNtt(B)(TrigResource resource,TrigNtt ntt,int side,out int value,out int maxValue,ObjectState!B state){
	value=maxValue=0;
	auto id=resolveNtt(ntt,side,state);
	if(id==0||state.isValidBuilding(id)) return false;
	final switch(resource) with(TrigResource){
		case mana:
			return state.movingObjectById!((ref obj,value,maxValue){
				*value=cast(int)obj.creatureStats.mana;
				*maxValue=cast(int)obj.creatureStats.maxMana;
				return true;
			},()=>false)(id,&value,&maxValue);
		case health:
			return state.movingObjectById!((ref obj,value,maxValue){
				*value=cast(int)obj.creatureStats.health;
				*maxValue=cast(int)obj.creatureStats.maxHealth;
				return true;
			},()=>false)(id,&value,&maxValue);
		case souls:
			return state.movingObjectById!((ref obj,value,state){
				if(obj.isWizard){
					if(auto wiz=state.getWizardForSide(obj.side)) *value=wiz.souls;
				}else *value=obj.creatureStats.souls;
				return true;
			},()=>false)(id,&value,state);
	}
}

// order conversion. retail: ConvertOrder (action 147 returns its result).
// notification orders have no sacengine analog and fail conversion without erroring the run.
bool convertOrder(B)(TrigOrder trigOrder,int side,out Order order,ref TriggerRun run,ref TriggerState!B triggerState,ObjectState!B state){
	order=Order.init;
	if(auto attack=cast(TrigOrderAttack)trigOrder){
		auto id=resolveNtt(attack.target,side,state);
		if(id==0) return false;
		Vector3f position;
		objectPosition(id,position,state);
		auto type=state.isValidBuilding(id)?TargetType.building:TargetType.creature;
		order=Order(CommandType.attack,OrderTarget(type,id,position));
		return true;
	}
	if(auto castOrder=cast(TrigOrderCast)trigOrder){
		auto spec=castOrder.spellSpec;
		char[4] spellTag;
		OrderTarget target;
		if(auto atNtt=cast(TrigSpellAtNtt)spec){
			spellTag=atNtt.tag;
			auto id=resolveNttId(atNtt.ntt,side,false,state);
			if(id==0) id=resolveNttId(atNtt.ntt,side,true,state);
			if(id==0) return false;
			target=centerTarget(id,state);
		}else if(auto atSoul=cast(TrigSpellAtSoulOfNtt)spec){
			spellTag=atSoul.tag;
			auto creatureId=resolveNttId(atSoul.ntt,side,false,state);
			if(creatureId==0) return false;
			auto soulId=state.movingObjectById!((ref obj)=>obj.soulId,()=>0)(creatureId);
			if(soulId==0||!state.isValidTarget(soulId,TargetType.soul)) return false;
			auto position=state.soulById!((ref soul)=>soul.center,()=>Vector3f.init)(soulId);
			target=OrderTarget(TargetType.soul,soulId,position);
		}else if(auto atLocation=cast(TrigSpellAtLocation)spec){
			spellTag=atLocation.tag;
			if(auto atNtt=cast(TrigAtNtt)atLocation.location){
				auto id=resolveNtt(atNtt.ntt,side,state);
				if(id==0) return false;
				target=centerTarget(id,state);
			}else{
				Vector3f position;
				if(!locationPosition(atLocation.location,side,position,state)) return false;
				target=OrderTarget(TargetType.terrain,0,position);
			}
		}else if(auto spell=cast(TrigSpell)spec){
			spellTag=spell.tag;
		}else if(auto spell=cast(TrigCreatureSpell)spec){
			spellTag=spell.tag;
		}else return false;
		order=Order(CommandType.castSpell,target);
		order.spellTag=spellTag;
		return true;
	}
	if(auto turn=cast(TrigOrderTurnToFaceLocation)trigOrder){
		Vector3f position;
		if(!locationPosition(turn.location,side,position,state)) return false;
		if(auto atNtt=cast(TrigAtNtt)turn.location){
			auto id=resolveNtt(atNtt.ntt,side,state);
			if(id==0) return false;
			auto type=state.isValidBuilding(id)?TargetType.building:TargetType.creature;
			order=Order(CommandType.turnToFace,OrderTarget(type,id,position),float.init);
		}else order=Order(CommandType.turnToFace,OrderTarget(TargetType.terrain,0,position),float.init);
		return true;
	}
	CommandType command;
	TrigLocation location;
	if(auto goTo=cast(TrigOrderGoToLocation)trigOrder){ command=CommandType.move; location=goTo.location; }
	else if(auto attackLocation=cast(TrigOrderAttackLocation)trigOrder){ command=CommandType.attack; location=attackLocation.location; }
	else if(auto guardLocation=cast(TrigOrderGuardLocation)trigOrder){ command=CommandType.retreat; location=guardLocation.location; }
	// formation orders: the formation is not represented per-order in sacengine, otherwise identical
	else if(auto goTo=cast(TrigOrderGoToLocationInFormation)trigOrder){ command=CommandType.move; location=goTo.location; }
	else if(auto attackLocation=cast(TrigOrderAttackLocationInFormation)trigOrder){ command=CommandType.attack; location=attackLocation.location; }
	else if(auto guardLocation=cast(TrigOrderGuardLocationInFormation)trigOrder){ command=CommandType.retreat; location=guardLocation.location; }
	else return false; // notify/passive notify orders: unsupported (see above)
	Vector3f position;
	if(!locationPosition(location,side,position,state)) return false;
	if(auto atNtt=cast(TrigAtNtt)location){
		auto id=resolveNtt(atNtt.ntt,side,state);
		if(id==0) return false;
		auto type=state.isValidBuilding(id)?TargetType.building:TargetType.creature;
		order=Order(command,OrderTarget(type,id,position));
	}else{
		if(command==CommandType.retreat) command=CommandType.guardArea;
		order=Order(command,OrderTarget(TargetType.terrain,0,position));
	}
	return true;
}

void setPassiveNotify(B)(ref MovingObject!B obj){
	obj.notificationState.passiveNotify=true;
	// Familiars retain the talking cursor, but do not display the peasant-style red alert.
	obj.notificationState.passiveAlert=!obj.isFamiliar;
}

void clearPassiveNotify(B)(ref MovingObject!B obj){
	obj.notificationState.passiveNotify=false;
	obj.notificationState.passiveAlert=false;
}

// issues a trigger order to a single creature. returns false if the order could not be converted.
bool issueOrder(B)(ref MovingObject!B obj,TrigOrder trigOrder,ref TriggerRun run,ref TriggerState!B triggerState,ObjectState!B state){
	if(cast(TrigOrderPassiveNotify)trigOrder){
		obj.setPassiveNotify();
		return true;
	}
	if(auto notify=cast(TrigOrderNotify)trigOrder){
		auto id=resolveNtt(notify.creature,run.side,state);
		if(id==0||state.isValidBuilding(id)) return false;
		state.movingObjectById!((ref target){ target.setPassiveNotify(); },(){})(id);
		return true;
	}
	if(cast(TrigOrderCancelOrders)trigOrder){
		obj.clearPassiveNotify();
		obj.clearOrderQueue(state);
		return true;
	}
	if(cast(TrigOrderDie)trigOrder){
		if(obj.isAlive) obj.kill(state);
		return true;
	}
	Order order;
	if(!convertOrder(trigOrder,run.side,order,run,triggerState,state)) return false;
	// The retail internal-order constructor captures this heading at issuance.
	order.targetFacing=obj.facingTowards(order.target.position,state);
	if(order.command==CommandType.castSpell) obj.prequeueTriggerCastOrder(order,state,obj.side);
	else obj.order(order,state,obj.side);
	return true;
}

// issues a trigger order to a single creature. returns false if the order could not be converted.
bool issueOrder(B)(int id,TrigOrder trigOrder,ref TriggerRun run,ref TriggerState!B triggerState,ObjectState!B state){
	return state.movingObjectById!((ref obj,trigOrder,run,triggerState,state){
		return issueOrder(obj,trigOrder,*run,*triggerState,state);
	},()=>false)(id,trigOrder,&run,&triggerState,state);
}

// retail: charm-style side change (clear orders, unselect, remove from groups)
void changeSideOfObject(B)(int id,int side,ObjectState!B state){
	if(!(0<=side&&side<32)) return;
	if(state.isValidBuilding(id)){
		state.buildingById!((ref building,side){ building.side=side; },(){})(id,side);
		return;
	}
	state.movingObjectById!((ref obj,side,state){
		obj.clearOrderQueue(state);
		obj.unselect(state);
		obj.removeFromGroups(state);
		obj.side=side;
		state.botSideChanged(obj);
	},(){})(id,side,state);
}

void giveResource(B)(TrigResource resource,int amount,int id,ObjectState!B state){
	if(state.isValidBuilding(id)) return;
	state.movingObjectById!((ref obj,resource,amount,state){
		final switch(resource) with(TrigResource){
			case mana:
				obj.creatureStats.mana=min(max(obj.creatureStats.mana+amount,0.0f),obj.creatureStats.maxMana);
				break;
			case health:
				obj.creatureStats.health=min(max(obj.creatureStats.health+amount,0.0f),obj.creatureStats.maxHealth);
				break;
			case souls:
				if(obj.isWizard){
					if(auto wiz=state.getWizardForSide(obj.side)) wiz.souls=max(0,wiz.souls+amount);
				}else obj.creatureStats.souls=max(0,obj.creatureStats.souls+amount);
				break;
		}
	},(){})(id,resource,amount,state);
}

// retail: setNttState maps to the ntt flag bits (ntts.d Flags);
// walking/collectsRedSouls have no sacengine analog and are ignored
uint nttStateFlag(TrigNttState nttState){
	final switch(nttState) with(TrigNttState){
		case rescuable: return Flags.rescuable;
		case damaged: return Flags.damaged;
		case destroyed: return Flags.destroyed;
		case cannotGib: return Flags.cannotGib;
		case cannotDamage: return Flags.cannotDamage;
		case cannotDestroy: return Flags.cannotDestroyKill;
		case walking,collectsRedSouls: return 0u;
		case notOnMinimap: return Flags.notOnMinimap;
	}
}

void setNttStateOnObject(B)(int id,TrigNttState nttState,bool on,ObjectState!B state){
	auto flag=nttStateFlag(nttState);
	if(flag==0) return;
	if(state.isValidBuilding(id)){
		state.buildingById!((ref building,flag,on){
			if(on) building.flags|=flag;
			else building.flags&=~flag;
		},(){})(id,flag,on);
		return;
	}
	state.movingObjectById!((ref obj,flag,on){
		if(on) obj.creatureStats.flags|=flag;
		else obj.creatureStats.flags&=~flag;
	},(){})(id,flag,on);
}

// spawn a creature for the create actions, modeled on placeNTT
int spawnCreature(B)(char[4] ctype,int side,Vector3f position,ObjectState!B state){
	if(!(0<=side&&side<32)) side=neutralSide;
	auto sacObject=SacObject!B.getSAXS!Creature(ctype);
	if(sacObject is null) return 0;
	if(!state.isOnGround(position)) return 0;
	position.z=state.getGroundHeight(position);
	return state.placeCreature(sacObject,0,side,position,0.0f);
}

string triggerResourceFilename(char[4] tag){
	char[4] name=tag;
	reverse(cast(ubyte[])name[]);
	return normalizeFilename(name[].idup);
}
string genericTriggerText(char[4] tag,string mapFolder,string resourceFolder){
	auto filename=buildPath(mapFolder,"ENGL.LANG",resourceFolder,triggerResourceFilename(tag)~".TEXT");
	if(fileExists(filename)) return loadText(filename);
	return texts.get(tag,"");
}
string genericSpeechText(char[4] tag,string mapFolder){
	return genericTriggerText(tag,mapFolder,"TRIG.FLDR");
}
string genericSpeechSample(char[4] tag,string mapFolder){
	auto filename=buildPath(mapFolder,"SAMP.FLDR",triggerResourceFilename(tag)~".SAMP");
	if(fileExists(filename)) return filename;
	return samps.get(tag,null);
}
int genericSpeechSampleDuration(string filename){
	if(!filename.length) return 0;
	auto samp=loadSAMP(filename);
	return sampDuration(samp,updateFPS);
}

// retail: timed generic speech freezes its trigger run for an integer frame duration.
// An unresolved sample is null in retail, so auto timing falls back to the text length.
// Persistent and input-driven speech are released by clear-text or validated trigger responses.
int genericSpeechDuration(B)(TrigSpeechWithTextAction speech,ref TriggerRun run,ref TriggerState!B triggerState,ObjectState!B state){
	if(auto forFrames=cast(TrigForFrames)speech.timing)
		return max(0,evalQuantity(forFrames.quantity,run,triggerState,state));
	int subtract=0;
	if(auto sampleMinus=cast(TrigSampleLengthMinusFrames)speech.timing)
		subtract=evalQuantity(sampleMinus.quantity,run,triggerState,state);
	else if(!cast(TrigAutoTimed)speech.timing) return -1;
	int duration=-1;
	if(auto withSample=cast(TrigWithSample)speech.sampleSpec){
		auto filename=genericSpeechSample(withSample.sample,state.map.mapFolder);
		if(filename) duration=genericSpeechSampleDuration(filename);
	}
	if(duration<0) duration=6*cast(int)(genericSpeechText(speech.text,state.map.mapFolder).length+10);
	return max(0,duration-subtract);
}

bool triggerTextAvailable(char[4] tag,string mapFolder){
	auto filename=buildPath(mapFolder,"ENGL.LANG","TRIG.FLDR",triggerResourceFilename(tag)~".TEXT");
	return fileExists(filename)||(tag in texts)!is null;
}

bool triggerSampleAvailable(char[4] tag,string mapFolder){
	return genericSpeechSample(tag,mapFolder).length!=0;
}

int triggerSpeechEmotion(TrigSpeaks speaks){
	if(auto withEmotion=cast(TrigSaysWithEmotion)speaks) return cast(int)withEmotion.emotion;
	if(auto withEmotion=cast(TrigAsksWithEmotion)speaks) return cast(int)withEmotion.emotion;
	if(auto withEmotion=cast(TrigExclaimsWithEmotion)speaks) return cast(int)withEmotion.emotion;
	return 0;
}

char[4] triggerSampleSpecTag(TrigSampleSpec sampleSpec){
	if(auto withSample=cast(TrigWithSample)sampleSpec) return withSample.sample;
	return (char[4]).init;
}

int automaticSpeechDuration(B)(char[4] text,char[4] sample,ObjectState!B state){
	auto filename=genericSpeechSample(sample,state.map.mapFolder);
	if(filename.length) return genericSpeechSampleDuration(filename);
	return 6*cast(int)(genericSpeechText(text,state.map.mapFolder).length+10);
}

bool startCreatureSpeech(B)(TrigCreature creature,char[4] text,char[4] sample,bool needsText,TriggerSpeechKind kind,int emotion,ref TriggerRun run,ref TriggerState!B triggerState,ObjectState!B state){
	auto target=resolveNtt(creature,run.side,state);
	if(target==0||state.isValidBuilding(target)) return true; // unresolved creature: successful no-op
	if(needsText&&!triggerTextAvailable(text,state.map.mapFolder)) return false;
	if(!triggerSampleAvailable(sample,state.map.mapFolder)) return false;
	TriggerSpeech speech;
	speech.side=run.side;
	speech.runId=run.id;
	speech.target=target;
	speech.text=text;
	speech.sample=sample;
	speech.kind=kind;
	speech.emotion=emotion;
	speech.duration=automaticSpeechDuration(text,sample,state);
	// Retail clears passive talk state when creature speech starts (Sacrifice.exe 0x479ee2).
	state.movingObjectById!((ref target){ target.clearPassiveNotify(); },(){})(target);
	addTriggerSpeech(run,triggerState,speech);
	return true;
}

bool startAttachedSpeech(B)(TriggerSpeech speech,char[4] text,char[4] sample,ref TriggerRun run,ref TriggerState!B triggerState,ObjectState!B state){
	if(!triggerTextAvailable(text,state.map.mapFolder)||!triggerSampleAvailable(sample,state.map.mapFolder)) return false;
	speech.side=run.side;
	speech.runId=run.id;
	speech.text=text;
	speech.sample=sample;
	speech.duration=automaticSpeechDuration(text,sample,state);
	addTriggerSpeech(run,triggerState,speech);
	return true;
}

bool cameraLocationPosition(B)(TrigLocation location,int side,out Vector3f position,out int target,ObjectState!B state){
	position=Vector3f(0.0f,0.0f,0.0f);
	target=0;
	if(auto atNtt=cast(TrigAtNtt)location){
		target=resolveNtt(atNtt.ntt,side,state);
		return target!=0&&objectPosition(target,position,state);
	}
	uint markerId;
	uint height=0;
	if(auto marker=cast(TrigMarker)location) markerId=marker.id;
	else if(auto markerAtHeight=cast(TrigMarkerAtHeight)location){
		markerId=markerAtHeight.id;
		height=markerAtHeight.height;
	}else return false;
	auto marker=state.triggers.findMarker(cast(int)markerId);
	if(marker is null) return false;
	position=marker.position;
	position.z+=height;
	return true;
}

void setTriggerCameraOrigin(B)(TrigLocation location,ref TriggerRun run,ref TriggerState!B triggerState,ObjectState!B state){
	Vector3f position;
	int target;
	if(!cameraLocationPosition(location,run.side,position,target,state)) return;
	triggerState.camera.active=true;
	triggerState.camera.originValid=true;
	triggerState.camera.originEnd=position;
	triggerState.camera.originTarget=target;
	triggerState.camera.originStartTick=triggerState.tick;
	triggerState.camera.originDuration=max(0,run.locals[7]);
	++triggerState.camera.revision;
}

void setTriggerCameraFocus(B)(TrigLocation location,ref TriggerRun run,ref TriggerState!B triggerState,ObjectState!B state){
	Vector3f position;
	int target;
	if(!cameraLocationPosition(location,run.side,position,target,state)) return;
	triggerState.camera.active=true;
	triggerState.camera.focusValid=true;
	triggerState.camera.focusEnd=position;
	triggerState.camera.focusTarget=target;
	triggerState.camera.focusStartTick=triggerState.tick;
	triggerState.camera.focusDuration=max(0,run.locals[7]);
	++triggerState.camera.revision;
}

void startTriggerAsk(B)(char[4] question,TrigSampleSpec sampleSpec,char[4] optionA,char[4] optionB,uint variable,ref TriggerRun run,ref TriggerState!B triggerState,ObjectState!B state){
	if(variable>=state.triggers.variableOffsets.length){
		runError(run,text("ask: invalid variable ",variable));
		return;
	}
	TriggerAsk ask;
	ask.runId=run.id;
	ask.side=run.side;
	ask.variable=variable;
	ask.question=question;
	ask.optionA=optionA;
	ask.optionB=optionB;
	triggerState.asks~=ask;
	run.flags|=TriggerRunFlags.frozen;
	run.waitKind=TriggerRunWait.ask;
	run.waitId=run.id;
	run.wakeTick=int.max;
	auto sample=triggerSampleSpecTag(sampleSpec);
	if(sample!="\0\0\0\0"&&triggerSampleAvailable(sample,state.map.mapFolder))
		addTriggerAudioEvent(triggerState,run.side,sample,genericSpeechSampleDuration(genericSpeechSample(sample,state.map.mapFolder)));
}

void showTriggerTip(B)(char[4] text,ref TriggerRun run,ref TriggerState!B triggerState){
	if(triggerState.tipboxSuppressed||!(0<=run.side&&run.side<32)) return;
	triggerState.tips[run.side].active=true;
	triggerState.tips[run.side].text=text;
	triggerState.tips[run.side].startTick=triggerState.tick;
	triggerState.tips[run.side].duration=0; // local dismissal; no deterministic trigger wait
}

// return values follow retail RunAction (selectors 0x47b0ec, handlers 0x47afc4):
// - true (chain into the next action on the same tick): game timer 95-97, cinematics 109/110,
//   view zoom 121, view speed 141, suppress tipbox 255 (always);
//   setVariable 57, resource of ntt 196, random in range 162, display/hide variable 61/72,
//   objectives 76-78, setNttState 153, next mission 171/172, interface element 198 (on success)
// - orderList 147: order conversion result
// - create actions 56/80/142: creation result
// - all other actions: false (the run continues with the next action on the next tick)
bool runAction(B)(TrigAction action,ref TriggerRun run,ref TriggerState!B triggerState,ObjectState!B state){
	if(auto pause=cast(TrigPauseAction)action){
		setTimer(run,triggerState,cast(int)pause.numFrames);
		return false;
	}
	if(cast(TrigEndMissionInDefeatAction)action){ state.defeat(run.side); return false; }
	if(cast(TrigEndMissionInVictoryAction)action){ state.victory(run.side); return false; }
	if(cast(TrigEndMissionAction)action){ state.victory(run.side); return false; }
	if(auto declare=cast(TrigDeclareStanceToSideAction)action){
		if(declare.side<32&&0<=run.side&&run.side<state.sid.sides.length){
			final switch(declare.stance) with(TrigStance){
				case hostile: state.setStance(run.side,cast(int)declare.side,Stance.enemy); break;
				case friendly: state.setStance(run.side,cast(int)declare.side,Stance.ally); break;
				case neutral: state.setStance(run.side,cast(int)declare.side,Stance.neutral); break;
			}
		}
		return false;
	}
	if(auto changeSide=cast(TrigChangeSideAction)action){
		auto id=resolveNtt(changeSide.ntt,run.side,state);
		if(id==0) runError(run,text("change side: cannot resolve ",changeSide.ntt));
		else changeSideOfObject(id,cast(int)changeSide.side,state);
		return false;
	}
	if(auto changeSide=cast(TrigChangeSideAllOfTypeAction)action){
		changeSideAllOfType(changeSide.nttType,null,cast(int)changeSide.side,state);
		return false;
	}
	if(auto changeSide=cast(TrigChangeSideAllOfTypeAtLocationAction)action){
		NttFilter filter;
		if(setupLocation(changeSide.location,run.side,filter.location,state))
			changeSideAllOfType(changeSide.nttType,&filter,cast(int)changeSide.side,state);
		return false;
	}
	if(auto orderAction=cast(TrigOrderAction)action){
		auto id=resolveNtt(orderAction.creature,run.side,state);
		if(id==0||state.isValidBuilding(id)) runError(run,text("order: cannot resolve creature ",orderAction.creature.id));
		else issueOrder(id,orderAction.order,run,triggerState,state);
		return false;
	}
	if(auto orderList=cast(TrigOrderListAction)action){
		auto convertible=orderConvertible(orderList.order,run,triggerState,state);
		foreach(creature;orderList.creatures){
			auto id=resolveNtt(creature,run.side,state);
			if(id==0||state.isValidBuilding(id)) continue;
			issueOrder(id,orderList.order,run,triggerState,state);
		}
		return convertible;
	}
	if(auto orderAll=cast(TrigOrderAllOfTypeAction)action){
		orderAllOfType(orderAll.ctype,null,orderAll.order,run,triggerState,state);
		return false;
	}
	if(auto orderAll=cast(TrigOrderAllOfTypeAtLocationAction)action){
		NttFilter filter;
		if(setupLocation(orderAll.location,run.side,filter.location,state))
			orderAllOfType(orderAll.ctype,&filter,orderAll.order,run,triggerState,state);
		return false;
	}
	if(auto display=cast(TrigDisplayVariableAction)action){
		if(display.variable>=state.triggers.variableOffsets.length){
			runError(run,text("display variable: invalid variable ",display.variable));
			return true;
		}
		triggerState.variableDisplayFlags[display.variable]=1;
		return true;
	}
	if(auto display=cast(TrigDisplayTextAction)action){
		// Retail resolves the resource and discards it; it does not create a visible display.
		genericSpeechText(display.text,state.map.mapFolder);
		return false;
	}
	if(auto hide=cast(TrigHideVariableAction)action){
		if(hide.variable>=state.triggers.variableOffsets.length){
			runError(run,text("hide variable: invalid variable ",hide.variable));
			return true;
		}
		triggerState.variableDisplayFlags[hide.variable]=0;
		return true;
	}
	if(cast(TrigClearTextAction)action){ clearTriggerSpeeches(triggerState); return false; }
	if(auto sample=cast(TrigPlaySampleAction)action){
		auto filename=genericSpeechSample(sample.sample,state.map.mapFolder);
		if(filename.length) addTriggerAudioEvent(triggerState,run.side,sample.sample,genericSpeechSampleDuration(filename));
		return false;
	}
	if(auto create=cast(TrigCreateCreatureTypeAtLocationAction)action){
		Vector3f position;
		if(!locationPosition(create.location,run.side,position,state)) return false;
		return spawnCreature(create.ctype,neutralSide,position,state)!=0;
	}
	if(auto create=cast(TrigCreateCreatureTypeOnSideAtLocationAction)action){
		Vector3f position;
		if(!locationPosition(create.location,run.side,position,state)) return false;
		return spawnCreature(create.ctype,cast(int)create.side,position,state)!=0;
	}
	if(auto create=cast(TrigCreateMultipleCreatureTypeOnSideAtLocationAction)action){
		Vector3f position;
		if(!locationPosition(create.location,run.side,position,state)) return false;
		bool ok=false;
		foreach(i;0..create.amount)
			ok|=spawnCreature(create.ctype,cast(int)create.side,position,state)!=0;
		return ok;
	}
	if(auto setVar=cast(TrigSetVariableAction)action){
		auto value=evalQuantity(setVar.quantity,run,triggerState,state);
		setVariable(setVar.variable,value,run,triggerState,state);
		return true;
	}
	if(auto setVar=cast(TrigSetVariableToNumberOfNttsAction)action){
		setVariable(setVar.variable,countQuantifiedNtts(setVar.quantifiedNtts,run.side,run,triggerState,state),run,triggerState,state);
		return false;
	}
	if(auto setVar=cast(TrigSetVariableToResourceOfNttAction)action){
		int value,maxValue;
		if(!resourceOfNtt(setVar.resource,setVar.ntt,run.side,value,maxValue,state)){
			runError(run,text("set variable to resource: cannot resolve ntt"));
			return true;
		}
		setVariable(setVar.variable,value,run,triggerState,state);
		return true;
	}
	if(auto setVar=cast(TrigSetVariableToResourceOfNttsAction)action){
		setVariable(setVar.variable,resourceOfQuantifiedNtts(setVar.resource,setVar.quantifiedNtts,run.side,run,triggerState,state),run,triggerState,state);
		return false;
	}
	if(auto setVar=cast(TrigSetVariableToRandomNumberInRangeAction)action){
		auto low=evalQuantity(setVar.low,run,triggerState,state);
		auto high=evalQuantity(setVar.high,run,triggerState,state);
		if(high<low) swap(low,high);
		setVariable(setVar.variable,low+state.uniform(max(1,high-low+1)),run,triggerState,state);
		return true;
	}
	if(auto speechAction=cast(TrigSpeechWithTextAction)action){
		TriggerSpeech speech;
		speech.side=run.side;
		speech.text=speechAction.text;
		speech.sample=triggerSampleSpecTag(speechAction.sampleSpec);
		speech.emotion=triggerSpeechEmotion(speechAction.speaks);
		speech.duration=genericSpeechDuration(speechAction,run,triggerState,state);
		speech.pauseForInput=cast(TrigPauseForInput)speechAction.timing!is null;
		if(auto actor=cast(TrigActorCreature)speechAction.actor){
			speech.kind=TriggerSpeechKind.creature;
			speech.target=resolveNtt(actor.creature,run.side,state);
			if(state.isValidBuilding(speech.target)) speech.target=0;
			// Retail falls back to independent speech when the creature cannot be resolved.
			if(speech.target!=0){
				speech.runId=run.id;
				state.movingObjectById!((ref target){ target.clearPassiveNotify(); },(){})(speech.target);
			}
		}else if(auto actor=cast(TrigActorNameText)speechAction.actor){
			speech.kind=TriggerSpeechKind.named;
			speech.runId=run.id;
			speech.speakerName=actor.text;
		}else if(cast(TrigActorNamePlayerWizard)speechAction.actor){
			speech.kind=TriggerSpeechKind.named;
			speech.runId=run.id;
			speech.actor=1; // renderer resolves the current side's wizard name
		}else if(auto actor=cast(TrigActorGod)speechAction.actor){
			speech.kind=TriggerSpeechKind.god;
			speech.actor=cast(int)actor.god;
			speech.runId=run.id;
		}else{
			runError(run,text("speech: unsupported actor ",typeid(speechAction.actor)));
			return false;
		}
		addTriggerSpeech(run,triggerState,speech);
		return false;
	}
	if(auto speech=cast(TrigSpeechCreatureSpeaksSampleAction)action){
		char[4] noText=0;
		startCreatureSpeech(speech.creature,noText,speech.sample,false,TriggerSpeechKind.sampleOnly,triggerSpeechEmotion(speech.speaks),run,triggerState,state);
		return false;
	}
	if(auto speech=cast(TrigSpeechCreatureSaysTextWithSampleAction)action)
		return startCreatureSpeech(speech.creature,speech.text,speech.sample,true,TriggerSpeechKind.creature,0,run,triggerState,state);
	if(auto speech=cast(TrigSpeechCreatureAsksTextWithSampleAction)action)
		return startCreatureSpeech(speech.creature,speech.text,speech.sample,true,TriggerSpeechKind.creature,0,run,triggerState,state);
	if(auto speech=cast(TrigSpeechCreatureExclaimsTextWithSampleAction)action)
		return startCreatureSpeech(speech.creature,speech.text,speech.sample,true,TriggerSpeechKind.creature,0,run,triggerState,state);
	if(auto speechAction=cast(TrigSpeechGodSaysTextWithSampleAction)action){
		TriggerSpeech speech;
		speech.kind=TriggerSpeechKind.god;
		speech.actor=cast(int)speechAction.god;
		startAttachedSpeech(speech,speechAction.text,speechAction.sample,run,triggerState,state);
		return false;
	}
	if(auto speechAction=cast(TrigSpeechNarratorNarratesTextWithSampleAction)action){
		TriggerSpeech speech;
		speech.kind=TriggerSpeechKind.narrator;
		speech.actor=cast(int)speechAction.narrator;
		startAttachedSpeech(speech,speechAction.text,speechAction.sample,run,triggerState,state);
		return false;
	}
	if(auto objective=cast(TrigSetObjectiveCompleteAction)action){
		if(objective.missionObjective>=triggerState.objectiveFlags.length){
			runError(run,text("set objective complete: invalid objective ",objective.missionObjective));
			return true;
		}
		triggerState.objectiveFlags[objective.missionObjective]|=2;
		return true;
	}
	if(auto objective=cast(TrigEnableObjectiveAction)action){
		if(objective.missionObjective>=triggerState.objectiveFlags.length){
			runError(run,text("enable objective: invalid objective ",objective.missionObjective));
			return true;
		}
		triggerState.objectiveFlags[objective.missionObjective]|=1;
		return true;
	}
	if(auto objective=cast(TrigDisableObjectiveAction)action){
		if(objective.missionObjective>=triggerState.objectiveFlags.length){
			runError(run,text("disable objective: invalid objective ",objective.missionObjective));
			return true;
		}
		triggerState.objectiveFlags[objective.missionObjective]&=~1;
		return true;
	}
	if(auto teleport=cast(TrigTeleportAllOfTypeAtLocationToLocationAction)action){
		Vector3f target;
		NttFilter filter;
		if(locationPosition(teleport.location2,run.side,target,state)&&setupLocation(teleport.location1,run.side,filter.location,state))
			teleportAllOfType(teleport.ctype,&filter,target,state);
		return false;
	}
	// teleport "away" has unclear semantics in retail (0x43a20/0x4ea80), ported as a no-op
	if(cast(TrigTeleportAllOfTypeAtLocationAwayAction)action) return false;
	if(auto teleport=cast(TrigTeleportCreatureToLocationAction)action){
		auto id=resolveNtt(teleport.creature,run.side,state);
		Vector3f target;
		if(id==0||state.isValidBuilding(id)) runError(run,text("teleport: cannot resolve creature ",teleport.creature.id));
		else if(locationPosition(teleport.location,run.side,target,state))
			state.movingObjectById!((ref obj,target,state){ .teleport(obj,target,state,false,false); },(){})(id,target,state);
		return false;
	}
	if(cast(TrigTeleportCreatureAwayAction)action) return false; // see above
	if(auto timer=cast(TrigSetGameTimerAction)action){
		triggerState.gameTimer=evalQuantity(timer.quantity,run,triggerState,state);
		return true;
	}
	if(cast(TrigDisplayGameTimerAction)action){ triggerState.gameTimerVisible=true; return true; }
	if(cast(TrigHideGameTimerAction)action){ triggerState.gameTimerVisible=false; return true; }
	// AI settings (pause/unpause/aggression) apply to the retail AI; the shiny bots do not consume them
	if(cast(TrigSetAiSetting)action) return false;
	if(auto beacon=cast(TrigTurnBeaconAtLocationAction)action){
		if(auto atNtt=cast(TrigAtNtt)beacon.location){
			auto target=resolveNtt(atNtt.ntt,run.side,state);
			if(target) setTriggerBeacon(run.side,target,beacon.beaconSetting==TrigSwitch.on,state);
		}
		return false;
	}
	if(cast(TrigCinematicsStartAction)action){
		if(triggerState.cinematics) return true;
		triggerState.cinematics=true;
		triggerState.camera.active=true;
		++triggerState.camera.revision;
		return true;
	}
	if(cast(TrigCinematicsEndAction)action){
		if(!triggerState.cinematics) return true;
		triggerState.cinematics=false;
		triggerState.camera.active=false;
		triggerState.camera.originValid=false;
		triggerState.camera.focusValid=false;
		++triggerState.camera.revision;
		return true;
	}
	if(auto view=cast(TrigSetViewFocusToLocationAction)action){
		setTriggerCameraFocus(view.location,run,triggerState,state);
		return false;
	}
	if(auto view=cast(TrigSetViewOriginFromLocationAction)action){
		setTriggerCameraOrigin(view.location,run,triggerState,state);
		return false;
	}
	if(auto view=cast(TrigSetViewOriginFromLocationFocusToLocationAction)action){
		setTriggerCameraOrigin(view.location1,run,triggerState,state);
		setTriggerCameraFocus(view.location2,run,triggerState,state);
		return false;
	}
	if(auto view=cast(TrigSetViewZoomAction)action){
		final switch(view.zoomLevel) with(TrigZoomLevel){
			case closest: triggerState.camera.zoom=0.0f; break;
			case close: triggerState.camera.zoom=0.25f; break;
			case medium: triggerState.camera.zoom=0.5f; break;
			case far: triggerState.camera.zoom=0.75f; break;
			case farthest: triggerState.camera.zoom=1.0f; break;
		}
		++triggerState.camera.zoomRevision;
		return true;
	}
	if(auto view=cast(TrigSetViewSpeedAction)action){
		run.locals[7]=evalQuantity(view.quantity,run,triggerState,state);
		return true;
	}
	if(auto give=cast(TrigGiveCreatureResourceAction)action){
		auto id=resolveNtt(give.creature,run.side,state);
		if(id==0) runError(run,text("give resource: cannot resolve creature ",give.creature.id));
		else giveResource(give.resource,evalQuantity(give.quantity,run,triggerState,state),id,state);
		return false;
	}
	if(auto give=cast(TrigGiveAllOfTypeAtLocationResourceAction)action){
		NttFilter filter;
		if(setupLocation(give.location,run.side,filter.location,state))
			giveResourceAllOfType(give.ctype,&filter,give.resource,evalQuantity(give.quantity,run,triggerState,state),state);
		return false;
	}
	if(auto give=cast(TrigGiveWizardSpellAction)action){
		auto id=resolveNtt(give.wizard,run.side,state);
		if(id==0||state.isValidBuilding(id)) runError(run,text("give spell: cannot resolve wizard ",give.wizard.id));
		else if(auto wiz=state.getWizard(id))
			wiz.spellbook.grantSpell(0,SacSpell!B.get(give.spell));
		return false;
	}
	// Retail casts at the game level without a caster wizard (Sacrifice.exe 0x453600): the spell
	// instance targets the location's object and runs the spell's proc. The utility procs that
	// appear in campaign triggers are emulated directly; all except LifeShieldRun only spawn
	// presentation effects and do nothing without a target object (retail finishes the proc).
	if(auto castAction=cast(TrigCastSpellAtLocationAction)action){
		if(auto spel=castAction.spell in spels){
			auto procLength=spel.proc1[].countUntil('\0');
			auto proc1=spel.proc1[0..procLength<0?spel.proc1.length:procLength];
			auto id=0;
			if(auto atNtt=cast(TrigAtNtt)castAction.location)
				id=resolveNtt(atNtt.ntt,run.side,state);
			if(id!=0) state.movingObjectById!((ref obj,proc1,spellTag,state){
				switch(proc1){
					case "LifeShieldRun":
						obj.lifeShield(SacSpell!B.get(spellTag),state);
						break;
					case "TeleportOutProc":
						animateTeleport(true,obj.hitbox,state,false);
						break;
					case "TeleportInProc":
						animateTeleport(false,obj.hitbox,state,false);
						break;
					case "BoonRun": // TODO: render the actual boon beam for the spell duration
						obj.levelUpEffect(state);
						break;
					default: break;
				}
			},(){})(id,proc1,castAction.spell,state);
		}
		return false;
	}
	if(auto setState=cast(TrigSetNttStateAction)action){
		auto id=resolveNtt(setState.ntt,run.side,state);
		if(id==0) runError(run,text("set ntt state: cannot resolve ntt"));
		else setNttStateOnObject(id,setState.state,setState.switch_==TrigSwitch.on,state);
		return true; // retail: always returns 1 (errors when the ntt is null)
	}
	if(auto setState=cast(TrigSetAllOfTypeStateAction)action){
		setStateAllOfType(setState.nttType,null,setState.state,setState.switch_==TrigSwitch.on,state);
		return false;
	}
	if(auto setState=cast(TrigSetAllOfTypeAtLocationStateAction)action){
		NttFilter filter;
		if(setupLocation(setState.location,run.side,filter.location,state))
			setStateAllOfType(setState.nttType,&filter,setState.state,setState.switch_==TrigSwitch.on,state);
		return false;
	}
	if(auto setStat=cast(TrigSetCreatureStatAction)action){
		auto id=resolveNtt(setStat.creature,run.side,state);
		if(id==0||state.isValidBuilding(id)) runError(run,text("set creature stat: cannot resolve creature ",setStat.creature.id));
		else state.movingObjectById!((ref obj,stat,value){ .setCreatureStat(obj,stat,value); },(){})(id,setStat.creatureStat,evalQuantity(setStat.quantity,run,triggerState,state));
		return false;
	}
	if(cast(TrigSetWeatherAction)action) return false; // no weather in sacengine
	if(cast(TrigSetNextMissionFilenameAction)action) return true; // no campaign progression in sacengine
	if(cast(TrigSetNextMissionIdAction)action) return true;
	if(auto fade=cast(TrigFadeToColorOverFramesAction)action){
		auto frames=evalQuantity(fade.quantity,run,triggerState,state);
		auto target=fade.color==TrigColor.clear?0.0f:1.0f;
		triggerState.fade.color=cast(int)fade.color;
		if(frames<=0){
			triggerState.fade.amount=target;
			triggerState.fade.step=0.0f;
		}else triggerState.fade.step=1.0f/frames;
		return false;
	}
	if(auto shake=cast(TrigScreenShakeAtLocationAction)action){
		Vector3f position;
		if(locationPosition(shake.location,run.side,position,state)){
			TriggerShake event;
			event.id=++triggerState.nextShakeId;
			event.side=run.side;
			event.position=position;
			event.startTick=triggerState.tick;
			triggerState.shakes~=event;
		}
		return false;
	}
	if(auto interfaceAction=cast(TrigTurnInterfaceElement)action){
		uint bit;
		final switch(interfaceAction.interfaceElement) with(TrigInterfaceElement){
			case selectionList: bit=TriggerInterfaceBit.selectionList; break;
			case spellList: bit=TriggerInterfaceBit.spellList; break;
			case minimap: bit=TriggerInterfaceBit.minimap; break;
			case statusBar: bit=TriggerInterfaceBit.statusBar; break;
			case soulCounter: bit=TriggerInterfaceBit.soulCounter; break;
		}
		if(interfaceAction.switch_==TrigSwitch.on) triggerState.hiddenInterfaceElements&=~bit;
		else triggerState.hiddenInterfaceElements|=bit;
		return true;
	}
	if(auto setActive=cast(TrigSetStructureActiveLevelAction)action){
		auto id=resolveNtt(setActive.structure,run.side,state);
		if(id==0||!state.isValidBuilding(id)) runError(run,text("set structure active level: cannot resolve structure ",setActive.structure.id));
		else state.buildingById!((ref building,value){ building.activeValue=value; },(){})(id,evalQuantity(setActive.quantity,run,triggerState,state));
		return false;
	}
	if(auto ask=cast(TrigAskTextAction)action){
		startTriggerAsk(ask.question,null,ask.option_a,ask.option_b,ask.variable,run,triggerState,state);
		return false;
	}
	if(auto ask=cast(TrigAskTextWithSampleAction)action){
		startTriggerAsk(ask.question,ask.sampleSpec,ask.option_a,ask.option_b,ask.variable,run,triggerState,state);
		return false;
	}
	if(cast(TrigShowRandomTipAction)action){
		if(tipTags.length) showTriggerTip(tipTags[state.uniform(cast(int)tipTags.length)],run,triggerState);
		return false;
	}
	if(auto tip=cast(TrigShowTipTextAction)action){ showTriggerTip(tip.text,run,triggerState); return false; }
	if(cast(TrigSuppressTipboxAction)action){ triggerState.tipboxSuppressed=true; return true; }
	if(auto history=cast(TrigAddTextWithSampleToSpeechHistoryAction)action){
		TriggerHistoryEntry entry;
		entry.side=run.side;
		entry.text=history.text;
		entry.sample=triggerSampleSpecTag(history.sampleSpec);
		triggerState.speechHistory~=entry;
		return false;
	}
	if(auto history=cast(TrigAddIntroSampleToSpeechHistoryAction)action){
		TriggerHistoryEntry entry;
		entry.side=run.side;
		entry.sample=history.sample;
		entry.intro=true;
		triggerState.speechHistory~=entry;
		return false;
	}
	// music actions are plain no-ops in both retail and thaum
	if(cast(TrigMusicResetAction)action) return false;
	if(cast(TrigMusicAddToMoodAction)action) return false;
	if(cast(TrigMusicTurnAction)action) return false;
	runError(run,text("unsupported action ",typeid(action)));
	return false;
}

bool orderConvertible(B)(TrigOrder trigOrder,ref TriggerRun run,ref TriggerState!B triggerState,ObjectState!B state){
	// orders that cannot be represented in sacengine fail conversion (retail: ConvertOrder returns 0)
	if(cast(TrigOrderPassiveNotify)trigOrder) return true;
	if(auto notify=cast(TrigOrderNotify)trigOrder){
		auto id=resolveNtt(notify.creature,run.side,state);
		return id!=0&&!state.isValidBuilding(id);
	}
	if(cast(TrigOrderCancelOrders)trigOrder||cast(TrigOrderDie)trigOrder||cast(TrigOrderTurnToFaceLocation)trigOrder) return true;
	Order order;
	return convertOrder(trigOrder,run.side,order,run,triggerState,state);
}

void orderAllOfType(B)(char[4] ctype,const(NttFilter)* filter,TrigOrder trigOrder,ref TriggerRun run,ref TriggerState!B triggerState,ObjectState!B state){
	state.obj.eachMoving!((ref obj,ctype,filter,trigOrder,run,triggerState,state){
		if(!obj.isAlive) return;
		if(!matchesCreatureType(ctype,obj)) return;
		if(filter!is null&&!passesFilter(obj,filter,state)) return;
		issueOrder(obj,trigOrder,*run,*triggerState,state);
	})(ctype,filter,trigOrder,&run,&triggerState,state);
}

void giveResourceAllOfType(B)(char[4] ctype,const(NttFilter)* filter,TrigResource resource,int amount,ObjectState!B state){
	state.obj.eachMoving!((ref obj,ctype,filter,resource,amount,state){
		if(!obj.isAlive) return;
		if(!matchesCreatureType(ctype,obj)) return;
		if(filter!is null&&!passesFilter(obj,filter,state)) return;
		giveResource(resource,amount,obj.id,state);
	})(ctype,filter,resource,amount,state);
}

void teleportAllOfType(B)(char[4] ctype,const(NttFilter)* filter,Vector3f target,ObjectState!B state){
	state.obj.eachMoving!((ref obj,ctype,filter,target,state){
		if(!obj.isAlive) return;
		if(!matchesCreatureType(ctype,obj)) return;
		if(filter!is null&&!passesFilter(obj,filter,state)) return;
		teleport(obj,target,state,false,false);
	})(ctype,filter,target,state);
}

void changeSideAllOfType(B)(char[4] nttType,const(NttFilter)* filter,int side,ObjectState!B state){
	state.obj.eachMoving!((ref obj,nttType,filter,side,state){
		if(!obj.isAlive) return;
		if(!matchesCreatureType(nttType,obj)) return;
		if(filter!is null&&!passesFilter(obj,filter,state)) return;
		changeSideOfObject(obj.id,side,state);
	})(nttType,filter,side,state);
	state.obj.eachBuilding!((ref building,nttType,filter,side,state){
		if(!matchesNttTypeStructure(nttType,building)) return;
		if(filter!is null){
			if(filter.ownerSide>=0&&building.side!=filter.ownerSide) return;
			if(filter.location.type!=0){
				if(!building.componentIds.length) return;
				if(!isAtLocation(building.position(state),*cast(CheckLocation*)&filter.location,state)) return;
			}
		}
		changeSideOfObject(building.id,side,state);
	})(nttType,filter,side,state);
}

void setStateAllOfType(B)(char[4] nttType,const(NttFilter)* filter,TrigNttState nttState,bool on,ObjectState!B state){
	state.obj.eachMoving!((ref obj,nttType,filter,nttState,on,state){
		if(!obj.isAlive) return;
		if(!matchesCreatureType(nttType,obj)) return;
		if(filter!is null&&!passesFilter(obj,filter,state)) return;
		setNttStateOnObject(obj.id,nttState,on,state);
	})(nttType,filter,nttState,on,state);
	state.obj.eachBuilding!((ref building,nttType,filter,nttState,on,state){
		if(!matchesNttTypeStructure(nttType,building)) return;
		if(filter!is null){
			if(filter.ownerSide>=0&&building.side!=filter.ownerSide) return;
			if(filter.location.type!=0){
				if(!building.componentIds.length) return;
				if(!isAtLocation(building.position(state),*cast(CheckLocation*)&filter.location,state)) return;
			}
		}
		setNttStateOnObject(building.id,nttState,on,state);
	})(nttType,filter,nttState,on,state);
}

// number of ntts of a quantified spec on the given side (retail: CountNtts on the run side)
int countQuantifiedNtts(B)(TrigQuantifiedNtts quantifiedNtts,int side,ref TriggerRun run,ref TriggerState!B triggerState,ObjectState!B state){
	NttFilter filter;
	filter.ownerSide=side;
	if(auto creatures=cast(TrigCreatureTypeNtts)quantifiedNtts)
		return countCreatureType(creatures.ctype,&filter,state);
	if(auto structures=cast(TrigStructureTypeNtts)quantifiedNtts)
		return countStructureType(structures.stype,&filter,state);
	if(auto creatures=cast(TrigCreatureTypeAtLocationNtts)quantifiedNtts){
		if(!setupLocation(creatures.location,side,filter.location,state)) return 0;
		return countCreatureType(creatures.ctype,&filter,state);
	}
	if(auto structures=cast(TrigStructureTypeAtLocationNtts)quantifiedNtts){
		if(!setupLocation(structures.location,side,filter.location,state)) return 0;
		return countStructureType(structures.stype,&filter,state);
	}
	runError(run,text("unsupported quantified ntts ",typeid(quantifiedNtts)));
	return 0;
}

int resourceOfQuantifiedNtts(B)(TrigResource resource,TrigQuantifiedNtts quantifiedNtts,int side,ref TriggerRun run,ref TriggerState!B triggerState,ObjectState!B state){
	NttFilter filter;
	filter.ownerSide=side;
	char[4] ctype;
	bool creatures=true;
	if(auto q=cast(TrigCreatureTypeNtts)quantifiedNtts) ctype=q.ctype;
	else if(auto q=cast(TrigCreatureTypeAtLocationNtts)quantifiedNtts){
		if(!setupLocation(q.location,side,filter.location,state)) return 0;
		ctype=q.ctype;
	}else if(cast(TrigStructureTypeNtts)quantifiedNtts||cast(TrigStructureTypeAtLocationNtts)quantifiedNtts){
		creatures=false; // structures hold no mana/health/souls resource in sacengine
	}else{
		runError(run,text("unsupported quantified ntts ",typeid(quantifiedNtts)));
		return 0;
	}
	if(!creatures) return 0;
	int sum=0;
	state.obj.eachMoving!((ref obj,ctype,filter,resource,state,sum){
		if(!obj.isAlive) return;
		if(!matchesCreatureType(ctype,obj)) return;
		if(!passesFilter(obj,filter,state)) return;
		final switch(resource) with(TrigResource){
			case mana: *sum+=cast(int)obj.creatureStats.mana; break;
			case health: *sum+=cast(int)obj.creatureStats.health; break;
			case souls:
				if(obj.isWizard){
					if(auto wiz=state.getWizardForSide(obj.side)) *sum+=wiz.souls;
				}else *sum+=obj.creatureStats.souls;
				break;
		}
	})(ctype,&filter,resource,state,&sum);
	return sum;
}
