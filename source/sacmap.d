import dagon;
import util;
import maps,txtr;
import std.exception, std.string, std.algorithm, std.conv, std.range;
import std.stdio, std.path, std.file;
import std.typecons: tuple,Tuple;

class SacMap{ // TODO: make this an entity
	TerrainMesh[] meshes;
	Texture[] textures;
	Texture[] details;
	Texture color;
	ubyte[] dti;

	this(string filename){
		enforce(filename.endsWith(".HMAP"));
		auto hmap=loadHMap(filename);
		auto tmap=loadTMap(filename[0..$-".HMAP".length]~".TMAP");
		meshes=createMeshes(hmap,tmap);
		auto land="extracted/prsc/prsc.WAD!/prsc.LAND";
		//auto land="extracted/james_a/JA_A.WAD!/JA_A.LAND";
		//auto land="extracted/strato_a/ST_A.WAD!/ST_A.LAND";

		dti=loadDTIndex(land).dts;
		static Texture makeTexture(SuperImage i){
			auto texture=New!Texture(null); // TODO: set owner
			texture.image=i;
			texture.createFromImage(texture.image);
			return texture;
		}
		auto mapts=loadMAPTs(land);
		auto bumps=loadDTs(land);
		textures=loadMAPTs(land).map!makeTexture.array;
		details=bumps.map!makeTexture.array;
		auto lmap=loadLMap(filename[0..$-".HMAP".length]~".LMAP");
		color=makeTexture(lmap);
	}

	void createEntities(Scene s){
		foreach(i,mesh;meshes){
			if(!mesh) continue;
			auto obj=s.createEntity3D();
			obj.drawable = mesh;
			obj.position = Vector3f(0, 0, 0);
			auto mat=s.createMaterial(s.terrainMaterialBackend);
			assert(!!textures[i]);
			mat.diffuse=textures[i];
			assert(!!details[dti[i]]);
			mat.detail=details[dti[i]];
			mat.color=color;
			mat.specular=0.8;
			mat.roughness=1;
			mat.metallic=0.6;
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
			auto maptFile=buildPath(directory,format("%04d.MAPT",i));
			auto img=image(64,64);
			if(!exists(maptFile)) return img;
			auto data=readFile(maptFile);
			foreach(y;0..64){
				foreach(x;0..64){
					uint ccol=data[64*y+x];
					img[x,y]=Color4f(Color4(palt[3*ccol],palt[3*ccol+1],palt[3*ccol+2]));
				}
			}
			return img;
		}).array;
}

TerrainMesh[] createMeshes(HMap hmap, TMap tmap, float scaleFactor=1){
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
	auto meshes=new TerrainMesh[](256);
	foreach(j;0..n-1){
		foreach(i;0..m-1){
			auto t=tiles[n-2-j][i];
			if(!meshes[t]){
				if(!numFaces[t]) continue;
				meshes[t]=new TerrainMesh(null);
				meshes[t].vertices=New!(Vector3f[])(numVertices[t]);
				meshes[t].normals=New!(Vector3f[])(numVertices[t]);
				meshes[t].texcoords=New!(Vector2f[])(numVertices[t]);
				meshes[t].coords=New!(Vector2f[])(numVertices[t]);
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
				meshes[t].coords[curVertex[t]+k]=Vector2f(i+di(k),n-1-(j+dj(k)))/256.0f;
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
