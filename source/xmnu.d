import util;
import std.exception, std.string;

struct Xmnl{
	enum Dir:uint{
		up, down,
		left, right,
	}
	static struct Entry{
		char[4][2] entries;
		Dir dir;
	}
	Entry[] entries;
}

Xmnl parseXmnl(ubyte[] data){
	auto len=parseLE(eat(data,4));
	enforce(data.length==len*Xmnl.Entry.sizeof);
	return Xmnl(cast(Xmnl.Entry[])data);	
}

Xmnl loadXmnl(string filename){
	enforce(filename.endsWith(".XMNL"));
	return parseXmnl(readFile(filename));
}

enum XmnuCenterTag:char[4]{
	none="enon",
	attack="kcta",
	guard="drug",
	move="otog",
	manalith="htil",
	convert="ccas",
}

enum XmnuTag:char[4]{
	center="nec1",
	semicircleFormation="mes1",
	ability="iba1",
	lineFormation="nil1",
	attack="tta1",
	wedgeFormation="jdw1",
	circleFormation="ric1",
	flankRightFormation="rlf1",
	flankLeftFormation="llf1",
	changeCamera="mcc1",
	retreat="zwp1",
	skirmishFormation="rks1",
	phalanxFormation="ahp1",
	guard="aug1",
	move="vom1",
}

enum XmnuAction:char[4]{
	abort="orez",
	attack="ttat", attackDefault="kcta",
	guard="augt", guardDefault="drug",
	move="togt", moveDefault="otog",
	retreat="ziwp",
	ability="ibaK",
	formation="mrof",
	changeCamera="macc",		
	spell="lpsX",
}

enum FormationTag:char[4]{
	line="nilf",
	flankLeft="llff",
	flankRight="rlff",
	phalanx="ahpf",
	semicircle="mesf",
	circle="ricf",
	wedge="jdwf",
	skirmish="rksf",
}

struct Xmnu{
	char[4] tag;
	char[4] name;
	char[4] icon;
	//XmnuAction action;
	char[4] action;
	char[4] arg; // spell or formation tag
	char[4] unknown;
}

Xmnu parseXmnu(ubyte[] data){
	enforce(data.length==Xmnu.sizeof);
	auto xmnu=*cast(Xmnu*)data.ptr;
	return xmnu;
}

Xmnu loadXmnu(string filename){
	enforce(filename.endsWith(".XMNU"));
	return parseXmnu(readFile(filename));
}
