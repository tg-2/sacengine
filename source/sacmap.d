import dagon;
import util;
import maps,txtr;
import std.exception, std.string, std.algorithm, std.conv, std.range;
import std.stdio, std.path, std.file;
import std.typecons: tuple,Tuple;

class SacMap{ // TODO: make this an entity
	Mesh[] meshes;
	Texture[] textures;
	Texture[] bump;
	Texture colors;
	ubyte[] dti;

	this(string filename){
		enforce(filename.endsWith(".HMAP"));
		auto hmap=loadHMap(filename);
		auto tmap=loadTMap(filename[0..$-".HMAP".length]~".TMAP");
		meshes=createMeshes(hmap,tmap);
		auto land="extracted/prsc/prsc.WAD!/prsc.LAND";
		dti=loadDTIndex(land).dts;
		static Texture makeTexture(SuperImage i){
			auto texture=New!Texture(null); // TODO: set owner
			texture.image=i;
			texture.createFromImage(texture.image);
			return texture;
		}
		static SuperImage addDetail(ref SuperImage img,ref SuperImage dt){
			auto r=image(dt.width,dt.height);
			foreach(j;0..256){
				foreach(i;0..256){
					// TODO: use proper interpolation here
					auto cur=img[j/4,i/4];
					auto up=j/4?img[j/4-1,i/4]:cur;
					auto ri=i/4<63?img[j/4,i/4+1]:cur;
					auto lo=j/4<63?img[j/4+1,i/4]:cur;
					auto le=i/4<63?img[j/4-1,i/4]:cur;
					auto col=(cur+up+ri+lo+le)/5;
					auto det=dt[j,i];
					r[j,i]=0.5*col+0.5*Color4f(col.r*det.r,col.g*det.g,col.b*det.b);
				}
			}
			return r;
		}
		auto mapts=loadMAPTs(land);
		auto bumps=loadDTs(land);
		textures=iota(256).map!(i=>meshes[i]?addDetail(mapts[i],bumps[dti[i]]):mapts[i]).map!makeTexture.array;
		bump=bumps.map!makeTexture.array;
		//textures=loadMAPTs(land).map!makeTexture.array;
		auto lmap=loadLMap(filename[0..$-".HMAP".length]~".LMAP");
		colors=makeTexture(lmap);
	}

	void createEntities(Scene s){
		foreach(i,mesh;meshes){
			if(!mesh) continue;
			auto obj=s.createEntity3D();
			obj.drawable = mesh;
			obj.position = Vector3f(0, 0, 0);
			//auto land="extracted/strato_a/ST_A.WAD!/ST_A.LAND";
			//auto land="extracted/james_a/JA_A.WAD!/JA_A.LAND";
			//auto dts=loadDTs(land);
			//bump=New!Texture(null);
			//texture.image=mapts;
			//bump.image=dts;
			//bump.createFromImage(texture.image);
			auto mat=s.createMaterial();
			assert(!!textures[i]);
			mat.diffuse=textures[i];
			//mat.diffuse=bump[dti[i]];
			assert(!!bump[dti[i]]);
			//mat.height=bump[dti[i]];
			//mat.parallax=ParallaxSimple;
			mat.specular=0;
			mat.roughness=0;
			mat.metallic=0;
			obj.material=mat;
		}
	}
}

SuperImage loadLMap(string filename){
	enforce(filename.endsWith(".LMAP"));
	auto colors=maps.loadLMap(filename).colors;
	auto img=image(256,256);
	assert(colors.length==256);
	foreach(y;0..cast(int)colors.length){
		assert(colors[y].length==256);
		foreach(x;0..cast(int)colors[y].length){
			img[x,y]=Color4f(Color4(colors[y][x][0],colors[y][x][1],colors[y][x][2]));
		}
	}
	return img;
}

SuperImage[] loadDTs(string directory){
	auto r=iota(0,7).map!(i=>loadTXTR(buildPath(directory,format("DT%02d.TXTR",i)))).array;
	foreach(ref img;r){
		foreach(j;0..256){
			foreach(i;0..256){
				img[j,i]=Color4f(img[j,i].r,img[j,i].g,img[j,i].b,img[j,i].b);
			}
		}
	}
	return r;
}

SuperImage[] loadMAPTs(string directory){
	auto palFile=buildPath(directory, "LAND.PALT");
	auto palt=readFile(palFile);
	palt=palt[8..$]; // header bytes (TODO: figure out what they mean)
	return iota(0,256).map!((i){
			//auto maptFile=buildPath(directory,format("%04d.MAPT",i));
			auto maptFile=buildPath(directory,format("%04d.MAPT",i));
			auto img=image(64,64);
			if(!exists(maptFile)) return img;
			auto data=readFile(maptFile);
			foreach(y;0..64){
				foreach(x;0..64){
					uint ccol=data[64*y+x];
					img[x,y]=Color4f(Color4(palt[3*ccol],palt[3*ccol+1],palt[3*ccol+2]))*0.6;
				}
			}
			return img;
		}).array;
}

Mesh[] createMeshes(HMap hmap, TMap tmap, float scaleFactor=1){
	auto edges=hmap.edges;
	auto heights=hmap.heights.dup;
	auto tiles=tmap.tiles;
	auto minHeight=1e9;
	foreach(h;heights) foreach(x;h) minHeight=min(minHeight,x);
	foreach(h;heights) foreach(ref x;h) x-=minHeight;
	//foreach(e;edges) e[]=false;
	Vector3f getVertex(int z,int x){
		return scaleFactor*Vector3f(10*x,heights[z][x]/100,10*z);
	}
	auto n=to!int(hmap.edges.length);
	enforce(n);
	auto m=to!int(hmap.edges[0].length);
	enforce(heights.length==n);
	enforce(edges.all!(x=>x.length==m));
	enforce(heights.all!(x=>x.length==m));
	int di(int i){ return i==1||i==2; }
	int dj(int i){ return i==2||i==3; }
	auto getFaces(O)(int j,int i,O o){
		if(!edges[j][i]&&!edges[j+1][i+1]&&!edges[j][i+1]) o.put([0,2,1]);
		if(!edges[j+1][i+1]&&!edges[j][i]&&!edges[j+1][i]) o.put([2,0,3]);
		if(edges[j][i]&&!edges[j][i+1]&&!edges[j+1][i+1]&&!edges[j+1][i]) o.put([1,3,2]);
		if(edges[j+1][i+1]&&!edges[j][i]&&!edges[j][i+1]&&!edges[j+1][i]) o.put([0,3,1]);
	}
	auto normals=new Vector3f[][](n,m);
	foreach(j;0..n) normals[j][]=Vector3f(0,0,0);
	foreach(j;0..n-1){
		foreach(i;0..m-1){
			struct ProcessFaces{
				void put(uint[3] f){
					Vector3f[3] v;
					foreach(k;0..3){
						v[k]=getVertex(j+dj(f[k]),i+di(f[k]));
					}
					Vector3f p=cross(v[1]-v[0],v[2]-v[0]);
					foreach(k;0..3){
						normals[j+dj(f[k])][i+di(f[k])]+=p;
					}
				}
			}
			getFaces(j,i,ProcessFaces());
		}
	}
	foreach(j;0..n)
		foreach(i;0..m)
			normals[j][i]=normals[j][i].normalized;
	auto numVertices=new uint[](256);
	auto numFaces=new uint[](256);
	foreach(j;0..n-1){
		foreach(i;0..m-1){
			auto t=tiles[n-2-j][i];
			int faces=0;
			struct FaceCounter{
				void put(uint[3]){
					faces++;
				}
			}
			getFaces(j,i,FaceCounter());
			if(faces){
				numVertices[t]+=4;
				numFaces[t]+=faces;
			}
		}
	}
	auto curVertex=new uint[](256);
	auto curFace=new uint[](256);
	auto meshes=new Mesh[](256);
	foreach(j;0..n-1){
		foreach(i;0..m-1){
			auto t=tiles[n-2-j][i];
			if(!meshes[t]){
				if(!numFaces[t]) continue;
				meshes[t]=new Mesh(null);
				meshes[t].vertices=New!(Vector3f[])(numVertices[t]);
				meshes[t].normals=New!(Vector3f[])(numVertices[t]);
				meshes[t].texcoords=New!(Vector2f[])(numVertices[t]);
				meshes[t].indices=New!(uint[3][])(numFaces[t]);
			}
			int faces=0;
			struct FaceCounter2{
				void put(uint[3]){
					faces++;
				}
			}
			getFaces(j,i,FaceCounter2());
			if(!faces) continue;
			foreach(k;0..4){
				meshes[t].vertices[curVertex[t]+k]=getVertex(j+dj(k),i+di(k));
				meshes[t].normals[curVertex[t]+k]=normals[j+dj(k)][i+di(k)];
				meshes[t].texcoords[curVertex[t]+k]=Vector2f(di(k),!dj(k));
			}
			struct ProcessFaces2{
				void put(uint[3] f){
					meshes[t].indices[curFace[t]++]=[curVertex[t]+f[0],curVertex[t]+f[1],curVertex[t]+f[2]];
				}
			}
			getFaces(j,i,ProcessFaces2());
			curVertex[t]+=4;
		}
	}
	assert(curVertex==numVertices && curFace==numFaces);
	foreach(mesh;meshes){
		if(!mesh) continue;
		mesh.dataReady=true;
		mesh.prepareVAO();
	}
	return meshes;
}
