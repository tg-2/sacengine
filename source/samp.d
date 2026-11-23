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
	enforce(data.length>=Header.sizeof);
	Header header;
	(cast(ubyte*)&header)[0..Header.sizeof]=data[0..Header.sizeof];
	auto blockAlign=header.blockAlign;
	auto buffer=data[Header.sizeof..$];
	auto channels=header.channels;
	enforce(channels==1||channels==2);
	enforce(blockAlign>=4*channels);
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
	static short clampToShort(int x){
		if(x<=short.min) return short.min;
		if(x>=short.max) return short.max;
		return cast(short)x;
	}
	size_t numSamples;
	for(auto remaining=buffer;remaining.length;){
		auto blockSize=remaining.length<blockAlign?remaining.length:blockAlign;
		enforce(blockSize>=4*channels);
		auto compressedSize=blockSize-4*channels;
		// stereo blocks contain four compressed bytes per channel in turn.
		enforce(channels==1||compressedSize%(4*channels)==0);
		numSamples+=channels+2*compressedSize;
		remaining=remaining[blockSize..$];
	}
	short[] result;
	// decode ima adpcm
	result.length=numSamples;
	size_t outputOffset;
	while(buffer.length){
		auto blockSize=buffer.length<blockAlign?buffer.length:blockAlign;
		auto block=buffer[0..blockSize];
		buffer=buffer[blockSize..$];
		int[2] predictors,stepIndices;
		foreach(channel;0..channels){
			auto offset=4*channel;
			auto predictor=cast(short)(block[offset+1]<<8|block[offset]);
			predictors[channel]=predictor;
			stepIndices[channel]=block[offset+2];
			result[outputOffset+channel]=predictor;
		}
		size_t frame=1;
		auto offset=4*channels;
		while(offset<block.length){
			foreach(channel;0..channels){
				foreach(i;0..4){
					if(offset>=block.length) break; // a final mono block may have a short group.
					auto packed=block[offset++];
					foreach(nibbleIndex;0..2){
						auto nibble=nibbleIndex==0?packed&0x0f:packed>>4;
						if(stepIndices[channel]<0) stepIndices[channel]=0;
						if(stepIndices[channel]>88) stepIndices[channel]=88;
						auto step=ima_step_table[stepIndices[channel]];
						auto sign=nibble&8;
						auto delta=nibble&7;
						auto diff=((2*delta+1)*step)>>3;
						if(sign) predictors[channel]-=diff;
						else predictors[channel]+=diff;
						auto predictor=clampToShort(predictors[channel]);
						predictors[channel]=predictor;
						stepIndices[channel]+=ima_index_table[nibble];
						result[outputOffset+(frame+2*i+nibbleIndex)*channels+channel]=predictor;
					}
				}
			}
			frame+=8;
		}
		outputOffset+=channels+2*(block.length-4*channels);
	}
	enforce(outputOffset==result.length);
	return cast(ubyte[])result;
}

struct SampHeader{
	ubyte[4] unknown0;
	ubyte[4] unknown1;
	ubyte[4] unknown2;
	uint size;
	ushort audioFormat=1;
	ushort channels=1;
	uint sampleRate=22050;
	uint byteRate=44100;
	ushort unknown5=32;
	ushort bitsPerSample=16;
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

int sampDuration(Samp samp,int framesPerSecond){
	auto byteRate=short.sizeof*samp.header.channels*samp.header.sampleRate;
	if(!byteRate) return 0;
	return cast(int)((samp.data.length*framesPerSecond+byteRate-1)/byteRate);
}

Samp loadSAMP(string filename){
	enforce(filename.endsWith(".SAMP"));
	return parseSAMP(readFile(filename));
}

Samp sliceSAMP(Samp orig,float lfrac,float rfrac){
	auto header=new SampHeader;
	*header=*orig.header;
	auto frameSize=cast(uint)(short.sizeof*orig.header.channels);
	enforce(frameSize!=0);
	enforce(orig.data.length%frameSize==0);
	auto l=cast(uint)(orig.data.length*lfrac)/frameSize*frameSize;
	auto r=cast(uint)(orig.data.length*rfrac+frameSize-1)/frameSize*frameSize;
	header.size=r-l;
	return Samp(header,orig.data[l..r]);
}
