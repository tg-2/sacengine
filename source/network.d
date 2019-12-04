import state, sacspell;

struct NetworkCommand{
	CommandType type;
	int side;
	int wizard;
	int creature;
	char[4] spell;
	Target target;
	float targetFacing;
	Formation formation;
	int group;
	int id;
}

Command!B fromNetwork(B)(NetworkCommand networkCommand){
	Command!B command;
	static assert(networkCommand.tupleof.length==command.tupleof.length);
	static foreach(i;0..command.tupleof.length){
		static assert(__traits(identifier,command.tupleof[i])==__traits(identifier,networkCommand.tupleof[i]));
		static if(is(typeof(command.tupleof[i])==SacSpell!B)){
			command.tupleof[i]=networkCommand.tupleof[i]!="\0\0\0\0"?SacSpell!B.get(networkCommand.tupleof[i]):null;
		}else command.tupleof[i]=networkCommand.tupleof[i];
	}
	// TODO: validate command format
	return command;
}

NetworkCommand toNetwork(B)(Command!B command){
	NetworkCommand networkCommand;
	static assert(networkCommand.tupleof.length==command.tupleof.length);
	static foreach(i;0..command.tupleof.length){
		static assert(__traits(identifier,command.tupleof[i])==__traits(identifier,networkCommand.tupleof[i]));
		static if(is(typeof(command.tupleof[i])==SacSpell!B)){
			networkCommand.tupleof[i]=command.tupleof[i]?command.tupleof[i].tag:"\0\0\0\0";
		}else networkCommand.tupleof[i]=command.tupleof[i];
	}
	return networkCommand;	
}
