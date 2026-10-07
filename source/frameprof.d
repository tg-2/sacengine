// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

// opt-in frame spike profiling, enabled via --log-frame-spikes[=threshold in ms]
module frameprof;

import core.time;
import std.algorithm: max, sort;
import std.datetime.stopwatch;
import std.stdio: stderr;

bool enabled=false;
long stepThreshold=10*10_000;  // hnsecs; sim steps at least this slow are logged
long frameThreshold=25*10_000; // hnsecs; rendered frames at least this slow are logged

void enable(){
	enable(10.0);
}
void enable(double thresholdMs){
	enabled=true;
	stepThreshold=cast(long)(thresholdMs*10_000);
	frameThreshold=max(25*10_000,2*stepThreshold);
}

StopWatch timer(){
	StopWatch sw;
	if(enabled) sw.start();
	return sw;
}

private enum maxPhases=32;
private int numPhases;
private string[maxPhases] phaseNames;
private Duration[maxPhases] phaseTimes;
private StopWatch stepSw;
private Duration lastMark;
private int findPathCalls;
private Duration findPathTime, findPathMax;
private int edgeUpdateCalls;
private Duration edgeUpdateTime;

private enum maxBotSlots=128;
private int numBotSlots;
private int[maxBotSlots] botSlotSide, botSlotK;
private Duration[maxBotSlots] botSlotTimes;
private StopWatch botSlotSw;

// replan sub-phases: named and nestable; accumulated times are inclusive (outer includes inner)
private enum maxReplanPhases=24;
private enum maxReplanDepth=8;
private int numReplanPhases;
private string[maxReplanPhases] replanNames;
private Duration[maxReplanPhases] replanTimes;
private int replanDepth;
private int[maxReplanDepth] replanStackIdx;
private MonoTime[maxReplanDepth] replanStackStart;

void beginReplanPhase(string name){
	if(!enabled) return;
	if(replanDepth>=maxReplanDepth) return;
	int idx=-1;
	foreach(i;0..numReplanPhases) if(replanNames[i]==name){ idx=i; break; }
	if(idx<0){
		if(numReplanPhases>=maxReplanPhases) return;
		idx=numReplanPhases++;
		replanNames[idx]=name;
	}
	replanStackIdx[replanDepth]=idx;
	replanStackStart[replanDepth]=MonoTime.currTime;
	replanDepth++;
}

void endReplanPhase(string name){
	if(!enabled) return;
	if(replanDepth==0) return;
	replanDepth--;
	replanTimes[replanStackIdx[replanDepth]]+=MonoTime.currTime-replanStackStart[replanDepth];
}

// rendered-frame phases: named, accumulate by name (a phase may be marked several times per frame)
private enum maxRenderPhases=16;
private int numRenderPhases;
private string[maxRenderPhases] renderPhaseNames;
private Duration[maxRenderPhases] renderPhaseTimes;
private StopWatch renderSw;
private Duration renderLastMark;

void beginRenderFrame(){
	if(!enabled) return;
	numRenderPhases=0;
	renderPhaseTimes[]=Duration.zero; // buckets are reused by index; without this they accumulate across frames
	renderSw.reset();
	renderSw.start();
	renderLastMark=Duration.zero;
}

void markRender(string phase){
	if(!enabled) return;
	auto now=renderSw.peek();
	auto d=now-renderLastMark;
	renderLastMark=now;
	int idx=-1;
	foreach(i;0..numRenderPhases) if(renderPhaseNames[i]==phase){ idx=i; break; }
	if(idx<0){
		if(numRenderPhases>=maxRenderPhases) return;
		idx=numRenderPhases++;
		renderPhaseNames[idx]=phase;
	}
	renderPhaseTimes[idx]+=d;
}

void beginBotSlot(){
	if(!enabled) return;
	botSlotSw.reset();
	botSlotSw.start();
}

void endBotSlot(int side,int k){
	if(!enabled) return;
	if(numBotSlots<maxBotSlots){
		botSlotSide[numBotSlots]=side;
		botSlotK[numBotSlots]=k;
		botSlotTimes[numBotSlots]=botSlotSw.peek();
		numBotSlots++;
	}
}

void beginStep(){
	if(!enabled) return;
	numPhases=0;
	numBotSlots=0;
	numReplanPhases=0;
	replanDepth=0;
	replanTimes[]=Duration.zero;
	findPathCalls=edgeUpdateCalls=0;
	findPathTime=findPathMax=edgeUpdateTime=Duration.zero;
	stepSw.reset();
	stepSw.start();
	lastMark=Duration.zero;
}

void mark(string phase){
	if(!enabled) return;
	auto now=stepSw.peek();
	if(numPhases<maxPhases){
		phaseNames[numPhases]=phase;
		phaseTimes[numPhases]=now-lastMark;
		numPhases++;
	}
	lastMark=now;
}

void countFindPath(Duration d){
	if(!enabled) return;
	findPathCalls++;
	findPathTime+=d;
	if(d>findPathMax) findPathMax=d;
}

void countEdgeUpdate(Duration d){
	if(!enabled) return;
	edgeUpdateCalls++;
	edgeUpdateTime+=d;
}

private double ms(Duration d){
	return d.total!"hnsecs"/10_000.0;
}

void endStep(int frame){
	if(!enabled) return;
	stepSw.stop();
	auto total=stepSw.peek();
	if(total.total!"hnsecs"<stepThreshold) return;
	if(numPhases<maxPhases){
		phaseNames[numPhases]="end";
		phaseTimes[numPhases]=total-lastMark;
		numPhases++;
	}
	int[maxPhases] order;
	foreach(i;0..numPhases) order[i]=i;
	sort!((a,b)=>phaseTimes[a]>phaseTimes[b])(order[0..numPhases]);
	stderr.writef!"frame %d: sim step %.1fms:"(frame,ms(total));
	foreach(i;order[0..numPhases])
		stderr.writef!" %s=%.1f"(phaseNames[i],ms(phaseTimes[i]));
	if(numBotSlots){
		static immutable string[6] slotNames=["status","stance","ntts","groups","replan","tasks"];
		int[maxBotSlots] botOrder;
		foreach(i;0..numBotSlots) botOrder[i]=i;
		sort!((a,b)=>botSlotTimes[a]>botSlotTimes[b])(botOrder[0..numBotSlots]);
		stderr.writef!" [bots:";
		foreach(i;botOrder[0..numBotSlots]){
			auto k=botSlotK[i];
			stderr.writef!" s%d.%s=%.1f"(botSlotSide[i],0<=k&&k<6?slotNames[k]:"setup",ms(botSlotTimes[i]));
		}
		stderr.writef!" ]";
	}
	if(numReplanPhases){
		int[maxReplanPhases] replanOrder;
		foreach(i;0..numReplanPhases) replanOrder[i]=i;
		sort!((a,b)=>replanTimes[a]>replanTimes[b])(replanOrder[0..numReplanPhases]);
		stderr.writef!" [replan:";
		foreach(i;replanOrder[0..numReplanPhases])
			if(replanTimes[i]>Duration.zero)
				stderr.writef!" %s=%.1f"(replanNames[i],ms(replanTimes[i]));
		stderr.writef!" ]";
	}
	if(findPathCalls)
		stderr.writef!" (findPath: %dx %.1fms, max %.1fms)"(findPathCalls,ms(findPathTime),ms(findPathMax));
	if(edgeUpdateCalls)
		stderr.writef!" (edgeUpdate: %dx %.1fms)"(edgeUpdateCalls,ms(edgeUpdateTime));
	stderr.writeln();
}

void reportCatchUp(int frame,int numSteps,Duration elapsed){
	if(!enabled) return;
	if(numSteps>=2&&elapsed.total!"hnsecs">=stepThreshold)
		stderr.writefln!"frame %d: catch-up: ran %d sim steps in %.1fms"(frame,numSteps,ms(elapsed));
}

void reportRenderedFrame(Duration frameTime,Duration logicTime){
	if(!enabled) return;
	if(frameTime.total!"hnsecs"<frameThreshold&&logicTime.total!"hnsecs"<frameThreshold) return;
	stderr.writef!"slow frame: %.1fms total, %.1fms logic+sim"(ms(frameTime),ms(logicTime));
	if(numRenderPhases){
		int[maxRenderPhases] renderOrder;
		foreach(i;0..numRenderPhases) renderOrder[i]=i;
		sort!((a,b)=>renderPhaseTimes[a]>renderPhaseTimes[b])(renderOrder[0..numRenderPhases]);
		stderr.writef!" [render:";
		foreach(i;renderOrder[0..numRenderPhases])
			stderr.writef!" %s=%.1f"(renderPhaseNames[i],ms(renderPhaseTimes[i]));
		stderr.writef!" ]";
	}
	stderr.writeln();
}
