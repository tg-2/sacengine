// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import std.exception, std.string;
import util;

string parseText(ubyte[] data){
	if(data.length&&data[$-1]=='\0') data=data[0..$-1];
	auto text=cast(string)data;
	// TEXT files are in a Windows code page: if this is not valid UTF-8, read it as Windows-1252
	// (fonts map characters back to Windows-1252 bytes, so localized fonts still get their original bytes)
	import std.utf: validate, UTFException;
	try validate(text);
	catch(UTFException){
		static immutable dchar[32] windows1252={
			dchar[32] r;
			static immutable ushort[32] high=[0x20AC,0x81,0x201A,0x0192,0x201E,0x2026,0x2020,0x2021,0x02C6,0x2030,0x0160,0x2039,0x0152,0x8D,0x017D,0x8F,
			                                  0x90,0x2018,0x2019,0x201C,0x201D,0x2022,0x2013,0x2014,0x02DC,0x2122,0x0161,0x203A,0x0153,0x9D,0x017E,0x0178];
			foreach(i;0..32) r[i]=high[i];
			return r;
		}();
		import std.array: appender;
		import std.utf: encode;
		auto result=appender!string();
		foreach(ubyte b;data){
			dchar c=0x80<=b&&b<0xA0?windows1252[b-0x80]:cast(dchar)b;
			char[4] buf;
			result.put(buf[0..encode(buf,c)]);
		}
		text=result.data;
	}
	// TEXT files write line breaks as \n
	import std.algorithm: canFind;
	import std.array: replace;
	if(text.canFind(`\n`)) text=text.replace(`\n`,"\n");
	return text;
}
string loadText(string filename){
	enforce(filename.endsWith(".TEXT"));
	return parseText(readFile(filename));
}
