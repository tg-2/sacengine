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
		void fixLocustAnimations(ref Cre8 c){
			swap(c.animations.hover,c.animations.stance1);
		}
		fixLocustAnimations(result["pazb"]);
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


immutable struct CreatureData{
	char[4] tag;
	string name; // TODO: internationalization
	string model;
	string stance;
	float scaling=2e-3;
	float zfactorOverride=float.nan;
}

CreatureData abomination={
	tag: "ctug",
	name: "Abomination",
	scaling: 2e-3,
};

CreatureData astaroth={
	tag: "RAMH",
	name: "Astaroth",
	scaling: 2e-3,
};

CreatureData basilisk={
	tag: "guls",
	name: "Basilisk",
	scaling: 1e-3,
};

CreatureData blight={
	tag: "kacd",
	name: "Blight",
	scaling: 1e-3,
};

CreatureData bombard={
	tag: "wlcf",
	name: "Bombard",
	scaling: 2e-3,
};

CreatureData boulderdash={
	tag: "llab",
	name: "Boulderdash",
	scaling: 2e-3,
};

CreatureData brainiac={
	tag: "bobs",
	name: "Brainiac",
	scaling: 1e-3,
};

CreatureData cog={
	tag: "zidf",
	name: "Cog",
	scaling: 1e-3,
};

CreatureData deadeye={
	tag: "plfd",
	name: "Deadeye",
	scaling: 1e-3,
};

CreatureData dragon={
	tag: "grdg",
	name: "Dragon",
	scaling: 4e-3,
};

CreatureData dragonHatchling={
	tag: "rdbO",
	name: "Dragon Hatchling",
	scaling: 1e-3,
};

CreatureData druid={
	tag: "nmuh",
	name: "Druid",
	scaling: 1e-3,
};

CreatureData earthfling={
	tag: "palk",
	name: "Earthfling",
	scaling: 1e-3,
};

CreatureData ent={
	tag: "mtsl",
	name: "Ent",
	scaling: 2e-3,
};

CreatureData faestus1={
	tag: "ehtH",
	name: "Faestus",
	scaling: 1.5e-3,
};

CreatureData faestus2={
	tag: "EHTH",
	name: "Faestus",
	scaling: 1.5e-3,
};

CreatureData fallen={
	tag: "dplk",
	name: "Fallen",
	scaling: 1e-3,
};

CreatureData familiar={
	tag: "imaf",
	name: "Familiar",
	scaling: 1e-3,
};

CreatureData farmer={
	tag: "zepe",
	name: "Farmer",
	scaling: 1e-3,
};

CreatureData firefist={
	tag: "lrtf",
	name: "Firefist",
	scaling: 2e-3,
};

CreatureData flameminion={
	tag: "fplk",
	name: "Earthfling",
	scaling: 1e-3,
};

CreatureData flummox={
	tag: "wlce",
	name: "Flummox",
	scaling: 1.5e-3,
};

CreatureData flurry={
	tag: "wlca",
	name: "Flurry",
	scaling: 1.5e-3,
};

CreatureData frostwolf={ // TODO: this is screwed up, why?
	tag: "lbog",
	name: "Frostwolf",
	scaling: 1e-3,
	zfactorOverride: 1.0f,
};

CreatureData gammel={
	tag: "magH",
	name: "Gammel",
	scaling: 1.5e-3,
};

CreatureData gangrel={
	tag: "ramH",
	name: "Gangrel",
	scaling: 2e-3,
};

CreatureData gargoyle={
	tag: "sohe",
	name: "Gargoyle",
	scaling: 1e-3,
};

CreatureData ghost={
	tag: "tshg",
	name: "Ghost",
	scaling: 1e-3,
};

CreatureData gnome={
	tag: "plfl",
	name: "Gnome",
	scaling: 1e-3,
};

CreatureData gremlin={
	tag: "lrps",
	name: "Gremlin",
	scaling: 1e-3,
};

CreatureData hellmouth={
	tag: "nomd",
	name: "Hellmouth",
	scaling: 3e-3,
};

CreatureData ikarus={
	tag: "kace",
	name: "Ikarus",
	scaling: 1e-3,
};

CreatureData jabberocky={
	tag: "mtse",
	name: "Jabberocky",
	scaling: 2e-3,
};

CreatureData locust={
	tag: "pazb",
	name: "Locust",
	scaling: 1e-3,
};

CreatureData lordSurtur={
	tag: "uslH",
	name: "Lord Surtur",
	scaling: 2.5e-3,
};

CreatureData manahoar={
	tag: "oham",
	name: "Manahoar",
	scaling: 1e-3,
};

CreatureData mutant={
	tag: "cbab",
	name: "Mutant",
	scaling: 2e-3,
};

CreatureData necryl={
	tag: "glsd",
	name: "Necryl",
	scaling: 1e-3,
};

CreatureData netherfiend={
	tag: "crpd",
	name: "Netherfiend",
	scaling: 2e-3,
};

CreatureData peasant={
	tag: "saep",
	name: "Peasant",
	scaling: 1e-3,
};

CreatureData phoenix={
	tag: "grdr",
	name: "Phoenix",
	scaling: 4e-3,
};

CreatureData pyrodactyl={
	tag: "kacf",
	name: "Pyrodactyl",
	scaling: 1e-3,
};

CreatureData pyromaniac={
	tag: "plff",
	name: "Pyromaniac",
	scaling: 1e-3,
};

CreatureData ranger={
	tag: "amuh",
	name: "Ranger",
	scaling: 1e-3,
};

CreatureData rhinok={
	tag: "gard",
	name: "Rhinok",
	scaling: 3e-3,
};

CreatureData sacDoctor={
	tag: "dcas",
	name: "Sac Doctor",
	scaling: 2e-3,
};

CreatureData saraBella={
	tag: "pezH",
	name: "Sara Bella",
	scaling: 2e-3,
};

CreatureData scarab={
	tag: "cara",
	name: "Scarab",
	scaling: 1e-3,
};

CreatureData scythe={
	tag: "dzid",
	name: "Scythe",
	scaling: 1e-3,
};

CreatureData seraph={
	tag: "grps",
	name: "Seraph",
	scaling: 1e-3,
};

CreatureData shrike={
	tag: "tbsh",
	name: "Shrike",
	scaling: 1e-3,
};

CreatureData silverback={
	tag: "grdb",
	name: "Silverback",
	scaling: 3e-3,
	zfactorOverride: 1.0,
};

CreatureData sirocco={
	tag: "risH",
	name: "Sirocco",
	scaling: 5e-3,
};

CreatureData slave={
	tag: "zepf",
	name: "Slave",
	scaling: 1e-3,
};

CreatureData snowman={
	tag: "zepa",
	name: "Snowman",
	scaling: 1e-3,
};

CreatureData spitfire={
	tag: "sohf",
	name: "Spitfire",
	scaling: 1e-3,
};

CreatureData squall={
	tag: "alab",
	name: "Squall",
	scaling: 1.5e-3,
};

CreatureData stormGiant={
	tag: "rgos",
	name: "Storm Giant",
	scaling: 2e-3,
};

CreatureData styx={
	tag: "nugd",
	name: "Styx",
	scaling: 2e-3,
};

CreatureData sylph={
	tag: "ahcr",
	name: "Sylph",
	scaling: 1e-3,
};

CreatureData taurock={
	tag: "raeb",
	name: "Taurock",
	scaling: 2e-3,
	zfactorOverride: 0.8,
};

CreatureData thestor={
	tag: "eafH",
	name: "Thestor",
	scaling: 1.5e-3,
};

CreatureData tickferno={
	tag: "craf",
	name: "Tickferno",
	scaling: 1e-3,
};

CreatureData toldor={
	tag: "oohH",
	name: "Toldor",
	scaling: 2.5e-3,
};

CreatureData trogg={
	tag: "ycro",
	name: "Trogg",
	scaling: 1e-3,
};

CreatureData troll={
	tag: "lort",
	name: "Troll",
	scaling: 2e-3,
};

CreatureData vortick={
	tag: "craa",
	name: "Vortick",
	scaling: 1e-3,
};

CreatureData warmonger={
	tag: "nugf",
	name: "Warmonger",
	scaling: 2e-3,
};

CreatureData yeti={
	tag: "ycrp",
	name: "Yeti",
	scaling: 2e-3,
};

CreatureData zombie={
	tag: "zepd",
	name: "Zombie",
	scaling: 1e-3,
};

CreatureData zyzyx={
	tag: "tnem",
	name: "Zyzyx",
	scaling: 1e-3,
};

CreatureData abraxus={
	tag: "0ewc",
	name: "Abraxus",
	scaling: 1e-3,
};

CreatureData acheron={
	tag: "1dwc",
	name: "Acheron",
	scaling: 1e-3,
};

CreatureData ambassadorButa={
	tag: "0fwc",
	name: "Ambassador Buta",
	scaling: 1e-3,
};

CreatureData charlotte={
	tag: "2fwc",
	name: "Charlotte",
	scaling: 1e-3,
};

CreatureData eldred={
	tag: "2ewc",
	name: "Eldred",
	scaling: 1e-3,
};

CreatureData grakkus={
	tag: "1fwc",
	name: "Grakkus",
	scaling: 1e-3,
};

CreatureData hachimen={
	tag: "2lwc",
	name: "Hachimen",
	scaling: 1e-3,
};

CreatureData jadugarr={
	tag: "0awc",
	name: "Jadugarr",
	scaling: 1e-3
};

CreatureData marduk={
	tag: "2awc",
	name: "Marduk",
	scaling: 1e-3
};

CreatureData mithras={
	tag: "1ewc",
	name: "Mithras",
	scaling: 1e-3,
};

CreatureData seerix={
	tag: "1awc",
	name: "Seerix",
	scaling: 1e-3,
};

CreatureData shakti={
	tag: "0lwc",
	name: "Shakti",
	scaling: 1e-3
};

CreatureData sorcha={
	tag: "2dwc",
	name: "Sorcha",
	scaling: 1e-3,
};

CreatureData theRagman={
	tag: "0dwc",
	name: "The Ragman",
	scaling: 1e-3,
};

CreatureData yogo={
	tag: "1lwc",
	name: "Yogo",
	scaling: 1e-3
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
