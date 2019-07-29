import ntts: God;
struct Options{
	// graphics options
	int width,height;
	bool enableFullscreen=false;
	float scale=1.0f;
	bool scaleToFit=true;
	float aspectDistortion=1.2f;
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
	string wizard="";
	God god;
	int level=9;
	int souls=12;
	int delayStart=0;
}
