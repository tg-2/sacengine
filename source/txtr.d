// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import util;
import dlib.image,dlib.image.color;
import std.stdio, std.string, std.algorithm, std.path, std.exception;

SuperImage loadTXTR(string filename){
	enforce(filename.endsWith(".TXTR")||filename.endsWith(".ICON"));
	auto base = filename[0..$-".TXTR".length];
	auto txt=readFile(filename);
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
		palt=readFile(palFile);
		palt=palt[8..$]; // header bytes (TODO: figure out what they mean)
	}
	auto channels=3+(hasAlphaColor||hasExplicitAlpha);
	auto img=image(width, height, channels);
	auto data=img.data;
	static foreach(schannels;3..5){
		if(channels==schannels){
			foreach(i;0..data.length/schannels){
				auto ccol=txt[i];
				ubyte[3] tcol;
				if(grayscale) tcol=[ccol,ccol,ccol];
				else tcol=[palt[3*ccol+0],palt[3*ccol+1],palt[3*ccol+2]];
				data[schannels*i..schannels*i+3]=tcol[];
				static if(schannels==4){
					if(!(hasAlphaColor&&tcol==alphaColor))
						data[schannels*i+3]=alphaChannel.length?alphaChannel[i]:255;
				}
			}
			goto Lend;
		}
	}
Lend:;
	return img;
}
