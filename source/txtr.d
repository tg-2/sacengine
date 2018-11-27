import util;
import dlib.image,dlib.image.color;
import std.stdio, std.string, std.algorithm, std.path, std.exception;

SuperImage loadTXTR(string filename){ // TODO: maybe integrate with dagon's TextureAsset
	enforce(filename.endsWith(".TXTR")||filename.endsWith(".ICON"));
	auto base = filename[0..$-".TXTR".length];
	ubyte[] txt;
	foreach(ubyte[] chunk;chunks(File(filename,"rb"),4096)) txt~=chunk;
	auto width=parseLE(txt[0..4]);
	txt=txt[4..$];
	auto height=parseLE(txt[0..4]);
	txt=txt[4..$];
	auto tmp=txt[0..4].dup;
	txt=txt[4..$];
	reverse(tmp);
	bool grayscale=false;
	string pal=cast(string)tmp.idup;
	auto hasAlphaColor=!!(txt[0]&4);
	auto hasExplicitAlpha=!!(txt[2]&1);
	ubyte[3] alphaColor=[txt[6],txt[5],txt[4]];
	txt=txt[8..$];
	txt=txt[16..$]; // remove further header bytes (TODO: figure out what they mean)
	ubyte[] alphaChannel;
	if(hasExplicitAlpha){
		enforce(txt.length==2*width*height);
		alphaChannel=txt[$-width*height..$];
		txt=txt[0..width*height];
	}
	enforce(txt.length==width*height);
	ubyte[] palt;
	if(pal.toLower()=="gray"){
		grayscale=true;
	}else{
		auto palFile=buildPath(dirName(filename), pal~".PALT");
		foreach(ubyte[] chunk;chunks(File(palFile, "rb"),4096)) palt~=chunk;
		palt=palt[8..$]; // header bytes (TODO: figure out what they mean)
	}
	auto img=image(width, height, 3+(hasAlphaColor||hasExplicitAlpha));
	foreach(y;0..height){
		foreach(x;0..width){
			auto index = y*img.width+x;
			auto ccol = txt[index];
			ubyte[3] tcol;
			if(grayscale) tcol=[ccol,ccol,ccol];
			else tcol=[palt[3*ccol+0],palt[3*ccol+1],palt[3*ccol+2]];
			if(!hasAlphaColor||tcol!=alphaColor){
				img[x,y]=Color4f(Color4(tcol[0],tcol[1],tcol[2],alphaChannel.length?alphaChannel[index]:255));
			}else img[x,y]=Color4f(Color4(tcol[0],tcol[1],tcol[2],0));
		}
	}
	return img;
}
