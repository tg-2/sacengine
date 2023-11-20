// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import std.stdio, std.algorithm, std.exception;
import util: Array;
import state, network, recording_;


final class Controller(B){
	GameState!B state;
	Network!B network;
	Recording!B recording, playback;
	int controlledSlot;
	int controlledSide;
	int commandId=0;
	int lastCheckSynch=-1;
	int firstUpdatedFrame;
	int currentFrame;
	this(int controlledSlot,GameState!B state,Network!B network,Recording!B recording,Recording!B playback)in{
		assert(controlledSlot==-1||0<=controlledSlot&&controlledSlot<state.slots.length);
	}do{
		this.controlledSlot=controlledSlot;
		this.controlledSide=controlledSlot==-1?-1:state.slots[controlledSlot].controlledSide;
		this.state=state;
		this.network=network;
		currentFrame=state.current.frame;
		firstUpdatedFrame=currentFrame;
		this.recording=recording;
		this.playback=playback;
		//initSynchState();
	}
	bool isControllingSide(int side){
		if(network&&!network.players[network.me].isControllingState)
			return false;
		return side==controlledSide;
	}
	void addCommand(int frame,Command!B command)in{
		assert(command.id==0);
		assert(!network||network.playing||command.type==CommandType.surrender);
		assert(state.lastCommitted.frame<=frame);
	}do{
		if(!isControllingSide(command.side)){
			bool observerChat=command.side==-1&&command.type==CommandType.chatMessage;
			if(!observerChat) return;
			if(network&&!network.isHost){
				network.addCommand(-1,command);
				return;
			}
		}
		command.id=++commandId;
		firstUpdatedFrame=min(firstUpdatedFrame,frame);
		state.addCommandInconsistent(frame,command);
		if(network) network.addCommand(frame,command);
		if(recording) recording.addCommand(frame,command);
		if(network && command.type==CommandType.surrender)
			updateNetworkOnSurrender(command.side);
	}
	void addCommand(Command!B command){
		if(network&&!network.playing) return;
		addCommand(currentFrame,command);
	}
	void addCommand(Command!B command,CommandQueueing queueing){
		command.queueing=queueing;
		addCommand(command);
	}
	void addExternalCommand(int frame,Command!B command)in{
		import std.conv: text;
		assert(state.lastCommitted.frame<=frame,text(state.lastCommitted.frame," ",frame," ",command));
	}do{
		// TODO: check if player that issued the command is allowed to do so
		firstUpdatedFrame=min(firstUpdatedFrame,frame);
		state.addCommandInconsistent(frame,command);
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
		deserialize(state.current,serialized);
		currentFrame=state.current.frame;
		static if(B.hasAudio) B.updateAudioAfterRollback();
		deserialize(state.commands,state.current,serialized);
		firstUpdatedFrame=state.current.frame;
		/+if(synchState.frame!=0){
			synchState.update(state.commands[synchState.frame].data);
			lastConfirmSynch=synchState.frame;
			synchState.serialized(&network.logDesynch);
			import std.conv:text;
			while(synchState.frame<state.current.frame){
				synchState.update(state.commands[synchState.frame].data);
			}
			enforce(synchState.frame==state.current.frame,text(synchState.frame," ",state.current.frame));
			writeln("SYNCHSTATE: ",synchState.frame," ",synchState.hash," CURRENTSTATE: ",state.current.frame," ",state.current.hash);
		}+/
		if(network.logDesynch_) state.lastCommitted.serialized(&network.logDesynch); // TODO: don't log if late join
		if(recording) recording.replaceState(state.lastCommitted,state.commands);
		network.updateStatus(PlayerStatus.stateResynched);
	}
	void logDesynch(int side,scope ubyte[] serialized){
		if(recording) try{ recording.logDesynch(side,serialized,state.current); }catch(Exception e){ stderr.writeln("bad desynch log: ",e.msg); }
	}
	/+int lastConfirmSynch=-1;
	ObjectState!B synchState;
	void initSynchState(){
		if(lastConfirmSynch==-1){
			synchState=new ObjectState!B(state.lastCommitted.map,state.lastCommitted.sides,state.lastCommitted.proximity,state.lastCommitted.pathFinder,state.lastCommitted.triggers);
			synchState.copyFrom(state.current);
			lastConfirmSynch=state.current.frame;
		}
	}
	void confirmSynch(int frame,int hash){
		import std.conv: text;
		enforce(synchState.frame<=lastConfirmSynch);
		enforce(lastConfirmSynch<=frame,text(lastConfirmSynch," ",frame));
		lastConfirmSynch=frame;
		while(synchState.frame<frame){
			synchState.update(state.commands[synchState.frame].data);
		}
		enforce(synchState.frame==frame && synchState.hash==hash,text("confirmed ",synchState.frame," ",synchState.hash,", but was ",hash));
	}+/
	void updateCommitted()in{
		assert(!!network);
	}do{
		auto committedFrame=network.committedFrame;
		if(!network.isHost&&(network.desynched||network.lateJoining)) return; // avoid simulating entire game after rejoin
		import std.conv: text;
		enforce(state.lastCommitted.frame<=committedFrame,text(state.lastCommitted.frame," ",committedFrame," ",network.players.map!((ref p)=>p.committedFrame)," ",network.activePlayerIds," ",network.players.map!((ref p)=>p.status)));
		if(state.commands.length<committedFrame+1)
			state.commands.length=committedFrame+1;
		assert(state.lastCommitted.frame<=firstUpdatedFrame);
		while(state.lastCommitted.frame<committedFrame){
			//playAudio=firstUpdatedFrame<=state.lastCommitted.frame;
			state.stepCommittedUnsafe();
			if(recording) recording.stepCommitted(state.lastCommitted);
			if(network.isHost) network.addSynch(state.lastCommitted.frame,state.lastCommitted.hash);
		}
		//playAudio=false;
		enforce(committedFrame==state.lastCommitted.frame,
		        text(network.activePlayerIds," ",network.players.map!((ref p)=>p.committedFrame)," ",
		             committedFrame," ",state.lastCommitted.frame));
		if(state.current.frame<committedFrame||state.current.frame==committedFrame&&firstUpdatedFrame<committedFrame)
			state.current.copyFrom(state.lastCommitted); // restore invariant
		currentFrame=max(currentFrame,committedFrame);
		firstUpdatedFrame=max(firstUpdatedFrame,committedFrame);
	}
	void updateNetworkGameState()in{
		assert(!!network);
	}do{
		foreach(ref p;network.players){
			if(p.slot==-1) continue;
			p.lostWizard|=!state.lastCommitted.isValidTarget(state.slots[p.slot].wizard,TargetType.creature);
		}
	}
	void updateNetworkOnSurrender(int side){
		foreach(ref p;network.players) if(p.slot!=-1&&state.slots[p.slot].controlledSide==side) p.lostWizard=true;
	}

	bool updateNetwork(){
		if(network){
			network.update(this);
			if(firstUpdatedFrame<state.current.frame){
				// TODO: save multiple states, pick most recent with frame<=firstUpdatedFrame?
				import std.conv: text;
				enforce(state.lastCommitted.frame<=firstUpdatedFrame,text(state.lastCommitted.frame," ",firstUpdatedFrame," ",currentFrame));
				state.rollback();
			}
			if(network.isHost){ // handle new connections
				network.synchronizeMap(null);
				if(network.hasGameInitData){
					auto hash=network.hostSettings.mapHash;
					foreach(i,ref player;network.players){
						if(player.status==PlayerStatus.pendingGameInit && player.settings.mapHash==hash){
							network.initGame(cast(int)i,network.gameInitData.data);
							network.updateStatus(cast(int)i,PlayerStatus.lateJoining);
						}
					}
				}
			}
			if(network.hostDropped) return true;
			if(network.lateJoining) network.updateStatus(PlayerStatus.desynched);
			if(network.desynched){
				if(network.pendingResynch) network.updateStatus(PlayerStatus.readyToResynch);
				if(network.isHost && network.readyToResynch){
					network.acceptingNewConnections=false;
					import serialize_;
					//writeln("SENDING STATE AT FRAME: ",currentFrame," ",network.players.map!((ref p)=>p.committedFrame));
					import std.conv: text;
					enforce(currentFrame<=network.resynchCommittedFrame,text(currentFrame," ",network.resynchCommittedFrame," ",network.players.map!((ref p)=>p.status),network.players.map!((ref p)=>p.committedFrame)));
					currentFrame=network.resynchCommittedFrame;
					enforce(state.current.frame<=firstUpdatedFrame);
					if(state.commands.length<currentFrame+1)
						state.commands.length=currentFrame+1;
					state.simulateTo(currentFrame);
					firstUpdatedFrame=currentFrame;
					assert(state.current.frame==currentFrame);
					state.current.serialized((scope ubyte[] stateData){
						state.commands.serialized((scope ubyte[] commandData){
							foreach(i,ref player;network.players)
								network.sendState(cast(int)i,stateData,commandData);
						});
					});
					network.updateStatus(PlayerStatus.stateResynched);
				}
				if(network.stateResynched && network.players[network.me].status==PlayerStatus.stateResynched){
					//writeln("STATE IS ACTUALLY AT FRAME: ",currentFrame);
					enforce(firstUpdatedFrame==currentFrame);
					if(!network.isHost){
						state.lastCommitted.copyFrom(state.current);
						/+synchState.copyFrom(state.current);
						lastConfirmSynch=currentFrame;+/
					}
					if(network.players[network.me].committedFrame<currentFrame)
						network.commit(currentFrame);
					network.updateStatus(PlayerStatus.resynched);
				}
				if(network.isHost && network.resynched){
					updateCommitted();
					enforce(state.lastCommitted.frame==currentFrame);
					import std.conv: text;
					enforce(state.lastCommitted.hash==state.current.hash,text(state.lastCommitted.hash," ",state.current.hash));
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
			if(network.paused) return true;
			if(!network.playing){ // start game
				network.updateStatus(PlayerStatus.readyToStart);
				if(network.isHost&&network.readyToStart()){
					network.start(this);
				}
				return true; // ignore passed time in next frame
			}else if(network.pauseOnDrop&&network.anyonePending) return true;
			network.acceptingNewConnections=true;
		}else assert(state.lastCommitted.frame==state.current.frame);
		return false;
	}

	bool step(){
		bool oldPlayAudio=playAudio;
		//playAudio=firstUpdatedFrame<=state.current.frame;
		playAudio=false;
		scope(exit) playAudio=oldPlayAudio;
		if(updateNetwork()) return true;
		while(state.current.frame<currentFrame){
			state.step();
			firstUpdatedFrame=max(firstUpdatedFrame,state.current.frame);
			if(updateNetwork()) return true;
		}
		playAudio=oldPlayAudio;
		state.step();
		if(recording){
			recording.step();
			if(!network) recording.stepCommitted(state.current);
		}
		currentFrame=state.current.frame;
		firstUpdatedFrame=currentFrame;
		if(network){
			network.commit(currentFrame);
			playAudio=false;
			updateCommitted();
			updateNetworkGameState();
			if(!network.isHost&&lastCheckSynch<state.lastCommitted.frame){
				network.checkSynch(state.lastCommitted.frame,state.lastCommitted.hash);
				lastCheckSynch=state.lastCommitted.frame;
			}
		}else if(playback){
			if(auto replacement=playback.stateReplacement(state.current.frame)){
				assert(replacement.frame==state.current.frame);
				writeln("enountered state replacement at frame ",state.current.frame,replacement.hash!=state.current.hash?":":"");
				if(replacement.hash!=state.current.hash){
					import diff;
					diffStates(state.current,replacement);
					state.current.copyFrom(replacement);
				}
			}
			int side=-1;
			if(auto desynch=playback.desynch(state.current.frame,side)){
				auto sideName=getSideName(side,state.current);
				if(sideName=="") writeln("player ",side," desynched at frame ",state.current.frame);
				else writeln(sideName," (player ",side,") desynched at frame ",state.current.frame);
				if(desynch.hash!=state.current.hash){
					writeln("their state was replaced:");
					import diff;
					diffStates(desynch,state.current);
					//enforce(0);
				}
			}
		}
		return false;
	}
}
