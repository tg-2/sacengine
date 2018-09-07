import dagon;

uint parseLE(ubyte[] raw)in{
	assert(raw.length<=4);
}body{
	uint r=0;
	foreach_reverse(x;raw) r=256*r+x;
	return r;
}

Vector3f fromSac(Vector3f v){
	return Vector3f(-v.x,v.z,v.y);
}

float[3] fromSac(float[3] v){
	return [-v[0],v[2],v[1]];
}
