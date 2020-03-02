import ntts: God;
struct Options{
	// graphics options
	int width,height;
	bool enableFullscreen=false;
	float scale=1.0f;
	bool scaleToFit=true;
	float aspectDistortion=1.2f;
	float sunFactor=1.0f;
	float ambientFactor=1.0f;
	int shadowMapResolution=1024;
	bool enableWidgets=true;
	bool enableMapBottom=true;
	bool enableFog=false;
	bool enableSSAO=false;
	bool enableGlow=true;
	float glowBrightness=0.5;
	bool enableAntialiasing=true;
	int cursorSize=32;
	bool printFps=false;
	// audio options
	float volume=1.0f;
	float musicVolume=1.0f;
	float soundVolume=1.0f;
	// just for testing:
	bool enableReadFromWads=true;
	int replicateCreatures=1;
	int protectManafounts=0;
	int delayStart=0;
	int host=0;
	string joinIP="";
	Settings settings;
	bool testLag=false;
	bool dumpTraffic=false;
	bool checkDesynch=true;
	string recordingFilename="";
	bool logCore=false;
	string playbackFilename="";
	alias settings this;
}

struct Settings{
	string map="";
	int controlledSide=-1;
	char[4] wizard="";
	God god;
	int level=9;
	int souls=12;
}
