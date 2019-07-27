import dlib.math;
import std.container, std.algorithm: sort, swap;
import audio, samp, nttData, sacobject, maps, state;
import util;

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

enum AdvisorHelpSound:char[4]{
	altarBeingDesecrated="00DA",
	armyHasBeenSlaughtered="10DA",
	buildingUnderAttack="20DA",
	buildingInRuin="30DA",
	lowOnHealth="40DA",
	creaturesUnderAttack="50DA",
	creaturesAreDying="60DA",
	enemyWizardApproachingAltar="70DA",
	enemySighted="80DA",
	enemiesFallBeforeUs="90DA",
	invalidTarget="01DA",
	lowOnMana="11DA",
	allManahoarsSlaughtered="21DA",
	allManalithsDestroyed="31DA",
	mustBeNearEnemyAltar="51DA",
	needMoreSouls="81DA",
	outOfRange="91DA",
	sacrificeComplete="02DA",
	someoneSeeksAnAudience="12DA",
	notReady="22DA",
	wizardUnderAttack="32DA",
	desecrationInterrupted="42DA",
}

final class AudioBackend(B){
	MP3[Theme.max] themes;
	MP3 sacrifice1;
	MP3 defeat;
	MP3 victory;
	auto currentTheme=Theme.none;
	auto nextTheme=Theme.none;
	float musicGain;
	float soundGain;
	float themeGain=1.0f;
	enum _3dSoundVolumeMultiplier=6.0f;
	this(float volume,float musicVolume,float soundVolume){
		musicGain=volume*musicVolume;
		soundGain=volume*soundVolume;
		themes[Theme.battle1]=MP3("data/music/Battle 1.mp3");
		themes[Theme.battle2]=MP3("data/music/Battle 2.mp3");
		themes[Theme.battle3]=MP3("data/music/Battle 3.mp3");
		themes[Theme.battle4]=MP3("data/music/Battle 4.mp3");
		themes[Theme.battle5]=MP3("data/music/Battle 5.mp3");
		themes[Theme.losing]=MP3("data/music/Sacrifice Losing.mp3");
		themes[Theme.winning]=MP3("data/music/Sacrifice Victory.mp3");
		themes[Theme.menu]=MP3("data/music/menu.mp3");
		sacrifice1=MP3("data/music/Sacrifice 1.mp3");
		defeat=MP3("data/music/Defeat Theme.mp3");
		victory=MP3("data/music/Victory Theme.mp3");

		sounds1.reserve(20);
		sounds2.reserve(20);
		sounds3.reserve(20);
		oldSounds3.reserve(20);

		dialogSource=makeSource();
		dialogQueue.payload.reserve(5);
	}
	void setTileset(Tileset tileset){
		themes[Theme.normal]=MP3(godThemes[tileset]);
	}
	void switchTheme(Theme next){
		nextTheme=next;
	}
	enum fadeOutTime=0.5f;
	void updateTheme(float dt){
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
		if(currentTheme!=Theme.none){
			themes[currentTheme].feed();
			if(!themes[currentTheme].source.isPlaying())
				themes[currentTheme].source.play();
		}
	}

	struct BufferWithDuration{
		Buffer buffer;
		int duration;
		alias buffer this;
	}
	static BufferWithDuration[char[4]] buffers;

	static BufferWithDuration getBufferWithDuration(char[4] sound){
		if(sound in buffers) return buffers[sound];
		auto samp=loadSAMP(samps[sound]);
		auto duration=cast(int)((samp.data.length*updateFPS+samp.header.byteRate-1)/samp.header.byteRate);
		return buffers[sound]=BufferWithDuration(makeBuffer(samp),duration);
	}
	static Buffer getBuffer(char[4] sound){
		return getBufferWithDuration(sound).buffer;
	}
	static int getDuration(char[4] sound){
		return getBufferWithDuration(sound).duration;
	}

	Source dialogSource;
	struct DialogSound{
		char[4] sound;
		DialogPriority priority;
	}
	Queue!DialogSound dialogQueue;
	DialogSound currentDialogSound;
	void queueDialogSound(char[4] sound,DialogPriority priority){
		Lwhile: while(!dialogQueue.empty){
			final switch(dialogPolicy(dialogQueue.back.priority,priority)){
				case DialogPolicy.queue: break Lwhile;
				case DialogPolicy.interruptPrevious: goto case DialogPolicy.ignorePrevious;
				case DialogPolicy.ignorePrevious: dialogQueue.popBack(); break;
				case DialogPolicy.ignoreCurrent: return;
			}
		}
		if(currentDialogSound!=DialogSound.init){
			final switch(dialogPolicy(currentDialogSound.priority,priority)){
				case DialogPolicy.queue: break;
				case DialogPolicy.interruptPrevious:
					dialogSource.stop();
					currentDialogSound=DialogSound.init;
					break;
				case DialogPolicy.ignorePrevious: break;
				case DialogPolicy.ignoreCurrent: return;
			}
		}
		dialogQueue.push(DialogSound(sound,priority));
	}

	struct Sound0{
		Source source;
	}
	Array!Sound0 sounds0;
	void playSound(char[4] sound,float gain=1.0f){
		auto source=makeSource();
		source.gain=soundGain*gain;
		source.buffer=getBuffer(sound);
		source.play();
		sounds0~=Sound0(source);
	}
	struct Sound1{
		Source source;
		Vector3f position;
	}
	Array!Sound1 sounds1;
	void playSoundAt(char[4] sound,Vector3f position,float gain=1.0f){
		auto source=makeSource();
		source.gain=soundGain*gain*_3dSoundVolumeMultiplier;
		source.buffer=getBuffer(sound);
		sounds1~=Sound1(source,position);
	}
	struct Sound2{
		Source source;
		int id;
	}
	Array!Sound2 sounds2;
	void playSoundAt(char[4] sound,int id,float gain=1.0f)in{
		assert(id>0);
	}do{
		auto source=makeSource();
		source.gain=soundGain*gain*_3dSoundVolumeMultiplier;
		source.buffer=getBuffer(sound);
		sounds2~=Sound2(source,id);
	}
	struct LoopSound{
		Source source;
		int id;
	}
	Array!LoopSound sounds3;
	void loopSoundAt(Buffer buffer,int id,float gain=1.0f){
		auto source=makeSource();
		source.gain=soundGain*gain*_3dSoundVolumeMultiplier;
		source.buffer=buffer;
		source.looping=true;
		sounds3~=LoopSound(source,id);
	}
	void loopSoundAt(char[4] sound,int id,float gain=1.0f){
		loopSoundAt(getBuffer(sound),id,gain);
	}
	void loopingSoundSetup(StaticObject!B object){
		auto sound=object.sacObject.loopingSound;
		if(sound!="\0\0\0\0") loopSoundAt(sound,object.id);
	}
	void deleteLoopingSounds(){
		foreach(i;0..sounds3.length)
			sounds3[i].source.release();
		sounds3.length=0;
	}
	void stopSoundsAt(int id){ // TODO: linear search good?
		for(int i=0;i<sounds2.length;){
			if(sounds2[i].id==id){
				sounds2[i].source.release();
				swap(sounds2[i],sounds2[$-1]);
				sounds2.length=sounds2.length-1;
				continue;
			}
			i++;
		}
		for(int i=0;i<sounds3.length;){
			if(sounds3[i].id==id){
				sounds3[i].source.release();
				swap(sounds3[i],sounds3[$-1]);
				sounds3.length=sounds3.length-1;
				continue;
			}
			i++;
		}
	}

	Array!LoopSound oldSounds3;
	void updateAudioAfterRollback(ObjectState!B state){
		oldSounds3.length=0;
		swap(sounds3,oldSounds3);
		sort!"a.id<b.id"(oldSounds3.data);
		static void updateLoopingSound(StaticObject!B object,AudioBackend self,ObjectState!B state){
			auto sound=object.sacObject.loopingSound;
			if(sound=="\0\0\0\0"||!object.isActive(state)) return;
			size_t l=-1,r=self.oldSounds3.length;
			Buffer buffer=self.getBuffer(sound);
			while(l+1<r){
				auto m=l+(r-l)/2;
				if(self.oldSounds3[m].id<object.id) l=m;
				else if(self.oldSounds3[m].id!=object.id) r=m;
				else if(self.oldSounds3[m].source.id!=0){
					auto oldBuffer=self.oldSounds3[m].source.buffer;
					if(oldBuffer==buffer){
						self.sounds3~=self.oldSounds3[m];
						self.oldSounds3[m].source.id=0;
						return;
					}else break;
				}else break;
			}
			self.loopSoundAt(buffer,object.id);
		}
		state.eachStatic!updateLoopingSound(this,state);
		foreach(i;0..oldSounds3.length)
			if(oldSounds3[i].source.id!=0)
				oldSounds3[i].source.release();
	}

	void updateSounds(float dt,Matrix4f viewMatrix,ObjectState!B state){
		if(!dialogSource.isPlaying){
			currentDialogSound=DialogSound.init;
			if(!dialogQueue.empty){
				currentDialogSound=dialogQueue.removeFront();
				auto sound=currentDialogSound.sound;
				auto buffer=getBuffer(sound);
				dialogSource.gain=soundGain;
				dialogSource.buffer=buffer;
				dialogSource.play();
			}
		}
		for(int i=0;i<sounds0.length;){
			if(!sounds0[i].source.isPlaying){
				swap(sounds0[i],sounds0[$-1]);
				sounds0[$-1].source.release();
				sounds0.length=sounds0.length-1;
				continue;
			}
			i++;
		}
		for(int i=0;i<sounds1.length;){
			sounds1[i].source.position=sounds1[i].position*viewMatrix;
			if(sounds1[i].source.isInitial)
				sounds1[i].source.play();
			else if(!sounds1[i].source.isPlaying){
				swap(sounds1[i],sounds1[$-1]);
				sounds1[$-1].source.release();
				sounds1.length=sounds1.length-1;
				continue;
			}
			i++;
		}
		for(int i=0;i<sounds2.length;){
			if(state.isValidId(sounds2[i].id))
				sounds2[i].source.position=state.objectById!((obj)=>obj.center)(sounds2[i].id)*viewMatrix;
			if(sounds2[i].source.isInitial){
				sounds2[i].source.play();
			}else if(!sounds2[i].source.isPlaying){
				swap(sounds2[i],sounds2[$-1]);
				sounds2[$-1].source.release();
				sounds2.length=sounds2.length-1;
				continue;
			}
			i++;
		}
		for(int i=0;i<sounds3.length;){
			if(!state.isValidId(sounds3[i].id)){
				swap(sounds3[i],sounds3[$-1]);
				sounds3[$-1].source.stop();
				sounds3[$-1].source.release();
				sounds3.length=sounds3.length-1;
				continue;
			}
			sounds3[i].source.position=state.objectById!((obj)=>obj.center)(sounds3[i].id)*viewMatrix;
			if(sounds3[i].source.isInitial)
				sounds3[i].source.play();
			i++;
		}
	}

	void update(float dt,Matrix4f viewMatrix,ObjectState!B state){
		updateTheme(dt);
		updateSounds(dt,viewMatrix,state);
	}
	void release(){
		foreach(ref theme;themes) theme.release();
		sacrifice1.release();
		defeat.release();
		victory.release();
		foreach(i;0..sounds1.length) sounds1[i].source.release();
		sounds1.length=0;
		foreach(i;0..sounds2.length) sounds2[i].source.release();
		sounds2.length=0;
		foreach(i;0..sounds3.length) sounds3[i].source.release();
		sounds3.length=0;
		foreach(k,v;buffers) v.release();

		dialogSource.release();
	}
	~this(){ release(); }
}
