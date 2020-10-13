// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import ntts: God;
import hotkeys_: Hotkeys;
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
	bool advisorHelpSpeech=true;
	// input options
	string hotkeyFilename="";
	Hotkeys hotkeys;
	float cameraMouseSensitivity=1.0f;
	float mouseWheelSensitivity=1.0f;
	bool debugHotkeys=false;
	// player-specific settings
	God god;
	Settings settings;
	bool randomSpellbook=false;
	// global settings
	string mapList;
	bool _2v2=false;
	bool _3v3=false;
	bool shuffleSides=false;
	bool shuffleTeams=false;
	bool randomWizards=false;
	bool randomSpellbooks=false;
	bool synchronizeLevel=true;
	bool synchronizeSouls=true;
	// just for testing:
	bool enableReadFromWads=true;
	int replicateCreatures=1;
	int protectManafounts=0;
	int delayStart=0;
	int host=0;
	string joinIP="";
	bool testLag=false;
	bool dumpTraffic=false;
	bool checkDesynch=true;
	string recordingFilename="";
	bool logCore=false;
	string playbackFilename="";
	alias settings this;
}

struct SpellSpec{
	int level;
	char[4] tag;
}
struct Settings{
	string map="";
	bool observer=false;
	int controlledSide=-1;
	int team=-1;
	string name="";
	char[4] wizard="";
	immutable(SpellSpec)[] spellbook;
	int level=9;
	int souls=12;
}
