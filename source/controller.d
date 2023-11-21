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

	bool paused=false;
	bool waitingOnNetwork=false;
	void pause(){
		paused=true;
		timer.pause();
		timer.setFrame(timer.frame);
	}
	void unpause(){
		paused=false;
		if(waitingOnNetwork) return;
		timer.setFrame(state.currentFrame);
		timer.start();
	}

	bool isControllingSide(int side){
		if(network&&!network.players[network.me].isControllingState)
			return false;
		return side==controlledSide;
	}
	void addCommand(Command!B command)in{
		assert(command.id==0);
	}do{
		if(network&&!network.playing) return;
		if(!isControllingSide(command.side)){
			bool observerChat=command.side==-1&&command.type==CommandType.chatMessage;
			if(!observerChat) return;
			if(network&&!network.isHost){
				network.addCommand(-1,command);
				return;
			}
		}
		command.id=++commandId;
		auto frame=currentFrame;
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
		state.replaceState(serialized);
		import serialize_;
		if(network.logDesynch_) state.committed.serialized(&network.logDesynch); // TODO: don't log if late join
		if(recording) recording.replaceState(state.current,state.commands);
		network.updateStatus(PlayerStatus.stateResynched);
	}
	void logDesynch(int side,scope ubyte[] serialized){
		if(recording) try{ recording.logDesynch(side,serialized,state.current); }catch(Exception e){ stderr.writeln("bad desynch log: ",e.msg); }
	}
	void updateCommittedTo(int frame){
		if(network.players[network.me].committedFrame<currentFrame)
			network.commit(currentFrame);
		auto committedFrame=network.committedFrame;
		if(frame==-1) frame=committedFrame;
		if(!network.isHost&&(network.desynched||network.lateJoining)) return; // avoid simulating entire game after rejoin
		import std.conv: text;
		enforce(state.committedFrame<=committedFrame,text(state.committedFrame," ",committedFrame," ",network.players.map!((ref p)=>p.committedFrame)," ",network.activePlayerIds," ",network.players.map!((ref p)=>p.status)));
		auto target=min(frame,committedFrame);
		if(target<state.committedFrame)
			return;
		state.simulateCommittedTo!((){
			if(recording) recording.stepCommitted(state.committed);
			if(network.isHost) network.addSynch(state.committedFrame,state.committed.hash);
			if(network.players[network.me].committedFrame<currentFrame)
				network.commit(currentFrame);
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
			p.lostWizard|=!state.committed.isValidTarget(state.slots[p.slot].wizard,TargetType.creature);
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
					enforce(state.committed.frame==state.current.frame);
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

	bool run(){
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
		}else if(playback){
			playback.report(state.current);
		}
		return false;
	}
}
