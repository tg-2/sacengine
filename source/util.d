import dagon;

uint parseLE(ubyte[] raw)in{
	assert(raw.length<=4);
}body{
	uint r=0;
	foreach_reverse(x;raw) r=256*r+x;
	return r;
}

Vector3f fromSac(Vector3f v){
	return Vector3f(v.y,v.x,-v.z);
}
float[3] fromSac(float[3] v){
	return [v[1],v[0],-v[2]];
}

Vector3f fromSXMD(Vector3f v){
	return Vector3f(-v.x,v.z,-v.y);
}
float[3] fromSXMD(float[3] v){
	return [-v[0],v[2],-v[1]];
}

ubyte[] readFile(string filename){
	ubyte[] data;
	import std.stdio;
	foreach(ubyte[] chunk;chunks(File(filename,"rb"),4096)) data~=chunk;
	return data;
}
