// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

// port of the original ai (excavated from thaum.exe) for ai-controlled sides.
module bots.shiny;

import state, sacobject, sacspell, spells, sids, nttData, stats, util;
import dlib.math, dlib.math.portable;
import std.typecons: Tuple, tuple;
import std.algorithm: among;
import std.conv:to;
private alias SpellType=sacspell.SpellType; // (conflicts with spells.SpellType)

enum SideType{
	neutral,
	human,
	shinyBot,
}

// MSVCRT _ftol: round to nearest, ties to even
int ftol(T)(T x){
	T f=floor(x),d=x-f;
	auto i=cast(int)f;
	if(d>0.5) i+=1;
	else if(d==0.5) i+=(i&1);
	return i;
}

// MSVCRT rand()
struct ShinyRand{
	uint state=1;
	int rand(){
		state=state*214013u+2531011u;
		return (state>>16)&0x7fff;
	}
}

// rater accumulator (thaum 0x28 bytes)
struct RaterAcc{
	int key=0;            // creature tag for by-tag accs
	int ownerNode=0;      // owning node
	float[5] rating=0;    // melee, abilities, health (melee res), health (ranged res), speed
	float cachedRate=0.0f;
}
enum rateMelee=0, rateAbility=1, rateHealthMelee=2, rateHealthRanged=3, rateSpeed=4;

enum NodeKind{ none, wiz, cre, maho, t4o, str }

// rater2 rating functions (thaum addresses; f48cbd0 is retail-only)
enum RatingFn{ none, f489700, f489780, f489860, f489a20, f489af0, f489ae0, f489bc0, f489c40, f489d70, f489e70, f48cbd0 }

struct SpellAcc(B){           // rater2 spell accumulator
	SacSpell!B spell;         // spinfo
	RatingFn ratingFn;
}

struct SummonEntry(B){        // wizard summon list entry
	char[4] tag;
	RaterAcc acc;
	SacSpell!B spell;         // creature spell
}

struct CastEntry(B){          // wizard cast queue entry
	ubyte flag=0;             // bit0: forced
	float score=0.0f;
	int target=0;             // target node
	int obj=0;                // node to walk to / cast at
	float range=0.0f;
	SacSpell!B provider;      // spell record
}

struct AINode(B){
	NodeKind kind=NodeKind.none;
	int id=0;                 // entity id (moving object or building)
	uint flags=0;             // relationship/class flags
	uint status=0;            // status flags
	int age=0;                // ticks tracked
	int ageSeen=0;            // age at last seen
	Vector3f curPos=Vector3f(0.0f,0.0f,0.0f);     // thaum zero-inits (C++), D defaults to NaN
	Vector3f extrapPos=Vector3f(0.0f,0.0f,0.0f);
	Vector3f prevPos=Vector3f(0.0f,0.0f,0.0f);
	Vector3f velocity=Vector3f(0.0f,0.0f,0.0f);
	// intrusive list links (node indices, 0 = none)
	int idxP=0, idxN=0;       // all-nodes index list
	int catP=0, catN=0;       // slot0 category sublist
	int famP=0, famN=0;       // slot1/2/3 family sublist (only one per node)
	int grpP=0, grpN=0;       // slot4-group membership / scratch
	int group=0;              // slot4-group back-pointer
	int cgrpP=0, cgrpN=0;     // slot5-group membership / scratch (cre)
	int cgroup=0;             // slot5-group back-pointer (cre)
	int recP=0, recN=0;       // record membership / temp list
	int record=0;             // owning claim record
	// ratings
	RaterAcc acc;             // t4o/maho/wiz/str
	float cachedRate=0.0f;    // t4o/maho/wiz (+0x7c), str (+0x6c)
	float minManaCost=0.0f;   // t4o/wiz (+0x60)
	int rerateTick=0;         // t4o-style (+0x74)
	int rerateTick2=0;        // str (+0x64)
	int statusTick=0;         // str (+0x68), maho (+0xa8)
	// wizard extras
	float threat=0.0f;        // threat ratio (+0x6c)
	int threatTick=0;         // +0xac
	int nextReplan=0;         // +0xb0
	int nextOrderReissue=0;   // +0xb4
	int soulsSnapTick=0;      // +0xb8
	int manaSnap=0;           // +0xbc
	int soulsSnap=0;          // +0xc0
	uint spellDirty=0;        // +0xc4
	SacSpell!B manahoarSpell; // +0xc8 ('oham')
	SacSpell!B shrineSpell;   // +0xcc
	SacSpell!B convertSpell;  // +0xd0 ('sacc')
	SacSpell!B desecrateSpell;// +0xd4 ('sacu')
	Array!(SummonEntry!B) summons;   // summon list (+0xdc)
	Array!(SpellAcc!B) spellAccs;    // spell accs (+0x88, t4o/wiz)
	Array!(CastEntry!B) castQueue;   // cast queue (+0xf4, sorted)
	// last issued order (thaum caches the ntt's live order for 0x4878c0)
	int ordState=0;
	int ordTarget=0;          // target node index
	Vector3f ordPos=Vector3f(0.0f,0.0f,0.0f);
}

struct AIGroup{
	int prio=0;               // K value {1,2,0,4}
	uint statusOR=0;
	Vector3f center=Vector3f(0.0f,0.0f,0.0f); // thaum zero-inits (C++), D defaults to NaN
	Vector3f predicted=Vector3f(0.0f,0.0f,0.0f);
	Vector3f prevCenter=Vector3f(0.0f,0.0f,0.0f);
	Vector3f avgVel=Vector3f(0.0f,0.0f,0.0f);
	Vector3f stddev=Vector3f(0.0f,0.0f,0.0f);
	int count=0;
	int memberHead=0, memberTail=0; // node links (grpP/grpN or cgrpP/cgrpN)
	// slot4 aggregates
	RaterAcc acc;
	int manaSum=0;
	int maxManaSum=0;
	int healthSum=0;
	int healthSum2=0;
	int readyCount=0;
	int soulsSum=0;
	int number=0;
	// list links
	int gP=0, gN=0;
	int freeN=0;
}

struct AIRecord(B){
	float score=0.0f;
	int target=0;             // target node
	int leader=0;             // leader node
	uint flags=0;             // bit1: proximity trigger
	uint reqStatus=0;         // required-status mask (1/3/9)
	Vector3f anchor=Vector3f(0.0f,0.0f,0.0f); // target pos snapshot; thaum zero-inits (C++), D defaults to NaN
	RaterAcc targetAcc;
	// embedded member list
	int memberHead=0, memberTail=0; // node links recP/recN
	int count=0;
	uint statusOR=0;
	Vector3f center=Vector3f(0.0f,0.0f,0.0f);
	Vector3f predicted=Vector3f(0.0f,0.0f,0.0f);
	Vector3f prevCenter=Vector3f(0.0f,0.0f,0.0f);
	Vector3f velAcc=Vector3f(0.0f,0.0f,0.0f);
	Vector3f stddev=Vector3f(0.0f,0.0f,0.0f);
	RaterAcc membersAcc;
	// task list links (claimed and free lists share them, like thaum's +0xb0/+0xb4)
	int claimedP=0, claimedN=0;
}

enum TaskKind{ idle=0, guard=1, capture=2 }
struct AITask(B){
	int kind=0;
	float priority=0.0f;
	int freeHead=0, freeTail=0;
	int claimedHead=0, claimedTail=0;
}

struct StanceRec{
	uint[11] u;               // thaum dword view (int/float type-punned)
	RaterAcc acc;
}
int si(ref StanceRec r,int i){ return cast(int)r.u[i]; }
float sf(ref StanceRec r,int i){ return *cast(float*)&r.u[i]; }
void setI(ref StanceRec r,int i,int v){ r.u[i]=cast(uint)v; }
void setF(ref StanceRec r,int i,float v){ r.u[i]=*cast(uint*)&v; }

// rater1: exact fpu-order formulas (double stands in for the 80-bit fpu stack)
private enum double kMilli=0.001;     // 0x4bb7a0
private enum double kInvFly=1.0/980;  // 0x4bcde0
private enum double kAbi=0.04;        // 0x4bcdd8

void clear(ref RaterAcc acc){
	acc.rating[]=0;
	acc.cachedRate=0.0f;
}
// network determinism: invalid float divisions (0.0/0.0, inf/inf) produce a NaN whose bit pattern
// depends on the architecture (x86 0xffc00000, arm 0x7fc00000) and desynchs network games.
// safediv canonicalizes a NaN result to the portable float.init/double.init pattern;
// every non-NaN result (including infinities) is bit-identical to a plain division.
float safediv(float a,float b){
	auto r=a/b;
	return r!=r?float.init:r;
}
double safediv(double a,double b){
	auto r=a/b;
	return r!=r?double.init:r;
}
void combine(ref RaterAcc a,float wA,ref RaterAcc b,float wB){ // 0x4891e0
	foreach(i;0..5) a.rating[i]=cast(float)(cast(double)wB*b.rating[i]+cast(double)wA*a.rating[i]);
}
void divide(ref RaterAcc acc,float w){ // elements 0..3 only
	if(w==0.0f) return;
	foreach(i;0..4) acc.rating[i]=cast(float)safediv(cast(double)acc.rating[i],cast(double)w);
}
float rate(ref RaterAcc acc){ // 0x488a60
	double r=(cast(double)acc.rating[3]+acc.rating[2])*0.5f;
	double s=cast(double)acc.rating[1]+acc.rating[0];
	r+=s+s;
	acc.cachedRate=cast(float)r;
	return acc.cachedRate;
}
float rateWithBase(ref RaterAcc a,ref RaterAcc b){ // 0x4889e0
	static double pos(double x){ return x>0.0?x:0.0; }
	double r=pos(cast(double)a.rating[0]-0.1*b.rating[2])+pos(cast(double)a.rating[1]-0.1*b.rating[3]);
	double t=pos(cast(double)b.rating[1]-0.1*a.rating[3])+pos(cast(double)b.rating[0]-0.1*a.rating[2]);
	r=r-t+cast(double)(a.rating[4]-b.rating[4])*10.0f;
	return cast(float)r;
}

// creature type stats as thaum's crinfo record sees them (file words)
struct TypeStats{
	int unk10,unk11,run,fly,health,regen,drain,rangedAcc,meleeRes,dRangedRes;
	int meleeStrength,mana;
}
// thaum's wizd loader forces these defaults over the file values
enum wizardTypeStats=TypeStats(1250,1250,1000,0,1500,1000,0,0,1000,1000,120,1000);
TypeStats typeStats(immutable(Cre8)* c,immutable(Wizd)* w){
	if(c) return TypeStats(c.meleeAccuracy,c.meleeEvasion,c.runningSpeed,c.flyingSpeed,c.health,c.regeneration,c.drain,c.rangedAccuracy,c.meleeResistance,c.directRangedResistance,c.meleeStrength,c.mana);
	return wizardTypeStats;
}
TypeStats typeStats(B)(SacObject!B so){ return typeStats(so.cre8,so.wizd); }

// ability helper 0x489160 (no flag filter inside)
void abilityAcc(ref RaterAcc acc,immutable(Spel)* spel,double unk10f,double rangedAccf,double manaf,double flyf){
	double t1=unk10f*kMilli*spel.amount2;
	double k=rangedAccf*(flyf!=0.0f?kInvFly:kMilli)*spel.range;
	double f=manaf>cast(double)spel.manaCost?safediv(cast(double)spel.manaCost,manaf):1.0f;
	acc.rating[1]=cast(float)(acc.rating[1]+t1*(k*(1.0-f))*kAbi);
}

// shared ratings 0,2,3,4 (tail of 0x488de0)
void fillStats(ref RaterAcc acc,TypeStats ts){
	acc.rating[0]=cast(float)(cast(double)ts.meleeStrength*(ts.unk10*kMilli));
	float unk11K=cast(float)(ts.unk11*kMilli);
	double p1=cast(double)unk11K*ts.health*((ts.regen+2.0*ts.drain)*kMilli);
	float p1f=cast(float)p1;
	double r2=safediv(1000.0,ts.meleeRes==0?1.0:cast(double)ts.meleeRes)*p1f;
	if(ts.fly>0) r2*=4.0;
	acc.rating[2]=cast(float)r2;
	acc.rating[3]=cast(float)(safediv(1000.0,ts.dRangedRes==0?1.0:cast(double)ts.dRangedRes)*p1f);
	float runF=ts.run, flyF=ts.fly;
	acc.rating[4]=cast(float)(cast(double)(runF<flyF?flyF:runF)*kMilli);
}

// by-tag fill 0x488de0: type mana, unfiltered ability loop over record+0x5c[8]
void fillByTag(B)(ref RaterAcc acc,char[4] tag,immutable(Cre8)* c8,immutable(Wizd)* wz){
	acc.clear();
	acc.key=cast(ubyte)tag[0]|cast(ubyte)tag[1]<<8|cast(ubyte)tag[2]<<16|cast(ubyte)tag[3]<<24;
	auto ts=typeStats(c8,wz);
	fillStats(acc,ts);
	acc.rating[1]=0.0f;
	auto rec=c8?cast(immutable(uint)*)c8:cast(immutable(uint)*)wz;
	foreach(i;0..8){
		if(rec[0x17+i]==0) continue;
		auto atag=*cast(immutable(char[4])*)&rec[0x17+i];
		if(auto ps=atag in SacSpell!B.spells)
			if(auto spel=(*ps).spel)
				abilityAcc(acc,spel,ts.unk10,ts.rangedAcc,ts.mana,ts.fly);
	}
}

// instance fill 0x488ab0: current mana, filtered ability loop, wizard spellbook loop
// (thaum reads live-mutated instance stat words; we read the base type words)
void fillFromObject(B)(ref RaterAcc acc,SacObject!B so,int curMana,Spellbook!B* spellbook){
	acc.clear();
	auto ts=typeStats!B(so);
	fillStats(acc,ts);
	acc.rating[1]=0.0f;
	float manaF=curMana;
	foreach(ab;so.abilities){
		if(ab is null) continue;
		auto spel=ab.spel;
		if(!spel) continue;
		if(ab.type!=SpellType.spell) continue;
		if(!(cast(uint)spel.flags1&0x4000)) continue;
		if((spel.flags&SpelFlags.targetCreatures)==0) continue;
		abilityAcc(acc,spel,ts.unk10,ts.rangedAcc,manaF,ts.fly);
	}
	if(spellbook) foreach(ref info;spellbook.spells.data){
		auto s=info.spell;
		if(s.type!=SpellType.spell||!s.spel) continue;
		auto spel=s.spel;
		if(!(cast(uint)spel.flags1&0xfc00)) continue;
		double t=cast(double)spel.amount2*spel.range;
		double f=manaF>cast(double)spel.manaCost?safediv(cast(float)spel.manaCost,manaF):1.0f;
		t*=(1.0-f);
		t*=kAbi;
		acc.rating[1]=cast(float)(acc.rating[1]+t);
	}
}

// lookup a creature/wizard record by tag without creating anything
bool findRecord(B)(char[4] tag,ref immutable(Cre8)* c8,ref immutable(Wizd)* wz){
	if(auto ps=tag in SacSpell!B.spells) if(auto c=(*ps).cre8){ c8=c; return true; }
	if(auto pso=tag in SacObject!B.objects){
		if(auto c=(*pso).cre8){ c8=c; return true; }
		if(auto w=(*pso).wizd){ wz=w; return true; }
	}
	return false;
}

// rater2 spell-acc creation 0x4894d0
bool wantsSpellAcc(B)(SacSpell!B s){
	return s.type==SpellType.spell&&s.spel&&(cast(uint)s.spel.flags1&0xfc00)!=0;
}
// flags1 fallback chain of the rating function selection 0x489540
RatingFn ratingFnFlags(B)(SacSpell!B s){
	auto f1=cast(uint)s.spel.flags1;
	if(f1&0x4000) return (f1&0x40)&&s.spel.effectRange>0.0f?RatingFn.f489860:RatingFn.f489780;
	if(f1&0x8000) return RatingFn.f489af0;
	if(f1&0x800) return RatingFn.f489e70;
	if(f1&0x400) return RatingFn.f489bc0;
	return RatingFn.none;
}
// rating function selection 0x489540 (tag table ds:0x4cfa68, compares the SPEL name field s_spell+0x10)
RatingFn ratingFn(B)(SacSpell!B s){
	auto name=s.spel.name[];
	if(name=="taed") return RatingFn.f48cbd0; // retail-only table entry (retail 0x48cbd0); thaum.exe lacks it and falls to the flags1 chain
	if(name=="omna") return RatingFn.f489700;
	if(name=="ndrg") return RatingFn.f489a20;
	if(name=="laeh") return RatingFn.f489af0;
	if(name=="pups") return RatingFn.f489c40;
	if(name=="elet") return RatingFn.f489d70;
	if(name=="ccas") return RatingFn.f489ae0;
	return ratingFnFlags!B(s);
}

final class ShinyAI(B){
	bool initialized=false;
	int side=-1;
	uint config=0;
	int schedTime=0;
	uint forceFlags=0xf;
	uint handledFlags=0;
	uint contactedSides=0; // thaum side+0x50: first-contact mask per owner side (set once, never reset)
	int[6] nextRun=0;
	// nodes ([0] = dummy)
	Array!(AINode!B) nodes;
	int nodeFree=0;
	Array!int nodeById; // entity id -> node index, 0 = untracked (object ids are unique and never reused: ObjectManager.addObject); derived cache, excluded from serialization
	int lastWizComponent=-1; // wizard pathfinder component; a change arms the one-shot discovery scan (forceFlags 0x20)
	int idxHead=0, idxTail=0;
	int[4] catHead, catTail;
	int[4] fam1Head, fam1Tail;
	int[4] fam2Head, fam2Tail;
	int[4] fam3Head, fam3Tail;
	int[4] grp4Head, grp4Tail;
	int[4] grp5Head, grp5Tail;
	// group pools ([0] = dummy)
	Array!AIGroup groups4;
	int grp4Free=0;
	Array!AIGroup groups5;
	int grp5Free=0;
	// tasks in thaum list order: capture, guard, idle
	AITask!B[3] tasks;
	// claim records, one global pool ([0] = dummy); per-task free/claimed lists
	Array!(AIRecord!B) records;
	// stance + stats
	StanceRec[4] stanceRecs;
	float strengthRatio=0.0f;
	float aggression=1.0f;
	int enemyCount=0;
	RaterAcc acc1, acc2;
	bool acc1Valid=false, acc2Valid=false;
	int maxSoulsSeen=0;
	int neutralManafounts=0;
	int livingSides=0;
	int allianceTeams=0;
	// per-instance behavior switches: false = Sacrifice.exe (retail), true = thaum.exe (beta); --beta-patch-bots initializes all to true
	bool betaMinManaSacu=false;         // retail GetMinimumMana@AIWIZARDNODE 0x490ac0: 'sacu' gate on the queue-head boost (thaum 0x48df30 has none)
	bool betaManahoarRadius=false;      // mahoBrain seek radius: retail 0x48a8f0 3620.0 vs thaum 0x487ae0 256.0
	bool betaAttackCoeff=false;         // CheckAttack coeff: retail 0x4901a0 280.0 vs thaum 0x48d640 180.0
	bool betaCastBuildingThreshold=false; // castCachedInRange threat gate: retail 0x490850 0.9 vs thaum 0x48dce0 0.6
	bool betaWizardOrderScore=false;    // Order@AIWIZARDNODE score: retail 0x490b20 100/80 vs thaum 0x48df70 80/60
	bool betaDeathEvaluator=false;      // 'taed' spell evaluator: retail 0x48cbd0 (thaum has no table entry, flags1 fallback)
	bool betaSummonAccounting=false;    // summon accounting: retail counts own+ally manaliths, ready cap /2 (thaum own only, /4)
	bool betaManaSourceOwnOnly=false;   // GetManaSource 0x485a40: retail walks own+ally lists (thaum own only)
	bool betaPickupNeutralOnly=false;   // GetNearestPickup 0x485490: retail list sets {0,2}/{2,3} (thaum neutral slot 2 only)
	bool betaCaptureTerritory=false;    // CAPTURE::Replan 0x48dbf0: territorial gates 0x488d70 + own+ally f1/f2 divisor
	bool betaRateManasourceWeights=false; // RateManasource@AITASKCAPTURENODE (port nodeValueScore) lerp weights: thaum 0x48aee0 = 0.4/0.35 vs retail 0x48db30 = 0.45/0.3
	bool betaUnbuiltCaptureReq=false;   // CAPTURE::Replan status&0x8000 branch reqStatus: thaum 0x48b0a4 = 3 vs retail 0x48dcf7 = 2 (patch3 lets the wizard's status bit1 satisfy it)
	bool betaGuardWizardExclude=false;  // GUARD::Assign member mask: thaum 0x48ad24 = status&1 (wizard 0x2000e excluded) vs retail 0x48d994 = status&3 (wizard joins guard records; claim 0x48a740/0x48d490 makes it the record leader via status&0x20000, recordUpdate members follow leader.extrapPos)
	bool betaCaptureAggGuardians=false; // CAPTURE::Assign aggregate pass: thaum 0x48b50a aggregates ALL members; retail 0x48e21b skips guardian-bound ([ntt+0x5c8]!=0)
	bool betaStanceU4Quirk=false;       // stance u[4] (influenceGroups divisor 0x485cfa, summon gate 0x48d941): thaum reset 0x484700 never clears it (grows forever, influence decays to 0); retail reset 0x48677e clears to 1 per updateStance
	void setBetaPatchBots(bool beta){
		betaMinManaSacu=beta;
		betaManahoarRadius=beta;
		betaAttackCoeff=beta;
		betaCastBuildingThreshold=beta;
		betaWizardOrderScore=beta;
		betaDeathEvaluator=beta;
		betaSummonAccounting=beta;
		betaManaSourceOwnOnly=beta;
		betaPickupNeutralOnly=beta;
		betaCaptureTerritory=beta;
		betaRateManasourceWeights=beta;
		betaUnbuiltCaptureReq=beta;
		betaGuardWizardExclude=beta;
		betaCaptureAggGuardians=beta;
		betaStanceU4Quirk=beta;
	}
	// rater1 by-tag acc cache
	enum numTagAccs=96;
	RaterAcc[numTagAccs] tagAccs;
	char[4][numTagAccs] tagAccKeys;
	int tagAccCount=0;
	ShinyRand rng;
	void copyFrom(ShinyAI rhs){
		foreach(i,ref x;this.tupleof) x=rhs.tupleof[i];
	}
}

RaterAcc* tagAcc(B)(ref ShinyAI!B ai,char[4] tag){
	foreach(i;0..ai.tagAccCount)
		if(ai.tagAccKeys[i]==tag) return &ai.tagAccs[i];
	if(ai.tagAccCount>=ai.numTagAccs) return null;
	immutable(Cre8)* c8; immutable(Wizd)* wz;
	if(!findRecord!B(tag,c8,wz)) return null;
	auto acc=&ai.tagAccs[ai.tagAccCount];
	fillByTag!B(*acc,tag,c8,wz);
	ai.tagAccKeys[ai.tagAccCount]=tag;
	ai.tagAccCount++;
	return acc;
}

// ---- debug logging (temporary, for behavioral debugging) ----

private enum shinyAILog=false;
private void ailog(Args...)(Args args){ import std.stdio:writeln; writeln(args); }

void updateBots(B)(ObjectState!B state){
	foreach(side;0..cast(int)state.sid.sides.length){
		auto data=&state.sid.sides[side];
		if(data.sideType!=SideType.shinyBot) continue;
		if(data.state!=SideState.playing) continue;
		data.shinyAI.run(state,side,1);
	}
}

void run(B)(ref ShinyAI!B ai,ObjectState!B state,int side,int dTicks){
	import frameprof;
	if(!ai.initialized){
		frameprof.beginBotSlot();
		ai.setup(state,side);
		frameprof.endBotSlot(side,-1);
	}
	if(ai.config&8) return;
	ai.handledFlags=0;
	static immutable int[6] periods=[12,60,6,6,60,12];
	static immutable uint[6] masks=[0xe,0xf,1,1,0x3f,1]; // k=4 mask includes 0x20: an armed discovery scan runs updateReplan early
	static foreach(k;0..6){
		if(ai.nextRun[k]<=ai.schedTime){
			static if(shinyAILog) ailog("SLOT ",ai.side," t",ai.schedTime," k",k," scheduled forceFlags=",ai.forceFlags);
			frameprof.beginBotSlot();
			ai.scheduler!k(state,dTicks);
			frameprof.endBotSlot(side,k);
			ai.nextRun[k]+=periods[k];
		}else if(ai.forceFlags&masks[k]){
			static if(shinyAILog) ailog("SLOT ",ai.side," t",ai.schedTime," k",k," forced forceFlags=",ai.forceFlags);
			frameprof.beginBotSlot();
			ai.scheduler!k(state,dTicks);
			frameprof.endBotSlot(side,k);
		}
	}
	static if(shinyAILog) if(ai.handledFlags) ailog("SLOT ",ai.side," t",ai.schedTime," handled=",ai.handledFlags," force->",cast(int)(ai.forceFlags&~ai.handledFlags));
	ai.forceFlags&=~ai.handledFlags;
	ai.schedTime+=dTicks;
}

void scheduler(int k,B)(ref ShinyAI!B ai,ObjectState!B state,int dTicks){
	static if(k==0) ai.updateStatus(state,dTicks);
	else static if(k==1) ai.updateStance(state,dTicks);
	else static if(k==2) ai.updateNtts(state,dTicks);
	else static if(k==3) ai.updateGroups(state,dTicks);
	else static if(k==4) ai.updateReplan(state,dTicks);
	else static if(k==5) ai.updateTasks(state,dTicks);
}

// ---- thaum AI events (AI::NotifyEvent 0x483dd0, jump table 0x483ea4) ----
// thaum fires these on the object-owner's side AI ([side+0x54]) via SIDE::NotifyEvent 0x4724d0 / CREATURE::NotifyEvent 0x45ebc0;
// SIDE::NotifyEvent's side+0x4c bookkeeping for events 3..0xc is engine-side, not AI

enum BotEvent{ // thaum event ids
	firstContactAlly=1,   // SIDE::MarkAsVisible: ally-owned creature/wizard revealed (one-shot per owner side)
	firstContactEnemy=2,  // SIDE::MarkAsVisible: enemy-owned creature/wizard revealed (one-shot per owner side)
	death=6,              // FSMEnterState, 0x4000 rising (entered death or SDOC carry state); broadcast to all AIs
	revive=9,             // 0x4000 falling (revive/convert-revive/unghost/thrash drop)
	sacrifice=10,         // LANDITEM::Sacrifice (victim owned, != altar owner)
	enemyNearBuilding=11, // LANDITEM::Run + nearbywizardcallback 0x466d00 (enemy wizard within 100.0f)
	buildingDamaged=12,   // LANDITEM::Damage (damage>0)
	buildingDestroyed=13, // LANDITEM::Destroy (fully-built only)
	addedToSide=15,       // SIDE::AddToSide
	relationsChanged=16,  // side relations changed
	spellListUpdated=19,  // WIZARD::UpdateSpellLists (level up/down)
	sideChanged=20,       // sacengine extension: charm/rescue changed object.side (thaum has no event here; its SIDE bookkeeping covers it)
}

void notifyEvent(B)(ref ShinyAI!B ai,ObjectState!B state,NodeKind kind1,int id1,NodeKind kind2,int id2,int event){
	switch(event) with(BotEvent){
		case firstContactAlly,firstContactEnemy: ai.forceFlags|=3; break;
		case death: removeNodeByEnt(ai,state,kind2,id2); break;
		case revive: // broadcast to all AIs (thaum notifies the owner side only; foreign re-adds came from its seen-list walk, our ever-seen gate)
			if(entSide!B(state,kind2,id2)==ai.side||state.sid.lastSeenTick(ai.side,id2)>=0)
				addNode(ai,state,kind2,id2); // no-op if already tracked or untrackable
			ai.forceFlags|=3; // was |=7: bit 4 (scanOwn) is obsolete, the entity is added directly
			break;
		case sacrifice,enemyNearBuilding,buildingDamaged: ai.forceFlags|=1; break;
		case buildingDestroyed: ai.forceFlags|=3; break;
		case addedToSide:
			addNode(ai,state,kind1,id1); // direct add (was |=7: bit 4 prompted a full own-side rescan)
			ai.forceFlags|=3;
			break;
		case sideChanged:
			if(auto n=findNode(ai,kind1,id1)){
				if(liveRelation(ai,state,n)!=categoryFromFlags(ai.nodes[n].flags)){
					removeNode(ai,state,n);
					addNode(ai,state,kind1,id1); // re-add under the new relation (shouldTrack-gated)
				}
			}else if(entSide!B(state,kind1,id1)==ai.side||state.sid.lastSeenTick(ai.side,id1)>=0)
				addNode(ai,state,kind1,id1); // own acquisition, or foreign but ever-seen
			ai.forceFlags|=3;
			break;
		case relationsChanged: ai.forceFlags|=0x13; break;
		case spellListUpdated: if(auto n=findNode(ai,NodeKind.wiz,id1)) ai.nodes[n].spellDirty|=1; break;
		default: break; // 3,4,5,7,8,14,17,18: thaum nops (damage pings, wizard run)
	}
}

ShinyAI!B botFor(B)(ObjectState!B state,int side){
	if(!(0<=side&&side<state.sid.sides.length)) return null;
	auto data=&state.sid.sides[side];
	if(data.sideType!=SideType.shinyBot||data.state!=SideState.playing) return null;
	return data.shinyAI;
}
NodeKind botNodeKind(B)(ref MovingObject!B o){
	return o.isWizard?NodeKind.wiz:o.sacObject.isManahoar?NodeKind.maho:NodeKind.t4o;
}
void botEvent(B)(ObjectState!B state,int side,int event,NodeKind kind1=NodeKind.none,int id1=0,NodeKind kind2=NodeKind.none,int id2=0){
	if(auto ai=botFor!B(state,side)) notifyEvent(ai,state,kind1,id1,kind2,id2,event);
}

// ---- event call sites: state.d wires each thaum event source with a single call ----

void botDeath(B)(ObjectState!B state,ref MovingObject!B o){ // thaum FSMEnterState, 0x4000 rising (death/SDOC carry states): CREATURE::NotifyEvent event 6 to own side plus 0x453b20 (retail 0x4529e0) broadcast flags=0xf -> AI::DeleteNTT vt[0x10] (0x483ad0/0x4852d0) on EVERY side's AI
	foreach(side;0..cast(int)state.sid.sides.length)
		if(auto ai=botFor!B(state,side)) notifyEvent(ai,state,NodeKind.none,0,botNodeKind(o),o.id,BotEvent.death);
}
void botRevive(B)(ObjectState!B state,ref MovingObject!B o){ // thaum 0x4000 falling (revive/convert-revive/unghost); broadcast so ever-seen foreign AIs re-track without a scan
	foreach(side;0..cast(int)state.sid.sides.length)
		if(auto ai=botFor!B(state,side)) notifyEvent(ai,state,botNodeKind(o),o.id,botNodeKind(o),o.id,BotEvent.revive);
}
void botSideChanged(B)(ObjectState!B state,ref MovingObject!B o){ // charm/rescue: object.side changed (state.d wires the assignment sites)
	foreach(side;0..cast(int)state.sid.sides.length)
		if(auto ai=botFor!B(state,side)) notifyEvent(ai,state,botNodeKind(o),o.id,NodeKind.none,0,BotEvent.sideChanged);
}
void botSpawned(B)(ObjectState!B state,int id){ // thaum SIDE::AddToSide: MovingObject creation (souls excluded: thaum assigns soul ntts the neutral side record)
	if(id<=0) return;
	auto sideKind=state.movingObjectReadById!((ref cols,i)=>tuple(cols.sides[i],cols.sacObject.isWizard?NodeKind.wiz:cols.sacObject.isManahoar?NodeKind.maho:NodeKind.t4o),()=>tuple(-1,NodeKind.none))(id);
	if(sideKind[0]>=0) state.botEvent(sideKind[0],BotEvent.addedToSide,sideKind[1],id);
}
void botBuilt(B)(ObjectState!B state,int side,int id){ // thaum SIDE::AddToSide: building creation (wired in makeBuilding, after components are added)
	state.botEvent(side,BotEvent.addedToSide,NodeKind.str,id);
}
void botSoulSpawned(B)(ObjectState!B state,int id){ // soul creation (ObjectState.addObject funnel): discover tracks souls ungated (no vision tracking), so notify every AI directly
	foreach(side;0..cast(int)state.sid.sides.length)
		if(auto ai=botFor!B(state,side)) notifyEvent(ai,state,NodeKind.cre,id,NodeKind.cre,id,BotEvent.addedToSide);
}
void botDamaged(B)(ObjectState!B state,ref Building!B b,float actualDamage){ // thaum LANDITEM::Damage (cond: damage>0)
	if(actualDamage>0.0f) state.botEvent(b.side,BotEvent.buildingDamaged);
}
void botDestroyed(B)(ObjectState!B state,ref Building!B b){ // thaum LANDITEM::Destroy (thaum gates on fully-built +0x43c==1.0; sacengine buildings are never damageable mid-construction)
	state.botEvent(b.side,BotEvent.buildingDestroyed);
}
void botSacrificed(B)(ObjectState!B state,int side,int victimSide){ // thaum LANDITEM::Sacrifice (cond: victim owned, != altar owner)
	if(0<=victimSide&&victimSide!=side) state.botEvent(side,BotEvent.sacrifice);
}
void botSpellListUpdated(B)(ObjectState!B state,int side,int wizardId){ // thaum WIZARD::UpdateSpellLists (level up/down)
	state.botEvent(side,BotEvent.spellListUpdated,NodeKind.wiz,wizardId);
}
void botRelationsChanged(B)(ObjectState!B state,int side){ // thaum NETSetupSideTeam 0x4a56b7; thaum also fires from alliance triggers, which sacengine does not implement
	state.botEvent(side,BotEvent.relationsChanged);
}
void botFirstContact(B)(ObjectState!B state,int side,int id){ // thaum SIDE::MarkAsVisible 0x4723e0: one-shot AI wake per owner side (side+0x50, never reset); creature/wizard ntts only
	if(state.targetTypeFromId(id)!=TargetType.creature) return;
	auto ownerSide=state.objectById!(.side)(id,state);
	if(!(0<=ownerSide&&ownerSide<32)||ownerSide==side) return; // thaum own-side additionally requires ntt+0x234&0x2000 (unknown flag); own additions wake via BotEvent.addedToSide
	auto ai=botFor!B(state,side);
	if(ai is null) return;
	if(ai.contactedSides&(1u<<ownerSide)) return;
	ai.contactedSides|=1u<<ownerSide;
	final switch(state.sides.getStance(side,ownerSide)){
		case Stance.ally: notifyEvent(ai,state,NodeKind.none,0,NodeKind.none,0,BotEvent.firstContactAlly); break;
		case Stance.enemy: notifyEvent(ai,state,NodeKind.none,0,NodeKind.none,0,BotEvent.firstContactEnemy); break;
		case Stance.neutral: break; // thaum sets the bit without firing an event
	}
}
void botSeen(B)(ObjectState!B state,int side,int id,TargetType type){ // markAsVisibleImpl hook: a sighting adds the node directly (was discover's periodic ever-seen pickup)
	auto ai=botFor!B(state,side);
	if(ai is null) return;
	if(0<id&&id<ai.nodeById.length&&ai.nodeById[id]) return; // already tracked: O(1) early-out (hot path)
	switch(type) with(TargetType){
		case creature:
			auto sideKind=state.movingObjectReadById!((ref cols,i)=>tuple(cols.sides[i],cols.sacObject.isWizard?NodeKind.wiz:cols.sacObject.isManahoar?NodeKind.maho:NodeKind.t4o),()=>tuple(-1,NodeKind.none))(id);
			if(sideKind[0]<0||sideKind[0]==side) return; // own entities are tracked via spawn/side-change events
			addNode(ai,state,sideKind[1],id);
			break;
		case building:
			auto buildingId=state.staticObjectById!((ref o)=>o.buildingId,()=>0)(id); // marked ids are static components
			if(buildingId==0&&state.buildingById!((ref b)=>true,()=>false)(id)) buildingId=id; // defensive: building id directly
			if(buildingId==0) return;
			if(state.buildingById!((ref b)=>b.side,()=>-1)(buildingId)==side) return;
			addNode(ai,state,NodeKind.str,buildingId);
			break;
		default: break; // souls are not vision-tracked; added at spawn
	}
}
void botScanBuilding(B)(ref Building!B b,ObjectState!B state){ // thaum LANDITEM::Run 0x466d60 event-11 scan: enemy within 100.0f (3D)
	if((b.id+state.frame)%32!=0) return; // thaum's +0x4ec countdown fires every 32 ticks phased by creation tick, here phased by building id
	if(!(cast(uint)b.sacBuilding.flags&1)) return; // bldg data flags +0x47c&1
	if(!(0<=b.side&&b.side!=neutralSide&&b.health!=0.0f)) return; // owner wizard (+0x1c4); Run stops at Destroy
	// nearbywizardcallback 0x466d00: first enemy wizard (NTT::IsEnemy); EnumerateType 0x48fb80 walks list[1]+mask 1 = wizard ntts only (ntt types: 1=wiz, 2=soul, 4=creature, 0x10=building)
	auto position=state.staticObjectById!((ref obj)=>obj.position,()=>Vector3f.init)(b.componentIds[0]);
	enum range=100.0f;
	static bool isWizardFilter(T...)(ref CenterProximityEntry entry,ObjectState!B state){
		return entry.id&&state.movingObjectReadById!((ref cols,i)=>cols.sacObject.isWizard,()=>false)(entry.id);
	}
	if(state.proximity.closestEnemyInRange!isWizardFilter(b.side,position,100.0f,EnemyType.creature,state,float.infinity,state))
		state.botEvent(b.side,BotEvent.enemyNearBuilding);
	/+bool found=false;
	state.eachMoving!((ref MovingObject!B o,ObjectState!B state,Vector3f position,int side,bool* found){
		if(*found||!o.isWizard) return;
		if(state.sides.getStance(side,o.side)!=Stance.enemy&&state.sides.getStance(o.side,side)!=Stance.enemy) return; // thaum additionally counts ntt+0x234&0x2000 (provoked flag, no sacengine equivalent)
		if((o.position-position).lengthsqr<range*range) *found=true;
	})(state,position,b.side,&found);
	if(found) state.botEvent(b.side,BotEvent.enemyNearBuilding);+/
}

void setup(B)(ref ShinyAI!B ai,ObjectState!B state,int side){
	ai.initialized=true;
	ai.side=side;
	ai.schedTime=0;
	ai.forceFlags=0xf;
	ai.aggression=1.0f;
	ai.nodes.length=1; // dummy
	ai.groups4.length=1; // dummy
	ai.groups5.length=1; // dummy
	ai.records.length=1; // dummy
	foreach(i,kind;[TaskKind.capture,TaskKind.guard,TaskKind.idle])
		ai.tasks[i].kind=kind;
}

// ---- entity access (thaum ntt pointer, dispatched by node kind) ----

int entSide(B)(ObjectState!B state,NodeKind kind,int id){
	final switch(kind) with(NodeKind){
		case wiz,maho,t4o: return state.movingObjectReadById!((ref cols,i,state)=>cols.sides[i],()=>-1)(id,state);
		case cre: return state.soulById!((ref s,state)=>neutralSide,()=>-1)(id,state); // thaum assigns soul ntts the neutral side record at spawn (0x459df9: vtbl[0x58](ds:0x4d7c68)); the owner side lives only in the +0x434 touch-collect mask (pickupMask)
		case str: return state.buildingById!((ref b,state)=>b.side,()=>-1)(id,state);
		case none: return -1;
	}
}
Vector3f entPos(B)(ObjectState!B state,NodeKind kind,int id){
	final switch(kind) with(NodeKind){
		case wiz,maho,t4o: return state.movingObjectReadById!((ref cols,i,state)=>cols.positions[i],()=>Vector3f.init)(id,state);
		case cre: return state.soulById!((ref s,state)=>s.position,()=>Vector3f.init)(id,state);
		case str: return state.buildingById!((ref b,ObjectState!B state)=>b.position(state),()=>Vector3f.init)(id,state);
		case none: return Vector3f.init;
	}
}
bool entExists(B)(ObjectState!B state,NodeKind kind,int id){
	// no blanket isValidTarget: sacengine building ids fail it (ObjectType.building>=numMoving+numStatic); the per-kind lookups validate
	if(!id) return false;
	final switch(kind) with(NodeKind){
		case wiz,maho,t4o: return state.movingObjectReadById!((ref cols,i,state)=>true,()=>false)(id,state);
		case cre: return state.soulById!((ref s,state)=>true,()=>false)(id,state);
		case str: return state.buildingById!((ref b,state)=>true,()=>false)(id,state);
		case none: return false;
	}
}
// thaum targets the ntt directly; sacengine needs a TargetType-specific OrderTarget:
// buildings are targeted via their static component (cf. mouse picking), souls with the raised center (cf. state.d:13032)
OrderTarget entOrderTarget(B)(ObjectState!B state,NodeKind kind,int id){
	final switch(kind) with(NodeKind){
		case wiz,maho,t4o: return state.movingObjectById!((ref o)=>OrderTarget(TargetType.creature,o.id,o.center),()=>OrderTarget.init)(id);
		case str: return state.buildingById!((ref b,ObjectState!B state)=>b.componentIds.length?centerTarget(b.componentIds[0],state):OrderTarget.init,()=>OrderTarget.init)(id,state);
		case cre: return state.soulById!((ref s)=>OrderTarget(TargetType.soul,s.id,s.position+Vector3f(0.0f,0.0f,0.75f*SacSoul!B.soulHeight)),()=>OrderTarget.init)(id);
		case none: return OrderTarget.init;
	}
}
Vector3f entAimPos(B)(ObjectState!B state,NodeKind kind,int id){ // SIF_GetAimPos 0x44f330: live average of hitbox midpoints
	return entOrderTarget!B(state,kind,id).position;
}
// NTT::CanSee 0x48c050==1: target IsVisible (vtbl[0x10]; CREATURE 0x46c260 tests current-state flag 0x10000, base NTT always visible),
// then game3d land LOS between the live aim positions (NOT the cached curPos)
bool entCanSee(B)(ObjectState!B state,NodeKind kind,int id,Vector3f spos,Vector3f tpos){
	if(isNaN(spos.x)||isNaN(tpos.x)) return false; // entity gone (thaum always has a live ntt)
	if(kind==NodeKind.wiz||kind==NodeKind.maho||kind==NodeKind.t4o){
		auto visible=state.movingObjectReadById!((ref cols,i,state)=>cols.creatureStates[i].mode.isVisibleToAI&&!cols.creatureStatss[i].effects.stealth,()=>false)(id,state); // state-flag 0x10000 approximation
		if(!visible) return false;
	}
	if(!state.fogOfWar) return true;
	return state.terrainLineOfSight(spos,tpos);
}
// NTT::CanHit 0x48c160==4: no blocking ntt on the shot line (zone crawl between the live aim positions, terrain NOT checked)
bool entCanHit(B)(ObjectState!B state,int sid,Vector3f spos,int tid,Vector3f tpos){
	if(isNaN(spos.x)||isNaN(tpos.x)) return true; // entity gone (thaum always has a live ntt)
	static bool filter(ref ProximityEntry entry,int sid,int tid){ return entry.isObstacle&&entry.isProjectileObstacle&&entry.id!=sid&&entry.id!=tid; }
	return state.proximity.collideRay!filter(spos,tpos-spos,1.0f,sid,tid)[0]==float.infinity;
}
// thaum ntt.vtbl[14] (IsDead@CREATURE 0x46c0f0): [stateRec+0x30]&0x4000; states with 0x4000 in norm.FSMC/ofly.FSMC: all death states, vivify rise/float, all sac doctor carry states
bool entDead(B)(ObjectState!B state,int id){
	return state.movingObjectReadById!((ref cols,i,state)=>!!cols.creatureStates[i].mode.among(CreatureMode.dying,CreatureMode.dead,CreatureMode.deadToGhost,CreatureMode.dissolving,CreatureMode.reviving,CreatureMode.fastReviving,CreatureMode.convertReviving,CreatureMode.thrashing),()=>false)(id,state);
}
// CREATURE::IsRespawning entity-side: [stateRec+0x30]&0x40000
bool entGhost(B)(ObjectState!B state,int id){
	return state.movingObjectReadById!((ref cols,i,state)=>!!cols.creatureStates[i].mode.among(CreatureMode.idleGhost,CreatureMode.movingGhost),()=>false)(id,state);
}

// thaum relation 0x486c60: 0=own, 1=ally, 2=neutral, 3=enemy
int relation(B)(ObjectState!B state,int mySide,int entSide){
	if(entSide<0) return 2; // entity gone between scan and setup (thaum always has a live ntt)
	if(entSide==mySide) return 0;
	if(state.sides.getStance(mySide,entSide)==Stance.ally||state.sides.getStance(entSide,mySide)==Stance.ally) return 1;
	if(state.sides.getStance(mySide,entSide)==Stance.enemy||state.sides.getStance(entSide,mySide)==Stance.enemy) return 3;
	return 2;
}
enum uint[4] relationFlag=[1,2,0,4];
int categoryFromFlags(uint flags){ // 0x486c30
	if(flags&1) return 0;
	if(flags&2) return 1;
	return ((flags&4)|8)>>2;
}

// 0x487cd0
bool shouldTrack(B)(ref ShinyAI!B ai,ObjectState!B state,NodeKind kind,int id){
	if(auto wiz=state.getWizardForSide(ai.side)){
		auto wizPos=state.movingObjectReadById!((ref cols,i,state)=>cols.positions[i],()=>Vector3f.init)(wiz.id,state);
		// thaum sameRegion 0x470700; closest match is pathfinder component equality
		auto ra=state.pathFinder.getComponentId(entPos!B(state,kind,id),state);
		if(ra<0) return false;
		auto rb=state.pathFinder.getComponentId(wizPos,state);
		if(rb<0||ra!=rb) return false;
	}
	final switch(kind) with(NodeKind){
		// thaum rejects sub-components of multi-component structures (ntt+0x440=primary component, set by the map loader); sacengine folds those into one Building, so no case remains: fount-placed buildings keep ntt+0x440==0 in thaum and are tracked
		case str: return state.buildingById!((ref b,state)=>(cast(uint)b.sacBuilding.flags&0xc17)!=0,()=>false)(id,state);
		// 0x487cd0: wizard gate is IsDead (vtbl[0x38]=0x46c0f0, state flags&0x4000) only; ghosts (0x40000) pass here and are dropped by discover phase-2 (0x484c22)
		case wiz: return !entDead!B(state,id);
		case t4o,maho: return !entDead!B(state,id);
		case cre: return true;
		case none: return false;
	}
}

// ---- intrusive list ops (all per-category, k = categoryFromFlags) ----

void idxAppend(B)(ref ShinyAI!B ai,int n){ // all-nodes tail-append
	auto node=&ai.nodes[n];
	node.idxN=0;
	if(ai.idxTail) ai.nodes[ai.idxTail].idxN=n; else ai.idxHead=n;
	node.idxP=ai.idxTail;
	ai.idxTail=n;
}
void idxUnlink(B)(ref ShinyAI!B ai,int n){
	auto node=&ai.nodes[n];
	if(node.idxP) ai.nodes[node.idxP].idxN=node.idxN; else ai.idxHead=node.idxN;
	if(node.idxN) ai.nodes[node.idxN].idxP=node.idxP; else ai.idxTail=node.idxP;
	node.idxN=node.idxP=0;
}
void catAppend(B)(ref ShinyAI!B ai,int n){ // 0x4831a0
	auto k=categoryFromFlags(ai.nodes[n].flags);
	auto node=&ai.nodes[n];
	node.catN=0;
	if(ai.catTail[k]) ai.nodes[ai.catTail[k]].catN=n; else ai.catHead[k]=n;
	node.catP=ai.catTail[k];
	ai.catTail[k]=n;
}
void catUnlink(B)(ref ShinyAI!B ai,int n){ // 0x4831f0 (recomputes k from current flags)
	auto k=categoryFromFlags(ai.nodes[n].flags);
	auto node=&ai.nodes[n];
	if(node.catP) ai.nodes[node.catP].catN=node.catN; else ai.catHead[k]=node.catN;
	if(node.catN) ai.nodes[node.catN].catP=node.catP; else ai.catTail[k]=node.catP;
	node.catN=node.catP=0;
}
void famAppend(B)(ref ShinyAI!B ai,ref int[4] heads,ref int[4] tails,int n){ // 0x483250/0x483320/0x4833d0
	auto k=categoryFromFlags(ai.nodes[n].flags);
	auto node=&ai.nodes[n];
	node.famN=0;
	if(tails[k]) ai.nodes[tails[k]].famN=n; else heads[k]=n;
	node.famP=tails[k];
	tails[k]=n;
}
void famUnlink(B)(ref ShinyAI!B ai,ref int[4] heads,ref int[4] tails,int n){ // 0x4832a0/0x483370/0x483420
	auto k=categoryFromFlags(ai.nodes[n].flags);
	auto node=&ai.nodes[n];
	if(node.famP) ai.nodes[node.famP].famN=node.famN; else heads[k]=node.famN;
	if(node.famN) ai.nodes[node.famN].famP=node.famP; else tails[k]=node.famP;
	node.famN=node.famP=0;
}

// ---- node pool ----

int allocNode(B)(ref ShinyAI!B ai){
	if(ai.nodeFree){
		auto n=ai.nodeFree;
		ai.nodeFree=ai.nodes[n].idxN;
		auto node=&ai.nodes[n];
		auto summons=node.summons, spellAccs=node.spellAccs, castQueue=node.castQueue;
		*node=AINode!B.init;
		node.summons=summons; node.spellAccs=spellAccs; node.castQueue=castQueue;
		return n;
	}
	ai.nodes~=AINode!B.init;
	return cast(int)ai.nodes.length-1;
}
void freeNode(B)(ref ShinyAI!B ai,int n){
	auto node=&ai.nodes[n];
	node.summons.length=0; node.spellAccs.length=0; node.castQueue.length=0;
	node.idxN=ai.nodeFree; ai.nodeFree=n;
}
int findNode(B)(ref ShinyAI!B ai,NodeKind kind,int id){ // 0x483160; O(1) via the flat id->node map (object ids are unique and never reused)
	if(id<=0||id>=ai.nodeById.length) return 0;
	auto n=ai.nodeById[id];
	return n&&ai.nodes[n].kind==kind?n:0;
}
void rebuildNodeById(B)(ref ShinyAI!B ai){ // after deserialization (the map is excluded from the stream)
	ai.nodeById.length=0;
	for(int n=ai.idxHead;n;n=ai.nodes[n].idxN){
		auto id=ai.nodes[n].id;
		if(id<=0) continue;
		if(ai.nodeById.length<=id) ai.nodeById.length=id+1;
		ai.nodeById[id]=n;
	}
}

// ---- node setup (thaum vtbl[2]) ----

void setupBase(B)(ref ShinyAI!B ai,ObjectState!B state,int n,NodeKind kind,int id,uint flags){ // 0x4869b0
	auto node=&ai.nodes[n];
	node.kind=kind;
	node.id=id;
	node.flags=flags;
	node.status=0;
	node.age=0;
	node.ageSeen=0;
	node.flags|=relationFlag[relation!B(state,ai.side,entSide!B(state,kind,id))];
	auto p=entPos!B(state,kind,id);
	node.curPos=p;
	node.prevPos=p;
	node.extrapPos=p;
	node.velocity=Vector3f(0.0f,0.0f,0.0f);
}
void setupCre(B)(ref ShinyAI!B ai,ObjectState!B state,int n,int id,uint flags){ // 0x486f50
	setupBase(ai,state,n,NodeKind.cre,id,flags|0x8);
}
void fillNodeAcc(B)(ref ShinyAI!B ai,ObjectState!B state,AINode!B* node){ // rater1 getOrCreateAccForNode/fillFromObject 0x488ab0
	state.movingObjectReadById!((ref cols,i,ObjectState!B state){
		auto wiz=node.kind==NodeKind.wiz?state.getWizardForSide(cols.sides[i]):null;
		fillFromObject!B(node.acc,cols.sacObject,ftol(cols.creatureStatss[i].mana),wiz?&wiz.spellbook:null);
	},(){})(node.id,state);
}
void setupT4oBody(B)(ref ShinyAI!B ai,ObjectState!B state,int n,NodeKind kind,int id,uint flags){ // 0x487090
	setupBase(ai,state,n,kind,id,flags|0x10);
	auto node=&ai.nodes[n];
	node.flags|=0x40;
	state.movingObjectReadById!((ref cols,i,ObjectState!B state){
		auto so=cols.sacObject;
		int numAbil=0;
		foreach(ab;so.abilities) if(ab !is null) numAbil++;
		// thaum: base stat word[2] (aggressiveness; wizards have 1000) or ability count
		if(numAbil||(so.cre8?so.cre8.aggressiveness:1000)!=0) node.status|=1;
		// ntt+0xb24&0x200 -> status|=0x2000: no sacengine equivalent (documented gap)
		node.minManaCost=numAbil?cast(float)ftol(cols.creatureStatss[i].maxMana):0.0f; // thaum: float(ntt+0xb10)
		foreach(ab;so.abilities){
			if(ab is null) continue;
			auto spel=ab.spel;
			if(ab.type==SpellType.spell&&spel&&(cast(uint)spel.flags2&0x800000)&&wantsSpellAcc!B(ab))
				node.spellAccs~=SpellAcc!B(ab,ratingFn!B(ab));
			auto mc=cast(float)ab.manaCost; // 0x487191: min over ALL ability entries (gate-skip lands here)
			if(mc<node.minManaCost) node.minManaCost=mc;
		}
	},(){})(id,state);
	fillNodeAcc(ai,state,node);
}
void setupMaho(B)(ref ShinyAI!B ai,ObjectState!B state,int n,int id,uint flags){ // 0x4879f0
	setupBase(ai,state,n,NodeKind.maho,id,flags|0x10);
	auto node=&ai.nodes[n];
	node.flags|=0x40;
	fillNodeAcc(ai,state,node);
}
void setupWiz(B)(ref ShinyAI!B ai,ObjectState!B state,int n,int id,uint flags){ // 0x48c800
	setupT4oBody(ai,state,n,NodeKind.wiz,id,flags|0x100);
	auto node=&ai.nodes[n];
	node.status|=0x2000e;
	node.flags|=0x100;
	state.movingObjectReadById!((ref cols,i,state){ node.minManaCost=cast(float)(ftol(cols.creatureStatss[i].maxMana)/4); },(){})(id,state); // thaum 0x48c800: fild(ntt+0xb10)/4
	node.spellDirty=1;
	// own: thaum marks ntt+0xb24|=0x8000; no consumer in sacengine
}
void fillStrAcc(B)(AINode!B* node,ref Building!B b){ // 0x4888e0 (no clear; idempotent)
	if(cast(uint)b.sacBuilding.flags&0x80){
		node.acc.rating[2]=0.0f;
		node.acc.rating[3]=cast(float)(cast(double)b.sacBuilding.maxHealth*10.0);
	}
}
void setupStr(B)(ref ShinyAI!B ai,ObjectState!B state,int n,int id,uint flags){ // 0x486d70
	setupBase(ai,state,n,NodeKind.str,id,flags|0x20);
	auto node=&ai.nodes[n];
	state.buildingById!((ref b){
		fillStrAcc!B(node,b);
		if(cast(uint)b.sacBuilding.flags&1) node.flags|=0x300;
		if(cast(uint)b.sacBuilding.flags&0xc17) node.flags|=0x100;
		static if(shinyAILog) ailog("BLD ",ai.side," tag ",b.sacBuilding.tag[]," id ",id," bflags ",b.flags," base ",b.base," top ",b.top," mf ",b.sacBuilding.isManafount?1:0," altar ",b.sacBuilding.isAltar?1:0);
	},(){})(id);
}

// ---- add/remove ----

int addNode(B)(ref ShinyAI!B ai,ObjectState!B state,NodeKind kind,int id){ // 0x483480
	if(id<=0) return 0;
	if(auto n=findNode(ai,kind,id)) return n; // already tracked (O(1))
	if(!shouldTrack(ai,state,kind,id)) return 0;
	auto n=allocNode(ai);
	final switch(kind) with(NodeKind){
		case wiz: setupWiz(ai,state,n,id,0); break;
		case cre: setupCre(ai,state,n,id,0); break;
		case maho: setupMaho(ai,state,n,id,0); break;
		case t4o: setupT4oBody(ai,state,n,NodeKind.t4o,id,0); break;
		case str: setupStr(ai,state,n,id,0); break;
		case none: return 0;
	}
	if(ai.nodeById.length<=id) ai.nodeById.length=id+1;
	ai.nodeById[id]=n;
	final switch(kind) with(NodeKind){
		case wiz,maho,t4o: famAppend(ai,ai.fam1Head,ai.fam1Tail,n); break;
		case str: famAppend(ai,ai.fam2Head,ai.fam2Tail,n); break;
		case cre: famAppend(ai,ai.fam3Head,ai.fam3Tail,n); break;
		case none: break;
	}
	catAppend(ai,n);
	idxAppend(ai,n);
	updateNode(ai,state,n,0);
	ai.forceFlags|=1;
	return n;
}
void groupRemoveMember(B)(ref ShinyAI!B ai,int g,int n){ // slot4 group vtbl[4] 0x486800
	auto node=&ai.nodes[n];
	if(node.grpP==0&&node.grpN==0&&ai.groups4[g].memberHead!=n) return; // stale back-pointer guard (thaum unlinks blindly)
	auto grp=&ai.groups4[g];
	if(node.grpP) ai.nodes[node.grpP].grpN=node.grpN; else grp.memberHead=node.grpN;
	if(node.grpN) ai.nodes[node.grpN].grpP=node.grpP; else grp.memberTail=node.grpP;
	node.grpP=node.grpN=0;
	grp.count--;
}
void creGroupRemoveMember(B)(ref ShinyAI!B ai,int g,int n){ // slot5 group vtbl[4] 0x4864c0
	auto node=&ai.nodes[n];
	if(node.cgrpP==0&&node.cgrpN==0&&ai.groups5[g].memberHead!=n) return; // stale back-pointer guard
	auto grp=&ai.groups5[g];
	if(node.cgrpP) ai.nodes[node.cgrpP].cgrpN=node.cgrpN; else grp.memberHead=node.cgrpN;
	if(node.cgrpN) ai.nodes[node.cgrpN].cgrpP=node.cgrpP; else grp.memberTail=node.cgrpP;
	node.cgrpP=node.cgrpN=0;
	grp.count--;
}
void removeNode(B)(ref ShinyAI!B ai,ObjectState!B state,int n){ // 0x483970
	for(int m=ai.fam1Head[0];m;){ // node slot20 per own slot1 node (wiz cast-queue purge 0x48e2c0)
		auto nn=ai.nodes[m].famN;
		if(ai.nodes[m].kind==NodeKind.wiz){
			auto node=&ai.nodes[m];
			size_t i=0;
			while(i<node.castQueue.length){
				if(node.castQueue[i].target==n){
					for(size_t j=i;j+1<node.castQueue.length;j++) node.castQueue[j]=node.castQueue[j+1];
					node.castQueue.length=node.castQueue.length-1;
				}else i++;
			}
		}
		m=nn;
	}
	foreach(ref task; ai.tasks) taskReleaseRecordsTargeting(ai,task,n); // task vtbl[10] 0x48a540
	auto node=&ai.nodes[n];
	if(node.kind==NodeKind.wiz||node.kind==NodeKind.maho||node.kind==NodeKind.t4o){ // node slot13 != 0
		foreach(ref task; ai.tasks) taskRemoveRecordMember(ai,task,n); // task vtbl[11] 0x48a4e0
		famUnlink(ai,ai.fam1Head,ai.fam1Tail,n);
		if(node.group){ groupRemoveMember(ai,node.group,n); node.group=0; }
	}else if(node.kind==NodeKind.str){
		famUnlink(ai,ai.fam2Head,ai.fam2Tail,n);
	}else if(node.flags&8){
		famUnlink(ai,ai.fam3Head,ai.fam3Tail,n);
		if(node.cgroup){ creGroupRemoveMember(ai,node.cgroup,n); node.cgroup=0; }
	}
	catUnlink(ai,n);
	idxUnlink(ai,n);
	if(node.id>0&&node.id<ai.nodeById.length&&ai.nodeById[node.id]==n) ai.nodeById[node.id]=0;
	freeNode(ai,n);
}
void removeNodeByEnt(B)(ref ShinyAI!B ai,ObjectState!B state,NodeKind kind,int id){ // 0x483ad0
	if(auto n=findNode(ai,kind,id)){
		removeNode(ai,state,n);
		ai.forceFlags|=1;
	}
}

// ---- node update (thaum vtbl[0]) ----

void updateBase(B)(ref ShinyAI!B ai,ObjectState!B state,int n,int dt){ // 0x486b10
	auto node=&ai.nodes[n];
	if(!(node.flags&0x81)) return;
	node.age+=dt;
	auto p=entPos!B(state,node.kind,node.id);
	node.curPos=p;
	node.velocity=p-node.prevPos;
	if(dt!=0){
		node.velocity.x=safediv(node.velocity.x,cast(float)dt);
		node.velocity.y=safediv(node.velocity.y,cast(float)dt);
		node.velocity.z=safediv(node.velocity.z,cast(float)dt);
	}
	node.prevPos=p;
	node.extrapPos=p;
	node.extrapPos+=node.velocity;
}
void updateT4o(B)(ref ShinyAI!B ai,ObjectState!B state,int n,int dt){ // 0x4872e0
	updateBase(ai,state,n,dt);
	auto node=&ai.nodes[n];
	if(node.age>=node.rerateTick){
		node.rerateTick=node.age+0x10;
		fillNodeAcc(ai,state,node); // rerate 0x4871f0
		node.cachedRate=rate(node.acc);
	}
}
void updateMaho(B)(ref ShinyAI!B ai,ObjectState!B state,int n,int dt){ // 0x487a90
	updateT4o(ai,state,n,dt);
	auto node=&ai.nodes[n];
	if(node.age>=node.statusTick){
		node.statusTick=node.age+8;
		// thaum: tag-property 'anam' on the ntt; closest match is the ability-enabled predicate
		state.movingObjectReadById!((ref cols,i,state){
			if(manahoarAbilityEnabled(cols.creatureStates[i].mode)) node.status|=0x1000;
			else node.status&=~0x1000;
		},(){})(node.id,state);
	}
}
void updateWiz(B)(ref ShinyAI!B ai,ObjectState!B state,int n,int dt){ // 0x48dd70
	updateT4o(ai,state,n,dt);
	auto node=&ai.nodes[n];
	if(node.flags&1&&node.age>=node.threatTick){
		node.threatTick=node.age+8;
		node.threat=0.0f;
		RaterAcc acc0,acc1,acc3; // 0x485be0 influence scans at extrapPos (return values discarded by thaum)
		acc0.clear(); acc1.clear(); acc3.clear();
		influenceGroups(ai,state,0,node.extrapPos,10.0f,280.0f,&acc0);
		influenceGroups(ai,state,1,node.extrapPos,10.0f,280.0f,&acc1);
		influenceGroups(ai,state,3,node.extrapPos,10.0f,280.0f,&acc3);
		node.threat=rate(acc3);
		if(node.threat!=0.0f) node.threat=cast(float)safediv(cast(double)node.threat,cast(double)node.threat+rate(acc0)+rate(acc1));
	}
	if(node.spellDirty&1){
		wizSpellRebuild(ai,state,n);
		node.spellDirty&=~1;
	}
	if(node.age>=node.soulsSnapTick){
		node.soulsSnapTick=node.age+32;
		state.movingObjectReadById!((ref cols,i,ObjectState!B state){
			if(auto wiz=state.getWizardForSide(cols.sides[i])) node.soulsSnap=wiz.souls;
		},(){})(node.id,state);
	}
}
void updateStr(B)(ref ShinyAI!B ai,ObjectState!B state,int n,int dt){ // 0x486e10
	updateBase(ai,state,n,dt);
	auto node=&ai.nodes[n];
	if(node.age>=node.rerateTick2){
		node.rerateTick2=node.age+0x20;
		state.buildingById!((ref b){ fillStrAcc!B(node,b); },(){})(node.id);
		node.cachedRate=rate(node.acc);
	}
	if(node.age>=node.statusTick){
		node.statusTick=node.age+8;
		state.buildingById!((ref b){
			auto bfl=cast(uint)b.sacBuilding.flags;
			// ntt+0x440==0 always holds here: thaum sets +0x440 only on sub-component entities of multi-component structures (altar tops), which sacengine folds into one Building; the fount association is one-directional (fount ntt+0x474 = building on top, sacengine top/base)
			if(bfl&0x10){
				if(b.top==0) node.status|=0x8000; else node.status&=~0x8000;
			}
			// ntt+0x43c = construction progress, always 1.0f in sacengine (documented gap)
			if(b.top==0&&(bfl&0xc00)&&ftol(cast(double)b.sacBuilding.bldg.unknown1[3]*36408.88888888889)!=0)
				node.status|=0x1000;
			else node.status&=~0x1000;
			if(bfl&0x4000) node.status|=0x4000; else node.status&=~0x4000;
			if(bfl&2) node.status|=0x40000; else node.status&=~0x40000;
		},(){})(node.id);
	}
}
void updateNode(B)(ref ShinyAI!B ai,ObjectState!B state,int n,int dt){
	final switch(ai.nodes[n].kind) with(NodeKind){
		case wiz: updateWiz(ai,state,n,dt); break;
		case cre: updateBase(ai,state,n,dt); break;
		case maho: updateMaho(ai,state,n,dt); break;
		case t4o: updateT4o(ai,state,n,dt); break;
		case str: updateStr(ai,state,n,dt); break;
		case none: break;
	}
}

// ---- scheduler records ----

int liveRelation(B)(ref ShinyAI!B ai,ObjectState!B state,int n){ // 0x486c60
	auto node=&ai.nodes[n];
	return relation!B(state,ai.side,entSide!B(state,node.kind,node.id));
}

void updateStatus(B)(ref ShinyAI!B ai,ObjectState!B state,int dTicks){ // 0x484050
	// shouldTrack gates on the wizard's pathfinder component; a component change (teleport/respawn) arms a one-shot
	// discovery scan (0x20, consumed by discover) so out-of-region entities become trackable without a periodic scan
	int wizComponent=-1;
	if(auto wiz=state.getWizardForSide(ai.side))
		wizComponent=state.pathFinder.getComponentId(entPos!B(state,NodeKind.wiz,wiz.id),state);
	if(wizComponent!=ai.lastWizComponent){
		ai.lastWizComponent=wizComponent;
		ai.forceFlags|=0x20;
	}
	if(ai.forceFlags&0x10){ // recategorize: relations changed (thaum event 16, wired at setStance)
		foreach(k;1..4)
			for(int n=ai.catHead[k];n;){
				auto nn=ai.nodes[n].catN;
				if(liveRelation(ai,state,n)!=k){
					auto kind=ai.nodes[n].kind, id=ai.nodes[n].id;
					removeNode(ai,state,n);
					addNode(ai,state,kind,id); // re-add under the new relation (was: periodic scan pickup)
				}
				n=nn;
			}
		ai.handledFlags|=0x10;
	}
	if(ai.forceFlags&4){ // own-side scan (thaum side buckets 4,1,0x10 via 0x48f490, cb 0x484160): setup only, bit 4 is never re-armed (spawn/revive/side-change events add directly)
		scanOwn(ai,state);
		ai.handledFlags|=4;
	}
	if(ai.forceFlags&8){ // thaum: global spawn scan gated by config&0x10, but config is 0x10 at all three AI-creation call sites (0x404c66, 0x457e08, 0x4a25d5), so it runs once at setup (forceFlags=0xf; no event re-sets bit 8)
		scanGlobal(ai,state);
		ai.handledFlags|=8;
	}
	if(ai.forceFlags&2){ // stats 0x484540
		updateStats(ai,state);
		ai.handledFlags|=2;
	}
}
void scanOwn(B)(ref ShinyAI!B ai,ObjectState!B state){
	state.eachMoving!((ref MovingObject!B o,ObjectState!B state,ShinyAI!B ai){
		if(o.side!=ai.side) return;
		addNode(ai,state,o.isWizard?NodeKind.wiz:o.sacObject.isManahoar?NodeKind.maho:NodeKind.t4o,o.id);
	})(state,ai);
	state.eachBuilding!((ref Building!B b,ObjectState!B state,ShinyAI!B ai){
		if(b.side!=ai.side) return;
		addNode(ai,state,NodeKind.str,b.id);
	})(state,ai);
}
void scanGlobal(B)(ref ShinyAI!B ai,ObjectState!B state){ // thaum ForEachNTT(0x15, cb 0x484190): add-if-unknown all structures, wizards and creatures map-wide
	state.eachBuilding!((ref Building!B b,ObjectState!B state,ShinyAI!B ai){
		addNode(ai,state,NodeKind.str,b.id);
	})(state,ai);
	state.eachMoving!((ref MovingObject!B o,ObjectState!B state,ShinyAI!B ai){
		// thaum gates creatures on ntt+0x238&0x10 (0x4841a1), which is set at every creature spawn (0x459ce1): all creatures pass
		addNode(ai,state,o.isWizard?NodeKind.wiz:o.sacObject.isManahoar?NodeKind.maho:NodeKind.t4o,o.id);
	})(state,ai);
}
void updateStats(B)(ref ShinyAI!B ai,ObjectState!B state){ // 0x484540
	int soulsSeen=0;
	foreach(k;0..4){
		for(int n=ai.fam3Head[k];n;n=ai.nodes[n].famN) soulsSeen+=1; // souls
		for(int n=ai.fam1Head[k];n;n=ai.nodes[n].famN){ // soul pair, vtbl[21]
			auto node=&ai.nodes[n];
			if(node.kind==NodeKind.wiz) soulsSeen+=node.manaSnap+node.soulsSnap; // 0x48e390
			else soulsSeen+=state.movingObjectReadById!((ref cols,i,state)=>cols.creatureStatss[i].effects.carrying,()=>0)(node.id,state); // 0x4879a0
		}
	}
	if(soulsSeen>ai.maxSoulsSeen) ai.maxSoulsSeen=soulsSeen;
	ai.neutralManafounts=0;
	for(int n=ai.fam2Head[2];n;n=ai.nodes[n].famN)
		ai.neutralManafounts+=state.buildingById!((ref b,state)=>b.base==0&&(cast(uint)b.sacBuilding.flags&0x10)!=0,()=>false)(ai.nodes[n].id,state);
	// living sides + alliance teams; thaum walks its global side list, we approximate membership by assignment!=0
	ai.livingSides=0;
	uint[8] teamMasks=0;
	int n=0;
	foreach(i,ref side;state.sides){
		if(i==neutralSide||side.assignment==0) continue;
		ai.livingSides++;
		auto mask=1u<<i;
		bool covered=false;
		foreach(j;0..n) if(teamMasks[j]&mask){ covered=true; break; }
		if(covered) continue;
		if(n>=8) break; // thaum would overflow its fixed array; unreachable with <=8 sides
		teamMasks[n]|=mask;
		foreach(j,ref inner;state.sides){ // inner walk has no neutral skip
			if(inner.assignment==0) continue;
			auto imask=1u<<j;
			if((inner.allies&mask)||(side.allies&imask)||imask==mask) teamMasks[n]|=imask;
		}
		n++;
	}
	ai.allianceTeams=n;
}
void updateStance(B)(ref ShinyAI!B ai,ObjectState!B state,int dTicks){ // rec1 0x4847f0
	// reset 0x484700/0x486660: u[7..9] not reset in either binary; u[4] thaum never resets (quirk), retail 0x48677e resets to 1
	foreach(k;0..4){
		auto rec=&ai.stanceRecs[k];
		rec.acc.clear();
		setI(*rec,0,0); setI(*rec,1,0); setI(*rec,2,1); setI(*rec,3,1); setI(*rec,5,0); setI(*rec,6,0);
		if(!ai.betaStanceU4Quirk) setI(*rec,4,1); // retail 0x48677e
	}
	ai.enemyCount=0;
	foreach(i,ref s;state.sides){ // both-direction enemy stances against living wizard sides
		if(i==ai.side||i==neutralSide||s.assignment==0) continue;
		if(state.sides.getStance(ai.side,to!int(i))!=Stance.enemy&&state.sides.getStance(to!int(i),ai.side)!=Stance.enemy) continue;
		if(state.getWizardForSide(to!int(i)) is null) continue; // 0x472030
		ai.enemyCount++;
	}
	foreach(k;0..4){
		auto rec=&ai.stanceRecs[k];
		rec.acc.clear();
		for(int g=ai.grp4Head[k];g;g=ai.groups4[g].gN){ // 0x484790
			auto grp=&ai.groups4[g];
			setI(*rec,6,si(*rec,6)+grp.count); // dead store: overwritten below (thaum quirk)
			setI(*rec,0,si(*rec,0)+grp.manaSum);
			setI(*rec,1,si(*rec,1)+grp.maxManaSum);
			combine(rec.acc,1.0f,grp.acc,1.0f);
		}
		for(int n=ai.fam1Head[k];n;n=ai.nodes[n].famN){ // soul pairs, node vtbl[21]
			auto p=soulsPair21(ai,state,n);
			setI(*rec,2,si(*rec,2)+p[0]);
			setI(*rec,3,si(*rec,3)+p[1]);
			setI(*rec,4,si(*rec,4)+p[0]+p[1]);
		}
		int c=0; // 0x484af0: fam2[k] nodes with status&0x4000
		for(int n=ai.fam2Head[k];n;n=ai.nodes[n].famN)
			if(ai.nodes[n].status&0x4000) c++;
		setI(*rec,5,c);
		if(k>0){
			auto rec0=&ai.stanceRecs[0];
			// safediv keeps the retail 0/0 NaN (branch-identical: every NaN comparison is false)
			// but canonicalizes its bit pattern so network games stay in sync across architectures
			foreach(j;0..3)
				setF(*rec,6+j,cast(float)safediv(cast(double)si(*rec0,2+j),cast(double)(si(*rec,2+j)+si(*rec0,2+j))));
		}else{
			setF(*rec,6,1.0f); setF(*rec,7,1.0f); setF(*rec,8,1.0f);
		}
	}
	int ebx=0,ebp=0;
	for(int n=ai.fam2Head[3];n;n=ai.nodes[n].famN){
		if(ai.nodes[n].flags&0x200) ebx++;
		if(ai.nodes[n].flags&0x80) ebp++;
	}
	int edx=0,edi=0;
	for(int n=ai.fam2Head[2];n;n=ai.nodes[n].famN){
		if(ai.nodes[n].flags&0x100) edx++;
		if(ai.nodes[n].flags&0x80) edi++;
	}
	ai.strengthRatio=cast(float)safediv(cast(double)(edi+ebp),cast(double)(edx+ebx)); // safediv: canonical NaN on 0/0, see above
	// acc1/acc2; the divide divisor is fild of the int sum of the u[6] float bits (thaum quirk)
	ai.acc1.clear(); ai.acc1Valid=true;
	combine(ai.acc1,1.0f,ai.stanceRecs[0].acc,1.0f);
	combine(ai.acc1,1.0f,ai.stanceRecs[1].acc,1.0f);
	divide(ai.acc1,cast(float)(si(ai.stanceRecs[1],6)+si(ai.stanceRecs[0],6)));
	ai.acc2.clear(); ai.acc2Valid=true;
	combine(ai.acc2,1.0f,ai.stanceRecs[3].acc,1.0f);
	divide(ai.acc2,cast(float)si(ai.stanceRecs[3],6));
}
void updateNtts(B)(ref ShinyAI!B ai,ObjectState!B state,int dTicks){ // 0x483f90
	for(int n=ai.idxHead;n;){
		auto nn=ai.nodes[n].idxN;
		if(!entExists!B(state,ai.nodes[n].kind,ai.nodes[n].id)){
			// thaum removes via event 6 (wired at kill/gib); entExists is the fallback for unwitnessed removals
			removeNode(ai,state,n);
			ai.forceFlags|=1;
		}else updateNode(ai,state,n,dTicks);
		n=nn;
	}
}
void updateGroups(B)(ref ShinyAI!B ai,ObjectState!B state,int dTicks){ // 0x483fd0
	foreach(k;0..4)
		for(int g=ai.grp4Head[k];g;g=ai.groups4[g].gN)
			groupRefresh4(ai,state,g);
}
void updateReplan(B)(ref ShinyAI!B ai,ObjectState!B state,int dTicks){ // 0x4841c0
	import frameprof;
	frameprof.beginReplanPhase("discover");
	discover(ai,state); // 0x484b30
	frameprof.endReplanPhase("discover");
	frameprof.beginReplanPhase("recycle");
	recycleGroups(ai);  // 0x4830a0
	frameprof.endReplanPhase("recycle");
	static immutable int[4] prio=[1,2,0,4];
	foreach(k;0..4){
		frameprof.beginReplanPhase("sort");
		sortFam1(ai,k);
		frameprof.endReplanPhase("sort");
		frameprof.beginReplanPhase("form4");
		formGroups4(ai,state,k,prio[k]); // 0x484d60
		frameprof.endReplanPhase("form4");
		frameprof.beginReplanPhase("form5");
		formGroups5(ai,state,k,prio[k]); // 0x485020
		frameprof.endReplanPhase("form5");
	}
	replanTasks(ai,state);  // 0x485260
	frameprof.beginReplanPhase("claim");
	claimPass(ai,state);    // 0x484c70
	frameprof.endReplanPhase("claim");
	ai.handledFlags|=1;
}
void discoverScan(B)(ref ShinyAI!B ai,ObjectState!B state,NodeKind kind,int id){
	auto n=addNode(ai,state,kind,id); // idempotent, shouldTrack-gated
	if(n){
		ai.nodes[n].flags|=0x80;
		ai.nodes[n].ageSeen=ai.nodes[n].age;
	}
}
void discoverScanAll(B)(ref ShinyAI!B ai,ObjectState!B state){ // armed pickup scan (forceFlags 0x20): runs at setup and on wizard region changes only; was discover's phase 1, ran every 60 ticks
	// thaum walks the side's seen-ntt list ([side+0xc], records written by SIDE::MarkAsVisible 0x4723e0; lookup 0x490f20 chains [side+0xc] matching rec+0x8==ntt), so only foreign entities the side has seen are added; own entities are always known
	state.eachMoving!((ref MovingObject!B o,ObjectState!B state,ShinyAI!B ai){
		if(o.side!=ai.side&&state.sid.lastSeenTick(ai.side,o.id)<0) return;
		if(o.isWizard){
			discoverScan(ai,state,NodeKind.wiz,o.id);
		}else{
			auto k=o.sacObject.isManahoar?NodeKind.maho:NodeKind.t4o;
			discoverScan(ai,state,k,o.id);
		}
	})(state,ai);
	state.eachBuilding!((ref Building!B b,ObjectState!B state,ShinyAI!B ai){
		if(b.side!=ai.side){
			// thaum marks the structure ntt itself visible; sacengine marks the building's component static objects
			bool seen=false;
			foreach(cid;b.componentIds) if(state.sid.lastSeenTick(ai.side,cid)>=0){ seen=true; break; }
			if(!seen) return;
		}
		discoverScan(ai,state,NodeKind.str,b.id);
	})(state,ai);
	state.eachSoul!((ref Soul!B s,ObjectState!B state,ShinyAI!B ai){
		discoverScan(ai,state,NodeKind.cre,s.id); // sacengine does not vision-track souls (no proximity entries), left ungated
	})(state,ai);
}
bool nodeSeen(B)(ref ShinyAI!B ai,ObjectState!B state,NodeKind kind,int id){ // the phase-1 ever-seen filter, applied per tracked node
	final switch(kind) with(NodeKind){
		case wiz,t4o,maho: return state.sid.lastSeenTick(ai.side,id)>=0;
		case str: return state.buildingById!((ref b,int side,ObjectState!B state){
				foreach(cid;b.componentIds) if(state.sid.lastSeenTick(side,cid)>=0) return true;
				return false;
			},()=>false)(id,ai.side,state);
		case cre: return true; // souls are not vision-tracked (no proximity entries), left ungated
		case none: return false;
	}
}
void discover(B)(ref ShinyAI!B ai,ObjectState!B state){ // 0x484b30
	if(ai.forceFlags&0x20){ // one-shot pickup scan: setup / wizard region change (entities are otherwise added by events)
		discoverScanAll(ai,state);
		ai.handledFlags|=0x20;
	}
	// phase 2 (0x484bfd): non-own nodes only (node+0x3c&1 = own relation flag, test at 0x484c14); remove ghost wizards, eliminated wizards, stale unseen nodes
	// the phase-1 ageSeen refresh for already-tracked nodes is folded into this sweep
	for(int n=ai.idxHead;n;){
		auto nn=ai.nodes[n].idxN;
		auto node=&ai.nodes[n];
		if(!(node.flags&1)){
			bool remove=false;
			if(node.kind==NodeKind.wiz){
				auto ws=entSide!B(state,node.kind,node.id);
				if(ws>=0&&state.sid.sides[ws].state!=SideState.playing) remove=true;
				if(!remove&&entGhost!B(state,node.id)) remove=true; // 0x484c22: wiz ntt (ntt+0x4==1) with stateFlags&0x40000 -> removeNode 0x483970, no side test beyond the own-node skip
			}
			if(!remove){
				if(nodeSeen(ai,state,node.kind,node.id)&&shouldTrack(ai,state,node.kind,node.id)){
					node.flags|=0x80;
					node.ageSeen=node.age;
				}else if((node.flags&0x80)&&cast(uint)node.ageSeen<cast(uint)node.age&&node.kind!=NodeKind.t4o&&node.kind!=NodeKind.maho)
					remove=true; // thaum 0x484c3d, retail 0x48721e: creatures (ntt+0x238&0x10) are exempt from the stale-seen removal
			}
			if(remove) removeNode(ai,state,n);
		}
		n=nn;
	}
}
void updateTasks(B)(ref ShinyAI!B ai,ObjectState!B state,int dTicks){ // 0x484020
	foreach(ref task; ai.tasks){
		auto cmd=taskCmd(task.kind);
		for(int r=task.claimedHead;r;){
			auto rn=ai.records[r].claimedN;
			static if(shinyAILog) ailog("TASK ",ai.side," t",ai.schedTime," kind ",task.kind," cmd ",cmd," r",r," score ",ai.records[r].score," tgt ",ai.records[r].target," count ",ai.records[r].count," flags ",ai.records[r].flags);
			recordUpdate(ai,state,r,cmd);
			r=rn;
		}
	}
}
uint taskCmd(int kind){ // task vtbl[13]: capture=2 (0x4cfaa0), guard=1 (0x4cfa9c), idle=ds:0x4ee030 (0x64692e70, never written)
	final switch(cast(TaskKind)kind) with(TaskKind){
		case capture: return 2;
		case guard: return 1;
		case idle: return 0x64692e70;
	}
}

// ---- node vtbl accessors used by groups/tasks ----

bool nodeIsAlive(B)(ref ShinyAI!B ai,ObjectState!B state,int n){ // node vtbl[8] 0x4872c0/0x486a90
	final switch(ai.nodes[n].kind) with(NodeKind){
		case wiz,maho,t4o: return !entDead!B(state,ai.nodes[n].id);
		case cre,str: return true;
		case none: return true;
	}
}
float sortKey(B)(ref ShinyAI!B ai,int n){ // node vtbl[7]
	final switch(ai.nodes[n].kind) with(NodeKind){
		case t4o,maho,wiz,str: return ai.nodes[n].cachedRate;
		case cre: return 0.0f; // 0x483750
		case none: return 0.0f;
	}
}
int sortKeyCmp(B)(ref ShinyAI!B ai,int a,int b){ // 0x484500: 1 if key(b)>key(a), -1 if key(b)<key(a)
	auto ka=sortKey(ai,a), kb=sortKey(ai,b);
	return kb>ka?1:kb<ka?-1:0;
}
bool hasAcc(B)(ref ShinyAI!B ai,int n){ return ai.nodes[n].kind!=NodeKind.cre; } // node vtbl[11] != 0
float nodeValue6c(B)(ref ShinyAI!B ai,int n){ // node+0x6c: wiz threat / str cached rate
	final switch(ai.nodes[n].kind) with(NodeKind){
		case wiz: return ai.nodes[n].threat;
		case str: return ai.nodes[n].cachedRate;
		case t4o,maho,cre,none: return 0.0f;
	}
}
Tuple!(int,int) outPair5(B)(ref ShinyAI!B ai,ObjectState!B state,int n){ // node vtbl[5]: (mana,maxMana)
	auto node=&ai.nodes[n];
	final switch(node.kind) with(NodeKind){
		case t4o,wiz:
			return state.movingObjectReadById!((ref cols,i,state)=>tuple(ftol(cols.creatureStatss[i].mana),ftol(cols.creatureStatss[i].maxMana)),()=>tuple(0,0))(node.id,state);
		case maho,str,cre,none: return tuple(0,0);
	}
}
Tuple!(int,int) soulsPair21(B)(ref ShinyAI!B ai,ObjectState!B state,int n){ // node vtbl[21]
	auto node=&ai.nodes[n];
	final switch(node.kind) with(NodeKind){
		case t4o,maho:
			return tuple(state.movingObjectReadById!((ref cols,i,state)=>cols.sacObject.numSouls,()=>0)(node.id,state),0); // thaum reads ntt+0xb30 (soul worth); effects.carrying is SacDoc-only
		case wiz: return tuple(node.manaSnap,node.soulsSnap); // manaSnap is never updated by thaum (stays 0)
		case str,cre,none: return tuple(0,0);
	}
}
bool claimable(B)(ref ShinyAI!B ai,ObjectState!B state,int n){ // ntt vtbl[19] 0x46c320
	// ntt+0xb24&0x100 check has no sacengine equivalent (documented gap)
	return state.movingObjectReadById!((ref cols,i,state)=>!cols.sacObject.isSacDoctor&&!cols.creatureStates[i].mode.among(CreatureMode.dying,CreatureMode.dead,CreatureMode.deadToGhost,CreatureMode.dissolving),()=>false)(ai.nodes[n].id,state);
}

// ---- groups ----

int allocGroup4(B)(ref ShinyAI!B ai){
	if(ai.grp4Free){
		auto g=ai.grp4Free;
		ai.grp4Free=ai.groups4[g].freeN;
		ai.groups4[g]=AIGroup.init;
		return g;
	}
	ai.groups4~=AIGroup.init;
	return cast(int)ai.groups4.length-1;
}
int allocGroup5(B)(ref ShinyAI!B ai){
	if(ai.grp5Free){
		auto g=ai.grp5Free;
		ai.grp5Free=ai.groups5[g].freeN;
		ai.groups5[g]=AIGroup.init;
		return g;
	}
	ai.groups5~=AIGroup.init;
	return cast(int)ai.groups5.length-1;
}
void grp4Append(B)(ref ShinyAI!B ai,int k,int g){
	auto grp=&ai.groups4[g];
	grp.gN=0;
	if(ai.grp4Tail[k]) ai.groups4[ai.grp4Tail[k]].gN=g; else ai.grp4Head[k]=g;
	grp.gP=ai.grp4Tail[k];
	ai.grp4Tail[k]=g;
}
void grp4ListUnlink(B)(ref ShinyAI!B ai,int k,int g){ // 0x483b10 (callers pass the prio-quirk sublist)
	auto grp=&ai.groups4[g];
	if(grp.gP) ai.groups4[grp.gP].gN=grp.gN; else ai.grp4Head[k]=grp.gN;
	if(grp.gN) ai.groups4[grp.gN].gP=grp.gP; else ai.grp4Tail[k]=grp.gP;
	grp.gP=grp.gN=0;
}
void grp5Append(B)(ref ShinyAI!B ai,int k,int g){
	auto grp=&ai.groups5[g];
	grp.gN=0;
	if(ai.grp5Tail[k]) ai.groups5[ai.grp5Tail[k]].gN=g; else ai.grp5Head[k]=g;
	grp.gP=ai.grp5Tail[k];
	ai.grp5Tail[k]=g;
}
void grp5ListUnlink(B)(ref ShinyAI!B ai,int k,int g){ // 0x483c90
	auto grp=&ai.groups5[g];
	if(grp.gP) ai.groups5[grp.gP].gN=grp.gN; else ai.grp5Head[k]=grp.gN;
	if(grp.gN) ai.groups5[grp.gN].gP=grp.gP; else ai.grp5Tail[k]=grp.gP;
	grp.gP=grp.gN=0;
}
int prioSub(int prio){ return prio&1?0:prio&2?1:prio&4?3:2; } // 0x483b10 unlink sublist quirk

void groupAddMember4(B)(ref ShinyAI!B ai,int g,int n){ // slot4 group vtbl[3], tail-append
	auto grp=&ai.groups4[g];
	auto node=&ai.nodes[n];
	node.grpN=0;
	if(grp.memberTail) ai.nodes[grp.memberTail].grpN=n; else grp.memberHead=n;
	node.grpP=grp.memberTail;
	grp.memberTail=n;
	grp.count++;
}
void creGroupAddMember5(B)(ref ShinyAI!B ai,int g,int n){ // slot5 group vtbl[3] 0x486480, tail-append
	auto grp=&ai.groups5[g];
	auto node=&ai.nodes[n];
	node.cgrpN=0;
	if(grp.memberTail) ai.nodes[grp.memberTail].cgrpN=n; else grp.memberHead=n;
	node.cgrpP=grp.memberTail;
	grp.memberTail=n;
	grp.count++;
}
void groupReset4(B)(ref ShinyAI!B ai,int g){ // 0x487de0
	ai.groups4[g].acc.clear();
	while(ai.groups4[g].memberHead) groupRemoveMember(ai,g,ai.groups4[g].memberHead);
}
void groupReset5(B)(ref ShinyAI!B ai,int g){ // 0x486440
	while(ai.groups5[g].memberHead) creGroupRemoveMember(ai,g,ai.groups5[g].memberHead);
}
void groupSetup4(B)(ref ShinyAI!B ai,ObjectState!B state,int g,int prio){ // 0x487da0 (ctx=ai; thaum's ebp-clobber on pool grow is dead in practice)
	groupReset4(ai,g);
	auto grp=&ai.groups4[g];
	grp.prio=prio;
	grp.count=0;
	groupRefresh4(ai,state,g);
	grp.acc.clear();
	grp.manaSum=0; grp.maxManaSum=0;
}
void groupSetup5(B)(ref ShinyAI!B ai,ObjectState!B state,int g,int prio){ // 0x486410
	groupReset5(ai,g);
	auto grp=&ai.groups5[g];
	grp.prio=prio;
	grp.count=0;
	groupRefresh5(ai,state,g); // refresh on the empty group: center stays (0,0,0) (thaum origin quirk)
}

void groupRefresh4(B)(ref ShinyAI!B ai,ObjectState!B state,int g){ // slot4 group vtbl[7] 0x487e90
	auto grp=&ai.groups4[g];
	grp.avgVel=Vector3f(0.0f,0.0f,0.0f); // accumulators: thaum zeroes (C++); Vector3f.init is NaN
	grp.prevCenter=grp.center;
	grp.center=Vector3f(0.0f,0.0f,0.0f);
	auto sumSq=Vector3f(0.0f,0.0f,0.0f);
	double countF=0.0;
	grp.count=0;
	grp.statusOR=0;
	for(int n=grp.memberHead;n;){
		auto node=&ai.nodes[n];
		auto nn=node.grpN;
		if(!nodeIsAlive(ai,state,n)){ groupRemoveMember(ai,g,n); n=nn; continue; }
		grp.count++;
		grp.statusOR|=node.status;
		if(node.status&1){
			countF+=1.0;
			grp.avgVel+=node.velocity;
			grp.center+=node.curPos;
			sumSq.x+=node.curPos.x*node.curPos.x;
			sumSq.y+=node.curPos.y*node.curPos.y;
			sumSq.z+=node.curPos.z*node.curPos.z;
		}
		n=nn;
	}
	if(countF!=0.0){
		auto inv=safediv(1.0,countF);
		grp.avgVel*=cast(float)inv;
		grp.center*=cast(float)inv;
		grp.stddev.x=cast(float)sqrt(fabs(cast(double)sumSq.x*inv-cast(double)grp.center.x*grp.center.x));
		grp.stddev.y=cast(float)sqrt(fabs(cast(double)sumSq.y*inv-cast(double)grp.center.y*grp.center.y));
		grp.stddev.z=cast(float)sqrt(fabs(cast(double)sumSq.z*inv-cast(double)grp.center.z*grp.center.z));
	}
	grp.predicted=grp.center+grp.avgVel;
	// slot4 tail 0x488034: rebuild acc/mana/health/ready/souls aggregates over members with status!=0
	grp.acc.clear();
	grp.manaSum=0; grp.maxManaSum=0;
	grp.healthSum=0; grp.healthSum2=0;
	grp.readyCount=0; grp.soulsSum=0;
	for(int n=grp.memberHead;n;n=ai.nodes[n].grpN){
		auto node=&ai.nodes[n];
		if(node.status==0) continue; // thaum tests the whole status dword, not the active bit
		auto p5=outPair5(ai,state,n);
		grp.manaSum+=p5[0]; grp.maxManaSum+=p5[1];
		state.movingObjectReadById!((ref cols,i,ObjectState!B state){
			grp.healthSum+=typeStats!B(cols.sacObject).health; // ntt stat word[3]
			grp.healthSum2+=ftol(cols.creatureStatss[i].health);   // ntt word +0x8ea
		},(){})(node.id,state);
		if(hasAcc(ai,n)) combine(grp.acc,1.0f,node.acc,1.0f);
		if(node.status&0x1000) grp.readyCount++;
		auto p21=soulsPair21(ai,state,n);
		grp.soulsSum+=p21[0]+p21[1];
	}
}
void groupRefresh5(B)(ref ShinyAI!B ai,ObjectState!B state,int g){ // slot5 group vtbl[7] 0x4865d0 (aggregate only)
	auto grp=&ai.groups5[g];
	grp.avgVel=Vector3f(0.0f,0.0f,0.0f); // accumulators: thaum zeroes (C++); Vector3f.init is NaN
	grp.prevCenter=grp.center;
	grp.center=Vector3f(0.0f,0.0f,0.0f);
	auto sumSq=Vector3f(0.0f,0.0f,0.0f);
	double countF=0.0;
	grp.count=0;
	grp.statusOR=0;
	for(int n=grp.memberHead;n;){
		auto node=&ai.nodes[n];
		auto nn=node.cgrpN;
		if(!nodeIsAlive(ai,state,n)){ creGroupRemoveMember(ai,g,n); n=nn; continue; } // cre isAlive always 1: never pruned
		grp.count++;
		grp.statusOR|=node.status;
		if(node.status&1){
			countF+=1.0;
			grp.avgVel+=node.velocity;
			grp.center+=node.curPos;
			sumSq.x+=node.curPos.x*node.curPos.x;
			sumSq.y+=node.curPos.y*node.curPos.y;
			sumSq.z+=node.curPos.z*node.curPos.z;
		}
		n=nn;
	}
	if(countF!=0.0){
		auto inv=safediv(1.0,countF);
		grp.avgVel*=cast(float)inv;
		grp.center*=cast(float)inv;
		grp.stddev.x=cast(float)sqrt(fabs(cast(double)sumSq.x*inv-cast(double)grp.center.x*grp.center.x));
		grp.stddev.y=cast(float)sqrt(fabs(cast(double)sumSq.y*inv-cast(double)grp.center.y*grp.center.y));
		grp.stddev.z=cast(float)sqrt(fabs(cast(double)sumSq.z*inv-cast(double)grp.center.z*grp.center.z));
	}
	grp.predicted=grp.center+grp.avgVel;
}

void recycleGroups(B)(ref ShinyAI!B ai){ // 0x4830a0
	foreach(k;0..4){
		for(int g=ai.grp4Head[k];g;){
			auto gn=ai.groups4[g].gN;
			groupReset4(ai,g);
			grp4ListUnlink(ai,prioSub(ai.groups4[g].prio),g);
			ai.groups4[g].freeN=ai.grp4Free; ai.grp4Free=g;
			g=gn;
		}
		for(int g=ai.grp5Head[k];g;){
			auto gn=ai.groups5[g].gN;
			groupReset5(ai,g);
			grp5ListUnlink(ai,prioSub(ai.groups5[g].prio),g);
			ai.groups5[g].freeN=ai.grp5Free; ai.grp5Free=g;
			g=gn;
		}
	}
}

void sortFam1(B)(ref ShinyAI!B ai,int k){ // 0x4841c0 inline sort: stable descending insertion sort from the tail, key = node vtbl[7]
	if(ai.fam1Tail[k]==0) return;
	for(int cur=ai.nodes[ai.fam1Tail[k]].famP;cur;){
		auto prev=ai.nodes[cur].famP;
		auto next=ai.nodes[cur].famN;
		if(sortKeyCmp(ai,cur,next)>0){ // next==0 reads the dummy node (key 0.0f); unreachable in practice
			int insertAfter=0;
			for(int scan=next;scan;scan=ai.nodes[scan].famN)
				if(sortKeyCmp(ai,cur,scan)<=0){ insertAfter=scan; break; }
			auto node=&ai.nodes[cur];
			if(node.famP) ai.nodes[node.famP].famN=node.famN; else ai.fam1Head[k]=node.famN;
			if(node.famN) ai.nodes[node.famN].famP=node.famP; else ai.fam1Tail[k]=node.famP;
			node.famP=node.famN=0;
			node.famN=insertAfter;
			node.famP=insertAfter?ai.nodes[insertAfter].famP:ai.fam1Tail[k];
			if(node.famP) ai.nodes[node.famP].famN=cur; else ai.fam1Head[k]=cur;
			if(insertAfter) ai.nodes[insertAfter].famP=cur; else ai.fam1Tail[k]=cur;
			if(ai.fam1Head[k]==0) ai.fam1Head[k]=cur; // thaum empty-list fixups (unreachable)
			if(ai.fam1Tail[k]==0) ai.fam1Tail[k]=cur;
		}
		cur=prev;
	}
}

// formGroups scratch: canAccept needs the live entity pos (thaum reads ntt+0x1b8, not the cached curPos),
// but positions cannot change during a single formGroups4/5 call (group setup/fill/refresh only touch ai
// structures), and the sacengine movingObjectById lookup copies the whole object out and back on every
// call, which dominated the replan cost (form4 was ~3-5ms per side per replan tick). Cache one entPos
// lookup per node while copying the scratch list instead; accept/reject decisions are bit-identical.
Vector3f[] formPosCache; // TLS, indexed by node index; valid for the current formGroups4/5 call only
bool canAccept(int count,Vector3f center,Vector3f p){ // group vtbl[6] 0x4868b0/0x486550; p = cached live entPos
	auto r=cast(double)count*0.1+1.0;
	if(!(r<1.7999999523162842)) r=1.7999999523162842; // fcom keep-smaller
	r*=30.0;
	auto d=p-center;
	auto d2=d.x*d.x+d.y*d.y+d.z*d.z; // float ops
	return !(r*r<cast(double)d2);
}

void formGroups4(B)(ref ShinyAI!B ai,ObjectState!B state,int k,int prio){ // 0x484d60
	int head=0, tail=0;
	if(formPosCache.length<ai.nodes.length) formPosCache.length=ai.nodes.length;
	for(int n=ai.fam1Head[k];n;n=ai.nodes[n].famN){ // copy sublist to scratch (grpP/grpN links)
		auto node=&ai.nodes[n];
		formPosCache[n]=entPos!B(state,node.kind,node.id);
		node.grpN=0;
		if(tail) ai.nodes[tail].grpN=n; else head=n;
		node.grpP=tail;
		tail=n;
	}
	while(head){
		auto n=head; // pop scratch head
		auto node=&ai.nodes[n];
		head=node.grpN;
		if(head) ai.nodes[head].grpP=node.grpP; else tail=node.grpP;
		node.grpP=node.grpN=0;
		auto g=allocGroup4(ai);
		groupSetup4(ai,state,g,prio);
		groupAddMember4(ai,g,n);
		node.group=g;
		fillGroup4(ai,state,g,head,tail);
		grp4Append(ai,k,g);
		groupRefresh4(ai,state,g); // refresh after append
	}
	if(ai.config&2){ int num=0; for(int g=ai.grp4Head[k];g;g=ai.groups4[g].gN) ai.groups4[g].number=num++; }
}
void fillGroup4(B)(ref ShinyAI!B ai,ObjectState!B state,int g,ref int head,ref int tail){ // 0x484f80
	groupRefresh4(ai,state,g); // entry refresh
	auto grp=&ai.groups4[g];
	// incremental refresh state: while filling, members are only ever tail-appended, so the running
	// sums below are bit-identical to re-running groupRefresh4's accumulation loop after each add
	// (same member order, same float operations); avgVel/stddev/aggregates are not read by canAccept
	// and are recomputed by the full refresh in formGroups4 once the group is complete
	Vector3f centerSum=Vector3f(0.0f,0.0f,0.0f);
	double countF=0.0;
	for(int n=grp.memberHead;n;n=ai.nodes[n].grpN){
		auto node=&ai.nodes[n];
		if(node.status&1){ countF+=1.0; centerSum+=node.curPos; }
	}
	for(int n=head;n;){
		if(!canAccept(grp.count,grp.center,formPosCache[n])){ n=ai.nodes[n].grpN; continue; }
		auto node=&ai.nodes[n];
		if(node.grpP) ai.nodes[node.grpP].grpN=node.grpN; else head=node.grpN;
		if(node.grpN) ai.nodes[node.grpN].grpP=node.grpP; else tail=node.grpP;
		node.grpP=node.grpN=0;
		groupAddMember4(ai,g,n);
		node.group=g;
		if(nodeIsAlive(ai,state,n)){ // usual case: fold the new member into the refresh sums
			grp.statusOR|=node.status;
			if(node.status&1){
				countF+=1.0;
				centerSum+=node.curPos;
				auto inv=safediv(1.0,countF);
				grp.center=centerSum*cast(float)inv;
			}
		}else{ // rare: the recursive refresh would have pruned the dead member; replicate it exactly
			groupRefresh4(ai,state,g);
			centerSum=Vector3f(0.0f,0.0f,0.0f);
			countF=0.0;
			for(int m=grp.memberHead;m;m=ai.nodes[m].grpN){
				auto mnode=&ai.nodes[m];
				if(mnode.status&1){ countF+=1.0; centerSum+=mnode.curPos; }
			}
		}
		n=head; // rescan from the head (same accept order as the recursion)
	}
}
void formGroups5(B)(ref ShinyAI!B ai,ObjectState!B state,int k,int prio){ // 0x485020
	int head=0, tail=0;
	if(formPosCache.length<ai.nodes.length) formPosCache.length=ai.nodes.length;
	for(int n=ai.fam3Head[k];n;n=ai.nodes[n].famN){ // copy sublist to scratch (cgrpP/cgrpN links)
		auto node=&ai.nodes[n];
		formPosCache[n]=entPos!B(state,node.kind,node.id);
		node.cgrpN=0;
		if(tail) ai.nodes[tail].cgrpN=n; else head=n;
		node.cgrpP=tail;
		tail=n;
	}
	while(head){
		auto n=head; // pop scratch head
		auto node=&ai.nodes[n];
		head=node.cgrpN;
		if(head) ai.nodes[head].cgrpP=node.cgrpP; else tail=node.cgrpP;
		node.cgrpP=node.cgrpN=0;
		auto g=allocGroup5(ai);
		groupSetup5(ai,state,g,prio); // refreshes the empty group: center=(0,0,0)
		creGroupAddMember5(ai,g,n);
		node.cgroup=g;
		fillGroup5(ai,state,g,head,tail); // no entry refresh: first canAccept round measures from the origin (thaum quirk)
		grp5Append(ai,k,g);
		groupRefresh5(ai,state,g); // refresh after append
	}
}
void fillGroup5(B)(ref ShinyAI!B ai,ObjectState!B state,int g,ref int head,ref int tail){ // 0x4851e0 (no entry refresh)
	auto grp=&ai.groups5[g];
	// incremental refresh state, same argument as fillGroup4; no entry refresh here (thaum quirk):
	// the first canAccept round still sees the group exactly as groupSetup5 left it (center (0,0,0))
	Vector3f centerSum=Vector3f(0.0f,0.0f,0.0f);
	double countF=0.0;
	uint statusORSum=0; // shadow accumulator: grp.statusOR itself is only written on an accept
	for(int n=grp.memberHead;n;n=ai.nodes[n].cgrpN){
		auto node=&ai.nodes[n];
		statusORSum|=node.status;
		if(node.status&1){ countF+=1.0; centerSum+=node.curPos; }
	}
	for(int n=head;n;){
		if(!canAccept(grp.count,grp.center,formPosCache[n])){ n=ai.nodes[n].cgrpN; continue; }
		auto node=&ai.nodes[n];
		if(node.cgrpP) ai.nodes[node.cgrpP].cgrpN=node.cgrpN; else head=node.cgrpN;
		if(node.cgrpN) ai.nodes[node.cgrpN].cgrpP=node.cgrpP; else tail=node.cgrpP;
		node.cgrpP=node.cgrpN=0;
		creGroupAddMember5(ai,g,n);
		node.cgroup=g;
		if(nodeIsAlive(ai,state,n)){ // usual case: fold the new member into the refresh sums
			statusORSum|=node.status;
			grp.statusOR=statusORSum;
			if(node.status&1){
				countF+=1.0;
				centerSum+=node.curPos;
				auto inv=safediv(1.0,countF);
				grp.center=centerSum*cast(float)inv;
			}
		}else{ // rare: the refresh after each addMember would have pruned the dead member; replicate it
			groupRefresh5(ai,state,g);
			centerSum=Vector3f(0.0f,0.0f,0.0f);
			countF=0.0;
			statusORSum=0;
			for(int m=grp.memberHead;m;m=ai.nodes[m].cgrpN){
				auto mnode=&ai.nodes[m];
				statusORSum|=mnode.status;
				if(mnode.status&1){ countF+=1.0; centerSum+=mnode.curPos; }
			}
		}
		n=head; // rescan from the head (same accept order as the recursion)
	}
}

// ---- claim records ----

void freePush(B)(ref ShinyAI!B ai,ref AITask!B task,int r){ // 0x48ba90 tail-append
	auto rec=&ai.records[r];
	rec.claimedN=0;
	if(task.freeTail) ai.records[task.freeTail].claimedN=r; else task.freeHead=r;
	rec.claimedP=task.freeTail;
	task.freeTail=r;
}
int freePop(B)(ref ShinyAI!B ai,ref AITask!B task){ // 0x48bb20 unlink from the tail (LIFO)
	auto r=task.freeTail;
	auto rec=&ai.records[r];
	task.freeTail=rec.claimedP;
	if(task.freeTail) ai.records[task.freeTail].claimedN=0; else task.freeHead=0;
	rec.claimedP=rec.claimedN=0;
	return r;
}
int allocRecord(B)(ref ShinyAI!B ai,ref AITask!B task){
	if(task.freeHead==0) foreach(i;0..0x20){ // grow 0x20 (0x48bbf0 ctor + 0x48ba90 tail-append)
		ai.records~=AIRecord!B.init;
		freePush(ai,task,cast(int)ai.records.length-1);
	}
	return freePop(ai,task);
}
void claimedUnlink(B)(ref ShinyAI!B ai,ref AITask!B task,int r){
	auto rec=&ai.records[r];
	if(rec.claimedP) ai.records[rec.claimedP].claimedN=rec.claimedN; else task.claimedHead=rec.claimedN;
	if(rec.claimedN) ai.records[rec.claimedN].claimedP=rec.claimedP; else task.claimedTail=rec.claimedP;
	rec.claimedP=rec.claimedN=0;
}
void sortedInsert(B)(ref ShinyAI!B ai,ref AITask!B task,int r){ // 0x48a660: desc by score; new record before ties
	auto rec=&ai.records[r];
	int at=task.claimedHead;
	while(at&&ai.records[at].score>rec.score) at=ai.records[at].claimedN;
	rec.claimedN=at;
	rec.claimedP=at?ai.records[at].claimedP:task.claimedTail;
	if(rec.claimedP) ai.records[rec.claimedP].claimedN=r; else task.claimedHead=r;
	if(at) ai.records[at].claimedP=r; else task.claimedTail=r;
}
void normalizeScores(B)(ref ShinyAI!B ai,ref AITask!B task,float total){ // 0x48a6f0
	if(cast(double)total==0.0) return;
	for(int r=task.claimedHead;r;r=ai.records[r].claimedN)
		ai.records[r].score=safediv(ai.records[r].score,total);
}

void recAddMember(B)(ref ShinyAI!B ai,int ri,int n){ // 0x48bc90 tail-append
	auto rec=&ai.records[ri];
	auto node=&ai.nodes[n];
	node.recN=0;
	if(rec.memberTail) ai.nodes[rec.memberTail].recN=n; else rec.memberHead=n;
	node.recP=rec.memberTail;
	rec.memberTail=n;
	rec.count++;
}
void recRemoveMember(B)(ref ShinyAI!B ai,int ri,int n){ // 0x48bce0
	auto rec=&ai.records[ri];
	auto node=&ai.nodes[n];
	if(node.recP) ai.nodes[node.recP].recN=node.recN; else rec.memberHead=node.recN;
	if(node.recN) ai.nodes[node.recN].recP=node.recP; else rec.memberTail=node.recP;
	node.recP=node.recN=0;
	rec.count--;
}
bool recContains(B)(ref ShinyAI!B ai,int ri,int n){ // 0x48bd50
	for(int m=ai.records[ri].memberHead;m;m=ai.nodes[m].recN) if(m==n) return true;
	return false;
}
void recordRefresh(B)(ref ShinyAI!B ai,ObjectState!B state,int ri){ // 0x48be10 (aggregate only, no rater tail)
	auto rec=&ai.records[ri];
	rec.velAcc=Vector3f(0.0f,0.0f,0.0f); // accumulators: thaum zeroes (C++); Vector3f.init is NaN
	rec.prevCenter=rec.center;
	rec.center=Vector3f(0.0f,0.0f,0.0f);
	auto sumSq=Vector3f(0.0f,0.0f,0.0f);
	double countF=0.0;
	rec.count=0;
	rec.statusOR=0;
	for(int n=rec.memberHead;n;){
		auto node=&ai.nodes[n];
		auto nn=node.recN;
		if(!nodeIsAlive(ai,state,n)){ recRemoveMember(ai,ri,n); n=nn; continue; }
		rec.count++;
		rec.statusOR|=node.status;
		if(node.status&1){
			countF+=1.0;
			rec.velAcc+=node.velocity;
			rec.center+=node.curPos;
			sumSq.x+=node.curPos.x*node.curPos.x;
			sumSq.y+=node.curPos.y*node.curPos.y;
			sumSq.z+=node.curPos.z*node.curPos.z;
		}
		n=nn;
	}
	if(countF!=0.0){
		auto inv=safediv(1.0,countF);
		rec.velAcc*=cast(float)inv;
		rec.center*=cast(float)inv;
		rec.stddev.x=cast(float)sqrt(fabs(cast(double)sumSq.x*inv-cast(double)rec.center.x*rec.center.x));
		rec.stddev.y=cast(float)sqrt(fabs(cast(double)sumSq.y*inv-cast(double)rec.center.y*rec.center.y));
		rec.stddev.z=cast(float)sqrt(fabs(cast(double)sumSq.z*inv-cast(double)rec.center.z*rec.center.z));
	}
	rec.predicted=rec.center+rec.velAcc;
}
void recordRelease(B)(ref ShinyAI!B ai,int ri){ // 0x48a020
	auto rec=&ai.records[ri];
	while(rec.memberHead) recRemoveMember(ai,ri,rec.memberHead);
	rec.target=0; rec.leader=0;
	rec.targetAcc.clear(); rec.membersAcc.clear();
}
void recordSetup(B)(ref ShinyAI!B ai,ObjectState!B state,int ri,int target,uint flags){ // 0x489fa0
	recordRelease(ai,ri);
	auto rec=&ai.records[ri];
	// thaum copies 13 dwords node+0x4..+0x38 (positions/velocity); only the anchor is ever read
	rec.anchor=target?ai.nodes[target].curPos:Vector3f(0.0f,0.0f,0.0f);
	rec.target=target;
	rec.score=0.0f;
	rec.flags=flags;
	static if(shinyAILog) ailog("RECSETUP ",ai.side," t",ai.schedTime," r",ri," tgt ",target," flags ",flags," anchor ",rec.anchor);
	rec.targetAcc.clear();
	rec.membersAcc.clear();
	recordRefresh(ai,state,ri); // embedded reset
}
void clearClaimed(B)(ref ShinyAI!B ai,ref AITask!B task){ // task vtbl[3] 0x48a3f0 -> vtbl[9] 0x48a5c0
	while(task.claimedHead){
		auto r=task.claimedHead;
		recordRelease(ai,r);
		claimedUnlink(ai,task,r);
		freePush(ai,task,r);
	}
}
void taskReleaseRecordsTargeting(B)(ref ShinyAI!B ai,ref AITask!B task,int n){ // task vtbl[10] 0x48a540
	for(int r=task.claimedHead;r;){
		auto rn=ai.records[r].claimedN;
		if(ai.records[r].target==n){
			recordRelease(ai,r);
			claimedUnlink(ai,task,r);
			freePush(ai,task,r);
		}
		r=rn;
	}
}
void taskRemoveRecordMember(B)(ref ShinyAI!B ai,ref AITask!B task,int n){ // task vtbl[11] 0x48a4e0
	for(int r=task.claimedHead;r;r=ai.records[r].claimedN){
		if(recContains(ai,r,n)) recRemoveMember(ai,r,n);
		else if(ai.records[r].leader==n) ai.records[r].leader=0;
	}
}
int claim(B)(ref ShinyAI!B ai,ObjectState!B state,ref AITask!B task,int ri,ref int tempHead,ref int tempTail,int n){ // 0x48a740
	auto node=&ai.nodes[n];
	if(node.recP) ai.nodes[node.recP].recN=node.recN; else tempHead=node.recN;
	if(node.recN) ai.nodes[node.recN].recP=node.recP; else tempTail=node.recP;
	node.recP=node.recN=0;
	auto rec=&ai.records[ri];
	combine(rec.membersAcc,1.0f,node.acc,1.0f);
	recAddMember(ai,ri,n);
	node.record=ri;
	if(node.status&0x20000&&rec.leader==0) rec.leader=n; // wizards: thaum setupWiz 0x48c800 sets status 0x2000e (incl. 0x20000)
	static if(shinyAILog) ailog("CLAIM ",ai.side," t",ai.schedTime," n",n,"(",node.kind," id ",node.id,") -> r",ri," task ",task.kind," tgt ",rec.target);
	auto p=soulsPair21(ai,state,n);
	return p[0]+p[1];
}

// ---- scoring helpers ----

float lerp(float a,float w,float b){ return a+(b-a)*w; } // 0x48abe0
float probOr(B)(ref ShinyAI!B ai,ObjectState!B state,Vector3f pos,int slot,uint mask,float near,float far,int exclude){ // 0x485d10
	float acc=0.0f;
	for(int n=ai.fam2Head[slot];n;n=ai.nodes[n].famN){
		if(n==exclude||!(ai.nodes[n].flags&mask)) continue;
		auto d=pos-ai.nodes[n].curPos;
		auto dist=sqrt(d.x*d.x+d.y*d.y+d.z*d.z);
		auto w=dist<=near?1.0f:dist>=far?0.0f:safediv(far-dist,far-near);
		acc+=w*w*(1.0f-acc);
	}
	return acc;
}
float territorialScore(B)(ref ShinyAI!B ai,ObjectState!B state,Vector3f pos,int exclude){ // retail 0x488d70 (no thaum twin): own+ally structure proximity score
	float acc=0.0f;
	foreach(k;0..4){ // k loop with (1<<k)&3 -> own+ally structure lists only (accessors 0x488f80/0x488fa0)
		if(!((1<<k)&3)) continue;
		for(int n=ai.fam2Head[k];n;n=ai.nodes[n].famN){
			if(n==exclude) continue; // node==arg rec
			auto node=&ai.nodes[n];
			auto r=node.status&0x4000?1000.0f:50.0f; // node+0x40&0x4000
			immutable dx=cast(float)(pos.x-node.curPos.x), dy=cast(float)(pos.y-node.curPos.y), dz=cast(float)(pos.z-node.curPos.z); // f32 subs
			auto d=cast(float)sqrt(cast(double)dz*dz+(cast(double)dy*dy+cast(double)dx*dx)); // dz^2+(dy^2+dx^2) 80-bit, _CIsqrt, f32 store
			float s;
			if(d<=10.0f) s=1.0f; // test ah,0x41
			else if(d<r) s=cast(float)safediv(cast(double)r-d,cast(double)r-10.0f); // test ah,1: strictly below r
			else s=0.0f;
			acc=cast(float)(cast(double)s*s*(1.0-cast(double)acc)+cast(double)acc); // 80-bit chain, f32 store each iter
		}
	}
	return acc;
}
float densityGroups(B)(ref ShinyAI!B ai,ObjectState!B state,Vector3f pos,float near,float far){ // 0x485e00
	float acc=0.0f;
	static immutable int[2] cats=[2,3];
	foreach(k;cats){
		for(int g=ai.grp5Head[k];g;g=ai.groups5[g].gN){
			auto grp=&ai.groups5[g];
			auto d=pos-grp.center;
			auto dist=sqrt(d.x*d.x+d.y*d.y+d.z*d.z);
			auto w=dist<=near?1.0f:dist>=far?0.0f:safediv(far-dist,far-near);
			acc+=w*cast(float)grp.count;
		}
		for(int g=ai.grp4Head[k];g;g=ai.groups4[g].gN){
			auto grp=&ai.groups4[g];
			if(grp.soulsSum==0) continue;
			auto d=pos-grp.center;
			auto dist=sqrt(d.x*d.x+d.y*d.y+d.z*d.z);
			auto w=dist<=near?1.0f:dist>=far?0.0f:safediv(far-dist,far-near);
			acc+=w*cast(float)grp.soulsSum;
		}
	}
	return safediv(acc,cast(float)ai.maxSoulsSeen);
}
float influenceGroups(B)(ref ShinyAI!B ai,ObjectState!B state,int slot,Vector3f pos,float near,float far,RaterAcc* acc){ // 0x485be0
	RaterAcc tmp;
	if(acc is null){ acc=&tmp; (*acc).clear(); }
	float soulsW=0.0f;
	for(int g=ai.grp4Head[slot];g;g=ai.groups4[g].gN){
		auto grp=&ai.groups4[g];
		if(!(grp.statusOR&1)) continue;
		auto d=pos-grp.center;
		auto dist=sqrt(d.x*d.x+d.y*d.y+d.z*d.z);
		float w;
		if(dist<=near) w=1.0f;
		else if(!(dist<far)) continue;
		else w=safediv(far-dist,far-near); // thaum also has a w==0->skip guard here, dead code (w>0 always)
		combine(*acc,1.0f,grp.acc,w);
		soulsW+=w*cast(float)grp.soulsSum;
	}
	// divisor is fild of u[4] (0x485cfa/0x488a09): never reset in thaum (grows forever), reset to 1 per cycle in retail
	return safediv(soulsW,cast(float)si(ai.stanceRecs[slot],4));
}
float nodeValueScore(B)(ref ShinyAI!B ai,ObjectState!B state,float f,int n){ // 0x48aee0 / retail twin 0x48db30
	auto node=&ai.nodes[n];
	auto w1=ai.betaRateManasourceWeights?0.4f:0.45f; // thaum 0x48af0c vs retail 0x48db5c
	auto w2=ai.betaRateManasourceWeights?0.35f:0.3f; // thaum 0x48af46 vs retail 0x48db96
	auto r=lerp(f,w1,densityGroups(ai,state,node.curPos,10.0f,280.0f));
	// probOr far band is 3620.0f in BOTH binaries (0x45624000 @ 0x48af22/0x48af5c and 0x48db72/0x48dbac); 2592.0f occurs in neither
	r=lerp(r,w2,probOr(ai,state,node.curPos,3,0x200,10.0f,3620.0f,n));
	r=lerp(r,0.5f,probOr(ai,state,node.curPos,0,0x200,10.0f,3620.0f,n));
	return r;
}

// ---- task replans ----

void replanTasks(B)(ref ShinyAI!B ai,ObjectState!B state){ // 0x485260
	import frameprof;
	foreach(ref task; ai.tasks){
		final switch(cast(TaskKind)task.kind) with(TaskKind){
			case capture:
				frameprof.beginReplanPhase("capture");
				replanCapture(ai,state,task);
				frameprof.endReplanPhase("capture");
				break;
			case guard:
				frameprof.beginReplanPhase("guard");
				replanGuard(ai,state,task);
				frameprof.endReplanPhase("guard");
				break;
			case idle:
				frameprof.beginReplanPhase("idle");
				replanIdle(ai,state,task);
				frameprof.endReplanPhase("idle");
				break;
		}
	}
}
void replanCapture(B)(ref ShinyAI!B ai,ObjectState!B state,ref AITask!B task){ // 0x48afa0
	import frameprof;
	clearClaimed(ai,task);
	// retail 0x48dc04: divisor A = own+ally manaliths ([statArray+0x40]+[+0x14]); thaum 0x48afb4: own only
	auto A=si(ai.stanceRecs[0],5)+(ai.betaCaptureTerritory?0:si(ai.stanceRecs[1],5)), Bv=si(ai.stanceRecs[3],5), E=ai.neutralManafounts;
	float f1, f2;
	if(A!=0&&cast(float)safediv(cast(double)(Bv+1),cast(double)A)>=1.0f){
		f1=1.0f;
		f2=cast(float)safediv(cast(double)Bv,cast(double)E); // fidiv: E==0 -> inf
	}else if(E==0){
		f1=1.0f; f2=0.0f;
	}else{
		f1=cast(float)(1.0-safediv(cast(double)A,cast(double)E)); // fsubr
		f2=cast(float)safediv(cast(double)Bv,cast(double)(Bv+A));
	}
	static immutable int[2] cats=[2,3];
	foreach(edi;cats){
		for(int n=ai.catHead[edi];n;n=ai.nodes[n].catN){
			auto node=&ai.nodes[n];
			if(!(node.flags&0x100)) continue;
			uint flags; float s1; float s2;
			if(node.status&0x8000){
				flags=ai.betaUnbuiltCaptureReq?3:2; // thaum 0x48b0a4 = 3; retail 0x48dcf7 = 2 (wizard status bit1 alone satisfies -> wizard-only capture claims when no aggressive creature is claimable)
				frameprof.beginReplanPhase("nvs");
				s1=nodeValueScore(ai,state,f1,n);
				frameprof.endReplanPhase("nvs");
				s2=cast(float)((1.0-cast(double)ai.aggression)*0.8+0.2);
			}else if(edi==3&&(node.flags&0x20)&&(node.status&0x4000||((node.status&0x40000)&&!(node.flags&0x200)))){
				// retail 0x48dd43: no own/ally structure support (0x488d70 score 0) -> reject while own+ally manaliths exist (jg on A), else proceed anyway
				if(!ai.betaCaptureTerritory&&territorialScore!B(ai,state,node.curPos,n)==0.0f&&A>0) continue;
				flags=1;
				frameprof.beginReplanPhase("nvs");
				s1=cast(float)(cast(double)nodeValueScore(ai,state,f2>f1?f2:f1,n)*0.99)*ai.aggression;
				frameprof.endReplanPhase("nvs");
				s2=cast(float)((1.0-cast(double)ai.aggression)*0.9+0.1);
			}else if(edi==3&&(node.flags&0x10)&&(node.status&0x08)){
				s1=(desecrationOngoing!B(state,node.id)?1.0f:probOr(ai,state,node.curPos,0,0x20,10.0f,180.0f,n))*ai.aggression; // 0x48b185: 'ucas' attach overwrites s1 with 1.0f before the aggression scale
				flags=3;
				s2=cast(float)((1.0-cast(double)ai.aggression)*0.8+0.2);
			}else if(node.flags&0x200){
				// retail 0x48de5d: no own/ally structure support (0x488d70 score 0) -> reject unconditionally, before the 'sacu' check
				if(!ai.betaCaptureTerritory&&territorialScore!B(ai,state,node.curPos,n)==0.0f) continue;
				if(desecrationOngoing!B(state,node.id)){ // 0x48b1b8: 'ucas' attach -> s1=0.4f (0x4bba30), s2=1.0f-ag (fsub f32), flags=1
					s1=0.4f;
					s2=1.0f-ai.aggression;
					flags=1;
				}else{
					auto t=2.0f*(sf(ai.stanceRecs[3],6)-0.3f);
					if(t<0.0f) t=0.0f;
					flags=9;
					auto m=1.0-cast(double)ai.aggression;
					s2=cast(float)(m<0.4?0.4:m); // max(1-ag, 0.4d)
					s1=ai.aggression*ai.aggression*t;
				}
			}else continue;
			auto ri=allocRecord(ai,task);
			recordSetup(ai,state,ri,n,2);
			ai.records[ri].reqStatus=flags;
			if(hasAcc(ai,n)) combine(ai.records[ri].targetAcc,1.0f,node.acc,1.0f);
			frameprof.beginReplanPhase("infl");
			auto s3=1.0f-influenceGroups(ai,state,3,ai.records[ri].anchor,10.0f,140.0f,&ai.records[ri].targetAcc);
			frameprof.endReplanPhase("infl");
			auto score=lerp(s1,s2,s3);
			if(score==0.0f){ recordRelease(ai,ri); freePush(ai,task,ri); }
			else{ ai.records[ri].score=score; sortedInsert(ai,task,ri); }
		}
	}
	// 0x48b3e0/0x48e0cb tail: decay claimed scores by sorted position (0.5^i), then normalize by the decayed sum (rec.score feeds 'ndrg' target scoring 0x489a20)
	double capF=1.0, capSum=0.0; // f/sum stay on the fpu stack in the binaries; 0.5^i exact
	for(int r=task.claimedHead;r;r=ai.records[r].claimedN){
		auto rec=&ai.records[r];
		rec.score=cast(float)(cast(double)rec.score*capF); // fmul st(2) (extended); f32 store (exact power-of-two scale)
		capF*=0.5; // fmul dbl(0.5)
		capSum+=cast(double)rec.score; // fadd the STORED f32 value, extended accumulation
	}
	normalizeScores(ai,task,cast(float)capSum); // fstp f32; 0x48a6f0/0x48d440
}
void replanGuard(B)(ref ShinyAI!B ai,ObjectState!B state,ref AITask!B task){ // 0x48a8f0
	import frameprof;
	clearClaimed(ai,task);
	float total=0.0f;
	for(int n=ai.catHead[0];n;n=ai.nodes[n].catN){
		auto node=&ai.nodes[n];
		float score;
		if(node.status&0xc){
			score=nodeValue6c(ai,n)*ai.aggression*0.6f+0.4f;
		}else{
			if(!(node.flags&0x20)||!(node.status&0x1000)) continue;
			if(node.flags&0x200){ // 0x48a94b: altar with 'ucas' attach -> guard score 1.0f; quiet altar -> no record
				if(!desecrationOngoing!B(state,node.id)) continue;
				score=1.0f;
			}else{
				auto s=lerp(0.4f,0.5f,probOr(ai,state,node.curPos,0,0x200,10.0f,3620.0f,n)); // 0x48a967/0x48d5d7: 0x45624000 (2592.0f occurs in neither binary)
				total=lerp(s,0.2f,probOr(ai,state,node.curPos,3,0x200,10.0f,3620.0f,n)); // 0x48a9a4/0x48d614: 0x45624000; thaum quirk: overwrites the accumulator mid-loop
				score=lerp(s,0.2f,densityGroups(ai,state,node.curPos,10.0f,160.0f));
			}
		}
		auto ri=allocRecord(ai,task);
		recordSetup(ai,state,ri,n,0);
		frameprof.beginReplanPhase("infl");
		auto s3=influenceGroups(ai,state,3,ai.records[ri].anchor,10.0f,3620.0f,&ai.records[ri].targetAcc); // 0x48ab07/0x48d777: 0x45624000
		frameprof.endReplanPhase("infl");
		auto fin=lerp(score,0.6f,s3);
		if(fin==0.0f){ recordRelease(ai,ri); freePush(ai,task,ri); }
		else{
			ai.records[ri].score=fin;
			divide(ai.records[ri].targetAcc,0.0f); // thaum calls divide with w=0 (no-op), ported as-is
			sortedInsert(ai,task,ri);
			total+=fin;
		}
	}
	normalizeScores(ai,task,total);
}
void replanIdle(B)(ref ShinyAI!B ai,ObjectState!B state,ref AITask!B task){ // 0x48b6d0
	clearClaimed(ai,task);
	auto ri=allocRecord(ai,task);
	recordSetup(ai,state,ri,0,0); // anchorless record, score 0.0
	sortedInsert(ai,task,ri);
}

// ---- claim pass ----

void claimPass(B)(ref ShinyAI!B ai,ObjectState!B state){ // 0x484c70
	int tempHead=0, tempTail=0;
	for(int n=ai.fam1Head[0];n;n=ai.nodes[n].famN){ // temp list of claimable own creatures (recP/recN links)
		if(!claimable(ai,state,n)) continue;
		auto node=&ai.nodes[n];
		node.recN=0;
		if(tempTail) ai.nodes[tempTail].recN=n; else tempHead=n;
		node.recP=tempTail;
		tempTail=n;
	}
	foreach(ref task; ai.tasks){ // thaum task list order: capture, guard, idle
		final switch(cast(TaskKind)task.kind) with(TaskKind){
			case capture: claimCapture(ai,state,task,tempHead,tempTail); break;
			case guard: claimGuard(ai,state,task,tempHead,tempTail); break;
			case idle: claimIdle(ai,state,task,tempHead,tempTail); break;
		}
	}
	// thaum debug-asserts the temp list is empty here
}
float claimCapture(B)(ref ShinyAI!B ai,ObjectState!B state,ref AITask!B task,ref int tempHead,ref int tempTail){ // 0x48b450
	foreach(i;0..state.obj.opaqueObjects.effects.sacDocCastings.length){ // 0x48b4a8: own wizard has a 'ucas' attach (ntt+0xb88) -> freeze capture claiming
		auto c=&state.obj.opaqueObjects.effects.sacDocCastings[i];
		if(c.type==RitualType.desecrate&&c.side==ai.side) return 0.0f;
	}
	auto threshold=cast(float)si(ai.stanceRecs[0],2)*sf(ai.stanceRecs[3],6)*0.9f*ai.aggression; // thaum 0x48b4c9: fild rec0+0x8 * [rec0+0xa0]=rec3+0x1c (u[0], p0-souls ratio, AI+0x25c) * 0.9f * aggression
	RaterAcc acc; acc.clear();
	uint statusOR=0; int count=0;
	for(int n=tempHead;n;n=ai.nodes[n].recN){
		if(!ai.betaCaptureAggGuardians&&isGuardianEnt!B(state,ai.nodes[n].id)) continue; // retail 0x48e21b: guardian-bound ([ntt+0x5c8]!=0) excluded from statusOR/count/membersAcc (thaum 0x48b50a aggregates all)
		statusOR|=ai.nodes[n].status;
		count++;
		combine(acc,cast(float)count,ai.nodes[n].acc,1.0f); // exploding-weight quirk
	}
	int found=0;
	for(int r=task.claimedHead;r;r=ai.records[r].claimedN){
		if((ai.records[r].reqStatus&statusOR)!=ai.records[r].reqStatus) continue;
		if(!(rateWithBase(acc,ai.records[r].targetAcc)<0.0f)){ found=r; break; }
	}
	if(found==0) return 0.0f;
	float total=0.0f;
	for(int n=tempHead;n;){
		auto nn=ai.nodes[n].recN; // preloaded: claim unlinks
		if(total>threshold) break;
		if(!isGuardianEnt!B(state,ai.nodes[n].id)&&ai.nodes[n].status&9) total+=cast(float)claim(ai,state,task,found,tempHead,tempTail,n); // thaum skips ntt+0x5b4!=0 (guardian-spell bound)
		n=nn;
	}
	return total;
}
float claimGuard(B)(ref ShinyAI!B ai,ObjectState!B state,ref AITask!B task,ref int tempHead,ref int tempTail){ // 0x48ac00
	auto threshold=cast(float)si(ai.stanceRecs[0],2);
	float total=0.0f;
	for(int r=task.claimedHead;r;r=ai.records[r].claimedN){
		auto rec=&ai.records[r];
		float claimedThis=0.0f;
		// pass 1: pre-claim creatures guardian-bound to the target structure (ntt+0x5b4==structure ntt); amounts go to BOTH claimedThis and total (thaum double-count quirk)
		if(rec.target&&ai.nodes[rec.target].kind==NodeKind.str){ // rec+0x8.vtbl[14]() (GetStructure) non-null
			auto tb=ai.nodes[rec.target].id;
			for(int n=tempHead;n;){
				auto nn=ai.nodes[n].recN; // preloaded: claim unlinks
				if(state.buildingById!((ref b,ObjectState!B state,int id){ foreach(j;0..b.guardianIds.length) if(b.guardianIds[j]==id) return true; return false; },()=>false)(tb,state,ai.nodes[n].id)){
					auto v=cast(float)claim(ai,state,task,r,tempHead,tempTail,n);
					claimedThis+=v; total+=v;
				}
				n=nn;
			}
		}
		if(total>threshold) continue; // thaum 0x48acc0: total>threshold skips the while-loop AND the total+=claimedThis below, but keeps processing the remaining records
		while(claimedThis+0.5f<=rec.score*threshold){
			int best=0; float bestVal=0.0f;
			for(int n=tempHead;n;n=ai.nodes[n].recN){
				if(n==rec.target||!(ai.nodes[n].status&(ai.betaGuardWizardExclude?0x1u:0x3u))) continue; // GUARD::Assign member mask: thaum 0x48ad24 = 1 (wizard excluded) vs retail 0x48d994 = 3 (wizard 0x2000e joins, becomes leader, members follow)
				if(isGuardianEnt!B(state,ai.nodes[n].id)) continue; // thaum 0x48ad2e: skips ntt+0x5b4!=0 (guardian-spell bound)
				auto d=ai.nodes[n].extrapPos-rec.anchor;
				auto dist=sqrt(d.x*d.x+d.y*d.y+d.z*d.z);
				float w;
				if(dist<=40.0f) w=1.0f;
				else if(dist>=3620.0f) continue;
				else{
					w=(3620.0f-dist)*0.0002793296007439494f; // 0x4bce60
					if(w==0.0f) continue;
				}
				auto w2=w*w;
				auto val=rateWithBase(ai.nodes[n].acc,rec.targetAcc);
				if(val<=0.0f) val=safediv(val,w2); else val=val*w2;
				if(best==0||bestVal<val){ bestVal=val; best=n; }
			}
			if(best==0) break;
			claimedThis+=cast(float)claim(ai,state,task,r,tempHead,tempTail,best);
		}
		total+=claimedThis;
	}
	return total;
}
float claimIdle(B)(ref ShinyAI!B ai,ObjectState!B state,ref AITask!B task,ref int tempHead,ref int tempTail){ // 0x48b8b0
	if(task.claimedHead==0) return 0.0f;
	auto r=task.claimedHead;
	float total=0.0f;
	for(int n=tempHead;n;){
		auto nn=ai.nodes[n].recN;
		claim(ai,state,task,r,tempHead,tempTail,n);
		total+=sortKey(ai,n); // node vtbl[7]
		n=nn;
	}
	return total;
}

// ---- order bridge ----

float distSq3(Vector3f a,Vector3f b){ auto x=a.x-b.x, y=a.y-b.y, z=a.z-b.z; return x*x+y*y+z*z; }

void issueOrder(B)(ref ShinyAI!B ai,ObjectState!B state,int n,int ostate,int target,Vector3f* pos,size_t line=__LINE__){ // thaum setOrder
	auto node=&ai.nodes[n];
	if(node.kind==NodeKind.cre||node.kind==NodeKind.str||node.kind==NodeKind.none){ // node vtbl[13]==0
		static if(shinyAILog) ailog("ORDFAIL ",ai.side," t",ai.schedTime," n",n,"(",node.kind,") @",line," ostate ",ostate,": inert kind");
		return;
	}
	state.movingObjectById!((ref o,ObjectState!B state){
		Order ord;
		if(target){
			auto tnode=&ai.nodes[target];
			if(!entExists!B(state,tnode.kind,tnode.id)){ // thaum always has a live target ntt
				static if(shinyAILog) ailog("ORDFAIL ",ai.side," t",ai.schedTime," n",n," @",line," ostate ",ostate,": target ",target," (",tnode.kind," id ",tnode.id,") dead");
				return;
			}
			ord.target=entOrderTarget!B(state,tnode.kind,tnode.id);
			if(ord.target.type==TargetType.none){
				static if(shinyAILog) ailog("ORDFAIL ",ai.side," t",ai.schedTime," n",n," @",line," ostate ",ostate,": target ",target," (",tnode.kind," id ",tnode.id,") no ordertarget");
				return;
			}
		}else if(pos) ord.target=positionTarget(*pos,state);
		else return;
		if(node.kind==NodeKind.wiz&&ostate==6){ // thaum 0x46e6e3: wizard ostate-6 orders are converted to ostate 7 in place (0x46e1a0); ostate-7 handler 0x46e539 is a plain move to the order's fixed position
			ord.target=positionTarget(pos?*pos:ai.nodes[target].curPos,state);
			ord.command=CommandType.move;
		}else switch(ostate){
			case 2: ord.command=CommandType.move; break;
			case 3: ord.command=target?CommandType.retreat:CommandType.guardArea; break; // thaum cmd 3/5 share handler 0x46e60a: move to live target pos, arrive at target ntt+0x2e4 + 10.0 (engine retreat matches)
			case 4: ord.command=CommandType.move; break;
			case 5: ord.command=target?CommandType.retreat:CommandType.move; break; // thaum capture/interact; no capture mechanic in sacengine (documented gap)
			case 6: ord.command=CommandType.attack; break;
			case 7: ord.command=CommandType.advance; break;
			case 34: // 0x22: brain-driven engage; guard approximation for creatures (documented gap), move for soul targets (thaum touch-collects by walking onto the soul; sacengine collects by proximity)
				ord.command=target?(ai.nodes[target].kind==NodeKind.cre?CommandType.move:CommandType.guard):CommandType.guardArea; break;
			default: return;
		}
		static if(shinyAILog){
			auto ok=order(o,ord,state,ai.side);
			ailog("ORDISS ",ai.side," t",ai.schedTime," n",n,"(",node.kind," id ",node.id,") @",line," ostate ",ostate," tgt ",target," pos ",pos is null?Vector3f.init:*pos," -> ",ord," accepted=",ok);
		}else order(o,ord,state,ai.side);
	},(){
		static if(shinyAILog) ailog("ORDFAIL ",ai.side," t",ai.schedTime," n",n," id ",node.id," @",line," ostate ",ostate,": entity gone");
	})(node.id,state);
}
void orderIfChanged(B)(ref ShinyAI!B ai,ObjectState!B state,int n,int ostate,int target,Vector3f* pos,size_t line=__LINE__){ // 0x4878c0
	// thaum compares against the ntt's live order (0x4878c0: 0x46e0f0 reads it); completed orders are retained
	// (see below), so re-issue only when the engine order popped and thaum would not have retained it
	auto node=&ai.nodes[n];
	static if(shinyAILog){
		auto live=state.movingObjectReadById!((ref cols,i,state)=>cols.creatureAIs[i].order,()=>Order.init)(node.id,state);
		ailog("ORDCHK ",ai.side," t",ai.schedTime," n",n,"(",node.kind," id ",node.id,") @",line," req(",ostate,",",target,",",pos is null?Vector3f.init:*pos,") cached(",node.ordState,",",node.ordTarget,",",node.ordPos,") live(",live.command,",",live.target,")");
	}
	if(node.ordState==ostate&&(target==0||node.ordTarget==target)&&(pos is null||node.ordPos==*pos)){
		// thaum retains completed orders (0x46ded0(queue,0) no-ops when order+0x24==0), so the live-order
		// compare in 0x4878c0 still matches after arrival and fixed-pos orders (ostates 4/7, handler
		// 0x46e539, arrival radius 0.5) are not re-issued while the requested pos equals the retained one;
		// ostates 2/0x22 force-pop (0x46ded0(queue,1)) and live-target orders (3/5) re-engage on target
		// movement, so those keep re-issuing once the engine order pops
		if((ostate==4||ostate==7)&&distSq3(node.curPos,node.ordPos)<=0.25f) return;
		if(state.movingObjectReadById!((ref cols,i,state)=>cols.creatureAIs[i].order.command!=CommandType.none,()=>true)(node.id,state)) return;
	}
	issueOrder(ai,state,n,ostate,target,pos,line);
	if(node.kind==NodeKind.wiz&&ostate==6){ // the converted order lives as ostate 7 (0x46e1a0), so 0x4878c0's compare and slot19's case table (0x487420) see 7, not the requested 6
		node.ordState=7;
		node.ordTarget=target; // 0x46e1a0 keeps the order's target ntt
		node.ordPos=pos?*pos:ai.nodes[target].curPos;
	}else{
		node.ordState=ostate;
		node.ordTarget=target;
		if(pos) node.ordPos=*pos;
	}
	// status 0x10000 maintenance: set iff state-5 order with capturable target structure (ntt vtbl[25]);
	// thaum clears it on every other issued order (or broken record->target chain)
	if(ostate==5&&node.record){
		auto t=ai.records[node.record].target;
		if(t&&ai.nodes[t].kind==NodeKind.str){ // thaum also tests target ntt+0x4&0x10 (str class bit)
			auto capturable=state.buildingById!((ref b,state)=>b.sacBuilding.isManafount&&b.side!=ai.side,()=>false)(ai.nodes[t].id,state);
			if(capturable) node.status|=0x10000; else node.status&=~0x10000;
		}else node.status&=~0x10000;
	}else node.status&=~0x10000;
}
int orderTargetRadius(B)(ref ShinyAI!B ai,ObjectState!B state,int n,int ostate,int target,float radius,size_t line=__LINE__){ // 0x487450
	auto node=&ai.nodes[n];
	if(radius>0.0f&&!(radius*radius<distSq3(node.curPos,ai.nodes[target].curPos))){ // within radius: hold current position
		static if(shinyAILog) ailog("ORDRADIUS ",ai.side," t",ai.schedTime," n",n," @",line," tgt ",target," radius ",radius,": in range -> hold");
		orderIfChanged(ai,state,n,ostate,0,&node.curPos,line);
		return 1;
	}
	static if(shinyAILog) ailog("ORDRADIUS ",ai.side," t",ai.schedTime," n",n," @",line," tgt ",target," radius ",radius,": chase");
	orderIfChanged(ai,state,n,ostate,target,null,line); // radius<=0 or out of range: chase target
	return 0;
}
int orderPosRadius(B)(ref ShinyAI!B ai,ObjectState!B state,int n,int ostate,Vector3f* pos,float radius,size_t line=__LINE__){ // 0x4874e0
	auto node=&ai.nodes[n];
	if(radius*radius<distSq3(node.curPos,*pos)){
		static if(shinyAILog) ailog("ORDRADIUS ",ai.side," t",ai.schedTime," n",n," @",line," pos ",*pos," radius ",radius,": out of range -> move");
		orderIfChanged(ai,state,n,ostate,0,pos,line);
		return 0;
	}
	static if(shinyAILog) ailog("ORDRADIUS ",ai.side," t",ai.schedTime," n",n," @",line," pos ",*pos," radius ",radius,": in range -> hold");
	orderIfChanged(ai,state,n,ostate,0,&node.curPos,line); // in range: hold current position
	return 1;
}
int orderInteract(B)(ref ShinyAI!B ai,ObjectState!B state,int n,Vector3f* pos,int target,float radius,size_t line=__LINE__){ // 0x487550
	auto node=&ai.nodes[n];
	if(radius*radius<distSq3(node.curPos,*pos)){ // too far: move to position first
		static if(shinyAILog) ailog("ORDINTERACT ",ai.side," t",ai.schedTime," n",n," @",line," pos ",*pos," tgt ",target," radius ",radius,": far -> move");
		orderIfChanged(ai,state,n,4,0,pos,line);
		return 0;
	}
	if(target&&ai.nodes[target].kind==NodeKind.str){ // thaum: targetNode+0x3c&0x20
		auto tnode=&ai.nodes[target];
		auto bflags=state.buildingById!((ref b,state)=>cast(uint)b.sacBuilding.flags,()=>0u)(tnode.id,state);
		if(!(bflags&0x80)) orderIfChanged(ai,state,n,5,target,null,line);
		else{
			// thaum ntt+0x448 = guardian count; approximation: building guardianIds
			auto numGuardians=state.buildingById!((ref b,state)=>cast(int)b.guardianIds.length,()=>0)(tnode.id,state);
			if(numGuardians<=1) orderIfChanged(ai,state,n,6,target,pos,line);
			else orderIfChanged(ai,state,n,7,0,pos,line);
		}
	}else orderIfChanged(ai,state,n,7,0,pos,line);
	return 1;
}
void nodeSlot19(B)(ref ShinyAI!B ai,ObjectState!B state,int n,int cmd,int ri,Vector3f* pos){ // node vtbl[19] 0x4873b0
	final switch(ai.nodes[n].kind) with(NodeKind){
		case wiz,maho,t4o:
			auto cs=ai.nodes[n].ordState; // case table 0x487420: states 2,3,6,34 -> brain
			static if(shinyAILog) ailog("SLOT19 ",ai.side," t",ai.schedTime," n",n,"(",ai.nodes[n].kind," id ",ai.nodes[n].id,") cmd ",cmd," ri ",ri," cachedOrdState ",cs,cs==2||cs==3||cs==6||cs==34?" -> brain":" -> move-to-center");
			if(cs==2||cs==3||cs==6||cs==34) nodeBrain(ai,state,n,cmd,ri);
			else orderPosRadius(ai,state,n,2,pos,5.0f);
			break;
		case str,cre,none: break; // inert
	}
}
void nodeBrain(B)(ref ShinyAI!B ai,ObjectState!B state,int n,int cmd,int ri){ // node vtbl[3]
	final switch(ai.nodes[n].kind) with(NodeKind){
		case t4o: t4oBrain(ai,state,n,cmd,ri); break;
		case maho: mahoBrain(ai,state,n,cmd,ri); break;
		case wiz: wizBrain(ai,state,n,cmd,ri); break;
		case str,cre,none: break; // 0x486cd0 (ret 1)
	}
}
bool nodeIsRespawning(B)(ref ShinyAI!B ai,ObjectState!B state,int n){ // CREATURE::IsRespawning: ntt+0x5ec.+0x30&0x40000
	auto node=&ai.nodes[n];
	final switch(node.kind) with(NodeKind){
		case wiz,t4o,maho,cre: return entGhost!B(state,node.id);
		case str,none: return false;
	}
}
int nodeSlot22(B)(ref ShinyAI!B ai,ObjectState!B state,int n){ // node vtbl[22]: t4o/maho 0x4871e0; wiz 0x48df30; cre/str 0x486bd0 (=0, minManaCost stays 0)
	auto node=&ai.nodes[n];
	if(node.kind==NodeKind.wiz&&node.castQueue.length){
		// retail 0x490ac0: GetTag(ntt+0xb9c,0,0)=='sacu' -> skip to the base implementation (no queue-head boost while sacrificing); thaum 0x48df30 has no gate
		if(!ai.betaMinManaSacu&&wizardSacrificing!B(ai,state,node.id)) return ftol(node.minManaCost);
		auto e=&node.castQueue[0];
		if(e.provider&&e.provider.type==SpellType.creature){ // queue head provider+0xc==2 (creature spell)
			auto souls=state.movingObjectReadById!((ref cols,i,ObjectState!B state){
				if(auto wiz=state.getWizardForSide(cols.sides[i])) return wiz.souls;
				return 0;
			},()=>0)(node.id,state);
			if(souls>e.provider.soulCost) return 5*ftol(e.provider.manaCost)/4; // strict >; lea*5 + sdiv4
		}
	}
	return ftol(node.minManaCost);
}
bool sameRegionPos(B)(ObjectState!B state,Vector3f a,Vector3f b){ // 0x470700 region map; approximation via pathfinder components
	auto ra=state.pathFinder.getComponentId(a,state), rb=state.pathFinder.getComponentId(b,state);
	return ra>=0&&rb>=0&&ra==rb;
}
bool findBestCaptureTarget(B)(ref ShinyAI!B ai,ObjectState!B state,Vector3f* pos,float radius,int* outNode,float* outRadius){ // 0x485a40 ("Mana")
	*outNode=0;
	float best=0.0f, br=0.0f; // br only read when *outNode!=0 (thaum leaves it uninitialized)
	// retail 0x4885e0 walks own+ally mana lists (mask 3: slots 0+1); thaum walks own only (slot 0)
	static immutable int[2] capSlots=[0,1];
	foreach(capSlot;ai.betaManaSourceOwnOnly?capSlots[0..1]:capSlots[0..2])
	for(int m=ai.catHead[capSlot];m;m=ai.nodes[m].catN){ // chain node+0x50
		auto node=&ai.nodes[m];
		if(!(node.status&0x1000)) continue;
		if(!sameRegionPos!B(state,*pos,node.curPos)) continue;
		auto d=sqrt(distSq3(*pos,node.curPos));
		float w;
		if(d<=1.0f) w=1.0f;
		else if(!(d<radius)) w=0.0f;
		else w=safediv(radius-d,radius-1.0f);
		if(node.flags&0x20){ // structure: ready unbuilt manafount, weight by souls (ntt+0x49c)
			w*=state.buildingById!((ref b,state){
				auto bfl=cast(uint)b.sacBuilding.flags;
				// ntt+0x474==0 && ntt+0x440==0 (always true, see updateStr) && ntt+0x43c==1.0 (progress always 1.0f in sacengine) && ntt+0x47c&0xc00
				if(b.top==0&&(bfl&0xc00)!=0) return cast(float)ftol(cast(double)b.sacBuilding.bldg.unknown1[3]*36408.88888888889);
				return 0.0f;
			},()=>0.0f)(node.id,state);
		}else w*=1000.0f; // active manahoar (maho status 0x1000)
		if(best<w){ best=w; *outNode=m; br=node.flags&0x20?50.0f:40.0f; }
	}
	if(*outNode!=0&&outRadius) *outRadius=br;
	return *outNode!=0;
}
int autoCapture(B)(ref ShinyAI!B ai,ObjectState!B state,int n){ // 0x487600
	auto node=&ai.nodes[n];
	auto p=outPair5(ai,state,n);
	if(p[1]==0) return 0;
	if(p[0]>nodeSlot22(ai,state,n)&&!nodeIsRespawning(ai,state,n)) return 0;
	int bn=0; float br=0.0f;
	if(!findBestCaptureTarget(ai,state,&node.curPos,3620.0f,&bn,&br)) return 0; // 0x487642: thaum passes 0x45624000 = 3620.0f
	static if(shinyAILog) ailog("AUTOCAP ",ai.side," t",ai.schedTime," n",n," bn ",bn," br ",br," outOfRange ",br*br<distSq3(node.curPos,ai.nodes[bn].curPos));
	if(br*br<distSq3(node.curPos,ai.nodes[bn].curPos)) orderIfChanged(ai,state,n,5,bn,null);
	return 1;
}
int t4oBrain(B)(ref ShinyAI!B ai,ObjectState!B state,int n,int cmd,int ri){ // 0x4876d0
	static if(shinyAILog) ailog("T4OBRAIN ",ai.side," t",ai.schedTime," n",n,"(",ai.nodes[n].kind," id ",ai.nodes[n].id,") cmd ",cmd," ri ",ri);
	if(autoCapture(ai,state,n)!=0) return 1;
	if(ri==0) return 0;
	auto rec=&ai.records[ri];
	switch(cmd){
		case 0: return 1;
		case 1: orderTargetRadius(ai,state,n,5,rec.target,0.0f); return 1;
		case 2:
			// thaum: flt((1.0-node+0x6c)*160.0); t4o node+0x6c is always 0.0f
			orderInteract(ai,state,n,&rec.anchor,rec.target,cast(float)((1.0-nodeValue6c(ai,n))*160.0));
			return 1;
		default: return 1; // 0x486cd0
	}
}
int mahoBrain(B)(ref ShinyAI!B ai,ObjectState!B state,int n,int cmd,int ri){ // 0x487ae0
	auto node=&ai.nodes[n];
	int bestG=0;
	float bestV=0.0f;
	for(int g=ai.grp4Head[0];g;g=ai.groups4[g].gN){ // slot4 cat0 groups
		auto grp=&ai.groups4[g];
		auto v=cast(float)(2*grp.maxManaSum-grp.manaSum);
		if(grp.statusOR&8) v+=v;
		auto d=sqrt(distSq3(node.extrapPos,grp.predicted));
		// retail 0x48a8f0: cutoff 3620.0f, scale 0.00027700831f; thaum 0x487ae0: 256.0f, 0.0040650405f
		immutable mcut=ai.betaManahoarRadius?256.0f:3620.0f, mscale=ai.betaManahoarRadius?0.0040650405f:0.00027700831f;
		float w;
		if(d<=10.0f) w=1.0f;
		else if(!(d<mcut)) w=0.0f;
		else w=(mcut-d)*mscale;
		v*=w;
		if(grp.readyCount>1) v=safediv(v,cast(float)grp.readyCount);
		if(bestV<v){ bestV=v; bestG=g; }
	}
	if(bestG){
		int bestM=0;
		int best2=0;
		for(int m=ai.groups4[bestG].memberHead;m;m=ai.nodes[m].grpN){ // members with status!=0 only
			if(ai.nodes[m].status==0) continue;
			auto p=outPair5(ai,state,m);
			auto v2=2*p[1]-p[0];
			if(best2<v2){ best2=v2; bestM=m; }
		}
		if(bestM){
			orderIfChanged(ai,state,n,3,bestM,null);
			return 1;
		}
	}
	return t4oBrain(ai,state,n,cmd,ri);
}

// ---- wizard: spell lists (thaum wiz slot0 dirty block) ----

void wizSpellRebuild(B)(ref ShinyAI!B ai,ObjectState!B state,int n){ // 0x48c8d0 summons, 0x48cb80 spell accs, 0x48ca50 cached spells
	auto node=&ai.nodes[n];
	node.summons.length=0;
	node.spellAccs.length=0;
	node.manahoarSpell=null; node.shrineSpell=null; node.convertSpell=null; node.desecrateSpell=null;
	state.movingObjectReadById!((ref cols,i,ObjectState!B state){
		if(auto wiz=state.getWizardForSide(cols.sides[i])){
			foreach(entry;wiz.getSpells()){
				auto s=entry.spell;
				if(s is null) continue;
				if(entry.level>wiz.level) continue; // thaum spellbook only holds spells granted for reached levels (WIZDEF_GiveSpellsForLevel 0x450f50: per level-up, word[s_spell+0x30]/25==level; NTT book synced by WIZARD::AddSpell 0x4811e0/ExperienceChanged 0x4829c0); sacengine books hold the whole loadout, so filter to entry.level<=wiz.level
				static if(shinyAILog) ailog("WIZSPELL ",ai.side," n",n," tag ",s.tag[]," type ",cast(int)s.type," flags ",cast(uint)s.flags," range ",s.range," mana ",s.manaCost," souls ",s.soulCost," lvl ",entry.level);
				if(s.type==SpellType.creature&&s.tag!="oham") // 0x48c8d0: creature spells except the manahoar
					if(auto acc=tagAcc(ai,s.tag)) node.summons~=SummonEntry!B(s.tag,*acc,s);
				if(wantsSpellAcc!B(s)) node.spellAccs~=SpellAcc!B(s,ratingFn!B(s)); // 0x48cb80
				if(s.tag=="oham") node.manahoarSpell=s; // 0x48ca50 cached spells
				if(s.tag=="ccas") node.convertSpell=s;
				if(s.tag=="ucas") node.desecrateSpell=s;
				// FindManalithSpell 0x48cc30: first match wins; thaum tests BldgHeader.flags bits 0x400|0x4000 of the god-0 BLDG def ([s_spell_building+0x48]) (not strc.flags, no spell has them there), on real data the match is always the manalith = first structure spell with onlyManafounts
				if(node.shrineSpell is null&&s.type==SpellType.structure&&(s.flags&SpelFlags.onlyManafounts)) node.shrineSpell=s;
			}
		}
	},(){})(node.id,state);
	static if(shinyAILog) ailog("WIZCACHED ",ai.side," n",n," maho ",node.manahoarSpell is null?"null":node.manahoarSpell.tag[]," shrine ",node.shrineSpell is null?"null":node.shrineSpell.tag[]," convert ",node.convertSpell is null?"null":node.convertSpell.tag[]," desecrate ",node.desecrateSpell is null?"null":node.desecrateSpell.tag[]);
}

// ---- wizard: cast queue (thaum 0x48cd40..0x48d080) ----

int enqueueCast(B)(ref ShinyAI!B ai,int n,float score,int target,SacSpell!B provider,float range,int obj0,ubyte flag){ // 0x48ced0 (dedup by spell tag, refill) + 0x48ce40 (sorted insert)
	auto node=&ai.nodes[n];
	CastEntry!B ce=CastEntry!B(flag,score,target,obj0?obj0:target,range,provider);
	size_t idx=size_t.max;
	if(provider) foreach(i;0..node.castQueue.length) // 0x48ce00: dedup replaces the existing entry with the same spell tag
		if(node.castQueue[i].provider&&node.castQueue[i].provider.tag==provider.tag){ idx=i; break; }
	if(idx!=size_t.max){
		for(size_t j=idx;j+1<node.castQueue.length;j++) node.castQueue[j]=node.castQueue[j+1];
		node.castQueue.length=node.castQueue.length-1;
	}
	size_t j=0; // insert: forced first, then descending score, ties go before existing entries
	for(;j<node.castQueue.length;j++){
		auto q=&node.castQueue[j];
		auto qF=!!(q.flag&1), nF=!!(ce.flag&1);
		if(qF!=nF){ if(nF) break; }
		else if(q.score<=ce.score) break;
	}
	static if(shinyAILog) ailog("ENQ ",ai.side," t",ai.schedTime," n",n," score ",score," flag ",flag," tgt ",target," obj ",ce.obj," range ",range," spell ",provider is null?"null":to!string(provider.tag)," at ",j,"/",node.castQueue.length);
	node.castQueue~=CastEntry!B.init;
	for(size_t k=node.castQueue.length-1;k>j;k--) node.castQueue[k]=node.castQueue[k-1];
	node.castQueue[j]=ce;
	return cast(int)j;
}

// rater2 per-spell-acc virtuals
bool spellAccAccepts(B)(ref SpellAcc!B acc,uint mask){ // rater2 vtbl[0] 0x489600
	// thaum also rejects when the spellbook item's +0x8&2 (disabled) is set; sacengine equivalent: wizSpellRebuild only builds accs for entry.level<=wiz.level spells (same predicate, applied at rebuild time)
	auto spel=acc.spell.spel;
	return ((cast(uint)spel.unknown16|cast(uint)spel.flags1<<16)&mask)!=0;
}
uint nttTypeBits(NodeKind kind){ // ntt+0x4 type bits
	final switch(kind) with(NodeKind){
		case wiz: return 1;
		case cre: return 2;
		case t4o,maho: return 4;
		case str: return 0x10;
		case none: return 0;
	}
}
Tuple!(int,int) healthPair(B)(ObjectState!B state,NodeKind kind,int id){ // ntt words +0x8ba (cur), +0x8ea (max)
	final switch(kind) with(NodeKind){
		case t4o,maho,wiz: return state.movingObjectReadById!((ref cols,i,state)=>tuple(ftol(cols.creatureStatss[i].health),ftol(cols.creatureStatss[i].maxHealth)),()=>tuple(0,0))(id,state);
		case str: return state.buildingById!((ref b)=>tuple(ftol(b.health),b.sacBuilding.maxHealth),()=>tuple(0,0))(id);
		case cre,none: return tuple(0,0);
	}
}
Tuple!(uint,uint) spellbookOR(B)(ObjectState!B state,int id){ // 0x487250: OR of s_spell+0x60/+0x28 over the creature spellbook
	return state.movingObjectReadById!((ref cols,i,state){
		uint out1=0,out2=0;
		foreach(ab;cols.sacObject.abilities){
			if(ab is null||!ab.spel) continue;
			out1|=cast(uint)ab.spel.unknown16|cast(uint)ab.spel.flags1<<16;
			out2|=cast(uint)ab.spel.flags;
		}
		return tuple(out1,out2);
	},()=>tuple(0u,0u))(id,state);
}
bool hasActiveHeal(B)(ObjectState!B state,int id){ // 0x46a840(ntt,'LAEH') approximation: an active heal effect
	foreach(i;0..state.obj.opaqueObjects.effects.heals.length) if(state.obj.opaqueObjects.effects.heals[i].creature==id) return true;
	return false;
}
bool hasActiveProtect(B)(ObjectState!B state,int id){ // 0x46a840(ntt,'TORP') approximation: an active protector
	foreach(i;0..state.obj.opaqueObjects.effects.protectors.length) if(state.obj.opaqueObjects.effects.protectors[i].id==id) return true;
	return false;
}
// NTT::QuerySpellEffect 0x46a840 approximation (thaum keeps a per-ntt (tag,ntt) table at +0x370; sacengine tracks effects in typed lists): known tags only
bool querySpellEffect(B)(ObjectState!B state,int id,char[4] tag){
	if(tag[]=="LAEH") return hasActiveHeal!B(state,id);
	if(tag[]=="TORP") return hasActiveProtect!B(state,id);
	if(tag[]=="sacu") return desecrationOngoing!B(state,id);
	if(tag[]=="ccas") return convertMask!B(state,id)!=0;
	return false; // unknown tags: no sacengine effect table to query (documented gap)
}
// CREATURE::IsFriendly 0x45e9d0 (caster = node n): base NTT::IsFriendly 0x46c550 = own side or either-direction ally
// (thaum additionally vetoes on: target +0x234&0x2000 = target counts as hostile regardless of sides (suspected blind rage 'egar'; setter is data-driven via the
// attachment system, not statically confirmed); caster +0xb24&0x4000 = consult the caster's personal side mask +0xb3c (accumulates event-source sides at 0x47252e, shared
// between nearby creatures at 0x455228 - a personal disposition system, cf. charmNeutralCreatures; sacengine charm just changes side, state.d:21691) - no sacengine equivalents, documented gaps)
bool ccFriendly(B)(ObjectState!B state,int cside,NodeKind tkind,int tid){
	if(cside<0) return false; // caster entity gone between scan and rating (thaum always has a live ntt)
	auto rel=relation!B(state,cside,entSide!B(state,tkind,tid));
	return rel==0||rel==1;
}
// GRIMOIRE::CanCastSpellOn 0x4517b0 (CheckSpellValid 0x48c330 calls it only with non-null caster/target; caster = node n)
bool canCastSpellOn(B)(ref ShinyAI!B ai,ObjectState!B state,int n,int target,SacSpell!B spell){
	auto tnode=&ai.nodes[target];
	auto spel=spell.spel;
	auto flags=cast(uint)spel.flags;
	if(flags==0) return true;
	// (thaum's internal type-mask gate 0x4517e4 can never reject here: CheckSpellValid's 0x781f mask check already passed and ntt types only have bits 0x17)
	if(flags&0x1f){ // 0x4517de: without target-type bits every ntt gate below is skipped
		if(spell.type==SpellType.spell){ // s_spell+0xc==4: 4 exclusion tags at Spel+0x2c..0x3b, first zero slot ends the scan
			auto tags=spel.exclusionTags;
			foreach(tag;tags){
				if(*cast(uint*)&tag==0) break;
				if(querySpellEffect!B(state,tnode.id,tag)) return false;
			}
		}
		if(flags&SpelFlags.onlyManafounts){ // primary unoccupied manafount (thaum also tests ntt+0x440==0; sacengine folds sub-components, see shouldTrack)
			if(tnode.kind!=NodeKind.str) return false;
			if(!state.buildingById!((ref b)=>(cast(uint)b.sacBuilding.flags&0x10)!=0&&b.top==0,()=>false)(tnode.id)) return false;
		}
		if(flags&SpelFlags.disallowFlying){ // reject targets >2.0 above terrain (thaum escapes grounded ntts (+0x234&2, set by ApplyMovement's terrain clamp); post-clamp altitude is ~0 for those, so the altitude test alone is equivalent on live data)
			if(tnode.kind.among(NodeKind.wiz,NodeKind.t4o,NodeKind.maho))
				if(state.movingObjectReadById!((ref cols,i,state)=>cols.positions[i].z-state.getHeight(cols.positions[i])>2.0f,()=>false)(tnode.id,state)) return false;
		}
		if(flags&SpelFlags.disallowHero){ // +0xb24&0x40 hero bit, tested on types 1|4; wizards included (testing type 1 would be dead code otherwise)
			if(tnode.kind.among(NodeKind.wiz,NodeKind.t4o,NodeKind.maho))
				if(state.movingObjectReadById!((ref cols,i,state)=>cols.sacObject.isWizard||cols.sacObject.isHero,()=>false)(tnode.id,state)) return false;
		}
		if(flags&SpelFlags.onlyCreatures){ // target NTT::CanSelect vtbl[0x48]: only CREATURE overrides nonzero (!statsFlags&0x100 && !stateFlags&0x2000), NTT/WIZARD/souls/buildings are always 0
			if(!tnode.kind.among(NodeKind.t4o,NodeKind.maho)||entDead!B(state,tnode.id)) return false; // (+0xb24&0x100 cannotSelect template flag: no sacengine equivalent, documented gap; dead nodes are untracked anyway)
		}
		auto cside=entSide!B(state,ai.nodes[n].kind,ai.nodes[n].id);
		if(flags&(SpelFlags.onlyOwned|SpelFlags.onlyAlly)){ // 0x81000
			if(tnode.kind==NodeKind.cre){ // soul: touch-collectible by the caster's side (+0x430&0xc0000000 = being collected/reabsorbed rejects)
				if(state.soulById!((ref s,state)=>s.state.among(SoulState.collecting,SoulState.reviving),()=>false)(tnode.id,state)) return false;
				if(cside<0||!(pickupMask!B(state,tnode.id)&(1u<<cside))) return false; // thaum rejects on null caster side here
			}else if(flags&SpelFlags.onlyOwned){ // same side record
				if(cside<0||entSide!B(state,tnode.kind,tnode.id)!=cside) return false;
			}else{ // onlyAlly: CREATURE::IsFriendly
				if(!ccFriendly!B(state,cside,tnode.kind,tnode.id)) return false;
			}
			if(tnode.kind==NodeKind.str&&!state.buildingById!((ref b)=>(cast(uint)b.sacBuilding.flags&0x55a7)!=0,()=>false)(tnode.id)) return false; // real structures only (founts excluded)
		}
		if(flags&SpelFlags.disallowAlly){ // 0x2000: inverted, and the soul mask inverts too
			if(tnode.kind==NodeKind.cre){
				if(state.soulById!((ref s,state)=>s.state.among(SoulState.collecting,SoulState.reviving),()=>false)(tnode.id,state)) return false;
				if(cside>=0&&(pickupMask!B(state,tnode.id)&(1u<<cside))) return false; // thaum passes on null caster side here
			}else{
				if(ccFriendly!B(state,cside,tnode.kind,tnode.id)) return false;
				if(tnode.kind==NodeKind.str&&!state.buildingById!((ref b)=>(cast(uint)b.sacBuilding.flags&0x55a7)!=0,()=>false)(tnode.id)) return false;
			}
		}
	}
	// (flags&0x20000: LAND::GetAnchorMap(pos)>=0x60 "open ground" - sacengine has no anchor map; approximated as pass, documented)
	return true;
}
// shared AoE base of 0x489860 (retail Eval_Death 0x48cbd0 calls the same body via its helper 0x48c540)
float aoeSpellBase(B)(ref ShinyAI!B ai,ObjectState!B state,ref SpellAcc!B acc,int target,float r2){
	auto spel=acc.spell.spel;
	auto tnode=&ai.nodes[target];
	auto inv=cast(float)safediv(1.0,cast(double)r2);
	auto base=hasAcc(ai,target)?rate(tnode.acc):0.0f;
	if(isSacDoctorEnt!B(state,tnode.kind,tnode.id)) base=cast(float)(cast(double)base*1000.0f); // thaum 0x4898fc / retail 0x48c5df: TARGET's summon-spell tag (ntt+0x414/0x41c -> +0x10)=="dcas" (sac doctor)
	auto amountI=cast(int)(cast(uint)spel.amount|cast(uint)spel.unknown14<<16);
	foreach(cat;0..4){
		if(cat==2) continue; // cats 0,1,3 only
		for(auto g=ai.grp4Head[cat];g;g=ai.groups4[g].gN){
			auto grp=&ai.groups4[g];
			auto d2=cast(float)distSq3(grp.center,tnode.curPos);
			if(cast(double)d2>cast(double)r2) continue;
			auto grpRate=cast(double)rate(grp.acc); // kept on the FPU stack in thaum
			auto Ad=(cast(double)r2-d2)*amountI*inv; // extended, no f32 stores
			auto Bd=cast(double)cast(float)grp.count;
			auto C=ftol(Ad<Bd?Ad:Bd);
			auto E=cast(float)(safediv(cast(double)C,cast(double)grp.healthSum2)*grpRate);
			base=cat==3?cast(float)(cast(double)E+base):cast(float)(cast(double)base-E);
		}
	}
	return base;
}
float rateSpellAcc(B)(ref ShinyAI!B ai,ObjectState!B state,ref SpellAcc!B acc,int n,int target,uint category,float distScaled){ // rater2 vtbl[1] 0x489630
	// validity 0x48c330: LOS helpers 0x48c050/0x48c160 never run for categories 0x85/5 (documented)
	auto node=&ai.nodes[n], tnode=&ai.nodes[target];
	auto spel=acc.spell.spel;
	auto mask=cast(uint)spel.flags&0x781f;
	if(mask&&!(nttTypeBits(tnode.kind)&mask)) return 0.0f;
	if((cast(uint)spel.flags1&0x10)&&n!=target) return 0.0f; // shield: self-cast only
	if(!canCastSpellOn!B(ai,state,n,target,acc.spell)) return 0.0f; // 0x48c411: GRIMOIRE::CanCastSpellOn
	if(!(category&0x80)){ category|=0x80; distScaled=cast(float)distSq3(node.curPos,tnode.curPos); }
	if(!(category&0x200)&&cast(double)distScaled>cast(double)spel.range*spel.range) return 0.0f;
	if((cast(uint)spel.flags1&3)&&(category&0x3a)) return 0.0f;
	auto rfn=acc.ratingFn;
	if(rfn==RatingFn.f48cbd0&&ai.betaDeathEvaluator) rfn=ratingFnFlags!B(acc.spell); // thaum.exe has no 'taed' table entry: it falls to the flags1 chain
	switch(rfn) with(RatingFn){
		case f489700: // omna
			if(!(tnode.flags&0x10)) return 0.0f;
			auto run=state.movingObjectReadById!((ref cols,i,state)=>typeStats!B(cols.sacObject).run,()=>0.0f)(tnode.id,state);
			auto val=cast(float)(cast(double)run*spel.duration*0.00016818028927009755);
			auto rg=influenceGroups(ai,state,3,tnode.curPos,0.0f,val,null);
			auto r=cast(float)(cast(double)rg-sortKey(ai,target));
			if(tnode.status&0x8) r+=r; // dead in thaum: node status bit 0x8 is never set
			return r;
		case f489780:
			if(!(nttTypeBits(tnode.kind)&0x15)) return 0.0f;
			if(!(tnode.flags&0x4)) return 0.0f; // enemy-either-way & different sides (setupBase 0x486a04)
			auto hp=healthPair(state,tnode.kind,tnode.id);
			auto m=cast(int)spel.amount2<hp[0]?cast(int)spel.amount2:hp[0];
			auto ratio=cast(float)safediv(cast(double)cast(float)m,cast(double)hp[1]);
			auto r=cast(float)(cast(double)sortKey(ai,target)*ratio);
			if(isSacDoctorEnt!B(state,tnode.kind,tnode.id)) r=cast(float)(cast(double)r*1000.0f); // thaum 0x48983e / retail 0x48c527: target is a sac doctor (summon tag "dcas")
			return r;
		case f489860: // AoE
			auto er=cast(double)spel.effectRange, dr=cast(double)spel.damageRange;
			auto rr=dr>er?dr:er;
			auto r2=cast(float)(rr*rr);
			return aoeSpellBase!B(ai,state,acc,target,r2);
		case f48cbd0: // taed, retail 0x48cbd0: f489860 base (helper 0x48c540), then subtract nearby enemy wizards
			auto erD=cast(double)spel.effectRange, drD=cast(double)spel.damageRange;
			auto rrD=drD>erD?drD:erD; // ties -> damageRange
			auto r2D=cast(float)(rrD*rrD);
			auto baseD=aoeSpellBase!B(ai,state,acc,target,r2D);
			if(baseD==0.0f) return 0.0f; // fcomp 0.0, test ah,0x40
			auto score=baseD;
			if(hasAcc(ai,target)&&(nttTypeBits(tnode.kind)&1)) // target node has a rating handle (vt+0x2c!=0) and is a wizard (ntt+0x4&1)
				score=cast(float)(cast(double)score-rate(tnode.acc));
			for(int e=ai.fam1Head[3];e;e=ai.nodes[e].famN){ // enemy fam1 list (GetFirstCreature(AI,3) 0x488f40), wizards only
				auto wn=&ai.nodes[e];
				if(wn.kind!=NodeKind.wiz) continue;
				auto d2=cast(float)distSq3(wn.curPos,tnode.curPos); // (dz^2+dy^2)+dx^2 from f32 subs
				if(cast(double)d2<=cast(double)r2D) // test ah,0x41
					score=cast(float)(cast(double)score-rate(wn.acc));
			}
			return score;
		case f489a20: // ndrg
			if(!(nttTypeBits(tnode.kind)&0x4)) return 0.0f;
			if(!(tnode.status&0x10000)) return 0.0f;
			auto ors=spellbookOR(state,tnode.id);
			if(!(ors[0]&0x40000000)||!(ors[1]&0x4)) return 0.0f;
			auto rec=&ai.records[tnode.record]; // non-null here: status&0x10000 implies a record
			auto rg=influenceGroups(ai,state,3,rec.center,10.0f,280.0f,null);
			return cast(float)(cast(double)sortKey(ai,target)*(cast(double)rec.score+1.0f)*(cast(double)rg+1.0f)*4.0f);
		case f489ae0: return 0.0f; // ccas
		case f489af0: // heal
			final switch(tnode.kind) with(NodeKind){ case t4o,maho,wiz: break; case cre,str,none: return 0.0f; }
			if(tnode.flags&0x4) return 0.0f; // not an enemy
			if(hasActiveHeal(state,tnode.id)) return 0.0f;
			auto hp=healthPair(state,tnode.kind,tnode.id);
			auto amountI=cast(int)(cast(uint)spel.amount|cast(uint)spel.unknown14<<16);
			auto missing=hp[1]-hp[0];
			auto healed=amountI<missing?amountI:missing;
			return cast(float)(cast(double)sortKey(ai,target)*safediv(cast(double)healed,cast(double)hp[1]));
		case f489bc0: // protect
			if(!(nttTypeBits(tnode.kind)&0x5)) return 0.0f;
			if(target!=n) return 0.0f; // self
			if(hasActiveProtect(state,tnode.id)) return 0.0f;
			auto hp=healthPair(state,tnode.kind,tnode.id);
			if(hp[1]==0) return 0.0f;
			return cast(float)(cast(double)sortKey(ai,target)*nodeValue6c(ai,target));
		case f489c40: // pups
			if(!(nttTypeBits(tnode.kind)&0x5)) return 0.0f;
			return state.movingObjectReadById!((ref cols,i,state){
				auto order=&cols.creatureAIs[i].order;
				double base;
				// thaum reads the target's live order cmd (0x46e1d0): 7 (advance) -> wizards excluded, empty spellbook required, base 60; 0x22 (engage) -> base 40, no gates; else 0
				if(tnode.ordState==7&&order.command==CommandType.advance){ // 7
					if(tnode.kind==NodeKind.wiz) return 0.0f;
					auto ors=spellbookOR(state,tnode.id);
					if(ors[0]||ors[1]) return 0.0f;
					base=60.0;
				}else if(tnode.ordState==34&&order.command.among(CommandType.guard,CommandType.guardArea,CommandType.move)) base=40.0; // 0x22 (move: soul-pickup engage maps to move)
				else return 0.0f;
				auto p=order.target.id&&order.target.type!=TargetType.terrain&&state.isValidTarget(order.target.id)?
					state.movingObjectReadById!((ref tcols,ti,state)=>tcols.positions[ti],()=>order.target.position)(order.target.id,state):order.target.position;
				auto d2=cast(float)distSq3(tnode.curPos,p);
				if(d2<100.0f) return 0.0f;
				return cast(float)(cast(double)sortKey(ai,target)*safediv(cast(double)d2,base*base));
			},()=>0.0f)(tnode.id,state);
		case f489d70: // elet
			if(!(nttTypeBits(tnode.kind)&0x1)) return 0.0f;
			if(!tnode.record) return 0.0f;
			auto anchor=ai.records[tnode.record].target; // record+0x8: the anchor node
			if(!anchor) return 0.0f;
			auto anode=&ai.nodes[anchor];
			if(entSide(state,anode.kind,anode.id)!=entSide(state,tnode.kind,tnode.id)) return 0.0f; // same side
			if(anode.kind!=NodeKind.str) return 0.0f; // anchor.vtbl[14]!=0: structure nodes only
			auto r2=cast(float)(cast(double)spel.effectRange*spel.effectRange*4.0f);
			auto total=0.0f;
			for(auto g=ai.grp4Head[0];g;g=ai.groups4[g].gN){
				auto grp=&ai.groups4[g];
				auto d2=cast(float)distSq3(grp.center,tnode.curPos);
				if(cast(double)d2<=cast(double)r2) total=cast(float)(cast(double)total+rate(grp.acc));
			}
			return total;
		case f489e70:
			if(!(nttTypeBits(tnode.kind)&0x5)) return 0.0f;
			if(!(tnode.flags&0x4)) return 0.0f; // enemy required
			return sortKey(ai,target);
		case none: return 0.0f;
		default: return 0.0f;
	}
}
int spellAccAnchor(B)(ref ShinyAI!B ai,ObjectState!B state,ref SpellAcc!B acc,int n,int target){ // rater2 vtbl[4] 0x4896d0
	if(acc.ratingFn==RatingFn.f489a20) return ai.records[ai.nodes[target].record].target; // node+0x70 non-null here (ndrg wins only with status&0x10000)
	return 0;
}

float findBestSpell(B)(ref ShinyAI!B ai,ObjectState!B state,int n,int target,uint mask,SacSpell!B* outSpell,float* outRange,int* outObj){ // 0x48d4d0
	auto node=&ai.nodes[n];
	// retail 0x490020: fild(maxMana * (own+ally manaliths)); thaum 0x48d4d0: own only
	auto pool=cast(float)(state.movingObjectReadById!((ref cols,i,state)=>ftol(cols.creatureStatss[i].maxMana),()=>0)(node.id,state)*(si(ai.stanceRecs[0],5)+(ai.betaSummonAccounting?0:si(ai.stanceRecs[1],5))));
	auto category=5u;
	float distScaled=0.0f;
	if(target){
		category=0x85u;
		auto dse=cast(double)distSq3(node.curPos,ai.nodes[target].curPos)*0.7142857313156128f;
		distScaled=cast(float)dse;
		if(dse<1600.0f) distScaled=0.0f; // thaum zeroes the slot when below 1600 (extended compare, f32 store)
	}
	float best=0.0f;
	SpellAcc!B* bestAcc=null;
	foreach(i;0..node.spellAccs.length){
		auto acc=&node.spellAccs[i];
		if(!spellAccAccepts!B(*acc,mask)) continue;
		auto s=cast(double)rateSpellAcc!B(ai,state,*acc,n,target,category,distScaled);
		if(pool>0.0f) s=(1.0-safediv(cast(double)ftol(acc.spell.manaCost),cast(double)pool))*s; // fild(cost)/pool; fsubr 1.0d; fmul s
		if(s>cast(double)best){ best=cast(float)s; bestAcc=acc; } // strict argmax, best starts at 0.0f
	}
	if(bestAcc is null) return 0.0f;
	*outSpell=bestAcc.spell;   // rater2 vtbl[3]: the spell record
	*outRange=bestAcc.spell.range;
	*outObj=spellAccAnchor!B(ai,state,*bestAcc,n,target);
	return best;
}

void weightTriple(B)(ref ShinyAI!B ai,int cmd,float[3]* w3){ // 0x48cc70
	auto m=1.0-cast(double)sf(ai.stanceRecs[3],6); // fld 1.0f; fsub f32 (exact)
	auto ag=cast(double)ai.aggression;
	float o0,o1; // thaum stores these two as f32 and reloads them
	double o2e;    // o2 stays on the fpu stack (extended)
	if(cmd<=1){ o0=cast(float)(ag*(1.0-m)*(1.0/6.0)); o1=cast(float)(1.0-m); o2e=m*ag; }
	else if(cmd==2){ o0=cast(float)(ag*(1.0-m)*0.5); o1=cast(float)((1.0-m)*(1.0/3.0)); o2e=m*ag; }
	else{ o0=o1=0.0f; o2e=0.0; } // thaum reads uninitialized locals here (documented); zeroes take the default branch
	auto total=(o2e+o1)+o0; // f32 adds in thaum; o1/o0 are the rounded values
	if(total<=0.0){ (*w3)[0]=(*w3)[1]=(*w3)[2]=0.333299994468689f; } // ds:0x3eaaa64c x3
	else{ (*w3)[0]=cast(float)safediv(cast(double)o0,total); (*w3)[1]=cast(float)safediv(cast(double)o1,total); (*w3)[2]=cast(float)safediv(o2e,total); }
}

// ---- wizard: target scans ----

bool isSacDoctorEnt(B)(ObjectState!B state,NodeKind kind,int id){ // thaum: ntt+0x414 (retail +0x41c) provider tag == "dcas" (SpellTag.sacDoctor; filename 'sacd' is the reversed fourcc)
	final switch(kind) with(NodeKind){
		case wiz,t4o,maho,cre: return state.movingObjectReadById!((ref cols,i,state)=>cols.sacObject.isSacDoctor,()=>false)(id,state);
		case str,none: return false;
	}
}
int buildingIdOf(B)(ObjectState!B state,int objectId){ // engine structure lookups (findClosestBuildings) return component object ids; AI str nodes track Building ids
	if(objectId<=0) return 0; // no altar/shrine in scan range (e.g. WizardInfo.closestEnemyAltar==0)
	return state.staticObjectById!((ref o,state)=>o.buildingId,()=>0)(objectId,state);
}
bool desecrationOngoing(B)(ObjectState!B state,int buildingId){ // 0x466950(ntt,0,0)=='sacu' approximation: a desecrate ritual targets the building (SacDocCasting.targetShrine holds its component object id)
	if(buildingId==0) return false;
	foreach(i;0..state.obj.opaqueObjects.effects.sacDocCastings.length){
		auto c=&state.obj.opaqueObjects.effects.sacDocCastings[i];
		if(c.type==RitualType.desecrate&&buildingIdOf!B(state,c.targetShrine)==buildingId) return true;
	}
	return false;
}
bool wizardSacrificing(B)(ref ShinyAI!B ai,ObjectState!B state,int wizardId){ // retail 0x490ac0: GetTag(ntt+0xb9c,0,0)=='sacu' approximation: the wizard's side has a desecrate ritual underway
	return state.movingObjectReadById!((ref cols,ci,ObjectState!B state){
		foreach(i;0..state.obj.opaqueObjects.effects.sacDocCastings.length){
			auto c=&state.obj.opaqueObjects.effects.sacDocCastings[i];
			if(c.type==RitualType.desecrate&&c.side==cols.sides[ci]) return true;
		}
		return false;
	},()=>false)(wizardId,state);
}
bool isGuardianEnt(B)(ObjectState!B state,int creatureId){ // ntt+0x5b4!=0: creature bound to a building by the guardian spell (setGuardian 0x460200, guardian spell only)
	return state.movingObjectReadById!((ref cols,i,state)=>cols.creatureStatss[i].effects.isGuardian,()=>false)(creatureId,state);
}
uint pickupMask(B)(ObjectState!B state,int id){ // thaum soul+0x434: static touch-collect side mask, from the soul record or 0xffffffff (0x4753e0/0x475abf); approximation via soulSide: creatureId==0 souls (e.g. gibs) are touch-collectible by everyone regardless of preferredSide
	auto s=soulSide(id,state);
	return s<0?0xffffffffu:1u<<s;
}
uint convertMask(B)(ObjectState!B state,int id){ // 'ccas' attachment check (0x46a840): convertSideMask bits are cleared at cast start and restored only when the ritual aborts, so ~mask also covers the carry phase
	return ~state.soulById!((ref soul)=>soul.convertSideMask,()=>-1u)(id);
}
int findBestNear(B)(ref ShinyAI!B ai,ObjectState!B state,Vector3f* pos,float radius,int enemyFlag){ // 0x485490 GetNearestPickup: thaum walks fam C cat2 (neutral souls) only, head ai+0x7c, chain node+0x6c; retail list masks 5 (pickups: slots 0+2) / 0xc (convert targets: slots 2+3)
	float best=0.0f;
	int bestNode=0;
	static immutable int[2] pickupSlots=[0,2], convertSlots=[2,3];
	foreach(slot;ai.betaPickupNeutralOnly?pickupSlots[1..2]:(enemyFlag?pickupSlots[0..2]:convertSlots[0..2]))
	for(int m=ai.fam3Head[slot];m;m=ai.nodes[m].famN){
		auto t=&ai.nodes[m];
		auto mask=pickupMask!B(state,t.id); // ntt+0x434
		if(enemyFlag){ if(!(mask&(1u<<ai.side))) continue; } // pickups: only souls we may touch-collect
		else if((mask&(1u<<ai.side))||convertMask!B(state,t.id)) continue; // convert targets: souls we may not touch-collect, without an active convert ritual ('ccas' attachment)
		if(!sameRegionPos!B(state,t.curPos,*pos)) continue; // 0x470700 region check (node+0x4)
		immutable dx=cast(double)t.extrapPos.x-pos.x, dy=cast(double)t.extrapPos.y-pos.y, dz=cast(double)t.extrapPos.z-pos.z; // node+0x10
		auto d=cast(float)sqrt(cast(float)(dx*dx+dy*dy+dz*dz));
		double w;
		if(d<=0.0f) w=1.0f;
		else if(d<radius) w=safediv(cast(double)(radius-d),cast(double)radius);
		else w=0.0f;
		if(cast(double)best<w){ best=cast(float)w; bestNode=m; } // strict argmax
	}
	return bestNode;
}
int pickGuardCreature(B)(ref ShinyAI!B ai,ObjectState!B state,int t){ // 0x485700 CommandeerSacrificeVictim: walks slot0 cat0 (ntt list, ai+0x2c), chain +0xa0
	float best=0.0f;
	int bestNode=0;
	for(int m=ai.catHead[0];m;m=ai.nodes[m].catN){
		auto c=&ai.nodes[m];
		if(c.kind==NodeKind.wiz) continue; // ntt+0x4&1
		if(isGuardianEnt!B(state,c.id)) continue; // ntt+0x5b4!=0 (guardian-spell bound, setGuardian 0x460200)
		auto p=soulsPair21(ai,state,m); // node vtbl[21] (non-creatures yield 0 souls and lose the strict argmax)
		immutable dx=cast(double)c.extrapPos.x-ai.nodes[t].curPos.x, dy=cast(double)c.extrapPos.y-ai.nodes[t].curPos.y, dz=cast(double)c.extrapPos.z-ai.nodes[t].curPos.z;
		auto d=cast(float)sqrt(cast(float)(dx*dx+dy*dy+dz*dz));
		double w;
		if(d<=10.0f) w=1.0f;
		else if(d<3620.0f) w=cast(double)(3620.0f-d)*0.0002770083083305508f;
		else w=0.0f; // thaum 0x4857ad: d>=3620 loads f32 0.0 (0x4bb5e0), so far creatures weigh 0 and are never picked (v=0 never beats best=0)
		auto v=w*p[0]; // fimul souls
		if(cast(double)best<v){ best=cast(float)v; bestNode=m; } // strict argmax
	}
	if(bestNode&&ai.nodes[bestNode].group){ // group-unclaim tail: slot4 group vtbl[4](group,member); member+0x68=0
		groupRemoveMember(ai,ai.nodes[bestNode].group,bestNode);
		ai.nodes[bestNode].group=0;
	}
	return bestNode;
}

// ---- wizard: cast phases ----

void wizAttack(B)(ref ShinyAI!B ai,ObjectState!B state,int n,float[3]* w3){ // 0x48d640 CheckAttack
	auto node=&ai.nodes[n];
	// thaum leaves best/total uninitialized (stack garbage); DEFEND zeroes total only, so we zero-init (documented)
	float best=0.0f, total=0.0f;
	int bestNode=0;
	// retail 0x4901a0: fmul 280.0d; thaum 0x48d640: fmul 180.0d (fsubr 1.0d; fmul; f32 store, hoisted before the loop)
	auto thr=cast(float)((1.0-cast(double)node.threat)*(ai.betaAttackCoeff?180.0:280.0));
	for(int m=ai.fam1Head[3];m;m=ai.nodes[m].famN){ // slot1 cat3 (enemy creatures), GetFirstCreature/GetNextCreature 0x486020/0x486030
		auto t=&ai.nodes[m];
		immutable dx=cast(double)node.extrapPos.x-t.extrapPos.x, dy=cast(double)node.extrapPos.y-t.extrapPos.y, dz=cast(double)node.extrapPos.z-t.extrapPos.z;
		auto d=cast(float)sqrt(cast(float)(dx*dx+dy*dy+dz*dz));
		double w;
		if(d<=10.0f) w=1.0f;
		else if(!(d<thr)) continue;
		else{
			w=safediv(cast(double)(thr-d),cast(double)(thr-10.0f));
			if(w==0.0f) continue; // dead-code guard in thaum (w>0 always here)
		}
		if(!(t.status&0x6)) w*=0.5f;
		if(!(t.status&0x1800)) w*=0.3333333432674408f;
		if(isSacDoctorEnt!B(state,t.kind,t.id)) w*=10.0f; // ntt+0x414.+0x10=="dcas" (sac doctor; thaum 0x48d710, retail 0x490270)
		if(cast(double)best<w){ best=cast(float)w; bestNode=m; } // strict argmax
		total=cast(float)(cast(double)total+w); // f32 store per add
	}
	if(total==0.0f||!bestNode) return;
	SacSpell!B sp; float range; int obj;
	auto s=findBestSpell(ai,state,n,bestNode,0x58000000,&sp,&range,&obj);
	if(s<=0.0f) return;
	enqueueCast(ai,n,cast(float)safediv(cast(double)best*(*w3)[0],cast(double)total),bestNode,sp,range,obj,0);
}
void wizSupport(B)(ref ShinyAI!B ai,ObjectState!B state,int n,float[3]* w3){ // 0x48d7c0
	auto node=&ai.nodes[n];
	float best=0.0f, total=0.0f;
	int bestNode=0, bo0=0;
	float bo1=0.0f;
	SacSpell!B bo2;
	for(int m=ai.fam1Head[0];m;m=ai.nodes[m].famN){ // slot1 cat0 (own creatures), GetFirstCreature 0x486020
		if(nodeIsRespawning(ai,state,m)) continue; // ntt+0x5ec.+0x30&0x40000
		SacSpell!B sp; float range; int obj;
		auto s=findBestSpell(ai,state,n,m,0xa4000000,&sp,&range,&obj);
		if(best<s){ best=s; bestNode=m; bo0=obj; bo1=range; bo2=sp; } // strict argmax
		total=cast(float)(cast(double)total+s); // total accumulates even when best is not updated
	}
	if(total==0.0f||best==0.0f||!bestNode) return; // thaum compares best against 0.0d
	enqueueCast(ai,n,cast(float)safediv(cast(double)best*(*w3)[1],cast(double)total),bestNode,bo2,bo1,bo0,0);
}
void wizRetreat(B)(ref ShinyAI!B ai,ObjectState!B state,int n,float[3]* w3){ // 0x48db60
	auto node=&ai.nodes[n];
	// thaum gates: ntt+0xb80!=0 (wizard has a home altar; closestShrine approximation) and node+0xd0!=0
	auto wiz=state.getWizard(node.id);
	if(wiz is null||wiz.closestShrine==0) return;
	if(node.convertSpell is null) return;
	// ntt+0xb80==ntt+0xb88 && attachment(ntt+0xb88)=='sacu': home altar being desecrated (documented approximation)
	if(desecrationOngoing!B(state,buildingIdOf!B(state,wiz.closestShrine))) return;
	auto v=cast(float)((1.0-cast(double)sf(ai.stanceRecs[3],6))*(1.0-cast(double)node.threat)*cast(double)ai.aggression*500.0);
	if(v<=10.0f) return; // fcomp 10.0d
	auto t=findBestNear(ai,state,&node.curPos,v,0);
	if(!t) return;
	// thaum then reads an uninitialized stack local in the Q=0.5f*(r1/r2)*(d2^2+garbage^2) retreat-abort
	// test and compares against f32(r1); it effectively never aborts deterministically (documented), fall through
	// thaum passes obj=0 (no approach: its cast path has no range check); sacengine's spellStatus gates range, so approach the soul (obj=t) or convert would never fire
	enqueueCast(ai,n,cast(float)((1.0-cast(double)node.threat)*(*w3)[2]*0.8999999761581421),t,node.convertSpell,node.convertSpell.range,t,0);
}
void wizSacrifice(B)(ref ShinyAI!B ai,ObjectState!B state,int n,float[3]* w3,int ri){ // 0x48d8b0
	auto node=&ai.nodes[n];
	int maxMana=0, souls=0;
	state.movingObjectReadById!((ref cols,i,ObjectState!B state){
		maxMana=ftol(cols.creatureStatss[i].maxMana);
		if(auto wiz=state.getWizardForSide(cols.sides[i])) souls=wiz.souls;
	},(){})(node.id,state);
	if(maxMana==0||souls==0) return; // ntt+0xb10/0xb30 gates
	auto randv=cast(double)ai.rng.rand()*3.0518509447574615e-05f; // fild(rand)*f32, stays extended
	auto threatv=cast(float)(cast(double)node.threat*1.2999999523162842f); // fstp f32
	if(cast(double)randv>=cast(double)threatv){ // BLOCK1: emergency manahoar; thaum 0x48d900 fcompp+test 0x41 takes the tie too (randv>=threatv)
		auto mcount=si(ai.stanceRecs[0],5)+(ai.betaSummonAccounting?0:si(ai.stanceRecs[1],5)); // retail: own+ally manaliths; thaum: own only
		if(mcount>0&&node.manahoarSpell !is null){
			int ready=0;
			for(int g=ai.grp4Head[0];g;g=ai.groups4[g].gN) ready+=ai.groups4[g].readyCount; // slot4 cat0 groups, +0x70
			if(ready<si(ai.stanceRecs[0],4)/(ai.betaSummonAccounting?4:2)){ // sdiv4 thaum / sdiv2 retail
				if(ready==0||safediv(cast(double)(2*si(ai.stanceRecs[0],1)-si(ai.stanceRecs[0],0)),cast(double)(mcount*ready))>1400.0){
					enqueueCast(ai,n,0.0f,0,node.manahoarSpell,0.0f,0,1); // 0x48d050 forced manahoar
					return; // only the enqueue returns; all other BLOCK1 exits fall through to BLOCK2
				}
			}
		}
	}
	// BLOCK2: summon the best creature
	if(!(cast(double)node.threat<0.6)) return; // fcomp 0.6d, CF only
	auto pool=maxMana*(si(ai.stanceRecs[0],5)+(ai.betaSummonAccounting?0:si(ai.stanceRecs[1],5))); // retail: own+ally manaliths; thaum: own only
	if(pool==0||node.summons.length==0) return;
	float bestScore=0.0f;
	SacSpell!B bestSpell=null;
	foreach(i;0..node.summons.length){
		auto e=&node.summons[i];
		if(e.spell is null) continue;
		if(e.spell.soulCost>souls) continue; // movsx word[provider+0x5a] > ntt+0xb30
		RaterAcc ctx; // fresh rater2 acc (vtbl[0])
		ctx.clear();
		bool recPath=false;
		if(ri&&ai.records[ri].target){ // thaum dereferences rec+0x8 unchecked; guarded here (documented)
			auto tn=&ai.nodes[ai.records[ri].target];
			// rec path iff !(target.flags&0x20) or the structure has ntt+0x47c&0x80 (built)
			recPath=!(tn.flags&0x20)||state.buildingById!((ref b,state)=>(cast(uint)b.sacBuilding.flags&0x80)!=0,()=>false)(tn.id,state);
			if(recPath) combine(ctx,1.0f,ai.records[ri].targetAcc,1.0f); // rec+0x4c (targetAcc approximation)
		}
		if(!recPath){
			auto m=sf(ai.stanceRecs[3],6);
			combine(ctx,1.0f,ai.acc1,m);
			combine(ctx,1.0f,ai.acc2,cast(float)(1.0f-m)); // fld 1.0f; fsub f32
		}
		auto s=rateWithBase(e.acc,ctx); // rater2 vtbl[11] 0x4892b0
		auto cost=safediv(cast(double)ftol(e.spell.manaCost),cast(double)pool); // fild(cost)/fild(pool)
		double sd=s;
		if(s>0.0f) sd=(1.0-cost)*sd; // fsubr 1.0d
		else sd=cost*sd;
		if(bestSpell is null||cast(double)bestScore<sd){ bestScore=cast(float)sd; bestSpell=e.spell; } // first entry always taken, then strict argmax
	}
	if(bestSpell !is null) enqueueCast(ai,n,0.0f,0,bestSpell,0.0f,0,1); // 0x48d050 forced summon
}

// ---- wizard: cast execution ----

bool lightCanCast(B)(ObjectState!B state,int wizardId,SacSpell!B spell){ // thaum WIZARD::CantCastSpell 0x481580 (returns 0 = can cast)
	return state.movingObjectReadById!((ref cols,i,ObjectState!B state){
		auto wiz=state.getWizardForSide(cols.sides[i]);
		if(wiz is null||wiz.id!=wizardId) return false;
		// thaum looks the spell up by tag (vtbl+0xf8): missing item, or item+0x8&2 set (level-locked by GRIMOIRE::UpdateSpellList 0x4514f0 after a de-level) -> "_XP_" reject;
		// sacengine book entries carry the spell level, entry.level>wiz.level is the same predicate
		if(spell.type==SpellType.creature&&wiz.souls<spell.soulCost) return false; // 'spir'
		// CantCastSpell 0x481580: s_spell+0xc==4 (SPEL records - convert/desecrate/guardian) tests flags2 (runtime +0x64 = file +0x5c): connectedToConversion -> wiz+0xb80 (closest own
		// shrine), nearEnemyAltar -> wiz+0xb7c (closest enemy altar), nearBuilding -> wiz+0xb84 (closest own shrine-or-altar); STRC records have no flags2 (the old SpellType.structure gate was dead code)
		if(spell.type==SpellType.spell){
			if(spell.connectedToConversion&&wiz.closestShrine==0) return false;
			if(spell.nearEnemyAltar&&wiz.closestEnemyAltar==0) return false;
			if(spell.nearBuilding&&wiz.closestShrine==0&&wiz.closestAltar==0) return false;
		}
		bool found=false;
		foreach(entry;wiz.getSpells())
			if(entry.spell is spell){
				if(entry.level>wiz.level) return false; // "_XP_"
				if(entry.cooldown>0.0f) return false; // 'dern' (item+0x14 pending)
				found=true;
				break;
			}
		if(!found) return false; // "_XP_" (spell not in spellbook)
		return ftol(spell.manaCost)<=ftol(cols.creatureStatss[i].mana); // 'mana' (thaum CalculateCost = max(fileManaCost,1), sacengine applies it at load)
	},()=>false)(wizardId,state);
}

int executeBestCast(B)(ref ShinyAI!B ai,ObjectState!B state,int n,int checkOnly){ // 0x48d0b0
	auto node=&ai.nodes[n];
	size_t i=0;
	while(i<node.castQueue.length){
	entry: {
		auto e=&node.castQueue[i];
		static if(shinyAILog) ailog("CASTQ ",ai.side," t",ai.schedTime," n",n," [",i,"] checkOnly ",checkOnly," flag ",e.flag," tgt ",e.target," obj ",e.obj," range ",e.range," spell ",e.provider is null?"null":to!string(e.provider.tag));
		if(e.provider is null) goto exit;
		if((e.flag&1)&&e.target&&checkOnly) goto exit;
		if(si(ai.stanceRecs[0],5)+(ai.betaSummonAccounting?0:si(ai.stanceRecs[1],5))==0){ // no manaliths (retail: own+ally; thaum: own): only affordable casts
			auto mana=state.movingObjectReadById!((ref cols,i,state)=>ftol(cols.creatureStatss[i].mana),()=>0)(node.id,state);
			if(ftol(e.provider.manaCost)>mana){ // thaum reads the int mana fields
				static if(shinyAILog) ailog("CASTQ ",ai.side," t",ai.schedTime," n",n," [",i,"]: mana ",ftol(e.provider.manaCost),">",mana,e.flag&1?" -> ret 0":" -> skip");
				if(e.flag&1) return 0;
				goto exit;
			}
		}
		float sq=0.0f;
		if(e.obj){
			if(e.target&&ai.nodes[e.target].kind==NodeKind.wiz&&nodeIsRespawning(ai,state,e.target)) goto exit; // target wizard respawning (0x486aa0 debug skipped)
			sq=distSq3(node.curPos,ai.nodes[e.obj].curPos);
			if(cast(double)sq>cast(double)e.range*e.range){ // out of range
				static if(shinyAILog) ailog("CASTQ ",ai.side," t",ai.schedTime," n",n," [",i,"]: obj ",e.obj," at ",ai.nodes[e.obj].curPos," dist^2 ",sq," > range^2 ",e.range*e.range,checkOnly?" -> skip":" -> approach");
				if(!checkOnly){
					orderPosRadius(ai,state,n,2,&ai.nodes[e.obj].curPos,e.range); // 0x4874e0(node,2,obj+0x4,range); thaum approaches unconditionally (no legality checks in its AI cast path)
					return 1;
				}
				goto exit;
			}
		}
		// thaum's light can-cast (WIZARD::CantCastSpell 0x481580, no range/target-validity checks): invalid targets are fired at
		// anyway, the engine rejects them without side effects, and the entry is consumed either way (thaum ignores the 0x45daa0 result)
		OrderTarget ot;
		if(e.target) ot=entOrderTarget!B(state,ai.nodes[e.target].kind,ai.nodes[e.target].id);
		auto canCast=lightCanCast!B(state,node.id,e.provider);
		static if(shinyAILog) ailog("CASTQ ",ai.side," t",ai.schedTime," n",n," [",i,"]: spell ",e.provider.tag[]," tgtNode ",e.target," ot(",ot.type,",",ot.id,") canCast ",canCast," flag ",e.flag);
		if(!canCast){
			if(!(e.flag&1)) goto exit;
			if(!e.obj) return 0;
			if(!checkOnly){
				orderTargetRadius(ai,state,n,3,e.obj,e.range); // 0x487450(node,3,obj,range)
				return 1;
			}
			goto exit;
		}
		// thaum step 6 (0x48d212): cast target (entry+0x8) is a building ntt (type 2) && (ntt+0x430&0xc0000000 || rise anim ntt+0x444<1.0) -> orderPosRadius toward e.obj with e.range instead of casting.
		// building ntts init +0x444=0 (0x4663dd) and rise to 1.0 (updater 0x4754c0); fount ntts persist (occupier at fount+0x440) while the shrine/manalith ntts rise on top,
		// so for bot structure casts (target = fount, never rising) step 6 could only fire via the unresolved +0x430 top bits; sacengine has no building-rise state
		// and occupancy already rejects casting a second structure on a fount - documented gap, deferred
		if(e.obj){
			bool half=false;
			auto waim=entAimPos!B(state,node.kind,node.id), oaim=entAimPos!B(state,ai.nodes[e.obj].kind,ai.nodes[e.obj].id); // live ntt aim positions (thaum passes ntts)
			if(e.provider.type==SpellType.spell&&(cast(uint)e.provider.flags1&0x3)) // 0x48d259: s_spell+0xc==4 (SPEL) && runtime +0x60&0x30000; runtime+0x60 = file+0x58 = unknown16|(flags1<<16), i.e. flags1&0x3 (basicAttackSpell|unknown1)
				half=!entCanHit!B(state,node.id,waim,ai.nodes[e.obj].id,oaim); // CanHit(wizNtt,objNtt)!=4; ==4 FALLS THROUGH to the LoS check below
			if(!half){
				auto rel=relation!B(state,ai.side,entSide!B(state,ai.nodes[e.target].kind,ai.nodes[e.target].id));
				half=rel==3&&!entCanSee!B(state,ai.nodes[e.obj].kind,ai.nodes[e.obj].id,waim,oaim); // enemy either-way, different sides, HaveLOS 0x4878a0(node,obj)==0
			}
			if(half){
				static if(shinyAILog) ailog("CASTQ ",ai.side," t",ai.schedTime," n",n," [",i,"]: no LOS",checkOnly?" -> skip":" -> half-range chase");
				if(!checkOnly){
					auto hr=cast(float)(sqrt(cast(double)sq)*0.5); // fsqrt; fmul 0.5d
					orderTargetRadius(ai,state,n,3,e.obj,hr);
					return 1;
				}
				goto exit;
			}
		}
		static if(shinyAILog) ailog("CASTQ ",ai.side," t",ai.schedTime," n",n," [",i,"]: EXECUTE");
		static if(shinyAILog){ auto castOk=startCasting(node.id,e.provider,ot,state); ailog("CASTGO ",ai.side," t",ai.schedTime," n",n," spell ",e.provider.tag[]," ok ",castOk); }else startCasting(node.id,e.provider,ot,state); // 0x45daa0 EXECUTE (thaum ignores the result)
		// wizard busy -> engine queueSpell: approximation of thaum's persistent entity order (documented)
		for(size_t j=i;j+1<node.castQueue.length;j++) node.castQueue[j]=node.castQueue[j+1]; // unlink (spent-pool relink is memory management only)
		node.castQueue.length=node.castQueue.length-1;
		return 1;
	}
	exit:
		i++;
	}
	return 0;
}
int enqueueForcedExecute(B)(ref ShinyAI!B ai,ObjectState!B state,int n,int target,SacSpell!B provider,float range,int obj0){ // 0x48d080
	enqueueCast(ai,n,0.0f,target,provider,range,obj0,1); // 0x48d050: score 0, forced
	return executeBestCast(ai,state,n,0);
}
int castCachedInRange(B)(ref ShinyAI!B ai,ObjectState!B state,int n,int t){ // 0x48dce0
	auto node=&ai.nodes[n];
	static if(shinyAILog) ailog("CCIR ",ai.side," t",ai.schedTime," n",n," tgt ",t," shrineSpell ",node.shrineSpell is null?"null":node.shrineSpell.tag[]," threat ",node.threat);
	if(node.shrineSpell is null) return 0;
	// fcomp: test ah,1;jne -> CF (threat below the bound or unordered) proceeds; retail 0x490850 0.9d, thaum 0x48dce0 0.6d
	if(cast(double)node.threat>=(ai.betaCastBuildingThreshold?0.6:0.9)) return 0;
	auto sq=distSq3(node.curPos,ai.nodes[t].curPos);
	auto r=cast(double)node.shrineSpell.range;
	r=r*r;
	r*=1.399999976158142;
	r*=25.0;
	static if(shinyAILog) ailog("CCIR ",ai.side," t",ai.schedTime," n",n," tgt ",t," dist^2 ",sq," vs ",r,cast(double)sq>r?" -> out of range":" -> in range, enqueue");
	if(cast(double)sq>r) return 0;
	return enqueueForcedExecute(ai,state,n,t,node.shrineSpell,node.shrineSpell.range,0);
}

// ---- wizard: brain (0x48df70) ----

int wizBrain(B)(ref ShinyAI!B ai,ObjectState!B state,int n,int cmd,int ri){
	auto node=&ai.nodes[n];
	static if(shinyAILog) ailog("WIZBRAIN ",ai.side," t",ai.schedTime," n",n," id ",node.id," cmd ",cmd," ri ",ri," age ",node.age," nextReplan ",node.nextReplan," nextReissue ",node.nextOrderReissue," threat ",node.threat," pos ",node.curPos);
	if(nodeIsRespawning(ai,state,n)){ // ntt+0x5ec.+0x30&0x40000
		// thaum gives ghosts record orders only (idle cmd -> stub 0x486cd0, no order): the ghost stands where it died and own manahoars converge on it (max mana deficit, x2 wizard bonus, mahoBrain 0x487ae0) and channel it back (giveMana heals ghosts 4.2x)
		bool mahoNear=false;
		for(int m=ai.catHead[0];m;m=ai.nodes[m].catN)
			if(ai.nodes[m].kind==NodeKind.maho&&distSq3(node.curPos,ai.nodes[m].curPos)<=256.0f*256.0f){ mahoNear=true; break; } // 256.0f = mahoBrain seek cutoff (ds:0x4bc108)
		if(!mahoNear){
			// DELIBERATE DEVIATION (not thaum): with no own manahoar nearby to revive it, the ghost seeks the nearest own mana structure (altar/manalith/shrine; engine mana zone radius 50) instead of standing still indefinitely
			int bs=0;
			float bd=float.infinity;
			for(int m=ai.catHead[0];m;m=ai.nodes[m].catN){
				auto t=&ai.nodes[m];
				if(t.kind!=NodeKind.str) continue;
				if(!state.buildingById!((ref b,state)=>b.sacBuilding.isManalith||b.sacBuilding.isShrine||b.sacBuilding.isAltar,()=>false)(t.id,state)) continue;
				auto d=distSq3(node.curPos,t.curPos);
				if(d<bd){ bd=d; bs=m; }
			}
			static if(shinyAILog) ailog("GHOST ",ai.side," t",ai.schedTime," n",n," no manahoar within 256, nearest mana str node ",bs);
			if(bs){ orderIfChanged(ai,state,n,3,bs,null); return 1; } // ostate 3 -> retreat -> moveWithinRange 9.0: inside the mana zone
		}
		return t4oBrain(ai,state,n,cmd,ri);
	}
	if(node.age>=node.nextReplan){ // +0xb0
		node.nextReplan=node.age+16; // ds:0x4cfbc0
		node.nextOrderReissue=node.age-1; // +0xb4
		float[3] w3;
		weightTriple(ai,cmd,&w3);
		static if(shinyAILog) ailog("WIZBRAIN ",ai.side," t",ai.schedTime," n",n," replan w3 ",w3[]);
		node.castQueue.length=0; // 0x48cd40 queue reset
		wizAttack(ai,state,n,&w3);
		wizSupport(ai,state,n,&w3);
		wizRetreat(ai,state,n,&w3);
		wizSacrifice(ai,state,n,&w3,cmd==2?ri:0);
	}
	// retail 0x490b20: fmul 100.0d fadd 80.0d; thaum 0x48df70: fmul 80.0d fadd 60.0d (fsubr 1.0d; f32)
	auto f=cast(float)((1.0-cast(double)node.threat)*(ai.betaWizardOrderScore?80.0:100.0)+(ai.betaWizardOrderScore?60.0:80.0));
	auto t=findBestNear(ai,state,&node.curPos,f,1);
	static if(shinyAILog) ailog("WIZBRAIN ",ai.side," t",ai.schedTime," n",n," findBestNear f ",f," -> ",t,t?ai.nodes[t].curPos:Vector3f.init);
	if(t){
		if(executeBestCast(ai,state,n,1)!=0) return 1;
		// 0x486aa0 debug output skipped (documented)
		orderTargetRadius(ai,state,n,0x22,t,0.0f); // 0x487450(node,0x22,t,0)
		return 1;
	}
	if(ri&&cmd==2){
		auto tn=ai.records[ri].target; // edi = rec+0x8
		static if(shinyAILog){
			ailog("WIZBRAIN ",ai.side," t",ai.schedTime," n",n," cmd2-block tn ",tn," age>=reissue ",node.age>=node.nextOrderReissue);
			if(tn) ailog("WIZBRAIN ",ai.side," t",ai.schedTime," n",n," cmd2-block tgt(",ai.nodes[tn].kind," id ",ai.nodes[tn].id,") flags ",ai.nodes[tn].flags," status ",ai.nodes[tn].status);
		}
		if(tn&&node.age>=node.nextOrderReissue){
			node.nextOrderReissue=node.age+8; // ds:0x4cfbcc
			auto tgt=&ai.nodes[tn];
			if(tgt.flags&0x200){ // desecrate path
				if(node.desecrateSpell !is null
				&&relation!B(state,ai.side,entSide!B(state,tgt.kind,tgt.id))==3 // enemy either way, different sides (side-record masks)
				&&!desecrationOngoing!B(state,tgt.id)){ // 0x466950(edi.ntt,0,0)=='sacu' approximation
					auto g=pickGuardCreature(ai,state,tn);
					if(g
					&&!state.movingObjectReadById!((ref cols,i,state)=>cols.creatureStates[i].mode.among(CreatureMode.convertReviving,CreatureMode.thrashing),()=>false)(ai.nodes[g].id,state) // 0x46a840(g.ntt,'ucas') approximation
					&&state.movingObjectReadById!((ref cols,i,ObjectState!B state){
						if(auto wiz=state.getWizardForSide(cols.sides[i])) return buildingIdOf!B(state,wiz.closestEnemyAltar)==tgt.id; // ntt+0xb7c==edi.ntt
						return false;
					},()=>false)(node.id,state)){
						auto r=cast(float)(cast(double)node.desecrateSpell.range*0.9); // fld range; fmul 0.9d; f32
						if(orderTargetRadius(ai,state,g,3,n,r)!=0) // 0x487450(g,3,node,r)
							if(enqueueForcedExecute(ai,state,n,g,node.desecrateSpell,node.desecrateSpell.range,0)!=0){
								node.nextOrderReissue+=7*8; // 7*ds:0x4cfbcc
								return 2;
							}
					}
				}
			}else if((tgt.flags&0x100)&&(tgt.status&0x8000)){
				if(castCachedInRange(ai,state,n,tn)!=0) return 2;
			}
		}
	}
	if(executeBestCast(ai,state,n,0)!=0) return 1;
	static if(shinyAILog) ailog("WIZBRAIN ",ai.side," t",ai.schedTime," n",n," -> t4oBrain");
	return t4oBrain(ai,state,n,cmd,ri);
}

// ---- record update ----

bool proximityTrigger(B)(ref ShinyAI!B ai,ObjectState!B state,int ri,uint cmd){ // 0x48a230
	auto rec=&ai.records[ri];
	if(rec.count==1) return false;
	auto s=rec.stddev.x*rec.stddev.x+rec.stddev.y*rec.stddev.y+rec.stddev.z*rec.stddev.z;
	auto r=cast(double)rec.count*0.1+1.0;
	if(!(r<1.7999999523162842)) r=1.7999999523162842;
	r*=30.0;
	static if(shinyAILog) ailog("PROX ",ai.side," t",ai.schedTime," r",ri," count ",rec.count," s ",s," r^2 ",r*r,cast(double)s<r*r?" -> clustered (brain)":" -> spread");
	if(cast(double)s<r*r) return false;
	auto r4=cast(float)(r*4.0f);
	if(cast(double)s>cast(double)r4*r4) return false; // thaum 0x48a2b1: very spread (s>(4r)^2) -> member brains, no slot19
	for(int m=rec.memberHead;m;){
		auto node=&ai.nodes[m];
		if(node.status==0){ m=node.recN; continue; }
		nodeSlot19(ai,state,m,cast(int)cmd,ri,&rec.center);
		m=node.recN;
	}
	return true;
}
void recordUpdate(B)(ref ShinyAI!B ai,ObjectState!B state,int ri,uint cmd){ // 0x48a070
	auto rec=&ai.records[ri];
	if(rec.count==0) return;
	recordRefresh(ai,state,ri); // entry refresh
	static if(shinyAILog) ailog("RECUPD ",ai.side," t",ai.schedTime," r",ri," cmd ",cmd," count ",rec.count," flags ",rec.flags," tgt ",rec.target," anchor ",rec.anchor," center ",rec.center," leader ",rec.leader);
	if(rec.leader){
		for(int m=rec.memberHead;m;){
			auto node=&ai.nodes[m];
			if(node.status==0){ m=node.recN; continue; }
			if(m==rec.leader){
				auto dx=node.curPos.x-rec.center.x, dy=node.curPos.y-rec.center.y; // 2D
				if(dx*dx+dy*dy<=10000.0f) nodeBrain(ai,state,m,cmd,ri);
				else nodeSlot19(ai,state,m,cmd,ri,&rec.center);
			}else{
				// thaum also calls 0x486aa0(member,&"Prot") here; its result is discarded
				auto p=ai.nodes[rec.leader].extrapPos;
				orderPosRadius(ai,state,m,7,&p,0.0f);
			}
			m=node.recN;
		}
		return;
	}
	if(rec.flags&2){
		auto dx=rec.anchor.x-rec.center.x, dy=rec.anchor.y-rec.center.y; // 2D
		static if(shinyAILog) ailog("RECUPD ",ai.side," t",ai.schedTime," r",ri," anchor-center d2 ",dx*dx+dy*dy,dx*dx+dy*dy<=10000.0f?" (<=100^2, proximity path)":" (>100^2, member brains)");
		if(dx*dx+dy*dy<=10000.0f&&proximityTrigger(ai,state,ri,cmd)) return;
	}
	for(int m=rec.memberHead;m;){
		auto node=&ai.nodes[m];
		if(node.status==0){ m=node.recN; continue; }
		static if(shinyAILog) ailog("RECUPD ",ai.side," t",ai.schedTime," r",ri," member ",m,"(",node.kind," id ",node.id,") -> brain");
		nodeBrain(ai,state,m,cmd,ri);
		m=node.recN;
	}
}
