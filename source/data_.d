import util;
import std.string, std.exception;

ubyte[] loadDATA(string filename){
	filename=fixPath(filename);
	enforce(filename.endsWith(".DATA"));
	return readFile(filename);
}
