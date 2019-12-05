import state;
final class Controller(B){
	GameState!B state;
	int controlledSide;
	this(int controlledSide,GameState!B state){
		this.controlledSide=controlledSide;
		this.state=state;
	}
	int commandId=0;
	void addCommand(int frame,Command!B command){
		if(command.side!=controlledSide) return;
		command.id=++commandId;
		state.addCommand(frame,command);
	}
	void addCommand(Command!B command){
		addCommand(state.current.frame,command);
	}
	void addExternalCommand(int frame,Command!B command)in{
		assert(command.side!=controlledSide);
	}do{
		state.addCommand(frame,command);
	}
	void setSelection(int side,int wizard,CreatureGroup selection,TargetLocation loc){
		if(side!=controlledSide) return;
		addCommand(Command!B(CommandType.clearSelection,side,wizard,0,Target.init,float.init));
		foreach_reverse(id;selection.creatureIds){
			if(id==0) continue;
			addCommand(Command!B(CommandType.automaticToggleSelection,side,wizard,id,Target.init,float.init));
		}
	}
}
