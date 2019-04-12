import ntts: God;
struct Options{
	int width,height;
	float scale=1.0f;
	bool scaleToFit=false;
	float aspectDistortion=1.2f;
	int shadowMapResolution=1024;
	bool enableWidgets=true;
	bool enableMapBottom=true;
	bool enableFog=false;
	bool enableSSAO=false;
	bool enableGlow=true;
	float glowBrightness=0.5;
	bool enableAntialiasing=true;
	int replicateCreatures=1;
	int cursorSize=32;
	bool printFPS=false;
	// just for testing:
	string wizard="cwe2";
	God god;
}
