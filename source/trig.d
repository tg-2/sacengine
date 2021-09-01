import std.conv:text,to;
import std.exception:enforce;
import std.algorithm:map;
import std.array:join;

import util;

abstract class TrigCondition{}
class TrigAlways: TrigCondition{
	override string toString(){ return "Always"; }
}

abstract class TrigSideSpec{}
class TrigCurrentSide: TrigSideSpec{
	override string toString(){ return "current side"; }
}

string sideIdToString(uint side){ return text("side ",side); }

class TrigSide: TrigSideSpec{
	uint side;
	this(uint side){ this.side=side; }
	override string toString(){ return sideIdToString(side); }
}
class TrigEnemySides: TrigSideSpec{
	override string toString(){ return "enemy sides"; }
}
class TrigFriendlySides: TrigSideSpec{
	override string toString(){ return "friendly sides"; }
}
class TrigNeutralSides: TrigSideSpec{
	override string toString(){ return "neutral sides"; }
}


abstract class TrigConstraint{}

class TrigAtLeast: TrigConstraint{
	TrigQuantity quantity;
	this(TrigQuantity quantity){ this.quantity=quantity; }
	override string toString(){ return text("at least ",quantity); }
}
class TrigAtMost: TrigConstraint{
	TrigQuantity quantity;
	this(TrigQuantity quantity){ this.quantity=quantity; }
	override string toString(){ return text("at most ",quantity); }
}
class TrigExactly: TrigConstraint{
	TrigQuantity quantity;
	this(TrigQuantity quantity){ this.quantity=quantity; }
	override string toString(){ return text("exactly ",quantity); }
}
class TrigAll: TrigConstraint{
	override string toString(){ return "all"; }
}
class TrigNone: TrigConstraint{
	override string toString(){ return "none"; }
}
class TrigTrue: TrigConstraint{
	override string toString(){ return "true"; }
}
class TrigFalse: TrigConstraint{
	override string toString(){ return "false"; }
}

abstract class TrigNtts{}
class TrigQuantityCreatureType: TrigNtts{
	TrigConstraint constraint;
	char[4] ctype;
	this(TrigConstraint constraint,char[4] ctype){ this.constraint=constraint; this.ctype=ctype; }
	override string toString(){ return text(constraint," ",creatureTypeToString(ctype)); }
}
class TrigQuantityStructureType: TrigNtts{
	TrigConstraint constraint;
	char[4] stype;
	this(TrigConstraint constraint,char[4] stype){ this.constraint=constraint; this.stype=stype; }
	override string toString(){ return text(constraint," ",structureTypeToString(stype)); }
}
class TrigNttsCreature: TrigNtts{
	TrigCreature creature;
	this(TrigCreature creature){ this.creature=creature; }
	override string toString(){ return text(creature); }
}
class TrigNttsStructure: TrigNtts{
	TrigStructure structure;
	this(TrigStructure structure){ this.structure=structure; }
	override string toString(){ return text(structure); }
}
class TrigIfSideSpecCommandsNttsCondition: TrigCondition{
	TrigSideSpec sideSpec;
	TrigNtts ntts;
	this(TrigSideSpec sideSpec,TrigNtts ntts){ this.sideSpec=sideSpec; this.ntts=ntts; }
	override string toString(){ return text("If ",sideSpec," commands ",ntts); }
}
class TrigIfSideSpecCommandsNttsAtLocationCondition: TrigCondition{
	TrigSideSpec sideSpec;
	TrigNtts ntts;
	TrigLocation location;
	this(TrigSideSpec sideSpec,TrigNtts ntts,TrigLocation location){ this.sideSpec=sideSpec; this.ntts=ntts; this.location=location; }
	override string toString(){ return text("If ",sideSpec," commands ",ntts," at ",location); }
}
class TrigIfSideSpecCommandsNttsWithinMetersOfNttCondition: TrigCondition{
	TrigSideSpec sideSpec;
	TrigNtts ntts;
	TrigQuantity quantity;
	TrigNtt ntt;
	this(TrigSideSpec sideSpec,TrigNtts ntts,TrigQuantity quantity,TrigNtt ntt){
		this.sideSpec=sideSpec; this.ntts=ntts; this.quantity=quantity; this.ntt=ntt;
	}
	override string toString(){ return text("If ",sideSpec," commands ",ntts," within ",quantity," meters of ",ntt); }
}
class TrigIfSideSpecDoesNotCommandNttsCondition: TrigCondition{
	TrigSideSpec sideSpec;
	TrigNtts ntts;
	this(TrigSideSpec sideSpec,TrigNtts ntts){ this.sideSpec=sideSpec; this.ntts=ntts; }
	override string toString(){ return text("If ",sideSpec," does not command ",ntts); }
}
class TrigIfSideSpecDoesNotCommandNttsAtLocationCondition: TrigCondition{
	TrigSideSpec sideSpec;
	TrigNtts ntts;
	TrigLocation location;
	this(TrigSideSpec sideSpec,TrigNtts ntts,TrigLocation location){ this.sideSpec=sideSpec; this.ntts=ntts; this.location=location; }
	override string toString(){ return text("If ",sideSpec," does not command ",ntts," at ",location); }
}

class TrigIfElapsedGameTimeIsFramesCondition: TrigCondition{
	TrigConstraint constraint;
	this(TrigConstraint constraint){ this.constraint=constraint; }
	override string toString(){ return text("If elapsed game time is ",constraint," frames"); }
}
class TrigIfGameTimerIsFramesCondition: TrigCondition{
	TrigConstraint constraint;
	this(TrigConstraint constraint){ this.constraint=constraint; }
	override string toString(){ return text("If game timer is ",constraint," frames"); }
}

class TrigIfSideSpecSeesNttsCondition: TrigCondition{
	TrigSideSpec sideSpec;
	TrigNtts ntts;
	this(TrigSideSpec sideSpec,TrigNtts ntts){ this.sideSpec=sideSpec; this.ntts=ntts; }
	override string toString(){ return text("If ",sideSpec," sees ",ntts); }
}
class TrigIfNttSeesNttsCondition: TrigCondition{
	TrigNtt ntt;
	TrigNtts ntts;
	this(TrigNtt ntt,TrigNtts ntts){ this.ntt=ntt; this.ntts=ntts; }
	override string toString(){ return text("If ",ntt," sees ",ntts); }
}

class TrigIfSideSpecIsAttackedBySideCondition: TrigCondition{
	TrigSideSpec sideSpec;
	uint sideId;
	this(TrigSideSpec sideSpec,uint sideId){ this.sideSpec=sideSpec; this.sideId=sideId; }
	override string toString(){ return text("If ",sideSpec," is attacked by ",sideIdToString(sideId)); }
}
class TrigIfCreatureIsAttackedBySideSpecCondition: TrigCondition{
	TrigCreature creature;
	TrigSideSpec sideSpec;
	this(TrigCreature creature,TrigSideSpec sideSpec){ this.creature=creature; this.sideSpec=sideSpec; }
	override string toString(){ return text("If ",creature," is attacked by ",sideSpec); }
}

class TrigIfVariableCondition: TrigCondition{
	uint variable;
	TrigConstraint constraint;
	this(uint variable,TrigConstraint constraint){ this.variable=variable; this.constraint=constraint; }
	override string toString(){ return text("If variable ",variable," ",constraint); }
}

class TrigIfNttHasResourceCondition: TrigCondition{
	TrigNtt ntt;
	TrigConstraint constraint;
	TrigResource resource;
	this(TrigNtt ntt,TrigConstraint constraint,TrigResource resource){
		this.ntt=ntt; this.constraint=constraint; this.resource=resource;
	}
	override string toString(){ return text("If ",ntt," has ",constraint," ",resourceToString(resource)); }
}
class TrigIfCreatureHasStatCondition: TrigCondition{
	TrigCreature creature;
	TrigConstraint constraint;
	TrigCreatureStat creatureStat;
	this(TrigCreature creature,TrigConstraint constraint,TrigCreatureStat creatureStat){
		this.creature=creature; this.constraint=constraint; this.creatureStat=creatureStat;
	}
	override string toString(){ return text("If ",creature," has ",constraint," ",creatureStatToString(creatureStat)); }
}
class TrigIfPlayerHasCreaturesSelectedCondition: TrigCondition{
	TrigCreature[] creatures;
	this(TrigCreature[] creatures){ this.creatures=creatures; }
	override string toString(){ return text("If player has ",creatures.map!text.join(" and "), " selected"); }
}
class TrigIfCreatureHasOrdersCondition: TrigCondition{
	TrigCreature creature;
	TrigOrder order;
	this(TrigCreature creature,TrigOrder order){ this.creature=creature; this.order=order; }
	override string toString(){ return text("If ",creature, " has orders ",order); }
}
class TrigIfStructureActiveValueCondition: TrigCondition{
	TrigStructure structure;
	TrigConstraint constraint;
	this(TrigStructure structure,TrigConstraint constraint){ this.structure=structure; this.constraint=constraint; }
	override string toString(){ return text("If ",structure," active value ",constraint); }
}
class TrigIfCurrentSideIsAnAiSide: TrigCondition{
	override string toString(){ return "If current side is an AI side"; }
}
class TrigIfCurrentSideIsAPlayerSide: TrigCondition{
	override string toString(){ return "If current side is a player side"; }
}

class TrigIfNttExistsCondition: TrigCondition{
	TrigNtt ntt;
	this(TrigNtt ntt){ this.ntt=ntt; }
	override string toString(){ return text("If ",ntt," exists"); }
}
class TrigIfNttExistsOnTheCurrentSideCondition: TrigCondition{
	TrigNtt ntt;
	this(TrigNtt ntt){ this.ntt=ntt; }
	override string toString(){ return text("If ",ntt," exists on the current side"); }
}
class TrigIfCreatureIsAliveCondition: TrigCondition{
	TrigCreature creature;
	this(TrigCreature creature){ this.creature=creature; }
	override string toString(){ return text("If ",creature," is alive"); }
}

class TrigOrCondition: TrigCondition{
	TrigCondition condition1,condition2;
	this(TrigCondition condition1,TrigCondition condition2){ this.condition1=condition1; this.condition2=condition2; }
	override string toString(){ return text("(",condition1,") OR (",condition2,")"); }
}
class TrigAndCondition: TrigCondition{
	TrigCondition condition1,condition2;
	this(TrigCondition condition1,TrigCondition condition2){ this.condition1=condition1; this.condition2=condition2; }
	override string toString(){ return text("(",condition1,") AND (",condition2,")"); }
}
class TrigNotCondition: TrigCondition{
	TrigCondition condition;
	this(TrigCondition condition){ this.condition=condition; }
	override string toString(){ return text("NOT ",condition); }
}

abstract class TrigAction{}
class TrigPauseAction: TrigAction{
	uint numFrames;
	this(uint numFrames){ this.numFrames=numFrames; }
	override string toString(){ return text("Pause for ",numFrames, " frames"); }
}
class TrigEndMissionInDefeatAction: TrigAction{
	override string toString(){ return text("End mission in defeat"); }
}
class TrigEndMissionInVictoryAction: TrigAction{
	override string toString(){ return text("End mission in victory"); }
}
class TrigEndMissionAction: TrigAction{
	override string toString(){ return text("End mission"); }
}
enum TrigStance{
	hostile=33,
	friendly=34,
	neutral=35,
}
class TrigDeclareStanceToSideAction: TrigAction{
	TrigStance stance;
	uint side;
	this(TrigStance stance,uint side){ this.stance=stance; this.side=side; }
	override string toString(){ return text("Declare ",stance," to ",sideIdToString(side)); }
}
class TrigChangeSideAction: TrigAction{
	TrigNtt ntt;
	uint side;
	this(TrigNtt ntt,uint side){ this.ntt=ntt; this.side=side; }
	override string toString(){ return text("Change side ",ntt," to ",sideIdToString(side)); }
}
string nttTypeToString(char[4] nttType){
	switch(nttType){
		case "latt": return "(Altar)";
		case "lstt": return "(Controllable Creature)";
		case "pctt": return "(Corpse)";
		case "rctt": return "(Creature)";
		case "fmtt": return "(Manafount)";
		case "nmtt": return "(Manalith)";
		case "cwtt": return "(Wizard or Creature)";
		case "zwtt": return "(Wizard)";
		default: return text(nttType);
	}
}
class TrigChangeSideAllOfTypeAction: TrigAction{
	char[4] nttType;
	uint side;
	this(char[4] nttType,uint side){ this.nttType=nttType; this.side=side; }
	override string toString(){ return text("Change side all ",nttTypeToString(nttType)," to ",sideIdToString(side)); }
}
class TrigChangeSideAllOfTypeAtLocationAction: TrigAction{
	char[4] nttType;
	TrigLocation location;
	uint side;
	this(char[4] nttType,TrigLocation location,uint side){ this.nttType=nttType; this.location=location; this.side=side; }
	override string toString(){ return text("Change side all ",nttTypeToString(nttType)," at ",location," to ",sideIdToString(side)); }
}

string nttToString(int ntt){ // wtf.
	if(ntt==*cast(int*)"cwct".ptr) return "(Current Side's Wizard)";
	if(ntt==*cast(int*)"swct".ptr) return "(Singleplayer Wizard)";
	return null;
}

abstract class TrigNtt{}
class TrigCreature:TrigNtt{
	uint id;
	bool isId2=false; // ?
	this(uint id,bool isId2){ this.id=id; this.isId2=isId2; }
	static string nttToString(int ntt){
		if(auto r=.nttToString(ntt)) return r;
		return text("creature ",ntt);
	}
	override string toString(){ return nttToString(id); }
}
class TrigWizard:TrigNtt{
	uint id;
	this(uint id){ this.id=id; }
	static string nttToString(int ntt){
		if(auto r=.nttToString(ntt)) return r;
		return text("wizard ",ntt);
	}
	override string toString(){ return nttToString(id); }
}
class TrigStructure:TrigNtt{
	uint id;
	this(uint id){ this.id = id; }
	override string toString(){ return text("structure ",id); }
}
abstract class TrigLocation{}
class TrigMarker: TrigLocation{
	uint id;
	this(uint id){ this.id = id; }
	override string toString(){ return text("Marker ",id); }
}
class TrigMarkerAtHeight: TrigLocation{
	uint id;
	uint height;
	this(uint id,uint height){ this.id = id; this.height=height; }
	override string toString(){ return text("Marker ",id," at ",height," meters height"); }
}
class TrigAtNtt: TrigLocation{
	TrigNtt ntt;
	this(TrigNtt ntt){ this.ntt=ntt; }
	override string toString(){ return text(ntt); }
}
abstract class TrigOrder{}
class TrigOrderAttack: TrigOrder{
	TrigNtt target;
	this(TrigNtt target){ this.target=target; }
	override string toString(){ return text("attack ",target); }
}
class TrigOrderGoToLocation: TrigOrder{
	TrigLocation location;
	this(TrigLocation location){ this.location=location; }
	override string toString(){ return text("go to ",location); }
}
class TrigOrderAttackLocation: TrigOrder{
	TrigLocation location;
	this(TrigLocation location){ this.location=location; }
	override string toString(){ return text("attack ",location); }
}
class TrigOrderGuardLocation: TrigOrder{
	TrigLocation location;
	this(TrigLocation location){ this.location=location; }
	override string toString(){ return text("guard ",location); }
}
enum TrigFormation{
	line=270,
	phalanx=271,
	skirmish=272,
	circle=273,
	semicircle=274,
	wedge=275,
	flankLeft=276,
	flankRight=277,
}
string trigFormationToString(TrigFormation formation){
	switch(formation) with(TrigFormation){
		case semicircle: return "semi-circle";
		case flankLeft: return "flank left";
		case flankRight: return "flank right";
		default: return text(formation);
	}
}
TrigFormation parseTrigFormation(ref ubyte[] data){
	auto type=parseUint(data);
	return to!TrigFormation(type);
}
class TrigOrderGoToLocationInFormation:TrigOrder{
	TrigLocation location;
	TrigFormation formation;
	this(TrigLocation location,TrigFormation formation){ this.location=location; this.formation=formation; }
	override string toString(){ return text("go to ",location," in ",trigFormationToString(formation)," formation"); }
}
class TrigOrderAttackLocationInFormation:TrigOrder{
	TrigLocation location;
	TrigFormation formation;
	this(TrigLocation location,TrigFormation formation){ this.location=location; this.formation=formation; }
	override string toString(){ return text("attack ",location," in ",trigFormationToString(formation)," formation"); }
}
class TrigOrderGuardLocationInFormation:TrigOrder{
	TrigLocation location;
	TrigFormation formation;
	this(TrigLocation location,TrigFormation formation){ this.location=location; this.formation=formation; }
	override string toString(){ return text("guard ",location," in ",trigFormationToString(formation)," formation"); }
}
class TrigSpellSpec{}
class TrigSpellAtNtt: TrigSpellSpec{
	char[4] tag;
	uint ntt;
	this(char[4] tag,uint ntt){ this.tag=tag; this.ntt=ntt; }
	static string nttToString(int ntt){ // wtf.
		if(auto r=.nttToString(ntt)) return r;
		return text(ntt);
	}
	override string toString(){ return text("cast ",tag," on ",nttToString(ntt)); }
}
class TrigSpellAtSoulOfNtt: TrigSpellSpec{
	char[4] tag;
	uint ntt;
	this(char[4] tag,uint ntt){ this.tag=tag; this.ntt=ntt; }
	static string nttToString(int ntt){ // wtf.
		if(auto r=.nttToString(ntt)) return r;
		return text("creature ",ntt);
	}
	override string toString(){ return text("cast ",tag," on soul of ",nttToString(ntt)); }
}
class TrigSpellAtLocation: TrigSpellSpec{
	char[4] tag;
	TrigLocation location;
	this(char[4] tag,TrigLocation location){ this.tag=tag; this.location=location; }
	override string toString(){ return text("cast ",tag," at ",location); }

}
class TrigSpell: TrigSpellSpec{
	char[4] tag;
	this(char[4] tag){ this.tag=tag; }
	override string toString(){ return text(tag); }
}
class TrigCreatureSpell: TrigSpellSpec{
	char[4] tag;
	this(char[4] tag){ this.tag=tag; }
	override string toString(){ return text(tag); }
}
class TrigOrderCast: TrigOrder{
	TrigSpellSpec spellSpec;
	this(TrigSpellSpec spellSpec){ this.spellSpec=spellSpec;}
	override string toString(){ return text("cast ",spellSpec); }
}
class TrigOrderNotify: TrigOrder{
	TrigCreature creature;
	this(TrigCreature creature){ this.creature=creature; }
	override string toString(){ return text("notify ",creature); }
}
class TrigOrderTurnToFaceLocation:TrigOrder{
	TrigLocation location;
	this(TrigLocation location){ this.location=location; }
	override string toString(){ return text("turn to face ",location); }
}
class TrigOrderPassiveNotify: TrigOrder{
	override string toString(){ return text("passive notify"); }
}
class TrigOrderCancelOrders: TrigOrder{
	override string toString(){ return text("cancel orders"); }
}
class TrigOrderDie: TrigOrder{
	override string toString(){ return text("die"); }
}

class TrigOrderAction: TrigAction{
	TrigCreature creature;
	TrigOrder order;
	this(TrigCreature creature,TrigOrder order){ this.creature=creature; this.order=order; }
	override string toString(){ return text("Order ",creature, " ",order); }
}
class TrigOrderListAction: TrigAction{
	TrigCreature[] creatures;
	TrigOrder order;
	this(TrigCreature[] creatures,TrigOrder order){ this.creatures=creatures; this.order=order; }
	override string toString(){ return text("Order ",creatures.map!text.join(" and "), " ",order); }
}
class TrigOrderAllOfTypeAtLocationAction: TrigAction{
	char[4] ctype;
	TrigLocation location;
	TrigOrder order;
	this(char[4] ctype,TrigLocation location,TrigOrder order){
		this.ctype=ctype; this.location=location; this.order=order;
	}
	override string toString(){ return text("Order all ",creatureTypeToString(ctype)," at ",location," ",order); }
}
class TrigOrderAllOfTypeAction: TrigAction{
	char[4] ctype;
	TrigOrder order;
	this(char[4] ctype,TrigOrder order){ this.ctype=ctype; this.order=order; }
	override string toString(){ return text("Order all ",creatureTypeToString(ctype)," ",order); }
}
class TrigDisplayVariableAction: TrigAction{
	uint variable;
	this(uint variable){ this.variable=variable; }
	override string toString(){ return text("Display variable ",variable); }
}
class TrigDisplayTextAction: TrigAction{
	char[4] text;
	this(char[4] text){ this.text=text; }
	override string toString(){ return .text("Display text ",text); }
}
class TrigHideVariableAction: TrigAction{
	uint variable;
	this(uint variable){ this.variable=variable; }
	override string toString(){ return text("Hide variable ",variable); }
}
class TrigClearTextAction: TrigAction{
	override string toString(){ return .text("Clear text"); }
}
class TrigPlaySampleAction: TrigAction{
	char[4] sample;
	this(char[4] sample){ this.sample=sample; }
	override string toString(){ return .text("Play sample ",sample); }
}
class TrigCreateCreatureTypeAtLocationAction: TrigAction{
	char[4] ctype;
	TrigLocation location;
	this(char[4] ctype,TrigLocation location){ this.ctype=ctype; this.location=location; }
	override string toString(){ return text("Create ",creatureTypeToString(ctype)," at ",location); }
}
class TrigCreateCreatureTypeOnSideAtLocationAction: TrigAction{
	char[4] ctype;
	uint side;
	TrigLocation location;
	this(char[4] ctype,uint side,TrigLocation location){
		this.ctype=ctype;
		this.side=side;
		this.location=location;
	}
	override string toString(){ return text("Create ",creatureTypeToString(ctype)," on ",sideIdToString(side)," at ",location); }
}
class TrigCreateMultipleCreatureTypeOnSideAtLocationAction: TrigAction{
	uint amount;
	char[4] ctype;
	uint side;
	TrigLocation location;
	this(uint amount,char[4] ctype,uint side,TrigLocation location){
		this.amount=amount;
		this.ctype=ctype;
		this.side=side;
		this.location=location;
	}
	override string toString(){
		return text("Create ",amount," ",creatureTypeToString(ctype)," on ",sideIdToString(side)," at ",location);
	}
}
abstract class TrigQuantity{}
class TrigQuantityTrue: TrigQuantity{ override string toString(){ return "true"; } }
class TrigQuantityFalse: TrigQuantity{ override string toString(){ return "false"; } }
class TrigQuantityInteger: TrigQuantity{
	int value;
	this(int value){ this.value=value; }
	override string toString(){ return text(value); }
}
class TrigQuantityVariable: TrigQuantity{
	uint variable;
	this(int variable){ this.variable=variable; }
	override string toString(){ return text("variable ",variable); }
}
class TrigQuantityAdd: TrigQuantity{
	TrigQuantity a,b;
	this(TrigQuantity a,TrigQuantity b){ this.a=a; this.b=b; }
	override string toString(){ return text("(",a," + ",b,")"); }
}
class TrigQuantitySub: TrigQuantity{
	TrigQuantity a,b;
	this(TrigQuantity a,TrigQuantity b){ this.a=a; this.b=b; }
	override string toString(){ return text("(",a," - ",b,")"); }
}
class TrigQuantityMul: TrigQuantity{
	TrigQuantity a,b;
	this(TrigQuantity a,TrigQuantity b){ this.a=a; this.b=b; }
	override string toString(){ return text("(",a," * ",b,")"); }
}
class TrigQuantityDiv: TrigQuantity{
	TrigQuantity a,b;
	this(TrigQuantity a,TrigQuantity b){ this.a=a; this.b=b; }
	override string toString(){ return text("(",a," / ",b,")"); }
}

enum TrigCreatureStat{
	speed=219,
	flyingSpeed=220,
	maxHealth=221,
	regeneration=222,
	drain=223,
	rangedAccuracy=224,
	resistanceToMelee=225,
	resistanceToDirectSpell=226,
	resistanceToSplashSpell=227,
	resistanceToDirectRanged=228,
	resistanceToSplashRanged=229,
	maxMana=230,
	kills=231,
	gibs=232,
}
string creatureStatToString(TrigCreatureStat stat){
	switch(stat) with(TrigCreatureStat){
		case flyingSpeed: return "flying speed";
		case maxHealth: return "max health";
		case rangedAccuracy: return "ranged accuracy";
		case resistanceToMelee: return "resistance to melee";
		case resistanceToDirectSpell: return "resistance to direct spell";
		case resistanceToSplashSpell: return "resistance to splash spell";
		case resistanceToDirectRanged: return "resistance to direct ranged";
		case resistanceToSplashRanged: return "resistance to splash ranged";
		case maxMana: return "max mana";
		default: return text(stat);
	}
}
class TrigQuantityCreatureStat: TrigQuantity{
	TrigCreatureStat stat;
	TrigCreature creature;
	this(TrigCreatureStat stat,TrigCreature creature){
		this.stat=stat;
		this.creature=creature;
	}
	override string toString(){ return text(creatureStatToString(stat)," of ",creature); }
}

class TrigSetVariableAction: TrigAction{
	uint variable;
	TrigQuantity quantity;
	this(uint variable,TrigQuantity quantity){ this.variable=variable; this.quantity=quantity; }
	override string toString(){ return text("Set variable ",variable," to ",quantity); }
}


abstract class TrigQuantifiedNtts{}

char[4] parseTrigCreatureType(ref ubyte[] data){
	auto vtype=parseUint(data);
	enforce(vtype==ValueType.creatureType);
	return cast(char[4])data.eat(4)[0..4];
}
string creatureTypeToString(char[4] ctype){
	if(ctype=="lstt") return "(Controllable Creature)";
	if(ctype=="pctt") return "(Corpse)";
	if(ctype=="rctt") return "(Creature)";
	if(ctype=="cwtt") return "(Wizard or Creature)";
	if(ctype=="zwtt") return "(Wizard)";
	return text(ctype);
}

class TrigCreatureTypeNtts: TrigQuantifiedNtts{
	char[4] ctype;
	this(char[4] ctype){ this.ctype=ctype; }
	override string toString(){ return creatureTypeToString(ctype); }
}

char[4] parseTrigStructureType(ref ubyte[] data){
	auto vtype=parseUint(data);
	enforce(vtype==ValueType.structureType);
	return cast(char[4])data.eat(4)[0..4];
}
string structureTypeToString(char[4] stype){
	if(stype=="latt") return "(Altar)";
	if(stype=="fmtt") return "(Manafount)";
	if(stype=="nmtt") return "(Manalith)";
	return text(stype);
}

class TrigStructureTypeNtts: TrigQuantifiedNtts{
	char[4] stype;
	this(char[4] stype){ this.stype=stype; }
	override string toString(){ return structureTypeToString(stype); }
}

class TrigCreatureTypeAtLocationNtts: TrigQuantifiedNtts{
	char[4] ctype;
	TrigLocation location;
	this(char[4] ctype,TrigLocation location){ this.ctype=ctype; this.location=location;}
	override string toString(){ return text(creatureTypeToString(ctype)," at ",location); }
}
class TrigStructureTypeAtLocationNtts: TrigQuantifiedNtts{
	char[4] stype;
	TrigLocation location;
	this(char[4] stype,TrigLocation location){ this.stype=stype; this.location=location;}
	override string toString(){ return text(structureTypeToString(stype)," at ",location); }
}
class TrigSetVariableToNumberOfNttsAction: TrigAction{
	uint variable;
	TrigQuantifiedNtts quantifiedNtts;
	this(uint variable,TrigQuantifiedNtts quantifiedNtts){ this.variable=variable; this.quantifiedNtts=quantifiedNtts; }
	override string toString(){ return text("Set variable ",variable," equal to number of ",quantifiedNtts); }
}

enum TrigResource{
	mana=130,
	health=131,
	souls=132,
}
string resourceToString(TrigResource resource){
	final switch(resource) with(TrigResource){
		case mana: return "Mana";
		case health: return "Health";
		case souls: return "Souls";
	}
}
class TrigSetVariableToResourceOfNttAction: TrigAction{
	uint variable;
	TrigResource resource;
	TrigNtt ntt;
	this(uint variable,TrigResource resource,TrigNtt ntt){
		this.variable=variable;
		this.resource=resource;
		this.ntt=ntt;
	}
	override string toString(){ return text("Set variable ",variable," equal to ",resourceToString(resource)," of ",ntt); }
}
class TrigSetVariableToResourceOfNttsAction: TrigAction{
	uint variable;
	TrigResource resource;
	TrigQuantifiedNtts quantifiedNtts;
	this(uint variable,TrigResource resource,TrigQuantifiedNtts quantifiedNtts){
		this.variable=variable;
		this.resource=resource;
		this.quantifiedNtts=quantifiedNtts;
	}
	override string toString(){ return text("Set variable ",variable," equal to ",resourceToString(resource)," of ",quantifiedNtts); }
}
class TrigSetVariableToRandomNumberInRangeAction: TrigAction{
	uint variable;
	TrigQuantity low,high;
	this(uint variable,TrigQuantity low,TrigQuantity high){
		this.variable=variable;
		this.low=low;
		this.high=high;
	}
	override string toString(){ return text("Set variable ",variable, " equal to random number in range ",low," to ",high); }
}

abstract class TrigActor{}
class TrigActorCreature: TrigActor{
	TrigCreature creature;
	this(TrigCreature creature){ this.creature=creature; }
	override string toString(){ return text(creature); }
}
abstract class TrigActorName: TrigActor{}
class TrigActorNameText: TrigActorName{
	char[4] text;
	this(char[4] text){ this.text=text; }
	override string toString(){ return .text(text); }
}
class TrigActorNamePlayerWizard: TrigActorName{
	override string toString(){ return "player wizard"; }
}
enum TrigGod{
	persephone=82,
	pyro=83,
	james=84,
	charnel=85,
	stratos=86,
}
string godToString(TrigGod god){
	switch(god) with(TrigGod){
		case persephone: return "Persephone";
		case pyro: return "Pyro";
		case james: return "James";
		case charnel: return "Charnel";
		case stratos: return "Stratos";
		default: return text(god);
	}
}
class TrigActorGod: TrigActor{
	TrigGod god;
	this(TrigGod god){ this.god=god; }
	override string toString(){ return godToString(god); }
}
abstract class TrigSpeaks{}
enum TrigEmotion{
	anger=214,
	happiness=215,
	sadness=216,
}
class TrigSays: TrigSpeaks{
	override string toString(){ return "says"; }
}
class TrigSaysWithEmotion: TrigSpeaks{
	TrigEmotion emotion;
	this(TrigEmotion emotion){ this.emotion=emotion; }
	override string toString(){ return text("says with ",emotion); }
}
class TrigAsks: TrigSpeaks{
	override string toString(){ return "asks"; }
}
class TrigAsksWithEmotion: TrigSpeaks{
	TrigEmotion emotion;
	this(TrigEmotion emotion){ this.emotion=emotion; }
	override string toString(){ return text("asks with ",emotion); }
}
class TrigExclaims: TrigSpeaks{
	override string toString(){ return "exclaims"; }
}
class TrigExclaimsWithEmotion: TrigSpeaks{
	TrigEmotion emotion;
	this(TrigEmotion emotion){ this.emotion=emotion; }
	override string toString(){ return text("exclaims with ",emotion); }
}
class TrigNarrates: TrigSpeaks{
	override string toString(){ return "narrates"; }
}

abstract class TrigTiming{}
class TrigAutoTimed: TrigTiming{
	override string toString(){ return "auto timed"; }
}
class TrigSampleLengthMinusFrames: TrigTiming{
	TrigQuantity quantity;
	this(TrigQuantity quantity){ this.quantity=quantity; }
	override string toString(){ return text("timed by sample length minus ",quantity," frames"); }
}
class TrigPersistent: TrigTiming{
	override string toString(){ return "persistent"; }
}
class TrigPauseForInput: TrigTiming{
	override string toString(){ return "pause for input"; }
}
class TrigForFrames: TrigTiming{
	TrigQuantity quantity;
	this(TrigQuantity quantity){ this.quantity=quantity; }
	override string toString(){ return text("for ",quantity," frames"); }
}

abstract class TrigSampleSpec{}
class TrigWithSampleNone: TrigSampleSpec{
	override string toString(){ return "with sample none"; }
}
class TrigWithSample: TrigSampleSpec{
	char[4] sample;
	this(char[4] sample){ this.sample=sample; }
	override string toString(){ return text("with sample ",sample); }
}
class TrigSpeechWithTextAction: TrigAction{
	TrigActor actor;
	TrigSpeaks speaks;
	char[4] text;
	TrigTiming timing;
	TrigSampleSpec sampleSpec;
	this(TrigActor actor,TrigSpeaks speaks,char[4] text,TrigTiming timing,TrigSampleSpec sampleSpec){
		this.actor=actor;
		this.speaks=speaks;
		this.text=text;
		this.timing=timing;
		this.sampleSpec=sampleSpec;
	}
	override string toString(){ return .text("Speech ",actor," ",speaks," text ",text," ",timing," ",sampleSpec); }
}

class TrigSpeechCreatureSpeaksSampleAction: TrigAction{
	TrigCreature creature;
	TrigSpeaks speaks;
	char[4] sample;
	this(TrigCreature creature,TrigSpeaks speaks,char[4] sample){ this.creature=creature; this.speaks=speaks; this.sample=sample; }
	override string toString(){ return text("Speech ",creature," ",speaks," sample ",sample); }
}
class TrigSpeechCreatureSaysTextWithSampleAction: TrigAction{
	TrigCreature creature;
	char[4] text;
	char[4] sample;
	this(TrigCreature creature,char[4] text,char[4] sample){ this.creature=creature; this.text=text; this.sample=sample; }
	override string toString(){ return .text("Speech ",creature," says text ",text," with sample ",sample); }
}
class TrigSpeechCreatureAsksTextWithSampleAction: TrigAction{
	TrigCreature creature;
	char[4] text;
	char[4] sample;
	this(TrigCreature creature,char[4] text,char[4] sample){ this.creature=creature; this.text=text; this.sample=sample; }
	override string toString(){ return .text("Speech ",creature," asks text ",text," with sample ",sample); }
}
class TrigSpeechCreatureExclaimsTextWithSampleAction: TrigAction{
	TrigCreature creature;
	char[4] text;
	char[4] sample;
	this(TrigCreature creature,char[4] text,char[4] sample){ this.creature=creature; this.text=text; this.sample=sample; }
	override string toString(){ return .text("Speech ",creature," exclaims text ",text," with sample ",sample); }
}
class TrigSpeechGodSaysTextWithSampleAction: TrigAction{
	TrigGod god;
	char[4] text;
	char[4] sample;
	this(TrigGod god,char[4] text,char[4] sample){ this.god=god; this.text=text; this.sample=sample; }
	override string toString(){ return .text(godToString(god)," says text ",text," with sample ",sample); }
}

enum TrigNarrator{
	playerWizard=115,
	familiar=116,
	sage=117,
}
string narratorToString(TrigNarrator narrator){
	switch(narrator) with(TrigNarrator){
		case playerWizard: return "Player Wizard";
		case familiar: return "Familiar";
		case sage: return "Sage";
		default: return text(narrator);
	}
}
class TrigSpeechNarratorNarratesTextWithSampleAction:  TrigAction{
	TrigNarrator narrator;
	char[4] text;
	char[4] sample;
	this(TrigNarrator narrator,char[4] text,char[4] sample){ this.narrator=narrator; this.text=text; this.sample=sample; }
	override string toString(){ return .text(narratorToString(narrator)," narrates text ",text," with sample ",sample); }
}

class TrigSetObjectiveCompleteAction: TrigAction{
	uint missionObjective;
	this(uint missionObjective){ this.missionObjective=missionObjective; }
	override string toString(){ return text("Set objective: mission objective ",missionObjective," complete"); }
}

class TrigEnableObjectiveAction: TrigAction{
	uint missionObjective;
	this(uint missionObjective){ this.missionObjective=missionObjective; }
	override string toString(){ return text("Enable objective: mission objective ",missionObjective); }
}
class TrigDisableObjectiveAction: TrigAction{
	uint missionObjective;
	this(uint missionObjective){ this.missionObjective=missionObjective; }
	override string toString(){ return text("Disable objective: mission objective ",missionObjective); }
}
class TrigTeleportAllOfTypeAtLocationToLocationAction: TrigAction{
	char[4] ctype;
	TrigLocation location1,location2;
	this(char[4] ctype,TrigLocation location1,TrigLocation location2){ this.ctype=ctype; this.location1=location1; this.location2=location2; }
	override string toString(){ return text("Teleport all ",ctype," at ",location1," to ",location2); }
}
class TrigTeleportAllOfTypeAtLocationAwayAction: TrigAction{
	char[4] ctype;
	TrigLocation location;
	this(char[4] ctype,TrigLocation location){ this.ctype=ctype; this.location=location; }
	override string toString(){ return text("Teleport all ",ctype," at ",location," away"); }
}
class TrigTeleportCreatureToLocationAction: TrigAction{
	TrigCreature creature;
	TrigLocation location;
	this(TrigCreature creature,TrigLocation location){ this.creature=creature; this.location=location; }
	override string toString(){ return text("Teleport ",creature," to ",location); }
}
class TrigTeleportCreatureAwayAction: TrigAction{
	TrigCreature creature;
	this(TrigCreature creature){ this.creature=creature; }
	override string toString(){ return text("Teleport ",creature," away"); }
}
class TrigSetGameTimerAction: TrigAction{
	TrigQuantity quantity;
	this(TrigQuantity quantity){ this.quantity=quantity; }
	override string toString(){ return text("Set game timer ",quantity); }
}
class TrigDisplayGameTimerAction: TrigAction{
	override string toString(){ return "Display game timer"; }
}
class TrigHideGameTimerAction: TrigAction{
	override string toString(){ return "Hide game timer"; }
}

abstract class TrigAiSetting{}
class TrigAiPaused: TrigAiSetting{
	override string toString(){ return "paused"; }
}
class TrigAiUnpaused: TrigAiSetting{
	override string toString(){ return "unpaused"; }
}
class TrigAiAggressionToQuantity: TrigAiSetting{
	TrigQuantity quantity;
	this(TrigQuantity quantity){ this.quantity=quantity; }
	override string toString(){ return text("aggression to ",quantity); }
}
class TrigSetAiSetting: TrigAction{
	TrigAiSetting aiSetting;
	this(TrigAiSetting aiSetting){ this.aiSetting=aiSetting; }
	override string toString(){ return text("Set AI ",aiSetting); }
}

enum TrigSwitch{
	on=107,
	off=108,
}
class TrigTurnBeaconAtLocationAction: TrigAction{
	TrigSwitch beaconSetting;
	TrigLocation location;
	this(TrigSwitch beaconSetting,TrigLocation location){
		this.beaconSetting=beaconSetting;
		this.location=location;
	}
	override string toString(){ return text("Turn beacon ",beaconSetting," on ",location); }
}

class TrigCinematicsStartAction: TrigAction{
	override string toString(){ return "Cinematics Start"; }
}
class TrigCinematicsEndAction: TrigAction{
	override string toString(){ return "Cinematics End"; }
}

class TrigSetViewFocusToLocationAction: TrigAction{
	TrigLocation location;
	this(TrigLocation location){ this.location=location; }
	override string toString(){ return text("Set view focus to ",location); }
}
class TrigSetViewOriginFromLocationAction: TrigAction{
	TrigLocation location;
	this(TrigLocation location){ this.location=location; }
	override string toString(){ return text("Set view origin from ",location); }
}
class TrigSetViewOriginFromLocationFocusToLocationAction: TrigAction{
	TrigLocation location1,location2;
	this(TrigLocation location1,TrigLocation location2){ this.location1=location1; this.location2=location2; }
	override string toString(){ return text("Set view origin from ",location1,", focus to ",location2); }
}


enum TrigZoomLevel{
	closest=122,
	close=123,
	medium=124,
	far=125,
	farthest=126,
}
string zoomLevelToString(TrigZoomLevel zoomLevel){
	switch(zoomLevel) with(TrigZoomLevel){
		case closest: return "Closest";
		case close: return "Close";
		case medium: return "Medium";
		case far: return "Far";
		case farthest: return "Farthest";
		default: return text(zoomLevel);
	}
}
class TrigSetViewZoomAction: TrigAction{
	TrigZoomLevel zoomLevel;
	this(TrigZoomLevel zoomLevel){ this.zoomLevel=zoomLevel; }
	override string toString(){ return text("Set view zoom to ",zoomLevelToString(zoomLevel)); }
}

class TrigSetViewSpeedAction: TrigAction{
	TrigQuantity quantity;
	this(TrigQuantity quantity){ this.quantity=quantity; }
	override string toString(){ return text("Set view speed to ",quantity); }
}

class TrigGiveCreatureResourceAction: TrigAction{
	TrigCreature creature;
	TrigQuantity quantity;
	TrigResource resource;
	this(TrigCreature creature,TrigQuantity quantity,TrigResource resource){
		this.creature=creature; this.quantity=quantity; this.resource=resource;
	}
	override string toString(){ return text("Give ",creature," ",quantity," ",resourceToString(resource)); }
}

class TrigGiveAllOfTypeAtLocationResourceAction: TrigAction{
	char[4] ctype;
	TrigLocation location;
	TrigQuantity quantity;
	TrigResource resource;
	this(char[4] ctype,TrigLocation location,TrigQuantity quantity,TrigResource resource){
		this.ctype=ctype; this.location=location; this.quantity=quantity; this.resource=resource;
	}
	override string toString(){ return text("Give all ",ctype," at ",location," ",quantity," ",resourceToString(resource)); }
}

class TrigGiveWizardSpellAction: TrigAction{
	TrigWizard wizard;
	char[4] spell;
	this(TrigWizard wizard,char[4] spell){ this.wizard=wizard; this.spell=spell; }
	override string toString(){ return text("Give ",wizard," spell ",spell); }
}

class TrigCastSpellAtLocationAction: TrigAction{
	char[4] spell;
	TrigLocation location;
	this(char[4] spell,TrigLocation location){ this.spell=spell; this.location=location; }
	override string toString(){ return text("Cast spell ",spell," at ",location); }
}

enum TrigNttState{
	rescuable=156,
	damaged=157,
	destroyed=233,
	cannotGib=158,
	cannotDamage=159,
	cannotDestroy=160,
	walking=256,
	collectsRedSouls=257,
	notOnMinimap=262,
}
string nttStateToString(TrigNttState state){
	switch(state) with(TrigNttState){
		case cannotGib: return "cannot gib";
		case cannotDamage: return "cannot damage";
		case cannotDestroy: return "cannot destroy";
		case collectsRedSouls: return "collects red souls";
		case notOnMinimap: return "not on minimap";
		default: return text(state);
	}
}
class TrigSetNttStateAction: TrigAction{
	TrigNtt ntt;
	TrigNttState state;
	TrigSwitch switch_;
	this(TrigNtt ntt,TrigNttState state,TrigSwitch switch_){ this.ntt=ntt; this.state=state; this.switch_=switch_; }
	override string toString(){ return text("Set ",ntt," ",nttStateToString(state)," ",switch_); }
}

class TrigSetAllOfTypeStateAction: TrigAction{
	char[4] nttType;
	TrigNttState state;
	TrigSwitch switch_;
	this(char[4] nttType,TrigNttState state,TrigSwitch switch_){ this.nttType=nttType; this.state=state; this.switch_=switch_; }
	override string toString(){ return text("Set all ",nttTypeToString(nttType)," ",nttStateToString(state)," ",switch_); }
}

class TrigSetAllOfTypeAtLocationStateAction: TrigAction{
	char[4] nttType;
	TrigLocation location;
	TrigNttState state;
	TrigSwitch switch_;
	this(char[4] nttType,TrigLocation location,TrigNttState state,TrigSwitch switch_){ this.nttType=nttType; this.location=location; this.state=state; this.switch_=switch_; }
	override string toString(){ return text("Set all ",nttTypeToString(nttType)," at ",location," ",nttStateToString(state)," ",switch_); }
}

class TrigSetCreatureStatAction: TrigAction{
	TrigCreature creature;
	TrigCreatureStat creatureStat;
	TrigQuantity quantity;
	this(TrigCreature creature,TrigCreatureStat creatureStat,TrigQuantity quantity){
		this.creature=creature; this.creatureStat=creatureStat; this.quantity=quantity;
	}
	override string toString(){ return text("Set ",creature," ",creatureStat," ",quantity); }
}

enum TrigWeather{
	rain=163,
	snow=164,
	hail=165,
	cinders=166,
	ash=167,
	insects=168,
}
class TrigSetWeatherAction: TrigAction{
	TrigWeather weather;
	TrigSwitch switch_;
	this(TrigWeather weather,TrigSwitch switch_){ this.weather=weather; this.switch_=switch_; }
	override string toString(){ return text("Set ",weather," ",switch_); }
}

class TrigSetNextMissionFilenameAction: TrigAction{
	char[4] filename;
	this(char[4] filename){ this.filename=filename; }
	override string toString(){ return text("Set next mission filename ",filename); }
}

enum TrigMissionId{
	etherealRealm=173,
	persephone=82,
	pyro=83,
	james=84,
	charnel=85,
	stratos=86,
}
string missionIdToString(TrigMissionId missionId){
	switch(missionId) with(TrigMissionId){
		case etherealRealm: return "Ethereal Realm";
		case persephone: return "Persephone";
		case pyro: return "Pyro";
		case james: return "James";
		case charnel: return "Charnel";
		case stratos: return "Stratos";
		default: return text(missionId);
	}
}
class TrigSetNextMissionIdAction: TrigAction{
	TrigMissionId missionId;
	this(TrigMissionId missionId){ this.missionId=missionId; }
	override string toString(){ return text("Set next mission ",missionIdToString(missionId)); }
}

enum TrigColor{
	black=192,
	white=193,
	red=194,
	clear=195,
}
class TrigFadeToColorOverFramesAction: TrigAction{
	TrigColor color;
	TrigQuantity quantity;
	this(TrigColor color,TrigQuantity quantity){ this.color=color; this.quantity=quantity; }
	override string toString(){ return text("Fade to ",color," over ",quantity," frames"); }
}

class TrigScreenShakeAtLocationAction: TrigAction{
	TrigLocation location;
	this(TrigLocation location){ this.location=location; }
	override string toString(){ return text("Screen shake at ",location); }
}

enum TrigInterfaceElement{
	selectionList=199,
	spellList=200,
	minimap=201,
	statusBar=202,
	soulCounter=203,
}
string interfaceElementToString(TrigInterfaceElement interfaceElement){
	switch(interfaceElement) with(TrigInterfaceElement){
		case selectionList: return "selection list";
		case spellList: return "spell list";
		case minimap: return "minimap";
		case statusBar: return "status bar";
		case soulCounter: return "soul counter";
		default: return text(interfaceElement);
	}
}
class TrigTurnInterfaceElement: TrigAction{
	TrigInterfaceElement interfaceElement;
	TrigSwitch switch_;
	this(TrigInterfaceElement interfaceElement,TrigSwitch switch_){ this.interfaceElement=interfaceElement; this.switch_=switch_; }
	override string toString(){ return text("Turn interface element ",interfaceElementToString(interfaceElement)," ",switch_); }
}

class TrigSetStructureActiveLevelAction: TrigAction{
	TrigStructure structure;
	TrigQuantity quantity;
	this(TrigStructure structure,TrigQuantity quantity){ this.structure=structure; this.quantity=quantity; }
	override string toString(){ return text("Set ",structure," active level to ",quantity); }
}

class TrigAskTextAction: TrigAction{
	char[4] question, option_a, option_b;
	uint variable;
	this(char[4] question,char[4] option_a,char[4] option_b,uint variable){
		this.question=question; this.option_a=option_a; this.option_b=option_b; this.variable=variable;
	}
	override string toString(){ return text( "Ask ",question,", give choices ",option_a," or ",option_b," and set variable ",variable); }
}
class TrigAskTextWithSampleAction: TrigAction{
	char[4] question;
	TrigSampleSpec sampleSpec;
	char[4] option_a, option_b;
	uint variable;
	this(char[4] question,TrigSampleSpec sampleSpec,char[4] option_a,char[4] option_b,uint variable){
		this.question=question; this.sampleSpec=sampleSpec; this.option_a=option_a; this.option_b=option_b; this.variable=variable;
	}
	override string toString(){ return text( "Ask ",question," ",sampleSpec,", give choices ",option_a," or ",option_b," and set variable ",variable); }
}

class TrigShowRandomTipAction: TrigAction{
	override string toString(){ return "Show random tip"; }
}
class TrigShowTipTextAction: TrigAction{
	char[4] text;
	this(char[4] text){ this.text=text; }
	override string toString(){ return .text("Show tip text ",text); }
}
class TrigSuppressTipboxAction: TrigAction{
	override string toString(){ return "Suppress tipbox"; }
}

class TrigAddTextWithSampleToSpeechHistoryAction: TrigAction{
	char[4] text;
	TrigSampleSpec sampleSpec;
	this(char[4] text,TrigSampleSpec sampleSpec){ this.text=text; this.sampleSpec=sampleSpec; }
	override string toString(){ return .text("Add text ",text," with ",sampleSpec," to speech history"); }
}
class TrigAddIntroSampleToSpeechHistoryAction: TrigAction{
	char[4] sample;
	this(char[4] sample){ this.sample=sample; }
	override string toString(){ return text("Add intro sample ",sample," to speech history"); }
}

class TrigMusicResetAction: TrigAction{
	override string toString(){ return "Music reset"; }
}
enum TrigMood{
	battle=266,
}
class TrigMusicAddToMoodAction: TrigAction{
	TrigQuantity quantity;
	TrigMood mood;
	this(TrigQuantity quantity,TrigMood mood){ this.quantity=quantity; this.mood=mood; }
	override string toString(){ return text("Music add ",quantity," to ",mood); }
}
class TrigMusicTurnAction: TrigAction{
	TrigSwitch switch_;
	this(TrigSwitch switch_){ this.switch_=switch_; }
	override string toString(){ return text("Music turn ",switch_); }
}

enum TriggerFlags{
	unknown=1,
	runOnce=2,
}

struct Trigger{
	uint flags;
	uint sides;
	TrigCondition[] conditions;
	TrigAction[] actions;

	string toString(){
		string r;
		if(conditions.length) r~=conditions.map!(c=>"- "~text(c)).join("\n")~"\nThen...\n";
		r~=actions.map!(c=>"- "~text(c)).join("\n");
		return r;
	}
}

TrigAlways parseTrigAlways(ref ubyte[] data){
	return new TrigAlways();
}

enum TrigSideSpecType{
	currentSide=44,
	side=40,
	enemySides=41,
	friendlySides=42,
	neutralSides=43,
}
TrigSideSpec parseTrigSideSpec(ref ubyte[] data){
	auto ssType=parseUint(data);
	switch(ssType){
		case TrigSideSpecType.currentSide:
			return new TrigCurrentSide();
		case TrigSideSpecType.side:
			auto side=parseTrigSideId(data);
			return new TrigSide(side);
		case TrigSideSpecType.enemySides:
			return new TrigEnemySides();
		case TrigSideSpecType.friendlySides:
			return new TrigFriendlySides();
		case TrigSideSpecType.neutralSides:
			return new TrigNeutralSides();
		default:
			enforce(0, text("unknown side spec type: ",ssType));
			assert(0);
	}
}

enum TrigConstraintType{
	none=0,
	atLeast=19,
	atMost=20,
	exactly=21,
	all=22,
	true_=137,
	false_=138,
}
TrigConstraint parseTrigConstraint(ref ubyte[] data){
	auto ctype=parseUint(data);
	switch(ctype){
		case TrigConstraintType.atLeast:
			auto quantity=parseTrigQuantity(data);
			return new TrigAtLeast(quantity);
		case TrigConstraintType.atMost:
			auto quantity=parseTrigQuantity(data);
			return new TrigAtMost(quantity);
		case TrigConstraintType.exactly:
			auto quantity=parseTrigQuantity(data);
			return new TrigExactly(quantity);
		case TrigConstraintType.all:
			return new TrigAll();
		case TrigConstraintType.none:
			return new TrigNone();
		case TrigConstraintType.true_:
			return new TrigTrue();
		case TrigConstraintType.false_:
			return new TrigFalse();
		default:
			enforce(0, text("unknown constraint type: ",ctype));
			assert(0);
	}
}

enum TrigNttsType{
	quantityCreatureType=15,
	quantityStructureType=16,
	creature=17,
	structure=18,
}
TrigNtts parseTrigNtts(ref ubyte[] data){
	auto nttsType=parseUint(data);
	switch(nttsType){
		case TrigNttsType.quantityCreatureType:
			auto constraint=parseTrigConstraint(data);
			auto ctype=parseTrigCreatureType(data);
			return new TrigQuantityCreatureType(constraint,ctype);
		case TrigNttsType.quantityStructureType:
			auto constraint=parseTrigConstraint(data);
			auto stype=parseTrigStructureType(data);
			return new TrigQuantityStructureType(constraint,stype);
		case TrigNttsType.creature:
			auto creature=parseTrigCreature(data);
			return new TrigNttsCreature(creature);
		case TrigNttsType.structure:
			auto structure=parseTrigStructure(data);
			return new TrigNttsStructure(structure);
		default:
			enforce(0,text("unknown ntts type: ",nttsType));
			assert(0);
	}
}

TrigIfSideSpecCommandsNttsCondition parseTrigIfSideSpecCommandsNttsCondition(ref ubyte[] data){
	auto sideSpec=parseTrigSideSpec(data);
	auto ntts=parseTrigNtts(data);
	return new TrigIfSideSpecCommandsNttsCondition(sideSpec,ntts);
}
TrigIfSideSpecCommandsNttsAtLocationCondition parseTrigIfSideSpecCommandsNttsAtLocationCondition(ref ubyte[] data){
	auto sideSpec=parseTrigSideSpec(data);
	auto ntts=parseTrigNtts(data);
	auto location=parseTrigLocation(data);
	return new TrigIfSideSpecCommandsNttsAtLocationCondition(sideSpec,ntts,location);
}
TrigIfSideSpecCommandsNttsWithinMetersOfNttCondition parseTrigIfSideSpecCommandsNttsWithinMetersOfNttCondition(ref ubyte[] data){
	auto sideSpec=parseTrigSideSpec(data);
	auto ntts=parseTrigNtts(data);
	auto quantity=parseTrigQuantity(data);
	auto ntt=parseTrigNtt(data);
	return new TrigIfSideSpecCommandsNttsWithinMetersOfNttCondition(sideSpec,ntts,quantity,ntt);
}
TrigIfSideSpecDoesNotCommandNttsCondition parseTrigIfSideSpecDoesNotCommandNttsCondition(ref ubyte[] data){
	auto sideSpec=parseTrigSideSpec(data);
	auto ntts=parseTrigNtts(data);
	return new TrigIfSideSpecDoesNotCommandNttsCondition(sideSpec,ntts);
}
TrigIfSideSpecDoesNotCommandNttsAtLocationCondition parseTrigIfSideSpecDoesNotCommandNttsAtLocationCondition(ref ubyte[] data){
	auto sideSpec=parseTrigSideSpec(data);
	auto ntts=parseTrigNtts(data);
	auto location=parseTrigLocation(data);
	return new TrigIfSideSpecDoesNotCommandNttsAtLocationCondition(sideSpec,ntts,location);
}
TrigIfElapsedGameTimeIsFramesCondition parseTrigIfElapsedGameTimeIsFramesCondition(ref ubyte[] data){
	auto constraint=parseTrigConstraint(data);
	return new TrigIfElapsedGameTimeIsFramesCondition(constraint);
}
TrigIfGameTimerIsFramesCondition parseTrigIfGameTimerIsFramesCondition(ref ubyte[] data){
	auto constraint=parseTrigConstraint(data);
	return new TrigIfGameTimerIsFramesCondition(constraint);
}

TrigIfSideSpecSeesNttsCondition parseTrigIfSideSpecSeesNttsCondition(ref ubyte[] data){
	auto sideSpec=parseTrigSideSpec(data);
	auto ntts=parseTrigNtts(data);
	return new TrigIfSideSpecSeesNttsCondition(sideSpec,ntts);
}
TrigIfNttSeesNttsCondition parseTrigIfNttSeesNttsCondition(ref ubyte[] data){
	auto ntt=parseTrigNtt(data);
	auto ntts=parseTrigNtts(data);
	return new TrigIfNttSeesNttsCondition(ntt,ntts);
}

TrigIfSideSpecIsAttackedBySideCondition parseTrigIfSideSpecIsAttackedBySideCondition(ref ubyte[] data){
	auto sideSpec=parseTrigSideSpec(data);
	auto sideId=parseTrigSideId(data);
	return new TrigIfSideSpecIsAttackedBySideCondition(sideSpec,sideId);
}
TrigIfCreatureIsAttackedBySideSpecCondition parseTrigIfCreatureIsAttackedBySideSpecCondition(ref ubyte[] data){
	auto creature=parseTrigCreature(data);
	auto sideSpec=parseTrigSideSpec(data);
	return new TrigIfCreatureIsAttackedBySideSpecCondition(creature,sideSpec);
}

TrigIfVariableCondition parseTrigIfVariableCondition(ref ubyte[] data){
	auto variable=parseTrigVariable(data);
	auto constraint=parseTrigConstraint(data);
	return new TrigIfVariableCondition(variable,constraint);
}

TrigIfNttHasResourceCondition parseTrigIfNttHasResourceCondition(ref ubyte[] data){
	auto ntt=parseTrigNtt(data);
	auto constraint=parseTrigConstraint(data);
	auto resource=parseUint(data);
	return new TrigIfNttHasResourceCondition(ntt,constraint,to!TrigResource(resource));
}
TrigIfCreatureHasStatCondition parseTrigIfCreatureHasStatCondition(ref ubyte[] data){
	auto creature=parseTrigCreature(data);
	auto constraint=parseTrigConstraint(data);
	auto creatureStat=parseUint(data);
	return new TrigIfCreatureHasStatCondition(creature,constraint,to!TrigCreatureStat(creatureStat));
}

TrigIfPlayerHasCreaturesSelectedCondition parseTrigIfPlayerHasCreaturesSelectedCondition(ref ubyte[] data){
	auto creatures=parseTrigCreatures(data);
	return new TrigIfPlayerHasCreaturesSelectedCondition(creatures);
}
TrigIfCreatureHasOrdersCondition parseTrigIfCreatureHasOrdersCondition(ref ubyte[] data){
	auto creature=parseTrigCreature(data);
	auto order=parseTrigOrder(data);
	return new TrigIfCreatureHasOrdersCondition(creature,order);
}

TrigIfStructureActiveValueCondition parseTrigIfStructureActiveValueCondition(ref ubyte[] data){
	auto structure=parseTrigStructure(data);
	auto constraint=parseTrigConstraint(data);
	return new TrigIfStructureActiveValueCondition(structure,constraint);
}

TrigIfCurrentSideIsAnAiSide parseTrigIfCurrentSideIsAnAiSide(ref ubyte[] data){
	return new TrigIfCurrentSideIsAnAiSide();
}
TrigIfCurrentSideIsAPlayerSide parseTrigIfCurrentSideIsAPlayerSide(ref ubyte[] data){
	return new TrigIfCurrentSideIsAPlayerSide();
}

TrigIfNttExistsCondition parseTrigIfNttExistsCondition(ref ubyte[] data){
	auto ntt=parseTrigNtt(data);
	return new TrigIfNttExistsCondition(ntt);
}
TrigIfNttExistsOnTheCurrentSideCondition parseTrigIfNttExistsOnTheCurrentSideCondition(ref ubyte[] data){
	auto ntt=parseTrigNtt(data);
	return new TrigIfNttExistsOnTheCurrentSideCondition(ntt);
}

TrigIfCreatureIsAliveCondition parseTrigIfCreatureIsAliveCondition(ref ubyte[] data){
	auto creature=parseTrigCreature(data);
	return new TrigIfCreatureIsAliveCondition(creature);
}

TrigOrCondition parseTrigOrCondition(ref ubyte[] data){
	auto condition1=parseTrigCondition(data);
	auto condition2=parseTrigCondition(data);
	return new TrigOrCondition(condition1,condition2);
}
TrigAndCondition parseTrigAndCondition(ref ubyte[] data){
	auto condition1=parseTrigCondition(data);
	auto condition2=parseTrigCondition(data);
	return new TrigAndCondition(condition1,condition2);
}
TrigNotCondition parseTrigNotCondition(ref ubyte[] data){
	auto condition=parseTrigCondition(data);
	return new TrigNotCondition(condition);
}

enum ConditionType{
	always=45,
	ifSideSpecCommandsNtts=1,
	ifSideSpecCommandsNttsAtLocation=2,
	ifSideSpecCommandsNttsWithinMetersOfNtt=151,
	ifSideSpecDoesNotCommandNtts=46,
	ifSideSpecDoesNotCommandNttsAtLocation=47,
	ifElapsedGameTimeIsFrames=3,
	ifSideSpecSeesNtts=53,
	ifNttSeesNtts=54,
	ifSideSpecIsAttackedBySide=55,
	ifCreatureIsAttackedBySideSpec=152,
	ifVariableCondition=59,
	ifNttHasResource=139,
	ifCreatureHasStat=235,
	ifPlayerHasCreaturesSelected=144,
	ifCreatureHasOrders=148,
	ifStructureActiveValueCondition=204,
	ifCurrentSideIsAnAiSide=236,
	ifCurrentSideIsAPlayerSide=237,
	ifNttExists=252,
	ifNttExistsOnTheCurrentSide=253,
	ifCreatureIsAlive=254,
	or=118,
	and=119,
	not=140,
}

TrigCondition parseTrigCondition(ref ubyte[] data){
	auto type=parseUint(data);
	switch(type){
		case ConditionType.always:
			return parseTrigAlways(data);
		case ConditionType.ifSideSpecCommandsNtts:
			return parseTrigIfSideSpecCommandsNttsCondition(data);
		case ConditionType.ifSideSpecCommandsNttsAtLocation:
			return parseTrigIfSideSpecCommandsNttsAtLocationCondition(data);
		case ConditionType.ifSideSpecCommandsNttsWithinMetersOfNtt:
			return parseTrigIfSideSpecCommandsNttsWithinMetersOfNttCondition(data);
		case ConditionType.ifSideSpecDoesNotCommandNtts:
			return parseTrigIfSideSpecDoesNotCommandNttsCondition(data);
		case ConditionType.ifSideSpecDoesNotCommandNttsAtLocation:
			return parseTrigIfSideSpecDoesNotCommandNttsAtLocationCondition(data);
		case ConditionType.ifElapsedGameTimeIsFrames:
			return parseTrigIfElapsedGameTimeIsFramesCondition(data);
		case ConditionType.ifSideSpecSeesNtts:
			return parseTrigIfSideSpecSeesNttsCondition(data);
		case ConditionType.ifNttSeesNtts:
			return parseTrigIfNttSeesNttsCondition(data);
		case ConditionType.ifSideSpecIsAttackedBySide:
			return parseTrigIfSideSpecIsAttackedBySideCondition(data);
		case ConditionType.ifCreatureIsAttackedBySideSpec:
			return parseTrigIfCreatureIsAttackedBySideSpecCondition(data);
		case ConditionType.ifVariableCondition:
			return parseTrigIfVariableCondition(data);
		case ConditionType.ifNttHasResource:
			return parseTrigIfNttHasResourceCondition(data);
		case ConditionType.ifCreatureHasStat:
			return parseTrigIfCreatureHasStatCondition(data);
		case ConditionType.ifPlayerHasCreaturesSelected:
			return parseTrigIfPlayerHasCreaturesSelectedCondition(data);
		case ConditionType.ifCreatureHasOrders:
			return parseTrigIfCreatureHasOrdersCondition(data);
		case ConditionType.ifStructureActiveValueCondition:
			return parseTrigIfStructureActiveValueCondition(data);
		case ConditionType.ifCurrentSideIsAnAiSide:
			return parseTrigIfCurrentSideIsAnAiSide(data);
		case ConditionType.ifCurrentSideIsAPlayerSide:
			return parseTrigIfCurrentSideIsAPlayerSide(data);
		case ConditionType.ifNttExists:
			return parseTrigIfNttExistsCondition(data);
		case ConditionType.ifNttExistsOnTheCurrentSide:
			return parseTrigIfNttExistsOnTheCurrentSideCondition(data);
		case ConditionType.ifCreatureIsAlive:
			return parseTrigIfCreatureIsAliveCondition(data);
		case ConditionType.or:
			return parseTrigOrCondition(data);
		case ConditionType.and:
			return parseTrigAndCondition(data);
		case ConditionType.not:
			return parseTrigNotCondition(data);
		default:
			enforce(0, text("unknown condition type: ",type));
			assert(0);
	}
}

enum ValueType{
	spell=13,
	formation=14,
	integer=24,
	creatureId=25,
	creatureType=26,
	structureId=27,
	structureType=28,
	sideId=30,
	creatureId2=37,
	nttType=39,
	variable=58,
	text=50,
	sample=75,
	missionObjective=79,
	god=82,
	autoSpell=135,
	filename=174,
	wizardId=239,
}

TrigCreature parseTrigCreature(ref ubyte[] data){
	auto vtype=parseUint(data);
	switch(vtype){
		case ValueType.creatureId,ValueType.creatureId2:
			auto id=parseUint(data);
			return new TrigCreature(id,vtype==ValueType.creatureId2);
		default:
			enforce(0, text("unknown creature value type: ",vtype));
			assert(0);
	}
}

TrigWizard parseTrigWizard(ref ubyte[] data){
	auto vtype=parseUint(data);
	switch(vtype){
		case ValueType.wizardId:
			auto id=parseUint(data);
			return new TrigWizard(id);
		default:
			enforce(0, text("unknown creature value type: ",vtype));
			assert(0);
	}
}

TrigStructure parseTrigStructure(ref ubyte[] data){
	auto vtype=parseUint(data);
	switch(vtype){
		case ValueType.structureId:
			auto id=parseUint(data);
			return new TrigStructure(id);
		default:
			enforce(0, text("unknown structure value type: ",vtype));
			assert(0);
	}
}

TrigNtt parseTrigNtt(ref ubyte[] data){
	auto nttType=parseUint(data);
	switch(nttType){
		case ValueType.creatureId,ValueType.creatureId2:
			auto id=parseUint(data);
			return new TrigCreature(id,nttType==ValueType.creatureId2);
		case ValueType.wizardId:
			auto id=parseUint(data);
			return new TrigWizard(id);
		case ValueType.structureId:
			auto id=parseUint(data);
			return new TrigStructure(id);
		default:
			enforce(0, text("unknown ntt type: ",nttType));
			assert(0);
	}
}

enum LocationType{
	marker=87,
	markerAtHeight=210,
	structure=29,
	creature=48,
}

uint parseTrigInteger(ref ubyte[] data){
	auto vtype=parseUint(data);
	enforce(vtype==ValueType.integer);
	return parseUint(data);
}

TrigLocation parseTrigLocation(ref ubyte[] data){
	auto locType=parseUint(data);
	switch(locType){
		case LocationType.marker:
			auto unknown=parseUint(data);
			enforce(unknown==88); // ?
			auto id=parseUint(data);
			return new TrigMarker(id);
		case LocationType.markerAtHeight:
			auto unknown=parseUint(data);
			enforce(unknown==88); // ?
			auto id=parseUint(data);
			auto quantityType=parseUint(data);
			enforce(quantityType==QuantityType.quantityInteger);
			auto height=parseTrigInteger(data);
			return new TrigMarkerAtHeight(id,height);
		case LocationType.structure,LocationType.creature:
			return new TrigAtNtt(parseTrigNtt(data));
		default:
			enforce(0, text("unknown location type: ",locType));
			assert(0);
	}
}

enum SpellSpecType{
	spellAtNtt=10,
	spellAtSoulOfNtt=241,
	spellAtLocation=11,
	spell=12,
	creatureSpell=217,
}

TrigSpellSpec parseTrigSpellSpec(ref ubyte[] data){
	auto specType=parseUint(data);
	auto unknown=parseUint(data);
	enforce(unknown==13); // ?
	auto tag=cast(char[4])data.eat(4)[0..4];
	switch(specType){
		case SpellSpecType.spellAtNtt:
			auto unknown2=parseUint(data);
			enforce(unknown2==ValueType.creatureId2); // ?
			auto ntt=parseUint(data);
			return new TrigSpellAtNtt(tag,ntt);
		case SpellSpecType.spellAtSoulOfNtt:
			auto unknown2=parseUint(data);
			enforce(unknown2==ValueType.creatureId); // ?
			auto ntt=parseUint(data);
			return new TrigSpellAtSoulOfNtt(tag,ntt);
		case SpellSpecType.spellAtLocation:
			auto location=parseTrigLocation(data);
			return new TrigSpellAtLocation(tag,location);
		case SpellSpecType.spell:
			return new TrigSpell(tag);
		case SpellSpecType.creatureSpell:
			return new TrigCreatureSpell(tag);
		default:
			enforce(0, text("unknown spell spec type: ",specType));
			assert(0);
	}
}

enum OrderType{
	attack=175,
	goToLocation=89,
	attackLocation=90,
	guardLocation=91,
	goToLocationInFormation=267,
	attackLocationInFormation=268,
	guardLocationInFormation=269,
	cast_=9,
	notify=73,
	turnToFaceLocation=120,
	passiveNotify=14,
	cancelOrders=92,
	die=136,
}
TrigOrder parseTrigOrder(ref ubyte[] data){
	auto otype=parseUint(data);
	switch(otype){
		case OrderType.attack:
			return new TrigOrderAttack(parseTrigNtt(data));
		case OrderType.goToLocation:
			return new TrigOrderGoToLocation(parseTrigLocation(data));
		case OrderType.attackLocation:
			return new TrigOrderAttackLocation(parseTrigLocation(data));
		case OrderType.guardLocation:
			return new TrigOrderGuardLocation(parseTrigLocation(data));
		case OrderType.goToLocationInFormation:
			auto location=parseTrigLocation(data);
			auto formation=parseTrigFormation(data);
			return new TrigOrderGoToLocationInFormation(location,formation);
		case OrderType.attackLocationInFormation:
			auto location=parseTrigLocation(data);
			auto formation=parseTrigFormation(data);
			return new TrigOrderAttackLocationInFormation(location,formation);
		case OrderType.guardLocationInFormation:
			auto location=parseTrigLocation(data);
			auto formation=parseTrigFormation(data);
			return new TrigOrderGuardLocationInFormation(location,formation);
		case OrderType.cast_:
			return new TrigOrderCast(parseTrigSpellSpec(data));
		case OrderType.notify:
			return new TrigOrderNotify(parseTrigCreature(data));
		case OrderType.turnToFaceLocation:
			return new TrigOrderTurnToFaceLocation(parseTrigLocation(data));
		case OrderType.passiveNotify:
			return new TrigOrderPassiveNotify();
		case OrderType.cancelOrders:
			return new TrigOrderCancelOrders();
		case OrderType.die:
			return new TrigOrderDie();
		default:
			enforce(0, text("unknown order type: ",otype));
			assert(0);
	}
}

TrigOrderAction parseTrigOrderAction(ref ubyte[] data){
	auto creature=parseTrigCreature(data);
	auto order=parseTrigOrder(data);
	return new TrigOrderAction(creature,order);
}

TrigCreature[] parseTrigCreatures(ref ubyte[] data){
	TrigCreature[] creatures;
listLoop: for(;;){
		auto listType=parseUint(data);
		creatures~=parseTrigCreature(data);
		switch(listType){
			case ListType.oneElement:
				break listLoop;
			case ListType.moreElements:
				break;
			default:
				enforce(0,text("unknown list type: ",listType));
		}
	}
	return creatures;
}

enum ListType{
	oneElement=145,
	moreElements=146,
}
TrigOrderListAction parseTrigOrderListAction(ref ubyte[] data){
	auto creatures=parseTrigCreatures(data);
	auto order=parseTrigOrder(data);
	return new TrigOrderListAction(creatures,order);
}

TrigOrderAllOfTypeAtLocationAction parseTrigOrderAllOfTypeAtLocationAction(ref ubyte[] data){
	auto ctype=parseTrigCreatureType(data);
	auto location=parseTrigLocation(data);
	auto order=parseTrigOrder(data);
	return new TrigOrderAllOfTypeAtLocationAction(ctype,location,order);
}
TrigOrderAllOfTypeAction parseTrigOrderAllOfTypeAction(ref ubyte[] data){
	auto ctype=parseTrigCreatureType(data);
	auto order=parseTrigOrder(data);
	return new TrigOrderAllOfTypeAction(ctype,order);
}
uint parseTrigSideId(ref ubyte[] data){
	auto vtype=parseUint(data);
	enforce(vtype==ValueType.sideId);
	return parseUint(data);
}
TrigDeclareStanceToSideAction parseTrigDeclareStanceToSideAction(ref ubyte[] data){
	auto stance=parseUint(data);
	auto side=parseTrigSideId(data);
	return new TrigDeclareStanceToSideAction(to!TrigStance(stance),side);
}
TrigChangeSideAction parseTrigChangeSideAction(ref ubyte[] data){
	auto ntt=parseTrigNtt(data);
	auto side=parseTrigSideId(data);
	return new TrigChangeSideAction(ntt,side);
}
char[4] parseTrigNttType(ref ubyte[] data){
	auto vtype0=parseUint(data);
	enforce(vtype0==ValueType.nttType);
	return cast(char[4])data.eat(4)[0..4];
}
TrigChangeSideAllOfTypeAction parseTrigChangeSideAllOfTypeAction(ref ubyte[] data){
	auto ctype=parseTrigNttType(data);
	auto side=parseTrigSideId(data);
	return new TrigChangeSideAllOfTypeAction(ctype,side);
}
TrigChangeSideAllOfTypeAction parseTrigChangeSideAllOfTypeAtLocationAction(ref ubyte[] data){
	auto ctype=parseTrigNttType(data);
	auto location=parseTrigLocation(data);
	auto side=parseTrigSideId(data);
	return new TrigChangeSideAllOfTypeAction(ctype,side);
}
uint parseTrigVariable(ref ubyte[] data){
	auto vtype=parseUint(data);
	enforce(vtype==ValueType.variable);
	return parseUint(data);
}
TrigDisplayVariableAction parseTrigDisplayVariableAction(ref ubyte[] data){
	auto variable=parseTrigVariable(data);
	return new TrigDisplayVariableAction(variable);
}
char[4] parseTrigText(ref ubyte[] data){
	auto vtype=parseUint(data);
	enforce(vtype==ValueType.text);
	return cast(char[4])data.eat(4)[0..4];
}
TrigDisplayTextAction parseTrigDisplayTextAction(ref ubyte[] data){
	auto text=parseTrigText(data);
	return new TrigDisplayTextAction(text);
}
TrigHideVariableAction parseTrigHideVariableAction(ref ubyte[] data){
	auto variable=parseTrigVariable(data);
	return new TrigHideVariableAction(variable);
}
TrigClearTextAction parseTrigClearTextAction(ref ubyte[] data){
	return new TrigClearTextAction();
}
char[4] parseTrigSample(ref ubyte[] data){
	auto vtype=parseUint(data);
	enforce(vtype==ValueType.sample);
	return cast(char[4])data.eat(4)[0..4];
}
TrigPlaySampleAction parseTrigPlaySampleAction(ref ubyte[] data){
	auto sample=parseTrigSample(data);
	return new TrigPlaySampleAction(sample);
}
TrigCreateCreatureTypeAtLocationAction parseTrigCreateCreatureTypeAtLocationAction(ref ubyte[] data){
	auto ctype=parseTrigCreatureType(data);
	auto location=parseTrigLocation(data);
	return new TrigCreateCreatureTypeAtLocationAction(ctype,location);
}
TrigCreateCreatureTypeOnSideAtLocationAction parseTrigCreateCreatureTypeOnSideAtLocationAction(ref ubyte[] data){
	auto ctype=parseTrigCreatureType(data);
	auto side=parseTrigSideId(data);
	auto location=parseTrigLocation(data);
	return new TrigCreateCreatureTypeOnSideAtLocationAction(ctype,side,location);
}
TrigCreateMultipleCreatureTypeOnSideAtLocationAction parseTrigCreateMultipleCreatureTypeOnSideAtLocationAction(ref ubyte[] data){
	auto quantityType=parseUint(data);
	enforce(quantityType==QuantityType.quantityInteger);
	auto amount=parseTrigInteger(data);
	auto ctype=parseTrigCreatureType(data);
	auto side=parseTrigSideId(data);
	auto location=parseTrigLocation(data);
	return new TrigCreateMultipleCreatureTypeOnSideAtLocationAction(amount,ctype,side,location);
}
enum QuantityType{
	quantityTrue=137,
	quantityFalse=138,
	quantityInteger=66,
	quantityVariable=71,
	quantityAdd=62,
	quantitySub=63,
	quantityMul=64,
	quantityDiv=65,
	quantityStat=218,
}
TrigQuantity parseTrigQuantity(ref ubyte[] data){
	auto vtype=parseUint(data);
	switch(vtype){
		case QuantityType.quantityTrue: return new TrigQuantityTrue();
		case QuantityType.quantityFalse: return new TrigQuantityFalse();
		case QuantityType.quantityInteger: return new TrigQuantityInteger(parseTrigInteger(data));
		case QuantityType.quantityVariable: return new TrigQuantityVariable(parseTrigVariable(data));
		case QuantityType.quantityAdd:
			auto a=parseTrigQuantity(data);
			auto b=parseTrigQuantity(data);
			return new TrigQuantityAdd(a,b);
		case QuantityType.quantitySub:
			auto a=parseTrigQuantity(data);
			auto b=parseTrigQuantity(data);
			return new TrigQuantitySub(a,b);
		case QuantityType.quantityMul:
			auto a=parseTrigQuantity(data);
			auto b=parseTrigQuantity(data);
			return new TrigQuantityMul(a,b);
		case QuantityType.quantityDiv:
			auto a=parseTrigQuantity(data);
			auto b=parseTrigQuantity(data);
			return new TrigQuantityDiv(a,b);
		case QuantityType.quantityStat:
			auto stat=to!TrigCreatureStat(parseUint(data));
			auto creature=parseTrigCreature(data);
			return new TrigQuantityCreatureStat(stat,creature);
		default:
			enforce(0, text("unknown variable quantity type: ",vtype));
			assert(0);
	}
}
TrigSetVariableAction parseTrigSetVariableAction(ref ubyte[] data){
	auto variable=parseTrigVariable(data);
	auto quantity=parseTrigQuantity(data);
	return new TrigSetVariableAction(variable,quantity);
}

enum QuantifiedNttType{
	creatureType=67,
	structureType=68,
	creatureTypeAtLocation=69,
	structureTypeAtLocation=70,
}

TrigQuantifiedNtts parseTrigQuantifiedNtts(ref ubyte[] data){
	auto qnttType=parseUint(data);
	switch(qnttType){
		case QuantifiedNttType.creatureType:
			auto ctype=parseTrigCreatureType(data);
			return new TrigCreatureTypeNtts(ctype);
		case QuantifiedNttType.structureType:
			auto stype=parseTrigStructureType(data);
			return new TrigStructureTypeNtts(stype);
		case QuantifiedNttType.creatureTypeAtLocation:
			auto ctype=parseTrigCreatureType(data);
			auto location=parseTrigLocation(data);
			return new TrigCreatureTypeAtLocationNtts(ctype,location);
		case QuantifiedNttType.structureTypeAtLocation:
			auto stype=parseTrigStructureType(data);
			auto location=parseTrigLocation(data);
			return new TrigStructureTypeAtLocationNtts(stype,location);
		default:
			enforce(0, text("unknown quantified ntt type: ",qnttType));
			assert(0);
	}
}
TrigSetVariableToNumberOfNttsAction parseTrigSetVariableToNumberOfNttsAction(ref ubyte[] data){
	auto variable=parseTrigVariable(data);
	auto quantifiedNtts=parseTrigQuantifiedNtts(data);
	return new TrigSetVariableToNumberOfNttsAction(variable,quantifiedNtts);
}
TrigSetVariableToResourceOfNttAction parseTrigSetVariableToResourceOfNttAction(ref ubyte[] data){
	auto variable=parseTrigVariable(data);
	auto resource=parseUint(data);
	auto ntt=parseTrigNtt(data);
	return new TrigSetVariableToResourceOfNttAction(variable,to!TrigResource(resource),ntt);
}
TrigSetVariableToResourceOfNttsAction parseTrigSetVariableToResourceOfNttsAction(ref ubyte[] data){
	auto variable=parseTrigVariable(data);
	auto resource=parseUint(data);
	auto quantifiedNtts=parseTrigQuantifiedNtts(data);
	return new TrigSetVariableToResourceOfNttsAction(variable,to!TrigResource(resource),quantifiedNtts);
}
TrigSetVariableToRandomNumberInRangeAction parseTrigSetVariableToRandomNumberInRangeAction(ref ubyte[] data){
	auto variable=parseTrigVariable(data);
	auto low=parseTrigQuantity(data);
	auto high=parseTrigQuantity(data);
	return new TrigSetVariableToRandomNumberInRangeAction(variable,low,high);
}

enum TrigActorNameType{
	text=180,
	playerWizard=179,
}
TrigActorName parseTrigActorName(ref ubyte[] data){
	auto anType=parseUint(data);
	switch(anType){
		case TrigActorNameType.text:
			auto text=parseTrigText(data);
			return new TrigActorNameText(text);
		case TrigActorNameType.playerWizard:
			return new TrigActorNamePlayerWizard();
		default:
			enforce(0, text("unknown actor name type: ",anType));
			assert(0);
	}
}

enum TrigActorType{
	creature=176,
	god=177,
	name=178,
}
TrigActor parseTrigActor(ref ubyte[] data){
	auto actorType=parseUint(data);
	switch(actorType){
		case TrigActorType.creature:
			auto creature=parseTrigCreature(data);
			return new TrigActorCreature(creature);
		case TrigActorType.god:
			auto god=parseUint(data);
			return new TrigActorGod(to!TrigGod(god));
		case TrigActorType.name:
			return parseTrigActorName(data);
		default:
			enforce(0,text("unknown actor type: ",actorType));
			assert(0);
	}
}

enum TrigSpeaksType{
	says=181,
	saysWithEmotion=211,
	asks=182,
	asksWithEmotion=212,
	exclaims=183,
	exclaimsWithEmotion=213,
	narrates=190,
}
TrigSpeaks parseTrigSpeaks(ref ubyte[] data){
	auto stype=parseUint(data);
	switch(stype){
		case TrigSpeaksType.says:
			return new TrigSays();
		case TrigSpeaksType.saysWithEmotion:
			auto emotion=parseUint(data);
			return new TrigSaysWithEmotion(to!TrigEmotion(emotion));
		case TrigSpeaksType.asks:
			return new TrigAsks();
		case TrigSpeaksType.asksWithEmotion:
			auto emotion=parseUint(data);
			return new TrigAsksWithEmotion(to!TrigEmotion(emotion));
		case TrigSpeaksType.exclaims:
			return new TrigExclaims();
		case TrigSpeaksType.exclaimsWithEmotion:
			auto emotion=parseUint(data);
			return new TrigExclaimsWithEmotion(to!TrigEmotion(emotion));
		case TrigSpeaksType.narrates:
			return new TrigNarrates();
		default:
			enforce(0, text("unknown speaks type: ",stype));
			assert(0);
	}
}

enum TrigTimingType{
	autoTimed=184,
	sampleLengthMinusFrames=185,
	persistent=186,
	pauseForInput=187,
	forFrames=188,
}
TrigTiming parseTrigTiming(ref ubyte[] data){
	auto ttype=parseUint(data);
	switch(ttype){
		case TrigTimingType.autoTimed:
			return new TrigAutoTimed();
		case TrigTimingType.sampleLengthMinusFrames:
			auto quantity=parseTrigQuantity(data);
			return new TrigSampleLengthMinusFrames(quantity);
		case TrigTimingType.persistent:
			return new TrigPersistent();
		case TrigTimingType.pauseForInput:
			return new TrigPauseForInput();
		case TrigTimingType.forFrames:
			auto quantity=parseTrigQuantity(data);
			return new TrigForFrames(quantity);
		default:
			enforce(0,text("unknown timing type: ",ttype));
			assert(0);
	}
}
enum TrigSampleSpecType{
	withSampleNone=0,
	withSample=189,
}
TrigSampleSpec parseTrigSampleSpec(ref ubyte[] data){
	auto type=parseUint(data);
	switch(type){
		case TrigSampleSpecType.withSampleNone:
			return new TrigWithSampleNone();
		case TrigSampleSpecType.withSample:
			auto sample=parseTrigSample(data);
			return new TrigWithSample(sample);
		default:
			enforce(0, text("unknown sample spec type: ",type));
			assert(0);
	}
}
TrigSpeechWithTextAction parseTrigSpeechWithTextAction(ref ubyte[] data){
	auto actor=parseTrigActor(data);
	auto speaks=parseTrigSpeaks(data);
	auto text=parseTrigText(data);
	auto timing=parseTrigTiming(data);
	auto sampleSpec=parseTrigSampleSpec(data);
	return new TrigSpeechWithTextAction(actor,speaks,text,timing,sampleSpec);
}
TrigSpeechCreatureSpeaksSampleAction parseTrigSpeechCreatureSpeaksSampleAction(ref ubyte[] data){
	auto creature=parseTrigCreature(data);
	auto speaks=parseTrigSpeaks(data);
	auto sample=parseTrigSample(data);
	return new TrigSpeechCreatureSpeaksSampleAction(creature,speaks,sample);
}
TrigSpeechCreatureSaysTextWithSampleAction parseTrigSpeechCreatureSaysTextWithSampleAction(ref ubyte[] data){
	auto creature=parseTrigCreature(data);
	auto text=parseTrigText(data);
	auto sample=parseTrigSample(data);
	return new TrigSpeechCreatureSaysTextWithSampleAction(creature,text,sample);
}
TrigSpeechCreatureAsksTextWithSampleAction parseTrigSpeechCreatureAsksTextWithSampleAction(ref ubyte[] data){
	auto creature=parseTrigCreature(data);
	auto text=parseTrigText(data);
	auto sample=parseTrigSample(data);
	return new TrigSpeechCreatureAsksTextWithSampleAction(creature,text,sample);
}
TrigSpeechCreatureExclaimsTextWithSampleAction parseTrigSpeechCreatureExclaimsTextWithSampleAction(ref ubyte[] data){
	auto creature=parseTrigCreature(data);
	auto text=parseTrigText(data);
	auto sample=parseTrigSample(data);
	return new TrigSpeechCreatureExclaimsTextWithSampleAction(creature,text,sample);
}
TrigSpeechGodSaysTextWithSampleAction parseTrigSpeechGodSaysTextWithSampleAction(ref ubyte[] data){
	auto god=parseUint(data);
	auto text=parseTrigText(data);
	auto sample=parseTrigSample(data);
	return new TrigSpeechGodSaysTextWithSampleAction(to!TrigGod(god),text,sample);
}
TrigSpeechNarratorNarratesTextWithSampleAction parseTrigSpeechNarratorNarratesTextWithSampleAction(ref ubyte[] data){
	auto narrator=parseUint(data);
	auto text=parseTrigText(data);
	auto sample=parseTrigSample(data);
	return new TrigSpeechNarratorNarratesTextWithSampleAction(to!TrigNarrator(narrator),text,sample);
}
uint parseMissionObjective(ref ubyte[] data){
	auto vtype=parseUint(data);
	enforce(vtype==ValueType.missionObjective);
	return parseUint(data);
}
TrigSetObjectiveCompleteAction parseTrigSetObjectiveCompleteAction(ref ubyte[] data){
	auto missionObjective=parseMissionObjective(data);
	return new TrigSetObjectiveCompleteAction(missionObjective);
}
TrigEnableObjectiveAction parseTrigEnableObjectiveAction(ref ubyte[] data){
	auto missionObjective=parseMissionObjective(data);
	return new TrigEnableObjectiveAction(missionObjective);
}
TrigDisableObjectiveAction parseTrigDisableObjectiveAction(ref ubyte[] data){
	auto missionObjective=parseMissionObjective(data);
	return new TrigDisableObjectiveAction(missionObjective);
}
TrigTeleportAllOfTypeAtLocationToLocationAction parseTrigTeleportAllOfTypeAtLocationToLocationAction(ref ubyte[] data){
	auto ctype=parseTrigCreatureType(data);
	auto location1=parseTrigLocation(data);
	auto location2=parseTrigLocation(data);
	return new TrigTeleportAllOfTypeAtLocationToLocationAction(ctype,location1,location2);
}
TrigTeleportAllOfTypeAtLocationAwayAction parseTrigTeleportAllOfTypeAtLocationAwayAction(ref ubyte[] data){
	auto ctype=parseTrigCreatureType(data);
	auto location=parseTrigLocation(data);
	return new TrigTeleportAllOfTypeAtLocationAwayAction(ctype,location);
}
TrigTeleportCreatureToLocationAction parseTrigTeleportCreatureToLocationAction(ref ubyte[] data){
	auto creature=parseTrigCreature(data);
	auto location=parseTrigLocation(data);
	return new TrigTeleportCreatureToLocationAction(creature,location);
}
TrigTeleportCreatureAwayAction parseTrigTeleportCreatureAwayAction(ref ubyte[] data){
	auto creature=parseTrigCreature(data);
	return new TrigTeleportCreatureAwayAction(creature);
}
TrigSetGameTimerAction parseTrigSetGameTimerAction(ref ubyte[] data){
	auto quantity=parseTrigQuantity(data);
	return new TrigSetGameTimerAction(quantity);
}
TrigDisplayGameTimerAction parseTrigDisplayGameTimerAction(ref ubyte[] data){
	return new TrigDisplayGameTimerAction();
}
TrigHideGameTimerAction parseTrigHideGameTimerAction(ref ubyte[] data){
	return new TrigHideGameTimerAction();
}
enum AiSettingType{
	paused=101,
	unpaused=102,
	aggression=238,
}
TrigAiSetting parseTrigAiSetting(ref ubyte[] data){
	auto aiType=parseUint(data);
	switch(aiType){
		case AiSettingType.paused:
			return new TrigAiPaused();
		case AiSettingType.unpaused:
			return new TrigAiUnpaused();
		case AiSettingType.aggression:
			auto quantity=parseTrigQuantity(data);
			return new TrigAiAggressionToQuantity(quantity);
		default:
			enforce(0,text("unknown ai setting type: ",aiType));
			assert(0);
	}
}
TrigSetAiSetting parseTrigSetAiSetting(ref ubyte[] data){
	return new TrigSetAiSetting(parseTrigAiSetting(data));
}
TrigTurnBeaconAtLocationAction parseTrigTurnBeaconAtLocationAction(ref ubyte[] data){
	auto beaconSetting=parseUint(data);
	auto location=parseTrigLocation(data);
	return new TrigTurnBeaconAtLocationAction(to!TrigSwitch(beaconSetting),location);
}

TrigCinematicsStartAction parseTrigCinematicsStartAction(ref ubyte[] data){
	return new TrigCinematicsStartAction();
}
TrigCinematicsEndAction parseTrigCinematicsEndAction(ref ubyte[] data){
	return new TrigCinematicsEndAction();
}

TrigSetViewFocusToLocationAction parseTrigSetViewFocusToLocationAction(ref ubyte[] data){
	auto location=parseTrigLocation(data);
	return new TrigSetViewFocusToLocationAction(location);
}
TrigSetViewOriginFromLocationAction parseTrigSetViewOriginFromLocationAction(ref ubyte[] data){
	auto location=parseTrigLocation(data);
	return new TrigSetViewOriginFromLocationAction(location);
}
TrigSetViewOriginFromLocationFocusToLocationAction parseTrigSetViewOriginFromLocationFocusToLocationAction(ref ubyte[] data){
	auto location1=parseTrigLocation(data);
	auto location2=parseTrigLocation(data);
	return new TrigSetViewOriginFromLocationFocusToLocationAction(location1,location2);
}

TrigSetViewZoomAction parseTrigSetViewZoomAction(ref ubyte[] data){
	auto zoomLevel=parseUint(data);
	return new TrigSetViewZoomAction(to!TrigZoomLevel(zoomLevel));
}

TrigSetViewSpeedAction parseTrigSetViewSpeedAction(ref ubyte[] data){
	auto quantity=parseTrigQuantity(data);
	return new TrigSetViewSpeedAction(quantity);
}

TrigGiveCreatureResourceAction parseTrigGiveCreatureResourceAction(ref ubyte[] data){
	auto creature=parseTrigCreature(data);
	auto quantity=parseTrigQuantity(data);
	auto resource=parseUint(data);
	return new TrigGiveCreatureResourceAction(creature,quantity,to!TrigResource(resource));
}

TrigGiveAllOfTypeAtLocationResourceAction parseTrigGiveAllOfTypeAtLocationResourceAction(ref ubyte[] data){
	auto ctype=parseTrigCreatureType(data);
	auto location=parseTrigLocation(data);
	auto quantity=parseTrigQuantity(data);
	auto resource=parseUint(data);
	return new TrigGiveAllOfTypeAtLocationResourceAction(ctype,location,quantity,to!TrigResource(resource));
}

char[4] parseTrigSpell(ref ubyte[] data,ValueType tvtype)in{
	assert(tvtype==ValueType.spell||tvtype==ValueType.autoSpell);
}do{
	auto vtype=parseUint(data);
	enforce(vtype==tvtype);
	return cast(char[4])data.eat(4)[0..4];
}

TrigGiveWizardSpellAction parseTrigGiveWizardSpellAction(ref ubyte[] data){
	auto wizard=parseTrigWizard(data);
	auto spell=parseTrigSpell(data,ValueType.spell);
	return new TrigGiveWizardSpellAction(wizard,spell);
}

TrigCastSpellAtLocationAction parseTrigCastSpellAtLocationAction(ref ubyte[] data){
	auto spell=parseTrigSpell(data,ValueType.autoSpell);
	auto location=parseTrigLocation(data);
	return new TrigCastSpellAtLocationAction(spell,location);
}

TrigSetNttStateAction parseTrigSetNttStateAction(ref ubyte[] data){
	auto ntt=parseTrigNtt(data);
	auto state=parseUint(data);
	auto switch_=parseUint(data);
	return new TrigSetNttStateAction(ntt,to!TrigNttState(state),to!TrigSwitch(switch_));
}

TrigSetAllOfTypeStateAction parseTrigSetAllOfTypeStateAction(ref ubyte[] data){
	auto nttType=parseTrigNttType(data);
	auto state=parseUint(data);
	auto switch_=parseUint(data);
	return new TrigSetAllOfTypeStateAction(nttType,to!TrigNttState(state),to!TrigSwitch(switch_));
}

TrigSetAllOfTypeAtLocationStateAction parseTrigSetAllOfTypeAtLocationStateAction(ref ubyte[] data){
	auto nttType=parseTrigNttType(data);
	auto location=parseTrigLocation(data);
	auto state=parseUint(data);
	auto switch_=parseUint(data);
	return new TrigSetAllOfTypeAtLocationStateAction(nttType,location,to!TrigNttState(state),to!TrigSwitch(switch_));
}

TrigSetCreatureStatAction parseTrigSetCreatureStatAction(ref ubyte[] data){
	auto creature=parseTrigCreature(data);
	auto stat=parseUint(data);
	auto quantity=parseTrigQuantity(data);
	return new TrigSetCreatureStatAction(creature,to!TrigCreatureStat(stat),quantity);
}

TrigSetWeatherAction parseTrigSetWeather(ref ubyte[] data){
	auto weather=parseUint(data);
	auto switch_=parseUint(data);
	return new TrigSetWeatherAction(to!TrigWeather(weather),to!TrigSwitch(switch_));
}

char[4] parseTrigFilename(ref ubyte[] data){
	auto vtype=parseUint(data);
	enforce(vtype==ValueType.filename);
	return cast(char[4])data.eat(4)[0..4];
}
TrigSetNextMissionFilenameAction parseTrigSetNextMissionFilename(ref ubyte[] data){
	auto filename=parseTrigFilename(data);
	return new TrigSetNextMissionFilenameAction(filename);
}

TrigSetNextMissionIdAction parseTrigSetNextMissionIdAction(ref ubyte[] data){
	auto missionId=parseUint(data);
	return new TrigSetNextMissionIdAction(to!TrigMissionId(missionId));
}

TrigFadeToColorOverFramesAction parseTrigFadeToColorOverFramesAction(ref ubyte[] data){
	auto color=parseUint(data);
	auto quantity=parseTrigQuantity(data);
	return new TrigFadeToColorOverFramesAction(to!TrigColor(color),quantity);
}

TrigScreenShakeAtLocationAction parseTrigScreenShakeAtLocationAction(ref ubyte[] data){
	auto location=parseTrigLocation(data);
	return new TrigScreenShakeAtLocationAction(location);
}

TrigTurnInterfaceElement parseTrigTurnInterfaceElement(ref ubyte[] data){
	auto interfaceElement=parseUint(data);
	auto switch_=parseUint(data);
	return new TrigTurnInterfaceElement(to!TrigInterfaceElement(interfaceElement),to!TrigSwitch(switch_));
}

TrigSetStructureActiveLevelAction parseTrigSetStructureActiveLevelAction(ref ubyte[] data){
	auto structure=parseTrigStructure(data);
	auto activeLevel=parseTrigQuantity(data);
	return new TrigSetStructureActiveLevelAction(structure,activeLevel);
}

TrigAskTextAction parseTrigAskTextAction(ref ubyte[] data){
	auto question=parseTrigText(data);
	auto option_a=parseTrigText(data);
	auto option_b=parseTrigText(data);
	auto variable=parseTrigVariable(data);
	return new TrigAskTextAction(question,option_a,option_b,variable);
}
TrigAskTextWithSampleAction parseTrigAskTextWithSampleAction(ref ubyte[] data){
	auto question=parseTrigText(data);
	auto sample=parseTrigSampleSpec(data);
	auto option_a=parseTrigText(data);
	auto option_b=parseTrigText(data);
	auto variable=parseTrigVariable(data);
	return new TrigAskTextWithSampleAction(question,sample,option_a,option_b,variable);
}

TrigShowRandomTipAction parseTrigShowRandomTipAction(ref ubyte[] data){
	return new TrigShowRandomTipAction();
}
TrigShowTipTextAction parseTrigShowTipTextAction(ref ubyte[] data){
	auto text=parseTrigText(data);
	return new TrigShowTipTextAction(text);
}
TrigSuppressTipboxAction parseTrigSuppressTipboxAction(ref ubyte[] data){
	return new TrigSuppressTipboxAction();
}

TrigAddTextWithSampleToSpeechHistoryAction parseTrigAddTextWithSampleToSpeechHistoryAction(ref ubyte[] data){
	auto text=parseTrigText(data);
	auto sampleSpec=parseTrigSampleSpec(data);
	return new TrigAddTextWithSampleToSpeechHistoryAction(text,sampleSpec);
}
TrigAddIntroSampleToSpeechHistoryAction parseTrigAddIntroSampleToSpeechHistoryAction(ref ubyte[] data){
	auto sample=parseTrigSample(data);
	return new TrigAddIntroSampleToSpeechHistoryAction(sample);
}

TrigMusicResetAction parseTrigMusicResetAction(ref ubyte[] data){
	return new TrigMusicResetAction();
}
TrigMusicAddToMoodAction parseTrigMusicAddToMoodAction(ref ubyte[] data){
	auto quantity=parseTrigQuantity(data);
	auto mood=parseUint(data);
	return new TrigMusicAddToMoodAction(quantity,to!TrigMood(mood));
}
TrigMusicTurnAction parseTrigMusicTurnAction(ref ubyte[] data){
	auto switch_=parseUint(data);
	return new TrigMusicTurnAction(to!TrigSwitch(switch_));
}

enum ActionType{
	order=4,
	orderList=147,
	orderAllOfTypeAtLocation=6,
	orderAllOfType=5,
	pause=51,
	endMissionInDefeat=7,
	endMissionInVictory=8,
	endMission=170,
	declareStanceToSide=32,
	changeSide=36,
	changeSideAllOfType=38,
	changeSideAllOfTypeAtLocation=143,
	displayVariable=61,
	displayText=49,
	hideVariable=72,
	clearText=52,
	playSample=98,
	createCreatureTypeAtLocation=56,
	createCreatureTypeOnSideAtLocation=80,
	createMultipleCreatureTypeOnSideAtLocation=142,
	setVariable=57,
	setVariableToNumberOfNtts=60,
	setVariableToResourceOfNtt=196,
	setVariableToResourceOfNtts=259,
	setVariableToRandomNumberInRange=162,
	speechWithText=23,
	speechCreatureSpeaksSample=258,
	speechCreatureSaysTextWithSample=74,
	speechCreatureAsksTextWithSample=127,
	speechCreatureExclaimsTextWithSample=128,
	speechGodSaysTextWithSample=81,
	speechNarratorNarratesTextWithSample=114,
	setObjectiveComplete=76,
	enableObjective=77,
	disableObjective=78,
	teleportAllOfTypeAtLocationToLocation=93,
	teleportAllOfTypeAtLocationAway=94,
	teleportCreatureToLocation=149,
	teleportCreatureAway=150,
	setGameTimer=95,
	displayGameTimer=96,
	hideGameTimer=97,
	setAiSetting=100,
	turnBeaconAtLocation=106,
	cinematicsStart=109,
	cinematicsEnd=110,
	setViewFocusToLocation=112,
	setViewOriginFromLocation=111,
	setViewOriginFromLocationFocusToLocation=113,
	setViewZoomLevel=121,
	setViewSpeed=141,
	giveCreatureResource=129,
	giveAllOfTypeAtLocationResource=133,
	giveWizardSpell=240,
	castSpellAtLocation=134,
	setNttState=153,
	setAllOfTypeState=154,
	setAllOfTypeAtLocationState=155,
	setCreatureStat=234,
	setWeather=169,
	setNextMissionFilename=171,
	setNextMissionId=172,
	fadeToColorOverFrames=191,
	screenShakeAtLocation=197,
	turnInterfaceElement=198,
	setStructureActiveLevel=205,
	askText=206,
	askTextWithSample=209,
	showRandomTip=207,
	showTipText=208,
	suppressTipbox=255,
	addTextWithSampleToSpeechHistory=260,
	addIntroSampleToSpeechHistory=261,
	musicReset=263,
	musicAddToMood=264,
	musicTurn=265,
}

TrigAction parseTrigAction(ref ubyte[] data){
	auto type=parseUint(data);
	switch(type){
		case ActionType.order:
			return parseTrigOrderAction(data);
		case ActionType.orderList:
			return parseTrigOrderListAction(data);
		case ActionType.orderAllOfTypeAtLocation:
			return parseTrigOrderAllOfTypeAtLocationAction(data);
		case ActionType.orderAllOfType:
			return parseTrigOrderAllOfTypeAction(data);
		case ActionType.pause:
			auto vtype=parseUint(data);
			enforce(vtype==24);
			auto numFrames=parseUint(data);
			return new TrigPauseAction(numFrames);
		case ActionType.endMissionInDefeat:
			return new TrigEndMissionInDefeatAction();
		case ActionType.endMissionInVictory:
			return new TrigEndMissionInVictoryAction();
		case ActionType.endMission:
			return new TrigEndMissionAction();
		case ActionType.declareStanceToSide:
			return parseTrigDeclareStanceToSideAction(data);
		case ActionType.changeSide:
			return parseTrigChangeSideAction(data);
		case ActionType.changeSideAllOfType:
			return parseTrigChangeSideAllOfTypeAction(data);
		case ActionType.changeSideAllOfTypeAtLocation:
			return parseTrigChangeSideAllOfTypeAtLocationAction(data);
		case ActionType.displayVariable:
			return parseTrigDisplayVariableAction(data);
		case ActionType.displayText:
			return parseTrigDisplayTextAction(data);
		case ActionType.hideVariable:
			return parseTrigHideVariableAction(data);
		case ActionType.clearText:
			return parseTrigClearTextAction(data);
		case ActionType.playSample:
			return parseTrigPlaySampleAction(data);
		case ActionType.createCreatureTypeAtLocation:
			return parseTrigCreateCreatureTypeAtLocationAction(data);
		case ActionType.createCreatureTypeOnSideAtLocation:
			return parseTrigCreateCreatureTypeOnSideAtLocationAction(data);
		case ActionType.createMultipleCreatureTypeOnSideAtLocation:
			return parseTrigCreateMultipleCreatureTypeOnSideAtLocationAction(data);
		case ActionType.setVariable:
			return parseTrigSetVariableAction(data);
		case ActionType.setVariableToNumberOfNtts:
			return parseTrigSetVariableToNumberOfNttsAction(data);
		case ActionType.setVariableToResourceOfNtt:
			return parseTrigSetVariableToResourceOfNttAction(data);
		case ActionType.setVariableToResourceOfNtts:
			return parseTrigSetVariableToResourceOfNttsAction(data);
		case ActionType.setVariableToRandomNumberInRange:
			return parseTrigSetVariableToRandomNumberInRangeAction(data);
		case ActionType.speechWithText:
			return parseTrigSpeechWithTextAction(data);
		case ActionType.speechCreatureSpeaksSample:
			return parseTrigSpeechCreatureSpeaksSampleAction(data);
		case ActionType.speechCreatureSaysTextWithSample:
			return parseTrigSpeechCreatureSaysTextWithSampleAction(data);
		case ActionType.speechCreatureAsksTextWithSample:
			return parseTrigSpeechCreatureAsksTextWithSampleAction(data);
		case ActionType.speechCreatureExclaimsTextWithSample:
			return parseTrigSpeechCreatureExclaimsTextWithSampleAction(data);
		case ActionType.speechGodSaysTextWithSample:
			return parseTrigSpeechGodSaysTextWithSampleAction(data);
		case ActionType.speechNarratorNarratesTextWithSample:
			return parseTrigSpeechNarratorNarratesTextWithSampleAction(data);
		case ActionType.setObjectiveComplete:
			return parseTrigSetObjectiveCompleteAction(data);
		case ActionType.enableObjective:
			return parseTrigEnableObjectiveAction(data);
		case ActionType.disableObjective:
			return parseTrigDisableObjectiveAction(data);
		case ActionType.teleportAllOfTypeAtLocationToLocation:
			return parseTrigTeleportAllOfTypeAtLocationToLocationAction(data);
		case ActionType.teleportAllOfTypeAtLocationAway:
			return parseTrigTeleportAllOfTypeAtLocationAwayAction(data);
		case ActionType.teleportCreatureToLocation:
			return parseTrigTeleportCreatureToLocationAction(data);
		case ActionType.teleportCreatureAway:
			return parseTrigTeleportCreatureAwayAction(data);
		case ActionType.setGameTimer:
			return parseTrigSetGameTimerAction(data);
		case ActionType.displayGameTimer:
			return parseTrigDisplayGameTimerAction(data);
		case ActionType.hideGameTimer:
			return parseTrigHideGameTimerAction(data);
		case ActionType.setAiSetting:
			return parseTrigSetAiSetting(data);
		case ActionType.turnBeaconAtLocation:
			return parseTrigTurnBeaconAtLocationAction(data);
		case ActionType.cinematicsStart:
			return parseTrigCinematicsStartAction(data);
		case ActionType.cinematicsEnd:
			return parseTrigCinematicsEndAction(data);
		case ActionType.setViewFocusToLocation:
			return parseTrigSetViewFocusToLocationAction(data);
		case ActionType.setViewOriginFromLocation:
			return parseTrigSetViewOriginFromLocationAction(data);
		case ActionType.setViewOriginFromLocationFocusToLocation:
			return parseTrigSetViewOriginFromLocationFocusToLocationAction(data);
		case ActionType.setViewZoomLevel:
			return parseTrigSetViewZoomAction(data);
		case ActionType.setViewSpeed:
			return parseTrigSetViewSpeedAction(data);
		case ActionType.giveCreatureResource:
			return parseTrigGiveCreatureResourceAction(data);
		case ActionType.giveAllOfTypeAtLocationResource:
			return parseTrigGiveAllOfTypeAtLocationResourceAction(data);
		case ActionType.giveWizardSpell:
			return parseTrigGiveWizardSpellAction(data);
		case ActionType.castSpellAtLocation:
			return parseTrigCastSpellAtLocationAction(data);
		case ActionType.setNttState:
			return parseTrigSetNttStateAction(data);
		case ActionType.setAllOfTypeState:
			return parseTrigSetAllOfTypeStateAction(data);
		case ActionType.setAllOfTypeAtLocationState:
			return parseTrigSetAllOfTypeAtLocationStateAction(data);
		case ActionType.setCreatureStat:
			return parseTrigSetCreatureStatAction(data);
		case ActionType.setWeather:
			return parseTrigSetWeather(data);
		case ActionType.setNextMissionFilename:
			return parseTrigSetNextMissionFilename(data);
		case ActionType.setNextMissionId:
			return parseTrigSetNextMissionIdAction(data);
		case ActionType.fadeToColorOverFrames:
			return parseTrigFadeToColorOverFramesAction(data);
		case ActionType.screenShakeAtLocation:
			return parseTrigScreenShakeAtLocationAction(data);
		case ActionType.turnInterfaceElement:
			return parseTrigTurnInterfaceElement(data);
		case ActionType.setStructureActiveLevel:
			return parseTrigSetStructureActiveLevelAction(data);
		case ActionType.askText:
			return parseTrigAskTextAction(data);
		case ActionType.askTextWithSample:
			return parseTrigAskTextWithSampleAction(data);
		case ActionType.showRandomTip:
			return parseTrigShowRandomTipAction(data);
		case ActionType.showTipText:
			return parseTrigShowTipTextAction(data);
		case ActionType.suppressTipbox:
			return parseTrigSuppressTipboxAction(data);
		case ActionType.addTextWithSampleToSpeechHistory:
			return parseTrigAddTextWithSampleToSpeechHistoryAction(data);
		case ActionType.addIntroSampleToSpeechHistory:
			return parseTrigAddIntroSampleToSpeechHistoryAction(data);
		case ActionType.musicReset:
			return parseTrigMusicResetAction(data);
		case ActionType.musicAddToMood:
			return parseTrigMusicAddToMoodAction(data);
		case ActionType.musicTurn:
			return parseTrigMusicTurnAction(data);
		default:
			enforce(0, text("unknown action type: ",type));
			assert(0);
	}
}

Trigger parseTrigger(ref ubyte[] data){
	auto flags=parseUint(data);
	auto sides=parseUint(data);
	auto numCond=parseUint(data);
	auto numCmd=parseUint(data);
	auto conds=data.eat(numCond);
	TrigCondition[] conditions;
	while(conds.length) conditions~=parseTrigCondition(conds);
	auto cmds=data.eat(numCmd);
	TrigAction[] actions;
	while(cmds.length) actions~=parseTrigAction(cmds);
	return Trigger(flags,sides,conditions,actions);
}

struct Trig{
	Trigger[] triggers;
}

Trig parseTRIG(ubyte[] data){
	auto numTrigs=parseUint(data);
	Trigger[] triggers;
	foreach(i;0..numTrigs){
		triggers~=parseTrigger(data);
	}
	enforce(data.length==0);
	return Trig(triggers);
}
Trig loadTRIG(string filename){
	return parseTRIG(readFile(filename));
}
