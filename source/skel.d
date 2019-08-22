import std.exception, std.string;
import util;

struct SkelEvent{
	uint frame;
	char[4] tag;
	float parameter;
}
struct SkelHand{
	ushort bone;
	ushort unknown;
	float[3] offset;
}
struct Skel{
	uint unknown0; // unused?
	uint unknown1;
	uint numEvents;
	SkelEvent[8] events;
	SkelHand[2] hands;
}
static assert(Skel.sizeof==140);

Skel parseSkel(ubyte[] data){
	enforce(data.length>=Skel.sizeof);
	return *cast(Skel*)data.ptr;
}

Skel loadSkel(string filename){
	enforce(filename.endsWith(".SKEL"));
	return parseSkel(readFile(filename));
}
