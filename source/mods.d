// Optional client-side mods.
//
// A mod lives in mods/<name>/source, is compiled into the game (dub.json) and
// registers itself from a module constructor; nothing in source/ imports it.
// Mods only read the game state and draw: they never change the simulation,
// the network protocol or the game data. With no active mod every hook below
// is a loop over an empty array.
module mods;

import core.time : Duration;
import dagon : GenericMaterial, GeometryPassBackend, RenderingContext;
import dagonBackend : DagonBackend, SacScene;
import options : Options;
import renderer : CreatureOverride, RenderInfo;
import sacmap : SacMap;
import sacobject : SacObject;
import saxs : Saxs;
import state : ObjectState;

private alias B=DagonBackend;

abstract class Mod{
	/// Whether the mod runs with these local options.
	abstract bool enabled(ref const Options options);

	// Scene (dagonBackend.d)
	void allocate(SacScene scene){}                               // the scene's GPU resources exist
	void stateChanged(SacScene scene){}                           // new or no game state; environment set up
	void update(SacScene scene,Duration dt){}                     // every frame, before Dagon's scene update
	void control(SacScene scene,Duration dt){}                    // local keys (scene.keyDown)
	void followCamera(SacScene scene,int target){}                // follow camera focused on target
	void drawShadowCasters(SacScene scene,RenderingContext* rc){} // after the game's shadow casters
	void drawOpaque(SacScene scene,RenderingContext* rc){}        // after the game's opaque objects
	void drawTransparent(SacScene scene,RenderingContext* rc){}   // after the game's transparent objects
	string statusLabel(SacScene scene){ return null; }            // short text under the FPS box

	// Materials and terrain
	void materialCreated(SacObject!B object,GenericMaterial material){}
	GeometryPassBackend sceneryBackend(){ return null; }          // opaque pass of static scenery
	void terrainTexture(SacMap!B map,int tile,bool scarred){}     // terrain texture about to be drawn (-1: done)

	// Models: the original model only, never a replacement model; called after
	// loading, before the meshes are made (parts, positions and textures may change)
	void modelLoaded(char[4] tag,char[4] model,ref Saxs!B saxs){}

	// Creatures, once per pass before they are drawn (see CreatureOverride in renderer.d)
	void creatures(bool opaquePass,ObjectState!B state,ref RenderInfo!B info,RenderingContext* rc,
	               ref CreatureOverride!B[] overrides){}
}

private __gshared Mod[] registered, active;

/// Called from a mod's module constructor.
void register(Mod mod){ registered~=mod; }

/// Called once at startup with the local options.
void configure(ref const Options options){
	active=null;
	foreach(mod;registered) if(mod.enabled(options)) active~=mod;
}

/// The mods enabled by the local options.
@property Mod[] activeMods(){ return active; }
