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
	bool isControllingSide(int side){
		if(network&&!network.players[network.me].isControllingState)
			return false;
		return side==controlledSide;
	}
	void addCommand(Command!B command)in{
		assert(command.id==0);
	}do{
		if(network&&!network.playing&&command.type!=CommandType.surrender) return;
		if(!isControllingSide(command.side)){
			bool observerChat=command.side==-1&&command.type==CommandType.chatMessage;
			if(!observerChat) return;
			if(network&&!network.isHost){
				network.addCommand(-1,command);
				return;
			}
		}
		command.id=++commandId;
		state.addCommand(command);
		auto frame=state.currentFrame;
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
		state.replaceState(serialized);
		import serialize_;
		if(network.logDesynch_) state.lastCommitted.serialized(&network.logDesynch); // TODO: don't log if late join
		if(recording) recording.replaceState(state.current,state.commands);
		network.updateStatus(PlayerStatus.stateResynched);
	}
	void logDesynch(int side,scope ubyte[] serialized){
		if(recording) try{ recording.logDesynch(side,serialized,state.current); }catch(Exception e){ stderr.writeln("bad desynch log: ",e.msg); }
	}
	void updateCommitted()in{
		assert(!!network);
	}do{
		auto committedFrame=network.committedFrame;
		if(!network.isHost&&(network.desynched||network.lateJoining)) return; // avoid simulating entire game after rejoin
		import std.conv: text;
		enforce(state.committedFrame<=committedFrame,text(state.committedFrame," ",committedFrame," ",network.players.map!((ref p)=>p.committedFrame)," ",network.activePlayerIds," ",network.players.map!((ref p)=>p.status)));
		if(state.commands.length<committedFrame+1)
			state.commands.length=committedFrame+1;
		while(state.committedFrame<committedFrame){
			//playAudio=firstUpdatedFrame<=state.committedFrame;
			state.stepCommittedUnsafe();
			if(recording) recording.stepCommitted(state.lastCommitted);
			if(network.isHost) network.addSynch(state.committedFrame,state.lastCommitted.hash);
		}
		//playAudio=false;
		enforce(state.committedFrame==committedFrame,
		        text(network.activePlayerIds," ",network.players.map!((ref p)=>p.committedFrame)," ",
		             committedFrame," ",state.committedFrame));
		state.updateCurrent();
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
					//writeln("SENDING STATE AT FRAME: ",currentFrame," ",network.players.map!((ref p)=>p.committedFrame));
					import std.conv: text;
					enforce(state.currentFrame<=network.resynchCommittedFrame,text(state.currentFrame," ",network.resynchCommittedFrame," ",network.players.map!((ref p)=>p.status),network.players.map!((ref p)=>p.committedFrame)));
					state.simulateTo(network.resynchCommittedFrame);
					import serialize_;
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
					enforce(state.currentReady);
					if(!network.isHost)
						state.commit();
					if(network.players[network.me].committedFrame<state.currentFrame)
						network.commit(state.currentFrame);
					network.updateStatus(PlayerStatus.resynched);
				}
				if(network.isHost && network.resynched){
					updateCommitted();
					enforce(state.currentReady);
					import std.conv: text;
					enforce(state.lastCommitted.frame==state.current.frame);
					if(state.lastCommitted.hash!=state.current.hash){
						stderr.writeln("warning: local desynch (",state.lastCommitted.hash,"!=",state.current.hash,")");
						state.current.copyFrom(state.lastCommitted);
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
			if(network.paused) return true;
			if(!network.playing){ // start game
				network.updateStatus(PlayerStatus.readyToStart);
				if(network.isHost&&network.readyToStart()){
					network.start(this);
				}
				return true; // ignore passed time in next frame
			}else if(network.pauseOnDrop&&network.anyonePending) return true;
			network.acceptingNewConnections=true;
		}else assert(state.committedFrame==state.current.frame);
		return false;
	}

	bool step(){
		bool oldPlayAudio=playAudio;
		//playAudio=firstUpdatedFrame<=state.current.frame;
		playAudio=false;
		scope(exit) playAudio=oldPlayAudio;
		if(updateNetwork()) return true;
		if(state.firstUpdatedFrame<state.current.frame){
			// TODO: save multiple states, pick most recent with frame<=firstUpdatedFrame?
			import std.conv: text;
			enforce(state.committedFrame<=state.firstUpdatedFrame,text(state.committedFrame," ",state.firstUpdatedFrame," ",state.currentFrame));
			state.rollback();
		}
		while(state.current.frame<state.currentFrame){
			state.step();
			if(updateNetwork()) return true;
		}
		playAudio=oldPlayAudio;
		state.step();
		if(recording){
			recording.step();
			if(!network) recording.stepCommitted(state.current);
		}
		assert(state.current.frame==state.currentFrame);
		if(network){
			network.commit(state.currentFrame);
			playAudio=false;
			updateCommitted();
			updateNetworkGameState();
			if(!network.isHost&&lastCheckSynch<state.committedFrame){
				network.checkSynch(state.committedFrame,state.lastCommitted.hash);
				lastCheckSynch=state.committedFrame;
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
				}
			}
		}
		return false;
	}
}
