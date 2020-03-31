import std.stdio, std.conv, std.string, std.algorithm, std.traits;
import util, keycodes;

enum BindableText{
	open="nepo",
	cast_="lpsK",
	gamma="amag",
	creationSpell="?rcK",
	spell="?psK",
	structureSpell="?hsK",
}

enum Bindable:char[4]{
	unknown="\0\0\0\0",
	// control keys
	moveForward="rofM",
	moveBackward="kabM",
	turnLeft="tflM",
	turnRight="tgrM",
	cameraZoomIn="imzM",
	cameraZoomOut="omzM",
	// orders
	attack="ttat",
	guard="augt",
	retreat="ziwp",
	move="otog",
	useAbility="ibaK",
	dropSoul="losd",
	// miscellaneous
	optionsMenu="UNEM",
	skipSpeech="piks",
	openNextSpellTab="nbat", // open
	openCreationSpells="8rcS", // open
	openSpells="gamS", // open
	openStructureSpells="rtsS", // open
	quickSave="vasQ",
	quickLoad="dolQ",
	pause="swap",
	changeCamera="macc",
	sendChatMessage="thcK",
	gammaCorrectionPlus="+mag", // gamma
	gammaCorrectionMinus="-mag", // gamma
	screenShot="tohs",
	// formations
	semicircleFormation="mesf",
	circleFormation="ricf",
	phalanxFormation="ahpf",
	wedgeFormation="jdwf",
	skirmishFormation="rksf",
	lineFormation="nilf",
	flankLeftFormation="llff",
	flankRightFormation="rlff",
	// taunts
	randomTaunt="tntr",
	taunt1="1ntK", // "tntK"
	taunt2="2ntK", // "tntK"
	taunt3="3ntK", // "tntK"
	taunt4="4ntK", // "tntK"
	// cast creation spell #
	castCreationSpell1="1rcK", // cast creationSpell 1
	castCreationSpell2="2rcK", // cast creationSpell 2
	castCreationSpell3="3rcK", // cast creationSpell 3
	castCreationSpell4="4rcK", // cast creationSpell 4
	castCreationSpell5="5rcK", // cast creationSpell 5
	castCreationSpell6="6rcK", // cast creationSpell 6
	castCreationSpell7="7rcK", // cast creationSpell 7
	castCreationSpell8="8rcK", // cast creationSpell 8
	castCreationSpell9="9rcK", // cast creationSpell 9
	castCreationSpell10="01cK", // cast creationSpell 10
	castCreationSpell11="11cK", // cast creationSpell 10
	// cast spell #
	castSpell1="1psK", // cast spell 1
	castSpell2="2psK", // cast spell 2
	castSpell3="3psK", // cast spell 3
	castSpell4="4psK", // cast spell 4
	castSpell5="5psK", // cast spell 5
	castSpell6="6psK", // cast spell 6
	castSpell7="7psK", // cast spell 7
	castSpell8="8psK", // cast spell 8
	castSpell9="9psK", // cast spell 9
	castSpell10="01sK", // cast spell 10
	castSpell11="11sK", // cast spell 11
	// cast structure spell #
	// castStructureSpell1="1hsK", // cast structureSpell 1
	// castStructureSpell2="2hsK," // cast structureSpell 2
	// castStructureSpell3="2hsK," // cast structureSpell 3
	// castStructureSpell4="2hsK," // cast structureSpell 4
	// castStructureSpell5="2hsK," // cast structureSpell 5
	// castStructureSpell6="2hsK," // cast structureSpell 6
	// cast neutral spell
	castManalith="htlm", // cast
	castManahoar="oham", // cast
	castSpeedUp="pups", // cast
	castGuardian="ndrg", // cast
	castConvert="ccas", // cast
	castDesecrate="ucas", // cast
	castTeleport="elet", // cast
	castHeal="laeh", // cast,
	castShrine="pcas", // cast
	// cast persephone spell
	// TODO
	// cast persephone faithful
	// TODO
	// cast pyro spell
	// TODO
	// cast pyro's Prole
	// TODO
	// cast james spell
	// TODO
	// cast james' men o' the glebe
	// TODO
	// cast stratos spell
	// TODO
	// cast stratos servants
	// TODO
	// cast charnel spell
	// TODO
	// cast charnel's minions
	// TODO
}

string defaultName(Bindable bindable){
	final switch(bindable) with(Bindable){
		case unknown: return "Unknown";
		// control keys
		case moveForward: return "Move Forward";
		case moveBackward: return "Move Backward";
		case turnLeft: return "Turn Left";
		case turnRight: return "Turn Right";
		case cameraZoomIn: return "Camera zoom in";
		case cameraZoomOut: return "Camera zoom out";
		// orders
		case attack: return "Attack";
		case guard: return "Guard";
		case retreat: return "Retreat!";
		case move: return "Go to";
		case useAbility: return "Use Creature Ability";
		case dropSoul: return "Drop Soul";
		// miscellanneous
		case optionsMenu: return "Options Menu";
		case skipSpeech: return "Skip Speech";
		case openNextSpellTab: return "Open Next Spell Tab";
		case openCreationSpells: return "Open Creation spells";
		case openSpells: return "Open Spells";
		case openStructureSpells: return "Open Structure spells";
		case quickSave: return "Quick Save";
		case quickLoad: return "Quick Load";
		case pause: return "Pause";
		case changeCamera: return "Change camera";
		case sendChatMessage: return "Send Chat Message";
		case gammaCorrectionPlus: return "Gamma Correction +";
		case gammaCorrectionMinus: return "Gamma Correction -";
		case screenShot: return "Screen Shot";
		// formations
		case semicircleFormation: return "Semicircle Formation";
		case circleFormation: return "Circle Formation";
		case phalanxFormation: return "Phalanx Formation";
		case wedgeFormation: return "Wedge Formation";
		case skirmishFormation: return "Skirmish Formation";
		case lineFormation: return "Line Formation";
		case flankLeftFormation: return "Flank left formation";
		case flankRightFormation: return "Flank right formation";
		// taunts
		case randomTaunt: return "Random Taunt";
		static foreach(i;1..4+1) case mixin(text(`taunt`,i)): return mixin(text(`"Taunt #`,i,`"`));
		// spells
		static foreach(i;1..11+1) case mixin(text(`castCreationSpell`,i)): return mixin(text(`"Cast creation spell #`,i,`"`));
		static foreach(i;1..11+1) case mixin(text(`castSpell`,i)): return mixin(text(`"Cast spell #`,i,`"`));
		//static foreach(i;1..6+1) case mixin(text(`castStructureSpell`,i)): return mixin(text(`"Cast structure spell #`,i,`"`));
		case castManalith: return "Cast Manalith";
		case castManahoar: return "Cast Manahoar";
		case castSpeedUp: return "Cast Speed Up";
		case castGuardian: return "Cast Guardian";
		case castConvert: return "Cast Convert";
		case castDesecrate: return "Cast Desecrate";
		case castTeleport: return "Cast Teleport";
		case castHeal: return "Cast Heal";
		case castShrine: return "Cast Shrine";
	}
}

// string translatedName(Bindable bindable){ } // TODO

enum Modifiers{
	None=0,
	ctrl=1,
	shift=2,
	shiftCtrl=3,
}

struct Hotkey{
	int keycode;
	Bindable action;
}

struct ModHotkey{
	Modifiers mod;
	Hotkey hotkey;
	alias hotkey this;
}

struct Hotkeys{
	bool capsIsCtrl=true;
	Hotkey[][Modifiers.max+1] hotkeys;
	alias hotkeys this;
	void add(ModHotkey modHotkey){
		hotkeys[modHotkey.mod]~=modHotkey.hotkey;
	}
}

Hotkeys defaultHotkeys(){
	return Hotkeys.init; // TODO
}

string _or_,shift,ctrl,shiftDash,ctrlDash;
Bindable[string] bindableTable;
void initHotkeys(){
	initKeycodes();
	import nttData:texts;
	_or_=texts.get("_or_","or");
	shift=texts.get("tfsK","Shift");
	shiftDash=shift~"-";
	ctrl=texts.get("ltcK","Ctrl");
	ctrlDash=ctrl~"-";
	void add(string name,Bindable bindable){
		bindableTable[toLower(name)]=bindable;
	}
	static foreach(bindable;EnumMembers!Bindable)
		add(defaultName(bindable),bindable);
}

Bindable parseBindable(string name){ return bindableTable.get(toLower(name),Bindable.unknown); }

struct ModKeycode{
	Modifiers mod;
	int keycode;
}
ModKeycode parseModKeycode(string key){
	ModKeycode result;
	for(;;){
		if(key.startsWith(ctrlDash)){
			result.mod|=Modifiers.ctrl;
			key=key[(ctrlDash).length..$];
		}else if(key.startsWith("Ctrl-")||key.startsWith("ctrl-")){
			result.mod|=Modifiers.ctrl;
			key=key["Ctrl-".length..$];
		}else if(key.startsWith(shiftDash)){
			result.mod|=Modifiers.shift;
			key=key[shiftDash.length..$];
		}else if(key.startsWith("Shift-")||key.startsWith("shift-")){
			result.mod|=Modifiers.shift;
			key=key["Shift-".length..$];
		}else break;
	}
	auto keycode=parseKeycode(key);
	if(!keycode){
		stderr.writeln("unknown key: ",key);
		return ModKeycode.init;
	}
	result.keycode=keycode;
	return result;
}

Hotkeys parseHotkeys(string hotkeys){
	Hotkeys result;
	foreach(line;hotkeys.lineSplitter){
		line=line.strip;
		if(line[0]=='#') continue;
		auto colon=line.indexOf(':');
		if(colon==line.length-1) continue;
		if(colon==-1){
			stderr.writeln("malformed hotkey description, missing ':': ",line);
			continue;
		}
		auto command=line[0..colon].strip;
		auto bindable=parseBindable(command);
		if(bindable==Bindable.unknown){
			stderr.writeln("unknown bindable command: ",command);
			continue;
		}
		foreach(key;line[colon+1..$].strip.splitter(" or ")){
			auto modKeycode=parseModKeycode(key);
			if(!modKeycode.keycode) continue;
			if(modKeycode.keycode==KEY_CAPSLOCK) result.capsIsCtrl=false;
			result.add(ModHotkey(modKeycode.mod,Hotkey(modKeycode.keycode,bindable)));
		}
	}
	return result;
}

Hotkeys loadHotkeys(string filename){
	return parseHotkeys(cast(string)readFile(filename));
}
