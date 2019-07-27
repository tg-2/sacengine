import util;
import std.mmfile;
import std.stdio, std.zlib, std.algorithm, std.path, std.conv;
import std.string, std.exception;

class WadManager{
	MmFile[] wads;
	ubyte[][string] files;
	string[][char[4]] byExt;
	private void toFile(alias filenameCallback)(ubyte[] data,string name){
		files[name]=data;
		byExt[name[$-4..$][0..4]]~=name;
		static if(is(typeof(filenameCallback(name))))
			filenameCallback(name);
	}
	void indexWADs(string dataDir){
		import std.file:dirEntries,SpanMode;
		foreach(string wad;dirEntries(dataDir,"*.wad",SpanMode.depth)){
			enforce(wad.startsWith(dataDir)&&wad.endsWith(".wad"));
			indexWAD(wad,buildPath("extracted",text(asRelativePath(text("/",wad[0..$-".wad".length]),text("/",dataDir)))));
			write(".");
			stdout.flush();
		}
		writeln();
	}
	void indexWAD(alias filenameCallback=0)(string wadPath,string dirPath){
		auto wad=new MmFile(wadPath);
		wads~=wad;
		auto input=cast(ubyte[])wad[];
		auto infoOff=parseLE(input[4..8]);
		auto infoSize=parseLE(input[8..12]);
		auto unknown1=parseLE(input[12..16]);
		auto unknown2=parseLE(input[16..20]);
		size_t offset=20;
		auto info=cast(ubyte[])uncompress(input[infoOff..$]);
		int[string][string] names;
		Stack!size_t dirSiz;
		string odir=dirPath;
		while(info.length){
			auto tmp=info.eat(4).dup;
			reverse(tmp);
			auto name=cast(string)tmp.idup;
			auto tmp2=info.eat(4).dup;
			reverse(tmp2);
			auto ext=cast(string)tmp2.idup;
			if(ext !in names) names[ext]=(int[string]).init;
			auto filename=buildPath(odir,name);
			auto zsize=parseLE(info.eat(4));
			auto size=parseLE(info.eat(4));
			auto subfiles=parseLE(info.eat(4));
			auto type=parseLE(info.eat(4));
			auto unknown=parseLE(info.eat(4));
			switch(type){
				case 0: // uncompressed file
					enforce(subfiles==0);
					enforce(size==zsize);
					toFile!filenameCallback(input[offset..offset+size],text(filename,".",ext));
					offset+=size;
					break;
				case 2: // compressed file
					enforce(subfiles==0);
					toFile!filenameCallback((zsize?cast(ubyte[])uncompress(input[offset..offset+zsize]):[]),text(filename,".",ext));
					offset+=zsize;
					break;
				case 1: // folder
					if(!dirSiz.empty) --dirSiz.top;
					odir=text(filename,".",ext);
					dirSiz.push(subfiles);
					break;
				default:
					//stderr.writeln("warning: unknown type ",type);
					if(subfiles!=0) goto case 1;
					enforce(subfiles==0);
					if(zsize<size) goto case 2;
					else goto case 0;
			}
			if(type!=1&&subfiles==0) --dirSiz.top;
			while(!dirSiz.empty && dirSiz.top==0){
				dirSiz.pop;
				odir=dirName(odir);
			}
		}
		enforce(dirSiz.empty);		
	}
}
