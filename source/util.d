// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import dlib.math, dlib.math.portable;
import std.typecons, std.algorithm;
import std.exception:enforce;

alias Seq(T...)=T;

enum head=import("HEAD")["ref: ".length..$].strip;
enum commit=import(head).strip;

version(LittleEndian){}else static assert(0,"some reinterpret-casts still assume little-endianness");

uint parseLE(const ubyte[] raw)in{
	assert(raw.length<=4);
}do{
	uint r=0;
	foreach_reverse(x;raw) r=256*r+x;
	return r;
}
uint parseUint(ref ubyte[] data){
	enforce(data.length>=4);
	uint r=0;
	foreach_reverse(x;data[0..4]) r=256*r+x;
	data=data[4..$];
	return r;
}
short parseShort(ref ubyte[] data){
	enforce(data.length>=2);
	auto r=cast(short)(256*data[0]+data[1]);
	data=data[2..$];
	return r;
}
inout(ubyte)[] eat(ref inout(ubyte)[] input, size_t n){
	auto r=input[0..n];
	input=input[n..$];
	return r;
}

Vector3f fromSac(Vector3f v){
	return v;
}
float[3] fromSac(float[3] v){
	return v;
}

Vector3f fromSXMD(Vector3f v){
	return Vector3f(-v.x,-v.z,v.y);
}
float[3] fromSXMD(float[3] v){
	return [-v[0],-v[2],v[1]];
}

import std.encoding;
enum placeholderLetter=cast(Windows1252Char)0x81;
bool canRenderDchar(dchar c){
	return canEncode!Windows1252Char(c)&&encodedLength!Windows1252Char(c)==1;
}
// US version uses code page 1252
// TODO: polish probably uses 1250 and russian 1251?
Windows1252Char convertDchar(dchar c){
	if(!canRenderDchar(c)) return placeholderLetter;
	Windows1252Char[1] result;
	encode(c,result[]);
	return result[0];
}

import wadmanager;
WadManager wadManager;
bool fileExists(string filename){
	if(wadManager&&filename in wadManager.files)
		return true;
	import std.file:exists;
	return exists(filename);
}
ubyte[] readFile(string filename){
	filename=fixPath(filename);
	if(wadManager&&filename in wadManager.files)
		return wadManager.files[filename];
	ubyte[] data;
	import std.stdio;
	foreach(ubyte[] chunk;chunks(File(filename,"rb"),4096)) data~=chunk;
	return data;
}

Quaternionf facingQuaternion(float facing){
	return rotationQuaternion(Axis.z,facing);
}
Quaternionf pitchQuaternion(float pitch){
	return rotationQuaternion(Axis.x,pitch);
}

Vector3f rotate(Quaternionf rotation, Vector3f v){
	return rotation.rotate(v);
}

Vector3f transform(Matrix4f m, Vector3f v){
	auto w=Vector4f(v.x,v.y,v.z,1.0f)*m;
	return w.xyz/w.w;
}

Quaternionf limitRotation(Quaternionf q, float maxAbsAngle){
	import std.algorithm;
	auto len=q.xyz.length;
	auto angle=2*atan2(len,q.w);
	if(angle>pi!float) angle-=2*pi!float;
	else if(angle<-pi!float) angle+=2*pi!float;
	if(angle<-maxAbsAngle) angle=-maxAbsAngle;
	if(angle>maxAbsAngle) angle=maxAbsAngle;
	if(angle==0.0f||len==0.0f) return Quaternionf.identity();
	return rotationQuaternion(q.xyz/len,angle); // dlib's rotationAxis is wrong
}

Vector3f limitLengthInPlane(Vector3f v,float len){
	auto plen=v.xy.length;
	if(plen<=len) return v;
	Vector2f k=v.xy*(len/plen);
	return Vector3f(k.x,k.y,v.z);
}

struct Transformation{
	Quaternionf rotation;
	Vector3f offset;
	this(Quaternionf rotation,Vector3f offset){
		this.rotation=rotation;
		this.offset=offset;
	}
	Vector3f rotate(Vector3f v){
		return .rotate(rotation,v);
	}
	Vector3f opCall(Vector3f v){
		auto rotated=rotate(v);
		return rotated+offset;
	}
	Transformation opBinary(string op:"*")(Transformation rhs){
		return Transformation(rotation*rhs.rotation,opCall(rhs.offset));
	}
	Matrix4f getMatrix4f(){
		auto id=Matrix3f.identity();
		Matrix4f result;
		result.arrayof[0..3]=rotate(Vector3f(id.arrayof[0..3])).arrayof[];
		result.arrayof[3]=0.0f;
		result.arrayof[4..7]=rotate(Vector3f(id.arrayof[3..6])).arrayof[];
		result.arrayof[7]=0.0f;
		result.arrayof[8..11]=rotate(Vector3f(id.arrayof[6..9])).arrayof[];
		result.arrayof[11]=0.0f;
		result.arrayof[12..15]=offset.arrayof[];
		result.arrayof[15]=1.0f;
		return result;
	}
}

Vector3f[2] bbox(R)(R positions){
	auto small=Vector3f(float.max,float.max,float.max);
	auto large=-small;
	foreach(p;positions){
		static assert(is(typeof(p)==Vector3f));
		static foreach(k;0..3){
			small[k]=min(small[k],p[k]);
			large[k]=max(large[k],p[k]);
		}
	}
	return [small,large];
}

bool intervalsIntersect(float[2] a, float[2] b){
	return a[0]<b[1] && b[0]<a[1];
}

bool boxesIntersect(Vector3f[2] a,Vector3f[2] b){
	return intervalsIntersect([a[0].x,a[1].x], [b[0].x,b[1].x])
		&& intervalsIntersect([a[0].y,a[1].y], [b[0].y,b[1].y])
		&& intervalsIntersect([a[0].z,a[1].z], [b[0].z,b[1].z]);
}

Vector!(T,n)[2] moveBox(T,size_t n)(Vector!(T,n)[2] box, Vector!(T,n) offset){
	box[0]+=offset;
	box[1]+=offset;
	return box;
}

Vector!(T,n) boxCenter(T,size_t n)(Vector!(T,n)[2] box){
	return 0.5f*(box[0]+box[1]);
}
Vector!(T,n) boxSize(T,size_t n)(Vector!(T,n)[2] box){
	return box[1]-box[0];
}
Vector!(T,n)[2] scaleBox(T,size_t n)(Vector!(T,n)[2] box, float factor){
	auto size=box[1]-box[0];
	auto center=0.5f*(box[0]+box[1]);
	size*=factor;
	return [center-0.5f*size,center+0.5f*size];
}

Tuple!(Vector!(float,n),float) closestBoxFaceNormalWithProjectionLength(size_t n)(Vector!(float,n)[2] box, Vector!(float,n) position){
	auto bestDist=-float.infinity;
	size_t normalDirection,normalIndex;
	static foreach(j;0..2){
		foreach(i;0..n){
			static if(j==0) auto candDist=box[0][i]-position[i];
			else auto candDist=position[i]-box[1][i];
			if(candDist>bestDist){
				bestDist=candDist;
				normalDirection=j;
				normalIndex=i;
			}
		}
	}
	Vector!(float,n) result;
	result.arrayof[]=0.0f;
	result[normalIndex]=normalDirection?1.0f:-1.0f;
	return tuple(result,cast(float)bestDist);
}
Vector!(float,n) closestBoxFaceNormal(size_t n)(Vector!(float,n)[2] box, Vector!(float,n) position){
	return closestBoxFaceNormalWithProjectionLength(box,position)[0];
}

Vector!(float,n) projectToBox(size_t n)(Vector!(float,n)[2] box,Vector!(float,n) point){
	auto projection=point;
	foreach(i;0..n){
		projection[i]=max(projection[i],box[0][i]);
		projection[i]=min(projection[i],box[1][i]);
	}
	return projection;
}

Vector!(float,n) projectToBoxTowardsCenter(size_t n)(Vector!(float,n)[2] box,Vector!(float,n) point){
	auto center=boxCenter(box);
	auto distance=point-center;
	auto t=1.0f;
	foreach(i;0..n){
		foreach(j;0..2){
			auto cand=(box[j][i]-center[i])/distance[i];
			if(cand>=0.0f) t=min(t,cand);
		}
	}
	return center+t*distance;
}

float boxPointDistanceSqr(size_t n)(Vector!(float,n)[2] box,Vector!(float,n) point){
	return (point-projectToBox(box,point)).lengthsqr;
}
float boxPointDistance(size_t n)(Vector!(float,n)[2] box,Vector!(float,n) point){
	return sqrt(boxPointDistanceSqr(box,point));
}
float boxBoxDistanceSqr(size_t n)(Vector!(float,n)[2] boxa,Vector!(float,n)[2] boxb){
	auto p=projectToBox(boxa,boxb[0]);
	auto q=projectToBox(boxb,p);
	return (p-q).lengthsqr;
}
float boxBoxDistance(size_t n)(Vector!(float,n)[2] boxa,Vector!(float,n)[2] boxb){
	return sqrt(boxBoxDistanceSqr(boxa,boxb));
}

bool isInside(Vector3f point,Vector3f[2] box){
	return box[0].x<=point.x&&point.x<=box[1].x&&
		box[0].y<=point.y&&point.y<=box[1].y&&
		box[0].z<=point.z&&point.z<=box[1].z;
}

float rayBoxIntersect(Vector3f start,Vector3f direction,Vector3f[2] box,float limit=float.infinity){
	if(isInside(start,box)) return 0.0f;
	float result=float.infinity;
	foreach(d;0..3){
		foreach(p;0..2){
			auto t=(box[p][d]-start[d])/direction[d];
			if(0<=t&&t<result&&t<limit){
				auto intersectionPoint=start+t*direction;
				bool ok=true;
				foreach(e;0..3){
					if(e==d) continue;
					if(intersectionPoint[e]<box[0][e]
					   ||intersectionPoint[e]>box[1][e]){
						ok=false;
						break;
					}
				}
				if(ok) result=t;
			}
		}
	}
	return result;
}

static import std.container.array;
struct Array(T){
	std.container.array.Array!T payload;
	alias payload this;
	static if(!is(T==bool)){
		T[] data(){
			// std.container.array should just provide this functionality...
			auto implPtr=payload.tupleof[0]._refCounted.tupleof[0];
			if(!implPtr) return [];
			return implPtr._payload._payload;
		}
	}
	void opAssign(ref Array!T rhs){
		this.length=rhs.length;
		foreach(i;0..length)
			this[i]=rhs[i];
	}
	void opAssign(Array!T rhs){
		payload=move(rhs.payload);
	}
	this(this){ payload=payload.dup; }

	static if(!is(T==bool)) string toString()(){ import std.conv; return text(data); }
}

mixin template Assign(){
	void opAssign(ref typeof(this) rhs){
		foreach(i,ref x;this.tupleof)
			x=rhs.tupleof[i];
	}
	void opAssign(typeof(this) rhs){
		foreach(i,ref x;this.tupleof)
			x=move(rhs.tupleof[i]);
	}
}

import dlib.image;
auto imageFromData(const(ubyte)[] data,int width,int height,int channels)in{
	assert(data.length==width*height*channels);
}do{
	auto img=image(width,height,channels);
	img.data[]=data[];
	return img;
}

auto makeOnePixelImage(Color4f color){
	import dagon;
	auto img = New!UnmanagedImageRGBA8(8, 8);
	img.fillColor(color);
	return img;
}

// useful for getting naming conventions right in string mixins:
string lowerf(string s){
	if('A'<=s[0]&&s[0]<='Z') return cast(char)(s[0]+('a'-'A'))~s[1..$];
	return s;
}

string upperf(string s){
	if('a'<=s[0]&&s[0]<='z') return cast(char)(s[0]+('A'-'a'))~s[1..$];
	return s;
}

string flagText(E)(E arg)if(is(E==enum)){
	string r;
	import std.traits: EnumMembers;
	import std.conv: text;
	foreach(e;EnumMembers!E)
		if(arg&e) r~=text(r.length?"|":"",e);
	return r;
}

struct Queue(T){
	Array!T payload;
	size_t first=0,last=0;
	void push(T val){
		// TODO: this has a bad amortized worst case
		if(payload.length==last-first){
			if(payload.length>1){
				import std.algorithm: bringToFront;
				bringToFront(payload[0..first%$],payload[first%$..$]);
			}
			last=last-first;
			first=0;
			payload~=val;
			last+=1;
		}else payload[last++%$]=val;
	}
	void pushFront(T val){
		// TODO: faster implementation?
		push(val);
		foreach_reverse(i;first..last){
			if(i+1==last) continue;
			swap(payload[i%$],payload[(i+1)%$]);
		}
	}
	ref T front(){ return payload[first%$]; }
	void popFront(){ ++first; }
	T removeFront(){ return payload[first++%$]; }
	ref T back(){ return payload[(last+$-1)%$]; }
	void popBack(){ --last; }
	T removeBack(){ return payload[--last%$]; }
	bool empty(){ return first==last; }
	this(this){ compactify(); }
	void opAssign(ref Queue!T rhs){
		if(&this is &rhs) return;
		first=0;
		payload.length=last=rhs.last-rhs.first;
		foreach(i;rhs.first..rhs.last){
			payload[i-rhs.first]=rhs.payload[i%$];
		}
	}
	void opAssign(Queue!T rhs){ this.tupleof=move(rhs).tupleof; }
	void clear(){ payload.length=first=last=0; }
	void compactify(){
		if(!payload.length) return;
		bringToFront(payload.data[0..first%$],payload.data[first%$..$]);
		last-=first;
		first=0;
		payload.length=last;
	}
}

struct Heap(T,size_t N=4){
	private Array!T payload;
	void clear(){ payload.length=0; }
	bool empty(){ return payload.length==0; }
	void push(T value){
		payload~=move(value);
		for(size_t i=payload.length-1;i;i=(i-1)/N){
			if(payload[i].less(payload[(i-1)/N]))
				swap(payload[i],payload[(i-1)/N]);
			else break;
		}
	}
	T pop(){
		swap(payload[0],payload[$-1]);
		auto result=move(payload[$-1]);
		payload.removeBack(1);
		for(size_t i=0;N*i+1<payload.length;){
			auto j=N*i+1;
			foreach(k;N*i+2..min(N*i+N+1,payload.length))
				if(payload[k].less(payload[j]))
					j=k;
			if(payload[j].less(payload[i])){
				swap(payload[i],payload[j]);
				i=j;
			}else break;
		}
		return result;
	}
}

struct Stack(T){
	private T[] data;
	bool empty(){
		return data.length==0;
	}
	ref T top(){
		return data[$-1];
	}
	void push(T t){
		data~=t;
	}
	void pop(){
		data=data[0..$-1];
		data.assumeSafeAppend();
	}
}

import std.string,std.path,std.algorithm,std.range;
string fixPath(string path){ static if(dirSeparator=="/") return path; else return path.replace("/",dirSeparator); }
string[] fixPaths(string[] paths){ static if(dirSeparator=="/") return paths; else return paths.map!fixPath.array; }

string[2][] symbolReplacements=[
	["/","_SLASH_"],
	["\\","_BSLASH_"],
	["`","_TICK_"],
	["\0","_ZERO_"],
	["^","_HAT_"],
	["/","_SLASH_"],
	["?","_QUESTIONMARK_"],
];

string normalizeFilename(string name){
	foreach(x;symbolReplacements) name=name.replace(x[0],x[1]);
	return name;
}
string unnormalizeFilename(string name){
	foreach(x;symbolReplacements) name=name.replace(x[1],x[0]);
	return name;
}

struct SmallArray(T,size_t n){
	size_t length;
	T[n] elements;
	Array!T rest;
	void opOpAssign(string op:"~")(T elem){
		if(length<n){
			elements[length++]=elem;
		}else{
			length+=1;
			rest~=elem;
		}
	}
	ref T opIndex(size_t i){
		if(i<n) return elements[i];
		return rest[i-n];
	}
	auto opSlice()return{
		return chain(elements[0..min($,length)],rest.data[]);
	}
}

Vector3f[2] cintp2(Vector3f[2][2] locations,float t){
	auto p0=locations[0][0], m0=locations[0][1];
	auto p1=locations[1][0], m1=locations[1][1];
	auto p=(2*t^^3-3*t^^2+1)*p0+(t^^3-2*t^^2+t)*m0+(-2*t^^3+3*t^^2)*p1+(t^^3-t^^2)*m1;
	auto m=(6*t^^2-6*t)*p0+(3*t^^2-4*t+1)*m0+(-6*t^^2+6*t)*p1+(3*t^^2-2*t)*m1;
	return [p,m];
}

Vector3f[2] cintp(R)(R locations,float t){
	auto n=locations.length;
	auto i=max(0,min(cast(int)floor(t*(n-1)),n-2));
	auto u=max(0.0f,min(t*(n-1)-i,1.0f));
	auto p0=locations[i], p1=locations[i+1];
	auto m0=locations[min(i+1,cast(int)$-1)]-locations[max(0,cast(int)i-1)];
	auto m1=locations[min(i+2,cast(int)$-1)]-locations[i];
	//auto p=(1.0f-u)*locations[i]+u*locations[i+1], m=locations[i+1]-locations[i]; // linear interpolation
	auto p=(2*u^^3-3*u^^2+1)*p0+(u^^3-2*u^^2+u)*m0+(-2*u^^3+3*u^^2)*p1+(u^^3-u^^2)*m1;
	auto m=(6*u^^2-6*u)*p0+(3*u^^2-4*u+1)*m0+(-6*u^^2+6*u)*p1+(3*u^^2-2*u)*m1;
	return [p,m];
}

Vector3f[2] lintp(Vector3f[] locations,float t){
	auto n=locations.length;
	auto i=max(0,min(cast(int)floor(t*(n-1)),n-2));
	auto u=max(0.0f,min(t*(n-1)-i,1.0f));
	auto p0=locations[i], p1=locations[i+1];
	auto p=(1.0f-u)*p0+u*p1;
	auto m=p1-p0;
	return [p,m];
}
