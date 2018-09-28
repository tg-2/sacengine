import dagon;
import hmap;
import std.exception, std.string, std.algorithm, std.conv, std.range;
import std.stdio;

class SacMap{
	Mesh mesh;
	//Texture texture;

	this(string filename){
		enforce(filename.endsWith(".HMAP"));
		auto hmap=loadHMap(filename);
		mesh=createMesh(hmap);
	}

	void createEntities(Scene s){
		if(!mesh) return;
		auto obj=s.createEntity3D();
		obj.drawable = mesh;
		obj.position = Vector3f(0, 0, 0);
	}
}

Mesh createMesh(HMap hmap, float scaleFactor=0.1){
	auto edges=hmap.edges;
	auto heights=hmap.heights.dup;
	//auto minHeight=1e9;
	//foreach(h;heights) foreach(x;h) minHeight=min(minHeight,x);
	//foreach(h;heights) foreach(ref x;h) x-=minHeight;
	//foreach(e;edges) e[]=false;
	auto mesh=new Mesh(null);
	auto n=to!int(hmap.edges.length);
	enforce(m);
	auto m=to!int(hmap.edges[0].length);
	enforce(heights.length==n);
	enforce(edges.all!(x=>x.length==m));
	enforce(heights.all!(x=>x.length==m));
	auto numVertices=4*(m-1)*(n-1);
	mesh.vertices=New!(Vector3f[])(numVertices);
	mesh.texcoords=New!(Vector2f[])(numVertices);
	foreach(j;0..n-1){
		foreach(i;0..m-1){
			foreach(k;0..4){
				int di=(k==1)+(k==2),dj=(k==2)+(k==3);
				int x=i+di,z=j+dj;
				mesh.vertices[4*((n-1)*i+j)+k]=scaleFactor*Vector3f(10*x,heights[z][x]/100,10*z);
				mesh.texcoords[4*((n-1)*i+j)+k]=Vector2f(di,dj);
			}
		}
	}
	mesh.indices=New!(uint[3][])(2*(m-1)*(n-1));
	foreach(int j;0..n-1){
		foreach(int i;0..m-1){
			if(!edges[j][i]&&!edges[j+1][i+1]&&!edges[j][i+1])
				mesh.indices[2*((n-1)*i+j)]=[4*((n-1)*i+j)+0,4*((n-1)*i+j)+2,4*((m-1)*i+j)+1];
			if(!edges[j+1][i+1]&&!edges[j][i]&&!edges[j+1][i])
				mesh.indices[2*((n-1)*i+j)+1]=[4*((n-1)*i+j)+2,4*((n-1)*i+j)+0,4*((m-1)*i+j)+3];
			if(edges[j][i]&&!edges[j][i+1]&&!edges[j+1][i+1]&&!edges[j+1][i])
				mesh.indices[2*((n-1)*i+j)]=[4*((n-1)*i+j)+1,4*((n-1)*i+j)+3,4*((m-1)*i+j)+2];
			if(edges[j+1][i+1]&&!edges[j][i]&&!edges[j][i+1]&&!edges[j+1][i])
				mesh.indices[2*((n-1)*i+j)+1]=[4*((n-1)*i+j)+0,4*((n-1)*i+j)+3,4*((m-1)*i+j)+1];
		}
	}
	mesh.normals=New!(Vector3f[])(numVertices);
	mesh.normals[] = Vector3f(0.0f, 0.0f, 0.0f);
	foreach(ref f;mesh.indices){
		auto v0=mesh.vertices[f[0]], v1=mesh.vertices[f[1]], v2=mesh.vertices[f[2]];
		Vector3f p=cross(v1-v0,v2-v0);
		auto clones(int x){
			int offset=x&3;
			int location=x/4;
			int i=location/(n-1);
			int j=location%(n-1);
			assert(0<=i&&i<m-1);
			assert(0<=j&&j<n-1);
			typeof(only(n,n,n)) r;
			final switch(offset){
				case 0:
					r=only(4*((n-1)*(i-1)+j)+1,4*((n-1)*i+(j-1))+3,4*((n-1)*(i-1)+(j-1))+2);
					break;
				case 1:
					r=only(4*((n-1)*i+(j-1))+2,4*((n-1)*(i+1)+(j-1))+3,4*((n-1)*(i+1)+j));
					break;
				case 2:
					r=only(4*((n-1)*(i+1)+j)+3,4*((n-1)*i+(j+1))+1,4*((n-1)*(i+1)+(j+1)));
					break;
				case 3:
					r=only(4*((n-1)*(i-1)+j)+2,4*((n-1)*(i-1)+(j+1))+1,4*((n-1)*i+(j+1)));
				break;
			}
			return chain(only(x),r.filter!(x=>0<=x&&x<mesh.normals.length));
		}
		foreach(i;0..3){
			foreach(v;clones(f[i])) assert(mesh.vertices[v]==mesh.vertices[f[i]],text(v," ",f[i]));
			foreach(v;clones(f[i])) mesh.normals[v]+=p;
		}
	}
	foreach(i,normal;mesh.normals){
		mesh.normals[i] = normal.normalized;
	}
	mesh.dataReady=true;
	mesh.prepareVAO();
	return mesh;
}
