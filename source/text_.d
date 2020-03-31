import std.exception, std.string;
import util;

string parseText(ubyte[] data){
	if(data[$-1]=='\0') data=data[0..$-1];
	return cast(string)data;
}
string loadText(string filename){
	enforce(filename.endsWith(".TEXT"));
	return parseText(readFile(filename));
}
