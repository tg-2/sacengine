import std.algorithm;
import options,sacspell,state,controller;
import ntts: God;

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

bool isValidCommand(B)(ref Command!B command){
	return true; // TODO: defend
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
	if(isValidCommand(command)) return command;
	return Command!B.init;
}

NetworkCommand toNetwork(B)(Command!B command)in{
	assert(isValidCommand(command));
}do{
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

enum PacketType{
	nop,
	disconnect,
	ping,
	ack,
	setOption,
	readyToLoad,
	loadGame,
	readyToStart,
	startGame,
	command,
	commit,
}

struct Packet{
	int size=Packet.sizeof;
	PacketType type;
	union{
		struct{}// nop
		struct{ int id; }// ping
		struct{ int pingId; } // ack
		struct{ // setOption, readyToLoad, readyToStart
			int player;
			char[32] optionName;
			union{
				int intValue;
				int boolValue;
				float floatValue;
				God godValue;
				char[4] char4Value;
			}
		}
		struct{ uint startDelay; } // startGame
		struct{ // command
			int frame;
			NetworkCommand networkCommand;
		}
		struct{ // commit
			int commitPlayer;
			int commitFrame;
		}
	}
	static Packet nop(){ return Packet.init; }
	static Packet disconnect(){
		Packet p;
		p.type=PacketType.disconnect;
		return p;
	}
	static Packet ping(int id){
		Packet p;
		p.type=PacketType.ping;
		p.id=id;
		return p;
	}
	static Packet ack(int pingId){
		Packet p;
		p.type=PacketType.ack;
		p.pingId=pingId;
		return p;
	}
	static Packet setOption(string name)(int player,typeof(mixin(`Options.`~name)) value){
		Packet p;
		p.type=PacketType.setOption;
		p.player=player;
		optionName[]='\0';
		optionName[0..name.length]=name[];
		static assert(name.length<optionName.length);
		static if(is(typeof(value)==int)) intValue=value;
		else static if(is(typeof(value)==bool)) boolValue=value;
		else static if(is(typeof(value)==float)) floatValue=value;
		else static if(is(typeof(value)==God)) godValue=value;
		else static if(is(typeof(value)==char[4])) char4Value=value;
		else static assert(0);
		return p;
	}
	static Packet readyToLoad(int player){
		Packet p;
		p.type=PacketType.readyToLoad;
		p.player=player;
		return p;
	}
	static Packet loadGame(){
		Packet p;
		p.type=PacketType.loadGame;
		return p;
	}
	static Packet readyToStart(int player){
		Packet p;
		p.type=PacketType.readyToStart;
		p.player=player;
		return p;
	}
	static Packet startGame(uint startDelay){
		Packet p;
		p.type=PacketType.startGame;
		p.startDelay=startDelay;
		return p;
	}
	static Packet command(B)(int frame,Command!B command){
		Packet p;
		p.frame=frame;
		p.command=toNetwork(command);
		return p;
	}
	static Packet commit(int player,int frame){
		Packet p;
		p.commitPlayer=player;
		p.commitFrame=frame;
		return p;
	}
}

import std.socket;
abstract class Connection{
	abstract bool alive();
	abstract bool ready();
	abstract Packet receive();
	abstract void send(Packet packet);
}
class TCPConnection: Connection{
	Socket tcpSocket;
	this(Socket tcpSocket)in{
		assert(!tcpSocket.blocking);
	}do{
		this.tcpSocket=tcpSocket;
	}
	bool alive_=true;
	override bool alive(){ return alive_; }
	bool ready_=false;
	override bool ready(){ return ready_; }
	union{
		Packet packet;
		ubyte[packet.sizeof] data;
	}
	int dataIndex=0;
	override Packet receive(){
		assert(ready);
		auto result=packet;
		ready_=false;
		dataIndex=0;
		alive_&=tcpSocket.isAlive;
		if(alive) receiveData();
		return result;
	}
	void receiveData(){
		assert(dataIndex<data.length);
		auto ret=tcpSocket.receive(data[dataIndex..$]);
		if(ret==Socket.ERROR){
			import std.stdio;
			stderr.writeln(lastSocketError());
			ret=0;
		}
		if(ret==0){
			if(wouldHaveBlocked()) return;
			ready_=true;
			alive_=false;
			packet=Packet.disconnect();
			tcpSocket.close();
			return;
		}
		dataIndex+=ret;
		if(dataIndex==data.length){
			ready_=true;
		}
	}
	override void send(Packet packet){
		tcpSocket.send((cast(ubyte*)&packet)[0..packet.sizeof]);
	}
}

enum PlayerStatus{
	connected,
	readyToLoad,
	readyToStart,
	playing,
	disconnected,
}

struct Player{
	PlayerStatus status;
	Settings settings;
	Connection connection;
}

class Network(B){
	Player[] players;
	size_t me;
	void handlePacket(ref Player player,Packet p,Controller!B controller){
		final switch(p.type){
			case PacketType.nop: break;
			case PacketType.disconnect: player.connection=null; break;
			case PacketType.ping: player.connection.send(Packet.ack(p.id)); break;
			case PacketType.ack: break; // TODO
			case PacketType.setOption:
				auto len=0;
				while(len<p.optionName.length&&p.optionName[len]!='\0') ++len;
				if(len==p.optionName.length) break;
			Lswitch:switch(p.optionName[0..len]){
					static foreach(setting;__traits(allMembers,Settings)){
						case setting:
							if(p.player<0||p.player>=players.length) break Lswitch;
							if(players[p.player].status>=PlayerStatus.readyToLoad) break Lswitch;
							alias T=typeof(mixin(`players[p.player].settings.`~setting));
							static if(is(T==int)) mixin(`players[p.player].settings.`~setting)=p.intValue;
							else static if(is(T==bool))  mixin(`players[p.player].settings.`~setting)=p.boolValue;
							else static if(is(T==float))  mixin(`players[p.player].settings.`~setting)=p.floatValue;
							else static if(is(T==God))  mixin(`players[p.player].settings.`~setting)=p.godValue;
							else static if(is(T==char[4])) mixin(`players[p.player].settings.`~setting)=p.char4Value;
							else static assert(0);
							break Lswitch;
					}
					default: break;
				}
				break;
			case PacketType.readyToLoad:
				if(p.player<0||p.player>=players.length) break;
				players[p.player].status=max(players[p.player].status,PlayerStatus.readyToLoad);
				break;
			case PacketType.loadGame:
				// TODO: load the game, send readyToStart message
				break;
			case PacketType.readyToStart:
				if(p.player<0||p.player>=players.length) break;
				players[p.player].status=max(players[p.player].status,PlayerStatus.readyToStart);
				break;
			case PacketType.startGame:
				// TODO: wait for the specified amount, start game
				break;
			case PacketType.command:
				controller.addExternalCommand(p.frame,fromNetwork!B(p.networkCommand));
				break;
			case PacketType.commit:
				// TODO: commit state to max of all committed states
				break;
		}
	}
	void update(Controller!B controller){
		foreach(ref player;players){
			if(!player.connection) continue;
			if(!player.connection.alive){
				player.connection=null;
				player.status=PlayerStatus.disconnected;
				continue;
			}
			while(player.connection.ready){
				handlePacket(player,player.connection.receive,controller);
			}
		}
	}
}

class GameHost{
	Socket acceptingSocket;
	int[] controlledSides;
	this(int[] controlledSides){
		this.controlledSides=controlledSides;
	}
}
