import util;
import dlib.core.stream,dlib.image,dlib.image.color;
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
	auto img=loadTGA(new ArrayStream(readFile(filename)));
	if(!alpha) return img;
	auto nimg=image(img.width,img.height,4); // TODO: process data only once
	auto data=img.data,ndata=nimg.data;
	foreach(i;0..nimg.data.length/4){
		ndata[4*i..4*i+3]=data[3*i..3*i+3];
		ndata[4*i+3]=data[3*i]==0&&data[3*i+1]==0&&data[3*i+2]==0?0:255;
	}
	img.free();
	return nimg;
}
