import audio, nttData, maps;
enum Theme{
	normal,
	battle1,
	battle2,
	battle3,
	battle4,
	battle5,
	losing,
	winning,
	menu,
	none,
}
class AudioBackend{
	MP3[Theme.max] themes;
	MP3 sacrifice1;
	MP3 defeat;
	MP3 victory;
	auto currentTheme=Theme.none;
	auto nextTheme=Theme.none;
	float musicGain=1.0f;
	float soundEffectGain=1.0f;
	float themeGain=1.0f;
	this(Tileset tileset,float volume){ // TODO: load all god themes?
		musicGain=soundEffectGain=volume;
		themes[Theme.normal]=MP3(godThemes[tileset]);
		themes[Theme.battle1]=MP3("extracted/music/Battle 1.mp3");
		themes[Theme.battle2]=MP3("extracted/music/Battle 2.mp3");
		themes[Theme.battle3]=MP3("extracted/music/Battle 3.mp3");
		themes[Theme.battle4]=MP3("extracted/music/Battle 4.mp3");
		themes[Theme.battle5]=MP3("extracted/music/Battle 5.mp3");
		themes[Theme.losing]=MP3("extracted/music/Sacrifice Losing.mp3");
		themes[Theme.winning]=MP3("extracted/music/Sacrifice Victory.mp3");
		themes[Theme.menu]=MP3("extracted/music/menu.mp3");
		sacrifice1=MP3("extracted/music/Sacrifice 1.mp3");
		defeat=MP3("extracted/music/Defeat Theme.mp3");
		victory=MP3("extracted/music/Victory Theme.mp3");
	}
	void switchTheme(Theme next){
		nextTheme=next;
	}
	enum fadeOutTime=0.5f;
	void update(float dt){
		if(nextTheme!=currentTheme){
			if(currentTheme==Theme.none){
				currentTheme=nextTheme;
				themes[currentTheme].source.gain=musicGain;
				themes[currentTheme].play();
			}else{
				themeGain-=(1.0f/fadeOutTime)*dt;
				if(themeGain<=0.0f){
					themeGain=1.0f;
					themes[currentTheme].stop();
					themes[currentTheme].source.gain=musicGain;
					currentTheme=nextTheme;
					if(currentTheme!=Theme.none) themes[currentTheme].play();
				}else themes[currentTheme].source.gain=themeGain*musicGain;
			}
		}
		if(currentTheme!=Theme.none) themes[currentTheme].feed();
	}
	void release(){
		foreach(ref theme;themes) theme.release();
		sacrifice1.release();
		defeat.release();
		victory.release();
	}
}
