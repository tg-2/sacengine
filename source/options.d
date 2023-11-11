// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import ntts: God;
import hotkeys_: Hotkeys;

enum GameMode{
	scenario,
	skirmish,
	slaughter,
	domination,
	soulHarvest,
}

struct Options{
	// graphics options
	int width=1280, height=720;
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
	GameMode gameMode=GameMode.skirmish;
	int gameModeParam;
	bool ffa=false;
	bool _2v2=false;
	bool _3v3=false;
	bool mirrorMatch=false;
	bool shuffleSides=false;
	bool shuffleTeams=false;
	bool shuffleAltars=false;
	bool shuffleSlots=false;
	bool randomWizards=false;
	bool randomSpellbooks=false;
	// just for testing:
	bool enableReadFromWads=true;
	int replicateCreatures=1;
	int protectManafounts=0;
	bool terrainSineWave=false;
	bool enableParticles=true;
	int delayStart=0;
	// zerotier
	string zerotierIdentity="zerotier-identity";
	ulong zerotierNetwork=0;
	// multiplayer
	bool host=false;
	int numSlots=1;
	string joinIP="";
	bool testLag=false;
	bool testRenderDelay=false;
	bool dumpTraffic=false;
	bool dumpNetworkStatus=false;
	bool dumpNetworkSettings=false;
	bool checkDesynch=true;
	bool logDesynch=true;
	bool synchronizeObserverChat=true;
	bool synchronizeLevel=true;
	bool synchronizeSouls=true;
	bool synchronizeLevelBounds=true;
	bool synchronizeXPRate=true;
	bool pauseOnDrop=true;
	// recording and playback
	string recordingFilename="";
	bool compressRecording=true;
	int logCore=0;
	string playbackFilename="";
	string continueFilename="";
	int continueFrame=-1;
	// asset export
	string exportFolder="sacengine-exports";
	alias settings this;
}

struct SpellSpec{
	int level;
	char[4] tag;
}
struct Settings{
	string commit;
	string map="";
	int mapHash=0;
	string name="";
	bool observer=false;
	bool observerChat=true;
	int slot=-1;
	int team=-1;
	char[4] wizard="";
	immutable(SpellSpec)[] spellbook;
	int level=9;
	int souls=12;

	int minLevel=1;
	int maxLevel=9;
	float xpRate=1.0f;
}
