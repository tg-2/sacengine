import options:Options,Settings;
import sids, sacmap, state, controller, network, recording_;
import util;
import std.string, std.range, std.algorithm, std.stdio;
import std.exception, std.conv;

GameInit!B gameInit(alias multiplayerSide,B,R)(R playerSettings,ref Options options){
	GameInit!B gameInit;
	auto numSlots=options.numSlots;
	if(options._2v2) enforce(numSlots>=4);
	if(options._3v3) enforce(numSlots>=6);
	gameInit.slots=new GameInit!B.Slot[](numSlots);
	auto sides=iota(numSlots).map!(i=>multiplayerSide(i)).array;
	if(options.shuffleSides){
		import std.random: randomShuffle;
		randomShuffle(sides);
	}
	auto teams=(-1).repeat(numSlots).array;
	if(options.ffa||options._2v2||options._3v3){
		int teamSize=1;
		if(options._2v2) teamSize=2;
		if(options._3v3) teamSize=3;
		foreach(slot,ref team;teams)
			team=cast(int)slot/teamSize;
	}else{
		foreach(ref settings;playerSettings)
			if(settings.slot!=-1)
				teams[settings.slot]=settings.team;
	}
	if(options.shuffleTeams){
		import std.random: randomShuffle;
		randomShuffle(teams);
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
				copyWizard(gameInit.wizards[t[i]],gameInit.wizards[teamIndex[0][i]]);
			}
		}
	}
	gameInit.replicateCreatures=options.replicateCreatures;
	gameInit.protectManafounts=options.protectManafounts;
	gameInit.terrainSineWave=options.terrainSineWave;
	return gameInit;
}

struct Lobby(B){
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

	GameState!B state;
	GameInit!B gameInit;
	Recording!B recording=null;

	bool hasSlot;
	int wizId;
	Controller!B controller;

	void start(int slot,ref Options options){
		this.slot=slot;
		if(options.host){
			network=new Network!B();
			network.hostGame(options.settings);
		}else if(options.joinIP!=""){
			network=new Network!B();
			auto address=new InternetAddress(options.joinIP,listeningPort);
			while(!network.joinGame(address,options.settings)){
				// TODO: loop externally
				import core.thread;
				Thread.sleep(200.msecs);
				if(!B.processEvents()) return;
			}
		}
	}

	bool canPlayRecording(){ return !playback && !toContinue && !network; }
	void initializePlayback(Recording!B recording,ref Options options)in{
		assert(canPlayRecording);
	}do{
		playback=recording;
		enforce(playback.mapName.endsWith(".scp")||playback.mapName.endsWith(".HMAP"));
		options.map=playback.mapName;
		slot=-1;
		map=playback.map;
		sides=playback.sides;
		proximity=playback.proximity;
		pathFinder=playback.pathFinder;
		triggers=playback.triggers;
	}

	bool canContinue(){ return !toContinue && !playback && isHost; }
	void continueGame(Recording!B recording,int frame,ref Options options)in{
		assert(canContinue);
	}do{
		toContinue=recording;
		if(frame!=-1){
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
			static struct SlotData{
				int slot;
				string name;
			}
			SlotData toSlotData(int i){
				return SlotData(i,toContinue.gameInit.wizards[toContinue.gameInit.slots[i].wizardIndex].name);
			}
			assert(network.players.length==1);
			network.players[network.me].committedFrame=frame;
			network.initSlots(iota(options.numSlots).map!toSlotData);
		}
	}

	void initializeNetworking(ref Options options)in{
		assert(!!network);
	}do{
		if(isHost){
			map=loadSacMap!B(options.map,&mapData); // TODO: compute hash without loading map
			options.mapHash=map.crc32; // TODO: store this somewhere else?
		}
		network.dumpTraffic=options.dumpTraffic;
		network.checkDesynch=options.checkDesynch;
		network.logDesynch_=options.logDesynch;
		network.pauseOnDrop=options.pauseOnDrop;
		while(!network.synched){
			network.idleLobby(); // TODO: external looping
			if(!B.processEvents()) return;
		}
		network.updateSetting!"mapHash"(options.mapHash);
		network.updateStatus(PlayerStatus.commitHashReady);
		if(!network.isHost){
			while(!network.hostCommitHashReady){
				network.idleLobby(); // TODO: external looping
				if(!B.processEvents()) return;
			}
			if(network.hostSettings.commit!=options.commit){
				writeln("incompatible version #");
				writeln("host is using version ",network.hostSettings.commit);
				network.disconnectPlayer(network.host,null);
				return;
			}
			network.updateStatus(PlayerStatus.readyToLoad);
		}
		while(!network.readyToLoad&&!network.pendingResynch){
			network.idleLobby(); // TODO: external looping
			if(!B.processEvents()) return;
			if(network.isHost&&network.numReadyPlayers+(network.players[network.host].wantsToControlState)>=options.numSlots&&network.clientsReadyToLoad()){
				network.acceptingNewConnections=false;
				//network.stopListening();
				auto numSlots=options.numSlots;
				auto slotTaken=new bool[](numSlots);
				foreach(i,ref player;network.players){
					if(player.settings.observer) continue;
					auto pslot=player.settings.slot;
					if(0<=pslot && pslot<options.numSlots && !slotTaken[pslot])
						slotTaken[pslot]=true;
					else pslot=-1;
					network.updateSlot(cast(int)i,pslot);
				}
				auto freeSlots=iota(numSlots).filter!(i=>!slotTaken[i]);
				foreach(i,ref player;network.players){
					if(player.settings.observer) continue;
					if(freeSlots.empty) break;
					if(player.slot==-1){
						network.updateSlot(cast(int)i,freeSlots.front);
						freeSlots.popFront();
					}
				}
				if(options.synchronizeLevel) network.synchronizeSetting!"level"();
				if(options.synchronizeSouls) network.synchronizeSetting!"souls"();

				if(options.synchronizeLevelBounds){
					network.synchronizeSetting!"minLevel"();
					network.synchronizeSetting!"maxLevel"();
				}
				if(options.synchronizeXPRate) network.synchronizeSetting!"xpRate"();

				network.updateStatus(PlayerStatus.readyToLoad);
				assert(network.readyToLoad());
				break;
			}
		}
		auto mapName=network.hostSettings.map;
		if(network.settings.map!=mapName)
			network.updateSetting!"map"(mapName);
		auto hash=network.hostSettings.mapHash;
		if(!network.isHost){
			import std.file: exists;
			if(exists(mapName)){
				map=loadSacMap!B(mapName); // TODO: compute hash without loading map
				options.mapHash=map.crc32;
			}
			network.updateSetting!"mapHash"(options.mapHash);
			network.updateStatus(PlayerStatus.mapHashed);
		}else{
			network.mapData=mapData;
			network.updateStatus(PlayerStatus.mapHashed);
		}
		void loadMap(string name){
			mapName=name;
			map=loadSacMap!B(mapName);
			enforce(map.crc32==hash,"map hash mismatch");
			network.updateSetting!"mapHash"(map.crc32);
			network.updateStatus(PlayerStatus.mapHashed);
		}
		while(!network.synchronizeMap(&loadMap)){
			network.idleLobby(); // TODO: external looping
			if(!B.processEvents()) return;
		}
		if(network.isHost){
			network.load();
		}else{
			while(!network.loading&&network.players[network.me].status!=PlayerStatus.desynched){ // desynched at start if late join
				network.idleLobby(); // TODO: external looping
				if(!B.processEvents()) return;
			}
		}
		options.settings=network.settings;
		slot=network.slot;
	}

	void loadGame(ref Options options){
		sides=new Sides!B(map.sids);
		proximity=new Proximity!B();
		pathFinder=new PathFinder!B(map);
		triggers=new Triggers!B(map.trig);
		state=new GameState!B(map,sides,proximity,pathFinder,triggers);
		int[32] multiplayerSides=-1;
		bool[32] matchedSides=false;
		foreach(i,ref side;sides){
			int mpside=side.assignment&PlayerAssignment.multiplayerMask;
			if(!mpside) continue;
			multiplayerSides[mpside-1]=cast(int)i;
			matchedSides[i]=true;
		}
		iota(32).filter!(i=>!matchedSides[i]).copy(multiplayerSides[].filter!(x=>x==-1));
		int multiplayerSide(int slot){
			if(slot<0||slot>=multiplayerSides.length) return slot;
			return multiplayerSides[slot];
		}
		if(!playback||network){
			if(network){
				import serialize_;
				if(network.isHost){
					if(toContinue) gameInit=toContinue.gameInit;
					else gameInit=.gameInit!(multiplayerSide,B)(network.players.map!(ref(return ref x)=>x.settings),options);
					gameInit.serialized(&network.initGame);
				}else{
					while(!network.gameInitData){
						network.idleLobby(); // TODO: external looping
						if(!B.processEvents()) return;
					}
					deserialize(gameInit,state.current,network.gameInitData);
					network.gameInitData=null;
				}
			}else{
				if(toContinue) gameInit=toContinue.gameInit;
				else gameInit=.gameInit!(multiplayerSide,B)(only(options.settings),options);
			}
		}else gameInit=playback.gameInit;
		if((!playback||network)&&options.recordingFilename.length){
			recording=new Recording!B(options.map,map,sides,proximity,pathFinder,triggers);
			recording.gameInit=gameInit;
			recording.logCore=options.logCore;
		}
		state.initGame(gameInit);
		hasSlot=0<=slot&&slot<=state.slots.length;
		wizId=hasSlot?state.slots[slot].wizard:0;
		state.current.map.makeMeshes(options.enableMapBottom);
		if(toContinue){
			state.commands=toContinue.commands;
			playAudio=false;
			while(state.current.frame+1<state.commands.length){
				state.step();
				if(state.current.frame%1000==0){
					writeln("continue: simulated ",state.current.frame," of ",state.commands.length-1," frames");
				}
			}
			playAudio=true;
			writeln(state.current.frame," ",options.continueFrame);
			assert(state.current.frame==options.continueFrame);
			if(network){
				assert(network.isHost);
				foreach(i;network.connectedPlayerIds) if(i!=network.host) network.updateStatus(cast(int)i,PlayerStatus.desynched);
				network.continueSynchAt(options.continueFrame);
			}
		}
		state.commit();
		if(network && network.isHost) network.addSynch(state.lastCommitted.frame,state.lastCommitted.hash);
		if(recording) recording.stepCommitted(state.lastCommitted);
		controller=new Controller!B(hasSlot?slot:-1,state,network,recording,playback);
	}
}
