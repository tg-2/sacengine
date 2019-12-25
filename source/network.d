import std.algorithm, std.range, std.stdio, std.conv, std.exception, core.thread;
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
	// TODO: defend comprehensively
	return CommandType.min<=command.type&&command.type<=CommandType.max;
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
	loadGame,
	startGame,
	// host query
	checkSynch,
	// broadcast
	updateSetting,
	setMap,
	appendMap,
	updateStatus,
	command,
	commit,
}

PacketPurpose purposeFromType(PacketType type){
	final switch(type) with(PacketType) with(PacketPurpose){
		case nop,disconnect,ping,ack: return peerToPeer;
		case updatePlayerId,loadGame,startGame: return hostMessage;
		case checkSynch: return hostQuery;
		case updateSetting,setMap,appendMap,updateStatus,command,commit: return broadcast;
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
			case loadGame: return text("Packet.loadGame()");
			case startGame: return text("Packet.startGame(",startDelay,")");
			case checkSynch: return text("Packet.checkSynch(",synchFrame,",",synchHash,")");
			case updateSetting:
				auto len=0;
				while(len<optionName.length&&optionName[len]!='\0') ++len;
				switch(optionName[0..len]){
					static foreach(setting;__traits(allMembers,Settings)){
						static if(setting!="map"){
							case setting:
								alias T=typeof(mixin(`Settings.`~setting));
								static if(is(T==int)) return text(`Packet.updateSetting!"`,setting,`"(`,player,",",intValue,")");
								else static if(is(T==bool))  return text(`Packet.updateSetting!"`,setting,`"(`,player,",",boolValue,")");
								else static if(is(T==float))  return text(`Packet.updateSetting!"`,setting,`"(`,player,",",floatValue,")");
								else static if(is(T==God)) return text(`Packet.updateSetting!"`,setting,`"(`,player,",",godValue,")");
								else static if(is(T==char[4]))  return text(`Packet.updateSetting!"`,setting,`"(`,player,`,"`,char4Value,`")`);
								else static assert(0);
						}
					}
					default: return text(`Packet.updateSetting!"`,optionName[0..len],`"(?)`);
				}
			case setMap: return text("Packet.setMap(",mapPlayer,",",mapName,")");
			case appendMap: return text("Packet.appendMap(",mapPlayer,",",mapName,")");
			case updateStatus: return text("Packet.updateStatus(",player,`,PlayerStatus.`,newStatus,")");
			case command: return text("Packet.command(fromNetwork(",networkCommand,"))");
			case commit: return text("Packet.commit(",commitPlayer,",",commitFrame,")");
		}
	}
	int size=Packet.sizeof;
	PacketType type;
	union{
		struct{}// nop
		struct{}// disconnect
		struct{ int id; }// ping, updatePlayerId
		struct{}// loadGame
		struct{ uint startDelay; } // startGame
		struct{ // checkSynch
			int synchFrame;
			int synchHash;
		}
		struct{ int pingId; } // ack
		struct{ // updateSetting, updateStatus
			int player;
			union{
				struct{// updateSetting
					char[32] optionName;
					union{
						int intValue;
						int boolValue;
						float floatValue;
						God godValue;
						char[4] char4Value;
					}
				}
				struct{
					PlayerStatus newStatus;
				}
			}
		}
		struct{ int mapPlayer; char[32] mapName; } // setMap, appendMap
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
	static Packet updatePlayerId(int id){
		Packet p;
		p.type=PacketType.updatePlayerId;
		p.id=id;
		return p;
	}
	static Packet loadGame(){
		Packet p;
		p.type=PacketType.loadGame;
		return p;
	}
	static Packet startGame(uint startDelay){
		Packet p;
		p.type=PacketType.startGame;
		p.startDelay=startDelay;
		return p;
	}
	static Packet checkSynch(int frame,int hash){
		Packet p;
		p.type=PacketType.checkSynch;
		p.synchFrame=frame;
		p.synchHash=hash;
		return p;
	}
	static Packet updateSetting(string name)(int player,typeof(mixin(`Options.`~name)) value){
		Packet p;
		p.type=PacketType.updateSetting;
		p.player=player;
		p.optionName[]='\0';
		p.optionName[0..name.length]=name[];
		static assert(name.length<optionName.length);
		static if(is(typeof(value)==int)) p.intValue=value;
		else static if(is(typeof(value)==bool)) p.boolValue=value;
		else static if(is(typeof(value)==float)) p.floatValue=value;
		else static if(is(typeof(value)==God)) p.godValue=value;
		else static if(is(typeof(value)==char[4])) p.char4Value=value;
		else static assert(0);
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
		return p;
	}
	static Packet updateStatus(int player,PlayerStatus newStatus){
		Packet p;
		p.type=PacketType.updateStatus;
		p.player=player;
		p.newStatus=newStatus;
		return p;
	}
	static Packet command(B)(int frame,Command!B command){
		Packet p;
		p.type=PacketType.command;
		p.frame=frame;
		p.networkCommand=toNetwork(command);
		return p;
	}
	static Packet commit(int player,int frame){
		Packet p;
		p.type=PacketType.commit;
		p.commitPlayer=player;
		p.commitFrame=frame;
		return p;
	}
}

public import std.socket;
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
	override bool alive(){
		alive_&=tcpSocket.isAlive;
		return alive_;
	}
	bool ready_=false;
	override bool ready(){
		if(!ready_&&alive) receiveData;
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
		return result;
	}
	void receiveData(){
		assert(dataIndex<data.length);
		auto ret=tcpSocket.receive(data[dataIndex..$]);
		if(ret==Socket.ERROR){
			if(wouldHaveBlocked()) return;
			stderr.writeln(lastSocketError());
			ret=0;
		}
		if(ret==0){
			alive_=false;
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
	synched,
	readyToLoad,
	loading,
	readyToStart,
	playing,
	desynched,
	disconnected,
}

struct Player{
	PlayerStatus status;
	Settings settings;

	Connection connection;
	bool alive(){ return connection&&connection.alive; }
	void send(Packet p){
		if(alive)
			connection.send(p);
	}
	bool ready(){ return connection&&connection.ready; }
	Packet receive()in{
		assert(ready);
	}do{
		return connection.receive;
	}

	int committedFrame=0;
	int synchronizedFrame=0;
	int ping=-1;
}

enum playerLimit=256;
enum listeningPort=9116;

final class SynchQueue{
	enum maxLength=256;
	int[maxLength] hashes;
	int start=0,end=0;
	void addReference(int frame,int hash)in{
		assert(frame==end,text(frame," ",end));
	}do{
		while(end+1-start>cast(int)hashes.length)
			start++;
		hashes[(end++)%$]=hash;
	}
	bool check(int frame,int hash){
		if(frame<start) return true; // too old. TODO: count this as a desynch?
		if(frame>=end) return false; // impossibly recent
		return hashes[frame%$]==hash;
	}
}

final class Network(B){
	Player[] players;
	Socket listener;
	void makeListener(){
		listener=new Socket(AddressFamily.INET,SocketType.STREAM);
		listener.setOption(SocketOptionLevel.SOCKET,SocketOption.REUSEADDR,true);
		try{
			listener.bind(new InternetAddress(listeningPort));
			listener.listen(playerLimit);
			listener.blocking=false;
		}catch(Exception){
			listener=null;
		}
	}
	this(){
		// makeListener
	}
	enum host=0;
	bool dumpTraffic=false;
	bool checkDesynch=true;
	bool isHost(){ return me==host; }
	SynchQueue synchQueue;
	void hostGame()in{
		assert(!players.length);
	}do{
		makeListener();
		enforce(listener!is null,text("cannot host on port ",listeningPort));
		static assert(host==0);
		players=[Player(PlayerStatus.synched,Settings.init,null)];
		me=0;
		if(checkDesynch) synchQueue=new SynchQueue();
	}
	bool joinGame(InternetAddress hostAddress)in{
		assert(!players.length);
	}do{
		auto socket=new Socket(AddressFamily.INET,SocketType.STREAM);
		try socket.connect(hostAddress);
		catch(Exception){ return false; }
		socket.blocking=false;
		players=[Player(PlayerStatus.connected,Settings.init,new TCPConnection(socket))];
		return true;
	}
	bool synched(){
		return me!=-1&&players[me].status>=PlayerStatus.synched;
	}
	bool readyToLoad(){
		return players.all!(p=>p.status>=PlayerStatus.readyToLoad);
	}
	bool clientsReadyToLoad(){
		return iota(players.length).filter!(i=>i!=host).map!(i=>players[i]).all!(p=>p.status>=PlayerStatus.readyToLoad);
	}
	bool loading(){
		return me!=-1&&players[me].status==PlayerStatus.loading;
	}
	bool readyToStart(){
		return players.all!(p=>p.status>=PlayerStatus.readyToStart);
	}
	bool playing(){
		return me!=-1&&players[me].status==PlayerStatus.playing;
	}
	bool desynched(){
		//return me!=-1&&players[me].status==PlayerStatus.desynched;
		return players.any!(p=>p.status==PlayerStatus.desynched);
	}
	int committedFrame(){
		if(!players.length) return 0;
		return players.map!(p=>p.committedFrame).reduce!min;
	}
	int me=-1;
	@property settings()in{
		assert(readyToLoad());
	}do{
		return players[me].settings;
	}
	void broadcast(Packet p)in{
		assert(purposeFromType(p.type)==PacketPurpose.broadcast);
	}do{
		if(isHost){
			foreach(i;0..players.length)
				players[i].send(p);
		}else players[host].send(p);
	}
	void updateStatus(int player,PlayerStatus newStatus)in{
		assert(player==me||isHost);
	}do{
		auto oldStatus=players[player].status;
		if(oldStatus>=newStatus) return;
		broadcast(Packet.updateStatus(player,newStatus));
		players[player].status=newStatus;
	}
	void updateStatus(PlayerStatus newStatus)in{
		assert(me!=-1);
	}do{
		updateStatus(me,newStatus);
	}
	void updateSetting(string setting,T)(int player,T value){
		if(mixin(`players[player].settings.`~setting)==value) return;
		static if(setting=="map"){
			enum blockSize=Packet.mapName.length;
			foreach(i;0..(value.length+blockSize-1)/blockSize){
				auto part=value[i*blockSize..min($,(i+1)*blockSize)];
				if(i==0) broadcast(Packet.setMap(player,part));
				else broadcast(Packet.appendMap(player,part));
			}
		}else broadcast(Packet.updateSetting!setting(player,value));
		mixin(`players[player].settings.`~setting)=value;
	}
	void synchronizeSetting(string setting)()in{
		assert(isHost);
	}do{
		foreach(player;0..cast(int)players.length)
			updateSetting!setting(player,mixin(`players[host].settings.`~setting));
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
		assert(playing&&players[me].committedFrame<=frame);
	}do{
		broadcast(Packet.command(frame,command));
	}
	void commit(int frame)in{
		assert(playing&&players[me].committedFrame<frame);
	}do{
		broadcast(Packet.commit(me,frame));
		players[me].committedFrame=frame;
	}
	enum AckHandler{
		none,
		measurePing,
	}
	AckHandler ackHandler;
	void performPacketAction(int sender,Packet p,Controller!B controller){
		if(dumpTraffic) writeln("from ",sender,": ",p);
		final switch(p.type){
			// peer to peer:
			case PacketType.nop: break;
			case PacketType.disconnect:
				writeln("player ",sender," disconnected");
				players[sender].connection=null;
				break;
			case PacketType.ping: players[sender].send(Packet.ack(p.id)); break;
			case PacketType.ack:
				final switch(ackHandler) with(AckHandler){
					case none: break;
					case measurePing:
						players[sender].ping=B.ticks()-p.pingId; // TODO: use a median over some window
						break;
				}
				break;
			// host message:
			case PacketType.updatePlayerId:
				if(sender!=host){
					stderr.writeln("non-host player ",sender," attempted to update id: ",p);
					break;
				}
				if(me!=-1){
					stderr.writeln("host attempted to identify already identified player ",me,": ",p);
					break;
				}
				if(p.id<0||p.id>=players.length){
					stderr.writeln("attempt to identify to invalid id ",p.id);
					break;
				}
				me=p.id;
				updateStatus(PlayerStatus.synched);
				break;
			case PacketType.loadGame:
				if(sender!=host){
					stderr.writeln("non-host player ",sender," attempted to initiate loading: ",p);
					break;
				}
				if(!readyToLoad){
					stderr.writeln("attempt to load game before ready: ",p);
					break;
				}
				updateStatus(PlayerStatus.loading);
				break;
			case PacketType.startGame:
				// TODO: wait for the specified amount of time
				if(sender!=host){
					stderr.writeln("non-host player ",sender," attempted to start game: ",p);
					break;
				}
				if(!readyToStart){
					stderr.writeln("attempt to start game before ready: ",p);
					break;
				}
				Thread.sleep(p.startDelay.msecs);
				updateStatus(PlayerStatus.playing);
				break;
			// host query:
			case PacketType.checkSynch:
				if(!checkDesynch) return;
				if(!isHost){
					stderr.writeln("checkSynch packet sent to non-host player ",me,": ",p);
					break;
				}
				assert(!!synchQueue);
				if(!synchQueue.check(p.synchFrame,p.synchHash)){
					stderr.writeln("player ",sender," desynchronized at frame ",p.synchFrame);
					if(p.synchFrame>=synchQueue.end){
						stderr.writeln("tried to synch on non-committed frame (after ",synchQueue.end,")");
					}else{
						stderr.writeln("expected hash ",synchQueue.hashes[p.frame%$],", got ",p.synchHash);
					}
					updateStatus(sender,PlayerStatus.desynched);
				}
				break;
			// broadcast:
			case PacketType.updateSetting,PacketType.setMap,PacketType.appendMap:
				if(!isHost&&sender!=host){
					stderr.writeln("non-host player ",sender," attempted to update settings: ",p);
					break;
				}
				if(me!=-1&&players[me].status>=PlayerStatus.loading){
					stderr.writeln("attempt to change settings after game started loading: ",p);
					break;
				}
				static assert(p.player.offsetof is p.mapPlayer.offsetof);
				if(p.player<0||p.player>=playerLimit){
					stderr.writeln("player id out of range: ",p);
					break;
				}
				if(p.player>=players.length) players.length=p.player+1;
				if(players[sender].status>=PlayerStatus.readyToLoad){
					stderr.writeln("attempt to change settings after marked ready to load: ",p);
					break;
				}
				if(p.type==PacketType.updateSetting){
					auto len=0;
					while(len<p.optionName.length&&p.optionName[len]!='\0') ++len;
					if(len==p.optionName.length) break;
				Lswitch:switch(p.optionName[0..len]){
						static foreach(setting;__traits(allMembers,Settings)){
							static if(setting!="map"){
								case setting:
									alias T=typeof(mixin(`players[p.player].settings.`~setting));
									static if(is(T==int)) mixin(`players[p.player].settings.`~setting)=p.intValue;
									else static if(is(T==bool))  mixin(`players[p.player].settings.`~setting)=p.boolValue;
									else static if(is(T==float))  mixin(`players[p.player].settings.`~setting)=p.floatValue;
									else static if(is(T==God))  mixin(`players[p.player].settings.`~setting)=p.godValue;
									else static if(is(T==char[4])) mixin(`players[p.player].settings.`~setting)=p.char4Value;
									else static assert(0);
									break Lswitch;
							}
						}
						default: break;
					}
				}else if(p.type==PacketType.setMap){
					auto len=0;
					while(len<p.mapName.length&&p.mapName[len]!='\0') ++len;
					players[p.mapPlayer].settings.map=p.mapName[0..len].idup;
				}else if(p.type==PacketType.appendMap){
					auto len=0;
					while(len<p.mapName.length&&p.mapName[len]!='\0') ++len;
					players[p.mapPlayer].settings.map~=p.mapName[0..len];
				}else assert(0);
				break;
			case PacketType.updateStatus:
				if(p.player<0||p.player>=playerLimit) break;
				if(p.player>=players.length) players.length=p.player+1;
				players[p.player].status=max(players[p.player].status,p.newStatus);
				break;
			case PacketType.command:
				if(controller) controller.addExternalCommand(p.frame,fromNetwork!B(p.networkCommand));
				break;
			case PacketType.commit:
				players[p.commitPlayer].committedFrame=max(players[p.commitPlayer].committedFrame,p.commitFrame);
				if(controller) controller.updateCommitted();
				break;
		}
	}
	void forwardPacket(int sender,Packet p,Controller!B controller){
		if(!isHost) return;
		// host forwards state updates to all clients
		// TODO: for commands, allow direct connections, to decrease latency
		final switch(purposeFromType(p.type)) with(PacketPurpose){
			case peerToPeer: break;
			case hostMessage: stderr.writeln("host message sent to host: ",p); break;
			case broadcast:
				foreach(other;0..players.length){
					if(other==sender) continue;
					players[other].send(p);
				}
				break;
			case hostQuery: break;
		}
	}
	void handlePacket(int sender,Packet p,Controller!B controller){
		performPacketAction(sender,p,controller);
		forwardPacket(sender,p,controller);
	}
	void sendPlayerData(Connection connection,int player)in{
		assert(isHost);
	}do{
		if(!connection) return;
		static foreach(setting;__traits(allMembers,Settings)){
			static if(setting=="map"){
				enum blockSize=Packet.mapName.length;
				auto value=players[player].settings.map;
				foreach(i;0..(value.length+blockSize-1)/blockSize){
					auto part=value[i*blockSize..min($,(i+1)*blockSize)];
					if(i==0) connection.send(Packet.setMap(player,part));
					else connection.send(Packet.appendMap(player,part));
				}
			}else connection.send(Packet.updateSetting!setting(player,mixin(`players[player].settings.`~setting)));
		}
		connection.send(Packet.updateStatus(player,players[player].status));
		// TODO: send address to attempt to establish peer to peer connection
	}
	void addPlayer(Player player)in{
		assert(isHost);
	}do{
		int newId=cast(int)players.length;
		players~=player;
		foreach(other;0..cast(int)players.length-1)
			sendPlayerData(players[other].connection,newId);
		foreach(other;0..cast(int)players.length)
			sendPlayerData(players[newId].connection,other);
		players[newId].send(Packet.updatePlayerId(newId));
	}
	void acceptNewConnections(){
		if(!listener) return;
		if(playing) return; // TODO: allow observers to join and dropped players to reconnect
		if(isHost){
			if(players.length>=playerLimit) return;
			for(Socket newSocket=null;;newSocket=null){
				try newSocket=listener.accept();
				catch(Exception){}
				if(!newSocket||!newSocket.isAlive) break;
				newSocket.blocking=false;
				// TODO: detect reconnection attempts
				auto newPlayer=Player(PlayerStatus.connected,Settings.init,new TCPConnection(newSocket));
				addPlayer(newPlayer);
				writeln("player ",players.length-1," joined");
			}
		}else{
			// TODO: accept peer-to-peer connections to decrease latency
		}
	}
	void update(Controller!B controller){
		acceptNewConnections();
		foreach(i,ref player;players){
			if(!player.connection) continue;
			if(!player.alive){
				player.connection=null;
				stderr.writeln("player ",i," dropped");
				continue;
			}
			while(player.ready) handlePacket(cast(int)i,player.receive,controller);
		}
	}
	void idleLobby()in{
		assert(me==-1||players[me].status<PlayerStatus.loading);
	}do{
		update(null);
		Thread.sleep(1.msecs);
	}
	void load()in{
		assert(isHost);
	}do{
		foreach(ref player;players)
			player.send(Packet.loadGame);
		updateStatus(PlayerStatus.loading);
	}
	void start()in{
		assert(isHost&&readyToStart);
	}do{
		ackHandler=AckHandler.measurePing;
		players[me].ping=0;
		foreach(ref player;players)
			player.send(Packet.ping(B.ticks()));
		while(players.any!(p=>p.ping==-1))
			update(null);
		auto maxPing=players.map!(p=>p.ping).reduce!max;
		enforce(maxPing!=-1);
		writeln("pings: ",players.map!(p=>p.ping));
		foreach(ref player;players)
			player.send(Packet.startGame((maxPing-player.ping)/2));
		Thread.sleep((maxPing/2).msecs);
		updateStatus(PlayerStatus.playing);
	}
	void addSynch(int frame,int hash)in{
		assert(isHost);
	}do{
		synchQueue.addReference(frame,hash);
	}
	void checkSynch(int frame,int hash)in{
		assert(!isHost);
	}do{
		players[host].send(Packet.checkSynch(frame,hash));
	}
}
