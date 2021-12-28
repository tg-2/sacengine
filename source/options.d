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
	int cursorSize=-1;
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
	bool randomGods=false;
	bool randomSpellbook=false;
	// global settings
	bool noMap=false;
	string mapList;
	bool _2v2=false;
	bool _3v3=false;
	bool mirrorMatch=false;
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
	// multiplayer
	int host=0;
	string joinIP="";
	bool testLag=false;
	bool dumpTraffic=false;
	bool checkDesynch=true;
	// recording and playback
	string recordingFilename="";
	bool compressRecording=true;
	int logCore=0;
	string playbackFilename="";
	// asset export
	string exportFolder="sacengine-exports";
	alias settings this;
}

struct SpellSpec{
	int level;
	char[4] tag;
}
struct Settings{
	string map="";
	int mapHash=0;
	bool observer=false;
	int controlledSide=-1;
	int team=-1;
	string name="";
	char[4] wizard="";
	immutable(SpellSpec)[] spellbook;
	int level=9;
	int souls=12;
}
