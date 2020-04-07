import util;
import std.exception, std.string;

enum SoundType:char[4]{
	none="\0\0\0\0",
	// creature SSETs/melee SSETs
	rescued="serX",
	selected="tncX",
	annoyed="nnaX",
	moving="fncX",
	attacking="tacX",
	melee="ttaX",
	damaged="madX",
	death="eidX",
	incantation="cniX",
	circleFormation="ricf",
	semicircleFormation="mesf",
	lineFormation="nilf",
	phalanxFormation="ahpf",
	skirmishFormation="rksf",
	wedgeFormation="jdwf",
	group1="1prg",
	group2="2prg",
	group3="3prg",
	group4="4prg",
	group5="5prg",
	group6="6prg",
	group7="7prg",
	group8="8prg",
	group9="9prg",
	group10="0prg",
	beGroup1="1gsa",
	beGroup2="2gsa",
	beGroup3="3gsa",
	beGroup4="4gsa",
	beGroup5="5gsa",
	beGroup6="6gsa",
	beGroup7="7gsa",
	beGroup8="8gsa",
	beGroup9="9gsa",
	beGroup10="0gsa",
	attackBuilding="Btta",
	advance="Gtta",
	attack="Utta",
	guardBuilding="Bdrg",
	defendArea="Gdrg",
	guardMe="Mdrg",
	guard="Udrg",
	move="Gvom",
	taunt1="1TNT",
	taunt2="2TNT",
	taunt3="3TNT",
	taunt4="4TNT",
	anyTaunt="TNTx",
	hit="tihX",
	stun="ntsX",
	hitWall="duwX",
	//?=drhX (peasants)
	//?=mrfX (peasants)
	idleTalk="tagX",
	cower="wocX",
	run="nurX",

	// spel.SSET
	sacrifice="casX",
	gib="bigX",
	suckBlood="dulb", // ?
	spirit="rips",
	spiritRevive="nips", // ?
	summon="NMUS",
	convertRevive="jncX",
	insectFlap="pfiX",
	slime="xrfX", // ?
	frog="grfX",
	bow="wobX",
	arrow="rraX",
	abomination="babX",
	sylphBow="obsX",
	fireball="lbfX",
	explodingFireball="xbfX",
	pyromaniacHit="rypX",
	laser="salX",
	oil="lioX",
	fire="rifX",
	steam="mtsX",
	ringOfFire="drfX",
	ignite="ngiX",
	onFire="fnoX",
	bombardment="bhmX",
	cog="gocX",
	rainOfFireHit="hrfX",
	unknown0="temX",
	freeze="zrfX",
	lightning="ntlX",
	breakingIce="eciX",
	bombardmentHit="thmX",
	bore="kuqX",
	boreRepair="rkqX",
	cow="wocX",
	explodingRock="pxrX",
	hover="vohX", // ?
	land="dnlX", // ?
	swarm="rwsX",
	gut="tugX",
	demon="nmdX",
	wail="lawX",
	animate="mnaX", // ?
	mites="timX",
	blade="dlbX",
	thunder="nhtX",
	wind="dnwA",
	stratosWind="UtsA", // ?
	jamesWind="UajA", // ?
	bird="drbA",
	persephoneBird="CepA", // ?
	coyote="yocA",
	jamesAnimals="NajA", // ?
	charnelAnimals="NhcA",
	crows="ercA",
	crickets="ircA",
	haunted="uahA",
	charnelWind="UhcA",
	howl="wohA",
	insects="sniA",
	insects2="ChcA", // ?
	owl="lwoA",
	snake="ansA",
	unknown1="rtsA",
	vulpture="luvA",
}

struct SsetEntry{
	char[4] type;
	char[4][] sounds;
}
struct Sset{
	char[4] name;
	SsetEntry[] entries;
	inout(char[4])[] getSounds(char[4] type)inout{
		foreach(ref e;entries)
			if(e.type==type)
				return e.sounds;
		return [];
	}
}
Sset parseSSET(ubyte[] data){
	enforce(data.length>=8);
	ubyte[4] name=data[0..4];
	auto numEntries=*cast(uint*)data[4..8].ptr;
	int offset=8;
	auto entries=new SsetEntry[](numEntries);
	foreach(ref entry;entries){
		enforce(data.length>=offset+4);
		ubyte[4] type=data[offset..offset+4];
		offset+=4;
		enforce(data.length>=offset+4);
		auto numSounds=*cast(uint*)data[offset..offset+4];
		offset+=4;
		enforce(data.length>=offset+4*numSounds);
		auto sounds=cast(char[4][])data[offset..offset+4*numSounds];
		offset+=4*numSounds;
		entry=SsetEntry(cast(char[4])type,sounds);
	}
	return Sset(cast(char[4])name,entries);
}
Sset loadSSET(string filename){
	enforce(filename.endsWith(".SSET"));
	return parseSSET(readFile(filename));
}
