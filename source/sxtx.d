import util;
import dlib.image,dlib.image.color;
import std.stdio, std.string, std.algorithm, std.path, std.exception;

SuperImage loadSXTX(string filename,bool alpha){
	enforce(filename.endsWith(".SXTX"));
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
	auto img=loadTGA(filename);
	if(!alpha) return img;
	auto nimg=image(img.width,img.height,4); // TODO: process data only once
	foreach(y;0..img.height){
		foreach(x;0..img.width){
			auto color=img[x,y];
			nimg[x,y]=Color4f(color.r,color.g,color.b,color==Color4f(0,0,0)?0.0f:1.0f);
		}
	}
	img.free();
	return nimg;
}
