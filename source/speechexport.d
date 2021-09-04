import std.stdio, std.string, std.algorithm, std.exception;
import trig, text_, samp, sacobject, state, app, options, util;

void exportSpeech(B)(ref Options options){
	if(!(options.map.endsWith(".scp")||options.map.endsWith(".HMAP"))){
		auto folder=options.map;
		scope(exit) options.map=folder;
		import std.file;
		foreach(file;dirEntries(folder,"*.scp",SpanMode.depth)){
			writeln("handling map: ",file);
			options.map=file;
			exportSpeech!B(options);
		}
		return;
	}
	auto state=prepareGameState!B(options);
	auto triggers=state.triggers;
	import nttData,text_,std.path;
	auto folder=dirName(state.current.map.hmap);
	auto texts=makeByTag!loadText(options.enableReadFromWads,[buildPath(folder,"ENGL.LANG","TRIG.FLDR")],"TEXT");
	static ubyte[] loadWAV(string filename){ return readFile(filename)[32..$]; }
	auto samps=makeByTag!loadWAV(options.enableReadFromWads,[buildPath(folder,"SAMP.FLDR")],"SAMP");
	auto sampTexts=makeByTag!loadText(options.enableReadFromWads,[buildPath(folder,"SAMP.FLDR")],"TEXT");
	/*static foreach(alias x;TrigAstNodes){
		static if([__traits(allMembers,x)].canFind!(x=>x.startsWith("samp")))
			static if(is(mixin(x):TrigAction))
				pragma(msg,x," ",__traits(identifier,x.tupleof[0]));
	}*/
	void recordSpeech(string name,char[4] sample,char[4] text){
		if(name=="(Singleplayer Wizard)") name="Player wizard";
		if(name=="(Current Side's Wizard") name="Current wizard";
		auto theSample=samps[sample];
		auto theText=texts.get(text,null);
		bool success=!name.among("unknown","failed")&&theText;
		//writeln(name,", ",sample,", \"",texts.get(text,"<no text>"),"\"");
		import std.file;
		import std.digest.sha;
		string subfoldername;
		string sampFilename;
		string textFilename;
		if(auto sampText=sampTexts.get(sample,null)){
			subfoldername=sampFilename=textFilename=sampText;
		}else{
			ubyte[5] sampHash=sha1Of(theSample)[0..5];
			ubyte[5] textHash=sha1Of(theText)[0..5];
			ubyte[10] subfolder=sampHash[]~textHash[];
			subfoldername=toHexString(subfolder).idup;
			sampFilename=toHexString(sampHash).idup;
			textFilename=toHexString(textHash).idup;
		}
		auto folder=buildPath(options.exportFolder,success?"done":"todo",name,subfoldername);
		mkdirRecurse(folder);
		theSample.toFile(buildPath(folder,sampFilename~".wav"));
		if(theText) theText.toFile(buildPath(folder,textFilename~".txt"));
	}
	void recordSpeechUnknown(char[4] sample,char[4] text){
		if(auto name=sample in sampTexts){
			if((*name).canFind("mit_"))
				return recordSpeech(SacObject!B.get(WizardTag.mithras).name,sample,text);
			if((*name).canFind("zyz_"))
				return recordSpeech(SacObject!B.get(SpellTag.zyzyx).name,sample,text);
		}
		recordSpeech("unknown",sample,text);
	}
	void recordSpeechWithCreature(TrigCreature creature,char[4] sample,char[4] text){
		auto id=triggers.associatedId(creature.id);
		auto name=id?state.current.movingObjectById!((ref obj)=>obj.sacObject.name,()=>"failed")(id):"failed";
		if(name=="failed")
			if(auto str=creature.nttToString(creature.id))
				name=str;
		recordSpeech(name,sample,text);
	}
	void recordSpeechWithGod(TrigGod god,char[4] sample,char[4] text){
		return recordSpeech(godToString(god),sample,text);
	}
	void recordSpeechWithActor(TrigActor actor,char[4] sample,char[4] text){
		if(auto creature=cast(TrigActorCreature)actor)
			return recordSpeechWithCreature(creature.creature,sample,text);
		if(auto nameText=cast(TrigActorNameText)actor)
			return recordSpeech(texts.get(nameText.text,"failed"),sample,text);
		if(auto playerWizard=cast(TrigActorNamePlayerWizard)actor)
			return recordSpeech("Player wizard",sample,text);
		if(auto god=cast(TrigActorGod)actor)
			return recordSpeechWithGod(god.god,sample,text);
		enforce(0,"unsupported actor");
		assert(0);
	}
	void recordSpeechWithNarrator(TrigNarrator narrator,char[4] sample,char[4] text){
		return recordSpeech(narratorToString(narrator),sample,text);
	}
	class SpeechVisitor:TrigVisitorRecursive{
		void handle(TrigAction action){
			// writeln(action);
		}
		override void accept(TrigPlaySampleAction action){
			// unknown
			handle(action);
			recordSpeechUnknown(action.sample,"\0\0\0\0");
		}
		override void accept(TrigSpeechWithTextAction action){
			// actor
			handle(action);
			if(auto sample=cast(TrigWithSample)action.sampleSpec)
				return recordSpeechWithActor(action.actor,sample.sample,action.text);
		}
		override void accept(TrigSpeechCreatureSpeaksSampleAction action){
			// creature
			handle(action);
			recordSpeechWithCreature(action.creature,action.sample,"\0\0\0\0");
		}
		override void accept(TrigSpeechCreatureSaysTextWithSampleAction action){
			// creature
			handle(action);
			recordSpeechWithCreature(action.creature,action.sample,action.text);
		}
		override void accept(TrigSpeechCreatureAsksTextWithSampleAction action){
			// creature
			handle(action);
			recordSpeechWithCreature(action.creature,action.sample,action.text);
		}
		override void accept(TrigSpeechCreatureExclaimsTextWithSampleAction action){
			// creature
			handle(action);
			recordSpeechWithCreature(action.creature,action.sample,action.text);
		}
		override void accept(TrigSpeechGodSaysTextWithSampleAction action){
			// god
			handle(action);
			recordSpeechWithGod(action.god,action.sample,action.text);
		}
		override void accept(TrigSpeechNarratorNarratesTextWithSampleAction action){
			// narrator
			handle(action);
			recordSpeechWithNarrator(action.narrator,action.sample,action.text);
		}
		override void accept(TrigAskTextWithSampleAction action){
			// unknown
			handle(action);
			if(auto sample=cast(TrigWithSample)action.sampleSpec)
				recordSpeechUnknown(sample.sample,action.question);
		}
		override void accept(TrigAddTextWithSampleToSpeechHistoryAction action){
			// unknown
			handle(action);
			if(auto sample=cast(TrigWithSample)action.sampleSpec)
				recordSpeechUnknown(sample.sample,action.text);
		}
		override void accept(TrigAddIntroSampleToSpeechHistoryAction action){
			// unknown
			handle(action);
			recordSpeechUnknown(action.sample,"\0\0\0\0");
		}
		alias accept=typeof(super).accept;
	}
	auto visitor=new SpeechVisitor();
	foreach(ref t;triggers.trig.triggers){
		//writeln(t);
		foreach(a;t.actions){
			a.visit(visitor);
		}
	}
}
