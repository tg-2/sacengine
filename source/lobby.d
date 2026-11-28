import options:GameMode,Options,Settings,randomGod;
import sids, sacmap, state, controller, network, recording_;
import ntts:God;
import bots.shiny:SideType;
import util;
import loading: loadingPhase, loadingStep, loadingStatus;
import std.string, std.range, std.algorithm, std.stdio;
import std.exception, std.conv;

auto teamSizesToTeams(int[] teamSizes){
	int sumSiz=sum(teamSizes);
	return zip(zip(iota(to!int(teamSizes.length)),teamSizes)
	    .map!(tn=>tn[0].repeat(tn[1]))
	    .joiner.repeat.joiner,
	    recurrence!((a,n)=>a[n-1]+teamSizes.length)(0)
	    .map!(i=>i.repeat(sumSiz)).joiner
	).map!(x=>x[0]+x[1]);
}

// lobby: the game setup that the players see and change before the game starts (shown by the lobby screen)
// the state is owned by the host of a network game, or by the only player of a local game: the host applies the actions
// of the players and replicates the state to the other players
enum LobbySlotType{
	open,
	human,
	computer,
}
struct LobbySlot{
	LobbySlotType type;
	int player=-1; // human: player id (as in the network, 0 in a local game)
	string name;
	God god=randomGod; // (God.none: the player's own spellbook)
	int team=-1;
	bool observer=false; // human: watches the game
	bool ready=false; // human: ready for the game to start
	bool notReady=false; // human: the player switched to "not ready"
	float damageFactor=1.0f; // computer
	bool playing()const{ return type==LobbySlotType.computer||type==LobbySlotType.human&&!observer; }
}
enum LobbyActionType{
	nextGod,
	nextTeam,
	toggleReady,
	takeSlot, // move to an open slot, or swap slots with a computer player (host: also with another player)
	toggleComputer, // add or remove a computer player
	chat,
	start,
}
struct LobbyAction{
	LobbyActionType type;
	int slot=-1;
	string text; // chat
}
struct LobbyData{
	LobbySlot[] slots;
	int gameSlots=0; // slots of the game, players who are in a slot after them when the game starts observe it
	int maxSlots=0; // (slots are added after those of the game up to this number, so that there is an open slot for whoever joins)
	string map;
	// chosen by the host for all slots (--gods, --NvN): the players cannot change theirs until the host changes one in the lobby
	God[] gods; // (God.none: up to the player)
	int[] teams;
	enum chatMessageLimit=512;

	int slotOf(int player)const{
		foreach(i,ref slot;slots)
			if(slot.type==LobbySlotType.human&&slot.player==player) return to!int(i);
		return -1;
	}
	bool godFixed(size_t slot)const{ return slot<gods.length&&gods[slot]!=God.none; }
	bool teamFixed(size_t slot)const{ return slot<teams.length; }
	// what always holds: gods and teams fixed by the host, and after the slots of the game come the occupied slots
	// for observers, followed by one open slot (unless there are maxSlots slots already)
	void applyRules(){
		foreach(i,ref slot;slots){
			if(slot.type==LobbySlotType.open) continue;
			if(godFixed(i)) slot.god=gods[i];
			if(teamFixed(i)) slot.team=teams[i];
		}
		size_t numSlots=gameSlots;
		foreach(i;gameSlots..slots.length){
			if(slots[i].type==LobbySlotType.open) continue;
			if(i!=numSlots) swap(slots[numSlots],slots[i]);
			numSlots++;
		}
		if(numSlots<maxSlots) numSlots++;
		if(slots.length!=numSlots){
			slots.length=numSlots;
			slots.assumeSafeAppend();
		}
	}
	// puts a player into the preferred slot if it is open, otherwise players get the first open slot and observers the last one (-1: none)
	int addPlayer(int player,int preferredSlot,bool observer){
		auto slot=preferredSlot;
		if(slot<0||slot>=slots.length||slots[slot].type!=LobbySlotType.open){
			slot=-1;
			foreach(i,ref candidate;slots){
				if(candidate.type!=LobbySlotType.open) continue;
				slot=to!int(i);
				if(!observer) break;
			}
		}
		if(slot==-1) return -1;
		slots[slot]=LobbySlot(LobbySlotType.human,player);
		slots[slot].observer=observer;
		return slot;
	}
	void removePlayer(int player){
		auto slot=slotOf(player);
		if(slot!=-1) slots[slot]=LobbySlot.init;
	}
	// what a player may do (host: this player is the host)
	bool allowed(int player,bool host,ref const LobbyAction action)const{
		if(action.type<LobbyActionType.min||action.type>LobbyActionType.max) return false;
		auto own=slotOf(player);
		final switch(action.type) with(LobbyActionType){
			case nextGod,nextTeam,toggleReady,takeSlot,toggleComputer:
				if(action.slot<0||action.slot>=slots.length) return false;
				auto type=slots[action.slot].type;
				if(action.type==toggleReady) return action.slot==own;
				bool computer=host&&type==LobbySlotType.computer;
				if(action.type==nextGod) return action.slot==own||computer; // (fixed god: observe or not)
				if(action.type==nextTeam) return action.slot==own&&(host||!teamFixed(own))||computer;
				if(action.type==toggleComputer) return host&&type!=LobbySlotType.human&&action.slot<gameSlots;
				if(type==LobbySlotType.computer&&own>=gameSlots) return false; // (computer players do not observe)
				return own!=-1&&action.slot!=own&&(host||type!=LobbySlotType.human);
			case chat: return action.text.length&&action.text.length<=chatMessageLimit;
			case start: return host;
		}
	}
	void apply(int player,bool host,ref const LobbyAction action)in{
		assert(allowed(player,host,action));
	}do{
		switch(action.type) with(LobbyActionType){
			case nextGod: // gods in order, then random; human players observe after the last god
				if(host) gods=[];
				auto slot=&slots[action.slot];
				bool human=slot.type==LobbySlotType.human;
				if(human&&slot.observer){
					slot.observer=false;
					slot.god=randomGod;
				}else if(human&&(godFixed(action.slot)||slot.god==God.max)) slot.observer=true;
				else slot.god=slot.god==God.max?randomGod:slot.god==randomGod||slot.god==God.none?God.persephone:cast(God)(slot.god+1);
				break;
			case nextTeam: // teams in order, then none
				if(host) teams=[];
				auto slot=&slots[action.slot];
				slot.team=slot.team<0?0:slot.team>=2?-1:slot.team+1;
				break;
			case toggleReady:
				auto slot=&slots[action.slot];
				slot.notReady=!slot.notReady;
				if(slot.notReady) slot.ready=false;
				break;
			case takeSlot: swap(slots[slotOf(player)],slots[action.slot]); break;
			case toggleComputer:
				auto slot=&slots[action.slot];
				*slot=slot.type==LobbySlotType.open?LobbySlot(LobbySlotType.computer):LobbySlot.init;
				break;
			default: break; // (not about the state)
		}
		applyRules();
	}
}
// the lobby as shown to a player
struct LobbyView{
	const(LobbyData)* data;
	int me=-1; // (player id)
	bool isHost=false;
	bool canStart=false;
	const(string)[] chat; // ("name: message")
	string mapFilename; // local file of the map, if any (for its preview)
	bool allowed(ref const LobbyAction action)const{ return data&&data.allowed(me,isHost,action); }
}

// god of a spellbook, as shown in the lobby
God lobbyGod(ref Settings settings){
	if(settings.randomGod) return randomGod;
	foreach(god;God.persephone..God.max+1)
		if(settings.spellbook==defaultSpells[god]) return cast(God)god;
	return God.none;
}

// game initialization from the lobby, playerSettings gives the settings of a human player
// a slot only gets a wizard if the map has an altar for its side
GameInit!B gameInit(B)(SacMap!B map,Sides!B sides_,ref const LobbyData lobby,scope Settings delegate(int player) playerSettings,ref Options options){
	GameInit!B gameInit;
	auto numSlots=lobby.gameSlots;
	auto slots=lobby.slots[0..numSlots];
	gameInit.slots=new GameInit!B.Slot[](numSlots);
	auto sides=options.gameMode==GameMode.scenario?
		iota(numSlots).map!(i=>sides_.scenarioSide(i)).array:
		iota(numSlots).map!(i=>sides_.multiplayerSide(i)).array;
	auto teams=(-1).repeat(numSlots).array;
	if(options.gameMode!=GameMode.scenario){
		foreach(i,ref slot;slots)
			teams[i]=slot.playing?slot.team:lobby.teamFixed(i)?lobby.teams[i]:-1;
	}
	if(options.shuffleAltars){
		import std.random: randomShuffle;
		randomShuffle(sides);
	}
	if(options.shuffleTeams){
		import std.random: randomShuffle;
		randomShuffle(teams);
	}
	if(options.shuffleSides){
		import std.random: randomShuffle;
		randomShuffle(zip(sides,teams));
	}
	foreach(i,side;options.sides)
		if(i<sides.length) sides[i]=options.gameMode==GameMode.scenario?sides_.scenarioSide(side):sides_.multiplayerSide(side);
	int altarSides=0;
	import sacobject: SacBuilding;
	foreach(ref structure;map.ntts.structures){
		auto side=structure.side;
		if(side<0||side>=32) side=31;
		if(SacBuilding!B.get(structure.tag).isAltar) altarSides|=1<<side;
	}
	void placeWizard(int slot,ref Settings settings,God god,bool computer){
		import std.random: uniform;
		auto side=sides[slot];
		if(options.gameMode!=GameMode.scenario&&!(0<=side&&side<32&&altarSides&1<<side))
			return; // (state.placeWizard silently skips wizards whose side has no altar)
		char[4] tag=settings.wizard[0..4];
		if(options.randomWizards){
			import nttData:wizards;
			tag=cast(char[4])wizards[uniform!"[)"(0,$)];
		}
		auto name=settings.name;
		auto level=settings.level;
		auto souls=settings.souls;
		float experience=0.0f;
		auto minLevel=settings.minLevel;
		auto maxLevel=settings.maxLevel;
		auto xpRate=settings.xpRate;
		auto spells=settings.spellbook;
		if(!computer){
			if(god==randomGod||options.randomGods) spells=defaultSpells[uniform!"[]"(1,5)];
			else if(god!=God.none) spells=defaultSpells[god];
			if(options.randomSpellbooks) spells=randomSpells();
			god=God.none;
		}
		if(lobby.godFixed(slot)) god=lobby.gods[slot];
		if(god!=God.none) spells=defaultSpells[god==randomGod?cast(God)uniform!"[]"(1,5):god];
		auto spellbook=getSpellbook!B(spells);
		import nttData:WizardTag;
		assert(gameInit.slots[slot]==GameInit!B.Slot(-1));
		int wizardIndex=cast(int)gameInit.wizards.length;
		gameInit.slots[slot]=GameInit!B.Slot(wizardIndex);
		gameInit.slots[slot].sideType=computer?SideType.shinyBot:SideType.human;
		gameInit.wizards~=GameInit!B.Wizard(to!WizardTag(tag),name,side,level,souls,experience,minLevel,maxLevel,xpRate,spellbook);
	}
	foreach(i,ref slot;slots){
		if(!slot.playing) continue;
		if(slot.type==LobbySlotType.human){
			auto settings=playerSettings(slot.player);
			placeWizard(to!int(i),settings,slot.god,false);
		}else{
			import std.random: uniform;
			import nttData: wizards, randomWizardName;
			auto botSettings=options.settings;
			botSettings.name=slot.name.length?slot.name:randomWizardName();
			botSettings.wizard=cast(char[4])wizards[uniform!"[)"(0,$)];
			placeWizard(to!int(i),botSettings,slot.god==God.none?randomGod:slot.god,true);
		}
	}
	auto damageFactors=1.0f.repeat(numSlots).array;
	foreach(i,f;options.damageFactors)
		if(i<numSlots) damageFactors[i]=f;
	foreach(i,ref slot;slots)
		if(slot.type==LobbySlotType.computer) damageFactors[i]*=slot.damageFactor;
	if(options.shuffleSlots){
		import std.random: randomShuffle;
		randomShuffle(zip(gameInit.slots,teams,damageFactors));
	}
	gameInit.damageFactors=damageFactors;
	if(options.gameMode!=GameMode.scenario){
		foreach(i;0..numSlots){
			foreach(j;i+1..numSlots){
				int wi=gameInit.slots[i].wizardIndex, wj=gameInit.slots[j].wizardIndex;
				if(wi==-1||wj==-1) continue;
				int s=gameInit.wizards[wi].side, t=gameInit.wizards[wj].side;
				if(s==-1||t==-1) continue;
				assert(s!=t);
				int x=teams[i], y=teams[j];
				auto stance=x!=-1&&y!=-1&&x==y?Stance.ally:Stance.enemy;
				gameInit.stanceSettings~=GameInit!B.StanceSetting(s,t,stance);
				gameInit.stanceSettings~=GameInit!B.StanceSetting(t,s,stance);
			}
		}
		if(options.mirrorMatch){
			int[int] teamLoc;
			int[][] teamIndex;
			foreach(slot;0..numSlots) if(teams[slot]!=-1){
				if(teams[slot]!in teamLoc){
					teamLoc[teams[slot]]=cast(int)teamIndex.length;
					teamIndex~=[[]];
				}
				teamIndex[teamLoc[teams[slot]]]~=slot;
			}
			foreach(slot;0..numSlots) if(teams[slot]<0) teamIndex~=[slot];
			teamIndex.sort!("a.length > b.length",SwapStrategy.stable);
			foreach(t;teamIndex[1..$]){
				foreach(i;0..t.length){
					void copyWizard(T)(ref T a,ref T b){
						if(options.randomWizards) a.tag=b.tag;
						a.spellbook=b.spellbook;
					}
					auto w1=gameInit.slots[t[i]].wizardIndex, w2=gameInit.slots[teamIndex[0][i]].wizardIndex;
					if(w1!=-1&&w2!=-1) copyWizard(gameInit.wizards[w1],gameInit.wizards[w2]);
				}
			}
		}
	}
	gameInit.gameMode=options.gameMode;
	gameInit.gameModeParam=options.gameModeParam;
	gameInit.replicateCreatures=options.replicateCreatures;
	gameInit.protectManafounts=options.protectManafounts;
	gameInit.terrainSineWave=options.terrainSineWave;
	gameInit.mapWizards=options.mapWizards;
	gameInit.mapCreatures=options.mapCreatures;
	gameInit.mapSouls=options.mapSouls;
	gameInit.fogOfWar=options.fogOfWar;
	gameInit.fogOfWar3d=options.fogOfWar3d;
	gameInit.alliedVision=options.alliedVision;
	gameInit.alliedBeamVision=options.alliedBeamVision;
	gameInit.collectAlliedSouls=options.collectAlliedSouls;
	gameInit.friendlyFire=options.friendlyFire;
	gameInit.damageFactor=options.damageFactor;
	gameInit.botDamageFactor=options.botDamageFactor;
	gameInit.alwaysGib=options.alwaysGib;
	gameInit.revealBlueSouls=options.revealBlueSouls;
	gameInit.dimUnexplored=options.dimUnexplored;
	gameInit.randomCreatureScale=options.randomCreatureScale;
	gameInit.enableDropSoul=options.enableDropSoul;
	gameInit.targetDroppedSouls=options.targetDroppedSouls;
	gameInit.charmNeutralCreatures=options.charmNeutralCreatures;
	gameInit.enableParticles=options.enableParticles;
	gameInit.greenAllySouls=options.greenAllySouls;
	gameInit.fasterStandupTimes=options.fasterStandupTimes;
	gameInit.fasterCastingTimes=options.fasterCastingTimes;
	gameInit.terrainScars=options.terrainScars;
	gameInit.maxScarTextures=options.maxScarTextures;
	gameInit.alwaysOnMinimap=options.alwaysOnMinimap;
	gameInit.betaPatchBots=options.betaPatchBots;
	gameInit.aiSides=options.aiSides;
	if(gameInit.greenAllySouls){
		foreach(ref slot;slots)
			if(slot.type==LobbySlotType.human&&!slot.observer&&playerSettings(slot.player).refuseGreenSouls)
				gameInit.greenAllySouls=false;
	}
	return gameInit;
}

enum LobbyState{
	empty,
	initialized,
	offline,
	connected,
	synched,
	commitHashReady,
	incompatibleVersion,
	readyToLoad,
	waitingForClients,
	readyToStart,
}

class Lobby(B){
	LobbyState state;
	this(){}
	Network!B network=null;
	int slot;
	bool isHost(){ return !network||network.isHost; }
	Recording!B playback=null;
	Recording!B toContinue=null;

	SacMap!B map;
	ubyte[] mapData;
	Sides!B sides;
	Proximity!B proximity;
	PathFinder!B pathFinder;
	Triggers!B triggers;

	GameState!B gameState;
	GameInit!B gameInit;
	Recording!B recording=null;

	bool hasSlot;
	int wizId;
	Controller!B controller;

	void initialize(int slot,ref Options options)in{
		assert(state==LobbyState.empty);
	}do{
		this.slot=slot;
		state=LobbyState.initialized;
	}

	private void createNetwork(ref Options options)in{
		assert(!network);
	}do{
		network=new Network!B(options);
	}

	import core.time: MonoTime, msecs, seconds;
	MonoTime nextJoinAttempt; // (MonoTime.init: attempt immediately)
	enum joinRetryInterval=200.msecs;

	import zerotier: ZerotierConnector;
	ZerotierConnector zerotier;

	// --delay-start (for easier recording): count down once per second before connecting
	int delayStartLeft=-1; // (-1: not initialized yet)
	MonoTime nextDelayStartTick;
	bool waitDelayStart(ref Options options){
		if(delayStartLeft==-1) delayStartLeft=max(0,options.delayStart);
		auto now=MonoTime.currTime;
		if(now<nextDelayStartTick) return true;
		if(!delayStartLeft) return false;
		writeln(delayStartLeft);
		delayStartLeft--;
		nextDelayStartTick=now+1.seconds;
		return true;
	}

	// does not block, can be called each frame until it returns true
	bool tryConnect(ref Options options)in{
		assert(state==LobbyState.initialized);
	}do{
		bool useZerotier=!!options.zerotierNetwork;
		if(useZerotier&&(options.host||options.joinIP!="")&&!zerotier.ready){
			zerotier.identityFolder=options.zerotierIdentity;
			zerotier.netId=options.zerotierNetwork;
			if(!zerotier.step()) return false;
		}
		if(waitDelayStart(options)) return false;
		if(options.host){
			if(!network) createNetwork(options);
			if(options.continueFilename!=""||options.playbackFilename!=""&&options.continueFrame)
				network.acceptingNewConnections=false;
			network.hostGame(options.settings,useZerotier);
			state=LobbyState.connected;
			return true;
		}
		if(options.joinIP!=""){
			auto now=MonoTime.currTime;
			if(now<nextJoinAttempt) return false;
			nextJoinAttempt=now+joinRetryInterval;
			if(!network) createNetwork(options);
			auto result=network.joinGame(options.joinIP,listeningPort,options.settings,useZerotier);
			if(result) state=LobbyState.connected;
			return result;
		}
		state=LobbyState.offline;
		return true;
	}

	bool canPlayRecording(){ return state==LobbyState.offline && !playback && !toContinue; }
	void initializePlayback(Recording!B recording,int frame,ref Options options)in{
		assert(canPlayRecording);
	}do{
		if(frame<0){
			frame=max(0,to!int(recording.commands.length)+frame);
			options.continueFrame=frame;
		}
		playback=recording;
		enforce(playback.mapName.endsWith(".scp")||playback.mapName.endsWith(".HMAP"));
		options.map=playback.mapName;
		slot=-1;
		map=playback.map;
		sides=playback.sides;
		proximity=playback.proximity;
		pathFinder=playback.pathFinder;
		triggers=playback.triggers;
		options.mapHash=map.crc32;
		enum supportRollback=false;
		gameState=new GameState!B(map,sides,proximity,pathFinder,triggers,supportRollback);
		gameState.commands=playback.commands;
		if(gameState.commands.length<frame+1) gameState.commands.length=frame+1;
		gameState.initMap();
	}

	bool canContinue(){ return state.among(LobbyState.offline, LobbyState.connected) && isHost && !toContinue && !playback; }
	void continueGame(Recording!B recording,int frame,ref Options options)in{
		assert(canContinue);
	}do{
		toContinue=recording;
		if(frame!=-1){
			if(frame<0){
				frame=max(0,to!int(toContinue.commands.length)+frame);
				options.continueFrame=frame;
			}
			toContinue.commands.length=frame;
			toContinue.commands~=Array!(Command!B)();
		}else{
			if(toContinue.commands[$-1].length) toContinue.commands~=Array!(Command!B)();
			frame=max(0,to!int(toContinue.commands.length)-1);
			options.continueFrame=frame;
		}
		options.map=toContinue.mapName;
		if(network) network.hostSettings=options.settings;
		options.numSlots=to!int(toContinue.gameInit.slots.length);
		map=toContinue.map;
		sides=toContinue.sides;
		proximity=toContinue.proximity;
		pathFinder=toContinue.pathFinder;
		triggers=toContinue.triggers;
		if(network){
			assert(state==LobbyState.connected);
			static struct SlotData{
				int slot;
				string name;
				int committedFrame;
			}
			SlotData toSlotData(int i){
				auto wizardIndex=toContinue.gameInit.slots[i].wizardIndex;
				string name=null;
				if(0<=wizardIndex&&wizardIndex<toContinue.gameInit.wizards.length)
					name=toContinue.gameInit.wizards[wizardIndex].name;
				return SlotData(i,name,frame);
			}
			assert(network.players.length==1);
			network.players[network.me].committedFrame=frame;
			network.initSlots(iota(options.numSlots).map!toSlotData);
		}else assert(state==LobbyState.offline);
		options.mapHash=map.crc32;
	}

	bool trySynch(){
		network.update(controller); // (may be null)
		bool result=network.synched;
		if(result||network.isHost) state=LobbyState.synched;
		return result;
	}

	void updateSettings(ref Options options)in{
		assert(network&&isHost);
	}do{
		if(options.synchronizeObserverChat) network.synchronizeSetting!"observerChat"();

		if(options.synchronizeLevel) network.synchronizeSetting!"level"();
		if(options.synchronizeSouls) network.synchronizeSetting!"souls"();

		if(options.synchronizeLevelBounds){
			network.synchronizeSetting!"minLevel"();
			network.synchronizeSetting!"maxLevel"();
		}
		if(options.synchronizeXpRate) network.synchronizeSetting!"xpRate"();

		network.synchronizeSetting!"pauseOnDrop"();
	}

	bool synchronizeSettings(ref Options options)in{
		assert(!!network);
		with(LobbyState) assert(state.among(synched,commitHashReady,waitingForClients,readyToLoad,readyToStart));
	}do{
		//writeln(10);
		if(state<LobbyState.commitHashReady){
			if(isHost) hashMap(options);
			network.updateSetting!"mapHash"(options.mapHash);
			network.updateStatus(PlayerStatus.commitHashReady);
			state=LobbyState.commitHashReady;
		}
		//writeln(20);
		if(state==LobbyState.commitHashReady){
			if(!network.isHost){
				network.update(controller); // (may be null)
				if(!network.hostCommitHashReady)
					return false;
				if(network.hostSettings.commit!=options.commit){
					writeln("incompatible version #");
					writeln("host is using version ",network.hostSettings.commit);
					network.disconnectPlayer(network.host,null);
					state=LobbyState.incompatibleVersion;
					return false;
				}
			}
			state=LobbyState.readyToLoad;
		}
		//writeln(30);
		if(!network.mapHashed){
			if(!network.isHost){
				if(!network.waitingOnData&&!network.hasMapData){
					auto mapName=network.hostSettings.map;
					network.updateSetting!"map"(mapName);
					auto hash=network.hostSettings.mapHash;
					version(Windows){}else mapName=mapName.replace("\\","/"); // hack
					import std.file: exists;
					if(exists(mapName)){
						options.map=mapName; // (loaded when the game starts)
						options.mapHash=mapFileHash(mapName);
					}
					network.updateSetting!"mapHash"(options.mapHash);
					network.updateStatus(PlayerStatus.mapHashed);
				}
			}else{
				network.mapData.length=mapData.length;
				network.mapData.data[]=mapData[];
				network.updateStatus(PlayerStatus.mapHashed);
			}
		}
		//writeln(40);
		void loadMap(string mapName){ // (downloaded map, its hash was already checked)
			options.map=mapName; // (loaded when the game starts)
			options.mapHash=mapFileHash(mapName);
			auto hash=network.hostSettings.mapHash;
			enforce(options.mapHash==hash,"map hash mismatch");
			network.updateSetting!"mapHash"(options.mapHash);
			network.updateStatus(PlayerStatus.mapHashed);
		}
		network.update(controller); // (may be null)
		if(!network.synchronizeMap(&loadMap))
			return false;
		//writeln(50);
		if(options.refuseGreenSouls)
			enforce(network.settings.refuseGreenSouls,"host attempted to override --refuse-green-souls");
		auto localMapName=options.map;
		options.settings=network.settings;
		version(Windows){
			if(localMapName!=options.map) localMapName=options.map;
		}else{
			auto networkMapName=options.map.replace("\\","/");
			if(localMapName.replace("\\","/")!=networkMapName) localMapName=networkMapName;
		}
		options.map=localMapName;
		slot=network.slot;
		if(!isHost) network.updateStatus(PlayerStatus.pendingGameInit); // TODO: tie this to thumbs up
		return true;
	}

	// network game: the host only reads the map file (for its hash and to send it to other players), the map is loaded when the game starts
	void hashMap(ref Options options){
		if(map) options.mapHash=map.crc32; // (continued game)
		else options.mapHash=mapFileHash(options.map,&mapData);
	}

	void loadMap(ref Options options){
		if(!map){
			loadingPhase(0.0f,0.4f);
			map=loadSacMap!B(options.map,&mapData); // TODO: compute hash without loading map?
		}
		options.mapHash=map.crc32; // TODO: store this somewhere else?
		if(state==LobbyState.offline) state=LobbyState.readyToLoad;
	}

	bool loadGame(bool lastLoad,ref Options options)in{
		assert(!!map);
		assert(state.among(LobbyState.readyToLoad,LobbyState.waitingForClients));
	}do{
		/+if(network.isHost){
			network.load();
		}else{
			if(!network.loading&&network.players[network.me].status!=PlayerStatus.desynched) // desynched at start if late join
				return false;
		}+/
		void initState(){
			if(!gameState){
				loadingPhase(0.4f,0.5f);
				if(!sides) sides=new Sides!B(map.sids);
				if(!proximity) proximity=new Proximity!B();
				if(!pathFinder) pathFinder=new PathFinder!B(map);
				loadingStep(1,3);
				if(!triggers) triggers=new Triggers!B(map.trig,map.ntts);
				auto supportRollback=network !is null;
				gameState=new GameState!B(map,sides,proximity,pathFinder,triggers,supportRollback);
				loadingStep(2,3);
				gameState.initMap();
				loadingStep(3,3);
			}
		}
		if(!playback||network){
			if(network){
				import serialize_;
				if(network.isHost){
					initState();
					if(toContinue) gameInit=toContinue.gameInit;
					else initializeGame(options);
					gameInit.serialized(&network.initGame);
				}else{
					network.update(controller); // (may be null)
					if(!network.hasGameInitData())
						return lastLoad?false:!!gameState;
					slot=network.slot; // (the host decides it with the game initialization)
					initState();
					scope gameInitData=network.gameInitData.data;
					deserialize(gameInit,gameState.current,gameInitData);
					network.clearGameInitData();
				}
			}else{
				initState();
				if(options.gameMode==GameMode.scenario){ // TODO: move to gameInit!B?
					auto singleplayerSides=iota(map.sids.length).filter!(i=>!!(map.sids[i].assignment&PlayerAssignment.singleplayerSide)).map!(i=>map.sids[i].id);
					if(!singleplayerSides.empty && options.slot==0){
						auto side=singleplayerSides.front;
						if(0<=side&&side<32){
							options.minLevel=to!int(map.levl.singleStartLevel);
							options.level=options.minLevel;
							options.maxLevel=to!int(map.levl.singleMaxLevel);
							options.souls=to!int(map.levl.singleSouls);
							import ntts:God;
							if(map.levl.singleAssociatedGod && map.levl.singleAssociatedGod<=God.max){
								options.spellbook=defaultSpells[options.god];
							}
						}
					}
				}else if(options.useMapSettings){
					options.minLevel=to!int(map.levl.multiMinLevel);
					options.level=options.minLevel;
					options.maxLevel=to!int(map.levl.multiMaxLevel);
					options.souls=to!int(map.levl.multiSouls);
				}
				if(toContinue) gameInit=toContinue.gameInit;
				else initializeGame(options);
			}
		}else gameInit=playback.gameInit;
		if(options.refuseGreenSouls)
			enforce(!gameInit.greenAllySouls||options.slot==-1,"attempted to initialize a game with green souls");
		if((!playback||network)&&options.recordingFilename.length){
			if(!recording) recording=new Recording!B(options.map,map,sides,proximity,pathFinder,triggers);
			recording.gameInit=gameInit;
			recording.logCore=options.logCore;
			if(options.quickContinue) recording.logCore=max(recording.logCore,1);
		}
		loadingStatus.initializingGame=true; // (the game screen is blacked out while the state is rebuilt)
		scope(exit) loadingStatus.initializingGame=false;
		gameState.rollback();
		loadingPhase(0.5f,0.95f);
		gameState.initGame(gameInit);
		hasSlot=0<=slot&&slot<gameState.slots.length;
		wizId=hasSlot?gameState.slots[slot].wizard:0;
		initController(options);
		// TODO: if game init can place additional buildings this would need to be reflected here:
		loadingPhase(0.95f,1.0f);
		if(!gameState.current.map.meshes.length)
			gameState.current.map.makeMeshes(options.enableMapBottom);
		loadingStep(1,1);
		if(toContinue){
			gameState.commands=toContinue.commands;
			assert(options.continueFrame+1==gameState.commands.length);
		}
		if(toContinue||playback&&options.continueFrame){
			playAudio=false;
			auto recording=toContinue?toContinue:playback;
			assert(!!recording);
			if(options.quickContinue&&options.continueFrame>0){
				ObjectState!B bestState=null;
				foreach(state;recording.core.data[]){
					if(state.frame>options.continueFrame) continue;
					if(!bestState||bestState.frame<state.frame){
						bestState=state;
					}
				}
				if(bestState){
					writeln("continue: keyframe found at frame ",bestState.frame);
					gameState.replaceState(bestState);
					gameState.rollback();
				}else writeln("continue: replay does not contain a suitable key frame state, resimulating...");
			}
			bool afterStep(){
				recording.report(gameState);
				if(gameState.current.frame%1000==0){
					writeln("continue: simulated ",gameState.current.frame," of ",options.continueFrame," frames");
				}
				B.processEvents();
				return false;
			}
			gameState.simulateCommittedTo!afterStep(options.continueFrame);
			playAudio=true;
			assert(options.continueFrame==-1||gameState.current.frame==options.continueFrame);
			if(network){
				assert(network.isHost);
				//foreach(i;network.connectedPlayerIds) if(i!=network.host) network.updateStatus(cast(int)i,PlayerStatus.desynched);
				network.continueSynchAt(gameState.current.frame);
				if(controller){
					assert(network is controller.network);
					controller.updateNetworkGameState();
				}
			}
		}
		return true;
	}

	bool update(ref Options options)in{
		with(LobbyState)
		assert(state.among(offline,connected,synched,commitHashReady,waitingForClients,readyToLoad));
	}do{
		//writeln(state," ",network.players.map!((ref p)=>p.status));
		if(network&&!isHost&&network.hostDropped){ // (before the game has started)
			B.hideLobby();
			B.showHostQuit();
			return false;
		}
		if(network){
			//writeln(1);
			if(state==LobbyState.connected){
				if(!trySynch())
					return false;
			}
			//writeln(2);
			if(isHost) updateSettings(options);
			with(LobbyState)
			if(state.among(synched,commitHashReady,waitingForClients,readyToLoad,readyToStart)){
				if(!synchronizeSettings(options))
					return false;
			}
		}
		//writeln(3);
		if(!toContinue&&!playback&&state.among(LobbyState.offline,LobbyState.readyToLoad,LobbyState.waitingForClients))
			return waitForGameStart(options);
		if(!network) loadMap(options);
		assert(!!map||network); // (network game: map loaded when the game starts)
		if(state==LobbyState.readyToLoad||state==LobbyState.waitingForClients){
			if(state==LobbyState.readyToLoad||network){
				bool reinitialize=!gameState||!network||network.pendingGameInit;
				if(reinitialize){
					if(!loadGame(false,options))
						return false;
				}
				if(network&&network.isHost){
					foreach(i;0..network.players.length){
						if(network.players[i].status==PlayerStatus.pendingGameInit){
							if(!reinitialize&&!network.players[i].allowedToControlState){
								import serialize_;
								gameInit.serialized((scope ubyte[] gameInitData)=>network.initGame(to!int(i), gameInitData));
							}
							network.updateStatus(to!int(i), PlayerStatus.readyToLoad);
							with(network) if(controller){
								auto message=players[i].allowedToControlState?"has joined the game.":"will observe.";
								sidechannelChatMessage(ChatMessageType.network,players[i].settings.name,message,controller);
							}
						}
					}
				}
				if(reinitialize){
					B.setState(gameState);
					if(hasSlot) B.setSlot(slot);
					if(wizId) B.focusCamera(wizId,false);
					else if(!B.scene.mouse.visible&&!B.scene.fpview.active) B.scene.fpview.active=true;
				}
			}
			if(network){
				if(toContinue){
					network.pauseOnDropOnce=true;
					network.updateStatus(PlayerStatus.readyToLoad);
					state=LobbyState.readyToStart;
				}else state=LobbyState.waitingForClients;
			}else state=LobbyState.readyToStart;
		}
		//writeln(4);
		if(state==LobbyState.waitingForClients){
			assert(!!network);
			network.update(controller); // (may be null)
			//writeln(network.isHost," ",network.numReadyPlayers," ",(network.players[network.host].wantsToControlState)," ",options.numSlots," ",network.clientsReadyToLoad()," ",network.readyToLoad," ",network.pendingResynch);
			if(network.lateJoining||network.pendingResynch){
				initController(options);
				controller.lateJoining=true;
				state=LobbyState.readyToStart;
			}else if(!network.readyToLoad){
				if(!network.isHost) return false;
				auto occupiedSlots=network.numReadyPlayers;
				if(network.players[network.host].wantsToControlState)
					occupiedSlots+=1;
				occupiedSlots+=gameInit.slots.count!(slot=>slot.sideType==SideType.shinyBot);
				if(occupiedSlots>=options.numSlots&&network.clientsReadyToLoad()){
					network.acceptingNewConnections=false;
					//network.stopListening();
					loadGame(true,options);
					network.updateStatus(PlayerStatus.readyToLoad);
					assert(network.readyToLoad());
					state=LobbyState.readyToStart;
				}else return false;
			}else{
				if(!network.isHost) loadGame(true,options);
				state=LobbyState.readyToStart;
			}
		}
		return state==LobbyState.readyToStart;
	}

	// the lobby (see LobbyData): the players set up the game until the host starts it, only then the map is loaded and the game initialized
	// network game: the host sets its own status to pendingGameInit when the game starts: the other players load the map meanwhile,
	// then the host sends them the game initialization and marks them ready to load (as before, in this order)
	LobbyData data;
	Array!string chat; // ("name: message")
	bool lobbyInitialized=false, startRequested=false;
	bool gameStarting=false, gameInitialized=false;
	int me(){ return network?network.me:0; }
	bool waitForGameStart(ref Options options)in{
		assert(!toContinue&&!playback);
	}do{
		if(network){
			state=LobbyState.waitingForClients;
			B.setLobbyNetwork(network,data.gameSlots?data.gameSlots:-1); // (players are shown while waiting)
			network.update(controller); // (may be null)
		}
		bool lateJoining=false;
		if(isHost){
			if(!gameStarting){
				if(!updateLobby(options)) return false;
				B.hideLobby();
				if(network){
					network.acceptingNewConnections=false;
					network.updateStatus(PlayerStatus.pendingGameInit); // (the other players start loading the map)
				}
				gameStarting=true;
			}
		}else{
			lateJoining=network.lateJoining||network.pendingResynch;
			auto hostStatus=network.players[network.host].status;
			if(!lateJoining&&!(isConnectedStatus(hostStatus)&&hostStatus>=PlayerStatus.pendingGameInit)){
				if(!gameStarting) followLobby(options);
				return false; // (game not started yet)
			}
			B.hideLobby();
			gameStarting=true;
		}
		if(!network) loadMap(options);
		else if(!map){
			loadingPhase(0.0f,0.4f);
			map=loadSacMap!B(options.map);
			enforce(cast(int)map.crc32==options.mapHash,"map file changed");
		}
		if(!gameInitialized){
			if(!loadGame(true,options)) // (host: sends the game initialization to the other players)
				return false; // (waiting for the game initialization from the host)
			gameInitialized=true;
		}
		if(network){
			if(isHost){
				foreach(i,ref player;network.players.data)
					if(i!=network.me&&player.status==PlayerStatus.pendingGameInit)
						network.updateStatus(to!int(i),PlayerStatus.readyToLoad);
				network.updateStatus(PlayerStatus.readyToLoad);
			}else if(lateJoining){
				initController(options);
				controller.lateJoining=true;
			}else if(!isReadyToLoadStatus(network.players[network.me].status))
				return false; // (the host marks this player ready to load right after sending the game initialization)
		}
		B.setState(gameState);
		if(hasSlot) B.setSlot(slot);
		if(wizId) B.focusCamera(wizId,false);
		else if(!B.scene.mouse.visible&&!B.scene.fpview.active) B.scene.fpview.active=true;
		state=LobbyState.readyToStart;
		return true;
	}
	enum lobbySlotLimit=12; // (including the slots that are added for observers)
	// the lobby screen is shown in network games, a local game only stops in the lobby with --lobby
	bool lobbyShown(ref Options options){ return network||options.lobby; }
	void initializeLobby(ref Options options)in{
		assert(isHost&&!lobbyInitialized);
	}do{
		data.slots=new LobbySlot[](max(0,options.numSlots));
		data.gameSlots=to!int(data.slots.length);
		data.maxSlots=network?max(data.gameSlots,lobbySlotLimit):data.gameSlots; // (nobody joins a local game)
		data.map=options.map;
		data.gods=options.gods.dup;
		if(options.gameMode!=GameMode.scenario&&options.teamSizes.length)
			data.teams=teamSizesToTeams(options.teamSizes).take(data.slots.length).array;
		data.applyRules();
		updatePlayers(options); // (this player takes its slot before the computer players)
		foreach(k,botSlot;options.botSlots){
			if(botSlot<0||botSlot>=data.gameSlots||data.slots[botSlot].type!=LobbySlotType.open) continue;
			auto slot=LobbySlot(LobbySlotType.computer);
			if(k<options.botNames.length) slot.name=options.botNames[k];
			if(k<options.botGods.length&&options.botGods[k]!=God.none) slot.god=options.botGods[k];
			if(k<options.botTeams.length) slot.team=options.botTeams[k];
			if(k<options.botDamageFactors.length) slot.damageFactor=options.botDamageFactors[k];
			data.slots[botSlot]=slot;
		}
		data.applyRules();
		lobbyInitialized=true;
	}
	// players get a slot when they arrive (as they prefer, if possible) and free it when they leave
	Array!bool inLobby; // (by player id)
	void updatePlayers(ref Options options)in{
		assert(isHost);
	}do{
		void update(int player,ref Settings settings,bool present,bool ready){
			if(inLobby.length<=player) inLobby.length=player+1;
			if(inLobby[player]!=present){ // (messages of the original lobby)
				import nttData: formTexts;
				inLobby[player]=present;
				if(player!=me) say(text(playerName(player,options)," ",present?formTexts.get("njlp","has joined the game."):formTexts.get("vllp","has left the game.")));
			}
			auto slot=data.slotOf(player);
			if(!present){
				data.removePlayer(player);
				return;
			}
			if(slot==-1){
				slot=data.addPlayer(player,settings.slot,settings.observer);
				if(slot==-1) return; // (no open slot)
				data.slots[slot].god=lobbyGod(settings);
				data.slots[slot].team=settings.team;
			}
			data.slots[slot].name=settings.name;
			data.slots[slot].ready=ready&&!data.slots[slot].notReady;
		}
		if(network){
			foreach(i,ref player;network.players.data)
				update(to!int(i),player.settings,isConnectedStatus(player.status),i==network.host||player.status==PlayerStatus.pendingGameInit);
		}else update(me,options.settings,true,true);
		data.applyRules();
	}
	// computer players get a random name that no other player in the lobby has (unless they were named with --bot-names)
	void nameComputers(){
		import nttData: randomWizardName;
		foreach(ref slot;data.slots){
			if(slot.type!=LobbySlotType.computer||slot.name.length) continue;
			foreach(_;0..16){
				slot.name=randomWizardName();
				if(data.slots.count!((ref other)=>other.name==slot.name)==1) break;
			}
		}
	}
	string playerName(int player,ref Options options){
		auto name=network?network.players[player].settings.name:options.name;
		return name.length?name:"Anonymous";
	}
	void say(string line)in{
		assert(isHost);
	}do{
		import serialize_;
		chat~=line;
		if(network) line.serialized(&network.sendLobbyMessage);
	}
	void perform(int player,ref LobbyAction action,ref Options options)in{
		assert(isHost);
	}do{
		bool host=player==me;
		if(!data.allowed(player,host,action)) return;
		switch(action.type){
			case LobbyActionType.chat:
				import std.utf: validate;
				validate(action.text);
				say(text(playerName(player,options),": ",action.text));
				break;
			case LobbyActionType.start: startRequested=true; break;
			default: data.apply(player,host,action); break;
		}
	}
	// network game: the players' slots and settings follow the lobby, and the lobby is replicated to the other players
	void publish()in{
		assert(isHost);
	}do{
		if(!network) return;
		import serialize_;
		int slotOf(int player){
			auto slot=data.slotOf(player);
			return slot!=-1&&slot<data.gameSlots&&!data.slots[slot].observer?slot:-1;
		}
		foreach(i,ref player;network.players.data) // (a slot is vacated before another player gets it)
			if(player.slot!=-1&&player.slot!=slotOf(to!int(i))) network.updateSlot(to!int(i),-1);
		foreach(i;0..to!int(network.players.length)) network.updateSlot(i,slotOf(i));
		foreach(ref slot;data.slots){
			if(slot.type!=LobbySlotType.human) continue;
			network.updateSetting!"observer"(slot.player,slot.observer);
			network.updateSetting!"team"(slot.player,slot.team);
			network.updateSetting!"randomGod"(slot.player,slot.god==randomGod);
			if(slot.god!=randomGod&&slot.god!=God.none) network.updateSetting!"spellbook"(slot.player,defaultSpells[slot.god]);
		}
		data.serialized(&network.replicateLobbyState);
	}
	// host (or local game): one step of the lobby, returns true once the game starts
	bool updateLobby(ref Options options)in{
		assert(isHost&&!gameStarting);
	}do{
		import serialize_;
		if(!lobbyInitialized) initializeLobby(options);
		updatePlayers(options);
		foreach(ref action;B.lobbyActions.data){
			try perform(me,action,options);
			catch(Exception e){}
		}
		B.lobbyActions.length=0;
		if(network){
			foreach(ref packet;network.lobbyActions.data){
				try{
					LobbyAction action;
					auto actionData=packet.data;
					deserialize(action,ObjectState!B.init,actionData);
					perform(packet.sender,action,options);
				}catch(Exception e) network.report!true(packet.sender,"sent a lobby action with wrong encoding: ",e.msg);
			}
			network.lobbyActions.length=0;
		}
		nameComputers();
		publish();
		bool canStart=(!network||allPlayersWaiting())&&playersReady();
		bool start=canStart&&(startRequested||!lobbyShown(options)||options.autoStart&&enoughPlayers(options));
		startRequested=false;
		if(!start&&lobbyShown(options)) B.showLobby(LobbyView(&data,me,true,canStart,chat.data,options.map));
		return start;
	}
	// other players of a network game: show the lobby of the host and send it the actions of this player
	void followLobby(ref Options options)in{
		assert(network&&!isHost&&!gameStarting);
	}do{
		import serialize_;
		if(network.lobbyStateReceived){
			network.lobbyStateReceived=false;
			auto stateData=network.lobbyState.data;
			deserialize(data,ObjectState!B.init,stateData);
		}
		foreach(ref packet;network.lobbyMessages.data){
			try{
				string line;
				auto lineData=packet.data;
				deserialize(line,ObjectState!B.init,lineData);
				import std.utf: validate;
				validate(line);
				chat~=line;
			}catch(Exception e){}
		}
		network.lobbyMessages.length=0;
		foreach(ref action;B.lobbyActions.data)
			if(data.allowed(me,false,action)) action.serialized(&network.sendLobbyAction);
		B.lobbyActions.length=0;
		if(data.slots.length) B.showLobby(LobbyView(&data,me,false,false,chat.data,options.map));
	}
	// the host can start the game once no player in a slot is still connecting or downloading the map
	bool allPlayersWaiting()in{
		assert(network&&isHost);
	}do{
		foreach(i,ref player;network.players.data){
			if(i==network.host||!isConnectedStatus(player.status)) continue;
			if(player.requiredToControlState&&player.status!=PlayerStatus.pendingGameInit) return false;
		}
		return true;
	}
	// the game only starts once the players in the slots of the game are ready (they can switch to "not ready")
	bool playersReady(){
		return data.slots[0..data.gameSlots].all!((ref slot)=>slot.type!=LobbySlotType.human||slot.observer||slot.ready);
	}
	// --auto-start: the host starts the game once enough players are ready to play
	bool enoughPlayers(ref Options options){
		return data.slots[0..data.gameSlots].count!((ref slot)=>slot.playing&&(slot.ready||slot.type==LobbySlotType.computer))>=options.numSlots;
	}
	// game initialization from the lobby: only now the players whose slot does not get a wizard become observers
	// (the map has no altar for it, or it is not a slot of the game), their choices in the lobby are not changed before
	void initializeGame(ref Options options)in{
		assert(isHost&&lobbyInitialized);
	}do{
		Settings playerSettings(int player){ return network?network.players[player].settings:options.settings; }
		gameInit=.gameInit!B(map,sides,data,&playerSettings,options);
		foreach(i,ref lobbySlot;data.slots){
			if(i<data.gameSlots&&gameInit.slots[i].wizardIndex!=-1) continue;
			if(lobbySlot.type==LobbySlotType.human) lobbySlot.observer=true;
			else lobbySlot=LobbySlot.init;
		}
		publish();
		auto own=data.slotOf(me);
		slot=own!=-1&&!data.slots[own].observer?own:-1;
	}

	void initController(ref Options options)in{
		assert(!!gameState);
	}do{
		if(!controller) controller=new Controller!B(hasSlot?slot:-1,gameState,network,recording,playback);
		if(hasSlot) controller.setControlledSlot(slot);
		B.setState(controller.state);
		B.setController(controller);
	}

	void start(ref Options options)in{
		assert(state==LobbyState.readyToStart);
	}do{
		assert(!!gameState);
		gameState.commit();
		if(wizId) B.focusCamera(wizId);
		if(network && network.isHost) network.addSynch(gameState.committed.frame,gameState.committed.hash);
		if(recording) recording.stepCommitted(gameState.committed);
		initController(options);
		controller.start();
		if(options.focusOnStart) B.grabFocus();
		if(options.captureMouse) B.captureMouse();
		B.hideMouse(); // (should be hidden already, just to make sure)
	}
}
