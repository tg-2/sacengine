// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import dlib.math.portable;
import dlib.math.vector, dlib.math.matrix, dlib.math.quaternion, dlib.math.transformation, dlib.math.utils: Axis, degtorad;
import dlib.image.color;
import std.stdio;
import std.algorithm: min, max, among, map, filter, all, splitter, swap;
import std.range: iota, walkLength, enumerate;
import std.typecons: tuple, Tuple;
import std.conv: to;
import std.exception: enforce;
import state,sacobject,sacspell,nttData,sacmap,levl,form,sacform,sacfont;
import util;

struct Camera{
	int target=0;
	float distance=6.0f;
	float floatingHeight=2.0f;
	float zoom=0.125f;
	float targetZoom=0.125f;
	float minimapZoom=2.7f;
	float focusHeight;
	bool centering=false;
	enum rotationSpeed=0.95f*pi!float;
	enum slowRotationSpeed=0.2f*pi!float;
	float lastTargetFacing;

	int width,height;
	Vector3f position=Vector3f(1270.0f,1270.0f,2.0f);
	float turn=0.0f,pitch=-90.0f,roll=0.0f; // TODO: use radians
	float pitchOffset=0.0f;
}

struct Mouse(B){
	float x,y;
	float leftButtonX,leftButtonY;
	bool visible,showFrame;
	enum Status{
		standard,
		rectangleSelect,
		xmenu,
		icon,
	}
	bool dragging;
	bool rotating;
	Status status;
	MouseIcon icon;
	SacSpell!B spell;
	bool additiveSelect=false;
	auto cursor=Cursor.normal;
	Target target;
	Target xmenuTarget;
	SacSpell!B targetSpell;
	char[4] xmenuTargetId=0;
	char[4] xmenuCenterTargetId=0;
	char[4] xmenuMiddleTargetId=0;
	float xmenuOffsetX=0,xmenuOffsetY=0;
	int xmenuFrame;
	bool xmenuVisible=false;
	bool targetValid;
	bool inHitbox=false;
	int frame=0;
	int targetUpdateFrame=0;
	enum mouseoverBoxDelay=0.5f*updateFPS;
	Target cachedTarget;
	float cachedTargetX,cachedTargetY;
	int cachedTargetFrame;
	enum targetCacheDelta=10.0f;
	enum minimapTargetCacheDelta=2.0f;
	enum targetCacheDuration=0.6f*updateFPS;
	enum Location{
		scene,
		minimap,
		selectionRoster,
		spellbook,
	}
	Location loc;
	bool menuMode;
	@property bool onMinimap(){ return loc==Location.minimap; }
	@property bool onSelectionRoster(){ return loc==Location.selectionRoster; }
	@property bool onSpellbook(){ return loc==Location.spellbook; }
}

struct ActiveChatMessage{
	int index;
	int offset;
	int height;
	int frame;
	bool fromNetwork;
}
struct ActiveChatMessages{
	Array!ActiveChatMessage messages;
	int[2] chatMessageIndex=0;
	int chatMessageLowerBound=0;
	bool[480] occupied=false;
	int frame=0;
	void update(){ frame+=1; }
	void add(int index,int height,int topOffset,int gapSize,bool fromNetwork,int frame){
		int offset=topOffset; // TODO: delay messages instead if nothing is found
		int curGap=gapSize;
		foreach(i,x;occupied){
			if(x) curGap=0;
			else ++curGap;
			if(i>=topOffset+height&&curGap>=gapSize+height&&(i+1>=occupied.length||!occupied[i+1])){
				occupied[i-height..i]=true;
				offset=to!int(i-height);
				break;
			}
		}
		messages~=ActiveChatMessage(index,offset,height,frame,fromNetwork);
	}
	void remove(int localIndex){
		occupied[messages[localIndex].offset..min(messages[localIndex].offset+messages[localIndex].height,$)]=false;
		swap(messages[localIndex],messages[$-1]);
		messages.length=messages.length-1;
	}
	void clearSidechannelMessages(){
		for(int i=0;i<messages.length;){
			if(messages[i].fromNetwork) remove(i);
			else i++;
		}
	}
}

struct RenderInfo(B){
	int renderSlot=-1;
	int renderSide=-1;
	float hudScaling;
	int hudSoulFrame=0;
	bool hudVisible=true;
	Mouse!B mouse;
	struct MouseSparkle{
		float x,y;
		int frame=0;
	}
	Array!MouseSparkle mouseSparkles;
	Camera camera;
	int windowHeight;
	@property int width(){ return camera.width; }
	@property int height(){ return camera.height; }
	float screenScaling;
	auto spellbookTab=SpellType.creature;
	ActiveChatMessages activeChatMessages;
}

struct Renderer(B){
	SacSky!B sacSky;
	void createSky(){
		sacSky=new SacSky!B();
	}
	SacSoul!B sacSoul;
	SacGreenSoul!B sacGreenSoul=null;
	static struct SoulOpt{
		bool refuseGreenSouls;
	}
	void createSouls(SoulOpt options){
		sacSoul=new SacSoul!B();
		if(!options.refuseGreenSouls)
			sacGreenSoul=new SacGreenSoul!B();
	}
	SacObject!B sacDebris;
	SacExplosion!B createExplosion(){
		enum nU=4,nV=4;
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=1.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacExplosion!B(texture,mat,frames);
	}
	SacExplosion!B explosion;
	SacBlueRing!B createBlueRing(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=20.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacBlueRing!B(texture,mat,frames);
	}
	SacBlueRing!B blueRing;
	SacLevelUpRing!B createLevelUpRing(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=20.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacLevelUpRing!B(texture,mat,frames);
	}
	SacLevelUpRing!B levelUpRing;
	SacLevelDownRing!B createLevelDownRing(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=20.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacLevelDownRing!B(texture,mat,frames);
	}
	SacLevelDownRing!B levelDownRing;
	SacVortex!B createVortex(){
		SacVortex!B result;
		result.loadTextures();
		result.rimMeshes=typeof(return).createRimMeshes();
		result.redRimMat=B.makeMaterial(B.shadelessMaterialBackend);
		result.redRimMat.depthWrite=false;
		result.redRimMat.blending=B.Blending.Additive;
		result.redRimMat.energy=10.0f;
		result.redRimMat.diffuse=result.redRim;
		result.blueRimMat=B.makeMaterial(B.shadelessMaterialBackend);
		result.blueRimMat.depthWrite=false;
		result.blueRimMat.blending=B.Blending.Additive;
		result.blueRimMat.energy=10.0f;
		result.blueRimMat.diffuse=result.blueRim;
		result.centerMeshes=typeof(return).createCenterMeshes();
		result.redCenterMat=B.makeMaterial(B.shadelessMaterialBackend);
		result.redCenterMat.depthWrite=false;
		result.redCenterMat.blending=B.Blending.Additive;
		result.redCenterMat.energy=1.0f;
		result.redCenterMat.diffuse=result.redCenter;
		result.blueCenterMat=B.makeMaterial(B.shadelessMaterialBackend);
		result.blueCenterMat.depthWrite=false;
		result.blueCenterMat.blending=B.Blending.Additive;
		result.blueCenterMat.energy=1.0f;
		result.blueCenterMat.diffuse=result.blueCenter;
		return result;
	}
	SacVortex!B vortex;
	SacTether!B createTether(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessBoneMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=15.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacTether!B(texture,mat,frames);
	}
	SacTether!B tether;
	SacGuardianTether!B createGuardianTether(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessBoneMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=5.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacGuardianTether!B(texture,mat,frames);
	}
	SacGuardianTether!B guardianTether;
	SacLightning!B createLightning(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessBoneMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=15.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacLightning!B(texture,mat,frames);
	}
	SacLightning!B lightning;
	SacWrath!B createWrath(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=20.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacWrath!B(texture,mat,frames);
	}
	SacWrath!B wrath;
	SacCommandCone!B sacCommandCone;
	SacObject!B rock;
	SacBug!B bug;
	SacBug!B createBug(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Transparent;
		mat.energy=1.0f;
		mat.diffuse=texture;
		auto mesh=typeof(return).createMesh();
		return SacBug!B(texture,mat,mesh);
	}
	SacProtectiveBug!B protectiveBug;
	SacProtectiveBug!B createProtectiveBug(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Transparent;
		mat.energy=1.0f;
		mat.diffuse=texture;
		auto meshes=typeof(return).createMeshes();
		return SacProtectiveBug!B(texture,mat,meshes);
	}
	SacAirShield!B airShield;
	SacAirShield!B createAirShield(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Transparent;
		mat.energy=5.0f;
		mat.transparency=0.075f;
		mat.diffuse=texture;
		auto meshes=typeof(return).createMeshes;
		return SacAirShield!B(texture,mat,meshes);
	}
	SacAirShieldEffect!B airShieldEffect;
	SacAirShieldEffect!B createAirShieldEffect(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=10.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacAirShieldEffect!B(texture,mat,frames);
	}
	SacFreeze!B freeze;
	SacFreeze!B createFreeze(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Transparent;
		mat.energy=5.0f;
		mat.transparency=0.2f;
		mat.diffuse=texture;
		auto mesh=typeof(return).createMesh();
		return SacFreeze!B(texture,mat,mesh);
	}
	SacSlime!B slime;
	SacSlime!B createSlime(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.defaultMaterialBackend);
		mat.specular=Color4f(1,1,1,1);
		mat.roughness=1.0f;
		mat.metallic=0.5f;
		mat.diffuse=texture;
		auto mesh=typeof(return).createMesh();
		return SacSlime!B(texture,mat,mesh);
	}
	SacVine!B vine;
	SacVine!B createVine(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.boneMaterialBackend);
		mat.specular=Color4f(1,1,1,1);
		mat.roughness=1.0f;
		mat.metallic=0.5f;
		mat.diffuse=texture;
		auto mesh=typeof(return).createMesh();
		return SacVine!B(texture,mat,mesh);
	}
	SacRainbow!B rainbow;
	SacRainbow!B createRainbow(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessBoneMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=10.0f;
		mat.diffuse=texture;
		auto mesh=typeof(return).createMesh();
		return SacRainbow!B(texture,mat,mesh);
	}
	SacAnimateDead!B animateDead;
	SacAnimateDead!B createAnimateDead(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessBoneMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=10.0f;
		mat.diffuse=texture;
		auto meshes=typeof(return).createMeshes();
		return SacAnimateDead!B(texture,mat,meshes);
	}
	SacHellmouthProjectile!B hellmouthProjectile;
	SacHellmouthProjectile!B createHellmouthProjectile(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessBoneMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Transparent;
		mat.energy=1.0f;
		mat.diffuse=texture;
		auto mesh=typeof(return).createMesh();
		return SacHellmouthProjectile!B(texture,mat,mesh);
	}
	SacDragonfire!B dragonfire;
	SacDragonfire!B createDragonfire(){
		auto obj=typeof(return).create();
		return SacDragonfire!B(obj);
	}
	SacSoulWind!B soulWind;
	SacSoulWind!B createSoulWind(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Transparent;
		mat.energy=5.0f;
		mat.transparency=0.75f;
		mat.diffuse=texture;
		auto meshes=typeof(return).createMeshes;
		return SacSoulWind!B(texture,mat,meshes);
	}
	SacExplosionEffect!B explosionEffect;
	SacExplosionEffect!B createExplosionEffect(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=8.0f;
		mat.transparency=0.5f;
		mat.diffuse=texture;
		auto meshes=typeof(return).createMeshes;
		return SacExplosionEffect!B(texture,mat,meshes);
	}
	SacCloud!B cloud;
	SacCloud!B createCloud(){
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Transparent;
		import dlib.core.memory, dlib.image.unmanaged, dlib.image.render.shapes; // TODO: move to util?
		auto img=New!UnmanagedImageRGBA8(8, 8);
        img.fillColor(Color4f(0.0f,0.0f,0.0f,0.15f));
        auto tex=New!(B.Texture)(img, mat);
		mat.diffuse=tex;
		auto meshes=typeof(return).createMeshes;
		return SacCloud!B(mat,meshes);
	}
	SacRainFrog!B rainFrog;
	SacRainFrog!B createRainFrog(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Transparent;
		mat.energy=3.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacRainFrog!B(texture,mat,frames);
	}
	SacDemonicRiftSpirit!B demonicRiftSpirit;
	SacDemonicRiftSpirit!B createDemonicRiftSpirit(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessBoneMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=20.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacDemonicRiftSpirit!B(texture,mat,frames);
	}
	SacDemonicRiftBorder!B demonicRiftBorder;
	SacDemonicRiftBorder!B createDemonicRiftBorder(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=-3.0f;
		//mat.transparency=0.75f;
		mat.diffuse=texture;
		auto meshes=typeof(return).createMeshes;
		return SacDemonicRiftBorder!B(texture,mat,meshes);
	}
	SacDemonicRiftEffect!B demonicRiftEffect;
	SacDemonicRiftEffect!B createDemonicRiftEffect(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=20.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacDemonicRiftEffect!B(texture,mat,frames);
	}
	SacHealingAura!B healingAura;
	SacHealingAura!B createHealingAura(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=5.0f;
		mat.transparency=0.075f;
		mat.diffuse=texture;
		auto meshes=typeof(return).createMeshes;
		return SacHealingAura!B(texture,mat,meshes);
	}
	SacSpike!B createSpike(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.defaultMaterialBackend);
		mat.specular=Color4f(1,1,1,1);
		mat.roughness=1.0f;
		mat.metallic=0.5f;
		mat.diffuse=texture;
		auto mesh=typeof(return).createMesh();
		return SacSpike!B(texture,mat,mesh);
	}
	SacSpike!B spike;
	SacBrainiacEffect!B brainiacEffect;
	SacBrainiacEffect!B createBrainiacEffect(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Transparent;
		mat.energy=20.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacBrainiacEffect!B(texture,mat,frames);
	}
	SacShrikeEffect!B shrikeEffect;
	SacShrikeEffect!B createShrikeEffect(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=15.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacShrikeEffect!B(texture,mat,frames);
	}
	SacArrow!B arrow;
	SacArrow!B createArrow(){
		auto sylphTexture=typeof(return).loadSylphTexture();
		auto smat=B.makeMaterial(B.shadelessMaterialBackend);
		smat.depthWrite=false;
		smat.blending=B.Blending.Additive;
		smat.energy=30.0f;
		smat.diffuse=sylphTexture;
		auto rangerTexture=typeof(return).loadRangerTexture();
		auto rmat=B.makeMaterial(B.shadelessMaterialBackend);
		rmat.depthWrite=false;
		rmat.blending=B.Blending.Additive;
		rmat.energy=45.0f;
		rmat.diffuse=rangerTexture;
		auto frames=typeof(return).createMeshes();
		return SacArrow!B(sylphTexture,smat,rangerTexture,rmat,frames);
	}
	SacLaser!B laser;
	SacLaser!B createLaser(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessBoneMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=15.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacLaser!B(texture,mat,frames);
	}
	SacBasiliskEffect!B basiliskEffect;
	SacBasiliskEffect!B createBasiliskEffect(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=20.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacBasiliskEffect!B(texture,mat,frames);
	}
	SacTube!B tube;
	SacTube!B createTube(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=20.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacTube!B(texture,mat,frames);
	}
	SacVortexEffect!B vortexEffect;
	SacVortexEffect!B createVortexEffect(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=20.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacVortexEffect!B(texture,mat,frames);
	}
	SacSquallEffect!B squallEffect;
	SacSquallEffect!B createSquallEffect(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=20.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacSquallEffect!B(texture,mat,frames);
	}
	SacPyromaniacRocket!B pyromaniacRocket;
	SacPyromaniacRocket!B createPyromaniacRocket(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Transparent;
		mat.energy=3.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacPyromaniacRocket!B(texture,mat,frames);
	}
	SacGnomeEffect!B gnomeEffect;
	SacGnomeEffect!B createGnomeEffect(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=10.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacGnomeEffect!B(texture,mat,frames);
	}
	SacWarmongerEffect!B warmongerEffect;
	SacWarmongerEffect!B createWarmongerEffect(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=10.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacWarmongerEffect!B(texture,mat,frames);
	}
	SacPoisonDart!B poisonDart;
	SacPoisonDart!B createPoisonDart(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Transparent;
		mat.energy=3.0f;
		mat.diffuse=texture;
		auto mesh=typeof(return).createMesh();
		return SacPoisonDart!B(texture,mat,mesh);
	}
	SacLifeShield!B lifeShield;
	SacLifeShield!B createLifeShield(){
		import txtr;
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=10.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacLifeShield!B(texture,mat,frames);
	}
	SacDivineSight!B divineSight;
	SacDivineSight!B createDivineSight(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Transparent;
		mat.energy=3.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacDivineSight!B(texture,mat,frames);
	}
	SacBlightMite!B blightMite;
	SacBlightMite!B createBlightMite(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Transparent;
		mat.energy=3.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacBlightMite!B(texture,mat,frames);
	}
	SacCord!B cord;
	SacCord!B createCord(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Transparent;
		mat.energy=3.0f;
		mat.diffuse=texture;
		auto mesh=typeof(return).createMesh();
		return SacCord!B(texture,mat,mesh);
	}
	SacWeb!B web;
	SacWeb!B createWeb(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Transparent;
		mat.energy=3.0f;
		mat.diffuse=texture;
		auto mesh=typeof(return).createMesh();
		return SacWeb!B(texture,mat,mesh);
	}
	SacCage!B cage;
	SacCage!B createCage(){
		import txtr;
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=10.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacCage!B(texture,mat,frames);
	}
	SacStickyBomb!B stickyBomb;
	SacStickyBomb!B createStickyBomb(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Transparent;
		mat.energy=3.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacStickyBomb!B(texture,mat,frames);
	}
	SacOil!B oil;
	SacOil!B createOil(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Transparent;
		mat.energy=3.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacOil!B(texture,mat,frames);
	}
	SacMutantProjectile!B mutantProjectile;
	SacMutantProjectile!B createMutantProjectile(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Transparent;
		mat.energy=3.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacMutantProjectile!B(texture,mat,frames);
	}
	SacAbominationProjectile!B abominationProjectile;
	SacAbominationProjectile!B createAbominationProjectile(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Transparent;
		mat.energy=3.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacAbominationProjectile!B(texture,mat,frames);
	}
	SacBombardProjectile!B bombardProjectile;
	SacBombardProjectile!B createBombardProjectile(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=20.0f;
		mat.diffuse=texture;
		auto frames=typeof(return).createMeshes();
		return SacBombardProjectile!B(texture,mat,frames);
	}
	SacFlurryProjectile!B flurryProjectile;
	SacFlurryProjectile!B createFlurryProjectile(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=20.0f;
		mat.diffuse=texture;
		auto mesh=typeof(return).createMesh();
		return SacFlurryProjectile!B(texture,mat,mesh);
	}
	SacFlurryImplosion!B flurryImplosion;
	SacFlurryImplosion!B createFlurryImplosion(){
		auto texture=typeof(return).loadTexture();
		auto mat=B.makeMaterial(B.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=B.Blending.Additive;
		mat.energy=0.5f;
		mat.diffuse=texture;
		auto mesh=typeof(return).createMesh();
		return SacFlurryImplosion!B(texture,mat,mesh);
	}
	void createEffects(){
		import std.traits:EnumMembers;
		foreach(ptype;EnumMembers!ParticleType) SacParticle!B.get(ptype);
		sacCommandCone=new SacCommandCone!B();
		sacDebris=new SacObject!B("extracted/models/MODL.WAD!/bold.MRMC/bold.MRMM");
		enforce(sacDebris.meshes.length==1);
		explosion=createExplosion();
		blueRing=createBlueRing();
		levelUpRing=createLevelUpRing();
		levelDownRing=createLevelDownRing();
		vortex=createVortex();
		tether=createTether();
		guardianTether=createGuardianTether();
		lightning=createLightning();
		wrath=createWrath();
		rock=new SacObject!B("extracted/models/MODL.WAD!/rock.MRMC/rock.MRMM");
		enforce(rock.meshes.length==1);
		bug=createBug();
		protectiveBug=createProtectiveBug();
		airShield=createAirShield();
		airShieldEffect=createAirShieldEffect();
		freeze=createFreeze();
		spike=createSpike();
		brainiacEffect=createBrainiacEffect();
		shrikeEffect=createShrikeEffect();
		arrow=createArrow();
		laser=createLaser();
		basiliskEffect=createBasiliskEffect();
		tube=createTube();
		vortexEffect=createVortexEffect();
		squallEffect=createSquallEffect();
		pyromaniacRocket=createPyromaniacRocket();
		gnomeEffect=createGnomeEffect();
		warmongerEffect=createWarmongerEffect();
		poisonDart=createPoisonDart();
		lifeShield=createLifeShield();
		divineSight=createDivineSight();
		blightMite=createBlightMite();
		cord=createCord();
		web=createWeb();
		cage=createCage();
		stickyBomb=createStickyBomb();
		oil=createOil();
		slime=createSlime();
		vine=createVine();
		rainbow=createRainbow();
		animateDead=createAnimateDead();
		hellmouthProjectile=createHellmouthProjectile();
		dragonfire=createDragonfire();
		soulWind=createSoulWind();
		explosionEffect=createExplosionEffect();
		cloud=createCloud();
		rainFrog=createRainFrog();
		demonicRiftSpirit=createDemonicRiftSpirit();
		demonicRiftBorder=createDemonicRiftBorder();
		demonicRiftEffect=createDemonicRiftEffect();
		healingAura=createHealingAura();
		mutantProjectile=createMutantProjectile();
		abominationProjectile=createAbominationProjectile();
		bombardProjectile=createBombardProjectile();
		flurryProjectile=createFlurryProjectile();
		flurryImplosion=createFlurryImplosion();
	}

	static struct InitOpt{
		bool freetypeFonts;
		bool refuseGreenSouls;
	}
	void initialize(InitOpt options){
		createSky();
		SoulOpt soulOpt={refuseGreenSouls: options.refuseGreenSouls};
		createSouls(soulOpt);
		createEffects();
		HudOpt hudOpt={freetypeFonts: options.freetypeFonts};
		initializeHUD(hudOpt);
	}

	struct EnvOpt{
		float sunFactor;
		float ambientFactor;
		bool enableFog;
	}

	void setupEnvironment(EnvOpt options,SacMap!B map){
		auto env=B.environment; // TODO: get rid of this?
		auto envi=&map.envi;
		//writeln(envi.sunDirectStrength," ",envi.sunAmbientStrength);
		float sunStrength;
		final switch(map.tileset) with(Tileset){
			case ethereal: sunStrength=6.0f; break;
			case persephone: sunStrength=6.0f; break;
			case pyro: sunStrength=2.0f; break;
			case james: sunStrength=14.0f; break;
			case stratos: sunStrength=12.0f; break;
			case charnel: sunStrength=4.0f; break;
		}
		env.sunEnergy=min(sunStrength*envi.sunDirectStrength,30.0f)*options.sunFactor;
		static Color4f fixColor(Color4f sacColor){
			return Color4f(0,0.3,1,1)*0.2+sacColor*0.8;
		}
		//env.ambientConstant = fixColor(Color4f(envi.ambientRed*ambi,envi.ambientGreen*ambi,envi.ambientBlue*ambi,1.0f));
		auto ambi=envi.sunAmbientStrength;
		//auto ambi=1.5f*envi.sunAmbientStrength;
		//env.ambientConstant = fixColor(Color4f(envi.sunColorRed/255.0f*ambi,envi.sunColorGreen/255.0f*ambi,envi.sunColorBlue/255.0f*ambi,1.0f));
		Color4f capColor(Color4f sacColor){
			return Color4f(max(0.0f,min(sacColor.r,1.0f)),max(0.0f,min(sacColor.g,1.0f)),max(0.0f,min(sacColor.b,1.0f)),max(0.0f,min(sacColor.a,1.0f)));
		}
		env.ambientConstant = Color4f(options.ambientFactor*capColor(Color4f(ambi*envi.ambientRed/255.0f,ambi*envi.ambientGreen/255.0f,ambi*envi.ambientBlue/255.0f,1.0f)));
		env.backgroundColor = capColor(Color4f(envi.skyRed/255.0f,envi.skyGreen/255.0f,envi.skyBlue/255.0f,1.0f));
		// envi.minAlphaInt, envi.maxAlphaInt, envi.minAlphaFloat ?
		// envi.maxAlphaFloat used for sky alpha
		// sky_, skyt, skyb, sun_, undr used above
		auto sunDirection=Vector3f(envi.sunDirectionX,envi.sunDirectionY,envi.sunDirectionZ);
		//sunDirection.z=abs(sunDirection.z);
		//sunDirection.z=max(0.7,sunDirection.z);
		//sunDirection=sunDirection.normalized(); // TODO: why are sun directions in standard maps so extreme?
		env.sunRotation=rotationBetween(Vector3f(0,0,1),sunDirection);
		//env.sunColor=fixColor(Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f));
		//env.sunColor=Color4f(envi.ambientRed/255.0f,envi.ambientGreen/255.0f,envi.ambientBlue/255.0f,1.0f);
		//env.sunColor=fixColor(Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f));
		//env.sunColor=Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f);
		/+env.sunColor=0.5f*Color4f(envi.ambientRed/255.0f,envi.ambientGreen/255.0f,envi.ambientBlue/255.0f,1.0f)+
			0.5f*Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f);+/
		/+auto sunColor=envi.sunAmbientStrength/(envi.sunDirectStrength+envi.sunAmbientStrength)*Color4f(envi.ambientRed/255.0f,envi.ambientGreen/255.0f,envi.ambientBlue/255.0f,1.0f)+
			envi.sunDirectStrength/(envi.sunDirectStrength+envi.sunAmbientStrength)*Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f);+/
		auto sunColor=envi.sunAmbientStrength/(envi.sunDirectStrength+envi.sunAmbientStrength)*capColor(Color4f(ambi*envi.ambientRed/255.0f,ambi*envi.ambientGreen/255.0f,ambi*envi.ambientBlue/255.0f,1.0f))+
			envi.sunDirectStrength/(envi.sunDirectStrength+envi.sunAmbientStrength)*capColor(Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f));
		env.sunColor=capColor(Color4f(sunColor));
		// TODO: figure this out
		/+if(exp(envi.sunDirectStrength)==float.infinity)
			env.sunColor=Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f);
		else
			//env.sunColor=(exp(envi.sunDirectStrength)*Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f)+exp(4*min(10,envi.sunAmbientStrength^^10))*Color4f(envi.ambientRed/255.0f,envi.ambientGreen/255.0f,envi.ambientBlue/255.0f,1.0f))/(exp(envi.sunDirectStrength)+exp(4*min(10,envi.sunAmbientStrength^^10)));
			env.sunColor=(exp(envi.sunDirectStrength)*Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f)+0.5f*exp(envi.sunAmbientStrength)*Color4f(envi.ambientRed/255.0f,envi.ambientGreen/255.0f,envi.ambientBlue/255.0f,1.0f))/(exp(envi.sunDirectStrength)+0.5f*exp(envi.sunAmbientStrength));+/
		/+if(envi.sunAmbientStrength>=envi.sunDirectStrength){
			env.sunColor=(exp(envi.sunDirectStrength)*Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f)+exp(4*envi.sunAmbientStrength)*Color4f(envi.ambientRed/255.0f,envi.ambientGreen/255.0f,envi.ambientBlue/255.0f,1.0f))/(exp(envi.sunDirectStrength)+exp(4*envi.sunAmbientStrength));
		}else{
			env.sunColor=(exp(4*envi.sunDirectStrength)*Color4f(envi.sunColorRed/255.0f,envi.sunColorGreen/255.0f,envi.sunColorBlue/255.0f,1.0f)+exp(envi.sunAmbientStrength)*Color4f(envi.ambientRed/255.0f,envi.ambientGreen/255.0f,envi.ambientBlue/255.0f,1.0f))/(exp(4*envi.sunDirectStrength)+exp(envi.sunAmbientStrength));
		}+/
		// envi.sunFullbrightRed, envi.sunFullbrightGreen, envi.sunFullbrightBlue?
		// landscapeSpecularity, specularityRed, specularityGreen, specularityBlue and
		// landscapeGlossiness used for terrain material.
		//env.atmosphericFog=true;
		B.shadowMap.shadowColor=Color4f(envi.ambientRed/255.0f,envi.ambientGreen/255.0f,envi.ambientBlue/255.0f,1.0f);
		B.shadowMap.shadowBrightness=max(0.0f,min(1.0f,1.0f-envi.shadowStrength));
		env.fogColor=capColor(Color4f(envi.fogRed/255.0f,envi.fogGreen/255.0f,envi.fogBlue/255.0f,1.0f));
		// fogType ?
		if(options.enableFog){
			env.fogStart=envi.fogNearZ;
			env.fogEnd=envi.fogFarZ;
		}
		// fogDensity?
	}

	void renderSky(ObjectState!B state,ref RenderInfo!B info,B.RenderContext rc){
		auto totalTime=state.frame*1.0f/updateFPS;
		B.sacSkyMaterialBackend.sunLoc = sacSky.sunSkyRelLoc(info.camera.position);
		B.sacSkyMaterialBackend.cloudOffset=state.frame%(64*updateFPS)*1.0f/(64*updateFPS)*Vector2f(1.0f,-1.0f);
		auto skyRotation=rotationQuaternion(Axis.z,2*pi!float/512.0f*totalTime);
		auto map=state.map;
		auto x=10.0f*map.n/2, y=10.0f*map.m/2;
		auto skyPosition=Vector3f(x,y,sacSky.dZ*sacSky.scaling+1);
		auto envi=&map.envi;
		auto backend0=B.shadelessMaterialBackend;
		backend0.bind(null,rc);
		B.enableDepthMask();
		backend0.setInformation(Vector4f(0.0f,0.0f,0.0f,0.0f));
		backend0.setEnergy(sacSky.energy);
		backend0.setTransformation(skyPosition,skyRotation,rc);
		backend0.bindDiffuse(map.textures[skybIndex]);
		sacSky.skyb.render(rc);
		backend0.bindDiffuse(map.textures[skytIndex]);
		sacSky.skyt.render(rc);
		backend0.bindDiffuse(map.textures[undrIndex]);
		sacSky.undr.render(rc);
		auto backend1=B.sacSunMaterialBackend;
		backend1.bind(null,rc);
		backend1.setAlpha(1.0f);
		backend1.setEnergy(25.0f*sacSky.energy);
		backend1.bindDiffuse(map.textures[sunIndex]);
		backend1.setTransformation(skyPosition,Quaternionf.identity(),rc); // TODO: don't create rotation matrix
		sacSky.sun.render(rc);
		auto backend2=B.sacSkyMaterialBackend;
		backend2.bind(null,rc);
		backend2.setAlpha(min(map.envi.maxAlphaFloat,1.0f));
		backend2.setEnergy(sacSky.energy);
		backend2.bindDiffuse(map.textures[skyIndex]);
		backend2.setTransformation(skyPosition,Quaternionf.identity(),rc); // TODO: don't create rotation matrix
		sacSky.sky.render(rc);
	}

	void renderMap(ObjectState!B state,ref RenderInfo!B info,B.RenderContext rc){
		auto map=state.map;
		rc.layer=1;
		rc.modelMatrix=Matrix4x4f.identity();
		rc.invModelMatrix=Matrix4x4f.identity();
		rc.prevModelViewProjMatrix=Matrix4x4f.identity(); // TODO: get rid of this?
		rc.modelViewMatrix=rc.viewMatrix*rc.modelMatrix;
		rc.blurModelViewProjMatrix=rc.projectionMatrix*rc.modelViewMatrix; // TODO: get rid of this
		B.Material mat;
		if(!rc.shadowMode){
			mat=map.material; // TODO: get rid of this completely?
			mat.bind(rc);
			B.terrainMaterialBackend.bindColor(map.color);
		}else{
			B.terrainShadowBackend.bind(null,rc);
		}
		foreach(i,mesh;map.meshes){
			if(!mesh) continue;
			if(!rc.shadowMode){
				B.terrainMaterialBackend.bindDiffuse(map.textures[i]);
				if(i<map.dti.length){
					assert(!!map.details[map.dti[i]]);
					B.terrainMaterialBackend.bindDetail(map.details[map.dti[i]]);
				}else B.terrainMaterialBackend.bindDetail(null);
				B.terrainMaterialBackend.bindEmission(map.textures[i]);
			}
			mesh.render(rc);
		}
		//mat.unbind(rc); // TODO: needed?
		/+auto pathFinder=state.pathFinder;
		foreach(y;0..511){
			foreach(x;0..511){
				if(!pathFinder.unblocked(x,y,state)) continue;
				auto p=pathFinder.position(x,y,state);
				renderBox([p-Vector3f(1.0f,1.0f,1.0f),p+Vector3f(1.0f,1.0f,1.0f)],false,rc);
			}
		}+/
	}

	static void renderLoadedArrow(B)(ref MovingObject!B object,B.Mesh mesh,ObjectState!B state,RenderInfo!B* info,B.RenderContext rc){
		auto loadedArrow=object.loadedArrow;
		if(loadedArrow!=loadedArrow) return;
		void renderArrow(Vector3f start,Vector3f end,float scale=1.0f){
			auto direction=end-start;
			auto len=direction.length;
			auto rotation=rotationBetween(Vector3f(0.0f,0.0f,1.0f),direction/len);
			B.shadelessMaterialBackend.setTransformationScaled(start,rotation,Vector3f(scale,scale,len),rc);
			mesh.render(rc);
		}
		with(loadedArrow){
			renderArrow(hand,top,0.5f);
			renderArrow(hand,bottom,0.5f);
			renderArrow(hand,front);
		}
	}

	struct R3DOpt{
		bool enableWidgets;
	}

	void renderNTTs(RenderMode mode)(R3DOpt options,ObjectState!B state,ref RenderInfo!B info,B.RenderContext rc){
		static void render(T)(ref T objects,Renderer!B* self,bool enableWidgets,ObjectState!B state,RenderInfo!B* info,B.RenderContext rc){ // TODO: why does this need to be static? DMD bug?
			static if(is(typeof(objects.sacObject))){
				auto sacObject=objects.sacObject;
				enum isMoving=is(T==MovingObjects!(B, renderMode), RenderMode renderMode);
				enum isStatic=is(T==StaticObjects!(B, renderMode), RenderMode renderMode);
				enum isFixed=is(T==FixedObjects!B);
				static if(isFixed) if(!enableWidgets) return; // TODO: instanced rendering

				static if(objects.renderMode==RenderMode.opaque){
					enum prepareMaterials=RenderMode.opaque;
				}else{
					static if(isStatic){
						enum prepareMaterials=mode;
					}else{
						enum prepareMaterials=RenderMode.transparent;
					}
				}
				static if(prepareMaterials==RenderMode.opaque){
					auto materials=rc.shadowMode?sacObject.shadowMaterials:sacObject.materials;
				}else static if(prepareMaterials==RenderMode.transparent){
					auto opaqueMaterials=rc.shadowMode?sacObject.shadowMaterials:sacObject.materials;
					auto materials=rc.shadowMode?sacObject.shadowMaterials:sacObject.transparentMaterials;
				}else static assert(0);
				foreach(i;0..materials.length){
					auto material=materials[i];
					if(!material) continue;
					auto blending=B.blending(material);
					if((mode==RenderMode.transparent)!=(blending==B.Blending.Additive||blending==B.Blending.Transparent)) continue;
					if(rc.shadowMode&&blending==B.Blending.Additive) continue;
					static if(isStatic&&objects.renderMode==RenderMode.transparent){
						auto originalBackend=material.backend;
						static if(mode==RenderMode.opaque) material.backend=B.buildingSummonMaterialBackend1;
						else material.backend=B.buildingSummonMaterialBackend2;
						scope(success) material.backend=originalBackend;
					}
					material.bind(rc);
					scope(success) material.unbind(rc);
					static if(isMoving){
						auto mesh=sacObject.saxsi.meshes[i];
						foreach(j;0..objects.length){ // TODO: use instanced rendering instead
							if(rc.shadowMode&&objects.creatureStatss[j].effects.stealth) continue;
							material.backend.setTransformation(objects.positions[j], objects.rotations[j], rc);
							auto id=objects.ids[j];
							Vector4f information;
							if(info.renderSide!=objects.sides[j]&&objects.creatureStates[j].mode.isGhost) continue;
							if(info.renderSide!=objects.sides[j]
							   &&(!objects.creatureStates[j].mode.isVisibleToOtherSides||objects.creatureStatss[j].effects.stealth)
							   &&objects.creatureStates[j].mode!=CreatureMode.dead // TODO: dead creatures should not hide their own souls
							){
								information=Vector4f(0.0f,0.0f,0.0f,0.0f);
							}else information=Vector4f(2.0f,id>>16,id&((1<<16)-1),1.0f);
							material.backend.setInformation(information);
							float bulk=objects.creatureStatss[j].effects.bulk;
							if(bulk!=1.0f){
								if(material.backend is B.boneMaterialBackend) B.boneMaterialBackend.setBulk(bulk);
								if(material.backend is B.shadelessBoneMaterialBackend) B.shadelessBoneMaterialBackend.setBulk(bulk);
								if(material.backend is B.boneShadowBackend) B.boneShadowBackend.setBulk(bulk);
							}
							scope(success) if(bulk!=1.0f){
								if(material.backend is B.boneMaterialBackend) B.boneMaterialBackend.setBulk(1.0f);
								if(material.backend is B.shadelessBoneMaterialBackend) B.shadelessBoneMaterialBackend.setBulk(1.0f);
								if(material.backend is B.boneShadowBackend) B.boneShadowBackend.setBulk(1.0f);
							}
							static if(prepareMaterials==RenderMode.transparent){
								if(!rc.shadowMode){
									B.shadelessBoneMaterialBackend.setAlpha(objects.alphas[j]);
									B.shadelessBoneMaterialBackend.setEnergy(objects.energies[j]);
								}
							}else{
								bool petrified=!rc.shadowMode && material.backend is B.boneMaterialBackend && objects.creatureStatss[j].effects.stoneEffect;
								if(petrified) B.boneMaterialBackend.setPetrified(true);
								scope(success) if(petrified) B.boneMaterialBackend.setPetrified(false);
								bool slimed=!rc.shadowMode && material.backend is B.boneMaterialBackend && objects.creatureStatss[j].effects.slimed;
								auto idiffuse = typeof("diffuse" in material.inputs).init;
								if(slimed){
									idiffuse="diffuse" in material.inputs;
									auto sdiffuse="diffuse" in self.slime.material.inputs;
									if(auto stx=sdiffuse.texture) B.boneMaterialBackend.bindDiffuse(stx); // TODO: render slimed creatures in a separate pass/using shader setting instead?
									else idiffuse=null;
								}
								scope(success){
									if(slimed && idiffuse.texture) B.boneMaterialBackend.bindDiffuse(idiffuse.texture);
								}
							}
							// TODO: interpolate animations to get 60 FPS?
							auto pose=sacObject.getFrame(objects.animationStates[j],objects.frames[j]/updateAnimFactor);
							if(material.backend is B.boneMaterialBackend) B.boneMaterialBackend.setPose(pose);
							if(material.backend is B.shadelessBoneMaterialBackend) B.shadelessBoneMaterialBackend.setPose(pose);
							if(material.backend is B.boneShadowBackend) B.boneShadowBackend.setPose(pose);
							mesh.render(rc);
						}
					}else{
						material.backend.setInformation(Vector4f(0.0f,0.0f,0.0f,0.0f));
						int frame=0; // TODO: select frame
						auto mesh=sacObject.meshes[frame][i];
						static if(isStatic&&objects.renderMode==RenderMode.transparent&&mode==RenderMode.transparent){
							auto opaqueMaterial=opaqueMaterials[i];
							auto opaqueBlending=B.blending(opaqueMaterial);
							bool enableDiscard=opaqueBlending!=B.Blending.Transparent;
							if(!enableDiscard) B.buildingSummonMaterialBackend2.setEnableDiscard(false);
							scope(success) if(!enableDiscard) B.buildingSummonMaterialBackend2.setEnableDiscard(true);
						}
						foreach(j;0..objects.length){
							static if(isStatic&&objects.renderMode==RenderMode.transparent){
								auto thresholdZ=objects.thresholdZs[j];
								static if(mode==RenderMode.opaque){
									B.buildingSummonMaterialBackend1.setThresholdZ(thresholdZ);
								}else static if(mode==RenderMode.transparent){
									B.buildingSummonMaterialBackend2.setThresholdZ(thresholdZ,thresholdZ+structureCastingGradientSize);
								}else static assert(0);
							}
							auto position=objects.positions[j];
							static if(isFixed) position.z=state.getGroundHeight(position);
							static if(isStatic){
								material.backend.setTransformationScaled(position, objects.rotations[j], objects.scales[j]*Vector3f(1.0f,1.0f,1.0f), rc);
							}else material.backend.setTransformation(position, objects.rotations[j], rc);
							static if(isStatic){
								auto id=objects.ids[j];
								material.backend.setInformation(Vector4f(2.0f,id>>16,id&((1<<16)-1),1.0f));
							}
							mesh.render(rc);
						}
					}
				}
			}else static if(is(T==Souls!B)){
				static if(mode==RenderMode.transparent){
					if(rc.shadowMode) return;
					void renderSouls(bool filterGreen,T)(T sacSoul){
						auto material=sacSoul.material;
						foreach(j;0..objects.length){
							auto soul=objects[j];
							auto color=soul.color(info.renderSide,state);
							static if(filterGreen){
								bool isGreen=color==SoulColor.green;
								static if(is(T==SacSoul!B)){
									if(isGreen) continue;
								}else static if(is(T==SacGreenSoul!B)){
									if(!isGreen) continue;
								}
							}
							auto mesh=sacSoul.getMesh(color,soul.frame/updateAnimFactor); // TODO: do in shader?
							auto id=soul.id;
							material.backend.setInformation(Vector4f(3.0f,id>>16,id&((1<<16)-1),1.0f));
							if(objects[j].number==1){
								material.backend.setSpriteTransformationScaled(soul.position+soul.scaling*Vector3f(0.0f,0.0f,1.25f*sacSoul.soulHeight),soul.scaling,rc);
								mesh.render(rc);
							}else{
								auto number=objects[j].number;
								auto soulScaling=max(0.5f,1.0f-0.05f*number);
								auto radius=soul.scaling*sacSoul.soulRadius;
								if(number<=3) radius*=0.3*number;
								foreach(k;0..number){
									auto position=soul.position+rotate(facingQuaternion(objects[j].facing+2*pi!float*k/number), Vector3f(0.0f,radius,0.0f));
									material.backend.setSpriteTransformationScaled(position+soul.scaling*Vector3f(0.0f,0.0f,1.25f*sacSoul.soulHeight),soul.scaling*soulScaling,rc);
									mesh.render(rc);
								}
							}
						}
					}
					if(state.greenAllySouls&&self.sacGreenSoul){
						self.sacSoul.material.bind(rc);
						renderSouls!true(self.sacSoul);
						self.sacSoul.material.unbind(rc);
						self.sacGreenSoul.material.bind(rc);
						renderSouls!true(self.sacGreenSoul);
						self.sacGreenSoul.material.unbind(rc);
					}else{
						auto sacSoul=self.sacSoul;
						auto material=sacSoul.material;
						material.bind(rc);
						renderSouls!false(sacSoul);
						material.unbind(rc);
					}
				}
			}else static if(is(T==Buildings!B)){
				// do nothing
			}else static if(is(T==Effects!B)){
				static if(mode==RenderMode.opaque) if(objects.debris.length||objects.fireballCastings.length||objects.fireballs.length){
					auto materials=self.sacDebris.materials;
					foreach(i;0..materials.length){
						auto material=materials[i];
						material.bind(rc);
						scope(success) material.unbind(rc);
						auto mesh=self.sacDebris.meshes[0][i];
						foreach(j;0..objects.debris.length){
							material.backend.setTransformationScaled(objects.debris[j].position,objects.debris[j].rotation,0.2f*Vector3f(1.0f,1.0f,1.0f),rc);
							mesh.render(rc);
						}
						foreach(j;0..objects.fireballCastings.length){
							auto scale=0.25f*min(1.0f,objects.fireballCastings[j].frame/(objects.fireballCastings[j].fireball.spell.castingTime(9)*updateFPS));
							material.backend.setTransformationScaled(objects.fireballCastings[j].fireball.position,objects.fireballCastings[j].fireball.rotation,scale*Vector3f(1.0f,1.0f,1.0f),rc);
							mesh.render(rc);
						}
						foreach(j;0..objects.fireballs.length){
							material.backend.setTransformationScaled(objects.fireballs[j].position,objects.fireballs[j].rotation,0.25f*Vector3f(1.0f,1.0f,1.0f),rc);
							mesh.render(rc);
						}
					}
				}
				static if(mode==RenderMode.transparent)
				if(!rc.shadowMode&&
				   (objects.explosions.length||
				    objects.styxExplosions.length)
				){
					auto material=self.explosion.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					foreach(j;0..objects.explosions.length){
						auto mesh=self.explosion.getFrame(objects.explosions[j].frame);
						material.backend.setTransformationScaled(objects.explosions[j].position,Quaternionf.identity(),objects.explosions[j].scale*Vector3f(1.1f,1.1f,0.9f),rc);
						mesh.render(rc);
					}
					if(objects.styxExplosions.length){
						assert(material.backend is B.shadelessMaterialBackend);
						B.shadelessMaterialBackend.setEnergy(-1.0f);
					}
					foreach(j;0..objects.styxExplosions.length){
						auto mesh=self.explosion.getFrame(objects.styxExplosions[j].frame);
						material.backend.setTransformationScaled(objects.styxExplosions[j].position,Quaternionf.identity(),objects.styxExplosions[j].scale*Vector3f(1.1f,1.1f,0.9f),rc);
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&(objects.sacDocCastings.length||objects.rituals.length)){
					auto centerMat=self.vortex.redCenterMat;
					void renderRedCenter(ref RedVortex vortex){
						centerMat.backend.setSpriteTransformationScaled(vortex.position,vortex.scale*vortex.radius,rc);
						auto mesh=self.vortex.getCenterFrame(vortex.frame%self.vortex.numRimFrames);
						mesh.render(rc);
					}
					auto rimMat=self.vortex.redRimMat;
					void renderRedRim(ref RedVortex vortex){
						rimMat.backend.setSpriteTransformationScaled(vortex.position,vortex.scale*vortex.radius,rc);
						auto mesh=self.vortex.getRimFrame(vortex.frame%self.vortex.numRimFrames);
						mesh.render(rc);
					}
					centerMat.bind(rc);
					foreach(j;0..objects.sacDocCastings.length) renderRedCenter(objects.sacDocCastings[j].vortex);
					foreach(j;0..objects.rituals.length) if(!isNaN(objects.rituals[j].vortex.position.x)) renderRedCenter(objects.rituals[j].vortex);
					centerMat.unbind(rc);
					rimMat.bind(rc);
					foreach(j;0..objects.sacDocCastings.length) renderRedRim(objects.sacDocCastings[j].vortex);
					foreach(j;0..objects.rituals.length) if(!isNaN(objects.rituals[j].vortex.position.x)) renderRedRim(objects.rituals[j].vortex);
					rimMat.unbind(rc);
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.sacDocCarries.length){
					auto getPositionAndScaleForId(int id,float scale){
						alias H=Vector3f[2];
						auto hitbox=state.movingObjectById!((ref obj)=>obj.hitbox,()=>H.init)(id);
						auto size=boxSize(hitbox);
						return tuple(boxCenter(hitbox),scale*0.65f*Vector3f(1.1f*size.length,0.9f*size.length,0.0f)); // TODO
					}
					auto centerMat=self.vortex.blueCenterMat;
					void renderBlueCenter(Vector3f position,Vector3f scale,int frame){
						if(isNaN(position.x)) return;
						centerMat.backend.setSpriteTransformationScaled(position,scale,rc);
						auto mesh=self.vortex.getCenterFrame(frame%self.vortex.numRimFrames);
						mesh.render(rc);
					}
					void renderBlueCenterForId(int id,float scale,int frame){
						if(!id) return;
						return renderBlueCenter(getPositionAndScaleForId(id,scale).expand,frame);
					}
					auto rimMat=self.vortex.blueRimMat;
					void renderBlueRim(Vector3f position,Vector3f scale,int frame){
						if(isNaN(position.x)) return;
						rimMat.backend.setSpriteTransformationScaled(position,scale,rc);
						auto mesh=self.vortex.getRimFrame(frame%self.vortex.numRimFrames);
						mesh.render(rc);
					}
					void renderBlueRimForId(int id,float scale,int frame){
						if(!id) return;
						return renderBlueRim(getPositionAndScaleForId(id,scale).expand,frame);
					}
					centerMat.bind(rc);
					foreach(j;0..objects.sacDocCarries.length)
						if(objects.sacDocCarries[j].status.among(SacDocCarryStatus.move,SacDocCarryStatus.shrinking))
							renderBlueCenterForId(objects.sacDocCarries[j].creature,objects.sacDocCarries[j].vortexScale,objects.sacDocCarries[j].frame);
					centerMat.unbind(rc);
					rimMat.bind(rc);
					foreach(j;0..objects.sacDocCarries.length)
						if(objects.sacDocCarries[j].status.among(SacDocCarryStatus.move,SacDocCarryStatus.shrinking))
							renderBlueRimForId(objects.sacDocCarries[j].creature,objects.sacDocCarries[j].vortexScale,objects.sacDocCarries[j].frame);
					rimMat.unbind(rc);
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&(objects.sacDocCarries.length||objects.rituals.length)){
					auto material=self.tether.material;
					material.bind(rc);
					B.disableCulling();
					scope(success){
						B.enableCulling();
						material.unbind(rc);
					}
					B.shadelessBoneMaterialBackend.setTransformation(Vector3f(0.0f,0.0f,0.0f),Quaternionf.identity(),rc);
					void renderTether(ref SacDocTether tether,int frame){
						if(isNaN(tether.locations[0].x)) return;
						auto alpha=pi!float*frame/updateFPS;
						auto energy=0.375f+14.625f*(0.5f+0.25f*cos(7.0f*alpha)+0.25f*sin(11.0f*alpha));
						B.shadelessBoneMaterialBackend.setEnergy(energy);
						auto mesh=self.tether.getFrame(frame%self.tether.numFrames);
						Matrix4x4f[self.tether.numSegments+1] pose;
						foreach(i,ref x;pose){
							auto curve = tether.get(i/float(pose.length-1));
							auto rotation=rotationBetween(Vector3f(0.0f,0.0f,1.0f),curve[1].normalized);
							x=Transformation(rotation,curve[0]).getMatrix4f;
						}
						B.shadelessBoneMaterialBackend.setPose(pose);
						mesh.render(rc);
					}
					foreach(j;0..objects.sacDocCarries.length) renderTether(objects.sacDocCarries[j].tether,objects.sacDocCarries[j].frame);
					foreach(j;0..objects.rituals.length) foreach(k;0..4) renderTether(objects.rituals[j].tethers[k],objects.rituals[j].frame);
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.guardians.length){
					auto material=self.guardianTether.material;
					material.bind(rc);
					B.disableCulling();
					scope(success){
						B.enableCulling();
						material.unbind(rc);
					}
					void renderGuardianTether(ref Guardian guardian){
						with(guardian){
							auto diff=end-start;
							auto len=diff.length;
							auto rotation=rotationBetween(Vector3f(0.0f,0.0f,1.0f),diff/len);
							auto pulse=0.75f+0.25f*0.5f*(1.0f+sin(2.0f*pi!float*(frame%pulseFrames)/(pulseFrames-1)));
							B.shadelessBoneMaterialBackend.setTransformationScaled(start,rotation,Vector3f(pulse,pulse,(1.0f/1.5f)*len),rc);
							auto mesh=self.guardianTether.getFrame(frame%self.guardianTether.numFrames);
							Matrix4x4f[self.guardianTether.numSegments+1] pose;
							pose[0]=pose[self.guardianTether.numSegments]=Matrix4f.identity();
							foreach(i,ref x;pose[1..$-1]){
								auto curve=get(i/float(pose.length-1));
								x=Transformation(Quaternionf.identity(),curve[0]).getMatrix4f;
							}
							B.shadelessBoneMaterialBackend.setPose(pose);
							mesh.render(rc);
						}
					}
					foreach(ref guardian;objects.guardians) renderGuardianTether(guardian);
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&(objects.blueRings.length||objects.teleportRings.length)){
					auto material=self.blueRing.material;
					material.bind(rc);
					B.disableCulling();
					scope(success){
						B.enableCulling();
						material.unbind(rc);
					}
					foreach(j;0..objects.blueRings.length){
						auto position=objects.blueRings[j].position;
						auto scale=objects.blueRings[j].scale;
						B.shadelessMaterialBackend.setTransformationScaled(position,Quaternionf.identity(),scale*Vector3f(1.0f,1.0f,1.0f),rc);
						B.shadelessMaterialBackend.setEnergy(20.0f*scale^^4);
						auto mesh=self.blueRing.getFrame(objects.blueRings[j].frame%self.blueRing.numFrames);
						mesh.render(rc);
					}
					foreach(j;0..objects.teleportRings.length){
						auto position=objects.teleportRings[j].position;
						auto scale=objects.teleportRings[j].scale*sqrt(1.0f-float(objects.teleportRings[j].frame)/teleportRingLifetime);
						B.shadelessMaterialBackend.setTransformationScaled(position,Quaternionf.identity(),0.08f*scale*Vector3f(1.0f,1.0f,1.0f),rc);
						B.shadelessMaterialBackend.setEnergy(20.0f*scale^^2);
						auto mesh=self.blueRing.getFrame(objects.teleportRings[j].frame%self.blueRing.numFrames);
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.levelUpRings.length){
					auto material=self.levelUpRing.material;
					material.bind(rc);
					B.disableCulling();
					scope(success){
						B.enableCulling();
						material.unbind(rc);
					}
					foreach(j;0..objects.levelUpRings.length){
						auto position=objects.levelUpRings[j].position;
						auto scale=objects.levelUpRings[j].scale*sqrt(1.0f-float(max(0,objects.levelUpRings[j].frame))/levelUpRingLifetime);
						B.shadelessMaterialBackend.setTransformationScaled(position,Quaternionf.identity(),0.08f*scale*Vector3f(1.0f,1.0f,1.0f),rc);
						B.shadelessMaterialBackend.setEnergy(20.0f*scale);
						auto mesh=self.levelUpRing.getFrame(objects.levelUpRings[j].spriteFrame%self.levelUpRing.numFrames);
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.levelDownRings.length){
					auto material=self.levelDownRing.material;
					material.bind(rc);
					B.disableCulling();
					scope(success){
						B.enableCulling();
						material.unbind(rc);
					}
					foreach(j;0..objects.levelDownRings.length){
						auto position=objects.levelDownRings[j].position;
						auto scale=objects.levelDownRings[j].scale*sqrt(1.0f-float(objects.levelDownRings[j].frame)/levelDownRingLifetime);
						B.shadelessMaterialBackend.setTransformationScaled(position,Quaternionf.identity(),0.08f*scale*Vector3f(1.0f,1.0f,1.0f),rc);
						B.shadelessMaterialBackend.setEnergy(20.0f*scale^^2);
						auto mesh=self.levelDownRing.getFrame(objects.levelDownRings[j].spriteFrame%self.levelUpRing.numFrames);
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode){
					foreach(j;0..objects.speedUpShadows.length){
						if((objects.speedUpShadows[j].age+1)%speedUpShadowSpacing!=0) continue;
						auto id=objects.speedUpShadows[j].creature;
						if(!state.isValidTarget(id,TargetType.creature)) continue;
						auto sacObjectPetrifiedSlimedBulk=state.movingObjectById!((obj)=>tuple(obj.sacObject,obj.creatureStats.effects.stoneEffect,obj.creatureStats.effects.slimed,obj.creatureStats.effects.bulk),()=>tuple(SacObject!B.init,false,false,1.0f))(id); // TODO: store within SpeedUpShadow?
						auto sacObject=sacObjectPetrifiedSlimedBulk[0], petrified=sacObjectPetrifiedSlimedBulk[1], slimed=sacObjectPetrifiedSlimedBulk[2], bulk=sacObjectPetrifiedSlimedBulk[3];
						if(!sacObject) continue;
						auto materials=sacObject.transparentMaterials;
						foreach(i;0..materials.length){
							auto mesh=sacObject.saxsi.meshes[i];
							auto material=materials[i];
							material.bind(rc);
							scope(success) material.unbind(rc);
							material.backend.setTransformation(objects.speedUpShadows[j].position,objects.speedUpShadows[j].rotation,rc);
							B.shadelessBoneMaterialBackend.setAlpha(0.3f);
							B.shadelessBoneMaterialBackend.setEnergy(10.0f);
							if(bulk!=1.0f) B.shadelessBoneMaterialBackend.setBulk(bulk);
							scope(success) if(bulk!=1.0f) B.shadelessBoneMaterialBackend.setBulk(1.0f);
							if(petrified) B.shadelessBoneMaterialBackend.setPetrified(true);
							scope(success) if(petrified) B.shadelessBoneMaterialBackend.setPetrified(false);
							auto idiffuse = typeof("diffuse" in material.inputs).init;
							if(slimed){
									idiffuse="diffuse" in material.inputs;
									auto sdiffuse="diffuse" in self.slime.material.inputs;
									if(auto stx=sdiffuse.texture) B.boneMaterialBackend.bindDiffuse(stx); // TODO: render slimed creatures in a separate pass/using shader setting instead?
									else idiffuse=null;
							}
							scope(success){
								if(slimed && idiffuse.texture) B.boneMaterialBackend.bindDiffuse(idiffuse.texture);
							}
							auto pose=sacObject.getFrame(objects.speedUpShadows[j].animationState,objects.speedUpShadows[j].frame/updateAnimFactor);
							B.shadelessBoneMaterialBackend.setPose(pose);
							mesh.render(rc);
						}
					}
				}
				static if(mode==RenderMode.transparent)
					if(!rc.shadowMode&&
					   (objects.lightnings.length||
					    objects.chainLightningCastingEffects.length||
					    objects.soulWindEffects.length||
					    objects.cagePulls.length||
					    objects.rituals.length||
					    objects.styxBolts.length)
				){
					auto material=self.lightning.material;
					material.bind(rc);
					B.disableCulling();
					scope(success){
						B.enableCulling();
						material.unbind(rc);
					}
					void renderBolts(int totalFrames,float scale=1.0f,bool negativeEnergy=false)(LightningBolt[] bolts,Vector3f start,Vector3f end,int frame,float α,float β){
						auto diff=end-start;
						auto len=diff.length;
						auto rotation=rotationBetween(Vector3f(0.0f,0.0f,1.0f),diff/len);
						B.shadelessBoneMaterialBackend.setTransformationScaled(start,rotation,Vector3f(scale,scale,scale*0.1f*len),rc);
						auto alpha=pi!float*frame/float(totalFrames);
						auto energy=0.375f+14.625f*(0.5f+0.25f*cos(7.0f*alpha)+0.25f*sin(11.0f*alpha));
						static if(negativeEnergy) energy*=-2.0f/15.0f;
						B.shadelessBoneMaterialBackend.setEnergy(energy);
						auto mesh=self.lightning.getFrame(frame%self.lightning.numFrames);
						foreach(ref bolt;bolts){
							Matrix4x4f[numLightningSegments+1] pose;
							foreach(k,ref x;pose) x=Transformation(Quaternionf.identity(),(1.0f/scale)*bolt.get(max(α,min(float(k)/numLightningSegments,β)))).getMatrix4f;
							B.shadelessBoneMaterialBackend.setPose(pose);
							mesh.render(rc);
						}
					}
					foreach(j;0..objects.lightnings.length){
						auto start=objects.lightnings[j].start.center(state);
						auto end=objects.lightnings[j].end.center(state);
						auto frame=objects.lightnings[j].frame;
						enum totalFrames=Lightning!B.totalFrames;
						enum travelDelay=Lightning!B.travelDelay;
						auto α=0.0f,β=1.0f;
						if(frame<travelDelay){
							β=frame/float(travelDelay);
						}else if(frame>totalFrames-travelDelay){
							α=(frame-(totalFrames-travelDelay))/float(travelDelay);
						}
						auto bolts=objects.lightnings[j].bolts[];
						renderBolts!totalFrames(bolts,start,end,frame,α,β);
					}
					foreach(j;0..objects.chainLightningCastingEffects.length){
						auto start=objects.chainLightningCastingEffects[j].start;
						auto end=objects.chainLightningCastingEffects[j].end;
						auto frame=objects.chainLightningCastingEffects[j].frame;
						enum totalFrames=ChainLightningCastingEffect!B.totalFrames;
						enum travelDelay=ChainLightningCastingEffect!B.travelDelay;
						auto α=0.0f,β=1.0f;
						if(frame<travelDelay){
							β=frame/float(travelDelay);
						}else if(frame>totalFrames-travelDelay){
							α=(frame-(totalFrames-travelDelay))/float(travelDelay);
						}
						auto bolts=(&objects.chainLightningCastingEffects[j].bolt)[0..1];
						renderBolts!(totalFrames,0.5f)(bolts,start,end,frame,α,β);
					}
					foreach(j;0..objects.soulWindEffects.length){
						auto start=objects.soulWindEffects[j].start.center(state);
						auto end=objects.soulWindEffects[j].end.center(state);
						auto frame=objects.soulWindEffects[j].frame;
						enum totalFrames=SoulWindEffect.totalFrames;
						auto bolts=objects.soulWindEffects[j].bolts[];
						renderBolts!totalFrames(bolts,start,end,frame,0.0f,1.0f);
					}
					foreach(j;0..objects.cagePulls.length){
						auto creature=objects.cagePulls[j].creature;
						auto start=state.movingObjectById!((ref obj)=>obj.shotPosition,()=>Vector3f.init)(creature);
						if(isNaN(start.x)) continue;
						auto target=objects.cagePulls[j].target;
						if(!target) continue;
						auto end=state.movingObjectById!((ref obj)=>obj.center,()=>Vector3f.init)(target);
						if(isNaN(end.x)) continue;
						auto frame=objects.cagePulls[j].frame;
						enum totalFrames=typeof(objects.cagePulls[j]).totalFrames;
						enum travelDelay=typeof(objects.cagePulls[j]).numShootFrames;
						auto α=0.0f,β=1.0f;
						if(frame<travelDelay) β=frame/float(travelDelay);
						auto bolts=(&objects.cagePulls[j].bolt)[0..1];
						renderBolts!(totalFrames,0.75f)(bolts,start,end,frame,α,β);
					}
					foreach(j;0..objects.rituals.length){
						auto frame=objects.rituals[j].frame;
						if(!isNaN(objects.rituals[j].altarBolts[0].displacement[0].x)){
							auto start=state.staticObjectById!((ref obj)=>obj.position+Vector3f(0.0f,0.0f,60.0f),()=>Vector3f.init)(objects.rituals[j].shrine);
							auto end=state.movingObjectById!(center,()=>Vector3f.init)(objects.rituals[j].creature);
							if(!isNaN(end.x)&&!isNaN(start.x)) renderBolts!(Lightning!B.totalFrames)(objects.rituals[j].altarBolts[],start,end,frame,0.0f,1.0f);
						}
						if(objects.rituals[j].targetWizard){
							auto start=objects.rituals[j].vortex.position;
							auto end=state.movingObjectById!(center,()=>Vector3f.init)(objects.rituals[j].targetWizard);
							if(!isNaN(end.x)&&!isNaN(start.x)) renderBolts!(Lightning!B.totalFrames)(objects.rituals[j].desecrateBolts[],start,end,frame,0.0f,1.0f);
						}
					}
					foreach(j;0..objects.styxBolts.length){
						auto start=objects.styxBolts[j].position;
						auto end=objects.styxBolts[j].targetPosition;
						auto frame=objects.styxBolts[j].frame;
						enum totalFrames=StyxBolt!B.totalFrames;
						auto bolts=(&objects.styxBolts[j].bolt)[0..1];
						renderBolts!(totalFrames,1.5f,true)(bolts,start,end,frame,0.0f,1.0f);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&(objects.wraths.length||objects.altarDestructions.length)){
					auto material=self.wrath.material;
					material.bind(rc);
					B.disableCulling();
					scope(success){
						B.enableCulling();
						material.unbind(rc);
					}
					void renderWrath(int frame,Vector3f position,float scale_=1.0f){
						auto mesh=self.wrath.getFrame(frame);
						auto scale=scale_*self.wrath.maxScale/self.wrath.numFrames*frame;
						B.shadelessMaterialBackend.setTransformationScaled(position,Quaternionf.identity(),Vector3f(scale,scale,1.0f),rc);
						mesh.render(rc);
					}
					foreach(j;0..objects.wraths.length){
						if(objects.wraths[j].status!=WrathStatus.exploding) continue;
						auto frame=objects.wraths[j].frame;
						auto position=objects.wraths[j].position+Vector3f(0.0f,0.0f,self.wrath.maxOffset/self.wrath.numFrames*objects.wraths[j].frame);
						renderWrath(frame,position);
					}
					foreach(j;0..objects.altarDestructions.length){
						enum delay=AltarDestruction.disappearDuration+AltarDestruction.floatDuration;
						if(objects.altarDestructions[j].frame<delay) continue;
						auto frame=(objects.altarDestructions[j].frame-delay)*(self.wrath.numFrames-1)/AltarDestruction.explodeDuration;
						auto position=objects.altarDestructions[j].position;
						renderWrath(frame,position,20.0f);
					}
				}
				static if(mode==RenderMode.opaque) if(objects.rockCastings.length||objects.rocks.length||
				                                      objects.soulMoleCastings.length||objects.soulMoles.length||
													  objects.haloOfEarthCastings.length||objects.haloOfEarths.length||
				                                      objects.eruptDebris.length||
				                                      objects.earthflingProjectiles.length||objects.flummoxProjectiles.length||objects.boulderdashProjectiles.length||
				                                      objects.rockForms.length
				){
					auto materials=self.rock.materials;
					foreach(i;0..materials.length){
						auto material=materials[i];
						material.bind(rc);
						scope(success) material.unbind(rc);
						auto mesh=self.rock.meshes[0][i];
						foreach(j;0..objects.rockCastings.length){
							auto scale=1.0f*Vector3f(1.0f,1.0f,1.0f);
							material.backend.setTransformationScaled(objects.rockCastings[j].rock.position,objects.rockCastings[j].rock.rotation,scale,rc);
							mesh.render(rc);
						}
						foreach(j;0..objects.rocks.length){
							material.backend.setTransformationScaled(objects.rocks[j].position,objects.rocks[j].rotation,1.0f*Vector3f(1.0f,1.0f,1.0f),rc);
							mesh.render(rc);
						}
						foreach(j;0..objects.soulMoleCastings.length){
							material.backend.setTransformationScaled(objects.soulMoleCastings[j].soulMole.position,Quaternionf.identity(),Vector3f(1.0f,1.0f,1.0f),rc);
							mesh.render(rc);
						}
						foreach(j;0..objects.soulMoles.length){
							material.backend.setTransformationScaled(objects.soulMoles[j].position,Quaternionf.identity(),Vector3f(1.0f,1.0f,1.0f),rc);
							mesh.render(rc);
						}
						foreach(j;0..objects.haloOfEarthCastings.length){
							foreach(k;objects.haloOfEarthCastings[j].haloOfEarth.numDespawned..objects.haloOfEarthCastings[j].haloOfEarth.numSpawned){
								material.backend.setTransformationScaled(objects.haloOfEarthCastings[j].haloOfEarth.rocks[k].position,objects.haloOfEarthCastings[j].haloOfEarth.rocks[k].rotation,haloRockSize/2.0f*Vector3f(1.0f,1.0f,1.0f),rc);
								mesh.render(rc);
							}
						}
						foreach(j;0..objects.haloOfEarths.length){
							foreach(k;objects.haloOfEarths[j].numDespawned..objects.haloOfEarths[j].numSpawned){
								material.backend.setTransformationScaled(objects.haloOfEarths[j].rocks[k].position,objects.haloOfEarths[j].rocks[k].rotation,haloRockSize/2.0f*Vector3f(1.0f,1.0f,1.0f),rc);
								mesh.render(rc);
							}
						}
						foreach(j;0..objects.eruptDebris.length){
							material.backend.setTransformationScaled(objects.eruptDebris[j].position,objects.eruptDebris[j].rotation,0.4f*Vector3f(1.0f,1.0f,1.0f),rc);
							mesh.render(rc);
						}
						foreach(j;0..objects.earthflingProjectiles.length){
							material.backend.setTransformationScaled(objects.earthflingProjectiles[j].position,objects.earthflingProjectiles[j].rotation,0.3f*Vector3f(1.0f,1.0f,1.0f),rc);
							mesh.render(rc);
						}
						foreach(j;0..objects.flummoxProjectiles.length){
							material.backend.setTransformationScaled(objects.flummoxProjectiles[j].position,objects.flummoxProjectiles[j].rotation,1.25f*Vector3f(1.0f,1.0f,1.0f),rc);
							mesh.render(rc);
						}
						foreach(j;0..objects.boulderdashProjectiles.length){
							material.backend.setTransformationScaled(objects.boulderdashProjectiles[j].position,objects.boulderdashProjectiles[j].rotation,0.3f*Vector3f(1.0f,1.0f,1.0f),rc);
							mesh.render(rc);
						}
						foreach(j;0..objects.rockForms.length){
							auto target=objects.rockForms[j].target;
							auto positionRotation=state.movingObjectById!((ref obj)=>tuple(center(obj),obj.rotation), function Tuple!(Vector3f,Quaternionf)(){ return typeof(return).init; })(target);
							auto position=positionRotation[0], rotation=positionRotation[1];
							if(isNaN(position.x)) continue;
							auto scale=objects.rockForms[j].scale*objects.rockForms[j].relativeScale;
							material.backend.setTransformationScaled(position,rotation,scale*Vector3f(1.0f,1.0f,1.0f),rc);
							mesh.render(rc);
						}
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&(objects.swarmCastings.length||objects.swarms.length||objects.fallenProjectiles.length)){
					// TODO: render bug shadows?
					auto material=self.bug.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					auto mesh=self.bug.mesh;
					void renderBug(bool fallen=false)(ref Bug!B bug){
						material.backend.setSpriteTransformationScaled(bug.position,fallen?0.5f*bug.scale:bug.scale,rc);
						mesh.render(rc);
					}
					foreach(j;0..objects.swarmCastings.length)
						foreach(k;0..objects.swarmCastings[j].swarm.bugs.length)
							renderBug(objects.swarmCastings[j].swarm.bugs[k]);
					foreach(j;0..objects.swarms.length){
						if(objects.swarms[j].status==SwarmStatus.dispersing){
							material.backend.setAlpha(Bug!B.alpha/64.0f*(swarmDispersingFrames-objects.swarms[j].frame));
						}else material.backend.setAlpha(Bug!B.alpha);
						foreach(k;0..objects.swarms[j].bugs.length)
							renderBug(objects.swarms[j].bugs[k]);
					}
					foreach(j;0..objects.fallenProjectiles.length){
						if(objects.fallenProjectiles[j].status==SwarmStatus.dispersing){
							material.backend.setAlpha(Bug!B.alpha/64.0f*(fallenProjectileDispersingFrames-objects.fallenProjectiles[j].frame));
						}else material.backend.setAlpha(Bug!B.alpha);
						foreach(k;0..objects.fallenProjectiles[j].bugs.length)
							renderBug!true(objects.fallenProjectiles[j].bugs[k]);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&(objects.protectiveSwarmCastings.length||objects.protectiveSwarms.length)){
					// TODO: render bug shadows?
					auto material=self.protectiveBug.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					void renderProtectiveBug(ref ProtectiveBug!B protectiveBug,Vector3f position,Quaternionf rotation){
						material.backend.setSpriteTransformationScaled(position+rotate(rotation,protectiveBug.position),protectiveBug.scale,rc);
						auto mesh=self.protectiveBug.getFrame(protectiveBug.frame%self.protectiveBug.numFrames);
						mesh.render(rc);
					}
					void renderProtectiveSwarm(ref ProtectiveSwarm!B protectiveSwarm){
						material.backend.setAlpha(ProtectiveBug!B.alpha*protectiveSwarm.alpha);
						auto positionRotation=state.movingObjectById!((ref object)=>tuple(object.center,object.rotation),()=>Tuple!(Vector3f,Quaternionf).init)(protectiveSwarm.target);
						auto position=positionRotation[0],rotation=positionRotation[1];
						if(isNaN(position.x)) return;
						foreach(k;0..protectiveSwarm.bugs.length)
							renderProtectiveBug(protectiveSwarm.bugs[k],position,rotation);
					}
					foreach(j;0..objects.protectiveSwarmCastings.length) renderProtectiveSwarm(objects.protectiveSwarmCastings[j].protectiveSwarm);
					foreach(j;0..objects.protectiveSwarms.length) renderProtectiveSwarm(objects.protectiveSwarms[j]);
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&(objects.airShieldCastings.length||objects.airShields.length)){
					B.disableDepthMask();
					B.enableCulling();
					scope(success) B.enableDepthMask();
					auto material=self.airShield.material;
					auto effectMaterial=self.airShieldEffect.material;
					void renderAirShield(ref AirShield!B airShield){
						B.shadelessMorphMaterialBackend.bind(material,rc);
						B.enableTransparency();
						B.disableDepthMask();
						auto target=airShield.target;
						auto positionRotationBoxSize=state.movingObjectById!((ref obj)=>tuple(center(obj),obj.position,obj.rotation,boxSize(obj.sacObject.largeHitbox(Quaternionf.identity(),obj.animationState,obj.frame/updateAnimFactor))), function Tuple!(Vector3f,Vector3f,Quaternionf,Vector3f)(){ return typeof(return).init; })(target);
						auto position=positionRotationBoxSize[0], rawPosition=positionRotationBoxSize[1], rotation=positionRotationBoxSize[2], boxSize=positionRotationBoxSize[3];
						if(isNaN(position.x)) return;
						auto scale=airShield.scale+0.05f*(1.0f*sin(2.0f*pi!float*2.0f*airShield.frame/updateFPS));
						boxSize.x=boxSize.y=sqrt(0.5f*(boxSize.x^^2+boxSize.y^^2));
						auto dimensions=Vector3f(2.0f,2.0f,1.5f)*boxSize;
						B.shadelessMorphMaterialBackend.setTransformationScaled(position,rotation,scale*dimensions,rc);
						foreach(v;0..3){
							auto mesh1Mesh2Progress=self.airShield.getFrame(airShield.frame+20*v,airShield.frame);
							auto mesh1=mesh1Mesh2Progress[0], mesh2=mesh1Mesh2Progress[1], progress=mesh1Mesh2Progress[2];
							B.shadelessMorphMaterialBackend.setMorphProgress(progress);
							mesh1.morph(mesh2,rc);
						}
						B.shadelessMorphMaterialBackend.unbind(material,rc);
						effectMaterial.bind(rc);
						foreach(ref particle;airShield.particles){
							auto location=Vector3f(particle.radius*cos(particle.θ),particle.radius*sin(particle.θ),particle.height)*airShield.scale;
							auto pposition=rawPosition+rotate(rotation,location);
							auto frame=particle.frame;
							B.shadelessMaterialBackend.setSpriteTransformationScaled(pposition,scale,rc);
							auto pmesh=self.airShieldEffect.getFrame(frame%self.airShieldEffect.numFrames);
							pmesh.render(rc);
						}
						effectMaterial.unbind(rc);
					}
					foreach(ref airShieldCasting;objects.airShieldCastings) renderAirShield(airShieldCasting.airShield);
					foreach(ref airShield;objects.airShields) renderAirShield(airShield);
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.freezes.length){
					auto material=self.freeze.material;
					auto mesh=self.freeze.mesh;
					material.bind(rc);
					B.disableCulling();
					scope(success){
						B.enableCulling();
						material.unbind(rc);
					}
					void renderFreeze(ref Freeze!B freeze){
						auto scale=freeze.scale;
						auto creature=freeze.creature;
						auto hitbox=state.movingObjectById!((ref obj){
							auto hitbox=obj.sacObject.largeHitbox(obj.rotation,obj.animationState,obj.frame/updateAnimFactor);
							hitbox[0]+=obj.position;
							hitbox[1]+=obj.position;
							return hitbox;
						}, ()=>(Vector3f[2]).init)(creature);
						auto center=boxCenter(hitbox), size=boxSize(hitbox);
						if(isNaN(center.x)) return;
						material.backend.setTransformationScaled(center,Quaternionf.identity(),scale*size,rc);
						mesh.render(rc);
					}
					foreach(ref freeze;objects.freezes) renderFreeze(freeze);
				}
				static if(mode==RenderMode.opaque) if(objects.slimeCastings.length){
					auto material=self.slime.material;
					auto mesh=self.slime.mesh;
					material.bind(rc);
					scope(success) material.unbind(rc);
					void renderSlime(ref SlimeCasting!B slime){
						auto scale=min(1.0f,slime.progress/slime.progressThreshold);
						auto position=1.0f-1.0f/(1.0f-slime.progressThreshold)*max(0.0f,slime.progress-slime.progressThreshold);
						auto offset=Vector3f(0.0f,0.0f,position*slime.heightOffset);
						auto creature=slime.creature;
						import animations;
						auto sizeCenter=state.movingObjectById!((ref obj){
							auto hitbox=obj.sacObject.largeHitbox(Quaternionf.identity(),AnimationState.stance1,0);
							hitbox[0]+=obj.position;
							hitbox[1]+=obj.position;
							return tuple(boxSize(hitbox).length,boxCenter(hitbox));
						},()=>tuple(float.nan,Vector3f.init))(creature);
						auto size=sizeCenter[0],center=sizeCenter[1];
						if(isNaN(size)) return;
						material.backend.setTransformationScaled(center+offset,Quaternionf.identity(),scale*size*Vector3f(1.0f,1.0f,1.0f),rc);
						mesh.render(rc);
					}
					foreach(ref slime;objects.slimeCastings) renderSlime(slime);
				}
				static if(mode==RenderMode.opaque) if(objects.graspingViness.length){
					auto material=self.vine.material; // TODO: shadowMaterial?
					auto mesh=self.vine.mesh;
					material.bind(rc);
					void renderVine(ref Vine vine,float lengthFactor){
						if(isNaN(vine.locations[0].x)) return;
						Matrix4x4f[self.vine.numSegments+1] pose;
						foreach(i,ref x;pose){
							auto curve = vine.get(i/float(pose.length-1));
							auto rotation=rotationBetween(Vector3f(0.0f,0.0f,1.0f),curve[1].normalized);
							//auto rotation=Quaternionf.identity();
							x=Transformation(rotation,curve[0]/(vine.scale*lengthFactor)).getMatrix4f;
						}
						auto scale=vine.scale*lengthFactor*Vector3f(1.0f,1.0f,1.0f);
						B.boneMaterialBackend.setTransformationScaled(Vector3f(0.0f,0.0f,0.0f),Quaternionf.identity(),scale,rc);
						B.boneMaterialBackend.setPose(pose);
						mesh.render(rc);
					}
					foreach(ref graspingVines;objects.graspingViness)
						foreach(ref vine;graspingVines.vines)
							renderVine(vine,graspingVines.lengthFactor);
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.rainbowEffects.length){
					auto material=self.rainbow.material;
					material.bind(rc);
					B.disableCulling();
					scope(success){
						B.enableCulling();
						material.unbind(rc);
					}
					B.shadelessBoneMaterialBackend.setTransformation(Vector3f(0.0f,0.0f,0.0f),Quaternionf.identity(),rc);
					auto mesh=self.rainbow.mesh;
					void renderRainbow(ref RainbowEffect!B rainbow){
						Matrix4x4f[self.rainbow.numSegments+1] pose;
						auto start=rainbow.start.position, end=rainbow.end.position;
						auto direction=(end-start).normalized;
						float startProgress=0.0f,endProgress=1.0f;
						enum travelFrames=rainbow.travelFrames, delay=rainbow.delay;
						auto frame=rainbow.frame;
						if(frame<travelFrames) endProgress=float(frame)/travelFrames;
						if(travelFrames+delay<=frame) startProgress=float(frame-(travelFrames+delay))/travelFrames;
						auto defaultRotation=rotationBetween(Vector3f(0.0f,0.0f,1.0f),direction);
						auto center=0.5f*(start+end);
						auto rotationAxis=cross(Vector3f(0.0f,0.0f,1.0f),end-start).normalized;
						if(isNaN(rotationAxis.x)) rotationAxis=Vector3f(0.0f,1.0f,0.0f);
						auto positionAt(float x){
							//return (1.0f-x)*start+x*end;
							static Vector3f xy(Vector3f xyz){ return Vector3f(xyz.x,xyz.y,0.0f); }
							auto position=xy(center)+rotate(rotationQuaternion(rotationAxis,x*pi!float),xy(start-center));
							auto dstart=(xy(position)-xy(start)).length, dend=(xy(end)-xy(position)).length;
							if(dstart==0.0f&&dend==0.0f) return start;
							position.z+=dend/(dstart+dend)*start.z+dstart/(dstart+dend)*end.z;
							return position;
						}
						auto rotationAt(float x){
							return rotationQuaternion(rotationAxis,-(1.0f-x)*0.5f*pi!float+x*0.5f*pi!float)*defaultRotation;
						}
						foreach(i,ref x;pose){
							auto relativeProgress=float(i)/self.rainbow.numSegments;
							auto progress=(1.0f-relativeProgress)*startProgress+relativeProgress*endProgress;
							x=Transformation(rotationAt(progress),positionAt(progress)).getMatrix4f;
						}
						B.shadelessBoneMaterialBackend.setPose(pose);
						mesh.render(rc);
					}
					foreach(j;0..objects.rainbowEffects.length) renderRainbow(objects.rainbowEffects[j]);
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.animateDeadEffects.length){
					auto material=self.animateDead.material;
					material.bind(rc);
					B.disableCulling();
					scope(success){
						B.enableCulling();
						material.unbind(rc);
					}
					B.shadelessBoneMaterialBackend.setTransformation(Vector3f(0.0f,0.0f,0.0f),Quaternionf.identity(),rc);
					void renderAnimateDead(ref AnimateDeadEffect!B animateDead){
						Matrix4x4f[self.animateDead.numSegments+1] pose;
						auto start=animateDead.start.position, end=animateDead.end.position;
						auto direction=(end-start).normalized;
						auto frame=animateDead.frame;
						auto relativeLength=animateDead.relativeLength;
						auto startProgress=(1.0f+relativeLength)*float(frame)/animateDead.totalFrames;
						auto endProgress=startProgress-relativeLength;
						foreach(i,ref x;pose){
							auto relativeProgress=float(i)/self.animateDead.numSegments;
							auto progress=max(0.0f,min((1.0f-relativeProgress)*startProgress+relativeProgress*endProgress,1.0f));
							auto location=cintp2([[animateDead.start.position,animateDead.startDirection],[animateDead.end.position,animateDead.endDirection]],progress);
							x=Transformation(rotationBetween(Vector3f(0.0f,0.0f,1.0f),location[1].normalized),location[0]).getMatrix4f;
						}
						auto mesh=self.animateDead.getFrame(frame%self.animateDead.numFrames);
						B.shadelessBoneMaterialBackend.setPose(pose);
						mesh.render(rc);
					}
					foreach(j;0..objects.animateDeadEffects.length) renderAnimateDead(objects.animateDeadEffects[j]);
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.hellmouthProjectiles.length){
					auto material=self.hellmouthProjectile.material;
					material.bind(rc);
					B.disableCulling();
					scope(success){
						B.enableCulling();
						material.unbind(rc);
					}
					B.shadelessBoneMaterialBackend.setTransformation(Vector3f(0.0f,0.0f,0.0f),Quaternionf.identity(),rc);
					auto mesh=self.hellmouthProjectile.mesh;
					void renderHellmouthProjectile(ref HellmouthProjectile!B hellmouthProjectile){
						Matrix4x4f[self.hellmouthProjectile.numSegments+1] pose;
						foreach(i,ref x;pose){
							auto curve=hellmouthProjectile.get(i/float(pose.length-1));
							auto rotation=rotationBetween(Vector3f(0.0f,0.0f,1.0f),curve[1].normalized);
							x=Transformation(rotation,curve[0]).getMatrix4f;
						}
						auto mesh=self.hellmouthProjectile.mesh;
						B.shadelessBoneMaterialBackend.setPose(pose);
						mesh.render(rc);
					}
					foreach(j;0..objects.hellmouthProjectiles.length) renderHellmouthProjectile(objects.hellmouthProjectiles[j]);
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&(objects.dragonfireCastings.length||objects.dragonfires.length)){
					B.disableDepthMask();
					B.disableCulling();
					scope(success){
						B.enableCulling();
						B.enableDepthMask();
					}
					foreach(i,mat;self.dragonfire.obj.materials){
						B.shadelessMorphMaterialBackend.bind(mat,rc);
						B.enableTransparency();
						scope(success) B.shadelessMorphMaterialBackend.unbind(mat,rc);
						void renderDragonfire(Vector3f position,Vector3f direction,int frame,float scale){
							auto mesh1Mesh2Progress=self.dragonfire.getFrame(frame%self.dragonfire.numFrames);
							auto mesh1=mesh1Mesh2Progress[0], mesh2=mesh1Mesh2Progress[1], progress=mesh1Mesh2Progress[2];
							assert(mesh1.length==mesh2.length&&mesh1.length==self.dragonfire.obj.materials.length);
							auto intermediate=Vector3f(direction.x,direction.y,0.0f).normalized;
							auto rotation=rotationBetween(intermediate,direction)*rotationBetween(Vector3f(0.0f,1.0f,0.0f),intermediate);
							B.shadelessMorphMaterialBackend.setTransformationScaled(position,rotation,scale*Vector3f(1.0f,1.0f,1.0f),rc);
							B.shadelessMorphMaterialBackend.setMorphProgress(progress);
							mesh1[i].morph(mesh2[i],rc);
						}
						foreach(ref dragonfireCasting;objects.dragonfireCastings) with(dragonfireCasting) renderDragonfire(dragonfire.position,dragonfire.direction,dragonfire.frame,scale);
						foreach(ref dragonfire;objects.dragonfires) renderDragonfire(dragonfire.position,dragonfire.direction,dragonfire.frame,dragonfire.scale);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&(objects.soulWindCastings.length||objects.soulWinds.length)){
					auto material=self.soulWind.material;
					material.bind(rc);
					B.disableCulling();
					scope(success){
						B.enableCulling();
						material.unbind(rc);
					}
					void renderSoulWind(ref SoulWind!B soulWind){
						auto frame=soulWind.frame;
						auto position=soulWind.position;
						auto rotation=facingQuaternion(2*pi!float*frame/(4*updateFPS));
						B.shadelessMaterialBackend.setTransformation(position,rotation,rc);
						auto mesh=self.soulWind.getFrame(frame%self.soulWind.numFrames);
						mesh.render(rc);
					}
					foreach(ref soulWindCasting;objects.soulWindCastings)
						renderSoulWind(soulWindCasting.soulWind);
					foreach(ref soulWind;objects.soulWinds)
						renderSoulWind(soulWind);
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.explosionCastings.length){
					B.disableDepthMask();
					B.enableCulling();
					scope(success){
						B.enableCulling();
						B.enableDepthMask();
					}
					auto material=self.explosionEffect.material;
					B.shadelessMorphMaterialBackend.bind(material,rc);
					B.enableTransparency();
					scope(success) B.shadelessMorphMaterialBackend.unbind(material,rc);
					void renderExplosionEffect(ref ExplosionEffect effect){
						auto frame=effect.frame;
						auto rotation=facingQuaternion(effect.rotationSpeed*frame/updateFPS);
						auto scale=effect.scale;
						auto radius=scale*effect.maxRadius;
						auto position=effect.position+Vector3f(0.0f,0.0f,radius);
						B.shadelessMorphMaterialBackend.setTransformationScaled(position,rotation,radius*Vector3f(1.1f,1.1f,0.9f),rc);
						foreach(v;0..3){ // TODO
							auto mesh1Mesh2Progress=self.explosionEffect.getFrame(frame+20*v,frame);
							auto mesh1=mesh1Mesh2Progress[0], mesh2=mesh1Mesh2Progress[1], progress=mesh1Mesh2Progress[2];
							B.shadelessMorphMaterialBackend.setMorphProgress(progress);
							mesh1.morph(mesh2,rc);
						}
					}
					foreach(ref explosionCasting;objects.explosionCastings)
						foreach(ref effect;explosionCasting.effects)
							renderExplosionEffect(effect);
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&& // TODO: cloud shadows?
														   (objects.rainOfFrogsCastings.length||
															objects.rainOfFrogss.length)
				){
					B.disableDepthMask();
					B.enableCulling();
					scope(success){
						B.enableCulling();
						B.enableDepthMask();
					}
					auto material=self.cloud.material;
					B.shadelessMorphMaterialBackend.bind(material,rc);
					B.enableTransparency();
					scope(success) B.shadelessMorphMaterialBackend.unbind(material,rc);
					void renderCloud(Vector3f position,float radius,float scale,int frame){
						B.shadelessMorphMaterialBackend.setTransformationScaled(position,Quaternionf.identity(),radius*(0.5f+0.5f*scale)*Vector3f(1.3f,1.3f,0.4f),rc);
						B.shadelessMorphMaterialBackend.setAlpha(scale);
						foreach(v;0..20){
							auto mesh1Mesh2Progress=self.cloud.getFrame(frame+4*updateFPS*v);
							auto mesh1=mesh1Mesh2Progress[0], mesh2=mesh1Mesh2Progress[1], progress=mesh1Mesh2Progress[2];
							B.shadelessMorphMaterialBackend.setMorphProgress(progress);
							mesh1.morph(mesh2,rc);
						}
					}
					foreach(ref rainOfFrogsCasting;objects.rainOfFrogsCastings)
						with(rainOfFrogsCasting.rainOfFrogs) renderCloud(position,spell.effectRange,cloudScale,cloudFrame);
					foreach(ref rainOfFrogs;objects.rainOfFrogss)
						with(rainOfFrogs) renderCloud(position,spell.effectRange,cloudScale,cloudFrame);
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.rainFrogs.length){
					auto material=self.rainFrog.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					foreach(j;0..objects.rainFrogs.length){
						auto position=objects.rainFrogs[j].position+Vector3f(0.0f,0.0f,0.5f*self.rainFrog.size);
						if(auto target=objects.rainFrogs[j].target){
							auto targetPositionTargetRotation=state.movingObjectById!((ref obj)=>tuple(obj.position,obj.rotation),()=>Tuple!(Vector3f,Quaternionf).init)(target);
							auto targetPosition=targetPositionTargetRotation[0], targetRotation=targetPositionTargetRotation[1];
							position=targetPosition+rotate(targetRotation,position);
						}
						auto frame=objects.rainFrogs[j].animationFrame;
						auto mesh=self.rainFrog.getFrame(frame%self.rainFrog.numFrames);
						material.backend.setSpriteTransformation(position,rc);
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.demonicRifts.length){
					auto material=self.demonicRiftSpirit.material;
					material.bind(rc);
					B.disableCulling();
					scope(success){
						B.enableCulling();
						material.unbind(rc);
					}
					B.shadelessBoneMaterialBackend.setTransformation(Vector3f(0.0f,0.0f,0.0f),Quaternionf.identity(),rc);
					void renderDemonicRiftSpirit(ref DemonicRiftSpirit!B demonicRiftSpirit){
						auto scale=demonicRiftSpirit.scale;
						auto frame=demonicRiftSpirit.frame;
						Matrix4x4f[self.demonicRiftSpirit.numSegments+1] pose;
						foreach(i,ref x;pose){
							auto progress=float(i)/self.demonicRiftSpirit.numSegments;
							auto curve=demonicRiftSpirit.get(progress);
							x=Transformation(rotationBetween(Vector3f(0.0f,0.0f,1.0f),curve[1].normalized),curve[0]).getMatrix4f;
							foreach(k;0..3) foreach(l;0..3) x.arrayof[k*4+l]*=scale;
							// TODO: scale
						}
						auto mesh=self.demonicRiftSpirit.getFrame(frame%self.demonicRiftSpirit.numFrames);
						B.shadelessBoneMaterialBackend.setPose(pose);
						mesh.render(rc);
					}
					foreach(ref demonicRift;objects.demonicRifts)
						foreach(ref spirit;demonicRift.spirits[demonicRift.numDespawned..demonicRift.numSpawned])
							renderDemonicRiftSpirit(spirit);
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&(objects.demonicRifts.length||objects.demonicRiftCastings.length)){
					auto material=self.demonicRiftBorder.material;
					material.bind(rc);
					B.disableCulling();
					scope(success){
						B.enableCulling();
						material.unbind(rc);
					}
					void renderDemonicRiftBorder(ref DemonicRift!B rift){
						auto position=rift.position;
						auto heightScale=rift.heightScale;
						auto radius=rift.radius;
						B.shadelessMaterialBackend.setTransformationScaled(position,Quaternionf.identity(),radius*Vector3f(1.0f,1.0f,heightScale),rc);
						B.shadelessMaterialBackend.setAlpha(heightScale^^2);
						auto mesh=self.demonicRiftBorder.getFrame(rift.frame%self.demonicRiftBorder.numFrames);
						mesh.render(rc);
					}
					foreach(j;0..objects.demonicRiftCastings.length) renderDemonicRiftBorder(objects.demonicRiftCastings[j].demonicRift);
					foreach(j;0..objects.demonicRifts.length) renderDemonicRiftBorder(objects.demonicRifts[j]);
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.demonicRiftEffects.length){
					auto material=self.demonicRiftEffect.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					foreach(j;0..objects.demonicRiftEffects.length){
						auto position=objects.demonicRiftEffects[j].position;
						//auto radius=objects.demonicRiftEffects[j].radius;
						auto radius=DemonicRift!B.radius;
						auto scale=objects.demonicRiftEffects[j].scale;
						B.shadelessMaterialBackend.setTransformationScaled(position,Quaternionf.identity(),scale*radius*Vector3f(1.0f,1.0f,1.0f),rc);
						B.shadelessMaterialBackend.setEnergy(20.0f*scale^^4);
						auto mesh=self.demonicRiftEffect.getFrame(objects.demonicRiftEffects[j].frame%self.demonicRiftEffect.numFrames);
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.healingAuras.length){
					B.disableDepthMask();
					B.enableCulling();
					auto material=self.healingAura.material;
					B.shadelessMorphMaterialBackend.bind(material,rc);
					B.enableAdditive();
					scope(success){
						B.enableDepthMask();
						B.shadelessMorphMaterialBackend.unbind(material,rc);
					}
					void renderHealingAura(ref HealingAura!B healingAura){
						auto target=healingAura.target;
						auto positionRotationBoxSize=state.movingObjectById!((ref obj)=>tuple(center(obj),obj.position,obj.rotation,boxSize(obj.sacObject.largeHitbox(Quaternionf.identity(),obj.animationState,obj.frame/updateAnimFactor))), function Tuple!(Vector3f,Vector3f,Quaternionf,Vector3f)(){ return typeof(return).init; })(target);
						auto position=positionRotationBoxSize[0], rawPosition=positionRotationBoxSize[1], rotation=positionRotationBoxSize[2], boxSize=positionRotationBoxSize[3];
						if(isNaN(position.x)) return;
						auto scale=healingAura.scale;//+0.05f*(1.0f*sin(2.0f*pi!float*2.0f*healingAura.frame/updateFPS));
						boxSize.x=boxSize.y=sqrt(0.5f*(boxSize.x^^2+boxSize.y^^2));
						auto dimensions=Vector3f(1.9f,1.9f,1.45f)*boxSize;
						B.shadelessMorphMaterialBackend.setTransformationScaled(position,rotation,-scale*dimensions,rc);
						foreach(v;0..3){
							auto mesh1Mesh2Progress=self.healingAura.getFrame(healingAura.frame+20*v,healingAura.frame);
							auto mesh1=mesh1Mesh2Progress[0], mesh2=mesh1Mesh2Progress[1], progress=mesh1Mesh2Progress[2];
							B.shadelessMorphMaterialBackend.setMorphProgress(progress);
							mesh1.morph(mesh2,rc);
						}
					}
					foreach(ref healingAura;objects.healingAuras) renderHealingAura(healingAura);
				}
				static if(mode==RenderMode.opaque) if(objects.spikes.length){
					auto material=self.spike.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					void renderSpike(float scale,Vector3f position,Vector3f direction){
						auto ndirection=direction/direction.z;
						auto modelMatrix=translationMatrix(position)*scaleMatrix(Vector3f(scale,scale,scale*direction.z))*shearMatrix(Axis.z,ndirection.x,ndirection.y);
						B.defaultMaterialBackend.setModelViewMatrix(rc.viewMatrix*modelMatrix);
						auto mesh=self.spike.mesh;
						mesh.render(rc);
					}
					foreach(ref spike;objects.spikes) renderSpike(spike.currentScale,spike.position,spike.direction);
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.brainiacEffects.length){
					auto material=self.brainiacEffect.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					foreach(j;0..objects.brainiacEffects.length){
						auto position=objects.brainiacEffects[j].position;
						auto rotation=rotationBetween(Vector3f(0.0f,0.0f,1.0f),objects.brainiacEffects[j].direction); // TODO: precompute this?
						auto frame=objects.brainiacEffects[j].frame;
						auto relativeProgress=float(frame)/self.brainiacEffect.numFrames;
						auto scale=1.0f+0.6f*relativeProgress^^2.5f;
						B.shadelessMaterialBackend.setTransformationScaled(position,rotation,scale*Vector3f(1.0f,1.0f,1.0f),rc);
						B.shadelessMaterialBackend.setAlpha(0.95f*(1.0f-relativeProgress)^^1.5f);
						auto mesh=self.brainiacEffect.getFrame(objects.brainiacEffects[j].frame%self.brainiacEffect.numFrames);
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.shrikeEffects.length){
					auto material=self.shrikeEffect.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					foreach(j;0..objects.shrikeEffects.length){
						auto position=objects.shrikeEffects[j].position;
						auto rotation=rotationBetween(Vector3f(0.0f,0.0f,1.0f),objects.shrikeEffects[j].direction); // TODO: precompute this?
						auto frame=objects.shrikeEffects[j].frame;
						auto relativeProgress=float(frame)/self.shrikeEffect.numFrames;
						auto scale=(1.0f+0.6f*relativeProgress^^2.5f)*objects.shrikeEffects[j].scale;
						B.shadelessMaterialBackend.setTransformationScaled(position,rotation,scale*Vector3f(1.0f,1.0f,1.0f),rc);
						B.shadelessMaterialBackend.setAlpha(0.95f*(1.0f-relativeProgress)^^2.0f);
						auto mesh=self.shrikeEffect.getFrame(objects.shrikeEffects[j].frame%self.shrikeEffect.numFrames);
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.spitfireEffects.length){
					auto fire=SacParticle!B.get(ParticleType.fire);
					auto material=fire.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					foreach(j;0..objects.spitfireEffects.length){
						auto position=objects.spitfireEffects[j].position;
						auto frame=objects.spitfireEffects[j].frame;
						auto scale=objects.spitfireEffects[j].scale;
						material.backend.setSpriteTransformationScaled(position,scale,rc);
						auto mesh=fire.getMesh(objects.spitfireEffects[j].frame%fire.numFrames);
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.gargoyleEffects.length){
					auto rock=SacParticle!B.get(ParticleType.rock);
					auto material=rock.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					foreach(j;0..objects.gargoyleEffects.length){
						auto position=objects.gargoyleEffects[j].position;
						auto frame=objects.gargoyleEffects[j].frame;
						auto scale=objects.gargoyleEffects[j].scale;
						material.backend.setSpriteTransformationScaled(position,scale,rc);
						auto mesh=rock.getMesh(objects.gargoyleEffects[j].frame%rock.numFrames);
						mesh.render(rc);
					}
				}
				static foreach(arrow;["sylph","ranger"])
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&(mixin(`objects.`~arrow~`Effects`).length||mixin(`objects.`~arrow~`Projectiles`).length)){
					auto material=mixin(`self.arrow.`~arrow~`Material`);
					material.bind(rc);
					B.disableCulling();
					scope(success){
						B.enableCulling();
						material.unbind(rc);
					}
					foreach(j;0..mixin(`objects.`~arrow~`Effects`).length){
						auto id=mixin(`objects.`~arrow~`Effects`)[j].attacker;
						if(!state.isValidTarget(id,TargetType.creature)) continue;
						auto mesh=self.arrow.getFrame(mixin(`objects.`~arrow~`Effects`)[j].frame%(16*updateAnimFactor));
						// static void renderLoadedArrow(B)(ref MovingObject!B object,SacScene scene,Mesh mesh,ObjectState!B state,RenderInfo!B* info,B.RenderContext rc){
						// 	// implementation moved to outer scope due to compiler bug
						// }
						state.movingObjectById!(renderLoadedArrow!B,(){})(id,mesh,state,info,rc);
					}
					foreach(j;0..mixin(`objects.`~arrow~`Projectiles`).length){
						auto position=mixin(`objects.`~arrow~`Projectiles`)[j].position;
						auto velocity=mixin(`objects.`~arrow~`Projectiles`)[j].velocity;
						auto direction=velocity.normalized;
						auto rotation=rotationBetween(Vector3f(0.0f,0.0f,1.0f),direction);
						B.shadelessMaterialBackend.setTransformationScaled(position,rotation,Vector3f(1.0f,1.0f,1.6f),rc);
						auto mesh=self.arrow.getFrame(mixin(`objects.`~arrow~`Projectiles`)[j].frame%(16*updateAnimFactor));
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.basiliskEffects.length){
					auto material=self.basiliskEffect.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					foreach(j;0..objects.basiliskEffects.length){
						auto position=objects.basiliskEffects[j].position;
						auto rotation=rotationBetween(Vector3f(0.0f,0.0f,1.0f),objects.basiliskEffects[j].direction); // TODO: precompute this?
						auto frame=objects.basiliskEffects[j].frame;
						auto relativeProgress=float(frame)/self.basiliskEffect.numFrames;
						auto scale=1.0f+0.6f*relativeProgress^^2.5f;
						B.shadelessMaterialBackend.setTransformationScaled(position,rotation,scale*Vector3f(1.0f,1.0f,1.0f),rc);
						B.shadelessMaterialBackend.setAlpha(0.95f*(1.0f-relativeProgress)^^1.5f);
						auto mesh=self.basiliskEffect.getFrame(objects.basiliskEffects[j].frame%self.basiliskEffect.numFrames);
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&(objects.tickfernoProjectiles.length||objects.phoenixProjectiles.length)){
					auto material=self.laser.material;
					material.bind(rc);
					B.disableCulling();
					scope(success){
						B.enableCulling();
						material.unbind(rc);
					}
					void renderLaser(float scale,int frame,Vector3f start,Vector3f end){
						auto diff=end-start;
						auto len=diff.length;
						auto rotation=rotationBetween(Vector3f(0.0f,0.0f,1.0f),diff/len);
						//auto pulse=0.75f+0.25f*0.5f*(1.0f+sin(2.0f*pi!float*(frame%pulseFrames)/(pulseFrames-1)));
						B.shadelessBoneMaterialBackend.setTransformationScaled(start,rotation,Vector3f(scale,scale,len),rc);
						auto mesh=self.laser.getFrame(frame%self.laser.numFrames);
						Matrix4x4f[self.laser.numSegments+1] pose;
						pose[0]=pose[self.laser.numSegments]=Matrix4f.identity();
						foreach(i,ref x;pose[1..$-1]){
							auto curve=Vector3f(0.0f,0.0f,0.0f);
							if(i+1==pose[1..$-1].length) curve.z=(1.0f/3.0f)*max(0.0f,1.0f-2.0f/len);
							x=Transformation(Quaternionf.identity(),curve).getMatrix4f;
						}
						B.shadelessBoneMaterialBackend.setPose(pose);
						mesh.render(rc);
					}
					foreach(ref projectile;objects.tickfernoProjectiles) renderLaser(2.0f/3.0f,projectile.frame,projectile.startPosition,projectile.position);
					foreach(ref projectile;objects.phoenixProjectiles) renderLaser(2.0f/3.0f,projectile.frame,projectile.startPosition,projectile.position);
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&(objects.tickfernoEffects.length||objects.vortickEffects.length||objects.phoenixEffects.length)){
					auto material=self.tube.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					void renderTube(Vector3f position,Vector3f direction,int frame,float scale_,float ltfactor=1.0f){
						auto rotation=rotationBetween(Vector3f(0.0f,0.0f,1.0f),direction); // TODO: precompute this?
						auto relativeProgress=float(frame)/(ltfactor*self.tube.numFrames);
						auto scale=scale_*(1.0f+0.6f*relativeProgress^^2.5f);
						B.shadelessMaterialBackend.setTransformationScaled(position,rotation,scale*Vector3f(1.0f,1.0f,1.0f),rc);
						B.shadelessMaterialBackend.setAlpha(0.95f*(1.0f-relativeProgress)^^1.5f);
						auto mesh=self.tube.getFrame(frame%self.tube.numFrames);
						mesh.render(rc);
					}
					foreach(ref effect;objects.tickfernoEffects.data) renderTube(effect.position,effect.direction,effect.frame,1.2f,2.0f);
					foreach(ref effect;objects.vortickEffects.data) renderTube(effect.position,effect.direction,effect.frame,0.6f,2.0f);
					foreach(ref effect;objects.phoenixEffects.data) renderTube(effect.position,effect.direction,effect.frame,1.2f,2.0f);
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.vortexEffects.length){
					auto material=self.vortexEffect.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					foreach(ref effect;objects.vortexEffects.data){
						foreach(ref particle;effect.particles.data){
							auto position=particle.position;
							auto frame=particle.frame;
							auto scale=(0.6f+0.4f*frame/(effect.duration*updateFPS)*particle.scale);
							B.shadelessMaterialBackend.setSpriteTransformationScaled(effect.position+position,scale,rc);
							auto alpha=(1.0f-1.0f*effect.frame/(effect.duration*updateFPS))^^2;
							B.shadelessMaterialBackend.setAlpha(alpha);
							auto mesh=self.vortexEffect.getFrame(frame%self.vortexEffect.numFrames);
							mesh.render(rc);
						}
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.squallEffects.length){
					auto material=self.squallEffect.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					void renderSquallEffect(Vector3f position,Vector3f direction,int frame,float scale_,float ltfactor=1.0f){
						auto rotation=rotationBetween(Vector3f(0.0f,0.0f,1.0f),direction); // TODO: precompute this?
						auto relativeProgress=float(frame)/(ltfactor*self.squallEffect.numFrames);
						auto scale=scale_*(1.0f+1.0f*relativeProgress^^2.5f);
						B.shadelessMaterialBackend.setTransformationScaled(position,rotation,scale*Vector3f(1.0f,1.0f,1.0f),rc);
						B.shadelessMaterialBackend.setAlpha(0.95f*(1.0f-relativeProgress)^^1.5f);
						auto mesh=self.squallEffect.getFrame(frame%self.squallEffect.numFrames);
						mesh.render(rc);
					}
					foreach(ref effect;objects.squallEffects.data) renderSquallEffect(effect.position,effect.direction,effect.frame,0.6f,2.0f);
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.pyromaniacRockets.length){
					auto material=self.pyromaniacRocket.material;
					material.bind(rc);
					B.disableCulling();
					scope(success){
						B.enableCulling();
						material.unbind(rc);
					}
					void renderPyromaniacRocket(Vector3f position,Vector3f direction,int frame){
						auto rotation=rotationBetween(Vector3f(0.0f,0.0f,1.0f),direction); // TODO: precompute this?
						B.shadelessMaterialBackend.setTransformation(position,rotation,rc);
						auto mesh=self.pyromaniacRocket.getFrame(frame%self.pyromaniacRocket.numFrames);
						mesh.render(rc);
					}
					foreach(ref effect;objects.pyromaniacRockets.data) renderPyromaniacRocket(effect.position,effect.direction,effect.frame);
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.gnomeEffects.length){
					auto material=self.gnomeEffect.material;
					material.bind(rc);
					B.disableCulling();
					scope(success){
						B.enableCulling();
						material.unbind(rc);
					}
					void renderGnomeEffect(Vector3f position,Vector3f direction,int frame){
						auto rotation=rotationBetween(Vector3f(0.0f,0.0f,1.0f),direction); // TODO: precompute this?
						B.shadelessMaterialBackend.setTransformation(position,rotation,rc);
						auto mesh=self.gnomeEffect.getFrame(frame%self.gnomeEffect.numFrames);
						mesh.render(rc);
					}
					foreach(ref effect;objects.gnomeEffects.data) renderGnomeEffect(effect.position,effect.direction,effect.frame);
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.warmongerGuns.length){
					auto material=self.warmongerEffect.material;
					material.bind(rc);
					B.disableCulling();
					scope(success){
						B.enableCulling();
						material.unbind(rc);
					}
					void renderWarmongerEffect(Vector3f position,Vector3f direction,int frame){
						auto rotation=rotationBetween(Vector3f(0.0f,0.0f,1.0f),direction); // TODO: precompute this?
						B.shadelessMaterialBackend.setTransformation(position,rotation,rc);
						auto mesh=self.warmongerEffect.getFrame(frame%self.warmongerEffect.numFrames);
						mesh.render(rc);
					}
					foreach(ref effect;objects.warmongerGuns.data) renderWarmongerEffect(effect.position,effect.direction,effect.frame);
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.poisonDarts.length){
					auto material=self.poisonDart.material;
					material.bind(rc);
					B.disableCulling();
					scope(success){
						B.enableCulling();
						material.unbind(rc);
					}
					void renderPoisonDart(Vector3f position,Vector3f direction){
						auto rotation=rotationBetween(Vector3f(0.0f,0.0f,1.0f),direction); // TODO: precompute this?
						B.shadelessMaterialBackend.setTransformation(position,rotation,rc);
						auto mesh=self.poisonDart.mesh;
						mesh.render(rc);
					}
					foreach(ref effect;objects.poisonDarts.data) renderPoisonDart(effect.position,effect.direction);
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.mutantProjectiles.length){
					auto material=self.mutantProjectile.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					foreach(j;0..objects.mutantProjectiles.length){
						auto position=objects.mutantProjectiles[j].position;
						auto frame=objects.mutantProjectiles[j].frame;
						auto mesh=self.mutantProjectile.getFrame(frame%self.mutantProjectile.numFrames);
						material.backend.setSpriteTransformation(position,rc);
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.abominationProjectiles.length){
					auto material=self.abominationProjectile.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					foreach(j;0..objects.abominationProjectiles.length){
						auto position=objects.abominationProjectiles[j].position;
						auto frame=objects.abominationProjectiles[j].frame;
						auto mesh=self.abominationProjectile.getFrame(frame%self.abominationProjectile.numFrames);
						material.backend.setSpriteTransformation(position,rc);
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.abominationDroplets.length){
					auto sacParticle=SacParticle!B.get(ParticleType.blood);
					auto frame=10; // TODO: ok?
					auto material=sacParticle.material;
					material.bind(rc);
					B.shadelessMaterialBackend.setEnergy(10.0f);
					scope(success) material.unbind(rc);
					auto mesh=sacParticle.getMesh(frame);
					foreach(j;0..objects.abominationDroplets.length){
						auto position=objects.abominationDroplets[j].position;
						material.backend.setSpriteTransformation(position,rc);
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.bombardProjectiles.length){
					auto material=self.bombardProjectile.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					foreach(j;0..objects.bombardProjectiles.length){
						auto position=objects.bombardProjectiles[j].position;
						auto frame=objects.bombardProjectiles[j].frame;
						auto mesh=self.bombardProjectile.getFrame(frame%self.bombardProjectile.numFrames);
						material.backend.setSpriteTransformation(position,rc);
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.flurryProjectiles.length){
					auto material=self.flurryProjectile.material;
					material.bind(rc);
					B.disableCulling();
					scope(success){
						B.enableCulling();
						material.unbind(rc);
					}
					foreach(j;0..objects.flurryProjectiles.length){
						auto position=objects.flurryProjectiles[j].position;
						auto rotation=objects.flurryProjectiles[j].rotation;
						auto mesh=self.flurryProjectile.mesh;
						material.backend.setTransformation(position,rotation,rc);
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.flurryImplosions.length){
					auto material=self.flurryImplosion.material;
					material.bind(rc);
					B.disableCulling();
					scope(success){
						B.enableCulling();
						material.unbind(rc);
					}
					foreach(j;0..objects.flurryImplosions.length){
						auto position=objects.flurryImplosions[j].position;
						auto scale=objects.flurryImplosions[j].scale*Vector3f(1.1f,1.1f,0.9f);
						auto mesh=self.flurryImplosion.mesh;
						material.backend.setTransformationScaled(position,Quaternionf.identity(),scale,rc);
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.silverbackEffects.length){
					auto cold=SacParticle!B.get(ParticleType.cold);
					auto material=cold.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					foreach(j;0..objects.silverbackEffects.length){
						auto position=objects.silverbackEffects[j].position;
						auto frame=objects.silverbackEffects[j].frame;
						auto scale=objects.silverbackEffects[j].scale;
						material.backend.setSpriteTransformationScaled(position,scale,rc);
						auto mesh=cold.getMesh(objects.silverbackEffects[j].frame%cold.numFrames);
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.lifeShields.length){
					auto material=self.lifeShield.material;
					material.bind(rc);
					B.disableCulling();
					scope(success){
						B.enableCulling();
						material.unbind(rc);
					}
					foreach(j;0..objects.lifeShields.length){
						auto target=objects.lifeShields[j].target;
						auto positionRotationBoxSize=state.movingObjectById!((ref obj)=>tuple(center(obj),obj.rotation,boxSize(obj.sacObject.largeHitbox(Quaternionf.identity(),obj.animationState,obj.frame/updateAnimFactor))), function Tuple!(Vector3f,Quaternionf,Vector3f)(){ return typeof(return).init; })(target);
						auto position=positionRotationBoxSize[0], rotation=positionRotationBoxSize[1], boxSize=positionRotationBoxSize[2];
						if(isNaN(position.x)) continue;
						auto scale=objects.lifeShields[j].scale;
						material.backend.setTransformationScaled(position,rotation,scale*1.4f*boxSize,rc);
						auto mesh=self.lifeShield.getFrame(objects.lifeShields[j].frame%self.lifeShield.numFrames);
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.divineSights.length){
					auto material=self.divineSight.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					foreach(j;0..objects.divineSights.length){
						auto position=objects.divineSights[j].position;
						auto frame=objects.divineSights[j].frame;
						auto mesh=self.divineSight.getFrame(frame%self.divineSight.numFrames);
						auto scale=objects.divineSights[j].scale;
						auto alpha=scale^^2;
						material.backend.setSpriteTransformationScaled(position,scale,rc);
						material.backend.setAlpha(alpha);
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.blightMites.length){
					auto material=self.blightMite.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					foreach(j;0..objects.blightMites.length){
						auto position=objects.blightMites[j].position;
						if(auto target=objects.blightMites[j].target){
							auto targetPositionTargetRotation=state.movingObjectById!((ref obj)=>tuple(obj.position,obj.rotation),()=>Tuple!(Vector3f,Quaternionf).init)(target);
							auto targetPosition=targetPositionTargetRotation[0], targetRotation=targetPositionTargetRotation[1];
							position=targetPosition+rotate(targetRotation,position);
						}
						auto frame=objects.blightMites[j].frame;
						auto mesh=self.blightMite.getFrame(frame%self.blightMite.numFrames);
						auto alpha=objects.blightMites[j].alpha;
						material.backend.setSpriteTransformation(position,rc);
						material.backend.setAlpha(alpha);
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(objects.webPulls.length){
					auto material=self.cord.material;
					material.bind(rc);
					auto mesh=self.cord.mesh;
					void renderCord(Vector3f start,Vector3f end,float scale=1.0f){
						auto direction=end-start;
						auto len=direction.length;
						auto rotation=rotationBetween(Vector3f(0.0f,0.0f,1.0f),direction/len);
						B.shadelessMaterialBackend.setTransformationScaled(start,rotation,Vector3f(scale,scale,len),rc);
						mesh.render(rc);
					}
					foreach(ref webPull;objects.webPulls){
						if(!webPull.target) continue;
						auto start=state.movingObjectById!((ref obj)=>obj.shotPosition,()=>Vector3f.init)(webPull.creature);
						auto end=state.movingObjectById!((ref obj)=>obj.center,()=>Vector3f.init)(webPull.target);
						if(isNaN(end.x)) continue;
						auto α=min(1.0f,float(webPull.frame)/webPull.numShootFrames);
						renderCord(start,(1-α)*start+α*end);
					}
					material.unbind(rc);
					material=self.web.material;
					material.bind(rc);
					mesh=self.web.mesh;
					void renderWeb(int target,float scale){
						if(!target) return;
						auto positionRotationBoxSize=state.movingObjectById!((ref obj)=>tuple(center(obj),obj.rotation,boxSize(obj.sacObject.largeHitbox(Quaternionf.identity(),obj.animationState,obj.frame/updateAnimFactor))), function Tuple!(Vector3f,Quaternionf,Vector3f)(){ return typeof(return).init; })(target);
						auto position=positionRotationBoxSize[0], rotation=positionRotationBoxSize[1], boxSize=positionRotationBoxSize[2];
						if(isNaN(position.x)) return;
						material.backend.setTransformationScaled(position,rotation,scale*1.4f*boxSize,rc);
						mesh.render(rc);
					}
					foreach(ref webPull;objects.webPulls){
						auto scale=max(0.0f,min(1.0f,float(webPull.frame-webPull.numShootFrames)/webPull.numGrowFrames));
						renderWeb(webPull.target,scale);
					}
					material.unbind(rc);
				}
				static if(mode==RenderMode.transparent) if(objects.cagePulls.length){
					auto material=self.cage.material;
					material.bind(rc);
					void renderCage(int target,int frame,float scale){
						if(!target) return;
						auto positionRotationBoxSize=state.movingObjectById!((ref obj)=>tuple(center(obj),obj.rotation,boxSize(obj.sacObject.largeHitbox(Quaternionf.identity(),obj.animationState,obj.frame/updateAnimFactor))), function Tuple!(Vector3f,Quaternionf,Vector3f)(){ return typeof(return).init; })(target);
						auto position=positionRotationBoxSize[0], rotation=positionRotationBoxSize[1], boxSize=positionRotationBoxSize[2];
						if(isNaN(position.x)) return;
						material.backend.setTransformationScaled(position,rotation,scale*1.4f*boxSize,rc);
						auto mesh=self.cage.getFrame(frame%self.cage.numFrames);
						mesh.render(rc);
					}
					foreach(ref cagePull;objects.cagePulls){
						auto scale=max(0.0f,min(1.0f,float(cagePull.frame-cagePull.numShootFrames)/cagePull.numGrowFrames));
						renderCage(cagePull.target,cagePull.frame,scale);
					}
					material.unbind(rc);
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&objects.stickyBombs.length){
					auto material=self.stickyBomb.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					foreach(j;0..objects.stickyBombs.length){
						auto position=objects.stickyBombs[j].position;
						if(auto target=objects.stickyBombs[j].target){
							auto targetPositionTargetRotation=state.movingObjectById!((ref obj)=>tuple(obj.position,obj.rotation),()=>Tuple!(Vector3f,Quaternionf).init)(target);
							auto targetPosition=targetPositionTargetRotation[0], targetRotation=targetPositionTargetRotation[1];
							position=targetPosition+rotate(targetRotation,position);
						}
						auto frame=objects.stickyBombs[j].frame;
						auto mesh=self.stickyBomb.getFrame(frame%self.stickyBomb.numFrames);
						auto scale=objects.stickyBombs[j].scale;
						material.backend.setSpriteTransformationScaled(position,scale*Vector3f(1.0f,1.0f,1.0f),rc);
						mesh.render(rc);
					}
				}
				static if(mode==RenderMode.transparent) if(!rc.shadowMode&&(objects.oilProjectiles.length||objects.oils.length)){
					auto material=self.oil.material;
					material.bind(rc);
					scope(success) material.unbind(rc);
					foreach(j;0..objects.oilProjectiles.length){
						auto position=objects.oilProjectiles[j].position;
						auto frame=objects.oilProjectiles[j].frame;
						auto mesh=self.oil.getFrame(frame%self.oil.numFrames);
						//auto scale=objects.oilProjectiles[j].scale;
						//material.backend.setSpriteTransformationScaled(position,scale*Vector3f(1.0f,1.0f,1.0f),rc);
						material.backend.setSpriteTransformation(position,rc);
						mesh.render(rc);
					}
					foreach(j;0..objects.oils.length){
						import std.random:MinstdRand0,uniform;
						auto rng=MinstdRand0(1);
						auto creature=objects.oils[j].creature;
						auto alpha=objects.oils[j].alpha;
						auto frame=objects.oils[j].frame;
						auto hitboxScale=state.movingObjectById!((ref obj)=>tuple(obj.hitbox,obj.getScale.length),()=>Tuple!(Vector3f[2],float).init)(creature);
						auto hitbox=hitboxScale[0], scale=hitboxScale[1];
						if(isNaN(hitbox[0].x)) continue;
						enum numParticles=10;
						foreach(_;0..numParticles){
							Vector3f position;
							foreach(i,ref x;position) x=uniform(hitbox[0][i],hitbox[1][i],rng);
							auto mesh=self.oil.getFrame((frame+uniform(0,self.oil.numFrames-1,rng))%self.oil.numFrames);
							material.backend.setSpriteTransformationScaled(position,0.5f*scale*Vector3f(1.0f,1.0f,1.0f),rc);
							material.backend.setAlpha(alpha);
							mesh.render(rc);
						}
					}
				}
			}else static if(is(T==Particles!(B,relative,sideFiltered),bool relative,bool sideFiltered)){
				static if(mode==RenderMode.transparent){
					if(rc.shadowMode) return; // TODO: particle shadows?
					auto sacParticle=objects.sacParticle;
					if(!sacParticle) return; // TODO: get rid of this?
					auto material=sacParticle.material;
					material.bind(rc);
					material.backend.setInformation(Vector4f(0.0f,0.0f,0.0f,0.0f));
					scope(success) material.unbind(rc);
					foreach(j;0..objects.length){
						static if(sideFiltered){
							if(objects.sideFilters[j]!=info.renderSide)
								continue;
						}
						auto mesh=sacParticle.getMesh(objects.frames[j]); // TODO: do in shader?
						static if(relative){
							auto position=objects.rotates[j]?state.movingObjectById!((obj,particlePosition)=>rotate(obj.rotation,particlePosition)+obj.position,()=>Vector3f(0.0f,0.0f,0.0f))(objects.baseIds[j],objects.positions[j])
								: objects.positions[j]+state.movingObjectById!((obj)=>obj.position,()=>Vector3f(0.0f,0.0f,0.0f))(objects.baseIds[j]);
						}
						else auto position=objects.positions[j];
						material.backend.setSpriteTransformationScaled(position,objects.scales[j]*sacParticle.getScale(objects.lifetimes[j]),rc);
						material.backend.setAlpha(sacParticle.getAlpha(objects.lifetimes[j]));
						mesh.render(rc);
					}
				}
			}else static if(is(T==CommandCones!B)) with(self){
				static if(mode==RenderMode.transparent){
					if(rc.shadowMode) return;
					if(objects.cones.length<=info.renderSide) return;
					if(iota(CommandConeColor.max+1).map!(i=>objects.cones[info.renderSide][i].length).all!(l=>l==0)) return;
					sacCommandCone.material.bind(rc);
					assert(sacCommandCone.material.backend is B.shadelessMaterialBackend);
					B.shadelessMaterialBackend.setInformation(Vector4f(0.0f,0.0f,0.0f,0.0f));
					scope(success) sacCommandCone.material.unbind(rc);
					enum maxLifetime=cast(int)(sacCommandCone.lifetime*updateFPS);
					foreach(i;0..CommandConeColor.max+1){
						if(objects.cones[info.renderSide][i].length==0) continue;
						auto color=sacCommandCone.colors[i];
						auto energy=0.4f*(3.0f/(color.r+color.g+color.b))^^4;
						B.shadelessMaterialBackend.setEnergy(energy);
						B.shadelessMaterialBackend.setColor(color);
						foreach(j;0..objects.cones[info.renderSide][i].length){
							auto dat=objects.cones[info.renderSide][i][j];
							auto position=dat.position;
							auto rotation=facingQuaternion(dat.lifetime);
							auto fraction=(1.0f-cast(float)dat.lifetime/maxLifetime);
							B.shadelessMaterialBackend.setAlpha(sacCommandCone.getAlpha(fraction));
							auto vertScaling=1.0f+0.25f*fraction;
							auto horzScaling=1.0f+2.0f*fraction;
							auto scaling=Vector3f(horzScaling,horzScaling,vertScaling);
							B.shadelessMaterialBackend.bindDiffuse(sacCommandCone.texture);
							B.shadelessMaterialBackend.setTransformationScaled(position, rotation, scaling, rc);
							sacCommandCone.mesh.render(rc);
							enum numShells=8;
							enum scalingFactor=0.95f;
							foreach(k;0..numShells){
								horzScaling*=scalingFactor;
								rotation=facingQuaternion((k&1?-1.0f:1.0f)*2.0f*pi!float*fraction*(k+1));
								scaling=Vector3f(horzScaling,horzScaling,vertScaling);
								if(k+1==numShells) B.shadelessMaterialBackend.bindDiffuse(self.whiteTexture);
								B.shadelessMaterialBackend.setTransformationScaled(position, rotation, scaling, rc);
								sacCommandCone.mesh.render(rc);
							}
						}
					}
				}
			}else static assert(0);
		}
		state.eachByType!(render,EachByTypeFlags.movingFirst|EachByTypeFlags.particlesBeforeEffects)(&this,options.enableWidgets,state,&info,rc);
	}

	bool selectionUpdated=false;
	CreatureGroup renderedSelection;
	CreatureGroup rectangleSelection;
	void renderCreatureStats(ObjectState!B state,ref RenderInfo!B info,B.RenderContext rc){
		bool updateRectangleSelect=false;
		if(info.renderSide!=-1){
			updateRectangleSelect=!selectionUpdated&&info.mouse.status==Mouse!B.Status.rectangleSelect&&!info.mouse.dragging;
			if(updateRectangleSelect){
				rectangleSelection=CreatureGroup.init;
				if(info.mouse.additiveSelect) renderedSelection=state.getSelection(info.renderSide);
				else renderedSelection=CreatureGroup.init;
			}else if(!selectionUpdated) renderedSelection=state.getSelection(info.renderSide);
		}else renderedSelection=CreatureGroup.init;
		rc.information=Vector4f(0.0f,0.0f,0.0f,0.0f);
		B.shadelessMaterialBackend.bind(null,rc);
		scope(success) B.shadelessMaterialBackend.unbind(null,rc);
		static void renderCreatureStat(B)(ref MovingObject!B obj,Renderer!B* self,bool healthAndMana,ObjectState!B state,ref RenderInfo!B info,B.RenderContext rc){
			if(obj.creatureState.mode.among(CreatureMode.dying,CreatureMode.dead,CreatureMode.dissolving,CreatureMode.firewalk)) return;
			if(info.renderSide!=obj.side&&(!obj.creatureState.mode.isVisibleToAI||obj.creatureStats.effects.stealth)) return;
			auto backend=B.shadelessMaterialBackend;
			backend.bindDiffuse(self.sacHud.statusArrows);
			backend.setColor(state.sides.sideColor(obj.side));
			// TODO: how is this actually supposed to work?
			import animations;
			auto hitbox0=obj.sacObject.hitbox(obj.rotation,AnimationState.stance1,0);
			auto hitbox=obj.sacObject.hitbox(obj.rotation,obj.animationState,obj.frame/updateAnimFactor);
			auto scaling=1.0f;
			auto position=obj.position+Vector3f(0.5f*(hitbox[0].x+hitbox[1].x),0.5f*(hitbox[0].y+hitbox[1].y),0.5f*(hitbox[0].z+hitbox[1].z)+0.75f*(hitbox0[1].z-hitbox0[0].z)+0.5f*scaling);
			backend.setSpriteTransformationScaled(position,scaling,rc);
			self.sacHud.statusArrowMeshes[0].render(rc);
			if(healthAndMana){
				backend.bindDiffuse(self.whiteTexture);
				enum width=92.0f/64.0f, height=10.0f/64.0f, gap=3.0f/64.0f;
				Vector3f fixPre(Vector3f prescaling){ // TODO: This is a hack. get rid of this.
					prescaling.x/=1.25f;
					return prescaling;
				}
				if(obj.creatureStats.maxHealth!=0.0f){
					Vector3f offset=Vector3f(0.0f,0.5f*height+0.5f,0.0f);
					Vector3f prescaling=Vector3f(width,height,0.0f);
					backend.setSpriteTransformationScaledPreprocess(position,scaling,offset,fixPre(prescaling),rc);
					backend.setColor(Color4f(0.5f,0.0f,0.0f));
					backend.setEnergy(4.0f);
					self.sacHud.statusArrowMeshes[0].render(rc); // TODO: different mesh?
					prescaling=Vector3f(width*obj.creatureStats.health/obj.creatureStats.maxHealth,height,0.0f);
					backend.setSpriteTransformationScaledPreprocess(position,scaling,offset+Vector3f(-0.5f*(width-prescaling.x),0.0f,0.0f),fixPre(prescaling),rc);
					backend.setColor(Color4f(1.0f,0.0f,0.0f));
					backend.setEnergy(8.0f);
					self.sacHud.statusArrowMeshes[0].render(rc); // TODO: different mesh?
				}
				if(obj.creatureStats.maxMana!=0.0f){
					Vector3f offset=Vector3f(0.0f,1.5f*height+gap+0.5f,0.0f);
					Vector3f prescaling=Vector3f(width,height,0.0f);
					backend.setSpriteTransformationScaledPreprocess(position,scaling,offset,fixPre(prescaling),rc);
					backend.setColor(Color4f(0.0f,0.25f,0.5f));
					backend.setEnergy(2.5f);
					self.sacHud.statusArrowMeshes[0].render(rc); // TODO: different mesh?
					prescaling=Vector3f(width*obj.creatureStats.mana/obj.creatureStats.maxMana,height,0.0f);
					backend.setSpriteTransformationScaledPreprocess(position,scaling,offset+Vector3f(-0.5f*(width-prescaling.x),0.0f,0.0f),fixPre(prescaling),rc);
					backend.setColor(Color4f(0.0f,0.5f,1.0f));
					backend.setEnergy(5.0f);
					self.sacHud.statusArrowMeshes[0].render(rc); // TODO: different mesh?
				}
			}
		}
		static void renderOtherSides(B)(MovingObject!B obj,Renderer!B* self,bool updateRectangleSelect,ObjectState!B state,RenderInfo!B* info,B.RenderContext rc){
			if(updateRectangleSelect){
				if(info.mouse.loc==Mouse!B.Location.minimap){
					// TODO: get rid of code duplication somehow
					auto radius=self.minimapRadius(*info);
					auto minimapFactor=info.hudScaling/info.camera.minimapZoom;
					auto camPos=info.camera.position;
					auto mapRotation=facingQuaternion(-degtorad(info.camera.turn));
					auto minimapCenter=Vector3f(camPos.x,camPos.y,0.0f)+rotate(mapRotation,Vector3f(0.0f,info.camera.distance*3.73f,0.0f));
					auto mapCenter=Vector3f(info.width-radius,info.height-radius,0);
					auto relativePosition=obj.position-minimapCenter;
					auto iconOffset=rotate(mapRotation,minimapFactor*Vector3f(relativePosition.x,-relativePosition.y,0));
					auto iconCenter=mapCenter+iconOffset;
					if(self.isOnMinimap(iconCenter.xy,*info)&&self.isInRectangleSelect(iconCenter.xy,*info)&&canSelect(info.renderSide,obj.id,state))
						self.rectangleSelection.addSorted(obj.id);
				}else{
					auto hitbox=obj.sacObject.hitbox(obj.rotation,obj.animationState,obj.frame/updateAnimFactor); // TODO: share computation with some other place?
					auto center2d=transform(B.getModelViewProjectionMatrix(obj.position,obj.rotation),0.5f*(hitbox[0]+hitbox[1]));
					if(center2d.z>1.0f) return;
					auto screenPosition=Vector2f(0.5f*(center2d.x+1.0f)*info.width,0.5f*(1.0f-center2d.y)*info.height);
					if(self.isInRectangleSelect(screenPosition,*info)&&canSelect(info.renderSide,obj.id,state)) self.rectangleSelection.addSorted(obj.id);
				}
			}
			if(obj.side!=info.renderSide) renderCreatureStat!B(obj,self,false,state,*info,rc);
		}
		state.eachMoving!(renderOtherSides!B)(&this,updateRectangleSelect,state,&info,rc);
		if(updateRectangleSelect) renderedSelection.addFront(rectangleSelection.creatureIds[]);
		foreach(id;renderedSelection.creatureIds)
			if(id) state.movingObjectById!(renderCreatureStat!B,(){})(id,&this,true,state,info,rc);
	}

	B.Mesh boxMesh=null;
	void renderBox(Vector3f[2] sl,bool wireframe,B.RenderContext rc){
		if(wireframe) B.enableWireframe();
		if(!boxMesh) boxMesh=makeBoxMesh!B(1.0f,1.0f,1.0f);
		hitboxMaterial.backend.setTransformationScaled(boxCenter(sl), Quaternionf.identity(), boxSize(sl), rc);
		boxMesh.render(rc);
		if(wireframe) B.disableWireframe();
	}
	bool showHitboxes=false;
	B.Material hitboxMaterial=null;
	void renderHitboxes(ObjectState!B state,ref RenderInfo!B info,B.RenderContext rc){
		static void render(T)(ref T objects,Renderer!B* self,ObjectState!B state,RenderInfo!B* info,B.RenderContext rc){
			enum isMoving=is(T==MovingObjects!(B, renderMode), RenderMode renderMode);
			enum isStatic=is(T==StaticObjects!(B, renderMode), RenderMode renderMode);
			static if(isMoving){
				auto sacObject=objects.sacObject;
				foreach(j;0..objects.length){
					auto hitbox=sacObject.hitbox(objects.rotations[j],objects.animationStates[j],objects.frames[j]/updateAnimFactor);
					hitbox[0]+=objects.positions[j];
					hitbox[1]+=objects.positions[j];
					self.renderBox(hitbox,true,rc);
					auto meleeHitbox=sacObject.meleeHitbox(objects.rotations[j],objects.animationStates[j],objects.frames[j]/updateAnimFactor);
					meleeHitbox[0]+=objects.positions[j];
					meleeHitbox[1]+=objects.positions[j];
					self.renderBox(meleeHitbox,true,rc);
					/+auto hands=sacObject.hands(objects.animationStates[j],objects.frames[j]/updateAnimFactor);
					foreach(i;0..2){
						if(hands[i] is Vector3f.init) continue;
						hands[i]=objects.positions[j]+rotate(objects.rotations[j],hands[i]);
						Vector3f[2] nbox;
						nbox=[hands[i]-(0.2*Vector3f(1,1,1)),hands[i]+(0.2*Vector3f(1,1,1))];
						renderBox(nbox,false,rc);
					}+/
					/+foreach(i;1..sacObject.saxsi.saxs.bones.length){
						auto bhitbox=sacObject.saxsi.saxs.bones[i].hitbox;
						foreach(ref x;bhitbox){
							x=objectrs.positions[j]+rotate(objects.rotations[j],x*sacObject.animations[objects.animationStates[j]].frames[objects.frames[j]/updateAnimFactor].matrices[i]);
						}
						if(i!=23&&i!=26) continue;
						//Vector3f[8] box=[Vector3f(-1,-1,-1),Vector3f(1,-1,-1),Vector3f(1,1,-1),Vector3f(-1,1,-1),Vector3f(-1,-1,1),Vector3f(1,-1,1),Vector3f(1,1,1),Vector3f(-1,1,1)];
						foreach(curVert;0..8){
							foreach(k;0..8){
								Vector3f[2] nbox;
								nbox=[bhitbox[curVert]-(0.05*Vector3f(1,1,1)),bhitbox[curVert]+(0.05*Vector3f(1,1,1))];
								renderBox(nbox,false,rc);
							}
						}
						/+Vector3f[8] hitbox=[Vector3f(-0.0730702, -0.0556806, 0),
						 Vector3f(0.22243, -0.0556806, 0),
						 Vector3f(-0.0730702, 0.0667194, 0),
						 Vector3f(0.22243, 0.0667194, 0),
						 Vector3f(0, -0.0556806, -0.247969),
						 Vector3f(0, -0.0556806, -0.0355686),
						 Vector3f(0, 0.0667194, -0.247969),
						 Vector3f(0, 0.0667194, -0.0355686)];+/
						//renderBox(hitbox,rc);
					}+/
				}
			}else static if(isStatic){
				auto sacObject=objects.sacObject;
				foreach(j;0..objects.length){
					foreach(hitbox;sacObject.hitboxes(objects.rotations[j])){
						hitbox[0]+=objects.positions[j];
						hitbox[1]+=objects.positions[j];
						self.renderBox(hitbox,true,rc);
					}
				}
			}
		}
		if(!hitboxMaterial){
			hitboxMaterial=B.makeMaterial(B.shadelessMaterialBackend);
			hitboxMaterial.diffuse=Color4f(1.0f,1.0f,1.0f,1.0f);
		}
		hitboxMaterial.bind(rc); scope(exit) hitboxMaterial.unbind(rc);
		state.eachByType!(render,EachByTypeFlags.none)(&this,state,&info,rc);
	}

	void renderFrame(Vector2f position,Vector2f size,Color4f color,ObjectState!B state,ref RenderInfo!B info,B.RenderContext rc){
		B.colorHUDMaterialBackend2.bind(null,rc);
		scope(success) B.colorHUDMaterialBackend2.unbind(null, rc);
		auto scaling=Vector3f(size.x,size.y,1.0f);
		B.colorHUDMaterialBackend2.setTransformationScaled(Vector3f(position.x,position.y,0.0f), Quaternionf.identity(), scaling, rc);
		B.colorHUDMaterialBackend2.setColor(color);
		border.render(rc);
	}

	static Vector2f[2] fixHitbox2dSize(Vector2f[2] position){
		auto center=0.5f*(position[0]+position[1]);
		auto size=position[1]-position[0];
		foreach(k;0..2) size[k]=max(size[k],48.0f);
		return [center-0.5f*size,center+0.5f*size];
	}

	void renderFrame(Vector3f[2] hitbox2d,Color4f color,ObjectState!B state,ref RenderInfo!B info,B.RenderContext rc){
		if(hitbox2d[0].z>1.0f) return;
		Vector2f[2] position=[Vector2f(0.5f*(hitbox2d[0].x+1.0f)*info.width,0.5f*(1.0f-hitbox2d[1].y)*info.height),
		                      Vector2f(0.5f*(hitbox2d[1].x+1.0f)*info.width,0.5f*(1.0f-hitbox2d[0].y)*info.height)];
		position=fixHitbox2dSize(position);
		auto size=position[1]-position[0];
		renderFrame(position[0],size,color,state,info,rc);
		info.mouse.inHitbox=info.mouse.loc==Mouse!B.Location.scene&&position[0].x<=info.mouse.x&&info.mouse.x<=position[1].x&&
			position[0].y<=info.mouse.y&&info.mouse.y<=position[1].y;
	}

	void renderTargetFrame(ObjectState!B state,ref RenderInfo!B info,B.RenderContext rc){
		if(!info.mouse.showFrame) return;
		if(info.mouse.target.id&&!state.isValidTarget(info.mouse.target.id,info.mouse.target.type)) info.mouse.target=Target.init;
		if(info.mouse.target.type.among(TargetType.creature,TargetType.building)){
			static void renderHitbox(T)(T obj,Renderer!B* self,ObjectState!B state,RenderInfo!B* info,B.RenderContext rc){
				auto hitbox2d=obj.hitbox2d(B.getModelViewProjectionMatrix(obj.position,obj.rotation));
				static if(is(T==MovingObject!B)) auto objSide=obj.side;
				else auto objSide=sideFromBuildingId!B(obj.buildingId,state);
				auto color=state.sides.sideColor(objSide);
				self.renderFrame(hitbox2d,color,state,*info,rc);
			}
			state.objectById!renderHitbox(info.mouse.target.id,&this,state,&info,rc);
		}else if(info.mouse.target.type==TargetType.soul){
			static void renderHitbox(B)(Soul!B soul,Renderer!B* self,ObjectState!B state,RenderInfo!B* info,B.RenderContext rc){
				auto hitbox2d=soul.hitbox2d(B.getSpriteModelViewProjectionMatrix(soul.position+soul.scaling*Vector3f(0.0f,0.0f,1.25f*sacSoul.soulHeight)));
				auto color=soulFrameColor[soul.color(info.renderSide,state)];
				self.renderFrame(hitbox2d,color,state,*info,rc);
			}
			state.soulById!(renderHitbox!B,(){})(info.mouse.target.id,&this,state,&info,rc);
		}
	}
	bool isInRectangleSelect(Vector2f position,ref RenderInfo!B info){
		if(info.mouse.status!=Mouse!B.Status.rectangleSelect||info.mouse.dragging) return false;
		auto x1=min(info.mouse.leftButtonX,info.mouse.x), x2=max(info.mouse.leftButtonX,info.mouse.x);
		auto y1=min(info.mouse.leftButtonY,info.mouse.y), y2=max(info.mouse.leftButtonY,info.mouse.y);
		return x1<=position.x&&position.x<=x2 && y1<=position.y&&position.y<=y2;
	}
	void renderRectangleSelectFrame(ref RenderInfo!B info,B.RenderContext rc){
		if(info.mouse.status!=Mouse!B.Status.rectangleSelect||info.mouse.dragging) return;
		auto x1=min(info.mouse.leftButtonX,info.mouse.x), x2=max(info.mouse.leftButtonX,info.mouse.x);
		auto y1=min(info.mouse.leftButtonY,info.mouse.y), y2=max(info.mouse.leftButtonY,info.mouse.y);
		auto color=Color4f(1.0f,1.0f,1.0f);
		if(info.mouse.loc==Mouse!B.Location.minimap){
			auto radius=minimapRadius(info);
			x1=max(x1,info.width-2.0f*radius);
			y1=max(y1,info.height-2.0f*radius);
			color=Color4f(1.0f,0.0f,0.0f);
		}
		auto rectWidth=x2-x1,rectHeight=y2-y1;
		B.colorHUDMaterialBackend.bind(null,rc);
		scope(success) B.colorHUDMaterialBackend.unbind(null,rc);
		B.colorHUDMaterialBackend.bindDiffuse(whiteTexture);
		B.colorHUDMaterialBackend.setColor(color);
		auto thickness=0.5f*info.hudScaling;
		auto scaling1=Vector3f(rectWidth+thickness,thickness,0.0f);
		auto position1=Vector3f(x1,y1,0.0f);
		auto position2=Vector3f(x1,y2,0.0f);
		B.colorHUDMaterialBackend.setTransformationScaled(position1, Quaternionf.identity(), scaling1, rc);
		quad.render(rc);
		B.colorHUDMaterialBackend.setTransformationScaled(position2, Quaternionf.identity(), scaling1, rc);
		quad.render(rc);
		auto scaling2=Vector3f(thickness,rectHeight+thickness,0.0f);
		auto position3=Vector3f(x1,y1,0.0f);
		auto position4=Vector3f(x2,y1,0.0f);
		B.colorHUDMaterialBackend.setTransformationScaled(position3, Quaternionf.identity(), scaling2, rc);
		quad.render(rc);
		B.colorHUDMaterialBackend.setTransformationScaled(position4, Quaternionf.identity(), scaling2, rc);
		quad.render(rc);
	}
	char[4] xmenuTargetId="\0\0\0\0";
	void updateXmenuTarget(char[4] targetId,Vector2f position,Vector2f scaling,ref RenderInfo!B info){
		if(!info.mouse.xmenuVisible) return;
		auto topLeft=position;
		auto bottomRight=position+scaling;
		if(floor(topLeft.x)<=info.mouse.x&&info.mouse.x<=ceil(bottomRight.x)
		   && floor(topLeft.y)<=info.mouse.y&&info.mouse.y<=ceil(bottomRight.y)){
			xmenuTargetId=targetId;
		}
	}
	void renderXmenu(ref RenderInfo!B info,B.RenderContext rc){
		auto hudScaling=info.hudScaling;
		float scale=32*hudScaling;
		float sparkleScale=40*hudScaling;
		xmenuTargetId="\0\0\0\0";
		if(info.mouse.xmenuMiddleTargetId=="\0\0\0\0")
			return;
		B.hudMaterialBackend.bind(null,rc);
		scope(exit) B.hudMaterialBackend.unbind(null, rc);
		void renderIcon(char[4] tag,Vector2f offset){
			if(tag=="\0\0\0\0") return;
			auto target=Target(TargetType.spell,0,Vector3f.init,TargetLocation.spellbook);
			auto position=Vector3f(info.mouse.xmenuOffsetX-0.5f*scale+offset.x,info.mouse.xmenuOffsetY-0.5f*scale+offset.y,0.0f);
			updateXmenuTarget(tag,position.xy,Vector2f(scale,scale),info);
			B.hudMaterialBackend.setTransformationScaled(position,Quaternionf.identity(),Vector3f(scale,scale,0.0f),rc);
			B.hudMaterialBackend.bindDiffuse(sacXmenu.get(tag).icon);
			B.hudMaterialBackend.setAlpha(1.0f);
			B.enableTransparency();
			quad.render(rc);
			B.hudMaterialBackend.bindDiffuse(sacXmenu.sparkleTexture);
			auto sparklePosition=Vector3f(info.mouse.xmenuOffsetX-0.5f*sparkleScale+offset.x,info.mouse.xmenuOffsetY-0.5f*sparkleScale+offset.y,0.0f);
			B.enableAdditive();
			B.hudMaterialBackend.setTransformationScaled(sparklePosition,Quaternionf.identity(),Vector3f(sparkleScale,sparkleScale,0.0f),rc);
			sacXmenu.sparkleMeshes[info.mouse.frame%$].render(rc);
		}
		import xmnu;
		char[4] transformTag(char[4] tag){
			if(tag==XmnuTag.center) return info.mouse.xmenuCenterTargetId;
			return tag;
		}
		renderIcon(info.mouse.xmenuMiddleTargetId,Vector2f(0.0f,0.0f));
		auto xmnux=sacXmenu.get(info.mouse.xmenuMiddleTargetId);
		auto up=xmnux.next[Xmnl.Dir.up];
		if(up!=-1) renderIcon(transformTag(sacXmenu.entries[up].xmnu.tag),Vector2f(0.0f,-scale));
		auto down=xmnux.next[Xmnl.Dir.down];
		if(down!=-1) renderIcon(transformTag(sacXmenu.entries[down].xmnu.tag),Vector2f(0.0f,scale));
		auto left=xmnux.next[Xmnl.Dir.left];
		if(left!=-1) renderIcon(transformTag(sacXmenu.entries[left].xmnu.tag),Vector2f(-scale,0.0f));
		auto right=xmnux.next[Xmnl.Dir.right];
		if(right!=-1) renderIcon(transformTag(sacXmenu.entries[right].xmnu.tag),Vector2f(scale,0.0f));
	}
	void renderCursor(int size,ObjectState!B state,ref RenderInfo!B info,B.RenderContext rc){
		if(info.mouse.xmenuVisible) renderXmenu(info,rc);
		float scale=size==-1?32*info.hudScaling:size;
		if(state&&info.mouse.target.location.among(TargetLocation.minimap,TargetLocation.scene)&&
		   info.mouse.target.id&&!state.isValidTarget(info.mouse.target.id,info.mouse.target.type))
			info.mouse.target=Target.init;
		auto position=Vector3f(info.mouse.x-0.5f*scale,info.mouse.y,0);
		if(info.mouse.status==Mouse!B.Status.rectangleSelect&&!info.mouse.dragging) position.y-=1.0f;
		auto scaling=Vector3f(scale,scale,1.0f);
		if(info.mouse.status==Mouse!B.Status.icon&&!info.mouse.dragging){
			auto iconPosition=position+Vector3f(0.0f,4.0f/32.0f*scale,0.0f);
			if(!info.mouse.icon.among(MouseIcon.spell,MouseIcon.ability)){
				auto material=sacCursor.iconMaterials[info.mouse.icon];
				material.bind(rc);
				material.backend.setTransformationScaled(iconPosition, Quaternionf.identity(), scaling, rc);
				quad.render(rc);
				material.unbind(rc);
			}else{
				B.hudMaterialBackend.bind(null,rc);
				B.hudMaterialBackend.bindDiffuse(sacHud.pages);
				B.hudMaterialBackend.setTransformationScaled(iconPosition, Quaternionf.identity(), scaling, rc);
				/+B.SubQuad[3] pages=[creaturePage,spellPage,structurePage];
				auto page=pages[info.mouse.spell.type];
				page.render(rc);+/
				B.hudMaterialBackend.bindDiffuse(info.mouse.spell.icon);
				quad.render(rc);
				B.hudMaterialBackend.unbind(null,rc);
			}
			if(!info.mouse.targetValid){
				auto material=sacCursor.invalidTargetIconMaterial;
				material.bind(rc);
				material.backend.setTransformationScaled(iconPosition, Quaternionf.identity(), scaling, rc);
				quad.render(rc);
				material.unbind(rc);
			}
		}
		auto material=sacCursor.materials[info.mouse.cursor];
		material.bind(rc);
		material.backend.setTransformationScaled(position, Quaternionf.identity(), scaling, rc);
		quad.render(rc);
		material.unbind(rc);
		if(info.mouseSparkles.length){
			auto mat=sacCursor.sparkleMaterial;
			mat.bind(rc);
			scope(exit) mat.unbind(rc);
			foreach(ref sparkle;info.mouseSparkles.data){
				auto spposition=Vector3f(sparkle.x,sparkle.y,0);
				auto spscaling=Vector3f(scale,-scale,1.0f);
				mat.backend.setTransformationScaled(spposition, Quaternionf.identity(), spscaling, rc);
				auto mesh=sacCursor.getSparkleMesh(sparkle.frame);
				mesh.render(rc);
			}
		}
	}

	SacCursor!B sacCursor;
	SacXmenu!B sacXmenu;
	B.Quad quad;
	B.Texture whiteTexture;
	B.CreatureFrame border;
	SacHud!B sacHud;
	B.SubQuad selectionRoster, minimapFrame, minimapCompass;
	B.Texture healthColorTexture,manaColorTexture;
	B.StatsFrame statsFrame;
	B.SubQuad creatureTab,spellTab,structureTab,tabSelector;
	B.SubQuad creaturePage,spellPage,structurePage;
	B.Cooldown cooldown;
	B.SubQuad spellbookFrame1,spellbookFrame2;
	B.Material hudSoulMaterial;
	B.Material minimapMaterial;
	B.SubQuad minimapQuad;
	B.SubQuad minimapAltarRing,minimapManalith,minimapWizard,minimapManafount,minimapShrine;
	B.SubQuad minimapCreatureArrow,minimapStructureArrow;
	B.Font[FontType.max+1] fonts=null;
	static struct HudOpt{ bool freetypeFonts; }
	void initializeHUD(HudOpt options){
		sacCursor=new SacCursor!B();
		sacXmenu=new SacXmenu!B();
		quad=B.makeQuad();
		whiteTexture=B.makeTexture(makeOnePixelImage(Color4f(1.0f,1.0f,1.0f)));
		border=B.makeCreatureFrame();
		sacHud=new SacHud!B();
		selectionRoster=B.makeSubQuad(-63.5f/128.0f,0.0f,63.5f/128.0f,2.0f);
		healthColorTexture=B.makeTexture(makeOnePixelImage(healthColor));
		manaColorTexture=B.makeTexture(makeOnePixelImage(manaColor));
		minimapFrame=B.makeSubQuad(0.5f,0.5f,1.5f,1.5f);
		minimapCompass=B.makeSubQuad(101.0f/128.0f,24.0f/128.0f,122.0f/128.0f,3.0f/128.0f);
		statsFrame=B.makeStatsFrame();
		creatureTab=B.makeSubQuad(1.0f/128.0f,0.0f,47.0f/128,48.0f/128.0f);
		spellTab=B.makeSubQuad(49.0f/128.0f,0.0f,95.0f/128.0f,48.0f/128.0f);
		structureTab=B.makeSubQuad(1.0f/128.0f,48.0f/128.0f,47.0f/128,96.0f/128.0f);
		tabSelector=B.makeSubQuad(49.0f/128.0f,48.0f/128.0f,95.0f/128,96.0f/128.0f);
		creaturePage=B.makeSubQuad(0.0f,0.0f,0.5f,0.5f);
		spellPage=B.makeSubQuad(0.5f,0.0f,1.0f,0.5f);
		structurePage=B.makeSubQuad(0.0f,0.5f,0.5f,1.0f);
		cooldown=B.makeCooldown();
		spellbookFrame1=B.makeSubQuad(0.5f,40.0f/128.0f,0.625f,48.0f/128.0f);
		spellbookFrame2=B.makeSubQuad(80.5f/128.0f,32.5f/128.0f,1.0f,48.0f/128.0f);
		assert(!!sacSoul.texture);
		hudSoulMaterial=B.makeMaterial(B.hudMaterialBackend2);
		hudSoulMaterial.blending=B.Blending.Transparent;
		hudSoulMaterial.diffuse=sacSoul.texture;
		// minimap
		minimapMaterial=B.makeMaterial(B.minimapMaterialBackend);
		minimapMaterial.diffuse=Color4f(1.0f,1.0f,1.0f,1.0f);
		minimapMaterial.blending=B.Blending.Transparent;
		minimapQuad=B.makeSubQuad(16.5f/64.0f,4.5f/65.0f,16.5f/64.0f,4.5f/64.0f);
		minimapAltarRing=B.makeSubQuad(1.0f/64.0f,1.0/65.0f,11.0f/64.0f,11.0f/64.0f);
		minimapManalith=B.makeSubQuad(12.0f/64.0f,0.0/65.0f,24.0f/64.0f,12.0f/64.0f);
		minimapWizard=B.makeSubQuad(25.5f/64.0f,1.0/65.0f,35.5f/64.0f,12.0f/64.0f);
		minimapManafount=B.makeSubQuad(36.5f/64.0f,1.0/65.0f,47.0f/64.0f,11.0f/64.0f);
		minimapShrine=B.makeSubQuad(48.0f/64.0f,0.0/65.0f,60.0f/64.0f,12.0f/64.0f);
		minimapCreatureArrow=B.makeSubQuad(0.0f/64.0f,13.0/65.0f,11.0f/64.0f,24.0f/64.0f);
		minimapStructureArrow=B.makeSubQuad(12.0f/64.0f,13.0/65.0f,23.0f/64.0f,24.0f/64.0f);
		// freetype fonts
		if(options.freetypeFonts){
			fonts[FontType.fn08]=null; // B.loadFont(8*fontScaleFactor,"fonts/verdana.ttf"); // TODO: fancy color gradient
			fonts[FontType.fn10]=B.loadFont(10*fontScaleFactor,"fonts/bookA.ttf");
			fonts[FontType.fn12]=B.loadFont(12*fontScaleFactor,"fonts/elgar.ttf");
			fonts[FontType.fndb]=null; // TODO: find font
			fonts[FontType.fnwt]=B.loadFont(8*fontScaleFactor,"fonts/verdana.ttf"); // TODO: improve rendering
			fonts[FontType.ft12]=B.loadFont(12*fontScaleFactor,"fonts/bookA.ttf");
		}
	}
	enum fontScaleFactor=64;

	void bindFont(SacFont!B font,B.RenderContext rc){
		auto type=font.type;
		if(!fonts[type]){
			B.colorHUDMaterialBackend.bind(null,rc);
			B.colorHUDMaterialBackend.bindDiffuse(font.texture);
		}else fonts[type].bind(rc);
	}
	void unbindFont(SacFont!B font,B.RenderContext rc){
		auto type=font.type;
		if(fonts[type]) fonts[type].unbind(rc);
		else B.colorHUDMaterialBackend.unbind(null,rc);
	}
	void setFontColor(SacFont!B font,Color4f color){
		auto type=font.type;
		if(fonts[type]) fonts[type].setColor(color);
		else B.colorHUDMaterialBackend.setColor(color);
	}
	static Vector2f getFreetypeOffset(SacFont!B font){
		auto type=font.type;
		final switch(type)with(FontType){
			case FontType.fndb: return Vector2f(0.0f,0.0f); // TODO

			case FontType.fn08: return Vector2f(0.0f,2.0f);
			case FontType.fnwt: return Vector2f(0.0f,2.0f);

			case FontType.fn10: return Vector2f(0.5f,1.75f);
			case FontType.fn12: return Vector2f(0.5f,1.0f);
			case FontType.ft12: return Vector2f(0.5f,0.5f); // TODO: ok?
		}
	}
	void drawText(SacFont!B font,const(char)[] text,float left,float top,FormatSettings settings,ref RenderInfo!B info,B.RenderContext rc){
		auto type=font.type;
		void drawLetter1(dchar c,B.SubQuad mesh,float x,float y,float width,float height){
			B.colorHUDMaterialBackend.setTransformationScaled(Vector3f(x,y,0.0f),Quaternionf.identity(),Vector3f(width,height,0.0f),rc);
			mesh.render(rc);
		}
		if(!fonts[type]){
			font.write!drawLetter1(text,left,top,settings);
		}else{
			/+unbindFont(font,rc);
			B.colorHUDMaterialBackend.bind(null,rc);
			B.colorHUDMaterialBackend.bindDiffuse(font.texture);
			B.colorHUDMaterialBackend.setColor(Color4f(0.0f,1.0f,0.0f,1.0f));
			font.write!drawLetter1(text,left,top,settings);
			B.colorHUDMaterialBackend.setColor(Color4f(1.0f,1.0f,0.0f,1.0f));
			B.colorHUDMaterialBackend.unbind(null,rc);
			bindFont(font,rc);
			setFontColor(font,Color4f(1.0f,1.0f,1.0f,1.0f));+/
			auto scale=1.5f*settings.scale;
			auto ftOffset=scale*getFreetypeOffset(font);
			if(type.among(FontType.fn08,FontType.fnwt)){
				void drawLetter2(dchar c,B.SubQuad mesh,float x,float y,float width,float height){
					float xscale=0.55f;
					switch(c){
						case 'f': x+=1.0f*scale; break;
						case 'j': x+=1.0f*scale; break;
						case 't': x+=0.5f*scale; break;
						case 'v': x+=1.0f*scale; break;
						case 'x': x+=1.0f*scale; break;
						case 'y','ÿ','ý','ỳ': x+=1.0f*scale; break;
						case 'A','Ä','Á','À','Ą': xscale=0.75f; break;
						case 'H': x+=0.25f*scale; break;
						case 'J': x+=1.0f*scale; break;
						case 'M': x+=0.5f*scale; break;
						case 'O','Ö','Ó','Ò': x+=0.5f*scale; break;
						case 'T': x+=1.5f*scale; break;
						case 'V': x+=1.0f*scale; break;
						case 'X': x+=1.0f*scale; break;
						case '/': x+=1.0f*scale; break;
						case '@': x+=1.5f*scale; break;
						default: break;
					}
					fonts[type].setTransformationScaled(Vector3f(x,y,0.0f),scale/fontScaleFactor*Vector3f(xscale,0.55f,1.0f),rc);
					import std.ascii:isASCII,isPrintable;
					if(!c.isASCII||c.isPrintable)
						fonts[type].renderGlyph(c,0);
				}
				font.write!drawLetter2(text,left+ftOffset.x,top+ftOffset.y,settings);
			}else{
				void drawLetter3(dchar c,B.SubQuad mesh,float x,float y,float width,float height){
					switch(c){
						case '\'': x-=0.75f*scale; break;
						default: break;
					}
					//fonts[type].setTransformationScaled(Vector3f(x,y,0.0f),0.63f*scale/fontScaleFactor*Vector3f(1.0f,1.0f,1.0f),rc);
					fonts[type].setTransformationScaled(Vector3f(x,y,0.0f),Vector3f(width-scale,0.6f*scale/fontScaleFactor,0.0f),rc);
					import std.ascii:isASCII,isPrintable;
					if(!c.isASCII||c.isPrintable)
						//fonts[type].renderGlyph(c,0);
						fonts[type].renderGlyphUnit(c);
				}
				font.write!drawLetter3(text,left+ftOffset.x,top+ftOffset.y,settings);
			}
		}
	}

	auto spellbookTarget=Target.init;
	SacSpell!B spellbookTargetSpell=null;
	auto selectionRosterTarget=Target.init;
	SacSpell!B selectionRosterTargetAbility=null;
	auto minimapTarget=Target.init;
	auto formTarget=Target.init;

	bool isOnSelectionRoster(Vector2f center,ref RenderInfo!B info){
		if(!info.hudVisible) return false;
		auto scaling=info.hudScaling*Vector3f(138.0f,256.0f-64.0f,1.0f);
		auto position=Vector3f(-34.0f*info.hudScaling,0.5*(info.height-scaling.y),0);
		auto topLeft=position;
		auto bottomRight=position+scaling;
		return floor(topLeft.x)<=center.x&&center.x<=cast(int)ceil(bottomRight.x)
			&& floor(topLeft.y)<=center.y&&center.y<=cast(int)ceil(bottomRight.y);
	}
	void updateSelectionRosterTarget(Target target,Vector2f position,Vector2f scaling,ref RenderInfo!B info){
		if(!info.mouse.onSelectionRoster) return;
		auto topLeft=position;
		auto bottomRight=position+scaling;
		if(floor(topLeft.x)<=info.mouse.x&&info.mouse.x<=ceil(bottomRight.x)
		   && floor(topLeft.y)<=info.mouse.y&&info.mouse.y<=ceil(bottomRight.y))
			selectionRosterTarget=target;
	}
	void updateSelectionRosterTargetAbility(Target target,SacSpell!B targetAbility,Vector2f position,Vector2f scaling,ref RenderInfo!B info){
		if(!info.mouse.onSelectionRoster) return;
		auto topLeft=position;
		auto bottomRight=position+scaling;
		if(floor(topLeft.x)<=info.mouse.x&&info.mouse.x<=ceil(bottomRight.x)
		   && floor(topLeft.y)<=info.mouse.y&&info.mouse.y<=ceil(bottomRight.y)){
			selectionRosterTarget=target;
			selectionRosterTargetAbility=targetAbility;
		}
	}
	void renderSelectionRoster(ObjectState!B state,ref RenderInfo!B info,B.RenderContext rc){
		if(info.mouse.onSelectionRoster){
			selectionRosterTarget=Target.init;
			selectionRosterTargetAbility=null;
		}
		auto material=sacHud.frameMaterial;
		material.bind(rc);
		scope(success) material.unbind(rc);
		auto hudScaling=info.hudScaling;
		auto scaling=info.hudScaling*Vector3f(138.0f,256.0f,1.0f);
		auto position=Vector3f(-34.0f*info.hudScaling,0.5f*(info.height-scaling.y),0);
		material.backend.setTransformationScaled(position, Quaternionf.identity(), scaling, rc);
		selectionRoster.render(rc);
		int i=0; // idiotic deprecation of foreach(int i,x;selection)
		foreach(x;renderedSelection.creatureIds){
			scope(success) i++;
			if(!renderedSelection.creatureIds[i]) continue;
			static void renderIcon(B)(MovingObject!B obj,int i,Vector3f position,Renderer!B* self,ObjectState!B state,RenderInfo!B* info,B.RenderContext rc){
				if(obj.sacObject.icon){
					auto cpos=position+info.hudScaling*Vector3f(i>=6?35.0f:-1.0f,(i%6)*32.0f,0.0f);
					auto scaling=info.hudScaling*Vector3f(34.0f,32.0f,0.0f);
					B.hudMaterialBackend.setTransformationScaled(cpos, Quaternionf.identity(), scaling, rc);
					B.hudMaterialBackend.bindDiffuse(obj.sacObject.icon);
					self.quad.render(rc);
					if(info.mouse.onSelectionRoster){
						auto target=Target(TargetType.creature,obj.id,obj.position,TargetLocation.selectionRoster);
						self.updateSelectionRosterTarget(target,cpos.xy,scaling.xy,*info);
					}
					if(obj.creatureStats.maxHealth!=0.0f){
						auto healthScaling=info .hudScaling*Vector3f(2.0f,30.0f*obj.creatureStats.health/obj.creatureStats.maxHealth,0.0f);
						auto healthPos=cpos+Vector3f(info.hudScaling*32.0f,info.hudScaling*30.0f-healthScaling.y,0.0f);
						B.hudMaterialBackend.setTransformationScaled(healthPos, Quaternionf.identity(), healthScaling, rc);
						B.hudMaterialBackend.bindDiffuse(self.healthColorTexture);
						self.quad.render(rc);
					}
					if(obj.creatureStats.maxMana!=0.0f){
						auto manaScaling=info.hudScaling*Vector3f(2.0f,30.0f*obj.creatureStats.mana/obj.creatureStats.maxMana,0.0f);
						auto manaPos=cpos+Vector3f(info.hudScaling*34.0f,info.hudScaling*30.0f-manaScaling.y,0.0f);
						B.hudMaterialBackend.setTransformationScaled(manaPos, Quaternionf.identity(), manaScaling, rc);
						B.hudMaterialBackend.bindDiffuse(self.manaColorTexture);
						self.quad.render(rc);
					}
				}
			}
			state.movingObjectById!(renderIcon!B,(){})(renderedSelection.creatureIds[i],i,Vector3f(position.x+34.0f*info.hudScaling,0.5*(info.height-scaling.y)+32.0f*info.hudScaling,0.0f),&this,state,&info,rc);
		}
		auto ability=renderedSelection.ability(state);
		if(ability&&ability.icon){
			auto ascaling=info.hudScaling*Vector3f(34.0f,34.0f,0.0f);
			auto apos=position+Vector3f(info.hudScaling*105.0f,0.5f*scaling.y-info.hudScaling*17.0f,0.0f);
			B.hudMaterialBackend.setTransformationScaled(apos, Quaternionf.identity(), ascaling, rc);
			B.hudMaterialBackend.bindDiffuse(ability.icon);
			quad.render(rc);
			if(info.mouse.onSelectionRoster){
				auto target=Target(TargetType.ability,0,Vector3f.init,TargetLocation.selectionRoster);
				updateSelectionRosterTargetAbility(target,ability,apos.xy,ascaling.xy,info);
			}
		}
	}
	float minimapRadius(ref RenderInfo!B info){ return info.hudScaling*80.0f; }
	bool isOnMinimap(Vector2f position,ref RenderInfo!B info){
		if(!info.hudVisible) return false;
		auto radius=minimapRadius(info);
		auto center=Vector2f(info.width-radius,info.height-radius);
		return (position-center).lengthsqr<=radius*radius;
	}
	void updateMinimapTarget(Target target,Vector2f center,Vector2f scaling,ref RenderInfo!B info){
		if(!info.mouse.onMinimap) return;
		auto topLeft=center-0.5f*scaling;
		auto bottomRight=center+0.5f*scaling;
		if(cast(int)topLeft.x<=info.mouse.x&&info.mouse.x<=cast(int)(bottomRight.x+0.5f)
		   && cast(int)topLeft.y<=info.mouse.y&&info.mouse.y<=cast(int)(bottomRight.y+0.5f))
			minimapTarget=target;
	}
	void updateMinimapTargetTriangle(Target target,Vector3f[3] triangle,ref RenderInfo!B info){
		if(!info.mouse.onMinimap) return;
		auto mousePos=Vector3f(info.mouse.x,info.mouse.y,0.0f);
		foreach(k;0..3) triangle[k]-=mousePos;
		foreach(k;0..3)
			if(cross(triangle[k],triangle[(k+1)%$]).z<0)
				return;
		minimapTarget=target;
	}
	void renderMinimap(ObjectState!B state,ref RenderInfo!B info,B.RenderContext rc){
		if(info.mouse.onMinimap) minimapTarget=Target.init;
		auto map=state.map;
		auto radius=minimapRadius(info);
		auto left=cast(int)(info.width-2.0f*radius), top=cast(int)(info.height-2.0f*radius);
		auto yOffset=info.windowHeight-cast(int)(info.height*info.screenScaling);
		B.scissor(cast(int)(left*info.screenScaling),0+yOffset,cast(int)((info.width-left)*info.screenScaling),cast(int)((info.height-top)*info.screenScaling));
		auto hudScaling=info.hudScaling;
		auto scaling=Vector3f(2.0f*radius,2.0f*radius,0f);
		auto position=Vector3f(info.width-scaling.x,info.height-scaling.y,0);
		auto material=minimapMaterial;
		B.minimapMaterialBackend.center=Vector2f(info.width-radius,info.height-radius);
		B.minimapMaterialBackend.radius=0.95f*radius;
		material.bind(rc);
		B.minimapMaterialBackend.setTransformationScaled(position, Quaternionf.identity(), scaling, rc);
		B.minimapMaterialBackend.setColor(Color4f(0.0f,65.0f/255.0f,66.0f/255.0f,1.0f));
		quad.render(rc);
		auto minimapFactor=info.hudScaling/info.camera.minimapZoom;
		auto camPos=info.camera.position;
		auto mapRotation=facingQuaternion(-degtorad(info.camera.turn));
		auto minimapCenter=Vector3f(camPos.x,camPos.y,0.0f)+rotate(mapRotation,Vector3f(0.0f,info.camera.distance*3.73f,0.0f));
		auto minimapSize=Vector2f(2560.0f,2560.0f);
		auto mapCenter=Vector3f(info.width-radius,info.height-radius,0);
		auto mapPosition=mapCenter+rotate(mapRotation,minimapFactor*Vector3f(-minimapCenter.x,minimapCenter.y,0));
		auto mapScaling=Vector3f(1,-1,1)*minimapFactor;
		B.minimapMaterialBackend.setTransformationScaled(mapPosition,mapRotation,mapScaling,rc);
		B.minimapMaterialBackend.setColor(Color4f(0.5f,0.5f,0.5f,1.0f));
		foreach(i,mesh;map.minimapMeshes){
			if(!mesh) continue;
			B.minimapMaterialBackend.bindDiffuse(map.textures[i]);
			mesh.render(rc);
		}
		if(!state.isValidTarget(info.camera.target,TargetType.creature)) info.camera.target=0;
		if(info.camera.target){
			import std.typecons: Tuple,tuple;
			auto facingPosition=state.movingObjectById!((obj)=>tuple(obj.creatureState.facing,obj.position), function Tuple!(float,Vector3f)(){ assert(0); })(info.camera.target);
			auto facing=facingPosition[0],targetPosition=facingPosition[1];
			auto relativePosition=targetPosition-minimapCenter;
			auto iconOffset=rotate(mapRotation,minimapFactor*Vector3f(relativePosition.x,-relativePosition.y,0));
			auto iconCenter=mapCenter+iconOffset;
			B.minimapMaterialBackend.bindDiffuse(whiteTexture);
			B.minimapMaterialBackend.setColor(Color4f(1.0f,1.0f,0.0f,1.0f));
			auto fovScaling=Vector3f(0.5f*info.hudScaling,2.0f*radius,0.0f);
			auto angle=2.0f*pi!float*82.0f/360.0f;
			auto fovRotation1=mapRotation*facingQuaternion(-facing-0.5f*angle+pi!float);
			B.minimapMaterialBackend.setTransformationScaled(iconCenter+rotate(fovRotation1,Vector3f(-0.5f*fovScaling.x,0.0f,0.0f)),fovRotation1,fovScaling,rc);
			quad.render(rc);
			auto fovRotation2=mapRotation*facingQuaternion(-facing+0.5f*angle+pi!float);
			B.minimapMaterialBackend.setTransformationScaled(iconCenter+rotate(fovRotation2,Vector3f(-0.5f*fovScaling.x,0.0f,0.0f)),fovRotation2,fovScaling,rc);
			quad.render(rc);
		}
		if(info.mouse.onMinimap){
			auto mouseOffset=Vector3f(info.mouse.x,info.mouse.y,0.0f)-mapCenter;
			auto minimapPosition=minimapCenter+rotate(mapRotation,Vector3f(mouseOffset.x,-mouseOffset.y,0.0f)/minimapFactor);
			minimapPosition.z=state.getHeight(minimapPosition);
			auto target=Target(TargetType.terrain,0,minimapPosition,TargetLocation.minimap);
			minimapTarget=target;
		}
		B.minimapMaterialBackend.bindDiffuse(sacHud.minimapIcons);
		 // temporary scratch space. TODO: maybe share memory with other temporary scratch spaces
		static Array!uint creatureArrowIndices;
		static Array!uint structureArrowIndices;
		static void render(T)(ref T objects,float minimapFactor,Vector3f minimapCenter,Vector3f mapCenter,float radius,Quaternionf mapRotation,Renderer!B* self,ObjectState!B state,RenderInfo!B* info,B.RenderContext rc){ // TODO: why does this need to be static? DMD bug?
			enum isMoving=is(T==MovingObjects!(B, renderMode), RenderMode renderMode);
			enum isStatic=is(T==StaticObjects!(B, renderMode), RenderMode renderMode);
			static if((is(typeof(objects.sacObject))||is(T==Souls!(B)))&&!is(T==FixedObjects!B)){
				auto quad=self.minimapQuad;
				auto iconScaling=info.hudScaling*Vector3f(2.0f,2.0f,0.0f);
				static if(is(typeof(objects.sacObject))){
					auto sacObject=objects.sacObject;
					bool isManafount=false;
					static if(isMoving){
						enum mayShowArrow=true;
						bool isWizard=false;
						if(sacObject.isWizard){
							isWizard=true;
							quad=self.minimapWizard;
							iconScaling=info.hudScaling*Vector3f(11.0f,11.0f,0.0f);
						}
					}else{
						bool mayShowArrow=false;
						enum isWizard=false;
						if(sacObject.isAltarRing){
							mayShowArrow=true;
							quad=self.minimapAltarRing;
							iconScaling=info.hudScaling*Vector3f(10.0f,10.0f,0.0f);
						}else if(sacObject.isManalith){
							mayShowArrow=true;
							quad=self.minimapManalith;
							iconScaling=info.hudScaling*Vector3f(12.0f,12.0f,0.0f);
						}else if(sacObject.isManafount){
							isManafount=true;
							quad=self.minimapManafount;
							iconScaling=info.hudScaling*Vector3f(11.0f,11.0f,0.0f);
							B.minimapMaterialBackend.setColor(Color4f(0.0f,160.0f/255.0f,219.0f/255.0f,1.0f));
						}else if(sacObject.isShrine){
							mayShowArrow=true;
							quad=self.minimapShrine;
							iconScaling=info.hudScaling*Vector3f(12.0f,12.0f,0.0f);
						}
					}
				}else enum mayShowArrow=false;
				enforce(objects.length<=uint.max);
				foreach(j;0..cast(uint)objects.length){
					static if(is(typeof(objects.sacObject))){
						static if(isMoving){
							if(objects.creatureStates[j].mode.among(CreatureMode.dead,CreatureMode.dissolving)) continue;
							if(info.renderSide!=objects.sides[j]&&(!objects.creatureStates[j].mode.isVisibleToOtherSides||objects.creatureStatss[j].effects.stealth))
								continue;
						}
						static if(isMoving){
							auto side=objects.sides[j];
							auto flags=objects.creatureStatss[j].flags;
						}else{
							auto sideFlags=state.buildingById!((ref b)=>tuple(b.side,b.flags),function Tuple!(int,int)(){ assert(0); })(objects.buildingIds[j]);
							auto side=sideFlags[0],flags=sideFlags[1];
						}
						import ntts: Flags;
						if(flags&Flags.notOnMinimap) continue;
						auto showArrow=mayShowArrow&&
							(side==info.renderSide||
							 (!isMoving||isWizard) && state.sides.getStance(side,info.renderSide)==Stance.ally);
					}else enum showArrow=false;
					auto clipRadiusFactor=showArrow?0.92f:1.08f;
					auto clipradiusSq=((clipRadiusFactor*radius+(showArrow?-1.0f:1.0f)*0.5f*iconScaling.x)*
					                   (clipRadiusFactor*radius+(showArrow?-1.0f:1.0f)*0.5f*iconScaling.y));
					static if(isStatic){
						if(state.buildingById!((ref bldg,isManafount)=>!isManafount&&!bldg.isAltar&&bldg.health==0.0f||bldg.top,()=>true)(objects.buildingIds[j],isManafount)) // TODO: merge with side lookup!
							continue;
					}
					static if(is(T==Souls!B)) auto position=objects[j].position-minimapCenter;
					else auto position=objects.positions[j]-minimapCenter;
					auto iconOffset=rotate(mapRotation,minimapFactor*Vector3f(position.x,-position.y,0));
					if(iconOffset.lengthsqr<=clipradiusSq){
						auto iconCenter=mapCenter+iconOffset;
						B.minimapMaterialBackend.setTransformationScaled(iconCenter-0.5f*iconScaling,Quaternionf.identity(),iconScaling,rc);
						static if(is(typeof(objects.sacObject))){
							if(!isManafount){
								auto color=state.sides.sideColor(side);
								B.minimapMaterialBackend.setColor(color);
							}
						}else static if(is(T==Souls!B)){
							auto soul=objects[j];
							if(!soul.state.among(SoulState.normal,SoulState.emerging)) continue;
							auto color=soulMinimapColor[soul.color(info.renderSide,state)];
							B.minimapMaterialBackend.setColor(color);
						}
						quad.render(rc);
						static if(is(typeof(objects.sacObject))){
							if(info.mouse.onMinimap){
								auto target=Target(isMoving?TargetType.creature:TargetType.building,objects.ids[j],objects.positions[j],TargetLocation.minimap);
								self.updateMinimapTarget(target,iconCenter.xy,iconScaling.xy,*info);
								if(self.isInRectangleSelect(iconCenter.xy,*info)&&canSelect(info.renderSide,objects.ids[j],state))
									self.rectangleSelection.addSorted(objects.ids[j]);
							}
						}
					}else static if(is(typeof(objects.sacObject))){
						if(showArrow){
							static if(isMoving) creatureArrowIndices~=objects.ids[j];
							else structureArrowIndices~=objects.ids[j];
						}
					}
				}
			}else static if(is(T==FixedObjects!B)){
				// do nothing
			}else static if(is(T==Buildings!B)){
				// do nothing
			}else static if(is(T==Effects!B)){
				// do nothing
			}else static if(is(T==Particles!(B,relative),bool relative)){
				// do nothing
			}else static if(is(T==CommandCones!B)){
				// do nothing
			}else static assert(0);
		}
		state.eachByType!(render,EachByTypeFlags.movingFirst|EachByTypeFlags.wizardsLast)(minimapFactor,minimapCenter,mapCenter,radius,mapRotation,&this,state,&info,rc);
		static void renderArrow(T)(T object,float minimapFactor,Vector3f minimapCenter,Vector3f mapCenter,float radius,Quaternionf mapRotation,Renderer!B* self,ObjectState!B state,RenderInfo!B* info,B.RenderContext rc){ // TODO: why does this need to be static? DMD bug?
			static if(is(typeof(object.sacObject))&&!is(T==FixedObjects!B)){
				auto sacObject=object.sacObject;
				enum isMoving=is(T==MovingObject!B);
				auto arrowQuad=isMoving?self.minimapCreatureArrow:self.minimapStructureArrow;
				auto arrowScaling=info.hudScaling*Vector3f(11.0f,11.0f,0.0f);
				auto position=object.position-minimapCenter;
				auto iconOffset=rotate(mapRotation,minimapFactor*Vector3f(position.x,-position.y,0));
				auto offset=iconOffset.normalized*(0.92f*radius-info.hudScaling*6.0f);
				auto iconCenter=mapCenter+offset;
				auto rotation=rotationQuaternion(Axis.z,pi!float/2+atan2(iconOffset.y,iconOffset.x));
				B.minimapMaterialBackend.setTransformationScaled(iconCenter-rotate(rotation,0.5f*arrowScaling),rotation,arrowScaling,rc);
				static if(isMoving) auto side=object.side;
				else auto side=sideFromBuildingId(object.buildingId,state);
				auto color=state.sides.sideColor(side);
				B.minimapMaterialBackend.setColor(color);
				arrowQuad.render(rc);
				if(info.mouse.onMinimap){
					auto target=Target(isMoving?TargetType.creature:TargetType.building,object.id,object.position,TargetLocation.minimap);
					Vector3f[3] triangle=[Vector3f(0.0f,-9.0f,0.0f),Vector3f(6.0f,6.0f,0.0f),Vector3f(-6.0f,6.0f,0.0f)];
					foreach(k;0..3) triangle[k]=iconCenter+rotate(rotation,info.hudScaling*triangle[k]);
					self.updateMinimapTargetTriangle(target,triangle,*info);
				}
			}
		}
		static foreach(isMoving;[true,false])
			foreach(id;isMoving?creatureArrowIndices.data:structureArrowIndices.data)
				state.objectById!renderArrow(id,minimapFactor,minimapCenter,mapCenter,radius,mapRotation,&this,state,&info,rc);
		creatureArrowIndices.length=0;
		structureArrowIndices.length=0;
		material.unbind(rc);
		material=sacHud.frameMaterial;
		material.bind(rc);
		material.backend.setTransformationScaled(position, Quaternionf.identity(), scaling, rc);
		minimapFrame.render(rc);
		auto compassScaling=0.8f*info.hudScaling*Vector3f(21.0f,21.0f,0.0f);
		auto compassPosition=mapCenter+rotate(mapRotation,Vector3f(0.0f,radius-3.0f*info.hudScaling,0.0f)-0.5f*compassScaling);
		material.backend.setTransformationScaled(compassPosition, mapRotation, compassScaling, rc);
		B.scissor(0,0+yOffset,cast(int)(info.width*info.screenScaling),cast(int)(info.height*info.screenScaling));
		minimapCompass.render(rc);
		material.unbind(rc);
	}
	void renderStats(ObjectState!B state,ref RenderInfo!B info,B.RenderContext rc){
		auto material=sacHud.frameMaterial;
		material.bind(rc);
		auto hudScaling=info.hudScaling;
		auto scaling0=Vector3f(64.0f,96.0f,0.0f);
		scaling0*=info.hudScaling;
		auto scaling1=Vector3f(32.0f,96.0f,0.0f);
		scaling1*=info.hudScaling;
		auto position0=Vector3f(info.width-2*scaling1.x-scaling0.x,0,0);
		auto position1=Vector3f(info.width-2*scaling1.x,0,0);
		auto position2=Vector3f(info.width-scaling1.x,0,0);
		material.backend.setTransformationScaled(position0, Quaternionf.identity(), scaling0, rc);
		statsFrame.render(rc);
		material.backend.setTransformationScaled(position1, Quaternionf.identity(), scaling1, rc);
		statsFrame.render(rc);
		material.backend.setTransformationScaled(position2, Quaternionf.identity(), scaling1, rc);
		statsFrame.render(rc);
		material.unbind(rc);
		material=hudSoulMaterial;
		material.bind(rc);
		auto soulPosition=position0+0.5f*scaling0;
		auto soulScaling=scaling0;
		soulScaling.x/=sacSoul.soulWidth;
		soulScaling.y/=sacSoul.soulHeight;
		soulScaling.y*=-1;
		soulScaling*=0.85f;
		material.backend.setTransformationScaled(soulPosition, Quaternionf.identity(), soulScaling, rc);
		sacSoul.getMesh(SoulColor.blue,info.hudSoulFrame/updateAnimFactor).render(rc);
		material.unbind(rc);
		if(!state.isValidTarget(info.camera.target,TargetType.creature)) info.camera.target=0;
		if(info.camera.target){
			static float getRelativeMana(B)(MovingObject!B obj){
				if(obj.creatureStats.maxMana==0.0f) return 0.0f;
				return obj.creatureStats.mana/obj.creatureStats.maxMana;
			}
			static float getRelativeHealth(B)(MovingObject!B obj){
				if(obj.creatureStats.maxHealth==0.0f) return 0.0f;
				return obj.creatureStats.health/obj.creatureStats.maxHealth;
			}
			void renderStatBar(Vector3f origin,float relativeSize,B.Material top,B.Material mid,B.Material bot){
				auto maxScaling=info.hudScaling*Vector3f(32.0f,68.0f,0.0f);
				auto position=origin+Vector3f(0.0f,info.hudScaling*14.0f+(1.0f-relativeSize)*maxScaling.y,0.0f);
				auto scaling=Vector3f(maxScaling.x,maxScaling.y*relativeSize,0.0f);
				auto topPosition=position+Vector3f(0.0f,-info.hudScaling*4.0f,0.0f);
				auto topScaling=Vector3f(maxScaling.x,info.hudScaling*4.0f,0.0f);
				auto bottomPosition=position+Vector3f(0.0f,scaling.y,0.0f);
				auto bottomScaling=Vector3f(maxScaling.x,info.hudScaling*6.0f,0.0f);

				B.Material[3] materials=[top,mid,bot];
				Vector3f[3] positions=[topPosition,position,bottomPosition];
				Vector3f[3] scalings=[topScaling,scaling,bottomScaling];
				static foreach(i;0..3){
					materials[i].bind(rc);
					materials[i].backend.setTransformationScaled(positions[i], Quaternionf.identity(), scalings[i], rc);
					quad.render(rc);
					materials[i].unbind(rc);
				}
			}
			auto relativeStats=state.movingObjectById!((obj)=>tuple(getRelativeMana(obj),getRelativeHealth(obj)),()=>tuple(0.0f,0.0f))(info.camera.target);
			auto relativeMana=relativeStats[0];
			renderStatBar(position1,relativeMana,sacHud.manaTopMaterial,sacHud.manaMaterial,sacHud.manaBottomMaterial);
			auto relativeHealth=relativeStats[1];
			renderStatBar(position2,relativeHealth,sacHud.healthTopMaterial,sacHud.healthMaterial,sacHud.healthBottomMaterial);
		}
	}

	int numSpells=0;
	bool isOnSpellbook(Vector2f center,ref RenderInfo!B info){
		if(!info.hudVisible) return false;
		auto hudScaling=info.hudScaling;
		auto tabScaling=hudScaling*Vector2f(3*48.0f,48.0f);
		auto tabPosition=Vector2f(0.0f,info.height-hudScaling*80.0f);
		auto tabTopLeft=tabPosition;
		auto tabBottomRight=tabPosition+tabScaling;
		if(floor(tabTopLeft.x)<=center.x&&center.x<=ceil(tabBottomRight.x)&&
		   floor(tabTopLeft.y)<=center.y&&center.y<=ceil(tabBottomRight.y))
			return true;
		auto spellScaling=hudScaling*Vector2f(numSpells*32.0f+12.0f,36.0f);
		auto spellPosition=Vector2f(0.0f,info.height-spellScaling.y);
		auto spellTopLeft=spellPosition;
		auto spellBottomRight=spellPosition+spellScaling;
		if(floor(spellTopLeft.x)<=center.x&&center.x<=ceil(spellBottomRight.x)&&
		   floor(spellTopLeft.y)<=center.y&&center.y<=ceil(spellBottomRight.y))
			return true;

		return false;
	}
	void updateSpellbookTarget(Target target,SacSpell!B targetSpell,Vector2f position,Vector2f scaling,ref RenderInfo!B info){
		if(!info.mouse.onSpellbook) return;
		auto topLeft=position;
		auto bottomRight=position+scaling;
		if(floor(topLeft.x)<=info.mouse.x&&info.mouse.x<=ceil(bottomRight.x)
		   && floor(topLeft.y)<=info.mouse.y&&info.mouse.y<=ceil(bottomRight.y)){
			spellbookTarget=target;
			spellbookTargetSpell=targetSpell;
		}
	}
	void renderSpellbook(ObjectState!B state,ref RenderInfo!B info,B.RenderContext rc){
		if(info.mouse.onSpellbook){
			spellbookTarget=Target.init;
			spellbookTargetSpell=null;
		}
		auto hudScaling=info.hudScaling;
		auto wizard=state.getWizard(info.camera.target);
		auto spells=state.getSpells(wizard).filter!(x=>x.spell.type==info.spellbookTab);
		numSpells=cast(int)spells.walkLength;
		auto material=sacHud.frameMaterial; // TODO: share material binding with other drawing commands (or at least the backend binding)
		material.bind(rc);
		auto position=Vector3f(0.0f,info.height-hudScaling*32.0f,0.0f);
		auto numFrameSegments=max(10,2*numSpells);
		auto scaling=hudScaling*Vector3f(16.0f,8.0f,0.0f);
		auto scaling2=hudScaling*Vector3f(48.0f,16.0f,0.0f);
		auto position2=Vector3f(hudScaling*16.0f*numFrameSegments-4.0f+scaling2.y,info.height-hudScaling*48.0f,0.0f);
		material.backend.setTransformationScaled(position2,facingQuaternion(pi!float/2),scaling2,rc);
		spellbookFrame2.render(rc);
		foreach(i;0..numFrameSegments){
			auto positioni=position+hudScaling*Vector3f(16.0f*i,-8.0f,0.0f);
			material.backend.setTransformationScaled(positioni,Quaternionf.identity(),scaling,rc);
			spellbookFrame1.render(rc);
		}
		material.unbind(rc);
		auto tabsPosition=Vector3f(0.0f,info.height-hudScaling*80.0f,0.0f);
		auto tabScaling=hudScaling*Vector3f(48.0f,48.0f,0.0f);
		auto tabs=tuple(creatureTab,spellTab,structureTab);
		material=sacHud.tabsMaterial;
		material.bind(rc);
		foreach(i,tab;tabs){
			auto tabPosition=tabsPosition+hudScaling*Vector3f(48.0f,0.0f,0.0f)*i;
			auto target=Target(cast(TargetType)(TargetType.creatureTab+i),0,Vector3f.init,TargetLocation.spellbook);
			updateSpellbookTarget(target,null,tabPosition.xy,tabScaling.xy,info);
			material.backend.setTransformationScaled(tabPosition,Quaternionf.identity(),tabScaling,rc);
			tab.render(rc);
		}
		material.backend.setTransformationScaled(tabsPosition+hudScaling*Vector3f(48.0f,0.0f,0.0f)*info.spellbookTab,Quaternionf.identity(),tabScaling,rc);
		tabSelector.render(rc);
		material.unbind(rc);
		B.hudMaterialBackend.bind(null,rc);
		B.hudMaterialBackend.bindDiffuse(sacHud.pages);
		B.SubQuad[3] pages=[creaturePage,spellPage,structurePage];
		auto page=pages[info.spellbookTab];
		auto pageScaling=hudScaling*Vector3f(32.0f,32.0f,0.0f);
		foreach(i,entry;enumerate(spells)){
			auto pagePosition=Vector3f(i*pageScaling.x,info.height-pageScaling.y,0.0f);
			auto target=Target(TargetType.spell,0,Vector3f.init,TargetLocation.spellbook);
			updateSpellbookTarget(target,entry.spell,pagePosition.xy,pageScaling.xy,info);
			B.hudMaterialBackend.setTransformationScaled(pagePosition,Quaternionf.identity(),pageScaling,rc);
			page.render(rc);
		}
		auto mana=info.camera.target?state.movingObjectById!((obj)=>obj.creatureStats.mana,function float()=>0.0f)(info.camera.target):0.0f;
		auto souls=wizard?wizard.souls:0;
		foreach(i,entry;enumerate(spells)){
			auto factor=min(1.0f,mana/entry.spell.manaCost);
			auto spellScaling=factor*pageScaling;
			auto spellPosition=Vector3f((i+0.5f)*pageScaling.x-0.5f*spellScaling.x,info.height-0.5f*pageScaling.y-0.5f*spellScaling.y,0.0f);
			B.hudMaterialBackend.setTransformationScaled(spellPosition,Quaternionf.identity(),spellScaling,rc);
			B.hudMaterialBackend.bindDiffuse(entry.spell.icon);
			B.hudMaterialBackend.setAlpha(factor);
			quad.render(rc);
			bool active=true;
			if(entry.spell.tag==SpellTag.guardian&&!wizard.closestBuilding) active=false;
			if(entry.spell.tag==SpellTag.desecrate&&!wizard.closestEnemyAltar) active=false;
			if(entry.spell.tag==SpellTag.convert&&!wizard.closestShrine) active=false;
			if(!active){
				auto inactivePosition=Vector3f(i*pageScaling.x,info.height-pageScaling.y,0.0f);
				B.hudMaterialBackend.setTransformationScaled(inactivePosition,Quaternionf.identity(),pageScaling,rc);
				B.hudMaterialBackend.bindDiffuse(sacCursor.invalidTargetIconTexture);
				B.hudMaterialBackend.setAlpha(1.0f);
				quad.render(rc);
			}
			if(entry.spell.soulCost>souls){
				auto spiritPosition=Vector3f(i*pageScaling.x,info.height-pageScaling.y,0.0f);
				auto spiritScaling=hudScaling*Vector3f(16.0f,16.0f,0.0f);
				B.hudMaterialBackend.setTransformationScaled(spiritPosition,Quaternionf.identity(),spiritScaling,rc);
				B.hudMaterialBackend.bindDiffuse(sacHud.spirit);
				B.hudMaterialBackend.setAlpha(1.0f);
				quad.render(rc);
			}
		}
		B.hudMaterialBackend.unbind(null,rc);
		bool bound=false;
		foreach(i,entry;enumerate(spells)){
			if(entry.cooldown==0.0f) continue;
			if(!bound){ B.cooldownMaterialBackend.bind(null,rc); bound=true; }
			auto pagePosition=Vector3f((i+0.5f)*pageScaling.x,info.height-0.5f*pageScaling.y,0.0f);
			B.cooldownMaterialBackend.setTransformationScaled(pagePosition,Quaternionf.identity(),pageScaling,rc);
			float progress=1.0f-entry.cooldown/entry.maxCooldown;
			B.cooldownMaterialBackend.setProgress(progress);
			cooldown.render(rc);
		}
		if(bound){
			B.cooldownMaterialBackend.unbind(null,rc);
			bound=false;
		}
		material=sacHud.spellReadyMaterial;
		foreach(i,entry;enumerate(spells)){
			if(entry.readyFrame>=16*updateAnimFactor) continue;
			if(!bound){ material.bind(rc); bound=true; }
			auto flarePosition=Vector3f((i+0.5f)*pageScaling.x,info.height-0.5f*pageScaling.y,0.0f);
			auto flareScaling=hudScaling*Vector3f(48.0f,48.0f,0.0f);
			flareScaling.y*=-1.0f;
			material.backend.setTransformationScaled(flarePosition,Quaternionf.identity(),flareScaling,rc);
			sacHud.getSpellReadyMesh(entry.readyFrame).render(rc);
		}
		if(bound) material.unbind(rc);
	}
	bool statsVisible(ObjectState!B state,ref RenderInfo!B info){
		if(!info.camera.target) return false;
		return .statsVisible(info.camera.target,state);
	}
	bool spellbookVisible(ObjectState!B state,ref RenderInfo!B info){
		if(!info.camera.target) return false;
		return .spellbookVisible(info.camera.target,state);
	}
	void renderHUD(ObjectState!B state,ref RenderInfo!B info,B.RenderContext rc){
		if(!info.hudVisible) return;
		renderMinimap(state,info,rc);
		if(info.renderSide!=-1){
			if(statsVisible(state,info)) renderStats(state,info,rc);
			renderSelectionRoster(state,info,rc);
			if(spellbookVisible(state,info)) renderSpellbook(state,info,rc);
		}
	}

	void renderMouseoverText(scope const(char)[] text,int cursorSize,ref RenderInfo!B info,B.RenderContext rc,int yoffset=-1,scope Color4f[] lineColors=null){
		auto font=SacFont!B.get(FontType.fnwt);
		auto hudScaling=info.hudScaling;
		auto cursor=Vector3f(info.mouse.x, info.mouse.y, 0.0f);
		FormatSettings settings = {flowType:FlowType.left, scale:hudScaling};
		auto size=font.getSize(text,settings)+Vector2f((3.0f+3.0f)*hudScaling,(2.0f+4.0f)*hudScaling);
		auto boxScale=Vector3f(size.x,size.y, 0.0f);
		auto offset=Vector3f(cursorSize==-1?16*hudScaling:0.5f*cursorSize,yoffset*hudScaling, 0.0f);
		if(info.mouse.x+offset.x+boxScale.x>info.width) offset.x=-boxScale.x;
		auto upperLeft=cursor+offset;
		upperLeft.y=min(upperLeft.y,info.height-boxScale.y);
		upperLeft.y=max(upperLeft.y,0.0f);
		B.colorHUDMaterialBackend.bind(null,rc);
		B.colorHUDMaterialBackend.bindDiffuse(whiteTexture);
		B.colorHUDMaterialBackend.setColor(Color4f(0.0f,0.0f,0.0f,0.68f));
		B.colorHUDMaterialBackend.setTransformationScaled(upperLeft,Quaternionf.identity(),boxScale,rc);
		quad.render(rc);
		B.colorHUDMaterialBackend.unbind(null,rc);
		/+B.colorHUDMaterialBackend.setColor(Color4f(1.0f,1.0f,1.0f,1.0f));
		B.colorHUDMaterialBackend.bindDiffuse(font.texture);
		void drawLetter(dchar c,B.SubQuad mesh,float x,float y,float width,float height){
			B.colorHUDMaterialBackend.setTransformationScaled(Vector3f(x,y,0.0f),Quaternionf.identity(),Vector3f(width,height,0.0f),rc);
			mesh.render(rc);
		}+/
		auto textPos=upperLeft+Vector3f(3.0f*hudScaling,2.0f*hudScaling);
		bindFont(font,rc);
		if(lineColors){
			foreach(i,line;enumerate(text.splitter('\n'))){
				//B.colorHUDMaterialBackend.setColor(lineColors[i]);
				//font.write!drawLetter(line,textPos.x,textPos.y+i*hudScaling*font.lineHeight,settings);
				setFontColor(font,lineColors[i]);
				drawText(font,line,textPos.x,textPos.y+i*hudScaling*font.lineHeight,settings,info,rc);
			}
		}else{
			//font.write!drawLetter(text,textPos.x,textPos.y,settings);
			setFontColor(font,Color4f(1.0f,1.0f,1.0f,1.0f));
			drawText(font,text,textPos.x,textPos.y,settings,info,rc);
		}
		unbindFont(font,rc);
	}

	void renderMouseoverBox(int cursorSize,ObjectState!B state,scope SacFormState!B[] forms,ref RenderInfo!B info,B.RenderContext rc){
		auto target=info.mouse.target;
		static bool requiresDelay(TargetType type){
			final switch(type) with(TargetType){
				case none,terrain,creatureTab,spellTab,structureTab,spell: return false;
				case creature,building,soul,ability,xmenu,soulStat,manaStat,healthStat,formElement: return true;
			}
		}
		if(requiresDelay(target.type)&&info.mouse.targetUpdateFrame+info.mouse.mouseoverBoxDelay>info.mouse.frame)
			return;
		char[4096] buffer='\0';
		auto buf=buffer[];
		// TODO: localization!
		import std.format: formattedWrite;
		final switch(target.type){
			case TargetType.none, TargetType.terrain: break;
			case TargetType.creature, TargetType.building:
				if(!target.id||!state) break;
				static struct NTTInfo{
					bool valid=false;
					B.Texture icon=null;
					string name=null;
					string sideName=null;
					float relativeHealth;
					bool dead=false;
					int foesKilled=-1;
					int foesGibbed=-1;
					int level=-1;
					float relativeXP;
				}
				auto getNTTInfo(int id){
					if(target.type==TargetType.creature){
						return state.movingObjectById!((ref obj,renderSide){
							auto icon=obj.sacObject.icon;
							auto name=obj.sacObject.name;
							string sideName=null;
							int level=-1;
							float relativeHealth=obj.health/obj.creatureStats.maxHealth;
							auto relativeXP=float.init;
							bool dead=obj.isDead;
							auto foesKilled=-1;
							auto foesGibbed=-1;
							if(auto wiz=obj.isWizard?state.getWizard(obj.id):null){
								if(wiz.name.length) name=wiz.name;
								sideName=null;
								if(obj.side==renderSide){
									foesKilled=wiz.wizardStatistics.foesKilled;
									foesGibbed=wiz.wizardStatistics.foesGibbed;
									enforce(globalMinLevel<=wiz.level&&wiz.level<=globalMaxLevel);
									relativeXP=max(0.0f,min(wiz.experience/xpForLevel[wiz.level+1],1.0f));
								}
								level=wiz.level;
							}else{
								sideName=getSideName(obj.side,state);
								if(obj.side==renderSide){
									foesKilled=obj.creatureStatistics.foesKilled;
									foesGibbed=obj.creatureStatistics.foesGibbed;
								}
							}
							return NTTInfo(true,icon,name,sideName,relativeHealth,dead,foesKilled,foesGibbed,level,relativeXP);
						},()=>NTTInfo.init)(id,info.renderSide);
					}else if(target.type==TargetType.building){
						return state.staticObjectById!((ref obj,state){
							return state.buildingById!((ref bldg,sacObject,state){
								auto icon=sacObject.icon;
								auto name=sacObject.name;
								if(!icon) icon=bldg.sacBuilding.icon;
								if(!name.length) name=bldg.sacBuilding.name;
								string sideName=getSideName(bldg.side,state);
								float relativeHealth=bldg.health/bldg.maxHealth(state);
								if(isNaN(relativeHealth) && !name.length)
									return NTTInfo.init;
								return NTTInfo(true,icon,name,sideName,relativeHealth);
							},()=>NTTInfo.init)(obj.buildingId,obj.sacObject,state);
						},()=>NTTInfo.init)(id,state);
					}else assert(0);
				}
				auto nttInfo=getNTTInfo(target.id);
				if(!nttInfo.valid) break;
				if(nttInfo.dead){
					buf.formattedWrite!"%s's corpse"(nttInfo.name);
					renderMouseoverText(buffer[0..buf.ptr-buffer.ptr],cursorSize,info,rc);
					break;
				}
				bool renderHealth=!isNaN(nttInfo.relativeHealth);
				bool renderXP=!isNaN(nttInfo.relativeXP);
				auto hudScaling=info.hudScaling;
				auto cursor=Vector3f(info.mouse.x, info.mouse.y, 0.0f);
				auto boxScale=Vector3f(220*hudScaling,(renderXP?103:renderHealth?(nttInfo.icon?70:56):40)*hudScaling, 0.0f);
				auto offset=Vector3f(cursorSize==-1?16*hudScaling:0.5f*cursorSize,(renderXP?-44:renderHealth?(nttInfo.icon?-27:-20):-12)*hudScaling, 0.0f);
				if(info.mouse.x+offset.x+boxScale.x>info.width) offset.x=-boxScale.x;
				auto upperLeft=cursor+offset;
				upperLeft.y=min(upperLeft.y,info.height-boxScale.y);
				upperLeft.y=max(upperLeft.y,0.0f);
				B.colorHUDMaterialBackend.bind(null,rc);
				B.colorHUDMaterialBackend.bindDiffuse(whiteTexture);
				B.colorHUDMaterialBackend.setColor(Color4f(0.0f,0.0f,0.0f,0.68f));
				B.colorHUDMaterialBackend.setTransformationScaled(upperLeft,Quaternionf.identity(),boxScale,rc);
				quad.render(rc);
				B.colorHUDMaterialBackend.setColor(Color4f(1.0f,1.0f,1.0f,1.0f));
				if(nttInfo.icon){
					B.colorHUDMaterialBackend.bindDiffuse(nttInfo.icon);
					auto iconPos=upperLeft+Vector3f(3.0f*hudScaling,3.0f*hudScaling,0.0f);
					auto iconScale=Vector3f(32*hudScaling,32.0f*hudScaling,0.0f);
					B.colorHUDMaterialBackend.setTransformationScaled(iconPos,Quaternionf.identity(),iconScale,rc);
					quad.render(rc);
				}
				B.colorHUDMaterialBackend.unbind(null,rc);

				auto font=SacFont!B.get(FontType.fnwt);
				/+B.colorHUDMaterialBackend.bind(null,rc);
				B.colorHUDMaterialBackend.bindDiffuse(font.texture);+/
				if(nttInfo.sideName.length) buf.formattedWrite!"%s's %s"(nttInfo.sideName,nttInfo.name);
				else buf.formattedWrite!"%s"(nttInfo.name);
				if(nttInfo.level!=-1) buf.formattedWrite!"\nLevel %d"(nttInfo.level);
				if(nttInfo.foesKilled!=-1) buf.formattedWrite!"\nFoes killed: %d"(nttInfo.foesKilled);
				if(nttInfo.foesGibbed!=-1) buf.formattedWrite!"\nFoes gibbed: %d"(nttInfo.foesGibbed);
				auto text=buffer[0..buf.ptr-buffer.ptr];
				FormatSettings settings = {flowType:FlowType.left, scale:hudScaling};
				auto infoPos=upperLeft+Vector3f((3.0f+32.0f+4.0f)*hudScaling,2.0f*hudScaling,0.0f);
				/+void drawLetter(dchar c,B.SubQuad mesh,float x,float y,float width,float height){
					B.colorHUDMaterialBackend.setTransformationScaled(Vector3f(x,y,0.0f),Quaternionf.identity(),Vector3f(width,height,0.0f),rc);
					mesh.render(rc);
				}
				font.write!drawLetter(text,infoPos.x,infoPos.y,settings);+/
				bindFont(font,rc);
				setFontColor(font,Color4f(1.0f,1.0f,1.0f,1.0f));
				drawText(font,text,infoPos.x,infoPos.y,settings,info,rc);
				if(renderXP){
					auto xpPos=upperLeft+Vector3f(9*hudScaling,75*hudScaling);
					//font.write!drawLetter("Experience:",xpPos.x,xpPos.y,settings);
					drawText(font,"Experience:",xpPos.x,xpPos.y,settings,info,rc);
				}
				unbindFont(font,rc);
				void renderStatBar(Vector3f position,Vector3f maxScaling,float endScaling,float emptyScaling,float relativeSize){
					auto rotation=rotationQuaternion(Axis.z,-pi!float/2);
					auto emptyOffset=0.5f*(maxScaling.x-emptyScaling);
					auto emptyPosition=position+rotate(rotation,Vector3f(emptyOffset,maxScaling.y*relativeSize+endScaling,0.0f));
					auto fullEmptyScaling=Vector3f(emptyScaling,maxScaling.y*(1.0f-relativeSize),0.0f);
					auto scaling=Vector3f(maxScaling.x,maxScaling.y*relativeSize,0.0f);
					auto topPosition=position+rotate(rotation,Vector3f(0.0f,-endScaling,0.0f));
					auto topScaling=Vector3f(maxScaling.x,endScaling,0.0f);
					auto bottomPosition=position+rotate(rotation,Vector3f(0.0f,scaling.y,0.0f));
					auto bottomScaling=Vector3f(maxScaling.x,endScaling,0.0f);

					B.Material empty=sacHud.manaTopMaterial;
					B.Material[3] materials=[sacHud.healthTopMaterial,sacHud.healthMaterial,sacHud.healthBottomMaterial];
					Vector3f[3] positions=[topPosition,position,bottomPosition];
					Vector3f[3] scalings=[topScaling,scaling,bottomScaling];
					assert(empty.backend is B.colorHUDMaterialBackend);
					B.colorHUDMaterialBackend.bind(null,rc);
					B.disableCulling();
					B.colorHUDMaterialBackend.bindDiffuse(sacHud.mana[0]);
					B.colorHUDMaterialBackend.setColor(Color4f(0.25f,0.75f,1.5f,1.0f)); // TODO: alpha gradient
					B.colorHUDMaterialBackend.setTransformationScaled(emptyPosition, rotation, fullEmptyScaling, rc);
					quad.render(rc);
					B.enableCulling();
					B.colorHUDMaterialBackend.unbind(null,rc);
					static foreach(i;0..3){
						materials[i].bind(rc);
						B.disableCulling();
						materials[i].backend.setTransformationScaled(positions[i], rotation, scalings[i], rc);
						quad.render(rc);
						B.enableCulling();
						materials[i].unbind(rc);
					}
				}
				if(renderHealth){
					auto healthBarOffset=Vector3f(11*hudScaling,(nttInfo.icon?49:41)*hudScaling,0.0f);
					auto healthBarScaling=Vector3f(-11*hudScaling,boxScale.x-2*11*hudScaling,0.0f);
					renderStatBar(upperLeft+healthBarOffset,healthBarScaling,2*hudScaling,-(5+2)*hudScaling,nttInfo.relativeHealth);
				}
				if(renderXP){
					auto xpBarOffset=Vector3f(11*hudScaling,89*hudScaling,0.0f);
					auto xpBarScaling=Vector3f(-7*hudScaling,boxScale.x-2*11*hudScaling,0.0f);
					renderStatBar(upperLeft+xpBarOffset,xpBarScaling,2*hudScaling,-(3+2)*hudScaling,nttInfo.relativeXP);
				}
				break;
			case TargetType.soul:
				if(!state) break;
				final switch(color(info.mouse.target.id,info.renderSide,state)){
					case SoulColor.blue:
						renderMouseoverText("Soul",cursorSize,info,rc);
						break;
					case SoulColor.red:
						renderMouseoverText("Heathen soul\nConvert this.",cursorSize,info,rc,-6);
						break;
					case SoulColor.green:
						if(!sacGreenSoul) goto case SoulColor.red;
						renderMouseoverText("Allied soul",cursorSize,info,rc,-6);
						break;
				}
				break;
			case TargetType.creatureTab:
				renderMouseoverText("Creation spells",cursorSize,info,rc);
				break;
			case TargetType.spellTab:
				renderMouseoverText("Spells",cursorSize,info,rc);
				break;
			case TargetType.structureTab:
				renderMouseoverText("Structure spells",cursorSize,info,rc);
				break;
			case TargetType.spell:
				if(!state) break;
				auto wizard=state.getWizard(info.camera.target);
				if(!wizard) break;
				auto availableMana=state.movingObjectById!((ref obj)=>obj.creatureStats.mana,()=>float.init)(info.camera.target);
				if(isNaN(availableMana)) break;
				auto availableSouls=wizard.souls;
				auto targetSpell=info.mouse.targetSpell;
				if(!targetSpell||!targetSpell.name.length) break;
				auto mana=targetSpell.manaCost;
				auto souls=targetSpell.soulCost;
				int yoffset=-6;
				auto red=Color4f(1.0f,0.0f,0.0f,1.0f);
				Color4f[3] lineColors=Color4f(1.0f,1.0f,1.0f,1.0);
				buf.formattedWrite!"%s\nMana: %d/%d"(targetSpell.name,cast(int)floor(mana),cast(int)floor(availableMana));
				int numLines=2;
				bool manaRed=availableMana<mana;
				if(manaRed) lineColors[1]=red;
				if(targetSpell.type==SpellType.creature){
					buf.formattedWrite!"\nSouls: %d"(souls);
					numLines++;
					bool soulsRed=availableSouls<souls;
					if(soulsRed) lineColors[2]=red;
					yoffset=-12;
				}
				renderMouseoverText(buffer[0..buf.ptr-buffer.ptr],cursorSize,info,rc,yoffset,lineColors[0..numLines]);
				break;
			case TargetType.ability:
				auto targetSpell=info.mouse.targetSpell;
				if(!targetSpell||!targetSpell.name.length) break;
				renderMouseoverText(targetSpell.name,cursorSize,info,rc);
				break;
			case TargetType.xmenu:
				if(info.mouse.xmenuTargetId!="\0\0\0\0")
					renderMouseoverText(sacXmenu.get(info.mouse.xmenuTargetId).name,cursorSize,info,rc);
				break;
			case TargetType.soulStat:
				renderMouseoverText("Soul counter",cursorSize,info,rc);
				break;
			case TargetType.manaStat:
				renderMouseoverText("Mana bar",cursorSize,info,rc);
				break;
			case TargetType.healthStat:
				renderMouseoverText("Health bar",cursorSize,info,rc);
				break;
			case TargetType.formElement:
				auto mouseoverText=forms[target.formIndex].elements[target.elementIndex].mouseoverText;
				if(mouseoverText) renderMouseoverText(mouseoverText,cursorSize,info,rc);
				break;
		}
	}

	void renderText(ObjectState!B state,ref RenderInfo!B info,B.RenderContext rc){
		auto font=SacFont!B.get(FontType.fn10);
		/+B.colorHUDMaterialBackend.bind(null,rc);
		B.colorHUDMaterialBackend.bindDiffuse(font.texture);
		void drawLetter(dchar c,B.SubQuad mesh,float x,float y,float width,float height){
			B.colorHUDMaterialBackend.setTransformationScaled(Vector3f(x,y,0.0f),Quaternionf.identity(),Vector3f(width,height,0.0f),rc);
			mesh.render(rc);
		}+/
		/*FormatSettings testSettings = {flowType: FlowType.left, scale: 2.0f*info.hudScaling, maxWidth: 0.5f*info.width};
		font.write!drawLetter("Test.",0.0f,0.0f,testSettings);*/
		// number of souls
		if(info.renderSide!=-1 && statsVisible(state,info)){
			if(auto wizard=state.getWizard(info.camera.target)){
				char[32] buffer='\0';
				import std.format: formattedWrite;
				buffer[].formattedWrite!"%d"(wizard.souls);
				import std.algorithm;
				auto text=buffer[0..buffer[].countUntil('\0')];
				FormatSettings settings = {flowType:FlowType.left, scale:info.hudScaling};
				auto size=font.getSize(text,settings);
				// TODO: get rid of code duplication
				auto scaling0=Vector2f(64.0f,96.0f);
				scaling0*=info.hudScaling;
				auto scaling1=Vector3f(32.0f,96.0f);
				scaling1*=info.hudScaling;
				auto position0=Vector2f(info.width-2*scaling1.x-0.5f*scaling0.x,0.5f*scaling0.y);
				auto soulPositionDark=position0-0.5f*size;
				bindFont(font,rc);
				//B.colorHUDMaterialBackend.setColor(Color4f(0.0f,0.0f,0.0f,1.0f));
				//font.write!drawLetter(text,soulPositionDark.x,soulPositionDark.y,settings);
				setFontColor(font,Color4f(0.0f,0.0f,0.0f,1.0f));
				drawText(font,text,soulPositionDark.x,soulPositionDark.y,settings,info,rc);
				auto soulPosition=position0-0.5f*(size+info.hudScaling);
				//B.colorHUDMaterialBackend.setColor(Color4f(1.0f,1.0f,1.0f,1.0f));
				//font.write!drawLetter(text,soulPosition.x,soulPosition.y,settings);
				setFontColor(font,Color4f(1.0f,1.0f,1.0f,1.0f));
				drawText(font,text,soulPosition.x,soulPosition.y,settings,info,rc);
				unbindFont(font,rc);
			}
		}
		/+auto gameState=B.scene.state;
		auto controller=B.scene.controller;
		if(gameState&&controller&&controller.network){
			char[1024] buf=0;
			import std.format: formattedWrite;
			buf[].formattedWrite!"%s %s (%s)\n%s\n%s (%s)\n%s\n%s\n%s %s"(
				gameState.committedFrame,gameState.currentFrame,gameState.currentFrame-gameState.committedFrame,
				controller.network.committedFrame-gameState.committedFrame,
				controller.network.players.map!(x=>x.committedFrame),controller.network.players.map!(x=>x.committedFrame-gameState.committedFrame),
				controller.network.players.map!(x=>x.status),
				controller.network.players.map!(x=>x.ping.total!"msecs"),
				controller.network.pauseOnDrop, controller.network.settings.pauseOnDrop
			);
			bindFont(font,rc);
			setFontColor(font,Color4f(1.0f,1.0f,1.0f,1.0f));
			import std.range,std.algorithm;
			auto text=buf[0..buf[].countUntil(0)];
			FormatSettings settings = {flowType:FlowType.left, scale:info.hudScaling};
			drawText(font,text,2,2,settings,info,rc);
			unbindFont(font,rc);
			//B.colorHUDMaterialBackend.unbind(null,rc);
		}+/
		static Array!char triggerBuffer;
		triggerBuffer.length=0;
		triggerText((scope const(char)[] text){ foreach(c;text) triggerBuffer~=c; },state.trig,state);
		if(triggerBuffer.length){
			bindFont(font,rc);
			setFontColor(font,Color4f(1.0f,1.0f,1.0f,1.0f));
			FormatSettings settings = {flowType:FlowType.left, scale:info.hudScaling};
			drawText(font,triggerBuffer.data,5*info.hudScaling,5*info.hudScaling,settings,info,rc);
			unbindFont(font,rc);
		}
	}

	void renderChatMessage(ref ChatMessage!B message,int yOffset,ref RenderInfo!B info,B.RenderContext rc){
		B.colorHUDMaterialBackend.bind(null,rc);
		B.colorHUDMaterialBackend.bindDiffuse(whiteTexture);
		B.colorHUDMaterialBackend.setColor(Color4f(0.0f,0.0f,0.0f,174.0f/255.0f));
		auto width=ChatMessage!B.boxWidth*info.hudScaling;
		auto pixelHeight=ChatMessage!B.additionalBoxHeight+message.textHeight;
		auto height=pixelHeight*info.hudScaling;
		auto offset=Vector3f(0.5f*(info.width-width),yOffset*info.hudScaling,0.0f);
		B.colorHUDMaterialBackend.setTransformationScaled(offset,Quaternionf.identity(),Vector3f(width,height,0.0f),rc);
		quad.render(rc);
		B.colorHUDMaterialBackend.unbind(null,rc);
		/+void drawLetter(dchar c,B.SubQuad mesh,float x,float y,float width,float height){
			B.colorHUDMaterialBackend.setTransformationScaled(Vector3f(x,y,0.0f),Quaternionf.identity(),Vector3f(width,height,0.0f),rc);
			mesh.render(rc);
		}+/
		auto titleFont=SacFont!B.get(FontType.fn12);
		auto titleSettings=FormatSettings(FlowType.left,info.hudScaling);
		auto titleSize=titleFont.getSize(message.content.title.data,titleSettings);
		auto titleOffset=Vector3f(0.5f*(info.width-titleSize.x),(yOffset+ChatMessage!B.titleOffset)*info.hudScaling,0.0f);
		//B.colorHUDMaterialBackend.bindDiffuse(titleFont.texture);
		//B.colorHUDMaterialBackend.setColor(Color4f(0.0f,1.0f,1.0f,1.0f));
		//titleFont.write!drawLetter(message.content.title.data,titleOffset.x,titleOffset.y,titleSettings);
		bindFont(titleFont,rc);
		setFontColor(titleFont,Color4f(0.0f,1.0f,1.0f,1.0f));
		drawText(titleFont,message.content.title.data,titleOffset.x,titleOffset.y,titleSettings,info,rc);
		unbindFont(titleFont,rc);
		auto font=SacFont!B.get(FontType.fn10);
		auto settings=FormatSettings(FlowType.left,info.hudScaling,ChatMessage!B.maxWidth*info.hudScaling);
		auto textSize=Vector2f(message.textWidth*info.hudScaling,message.textHeight*info.hudScaling);
		auto textOffset=Vector3f(floor(0.5f*(info.width-textSize.x)),floor((yOffset+ChatMessage!B.messageOffset)*info.hudScaling),0.0f); // TODO: should be a bit further to the left?
		//B.colorHUDMaterialBackend.bindDiffuse(font.texture);
		//B.colorHUDMaterialBackend.setColor(Color4f(1.0f,1.0f,1.0f,1.0f));
		//font.write!drawLetter(message.content.message.data,textOffset.x,textOffset.y,settings);
		bindFont(font,rc);
		setFontColor(font,Color4f(1.0f,1.0f,1.0f,1.0f));
		drawText(font,message.content.message.data,textOffset.x,textOffset.y,settings,info,rc);
		unbindFont(font,rc);
	}

	void renderChatMessages(ObjectState!B state,NetworkState!B networkState,ref RenderInfo!B info,B.RenderContext rc){
		int slot=info.renderSlot;
		auto frame=info.activeChatMessages.frame;
		foreach(fromNetwork;0..2){{
			if(!fromNetwork&&!state) continue;
			if(fromNetwork&&!networkState) continue;
			scope messages=(fromNetwork?networkState.chatMessages:state.obj.opaqueObjects.chatMessages).messages.data;
			info.activeChatMessages.chatMessageIndex[fromNetwork]=min(info.activeChatMessages.chatMessageIndex[fromNetwork],messages.length);
			// TODO: this may race a bit with game state updating in response to network
			for(;;++info.activeChatMessages.chatMessageIndex[fromNetwork]){
				auto i=info.activeChatMessages.chatMessageIndex[fromNetwork];
				if(i>=messages.length) break;
				if(!fromNetwork&&messages[i].startFrame>state.frame) break;
				auto height=ChatMessage!B.additionalBoxHeight+messages[i].textHeight;
				if(messages[i].visibleToSlot(slot,state))
					info.activeChatMessages.add(i,height,ChatMessage!B.topOffset,ChatMessage!B.gapSize,!!fromNetwork,frame);
			}
		}}
		for(int i=0;i<info.activeChatMessages.messages.length;){
			auto fromNetwork=info.activeChatMessages.messages[i].fromNetwork;
			if(!fromNetwork&&!state) continue;
			if(fromNetwork&&!networkState) continue;
			auto index=info.activeChatMessages.messages[i].index;
			int messageFrame=info.activeChatMessages.messages[i].frame;
			scope messages=(fromNetwork?networkState.chatMessages:state.obj.opaqueObjects.chatMessages).messages.data;
			if(index<messages.length&&messages[index].visibleToSlot(slot,state)){
				auto currentOffset=info.activeChatMessages.messages[i].offset;
				renderChatMessage(messages[index],currentOffset,info,rc);
			}
			bool removed=false;
			if(index<messages.length){
				if(messageFrame+messages[index].lifetime<=frame||messages[index].startFrame+messages[index].lifetime<=state.frame){
					info.activeChatMessages.remove(i);
					removed=true;
				}
			}
			if(!removed) i++;
		}
	}

	/+void renderSacForm(SacForm!B sacForm,ObjectState!B state,ref RenderInfo!B info,B.RenderContext rc){
		B.colorHUDMaterialBackend.bind(null,rc);
		void doIt(SacForm!B sacForm,Vector3f offset,Quaternionf rotation,Vector3f scale){
			B.colorHUDMaterialBackend.setTransformationScaled(offset,rotation,scale,rc);
			//import sacfont,form;
			SacFont!B[FormFont.max+1] fonts;
			import std.traits: EnumMembers;
			foreach(formFont;EnumMembers!FormFont)
				fonts[formFont]=formSacFont!B(formFont);
			foreach(element,ref sacElement;sacForm.sacElements){
				auto active=sacElement.type==ElementType.form||sacElement.id==sacForm.default_; // TODO: fix
				// auto active=state.frame/60%2==1;
				foreach(i,ref part;sacElement.parts){
					B.colorHUDMaterialBackend.bindDiffuse(part.texture);
					if(i==0&&sacElement.type==ElementType.canvas){
						B.colorHUDMaterialBackend.setColor(Color4f(0.0f,0.0f,0.0f,1.0f));
						part.mesh[active].render(rc); // TODO: actually get correct canvas contents
						B.colorHUDMaterialBackend.setColor(Color4f(1.0f,1.0f,1.0f,1.0f));
					}else part.mesh[active].render(rc);
				}
				foreach(i,ref subForm;sacElement.subForms){
					doIt(subForm.form,offset+Vector3f(subForm.offset.x*scale.x,subForm.offset.y*scale.y,0.0f),rotation,scale);
				}
				foreach(ref text;sacElement.texts){
					B.colorHUDMaterialBackend.unbind(null,rc);
					auto font=fonts[text.font];
					auto settings=FormatSettings(FlowType.left,scale.x);
					/+B.colorHUDMaterialBackend.bindDiffuse(font.texture);
					void drawLetter(dchar c,B.SubQuad mesh,float x,float y,float width,float height){
						B.colorHUDMaterialBackend.setTransformationScaled(Vector3f(x,y,0.0f),Quaternionf.identity(),Vector3f(width,height,0.0f),rc);
						mesh.render(rc);
					}
					font.write!drawLetter(text.text,offset.x+text.position.x*scale.x,offset.y+text.position.y*scale.y,settings);+/
					bindFont(font,rc);
					setFontColor(font,Color4f(1.0f,1.0f,1.0f,1.0f));
					drawText(font,text.text,offset.x+text.position.x*scale.x,offset.y+text.position.y*scale.y,settings,info,rc);
					unbindFont(font,rc);
					B.colorHUDMaterialBackend.bind(null,rc);
				}
				if(sacElement.subForms.length||sacElement.texts.length){
					B.colorHUDMaterialBackend.setTransformationScaled(offset,rotation,scale,rc);
				}
			}
		}
		auto offset=Vector3f(0.5f*(info.width-info.hudScaling*sacForm.width),0.5f*(info.height-info.hudScaling*sacForm.height),0.0f);
		auto rotation=Quaternionf.identity();
		auto scale=Vector3f(info.hudScaling,info.hudScaling,0.0f);
		doIt(sacForm,offset,rotation,scale);
		B.colorHUDMaterialBackend.unbind(null,rc);
	}+/

	void updateFormTarget(Target target,Vector2f position,Vector2f size,ref RenderInfo!B info){
		if(!info.mouse.menuMode) return;
		auto topLeft=position;
		auto bottomRight=position+size;
		if(floor(topLeft.x)<=info.mouse.x&&info.mouse.x<=ceil(bottomRight.x)
		   && floor(topLeft.y)<=info.mouse.y&&info.mouse.y<=ceil(bottomRight.y)){
			formTarget=target;
		}
	}

	void renderForm(ref SacFormState!B form,ushort formIndex,ref RenderInfo!B info,B.RenderContext rc){
		SacFont!B[FormFont.max+1] fonts;
		import std.traits: EnumMembers;
		foreach(formFont;EnumMembers!FormFont)
			fonts[formFont]=formSacFont!B(formFont);
		/+void drawLetter(dchar c,B.SubQuad mesh,float x,float y,float width,float height){
			B.colorHUDMaterialBackend.setTransformationScaled(Vector3f(x,y,0.0f),Quaternionf.identity(),Vector3f(width,height,0.0f),rc);
			mesh.render(rc);
		}+/
		void renderFormElements(SacForm!B sacForm,scope ElementState[] elements,int s,int e,int activeElement,int targetElement,Vector3f offset,Quaternionf rotation,Vector3f scale){
			enforce(elements[s].type==ElementType.form&&elements[s].numChildren+1==e-s);
			B.colorHUDMaterialBackend.setTransformationScaled(offset,rotation,scale,rc);
			void renderElement(ref SacFormElement!B sacElement,ushort elementIndex,bool active,bool target){
				if(!elements[elementIndex].visible) return;
				if(!elements[elementIndex].enabled) B.colorHUDMaterialBackend.setAlpha(0.5f);
				scope(success) if(!elements[elementIndex].enabled) B.colorHUDMaterialBackend.setAlpha(1.0f);
				auto elementTarget=Target.onForm(formIndex,elementIndex);
				assert(elementTarget.formIndex==formIndex&&elementTarget.elementIndex==elementIndex);
				auto scaledOffset=Vector2f(sacElement.offset.x*scale.x,sacElement.offset.y*scale.y);
				auto scaledSize=Vector2f(sacElement.size.x*scale.x,sacElement.size.y*scale.y);
				updateFormTarget(elementTarget,Vector2f(offset.x,offset.y)+scaledOffset,scaledSize,info);
				// active=state.frame/60%2==1;
				foreach(i,ref part;sacElement.parts){
					B.colorHUDMaterialBackend.bindDiffuse(part.texture);
					if(i==0&&sacElement.type==ElementType.canvas){
						B.colorHUDMaterialBackend.setColor(Color4f(0.0f,0.0f,0.0f,1.0f));
						part.mesh[active].render(rc); // TODO: actually get correct canvas contents
						B.colorHUDMaterialBackend.setColor(Color4f(1.0f,1.0f,1.0f,1.0f));
					}else if(i+1==sacElement.parts.length&&sacElement.type==ElementType.checkbox){
						part.mesh[elements[elementIndex].checked].render(rc);
					}else{
						part.mesh[active].render(rc);
					}
				}
				auto settings=FormatSettings(FlowType.left,scale.x);
				B.colorHUDMaterialBackend.unbind(null,rc);
				foreach(ref text;sacElement.texts){
					auto font=fonts[text.font];
					/+B.colorHUDMaterialBackend.bindDiffuse(font.texture);
					font.write!drawLetter(text.text,offset.x+text.position.x*scale.x,offset.y+text.position.y*scale.y,settings);+/
					bindFont(font,rc);
					auto alpha=font.type==FontType.fn08?(target?1.0f:0.75f):1.0f;
					setFontColor(font,Color4f(1.0f,1.0f,1.0f,alpha));
					const(char)[] textInput=elements[elementIndex].textInput.data[elements[elementIndex].textStart..elements[elementIndex].textEnd];
					drawText(font,textInput.length?textInput:text.text,offset.x+text.position.x*scale.x,offset.y+text.position.y*scale.y,settings,info,rc);
					unbindFont(font,rc);
				}
				if(sacElement.type==ElementType.entrybox){
					auto font=fonts[FormFont.standard];
					auto textPosition=Vector2f(offset.x+(sacElement.offset.x+20)*scale.x,offset.y+(sacElement.offset.y+3.0f)*scale.y);
					const(char)[] text=elements[elementIndex].textInput.data[elements[elementIndex].textStart..elements[elementIndex].textEnd];
					/+B.colorHUDMaterialBackend.bindDiffuse(font.texture);
					font.write!drawLetter(text,textPosition.x,textPosition.y,settings);+/
					bindFont(font,rc);
					setFontColor(font,Color4f(1.0f,1.0f,1.0f,1.0f));
					drawText(font,text,textPosition.x,textPosition.y,settings,info,rc);
					unbindFont(font,rc);
				}
				B.colorHUDMaterialBackend.bind(null,rc);
				B.colorHUDMaterialBackend.setColor(Color4f(1.0f,1.0f,1.0f,1.0f));
				if(sacElement.texts.length||sacElement.type==ElementType.entrybox){
					B.colorHUDMaterialBackend.setTransformationScaled(offset,rotation,scale,rc);
				}
			}
			renderElement(sacForm.sacElements[0],to!ushort(s),true,targetElement!=-1); // render form itself
			for(int i=s+1;i<e;i++){
				if(elements[i].type!=ElementType.form){
					enforce(sacForm.sacElements[elements[i].sacFormIndex].subForms.length==0);
					renderElement(sacForm.sacElements[elements[i].sacFormIndex],to!ushort(i),i==activeElement,i==targetElement);
				}else{
					enforce(sacForm.sacElements[elements[i].sacFormIndex].subForms.length==1);
					enforce(sacForm.sacElements[elements[i].sacFormIndex].parts.length==0);
					enforce(sacForm.sacElements[elements[i].sacFormIndex].texts.length==0);
					auto subOffsetRaw=sacForm.sacElements[elements[i].sacFormIndex].subForms[0].offset;
					auto subOffset=Vector3f(subOffsetRaw.x*scale.x,subOffsetRaw.y*scale.y,0.0f);
					auto subSacForm=sacForm.sacElements[elements[i].sacFormIndex].subForms[0].form;
					auto numChildren=elements[i].numChildren;
					renderFormElements(subSacForm,elements,i,i+1+numChildren,activeElement,targetElement,offset+subOffset,rotation,scale);
					B.colorHUDMaterialBackend.setTransformationScaled(offset,rotation,scale,rc);
					i+=numChildren;
				}
			}
		}
		auto sacForm=form.sacForm;
		auto offset=Vector3f(0.5f*(info.width-info.hudScaling*sacForm.width),0.5f*(info.height-info.hudScaling*sacForm.height),0.0f);
		auto rotation=Quaternionf.identity();
		auto scale=Vector3f(info.hudScaling,info.hudScaling,0.0f);
		auto elementIndex=-1;
		if(info.mouse.target.type==TargetType.formElement&&info.mouse.target.formIndex==formIndex)
			elementIndex=info.mouse.target.elementIndex;
		renderFormElements(sacForm,form.elements.data,0,to!int(form.elements.data.length),form.activeIndex,elementIndex,offset,rotation,scale);
	}

	void renderForms(scope SacFormState!B[] forms,ref RenderInfo!B info,B.RenderContext rc){
		if(info.mouse.menuMode) formTarget=Target.init;
		B.colorHUDMaterialBackend.bind(null,rc);
		B.colorHUDMaterialBackend.setColor(Color4f(1.0f,1.0f,1.0f,1.0f));
		/+//auto sacForm=SacForm!B.get("tsor");
		auto sacForm=SacForm!B.get("thci");
		//auto sacForm=SacForm!B.get("nsol");
		//auto sacForm=SacForm!B.get("rniw");
		//auto sacForm=SacForm!B.get("stls");
		//auto sacForm=SacForm!B.get("ybol");
		//auto sacForm=SacForm!B.get("unmg");
		//auto sacForm=SacForm!B.get("stpo");
		//auto sacForm=SacForm!B.get("tpog");
		//auto sacForm=SacForm!B.get("tpos");
		//auto sacForm=SacForm!B.get("tpok");
		//auto sacForm=SacForm!B.get("tpoc");
		//auto sacForm=SacForm!B.get("tpmc");
		renderSacForm(sacForm,info,rc);+/
		/+auto formInstance=sacFormInstance!B("thci");
		renderForm(formInstance,info,rc);+/
		foreach(i,ref form;forms){
			renderForm(form,to!ushort(i),info,rc);
		}
		B.colorHUDMaterialBackend.unbind(null,rc);
	}

	void renderShadowCastingEntities3D(R3DOpt options,ObjectState!B state,ref RenderInfo!B info,B.RenderContext rc){
		renderMap(state,info,rc);
		renderNTTs!(RenderMode.opaque)(options,state,info,rc);
	}

	void renderOpaqueEntities3D(R3DOpt options,ObjectState!B state,ref RenderInfo!B info,B.RenderContext rc){
		renderMap(state,info,rc);
		renderNTTs!(RenderMode.opaque)(options,state,info,rc);
		if(showHitboxes) renderHitboxes(state,info,rc);
	}
	void renderTransparentEntities3D(R3DOpt options,ObjectState!B state,ref RenderInfo!B info,B.RenderContext rc){
		renderSky(state,info,rc);
		renderNTTs!(RenderMode.transparent)(options,state,info,rc);
		renderCreatureStats(state,info,rc);
	}
	static struct R2DOpt{
		int cursorSize;
	}
	void renderEntities2D(R2DOpt options,ObjectState!B state,NetworkState!B networkState,scope SacFormState!B[] forms,ref RenderInfo!B info,B.RenderContext rc){
		if(info.mouse.visible){
			if(state){
				renderTargetFrame(state,info,rc);
				renderHUD(state,info,rc);
				renderText(state,info,rc);
			}
			renderChatMessages(state,networkState,info,rc);
			renderForms(forms,info,rc);
			renderRectangleSelectFrame(info,rc);
			renderCursor(options.cursorSize,state,info,rc);
			renderMouseoverBox(options.cursorSize,state,forms,info,rc);
		}else{
			renderChatMessages(state,networkState,info,rc);
			if(state) renderText(state,info,rc);
		}
	}
}

