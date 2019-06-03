import std.exception, std.conv, std.algorithm;
import spells, nttData, txtr;

enum TargetFlags{
	none,
	wizard=1<<0,
	soul=1<<1,
	creature=1<<2,
	corpse=1<<3,
	building=1<<4,
	manafount=1<<11,
	enemy=1<<12,
	ally=1<<13,
	ground=1<<14,
	flying=1<<15,
	owned=1<<19,
	 // TODO: figure out SpelFlag for these:
	hero=1<<20,
	shielded=1<<21,
	// TODO: figure out building flag for this:
	untargettable=1<<22,
	// irrelevant for spell targetting:
	rescuable,
}

bool isApplicable(SpelFlags sflags,TargetFlags tflags)in{
	assert(sflags);
}do{
	with(SpelFlags) with(TargetFlags){
		if(tflags&untargettable) return false;
		if(!(sflags&targetWizards)&&(tflags&wizard)) return false;
		if(!(sflags&targetSouls)&&(tflags&soul)) return false;
		if(!(sflags&targetCreatures)&&(tflags&creature)) return false;
		if(!(sflags&targetCorpses)&&(tflags&corpse)) return false;
		if(!(sflags&targetStructures)&&(tflags&building)) return false;
		if((sflags&onlyManafounts)&!(tflags&manafount)) return false;
		if((sflags&disallowEnemy)&(tflags&enemy)) return false;
		if((sflags&disallowAlly)&(tflags&ally)) return false;
		if(!(sflags&targetGround)&&(tflags&ground)) return false;
		if((sflags&disallowFlying)&&(tflags&flying)) return false;
		if(sflags&onlyCreatures&&!(tflags&creature)) return false;
		if(sflags&onlyOwned&&!(tflags&owned)) return false;
		// TODO: shield/hero
	}
	return true;
}

enum SpellType:int{
	creature=0,
	spell=1,
	structure=2,
}

class SacSpell(B){
	char[4] tag;
	immutable(Cre8)* cre8;
	immutable(Spel)* spel;
	immutable(Strc)* strc;
	B.Texture icon;

	SpellType type;
	ushort spellOrder;
	float range;
	float manaCost;
	float castingTime;
	float cooldown;

	@property bool stationary(){ return spel?!!(spel.flags2&SpelFlags2.stationaryCasting):true; }
	@property bool requiresTarget(){ return spel?!!spel.flags:false; }
	@property bool nearBuilding(){ return spel?!!(spel.flags2&SpelFlags2.nearBuilding):false; }
	@property bool nearEnemyAltar(){ return spel?!!(spel.flags2&SpelFlags2.nearEnemyAltar):false; }
	@property bool connectedToConversion(){ return spel?!!(spel.flags2&SpelFlags2.connectedToConversion):false; }

	private this(char[4] tag){
		this.tag=tag;
		cre8=tag in cre8s;
		spel=tag in spels;
		strc=tag in strcs;
		enforce((cre8!is null)+(spel!is null)+(strc!is null)==1,tag[]);
		if(cre8) type=SpellType.creature;
		else if(structureSpells.canFind(tag)) type=SpellType.structure;
		else type=SpellType.spell;
		auto iconTag=cre8?cre8.icon:spel?spel.icon:strc.icon;
		if(iconTag!="\0\0\0\0"){
			enforce(iconTag in icons,text(iconTag," ",icons));
			icon=B.makeTexture(loadTXTR(icons[iconTag]));
		}
		void setStats(T)(T arg){
			spellOrder=arg.spellOrder;
			manaCost=arg.manaCost;
			range=arg.range;
			castingTime=arg.castingTime/60.0f; // TODO
			cooldown=arg.cooldown/60.0f; // TODO
		}
		if(cre8) setStats(cre8);
		else if(spel) setStats(spel);
		else if(strc) setStats(strc);
	}
	static SacSpell!B[char[4]] spells;
	static SacSpell!B get(char[4] tag){
		if(auto r=tag in spells) return *r;
		return spells[tag]=new SacSpell!B(tag);
	}
}
