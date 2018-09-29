import dagon;
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
	ubyte[] palt;
	if(pal.toLower()=="gray"){
		grayscale=true;
	}else{
		auto palFile=buildPath(dirName(filename), pal~".PALT");
		foreach(ubyte[] chunk;chunks(File(palFile, "rb"),4096)) palt~=chunk;
		palt=palt[8..$]; // header bytes (TODO: figure out what they mean)
	}
	auto img=image(width, height);
	foreach(y;0..height){
		foreach(x;0..width){
			auto index = y*img.width+x;
			auto ccol = txt[index];
			if(grayscale){
				img[x,y]=Color4f(Color4(ccol,ccol,ccol));
			}else{
				img[x,y]=Color4f(Color4(palt[3*ccol],palt[3*ccol+1],palt[3*ccol+2]));
			}
		}
	}
	return img;
}
