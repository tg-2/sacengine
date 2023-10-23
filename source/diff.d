// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import dlib.math;
import std.algorithm, std.range, std.traits, std.exception, std.conv, std.stdio;;
import nttData,bldg,sacobject,sacspell,stats,state,util;

bool diffData(string[] noserialize=[],T)(ref T a,ref T b,lazy string path)if(is(T==struct)&&!is(T==Vector!(S,n),S,size_t n)&&!is(T==Array!S,S)&&!is(T==Queue!S,S)){
	bool r=false;
	static foreach(member;__traits(allMembers,T)){
		static if(is(typeof(__traits(getMember,a,member).offsetof))){
			static if(!noserialize.canFind(member)){
				r|=diffData(__traits(getMember,a,member),__traits(getMember,b,member),text(path,".",member));
			}
		}
	}
	static if(is(T==Particles!(B,relative),B,bool relative)){
		if(r){
			writeln(a.sacParticle.type," ",a.sacParticle.side);
		}
	}
	return r;
}
bool diffData(string[] noserialize=[],T)(T a,T b,lazy string path)if(is(T==class)&&!is(T==SacObject!B,B)&&!is(T==SacBuilding!B,B)&&!is(T==SacSpell!B,B)&&!is(T==SacParticle!B,B)){
	bool r=false;
	static foreach(member;__traits(allMembers,T)){
		static if(is(typeof(__traits(getMember,a,member).offsetof))){
			static if(!noserialize.canFind(member)){
				r|=diffData(__traits(getMember,a,member),__traits(getMember,b,member),text(path,".",member));
			}
		}
	}
	return r;
}
bool diffData(T)(T a,T b,lazy string path)if(is(T==SacObject!B,B)||is(T==SacBuilding!B,B)||is(T==SacSpell!B,B)){
	static if(is(T==SacObject!B,B)) return diffData(a.nttTag,b.nttTag,path);
	else if(a&&b) return diffData(a.tag,b.tag,path);
	else if(!!a!=!!b){
		writeln(path, "differs: ",!!a?"is not null":"is null",", but ",!!b?"is not null":"is null");
		return true;
	}else return false;
}
bool diffData(B)(SacParticle!B a,SacParticle!B b,lazy string path){
	bool r=false;
	r|=diffData(a.type,b.type,text(path,".type"));
	r|=diffData(a.side,b.side,text(path,".side"));
	return r;
}

bool diffData(T)(T a,T b,lazy string path)if(is(T==short)||is(T==ushort)||is(T==int)||is(T==uint)||is(T==size_t)||is(T==float)||is(T==bool)||is(T==ubyte)||is(T==char)||is(T==enum)||is(T==char[n],size_t n)||is(T==string)){
	bool r=false;
	static if(is(T==S[n],S,size_t n)){ // abool deprecation warning
		if(a!=b){
			writeln(path," differs: ",a," vs ",b);
			r=true;
		}
	}else static if(is(T==float)){
		if(a!is b){
			writeln(path," differs: ",a," vs ",b,", difference ",a-b);
			r=true;
		}
	}else{
		if(a!=b && a!is b){
			writeln(path," differs: ",a," vs ",b);
			r=true;
		}
	}
	return r;
}
bool diffData(T,size_t n)(ref T[n] a, ref T[n] b,lazy string path)if(!is(T==char)){
	bool r=false;
	foreach(i;0..n) r|=diffData(a[i],b[i],text(path,"[",i,"]"));
	return r;
}
bool diffData(T)(Array!T a,Array!T b,lazy string path){
	bool r=false;
	r|=diffData(a.length,b.length,text(path,".length"));
	if(a.length==b.length) foreach(i;0..a.length) r|=diffData(a[i],b[i],text(path,"[",i,"]"));
	else static if(is(T==Particles!(B,relative),B,bool relative)){
		writeln("a",path,":");
		foreach(ref x;a) writeln(x.sacParticle.type," ",x.sacParticle.side);
		writeln("b",path,":");
		foreach(ref y;b) writeln(y.sacParticle.type," ",y.sacParticle.side);
	}
	return r;
}
bool diffData(T)(T[] a,T[] b,lazy string path)if(!is(Unqual!T==char)){
	bool r=false;
	r|=diffData(a.length,b.length,text(path,".length"));
	if(a.length==b.length) foreach(i;0..a.length) r|=diffData(a[i],b[i],text(path,"[",i,"]"));
	return r;
}
bool diffData(T,size_t n)(ref Vector!(T,n) a,ref Vector!(T,n) b,lazy string path){
	bool r=false;
	static foreach(i;0..n) r|=diffData(a[i],b[i],text(path,"[",i,"]"));
	return r;
}
bool diffData(T)(ref Queue!T a,ref Queue!T b,lazy string path){
	bool r=false;
	a.compactify();
	b.compactify();
	r|=diffData(a.payload.length,b.payload.length,text(path,".length"));
	if(a.payload.length==b.payload.length) foreach(i;0..a.payload.length) r|=diffData(a.payload[i],b.payload[i],text(path,"[",i,"]"));
	return r;
}

bool diffStates(B)(ObjectState!B a,ObjectState!B b){
	return diffData!(["map","sides","proximity","pathFinder","triggers","toRemove"])(a,b,"c");
}
