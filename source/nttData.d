module nttData;
import std.file, std.path, std.stdio, std.algorithm, std.range, std.string, std.exception;
import bldg, spells;
import util;
immutable string[] bldgFolders=["joby/joby.WAD!/ethr.FLDR",
                                "joby/joby.WAD!/prsc.FLDR",
                                "pyromod/PMOD.WAD!/bild.FLDR",
                                "jamesmod/JMOD.WAD!/bild.FLDR",
                                "stratmod/SMOD.WAD!/bild.FLDR",
                                "joby/joby.WAD!/ch_a.FLDR",];

immutable string[] bldgModlFolders=["joby/joby.WAD!/ethr.FLDR",
                                    "joby/joby.WAD!/prsc.FLDR",
                                    "pyromod/PMOD.WAD!/modl.FLDR",
                                    "jamesmod/JMOD.WAD!/modl.FLDR",
                                    "stratmod/SMOD.WAD!/modl.FLDR",
                                    "joby/joby.WAD!/ch_a.FLDR"];

immutable char[4][] manalithTags=["amac","namj","anam","amyp","mats"];

import std.typecons;
Bldg[char[4]] makeBldgByTag(){
	Bldg[char[4]] result;
	foreach(folder;bldgFolders){
		auto path=buildPath("extracted",folder);
		foreach(bldgFile;dirEntries(path,"*.BLDG",SpanMode.shallow)){
			char[4] tag=bldgFile[$-9..$-5];
			reverse(tag[]);
			enforce(tag !in result);
			enforce(tag !in result);
			result[tag]=loadBldg(bldgFile);
		}
	}
	return result;
}

string[char[4]] makeBldgModlByTag(){
	string[char[4]] result;
	foreach(folder;bldgModlFolders){
		auto path=buildPath("extracted",folder);
		foreach(bldgModlFile;dirEntries(path,"*.MRMC",SpanMode.shallow)){
			char[4] tag=bldgModlFile[$-9..$-5];
			reverse(tag[]);
			enforce(tag !in result);
			result[tag]=buildPath(bldgModlFile,bldgModlFile[$-9..$-5]~".MRMM");
		}
	}
	return result;
}

immutable Bldg[char[4]] bldgs;
immutable string[char[4]] bldgModls;

immutable landFolders=["extracted/ethr/ethr.WAD!/ethr.LAND",
                       "extracted/prsc/prsc.WAD!/prsc.LAND",
                       "extracted/pyro_a/PY_A.WAD!/PY_A.LAND",
                       "extracted/james_a/JA_A.WAD!/JA_A.LAND",
                       "extracted/strato_a/ST_A.WAD!/ST_A.LAND",
                       "extracted/char/char.WAD!/char.LAND"];

string[char[4]] makeWidgModlByTag(){
	string[char[4]] result;
	foreach(folder;landFolders){
		foreach(widgModlFile;dirEntries(folder,"*.WIDG",SpanMode.depth)){
			char[4] tag=widgModlFile[$-9..$-5];
			reverse(tag[]);
			enforce(tag !in result);
			result[tag]=widgModlFile;
		}
	}
	return result;
}
immutable string[char[4]] widgModls;

immutable string spellsFolder="spells";

T[char[4]] makeSpellByTag(T)(){
	T[char[4]] result;
	static immutable path=buildPath("extracted",spellsFolder);
	static immutable ext=toUpper(T.stringof);
	foreach(spellFile;dirEntries(path,"*."~ext,SpanMode.depth)){
		char[4] tag=spellFile[$-9..$-5];
		reverse(tag[]);
		enforce(tag !in result);
		result[tag]=mixin(`load`~T.stringof)(spellFile);
	}
	static if(is(T==Cre8)){
		// dragon hatchlings have flying animations, but cannot fly
		// peasants have pulling animations stored in flying animations
		static immutable nonFlyingTags=["rdbO","zepa","zepd","zepe","zepf","saep","tshg"];
		foreach(char[4] tag;nonFlyingTags){
			void fixAnimations(ref Cre8 c){
				c.animations.takeoff=0;
				c.animations.fly=0;
				c.animations.land=0;
			}
			fixAnimations(result[tag]);
		}
		void fixLocust(ref Cre8 c){
			c.animations.stance1=c.animations.hover;
			c.creatureType="mron";
			c.animations.death[0]=c.animations.death[1];
			c.animations.death[1]=c.animations.death[2];
			c.animations.death[2]=0;
			assert(c.animations.run==c.animations.fly);
			c.animations.run=0;
		}
		fixLocust(result["pazb"]);
		void fixGammel(ref Cre8 c){
			c.animations.falling=result["kace"].animations.falling;
		}
		fixGammel(result["magH"]);
		void fixFamiliar(ref Cre8 c){
			c.creatureType="ylfo";
			c.animations.flyDamage=c.animations.doubletake;
			c.animations.stance1=c.animations.hover;
			c.animations.takeoff=0;
			c.animations.land=0;
			c.animations.run=0;
		}
		fixFamiliar(result["imaf"]);
		fixFamiliar(result["tnem"]);
	}
	return result;
}

char[4][char[4]] makeTagBySaxsModelTag(){
	char[4][char[4]] result;
	static immutable path=buildPath("extracted",spellsFolder);
	foreach(T;Seq!(Cre8,Wizd)){
		enum ext=toUpper(T.stringof);
		foreach(spellFile;dirEntries(path,"*."~ext,SpanMode.depth)){
			char[4] tag=spellFile[$-9..$-5];
			reverse(tag[]);
			auto spell=mixin(`load`~T.stringof)(spellFile);
			result[spell.saxsModel]=tag;
		}
	}
	return result;
}

immutable Cre8[char[4]] cre8s;
immutable Wizd[char[4]] wizds;
immutable Strc[char[4]] strcs;

immutable char[4][char[4]] tagsFromModel;

immutable string[] saxsModlFolders=["saxs/mrtd.WAD!",
                                    "saxs_add/AADD.WAD!",
                                    "saxs_odd/sxod.WAD!",
                                    "saxs_r1/sxr1.WAD!",
                                    "saxs_r2/sxr2.WAD!",
                                    "saxs_r3/sxr3.WAD!",
                                    "saxs_r4/sxr4.WAD!",
                                    "saxs_r5/sxr5.WAD!",
                                    "saxs_r6/sxr6.WAD!",
                                    "saxs_r7/sxr7.WAD!",
                                    "saxs_r8/sxr8.WAD!",
                                    "saxs_r9/sxr9.WAD!",
                                    "saxs_r10/sr10.WAD!",
                                    "saxs_r11/sr11.WAD!",
                                    "saxshero/hero.WAD!",
                                    "saxs_wiz/sxwz.WAD!"];

string[char[4]] makeSaxsModlByTag(){
	string[char[4]] result;
	foreach(folder;saxsModlFolders){
		auto path=buildPath("extracted",folder);
		foreach(saxsModlFile;dirEntries(path,"*.SXMD",SpanMode.depth)){
			char[4] tag=saxsModlFile[$-9..$-5];
			reverse(tag[]);
			enforce(tag !in result);
			result[tag]=saxsModlFile;
		}
	}
	return result;
}
string[][char[4]] makeSaxsAnimByTag(){
	string[][char[4]] result;
	foreach(folder;saxsModlFolders){
		auto path=buildPath("extracted",folder);
		foreach(saxsAnimFile;dirEntries(path,"*.SXSK",SpanMode.depth)){
			char[4] tag=saxsAnimFile[$-9..$-5];
			reverse(tag[]);
			import std.ascii: toLower;
			foreach(ref x;tag) x=toLower(x);
			result[tag]~=saxsAnimFile;
		}
	}
	return result;
}
immutable string[char[4]] saxsModls;
immutable string[][char[4]] saxsAnims;

string getSaxsAnim(string saxsModlFile, char[4] tag){
	string r=null;
	size_t best=0;
	import std.ascii: toLower;
	foreach(ref x;tag) x=toLower(x);
	foreach(anim;saxsAnims.get(tag,[])){
		size_t cur=zip(anim,saxsModlFile).until!"a[0]!=a[1]".walkLength;
		if(cur>=best){
			best=cur;
			r=anim;
		}
	}
	return r;
}

static this(){
	bldgs=cast(immutable)makeBldgByTag();
	bldgModls=cast(immutable)makeBldgModlByTag();

	widgModls=cast(immutable)makeWidgModlByTag();

	cre8s=cast(immutable)makeSpellByTag!Cre8();
	wizds=cast(immutable)makeSpellByTag!Wizd();
	strcs=cast(immutable)makeSpellByTag!Strc();

	tagsFromModel=cast(immutable)makeTagBySaxsModelTag();

	saxsModls=cast(immutable)makeSaxsModlByTag();
	saxsAnims=cast(immutable)makeSaxsAnimByTag();
}


enum RotateOnGround{
	no,
	sideways,
	completely,
}

enum HitboxType{
	large,
	small,
	largeZ,
	largeZbot,
}

enum StunBehavior{
	none,
	fromBehind,
	always,
}
enum StunnedBehavior{
	normal,
	onMeleeDamage,
	onDamage,
}

immutable struct CreatureData{
	char[4] tag;
	string name; // TODO: internationalization
	string model;
	string stance;
	float zfactorOverride=float.nan;
	auto rotateOnGround=RotateOnGround.no;
	auto hitboxType=HitboxType.large;
	auto stunBehavior=StunBehavior.none;
	auto stunnedBehavior=StunnedBehavior.normal;
}

CreatureData abomination={
	tag: "ctug",
	name: "Abomination",
	// hitboxType: ?
};

CreatureData astaroth={
	tag: "RAMH",
	name: "Astaroth",
	stunBehavior: StunBehavior.fromBehind,
};

CreatureData basilisk={
	tag: "guls",
	name: "Basilisk",
	rotateOnGround: RotateOnGround.completely,
};

CreatureData blight={
	tag: "kacd",
	name: "Blight",
	rotateOnGround: RotateOnGround.sideways,
	stunBehavior: StunBehavior.fromBehind,
};

CreatureData bombard={
	tag: "wlcf",
	name: "Bombard",
	rotateOnGround: RotateOnGround.sideways,
};

CreatureData boulderdash={
	tag: "llab",
	name: "Boulderdash",
	rotateOnGround: RotateOnGround.sideways,
};

CreatureData brainiac={
	tag: "bobs",
	name: "Brainiac",
};

CreatureData cog={
	tag: "zidf",
	name: "Cog",
};

CreatureData deadeye={
	tag: "plfd",
	name: "Deadeye",
	// hitboxType: ?
	stunnedBehavior: StunnedBehavior.onDamage,
};

CreatureData dragon={
	tag: "grdg",
	name: "Dragon",
	rotateOnGround: RotateOnGround.completely,
	hitboxType: HitboxType.largeZ,
	stunBehavior: StunBehavior.always,
};

CreatureData dragonHatchling={
	tag: "rdbO",
	name: "Dragon Hatchling",
	rotateOnGround: RotateOnGround.completely,
	hitboxType: HitboxType.largeZ, // ?
	stunBehavior: StunBehavior.fromBehind,
};

CreatureData druid={
	tag: "nmuh",
	name: "Druid",
};

CreatureData earthfling={
	tag: "palk",
	name: "Earthfling",
};

CreatureData ent={
	tag: "mtsl",
	name: "Ent",
	rotateOnGround: RotateOnGround.completely,
	hitboxType: HitboxType.largeZ,
	stunBehavior: StunBehavior.fromBehind,
};

CreatureData faestus1={
	tag: "ehtH",
	name: "Faestus",
};

CreatureData faestus2={
	tag: "EHTH",
	name: "Faestus",
};

CreatureData fallen={
	tag: "dplk",
	name: "Fallen",
};

CreatureData familiar={
	tag: "imaf",
	name: "Familiar",
};

CreatureData farmer={
	tag: "zepe",
	name: "Farmer",
	hitboxType: HitboxType.largeZ,
};

CreatureData firefist={
	tag: "lrtf",
	name: "Firefist",
};

CreatureData flameminion={
	tag: "fplk",
	name: "Earthfling",
};

CreatureData flummox={
	tag: "wlce",
	name: "Flummox",
	rotateOnGround: RotateOnGround.sideways,
};

CreatureData flurry={
	tag: "wlca",
	name: "Flurry",
	rotateOnGround: RotateOnGround.sideways,
};

CreatureData frostwolf={ // TODO: this is screwed up, why?
	tag: "lbog",
	name: "Frostwolf",
	zfactorOverride: 1.0f,
};

CreatureData gammel={
	tag: "magH",
	name: "Gammel",
	rotateOnGround: RotateOnGround.sideways,
	stunBehavior: StunBehavior.fromBehind,
};

CreatureData gangrel={
	tag: "ramH",
	name: "Gangrel",
	stunBehavior: StunBehavior.fromBehind,
};

CreatureData gargoyle={
	tag: "sohe",
	name: "Gargoyle",
};

CreatureData ghost={
	tag: "tshg",
	name: "Ghost",
	hitboxType: HitboxType.largeZ,
};

CreatureData gnome={
	tag: "plfl",
	name: "Gnome",
	// hitboxType: ?
	stunnedBehavior: StunnedBehavior.onDamage,
};

CreatureData gremlin={
	tag: "lrps",
	name: "Gremlin",
	rotateOnGround: RotateOnGround.sideways,
};

CreatureData hellmouth={
	tag: "nomd",
	name: "Hellmouth",
	rotateOnGround: RotateOnGround.completely,
};

CreatureData ikarus={
	tag: "kace",
	name: "Ikarus",
	rotateOnGround: RotateOnGround.sideways,
	stunBehavior: StunBehavior.fromBehind,
};

CreatureData jabberocky={
	tag: "mtse",
	name: "Jabberocky",
	rotateOnGround: RotateOnGround.completely,
	hitboxType: HitboxType.largeZ,
	stunBehavior: StunBehavior.fromBehind,
};

CreatureData locust={
	tag: "pazb",
	name: "Locust",
};

CreatureData lordSurtur={
	tag: "uslH",
	name: "Lord Surtur",
	stunBehavior: StunBehavior.fromBehind,
};

CreatureData manahoar={
	tag: "oham",
	name: "Manahoar",
	rotateOnGround: RotateOnGround.completely,
};

CreatureData mutant={
	tag: "cbab",
	name: "Mutant",
	// hitboxType: ?
	stunnedBehavior: StunnedBehavior.onDamage,
};

CreatureData necryl={
	tag: "glsd",
	name: "Necryl",
	rotateOnGround: RotateOnGround.completely,
};

CreatureData netherfiend={
	tag: "crpd",
	name: "Netherfiend",
	hitboxType: HitboxType.small,
	stunBehavior: StunBehavior.fromBehind,
};

CreatureData peasant={
	tag: "saep",
	name: "Peasant",
	hitboxType: HitboxType.largeZ,
};

CreatureData phoenix={
	tag: "grdr",
	name: "Phoenix",
	stunBehavior: StunBehavior.always,
};

CreatureData pyrodactyl={
	tag: "kacf",
	name: "Pyrodactyl",
	rotateOnGround: RotateOnGround.sideways,
	stunBehavior: StunBehavior.fromBehind,
};

CreatureData pyromaniac={
	tag: "plff",
	name: "Pyromaniac",
	stunnedBehavior: StunnedBehavior.onDamage,
};

CreatureData ranger={
	tag: "amuh",
	name: "Ranger",
};

CreatureData rhinok={
	tag: "gard",
	name: "Rhinok",
	rotateOnGround: RotateOnGround.completely,
	// hitboxType: ?
	stunBehavior: StunBehavior.always,
};

CreatureData sacDoctor={
	tag: "dcas",
	name: "Sac Doctor",
};

CreatureData saraBella={
	tag: "pezH",
	name: "Sara Bella",
};

CreatureData scarab={
	tag: "cara",
	name: "Scarab",
	rotateOnGround: RotateOnGround.completely,
};

CreatureData scythe={
	tag: "dzid",
	name: "Scythe",
	stunBehavior: StunBehavior.fromBehind,
};

CreatureData seraph={
	tag: "grps",
	name: "Seraph",
	rotateOnGround: RotateOnGround.sideways,
};

CreatureData shrike={
	tag: "tbsh",
	name: "Shrike",
};

CreatureData silverback={
	tag: "grdb",
	name: "Silverback",
	zfactorOverride: 1.0,
	rotateOnGround: RotateOnGround.completely,
	stunBehavior: StunBehavior.always,
};

CreatureData sirocco={
	tag: "risH",
	name: "Sirocco",
	rotateOnGround: RotateOnGround.completely,
	hitboxType: HitboxType.largeZ,
	stunBehavior: StunBehavior.fromBehind,
};

CreatureData slave={
	tag: "zepf",
	name: "Slave",
	hitboxType: HitboxType.largeZ,
};

CreatureData snowman={
	tag: "zepa",
	name: "Snowman",
	hitboxType: HitboxType.largeZ,
};

CreatureData spitfire={
	tag: "sohf",
	name: "Spitfire",
};

CreatureData squall={
	tag: "alab",
	name: "Squall",
	rotateOnGround: RotateOnGround.sideways,
};

CreatureData stormGiant={
	tag: "rgos",
	name: "Storm Giant",
	stunBehavior: StunBehavior.fromBehind,
};

CreatureData styx={
	tag: "nugd",
	name: "Styx",
	// hitboxType: ?
	stunnedBehavior: StunnedBehavior.onMeleeDamage,
};

CreatureData sylph={
	tag: "ahcr",
	name: "Sylph",
};

CreatureData taurock={
	tag: "raeb",
	name: "Taurock",
	zfactorOverride: 0.8,
	rotateOnGround: RotateOnGround.completely,
};

CreatureData thestor={
	tag: "eafH",
	name: "Thestor",
};

CreatureData tickferno={
	tag: "craf",
	name: "Tickferno",
	rotateOnGround: RotateOnGround.completely,
};

CreatureData toldor={
	tag: "oohH",
	name: "Toldor",
	rotateOnGround: RotateOnGround.completely,
	hitboxType: HitboxType.largeZ,
	stunBehavior: StunBehavior.fromBehind,
};

CreatureData trogg={
	tag: "ycro",
	name: "Trogg",
};

CreatureData troll={
	tag: "lort",
	name: "Troll",
};

CreatureData vortick={
	tag: "craa",
	name: "Vortick",
	rotateOnGround: RotateOnGround.completely,
};

CreatureData warmonger={
	tag: "nugf",
	name: "Warmonger",
	// hitboxType: ?
	stunnedBehavior: StunnedBehavior.onMeleeDamage,
};

CreatureData yeti={
	tag: "ycrp",
	name: "Yeti",
	stunBehavior: StunBehavior.fromBehind,
};

CreatureData zombie={
	tag: "zepd",
	name: "Zombie",
};

CreatureData zyzyx={
	tag: "tnem",
	name: "Zyzyx",
};

CreatureData abraxus={
	tag: "0ewc",
	name: "Abraxus",
};

CreatureData acheron={
	tag: "1dwc",
	name: "Acheron",
};

CreatureData ambassadorButa={
	tag: "0fwc",
	name: "Ambassador Buta",
	rotateOnGround: RotateOnGround.sideways,
};

CreatureData charlotte={
	tag: "2fwc",
	name: "Charlotte",
	rotateOnGround: RotateOnGround.completely,
};

CreatureData eldred={
	tag: "2ewc",
	name: "Eldred",
};

CreatureData grakkus={
	tag: "1fwc",
	name: "Grakkus",
};

CreatureData hachimen={
	tag: "2lwc",
	name: "Hachimen",
	rotateOnGround: RotateOnGround.sideways,
};

CreatureData jadugarr={
	tag: "0awc",
	name: "Jadugarr",
	rotateOnGround: RotateOnGround.completely,
};

CreatureData marduk={
	tag: "2awc",
	name: "Marduk",
};

CreatureData mithras={
	tag: "1ewc",
	name: "Mithras",
	rotateOnGround: RotateOnGround.completely,
};

CreatureData seerix={
	tag: "1awc",
	name: "Seerix",
	rotateOnGround: RotateOnGround.completely,
};

CreatureData shakti={
	tag: "0lwc",
	name: "Shakti",
};

CreatureData sorcha={
	tag: "2dwc",
	name: "Sorcha",
};

CreatureData theRagman={
	tag: "0dwc",
	name: "The Ragman",
};

CreatureData yogo={
	tag: "1lwc",
	name: "Yogo",
};

CreatureData* creatureDataByTag(char[4] tag){
Lswitch: switch(tag){
		static foreach(dataName;__traits(allMembers, nttData)){
			static if(is(typeof(mixin(`nttData.`~dataName))==CreatureData)){
				static if(mixin(`nttData.`~dataName).tag!=(char[4]).init)
				case mixin(`nttData.`~dataName).tag:{
					if(!mixin(`nttData.`~dataName).name)
						return null;
					else return &mixin(`nttData.`~dataName);
				}
			}
		}
		default:
			import std.stdio;
			stderr.writeln("WARNING: unknown creature tag '",tag,"'");
			return null;
	}
}
