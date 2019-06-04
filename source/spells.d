import util;
import animations;
import std.exception, std.string;

enum SpellType:uint{
	creature=2,
	spell=4,
	wizard=8,
	structure=16,
}

struct Cre8{
	char[4] id0;
	SpellType spellType;
	char[4] name;
	char[4] icon;
	uint unknown1; // unused
	uint cooldown;
	uint manaCost;
	float range; // unused
	uint unknown5; // unused. but it seems spell fails to cast if unknown5>5.
	ushort unknown6; // larger for bigger creatures
	ushort castingTime;
	ushort spellOrder;
	ushort unknown9; // unused?
	ushort obedience0;// if 0, creatures ignore attack orders, unclear what it does exactly
	ushort obedience1;// ?
	ushort aggressiveness;// if 0, creatures don't attack automatically, unclear what else it does
	ushort runningSpeed;
	ushort flyingSpeed;
	ushort health;
	ushort regeneration;
	ushort drain;
	ushort rangedAccuracy;
	ushort meleeResistance;
	ushort directSpellResistance;
	ushort splashSpellResistance;
	ushort directRangedResistance;
	ushort splashRangedResistance;
	ushort unknown15; // seems to be 0 for everything but flying melee
	ushort unknown16; // some multiplier?
	ushort unknown17; // some multiplier?
	ushort unknown18; // some multiplier?
	ushort unknown19; // a small number
	ushort souls;
	ushort unknown20; // some multiplier?
	uint unknown21; // unused?
	char[4] ability1; // refers to @ABI
	char[4] ability2;
	uint[6] unknown22; // unused?
	char[4] ability3;
	uint unknown23;
	uint meleeStrength; // moderately small number
	uint mana; // "
	uint unknown26; // unused?
	char[4] creatureType;
	char[4] saxsModel;
	ubyte unknown27; // unused?
	ubyte unknown28;
	ushort unknown29; // unused?
	uint numSSETs;
	char[4] meleeSSET; // refers to SSET files
	char[4] creatureSSET;
	char[4] kind; // may refer to subfolder with creature name
	uint unknown31; // unused?
	Animations animations;
	uint[24] unknown36; // unused
}
static assert(Cre8.sizeof==528);

Cre8 parseCre8(ubyte[] data){
	enforce(data.length==Cre8.sizeof);
	return *cast(Cre8*)data.ptr;
}

Cre8 loadCre8(string filename){
	enforce(filename.endsWith("CRE8"));
	return parseCre8(readFile(filename));
}

struct Wizd{
	char[4] id0;
	SpellType spellType;
	char[4] name;
	char[4] icon;
	uint[6] unknown0; // unused?
	uint unknown1; // differs by wizard, some number above 100
	ushort unknown2=1250;
	ushort unknown3=1250;
	ushort unknown4=1000;
	ushort runningSpeed=1000;
	ushort flyingSpeed=0;
	ushort health=1500;
	ushort regeneration=1000;
	ushort drain=0;
	ushort rangedAccuracy=0;
	ushort meleeResistance;
	ushort directSpellResistance;
	ushort splashSpellResistance;
	ushort directRangedResistance;
	ushort splashRangedResistance;
	ushort unknown15; // seems to be 0 for everything but flying melee
	ushort unknown16; // some multiplier?
	ushort unknown17; // some multiplier?
	ushort unknown18; // some multiplier?
	ushort unknown19; // a small number
	ushort souls=0;
	ushort unknown20; // some multiplier?
	uint unknown21; // unused?
	char[4] ability1; // refers to @ABI
	char[4] ability2;
	uint[6] unknown22; // unused?
	char[4] ability3;
	uint unknown23;
	uint unknown24; // moderately small number
	uint mana;
	uint unknown26; // unused?
	char[4] creatureType;
	char[4] saxsModel;
	ubyte unknown27; // unused?
	ubyte unknown28;
	ushort unknown29; // unused?
	uint unknown30;
	char[4] wizardSSET; // refers to SSET files
	char[4] meleeSSET1;
	char[4] meleeSSET2;
	char[4] kind; // may refer to subfolder with creature name
	Animations animations;
	uint[24] unknown36; // unused
	uint unknown37;
	uint unknown38;
	uint unknown39;
	uint unknown40;
	uint unknown41;
	uint unknown42;
	uint unknown43;
	uint unknown44; // unused
	uint unknown45; // unused
	uint unknown46; // unused
	char[4] unknown47;
	char[4] unknown48;
	char[4] unknown49;
	char[4] unknown50;
	char[4] unknown51;
	char[4] unknown52;
	char[4] unknown53;
	char[4] unknown54;
	char[4] unknown55;
	uint[59] unknown; // unused?
}
static assert(Wizd.sizeof==840);

Wizd parseWizd(ubyte[] data){
	enforce(data.length==Wizd.sizeof);
	return *cast(Wizd*)data.ptr;
}

Wizd loadWizd(string filename){
	enforce(filename.endsWith("WIZD"));
	return parseWizd(readFile(filename));
}

enum SpelFlags:uint{
	targetSelf=0,
	targetWizards=1<<0,
	targetSouls=1<<1,
	targetCreatures=1<<2,
	targetCorpses=1<<3,
	targetStructures=1<<4,
	onlyManafounts=1<<11,
	requireAlly=1<<12,
	requireEnemy=1<<13,
	targetGround=1<<14,
	disallowFlying=1<<16,
	onlyCreatures=1<<18, // redundant?
	onlyOwned=1<<19,
	disallowHero=1<<20,
}

enum SpelFlags1:ushort{
	none=0,
	basicAttackSpell=1<<0,
	unknown1=1<<1,
	shield=1<<4,
	unknown5=1<<5,
	unknown6=1<<6,
	unknown10=1<<10,
	crowdControl=1<<11,
	unknown12=1<<12,
	unknown13=1<<5,
	unknown14=1<<14,
	unknown15=1<<15,
}

enum SpelFlags2:uint{
	nearBuilding=1<<8,
	nearEnemyAltar=1<<9,
	connectedToConversion=1<<10,
	stationaryCasting=1<<25,
}


struct Spel{
	char[4] id0;
	SpellType spellType;
	char[4] name;
	char[4] icon;
	uint unknown1; // unused?
	uint cooldown;
	uint manaCost;
	float range;
	SpelFlags flags;
	ushort unknown6; // ?
	ushort castingTime;
	ushort spellOrder;
	ushort unknown9; // ?
	char[4] unknown10;
	char[4] unknown11;
	uint[4] unknown12; // unused?
	ushort amount; // e.g. damage or amount of healed hitpoints
	ushort unknown14; // unused?
	float speed;
	float acceleration;
	float duration;
	float effectRange;
	ushort unknown16; // unused?
	SpelFlags1 flags1;
	SpelFlags2 flags2;
	uint amount2; // seems to be the same as amount most of the time
	uint unknown20;
	uint unknown21; // unused?
	uint unknown22; // unused?
	ushort soundFlags; // unclear how to interpret
	char[4] sound; // TODO: how to read this?
	struct Sound{
		ushort flags;
		char[4] sound;
	}
	Sound[4] sounds; // TODO: how to read this?
	struct Arguments{
		char[4] type;
		char[4] what;
	}
	Arguments[8] args;
	char[36] aiProc;
	char[36] proc1;
	char[36] proc2;
}
static assert(Spel.sizeof==314+2); // 2 padding bytes

Spel parseSpel(ubyte[] data){
	enforce(data.length<=Spel.sizeof);
	data.length=Spel.sizeof;
	return *cast(Spel*)data.ptr;
}

Spel loadSpel(string filename){
	enforce(filename.endsWith("SPEL"));
	return parseSpel(readFile(filename));
}

struct Strc{
	char[4] id0;
	SpellType spellType;
	char[4] name;
	char[4] icon;
	uint unknown1; // unused?
	uint cooldown;
	uint manaCost;
	float range;
	SpelFlags flags;
	ushort unknown6; // ?
	ushort castingTime;
	ushort spellOrder;
	ushort unknown9; // ?
	char[4][5] structure;
}

Strc parseStrc(ubyte[] data){
	enforce(data.length==Strc.sizeof);
	return *cast(Strc*)data.ptr;
}

Strc loadStrc(string filename){
	enforce(filename.endsWith("STRC"));
	return parseStrc(readFile(filename));
}
