// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import util;
import std.exception, std.string;

struct SampHeader{
	ubyte[4] unknown0;
	ubyte[4] unknown1;
	ubyte[4] unknown2;
	uint size;
	ushort unknown3=16; // bits per sample?
	ushort unknown4=16; // bits per sample?
	uint sampleRate=22050;
	uint byteRate=44100;
	ushort unknown5=32;
	ushort unknown6=1; // channels?
}
struct Samp{
	SampHeader* header;
	ubyte[] data;
}

Samp parseSAMP(ubyte[] data){
	enforce(data.length>=SampHeader.sizeof);
	auto header=cast(SampHeader*)data.ptr;
	enforce(data.length==SampHeader.sizeof+header.size);
	return Samp(header,data[SampHeader.sizeof..$]);
}

Samp loadSAMP(string filename){
	enforce(filename.endsWith(".SAMP"));
	return parseSAMP(readFile(filename));
}

Samp sliceSAMP(Samp orig,float lfrac,float rfrac){
	auto header=new SampHeader;
	*header=*orig.header;
	auto byteRate=2;
	enforce(orig.data.length%byteRate==0);
	auto l=cast(uint)(orig.data.length*lfrac)/byteRate*byteRate;
	auto r=cast(uint)(orig.data.length*rfrac+byteRate-1)/byteRate*byteRate;
	header.size=r-l;
	return Samp(header,orig.data[l..r]);
}
