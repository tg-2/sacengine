module nttData;
import std.path, std.stdio, std.algorithm, std.range, std.string, std.exception;
import bldg, spells, sset;
import util;
import dlib.math.vector;

immutable string[] bldgFolders=["extracted/joby/joby.WAD!/ethr.FLDR",
                                "extracted/joby/joby.WAD!/prsc.FLDR",
                                "extracted/pyromod/PMOD.WAD!/bild.FLDR",
                                "extracted/jamesmod/JMOD.WAD!/bild.FLDR",
                                "extracted/stratmod/SMOD.WAD!/bild.FLDR",
                                "extracted/joby/joby.WAD!/ch_a.FLDR"].fixPaths;

immutable string[] bldgModlFolders=["extracted/joby/joby.WAD!/ethr.FLDR",
                                    "extracted/joby/joby.WAD!/prsc.FLDR",
                                    "extracted/pyromod/PMOD.WAD!/modl.FLDR",
                                    "extracted/jamesmod/JMOD.WAD!/modl.FLDR",
                                    "extracted/stratmod/SMOD.WAD!/modl.FLDR",
                                    "extracted/joby/joby.WAD!/ch_a.FLDR"].fixPaths;

immutable char[4][] manafountTags=["nfcp","tnfj","nfac","nofp","fmts"];
immutable char[4][] manalithTags=["amac","namj","anam","amyp","mats"];
immutable char[4][] shrineTags=["hscp","rhsj","psac","hsyp","rhss"];
immutable char[4][] altarTags=["1tla","laaj","a_ac","layp","lats",
                               "_aup","auaj","_auc","auyp","auts"];
immutable char[4][] altarRingTags=["r_ae","otla","gnrj","raac","gryp","gras",
                                          "raup","2uaj","rauc","2uyp","2uts"];
immutable char[4][] altarBaseTags=["b_ae","abla","tipj","baac","tpyp","tprc",
                                          "caup",       "bauc",             ];

auto makeFileIndex(bool multi=false,bool lowerCase=false)(bool readFromWads,const string[] folders,char[4] extension,bool noDup=true){
	static if(multi) string[][char[4]] result;
	else string[char[4]] result;
	void handle(string file){
		char[4] tag=file[$-9..$-5];
		reverse(tag[]);
		static if(lowerCase){
			import std.ascii: toLower;
			foreach(ref x;tag) x=toLower(x);
		}
		static if(!multi){
			if(noDup) enforce(tag !in result);
			result[tag]=file;
		}else result[tag]~=file;
	}
	foreach(folder;folders){
		if(readFromWads){
			enforce(!!wadManager);
			foreach(file;wadManager.byExt.get(extension,[])){
				if(file.startsWith(folder))
					handle(file);
			}
		}else{
			import std.file;
			foreach(file;dirEntries(folder,"*."~cast(immutable)extension[],SpanMode.depth))
				handle(file);
		}
	}
	return result;
}
immutable(typeof(load("")))[char[4]] makeByTag(alias load)(bool readFromWads,const string[] folders,char[4] extension,bool noDup=true){
	typeof(load(""))[char[4]] result;
	void handle(string file){
		char[4] tag=file[$-9..$-5];
		reverse(tag[]);
		if(noDup) enforce(tag !in result);
		result[tag]=load(file);
	}
	foreach(folder;folders){
		if(readFromWads){
			enforce(!!wadManager);
			foreach(file;wadManager.byExt.get(extension,[])){
				if(file.startsWith(folder))
					handle(file);
			}
		}else{
			import std.file;
			foreach(file;dirEntries(folder,"*."~cast(immutable)extension[],SpanMode.depth))
				handle(file);
		}
	}
	return cast(typeof(return))result;

}

immutable(Bldg)[char[4]] makeBldgByTag(bool readFromWads){
	return makeByTag!loadBldg(readFromWads,bldgFolders,"BLDG");
}
immutable(char[4])[immutable(Bldg)*] makeBldgTags(){
	char[4][immutable(Bldg)*] result;
	foreach(k,ref v;bldgs){
		assert(&v !in result);
		result[&v]=k;
	}
	return cast(typeof(return))result;
}

string[char[4]] makeBldgModlByTag(bool readFromWads){
	return makeFileIndex(readFromWads,bldgModlFolders,"MRMM");
}

immutable(Bldg)[char[4]] bldgs;
immutable(char[4])[immutable(Bldg)*] bldgTags;
string[char[4]] bldgModls;

immutable landFolders=["extracted/ethr/ethr.WAD!/ethr.LAND",
                       "extracted/prsc/prsc.WAD!/prsc.LAND",
                       "extracted/pyro_a/PY_A.WAD!/PY_A.LAND",
                       "extracted/james_a/JA_A.WAD!/JA_A.LAND",
                       "extracted/strato_a/ST_A.WAD!/ST_A.LAND",
                       "extracted/char/char.WAD!/char.LAND"].fixPaths;

immutable godThemes=["data/music/God Realm.mp3",
                     "data/music/persephone_normal.mp3",
                     "data/music/pyro_normal.mp3",
                     "data/music/james_normal.mp3",
                     "data/music/stratos_normal.mp3",
                     "data/music/charnel_normal.mp3"].fixPaths;

string[char[4]] makeWidgModlByTag(bool readFromWads){
	return makeFileIndex(readFromWads,landFolders,"WIDG");
}
string[char[4]] widgModls;

immutable string[] spellsFolders=["extracted/spells"].fixPaths;

immutable char[4][] peasantTags=["zepa","zepd","zepe","zepf","saep"];

immutable(T)[char[4]] makeSpellByTag(T)(bool readFromWads){
	enum char[4] ext=toUpper(T.stringof);
	auto result=cast(T[char[4]])makeByTag!(mixin(`load`~T.stringof))(readFromWads,spellsFolders,ext);
	static if(is(T==Cre8)){
		foreach(k,ref spell;result) if(spell.creatureSSET=="tsif") swap(spell.creatureSSET,spell.meleeSSET);
		// dragon hatchlings have flying animations, but cannot fly
		// peasants have pulling animations stored in flying animations
		static immutable nonFlyingTags=["rdbO","tshg"];
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
			c.animations.death[]="\0\0\0\0";
		}
		fixFamiliar(result["imaf"]);
		fixFamiliar(result["tnem"]);
	}
	return cast(typeof(return))result;
}

immutable(char[4])[char[4]] makeTagBySaxsModelTag(bool readFromWads){
	char[4][char[4]] result;
	static char[4] load(T)(string file){
		return mixin(`load`~T.stringof)(file).saxsModel;
	}
	foreach(T;Seq!(Cre8,Wizd)){
		enum ext=toUpper(T.stringof);
		foreach(k,v;makeByTag!(load!T)(readFromWads,spellsFolders,ext))
			result[v]=k;
	}
	return cast(typeof(return))result;
}

immutable(Cre8)[char[4]] cre8s;
immutable(Wizd)[char[4]] wizds;
immutable(Spel)[char[4]] spels;
immutable(Strc)[char[4]] strcs;

immutable(char[4])[char[4]] tagsFromModel;

immutable string[] saxsModlFolders=["extracted/saxs/mrtd.WAD!",
                                    "extracted/saxs_add/AADD.WAD!",
                                    "extracted/saxs_odd/sxod.WAD!",
                                    "extracted/saxs_r1/sxr1.WAD!",
                                    "extracted/saxs_r2/sxr2.WAD!",
                                    "extracted/saxs_r3/sxr3.WAD!",
                                    "extracted/saxs_r4/sxr4.WAD!",
                                    "extracted/saxs_r5/sxr5.WAD!",
                                    "extracted/saxs_r6/sxr6.WAD!",
                                    "extracted/saxs_r7/sxr7.WAD!",
                                    "extracted/saxs_r8/sxr8.WAD!",
                                    "extracted/saxs_r9/sxr9.WAD!",
                                    "extracted/saxs_r10/sr10.WAD!",
                                    "extracted/saxs_r11/sr11.WAD!",
                                    "extracted/saxshero/hero.WAD!",
                                    "extracted/saxs_wiz/sxwz.WAD!"].fixPaths;

string[char[4]] makeSaxsModlByTag(bool readFromWads){
	return makeFileIndex(readFromWads,saxsModlFolders,"SXMD");
}
string[][char[4]] makeSaxsAnimByTag(bool readFromWads){
	return makeFileIndex!(true,true)(readFromWads,saxsModlFolders,"SXSK");
}
string[char[4]] saxsModls;
string[][char[4]] saxsAnims;

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

immutable string[] iconFolders=["extracted/main/MAIN.WAD!/icon.FLDR"].fixPaths;
string[char[4]] icons;
string[char[4]] makeIconByTag(bool readFromWads){
	 // some icons seem to be replicated, e.g. rded.ICON
	return makeFileIndex(readFromWads,iconFolders,"ICON",false);
}

immutable string[] ssetFolders=["extracted/sounds/SFX_.WAD!"].fixPaths;
immutable(Sset)[char[4]] ssets;
immutable(Sset)[char[4]] makeSsetByTag(bool readFromWads){
	return makeByTag!loadSSET(readFromWads,ssetFolders,"SSET");
}
immutable string[] sampFolders=["extracted/sounds/SFX_.WAD!",
                                "extracted/local/sfx_english/SFXe.WAD!"].fixPaths;
immutable char[4][] commandAppliedSoundTags=["1lcI","2lcI"];

string[char[4]] samps;
string[char[4]] makeSampByTag(bool readFromWads){
	// samp names flp1, flp2, flp3, flp4, flp5 appear in both pyro and comn. TODO: figure this out
	return makeFileIndex(readFromWads,sampFolders,"SAMP",false);
}

immutable string[] textFolders=["extracted/local/lang_english/LANG.WAD!/ENGL.LANG",
                                "extracted/local/langp3_english/LNG+.WAD!/addl.LANG"].fixPaths;

immutable(string)[char[4]] texts;
immutable(string)[char[4]] makeTextByTag(bool readFromWads){
	import text_;
	// TODO: split into multiple tables to avoid duplicate tags
	return makeByTag!loadText(readFromWads,textFolders,"TEXT",false);
}

void initNTTData(bool readFromWads){
	bldgs=makeBldgByTag(readFromWads);
	bldgTags=makeBldgTags();
	bldgModls=makeBldgModlByTag(readFromWads);

	widgModls=makeWidgModlByTag(readFromWads);

	cre8s=makeSpellByTag!Cre8(readFromWads);
	wizds=makeSpellByTag!Wizd(readFromWads);
	spels=makeSpellByTag!Spel(readFromWads);
	strcs=makeSpellByTag!Strc(readFromWads);

	tagsFromModel=makeTagBySaxsModelTag(readFromWads);

	saxsModls=makeSaxsModlByTag(readFromWads);
	saxsAnims=makeSaxsAnimByTag(readFromWads);

	icons=makeIconByTag(readFromWads);

	ssets=makeSsetByTag(readFromWads);
	samps=makeSampByTag(readFromWads);

	texts=makeTextByTag(readFromWads);
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

enum RangedType{
	melee,
	ranged,
	friendlyRanged,
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
	bool continuousRegeneration=false;
	auto soulDisplacement=Vector3f(0.0f,0.0f,0.0f);
	float buildingMeleeDamageMultiplier=1.0f; // TODO: is this in creature stats?
	RangedType ranged=RangedType.melee; // TODO: is this in creature data?
}

CreatureData abomination={
	tag: "ctug",
	name: "Abomination",
	ranged: RangedType.ranged,
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
	ranged: RangedType.ranged,
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
	soulDisplacement: Vector3f(0.0f,-1.0f,0.0f),
	ranged: RangedType.ranged,
};

CreatureData boulderdash={
	tag: "llab",
	name: "Boulderdash",
	rotateOnGround: RotateOnGround.sideways,
	ranged: RangedType.ranged,
};

CreatureData brainiac={
	tag: "bobs",
	name: "Brainiac",
	ranged: RangedType.ranged,
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
	ranged: RangedType.ranged,
};

CreatureData dragon={
	tag: "grdg",
	name: "Dragon",
	rotateOnGround: RotateOnGround.completely,
	hitboxType: HitboxType.largeZ,
	stunBehavior: StunBehavior.always,
	buildingMeleeDamageMultiplier: 2.0f,
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
	ranged: RangedType.ranged,
};

CreatureData ent={
	tag: "mtsl",
	name: "Ent",
	rotateOnGround: RotateOnGround.completely,
	hitboxType: HitboxType.largeZ,
	stunBehavior: StunBehavior.fromBehind,
	soulDisplacement: Vector3f(0.0f,-1.0f,0.0f),
};

CreatureData faestus1={
	tag: "ehtH",
	name: "Faestus",
	ranged: RangedType.ranged,
};

CreatureData faestus2={
	tag: "EHTH",
	name: "Faestus",
	ranged: RangedType.ranged,
};

CreatureData fallen={
	tag: "dplk",
	name: "Fallen",
	ranged: RangedType.ranged,
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
	name: "Flame Minion",
	ranged: RangedType.ranged,
};

CreatureData flummox={
	tag: "wlce",
	name: "Flummox",
	rotateOnGround: RotateOnGround.sideways,
	ranged: RangedType.ranged,
};

CreatureData flurry={
	tag: "wlca",
	name: "Flurry",
	rotateOnGround: RotateOnGround.sideways,
	soulDisplacement: Vector3f(0.0f,0.6f,0.0f),
	ranged: RangedType.ranged,
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
	ranged: RangedType.ranged,
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
	ranged: RangedType.ranged,
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
	ranged: RangedType.ranged,
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
	soulDisplacement: Vector3f(0.0f,-1.0f,0.0f),
};

CreatureData locust={
	tag: "pazb",
	name: "Locust",
	ranged: RangedType.ranged,
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
	ranged: RangedType.ranged,
};

CreatureData necryl={
	tag: "glsd",
	name: "Necryl",
	rotateOnGround: RotateOnGround.completely,
	ranged: RangedType.ranged,
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
	ranged: RangedType.ranged,
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
	ranged: RangedType.ranged,
};

CreatureData ranger={
	tag: "amuh",
	name: "Ranger",
	ranged: RangedType.ranged,
};

CreatureData rhinok={
	tag: "gard",
	name: "Rhinok",
	rotateOnGround: RotateOnGround.completely,
	// hitboxType: ?
	stunBehavior: StunBehavior.always,
	ranged: RangedType.ranged,
};

CreatureData sacDoctor={
	tag: "dcas",
	name: "Sac Doctor",
};

CreatureData saraBella={
	tag: "pezH",
	name: "Sara Bella",
	ranged: RangedType.ranged,
};

CreatureData scarab={
	tag: "cara",
	name: "Scarab",
	rotateOnGround: RotateOnGround.completely,
	ranged: RangedType.friendlyRanged,
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
	ranged: RangedType.ranged,
};

CreatureData silverback={
	tag: "grdb",
	name: "Silverback",
	zfactorOverride: 1.0,
	rotateOnGround: RotateOnGround.completely,
	stunBehavior: StunBehavior.always,
	soulDisplacement: Vector3f(0.0f,0.0f,2.0f),
	ranged: RangedType.ranged,
};

CreatureData sirocco={
	tag: "risH",
	name: "Sirocco",
	rotateOnGround: RotateOnGround.completely,
	hitboxType: HitboxType.largeZ,
	stunBehavior: StunBehavior.fromBehind,
	buildingMeleeDamageMultiplier: 2.0f,
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
	ranged: RangedType.ranged,
};

CreatureData squall={
	tag: "alab",
	name: "Squall",
	rotateOnGround: RotateOnGround.sideways,
	ranged: RangedType.ranged,
};

CreatureData stormGiant={
	tag: "rgos",
	name: "Storm Giant",
	stunBehavior: StunBehavior.fromBehind,
	buildingMeleeDamageMultiplier: 0.5f,
};

CreatureData styx={
	tag: "nugd",
	name: "Styx",
	// hitboxType: ?
	stunnedBehavior: StunnedBehavior.onMeleeDamage,
	ranged: RangedType.ranged,
};

CreatureData sylph={
	tag: "ahcr",
	name: "Sylph",
	ranged: RangedType.ranged,
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
	ranged: RangedType.ranged,
};

CreatureData tickferno={
	tag: "craf",
	name: "Tickferno",
	rotateOnGround: RotateOnGround.completely,
	ranged: RangedType.ranged,
};

CreatureData toldor={
	tag: "oohH",
	name: "Toldor",
	rotateOnGround: RotateOnGround.completely,
	hitboxType: HitboxType.largeZ,
	stunBehavior: StunBehavior.fromBehind,
	soulDisplacement: Vector3f(0.0f,-1.2f,0.4f),
};

CreatureData trogg={
	tag: "ycro",
	name: "Trogg",
};

CreatureData troll={
	tag: "lort",
	name: "Troll",
	continuousRegeneration: true,
};

CreatureData vortick={
	tag: "craa",
	name: "Vortick",
	rotateOnGround: RotateOnGround.completely,
	ranged: RangedType.ranged,
};

CreatureData warmonger={
	tag: "nugf",
	name: "Warmonger",
	// hitboxType: ?
	stunnedBehavior: StunnedBehavior.onMeleeDamage,
	ranged: RangedType.ranged,
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
char[4] tagFromCreatureName(string name){
Lswitch: switch(name){
		static foreach(dataName;__traits(allMembers, nttData)){
			static if(is(typeof(mixin(`nttData.`~dataName))==CreatureData)&&mixin(`nttData.`~dataName).name!="Faestus"){
				static if(mixin(`nttData.`~dataName).tag!=(char[4]).init)
				case mixin(`nttData.`~dataName).name, toLower(mixin(`nttData.`~dataName).name):
					return mixin(`nttData.`~dataName).tag;
			}
		}
		default: return (char[4]).init;
	}
}

enum SpellTag:char[4]{
	// neutral creatures:
	manahoar="oham",
	sacDoctor="dcas",
	familiar="imaf",
	zyzyx="tnem",
	// neutral spells:
	speedup="pups",
	heal="laeh",
	// persephone creatures:
	druid="nmuh",
	ranger="amuh",
	shrike="tbsh",
	scarab="cara",
	troll="lort",
	gnome="plfl",
	gremlin="lrps",
	mutant="cbab",
	ent="mtsl",
	dragon="grdg",
	// persephone heroes:
	dragonHatchling="rdbO",
	faestus1="ehtH",
	toldor="oohH",
	sirocco="risH",
	// persephone spells
	wrath="oalf",
	etherealForm="mrfe",
	graspingVines="eniv",
	rainbow="wobr",
	rainOfFrogs="grfr",
	healingAura="ruah",
	vineWall="lawv",
	charm="mrhc",
	meanstalks="rter",
	// pyro creatures:
	cog="zidf",
	flameMinion="fplk",
	spitfire="sohf",
	tickferno="craf",
	firefist="lrtf",
	pyromaniac="plff",
	pyrodactyl="kacf",
	bombard="wlcf",
	warmonger="nugf",
	phoenix="grdr",
	// pyro heroes:
	faestus2="EHTH",
	// pyro spells:
	fireball="brif",
	fireform="mrff",
	ringsOfFire="rapf",
	dragonfire="rifd",
	explosion="pxef",
	firewall="lwrf",
	rainOfFire="rifr",
	blindRage="egar",
	volcano="clov",
	// james creatures:
	trogg="ycro",
	earthfling="palk",
	gargoyle="sohe",
	basilisk="guls",
	taurock="raeb",
	flummox="wlce",
	ikarus="kace",
	boulderdash="llab",
	jabberocky="mtse",
	rhinok="gard",
	// james heroes:
	gammel="magH",
	// james spells:
	rock="kcor",
	skinOfStone="niks",
	soulMole="pmcd",
	erupt="tpre",
	haloOfEarth="olah",
	wallOfSpikes="laws",
	bombardment="rtem",
	bovineIntervention="ivob",
	bore="erob",
	// stratos creatures:
	frostwolf="lbog",
	sylph="ahcr",
	brainiac="bobs",
	vortick="craa",
	squall="alab",
	stormGiant="rgos",
	seraph="grps",
	flurry="wlca",
	yeti="ycrp",
	silverback="grdb",
	// stratos heroes:
	saraBella="pezH",
	lordSurtur="uslH",
	// stratos spells:
	lightning="ntil",
	airShield="dlhs",
	freeze="zerf",
	chainLightning="ntlc",
	soulWind="dnws",
	frozenGround="zorf",
	fence="cnef",
	cloudkill="likc",
	tornado="nrot",
	// charnel creatures:
	scythe="dzid",
	fallen="dplk",
	locust="pazb",
	necryl="glsd",
	blight="kacd",
	netherfiend="crpd",
	deadeye="plfd",
	abomination="ctug",
	styx="nugd",
	hellmouth="nomd",
	// charnel heroes:
	gangrel="ramH",
	astaroth="RAMH",
	thestor="eafH",
	// charnel spells:
	insectSwarm="mrws",
	protectiveSwarm="rwsp",
	slime="htel",
	animateDead="deda",
	demonicRift="tfir",
	wailingWall="laww",
	plague="galp",
	intestinalVaporization="pavi",
	death="taed",
	// structure spells:
	manalith="htlm",
	guardian="ndrg",
	convert="ccas",
	desecrate="ucas",
	teleport="elet",
	shrine="pcas",
	// creature abilities:
	runAway="!nur",
	playDead="dedp",
	rockForm="dihk",
	stealth="ivni",
	lifeShield="hsba",
	divineSight="eesd",
	protector="HSba",
	// passive abilities:
	steamCloud="goc@",
	poisonCloud="cen@",
	// ranged attacks:
	brainiacShoot="bsba",
	shrikeShoot="absh",
	locustShoot="zbba",
	spitfireShoot="fhba",
	gargoyleShoot="ehba",
	earthflingShoot="ekba",
	flameMinionShoot="fkba",
	fallenShoot="dkba",
	sylphShoot="aaba",
	rangerShoot="wobf",

	necrylShoot="cena",
	scarabShoot="slba",
	basiliskShoot="dpsf",
	tickfernoShoot="sfba",
}

enum WizardTag:char[4]{
	abraxus="0ewc",
	acheron="1dwc",
	ambassadorButa="0fwc",
	charlotte="2fwc",
	eldred="2ewc",
	grakkus="1fwc",
	hachimen="2lwc",
	jadugarr="0awc",
	marduk="2awc",
	mithras="1ewc",
	seerix="1awc",
	shakti="0lwc",
	sorcha="2dwc",
	theRagman="0dwc",
	yogo="1lwc",
}


import ntts: God;
private alias ST=SpellTag;
immutable ST[] neutralCreatures=[ST.manahoar];
immutable ST[] persephoneCreatures=[ST.druid,ST.ranger,ST.shrike,ST.scarab,ST.troll,ST.gnome,ST.gremlin,ST.mutant,ST.ent,ST.dragon];
immutable ST[] pyroCreatures=[ST.cog,ST.flameMinion,ST.spitfire,ST.tickferno,ST.firefist,ST.pyromaniac,ST.pyrodactyl,ST.bombard,ST.warmonger,ST.phoenix];
immutable ST[] jamesCreatures=[ST.trogg,ST.earthfling,ST.gargoyle,ST.basilisk,ST.taurock,ST.flummox,ST.ikarus,ST.boulderdash,ST.jabberocky,ST.rhinok];
immutable ST[] stratosCreatures=[ST.frostwolf,ST.sylph,ST.brainiac,ST.vortick,ST.squall,ST.stormGiant,ST.seraph,ST.flurry,ST.yeti,ST.silverback];
immutable ST[] charnelCreatures=[ST.scythe,ST.fallen,ST.locust,ST.necryl,ST.blight,ST.netherfiend,ST.deadeye,ST.abomination,ST.styx,ST.hellmouth];
immutable ST[][6] creatureSpells=[neutralCreatures,neutralCreatures~persephoneCreatures,neutralCreatures~pyroCreatures,neutralCreatures~jamesCreatures,neutralCreatures~stratosCreatures,neutralCreatures~charnelCreatures];
static assert(creatureSpells.length==God.max+1);
immutable ST[] neutralSpells=[ST.speedup,ST.heal];
immutable ST[] persephoneSpells=[ST.wrath,ST.etherealForm,ST.graspingVines,ST.rainbow,ST.rainOfFrogs,ST.healingAura,ST.vineWall,ST.charm,ST.meanstalks];
immutable ST[] pyroSpells=[ST.fireball,ST.fireform,ST.ringsOfFire,ST.dragonfire,ST.explosion,ST.firewall,ST.rainOfFire,ST.blindRage,ST.volcano];
immutable ST[] jamesSpells=[ST.rock,ST.skinOfStone,ST.soulMole,ST.erupt,ST.haloOfEarth,ST.wallOfSpikes,ST.bombardment,ST.bovineIntervention,ST.bore];
immutable ST[] stratosSpells=[ST.lightning,ST.airShield,ST.freeze,ST.chainLightning,ST.soulWind,ST.frozenGround,ST.fence,ST.cloudkill,ST.tornado];
immutable ST[] charnelSpells=[ST.insectSwarm,ST.protectiveSwarm,ST.slime,ST.animateDead,ST.demonicRift,ST.wailingWall,ST.plague,ST.intestinalVaporization,ST.death];
immutable ST[][6] normalSpells=[neutralSpells,neutralSpells~persephoneSpells,neutralSpells~pyroSpells,neutralSpells~jamesSpells,neutralSpells~stratosSpells,neutralSpells~charnelSpells];
static assert(normalSpells.length==God.max+1);
immutable ST[] structureSpells=[ST.manalith,ST.guardian,ST.convert,ST.desecrate,ST.teleport,ST.shrine];

immutable ST[] specialCreatures=[ST.dragonHatchling]; // TODO: is this treated like a hero creature?
immutable ST[] heroCreatures=[ST.faestus1,ST.toldor,ST.sirocco,ST.faestus2,ST.gammel,ST.saraBella,ST.lordSurtur,ST.gangrel,ST.astaroth,ST.thestor];
immutable ST[] familiarCreatures=[ST.familiar,ST.zyzyx];

God getSpellGod(char[4] tag){ // TODO: figure out where this is stored
	static God[char[4]] getIndex(){
		God[char[4]] index;
		import std.traits: EnumMembers;
		foreach(god;EnumMembers!God){
			foreach(tag;chain(creatureSpells[god],normalSpells[god]))
				if(tag!in index) index[tag]=god;
		}
		return index;
	}
	switch(tag){
		static foreach(stag,god;getIndex())
		case stag: return god;
		default: return God.none;
	}

}

import std.traits:EnumMembers;
static immutable wizards=[EnumMembers!WizardTag];
