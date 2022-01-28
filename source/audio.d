// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

module audio;
import derelict.openal.al;
import derelict.mpg123;
import core.stdc.stdio;
import dlib.math;
import std.exception;
import util,samp;

__gshared ALCdevice* device;
__gshared ALCcontext* context;
bool loadAudio(){
	import derelict.util.exception: DerelictException;
	try{
		DerelictAL.load();
		device=alcOpenDevice(null);
		if(!device) return false;
		context=alcCreateContext(device,null);
		auto ok=alcMakeContextCurrent(context);
		if(!ok) return false;
		listenerPosition=Vector3f(0.0f,0.0f,0.0f);
		listenerVelocity=Vector3f(0.0f,0.0f,0.0f);
		listenerOrientation=Quaternionf.identity();
		DerelictMPG123.load();
		mpg123_init();
		return true;
	}catch(DerelictException){
		return false;
	}
}
void unloadAudio(){
	if(!device) return;
	alcMakeContextCurrent(null);
	alcDestroyContext(context);
	alcCloseDevice(device);
	device=null;
	context=null;
}
private{
	@property void listenerPosition(Vector3f position){
		alListenerfv(AL_POSITION,position.arrayof.ptr);
	}
	@property void listenerVelocity(Vector3f velocity){
		alListenerfv(AL_VELOCITY,velocity.arrayof.ptr);
	}
	@property void listenerOrientation(Quaternionf orientation){
		Vector3f[2] atUp=[rotate(orientation,Vector3f(0.0f,0.0f,-1.0f)),rotate(orientation,Vector3f(0.0f,1.0f,0.0f))];
		alListenerfv(AL_ORIENTATION,atUp[0].arrayof.ptr);
	}
}

struct Buffer{
	ALuint id=-1;
	void release(){ if(device&&alIsBuffer(id)){ alDeleteBuffers(1,&id); id=-1; } } // TODO: do this better?
}

Buffer makeBuffer(Samp samp){
	Buffer buffer;
	if(!device) return buffer;
	alGenBuffers(1,&buffer.id);
	alGetError();
	if(alGetError()==AL_NO_ERROR)
		alBufferData(buffer.id,AL_FORMAT_MONO16,samp.data.ptr,cast(int)samp.data.length,samp.header.sampleRate);
	return buffer;
}

struct Source{
	ALuint id=-1;
	@property ALenum state(){
		ALenum result;
		alGetSourcei(id,AL_SOURCE_STATE,&result);
		return result;
	}
	@property bool isPlaying(){ return state==AL_PLAYING; }
	@property bool isInitial(){ return state==AL_INITIAL; }
	@property void pitch(float p){ alSourcef(id,AL_PITCH,p); }
	@property void gain(float g){ alSourcef(id,AL_GAIN,g); }
	@property void position(Vector3f pos){ alSourcefv(id,AL_POSITION,pos.arrayof.ptr); }
	@property void velocity(Vector3f vel){ alSourcefv(id,AL_VELOCITY,vel.arrayof.ptr); }
	@property void looping(bool lp){ alSourcei(id,AL_LOOPING,lp?AL_TRUE:AL_FALSE); }
	@property Buffer buffer(){ ALint bid; alGetSourcei(id,AL_BUFFER,&bid); return Buffer(bid); }
	@property void buffer(Buffer buffer){ alSourcei(id,AL_BUFFER,buffer.id); }
	void play(){ alSourcePlay(id); }
	void pause(){ alSourcePause(id); }
	void stop(){ alSourceStop(id); }
	void release(){ if(device&&alIsSource(id)){ alDeleteSources(1,&id); id=-1; } } // TODO: do this better?
}

Source makeSource(){
	Source source;
	if(!device) return source;
	alGenSources(1,&source.id);
	alGetError();
	if(alGetError()==AL_NO_ERROR){
		source.pitch=1.0f;
		source.gain=1.0f;
		source.position=Vector3f(0.0f,0.0f,0.0f);
		source.velocity=Vector3f(0.0f,0.0f,0.0f);
		source.looping=false;
	}
	return source;
}

struct MP3{
	ALuint[4] buffer;
	enum byteRate=44100*2*2;
	enum chunkSize=byteRate; // one second of playback
	Source source;
	mpg123_handle* handle;
	this(string filename){
		alGenBuffers(buffer.length,buffer.ptr);
		source=makeSource();
		int err;
		handle=mpg123_new(null,&err);
		mpg123_format_none(handle);
		mpg123_format(handle,44100,2,mpg123_enc_enum.MPG123_ENC_SIGNED_16);
		import std.string:toStringz;
		mpg123_open(handle,filename.toStringz);
		initialize();
	}
	private bool read(ALuint buffer){
		ubyte[chunkSize] mp3data;
		size_t done;
		int err=mpg123_read(handle,mp3data.ptr,chunkSize,&done);
		bool finished=err==MPG123_DONE;
		if(finished) mpg123_seek(handle,0,SEEK_SET);
		alBufferData(buffer,AL_FORMAT_STEREO16,mp3data.ptr,cast(int)done,44100);
		return finished;
	}
	void initialize(){
		foreach(i;0..buffer.length) read(buffer[i]);
		alSourceQueueBuffers(source.id,buffer.length,buffer.ptr);		
	}
	void feed(){
		ALint processed;
		alGetSourcei(source.id,AL_BUFFERS_PROCESSED,&processed);
		foreach(_;0..processed){
			ALuint current;
			alSourceUnqueueBuffers(source.id,1,&current);
			read(current);
			alSourceQueueBuffers(source.id,1,&current);
		}
	}
	void play(){
		source.play();
	}
	void pause(){
		source.pause();
	}
	void stop(){
		source.stop();
		rewind();
	}
	void rewind(){
		mpg123_seek(handle,0,SEEK_SET);
		ALint queued;
		alGetSourcei(source.id,AL_BUFFERS_QUEUED,&queued);
		for(ALuint dummy;queued>0;queued--)
			alSourceUnqueueBuffers(source.id,1,&dummy);
		initialize();
	}
	void release(){
		if(!handle) return;
		alDeleteBuffers(buffer.length,buffer.ptr);
		source.release();
		mpg123_close(handle);
		mpg123_delete(handle);
		handle=null;
	}
	~this(){ release(); }
}

void testAudio(){
	auto sample=loadSAMP("extracted/sounds/SFX_.WAD!/ambi.FLDR/afir.SAMP");
	auto buffer=makeBuffer(sample);
	auto source=makeSource();
	source.looping=true;
	source.buffer=buffer;
	source.play();
	scope(exit){
		source.release();
		buffer.release();
	}
	auto mp3=MP3("extracted/music/stratos_normal.mp3");
	mp3.play();
	while(true){
		import core.thread;
		mp3.feed();
		Thread.sleep(dur!"msecs"(500));
	}
}
