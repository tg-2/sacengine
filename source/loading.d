// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

// Map and game loading can return to the main loop in between (so that the loading screen is drawn and the window
// stays responsive). This happens if the loading runs inside a LoadingTask with yielding enabled, which uses a Fiber.
// With yielding disabled (e.g. WebAssembly, where Fibers are not available) everything runs to completion at once.

import core.time: MonoTime, Duration, msecs;
import std.algorithm: max, min;

struct LoadingStatus{
	string mapFolder=null; // folder of the map being loaded (map files such as LIMG, DESC and LOAD), null until known
	float progress=0.0f; // in [0,1]
	float phaseStart=0.0f, phaseEnd=1.0f;
}
LoadingStatus loadingStatus;

// subsequent loadingStep calls report progress within [start,end]
void loadingPhase(float start,float end){
	loadingStatus.phaseStart=start;
	loadingStatus.phaseEnd=end;
	loadingStatus.progress=max(loadingStatus.progress,start);
}

// reports progress within the current phase, and returns to the main loop if enough time has passed
void loadingStep(size_t done,size_t total){
	if(total) with(loadingStatus){
		auto fraction=min(1.0f,cast(float)done/total);
		progress=max(progress,phaseStart+fraction*(phaseEnd-phaseStart));
	}
	loadingYield();
}

void loadingYield(){
	auto task=LoadingTask.current;
	if(!task||!task.yielding) return;
	auto now=MonoTime.currTime;
	if(now-task.lastYield<LoadingTask.yieldInterval) return;
	import core.thread: Fiber;
	Fiber.yield();
	task.lastYield=MonoTime.currTime;
}

final class LoadingTask{
	enum stackSize=16*1024*1024; // (loading uses large stack frames)
	enum yieldInterval=30.msecs; // return to the main loop at most this often while loading
	static LoadingTask current=null;

	bool yielding;
	private MonoTime lastYield;
	version(WebAssembly){}else{
		import core.thread: Fiber;
		private Fiber fiber=null;
	}
	private bool delegate() dg;
	private bool result;
	private bool running=false;

	this(bool yielding){
		version(WebAssembly) yielding=false;
		this.yielding=yielding;
	}
	// Starts dg, or resumes it if it returned to the main loop while loading. Returns false while dg has not
	// returned yet, true once it has returned, with its return value in result.
	// dg is only used when starting, it has to stay valid until it has returned.
	bool step(bool delegate() dg,out bool result){
		if(!yielding){
			result=dg();
			return true;
		}
		version(WebAssembly) assert(0);
		else{
			if(!running){
				this.dg=dg;
				if(!fiber) fiber=new Fiber(&run,stackSize);
				else fiber.reset();
				running=true;
			}
			auto previous=current;
			current=this;
			scope(exit) current=previous;
			lastYield=MonoTime.currTime;
			scope(failure) running=false;
			fiber.call(Fiber.Rethrow.yes);
			if(fiber.state!=Fiber.State.TERM) return false;
			running=false;
			result=this.result;
			return true;
		}
	}
	private void run(){ result=dg(); }
}

// loading screen contents of the map in mapFolder (as in the original):
// LOAD.DATA: the second word is the tag of the sample in the map's SAMP.FLDR that is played (0: none)
string loadingScreenSample(string mapFolder){
	import std.path: buildPath;
	import std.algorithm: reverse;
	import util: fileExists, readFile, normalizeFilename;
	auto loadData=buildPath(mapFolder,"LOAD.DATA");
	if(!fileExists(loadData)) return null;
	auto data=readFile(loadData);
	if(data.length<8) return null;
	char[4] name=cast(char[4])data[4..8];
	if(name=="\0\0\0\0") return null;
	reverse(cast(ubyte[])name[]);
	auto filename=buildPath(mapFolder,"SAMP.FLDR",normalizeFilename(name[].idup)~".SAMP");
	return fileExists(filename)?filename:null;
}
// LIMG.DATA: 384x384 picture (one palette index per pixel, rows from the top), followed by the palette (RGB)
// without it, the original shows data/defaultmap.tga
enum loadingScreenPictureSize=384;
ubyte[] loadingScreenPictureRGB(string mapFolder){
	import std.path: buildPath;
	import util: fileExists, readFile;
	enum n=loadingScreenPictureSize*loadingScreenPictureSize;
	auto limg=buildPath(mapFolder,"LIMG.DATA");
	if(!fileExists(limg)) return null;
	auto data=readFile(limg);
	if(data.length!=n+3*256) return null;
	auto palette=data[n..$];
	auto rgb=new ubyte[](3*n);
	foreach(i;0..n) rgb[3*i..3*i+3]=palette[3*data[i]..3*data[i]+3];
	return rgb;
}
string defaultLoadingScreenPicture(){
	import std.file: exists;
	foreach(name;["data/defaultmap.tga","data/Defaultmap.TGA","data/DefaultMap.tga","data/DEFAULTMAP.TGA"])
		if(exists(name)) return name;
	return null;
}
// DESC.TEXT: the map description is shown next to the picture
string loadingScreenText(string mapFolder){
	import std.path: buildPath;
	import util: fileExists;
	import text_: loadText;
	auto desc=buildPath(mapFolder,"ENGL.LANG","DESC.TEXT");
	return fileExists(desc)?loadText(desc):null;
}
