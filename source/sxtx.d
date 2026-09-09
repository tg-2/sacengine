// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import util,assets;
import dlib.core.stream,dlib.image,dlib.image.color;
import std.stdio, std.string, std.algorithm, std.path, std.exception;

SuperImage loadSXTX(string filename,int chromaKey=-1){ 
//consider changing this back to alpha for the new engine
// chroma is how retail sac does it picks a color and all the pixels of that color become transparent look at saxs_.d 
	filename=fixPath(filename);
	enforce(filename.endsWith(".SXTX"));
	auto base = filename[0..$-".SXTX".length];
	if(replacementPath(base) in textureReplacements) return textureReplacements[replacementPath(base)];
	/+ubyte[] txt;
	foreach(ubyte[] chunk;chunks(File(filename,"rb"),4096)) txt~=chunk;
	auto idLength=txt[0];
	enforce(idLength==0);
	auto colorMap=txt[1];
	enforce(colorMap==0);
	auto imageType=txt[2];
	enforce(imageType==2);
	auto colorMapSpec=txt[2..7];
	enforce(colorMapSpec.all!(x=>x==0));
	auto imageSpec=txt[7..17];
	writeln(imageSpec);
	assert(0);+/ // TODO?
	auto img=loadTGA(new ArrayStream(readFile(filename)));
	if(chromaKey<0) return img;
	auto nimg=image(img.width,img.height,4); // TODO: process data only once
	auto data=img.data,ndata=nimg.data;
	auto key=cast(uint)chromaKey&0xffffff;
	foreach(i;0..nimg.data.length/4){
		ndata[4*i..4*i+3]=data[3*i..3*i+3];
		auto rgb=(cast(uint)data[3*i]<<16)|(cast(uint)data[3*i+1]<<8)|data[3*i+2];
		ndata[4*i+3]=rgb==key?0:255;
	}
	img.free();
	return nimg;
}
