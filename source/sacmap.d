// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import dlib.image, dlib.math, dlib.math.portable, dlib.geometry;
import util,txtr;
import levl,envi,maps,sids,ntts,trig;
import std.exception, std.string, std.algorithm, std.conv, std.range;
import std.stdio, std.path;
import std.typecons: tuple,Tuple;

import sacobject;

SacMap!B loadSacMap(B)(string filename,ubyte[]* mapData=null){
	string levlName,enviName;
	string hmapName,tmapName,lmapName;
	string sidsName,nttsName;
	string trigName;
	uint crc32;
	if(filename.endsWith(".scp")){
		import wadmanager;
		if(!wadManager) wadManager=new WadManager();
		static void handle(ubyte[] data,string name,string* levlName,string* enviName,string* hmapName,string* tmapName,string* lmapName,string* sidsName,string* nttsName,string* trigName,uint* crc32,ubyte[]* mapData){
			if(name.endsWith(".LEVL")){
				if(*levlName) stderr.writeln("warning: multiple level specifications in scp file");
				else *levlName=name;
			}else if(name.endsWith(".ENVI")){
				if(*enviName) stderr.writeln("warning: multiple environment specifications in scp file");
				else *enviName=name;
			}else if(name.endsWith(".HMAP")){
				if(*hmapName) stderr.writeln("warning: multiple height maps in scp file"); // TODO: just create multiple meshes from those?
				else *hmapName=name;
			}else if(name.endsWith(".TMAP")){
				if(*tmapName) stderr.writeln("warning: multiple tile maps in scp file"); // TODO: just create multiple meshes from those?
				else *tmapName=name;
			}else if(name.endsWith(".LMAP")){
				if(*lmapName) stderr.writeln("warning: multiple light maps in scp file"); // TODO: just create multiple meshes from those?
				else *lmapName=name;
			}else if(name.endsWith(".SIDS")){
				if(*sidsName) stderr.writeln("warning: multiple side specifications in scp file");
				else *sidsName=name;
			}else if(name.endsWith(".NTTS")){
				if(*nttsName) stderr.writeln("warning: multiple ntt specifications in scp file"); // TODO: just place all?
				else *nttsName=name;
			}else if(name.endsWith(".TRIG")){
				if(*trigName) stderr.writeln("warning: multiple trigger specifications in scp file"); // TODO: just use all?
				else *trigName=name;
			}
		}
		static void handleData(ubyte[] data,string* levlName,string* enviName,string* hmapName,string* tmapName,string* lmapName,string* sidsName,string* nttsName,string* trigName,uint* crc32,ubyte[]* mapData){
			import std.digest.crc;
			auto result=digest!CRC32(data);
			static assert(result.sizeof==uint.sizeof);
			*crc32=*cast(uint*)&result;
			if(mapData) *mapData=data;
		}
		static int curMapNum=0; // TODO: needed?
		wadManager.indexWAD!(handle,handleData,false)(filename,text("`_map",curMapNum++),&levlName,&enviName,&hmapName,&tmapName,&lmapName,&sidsName,&nttsName,&trigName,&crc32,mapData);
		enforce(levlName!="","No level specification in scp file");
		enforce(enviName!="","No environment specification in scp file");
		enforce(hmapName!="","No height map in scp file");
		enforce(tmapName!="","No tile map in scp file");
		enforce(sidsName!="","No side specification in scp file");
		enforce(nttsName!="","No ntt specification in scp file");
		enforce(trigName!="","No trigger specification in scp file");
	}else{
		enforce(filename.endsWith(".HMAP"));
		auto base=filename[0..$-".HMAP".length];
		levlName=base~".LEVL";
		enviName=base~".ENVI";
		hmapName=filename;
		tmapName=base~".TMAP";
		lmapName=base~".LMAP";
		sidsName=base~".SIDS";
		nttsName=base~".NTTS";
		trigName=base~".TRIG";
	}
	auto mapFolder=dirName(levlName);
	auto levl=loadLevl(levlName);
	auto envi=loadEnvi(enviName);
	auto hmap=loadHMap(hmapName);
	auto tmap=loadTMap(tmapName);
	auto lmap=loadLMap(lmapName);
	auto sids=loadSids(sidsName);
	auto ntts=loadNTTs(nttsName);
	Trig trig;
	try trig=loadTRIG(trigName);
	catch(Exception e){ stderr.writeln("warning: failed to parse triggers (",e.msg,")"); }
	return new SacMap!B(filename,mapFolder,crc32,levl,envi,hmap,tmap,lmap,sids,ntts,trig);
}

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
enum edgeChangesEmptyHash=0xd8f49994; // crc32 hash of 2048 zero uints

static immutable int[2][9] fallingLandChunkNeighborOffsets=[[-1,-1],[0,-1],[1,-1],[1,0],[1,1],[0,1],[-1,1],[-1,0],[0,0]];

struct TerrainTileMeshInfo{
	uint vertexOffset=uint.max;
	uint faceOffset=uint.max;
	uint bottomVertexOffset=uint.max;
	uint bottomFaceOffset=uint.max;
	ubyte numFaces=0;
}
struct MinimapTileMeshInfo{
	uint vertexOffset=uint.max;
	uint faceOffset=uint.max;
	ubyte numFaces=0;
}
struct EdgeWallSlotInfo{
	uint[8] faceOffsets=uint.max;
}

struct ZeroDisplacement{
	static opCall()@nogc{ return typeof(this).init; }
	float opCall(float x,float y)@nogc{ return 0.0f; }
}

final class SacMap(B){
	string path;
	string mapFolder;
	uint crc32;

	Levl levl;
	Envi envi;
	int n,m;
	bool[][] baseEdges;
	bool[][] edges;
	float[][] heights;
	Tileset tileset;
	ubyte[][] tiles;
	ubyte[] dti;
	uint appliedEdgeChangesHash=uint.max;
	uint renderedEdgeChangesHash=edgeChangesEmptyHash;
	uint[2048] renderedEdgeChanges=0;
	TerrainTileMeshInfo[] terrainTileMeshInfos;
	MinimapTileMeshInfo[] minimapTileMeshInfos;
	EdgeWallSlotInfo[] edgeWallSlots;
	B.TerrainMesh dynamicEdgeMesh;
	bool enableMapBottom=false;
	static struct FallingLandChunkMesh{
		int vertexI,vertexJ,spawnFrame;
		B.TerrainMesh[4] topMeshes;
		B.TerrainMesh[4] bottomMeshes;
		B.TerrainMesh edgeMesh;
	}
	Array!FallingLandChunkMesh fallingLandChunkMeshes;
	B.TerrainMesh[] meshes;
	B.MinimapMesh[] minimapMeshes;
	B.Texture[] textures;
	B.Texture[] details;
	B.Texture color;
	B.Material material; // TODO: get rid of this completely?
	Side[] sids;
	NTTs ntts;
	Trig trig;

	this(LMap)(string path,string mapFolder,uint crc32,Levl levl,Envi envi,HMap hmap,TMap tmap,LMap lmap,Side[] sids,NTTs ntts,Trig trig){
		this.path=path;
		this.mapFolder=mapFolder;
		this.crc32=crc32;
		this.levl=levl;
		this.envi=envi;
		baseEdges=hmap.edges.map!(row=>row.dup).array;
		edges=baseEdges.map!(row=>row.dup).array;
		heights=hmap.heights;
		tiles=tmap.tiles;
		n=to!int(edges.length);
		m=to!int(edges[1].length);
		auto minHeight=float.infinity;
		foreach(j,h;hmap.heights) foreach(i,x;h) if(!edges[j][i]) minHeight=min(minHeight,x);
		if(minHeight!=float.infinity) foreach(h;hmap.heights) foreach(ref x;h) x-=minHeight;
		enforce(heights.length==n);
		enforce(edges.all!(x=>x.length==m));
		enforce(heights.all!(x=>x.length==m));
		import nttData: landFolders;
		tileset=levl.detectTileset;
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
		color=B.makeTexture(lmap);
		material=B.createMaterial(this);
		this.sids=sids;
		this.ntts=ntts;
		this.trig=trig;
	}
	bool applyEdgeChanges(uint hash,scope const(uint)[] changes){
		if(appliedEdgeChangesHash==hash) return false;
		enforce(32*changes.length>=n*m);
		bool updated=false;
		foreach(j;0..n){
			foreach(i;0..m){
				auto edge=baseEdges[j][i]^!!((changes[(j*m+i)/32]>>((j*m+i)%32))&1);
				if(edges[j][i]==edge) continue;
				edges[j][i]=edge;
				updated=true;
			}
		}
		appliedEdgeChangesHash=hash;
		return updated;
	}
	void makeMeshes(bool enableMapBottom){
		this.enableMapBottom=enableMapBottom;
		meshes=createMeshes!B(baseEdges,heights,tiles,enableMapBottom,terrainTileMeshInfos,edgeWallSlots); // TODO: allow dynamic retexturing
		minimapMeshes=createMinimapMeshes!B(baseEdges,tiles,minimapTileMeshInfos);
		renderedEdgeChangesHash=edgeChangesEmptyHash;
		renderedEdgeChanges[]=0;
	}
	void updateEdgeMeshes(T)(ref T edgeChanges){
		if(!meshes.length||renderedEdgeChangesHash==edgeChanges.hash) return;
		bool[255*255] dirtyTiles=false;
		bool[255*255] dirtyNormalTiles=false;
		bool[255*255] dirtyWallTiles=false;
		foreach(wordIndex;0..renderedEdgeChanges.length){
			auto diff=renderedEdgeChanges[wordIndex]^edgeChanges.changes[wordIndex];
			if(!diff) continue;
			foreach(bit;0..32){
				if(!(diff&(1u<<bit))) continue;
				auto index=to!int(32*wordIndex+bit);
				auto i=index%256,j=index/256;
				foreach(tj;max(0,j-1)..min(n-1,j+1)){
					foreach(ti;max(0,i-1)..min(m-1,i+1))
						dirtyTiles[tj*(m-1)+ti]=true;
				}
				foreach(tj;max(0,j-2)..min(n-1,j+2)){
					foreach(ti;max(0,i-2)..min(m-1,i+2)){
						dirtyNormalTiles[tj*(m-1)+ti]=true;
						dirtyWallTiles[tj*(m-1)+ti]=true;
					}
				}
			}
		}
		uint[3][2] collectedFaces;
		int collectedNumFaces=0;
		struct CollectFaces{
			void put(uint[3] face){
				if(collectedNumFaces<collectedFaces.length) collectedFaces[collectedNumFaces++]=face;
			}
		}
		void patchTerrainTile(int j,int i){
			auto info=terrainTileMeshInfos[j*(m-1)+i];
			if(!info.numFaces) return;
			collectedNumFaces=0;
			getFaces(edges,j,i,CollectFaces());
			auto texture=tiles[j][i];
			if(auto mesh=meshes[texture]){
				foreach(k;0..info.numFaces){
					auto offset=info.faceOffset+k;
					if(k<collectedNumFaces){
						auto face=collectedFaces[k];
						mesh.indices[offset]=[info.vertexOffset+face[0],info.vertexOffset+face[1],info.vertexOffset+face[2]];
					}else mesh.indices[offset]=[info.vertexOffset,info.vertexOffset,info.vertexOffset];
				}
				B.updateTerrainMeshIndices(mesh,info.faceOffset,mesh.indices[info.faceOffset..info.faceOffset+info.numFaces]);
			}
			if(info.bottomFaceOffset!=uint.max){
				if(auto mesh=meshes[bottomIndex]){
					foreach(k;0..info.numFaces){
						auto offset=info.bottomFaceOffset+k;
						if(k<collectedNumFaces){
							auto face=collectedFaces[k];
							mesh.indices[offset]=[info.bottomVertexOffset+face[0],info.bottomVertexOffset+face[2],info.bottomVertexOffset+face[1]];
						}else mesh.indices[offset]=[info.bottomVertexOffset,info.bottomVertexOffset,info.bottomVertexOffset];
					}
					B.updateTerrainMeshIndices(mesh,info.bottomFaceOffset,mesh.indices[info.bottomFaceOffset..info.bottomFaceOffset+info.numFaces]);
				}
			}
			auto minimapInfo=minimapTileMeshInfos[j*(m-1)+i];
			if(minimapInfo.numFaces){
				if(auto mesh=minimapMeshes[texture]){
					foreach(k;0..minimapInfo.numFaces){
						auto offset=minimapInfo.faceOffset+k;
						if(k<collectedNumFaces){
							auto face=collectedFaces[k];
							mesh.indices[offset]=[minimapInfo.vertexOffset+face[0],minimapInfo.vertexOffset+face[1],minimapInfo.vertexOffset+face[2]];
						}else mesh.indices[offset]=[minimapInfo.vertexOffset,minimapInfo.vertexOffset,minimapInfo.vertexOffset];
					}
					B.updateMinimapMeshIndices(mesh,minimapInfo.faceOffset,mesh.indices[minimapInfo.faceOffset..minimapInfo.faceOffset+minimapInfo.numFaces]);
				}
			}
		}
		void patchTerrainTileNormals(int j,int i){
			auto info=terrainTileMeshInfos[j*(m-1)+i];
			if(!info.numFaces) return;
			Vector3f[4] tileNormals;
			foreach(k;0..4) tileNormals[k]=computeVertexNormal(n,m,edges,heights,j+dj(k),i+di(k));
			if(auto mesh=meshes[tiles[j][i]]){
				foreach(k;0..4) mesh.normals[info.vertexOffset+k]=tileNormals[k];
				B.updateTerrainMeshNormals(mesh,info.vertexOffset,mesh.normals[info.vertexOffset..info.vertexOffset+4]);
			}
			if(info.bottomVertexOffset!=uint.max){
				if(auto mesh=meshes[bottomIndex]){
					foreach(k;0..4) mesh.normals[info.bottomVertexOffset+k]=-tileNormals[k];
					B.updateTerrainMeshNormals(mesh,info.bottomVertexOffset,mesh.normals[info.bottomVertexOffset..info.bottomVertexOffset+4]);
				}
			}
		}
		void patchWallTile(int j,int i){
			auto mesh=meshes[edgeIndex];
			if(!mesh) return;
			foreach(slot,faceOffset;edgeWallSlots[j*(m-1)+i].faceOffsets){
				if(faceOffset==uint.max) continue;
				auto vertexOffset=2*faceOffset;
				if(edgeWallExists(n,m,edges,j,i,cast(int)slot)){
					mesh.indices[faceOffset]=[vertexOffset+0,vertexOffset+2,vertexOffset+1];
					mesh.indices[faceOffset+1]=[vertexOffset+2,vertexOffset+0,vertexOffset+3];
				}else{
					mesh.indices[faceOffset]=[vertexOffset,vertexOffset,vertexOffset];
					mesh.indices[faceOffset+1]=[vertexOffset,vertexOffset,vertexOffset];
				}
				B.updateTerrainMeshIndices(mesh,faceOffset,mesh.indices[faceOffset..faceOffset+2]);
			}
		}
		foreach(j;0..n-1) foreach(i;0..m-1) if(dirtyTiles[j*(m-1)+i]) patchTerrainTile(j,i);
		foreach(j;0..n-1) foreach(i;0..m-1) if(dirtyNormalTiles[j*(m-1)+i]) patchTerrainTileNormals(j,i);
		foreach(j;0..n-1) foreach(i;0..m-1) if(dirtyWallTiles[j*(m-1)+i]) patchWallTile(j,i);
		Array!Vector3f edgeVertices,edgeNormals;
		Array!Vector2f edgeCoords,edgeTexcoords;
		Array!(uint[3]) edgeFaces;
		foreach(j;0..n-1){
			foreach(i;0..m-1){
				foreach(slot;0..8){
					if(!edgeWallExists(n,m,edges,j,i,slot)||edgeWallExists(n,m,baseEdges,j,i,slot)) continue;
					appendEdgeWall(n,m,edges,heights,j,i,slot,edgeVertices,edgeNormals,edgeCoords,edgeTexcoords,edgeFaces);
				}
			}
		}
		if(dynamicEdgeMesh) B.destroyTerrainMesh(dynamicEdgeMesh);
		dynamicEdgeMesh=null;
		if(edgeFaces.length){
			dynamicEdgeMesh=B.makeTerrainMesh(edgeVertices.length,edgeFaces.length);
			dynamicEdgeMesh.vertices[]=edgeVertices.data;
			dynamicEdgeMesh.normals[]=edgeNormals.data;
			dynamicEdgeMesh.coords[]=edgeCoords.data;
			dynamicEdgeMesh.texcoords[]=edgeTexcoords.data;
			dynamicEdgeMesh.indices[]=edgeFaces.data;
			B.finalizeTerrainMesh(dynamicEdgeMesh);
		}
		renderedEdgeChanges[]=edgeChanges.changes[];
		renderedEdgeChangesHash=edgeChanges.hash;
	}

	private static immutable int[3][4] fallingLandChunkQuadrantVertices=[[1,7,0],[1,3,2],[7,5,6],[3,5,4]];
	private static immutable int[3][4] fallingLandChunkFullTriangles=[[1,8,7],[1,3,8],[8,5,7],[8,3,5]];
	private static immutable int[3][4] fallingLandChunkO1HoleTriangles=[[0,8,7],[2,3,8],[8,5,6],[8,4,5]];
	private static immutable int[3][4] fallingLandChunkO2HoleTriangles=[[0,1,8],[1,2,8],[8,6,7],[8,3,4]];
	private static immutable float[2][9][4] fallingLandChunkTexcoords=[
		[[0,0],[1,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,1],[1,1]],
		[[0,0],[0,0],[1,0],[1,1],[0,0],[0,0],[0,0],[0,0],[0,1]],
		[[0,0],[0,0],[0,0],[0,0],[0,0],[1,1],[0,1],[0,0],[1,0]],
		[[0,0],[0,0],[0,0],[1,0],[1,1],[0,1],[0,0],[0,0],[0,0]],
	];
	private static bool fallingLandChunkTriangle(uint presentMask,int q,ref int[3] triangle){
		auto o1=fallingLandChunkQuadrantVertices[q][0],o2=fallingLandChunkQuadrantVertices[q][1],d=fallingLandChunkQuadrantVertices[q][2];
		bool p1=!!(presentMask&(1<<o1)),p2=!!(presentMask&(1<<o2)),pd=!!(presentMask&(1<<d));
		if(p1&&p2) triangle=fallingLandChunkFullTriangles[q];
		else if(p1&&pd) triangle=fallingLandChunkO2HoleTriangles[q];
		else if(p2&&pd) triangle=fallingLandChunkO1HoleTriangles[q];
		else return false;
		return true;
	}
	private static FallingLandChunkMesh makeFallingLandChunkMesh(bool enableMapBottom,int vertexI,int vertexJ,int spawnFrame,uint presentMask,float[9] heights,Vector3f[9] normals){
		FallingLandChunkMesh result;
		result.vertexI=vertexI;
		result.vertexJ=vertexJ;
		result.spawnFrame=spawnFrame;
		auto centerZ=heights[8];
		Vector3f position(int k){
			return Vector3f(10.0f*fallingLandChunkNeighborOffsets[k][0],10.0f*fallingLandChunkNeighborOffsets[k][1],heights[k]-centerZ);
		}
		Vector2f coord(int k){
			return Vector2f(vertexI+fallingLandChunkNeighborOffsets[k][0],vertexJ+fallingLandChunkNeighborOffsets[k][1])/256.0f;
		}
		int[3][4] triangles;
		int numTriangles=0;
		foreach(q;0..4){
			if(!fallingLandChunkTriangle(presentMask,q,triangles[numTriangles])) continue;
			auto mesh=B.makeTerrainMesh(3,1);
			auto bottomMesh=enableMapBottom?B.makeTerrainMesh(3,1):null;
			foreach(v;0..3){
				auto k=triangles[numTriangles][v];
				mesh.vertices[v]=position(k);
				mesh.normals[v]=normals[k];
				mesh.coords[v]=coord(k);
				mesh.texcoords[v]=Vector2f(fallingLandChunkTexcoords[q][k][0],fallingLandChunkTexcoords[q][k][1]);
				if(bottomMesh){
					bottomMesh.vertices[v]=position(k)+Vector3f(0.0f,0.0f,-mapDepth);
					bottomMesh.normals[v]=-normals[k];
					bottomMesh.coords[v]=coord(k);
					bottomMesh.texcoords[v]=Vector2f(fallingLandChunkTexcoords[q][k][0],1);
				}
			}
			mesh.indices[0]=[0,1,2];
			B.finalizeTerrainMesh(mesh);
			result.topMeshes[q]=mesh;
			if(bottomMesh){
				bottomMesh.indices[0]=[0,2,1];
				B.finalizeTerrainMesh(bottomMesh);
				result.bottomMeshes[q]=bottomMesh;
			}
			numTriangles++;
		}
		Array!Vector3f edgeVertices;
		Array!Vector3f edgeNormals;
		Array!Vector2f edgeCoords;
		Array!Vector2f edgeTexcoords;
		Array!(uint[3]) edgeFaces;
		foreach(t1;0..numTriangles){
			foreach(v;0..3){
				auto a=triangles[t1][v],b=triangles[t1][(v+1)%3];
				bool boundary=true;
				foreach(t2;0..numTriangles){
					if(t1==t2) continue;
					foreach(w;0..3){
						if(triangles[t2][w]==b&&triangles[t2][(w+1)%3]==a){
							boundary=false;
							break;
						}
					}
					if(!boundary) break;
				}
				if(!boundary) continue;
				auto off=to!uint(edgeVertices.length);
				edgeVertices~=position(a);
				edgeVertices~=position(b);
				edgeVertices~=position(b)+Vector3f(0.0f,0.0f,-mapDepth);
				edgeVertices~=position(a)+Vector3f(0.0f,0.0f,-mapDepth);
				auto normal=cross(edgeVertices[off+2]-edgeVertices[off+3],edgeVertices[off+1]-edgeVertices[off+3]);
				foreach(k;0..4) edgeNormals~=normal.normalized;
				edgeCoords~=coord(a);
				edgeCoords~=coord(b);
				edgeCoords~=coord(b);
				edgeCoords~=coord(a);
				edgeTexcoords~=Vector2f(0,0);
				edgeTexcoords~=Vector2f(1,0);
				edgeTexcoords~=Vector2f(1,1);
				edgeTexcoords~=Vector2f(0,1);
				uint[3] f0=[off+0,off+2,off+1],f1=[off+2,off+0,off+3];
				edgeFaces~=f0;
				edgeFaces~=f1;
			}
		}
		if(edgeFaces.length){
			auto edgeMesh=B.makeTerrainMesh(edgeVertices.length,edgeFaces.length);
			edgeMesh.vertices[]=edgeVertices.data;
			edgeMesh.normals[]=edgeNormals.data;
			edgeMesh.coords[]=edgeCoords.data;
			edgeMesh.texcoords[]=edgeTexcoords.data;
			edgeMesh.indices[]=edgeFaces.data;
			B.finalizeTerrainMesh(edgeMesh);
			result.edgeMesh=edgeMesh;
		}
		return result;
	}

	void updateFallingLandChunkMeshes(T)(T chunks){
		for(int k=0;k<fallingLandChunkMeshes.length;){
			bool found=false;
			foreach(ref chunk;chunks){
				if(chunk.vertexI==fallingLandChunkMeshes[k].vertexI&&chunk.vertexJ==fallingLandChunkMeshes[k].vertexJ&&chunk.spawnFrame==fallingLandChunkMeshes[k].spawnFrame){
					found=true;
					break;
				}
			}
			if(found){
				k++;
				continue;
			}
			foreach(mesh;fallingLandChunkMeshes[k].topMeshes) if(mesh) B.destroyTerrainMesh(mesh);
			foreach(mesh;fallingLandChunkMeshes[k].bottomMeshes) if(mesh) B.destroyTerrainMesh(mesh);
			if(fallingLandChunkMeshes[k].edgeMesh) B.destroyTerrainMesh(fallingLandChunkMeshes[k].edgeMesh);
			if(k+1<fallingLandChunkMeshes.length) fallingLandChunkMeshes[k]=fallingLandChunkMeshes[$-1];
			fallingLandChunkMeshes.length=fallingLandChunkMeshes.length-1;
		}
		foreach(ref chunk;chunks){
			bool found=false;
			foreach(ref cached;fallingLandChunkMeshes){
				if(cached.vertexI==chunk.vertexI&&cached.vertexJ==chunk.vertexJ&&cached.spawnFrame==chunk.spawnFrame){
					found=true;
					break;
				}
			}
			if(found) continue;
			fallingLandChunkMeshes~=makeFallingLandChunkMesh(enableMapBottom,chunk.vertexI,chunk.vertexJ,chunk.spawnFrame,chunk.presentMask,chunk.heights,chunk.normals);
		}
	}

	Tuple!(int,"j",int,"i") getTile(Vector3f pos)@nogc{
		return tuple!("j","i")(cast(int)(pos.y/10),cast(int)(pos.x/10));
	}
	Vector3f getVertex(T)(int j,int i,T displacement)@nogc{
		return Vector3f(10.0f*i,10.0f*j,heights[max(0,min(j,cast(int)$-1))][max(0,min(i,cast(int)$-1))]+displacement(i,j));
	}
	Tuple!(Tuple!(int,"j",int,"i")[3][2],"tri",int,"nt") getTriangles(bool invert=false)(int j,int i)@nogc{
		if(i<0||i+1>=n||j<0||j+1>=m) return typeof(return).init;
		Tuple!(int,"j",int,"i")[3][2] tri;
		int nt=0;
		void makeTri(int[] idx)()@nogc{
			static immutable indices=idx;
			foreach(k,ref x;tri[nt++]){
				x=tuple!("j","i")(j+dj(indices[k]),i+di(indices[k]));
			}
		}
		static if(!invert){
			if(!edges[j][i]){
				if(!edges[j+1][i+1]&&!edges[j][i+1]) makeTri!([0,1,2]);
			}else if(!edges[j][i+1]&&!edges[j+1][i+1]&&!edges[j+1][i]) makeTri!([1,2,3]);
			if(!edges[j+1][i+1]){
				if(!edges[j][i]&&!edges[j+1][i]) makeTri!([2,3,0]);
			}else if(!edges[j][i]&&!edges[j][i+1]&&!edges[j+1][i]) makeTri!([0,1,3]);
		}else{
			if(edges[j][i]){
				if(!edges[j+1][i+1]&&!edges[j][i+1]) makeTri!([2,3,0]);
			}else if(!edges[j][i+1]&&!edges[j+1][i+1]&&!edges[j+1][i]) makeTri!([0,1,3]);
			if(!edges[j+1][i+1]){
				if(!edges[j][i]&&!edges[j+1][i]) makeTri!([0,1,2]);
			}else if(!edges[j][i]&&!edges[j][i+1]&&!edges[j+1][i]) makeTri!([1,2,3]);
			if(nt==0){
				makeTri!([0,1,2]);
				makeTri!([2,3,0]);
			}
		}
		return tuple!("tri","nt")(tri,nt);
	}
	Plane getPlane(T)(Tuple!(int,"j",int,"i")[3] tri,T displacement)@nogc{
		static foreach(i;0..3)
			mixin(text(`auto p`,i,`=getVertex(tri[`,i,`].expand,displacement);`));
		Plane plane;
		plane.fromPoints(p0,p1,p2); // wtf.
		return plane;
	}
	bool isInside(Tuple!(int,"j",int,"i")[3] tri,Vector3f pos)@nogc{
		Vector3f getV(int k){
			auto v=getVertex(tri[k%$].j,tri[k%$].i,ZeroDisplacement())-pos;
			v.z=0;
			return v;
		}
		foreach(k;0..3){
			if(!(cross(getV(k),getV(k+1)).z>=0))
				return false;
		}
		return true;
	}
	Tuple!(int,"j",int,"i")[3] getTriangle(bool invert=false)(Vector3f pos)@nogc{
		auto tile=getTile(pos);
		int i=tile.i,j=tile.j;
		auto triNt=getTriangles!invert(j,i),tri=triNt[0],nt=triNt[1];
		if(nt==0) return typeof(return).init;
		if(!invert){
			if(isInside(tri[0],pos)) return tri[0]; // TODO: fix precision issues, by using fixed-point and splitting at line
			else if(nt==2) return tri[1];
			else return typeof(return).init;
		}else{
			if(nt==1||!isInside(tri[1],pos)) return tri[0];
			else return tri[1];
		}
	}

	bool isOnGround(Vector3f pos)@nogc{
		auto triangle=getTriangle(pos);
		return triangle[0]!=triangle[1];
	}
	private float getHeightImpl(T)(Tuple!(int,"j",int,"i")[3] triangle,Vector3f pos,T displacement)@nogc{
		auto plane=getPlane(triangle,displacement);
		return -(plane.a*pos.x+plane.b*pos.y+plane.d)/plane.c;
	}
	float getHeight(T)(Vector3f pos,T displacement)@nogc{
		auto triangle=getTriangle(pos);
		if(triangle[0]==triangle[1]) triangle=getTriangle!true(pos);
		if(triangle[0]==triangle[1]) return 0.0f;
		return getHeightImpl(triangle,pos,displacement);
	}
	float getGroundHeight(T)(Vector3f pos,T displacement)@nogc{
		auto triangle=getTriangle(pos);
		return getHeightImpl(triangle,pos,displacement);
	}
	float getGroundHeightDerivative(T)(Vector3f pos,Vector3f direction,T displacement)@nogc{
		auto triangle=getTriangle(pos);
		static foreach(i;0..3)
			mixin(text(`auto p`,i,`=getVertex(triangle[`,i,`].expand,displacement);`));
		Plane plane;
		plane.fromPoints(p0,p1,p2); // wtf.
		return -(plane.a*direction.x+plane.b*direction.y)/plane.c;
	}
	Vector3f moveOnGround(T)(Vector3f position,Vector3f direction,T displacement)@nogc in{
		assert(isOnGround(position));
	}do{
		auto newPosition=position+direction;
		if(isOnGround(newPosition)){
			newPosition.z=getGroundHeight(newPosition,displacement);
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
		bestNewPosition.z=getGroundHeight(bestNewPosition,displacement);
		return bestNewPosition;
	}
	float rayIntersection(T)(Vector3f start,Vector3f direction,T displacement,float limit=float.infinity)@nogc{
		float result=float.infinity;
		auto tile=getTile(start);
		int dj=direction.y<0?-1:1, di=direction.x<0?-1:1;
		float current=0.0f;
		while(current<=limit&&current<result&&(dj<0?tile.j>=0:tile.j<n)&&(di<0?tile.i>=0:tile.i<m)){
			auto trianglesNt=getTriangles(tile.expand),triangles=trianglesNt[0],nt=trianglesNt[1];
			foreach(k;0..nt){
				auto plane=getPlane(triangles[k],displacement);
				auto t=-plane.distance(start)/plane.dot(direction);
				if(0<=t&&t<=limit&&t<result){
					auto intersectionPoint=start+t*direction;
					if(isInside(triangles[k],intersectionPoint))
						result=t;
				}
			}
			auto next=getVertex(tile.j+(dj==1),tile.i+(di==1),displacement);
			auto tj=(next.y-start.y)/direction.y;
			auto ti=(next.x-start.x)/direction.x;
			if(isNaN(ti)||tj<ti){
				current=tj;
				tile.j+=dj;
			}else{
				current=ti;
				tile.i+=di;
			}
		}
		return result;
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
	auto r=iota(0,7).until!(i=>!fileExists(buildPath(directory,format("DT%02d.TXTR",i)))).map!(i=>loadTXTR(buildPath(directory,format("DT%02d.TXTR",i)))).array;
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
			if(!fileExists(maptFile)) return img;
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

int di(int k)@nogc{ return k==1||k==2; }
int dj(int k)@nogc{ return k==2||k==3; }
void getFaces(O)(bool[][] edges,int j,int i,O o){
	if(!edges[j][i]){
		if(!edges[j+1][i+1]&&!edges[j][i+1]) o.put([0,1,2]);
	}else if(!edges[j][i+1]&&!edges[j+1][i+1]&&!edges[j+1][i]) o.put([1,2,3]);
	if(!edges[j+1][i+1]){
		if(!edges[j][i]&&!edges[j+1][i]) o.put([2,3,0]);
	}else if(!edges[j][i]&&!edges[j][i+1]&&!edges[j+1][i]) o.put([0,1,3]);
}
Vector3f getVertex(int n,int m,float[][] heights,int j,int i){ return Vector3f(10*i,10*j,heights[j][i]); }
Vector2f getVertex2D(int n,int m,int j,int i){ return Vector2f(10*i,10*j); }

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

Vector3f computeVertexNormal(int n,int m,bool[][] edges,float[][] heights,int j,int i){
	Vector3f normal=Vector3f(0,0,0);
	foreach(tj;max(0,j-1)..min(n-1,j+1)){
		foreach(ti;max(0,i-1)..min(m-1,i+1)){
			struct ProcessFaces{
				void put(uint[3] f){
					Vector3f[3] v;
					foreach(k;0..3)
						v[k]=getVertex(n,m,heights,tj+dj(f[k]),ti+di(f[k]));
					Vector3f p=cross(v[1]-v[0],v[2]-v[0]);
					foreach(k;0..3)
						if(tj+dj(f[k])==j&&ti+di(f[k])==i)
							normal+=p;
				}
			}
			getFaces(edges,tj,ti,ProcessFaces());
		}
	}
	if(normal.lengthsqr==0.0f) return Vector3f(0.0f,0.0f,1.0f);
	return normal.normalized;
}

bool edgeWallExists(int n,int m,bool[][] edges,int j,int i,int slot)@nogc{
	final switch(slot){
		case 0: return (!j||edges[j-1][i]&&edges[j-1][i+1])&&!edges[j][i]&&!edges[j][i+1]&&(!edges[j+1][i]||!edges[j+1][i+1]);
		case 1: return (j+1==n-1||edges[j+2][i+1]&&edges[j+2][i])&&!edges[j+1][i+1]&&!edges[j+1][i]&&(!edges[j][i]||!edges[j][i+1]);
		case 2: return (!i||edges[j+1][i-1]&&edges[j][i-1])&&!edges[j+1][i]&&!edges[j][i]&&(!edges[j+1][i+1]||!edges[j][i+1]);
		case 3: return (i+1==m-1||edges[j][i+2]&&edges[j+1][i+2])&&!edges[j][i+1]&&!edges[j+1][i+1]&&(!edges[j][i]||!edges[j+1][i]);
		case 4: return edges[j][i+1]&&!edges[j][i]&&!edges[j+1][i+1]&&!edges[j+1][i];
		case 5: return edges[j+1][i+1]&&!edges[j][i+1]&&!edges[j+1][i]&&!edges[j][i];
		case 6: return edges[j+1][i]&&!edges[j+1][i+1]&&!edges[j][i]&&!edges[j][i+1];
		case 7: return edges[j][i]&&!edges[j+1][i]&&!edges[j][i+1]&&!edges[j+1][i+1];
	}
}
void appendEdgeWall(V,N,C,T,F)(int n,int m,bool[][] edges,float[][] heights,int j,int i,int slot,
                    ref V edgeVertices,ref N edgeNormals,ref C edgeCoords,ref T edgeTexcoords,ref F edgeFaces){
	if(!edgeWallExists(n,m,edges,j,i,slot)) return;
	int x1,y1,x2,y2;
	final switch(slot){
		case 0: x1=i;   y1=j;   x2=i+1; y2=j;   break;
		case 1: x1=i+1; y1=j+1; x2=i;   y2=j+1; break;
		case 2: x1=i;   y1=j+1; x2=i;   y2=j;   break;
		case 3: x1=i+1; y1=j;   x2=i+1; y2=j+1; break;
		case 4: x1=i;   y1=j;   x2=i+1; y2=j+1; break;
		case 5: x1=i+1; y1=j;   x2=i;   y2=j+1; break;
		case 6: x1=i+1; y1=j+1; x2=i;   y2=j;   break;
		case 7: x1=i;   y1=j+1; x2=i+1; y2=j;   break;
	}
	Vector3f getVertex(int j,int i){ return .getVertex(n,m,heights,j,i); }
	auto off=to!uint(edgeVertices.length);
	edgeVertices~=getVertex(y1,x1);
	edgeVertices~=getVertex(y2,x2);
	edgeVertices~=getVertex(y2,x2)+Vector3f(0,0,-mapDepth);
	edgeVertices~=getVertex(y1,x1)+Vector3f(0,0,-mapDepth);
	auto normal=cross(edgeVertices[off+2]-edgeVertices[off+3],edgeVertices[off+1]-edgeVertices[off+3]);
	foreach(k;0..4) edgeNormals~=normal.normalized;
	edgeCoords~=Vector2f(x1,y1)/256.0;
	edgeCoords~=Vector2f(x2,y2)/256.0;
	edgeCoords~=Vector2f(x2,y2)/256.0;
	edgeCoords~=Vector2f(x1,y1)/256.0;
	edgeTexcoords~=Vector2f(0,0);
	edgeTexcoords~=Vector2f(1,0);
	edgeTexcoords~=Vector2f(1,1);
	edgeTexcoords~=Vector2f(0,1);
	uint[3] f0=[off+0,off+2,off+1],f1=[off+2,off+0,off+3];
	edgeFaces~=f0;
	edgeFaces~=f1;
}

Tuple!(uint[],uint[]) getVertexAndFaceCount(int n,int m,bool[][] edges,ubyte[][] tiles,bool addBottom=false){
	auto numVertices=new uint[](257);
	auto numFaces=new uint[](257);
	foreach(j;0..n-1){
		foreach(i;0..m-1){
			auto t=tiles[j][i];
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

B.TerrainMesh[] createMeshes(B)(bool[][] edges, float[][] heights, ubyte[][] tiles, bool addBottom, ref TerrainTileMeshInfo[] tileMeshInfos, ref EdgeWallSlotInfo[] edgeWallSlots){
	//foreach(e;edges) e[]=false;
	auto n=to!int(edges.length);
	enforce(n);
	auto m=to!int(edges[0].length);
	enforce(heights.length==n);
	enforce(edges.all!(x=>x.length==m));
	enforce(heights.all!(x=>x.length==m));
	tileMeshInfos.length=(n-1)*(m-1);
	edgeWallSlots.length=(n-1)*(m-1);
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
			auto t=tiles[j][i];
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
			auto tileMeshInfo=&tileMeshInfos[j*(m-1)+i];
			tileMeshInfo.vertexOffset=curVertex[t];
			tileMeshInfo.faceOffset=curFace[t];
			tileMeshInfo.numFaces=cast(ubyte)faces;
			if(addBottom){
				tileMeshInfo.bottomVertexOffset=curVertex[bottomIndex];
				tileMeshInfo.bottomFaceOffset=curFace[bottomIndex];
			}
			foreach(k;0..4){
				meshes[t].vertices[curVertex[t]+k]=getVertex(j+dj(k),i+di(k));
				meshes[t].normals[curVertex[t]+k]=normals[j+dj(k)][i+di(k)];
				meshes[t].coords[curVertex[t]+k]=Vector2f(i+di(k),j+dj(k))/256.0f;
				meshes[t].texcoords[curVertex[t]+k]=Vector2f(di(k),dj(k));
				if(addBottom){
					meshes[bottomIndex].vertices[curVertex[bottomIndex]+k]=getVertex(j+dj(k),i+di(k))+Vector3f(0,0,-mapDepth);
					meshes[bottomIndex].normals[curVertex[bottomIndex]+k]=-normals[j+dj(k)][i+di(k)];
					meshes[bottomIndex].coords[curVertex[bottomIndex]+k]=Vector2f(i+di(k),j+dj(k))/256.0f;
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
			foreach(slot;0..8){
				auto faceOffset=to!uint(edgeFaces.length);
				appendEdgeWall(n,m,edges,heights,j,i,slot,edgeVertices,edgeNormals,edgeCoords,edgeTexcoords,edgeFaces);
				if(edgeFaces.length>faceOffset)
					edgeWallSlots[j*(m-1)+i].faceOffsets[slot]=faceOffset;
			}
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

B.MinimapMesh[] createMinimapMeshes(B)(bool[][] edges, ubyte[][] tiles, ref MinimapTileMeshInfo[] tileMeshInfos){
	//foreach(e;edges) e[]=false;
	auto n=to!int(edges.length);
	enforce(n);
	auto m=to!int(edges[0].length);
	enforce(edges.all!(x=>x.length==m));
	tileMeshInfos.length=(n-1)*(m-1);
	Vector2f getVertex(int j,int i){ return .getVertex2D(n,m,j,i); }
	void getFaces(O)(int j,int i,O o){ .getFaces(edges,j,i,o); }
	auto numVerticesNumFaces=getVertexAndFaceCount(n,m,edges,tiles); // TODO: share with createMeshes?
	auto numVertices=numVerticesNumFaces[0], numFaces=numVerticesNumFaces[1];
	auto curVertex=new uint[](numMapMeshes-1);
	auto curFace=new uint[](numMapMeshes-1);
	auto meshes=new B.MinimapMesh[](numMapMeshes);
	foreach(j;0..n-1){
		foreach(i;0..m-1){
			auto t=tiles[j][i];
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
			auto tileMeshInfo=&tileMeshInfos[j*(m-1)+i];
			tileMeshInfo.vertexOffset=curVertex[t];
			tileMeshInfo.faceOffset=curFace[t];
			tileMeshInfo.numFaces=cast(ubyte)faces;
			foreach(k;0..4){
				meshes[t].vertices[curVertex[t]+k]=getVertex(j+dj(k),i+di(k));
				meshes[t].texcoords[curVertex[t]+k]=Vector2f(di(k),dj(k));
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
