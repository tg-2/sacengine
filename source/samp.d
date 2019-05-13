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
