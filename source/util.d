import dlib.math;
import std.typecons, std.algorithm;

alias Seq(T...)=T;

uint parseLE(const ubyte[] raw)in{
	assert(raw.length<=4);
}body{
	uint r=0;
	foreach_reverse(x;raw) r=256*r+x;
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

import wadmanager;
WadManager wadManager;
bool fileExists(string filename){
	if(wadManager&&filename in wadManager.files)
		return true;
	import std.file:exists;
	return exists(filename);
}
ubyte[] readFile(string filename){
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
	import std.math, std.algorithm;
	auto len=q.xyz.length;
	auto angle=2*atan2(len,q.w);
	if(angle>PI) angle-=2*PI;
	else if(angle<-PI) angle+=2*PI;
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

Vector3f[2] moveBox(Vector3f[2] box, Vector3f offset){
	box[0]+=offset;
	box[1]+=offset;
	return box;
}

Vector3f boxCenter(Vector3f[2] box){
	return 0.5f*(box[0]+box[1]);
}
Vector3f boxSize(Vector3f[2] box){
	return box[1]-box[0];
}
Vector3f[2] scaleBox(Vector3f[2] box, float factor){
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


import std.container.array;
T[] data(T)(ref Array!T array){
	// std.container.array should just provide this functionality...
	auto implPtr=array.tupleof[0]._refCounted.tupleof[0];
	if(!implPtr) return [];
	return implPtr._payload.tupleof[1];
}


void assignArray(T)(ref Array!T to, ref Array!T from){
	to.length=from.length;
	foreach(i;0..from.length){ // TODO: this is slow!
		static if(is(T:Array!S,S)) // TODO: wrap array with different opAssign?
			assignArray(to[i],from[i]);
		else to[i]=from[i];
	}
}
/+ // TODO: use this for structs that are not arrays and have no opAssign
void assignArray(T)(ref Array!T to, ref Array!T from){
	to.length=from.length;
	to.data[]=from.data[];
}
+/

void fail(){ assert(0); }

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
	T front(){ return payload[first%$]; }
	void popFront(){ ++first; }
	T removeFront(){ return payload[first++%$]; }
	T back(){ return payload[(last+$-1)%$]; }
	void popBack(){ --last; }
	T removeBack(){ return payload[--last%$]; }
	bool empty(){ return first==last; }
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

template tryImport(string filename,string alt=""){
	static if(__traits(compiles,import(filename))) enum tryImport = import(filename)[0..$-1];
	else enum tryImport = alt;
}
