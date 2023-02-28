// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import util;
import std.exception, std.string;

ubyte[] parseWAV(ubyte[] data){
	static struct Header{
		char[4] chunkId;
		uint chunkSize;
		char[4] format;
		// fmt chunk
		char[4] fmtChunkId;
		uint fmtChunkSize;
		ushort audioFormat;
		ushort channels;
		uint sampleRate;
		uint byteRate;
		ushort blockAlign;
		ushort bitsPerSample;
		ushort numExtraFormatBytes;
		ushort extraFormatBytes;
		// fact chunk
		char[4] factChunkId;
		uint factSize;
		uint factData;
		// data chunk
		char[4] dataID;
		uint dataSize;
	}
	Header header;
	(cast(ubyte*)&header)[0..Header.sizeof]=data[0..Header.sizeof];
	auto buffer=data[Header.sizeof..$];
	enforce(header.channels==1);
	uint cur=0;
	ubyte get_nibble(){
		ubyte result;
		if(cur&1){
			result=buffer[0]>>4;
			buffer=buffer[1..$];
		}else result=buffer[0]&0x0f;
		cur+=1;
		return result;
	}
	immutable short[16] ima_index_table = [-1, -1, -1, -1, 2, 4, 6, 8,-1, -1, -1, -1, 2, 4, 6, 8];
	immutable short[89] ima_step_table = [7, 8, 9, 10, 11, 12, 13, 14, 16, 17,
	                                      19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
	                                      50, 55, 60, 66, 73, 80, 88, 97, 107, 118,
	                                      130, 143, 157, 173, 190, 209, 230, 253, 279, 307,
	                                      337, 371, 408, 449, 494, 544, 598, 658, 724, 796,
	                                      876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066,
	                                      2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358,
	                                      5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
	                                      15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767];
	short[] result;
	result.length=2*(buffer.length-4)+1;
	int predictor=result[0]=parseShort(buffer);
	int step_index=parseShort(buffer);
	int step=0;

	short clampToShort(int x){
		if(x<=short.min) return short.min;
		if(x>=short.max) return short.max;
		return cast(short)x;
	}
	// decode ima adpcm
	// TODO: this is noisy
	foreach(ref x;result[1..$]){
		auto nibble=get_nibble();
		step=ima_step_table[step_index];
		step_index+=ima_index_table[nibble];
		if(step_index<0) step_index=0;
		if(step_index>88) step_index=88;
		auto sign=nibble&8;
		auto delta=nibble&7;
		auto diff=((2*delta+1)*step)>>3;
		if(sign) predictor-=diff;
		else predictor+=diff;
		x=clampToShort(predictor);
		predictor=x;
	}
	return cast(ubyte[])result;
}

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
	data=data[SampHeader.sizeof..$];
	if(data.startsWith("RIFF")||data.startsWith("WAVE")) // TODO: check in header instead?
		data=parseWAV(data);
	else enforce(data.length==header.size);
	return Samp(header,data);
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
