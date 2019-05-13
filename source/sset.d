import util;
import std.exception, std.string;

enum SoundType:char[4]{
	none="\0\0\0\0",
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
