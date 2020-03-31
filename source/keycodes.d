public import dagon.core.keycodes;
import std.string, std.conv;

int keycodeFromName(string name){
	return 0; // TODO
}

enum KeyTag:char[4]{
	alt="tlaK",
	backspace="psbK",
	caps="pacK",
	control="ltcK",
	delete_="ledK",
	downArrow="nwdK",
	end="dneK",
	keypadEnter="tneK",
	escape="cseK",
	home="mohK",
	insert="sniK",
	leftArrow="tflK",
	numLock="lmnK",
	keypad="dapK",
	pageDown="dgpK",
	pageUp="ugpK",
	pause="swpK",
	return_="terK",
	rightArrow="tgrK",
	scrollLock="lcsK",
	shift="tfsK",
	space="cpsK",
	tab="cpsK",
	upArrow="_puK",
}

import nttData;
int[string] keycodesByName;
private{
	void add(string name,int keycode){
		keycodesByName[toLower(name)]=keycode;
	}
	void add(KeyTag tag,string name,int keycode,string suffix=""){
		if(suffix==""){
			add(toLower(texts[tag]),keycode);
			add(toLower(name),keycode);
		}else{
			add(toLower(texts[tag]~suffix),keycode);
			add(toLower(name~suffix),keycode);
		}
	}
}
void initKeycodes(){
	with(KeyTag){
		add(alt,"Alt",KEY_LALT);
		add(backspace,"Backspace",KEY_BACKSPACE);
		add(caps,"CAPS",KEY_CAPSLOCK);
		add(control,"Ctrl",KEY_LCTRL);
		add(delete_,"Delete",KEY_DELETE);
		add(downArrow,"Down Arrow",KEY_DOWN);
		add(end,"End",KEY_END);
		add(keypadEnter,"Keypad-enter",KEY_KP_ENTER);
		add(escape,"Escape",KEY_ESCAPE);
		add(home,"Home",KEY_HOME);
		add(insert,"Insert",KEY_INSERT);
		add(leftArrow,"Left Arrow",KEY_LEFT);
		add(numLock,"Num-lock",KEY_NUMLOCKCLEAR);
		// keypad
		void addKeypad(int keycode,string suffix){ add(keypad,"keypad-",keycode,suffix); }
		foreach(i;0..10) addKeypad(i==0?KEY_KP_0:KEY_KP_1+i-1,text(i));
		addKeypad(KEY_KP_DIVIDE,"/");
		addKeypad(KEY_KP_MULTIPLY,"*");
		addKeypad(KEY_KP_MINUS,"-");
		addKeypad(KEY_KP_PLUS,"+");
		addKeypad(KEY_KP_PERIOD,".");
		///
		add(pageDown,"Page Down",KEY_PAGEDOWN);
		add(pageUp,"Page Up",KEY_PAGEUP);
		add(pause,"Pause",KEY_PAUSE);
		add(return_,"Return",KEY_RETURN);
		add(rightArrow,"Right Arrow",KEY_RIGHT);
		add(scrollLock,"Scroll Lock",KEY_SCROLLLOCK);
		add(shift,"Shift",KEY_LSHIFT);
		add(space,"Space",KEY_SPACE);
		add(tab,"Tab",KEY_TAB);
		add(upArrow,"Up Arrow",KEY_UP);
		// keys without translation
		foreach(c;'a'..'z'+1) add(text(cast(char)c),KEY_A+(c-'a'));
		foreach(i;0..9) add(text(i),i==0?KEY_0:KEY_1+i-1);
		add("-",KEY_MINUS);
		add("=",KEY_EQUALS);
		add("[",KEY_LEFTBRACKET);
		add("]",KEY_RIGHTBRACKET);
		add("\\",KEY_BACKSLASH);
		add(";",KEY_SEMICOLON);
		add("'",KEY_APOSTROPHE);
		add("`",KEY_GRAVE);
		add(",",KEY_COMMA);
		add(".",KEY_PERIOD);
		add("/",KEY_SLASH);
		foreach(i;1..12+1) add(text("f",i),KEY_F1+i-1);
		add("Print Screen",KEY_PRINTSCREEN);
		
	}
}

int parseKeycode(string name){
	return keycodesByName.get(toLower(name),0);
}
