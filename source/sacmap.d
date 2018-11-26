import dagon;
import util;
import maps,txtr,ntts,envi;
import std.exception, std.string, std.algorithm, std.conv, std.range;
import std.stdio, std.path, std.file;
import std.typecons: tuple,Tuple;
import std.math;

import sacobject;

class SacMap{ // TODO: make this an entity
	TerrainMesh[] meshes;
	Texture[] textures;
	Texture[] details;
	Texture color;
	ubyte[] dti;
	int n,m;
	bool[][] edges;
	float[][] heights;
	ubyte[][] tiles;
	Envi envi;

	SacObject[] ntts;

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
		string land;
		final switch(detectTileset(filename[0..$-".HMAP".length]~".LEVL")) with(Tileset){
			case ethereal: land="extracted/ethr/ethr.WAD!/ethr.LAND"; break; // TODO
			case persephone: land="extracted/prsc/prsc.WAD!/prsc.LAND"; break;
			case pyro: land="extracted/pyro_a/PY_A.WAD!/PY_A.LAND"; break;
			case james: land="extracted/james_a/JA_A.WAD!/JA_A.LAND"; break;
			case stratos: land="extracted/strato_a/ST_A.WAD!/ST_A.LAND"; break;
			case charnel: land="extracted/char/char.WAD!/char.LAND"; break;
		}
		dti=loadDTIndex(land).dts;
		static Texture makeTexture(SuperImage i,GLuint repeat=GL_MIRRORED_REPEAT){
			auto texture=New!Texture(null); // TODO: set owner
			texture.image=i;
			texture.createFromImage(texture.image,true,repeat);
			return texture;
		}
		auto mapts=loadMAPTs(land);
		auto bumps=loadDTs(land);
		auto edge=loadTXTR(buildPath(land,chain(retro(envi.edge[]),".TXTR").to!string));
		//auto sky_=loadTXTR(buildPath(land,chain(retro(envi.sky_[]),".TXTR").to!string)); // TODO: smk files
		auto sky_=loadTXTR(buildPath(land,"SKY_.TXTR"));
		auto skyb=loadTXTR(buildPath(land,chain(retro(envi.skyb[]),".TXTR").to!string));
		auto skyt=loadTXTR(buildPath(land,chain(retro(envi.skyt[]),".TXTR").to!string));
		auto sun_=loadTXTR(buildPath(land,chain(retro(envi.sun_[]),".TXTR").to!string));
		auto undr=loadTXTR(buildPath(land,chain(retro(envi.undr[]),".TXTR").to!string));
		auto repeatMode=iota(256+6).map!(i=>i==257?GL_REPEAT:GL_MIRRORED_REPEAT);
		textures=zip(chain(mapts,only(edge,sky_,skyb,skyt,sun_,undr)),repeatMode).map!(x=>makeTexture(x.expand)).array;
		details=bumps.map!makeTexture.array;
		auto lmap=loadLMap(filename[0..$-".HMAP".length]~".LMAP");
		color=makeTexture(lmap);
		auto ntts=loadNTTs(filename[0..$-".HMAP".length]~".NTTS");
		/+import std.algorithm;
		writeln("#widgets: ",ntts.widgetss.map!(x=>x.num).sum);+/
		foreach(ref structure;ntts.structures)
			placeStructure(structure);
		foreach(ref wizard;ntts.wizards)
			placeNTT(wizard);
		foreach(ref creature;ntts.creatures)
			placeNTT(creature);
		/+foreach(widgets;ntts.widgetss) // TODO: improve engine to be able to handle this
			placeWidgets(land,widgets);+/
		meshes=createMeshes(hmap,tmap);
	}

	private struct Sky{
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

	Entity[] skyEntities;
	void createSky(Scene s){
		/+auto eSky=s.createSky();
		eSky.rotation=rotationQuaternion(Axis.z,cast(float)PI)*
			rotationQuaternion(Axis.x,cast(float)(PI/2));+/
		auto x=10.0f*n/2, y=10.0f*m/2;

		//auto mesh=New!ShapeSphere(sqrt(0.5^^2+0.7^^2), 8, 4, true, s.assetManager);

		auto matSkyb = s.createMaterial(s.shadelessMaterialBackend);
		matSkyb.diffuse=textures[258];
		matSkyb.blending=Transparent;
		matSkyb.energy=Sky.energy;
		auto eSkyb = s.createEntity3D();
		eSkyb.castShadow = false;
		eSkyb.material = matSkyb;
		auto meshb=New!Mesh(s.assetManager);
		meshb.vertices=New!(Vector3f[])(2*(Sky.numSegs+1));
		meshb.texcoords=New!(Vector2f[])(2*(Sky.numSegs+1));
		meshb.indices=New!(uint[3][])(2*Sky.numSegs);
		foreach(i;0..Sky.numSegs+1){
			auto angle=2*PI*i/Sky.numSegs, ca=cos(angle), sa=sin(angle);
			meshb.vertices[2*i]=Vector3f(0.5*ca*0.8,0.5*sa*0.8,Sky.undrZ)*Sky.scaling;
			meshb.vertices[2*i+1]=Vector3f(0.5*ca,0.5*sa,0)*Sky.scaling;
			auto txc=cast(float)i*Sky.numTextureRepeats/Sky.numSegs;
			meshb.texcoords[2*i]=Vector2f(txc,0);
			meshb.texcoords[2*i+1]=Vector2f(txc,1);
		}
		foreach(i;0..Sky.numSegs){
			meshb.indices[2*i]=[2*i,2*i+1,2*(i+1)];
			meshb.indices[2*i+1]=[2*(i+1),2*i+1,2*(i+1)+1];
		}
		meshb.generateNormals();
		meshb.dataReady=true;
		meshb.prepareVAO();
		eSkyb.drawable = meshb;
		eSkyb.position=Vector3f(x,y,Sky.dZ*Sky.scaling+1);
		eSkyb.updateTransformation();

		auto matSkyt = s.createMaterial(s.shadelessMaterialBackend);
		matSkyt.diffuse=textures[259];
		matSkyt.blending=Transparent;
		matSkyt.energy=Sky.energy;
		auto eSkyt = s.createEntity3D();
		eSkyt.castShadow = false;
		eSkyt.material = matSkyt;
		auto mesht=New!Mesh(s.assetManager);
		mesht.vertices=New!(Vector3f[])(2*(Sky.numSegs+1));
		mesht.texcoords=New!(Vector2f[])(2*(Sky.numSegs+1));
		mesht.indices=New!(uint[3][])(2*Sky.numSegs);
		foreach(i;0..Sky.numSegs+1){
			auto angle=2*PI*i/Sky.numSegs, ca=cos(angle), sa=sin(angle);
			mesht.vertices[2*i]=Vector3f(0.5*ca,0.5*sa,0)*Sky.scaling;
			mesht.vertices[2*i+1]=Vector3f(0.5*ca,0.5*sa,Sky.skyZ)*Sky.scaling;
			auto txc=cast(float)i*Sky.numTextureRepeats/Sky.numSegs;
			mesht.texcoords[2*i]=Vector2f(txc,1);
			mesht.texcoords[2*i+1]=Vector2f(txc,0);
		}
		foreach(i;0..Sky.numSegs){
			mesht.indices[2*i]=[2*i,2*i+1,2*(i+1)];
			mesht.indices[2*i+1]=[2*(i+1),2*i+1,2*(i+1)+1];
		}
		mesht.generateNormals();
		mesht.dataReady=true;
		mesht.prepareVAO();
		eSkyt.drawable = mesht;
		eSkyt.position=Vector3f(x,y,Sky.dZ*Sky.scaling+1);
		eSkyt.updateTransformation();

		auto matSun = s.createMaterial(s.sacSunMaterialBackend);
		matSun.diffuse=textures[260];
		matSun.blending=Transparent;
		matSun.energy=25.0f*Sky.energy;
		auto eSun = s.createEntity3D();
		eSun.castShadow = false;
		eSun.material = matSun;
		auto meshsu=New!Mesh(s.assetManager);
		meshsu.vertices=New!(Vector3f[])(4);
		meshsu.texcoords=New!(Vector2f[])(4);
		meshsu.indices=New!(uint[3][])(2);
		copy(iota(4).map!(i=>Vector3f((-0.5+(i==1||i==2))*0.25,(-0.5+(i==2||i==3))*0.25,Sky.skyZ)*Sky.scaling),meshsu.vertices);
		copy(iota(4).map!(i=>Vector2f((i==1||i==2),(i==2||i==3))),meshsu.texcoords);
		meshsu.indices[0]=[0,2,1];
		meshsu.indices[1]=[0,3,2];
		meshsu.generateNormals();
		meshsu.dataReady=true;
		meshsu.prepareVAO();
		eSun.drawable=meshsu;
		eSun.position=Vector3f(x,y,Sky.dZ*Sky.scaling+1);
		eSun.updateTransformation();

		auto matSky = s.createMaterial(s.sacSkyMaterialBackend);
		matSky.diffuse=textures[257];
		matSky.blending=Transparent;
		matSky.energy=Sky.energy;
		matSky.transparency=envi.maxAlphaFloat;
		auto eSky = s.createEntity3D();
		eSky.castShadow = false;
		eSky.material = matSky;
		auto meshs=New!Mesh(s.assetManager);
		meshs.vertices=New!(Vector3f[])(4);
		meshs.texcoords=New!(Vector2f[])(4);
		meshs.indices=New!(uint[3][])(2);
		copy(iota(4).map!(i=>Vector3f(-0.5+(i==1||i==2),-0.5+(i==2||i==3),Sky.skyZ*Sky.relCloudLoc)*Sky.scaling),meshs.vertices);
		copy(iota(4).map!(i=>Vector2f(4*(i==1||i==2),4*(i==2||i==3))),meshs.texcoords);
		meshs.indices[0]=[0,2,1];
		meshs.indices[1]=[0,3,2];
		meshs.generateNormals();
		meshs.dataReady=true;
		meshs.prepareVAO();
		eSky.drawable=meshs;
		eSky.position=Vector3f(x,y,Sky.dZ*Sky.scaling+1);
		eSky.updateTransformation();

		auto matUndr = s.createMaterial(s.shadelessMaterialBackend);
		matUndr.diffuse=textures[261];
		matUndr.blending=Transparent;
		matUndr.energy=Sky.energy;
		auto eUndr = s.createEntity3D();
		eUndr.castShadow = false;
		eUndr.material = matUndr;
		auto meshu=New!Mesh(s.assetManager);
		meshu.vertices=New!(Vector3f[])(4);
		meshu.texcoords=New!(Vector2f[])(4);
		meshu.indices=New!(uint[3][])(2);
		copy(iota(4).map!(i=>Vector3f((-0.5+(i==1||i==2)),(-0.5+(i==2||i==3)),Sky.undrZ)*Sky.scaling),meshu.vertices);
		copy(iota(4).map!(i=>Vector2f((i==1||i==2),(i==2||i==3))),meshu.texcoords);
		meshu.indices[0]=[0,1,2];
		meshu.indices[1]=[0,2,3];
		meshu.generateNormals();
		meshu.dataReady=true;
		meshu.prepareVAO();
		eUndr.drawable=meshu;
		eUndr.position=Vector3f(x,y,Sky.dZ*Sky.scaling+1);
		eUndr.updateTransformation();
		skyEntities=[eUndr,eSkyb,eSkyt,eSky,eSun];
	}

	void rotateSky(Quaternionf rotation){
		foreach(e;skyEntities[0..3]){
			e.rotation=rotation;
			e.updateTransformation();
		}
	}

	void setupEnvironment(Scene s){
		auto env=s.environment;
		//writeln(envi.sunDirectStrength," ",envi.sunAmbientStrength);
		env.sunEnergy=12.0f*(envi.sunDirectStrength+envi.sunAmbientStrength+max(0,7*log(envi.sunAmbientStrength)/log(2)));
		Color4f fixColor(Color4f sacColor){
			return Color4f(1,1,1,1)*0.2+sacColor*0.8;
		}
		//env.ambientConstant = fixColor(Color4f(envi.ambientRed*ambi,envi.ambientGreen*ambi,envi.ambientBlue*ambi,1.0f));
		auto ambi=envi.sunAmbientStrength;
		env.ambientConstant = fixColor(Color4f(envi.sunColorRed/255.0f*ambi,envi.sunColorGreen/255.0f*ambi,envi.sunColorBlue/255.0f*ambi,1.0f));
		env.backgroundColor = Color4f(envi.skyRed/255.0f,envi.skyGreen/255.0f,envi.skyBlue/255.0f,1.0f);
		// envi.minAlphaInt, envi.maxAlphaInt, envi.minAlphaFloat ?
		// envi.maxAlphaFloat used for sky alpha
		// sky_, skyt, skyb, sun_, undr used above
		// envi.shadowStrength ?
		auto sunDirection=Vector3f(envi.sunDirectionX,envi.sunDirectionY,envi.sunDirectionZ);
		sunDirection.z=abs(sunDirection.z); // TODO: support something like the effect you get in Sacrifice when setting sun direction from below
		//sunDirection.z=max(0.7,sunDirection.z);
		//sunDirection=sunDirection.normalized(); // TODO: why are sun directions in standard maps so extreme?
		env.sunRotation=rotationBetween(Vector3f(0,0,1),sunDirection);
		//env.sunColor=fixColor(Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f));
		//env.sunColor=Color4f(envi.ambientRed/255.0f,envi.ambientGreen/255.0f,envi.ambientBlue/255.0f,1.0f);
		// TODO: figure this out
		env.sunColor=(exp(envi.sunDirectStrength)*Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f)+exp(4*min(10,envi.sunAmbientStrength^^10))*Color4f(envi.ambientRed/255.0f,envi.ambientGreen/255.0f,envi.ambientBlue/255.0f,1.0f))/(exp(envi.sunDirectStrength)+exp(4*min(10,envi.sunAmbientStrength^^10)));
		/+if(envi.sunAmbientStrength>=envi.sunDirectStrength){
			env.sunColor=(exp(envi.sunDirectStrength)*Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f)+exp(4*envi.sunAmbientStrength)*Color4f(envi.ambientRed/255.0f,envi.ambientGreen/255.0f,envi.ambientBlue/255.0f,1.0f))/(exp(envi.sunDirectStrength)+exp(4*envi.sunAmbientStrength));
		}else{
			env.sunColor=(exp(4*envi.sunDirectStrength)*Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f)+exp(envi.sunAmbientStrength)*Color4f(envi.ambientRed/255.0f,envi.ambientGreen/255.0f,envi.ambientBlue/255.0f,1.0f))/(exp(4*envi.sunDirectStrength)+exp(envi.sunAmbientStrength));
		}+/
		// envi.sunFullbrightRed, envi.sunFullbrightGreen, envi.sunFullbrightBlue?
		// landscapeSpecularity, specularityRed, specularityGreen, specularityBlue and
		// landscapeGlossiness used for terrain material.
		//env.atmosphericFog=true;
		env.fogColor=Color4f(envi.fogRed/255.0f,envi.fogGreen/255.0f,envi.fogBlue/255.0f,1.0f);
		// fogType ?
		//env.fogStart=envi.fogNearZ;
		//env.fogEnd=envi.fogFarZ;
		// fogDensity?
	}

	void createEntities(Scene s,bool sky=true){
		setupEnvironment(s);
		if(sky) createSky(s);
		foreach(i,mesh;meshes){
			if(!mesh) continue;
			auto obj=s.createEntity3D();
			obj.drawable = mesh;
			obj.position = Vector3f(0, 0, 0);
			obj.updateTransformation();
			auto mat=s.createMaterial(s.terrainMaterialBackend);
			assert(!!textures[i]);
			mat.diffuse=textures[i];
			if(i<dti.length){
				assert(!!details[dti[i]]);
				mat.detail=details[dti[i]];
			}else mat.detail=0;
			mat.color=color;
			auto specu=envi.landscapeSpecularity;
			mat.specular=Color4f(specu*envi.specularityRed/255.0f,specu*envi.specularityGreen/255.0f,specu*envi.specularityBlue/255.0f);
			//mat.roughness=1.0f-envi.landscapeGlossiness;
			mat.roughness=1.0f;
			mat.metallic=0.0f;
			mat.emission=textures[i];
			mat.energy=0.05;
			obj.material=mat;
			obj.shadowMaterial=s.shadowMap.sm;
		}
		foreach(i,ntt;ntts){
			ntt.createEntities(s);
		}
	}

	static SacObject[string] objects;
	SacObject loadObject(string filename, float scaling=1.0f, float zfactorOverride=float.nan){
		SacObject obj;
		if(filename !in objects){
			obj=new SacObject(null, filename, scaling);
			if(obj.isSaxs&&!isNaN(zfactorOverride)) obj.saxsi.saxs.zfactor=zfactorOverride;
			objects[filename]=obj;
		}else obj=objects[filename];
		return obj;
	}
	private void placeStructure(ref Structure ntt){
		import nttData;
		auto data=ntt.retroKind in bldgs;
		enforce(!!data);
		auto position=Vector3f(ntt.x,ntt.y,ntt.z);
		auto ci=cast(int)(position.x/10+0.5);
		auto cj=cast(int)(position.y/10+0.5);
		import bldg;
		if(data.flags&BldgFlags.ground){
			auto ground=data.ground;
			foreach(j;max(0,cj-4)..min(n,cj+4)){
				foreach(i;max(0,ci-4)..min(m,ci+4)){
					auto dj=j-(cj-4), di=i-(ci-4);
					if(ground[dj][di])
						tiles[j][i]=ground[dj][di];
				}
			}
		}
		foreach(ref component;data.components){
			auto offset=Vector3f(component.x,component.y,component.z);
			offset=rotate(facingQuaternion(ntt.facing), offset);
			auto cposition=position+offset;
			if(!isOnGround(cposition)) continue;
			cposition.z=getGroundHeight(cposition);
			auto curObj=loadObject(bldgModls[component.retroModel]);
			auto obj=new SacObject(null,curObj);
			obj.position=cposition;
			obj.rotation=facingQuaternion(ntt.facing+component.facing);
			ntts~=obj;
		}
	}

	private void placeNTT(T)(ref T ntt) if(__traits(compiles, (T t)=>t.retroKind)){
		import nttData;
		static if(is(T==Creature)||is(T==Wizard))
			auto data=creatureDataByTag(ntt.retroKind);
		if(!data) return;
		auto curObj=loadObject(buildPath("extracted",data.model),data.scaling,data.zfactorOverride);
		auto obj=new SacObject(null,curObj);
		if(data.stance.length) obj.loadAnimation(buildPath("extracted",data.stance),data.scaling);
		auto position=Vector3f(ntt.x,ntt.y,ntt.z);
		if(!isOnGround(position)) return; // TODO
		position.z=getGroundHeight(position);
		obj.rotation=rotationQuaternion(Axis.z,cast(float)(2*PI/360*ntt.facing))*obj.rotation;
		obj.position=position;
		ntts~=obj;
	}
	private void placeWidgets(string land,Widgets w){
		auto name=w.retroName[].retro.to!string;
		auto filename=buildPath(land,name~".WIDC",name~".WIDG");
		auto curObj=loadObject(filename);
		foreach(pos;w.positions){
			auto position=Vector3f(pos[0],pos[1],0);
			if(!isOnGround(position)) continue;
			position.z=getGroundHeight(position);
			auto obj=new SacObject(null,curObj);
			// original engine screws up widget rotations
			// values look like angles in degrees, but they are actually radians
			obj.rotation=rotationQuaternion(Axis.z,cast(float)(-pos[2]));
			obj.position=position;
			ntts~=obj;
		}
	}

	Tuple!(int,"j",int,"i") getTile(Vector3f pos){
		return tuple!("j","i")(cast(int)(n-1-pos.y/10),cast(int)(pos.x/10));
	}
	Vector3f getVertex(int j,int i){
		return Vector3f(10*i,10*(n-1-j),heights[j][i]/100);
	}

	Tuple!(int,"j",int,"i")[3] getTriangle(Vector3f pos){
		auto tile=getTile(pos);
		int i=tile.i,j=tile.j;
		if(i<0||i>=n-1||j<0||j>=m-1) return typeof(return).init;
		Tuple!(int,"j",int,"i")[3][2] tri;
		int nt=0;
		int di(int i){ return i==1||i==2; }
		int dj(int i){ return i==2||i==3; }
		void makeTri(int[] indices)(){
			foreach(k,ref x;tri[nt++]){
				x=tuple!("j","i")(j+dj(indices[k]),i+di(indices[k]));
			}
		}
		if(!edges[j][i]){
			if(!edges[j+1][i+1]&&!edges[j][i+1]) makeTri!([0,2,1]);
		}else if(!edges[j][i+1]&&!edges[j+1][i+1]&&!edges[j+1][i]) makeTri!([1,3,2]);
		if(!edges[j+1][i+1]){
			if(!edges[j][i]&&!edges[j+1][i]) makeTri!([2,0,3]);
		}else if(!edges[j][i]&&!edges[j][i+1]&&!edges[j+1][i]) makeTri!([0,3,1]);
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
		if(isInside(tri[0])) return tri[0]; // TODO: fix precision issues, by using fixed-point and splitting at line
		else if(nt==2) return tri[1];
		else return typeof(return).init;
	}

	bool isOnGround(Vector3f pos){
		auto triangle=getTriangle(pos);
		return triangle[0]!=triangle[1];
	}
	float getGroundHeight(Vector3f pos){
		auto triangle=getTriangle(pos);
		static foreach(i;0..3)
			mixin(text(`auto p`,i,`=getVertex(triangle[`,i,`].expand);`));
		Plane plane;
		plane.fromPoints(p0,p1,p2); // wtf.
		return -(plane.a*pos.x+plane.b*pos.y+plane.d)/plane.c;
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

TerrainMesh[] createMeshes(HMap hmap, TMap tmap, float scaleFactor=1){
	auto edges=hmap.edges;
	auto heights=hmap.heights;
	auto tiles=tmap.tiles;
	//foreach(e;edges) e[]=false;
	auto n=to!int(hmap.edges.length);
	enforce(n);
	auto m=to!int(hmap.edges[0].length);
	enforce(heights.length==n);
	enforce(edges.all!(x=>x.length==m));
	enforce(heights.all!(x=>x.length==m));
	Vector3f getVertex(int j,int i){
		return scaleFactor*Vector3f(10*i,10*(n-1-j),heights[j][i]/100);
	}
	int di(int i){ return i==1||i==2; }
	int dj(int i){ return i==2||i==3; }
	auto getFaces(O)(int j,int i,O o){
		if(!edges[j][i]){
			if(!edges[j+1][i+1]&&!edges[j][i+1]) o.put([0,2,1]);
		}else if(!edges[j][i+1]&&!edges[j+1][i+1]&&!edges[j+1][i]) o.put([1,3,2]);
		if(!edges[j+1][i+1]){
			if(!edges[j][i]&&!edges[j+1][i]) o.put([2,0,3]);
		}else if(!edges[j][i]&&!edges[j][i+1]&&!edges[j+1][i]) o.put([0,3,1]);
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
	auto meshes=new TerrainMesh[](257);
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
	Vector3f[] edgeVertices;
	Vector3f[] edgeNormals;
	Vector2f[] edgeCoords;
	Vector2f[] edgeTexcoords;
	uint[3][] edgeFaces;
	enum mapDepth=50.0f;
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
	meshes[256]=new TerrainMesh(null);
	meshes[256].vertices=New!(Vector3f[])(edgeVertices.length);
	meshes[256].vertices[]=edgeVertices[];
	meshes[256].normals=New!(Vector3f[])(edgeNormals.length);
	meshes[256].normals[]=edgeNormals[];
	meshes[256].coords=New!(Vector2f[])(edgeCoords.length);
	meshes[256].coords[]=edgeCoords[];
	meshes[256].texcoords=New!(Vector2f[])(edgeTexcoords.length);
	meshes[256].texcoords[]=edgeTexcoords[];
	meshes[256].indices=New!(uint[3][])(edgeFaces.length);
	meshes[256].indices[]=edgeFaces[];
	foreach(mesh;meshes){
		if(!mesh) continue;
		mesh.dataReady=true;
		mesh.prepareVAO();
	}
	return meshes;
}
