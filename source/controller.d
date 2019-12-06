import std.algorithm;
import state, network;
final class Controller(B){
	GameState!B state;
	Network!B network;
	int controlledSide;
	int commandId=0;
	int committedFrame;
	int firstUpdatedFrame;
	int currentFrame;
	this(int controlledSide,GameState!B state,Network!B network){
		this.controlledSide=controlledSide;
		this.state=state;
		this.network=network;
		committedFrame=state.lastCommitted.frame;
		currentFrame=state.current.frame;
		firstUpdatedFrame=currentFrame;
	}
	void addCommand(int frame,Command!B command)in{
		assert(command.id==0);
		assert(!network||network.playing);
	}do{
		if(command.side!=controlledSide) return;
		command.id=++commandId;
		firstUpdatedFrame=min(firstUpdatedFrame,frame);
		state.addCommandInconsistent(frame,command);
		if(network) network.addCommand(frame,command);
	}
	void addCommand(Command!B command){
		if(network&&!network.playing) return;
		addCommand(state.current.frame,command);
	}
	void addExternalCommand(int frame,Command!B command)in{
		assert(command.side!=controlledSide);
	}do{
		firstUpdatedFrame=min(firstUpdatedFrame,frame);
		state.addCommandInconsistent(frame,command);
	}
	void setSelection(int side,int wizard,CreatureGroup selection,TargetLocation loc){
		if(side!=controlledSide) return;
		addCommand(Command!B(CommandType.clearSelection,side,wizard,0,Target.init,float.init));
		foreach_reverse(id;selection.creatureIds){
			if(id==0) continue;
			addCommand(Command!B(CommandType.automaticToggleSelection,side,wizard,id,Target.init,float.init));
		}
	}
	void step(){
		if(network){
			network.update(this);
			if(!network.playing){
				network.updateStatus(PlayerStatus.playing);
				if(network.isHost&&network.readyToStart())
					network.start();
				return;
			}
			committedFrame=network.committedFrame;
			assert(committedFrame<=currentFrame);
			if(state.lastCommitted.frame<committedFrame)
				state.simulateCommittedTo(committedFrame);
			if(firstUpdatedFrame<currentFrame){
				// TODO: save multiple states, pick most recent with frame<=firstUpdatedFrame?
				state.rollback(state.lastCommitted);
				state.simulateTo(currentFrame);
			}
		}else committedFrame=currentFrame;
		state.simulateTo(currentFrame);
		state.step();
		currentFrame=state.current.frame;
		firstUpdatedFrame=currentFrame;
		if(network) network.commit(currentFrame);
	}
}
