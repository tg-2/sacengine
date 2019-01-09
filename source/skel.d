import std.exception, std.string;
import util;

struct SkelEvent{
	uint frame;
	char[4] tag;
	float parameter;
}
struct SkelUnknown{
	uint flags; // ?
	uint unknown0;
	uint unknown1;
	uint unknown2;
}
struct Skel{
	uint unknown0; // unused?
	uint unknown1;
	uint numEvents;
	SkelEvent[8] events;
	SkelUnknown[2] unknown2;
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
