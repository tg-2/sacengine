// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

module assets;

import std.range,std.algorithm,std.exception,std.string;

import dlib.image:SuperImage;
SuperImage[char[4]] textureReplacementsSloppy;
SuperImage[string] textureReplacements;
void loadTextureReplacements(string filename,bool sloppy=false){
	enforce(filename.endsWith(".zip"));
	import std.zip,std.file:read;
	auto zip=new ZipArchive(read(filename));
	foreach(name,am;zip.directory){
		if(name.length<8) continue;
		if(!name.endsWith(".png")) continue;
		zip.expand(am);
		import dlib.core.stream:ArrayStream;
		auto input=new ArrayStream(am.expandedData);
		char[4] tag;
		import std.utf:byChar;
		copy(name[$-8..$-4].byChar.retro,tag[].byChar);
		import dlib.image.io.png:loadPNG;
		if(sloppy) textureReplacementsSloppy[tag]=loadPNG(input);
		else textureReplacements[name[0..$-4]]=loadPNG(input);
	}
}

string replacementPath(string base){
	if(base.startsWith("data/")||base.startsWith(`data\`)) return base["data/".length..$];
	if(base.startsWith("extracted/")||base.startsWith(`extracted\`)) return base["extracted/".length..$];
	return base;
}
