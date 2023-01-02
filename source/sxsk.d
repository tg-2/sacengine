// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import util;
import dlib.math;
import std.stdio, std.exception, std.algorithm, std.array;
import skel;

enum maxNumBones=32;
enum gpuSkinning=true;

struct Pose{
	Vector3f displacement;
	AnimEvent event;
	Quaternionf[] rotations;
	Matrix4f[] matrices;
}
private struct FrameHeader{
	short unknown;
	short[2] disp;
	uint offset;
}
static assert(FrameHeader.sizeof==12);

enum AnimEvent{
	none,
	sound,
	attack,
	load,
	shoot,
	cast_,
	death,
	grab,
	foot,
}

struct Hand{
	int bone;
	Vector3f position;
}
struct Animation{
	int numAttackTicks=0;
	int firstAttackTick=int.max;
	int numShootTicks=0;
	int firstShootTick=int.max;
	int castingTime=int.max;
	Hand[2] hands;
	Pose[] frames;
}

Animation parseSXSK(ubyte[] data,float scaling){
	auto numFrames=*cast(ushort*)data[2..4].ptr;
	double offsetY=*cast(float*)data[4..8].ptr;
	auto numBones=*data[8..12].ptr;
	enforce(numBones<=maxNumBones);
	auto frameHeaders=cast(FrameHeader[])data[12..12+numFrames*FrameHeader.sizeof];
	Pose[] frames;
	foreach(i,ref frameHeader;frameHeaders){
		enforce(frameHeader.offset<=frameHeader.offset+numBones*(short[4]).sizeof && frameHeader.offset+numBones*(short[4]).sizeof<=data.length);
		auto anim=cast(short[4][])data[frameHeader.offset..frameHeader.offset+numBones*(short[4]).sizeof];
		auto displacement=fromSXMD(Vector3f(frameHeader.disp[0],frameHeader.disp[1],0))*scaling;
		auto rotations=anim.map!(x=>Quaternionf(Vector3f(fromSXMD([x[0],x[1],x[2]])),x[3]).normalized()).array;
		frames~=Pose(displacement,AnimEvent.none,rotations);
	}
	return Animation(0,int.max,0,int.max,int.max,(Hand[2]).init,frames);
}

AnimEvent translateAnimEvent(char[4] tag){
	switch(tag){
		case "\0\0\0\0": return AnimEvent.none;
		case "!xfs": return AnimEvent.sound;
		case "kcta": return AnimEvent.attack;
		case "liba": return AnimEvent.load;
		case "lrba": return AnimEvent.shoot;
		case "tsac": return AnimEvent.cast_;
		case "hted": return AnimEvent.death;
		case "barg": return AnimEvent.grab;
		case "toof": return AnimEvent.foot;
		default:
			enforce(0,"unknown skel event '"~tag~"'");
			assert(0);
	}
}

void setAnimEvents(ref Animation anim, Skel skel, string filename){
	foreach(ref event;skel.events[0..skel.numEvents]){
		auto frame=min(event.frame,cast(int)anim.frames.length-1);
		auto aevent=translateAnimEvent(event.tag); // TODO: what about SkelEvent.parameter?
		// TODO: some wizards have two attack events in the same frame. was this supposed to duplicate the damage tick?
		enforce(anim.frames[frame].event.among(AnimEvent.none,aevent));
		anim.frames[frame].event=aevent;
		if(aevent==AnimEvent.attack){
			++anim.numAttackTicks;
			anim.firstAttackTick=min(anim.firstAttackTick,frame);
		}
		if(aevent==AnimEvent.shoot){
			++anim.numShootTicks;
			anim.firstShootTick=min(anim.firstShootTick,frame);
		}
		if(aevent==AnimEvent.cast_)
			anim.castingTime=min(anim.castingTime,frame);
	}
}

Animation loadSXSK(string filename,float scaling){
	enforce(filename.endsWith(".SXSK"), filename);
	auto anim=parseSXSK(readFile(filename),scaling);
	auto skel=loadSkel(filename[0..$-5]~".SKEL");
	anim.setAnimEvents(skel,filename);
	foreach(i;0..2){
		anim.hands[i]=Hand(skel.hands[i].bone,Vector3f(skel.hands[i].offset));
		if(anim.hands[i].position.y==275.0f) anim.hands[i].position.y*=1e-3; // fix yogo walking casting animation
	}
	return anim;
}

import saxs;
bool compile(B)(ref Animation anim, ref Saxs!B saxs){
	enforce(saxs.bones.length<=maxNumBones);
	bool ok=true;
	foreach(ref frame;anim.frames){
		//enforce(frame.rotations.length==saxs.bones.length);
		ok&=frame.rotations.length==saxs.bones.length;
		Transformation[maxNumBones] transform;
		transform[0]=Transformation(Quaternionf.identity,Vector3f(0,0,0));
		foreach(j,ref bone;saxs.bones)
			transform[j]=transform[bone.parent]*Transformation(frame.rotations[j],bone.position);
		auto displacement=frame.displacement;
		displacement.z*=saxs.zfactor;
		foreach(j;0..saxs.bones.length)
			transform[j].offset+=displacement;
		auto matrices=new Matrix4f[](saxs.bones.length);
		foreach(j;0..saxs.bones.length)
			matrices[j]=transform[j].getMatrix4f();
		frame.matrices=matrices;
	}
	return ok;
}
