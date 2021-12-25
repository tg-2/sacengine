// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import std.stdio, std.algorithm;
import state, network, recording_;


final class Controller(B){
	GameState!B state;
	Network!B network;
	Recording!B recording;
	int controlledSide;
	int commandId=0;
	int committedFrame;
	int lastCheckSynch=-1;
	int firstUpdatedFrame;
	int currentFrame;
	this(int controlledSide,GameState!B state,Network!B network,Recording!B recording){
		this.controlledSide=controlledSide;
		this.state=state;
		this.network=network;
		committedFrame=state.lastCommitted.frame;
		currentFrame=state.current.frame;
		firstUpdatedFrame=currentFrame;
		this.recording=recording;
		if(recording) recording.addCommitted(state.lastCommitted);
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
			if(recording) recording.addCommitted(state.lastCommitted);
			if(network.isHost) network.addSynch(state.lastCommitted.frame,state.lastCommitted.hash);
		}
		assert(committedFrame==state.lastCommitted.frame);
	}
	bool step(){
		playAudio=false;
		if(network){
			network.update(this);
			if(network.desynched)
				return false;
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
			if(!network) recording.addCommitted(state.current);
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
		}
		return false;
	}
}
