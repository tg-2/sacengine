// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

// Rendering-only dynamic lights. No simulation state is modified.
module dynamiclighting;

import dagon;
import core.time : MonoTime;
import dlib.math.portable;
import dlib.math.quaternion;
import std.algorithm : min, max;
import sacobject, state;
import ntts : God, Flags;
import util;

struct DynamicLighting {
    private util.Array!LightSource pool;
    enum maxLights = 72;
    enum float energyMultiplier = 10.0f;
    enum float fadeStart = 100.0f;
    enum float fadeEnd = 200.0f;
    private size_t used;
    enum float fountainFadeIn = 0.20f;
    enum float fountainFadeOut = 0.50f;
    enum float manalithFadeIn = 0.50f;
    enum float manalithFadeOut = 0.50f;
    enum float shrineFadeIn = 0.50f;
    enum float shrineFadeOut = 0.50f;

    // Local render history, independent of simulation time and state.
    private enum BuildingLight : long { fountain, manalith, shrine }
    private struct FadeRecord {
        long[5] key;
        Vector3f pos, color;
        float energy, radius, duration, level;
        MonoTime lastSeen;
        bool fading;
        bool matched;
    }
    private FadeRecord[maxLights] history;
    private size_t historyCount;

    // Per-frame lookup tables. They are cleared every frame but keep their
    // storage, so update does not allocate on the GC heap (the GC is disabled
    // while the game runs, built-in associative arrays would leak).
    private HashSet!int revivalTargets, animateDeadTargets, excludedCasters;
    private HashMap!(int,God) castingGods;
    private HashSet!(long[4]) occupied;

	// Use the distance to the light volume, not just its center.
	// Squared distances avoid a square root for every candidate.
	float distanceFade(SceneType)(Vector3f pos, float radius, SceneType scene) {
		auto cameraPos = scene.camera.position;
		auto d = pos - cameraPos;
		float d2 = d.x*d.x + d.y*d.y + d.z*d.z;
		float near = fadeStart + radius;
		float far = fadeEnd + radius;
		if (d2 >= far*far) return 0.0f;
		if (d2 <= near*near) return 1.0f;
		float t = (d2-near*near)/(far*far-near*near);
		return 1.0f-t*t*(3.0f-2.0f*t);
	}


	bool emit(SceneType,StateType)(Vector3f pos, Vector3f color, float energy, float radius, SceneType scene, StateType st) {
		if (used >= maxLights || energy <= 0.0f) return false;
		energy *= distanceFade(pos, radius, scene);
		if (energy <= 0.0f) return false;
		if (used == pool.length)
			pool ~= scene.createLight(Vector3f(0,0,0), Color4f(0,0,0,1), 0.0f, 0.01f);
		auto light = pool[used++];
		light.position = pos;
		light.color = color;
		light.energy = energy * energyMultiplier;
		light.radius = radius;
		return true;
	}

    void update(B, SceneType)(SceneType scene) {
        used = 0;
        scope(exit) {
            foreach (light; pool.data[used .. pool.length]) {
                light.energy = 0.0f;
                light.radius = 0.01f;
            }
        }
        if (!scene.lightManager) { historyCount = 0; return; }
        if (!scene.state || !scene.state.current) { historyCount = 0; return; }
		auto st = scene.state.current;
        auto objects = &st.obj.opaqueObjects;
		auto effects = &objects.effects;
        auto now = MonoTime.currTime;
        FadeRecord[maxLights] nextHistory;
        size_t nextCount = 0;
        foreach (ref record; history[0 .. historyCount]) record.matched = false;

        float secondsSince(MonoTime stamp) {
            return max(0.0f, cast(float)(now - stamp).total!"usecs" / 1_000_000.0f);
        }
        float smooth(float t) {
            t = max(0.0f, min(1.0f, t));
            return t*t*(3.0f-2.0f*t);
        }
        void emitPersistent(long[5] key, Vector3f pos, Vector3f color,
                            float energy, float radius) {
            float inTime, outTime;
            switch (cast(BuildingLight)key[0]) with (BuildingLight) {
                case fountain: inTime=fountainFadeIn; outTime=fountainFadeOut; break;
                case manalith: inTime=manalithFadeIn; outTime=manalithFadeOut; break;
                default: inTime=shrineFadeIn; outTime=shrineFadeOut; break;
            }
            float level = 0.0f;
            foreach (ref old; history[0 .. historyCount]) {
                if (old.key != key) continue;
                old.matched = true;
                float dt = secondsSince(old.lastSeen);
                level = old.fading ? old.level*max(0.0f,1.0f-dt/old.duration) : old.level;
                if (!old.fading) level = min(1.0f, level + dt/inTime);
                break;
            }
            if (used >= maxLights || nextCount >= maxLights || distanceFade(pos,radius,scene) <= 0.0f) return;
            float gain = smooth(level);
            if (gain > 0.0f && !emit(pos,color,energy*gain,radius,scene,st)) return;
            FadeRecord record;
            record.key = key;
            record.pos = pos;
            record.color = color;
            record.energy = energy;
            record.radius = radius;
            record.duration = outTime;
            record.level = level;
            record.lastSeen = now;
            nextHistory[nextCount++] = record;
        }
        enum orange = Vector3f(1,0.5f,0);
        enum yellow = Vector3f(1,1,0);
        enum purple = Vector3f(0.8f,0.15f,0.8f);
        enum white = Vector3f(1,1,1);
        enum green = Vector3f(0,1,0);
        enum blue = Vector3f(0,0.75f,1);
        enum lift = Vector3f(0,0,1.5f);
        void attached(int id, Vector3f color, float energy, float radius) {
            if (!st.isValidTarget(id,TargetType.creature)) return;
            auto pos = st.movingObjectReadById!((ref o,j) => o.positions[j], () => Vector3f.init)(id);
            emit(pos+lift,color,energy,radius,scene,st);
        }
        void beam(Vector3f a, Vector3f b, Vector3f color, float energy, float radius) {
	        foreach (i; 0..3) emit(a+(b-a)*(i/2.0f), color, energy, radius, scene, st);
        }

        // Explicit effect lights: independent of particle generation.
        foreach (ref e; effects.lightnings.data) {
            auto a = e.start.center(st), b = e.end.center(st);
            auto end = min(1.0f,e.frame/12.0f);
            auto start = max(0.0f,(e.frame-52)/12.0f);
            beam(a+(b-a)*start,a+(b-a)*end,white,6,45);
        }
        foreach (ref e; effects.chainLightnings.data)
            beam(e.last.center(st),e.current.center(st),white,4,35);
        foreach (ref e; effects.wraths.data)
	        emit(e.position+lift,orange,8,40,scene,st);
        foreach (ref e; effects.fireballs.data)
	        emit(e.position,Vector3f(1,0.34f,0.08f),5,25,scene,st);
        foreach (ref e; effects.fireforms.data) attached(e.target,orange,4,25);
        foreach (ref e; effects.etherealForms.data) attached(e.target,yellow,3*max(0.0f,min(1.0f,e.progress)),50);
        foreach (ref e; effects.airShields.data) attached(e.target,blue,2*max(0.0f,min(1.0f,e.scale)),25);
        // Run Away uses the same SpeedUp effect in SacEngine.
        foreach (ref e; effects.speedUps.data) attached(e.creature,green,3,25);
        foreach (ref e; effects.healingAuras.data) attached(e.target,yellow,4*max(0.0f,min(1.0f,e.scale)),50);
        foreach (ref e; effects.heals.data) attached(e.creature,yellow,3,25);
        foreach (ref e; effects.demonicRifts.data) emit(e.position+lift,purple,5*max(0.0f,min(1.0f,e.heightScale)),40,scene,st);
        // Heal has a separate casting phase before the active healing effect.
        foreach (ref e; effects.healCastings.data) attached(e.creature,yellow,3,25);
        // Breath of Life is the explicit ranged revival effect. No Animate Dead light.
        revivalTargets.clear();
        foreach (ref e; effects.breathOfLifes.data) {
            attached(e.creature,yellow,3,25);
            if (e.target.id !in revivalTargets) {
                attached(e.target.id,yellow,3,25);
                revivalTargets.insert(e.target.id);
            }
        }
        animateDeadTargets.clear();
        foreach (ref e; effects.animateDeads.data) animateDeadTargets.insert(e.creature.id);
        excludedCasters.clear();
        foreach (ref e; effects.animateDeadCastings.data) excludedCasters.insert(e.manaDrain.wizard);
        foreach (ref e; effects.lightningCastings.data) excludedCasters.insert(e.manaDrain.wizard);
        foreach (ref e; effects.chainLightningCastings.data) excludedCasters.insert(e.manaDrain.wizard);
        // Prefer the actual spell god when the casting record exposes it.
        castingGods.clear();
        foreach (ref e; effects.creatureCasts.data) castingGods[e.manaDrain.wizard] = e.spell.god;
        foreach (ref e; effects.structureCasts.data) castingGods[e.manaDrain.wizard] = e.god;
        foreach (ref e; effects.fireballCastings.data) castingGods[e.manaDrain.wizard] = God.pyro;
        foreach (ref e; effects.wrathCastings.data) castingGods[e.manaDrain.wizard] = God.pyro;
        foreach (ref e; effects.healCastings.data) castingGods[e.manaDrain.wizard] = God.persephone;
        foreach (ref e; effects.fireformCastings.data) castingGods[e.manaDrain.wizard] = e.spell.god;
        foreach (ref e; effects.etherealFormCastings.data) castingGods[e.manaDrain.wizard] = e.spell.god;
        foreach (ref e; effects.airShieldCastings.data) castingGods[e.manaDrain.wizard] = e.airShield.spell.god;
        foreach (ref e; effects.demonicRiftCastings.data) castingGods[e.manaDrain.wizard] = e.demonicRift.spell.god;
        foreach (ref e; effects.healingAuraCastings.data) castingGods[e.manaDrain.wizard] = e.spell.god;
        Vector3f castingColor(God god) {
            switch (god) with (God) {
                case pyro: return orange;
                case james: return yellow;
                case stratos: return white;
                case charnel: return purple;
                default: return green;
            }
        }

        // Ghost and resurrection states can exist in either render bucket.
        void creatures(T)(ref T groups) {
            foreach (ref g; groups.data) foreach (i; 0..g.length) {
                auto mode = g.creatureStates[i].mode;
                auto id = g.ids[i];
                if (scene.renderSide >= 0 && scene.renderSide < 32 && g.sides[i] != scene.renderSide &&
                    (mode.isGhost || g.creatureStatss[i].effects.stealth ||
                     (st.fogOfWar3d && !st.positionVisibleToSide(scene.renderSide,g.positions[i])))) continue;
                if (g.sacObject.isManahoar && mode.isAlive && g.creatureStatss[i].health > 0.0f) {
                    auto c = st.sides.manaColor(g.sides[i]);
                    emit(g.positions[i]+lift,Vector3f(c.r,c.g,c.b),2,18,scene,st);
                }
                if (g.sacObject.isWizard && mode.isCasting && id !in excludedCasters) {
                    auto god = id in castingGods;
                    auto actualGod = god ? *god : God.none;
                    if (actualGod == God.none) actualGod = st.getCurrentGod(id);
                    emit(g.positions[i]+lift,castingColor(actualGod),2,16,scene,st);
                }
                switch (mode) with (CreatureMode) {
                    case deadToGhost, idleGhost, movingGhost, ghostToIdle:
	                    emit(g.positions[i]+lift,blue,2,18,scene,st); break;
                    case reviving, fastReviving, convertReviving:
                        if (id !in animateDeadTargets && id !in revivalTargets)
	                        emit(g.positions[i]+lift,yellow,3,25,scene,st);
                        break;
                    default: break;
                }
            }
        }
        creatures(objects.movingObjects);
        creatures(st.obj.transparentObjects.movingObjects);

        // Preserve the strong red soul profile from the reference patch.
        foreach (ref soul; objects.souls.souls.data) {
	        auto color = soul.color(scene.renderSide,st);
            auto pos = soul.position + soul.scaling*Vector3f(0,0,1.25f*SacSoul!B.soulHeight);
            if (color == SoulColor.red) emit(pos,Vector3f(1,0,0),7,40,scene,st);
            else if (color == SoulColor.blue) emit(pos,blue,7,40,scene,st);
        }

        // Live buildings, not emitters. Match the original emitter anchor heights.
        foreach (i; 0..objects.buildings.length) {
            auto building = &objects.buildings[i];
            if (!building.componentIds.length ||
                (building.flags & (AdditionalBuildingFlags.inactive | Flags.destroyed))) continue;
            auto pos = (*building).position(st);
            if (st.fogOfWar3d && scene.renderSide >= 0 && scene.renderSide < 32 &&
                building.side != scene.renderSide && !st.positionExploredBySide(scene.renderSide,pos)) continue;
            auto id = cast(long)building.id;
            if ((*building).isManafount) {
                pos = st.staticObjectReadById!((ref o,j) => o.center(j), () => Vector3f.init)(building.componentIds[0]);
                emitPersistent([cast(long)BuildingLight.fountain,1L,id,0L,0L],pos+Vector3f(0,0,0.75f)+lift,blue,20,50);
            } else if ((*building).isManalith || (*building).isShrine || (*building).isAltar) {
                auto c = st.sides.manaColor(building.side);
                auto color = Vector3f(c.r,c.g,c.b);
                if ((*building).isManalith)
                    emitPersistent([cast(long)BuildingLight.manalith,1L,id,0L,0L],pos+Vector3f(0,0,15)+lift,color,20,50);
                else {
                    if ((*building).isEtherealAltar) pos.z += 95.0f;
                    emitPersistent([cast(long)BuildingLight.shrine,1L,id,0L,0L],pos+Vector3f(0,0,3)+lift,color,10,25);
                }
            }
        }

        // Only lightning casting particles remain eligible for particle lighting.
        // Limit particle lights to one per spatial cell and particle type.
        // This avoids hundreds of overlapping lights from a single cast.
        occupied.clear();
        // The state no longer stores the particles, only their emitters (blood
        // drops, the remaining stored particles, produce no light). Replay the
        // emitters like the renderer does to get the world positions of the
        // live particles at the current frame.
        static void particle(StateType)(SacParticle!B p,Vector3f pos,float size,float alpha,B.Mesh mesh,int sideFilter, DynamicLighting* self, SceneType scene, StateType st) {
            Vector3f color;
            float energy, radius;
            switch (p.type) with (ParticleType) {
                case lightningCasting, chainLightningCasting: color=white; energy=3; radius=20; break;
                default: return;
            }
            if (self.used >= maxLights) return;
            if (sideFilter != int.min && sideFilter != scene.renderSide) return;
            if (self.distanceFade(pos+lift, radius, scene) <= 0.0f) return;
            long[4] key=[cast(long)p.type,cast(long)(pos.x/5),cast(long)(pos.y/5),cast(long)(pos.z/5)];
            if (key in self.occupied) return;
            if (alpha<=0) return;
            self.occupied.insert(key);
            float actualEnergy = energy*min(1.0f,alpha*4);
            self.emit(pos+lift,color,actualEnergy,radius,scene,st);
        }
        // The emitters are stored by particle group, so only the groups of the
        // particle types that give light are replayed.
        static foreach (type; [ParticleType.lightningCasting, ParticleType.chainLightningCasting]) {{
            auto group = particleGroup(type);
            if (group < objects.particleEmitters.groups.length)
                foreach (ref emitter; objects.particleEmitters.groups[group].data)
                    emitter.eachEmitterParticle!particle(st,&this,scene,st);
        }}

        // Live sources always get first claim on the pool. A fading light
        // is discarded if it is too far away or the live lights fill the pool.
        foreach (ref record; history[0 .. historyCount]) {
            if (record.matched || used >= maxLights || nextCount >= maxLights) continue;
            if (!record.fading) {
                record.fading = true;
                record.lastSeen = now;
            }
            float level = record.level*max(0.0f,1.0f-secondsSince(record.lastSeen)/record.duration);
            if (emit(record.pos,record.color,record.energy*smooth(level),record.radius,scene,st))
                nextHistory[nextCount++] = record;
        }
        history[0 .. nextCount] = nextHistory[0 .. nextCount];
        historyCount = nextCount;
    }
}
