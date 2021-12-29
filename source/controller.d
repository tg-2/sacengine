// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import std.stdio, std.algorithm;
import util: Array, assignArray;
import state, network, recording_;


final class Controller(B){
	GameState!B state;
	Network!B network;
	Recording!B recording, playback;
	int controlledSide;
	int commandId=0;
	int committedFrame;
	int lastCheckSynch=-1;
	int firstUpdatedFrame;
	int currentFrame;
	this(int controlledSide,GameState!B state,Network!B network,Recording!B recording,Recording!B playback){
		this.controlledSide=controlledSide;
		this.state=state;
		this.network=network;
		committedFrame=state.lastCommitted.frame;
		currentFrame=state.current.frame;
		firstUpdatedFrame=currentFrame;
		this.recording=recording;
		this.playback=playback;
		if(playback) assignArray(state.commands,playback.commands);
	}
	void addCommand(int frame,Command!B command)in{
		assert(command.id==0);
		assert(!network||network.playing||command.type==CommandType.surrender);
		assert(committedFrame<=frame);
	}do{
		if(command.side!=controlledSide) return;
		command.id=++commandId;
		firstUpdatedFrame=min(firstUpdatedFrame,frame);
		state.addCommandInconsistent(frame,command);
		if(network) network.addCommand(frame,command);
		if(recording) recording.addCommand(frame,command);
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
		assert(committedFrame<=frame);
	}do{
		firstUpdatedFrame=min(firstUpdatedFrame,frame);
		state.addCommandInconsistent(frame,command);
		if(recording) recording.addExternalCommand(frame,command);
	}
	void replaceState(scope ubyte[] serialized)in{
		assert(network&&!network.isHost);
	}do{
		import serialize_;
		state.lastCommitted.serialized(&network.logDesynch);
		deserialize(state.lastCommitted,serialized);
		committedFrame=state.lastCommitted.frame;
		state.current.copyFrom(state.lastCommitted);
		static if(B.hasAudio) B.updateAudioAfterRollback();
		currentFrame=state.current.frame;
		state.commands.length=currentFrame;
		state.commands~=Array!(Command!B)();
		firstUpdatedFrame=currentFrame;
		if(network) network.players.each!((ref p){ p.committedFrame=committedFrame; }); // TODO: solve in a better way
		if(recording) recording.replaceState(state.lastCommitted);
		network.updateStatus(PlayerStatus.resynched);
	}
	void logDesynch(int side,scope ubyte[] serialized){
		if(recording) recording.logDesynch(side,serialized,state.current);
	}
	void setSelection(int side,int wizard,CreatureGroup selection,TargetLocation loc){
		if(side!=controlledSide) return;
		addCommand(Command!B(CommandType.clearSelection,side,wizard,0,Target.init,float.init));
		foreach_reverse(id;selection.creatureIds){
			if(id==0) continue;
			addCommand(Command!B(CommandType.automaticToggleSelection,side,wizard,id,Target.init,float.init));
		}
	}
	void updateCommitted(){
		committedFrame=network.committedFrame;
		currentFrame=max(state.current.frame,committedFrame);
		state.simulateTo(currentFrame);
		while(state.lastCommitted.frame<committedFrame){
			state.stepCommitted();
			if(recording) recording.stepCommitted(state.lastCommitted);
			if(network.isHost) network.addSynch(state.lastCommitted.frame,state.lastCommitted.hash);
		}
		assert(committedFrame==state.lastCommitted.frame);
	}
	bool step(){
		playAudio=false;
		if(network){
			network.update(this);
			if(network.desynched){
				if(!network.players[network.me].status.among(PlayerStatus.readyToResynch,PlayerStatus.resynched,PlayerStatus.loading))
					network.updateStatus(PlayerStatus.readyToResynch);
				if(network.isHost && network.readyToResynch){
					state.rollback(state.lastCommitted);
					currentFrame=state.current.frame;
					network.capSynch(currentFrame);
					state.commands.length=currentFrame;
					import util: Array;
					state.commands~=Array!(Command!B)();
					firstUpdatedFrame=currentFrame;
					network.players.each!((ref p){ p.committedFrame=committedFrame; }); // TODO: solve in a better way
					import serialize_;
					state.lastCommitted.serialized((scope ubyte[] stateData){
						foreach(i,ref player;network.players) network.sendState(cast(int)i,stateData);
					});
					network.updateStatus(PlayerStatus.resynched);
				}
				if(network.isHost && network.resynched)
					network.load();
				return false;
			}
			if(!network.playing){
				network.updateStatus(PlayerStatus.readyToStart);
				if(network.isHost&&network.readyToStart()){
					network.addSynch(state.lastCommitted.frame,state.lastCommitted.hash);
					network.start(this);
				}
				return true; // ignore passed time in next frame
			}
			updateCommitted();
			if(firstUpdatedFrame<currentFrame){
				// TODO: save multiple states, pick most recent with frame<=firstUpdatedFrame?
				state.rollback(state.lastCommitted);
			}
		}else committedFrame=currentFrame;
		state.simulateTo(currentFrame);
		playAudio=true;
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
			if(!network.isHost&&lastCheckSynch<committedFrame){
				network.checkSynch(state.lastCommitted.frame,state.lastCommitted.hash);
				lastCheckSynch=committedFrame;
			}
		}else if(playback){
			if(auto replacement=playback.stateReplacement(state.current.frame)){
				assert(replacement.frame==state.current.frame);
				writeln("enountered state replacement at frame ",state.current.frame,":");
				import diff;
				diffStates(state.current,replacement);
				state.current.copyFrom(replacement);
			}
			int side=-1;
			if(auto desynch=playback.desynch(state.current.frame,side)){
				writeln("player ",side," desynched at frame ",state.current.frame);
				writeln("their state was replaced:");
				import diff;
				diffStates(desynch,state.current);
			}
		}
		return false;
	}
}
