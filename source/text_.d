// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

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
