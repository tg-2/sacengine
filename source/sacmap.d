import dagon;
import util;
import hmap,tmap,txtr;
import std.exception, std.string, std.algorithm, std.conv, std.range;
import std.stdio, std.path, std.file;

class SacMap{
	Mesh mesh;
	Texture texture;
	Texture bump;

	this(string filename){
		enforce(filename.endsWith(".HMAP"));
		auto hmap=loadHMap(filename);
		auto tmap=loadTMap(filename[0..$-".HMAP".length]~".TMAP");
		mesh=createMesh(hmap,tmap);
	}

	void createEntities(Scene s){
		if(!mesh) return;
		auto obj=s.createEntity3D();
		obj.drawable = mesh;
		obj.position = Vector3f(0, 0, 0);
		auto land="extracted/prsc/prsc.WAD!/prsc.LAND";
		//auto land="extracted/strato_a/ST_A.WAD!/ST_A.LAND";
		//auto land="extracted/james_a/JA_A.WAD!/JA_A.LAND";
		auto mapts=loadMAPTs(land);
		//auto dts=loadDTs(land);
		texture=New!Texture(null);
		//bump=New!Texture(null);
		//texture.image=mapts;
		texture.image=mapts;
		//bump.image=dts;
		texture.createFromImage(texture.image);
		//bump.createFromImage(texture.image);
		auto mat=s.createMaterial();
		mat.diffuse=texture;
		//mat.height=bump;
		//mat.parallax=ParallaxSimple;
		mat.specular=texture;
		mat.roughness=0;
		mat.metallic=0;
		obj.material=mat;
	}
}

SuperImage loadDTs(string directory){
	auto images=iota(0,7).map!(i=>loadTXTR(buildPath(directory,format("DT%02d.TXTR",i)))).array;
	auto dti=loadDTIndex(directory).dts;
	auto img=image(256*16*3,256*16*3);
	foreach(i;0..256){
		foreach(k;0..3){
			foreach(l;0..3){
				foreach(x;0..256){
					foreach(y;0..256){
						int cy=l==0?0:l==1?y:255;
						int cx=k==0?0:k==1?x:255;
						img[k*256+3*256*(i%16)+x,l*256+3*256*(i/16)+y]=images[dti[i]][cx,cy];
					}
				}
			}
		}
	}
	//img.savePNG("test2.png");
	return img;
}

SuperImage loadMAPTs(string directory){
	auto img=image(64*16*3,64*16*3);
	auto palFile=buildPath(directory, "LAND.PALT");
	auto palt=readFile(palFile);
	palt=palt[8..$]; // header bytes (TODO: figure out what they mean)
	foreach(i;0..256){
		//auto maptFile=buildPath(directory,format("%04d.MAPT",i));
		auto maptFile=buildPath(directory,format("%04d.MAPT",i));
		if(!exists(maptFile)) continue;
		auto data=readFile(maptFile);
		import std.random;
		/+int sum=0;
		foreach(y;0..64){
			foreach(x;0..64){
				auto ccol=data[64*y+x];
				sum+=palt[3*ccol];
				sum+=palt[3*ccol+1];
				sum+=palt[3*ccol+2];
			}
		}
		sum/=64;+/
		//auto color=Color4f(Color4(uniform(0,256),uniform(0,256),uniform(0,256)))*0.8;
		/+Color4f color;
		if(sum<44000) color=Color4f(0,0,0);
		else color=Color4f(1,1,1);+/
		
		foreach(l;0..3){
			foreach(k;0..3){
				foreach(y;0..64){
					foreach(x;0..64){
						uint ccol;
						int cy=l==0?0:l==1?y:63;
						int cx=k==0?0:k==1?x:63;
						ccol=data[64*cy+cx];
						img[k*64+3*64*(i%16)+x,l*64+3*64*(i/16)+y]=Color4f(Color4(palt[3*ccol],palt[3*ccol+1],palt[3*ccol+2]))*0.6;
					}
				}
			}
		}
	}
	//img.savePNG("test.png");
	return img;
}

Mesh createMesh(HMap hmap, TMap tmap, float scaleFactor=1){
	auto edges=hmap.edges;
	auto heights=hmap.heights.dup;
	auto tiles=tmap.tiles;
	auto minHeight=1e9;
	foreach(h;heights) foreach(x;h) minHeight=min(minHeight,x);
	foreach(h;heights) foreach(ref x;h) x-=minHeight;
	//foreach(e;edges) e[]=false;
	auto mesh=new Mesh(null);
	auto n=to!int(hmap.edges.length);
	enforce(n);
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
				enum eps=1/3.0f;
				auto tile=tiles[n-1-j][i];
				mesh.texcoords[4*((n-1)*i+j)+k]=Vector2f((tile%16+(di?1-eps:eps))/16.0f,(tile/16+(!dj?1-eps:eps))/16.0f);
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
			//foreach(v;clones(f[i])) assert(mesh.vertices[v]==mesh.vertices[f[i]],text(v," ",f[i]));
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
