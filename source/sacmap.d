import dlib.image, dlib.math, dlib.geometry;
import util;
import maps,txtr,envi;
import std.exception, std.string, std.algorithm, std.conv, std.range;
import std.stdio, std.path, std.file;
import std.typecons: tuple,Tuple;
import std.math;

import sacobject;

enum{
	numMapTextures=256,
	bottomIndex=numMapTextures,
	edgeIndex,
	numMapMeshes,

	skyIndex=numMapMeshes,
	skybIndex,
	skytIndex,
	sunIndex,
	undrIndex,
	numSacMapTextures,
	numSkyMeshes=undrIndex+1-skyIndex,
}
enum mapDepth=50.0f;


final class SacMap(B){
	B.TerrainMesh[] meshes;
	B.MinimapMesh[] minimapMeshes;
	B.Texture[] textures;
	B.Texture[] details;
	B.Texture color;
	B.Material material; // TODO: get rid of this completely?
	ubyte[] dti;
	int n,m;
	bool[][] edges;
	float[][] heights;
	Tileset tileset;
	ubyte[][] tiles;
	Envi envi;

	this(string filename){
		enforce(filename.endsWith(".HMAP"));
		auto hmap=loadHMap(filename);
		auto minHeight=1e9;
		foreach(h;hmap.heights) foreach(x;h) minHeight=min(minHeight,x);
		foreach(h;hmap.heights) foreach(ref x;h) x-=minHeight;
		envi=loadENVI(filename[0..$-".HMAP".length]~".ENVI");
		auto tmap=loadTMap(filename[0..$-".HMAP".length]~".TMAP");
		edges=hmap.edges;
		heights=hmap.heights;
		tiles=tmap.tiles;
		n=to!int(edges.length);
		m=to!int(edges[1].length);
		enforce(heights.length==n);
		enforce(edges.all!(x=>x.length==m));
		enforce(heights.all!(x=>x.length==m));
		import nttData: landFolders;
		tileset=detectTileset(filename[0..$-".HMAP".length]~".LEVL");
		auto land=landFolders[tileset];
		dti=loadDTIndex(land).dts;
		auto mapts=loadMAPTs(land);
		auto bumps=loadDTs(land);
		auto edge=loadTXTR(buildPath(land,chain(retro(envi.edge[]),".TXTR").to!string));
		//auto sky_=loadTXTR(buildPath(land,chain(retro(envi.sky_[]),".TXTR").to!string)); // TODO: smk files
		auto sky_=loadTXTR(buildPath(land,"SKY_.TXTR"));
		auto skyb=loadTXTR(buildPath(land,chain(retro(envi.skyb[]),".TXTR").to!string));
		auto skyt=loadTXTR(buildPath(land,chain(retro(envi.skyt[]),".TXTR").to!string));
		auto sun_=loadTXTR(buildPath(land,chain(retro(envi.sun_[]),".TXTR").to!string));
		auto undr=loadTXTR(buildPath(land,chain(retro(envi.undr[]),".TXTR").to!string));
		auto mirroredRepeat=iota(numSacMapTextures).map!(i=>i!=skyIndex);
		textures=zip(chain(mapts,only(edge,edge,sky_,skyb,skyt,sun_,undr)),mirroredRepeat).map!(x=>B.makeTexture(x.expand)).array;
		details=bumps.map!(B.makeTexture).array;
		auto lmap=loadLMap(filename[0..$-".HMAP".length]~".LMAP");
		color=B.makeTexture(lmap);
		material=B.createMaterial(this);
	}

	struct Sky{
		enum scaling=4*10.0f*256.0f;
		enum dZ=-0.05, undrZ=-0.25, skyZ=0.25, relCloudLoc=0.7;
		enum numSegs=64, numTextureRepeats=8;
		enum energy=1.7f;
	}

	Vector2f sunSkyRelLoc(Vector3f cameraPos){
		auto sunPos=Vector3f(0,0,Sky.skyZ*Sky.scaling);
		auto adjCamPos=cameraPos-Vector3f(1280.0f,1280.0f,Sky.dZ*Sky.scaling+1);
		float zDiff=sunPos.z-adjCamPos.z;
		float tZDiff=Sky.scaling*Sky.skyZ*(1-Sky.relCloudLoc);
		auto intersection=sunPos+(adjCamPos-sunPos)*tZDiff/zDiff;
		return intersection.xy/(Sky.scaling/2);
	}

	Tuple!(int,"j",int,"i") getTile(Vector3f pos){
		return tuple!("j","i")(cast(int)(n-1-pos.y/10),cast(int)(pos.x/10));
	}
	Vector3f getVertex(int j,int i){
		return Vector3f(10*i,10*(n-1-j),heights[j][i]);
	}

	Tuple!(int,"j",int,"i")[3] getTriangle(bool invert=false)(Vector3f pos){
		auto tile=getTile(pos);
		int i=tile.i,j=tile.j;
		if(i<0||i>=n-1||j<0||j>=m-1) return typeof(return).init;
		Tuple!(int,"j",int,"i")[3][2] tri;
		int nt=0;
		void makeTri(int[] indices)(){
			foreach(k,ref x;tri[nt++]){
				x=tuple!("j","i")(j+dj(indices[k]),i+di(indices[k]));
			}
		}
		static if(!invert){
			if(!edges[j][i]){
				if(!edges[j+1][i+1]&&!edges[j][i+1]) makeTri!([0,2,1]);
			}else if(!edges[j][i+1]&&!edges[j+1][i+1]&&!edges[j+1][i]) makeTri!([1,3,2]);
			if(!edges[j+1][i+1]){
				if(!edges[j][i]&&!edges[j+1][i]) makeTri!([2,0,3]);
			}else if(!edges[j][i]&&!edges[j][i+1]&&!edges[j+1][i]) makeTri!([0,3,1]);
		}else{
			if(edges[j][i]){
				if(!edges[j+1][i+1]&&!edges[j][i+1]) makeTri!([2,0,3]);
			}else if(!edges[j][i+1]&&!edges[j+1][i+1]&&!edges[j+1][i]) makeTri!([0,3,1]);
			if(!edges[j+1][i+1]){
				if(!edges[j][i]&&!edges[j+1][i]) makeTri!([0,2,1]);
			}else if(!edges[j][i]&&!edges[j][i+1]&&!edges[j+1][i]) makeTri!([1,3,2]);
			if(nt==0){
				makeTri!([0,2,1]);
				makeTri!([2,0,3]);
			}
		}
		bool isInside(Tuple!(int,"j",int,"i")[3] tri){
			Vector3f getV(int k){
				auto v=getVertex(tri[k%$].j,tri[k%$].i)-pos;
				v.z=0;
				return v;
			}
			foreach(k;0..3){
				if(cross(getV(k),getV(k+1)).z<0)
					return false;
			}
			return true;
		}
		if(nt==0) return typeof(return).init;
		if(!invert){
			if(isInside(tri[0])) return tri[0]; // TODO: fix precision issues, by using fixed-point and splitting at line
			else if(nt==2) return tri[1];
			else return typeof(return).init;
		}else{
			if(nt==1||!isInside(tri[1])) return tri[0];
			else return tri[1];
		}
	}

	bool isOnGround(Vector3f pos){
		auto triangle=getTriangle(pos);
		return triangle[0]!=triangle[1];
	}
	private float getHeightImpl(Tuple!(int,"j",int,"i")[3] triangle,Vector3f pos){
		static foreach(i;0..3)
			mixin(text(`auto p`,i,`=getVertex(triangle[`,i,`].expand);`));
		Plane plane;
		plane.fromPoints(p0,p1,p2); // wtf.
		return -(plane.a*pos.x+plane.b*pos.y+plane.d)/plane.c;
	}
	float getHeight(Vector3f pos){
		auto triangle=getTriangle(pos);
		if(triangle[0]==triangle[1]) triangle=getTriangle!true(pos);
		if(triangle[0]==triangle[1]) return 0.0f;
		return getHeightImpl(triangle,pos);
	}
	float getGroundHeight(Vector3f pos){
		auto triangle=getTriangle(pos);
		return getHeightImpl(triangle,pos);
	}
	float getGroundHeightDerivative(Vector3f pos,Vector3f direction){
		auto triangle=getTriangle(pos);
		static foreach(i;0..3)
			mixin(text(`auto p`,i,`=getVertex(triangle[`,i,`].expand);`));
		Plane plane;
		plane.fromPoints(p0,p1,p2); // wtf.
		return -(plane.a*direction.x+plane.b*direction.y)/plane.c;
	}
	Vector3f moveOnGround(Vector3f position,Vector3f direction)in{
		assert(isOnGround(position));
	}do{
		auto newPosition=position+direction;
		if(isOnGround(newPosition)){
			newPosition.z=getGroundHeight(newPosition);
			return newPosition;
		}
		static immutable Vector2f[8] directions=cartesianProduct([-1,0,1],[-1,0,1]).filter!(x=>x[0]||x[1]).map!(x=>Vector2f(x[0],x[1],0.0f).normalized).array;
		Vector3f bestNewPosition=position;
		float largestDotProduct=0.0f;
		foreach(i;0..8){
			auto dotProduct=dot(directions[i],direction.xy);
			if(dotProduct>largestDotProduct){
				auto newPosition2D=position.xy+dotProduct*directions[i];
				newPosition=Vector3f(newPosition2D.x,newPosition2D.y,0.0f);
				if(isOnGround(newPosition)){
					bestNewPosition=newPosition;
					largestDotProduct=0.0f;
				}
			}
		}
		bestNewPosition.z=getGroundHeight(bestNewPosition);
		return bestNewPosition;
	}
}

SuperImage loadLMap(string filename){
	enforce(filename.endsWith(".LMAP"));
	auto img=image(256,256,4);
	auto idata=img.data,data=readFile(filename);
	enforce(idata.length==data.length);
	img.data[]=data[];
	return img;
}

SuperImage[] loadDTs(string directory){
	auto r=iota(0,7).until!(i=>!exists(buildPath(directory,format("DT%02d.TXTR",i)))).map!(i=>loadTXTR(buildPath(directory,format("DT%02d.TXTR",i)))).array;
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

int di(int k){ return k==1||k==2; }
int dj(int k){ return k==2||k==3; }
void getFaces(O)(bool[][] edges,int j,int i,O o){
	if(!edges[j][i]){
		if(!edges[j+1][i+1]&&!edges[j][i+1]) o.put([0,2,1]);
	}else if(!edges[j][i+1]&&!edges[j+1][i+1]&&!edges[j+1][i]) o.put([1,3,2]);
	if(!edges[j+1][i+1]){
		if(!edges[j][i]&&!edges[j+1][i]) o.put([2,0,3]);
	}else if(!edges[j][i]&&!edges[j][i+1]&&!edges[j+1][i]) o.put([0,3,1]);
}
Vector3f getVertex(int n,int m,float[][] heights,int j,int i){ return Vector3f(10*i,10*(n-1-j),heights[j][i]); }
Vector2f getVertex2D(int n,int m,int j,int i){ return Vector2f(10*i,10*(n-1-j)); }

Vector3f[][] generateNormals(int n,int m,bool[][] edges, float[][] heights){
	auto normals=new Vector3f[][](n,m);
	foreach(j;0..n) normals[j][]=Vector3f(0,0,0);
	foreach(j;0..n-1){
		foreach(i;0..m-1){
			struct ProcessFaces{
				void put(uint[3] f){
					Vector3f[3] v;
					foreach(k;0..3){
						v[k]=getVertex(n,m,heights,j+dj(f[k]),i+di(f[k]));
					}
					Vector3f p=cross(v[1]-v[0],v[2]-v[0]);
					foreach(k;0..3){
						normals[j+dj(f[k])][i+di(f[k])]+=p;
					}
				}
			}
			getFaces(edges,j,i,ProcessFaces());
		}
	}
	foreach(j;0..n)
		foreach(i;0..m)
			normals[j][i]=normals[j][i].normalized;
	return normals;
}

Tuple!(uint[],uint[]) getVertexAndFaceCount(int n,int m,bool[][] edges,ubyte[][] tiles,bool addBottom=false){
	auto numVertices=new uint[](257);
	auto numFaces=new uint[](257);
	foreach(j;0..n-1){
		foreach(i;0..m-1){
			auto t=tiles[n-2-j][i];
			int faces=0;
			struct FaceCounter{
				void put(uint[3]){
					faces++;
				}
			}
			getFaces(edges,j,i,FaceCounter());
			if(faces){
				numVertices[t]+=4;
				numFaces[t]+=faces;
				if(addBottom){
					numVertices[bottomIndex]+=4;
					numFaces[bottomIndex]+=faces;
				}
			}
		}
	}
	return tuple(numVertices,numFaces);
}

B.TerrainMesh[] createMeshes(B)(bool[][] edges, float[][] heights, ubyte[][] tiles, bool addBottom){
	//foreach(e;edges) e[]=false;
	auto n=to!int(edges.length);
	enforce(n);
	auto m=to!int(edges[0].length);
	enforce(heights.length==n);
	enforce(edges.all!(x=>x.length==m));
	enforce(heights.all!(x=>x.length==m));
	Vector3f getVertex(int j,int i){ return .getVertex(n,m,heights,j,i); }
	void getFaces(O)(int j,int i,O o){ .getFaces(edges,j,i,o); }
	auto normals=generateNormals(n,m,edges,heights);
	auto numVerticesNumFaces=getVertexAndFaceCount(n,m,edges,tiles,addBottom);
	auto numVertices=numVerticesNumFaces[0], numFaces=numVerticesNumFaces[1];
	auto curVertex=new uint[](numMapMeshes-1);
	auto curFace=new uint[](numMapMeshes-1);
	auto meshes=new B.TerrainMesh[](numMapMeshes);
	foreach(j;0..n-1){
		foreach(i;0..m-1){
			auto t=tiles[n-2-j][i];
			if(!meshes[t]){
				if(!numFaces[t]) continue;
				meshes[t]=B.makeTerrainMesh(numVertices[t], numFaces[t]);
			}
			if(!meshes[bottomIndex])
				meshes[bottomIndex]=B.makeTerrainMesh(numVertices[bottomIndex], numFaces[bottomIndex]);
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
				if(addBottom){
					meshes[bottomIndex].vertices[curVertex[bottomIndex]+k]=getVertex(j+dj(k),i+di(k))+Vector3f(0,0,-mapDepth);
					meshes[bottomIndex].normals[curVertex[bottomIndex]+k]=-normals[j+dj(k)][i+di(k)];
					meshes[bottomIndex].coords[curVertex[bottomIndex]+k]=Vector2f(i+di(k),n-1-(j+dj(k)))/256.0f;
					meshes[bottomIndex].texcoords[curVertex[bottomIndex]+k]=Vector2f(di(k),1);
				}
			}
			struct ProcessFaces2{
				void put(uint[3] f){
					meshes[t].indices[curFace[t]++]=[curVertex[t]+f[0],curVertex[t]+f[1],curVertex[t]+f[2]];
					if(addBottom){
						meshes[bottomIndex].indices[curFace[bottomIndex]++]=[curVertex[bottomIndex]+f[0],curVertex[bottomIndex]+f[2],curVertex[bottomIndex]+f[1]];
					}
				}
			}
			getFaces(j,i,ProcessFaces2());
			curVertex[t]+=4;
			if(addBottom) curVertex[bottomIndex]+=4;
		}
	}
	assert(curVertex==numVertices && curFace==numFaces);
	Vector3f[] edgeVertices;
	Vector3f[] edgeNormals;
	Vector2f[] edgeCoords;
	Vector2f[] edgeTexcoords;
	uint[3][] edgeFaces;
	foreach(j;0..n-1){
		foreach(i;0..m-1){
			void makeEdge(R,S)(int x1,int y1,int x2,int y2,R mustBeEdges,S someNonEdge){
				if(!mustBeEdges.all!((k)=>edges[k[1]][k[0]])||
				   edges[y1][x1]||edges[y2][x2]||!someNonEdge.any!((k)=>!edges[k[1]][k[0]])) return;
				auto off=to!uint(edgeVertices.length);
				edgeVertices~=[getVertex(y1,x1),getVertex(y2,x2),getVertex(y2,x2)+Vector3f(0,0,-mapDepth),getVertex(y1,x1)+Vector3f(0,0,-mapDepth)];
				auto normal=cross(edgeVertices[$-3]-edgeVertices[$-1],edgeVertices[$-2]-edgeVertices[$-1]);
				foreach(k;0..4) edgeNormals~=normal.normalized;
				edgeCoords~=[Vector2f(x1,n-1-y1)/256.0,Vector2f(x2,n-1-y2)/256.0,Vector2f(x2,n-1-y2)/256.0,Vector2f(x1,n-1-y1)/256.0];
				edgeTexcoords~=[Vector2f(0,0),Vector2f(1,0),Vector2f(1,1),Vector2f(0,1)];
				edgeFaces~=[[off+0,off+1,off+2],[off+2,off+3,off+0]];
			}
			makeEdge(i,j,i+1,j,only(tuple(i,j-1),tuple(i+1,j-1)).filter!(x=>!!j),only(tuple(i,j+1),tuple(i+1,j+1)));
			makeEdge(i+1,j+1,i,j+1,only(tuple(i+1,j+2),tuple(i,j+2)).filter!(x=>j+1!=n-1),only(tuple(i,j),tuple(i+1,j)));
			makeEdge(i,j+1,i,j,only(tuple(i-1,j+1),tuple(i-1,j)).filter!(x=>!!i),only(tuple(i+1,j+1),tuple(i+1,j)));
			makeEdge(i+1,j,i+1,j+1,only(tuple(i+2,j),tuple(i+2,j+1)).filter!(x=>i+1!=m-1),only(tuple(i,j),tuple(i,j+1)));
			makeEdge(i,j,i+1,j+1,only(tuple(i+1,j)),only(tuple(i,j+1)));
			makeEdge(i+1,j,i,j+1,only(tuple(i+1,j+1)),only(tuple(i,j)));
			makeEdge(i+1,j+1,i,j,only(tuple(i,j+1)),only(tuple(i+1,j)));
			makeEdge(i,j+1,i+1,j,only(tuple(i,j)),only(tuple(i+1,j+1)));
		}
	}
	meshes[edgeIndex]=B.makeTerrainMesh(edgeVertices.length,edgeFaces.length);
	meshes[edgeIndex].vertices[]=edgeVertices[];
	meshes[edgeIndex].normals[]=edgeNormals[];
	meshes[edgeIndex].coords[]=edgeCoords[];
	meshes[edgeIndex].texcoords[]=edgeTexcoords[];
	meshes[edgeIndex].indices[]=edgeFaces[];
	foreach(mesh;meshes){
		if(!mesh) continue;
		B.finalizeTerrainMesh(mesh);
	}
	return meshes;
}

B.MinimapMesh[] createMinimapMeshes(B)(bool[][] edges, ubyte[][] tiles){
	//foreach(e;edges) e[]=false;
	auto n=to!int(edges.length);
	enforce(n);
	auto m=to!int(edges[0].length);
	enforce(edges.all!(x=>x.length==m));
	Vector2f getVertex(int j,int i){ return .getVertex2D(n,m,j,i); }
	void getFaces(O)(int j,int i,O o){ .getFaces(edges,j,i,o); }
	auto numVerticesNumFaces=getVertexAndFaceCount(n,m,edges,tiles); // TODO: share with createMeshes?
	auto numVertices=numVerticesNumFaces[0], numFaces=numVerticesNumFaces[1];
	auto curVertex=new uint[](numMapMeshes-1);
	auto curFace=new uint[](numMapMeshes-1);
	auto meshes=new B.MinimapMesh[](numMapMeshes);
	foreach(j;0..n-1){
		foreach(i;0..m-1){
			auto t=tiles[n-2-j][i];
			if(!meshes[t]){
				if(!numFaces[t]) continue;
				meshes[t]=B.makeMinimapMesh(numVertices[t], numFaces[t]);
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
		B.finalizeMinimapMesh(mesh);
	}
	return meshes;
}
