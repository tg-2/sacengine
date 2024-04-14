// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import std.stdio, std.algorithm, std.exception;
import std.datetime.stopwatch, std.conv;
import core.time;
import util: Array;
import state, network, recording_;

struct GameTimer{
	Duration offset;
	StopWatch sw;
	void reset(){ offset=Duration.zero; sw.reset(); }
	Duration peek(){ return offset+sw.peek(); }
	bool paused=true;
	void pause(){
		if(paused) return;
		sw.stop();
		paused=true;
	}
	void start(){
		if(!paused) return;
		sw.start();
		paused=false;
	}
	void adjust(Duration dur){ offset+=dur; }
	void set(Duration dur){ offset=dur; sw.reset(); }
	int _frame=0;
	@property int frame(){
		_frame=max(_frame,to!int(peek()*updateFPS/1.dur!"seconds"));
		return _frame;
	}
	void setFrame(int frame){
		set(((frame*10_000_000L+updateFPS-1)/updateFPS).dur!"hnsecs");
		assert(offset*updateFPS/1.dur!"seconds"==frame);
		_frame=frame;
	}
}


final class Controller(B){
	GameState!B state;
	Network!B network;
	Recording!B recording, playback;
	int controlledSlot;
	int controlledSide;
	int commandId=0;
	int lastCheckSynch=-1;
	GameTimer timer;
	int currentFrame(){ return timer.frame; }
	this(int controlledSlot,GameState!B state,Network!B network,Recording!B recording,Recording!B playback)in{
		assert(controlledSlot==-1||0<=controlledSlot&&controlledSlot<state.slots.length);
	}do{
		this.controlledSlot=controlledSlot;
		this.controlledSide=controlledSlot==-1?-1:state.slots[controlledSlot].controlledSide;
		this.state=state;
		this.network=network;
		this.recording=recording;
		this.playback=playback;
	}

	void setControlledSlot(int controlledSlot){
		this.controlledSlot=controlledSlot;
		this.controlledSide=controlledSlot==-1?-1:state.slots[controlledSlot].controlledSide;
	}

	int slotFilter(bool allies,bool enemies,bool observers){
		if(controlledSlot==-1) return -1;
		int slots=observers?-1:0;
		if(allies||enemies) foreach(i,ref slot;state.slots.data){
			int side=slot.controlledSide;
			if(side==-1) continue;
			slots&=~(1<<i);
			final switch(state.current.sides.getStance(controlledSide,side)){
				case Stance.ally:
					if(allies) slots|=1<<i;
					break;
				case Stance.neutral,Stance.enemy:
					if(enemies) slots|=1<<i;
					break;
			}
		}
		assert(controlledSlot!=-1);
		slots|=1<<controlledSlot;
		return slots;
	}


	int chatMessageLowerBound=0;
	bool resetTimerOnUnpause=true; // TODO: this is a hack
	void setFrame(int frame){
		int oldFrame=currentFrame;
		timer.setFrame(frame);
		if(paused) resetTimerOnUnpause=false; // persist frame update even if paused
		if(oldFrame<=frame+updateFPS) chatMessageLowerBound=frame;
	}
	bool paused=false;
	bool waitingOnNetwork=false;
	bool pauseTimerOnPause=true; // TODO: this is a hack
	bool lateJoining=false; // TODO: this is a hack
	void pause(){
		paused=true;
		if(pauseTimerOnPause){
			timer.pause();
			timer.setFrame(timer.frame);
		}else pauseTimerOnPause=true;
	}
	void unpause(){
		paused=false;
		if(waitingOnNetwork) return;
		if(resetTimerOnUnpause){
			timer.setFrame(state.currentFrame);
		}else resetTimerOnUnpause=true;
		timer.start();
	}

	bool hasStarted=false;
	void start(){
		hasStarted=true;
		waitingOnNetwork=true;
		B.clearSidechannelMessages(); // TODO: does not work properly yet
	}

	bool isControllingSide(int side){
		if(side!=controlledSide) return false;
		if(network&&!network.players[network.me].isControllingState)
			return false;
		if(state.current.isDefeated(side))
			return false;
		return true;
	}
	void addCommand(Command!B command)in{
		assert(command.id==0);
	}do{
		if(network&&!network.playing){
			if(command.type==CommandType.chatMessage){
				// TODO: properly authorize observer chat
				network.addCommand(currentFrame,command);
				if(network.networkState)
					network.networkState.chatMessages.addChatMessage(command.chatMessage);
			}
			return;
		}
		if(!isControllingSide(command.side)){
			bool observerChat=command.side==-1&&command.type==CommandType.chatMessage;
			if(!observerChat) return;
			if(network&&!network.isHost){
				network.addCommand(-1,command);
				return;
			}
		}
		command.id=++commandId;
		auto frame=max(state.committedFrame,currentFrame); // TODO: why max needed?
		if(network) frame=max(frame,network.players[network.me].committedFrame);
		state.addCommand(frame,command);
		if(network) network.addCommand(frame,command);
		if(recording) recording.addCommand(frame,command);
		if(network && command.type==CommandType.surrender)
			updateNetworkOnSurrender(command.side);
	}
	void addCommand(Command!B command,CommandQueueing queueing){
		command.queueing=queueing;
		addCommand(command);
	}
	void addExternalCommand(int frame,Command!B command)in{
		import std.conv: text;
		assert(state.committedFrame<=frame,text(state.committedFrame," ",frame," ",command));
	}do{
		state.addCommand(frame,command);
		if(recording) recording.addExternalCommand(frame,command);
		if(network && command.type==CommandType.surrender)
			updateNetworkOnSurrender(command.side);
	}
	void setSelection(int side,int wizard,CreatureGroup selection,TargetLocation loc){
		if(!isControllingSide(side)) return;
		addCommand(Command!B(CommandType.clearSelection,side,wizard,0,Target.init,float.init));
		foreach_reverse(id;selection.creatureIds){
			if(id==0) continue;
			addCommand(Command!B(CommandType.automaticToggleSelection,side,wizard,id,Target.init,float.init));
		}
	}
	void replaceState(scope ubyte[] serialized)in{
		assert(network&&!network.isHost);
	}do{
		import serialize_;
		if(network.logDesynch_) state.committed.serialized(&network.logDesynch);
		state.replaceState(serialized);
		if(currentFrame<state.committedFrame)
			timer.setFrame(state.current.frame);
		state.commit();
		while(state.currentFrame<currentFrame){
			updateCommitted();
			state.step();
			B.processEvents();
		}
		if(lateJoining&&controlledSlot!=-1){
			B.focusCamera(state.slots[controlledSlot].wizard);
			lateJoining=false;
		}
		if(recording) recording.replaceState(state.current,state.commands);
	}
	void logDesynch(int side,scope ubyte[] serialized){
		if(recording) try{ recording.logDesynch(side,serialized,state.current); }catch(Exception e){ stderr.writeln("bad desynch log: ",e.msg); }
	}
	void updateCommittedTo(int frame){
		network.tryCommit(currentFrame);
		auto committedFrame=network.committedFrame;
		if(committedFrame<=state.committedFrame) return;
		if(!network.isHost&&(network.desynched||network.lateJoining)) return; // avoid simulating entire game after rejoin
		import std.conv: text;
		//enforce(state.committedFrame<=committedFrame,text(state.committedFrame," ",committedFrame," ",network.players.map!((ref p)=>p.committedFrame)," ",network.activePlayerIds," ",network.players.map!((ref p)=>p.status)));
		if(frame==-1) frame=committedFrame;
		auto target=min(frame,committedFrame);
		if(target<=state.committedFrame) return;
		state.simulateCommittedTo!((){
			if(recording) recording.stepCommitted(state.committed);
			if(network.isHost) network.addSynch(state.committedFrame,state.committed.hash);
			network.tryCommit(currentFrame);
			return false;
		})(target);
		enforce(state.committedFrame==target,
		        text(network.activePlayerIds," ",network.players.map!((ref p)=>p.committedFrame)," ",
		             committedFrame," ",state.committedFrame));

	}
	void updateCommitted(int limit=-1)in{
		assert(!!network);
	}do{
		auto cheaperCommitted=limit==-1?-1:state.committedFrame+limit;
		updateCommittedTo(cheaperCommitted);
	}
	void updateNetworkGameState()in{
		assert(!!network);
	}do{
		foreach(ref p;network.players){
			if(p.slot==-1) continue;
			p.lost|=state.committed.isDefeated(state.slots[p.slot].controlledSide);
			p.won|=state.committed.isVictorious(state.slots[p.slot].controlledSide);
			p.lost|=!state.committed.isValidTarget(state.slots[p.slot].wizard,TargetType.creature);
		}
	}
	void updateNetworkOnSurrender(int side){
		foreach(ref p;network.players) if(p.slot!=-1&&state.slots[p.slot].controlledSide==side) p.lost=true;
	}

	bool updateNetwork(){
		if(network){
			network.update(this);
			if(network.isHost){ // handle new connections
				network.synchronizeMap(null);
				if(network.hasGameInitData){
					auto hash=network.hostSettings.mapHash;
					foreach(i,ref player;network.players){
						if(player.status==PlayerStatus.pendingGameInit && player.settings.mapHash==hash){
							with(network){
								auto message=players[i].allowedToControlState?"has rejoined the game.":"is now observing.";
								sidechannelChatMessage(ChatMessageType.network,players[i].settings.name,message,this);
							}
							network.updateSetting!"pauseOnDrop"(cast(int)i,network.pauseOnDrop);
							network.initGame(cast(int)i,network.gameInitData.data);
							network.updateStatus(cast(int)i,PlayerStatus.lateJoining);
						}
					}
				}
			}
			if(network.hostDropped) return true;
			if(network.lateJoining){
				if(!network.paused&&!network.desynched){
					// stutter-free late join
					network.updateStatus(PlayerStatus.pendingLoad);
				}else network.updateStatus(PlayerStatus.desynched);
			}
			if(network.lateJoining||network.players[network.me].status==PlayerStatus.pendingLoad){
				timer.start();
				pauseTimerOnPause=false;
				return true;
			}
			if(network.isHost){
				bool anyoneLateJoining=false;
				foreach(i,ref player;network.players){
					if(player.status!=PlayerStatus.pendingLoad) continue;
					if(player.ping==-1.seconds){ network.ping(cast(int)i); continue; }
					auto frame=currentFrame;
					if(network.playing) frame=to!int(frame+player.ping/(1.seconds/updateFPS));
					network.setFrame(cast(int)i,frame);
					anyoneLateJoining=true;
				}
				if(anyoneLateJoining){
					updateCommittedTo(network.committedFrame);
					with(state){
						import serialize_;
						committed.serialized((scope ubyte[] stateData){
							commands.serialized((scope ubyte[] commandData){
								foreach(i,ref player;network.players){
									if(player.status!=PlayerStatus.pendingLoad) continue;
									if(player.ping==-1.seconds) continue;
									auto frame=state.currentFrame;
									network.updateStatus(cast(int)i,PlayerStatus.loading);
									network.resetCommitted(cast(int)i,frame);
									network.setFrame(cast(int)i,frame);
									network.sendState(cast(int)i,stateData,commandData);
									network.requestStatusUpdate(cast(int)i,PlayerStatus.playing);
								}
							});
						});
					}
				}
			}
			int rollbackToResynchCommittedFrame(){
				auto newFrame=max(state.committedFrame,network.resynchCommittedFrame);
				if(network.isHost) network.resetCommitted(network.me,newFrame);
				if(state.currentFrame!=newFrame){
					state.rollback();
					state.simulateTo(newFrame);
				}
				return newFrame;
			}
			int resetToResynchCommittedFrame(){
				if(network.isHost&&network.resynchCommittedFrame<state.committedFrame){
					stderr.writeln("warning: skipping frames on resynch: ",network.resynchCommittedFrame," to ",state.committedFrame);
					network.resetCommitted(state.committedFrame);
				}
				auto newFrame=network.resynchCommittedFrame;
				if(network.isHost) network.resetCommitted(network.me,newFrame);
				if(state.committedFrame<=newFrame){
					state.simulateCommittedTo!((){
						if(recording) recording.stepCommitted(state.committed);
						if(network.isHost) network.addSynch(state.committedFrame,state.committed.hash);
						return false;
					})(newFrame);
				}
				if(!network.isHost&&state.committedFrame!=newFrame&&!isDesynchedStatus(network.players[network.me].status)){
					stderr.writeln("warning: rolling back over network: ",newFrame," from ",state.committedFrame);
					network.updateStatus(PlayerStatus.desynched);
				}
				state.rollback();
				//writeln("removing future at frame: ",state.committedFrame," ",state.currentFrame);
				state.removeFuture();
				timer.setFrame(newFrame);
				return newFrame;
			}
			//writeln(network.players.map!((ref p)=>p.status)," ",network.pendingResynch," ",network.resynchCommittedFrame," ",network.players.map!((ref p)=>p.committedFrame));
			if(network.desynched){
				updateCommitted(); // TODO: needed?
				if(network.pendingResynch){
					if(network.isHost){
						resetToResynchCommittedFrame();
						network.updateStatus(PlayerStatus.readyToResynch);
					}else if(!isDesynchedStatus(network.players[network.me].status)){
						// attempt resynch without assistance from host
						auto newFrame=resetToResynchCommittedFrame();
						if(state.committedFrame==newFrame){
							network.updateStatus(PlayerStatus.stateResynched);
						}else{
							network.updateStatus(PlayerStatus.readyToResynch);
						}
					}else network.updateStatus(PlayerStatus.readyToResynch);
				}
				if(network.isHost && network.readyToResynch){
					network.acceptingNewConnections=false;
					auto newFrame=state.committedFrame;
					//writeln("SENDING STATE AT FRAME: ",newFrame," ",network.players.map!((ref p)=>p.committedFrame));
					import std.conv: text;
					enforce(state.currentFrame==newFrame,text(state.currentFrame," ",newFrame));
					network.setFrameAll(newFrame);
					network.resetCommitted(-1,newFrame);
					enforce(state.currentFrame==network.resynchCommittedFrame,text(state.currentFrame," ",network.resynchCommittedFrame," ",network.players.map!((ref p)=>p.status),network.players.map!((ref p)=>p.committedFrame)));
					import serialize_;
					state.committed.serialized((scope ubyte[] stateData){
						state.commands.serialized((scope ubyte[] commandData){
							static bool filter(int i,Network!B network){
								return network.players[i].status==PlayerStatus.readyToResynch;
							}
							network.sendStateAll!filter(stateData,commandData,network);
						});
					});
					network.requestStatusUpdateAll(PlayerStatus.stateResynched);
				}
				if(network.stateResynched && network.players[network.me].status==PlayerStatus.stateResynched){
					//writeln("STATE IS ACTUALLY AT FRAME: ",currentFrame);
					network.tryCommit(state.currentFrame);
					network.updateStatus(PlayerStatus.resynched);
				}
				if(network.isHost && network.resynched){
					enforce(state.currentReady);
					import std.conv: text;
					enforce(state.committed.frame==state.current.frame,text(state.committedFrame," ",state.currentFrame," ",currentFrame));
					if(state.committed.hash!=state.current.hash){
						stderr.writeln("warning: local desynch (",state.committed.hash,"!=",state.current.hash,")");
						state.current.copyFrom(state.committed);
					}
					network.load();
				}
				return true; // ignore passed time in next frame
			}
			if(network.isHost&&(network.pauseOnDrop||network.pauseOnDropOnce)){
				if(network.anyoneDropped){
					network.pause(PlayerStatus.pausedOnDrop);
					network.acceptingNewConnections=true;
				}else if(network.players[network.me].status==PlayerStatus.pausedOnDrop){
					network.unpause();
					network.pauseOnDropOnce=false;
				}
			}
			if(network.paused){
				if(state.committedFrame>0){
					auto newFrame=rollbackToResynchCommittedFrame();
					timer.setFrame(newFrame);
				}
				return true;
			}
			if(!network.playing){ // start game
				network.updateStatus(PlayerStatus.readyToStart);
				if(network.isHost&&network.readyToStart()){
					network.start(this);
				}
				return true; // ignore passed time in next frame
			}
			network.acceptingNewConnections=true;
			updateCommitted(0);
		}else assert(state.committedFrame==state.current.frame);
		return false;
	}

	bool run()in{
		assert(hasStarted);
	}do{
		bool oldPlayAudio=playAudio;
		//playAudio=state.firstUpdatedFrame<=state.currentFrame;
		playAudio=false;
		scope(exit) playAudio=oldPlayAudio;
		if(updateNetwork()||state.applyCommands!(()=>updateNetwork())){
			if(!waitingOnNetwork){
				pause();
				waitingOnNetwork=true;
			}
			return true;
		}
		if(waitingOnNetwork){
			waitingOnNetwork=false;
			unpause();
		}
		playAudio=oldPlayAudio;
		int numSteps=0;
		while(state.currentFrame<currentFrame){
			state.step();
			if(playback){
				playback.report(state);
			}
			if(recording){
				recording.step();
				if(!network) recording.stepCommitted(state.current);
			}
			numSteps+=1;
		}
		if(network){
			playAudio=false;
			updateCommitted(1+2*numSteps);
			updateNetworkGameState();
			if(!network.isHost&&lastCheckSynch<state.committedFrame){
				network.checkSynch(state.committed.frame,state.committed.hash);
				lastCheckSynch=state.committedFrame;
			}
		}
		return false;
	}
}
