import std.exception, std.string, std.conv;
version(Windows) import core.sys.windows.windows;
else import core.sys.posix.dlfcn;

enum zts_err_ok=0;
enum zts_err_socket=-1;
enum zts_err_service=-2;
enum zts_err_arg=-3;

enum zts_af_inet=2;
enum zts_sock_stream=1;

enum zts_ipproto_tcp=6;

enum zts_inet6_addrstrlen=46;
enum zts_max_ip_str_len=46;

static if(is(size_t==ulong)) alias ssize_t=long;
else static if(is(size_t==uint)) alias ssize_t=int;
else static assert(0);

struct zts_in_addr {
    uint s_addr;
}
struct zts_sockaddr_in {
    ubyte sin_len;
    ubyte sin_family;
    ushort sin_port;
    zts_in_addr sin_addr;
	enum sin_zero_len=8;
    ubyte[sin_zero_len] sin_zero;
}
alias zts_sockaddr=zts_sockaddr_in;

void* libzt;
void libztInit(){
	if(libzt) return;
	//writeln("loading libzt");
	version(Windows){
		libzt=LoadLibraryA(".\\libzt.dll");
	}else{
		libzt=dlopen("./libzt.so",2); // RTLD_NOW
	}
	enforce(!!libzt, text("failed to load libzt: ",errorStr()));
}
void libztDestroy(){
	if(!libzt) return;
	//writeln("destroying libzt");
	version(Windows){
		FreeLibrary(libzt);
	}else{
		dlclose(libzt);
	}
	libzt=null;
}
void* ztSymbol(string symbolName){
	//writeln(symbolName);
	libztInit();
	enforce(!!libzt,"libzt not initialized");
	version(Windows){
		return GetProcAddress(libzt, symbolName.toStringz());
	}else{
		return dlsym(libzt, symbolName.toStringz());
	}
}
enum load=q{
	static typeof(&__traits(parent,{})) sym;
	if(!sym) sym=cast(typeof(sym))ztSymbol(__traits(identifier,__traits(parent,{})));
	enforce(!!sym, text("failed to load function '",__traits(identifier,__traits(parent,{})),"': ",errorStr()));
};

extern(C):
int zts_init_from_storage(const char* path){ mixin(load); return sym(path); }
int zts_node_start(){ mixin(load); return sym(); }
int zts_node_stop(){ mixin(load); return sym(); }
int zts_node_is_online(){ mixin(load); return sym(); }
ulong zts_node_get_id(){ mixin(load); return sym(); }
int zts_net_join(ulong net_id){ mixin(load); return sym(net_id); }
int zts_net_leave(ulong net_id){ mixin(load); return sym(net_id); }
int zts_net_transport_is_ready(ulong net_id){ mixin(load); return sym(net_id); }
int zts_addr_is_assigned(ulong net_id,uint family){ mixin(load); return sym(net_id,family); }
int zts_addr_get_str(ulong net_id,uint family,char* dst,uint len){ mixin(load); return sym(net_id,family,dst,len); }

int zts_util_ipstr_to_saddr(const char* src_ipstr,ushort port,zts_sockaddr_in* dstaddr,uint* addrlen){
	mixin(load);
	return sym(src_ipstr,port,dstaddr,addrlen);
}

int zts_bsd_socket(int family,int type,int protocol){ mixin(load); return sym(family,type,protocol); }
int zts_set_blocking(int fd,int enabled){ mixin(load); return sym(fd,enabled); }
int zts_bsd_connect(int fd,const zts_sockaddr_in* addr,uint addrlen){
	mixin(load);
	return sym(fd,addr,addrlen);
}
int zts_bsd_bind(int fd,const zts_sockaddr_in* addr, uint addrlen){
	mixin(load);
	return sym(fd,addr,addrlen);
}
int zts_bsd_listen(int fd,int backlog){
	mixin(load);
	return sym(fd,backlog);
}
int zts_bsd_accept(int fd,zts_sockaddr_in* addr, uint* addrlen){
	mixin(load);
	return sym(fd,addr,addrlen);
}
ssize_t zts_bsd_read(int fd,void* buf,size_t len){
	mixin(load);
	return sym(fd,buf,len);
}
ssize_t zts_bsd_write(int fd,const void* buf,size_t len){
	mixin(load);
	return sym(fd,buf,len);	
}

int zts_bsd_getsockopt(int fd,int level,int optname,void* optval,uint* optlen){
	mixin(load);
	return sym(fd,level,optname,optval,optlen);
}
int zts_bsd_close(int fd){
	mixin(load);
	return sym(fd);
}

enum zts_shut_rd=0;
enum zts_shut_wr=1;
enum zts_shut_rdwr=2;

int zts_bsd_shutdown(int fd,int how){
	mixin(load);
	return sym(fd,how);
}
/+void zts_util_delay(ulong milliseconds){
	mixin(load);
	return sym(milliseconds);
}+/

int zts_get_last_socket_error(int fd){
	mixin(load);
	return sym(fd);
}

enum zts_eagain = 11;
enum zts_etimeout = 110;
bool zts_would_have_blocked(int fd){
	auto lasterr=zts_get_last_socket_error(fd);
	import std.stdio;
	return lasterr==0||lasterr==zts_eagain||lasterr==zts_etimeout;
}

/+
enum zts_sol_socket=0x0fff;
enum zts_so_type=0x1008;
bool zts_socket_alive(int fd){ // does not seem to work
	int type;
	uint typesize=type.sizeof;
	return !zts_bsd_getsockopt(fd,zts_sol_socket,zts_so_type,&type,&typesize);
}
+/

version(Windows){
	string errorStr(){
		import std.windows.syserror;
		return sysErrorString(GetLastError());
	}
}else{
	string errorStr(){
		import std.conv:to;
		auto err=dlerror();
		if(err is null)
			return "shared library error";
		return to!string(err);
	}
}	 

void connectToZerotier(string identity_folder,ulong net_id){
	import std.stdio,core.thread;
	int err=zts_err_ok;
	err=zts_init_from_storage(identity_folder.toStringz);
	enforce(err==zts_err_ok, "failed to initialize zerotier");
	writeln("zerotier initialized");
	err=zts_node_start();
	enforce(err==zts_err_ok, "failed to start node");
	while(!zts_node_is_online()) {
		//zts_util_delay(50);
		Thread.sleep(50.dur!"msecs");
	}
	ulong node_id=zts_node_get_id();
	writefln("node id: %x", node_id);
	writeln("online");
	writefln("joining net %x", net_id);
	if(zts_net_join(net_id)!=zts_err_ok){
		writeln("unable to join zerotier network");
		return;
	}
	while(!zts_net_transport_is_ready(net_id)) {
		//zts_util_delay(50);
		Thread.sleep(50.dur!"msecs");
	}
	writeln("joined");
	while(!zts_addr_is_assigned(net_id, zts_af_inet)){
		//zts_util_delay(50);
		Thread.sleep(50.dur!"msecs");
	}
	char[zts_max_ip_str_len] ipstr = 0;
	zts_addr_get_str(net_id,zts_af_inet,ipstr.ptr,zts_max_ip_str_len);

	import std.algorithm;
	writeln("ip address: ",ipstr[].until(0));
}
