// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import util;
import std.string, std.exception;

enum FogType:ubyte{
	linear=0,
	exponential=1,
}

struct Envi{
	uint size;
	float sunDirectStrength;
	float sunAmbientStrength;
	float ambientRed;
	float ambientGreen;
	float ambientBlue;
	ubyte skyBlue;
	ubyte skyGreen;
	ubyte skyRed;
	ubyte unused0=0;
	uint unknown0=31;
	uint minAlphaInt;
	uint maxAlphaInt;
	float minAlphaFloat;
	float maxAlphaFloat;
	char[4] sky_;
	uint[15] unused1=0;
	char[4] skyt;
	uint[15] unused2=0;
	char[4] skyb;
	uint[15] unused3=0;
	char[4] sun_;
	uint[15] unused4=0;
	char[4] undr;
	uint[15] unused5=0;
	float shadowStrength;
	float sunDirectionX;
	float sunDirectionY;
	float sunDirectionZ;
	ubyte sunColorRed;
	ubyte sunColorGreen;
	ubyte sunColorBlue;
	ubyte unused6=0;
	ubyte sunFullbrightRed;
	ubyte sunFullbrightGreen;
	ubyte sunFullbrightBlue;
	ubyte unused7=0;
	float landscapeSpecularity;
	float landscapeGlossiness;
	ubyte specularityRed;
	ubyte specularityGreen;
	ubyte specularityBlue;
	ubyte unused8=0;
	char[4] edge;
	ubyte fogBlue;
	ubyte fogGreen;
	ubyte fogRed;
	ubyte unused9=0;
	FogType fogType;
	float fogNearZ;
	float fogFarZ;
	float fogDensity;
}

Envi parseENVI(ubyte[] data){	
	enforce(data.length==Envi.sizeof);
	auto envi=cast(Envi*)data.ptr;
	enforce(envi.size==Envi.sizeof);
	return *envi;
}

Envi loadENVI(string filename){
	enforce(filename.endsWith(".ENVI"));
	return parseENVI(readFile(filename));
}
