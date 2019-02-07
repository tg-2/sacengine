import std.exception, std.string;
import util;
import dlib.image.color;

auto sideColors=[Color4f(1.0f,1.0f,1.0f,1.0f), // white
                 Color4f(0.0f,0.0f,1.0f,1.0f), // blue
                 Color4f(0.0f,1.0f,0.0f,1.0f), // green
                 Color4f(1.0f,1.0f,0.0f,1.0f), // yellow
                 Color4f(1.0f,0.0f,1.0f,1.0f), // purple
                 Color4f(182.0f/255.0f,47.0f/255.0f,0.0f,1.0f), // brown
                 Color4f(47.0f/255.0f,0.0f,182.0f/255.0f,1.0f), // dark blue
                 Color4f(0.0f,1.0f,1.0f,1.0f)]; // blue-green

enum SideColor{
	white,
	blue,
	green,
	yellow,
	purple,
	brown,
	darkBlue,
	blueGreen,
}

enum PlayerAssignment{
	none,
	multiplayerMask=31,
	singleplayerSide=32,
	aiSide=64,
}

struct Side{
	uint id;
	uint allies;
	uint enemies;
	uint assignment;
	SideColor color;
}
static assert(Side.sizeof==20);

Side[] parseSids(ubyte[] data){
	enforce(data.length>=4);
	auto numSides=*cast(uint*)data[0..4].ptr;
	enforce(data[4..$].length==numSides*Side.sizeof);
	auto sides=cast(Side[])data[4..$];
	return sides;
}

Side[] loadSids(string filename){
	enforce(filename.endsWith(".SIDS"));
	return parseSids(readFile(filename));
}
