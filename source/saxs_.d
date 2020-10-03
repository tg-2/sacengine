// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

module saxs_;
import util;
import std.string, std.exception;

struct SAXS{
	float scaling;
	uint unknown0;
	ubyte[4] unknown1;
	float resolution; // larger values mean fewer triangles
	float unknown2;
	uint unknown3;
	uint unknown4; // unused?
	uint unknown5; // unused?
	uint unknown6; // unused?
	float unknown7;
	uint[28] unknown8; // unused?
	uint unknown9;
	uint unknown10;
	uint unknown11;
	uint unknown12;
	uint unknown13;
	uint unknown14;
	uint unknown15;
	uint unknown16; // unused?
	bool[32] hitboxBones;
	uint unknown18;
	uint unknown19; // unused?
}
static assert(SAXS.sizeof==224);

SAXS parseSAXS(ubyte[] data){
	enforce(data.length>=SAXS.sizeof);
	return *cast(SAXS*)data.ptr;
}

SAXS loadSAXS(string filename){
	enforce(filename.endsWith(".SAXS"));
	return parseSAXS(readFile(filename));
}

