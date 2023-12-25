// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt
module netutil;

version(Posix){
import core.sys.posix.sys.socket;
import core.stdc.string;
struct ifaddrs{
	ifaddrs* ifa_next;
	char* ifa_name;
	uint ifa_flags;
	sockaddr* ifa_addr;
	sockaddr* ifa_netmask;
	union{
		sockaddr* ifu_broadaddr;
		sockaddr* ifu_dstaddr;
	}
	void* ifa_data;
}
extern(C) int getifaddrs(ifaddrs** list);
extern(C) void freeifaddrs(ifaddrs *__ifa);
struct in_addr {
	uint s_addr;
}
struct sockaddr_in {
	ubyte sin_family;
	ushort sin_port;
	in_addr sin_addr;
}
string[] getBroadcastAddresses(){
	string[] result=[];
	ifaddrs* list=null;
	getifaddrs(&list);
	scope(exit) if(list) freeifaddrs(list);
	for(auto curr=list;curr;curr=curr.ifa_next){
		if(!(curr.ifa_addr&&curr.ifa_addr.sa_family==AF_INET))
			continue;
		if(!(curr.ifa_netmask&&curr.ifa_netmask.sa_family==AF_INET))
			continue;
		auto name=curr.ifa_name[0..strlen(curr.ifa_name)];
		//import std.stdio;
		//writeln("name: ",name);
		auto addr=*cast(sockaddr_in*)curr.ifa_addr;
		auto netmask=*cast(sockaddr_in*)curr.ifa_netmask;
		auto broadcast=addr.sin_addr.s_addr|~netmask.sin_addr.s_addr;
		import std.format:format;
		result~=format!"%d.%d.%d.%d"(broadcast&0xff,(broadcast>>8)&0xff,(broadcast>>16)&0xff,(broadcast>>24)&0xff);
	}	
	return result;
}
}else version(Windows){
	import core.sys.windows.winbase, core.sys.windows.windef;
	import core.sys.windows.iptypes;
	import core.sys.windows.iphlpapi;
	import core.sys.windows.winerror;
	import std.windows.syserror;
	import core.stdc.stdlib;
	string[] getBroadcastAddresses(){
		string[] result=[];
		static void* iphlpapi=null;
		iphlpapi=LoadLibraryA("iphlpapi.dll");
		if(!iphlpapi) return result;
		extern(Windows) DWORD GetAdaptersInfo(PIP_ADAPTER_INFO pAdapterInfo, PULONG ulOutBufLen){
			static typeof(&__traits(parent,{})) sym;
			if(!sym) sym=cast(typeof(sym))GetProcAddress(iphlpapi,"GetAdaptersInfo");
			import std.exception,std.conv;
			enforce(!!sym,text("failed to load function '",__traits(identifier,__traits(parent,{})),"': ",sysErrorString(GetLastError())));
			return sym(pAdapterInfo,ulOutBufLen);
		}
		IP_ADAPTER_INFO* pAdapterInfo;
		scope(exit) if(pAdapterInfo) free(pAdapterInfo);
		ULONG ulOutBufLen;
		DWORD dwRetVal;
		pAdapterInfo=cast(IP_ADAPTER_INFO*)malloc(IP_ADAPTER_INFO.sizeof);
		ulOutBufLen=IP_ADAPTER_INFO.sizeof;
		if(GetAdaptersInfo(pAdapterInfo,&ulOutBufLen)!=ERROR_SUCCESS){
			free(pAdapterInfo);
			pAdapterInfo=cast(IP_ADAPTER_INFO*)malloc(ulOutBufLen);
		}
		if((dwRetVal=GetAdaptersInfo(pAdapterInfo,&ulOutBufLen))!=ERROR_SUCCESS)
			return [];
		for(auto pAdapter=pAdapterInfo;pAdapter;pAdapter=pAdapter.Next) {
			//import std.stdio;
			//writeln("name: ",pAdapter.AdapterName);
			//writeln("addr: ",pAdapter.IpAddressList.IpAddress.String);
			//writeln("netmask: ",pAdapter.IpAddressList.IpMask.String);
			auto addr_s=pAdapter.IpAddressList.IpAddress.String;
			auto netmask_s=pAdapter.IpAddressList.IpMask.String;
			uint parseIP(const(char)[] ip){
				ubyte[4] bytes;
				import std.format:formattedRead;
				ip.formattedRead!"%d.%d.%d.%d"(bytes[0],bytes[1],bytes[2],bytes[3]);
				return bytes[0]|bytes[1]<<8|bytes[2]<<16|bytes[3]<<24;
			}
			auto addr=parseIP(addr_s);
			auto netmask=parseIP(netmask_s);
			auto broadcast=addr|~netmask;
			import std.format:format;
			result~=format!"%d.%d.%d.%d"(broadcast&0xff,(broadcast>>8)&0xff,(broadcast>>16)&0xff,(broadcast>>24)&0xff);
		}
		return result;
	}
}else static assert(0);
