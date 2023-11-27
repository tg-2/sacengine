// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import std.algorithm, std.range, std.stdio, std.conv, std.exception, core.thread;
import std.traits: Unqual;
import util;
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
	CommandQueueing queueing;
}

bool isValidCommand(B)(ref Command!B command){
	// TODO: defend comprehensively
	return CommandType.min<=command.type&&command.type<=CommandType.max;
}
bool isCommandWithRaw(CommandType type)nothrow{
	final switch(type) with(CommandType){
		case none: return false;
		case moveForward,moveBackward,stopMoving,turnLeft,turnRight,stopTurning: return false;
		case clearSelection,select,selectAll,automaticSelectAll,toggleSelection,automaticToggleSelection,addAllToSelection,automaticAddAllToSelection: return false;
		case defineGroup,addToGroup,selectGroup,automaticSelectGroup: return false;
		case setFormation: return false;
		case retreat,move,guard,guardArea,attack,advance: return false;
		case castSpell,useAbility: return false;
		case surrender: return false;
		case chatMessage: return true;
	}
}

Command!B fromNetworkImpl(B)(NetworkCommand networkCommand){
	Command!B command;
	static assert(networkCommand.tupleof.length==command.tupleof.length-1);
	static assert(__traits(identifier,command.tupleof[$-1])=="chatMessage");
	static foreach(i;0..command.tupleof.length-1){
		static assert(__traits(identifier,command.tupleof[i])==__traits(identifier,networkCommand.tupleof[i]));
		static if(is(typeof(command.tupleof[i])==SacSpell!B)){
			command.tupleof[i]=networkCommand.tupleof[i]!="\0\0\0\0"?SacSpell!B.get(networkCommand.tupleof[i]):null;
		}else command.tupleof[i]=networkCommand.tupleof[i];
	}
	return command;
}

Command!B fromNetwork(B)(NetworkCommand networkCommand){
	enforce(!isCommandWithRaw(networkCommand.type));
	auto command=fromNetworkImpl!B(networkCommand);
	if(isValidCommand(command)) return command;
	return Command!B.init;
}

Command!B fromNetworkRaw(B)(NetworkCommand networkCommand,scope ubyte[] rawData){
	enforce(isCommandWithRaw(networkCommand.type));
	auto command=fromNetworkImpl!B(networkCommand);
	switch(command.type){
		case CommandType.chatMessage:
			import serialize_;
			deserialize(command.chatMessage,ObjectState!B.init,rawData);
			break;
		default: enforce(0,"TODO");
	}
	if(isValidCommand(command)) return command;
	return Command!B.init;
}

NetworkCommand toNetwork(B)(ref Command!B command)in{
	assert(isValidCommand(command));
}do{
	NetworkCommand networkCommand;
	static assert(networkCommand.tupleof.length==command.tupleof.length-1);
	static assert(__traits(identifier,command.tupleof[$-1])=="chatMessage");
	static foreach(i;0..command.tupleof.length-1){
		static assert(__traits(identifier,command.tupleof[i])==__traits(identifier,networkCommand.tupleof[i]));
		static if(is(typeof(command.tupleof[i])==SacSpell!B)){
			networkCommand.tupleof[i]=command.tupleof[i]?command.tupleof[i].tag:"\0\0\0\0";
		}else networkCommand.tupleof[i]=command.tupleof[i];
	}
	return networkCommand;
}

void withRawCommandData(B)(ref Command!B command,scope void delegate(scope ubyte[]) dg)in{
	assert(isValidCommand(command));
	assert(isCommandWithRaw(command.type));
}do{
	enforce(isCommandWithRaw(command.type));
	switch(command.type){
		case CommandType.chatMessage:
			import serialize_;
			command.chatMessage.serialized(dg);
			break;
		default: enforce(0,"TODO");
	}
}

enum PacketPurpose{
	peerToPeer,  // message from one peer to another
	hostMessage, // message from host
	hostQuery,   // message to host
	broadcast,   // messages that need to be received in consistent order by all other peers
}

enum PacketType{
	// peer to peer
	nop,
	disconnect,
	ping,
	ack,
	// host message
	updatePlayerId,
	updateSlot,
	sendMap,
	sendState,
	initGame,
	loadGame,
	startGame,
	setFrame,
	nudgeTimer,
	resetCommitted,
	requestStatusUpdate,
	confirmSynch,
	// host query
	join,
	checkSynch,
	logDesynch,
	// broadcast
	updateSetting,
	clearArraySetting,
	appendArraySetting,
	confirmArraySetting,
	setMap,
	appendMap,
	confirmMap,
	updateStatus,
	command,
	commandRaw,
	commit,
	jsonCommand,
	jsonResponse,
}

enum arrayLengthLimit=4096;

PacketPurpose purposeFromType(PacketType type){
	final switch(type) with(PacketType) with(PacketPurpose){
		case nop,disconnect,ping,ack: return peerToPeer;
		case updatePlayerId,updateSlot,sendMap,sendState,initGame,loadGame,startGame,setFrame,nudgeTimer,resetCommitted,requestStatusUpdate,confirmSynch,jsonResponse: return hostMessage;
		case join,checkSynch,logDesynch,jsonCommand: return hostQuery;
		case updateSetting,clearArraySetting,appendArraySetting,confirmArraySetting,setMap,appendMap,confirmMap,updateStatus,command,commandRaw,commit: return broadcast;
	}
}

bool isPacketType(int type){
	return PacketType.min<=type && type<=PacketType.max;
}

bool isHeaderType(PacketType type){
	final switch(type) with(PacketType){
		case nop,disconnect,ping,ack,updatePlayerId,updateSlot: return false;
		case sendMap,sendState,initGame: return true;
		case loadGame,startGame,setFrame,nudgeTimer,resetCommitted,requestStatusUpdate,confirmSynch: return false;
		case join: return true;
		case checkSynch: return false;
		case logDesynch: return true;
		case updateSetting,clearArraySetting,appendArraySetting,confirmArraySetting,setMap,appendMap,confirmMap,updateStatus,command: return false;
		case commandRaw: return true;
		case commit: return false;
		case jsonCommand,jsonResponse: return true;
	}
}

struct Packet{
	string toString(){
		final switch(type) with(PacketType){
			case nop: return "Packet.nop()";
			case disconnect: return "Packet.disconnect()";
			case ping: return text("Packet.ping(",id,")");
			case ack: return text("Packet.ack(",pingId,")");
			case updatePlayerId: return text("Packet.updatePlayerId(",id,")");
			case updateSlot: return text("Packet.updateSlot(",player,",",intValue,")");
			case sendMap: return text("Packet.sendMap(",rawDataSize,",...)");
			case sendState: return text("Packet.sendState(",rawDataSize,",...)");
			case initGame: return text("Packet.initGame(",rawDataSize,",...)");
			case loadGame: return text("Packet.loadGame()");
			case startGame: return text("Packet.startGame(",startDelay,")");
			case setFrame: return text("Packet.setFrame(",newFrame,")");
			case nudgeTimer: return text("Packet.nudgeTimer(",timerAdjustHnsecs,")");
			case resetCommitted: return text("Packet.commit(",commitPlayer,",",commitFrame,")");
			case confirmSynch: return text("Packet.confirmSynch(",synchFrame,",",synchHash,")");
			case requestStatusUpdate: return text("Packet.requestStatusUpdate(",requestedStatus,")");
			case join: return text("Packet.join(",rawDataSize,",...)");
			case checkSynch: return text("Packet.checkSynch(",synchFrame,",",synchHash,")");
			case logDesynch: return text("Packet.logDesynch(",rawDataSize,"...)");
			case updateSetting:
				auto len=0;
				while(len<optionName.length&&optionName[len]!='\0') ++len;
				switch(optionName[0..len]){
					static foreach(setting;__traits(allMembers,Settings)){{
						alias T=typeof(mixin(`Settings.`~setting));
						static if(!is(T==S[],S)){
							case setting:
								static if(is(T==int)) return text(`Packet.updateSetting!"`,setting,`"(`,player,",",intValue,")");
								else static if(is(T==bool))  return text(`Packet.updateSetting!"`,setting,`"(`,player,",",boolValue,")");
								else static if(is(T==float))  return text(`Packet.updateSetting!"`,setting,`"(`,player,",",floatValue,")");
								else static if(is(T==God)) return text(`Packet.updateSetting!"`,setting,`"(`,player,",",godValue,")");
								else static if(is(T==char[4]))  return text(`Packet.updateSetting!"`,setting,`"(`,player,`,"`,char4Value,`")`);
								else static assert(0);
						}
					}}
					default: return text(`Packet.updateSetting!"`,optionName[0..len],`"(?)`);
				}
			// TODO: generalize packet types on arrays and strings
			case clearArraySetting:
				auto len=0;
				while(len<optionName.length&&optionName[len]!='\0') ++len;
				return text(`Packet.clearArraySetting!"`,optionName[0..len],`"(`,player,`)`);
			case appendArraySetting:
				auto len=0;
				while(len<optionName.length&&optionName[len]!='\0') ++len;
				switch(optionName[0..len]){
					static foreach(setting;__traits(allMembers,Settings)){{
						alias T=typeof(mixin(`Settings.`~setting));
						static if(is(T==S[],S)){
							case setting:
								return text(`Packet.appendArraySetting!"`,setting,`"(`,player,`,`,getValue!S(),`)`);
						}
					}}
					default: return text(`Packet.appendArraySetting!"`,optionName[0..len],`"(?)`);
				}
			case confirmArraySetting:
				auto len=0;
				while(len<optionName.length&&optionName[len]!='\0') ++len;
				return text(`Packet.confirmArraySetting!"`,optionName[0..len],`"(`,player,`)`);
			case setMap: return text("Packet.setMap(",mapPlayer,",",mapName,")");
			case appendMap: return text("Packet.appendMap(",mapPlayer,",",mapName,")");
			case confirmMap: return text("Packet.confirmMap(",player,")");
			case updateStatus: return text("Packet.updateStatus(",player,`,PlayerStatus.`,newStatus,")");
			case command: return text("Packet.command(fromNetwork(",networkCommand,"))");
			case commandRaw: return text("Packet.commandRaw(fromNetwork(",networkCommand,"))");
			case commit: return text("Packet.commit(",commitPlayer,",",commitFrame,")");
			case jsonCommand: return text("Packet.jsonCommand(",rawDataSize,"...)");
			case jsonResponse: return text("Packet.jsonResponse(",rawDataSize,"...)");
		}
	}
	int size=0;
	PacketType type;
	union{
		struct{}// nop
		struct{}// disconnect
		struct{ int id; }// updatePlayerId
		struct{}// loadGame
		struct{ long startDelay; } // startGame
		struct{ int newFrame; } // setFrame
		struct{ long timerAdjustHnsecs; } // nudgeTimer
		struct{ // checkSynch, confirmSynch
			int synchFrame;
			uint synchHash;
		}
		struct{ PlayerStatus requestedStatus; } // requestStatusUpdate
		struct{ long pingId; } // ping, ack
		struct{ // updateSlot, updateStatus, updateSetting, clearArraySetting, appendArraySetting, confirmArraySetting
			int player;
			union{
				struct{// updateSetting, clearArraySetting, appendArraySetting, confirmArraySetting
					char[32] optionName;
					union{
						int intValue;
						int boolValue;
						float floatValue;
						God godValue;
						char[4] char4Value;
						char charValue;
						SpellSpec spellSpecValue;
					}
				}
				struct{
					PlayerStatus newStatus;
				}
			}
		}
		struct{ int mapPlayer; char[32] mapName; } // setMap, appendMap, confirmMap
		struct{ // command, commandRaw. sendMap, sendState, initGame, join, logDesynch, jsonCommand, jsonResponse
			ulong rawDataSize; // commandRaw, sendMap, sendState, initGame, join, logDesynch, jsonCommand, jsonResponse
			int frame; // command, commandRaw
			NetworkCommand networkCommand; // command, commandRaw
		}
		struct{ // commit, resetCommitted
			int commitPlayer;
			int commitFrame;
		}
	}
	private template memberSize(Members...){
		template getSize(alias member){
			enum workaround=__traits(getMember, Packet, __traits(identifier, member)).offsetof; // member.offsetof does not work
			enum getSize=workaround+member.sizeof;
		}
		import std.traits: staticMap;
		enum memberSize=[staticMap!(getSize,Members)].reduce!max;
	}
	static Packet nop(){ return Packet.init; }
	static Packet disconnect(){
		Packet p;
		p.type=PacketType.disconnect;
		p.size=memberSize!type;
		return p;
	}
	static Packet ping(long id){
		Packet p;
		p.type=PacketType.ping;
		p.pingId=id;
		p.size=memberSize!(type,pingId);
		return p;
	}
	static Packet ack(long pingId){
		Packet p;
		p.type=PacketType.ack;
		p.pingId=pingId;
		p.size=memberSize!(type,pingId);
		return p;
	}
	static Packet updatePlayerId(int id){
		Packet p;
		p.type=PacketType.updatePlayerId;
		p.id=id;
		p.size=memberSize!(type,id);
		return p;
	}
	static Packet updateSlot(int player,int slot){
		Packet p;
		p.type=PacketType.updateSlot;
		p.player=player;
		p.intValue=slot;
		p.size=memberSize!(type,player,intValue);
		return p;
	}
	static Packet sendMap(ulong rawDataSize){
		Packet p;
		p.type=PacketType.sendMap;
		p.rawDataSize=rawDataSize;
		p.size=memberSize!(type,rawDataSize);
		return p;
	}
	static Packet sendState(ulong rawDataSize){
		Packet p;
		p.type=PacketType.sendState;
		p.rawDataSize=rawDataSize;
		p.size=memberSize!(type,rawDataSize);
		return p;
	}
	static Packet initGame(ulong rawDataSize){
		Packet p;
		p.type=PacketType.initGame;
		p.rawDataSize=rawDataSize;
		p.size=memberSize!(type,rawDataSize);
		return p;
	}
	static Packet loadGame(){
		Packet p;
		p.type=PacketType.loadGame;
		p.size=memberSize!type;
		return p;
	}
	static Packet startGame(long startDelay){
		Packet p;
		p.type=PacketType.startGame;
		p.startDelay=startDelay;
		p.size=memberSize!(type,startDelay);
		return p;
	}
	static Packet setFrame(int frame){
		Packet p;
		p.type=PacketType.setFrame;
		p.newFrame=frame;
		p.size=memberSize!(type,newFrame);
		return p;
	}
	static Packet nudgeTimer(long hnsecs){
		Packet p;
		p.type=PacketType.nudgeTimer;
		p.timerAdjustHnsecs=hnsecs;
		p.size=memberSize!(type,timerAdjustHnsecs);
		return p;
	}
	static Packet resetCommitted(int player,int frame){
		Packet p;
		p.type=PacketType.resetCommitted;
		p.commitPlayer=player;
		p.commitFrame=frame;
		p.size=memberSize!(type,commitPlayer,commitFrame);
		return p;
	}
	static Packet requestStatusUpdate(PlayerStatus status){
		Packet p;
		p.type=PacketType.requestStatusUpdate;
		p.requestedStatus=status;
		p.size=memberSize!(type,requestedStatus);
		return p;
	}
	static Packet confirmSynch(int frame,uint hash){
		Packet p;
		p.type=PacketType.confirmSynch;
		p.synchFrame=frame;
		p.synchHash=hash;
		p.size=memberSize!(type,synchFrame,synchHash);
		return p;
	}
	static Packet join(ulong rawDataSize){
		Packet p;
		p.type=PacketType.join;
		p.rawDataSize=rawDataSize;
		p.size=memberSize!(type,rawDataSize);
		return p;
	}
	static Packet checkSynch(int frame,uint hash){
		Packet p;
		p.type=PacketType.checkSynch;
		p.synchFrame=frame;
		p.synchHash=hash;
		p.size=memberSize!(type,synchFrame,synchHash);
		return p;
	}
	static Packet logDesynch(ulong rawDataSize){
		Packet p;
		p.type=PacketType.logDesynch;
		p.rawDataSize=rawDataSize;
		p.size=memberSize!(type,rawDataSize);
		return p;
	}
	template valueMember(T){
		static if(is(T==int)) alias valueMember=intValue;
		else static if(is(T==bool)) alias valueMember=boolValue;
		else static if(is(T==float)) alias valueMember=floatValue;
		else static if(is(Unqual!T==char)) alias valueMember=charValue;
		else static if(is(T==char[4])) alias valueMember=char4Value;
		else static if(is(Unqual!T==SpellSpec)) alias valueMember=spellSpecValue;
		else static assert(0,T.stringof);
	}
	void setValue(T)(T value){ valueMember!T=value; }
	T getValue(T)(){
		static if(is(T==bool)) return !!boolValue;
		else return valueMember!T;
	}
	static Packet updateSetting(string name)(int player,typeof(mixin(`Options.`~name)) value){
		Packet p;
		p.type=PacketType.updateSetting;
		p.player=player;
		p.optionName[]='\0';
		p.optionName[0..name.length]=name[];
		static assert(name.length<optionName.length);
		p.setValue(value);
		p.size=memberSize!(type,player,optionName,valueMember!(typeof(value)));
		return p;
	}
	static Packet clearArraySetting(string name)(int player){
		Packet p;
		p.type=PacketType.clearArraySetting;
		p.player=player;
		p.optionName[]='\0';
		p.optionName[0..name.length]=name[];
		static assert(name.length<optionName.length);
		p.size=memberSize!(type,player,optionName);
		return p;
	}
	static Packet appendArraySetting(string name)(int player,typeof(mixin(`Options.`~name~`[0]`)) value){
		Packet p;
		p.type=PacketType.appendArraySetting;
		p.player=player;
		p.optionName[]='\0';
		p.optionName[0..name.length]=name[];
		static assert(name.length<optionName.length);
		p.setValue(value);
		p.size=memberSize!(type,player,optionName,valueMember!(typeof(value)));
		return p;
	}
	static Packet confirmArraySetting(string name)(int player){
		Packet p;
		p.type=PacketType.confirmArraySetting;
		p.player=player;
		p.optionName[]='\0';
		p.optionName[0..name.length]=name[];
		static assert(name.length<optionName.length);
		p.size=memberSize!(type,player,optionName);
		return p;
	}
	static Packet setMap(int player,string part)in{
		assert(part.length<=mapName.length);
	}do{
		Packet p;
		p.type=PacketType.setMap;
		p.mapPlayer=player;
		p.mapName[0..part.length]=part;
		p.mapName[part.length..$]=0;
		p.size=memberSize!(type,mapPlayer,mapName);
		return p;
	}
	static Packet appendMap(int player,string part)in{
		assert(part.length<=mapName.length);
	}do{
		Packet p;
		p.type=PacketType.appendMap;
		p.mapPlayer=player;
		p.mapName[0..part.length]=part;
		p.mapName[part.length..$]=0;
		p.size=memberSize!(type,mapPlayer,mapName);
		return p;
	}
	static Packet confirmMap(int player){
		Packet p;
		p.type=PacketType.confirmMap;
		p.player=player;
		p.size=memberSize!(type,player);
		return p;
	}
	static Packet updateStatus(int player,PlayerStatus newStatus){
		Packet p;
		p.type=PacketType.updateStatus;
		p.player=player;
		p.newStatus=newStatus;
		p.size=memberSize!(type,player,newStatus);
		return p;
	}
	static Packet command(B)(int frame,Command!B command){
		enforce(!isCommandWithRaw(command.type));
		Packet p;
		p.type=PacketType.command;
		p.rawDataSize=0;
		p.frame=frame;
		p.networkCommand=toNetwork(command);
		p.size=memberSize!(type,rawDataSize,frame,networkCommand);
		return p;
	}
	static Packet commandRaw(B)(int frame,Command!B command,ulong rawDataSize){
		enforce(isCommandWithRaw(command.type));
		Packet p;
		p.type=PacketType.commandRaw;
		p.rawDataSize=rawDataSize;
		p.frame=frame;
		p.networkCommand=toNetwork(command);
		p.size=memberSize!(type,rawDataSize,frame,networkCommand);
		return p;
	}
	static Packet commit(int player,int frame){
		Packet p;
		p.type=PacketType.commit;
		p.commitPlayer=player;
		p.commitFrame=frame;
		p.size=memberSize!(type,commitPlayer,commitFrame);
		return p;
	}
	static Packet jsonCommand(ulong rawDataSize){
		Packet p;
		p.type=PacketType.jsonCommand;
		p.rawDataSize=rawDataSize;
		p.size=memberSize!(type,rawDataSize);
		return p;
	}
	static Packet jsonResponse(ulong rawDataSize){
		Packet p;
		p.type=PacketType.jsonResponse;
		p.rawDataSize=rawDataSize;
		p.size=memberSize!(type,rawDataSize);
		return p;
	}
}

abstract class Connection{
	abstract bool alive();
	abstract bool ready();
	abstract bool rawReady();
	abstract Packet receive();
	abstract void receiveRaw(scope void delegate(scope ubyte[]));
	abstract void send(Packet packet);
	abstract void send(Packet packet,scope ubyte[] rawData);
	abstract void send(Packet packet,scope ubyte[] rawData1,scope ubyte[] rawData2);
	abstract void close();
}

abstract class ConnectionImpl: Connection{
	protected abstract bool checkAlive();
	protected long tryReceive(scope ubyte[] data);
	protected long trySend(scope ubyte[] data);

	bool alive_=true;
	override bool alive(){
		alive_&=checkAlive;
		return alive_;
	}
	bool ready_=false;
	override bool ready(){
		if(!alive) return false;
		sendRemaining();
		if(ready_) return true;
		receiveData();
		return ready_;
	}
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
		if(isHeaderType(packet.type)) rawReady_=true;
		return result;
	}
	bool rawReady_=false;
	Array!ubyte rawData;
	int rawDataIndex=0;
	override bool rawReady(){ return rawReady_; }
	override void receiveRaw(scope void delegate(scope ubyte[]) dg){
		assert(rawReady_);
		dg(rawData.data);
		rawData.length=0;
		rawDataIndex=0;
		rawReady_=false;
	}
	private void receiveData(){
		enum sizeAmount=Packet.size.offsetof+Packet.size.sizeof;
		static assert(sizeAmount==4);
		if(dataIndex<sizeAmount) dataIndex+=tryReceive(data[dataIndex..sizeAmount]);
		if(dataIndex<sizeAmount) return;
		if(packet.size>data.length){
			stderr.writeln("packet too long (",packet.size,")");
			close();
			return;
		}
		if(dataIndex<packet.size) dataIndex+=tryReceive(data[dataIndex..packet.size]);
		if(dataIndex<packet.size) return;
		enum typeAmount=Packet.type.offsetof+Packet.type.sizeof;
		static assert(typeAmount==8);
		if(packet.size<typeAmount){
			stderr.writeln("packet too short (",packet.size,")");
			close();
			return;
		}
		if(!isPacketType(packet.type)){
			stderr.writeln("invalid packet type ",packet.type);
			close();
			return;
		}
		data[packet.size..$]=0;
		if(isHeaderType(packet.type)){
			if(rawData.length==0) rawData.length=packet.rawDataSize;
			assert(rawDataIndex<rawData.length);
			rawDataIndex+=tryReceive(rawData.data[rawDataIndex..$]);
			if(rawDataIndex==rawData.length)
				ready_=true;
		}else ready_=true;
	}
	Array!ubyte remainingData;
	long remainingIndex=0;
	private bool sendRemaining(){
		while(remainingIndex<remainingData.length){
			auto sent=trySend(remainingData.data[remainingIndex..$]);
			if(sent==0) return false;
			remainingIndex+=sent;
		}
		return true;
	}
	private void bufferData(scope ubyte[] data){
		if(!alive_||!data.length) return;
		remainingData~=data;
		if(remainingData.length>4096 && remainingData.length/2<=remainingIndex){
			remainingData.data[0..$-remainingIndex]=remainingData.data[remainingIndex..$];
			remainingData.length=remainingData.length-remainingIndex;
			remainingIndex=0;
		}
	}
	private void send(scope ubyte[] data){
		auto sent=sendRemaining()?trySend(data):0;
		bufferData(data[sent..$]);
	}
	final override void send(Packet packet){
		assert(!isHeaderType(packet.type));
		send((cast(ubyte*)&packet)[0..packet.size]);
	}
	final override void send(Packet packet,scope ubyte[] rawData){
		assert(isHeaderType(packet.type)||rawData.length==0);
		assert(!isHeaderType(packet.type)||packet.rawDataSize==rawData.length);
		send((cast(ubyte*)&packet)[0..packet.size]);
		send(rawData);
	}
	final override void send(Packet packet,scope ubyte[] rawData1,scope ubyte[] rawData2){
		assert(isHeaderType(packet.type)||rawData1.length+rawData2.length==0);
		assert(!isHeaderType(packet.type)||packet.rawDataSize==rawData1.length+rawData2.length);
		send((cast(ubyte*)&packet)[0..packet.size]);
		send(rawData1);
		send(rawData2);
	}
	protected abstract void closeImpl();
	final override void close(){
		if(alive) for(int i=0;alive&&!sendRemaining()&&i<10;i++) Thread.sleep(50.dur!"msecs");
		closeImpl();
		destroy(remainingData);
	}
}

import std.socket;
class TCPConnection: ConnectionImpl{
	Socket tcpSocket;
	this(Socket tcpSocket)in{
		assert(!tcpSocket.blocking);
	}do{
		this.tcpSocket=tcpSocket;
	}
	override bool checkAlive(){ return tcpSocket.isAlive;  }
	override protected long tryReceive(scope ubyte[] data){
		auto ret=tcpSocket.receive(data);
		if(ret==Socket.ERROR){
			if(wouldHaveBlocked()) return 0;
			try stderr.writeln(lastSocketError());
			catch(Exception) stderr.writeln("socket error");
			alive_=false;
			tcpSocket.close();
			return 0;
		}
		return ret;
	}
	override protected long trySend(scope ubyte[] data){
		/+import std.datetime.stopwatch;
		static sw=StopWatch(AutoStart.no);
		if(!sw.running) sw.start();
		static long amountSent=0;
		auto rateLimit=100000; // 100 kbps
		auto limit=rateLimit*sw.peek.total!"msecs"()/1000;
		writeln(sw.peek.total!"msecs");
		auto allowedToSend=max(0,limit-amountSent);
		auto sent=tcpSocket.send(data[0..min(allowedToSend,$)]);
		scope(success) amountSent+=sent;+/
		auto sent=tcpSocket.send(data);
		if(sent==Socket.ERROR){
			if(!wouldHaveBlocked()){
				try stderr.writeln(lastSocketError());
				catch(Exception) stderr.writeln("socket error");
				alive_=false;
				tcpSocket.close();
			}
			sent=0;
		}
		return sent;
	}
	override void closeImpl(){
		tcpSocket.shutdown(SocketShutdown.BOTH);
		tcpSocket.close();
	}
}

import zerotier;
import std.string: toStringz;
class ZerotierTCPConnection: ConnectionImpl{
	int fd;
	this(int fd)in{
		//assert(!zts_get_blocking(fd));
	}do{
		this.fd=fd;
	}
	override bool checkAlive(){ return fd!=-1/+&&zts_socket_alive(fd)+/;  }
	override protected long tryReceive(scope ubyte[] data){
		auto ret=zts_bsd_read(fd,data.ptr,data.length);
		if(ret<0){
			if(zts_would_have_blocked(fd)) return 0;
			stderr.writeln("zerotier socket error on read");
			alive_=false;
			zts_bsd_close(fd);
			fd=-1;
			return 0;
		}
		return ret;
	}
	override protected long trySend(scope ubyte[] data){
		auto sent=zts_bsd_write(fd,data.ptr,data.length);
		if(sent<0){
			if(zts_would_have_blocked(fd)) return 0;
			stderr.writeln("zerotier socket error on write");
			alive_=false;
			zts_bsd_close(fd);
			fd=-1;
			return 0;
		}
		return sent;
	}
	override void closeImpl(){
		if(fd==-1) return;
		zts_bsd_shutdown(fd,zts_shut_rdwr);
		zts_bsd_close(fd);
		fd=-1;
	}
	~this(){ closeImpl(); }
}

struct Joiner{
	int fd=-1;
	Connection tryJoinZerotier(string hostIP, ushort port){
		if(fd==-1){
			int nfd=zts_bsd_socket(zts_af_inet, zts_sock_stream, zts_ipproto_tcp);
			enforce(nfd!=zts_err_arg,"bad arguments");
			enforce(nfd!=zts_err_service,"failed to make socket");
			enforce(nfd!=zts_err_socket,"failed to make socket");
			fd=nfd;
		}
		zts_sockaddr_in saddr;
		uint addrlen=saddr.sizeof;
		int err=zts_util_ipstr_to_saddr(hostIP.toStringz,port,&saddr,&addrlen);
		enforce(err==zts_err_ok,"bad address");
		err=zts_bsd_connect(fd,&saddr,addrlen);
		if(err!=zts_err_ok) return null;
		err=zts_set_blocking(fd, false);
		enforce(err==zts_err_ok,"failed to set blocking mode");
		auto connection=new ZerotierTCPConnection(fd);
		fd=-1;
		return connection;
	}
	Socket joinSocket=null;
	Connection tryJoin(string hostIP, ushort port,bool useZerotier){
		if(useZerotier) return tryJoinZerotier(hostIP, port);
		auto hostAddress = new InternetAddress(hostIP, port);
		if(!joinSocket) joinSocket=new Socket(AddressFamily.INET,SocketType.STREAM);
		try joinSocket.connect(hostAddress);
		catch(Exception){ return null; }
		joinSocket.blocking=false;
		auto connection=new TCPConnection(joinSocket);
		joinSocket=null;
		return connection;
	}
}

struct Listener{
	int fd=-1;
	void makeZerotier(){
		enforce(fd==-1,"zerotier listener already exists");
		int nfd=zts_bsd_socket(zts_af_inet, zts_sock_stream, zts_ipproto_tcp);
		enforce(nfd!=zts_err_arg,"bad arguments");
		enforce(nfd!=zts_err_service,"failed to make socket");
		enforce(nfd!=zts_err_socket,"failed to make socket");
		zts_sockaddr_in saddr;
		uint addrlen=saddr.sizeof;
		int err=zts_util_ipstr_to_saddr("0.0.0.0",listeningPort,&saddr,&addrlen);
		enforce(err==zts_err_ok,"bad address");
		err=zts_bsd_bind(nfd,&saddr,addrlen);
		enforce(err==zts_err_ok,"failed to bind");
		zts_bsd_listen(nfd,playerLimit);
		enforce(err==zts_err_ok,"listen failed");
		err=zts_set_blocking(nfd, false);
		enforce(err==zts_err_ok,"failed to set blocking mode");
		fd=nfd;
	}
	Socket listener;
	void make(bool useZerotier){
		if(useZerotier) makeZerotier();
		enforce(!listener, "listener already exists");
		listener=new Socket(AddressFamily.INET,SocketType.STREAM);
		listener.setOption(SocketOptionLevel.SOCKET,SocketOption.REUSEADDR,true);
		try{
			listener.bind(new InternetAddress(listeningPort));
			listener.listen(playerLimit);
			listener.blocking=false;
		}catch(Exception){
			listener=null;
		}
		enforce(listener!is null,text("cannot host on port ",listeningPort));
	}
	Connection acceptZerotier(){
		zts_sockaddr_in saddr;
		uint addrlen=saddr.sizeof;
		auto nfd=zts_bsd_accept(fd,&saddr,&addrlen);
		if(nfd<0) return null;
		int err=zts_set_blocking(nfd, false);
		enforce(err==zts_err_ok,"failed to set blocking mode");
		return new ZerotierTCPConnection(nfd);
	}
	Connection accept(){
		if(fd!=-1){
			if(auto connection=acceptZerotier())
				return connection;
			if(!listener) return null;
		}
		enforce(listener!is null,"cannot accept connections");
		Socket socket=null;
		try socket=listener.accept();
		catch(Exception){}
		if(!socket||!socket.isAlive) return null;
		socket.blocking=false;
		return new TCPConnection(socket);
	}
	void close(){
		if(fd!=-1){
			zts_bsd_close(fd);
			fd=-1;
		}
		if(listener){
			listener.close();
			listener=null;
		}
	}
	bool accepting(){
		return fd!=-1||listener;
	}
}

enum PlayerStatus{
	unconnected,
	dropped,
	connected,
	synched,
	commitHashReady,
	mapHashed,
	pendingGameInit,
	readyToLoad,
	lateJoining,
	pendingLoad,
	loading,
	readyToStart,
	pendingStart,
	playing,
	playingBadSynch,
	pausedOnDrop,
	paused,
	desynched,
	readyToResynch,
	stateResynched,
	commitResynched,
	resynched,
	disconnected,
}

bool isConnectedStatus(PlayerStatus status){
	return !status.among(PlayerStatus.unconnected,PlayerStatus.dropped,PlayerStatus.disconnected);
}
bool isPausedStatus(PlayerStatus status){
	return !!status.among(PlayerStatus.pausedOnDrop,PlayerStatus.paused);
}
bool isDesynchedStatus(PlayerStatus status){
	return PlayerStatus.desynched<=status && status<PlayerStatus.resynched;
}
bool isReadyToLoadStatus(PlayerStatus status){
	return !!status.among(PlayerStatus.readyToLoad,PlayerStatus.resynched);
}
bool isReadyStatus(PlayerStatus status){
	return isConnectedStatus(status) && !isDesynchedStatus(status) && PlayerStatus.readyToStart<=status;
}
bool isActiveStatus(PlayerStatus status){
	return isConnectedStatus(status) && !isDesynchedStatus(status) && PlayerStatus.pendingStart<=status;
}

struct Player{
	PlayerStatus status;
	Settings settings;
	int slot=-1;

	Connection connection;
	bool alive(){ return connection&&connection.alive; }
	void send(Packet p){
		if(alive)
			connection.send(p);
	}
	void send(Packet p,scope ubyte[] rawData){
		if(alive)
			connection.send(p,rawData);
	}
	void send(Packet p,scope ubyte[] rawData1,scope ubyte[] rawData2){
		if(alive)
			connection.send(p,rawData1,rawData2);
	}
	bool ready(){ return connection&&connection.ready; }
	Packet receive()in{
		assert(ready);
	}do{
		return connection.receive;
	}
	bool rawReady(){ return connection&&connection.rawReady; }
	void receiveRaw(scope void delegate(scope ubyte[]) dg)in{
		assert(rawReady);
	}do{
		return connection.receiveRaw(dg);
	}

	bool lost=false,won=false;
	int committedFrame=0;
	long pingTicks=-1; // TODO: switch to MonoTime
	long packetTicks=-1; // TODO: switch to MonoTime
	long ping=-1; // TODO: switch to Duration
	Duration pingDuration(){ return ping.msecs; } // TODO: remove

	void drop()in{
		assert(!connection);
	}do{
		committedFrame=0;
		ping=-1;
	}
	bool wantsToControlState(){
		if(settings.observer) return false;
		return true;
	}
	bool allowedToControlState(){
		if(!wantsToControlState) return false;
		if(slot==-1) return false;
		if(lost) return false;
		return true;
	}
	bool requiredToControlState(){
		return allowedToControlState()&&!won;
	}
	bool isReadyToControlState(){
		if(!wantsToControlState) return false;
		return isReadyToLoadStatus(status)||isReadyStatus(status);
	}
	bool isControllingState(){
		if(!allowedToControlState) return false;
		return isActiveStatus(status);
	}
	bool allowedToControlSide(B)(int side,Controller!B controller){
		if(!allowedToControlState()) return false;
		if(!controller) return false;
		auto slot=settings.slot;
		if(slot<0||slot>=controller.state.slots.length) return false;
		auto controlledSide=controller.state.slots[slot].controlledSide;
		return controlledSide==side;
	}
}

enum playerLimit=256;
enum listeningPort=9116;

final class SynchQueue{
	enum maxLength=1024;
	uint[maxLength] hashes;
	int start=0,end=0;
	void capReferences(int frame)in{
		assert(frame<=end);
	}do{
		end=frame;
		start=min(start,end);
	}
	void continueAt(int frame)in{
		assert(start==end);
	}do{
		start=end=frame;
	}
	void addReference(int frame,uint hash)in{
		assert(frame==end,text(frame," ",end));
	}do{
		while(end+1-start>cast(int)hashes.length)
			start++;
		hashes[(end++)%$]=hash;
	}
	bool check(int frame,uint hash){
		if(frame<start) return false; // too old. TODO: count this as a desynch?
		if(frame>=end) return false; // impossibly recent
		return hashes[frame%$]==hash;
	}
}

final class Network(B){
	Player[] players;
	auto connectedPlayerIds(){ return iota(players.length).filter!(i=>isConnectedStatus(players[i].status)); }
	auto connectedPlayers(){
		ref Player index(size_t i){ return players[i]; }
		return connectedPlayerIds.map!index;
	}
	auto readyPlayerIds(){ return iota(players.length).filter!(i=>players[i].isReadyToControlState); }
	auto readyPlayers(){
		ref Player index(size_t i){ return players[i]; }
		return connectedPlayerIds.map!index;
	}
	size_t numReadyPlayers(){ return readyPlayerIds.walkLength; }
	auto potentialPlayerIds(){ return iota(players.length).filter!(i=>players[i].allowedToControlState); }
	auto potentialPlayers(){
		ref Player index(size_t i){ return players[i]; }
		return potentialPlayerIds.map!index;
	}
	auto requiredPlayerIds(){ return iota(players.length).filter!(i=>players[i].requiredToControlState); }
	auto requiredPlayers(){
		ref Player index(size_t i){ return players[i]; }
		return requiredPlayerIds.map!index;
	}
	auto activePlayerIds(){ return connectedPlayerIds.filter!(i=>players[i].isControllingState); }
	auto activePlayers(){
		ref Player index(size_t i){ return players[i]; }
		return activePlayerIds.map!index;
	}
	size_t numActivePlayers(){ return activePlayerIds.walkLength; }
	Listener listener;
	NetworkState!B networkState;
	void sidechannelChatMessage(R,S)(ChatMessageType type,R name,S message,Controller!B controller)in{
		assert(!!controller);
	}do{
		auto controlledSlot=-1,slotFilter=-1;
		auto chatMessage=makeChatMessage!B(controlledSlot,slotFilter,type,name,message,controller.currentFrame);
		if(isHost) addCommand(-1,Command!B(-1,chatMessage));
		if(networkState) networkState.chatMessages.addChatMessage(move(chatMessage));
	}
	this(){
		// makeListener
		networkState=new NetworkState!B();
	}
	enum host=0;
	bool dumpTraffic=false;
	bool dumpNetworkStatus=false;
	bool dumpNetworkSettings=false;
	bool checkDesynch=true;
	bool stutterOnDesynch=false;
	bool nudgeTimers=true;
	bool dropOnTimeout=true;
	bool pauseOnDrop=false;
	bool pauseOnDropOnce=false;
	this(ref Options options){
		this.dumpTraffic=options.dumpTraffic;
		this.dumpNetworkStatus=options.dumpNetworkStatus;
		this.dumpNetworkSettings=options.dumpNetworkSettings;
		this.checkDesynch=options.checkDesynch;
		this.stutterOnDesynch=options.stutterOnDesynch;
		this.logDesynch_=options.logDesynch;
		this.nudgeTimers=options.nudgeTimers;
		this.dropOnTimeout=options.dropOnTimeout;
		this.pauseOnDrop=options.pauseOnDrop;
		this();
	}

	bool isHost(){ return me==host; }
	SynchQueue synchQueue;
	void hostGame(Settings settings,bool useZerotier=false)in{
		assert(!players.length);
	}do{
		listener.make(useZerotier);
		static assert(host==0);
		players=[Player(PlayerStatus.synched,settings,settings.slot,null)];
		me=0;
		if(checkDesynch) synchQueue=new SynchQueue();
	}
	Joiner joiner;
	bool joinGame(string hostIP, ushort port, Settings playerSettings,bool useZerotier=false)in{
		assert(!players.length);
	}do{
		auto connection=joiner.tryJoin(hostIP, port, useZerotier);
		if(!connection) return false;
		players=[Player(PlayerStatus.connected,Settings.init,-1,connection)];
		import serialize_;
		playerSettings.serialized((scope ubyte[] settingsData){
			players[host].connection.send(Packet.join(settingsData.length),settingsData);
		});
		return true;
	}
	bool synched(){ return me!=-1&&players[me].status>=PlayerStatus.synched; }
	bool hostCommitHashReady(){ return players[host].status>=PlayerStatus.commitHashReady; }
	bool mapHashed(){ return connectedPlayers.all!(p=>p.status>=PlayerStatus.mapHashed); }
	bool pendingGameInit(){ return connectedPlayers.any!(p=>p.status==PlayerStatus.pendingGameInit); }
	bool hostReadyToLoad(){ return isReadyToLoadStatus(players[host].status)||isReadyStatus(players[host].status); }
	bool clientsReadyToLoad(){
		return iota(players.length).filter!(i=>i!=host&&players[i].connection).all!(i=>isReadyToLoadStatus(players[i].status)||isReadyStatus(players[i].status));
	}
	bool readyToLoad(){ return connectedPlayers.all!(p=>isReadyToLoadStatus(p.status)||isReadyStatus(p.status)); }
	bool lateJoining(){ return me!=-1&&players[me].status==PlayerStatus.lateJoining; }
	bool loading(){ return me!=-1&&players[me].status==PlayerStatus.loading; }
	bool hostReadyToStart(){ return isReadyStatus(players[host].status); }
	bool clientsReadyToStart(){
		return iota(players.length).filter!(i=>i!=host&&players[i].connection).all!(i=>isReadyStatus(players[i].status));
	}
	bool readyToStart(){ return connectedPlayers.all!(p=>isReadyStatus(p.status)); }
	bool playing(){ return me!=-1&&players[me].status.among(PlayerStatus.playing,PlayerStatus.playingBadSynch) && !paused; }
	bool paused(){ return isPausedStatus(players[host].status); }
	bool anyoneDropped(){ return requiredPlayers.any!(p=>p.status==PlayerStatus.dropped); }
	bool hostDropped(){ return players[host].status==PlayerStatus.dropped; }
	bool anyonePending(){ return potentialPlayers.any!(p=>!isActiveStatus(p.status)); }
	bool desynched(){ return connectedPlayers.any!(p=>isDesynchedStatus(p.status)||p.status==PlayerStatus.resynched); }
	bool pendingResynch(){
		if(isHost){
			if(players[me].status.among(PlayerStatus.readyToResynch,PlayerStatus.stateResynched,PlayerStatus.resynched)) // resynch already initiatedendingresynch
				return false;
			return players.any!((ref p)=>isDesynchedStatus(p.status));
		}
		if(players[me].status==PlayerStatus.stateResynched) return false;
		return players[host].status==PlayerStatus.readyToResynch;
	}
	bool readyToResynch(){
		if(connectedPlayers.count!((ref p)=>p.status==PlayerStatus.readyToResynch)<=1) return false;
		if(players[host].status!=PlayerStatus.readyToResynch) return false;
		return connectedPlayers.all!((ref p)=>p.status.among(PlayerStatus.readyToResynch,PlayerStatus.stateResynched));
	}
	bool stateResynched(){ return connectedPlayers.all!(p=>p.status.among(PlayerStatus.stateResynched,PlayerStatus.resynched)); }
	//int resynchCommittedFrame(){ return connectedPlayers.map!((ref p)=>p.committedFrame).fold!max(players[host].committedFrame); }
	//int resynchCommittedFrame(){ return players[host].committedFrame; }
	int resynchCommittedFrame(){ return committedFrame; }
	bool resynched(){ return connectedPlayers.all!((ref p)=>p.status==PlayerStatus.resynched)/+ && connectedPlayers.all!((ref p)=>p.committedFrame==players[host].committedFrame)+/; }
	int committedFrame(){ return activePlayers.map!((ref p)=>p.committedFrame).fold!min(players[isConnectedStatus(players[host].status)?host:me].committedFrame); }
	int me=-1;
	@property ref settings(){ return players[me].settings; }
	@property int slot(){ return players[me].slot; }
	@property ref hostSettings(){ return players[host].settings; }
	@property hostStatus(){ return players[host].status; }
	void broadcast(Packet p,scope ubyte[] rawData)in{
		assert(purposeFromType(p.type)==PacketPurpose.broadcast);
		if(isHeaderType(p.type)) assert(p.rawDataSize==rawData.length);
		else assert(rawData.length==0);
	}do{
		if(isHost){
			foreach(i;0..players.length)
				players[i].send(p,rawData);
		}else players[host].send(p,rawData);
	}
	bool allowedToUpdateStatus(int actor,int player,PlayerStatus newStatus){
		if(!actor.among(host,player)) return false;
		auto oldStatus=players[player].status;
		if(isPausedStatus(oldStatus)&&newStatus==PlayerStatus.readyToResynch||isPausedStatus(newStatus)) return actor==host;
		return oldStatus<newStatus||
			oldStatus==PlayerStatus.playingBadSynch&&newStatus==PlayerStatus.playing||
			oldStatus==PlayerStatus.resynched&&newStatus==PlayerStatus.loading||
			actor==host&&newStatus.among(PlayerStatus.readyToLoad,PlayerStatus.unconnected,PlayerStatus.dropped);
	}
	void requestStatusUpdate(int player,PlayerStatus newStatus)in{
		assert(isHost&&player!=me);
	}do{
		players[player].send(Packet.requestStatusUpdate(newStatus));
	}
	void requestStatusUpdateAll(PlayerStatus newStatus)in{
		assert(isHost);
	}do{
		foreach(i,ref player;players){
			if(i!=me) player.send(Packet.requestStatusUpdate(newStatus));
		}
		updateStatus(newStatus);
	}
	void updateStatus(int player,PlayerStatus newStatus)in{
		assert(player==me||isHost);
	}do{
		if(players[player].status==newStatus) return;
		if(!allowedToUpdateStatus(me,player,newStatus)) return;
		broadcast(Packet.updateStatus(player,newStatus),[]);
		players[player].status=newStatus;
	}
	void updateStatus(PlayerStatus newStatus)in{
		assert(me!=-1);
	}do{
		updateStatus(me,newStatus);
	}
	void updateSetting(string setting,T)(int player,T value){
		if(mixin(`players[player].settings.`~setting)==value) return;
		static if(setting=="map"){ // TODO: generalize
			enum blockSize=Packet.mapName.length;
			foreach(i;0..(value.length+blockSize-1)/blockSize){
				auto part=value[i*blockSize..min($,(i+1)*blockSize)];
				if(i==0) broadcast(Packet.setMap(player,part),[]);
				else broadcast(Packet.appendMap(player,part),[]);
			}
			broadcast(Packet.confirmMap(player),[]);
		}else static if(is(typeof(mixin(`players[player].settings.`~setting))==S[],S)){ // TODO: generalize
			broadcast(Packet.clearArraySetting!setting(player),[]);
			foreach(entry;value) broadcast(Packet.appendArraySetting!setting(player,entry),[]);
			broadcast(Packet.confirmArraySetting!setting(player),[]);
		}else broadcast(Packet.updateSetting!setting(player,value),[]);
		mixin(`players[player].settings.`~setting)=value;
	}
	void updateSetting(string setting,T)(T value){
		updateSetting!setting(me,value);
	}
	void synchronizeSetting(string setting)()in{
		assert(isHost);
	}do{
		foreach(player;0..cast(int)players.length)
			updateSetting!setting(player,mixin(`hostSettings.`~setting));
	}
	void updateSettings(int player,Settings newSettings)in{
		assert(0<=player&&player<players.length);
		assert((player==me||isHost)&&players[player].status>=PlayerStatus.synched);
	}do{
		static foreach(setting;__traits(allMembers,Settings))
			updateSetting!setting(player,mixin(`newSettings.`~setting));
	}
	void updateSettings(Settings newSettings)in{
		assert(me!=-1&&players[me].status>=PlayerStatus.synched);
	}do{
		updateSettings(me,newSettings);
	}
	void addCommand(int frame,Command!B command)in{
		assert(playing&&players[me].committedFrame<=frame||command.type==CommandType.surrender||command.type==CommandType.chatMessage);
	}do{
		if(!isCommandWithRaw(command.type))
			broadcast(Packet.command(frame,command),[]);
		else{
			command.withRawCommandData((scope ubyte[] rawData){
				broadcast(Packet.commandRaw(frame,command,rawData.length),rawData);
			});
		}
	}
	void resetCommitted(int i,int frame)in{
		// (only meant to be used if player i is not playing)
		assert(isHost);
		assert(i==-1||i<players.length);
	}do{
		foreach(k,ref player;players){
			if(i!=me) player.send(Packet.resetCommitted(i,frame));
			if(i==k||i==-1) player.committedFrame=frame;
		}
	}
	void resetCommitted(int frame)in{
		assert(isHost&&!playing);
	}do{
		resetCommitted(-1,frame);
	}
	void commit(int i,int frame)in{
		assert(isHost||i==me&&players[me].status.among(PlayerStatus.playing,PlayerStatus.playingBadSynch,PlayerStatus.stateResynched));
	}do{
		broadcast(Packet.commit(i,frame),[]);
		players[i].committedFrame=max(players[i].committedFrame,frame);
	}
	bool canCommit(int frame){
		return players[me].committedFrame<frame &&
			players[me].status.among(PlayerStatus.playing,PlayerStatus.playingBadSynch,PlayerStatus.stateResynched);
	}
	void commit(int frame)in{
		assert(canCommit(frame),text(playing," ",players[me].committedFrame," ",frame));
	}do{
		commit(me,frame);
	}
	void tryCommit(int frame){
		if(canCommit(frame))
			commit(frame);
	}
	enum AckHandler{
		none,
		measurePing,
	}
	AckHandler ackHandler=AckHandler.measurePing;
	void report(bool error=false,T...)(int player,T action){
		static if(error){
			if(players[player].settings.name=="") stderr.writeln("player ",player," ",action);
			else stderr.writeln(players[player].settings.name," (player ",player,") ",action);
		}else{
			if(players[player].settings.name=="") writeln("player ",player," ",action);
			else writeln(players[player].settings.name," (player ",player,") ",action);
		}
	}
	bool performPacketAction(int sender,ref Packet p,scope ubyte[] rawData,Controller!B controller)in{
		if(isHeaderType(p.type)) assert(p.rawDataSize==rawData.length);
		else assert(rawData.length==0);
	}do{
		if(dumpTraffic) writeln("from ",sender,": ",p);
		final switch(p.type){
			// peer to peer:
			case PacketType.nop: return true;
			case PacketType.disconnect:
				/+disconnectPlayer(sender,controller);
				report(sender,"disconnected");+/
				dropPlayer(sender,controller);
				return true;
			case PacketType.ping: players[sender].send(Packet.ack(p.pingId)); return true;
			case PacketType.ack:
				final switch(ackHandler) with(AckHandler){
					case none: return true;
					case measurePing:
						players[sender].ping=B.ticks()-p.pingId; // TODO: use a median over some window
						return true;
				}
			// host message:
			case PacketType.updatePlayerId:
				if(sender!=host){
					stderr.writeln("non-host player ",sender," attempted to update id: ",p);
					return false;
				}
				if(me!=-1){
					stderr.writeln("host attempted to identify already identified player ",me,": ",p);
					return false;
				}
				if(p.id<0||p.id>=players.length){
					stderr.writeln("attempt to identify to invalid id ",p.id);
					return false;
				}
				me=p.id;
				updateStatus(PlayerStatus.synched);
				return true;
			case PacketType.updateSlot:
				if(sender!=host){
					stderr.writeln("non-host player ",sender," attempted to update slot: ",p);
					return false;
				}
				int slot=p.intValue;
				if(slot!=-1 && players[p.player].slot!=slot && players.any!((ref p)=>p.slot==slot)){
					stderr.writeln("host attempted to put multiple players on same slot: ",p);
					return false;
				}
				players[p.player].settings.slot=slot;
				players[p.player].slot=slot;
				return true;
			case PacketType.sendMap:
				if(sender!=host){
					stderr.writeln("non-host player ",sender," attempted to update map: ",p);
					return false;
				}
				mapData.length=p.rawDataSize;
				mapData.data[]=rawData[];
				return true;
			case PacketType.sendState:
				if(sender!=host){
					stderr.writeln("non-host player ",sender," attempted to update state: ",p);
					return false;
				}
				controller.replaceState(rawData);
				return true;
			case PacketType.initGame:
				if(sender!=host){
					stderr.writeln("non-host player ",sender," attempted to initialize the game: ",p);
					return false;
				}
				gameInitData.length=p.rawDataSize;
				gameInitData.data[]=rawData[];
				return true;
			case PacketType.loadGame:
				if(sender!=host){
					stderr.writeln("non-host player ",sender," attempted to initiate loading: ",p);
					return false;
				}
				if(!(isReadyToLoadStatus(players[me].status)||isReadyStatus(players[me].status))){
					stderr.writeln("attempt to load game before ready: ",p);
					return false;
				}
				updateStatus(PlayerStatus.loading);
				return true;
			case PacketType.startGame:
				if(sender!=host){
					stderr.writeln("non-host player ",sender," attempted to start game: ",p);
					return false;
				}
				if(!readyToStart){
					stderr.writeln("attempt to start game before ready: ",p);
					return false;
				}
				Thread.sleep(p.startDelay.msecs);
				updateStatus(PlayerStatus.playing);
				B.unpause();
				return true;
			case PacketType.setFrame:
				if(sender!=host){
					stderr.writeln("non-host player ",sender," attempted to set frame: ",p);
					return false;
				}
				if(controller) controller.setFrame(p.newFrame);
				return true;
			case PacketType.nudgeTimer:
				if(sender!=host){
					stderr.writeln("non-host player ",sender," attempted to nudge timer: ",p);
					return false;
				}
				if(controller) controller.timer.adjust(p.timerAdjustHnsecs.hnsecs);
				return true;
			case PacketType.resetCommitted:
				if(sender!=host){
					stderr.writeln("non-host player ",sender," attempted to reset committed frame: ",p);
					return false;
				}
				if(p.commitPlayer==-1){
					foreach(ref player;players)
						player.committedFrame=min(player.committedFrame,p.commitFrame);
				}else players[p.commitPlayer].committedFrame=p.commitFrame;
				return true;
			case PacketType.requestStatusUpdate:
				if(sender!=host){
					stderr.writeln("non-host player ",sender," requested status update: ",p);
					return false;
				}
				if(isDesynchedStatus(players[me].status)&&!isDesynchedStatus(p.requestedStatus)){
					stderr.writeln("warning: ignoring request to leave desynched status: ",p);
					return false;
				}
				updateStatus(p.requestedStatus);
				return true;
			case PacketType.confirmSynch:
				if(!checkDesynch) return true;
				if(desynched){
					stderr.writeln("confirmSynch packet sent while desynched: ",p);
					return false;
				}
				if(isHost){
					stderr.writeln("confirmSynch packet sent to host ",me,": ",p);
					return false;
				}
				//if(controller) controller.confirmSynch(p.synchFrame,p.synchHash);
				return true;
			// host query:
			case PacketType.join:
				stderr.writeln("stray join packet: ",p);
				controller.logDesynch(players[sender].settings.slot,rawData);
				return false;
			case PacketType.checkSynch:
				if(!checkDesynch) return true;
				if(desynched||players[sender].status==PlayerStatus.playingBadSynch){
					stderr.writeln("checkSynch packet sent while desynched: ",p);
					return false;
				}
				if(!isHost){
					stderr.writeln("checkSynch packet sent to non-host player ",me,": ",p);
					return false;
				}
				assert(!!synchQueue);
				if(controller) controller.updateCommittedTo(p.synchFrame);
				if(!synchQueue.check(p.synchFrame,p.synchHash)){
					report!true(sender,"desynchronized at frame ",p.synchFrame);
					if(p.synchFrame>=synchQueue.end){
						stderr.writeln("tried to synch on non-committed frame (after ",synchQueue.end,") ",players.map!((ref p)=>p.committedFrame)," ",players.map!((ref p)=>p.status));
					}else{
						stderr.writeln("expected hash ",synchQueue.hashes[p.frame%$],", got ",p.synchHash);
					}
					if(!stutterOnDesynch&&players[sender].status==PlayerStatus.playing){
						updateStatus(sender,PlayerStatus.playingBadSynch);
						with(controller.state){
							import serialize_;
							committed.serialized((scope ubyte[] stateData){
								commands.serialized((scope ubyte[] commandData){
									sendState(sender,stateData,commandData);
								});
							});
						}
						requestStatusUpdate(sender,PlayerStatus.playing); // TODO: this is a bit dangerous
					}else updateStatus(sender,PlayerStatus.desynched);
				}//else confirmSynch(sender,p.synchFrame,p.synchHash);
				return true;
			case PacketType.logDesynch:
				if(!isHost){
					stderr.writeln("logDesynch packet sent to non-host player ",me,": ",p);
					return false;
				}
				controller.logDesynch(players[sender].settings.slot,rawData);
				return true;
			// broadcast:
			case PacketType.updateSetting,PacketType.clearArraySetting,PacketType.appendArraySetting,PacketType.confirmArraySetting,PacketType.setMap,PacketType.appendMap,PacketType.confirmMap:
				if(!sender.among(host,p.player)){
					stderr.writeln("non-host player ",sender," attempted to update another player's settings: ",p);
					return false;
				}
				static assert(p.player.offsetof is p.mapPlayer.offsetof);
				if(p.player<0||p.player>=playerLimit){
					stderr.writeln("player id out of range: ",p);
					return false;
				}
				if(p.player>=players.length) players.length=p.player+1;
				if(players[p.player].status>=PlayerStatus.loading){
					stderr.writeln("attempt to change settings after game started loading: ",p);
					return false;
				}
				if(players[p.player].status>=PlayerStatus.readyToLoad){
					stderr.writeln("attempt to change settings after marked ready to load:  ",p);
					return false;
				}
				if(p.type==PacketType.updateSetting){
					auto len=0;
					while(len<p.optionName.length&&p.optionName[len]!='\0') ++len;
					switch(p.optionName[0..len]){
						static foreach(setting;__traits(allMembers,Settings)){{
							alias T=typeof(mixin(`players[p.player].settings.`~setting));
							static if(!is(T==S[],S)){
								case setting:
									mixin(`players[p.player].settings.`~setting)=p.getValue!T();
									return true;
							}
						}}
						default: stderr.writeln("warning: unknown setting '",p.optionName[0..len],"'"); return false;
					}
				}else if(p.type==PacketType.clearArraySetting||p.type==PacketType.appendArraySetting){
					auto len=0;
					while(len<p.optionName.length&&p.optionName[len]!='\0') ++len;
					switch(p.optionName[0..len]){
						static foreach(setting;__traits(allMembers,Settings)){{
							alias T=typeof(mixin(`players[p.player].settings.`~setting));
							static if(is(T==S[],S)){
								case setting:
									if(p.type==PacketType.clearArraySetting) mixin(`players[p.player].settings.`~setting)=[];
									else if(p.type==PacketType.appendArraySetting){
										if(mixin(`players[p.player].settings.`~setting).length<arrayLengthLimit)
											mixin(`players[p.player].settings.`~setting)~=p.getValue!S();
									}
									return true;
							}
						}}
						default: stderr.writeln("warning: unknown array setting '",p.optionName[0..len],"'"); return false;
					}
				}else if(p.type==PacketType.confirmArraySetting){
					auto len=0;
					while(len<p.optionName.length&&p.optionName[len]!='\0') ++len;
					if(p.optionName[0..len]=="name" && players[p.player].settings.name!="") writeln("player ",p.player," is ",players[p.player].settings.name);
					if(p.optionName[0..len]=="commit" && players[p.player].settings.commit!="") report(p.player,"is at commit ",players[p.player].settings.commit);
				}else if(p.type==PacketType.setMap){
					auto len=0;
					while(len<p.mapName.length&&p.mapName[len]!='\0') ++len;
					players[p.mapPlayer].settings.map=p.mapName[0..len].idup;
				}else if(p.type==PacketType.appendMap){
					auto len=0;
					while(len<p.mapName.length&&p.mapName[len]!='\0') ++len;
					if(players[p.mapPlayer].settings.map.length<arrayLengthLimit)
						players[p.mapPlayer].settings.map~=p.mapName[0..len];
				}else if(p.type==PacketType.confirmMap){
				}else assert(0);
				return true;
			case PacketType.updateStatus:
				if(p.player<0||p.player>=playerLimit){
					stderr.writeln("player id out of range: ",p);
					return false;
				}
				if(p.player>=players.length) players.length=p.player+1;
				if(isHost&&p.newStatus==PlayerStatus.readyToLoad&&players[p.player].settings.commit!=hostSettings.commit){
					report!true(p.player,"tried to join with incompatible version #\n",
					            "they were using version ",players[p.player].settings.commit);
					disconnectPlayer(p.player,controller);
					return false;
				}
				if(allowedToUpdateStatus(sender,p.player,p.newStatus)){
					players[p.player].status=p.newStatus;
					if(p.newStatus==PlayerStatus.dropped||p.newStatus==PlayerStatus.unconnected){
						if(players[p.player].settings.commit!=hostSettings.commit){
							report!true(p.player,"tried to join with incompatible version #");
							stderr.writeln("they were using version ",players[p.player].settings.commit);
						}else report(p.player,"dropped");
						players[p.player].drop();
					}
				}
				return true;
			static foreach(cmd;[PacketType.command,PacketType.commandRaw]){
				case cmd:
					if(controller){
						try{
							static if(cmd==PacketType.command) auto command=fromNetwork!B(p.networkCommand);
							else auto command=fromNetworkRaw!B(p.networkCommand,rawData);
							if(controller.state&&controller.state.committedFrame<=p.frame&&command.id!=0){
								if(!isHost||(players[sender].allowedToControlSide(command.side,controller)&&players[sender].isControllingState)){
									controller.addExternalCommand(p.frame,move(command));
									return true;
								}
								report(sender,"sent an unauthorized command");
								return false;
							}
							if(isHost&&p.frame==-1&&command.type==CommandType.chatMessage&&command.id==0){
								if(players[sender].isControllingState){
									report!true(sender,"tried to send an observer chat message while not being an observer");
									return false;
								}
								if(command.chatMessage.senderSlot!=players[sender].slot){
									report!true(sender,"tried to impersonate another player (slot ",command.chatMessage.senderSlot,")");
									disconnectPlayer(sender,controller);
									return false;
								}
								if(!players[sender].settings.observerChat){
									report!true(sender,"tried to send an observer chat message while muted");
									return false;
								}
								adjustChatMessage(command.chatMessage,controller.currentFrame);
								with(command.chatMessage){
									slotFilter=-1;
									content.type=ChatMessageType.observer;
								}
								if(controller&&playing){
									controller.addCommand(command);
									return false;
								}
							}
							if(command.type==CommandType.chatMessage&&command.id==0&&networkState){
								// TODO: properly authorize observer chat
								networkState.chatMessages.addChatMessage(command.chatMessage);
								if(isHost){
									command.withRawCommandData((scope ubyte[] rawData){
										forwardPacket(sender,Packet.commandRaw(controller.currentFrame,command,rawData.length),rawData,controller);
									});
									return false;
								}
								return true;
							}
							stderr.writeln("warning: invalid command ignored (frame: ",p.frame,", committed: ",controller.state.committedFrame,").");
							return false;
						}catch(Exception e){
							report!true(sender,"sent a command with wrong encoding: ",e.msg);
							disconnectPlayer(sender,controller);
							return false;
						}
					}
					return true;
			}
			case PacketType.commit:
				players[p.commitPlayer].committedFrame=max(players[p.commitPlayer].committedFrame,p.commitFrame);
				//if(controller) controller.updateCommitted();
				if(isHost&&nudgeTimers){
					ping(p.commitPlayer);
					auto frameTime=1.seconds/updateFPS;
					auto deltaFrames=players[p.commitPlayer].committedFrame-players[host].committedFrame;
					auto drift=deltaFrames*frameTime+players[p.commitPlayer].pingDuration/2;
					auto correction=-drift/60;
					nudgeTimer(p.commitPlayer,correction);
				}
				return true;
			case PacketType.jsonCommand:
				if(!isHost){
					stderr.writeln("jsonCommand packet sent to non-host player ",me,": ",p);
					return false;
				}
				try{
					auto str=cast(const(char)[])rawData;
					import std.utf:validate;
					validate(str);
					import jsonInterface:parseJSONCommand,runJSONCommand;
					runJSONCommand(parseJSONCommand(str),controller,(scope const(char)[] response){
						players[sender].send(Packet.jsonResponse(response.length),cast(ubyte[])response);
					});
					return true;
				}catch(Exception e){
					report!true(sender,"sent an invalid json command: ",e.msg);
					return false;
				}
			case PacketType.jsonResponse:
				report!true(sender,"sent an unsolicited json response");
				return false;
		}
	}
	void forwardPacket(int sender,Packet p,scope ubyte[] rawData,Controller!B controller){
		if(!isHost) return;
		// host forwards state updates to all clients
		// TODO: for commands, allow direct connections, to decrease latency
		final switch(purposeFromType(p.type)) with(PacketPurpose){
			case peerToPeer: break;
			case hostMessage: stderr.writeln("host message sent to host: ",p); break;
			case broadcast:
				foreach(other;0..players.length){
					if(other==sender) continue;
					players[other].send(p,rawData);
				}
				break;
			case hostQuery: break;
		}
	}
	void handlePacket(int sender,Packet p,scope ubyte[] rawData,Controller!B controller){
		bool ok=performPacketAction(sender,p,rawData,controller);
		if(ok) forwardPacket(sender,p,rawData,controller);
	}
	void sendPlayerData(Connection connection,int player)in{
		assert(isHost);
	}do{
		if(!connection) return;
		static foreach(setting;__traits(allMembers,Settings)){{
			static if(setting=="map"){ // TODO: generalize
				enum blockSize=Packet.mapName.length;
				auto value=players[player].settings.map;
				foreach(i;0..(value.length+blockSize-1)/blockSize){
					auto part=value[i*blockSize..min($,(i+1)*blockSize)];
					if(i==0) connection.send(Packet.setMap(player,part));
					else connection.send(Packet.appendMap(player,part));
				}
				connection.send(Packet.confirmMap(player));
			}else static if(is(typeof(mixin(`players[player].settings.`~setting))==S[],S)){
				connection.send(Packet.clearArraySetting!setting(player));
				foreach(entry;mixin(`players[player].settings.`~setting)) connection.send(Packet.appendArraySetting!setting(player,entry));
				connection.send(Packet.confirmArraySetting!setting(player));
			}else connection.send(Packet.updateSetting!setting(player,mixin(`players[player].settings.`~setting)));
		}}
		connection.send(Packet.updateSlot(player,players[player].slot));
		if(players[player].committedFrame!=0) connection.send(Packet.commit(player,players[player].committedFrame)); // for late joins
		connection.send(Packet.updateStatus(player,players[player].status));
		// TODO: send address to attempt to establish peer to peer connection
	}
	void updatePlayerId(int newId)in{
		assert(isHost);
		assert(players[newId].status==PlayerStatus.connected);
	}do{
		players[newId].send(Packet.updatePlayerId(newId));
	}
	void updateSlot(int i,int slot)in{
		assert(isHost);
	}do{
		if(players[i].slot==slot){
			updateSetting!"slot"(i,slot);
			return;
		}
		foreach(j;0..players.length)
			players[j].send(Packet.updateSlot(i,slot));
		players[i].settings.slot=slot;
		players[i].slot=slot;
	}
	private static bool canReplacePlayer(ref Player cand,ref Player old,bool replaceUnnamed){
		if(old.connection) return false;
		//if(old.status==PlayerStatus.unconnected) return true;
		if(old.settings.observer!=cand.settings.observer) return false;
		if(old.settings.name==cand.settings.name) return true;
		if(replaceUnnamed&&old.settings.name=="") return true;
		// TODO: more reliable authentication, e.g. with randomly-generated id or public key
		return false;
	}
	int addPlayer(Player player)in{
		assert(isHost);
	}do{
		auto validSpots=chain(iota(players.length).filter!(i=>i!=host&&canReplacePlayer(player,players[i],false)),
		                      iota(players.length+1).filter!(i=>i!=host&&(i==players.length||canReplacePlayer(player,players[i],true))));
		assert(!validSpots.empty);
		int newId=cast(int)validSpots.front;
		if(newId<players.length){
			enforce(players[newId].settings.name.among("",player.settings.name));
			players[newId].settings.name=player.settings.name;
			player.settings=players[newId].settings;
			player.slot=players[newId].slot;
			players[newId]=player;
		}else players~=player;
		foreach(other;iota(cast(int)players.length).filter!(i=>i!=newId))
			sendPlayerData(players[other].connection,newId);
		foreach(other;0..cast(int)players.length)
			sendPlayerData(players[newId].connection,other);
		players[newId].send(Packet.updatePlayerId(newId));
		return newId;
	}
	bool acceptingNewConnections=true;
	void stopListening(){
		acceptingNewConnections=false;
		listener.close();
	}
	Array!Player pendingJoin;
	void acceptNewConnections(){
		if(!acceptingNewConnections||!listener.accepting) return;
		if(isHost){
			if(players.length>=playerLimit) return;
			for(;;){
				// TODO: detect reconnection attempts
				auto connection=listener.accept();
				if(!connection) break;
				auto status=PlayerStatus.connected, settings=Settings.init, slot=-1;
				auto newPlayer=Player(status,settings,slot,connection);
				pendingJoin~=newPlayer;
			}
		}else{
			// TODO: accept peer-to-peer connections to decrease latency
		}
		for(int i=0;i<pendingJoin.length;){
			if(pendingJoin[i].ready){
				auto p=pendingJoin[i].receive();
				if(p.type==PacketType.join){
					assert(pendingJoin[i].rawReady);
					try{
						import serialize_;
						pendingJoin[i].receiveRaw((scope ubyte[] data){ deserialize(pendingJoin[i].settings,ObjectState!B.init,data); });
						auto newId=addPlayer(pendingJoin[i]);
						report(newId,"joined");
					}catch(Exception e){
						stderr.writeln("bad join attempt: ",e.msg);
						pendingJoin[i].connection.close();
					}
				}else{
					stderr.writeln("bad join attempt");
					pendingJoin[i].connection.close();
				}
				swap(pendingJoin[i],pendingJoin[$-1]);
				pendingJoin.length=pendingJoin.length-1;
			}else i++;
		}
	}
	void disconnectPlayer(int i,Controller!B controller){
		/+if(isHost||i==host){
			if(controller&&!players[i].settings.observer&&players[i].settings.controlledSide!=-1){// surrender
				auto controlledSide=controller.controlledSide;
				controller.controlledSide=players[i].settings.controlledSide;
				scope(exit) controller.controlledSide=controlledSide;
				controller.addCommand(max(controller.currentFrame,players[i].committedFrame),Command!B(players[i].settings.controlledSide));
			}
		}+/
		if(isHost) updateStatus(cast(int)i,PlayerStatus.disconnected);
		players[i].connection.close();
		players[i].connection=null;
	}
	void dropPlayer(int i,Controller!B controller){
		if(!isHost&&i!=host) return;
		if(players[i].settings.commit!=hostSettings.commit){
			report!true(cast(int)i,"tried to join with incompatible version #");
			stderr.writeln("they were using version ",players[i].settings.commit);
		}else report(cast(int)i,"dropped");
		if(controller){
			auto who=i==host?me:i;
			auto message=!players[who].allowedToControlState||players[who].won?"has left the game.":"has been dropped from the game.";
			sidechannelChatMessage(ChatMessageType.network,players[who].settings.name,message,controller);
		}
		if(!isHost){
			assert(i==host);
			players[i].status=PlayerStatus.dropped;
			foreach(ref player;players) if(!players[i].connection) player.status=PlayerStatus.dropped;
		}else updateStatus(cast(int)i,PlayerStatus.dropped);
		players[i].connection.close();
		players[i].connection=null;
		players[i].drop();
	}
	enum pingDelay=1000/60; // TODO: switch to Duration
	enum dropDelay=1000; // TODO: switch to Duration
	int lastUpdate=-1; // TODO: switch to MonoTime
	void ping(int i){
		auto ticks=B.ticks();
		auto sinceLastPing=ticks-players[i].pingTicks;
		if(sinceLastPing<pingDelay)
			return;
		players[i].send(Packet.ping(ticks));
		players[i].pingTicks=ticks;
	}
	void confirmConnectivity(int i){
		players[i].packetTicks=B.ticks();
	}
	void checkConnectivity(int i,Controller!B controller){
		if(!playing) ping(cast(int)i);
		// TODO: probably even if a player is not active there should be some timeout,
		// especially for players with status playingBadSynch
		if(!isActiveStatus(players[i].status)||players[i].status==PlayerStatus.playingBadSynch) return;
		if(!isActiveStatus(players[me].status)||players[me].status==PlayerStatus.playingBadSynch) return;
		auto sinceLastPacket=B.ticks()-players[i].packetTicks;
		if(dropOnTimeout&&players[i].packetTicks!=-1&&sinceLastPacket>=dropDelay){
			report!true(i,"timed out");
			dropPlayer(i,controller);
			return;
		}
	}
	void update(Controller!B controller){
		acceptNewConnections();
		dumpPlayerInfo();
		foreach(i,ref player;players){
			if(!player.connection) continue;
			if(!player.alive){
				dropPlayer(cast(int)i,controller);
				dumpPlayerInfo();
				continue;
			}
			while(player.ready){
				auto packet=player.receive;
				if(isHeaderType(packet.type)){
					assert(player.rawReady);
					player.receiveRaw((scope ubyte[] rawData){ handlePacket(cast(int)i,packet,rawData,controller); });
				}else handlePacket(cast(int)i,packet,[],controller);
				dumpPlayerInfo();
				confirmConnectivity(cast(int)i);
			}
			auto sinceLastUpdate=B.ticks()-lastUpdate;
			if(sinceLastUpdate<dropDelay/2) checkConnectivity(cast(int)i,controller);
		}
		lastUpdate=B.ticks();
	}
	void dumpPlayerInfo(){
		if(dumpNetworkStatus){
			static Array!PlayerStatus curStatus;
			auto newStatus=players.map!((ref p)=>p.status);
			if(!equal(newStatus,curStatus.data)){
				curStatus.length=players.length;
				copy(newStatus,curStatus.data[]);
				writeln("player status: ",curStatus);
			}
		}
		if(dumpNetworkSettings){
			static Array!Settings curSettings;
			auto newSettings=players.map!((ref p)=>p.settings);
			if(!equal(newSettings,curSettings.data)){
				curSettings.length=players.length;
				copy(newSettings,curSettings.data[]);
				writeln("player settings: ",curSettings);
			}
		}
	}
	bool idleLobby()in{
		assert(me==-1||players[me].status<=PlayerStatus.loading||players[me].status>max(PlayerStatus.playing,PlayerStatus.playingBadSynch),text(me," ",me!=-1?text(players[me].status):""));
	}do{
		if(me!=-1&&players[me].status==PlayerStatus.disconnected) return false;
		update(null);
		Thread.sleep(1.msecs);
		return true;
	}

	void initSlots(R)(R slotData)in{
		assert(isHost&&players.length==1);
	}do{
		assert(host==0);
		players.length=slotData.length+1;
		foreach(i,ref p;players[1..$]){
			p.status=PlayerStatus.dropped;
			p.settings.name=slotData[i].name;
			p.settings.slot=slotData[i].slot;
			p.slot=p.settings.slot;
		}
		players[0].slot=-1;
		Lreplace: foreach(replaceUnnamed;0..2){
			foreach(i,ref p;players[1..$]){
				if(canReplacePlayer(players[host],p,!!replaceUnnamed)){
					auto hostCommit=hostSettings.commit;
					auto hostMap=hostSettings.map;
					auto hostMapHash=hostSettings.mapHash;
					auto hostName=hostSettings.name;
					swap(hostSettings,p.settings);
					hostSettings.commit=hostCommit;
					hostSettings.map=hostMap;
					hostSettings.mapHash=hostMapHash;
					hostSettings.name=hostName;
					swap(players[host].slot,p.slot);
					swap(p,players[$-1]);
					players.length=players.length-1;
					players.assumeSafeAppend();
					break Lreplace;
				}
			}
		}
		sort!"a.slot<b.slot"(players[1..$]);
		hostSettings.slot=players[host].slot;
		foreach(ref p;players[1..$]) p.settings.commit=hostSettings.commit;
	}
	void sendMap(int i,scope ubyte[] mapData){
		players[i].send(Packet.sendMap(mapData.length),mapData);
	}
	void sendState(int i,scope ubyte[] stateData,scope ubyte[] commandData){
		players[i].send(Packet.sendState(stateData.length+commandData.length),stateData,commandData);
	}
	void sendStateAll(alias filter,T...)(scope ubyte[] stateData,scope ubyte[] commandData,T args){
		foreach(i,ref player;players){
			if(i==me) continue;
			if(!filter(cast(int)i,args)) continue;
			sendState(cast(int)i,stateData,commandData);
		}
	}
	Array!ubyte gameInitData;
	bool hasGameInitData(){ return !!gameInitData.length; }
	void clearGameInitData(){ gameInitData.length=0; }
	void initGame(int i,scope ubyte[] gameInitData)in{
		assert(isHost);
	}do{
		players[i].send(Packet.initGame(gameInitData.length),gameInitData);
	}
	void initGame(scope ubyte[] gameInitData)in{
		assert(isHost);
	}do{
		foreach(i;0..players.length){
			if(i==me) continue;
			if(!players[i].status.among(PlayerStatus.pendingGameInit,PlayerStatus.readyToLoad))
				continue;
			initGame(cast(int)i,gameInitData);
		}
		// for late joining:
		this.gameInitData.length=gameInitData.length;
		this.gameInitData.data[]=gameInitData[];
	}
	Array!ubyte mapData;
	bool hasMapData(){ return !!mapData.length; }
	void clearMapData(){ mapData.length=0; }
	bool synchronizeMap(scope void delegate(string name) load)in{
		assert(isHost||load!is null);
	}do{
		auto name=hostSettings.map;
		auto hash=hostSettings.mapHash;
		if(isHost){
			if(hasMapData()){
				foreach(i,ref player;players){
					if(i==host) continue;
					if(player.status!=PlayerStatus.mapHashed) continue;
					if(player.settings.mapHash==hash) continue;
					updateStatus(cast(int)i,PlayerStatus.commitHashReady);
					sendMap(cast(int)i,mapData.data);
				}
			}
			return mapHashed&&connectedPlayers.all!((ref p)=>p.settings.map==name&&p.settings.mapHash==hash);
		}else{
			enforce(settings.map==hostSettings.map,"bad map");
			if(settings.mapHash!=hash&&hasMapData()){
				import std.digest.crc;
				auto crc32=digest!CRC32(mapData.data);
				static assert(typeof(crc32).sizeof==int.sizeof);
				if(*cast(int*)&crc32==hash){
					import std.path: buildPath, baseName, setExtension;
					version(Windows){}else name=name.replace("\\","/"); // hack
					name=buildPath("maps",baseName(name));
					import file=std.file: exists, rename;
					if(file.exists(name)){
						import std.format:format;
						auto newName=setExtension(name,format(".%08x.scp",settings.mapHash));
						file.rename(name,newName);
						stderr.writeln("existing map '",name,"' moved to '",newName,"'");
					}
					mapData.data.toFile(name);
					stderr.writeln("downloaded map '",name,"'");
					if(load!is null) load(name);
				}
				clearMapData();
			}
			return mapHashed&&settings.map==name&&settings.mapHash==hash;
		}
	}
	void load(int i)in{
		assert(isHost&&isReadyToLoadStatus(players[i].status));
	}do{
		updateStatus(i,PlayerStatus.pendingLoad);
		players[i].send(Packet.loadGame);
	}
	void load()in{
		assert(isHost&&readyToLoad);
	}do{
		updateStatus(PlayerStatus.loading);
		foreach(i;connectedPlayerIds) if(i!=me) load(cast(int)i);
	}
	void start(Controller!B controller)in{
		assert(isHost&&readyToStart);
	}do{
		ackHandler=AckHandler.measurePing;
		players[me].ping=0;
		foreach(i,ref player;players)
			ping(cast(int)i);
		while(connectedPlayers.any!((ref p)=>p.status!=PlayerStatus.desynched&&p.ping==-1))
			update(controller);
		auto maxPing=connectedPlayers.map!(p=>p.ping).reduce!max;
		writeln("pings: ",players.map!(p=>p.ping));
		foreach(i;connectedPlayerIds){
			if(players[i].ping!=-1){
				updateStatus(cast(int)i,PlayerStatus.pendingStart);
				players[i].send(Packet.startGame((maxPing-players[i].ping)/2));
			}
		}
		Thread.sleep((maxPing/2).msecs);
		updateStatus(PlayerStatus.playing);
		if(controller.state){
			bool hasSlot=0<=slot&&slot<controller.state.slots.length;
			auto wizId=hasSlot?controller.state.slots[slot].wizard:0;
			if(wizId) B.focusCamera(wizId);
		}
		B.unpause();
	}
	void setFrame(int player,int frame){
		players[player].send(Packet.setFrame(frame));
	}
	void setFrameAll(int frame){
		foreach(i,ref player;players)
			if(i!=me)
				player.send(Packet.setFrame(frame));
	}
	void nudgeTimer(int player,Duration adjustment){
		players[player].send(Packet.nudgeTimer(adjustment.total!"hnsecs"));
	}
	void pause(PlayerStatus status)in{
		assert(isHost);
		assert(isPausedStatus(status));
	}do{
		updateStatus(status);
	}
	void unpause()in{
		assert(isHost);
		assert(paused);
	}do{
		updateStatus(PlayerStatus.readyToResynch); // TODO: a full resynch may be overkill
	}
	void addSynch(int frame,uint hash)in{
		assert(isHost);
	}do{
		synchQueue.addReference(frame,hash);
	}
	void capSynch(int frame)in{
		assert(isHost);
	}do{
		synchQueue.capReferences(frame);
	}
	void continueSynchAt(int frame)in{
		assert(isHost);
	}do{
		synchQueue.continueAt(frame);
	}
	void checkSynch(int frame,uint hash)in{
		assert(!isHost);
	}do{
		if(desynched) return;
		if(!checkDesynch) return;
		players[host].send(Packet.checkSynch(frame,hash));
		//writeln("checkDesynch(",frame,",",hash,"): ",committedFrame," ",players.map!((ref p)=>p.status)," ",players.map!((ref p)=>p.slot)," ",players.map!((ref p)=>p.committedFrame)," ",activePlayerIds);
	}
	/+void confirmSynch(int player,int frame,uint hash)in{
		assert(isHost);
	}do{
		if(desynched) return;
		if(!checkDesynch) return;
		players[player].send(Packet.confirmSynch(frame,hash));
	}+/
	bool logDesynch_=true;
	void logDesynch(scope ubyte[] stateData)in{
		assert(!isHost);
	}do{
		if(!logDesynch_) return;
		players[host].send(Packet.logDesynch(stateData.length),stateData);
	}

	void shutdown(){
		foreach(ref player;players){
			if(player.alive){
				player.send(Packet.disconnect());
				player.connection.close();
				player.connection=null;
			}
		}
	}
}
