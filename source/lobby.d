import options:GameMode,Options,Settings;
import sids, sacmap, state, controller, network, recording_;
import util;
import std.string, std.range, std.algorithm, std.stdio;
import std.exception, std.conv;

GameInit!B gameInit(B,R)(Sides!B sides_,R playerSettings,ref Options options){
	GameInit!B gameInit;
	auto numSlots=options.numSlots;
	enforce(numSlots>=sum(options.teamSizes));
	gameInit.slots=new GameInit!B.Slot[](numSlots);
	auto sides=options.gameMode==GameMode.scenario?
		iota(numSlots).map!(i=>sides_.scenarioSide(i)).array:
		iota(numSlots).map!(i=>sides_.multiplayerSide(i)).array;
	auto teams=(-1).repeat(numSlots).array;
	if(options.gameMode!=GameMode.scenario){
		if(options.teamSizes.length){
			int sumSiz=sum(options.teamSizes);
			zip(zip(iota(to!int(options.teamSizes.length)),options.teamSizes)
			    .map!(tn=>tn[0].repeat(tn[1]))
			    .joiner.repeat.joiner,
			    recurrence!((a,n)=>a[n-1]+options.teamSizes.length)(0)
			    .map!(i=>i.repeat(sumSiz)).joiner
			).map!(x=>x[0]+x[1])
				.take(teams.length)
				.copy(teams);
		}else{
			foreach(ref settings;playerSettings)
				if(settings.slot!=-1)
					teams[settings.slot]=settings.team;
		}
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
	void placeWizard(ref Settings settings){
		if(settings.observer) return;
		import std.random: uniform;
		int slot=settings.slot;
		if(slot<0||slot>=numSlots||gameInit.slots[slot].wizardIndex!=-1)
			return;
		char[4] tag=settings.wizard[0..4];
		if(options.randomWizards){
			import nttData:wizards;
			tag=cast(char[4])wizards[uniform!"[)"(0,$)];
		}
		auto name=settings.name;
		auto side=sides[settings.slot];
		auto level=settings.level;
		auto souls=settings.souls;
		float experience=0.0f;
		auto minLevel=settings.minLevel;
		auto maxLevel=settings.maxLevel;
		auto xpRate=settings.xpRate;
		auto spells=settings.spellbook;
		if(options.randomGods) spells=defaultSpells[uniform!"[]"(1,5)];
		if(options.randomSpellbooks) spells=randomSpells();
		auto spellbook=getSpellbook!B(spells);
		import nttData:WizardTag;
		assert(gameInit.slots[slot]==GameInit!B.Slot(-1));
		int wizardIndex=cast(int)gameInit.wizards.length;
		gameInit.slots[slot]=GameInit!B.Slot(wizardIndex);
		gameInit.wizards~=GameInit!B.Wizard(to!WizardTag(tag),name,side,level,souls,experience,minLevel,maxLevel,xpRate,spellbook);
	}
	foreach(ref settings;playerSettings) placeWizard(settings);
	if(options.shuffleSlots){
		import std.random: randomShuffle;
		randomShuffle(zip(gameInit.slots,teams));
	}
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
	gameInit.alliedBeamVision=options.alliedBeamVision;
	gameInit.randomCreatureScale=options.randomCreatureScale;
	gameInit.enableDropSoul=options.enableDropSoul;
	gameInit.targetDroppedSouls=options.targetDroppedSouls;
	gameInit.enableParticles=options.enableParticles;
	gameInit.greenAllySouls=options.greenAllySouls;
	gameInit.fasterStandupTimes=options.fasterStandupTimes;
	gameInit.fasterCastingTimes=options.fasterCastingTimes;
	if(gameInit.greenAllySouls){
		foreach(ref settings;playerSettings)
			if(settings.slot!=-1&&settings.refuseGreenSouls)
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

	bool tryConnect(ref Options options)in{
		assert(state==LobbyState.initialized);
	}do{
		bool useZerotier=!!options.zerotierNetwork;
		if(options.host){
			if(!network) createNetwork(options);
			if(options.continueFilename!=""||options.playbackFilename!=""&&options.continueFrame)
				network.acceptingNewConnections=false;
			network.hostGame(options.settings,useZerotier);
			state=LobbyState.connected;
			return true;
		}
		if(options.joinIP!=""){
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
				return SlotData(i,toContinue.gameInit.wizards[toContinue.gameInit.slots[i].wizardIndex].name,frame);
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
		auto numSlots=options.numSlots;
		auto slotTaken=new bool[](numSlots);
		foreach(i,ref player;network.players.data){
			if(player.settings.observer) continue;
			auto pslot=player.settings.slot;
			if(0<=pslot && pslot<options.numSlots && !slotTaken[pslot])
				slotTaken[pslot]=true;
			else pslot=-1;
			network.updateSlot(cast(int)i,pslot);
		}
		auto freeSlots=iota(numSlots).filter!(i=>!slotTaken[i]);
		foreach(i,ref player;network.players.data){
			if(player.settings.observer) continue;
			if(freeSlots.empty) break;
			if(player.slot==-1){
				network.updateSlot(cast(int)i,freeSlots.front);
				freeSlots.popFront();
			}
		}
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
			if(isHost) loadMap(options);
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
						map=loadSacMap!B(mapName); // TODO: compute hash without loading map?
						options.mapHash=map.crc32;
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
		void loadMap(string mapName){
			options.map=mapName;
			map=loadSacMap!B(mapName);
			options.mapHash=map.crc32;
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
		options.settings=network.settings;
		slot=network.slot;
		if(!isHost) network.updateStatus(PlayerStatus.pendingGameInit); // TODO: tie this to thumbs up
		return true;
	}

	void loadMap(ref Options options){
		if(!map) map=loadSacMap!B(options.map,&mapData); // TODO: compute hash without loading map?
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
				if(!sides) sides=new Sides!B(map.sids);
				if(!proximity) proximity=new Proximity!B();
				if(!pathFinder) pathFinder=new PathFinder!B(map);
				if(!triggers) triggers=new Triggers!B(map.trig);
				auto supportRollback=network !is null;
				gameState=new GameState!B(map,sides,proximity,pathFinder,triggers,supportRollback);
				gameState.initMap();
			}
		}
		if(!playback||network){
			if(network){
				import serialize_;
				if(network.isHost){
					initState();
					if(toContinue) gameInit=toContinue.gameInit;
					else gameInit=.gameInit!B(sides,network.players.data.map!(ref(return ref x)=>x.settings),options);
					gameInit.serialized(&network.initGame);
				}else{
					network.update(controller); // (may be null)
					if(!network.hasGameInitData())
						return lastLoad?false:!!gameState;
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
				else gameInit=.gameInit!B(sides,only(options.settings),options);
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
		gameState.rollback();
		gameState.initGame(gameInit);
		hasSlot=0<=slot&&slot<gameState.slots.length;
		wizId=hasSlot?gameState.slots[slot].wizard:0;
		initController(options);
		// TODO: if game init can place additional buildings this would need to be reflected here:
		if(!gameState.current.map.meshes.length)
			gameState.current.map.makeMeshes(options.enableMapBottom);
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
		}else loadMap(options);
		assert(!!map);
		//writeln(3);
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
