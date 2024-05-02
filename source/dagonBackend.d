// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import dagon;
import dlib.math.portable;
import options,util;
import std.stdio;
import std.algorithm, std.range, std.exception, std.typecons, std.conv;
import core.time: Duration, seconds, MonoTime;

import lobby;
import sacobject, sacspell, mrmm, nttData, sacmap, levl, state, form, sacform, controller, network;
import sxsk : gpuSkinning;
import renderer,audioBackend;

final class SacScene: Scene{
	//OBJAsset aOBJ;
	//Texture txta;
	Options options;
	this(SceneManager smngr, Options options){
		super(max(1,options.width), max(1,options.height), options.scale, options.aspectDistortion, smngr);
		this.shadowMapResolution=options.shadowMapResolution;
		this.options=options;
		if(options.volume!=0.0f) initializeAudio();
	}
	FirstPersonView2 fpview;
	override void onAssetsRequest(){
		//aOBJ = addOBJAsset("../jman.obj");
		//txta = New!Texture(null);// TODO: why?
		//txta.image = loadTXTR("extracted/jamesmod/JMOD.WAD!/modl.FLDR/jman.MRMC/M001.TXTR");
		//txta.createFromImage(txta.image);
	}
	GameState!DagonBackend state;
	util.Array!(SacFormState!DagonBackend) forms;

	Controller!DagonBackend controller;
	DynamicArray!(SacObject!DagonBackend) sacs;
	RenderInfo!DagonBackend info;
	alias MouseStatus=Mouse!DagonBackend.Status;
	alias MouseLocation=Mouse!DagonBackend.Location;
	@property ref int renderSlot(){ return info.renderSlot; }
	@property ref int renderSide(){ return info.renderSide; }
	@property ref float hudScaling(){ return info.hudScaling; }
	@property ref int hudSoulFrame(){ return info.hudSoulFrame; }
	@property ref Mouse!DagonBackend mouse(){ return info.mouse; }
	@property ref Camera camera(){ return info.camera; }
	@property ref float screenScaling(){ return info.screenScaling; }
	@property ref SpellType spellbookTab(){ return info.spellbookTab; }
	Renderer!DagonBackend renderer;
	void switchSpellbookTab(SpellType newTab){
		if(spellbookTab==newTab) return;
		if(audio) audio.playSound("okub");
		spellbookTab=newTab;
	}
	void spellAdvisorHelpSpeech(SpellStatus status){
		if(!options.advisorHelpSpeech) return;
		auto priority=DialogPriority.advisorAnnoy;
		char[4] tag;
		final switch(status) with(AdvisorHelpSound){
			case SpellStatus.inexistent: return;
			case SpellStatus.disabled: return;
			case SpellStatus.invalidTarget: tag=invalidTarget; break;
			case SpellStatus.lowOnMana: tag=lowOnMana; break;
			case SpellStatus.mustBeNearBuilding: return; // (missing)
			case SpellStatus.mustBeNearEnemyAltar: tag=mustBeNearEnemyAltar; break;
			case SpellStatus.mustBeConnectedToConversion: return; // (missing)
			case SpellStatus.needMoreSouls: tag=needMoreSouls; break;
			case SpellStatus.outOfRange: tag=outOfRange; break;
			case SpellStatus.notReady: tag=notReady; break;
			case SpellStatus.ready: return;
		}
		if(audio) audio.queueDialogSound(tag,priority);
	}
	bool castSpell(SacSpell!DagonBackend spell,Target target,bool playAudio=true){
		switchSpellbookTab(spell.type);
		if(!renderer.spellbookVisible(state.current,info)) return false;
		auto status=state.current.spellStatus!false(camera.target,spell,OrderTarget(target));
		if(status!=SpellStatus.ready){
			if(playAudio) spellAdvisorHelpSpeech(status);
			return false;
		}
		controller.addCommand(Command!DagonBackend(renderSide,camera.target,spell,target));
		return true;
	}
	bool castSpell(char[4] tag,Target target,bool playAudio=true){
		return castSpell(SacSpell!DagonBackend.get(tag),target,playAudio);
	}
	void playCommandAppliedSound(){
		import std.random:uniform; // TODO: put selected spells in game state?
		auto whichClick=uniform(0,2);
		if(audio) audio.playSound(commandAppliedSoundTags[whichClick]);
	}
	void playMenuActionSound(){
		import std.random:uniform;
		auto whichSound=uniform(0,4);
		if(audio) audio.playSound(menuActionSoundTags[whichSound]);
	}
	bool selectSpell(SacSpell!DagonBackend newSpell,bool playAudio=true){
		switchSpellbookTab(newSpell.type);
		if(!renderer.spellbookVisible(state.current,info)) return false;
		if(mouse.status==MouseStatus.icon){
			if(mouse.icon==MouseIcon.spell&&mouse.spell is newSpell) return false;
			if(playAudio&&audio) audio.playSound("kabI");
		}
		auto status=state.current.spellStatus!true(camera.target,newSpell);
		if(status==SpellStatus.disabled && playAudio) playCommandAppliedSound();
		if(status!=SpellStatus.ready){
			if(playAudio) spellAdvisorHelpSpeech(status);
			return false;
		}
		if(newSpell.requiresTarget){
			playCommandAppliedSound();
			if(playAudio) playCommandAppliedSound();
			mouse.status=MouseStatus.icon;
			mouse.icon=MouseIcon.spell;
			mouse.spell=newSpell;
			return true;
		}else{
			mouse.status=MouseStatus.standard;
			return castSpell(newSpell,Target.init);
		}
	}
	bool selectSpell(char[4] tag,bool playAudio=true){
		return selectSpell(SacSpell!DagonBackend.get(tag),playAudio);
	}
	bool selectSpell(SpellType tab,int index,bool playAudio=true){
		if(!renderer.spellbookVisible(state.current,info)) return false;
		auto spells=state.current.getSpells(camera.target).filter!(x=>x.spell.type==tab);
		foreach(i,entry;enumerate(spells)) if(i==index) return selectSpell(entry.spell,playAudio);
		return false;
	}
	bool useAbility(SacSpell!DagonBackend ability,Target target,CommandQueueing queueing,bool playAudio=true){
		auto status=state.current.abilityStatus!false(renderSide,ability,OrderTarget(target));
		if(status!=SpellStatus.ready){
			if(playAudio) spellAdvisorHelpSpeech(status);
			return false;
		}
		if(queueing==CommandQueueing.none) queueing=CommandQueueing.pre;
		controller.addCommand(Command!DagonBackend(renderSide,ability,target),queueing);
		return true;
	}
	bool useAbility(char[4] tag,Target target,CommandQueueing queueing,bool playAudio=true){
		return useAbility(SacSpell!DagonBackend.get(tag),target,queueing,playAudio);
	}
	bool selectAbility(SacSpell!DagonBackend newAbility,CommandQueueing queueing,bool playAudio=true){
		if(renderSide==-1) return false;
		auto status=state.current.abilityStatus!true(renderSide,newAbility);
		if(status!=SpellStatus.ready){
			if(playAudio) spellAdvisorHelpSpeech(status);
			return false;
		}
		if(newAbility.requiresTarget){
			if(mouse.status==MouseStatus.icon){
				if(mouse.icon==MouseIcon.ability&&mouse.spell is newAbility) return false;
				if(playAudio&&audio) audio.playSound("kabI");
			}
			import std.random:uniform; // TODO: put selected spells in game state?
			auto whichClick=uniform(0,2);
			if(playAudio&&audio) audio.playSound(commandAppliedSoundTags[whichClick]);
			mouse.status=MouseStatus.icon;
			mouse.icon=MouseIcon.ability;
			mouse.spell=newAbility;
			return true;
		}else{
			return useAbility(newAbility,Target.init,queueing);
		}
	}
	void selectAbility(CommandQueueing queueing,bool playAudio=true){
		auto ability=renderer.renderedSelection.ability(state.current);
		if(!ability) return;
		selectAbility(ability,queueing,playAudio);
	}


	override void renderShadowCastingEntities3D(RenderingContext* rc){
		super.renderShadowCastingEntities3D(rc);
		if(!state) return;
		typeof(renderer).R3DOpt r3dopt={enableWidgets: options.enableWidgets};
		renderer.renderShadowCastingEntities3D(r3dopt,state.current,info,rc);
	}

	override void renderOpaqueEntities3D(RenderingContext* rc){
		if(options.testRenderDelay){
			static bool delayed=false;
			if(!delayed){
				delayed=true;
				import core.thread;
				Thread.sleep(2.seconds);
			}
		}
		super.renderOpaqueEntities3D(rc);
		if(!state) return;
		typeof(renderer).R3DOpt r3dopt={enableWidgets: options.enableWidgets};
		renderer.renderOpaqueEntities3D(r3dopt,state.current,info,rc);
	}
	override void renderTransparentEntities3D(RenderingContext* rc){
		super.renderTransparentEntities3D(rc);
		if(!state) return;
		typeof(renderer).R3DOpt r3dopt={enableWidgets: options.enableWidgets};
		renderer.renderTransparentEntities3D(r3dopt,state.current,info,rc);
	}
	override void renderEntities2D(RenderingContext* rc){
		super.renderEntities2D(rc);
		mouse.x=eventManager.mouseX/screenScaling;
		mouse.y=eventManager.mouseY/screenScaling;
		mouse.x=max(0,min(mouse.x,width-1));
		mouse.y=max(0,min(mouse.y,height-1));
		typeof(renderer).R2DOpt r2dopt={cursorSize: options.cursorSize};
		auto networkState=controller&&controller.network?controller.network.networkState:null;
		renderer.renderEntities2D(r2dopt,state?state.current:null,networkState,forms.data,info,rc);
	}

	void setState(GameState!DagonBackend state)in{
		//assert(this.state is null);
	}do{
		this.state=state;
		if(state){
			Renderer!DagonBackend.EnvOpt envOpt={sunFactor: options.sunFactor,
			                                     ambientFactor: options.ambientFactor,
			                                     enableFog: options.enableFog};
			renderer.setupEnvironment(envOpt,state.current.map);
			if(audio) audio.setTileset(state.current.map.tileset);
		}
	}

	void setController(Controller!DagonBackend controller)in{
		assert(this.state!is null&&this.state is controller.state);
	}do{
		renderSlot=controller.controlledSlot;
		renderSide=controller.controlledSide;
		this.controller=controller;
	}

	void addObject(SacObject!DagonBackend sobj,Vector3f position,Quaternionf rotation){
		auto numFrames=sobj.isSaxs?1:sobj.meshes.length;
		auto offset=0.0f;
		foreach(hitbox;sobj.hitboxes_) offset=max(offset,hitbox[1].x-hitbox[0].x);
		foreach(frame;0..numFrames){
			foreach(i;0..sobj.numParts){
				auto obj=createEntity3D();
				obj.drawable = sobj.isSaxs?cast(Drawable)sobj.saxsi.meshes[i]:cast(Drawable)sobj.meshes[frame][i];
				obj.position = position-frame*Vector3f(offset+5.0f,0.0f,0.0f);
				obj.rotation = rotation;
				obj.updateTransformation();
				obj.material=sobj.materials[i];
				obj.shadowMaterial=sobj.shadowMaterials[i];
			}
		}
		sacs.insertBack(sobj);
	}

	override void onAllocate(){
		super.onAllocate();

		ssao.enabled=options.enableSSAO;
		glow.enabled=options.enableGlow;
		glow.brightness=options.glowBrightness;
		antiAliasing.enabled=options.enableAntialiasing;

		//view = New!Freeview(eventManager, assetManager);
		auto eCamera=createEntity3D();
		eCamera.position=camera.position;
		fpview=New!FirstPersonView2(eventManager, eCamera, assetManager);
		view=fpview;
		mouse.visible=false;
		info.hudVisible=false;
		fpview.mouseFactor=0.25f;
		//auto mat = createMaterial();
		//mat.diffuse = Color4f(0.2, 0.2, 0.2, 0.2);
		//mat.diffuse=txta;

		/+auto obj = createEntity3D();
		 obj.drawable = aOBJ.mesh;
		 obj.material = mat;
		 obj.position = Vector3f(0, 1, 0);
		 obj.rotation = rotationQuaternion(Axis.x,-pi!float/2);+/

		/+if(!state){
			auto sky=createSky();
			sky.rotation=rotationQuaternion(Axis.z,pi!float)*
				rotationQuaternion(Axis.x,pi!float/2);
		}+/
		/+auto ePlane = createEntity3D();
		 ePlane.drawable = New!ShapePlane(10, 10, 1, assetManager);
		 auto matGround = createMaterial();
		 //matGround.diffuse = ;
		 ePlane.material=matGround;+/
		//sortEntities(entities3D);
		//sortEntities(entities2D);
	}

	void initialize(Options options){
		initializeMouse();
		Renderer!DagonBackend.InitOpt initOpt={
			freetypeFonts: options.freetypeFonts,
			refuseGreenSouls: options.refuseGreenSouls,
		};
		renderer.initialize(initOpt);
	}

	//@property float hudScaling(){ return height/480.0f; }
	struct MovementState{ // to avoid sending too many commands. TODO: react to input events instead.
		MovementDirection movement;
		RotationDirection rotation;
	}
	MovementState targetMovementState;
	void focusCamera(int target,bool reset=true){
		if(!reset&&camera.target==target) return;
		camera.target=target;
		targetMovementState=MovementState.init;
		if(!target){
			if(!mouse.menuMode){
				fpview.active=true;
				fpview.mouseFactor=0.25f;
				mouse.visible=false;
			}else oldMouseVisible=false;
			info.hudVisible=false;
			return;
		}
		alias Tuple=std.typecons.Tuple;
		auto size=state.current.movingObjectById!((obj){
			import animations:AnimationState;
			auto hitbox=obj.sacObject.hitbox(Quaternionf.identity(),AnimationState.stance1,0);
			return hitbox[1]-hitbox[0];
		},()=>Vector3f.init)(target);
		if(isNaN(size.x)){ camera.target=0; return; }
		if(!mouse.visible) camera.pitch=-90.0f;
		if(!mouse.menuMode){
			fpview.active=false;
			mouse.visible=true;
		}else oldMouseVisible=true;
		info.hudVisible=true;
		import std.typecons;
		auto width=size.x,depth=size.y,height=size.z;
		height=max(height,1.5f);
		camera.distance=0.6f+2.32f*height;
		camera.distance=max(camera.distance,4.5f);
		camera.floatingHeight=1.75f*height-1.15f;
		camera.focusHeight=camera.floatingHeight-0.3f*(height-1.0f);
		updateCameraPosition(Duration.zero,true,false);
	}

	Vector3f getCameraDisplacement(Vector3f position){
		Vector3f result=Vector3f(0.0f,0.0f,0.0f);
		if(state) foreach(ref screenShake;state.current.obj.opaqueObjects.effects.screenShakes){
			result+=screenShake.getDisplacement(position);
		}
		return result;
	}

	void positionFPCamera(){
		camera.width=width;
		camera.height=height;
		info.windowHeight=eventManager.windowHeight;
		info.hudScaling=info.height/480.0f;
		fpview.camera.position=camera.position;
		fpview.camera.eyePosition=Vector3f(0.0f,0.0f,1.0f)+getCameraDisplacement(camera.position);
		fpview.camera.turn=camera.turn;
		fpview.camera.pitch=camera.pitch;
		fpview.camera.roll=camera.roll;
		fpview.camera.pitchOffset=camera.pitchOffset;
	}

	void positionCamera(){
		if(camera.target){
			import std.typecons: Tuple, tuple;
			static Tuple!(Vector3f,float) computePosition(B)(MovingObject!B obj,float turn,Camera camera,ObjectState!B state){
				auto zoom=camera.zoom;
				// TODO: distanceFactor to depend on height as well: this is too far for Sorcha and too close for Marduk
				auto distanceFactor=0.6+3.13f*zoom;
				auto heightFactor=0.6+2.8f*zoom;
				auto focusHeightFactor=zoom>=0.125?1.0f:(0.75+0.25f*zoom/0.125f);
				camera.focusHeight*=focusHeightFactor;
				auto distance=camera.distance*distanceFactor;
				auto height=camera.floatingHeight*heightFactor;
				auto focusHeight=camera.focusHeight;
				auto position=obj.position+rotate(rotationQuaternion(Axis.z,-degtorad(turn)),Vector3f(0.0f,-1.0f,0.0f))*distance;
				position.z=(obj.position.z-state.getHeight(obj.position)+state.getHeight(position))+height;
				auto pitchOffset=atan2(position.z-(obj.position.z+focusHeight),(obj.position.xy-position.xy).length);
				return tuple(position,pitchOffset);
			}
			auto posPitch=state.current.movingObjectById!(
				computePosition,function Tuple!(Vector3f,float)(){ assert(0); }
			)(camera.target,camera.turn,camera,state.current);
			camera.position=posPitch[0];
			camera.pitchOffset=radtodeg(posPitch[1]);
		}
		positionFPCamera();
	}

	void updateCameraTarget(){
		if(camera.target!=0&&(!state||!state.current.isValidTarget(camera.target,TargetType.creature)))
			focusCamera(0);
	}

	void updateCameraPosition(Duration dt,bool center,bool uncenter){
		if(center) camera.centering=true;
		if(uncenter) camera.centering=false;
		updateCameraTarget();
		while(camera.pitch>180.0f) camera.pitch-=360.0f;
		while(camera.pitch<-180.0f) camera.pitch+=360.0f;
		while(camera.turn>180.0f) camera.turn-=360.0f;
		while(camera.turn<-180.0f) camera.turn+=360.0f;
		if(camera.target!=0){
			if(camera.centering){
				auto newTurn=state.current.movingObjectById!(
					(obj)=>-radtodeg(obj.creatureState.facing),
					function float(){ assert(0); }
				)(camera.target);
				auto diff=newTurn-camera.turn;
				while(diff>180.0f) diff-=360.0f;
				while(diff<-180.0f) diff+=360.0f;
				auto speed=radtodeg(camera.rotationSpeed)*(dt.total!"hnsecs"*1e-7);
				if(dt==Duration.zero||abs(diff)<speed){
					camera.turn=newTurn;
					camera.centering=false;
				}else camera.turn+=sign(diff)*speed;
			}
		}
		if(camera.targetZoom!=camera.zoom){
			static import std.math;
			static immutable float factor=std.math.exp(2.0f*std.math.log(0.01f)/updateFPS);
			camera.zoom=(1-factor)*camera.targetZoom+factor*camera.zoom;
			camera.zoom=max(0.0f,min(camera.zoom,1.0f));
		}
		positionCamera();
	}
	float speed = 100.0f;

	int[512] keyDown,keyUp;
	int[255] mouseButtonDown,mouseButtonUp;

	override void onTextInput(dchar d){
		if(!mouse.menuMode) return;
		auto formIndex=0;
		ref form(){ return forms[formIndex]; }
		ref activeElement(){ return form.activeElement; }
		if(mouse.target.type==TargetType.formElement){
			formIndex=mouse.target.formIndex;
		}else if(forms.length!=1) return; // TODO?
		if(d!=' ') form.focusType(.form.ElementType.entrybox);
		if(activeElement.type==.form.ElementType.entrybox){
			activeElement.enterDchar!DagonBackend(d);
		}
	}
	override void onKeyDown(int key){ keyDown[key]+=1; }
	override void onKeyUp(int key){ keyUp[key]+=1; }
	override void onMouseButtonDown(int button){ mouseButtonDown[button]+=1; }
	override void onMouseButtonUp(int button){ mouseButtonUp[button]+=1; }

	void stopMoving(){
		auto cameraFacing=-degtorad(camera.turn);
		if(state&&camera.target){
			if(targetMovementState.movement!=MovementDirection.none){
				targetMovementState.movement=MovementDirection.none;
				controller.addCommand(Command!DagonBackend(CommandType.stopMoving,renderSide,camera.target,camera.target,Target.init,cameraFacing));
			}
			if(targetMovementState.rotation!=RotationDirection.none){
				targetMovementState.rotation=RotationDirection.none;
				controller.addCommand(Command!DagonBackend(CommandType.stopTurning,renderSide,camera.target,camera.target,Target.init,cameraFacing));
			}
		}
	}

	bool oldMouseVisible;
	void enableMenu(){
		if(mouse.menuMode) return;
		stopMoving();
		oldMouseVisible=mouse.visible;
		mouse.visible=true;
		fpview.active=false;
		mouse.menuMode=true;
		eventManager.enableTextInput();
	}
	void disableMenu(){
		if(!mouse.menuMode) return;
		eventManager.disableTextInput();
		mouse.menuMode=false;
		if(!oldMouseVisible){
			mouse.visible=false;
			fpview.active=true;
			fpview.mouseFactor=0.25f;
		}
	}

	void control(Duration dt){
		if(mouse.menuMode){
			menuControl(dt);
		}else{
			gameControl(dt);
		}
		keyDown[]=0;
		keyUp[]=0;
		mouseButtonDown[]=0;
		mouseButtonUp[]=0;
	}

	static struct ChatOptions{
		bool[4] checked=true;
	}
	ChatOptions chatOptions;
	void updateForm(int formIndex,int elementIndex){
		if(formIndex>=forms.length) return;
		switch(forms[formIndex].sacForm.tag){
			case "thci": // non-observer ingame chat
				if(2<=elementIndex&&elementIndex<=5){
					chatOptions.checked[elementIndex-2]=forms[formIndex].elements[elementIndex].checked;
					if(elementIndex==5) foreach(i;0..3) chatOptions.checked[i]=forms[formIndex].elements[2+i].checked=chatOptions.checked[$-1];
					else forms[formIndex].elements[5].checked=chatOptions.checked[$-1]=all(chatOptions.checked[0..$-1]);
				}
				break;
			default: break;
		}
	}

	void menuControl(Duration dt){
		enforce(forms.length);
		auto formIndex=0;
		ref form(){ return forms[formIndex]; }
		ref activeElement(){ return form.activeElement; }
		if(mouse.target.type==TargetType.formElement){
			formIndex=mouse.target.formIndex;
			auto elementIndex=mouse.target.elementIndex;
			ref element(){ return form.elements[elementIndex]; }
			auto mbDown=mouseButtonDown[MB_LEFT]+mouseButtonDown[MB_MIDDLE]+mouseButtonDown[MB_RIGHT];
			auto mbUp=mouseButtonUp[MB_LEFT]+mouseButtonUp[MB_MIDDLE]+mouseButtonUp[MB_RIGHT];
			if(mbDown!=0){
				form.activeIndex=mouse.target.elementIndex;
			}
			if(mbUp!=0){
				if(elementIndex==form.activeIndex){
					if(element.activate()){
						playMenuActionSound();
						updateForm(formIndex,form.activeIndex);
					}
				}
			}
		}else if(forms.length!=1) return; // TODO?
		import hotkeys_;
		Modifiers modifiers;
		if(eventManager.keyPressed[KEY_LCTRL]||options.hotkeys.capsIsCtrl&&eventManager.keyPressed[KEY_CAPSLOCK]) modifiers|=Modifiers.ctrl;
		if(eventManager.keyPressed[KEY_LSHIFT]) modifiers|=Modifiers.shift;
		if(modifiers&Modifiers.ctrl){
			foreach(_;0..keyDown[KEY_V]){
				if(SDL_HasClipboardText()){
					auto str=SDL_GetClipboardText();
					scope(exit) SDL_free(str);
					import std.uni: normalize, NFKC;
					import core.stdc.string: strlen;
					auto view=normalize!NFKC(str[0..strlen(str)]); // TODO: would be better without GC leak
					form.focusType(.form.ElementType.entrybox);
					if(activeElement.type==.form.ElementType.entrybox)
						foreach(dchar d;view) activeElement.enterDchar!DagonBackend(d);
				}
			}
		}
		foreach(_;0..keyDown[KEY_TAB]) form.tabActive();
		foreach(_;0..keyDown[KEY_SPACE]){
			if(activeElement.activate()){
				playMenuActionSound();
				updateForm(formIndex,form.activeIndex);
			}
		}
		foreach(_;0..keyDown[KEY_RETURN]){
			if(form.returnIsOk&&form.activeIndex!=form.escapeIndex) form.activeOk();
			if(activeElement.activate()){
				playMenuActionSound();
				updateForm(formIndex,form.activeIndex);
			}
		}
		foreach(_;0..keyDown[KEY_ESCAPE]){
			if(form.activeEscape()&&activeElement.activate()){
				playMenuActionSound();
				updateForm(formIndex,form.activeIndex);
			}
		}
		if(keyDown[KEY_BACKSPACE]!=0||keyDown[KEY_DELETE]!=0||keyDown[KEY_LEFT]!=0||keyDown[KEY_RIGHT]!=0){
			form.focusType(.form.ElementType.entrybox);
			if(activeElement.type==.form.ElementType.entrybox){
				foreach(_;0..keyDown[KEY_BACKSPACE])
					activeElement.deleteDchar!DagonBackend();
				foreach(_;0..keyDown[KEY_DELETE])
					activeElement.deleteDcharForward!DagonBackend();
				foreach(_;0..keyDown[KEY_LEFT])
					activeElement.moveLeft!DagonBackend();
				foreach(_;0..keyDown[KEY_RIGHT])
					activeElement.moveRight!DagonBackend();
			}
		}
		if(form.sacForm.isChatForm){
			if(state&&activeElement.checked){
				if(activeElement.id=="dnes"){
					auto defaultIndex=form.defaultIndex;
					enforce(0<=defaultIndex&&defaultIndex<form.elements.length);
					enforce(form.elements[defaultIndex].id=="thci");
					if(form.elements[defaultIndex].textInput.length!=0){
						string name=null;
						if(!observing){
							if(!observing){
								if(camera.target&&state.current.isValidTarget(camera.target))
									name=getCreatureName(camera.target,state.current);
								if(!name.length) name=getSideName(renderSide,state.current);
							}
						}else name=options.name;
						if(!name.length) name="Anonymous";
						int slotFilter=controller.slotFilter(chatOptions.checked[0],chatOptions.checked[1],chatOptions.checked[2]);
						auto controlledSlot=controller?controller.controlledSlot:0;
						auto chatMessage=makeChatMessage!DagonBackend(controlledSlot,slotFilter,ChatMessageType.standard,name,form.elements[defaultIndex].textInput.data[],state.current.frame);
						controller.addCommand(Command!DagonBackend(observing?-1:controller.controlledSide,move(chatMessage)));
					}
					forms.length=0;
					disableMenu();
				}else if(activeElement.id=="lcnc"){
					forms.length=0;
					disableMenu();
				}
			}
		}
	}

	Target xmenuTarget(){
		return Target(TargetType.xmenu,0,Vector3f.init,TargetLocation.xmenu);
	}
	char[4] xmenuCenter(){
		auto xtarget=mouse.xmenuTarget;
		import xmnu;
		switch(xtarget.type) with(TargetType) with(XmnuCenterTag){
			case terrain: return move;
			case creature,building:
				auto otarget=OrderTarget(xtarget);
				auto summary=otarget.summarize(renderSide,state.current);
				if(!(summary&TargetFlags.untargetable)){
					if(summary&TargetFlags.corpse){
						return guard;
					}else if(summary&TargetFlags.enemy){
						return attack;
					}else if(summary&TargetFlags.manafount){
						return manalith;
					}else{
						return guard;
					}
				}
				goto default;
				case soul:
					final switch(color(xtarget.id,renderSide,state.current)){
						case SoulColor.blue:
							return move;
						case SoulColor.red,SoulColor.green:
							return convert;
					}
				default: return none;

		}
	}
	int xmnuSoundFrame=-updateFPS;
	enum xmnuSoundGap=updateFPS/2;
	void showXmenu(){
		if(mouse.xmenuVisible) return;
		mouse.xmenuVisible=true;
		mouse.xmenuOffsetX=mouse.x;
		mouse.xmenuOffsetY=mouse.y;
		mouse.xmenuMiddleTargetId=mouse.xmenuTargetId;
		renderer.xmenuTargetId=mouse.xmenuTargetId;
	}
	void hideXmenu(){
		if(!mouse.xmenuVisible) return;
		mouse.xmenuVisible=false;
		mouse.status=MouseStatus.standard;
		mouse.xmenuTarget=Target.init;
		mouse.xmenuTargetId="\0\0\0\0";
		mouse.xmenuCenterTargetId="\0\0\0\0";
		mouse.xmenuMiddleTargetId="\0\0\0\0";
		mouse.xmenuOffsetX=mouse.xmenuOffsetY=0.0f;
		mouse.xmenuFrame=mouse.frame;
	}
	void updateXmenu(){
		if(mouse.status!=MouseStatus.xmenu){
			hideXmenu();
			return;
		}
		float size=32.0f*hudScaling;
		bool xmenuShouldBeVisible=mouse.frame-mouse.xmenuFrame>=options.xmenuTime;
		if(xmenuShouldBeVisible) showXmenu();
		else hideXmenu();
		void playXmenuSound(){
			if(mouse.frame-xmnuSoundFrame>=xmnuSoundGap){
				if(audio) audio.playSound("unmx");
				xmnuSoundFrame=mouse.frame;
			}
		}
		char[4] transformTag(char[4] tag){
			import xmnu:XmnuTag;
			if(tag==XmnuTag.center) return mouse.xmenuCenterTargetId;
			return tag;
		}
		if(!mouse.xmenuVisible){
			if(mouse.xmenuTargetId!="\0\0\0\0"){
				float scale=options.xmenuHiddenScale;
				auto sacXmenu=renderer.sacXmenu;
				import xmnu;
				auto xmnux=sacXmenu.get(mouse.xmenuTargetId);
				mouse.xmenuOffsetX+=eventManager.mouseRelX/scale;
				mouse.xmenuOffsetY+=eventManager.mouseRelY/scale;
				int next=-1;
				if(abs(mouse.xmenuOffsetX)>=abs(mouse.xmenuOffsetY)){
					if(abs(mouse.xmenuOffsetX)>=0.5f*size){
						if(mouse.xmenuOffsetX<0.0f){
							next=xmnux.next[Xmnl.Dir.left];
						}else{
							next=xmnux.next[Xmnl.Dir.right];
						}
						mouse.xmenuOffsetX=mouse.xmenuOffsetY=0.0f;
					}
				}else{
					if(abs(mouse.xmenuOffsetY)>=0.5f*size){
						if(mouse.xmenuOffsetY<0.0f){
							next=xmnux.next[Xmnl.Dir.up];
						}else{
							next=xmnux.next[Xmnl.Dir.down];
						}
						mouse.xmenuOffsetX=mouse.xmenuOffsetY=0.0f;
					}
				}
				if(next!=-1){
					mouse.xmenuTargetId=transformTag(sacXmenu.entries[next].xmnu.tag);
					playXmenuSound();
				}
			}
		}else{
			if(renderer.xmenuTargetId!=mouse.xmenuTargetId){
				if(mouse.xmenuTargetId!="\0\0\0\0")
					mouse.xmenuMiddleTargetId=mouse.xmenuTargetId;
				auto newTargetId=renderer.xmenuTargetId;
				if(newTargetId!=mouse.xmenuTargetId){
					if(mouse.xmenuMiddleTargetId!="\0\0\0\0"){
						import xmnu;
						auto sacXmenu=renderer.sacXmenu;
						auto xmnux=sacXmenu.get(mouse.xmenuMiddleTargetId);
						auto up=xmnux.next[Xmnl.Dir.up];
						if(up!=-1&&transformTag(sacXmenu.entries[up].xmnu.tag)==newTargetId){
							mouse.xmenuOffsetY-=size;
						}
						auto down=xmnux.next[Xmnl.Dir.down];
						if(down!=-1&&transformTag(sacXmenu.entries[down].xmnu.tag)==newTargetId){
							mouse.xmenuOffsetY+=size;
						}
						auto left=xmnux.next[Xmnl.Dir.left];
						if(left!=-1&&transformTag(sacXmenu.entries[left].xmnu.tag)==newTargetId){
							mouse.xmenuOffsetX-=size;
						}
						auto right=xmnux.next[Xmnl.Dir.right];
						if(right!=-1&&transformTag(sacXmenu.entries[right].xmnu.tag)==newTargetId){
							mouse.xmenuOffsetX+=size;
						}
					}
					mouse.xmenuTargetId=transformTag(newTargetId);
				}
				if(mouse.xmenuTargetId!="\0\0\0\0"&&mouse.xmenuTargetId!=mouse.xmenuMiddleTargetId){
					mouse.xmenuMiddleTargetId=mouse.xmenuTargetId;
					playXmenuSound();
				}
			}
		}
	}

	void performXmenuAction(float cameraFacing,CommandQueueing queueing){
		scope(exit) updateCursor(Duration.zero);
		if(mouse.target.type!=TargetType.xmenu){ hideXmenu(); return; }
		import xmnu;
		auto xtarget=mouse.xmenuTarget;
		auto xtargetId=mouse.xmenuTargetId;
		mouse.target=mouse.xmenuTarget;
		hideXmenu();
		if(xtargetId=="\0\0\0\0"){
			if(audio) audio.playSound("kabI");
			return;
		}
		auto xmnux=renderer.sacXmenu.get(xtargetId).xmnu;
		final switch(cast(XmnuAction)xmnux.action) with(XmnuAction){
			case abort: return;
			case moveDefault:
				if(xtarget.type==TargetType.terrain){
					controller.addCommand(Command!DagonBackend(CommandType.move,renderSide,camera.target,0,xtarget,cameraFacing),queueing);
				}else{
					auto target=Target(TargetType.terrain,0,xtarget.position,xtarget.location);
					controller.addCommand(Command!DagonBackend(CommandType.move,renderSide,camera.target,0,target,cameraFacing),queueing);
				}
				return;
			case guardDefault:
				if(xtarget.type.among(TargetType.creature,TargetType.building)){
					auto otarget=OrderTarget(xtarget);
					auto summary=otarget.summarize(renderSide,state.current);
					if(summary&TargetFlags.corpse){
						auto target=Target(TargetType.terrain,0,xtarget.position,xtarget.location);
						controller.addCommand(Command!DagonBackend(CommandType.guardArea,renderSide,camera.target,0,target,cameraFacing),queueing);
						return;
					}else{
						controller.addCommand(Command!DagonBackend(CommandType.guard,renderSide,camera.target,0,xtarget,cameraFacing),queueing);
						return;
					}
				}
				return;
			case attackDefault:
				if(xtarget.type.among(TargetType.creature,TargetType.building)){
					auto otarget=OrderTarget(xtarget);
					auto summary=otarget.summarize(renderSide,state.current);
					if(summary&TargetFlags.corpse){
					}else if(summary&TargetFlags.enemy){
						controller.addCommand(Command!DagonBackend(CommandType.attack,renderSide,camera.target,0,xtarget,cameraFacing),queueing);
						return;
					}
				}
				return;
			case spell:
				castSpell(SacSpell!DagonBackend.get(xmnux.arg),xtarget);
				return;
			case attack:
				mouse.status=MouseStatus.icon;
				mouse.icon=MouseIcon.attack;
				return;
			case guard:
				mouse.status=MouseStatus.icon;
				mouse.icon=MouseIcon.guard;
				return;
			case move:
				mouse.status=MouseStatus.icon;
				mouse.icon=MouseIcon.move;
				return;
			case retreat:
				auto target=Target(TargetType.creature,camera.target);
				controller.addCommand(Command!DagonBackend(CommandType.retreat,renderSide,camera.target,0,target,float.init));
				return;
			case ability:
				selectAbility(CommandQueueing.none);
				return;
			case formation:
				Formation formation;
				Lswitch:switch(xmnux.arg) with(FormationTag){
						import std.traits:EnumMembers;
						static foreach(alias tag;EnumMembers!FormationTag){
							case tag:
								formation=__traits(getMember,Formation,__traits(identifier,tag));
								break Lswitch;
						}
					default:
						stderr.writeln("formation not yet supported: ",xmnux.arg);
						return;
				}
				controller.addCommand(Command!DagonBackend(renderSide,camera.target,formation));
				return;
			case changeCamera:
				stderr.writeln("xmenu command not yet supported: change camera");
				return;
		}
	}

	int lastSelectedId=0,lastSelectedFrame=0;
	float lastSelectedX,lastSelectedY;
	void gameControl(Duration dt){
		auto oldMouseStatus=mouse.status;
		if(mouse.status.among(MouseStatus.standard,MouseStatus.icon)&&!mouse.dragging){
			if(renderer.isOnSpellbook(Vector2f(mouse.x,mouse.y),info)) mouse.loc=MouseLocation.spellbook;
			else if(renderer.isOnSelectionRoster(Vector2f(mouse.x,mouse.y),info)) mouse.loc=MouseLocation.selectionRoster;
			else if(renderer.isOnMinimap(Vector2f(mouse.x,mouse.y),info)) mouse.loc=MouseLocation.minimap;
			else mouse.loc=MouseLocation.scene;
		}
		updateCameraTarget();
		if(!controller) return;
		bool observing=this.observing;
		auto cameraFacing=-degtorad(camera.turn);
		import hotkeys_;
		Modifiers modifiers;
		if(eventManager.keyPressed[KEY_LCTRL]||options.hotkeys.capsIsCtrl&&eventManager.keyPressed[KEY_CAPSLOCK]) modifiers|=Modifiers.ctrl;
		if(eventManager.keyPressed[KEY_LSHIFT]) modifiers|=Modifiers.shift;
		bool ctrl=!!(modifiers&Modifiers.ctrl);
		bool shift=!!(modifiers&Modifiers.shift);
		bool pressed(int[] keyCodes){ return keyCodes.any!(key=>eventManager.keyPressed[key]);}
		if(options.testLag&&camera.target){
			static immutable commands=[CommandType.moveForward,CommandType.moveBackward,CommandType.turnLeft,CommandType.turnRight];
			import std.random;
			controller.addCommand(Command!DagonBackend(commands[uniform(0,$)],renderSide,camera.target,camera.target,Target.init,cameraFacing));
		}
		if(camera.target && !observing){
			if(pressed(options.hotkeys.moveForward) && !pressed(options.hotkeys.moveBackward)){
				if(targetMovementState.movement!=MovementDirection.forward){
					targetMovementState.movement=MovementDirection.forward;
					controller.addCommand(Command!DagonBackend(CommandType.moveForward,renderSide,camera.target,camera.target,Target.init,cameraFacing));
				}
			}else if(pressed(options.hotkeys.moveBackward) && !pressed(options.hotkeys.moveForward)){
				if(targetMovementState.movement!=MovementDirection.backward){
					targetMovementState.movement=MovementDirection.backward;
					controller.addCommand(Command!DagonBackend(CommandType.moveBackward,renderSide,camera.target,camera.target,Target.init,cameraFacing));
				}
			}else{
				if(targetMovementState.movement!=MovementDirection.none){
					targetMovementState.movement=MovementDirection.none;
					controller.addCommand(Command!DagonBackend(CommandType.stopMoving,renderSide,camera.target,camera.target,Target.init,cameraFacing));
				}
			}
			if(pressed(options.hotkeys.turnLeft) && !pressed(options.hotkeys.turnRight)){
				if(targetMovementState.rotation!=RotationDirection.left){
					targetMovementState.rotation=RotationDirection.left;
					controller.addCommand(Command!DagonBackend(CommandType.turnLeft,renderSide,camera.target,camera.target,Target.init,cameraFacing));
				}
			}else if(pressed(options.hotkeys.turnRight) && !pressed(options.hotkeys.turnLeft)){
				if(targetMovementState.rotation!=RotationDirection.right){
					targetMovementState.rotation=RotationDirection.right;
					controller.addCommand(Command!DagonBackend(CommandType.turnRight,renderSide,camera.target,camera.target,Target.init,cameraFacing));
				}
			}else{
				if(targetMovementState.rotation!=RotationDirection.none){
					targetMovementState.rotation=RotationDirection.none;
					controller.addCommand(Command!DagonBackend(CommandType.stopTurning,renderSide,camera.target,camera.target,Target.init,cameraFacing));
				}
			}
		}
		positionCamera();
		if(!state) return;
		if(mouseButtonDown[MB_LEFT]!=0){
			if(mouse.loc.among(MouseLocation.scene,MouseLocation.minimap)){
				mouse.leftButtonX=mouse.x;
				mouse.leftButtonY=mouse.y;
			}else mouse.leftButtonX=mouse.leftButtonY=float.nan;
		}
		void finishRectangleSelect(){
			mouse.status=MouseStatus.standard;
			if(renderSide==-1) return;
			TargetLocation loc;
			final switch(mouse.loc){
				case MouseLocation.scene: loc=TargetLocation.scene; break;
				case MouseLocation.minimap: loc=TargetLocation.minimap; break;
				case MouseLocation.selectionRoster,MouseLocation.spellbook: assert(0);
			}
			controller.setSelection(renderSide,camera.target,renderer.renderedSelection,loc);
			renderer.selectionUpdated=true;
		}
		if(mouse.status.among(MouseStatus.standard,MouseStatus.rectangleSelect)){
			if(eventManager.mouseButtonPressed[MB_LEFT]){
				enum rectangleThreshold=3.0f;
				if(mouse.status==MouseStatus.standard&&!fpview.active&&!mouse.dragging){
					if((abs(mouse.x-mouse.leftButtonX)>=rectangleThreshold||abs(mouse.y-mouse.leftButtonY)>=rectangleThreshold)&&
					   mouse.loc.among(MouseLocation.scene,MouseLocation.minimap))
						mouse.status=MouseStatus.rectangleSelect;
				}
			}else if(mouse.status==MouseStatus.rectangleSelect){
				finishRectangleSelect();
			}
		}
		if(mouse.status.among(MouseStatus.standard,MouseStatus.xmenu)){
			if(eventManager.mouseButtonPressed[MB_RIGHT]){
				if(mouse.status!=MouseStatus.xmenu){
					mouse.status=MouseStatus.xmenu;
					mouse.xmenuTarget=mouse.target;
					mouse.target=xmenuTarget();
					mouse.xmenuCenterTargetId=xmenuCenter();
					mouse.xmenuMiddleTargetId=mouse.xmenuCenterTargetId;
					mouse.xmenuTargetId=mouse.xmenuCenterTargetId;
					mouse.xmenuOffsetX=mouse.xmenuOffsetY=0.0f;
					mouse.targetUpdateFrame=mouse.frame;
					mouse.xmenuFrame=mouse.frame;
					updateXmenu();
				}
			}else if(mouse.status==MouseStatus.xmenu&&!mouseButtonUp[MB_RIGHT]){
				hideXmenu();
				mouse.status=MouseStatus.standard;
			}
		}
		foreach(key;KEY_1..KEY_0+1){
			foreach(_;0..keyDown[key]){
				auto type=!shift && ctrl ? CommandType.defineGroup:
					shift && !ctrl ? CommandType.addToGroup :
					CommandType.selectGroup;
				int group = key==KEY_0?9:key-KEY_1;
				if(group>=numCreatureGroups) break;
				controller.addCommand(Command!DagonBackend(type,renderSide,camera.target,group));
				if(type==CommandType.addToGroup)
					controller.addCommand(Command!DagonBackend(CommandType.automaticSelectGroup,renderSide,camera.target,group));
			}
		}
		auto queueing=shift?CommandQueueing.post:CommandQueueing.none;
		void triggerBindable(Bindable command){
			void unsupported(){
				stderr.writeln("bindable command not yet supported: ",defaultName(command));
			}
			Lswitch: final switch(command) with(Bindable){
				case unknown: break;
				// control keys
				case moveForward,moveBackward,turnLeft,turnRight,cameraZoomIn,cameraZoomOut:
				case moveUp, moveDown:
				case cameraUp, cameraDown, cameraForward, cameraBackward:
					enforce(0,"bad hotkeys");
					break;
				// orders
				case attack:
					if(mouse.status==MouseStatus.standard&&!mouse.dragging){
						mouse.status=MouseStatus.icon;
						mouse.icon=MouseIcon.attack;
					}
					break;
				case guard:
					if(mouse.status==MouseStatus.standard&&!mouse.dragging){
						mouse.status=MouseStatus.icon;
						mouse.icon=MouseIcon.guard;
					}
					break;
				case retreat:
					auto target=Target(TargetType.creature,camera.target);
					controller.addCommand(Command!DagonBackend(CommandType.retreat,renderSide,camera.target,0,target,float.init));
					break;
				case move:
					with(TargetType) if(mouse.target.type.among(terrain,creature,building,soul)){ // TODO: sky
						auto target=Target(terrain,0,mouse.target.position,mouse.target.location);
						target.position.z=state.current.getHeight(target.position);
						controller.addCommand(Command!DagonBackend(CommandType.move,renderSide,camera.target,0,target,cameraFacing),queueing);
					}
					break;
				case useAbility:
					selectAbility(CommandQueueing.none);
					break;
				case dropSoul:
					controller.addCommand(Command!DagonBackend(renderSide,camera.target));
					break;
				// miscellanneous
				case optionsMenu,skipSpeech: unsupported(); break;
				case openNextSpellTab:
					switchSpellbookTab(cast(SpellType)((spellbookTab+1)%(spellbookTab.max+1)));
					break;
				case openCreationSpells:
					switchSpellbookTab(SpellType.creature);
					break;
				case openSpells:
					switchSpellbookTab(SpellType.spell);
					break;
				case openStructureSpells:
					switchSpellbookTab(SpellType.structure);
					break;
				case quickSave,quickLoad,pause,changeCamera: unsupported(); break;
				case sendChatMessage:
					if(mouse.status==MouseStatus.standard&&!mouse.dragging&&!mouse.menuMode){
						if(observing){
							if(!options.observerChat) break;
							forms~=sacFormInstance!DagonBackend("thco");
						}else{
							auto form=sacFormInstance!DagonBackend("thci");
							void set(int i,ref ElementState e,string s){
								foreach(c;s) e.textInput~=c;
								e.textStart=0;
								e.textEnd=to!int(s.length);
								e.checked=chatOptions.checked[i];
							}
							set(0,form.elements[2],"Allies");
							set(1,form.elements[3],"Enemies");
							set(2,form.elements[4],"Observers");
							set(3,form.elements[5],"Everyone");
							forms~=.move(form);
						}
						enableMenu();
					}
					break;
				case gammaCorrectionPlus,gammaCorrectionMinus,screenShot: unsupported(); break;
				// formations
				case semicircleFormation:
					controller.addCommand(Command!DagonBackend(renderSide,camera.target,Formation.semicircle));
					break;
				case circleFormation:
					controller.addCommand(Command!DagonBackend(renderSide,camera.target,Formation.circle));
					break;
				case phalanxFormation:
					controller.addCommand(Command!DagonBackend(renderSide,camera.target,Formation.phalanx));
					break;
				case wedgeFormation:
					controller.addCommand(Command!DagonBackend(renderSide,camera.target,Formation.wedge));
					break;
				case skirmishFormation:
					controller.addCommand(Command!DagonBackend(renderSide,camera.target,Formation.skirmish));
					break;
				case lineFormation:
					controller.addCommand(Command!DagonBackend(renderSide,camera.target,Formation.line));
					break;
				case flankLeftFormation:
					controller.addCommand(Command!DagonBackend(renderSide,camera.target,Formation.flankLeft));
					break;
				case flankRightFormation:
					controller.addCommand(Command!DagonBackend(renderSide,camera.target,Formation.flankRight));
					break;
				// taunts
				case randomTaunt: unsupported(); break;
				static foreach(i;1..4+1){
					case mixin(text(`taunt`,i)):
						unsupported();
						break Lswitch;
				}
				// spells
				static foreach(i;1..11+1){
					case mixin(text(`castCreationSpell`,i)):
						selectSpell(SpellType.creature,i-1);
						break Lswitch;
				}
				static foreach(i;1..11+1){
					case mixin(text(`castSpell`,i)):
						selectSpell(SpellType.spell,i-1);
						break Lswitch;
				}
				/+static foreach(i;1..11+1){
					case mixin(text(`castStructureSpell`,i)):
						selectSpell(SpellType.structure,i-1);
						break Lswitch;
				}+/
				case castManalith,castManahoar,castSpeedUp,castGuardian,castConvert,castDesecrate,castTeleport,castHeal,castShrine:
					selectSpell(command);
					break;
				// SacEngine extensions
				case surrender:
					controller.addCommand(Command!DagonBackend(renderSide));
					break;
			}
		}
		foreach(ref hotkey;options.hotkeys[modifiers]){
			foreach(_;0..keyDown[hotkey.keycode])
				triggerBindable(hotkey.action);
		}
		mouse.additiveSelect=shift;
		renderer.selectionUpdated=false;
		if(mouse.status.among(oldMouseStatus,MouseStatus.icon)){
			foreach(_;0..mouseButtonUp[MB_LEFT]){
				bool done=true;
				if(mouse.status.among(MouseStatus.standard,MouseStatus.icon)&&!mouse.dragging){
					if(mouse.target.type==TargetType.creatureTab){
						switchSpellbookTab(SpellType.creature);
					}else if(mouse.target.type==TargetType.spellTab){
						switchSpellbookTab(SpellType.spell);
					}else if(mouse.target.type==TargetType.structureTab){
						switchSpellbookTab(SpellType.structure);
					}else if(mouse.target.type==TargetType.spell){
						selectSpell(mouse.targetSpell);
					}else if(mouse.target.type==TargetType.ability){
						selectAbility(mouse.targetSpell,queueing);
					}else done=false;
				}else done=false;
				if(!done&&!mouse.dragging) final switch(mouse.status){
					case MouseStatus.xmenu: break; // TOOD: ok?
					case MouseStatus.standard:
						if(mouse.target.type==TargetType.creature&&canSelect(renderSide,mouse.target.id,state.current)){
							auto type=mouse.additiveSelect?CommandType.toggleSelection:CommandType.select;
							auto delta=mouse.targetCacheDelta;
							if(ctrl){
								type=mouse.additiveSelect?CommandType.addAllToSelection:CommandType.selectAll;
							}else if(type.among(CommandType.select,CommandType.toggleSelection)&&
							         (lastSelectedId==mouse.target.id||
							          abs(lastSelectedX-mouse.x)<delta &&
							          abs(lastSelectedY-mouse.y)<delta) &&
							         state.current.frame-lastSelectedFrame<=options.doubleClickSpeed){
								type=mouse.additiveSelect?
									(state.current.getSelection(controller?controller.controlledSide:-1).has(mouse.target.id)?
									 CommandType.automaticAddAllToSelection:CommandType.addAllToSelection):
									CommandType.automaticSelectAll;
							}
							controller.addCommand(Command!DagonBackend(type,renderSide,camera.target,mouse.target.id,Target.init,cameraFacing));
							if(type.among(CommandType.select,CommandType.toggleSelection)){
								lastSelectedId=mouse.target.id;
								lastSelectedFrame=state.current.frame;
							}else{
								lastSelectedId=0;
								lastSelectedFrame=state.current.frame;
								lastSelectedX=mouse.x;
								lastSelectedY=mouse.y;
							}
						}
						break;
					case MouseStatus.rectangleSelect:
						finishRectangleSelect();
						break;
					case MouseStatus.icon:
						if(mouse.icon==MouseIcon.move){
							with(TargetType) if(mouse.target.type.among(terrain,creature,building,soul)){ // TODO: sky
								auto target=Target(terrain,0,mouse.target.position,mouse.target.location);
								target.position.z=state.current.getHeight(target.position);
								controller.addCommand(Command!DagonBackend(CommandType.move,renderSide,camera.target,0,target,cameraFacing),queueing);
								mouse.status=MouseStatus.standard;
							}
						}else if(mouse.targetValid){
							auto otarget=OrderTarget(mouse.target);
							auto summary=otarget.summarize(renderSide,state.current);
							final switch(mouse.icon){
								case MouseIcon.attack:
									if(summary&(TargetFlags.creature|TargetFlags.wizard|TargetFlags.building)&&!(summary&TargetFlags.corpse)){
										controller.addCommand(Command!DagonBackend(CommandType.attack,renderSide,camera.target,0,mouse.target,cameraFacing),queueing);
									}else{
										auto target=Target(TargetType.terrain,0,mouse.target.position,mouse.target.location);
										controller.addCommand(Command!DagonBackend(CommandType.advance,renderSide,camera.target,0,target,cameraFacing),queueing);
									}
									mouse.status=MouseStatus.standard;
									break;
								case MouseIcon.guard:
									if(summary&(TargetFlags.creature|TargetFlags.wizard|TargetFlags.building)&&!(summary&TargetFlags.corpse)){
										controller.addCommand(Command!DagonBackend(CommandType.guard,renderSide,camera.target,0,mouse.target,cameraFacing),queueing);
									}else{
										auto target=Target(TargetType.terrain,0,mouse.target.position,mouse.target.location);
										controller.addCommand(Command!DagonBackend(CommandType.guardArea,renderSide,camera.target,0,target,cameraFacing),queueing);
									}
									mouse.status=MouseStatus.standard;
									break;
								case MouseIcon.move:
									assert(0);
								case MouseIcon.spell:
									if(castSpell(mouse.spell,mouse.target))
										mouse.status=MouseStatus.standard;
									break;
								case MouseIcon.ability:
									if(useAbility(mouse.spell,mouse.target,queueing))
										mouse.status=MouseStatus.standard;
									break;
							}
						}else{
							auto otarget=OrderTarget(mouse.target);
							auto status=mouse.icon==MouseIcon.spell?state.current.spellStatus!false(camera.target,mouse.spell,otarget):
								mouse.icon==MouseIcon.ability?state.current.abilityStatus!false(renderSide,mouse.spell,otarget):SpellStatus.invalidTarget;
							spellAdvisorHelpSpeech(status);
						}
						break;
				}
			}
			foreach(_;0..mouseButtonUp[MB_RIGHT]){
				if(!mouse.dragging) final switch(mouse.status){
					case MouseStatus.xmenu:
						performXmenuAction(cameraFacing,queueing);
						break;
					case MouseStatus.standard:
						switch(mouse.target.type) with(TargetType){
							case terrain: controller.addCommand(Command!DagonBackend(CommandType.move,renderSide,camera.target,0,mouse.target,cameraFacing),queueing); break;
							case creature,building:
								auto otarget=OrderTarget(mouse.target);
								auto summary=otarget.summarize(renderSide,state.current);
								if(!(summary&TargetFlags.untargetable)){
									if(summary&TargetFlags.corpse){
										auto target=Target(TargetType.terrain,0,mouse.target.position,mouse.target.location);
										controller.addCommand(Command!DagonBackend(CommandType.guardArea,renderSide,camera.target,0,target,cameraFacing),queueing); break;
									}else if(summary&TargetFlags.enemy){
										controller.addCommand(Command!DagonBackend(CommandType.attack,renderSide,camera.target,0,mouse.target,cameraFacing),queueing); break;
									}else if(summary&TargetFlags.manafount){
										castSpell("htlm",mouse.target);
									}else{
										controller.addCommand(Command!DagonBackend(CommandType.guard,renderSide,camera.target,0,mouse.target,cameraFacing),queueing); break;
									}
								}
								break;
							case soul:
								final switch(color(mouse.target.id,renderSide,state.current)){
									case SoulColor.blue:
										auto target=Target(TargetType.terrain,0,mouse.target.position,mouse.target.location);
										controller.addCommand(Command!DagonBackend(CommandType.move,renderSide,camera.target,0,target,cameraFacing),queueing);
										break;
									case SoulColor.red,SoulColor.green:
										castSpell("ccas",mouse.target);
										break;
								}
								break;
							default: break;
						}
						break;
					case MouseStatus.rectangleSelect:
						// do nothing
						break;
					case MouseStatus.icon:
						mouse.status=MouseStatus.standard;
						if(audio) audio.playSound("kabI");
						updateCursor(Duration.zero);
						break;
				}
			}
		}
	}

	void cameraControl(Duration dt){
		if(fpview.active){
			float turn_m =  (eventManager.mouseRelX) * fpview.mouseFactor * options.cameraMouseSensitivity;
			float pitch_m = (eventManager.mouseRelY) * fpview.mouseFactor * options.cameraMouseSensitivity;

			camera.pitch += pitch_m;
			camera.turn += turn_m;
		}
		if(mouse.visible){
			if(!mouse.onMinimap){
				camera.targetZoom-=0.04f*eventManager.mouseWheelY*options.mouseWheelSensitivity;
				camera.targetZoom=max(0.0f,min(camera.targetZoom,1.0f));
			}else{
				import std.math:exp,log;
				camera.minimapZoom*=exp(log(1.3)*(-0.4f*eventManager.mouseWheelY*options.mouseWheelSensitivity+0.04f*(mouse.dragging?eventManager.mouseRelY:0)/hudScaling));
				camera.minimapZoom=max(0.5f,min(camera.minimapZoom,15.0f));
			}
		}
		bool ctrl=eventManager.keyPressed[KEY_LCTRL]||options.hotkeys.capsIsCtrl&&eventManager.keyPressed[KEY_CAPSLOCK];
		if(mouse.visible && !mouse.menuMode && mouse.status.among(MouseStatus.standard,MouseStatus.icon)){
			if(ctrl && eventManager.mouseButtonPressed[MB_LEFT]||
			   eventManager.mouseButtonPressed[MB_MIDDLE]
			){
				if(eventManager.mouseRelX||eventManager.mouseRelY)
					mouse.dragging=true;
				if(!mouse.onMinimap){
					fpview.active=true;
					fpview.mouseFactor=-0.25f;
				}else{
					SDL_SetRelativeMouseMode(SDL_TRUE);
				}
				mouse.x+=eventManager.mouseRelX/screenScaling;
				mouse.y+=eventManager.mouseRelY/screenScaling;
				mouse.x=max(0,min(mouse.x,width-1));
				mouse.y=max(0,min(mouse.y,height-1));
			}else{
				mouse.dragging=false;
				if(!mouse.onMinimap){
					if(fpview.active){
						fpview.active=false;
						fpview.mouseFactor=1.0f;
						eventManager.setMouse(cast(int)(mouse.x*screenScaling),cast(int)(mouse.y*screenScaling));
					}
				}else{
					SDL_SetRelativeMouseMode(SDL_FALSE);
				}
			}
		}
		if((options.windowScrollX||options.windowScrollY)&&mouse.visible&&!mouse.dragging&&!fpview.active){
			alias B=DagonBackend;
			enum border=100;
			bool relative=false,cancelRelative=false;
			mouse.x+=eventManager.mouseRelX/screenScaling;
			mouse.y+=eventManager.mouseRelY/screenScaling;
			mouse.x=max(0,min(mouse.x,width-1));
			mouse.y=max(0,min(mouse.y,height-1));
			if(options.windowScrollX){
				if(mouse.x==0){
					if(B.isMouseCaptured||B.globalMousePosition[0]<=border){
						auto speed=radtodeg(camera.slowRotationSpeed)*(dt.total!"hnsecs"*1e-7);
						auto xspeed=62.0f/float(height)*options.aspectDistortion*options.windowScrollXFactor;
						camera.turn-=speed-min(0.0f,eventManager.mouseRelX/screenScaling)*xspeed;
						relative=true;
					}else cancelRelative=true;
				}
				if(mouse.x+max(1.0f,1.05f/screenScaling)>=width){
					if(B.isMouseCaptured||B.globalMousePosition[0]+border>=B.screenResolution[0]){
						auto speed=radtodeg(camera.slowRotationSpeed)*(dt.total!"hnsecs"*1e-7);
						auto xspeed=62.0f/float(height)*options.aspectDistortion*options.windowScrollXFactor;
						camera.turn+=speed+max(0.0f,eventManager.mouseRelX/screenScaling)*xspeed;
						relative=true;
					}else cancelRelative=true;
				}
				mouse.rotating=relative&&!cancelRelative;
			}
			if(options.windowScrollY){
				if(mouse.y==0){
					if(B.isMouseCaptured||B.globalMousePosition[1]<=border){
						auto speed=0.5f*(dt.total!"hnsecs"*1e-7);
						auto yspeed=2.0f/float(height)*options.windowScrollYFactor;
						camera.targetZoom-=speed-min(0.0f,eventManager.mouseRelY/screenScaling)*yspeed;
						relative=true;
					}else cancelRelative=true;
				}
				if(mouse.y+max(1.0f,1.05f/screenScaling)>=height){
					if(B.isMouseCaptured||B.globalMousePosition[1]+border>=B.screenResolution[1]){
						auto speed=0.5f*(dt.total!"hnsecs"*1e-7);
						auto yspeed=2.0f/float(height)*options.windowScrollYFactor;
						camera.targetZoom+=speed+max(0.0f,eventManager.mouseRelY/screenScaling)*yspeed;
						relative=true;
					}else cancelRelative=true;
				}
				camera.targetZoom=max(0.0f,min(camera.targetZoom,1.0f));
			}
			SDL_SetRelativeMouseMode(relative&&!cancelRelative?SDL_TRUE:SDL_FALSE);
		}
	}


	void observerControl(Duration dt){
		Vector3f forward = fpview.camera.worldTrans.forward;
		Vector3f right = fpview.camera.worldTrans.right;
		Vector3f down = fpview.camera.worldTrans.up;
		Vector3f cameraForward = fpview.camera.observerTrans.forward;
		Vector3f cameraDown = fpview.camera.observerTrans.up;
		Vector3f dir = Vector3f(0, 0, 0);

		//if(eventManager.keyPressed[KEY_X]) dir += Vector3f(1,0,0);
		//if(eventManager.keyPressed[KEY_Y]) dir += Vector3f(0,1,0);
		//if(eventManager.keyPressed[KEY_Z]) dir += Vector3f(0,0,1);
		bool pressed(int[] keyCodes){ return keyCodes.any!(key=>eventManager.keyPressed[key]);}
		updateCameraTarget();
		if(camera.target==0){
			// Normal (camera's "look at" dependent) movement
			if(pressed(options.hotkeys.moveForward)) dir += -forward;
			if(pressed(options.hotkeys.moveBackward)) dir += forward;
			if(pressed(options.hotkeys.turnLeft)) dir += -right;
			if(pressed(options.hotkeys.turnRight)) dir += right;
			if(pressed(options.hotkeys.moveUp)) dir += -down;
			if(pressed(options.hotkeys.moveDown)) dir += down;
			// Absolute ("look at" agnostic) helicopter-like movement
			if(pressed(options.hotkeys.cameraForward)) dir += -cameraForward;
			if(pressed(options.hotkeys.cameraBackward)) dir += cameraForward;
			if(pressed(options.hotkeys.cameraUp)) dir += -cameraDown;
			if(pressed(options.hotkeys.cameraDown)) dir += cameraDown;

			if(eventManager.keyPressed[KEY_I]) speed = 10.0f;
			if(eventManager.keyPressed[KEY_O]) speed = 100.0f;
			if(eventManager.keyPressed[KEY_P]) speed = 1000.0f;

			float factor = 1.0f;
			if(eventManager.keyPressed[KEY_LSHIFT]) factor *= 2.0f;
			if(dir.lengthsqr>0.001f^^2) camera.position += dir.normalized * factor * speed * (dt.total!"hnsecs"*1e-7);
			if(state) camera.position.z=max(camera.position.z, state.current.getHeight(camera.position));
		}
		positionCamera();
		if(observing||options.debugHotkeys&&controller&&!controller.network){
			if(!eventManager.keyPressed[KEY_LSHIFT] && !eventManager.keyPressed[KEY_LCTRL] && !eventManager.keyPressed[KEY_CAPSLOCK]){
				if(state) foreach(_;0..keyDown[KEY_M]){
					if(mouse.target.type==TargetType.creature&&mouse.target.id){
						renderSide=state.current.movingObjectById!(side,()=>-1)(mouse.target.id,state.current);
						focusCamera(mouse.target.id);
					}
				}
				foreach(_;0..keyDown[KEY_N]){
					renderSide=controller?controller.controlledSide:-1;
					camera.target=0;
				}
				void showMouse(){
					fpview.active=false;
					mouse.visible=true;
					info.hudVisible=true;
					//if(!state) SDL_ShowCursor(SDL_ENABLE);
				}
				void hideMouse(){
					fpview.active=true;
					fpview.mouseFactor=0.25f;
					mouse.visible=false;
					info.hudVisible=false;
					//if(!state) SDL_ShowCursor(SDL_DISABLE);
				}
				void toggleMouse(){
					if(mouse.visible) hideMouse();
					else showMouse();
				}
				if(keyDown[KEY_K]) showMouse();
				if(keyDown[KEY_L]) hideMouse();
				if(state) foreach(key;KEY_1..KEY_0+1){
					foreach(_;0..keyDown[key]){
						int slot=key==KEY_0?9:key-KEY_1;
						int wizard=0<=slot&&slot<state.slots.length?state.slots[slot].wizard:0;
						if(camera.target==wizard){
							if(wizard==0) toggleMouse();
							wizard=0;
						}
						renderSide=wizard==0?(controller?controller.controlledSide:-1):state.slots[slot].controlledSide;
						if(camera.target!=wizard) focusCamera(wizard);
					}
				}
			}
		}
	}

	void stateTestControl()in{
		assert(!!state);
	}do{
		//auto ostate=state.current;
		auto ostate=state.committed;
		void resimulate(){
			if(state.committedFrame!=-1){
				auto currentFrame=state.currentFrame;
				state.rollback();
				state.simulateTo(currentFrame);
			}
		}
		updateCameraTarget();
		static void applyToMoving(alias f,B)(ObjectState!B state,Camera camera,Target target){
			static void perform(T)(ref T obj,ObjectState!B state){ f(obj,state); }
			if(camera.target==0){
				if(!state.isValidTarget(target.id,target.type)) target=Target.init;
				if(target.type.among(TargetType.none,TargetType.terrain))
					state.eachMoving!perform(state);
				else if(target.type==TargetType.creature)
					state.movingObjectById!(perform,(){})(target.id,state);
			}else state.movingObjectById!(perform,(){})(camera.target,state);
		}
		static void depleteMana(B)(ref MovingObject!B obj,ObjectState!B state){
			obj.creatureStats.mana=0.0f;
		}
		if(!eventManager.keyPressed[KEY_LSHIFT] && !eventManager.keyPressed[KEY_LCTRL] && !eventManager.keyPressed[KEY_CAPSLOCK]){
			//foreach(_;0..keyDown[KEY_A]) applyToMoving!depleteMana(ostate,camera,mouse.target);
			foreach(_;0..keyDown[KEY_PERIOD]){ applyToMoving!kill(ostate,camera,mouse.target); resimulate(); }
			foreach(_;0..keyDown[KEY_J]){ applyToMoving!stun(ostate,camera,mouse.target); resimulate(); }
			static void catapultRandomly(B)(ref MovingObject!B object,ObjectState!B state){
				import std.random;
				auto velocity=Vector3f(uniform!"[]"(-10.0f,10.0f), uniform!"[]"(-10.0f,10.0f), uniform!"[]"(10.0f,25.0f));
				//auto velocity=Vector3f(0.0f,0.0f,25.0f);
				object.catapult(velocity,state);
			}
			foreach(_;0..keyDown[KEY_RSHIFT]){ applyToMoving!catapultRandomly(ostate,camera,mouse.target); resimulate(); }
			foreach(_;0..keyDown[KEY_RETURN]){ applyToMoving!immediateRevive(ostate,camera,mouse.target); resimulate(); }
			//foreach(_;0..keyDown[KEY_G]) applyToMoving!startFlying(ostate,camera,mouse.target);
			//foreach(_;0..keyDown[KEY_V]) applyToMoving!land(ostate,camera,mouse.target);
			/+if(!eventManager.keyPressed[KEY_LSHIFT]) foreach(_;0..keyDown[KEY_SPACE]){
				//applyToMoving!startMeleeAttacking(ostate,camera,mouse.target);
				static void castingTest(B)(ref MovingObject!B object,ObjectState!B state){
					object.startCasting(3*updateFPS,true,state);
				}
				applyToMoving!castingTest(ostate,camera,mouse.target);
				/+if(camera.target){
					auto position=ostate.movingObjectById!((obj)=>obj.position,function Vector3f(){ return Vector3f.init; })(camera.target);
					destructionAnimation(position+Vector3f(0,0,5),ostate);
					//explosionAnimation(position+Vector3f(0,0,5),ostate);
				}+/
			}+/
		}
		foreach(_;0..keyDown[KEY_BACKSPACE]){
			if(eventManager.keyPressed[KEY_LCTRL]||eventManager.keyPressed[KEY_CAPSLOCK]){
				applyToMoving!fastRevive(ostate,camera,mouse.target);
				resimulate();
			}else if(!eventManager.keyPressed[KEY_LSHIFT]){
				applyToMoving!revive(ostate,camera,mouse.target);
				resimulate();
			}
		}
		// TODO: enabling the following destroys ESDF controls. Template-related compiler bug?
		/+if(eventManager.keyPressed[KEY_UP] && !eventManager.keyPressed[KEY_DOWN]){
			applyToMoving!startMovingForward(ostate,camera,mouse.target);
		}else if(eventManager.keyPressed[KEY_DOWN] && !eventManager.keyPressed[KEY_UP]){
			applyToMoving!startMovingBackward(ostate,camera,mouse.target);
		}else applyToMoving!stopMovement(ostate,camera,mouse.target);
		if(eventManager.keyPressed[KEY_LEFT] && !eventManager.keyPressed[KEY_RIGHT]){
			applyToMoving!startTurningLeft(ostate,camera,mouse.target);
		}else if(eventManager.keyPressed[KEY_RIGHT] && !eventManager.keyPressed[KEY_LEFT]){
			applyToMoving!startTurningRight(ostate,camera,mouse.target);
		}else applyToMoving!stopTurning(ostate,camera,mouse.target);+/


		if(!eventManager.keyPressed[KEY_LSHIFT] && !eventManager.keyPressed[KEY_LCTRL] && !eventManager.keyPressed[KEY_CAPSLOCK]){
			foreach(_;0..keyDown[KEY_U]) renderer.showHitboxes=true;
			foreach(_;0..keyDown[KEY_I]) renderer.showHitboxes=false;

			//foreach(_;0..keyDown[KEY_H]) state.commit();
			//foreach(_;0..keyDown[KEY_B]) state.rollback();

			foreach(_;0..keyDown[KEY_COMMA]) if(audio) audio.switchTheme(cast(Theme)((audio.currentTheme+1)%Theme.max));
		}

		/+if(camera.target){
			auto creatures=creatureSpells[options.god];
			static immutable hotkeys=[KEY_Q,KEY_Q,KEY_W,KEY_R,KEY_T,KEY_A,KEY_Z,KEY_X,KEY_C,KEY_V,KEY_SPACE];
			if(!eventManager.keyPressed[KEY_LSHIFT] && !(eventManager.keyPressed[KEY_LCTRL]||eventManager.keyPressed[KEY_CAPSLOCK])){
				if(creatures.length)
				foreach(_;0..keyDown[hotkeys[0]]){
					auto id=spawn(camera.target,creatures[0],0,ostate,false);
					ostate.addToSelection(renderSide,id);
				}
			}
			if(eventManager.keyPressed[KEY_LSHIFT] && !(eventManager.keyPressed[KEY_LCTRL]||eventManager.keyPressed[KEY_CAPSLOCK])){
				foreach(i;1..min(hotkeys.length,creatures.length)){
					foreach(_;0..keyDown[hotkeys[i]]){
						auto id=spawn(camera.target,creatures[i],0,ostate,false);
						ostate.addToSelection(renderSide,id);
					}
				}
			}
		}+/
	}

	override void onViewUpdate(Duration dt){
		if(options.scaleToFit) screenScaling=super.screenScaling=min(float(eventManager.windowWidth)/width,float(eventManager.windowHeight)/height);
		else screenScaling=options.scale;
		super.onViewUpdate(dt);
	}

	void updateHUD(Duration dt){
		hudSoulFrame+=1;
		if(hudSoulFrame>=renderer.sacSoul.numFrames*updateAnimFactor)
			hudSoulFrame=0;
		info.activeChatMessages.update();
	}

	final void pause(){ if(controller) controller.pause(); }
	final void unpause(){ if(controller) controller.unpause(); }

	util.Array!(bool delegate()) logicCallbacks; // TODO: use interface instead?
	void addLogicCallback(bool delegate() dg){
		logicCallbacks~=dg;
	}
	void updateLogicCallbacks(){
		foreach(ref dg;logicCallbacks){
			if(dg && !dg())
				dg=null;
		}
		auto nonNull=logicCallbacks.data.filter!(dg=>!!dg);
		auto num=walkLength(nonNull);
		copy(nonNull,logicCallbacks.data[0..num]);
		logicCallbacks.length=num;
	}

	final bool observing(){
		if(options.observer||camera.target==0||controller&&controller.controlledSlot==-1||!state) return true;
		if(!controller) return false;
		int slot=controller.controlledSlot;
		int wizard=0<=slot&&slot<state.slots.length?state.slots[slot].wizard:0;
		if(!wizard||!state.current.isValidTarget(wizard)) return true;
		auto network=controller.network;
		// hack to allow chat between surrender and disappearance of wizard
		// TODO: track surrendering in controller?
		if(network&&!network.players[network.me].allowedToControlState) return true;
		return false;
	}

	override void onLogicsUpdate(Duration dt){
		assert(dt==1.seconds/60);
		updateHUD(dt);
		updateMouseSparkles();
		if(!state) mouse.frame+=1;
	}

	bool gameEnded=false;
	override void onUpdate(Duration dt){
		//writeln(DagonBackend.getTotalGPUMemory()," ",DagonBackend.getAvailableGPUMemory());
		//writeln(eventManager.fps);
		if(!mouse.menuMode){
			if(observing) observerControl(dt);
			if(options.debugHotkeys&&state&&controller&&!controller.network&&options.playbackFilename=="") stateTestControl();
		}
		control(dt);
		cameraControl(dt);
		updateLogicCallbacks();
		if(state){
			if(controller&&controller.hasStarted){
				controller.run();
				if(!gameEnded){
					if(state.current.isVictorious(controller.controlledSide)){
						if(audio) audio.playThemeOnce(Theme.victory);
						gameEnded=true;
					}else if(state.current.isDefeated(controller.controlledSide)){
						if(audio) audio.playThemeOnce(Theme.defeat);
						gameEnded=true;
					}
				}
				if(audio){
					if(renderSide==-1){
						audio.switchTheme(Theme.normal);
					}else{
						auto wizard=state.current.getWizardForSide(renderSide);
						int smallestRitualFrame=int.max;
						bool victory=false;
						bool sacrificeTheme=false;
						foreach(ref ritual;state.current.obj.opaqueObjects.effects.rituals){
							if(ritual.frame<ritual.setupTime) continue;
							auto ritualPosition=state.current.staticObjectById!((ref obj)=>obj.position,()=>Vector3f.init)(ritual.shrine);
							sacrificeTheme|=(ritualPosition-camera.position).lengthsqr<70.0f^^2;
							if(ritual.type!=RitualType.desecrate) continue;
							if(!ritual.targetWizard) continue;
							if(smallestRitualFrame<=ritual.frame) continue;
							auto desecratedSide=ritual.shrine?state.current.staticObjectById!(side,()=>-1)(ritual.shrine,state.current):-1;
							if(ritual.side==renderSide) victory=true;
							else if(ritual.shrine&&desecratedSide==renderSide) victory=false;
							else continue;
							smallestRitualFrame=ritual.frame;
						}
						if(smallestRitualFrame<int.max){
							auto theme=victory?Theme.winning:Theme.losing;
							audio.switchTheme(theme);
							audio.setNextTheme(theme);
						}else{
							if(!sacrificeTheme&&wizard&&wizard.lastDamageFrame!=-1&&state.current.frame<=wizard.lastDamageFrame+120*updateFPS){
								import std.random;
								if(!audio.nextTheme.among(Theme.battle1,Theme.battle2,Theme.battle3,Theme.battle4,Theme.battle5))
									audio.switchTheme(uniform!"[]"(Theme.battle1,Theme.battle5));
								if(!audio.themeAfter.among(Theme.battle1,Theme.battle2,Theme.battle3,Theme.battle4,Theme.battle5))
									audio.setNextTheme(uniform!"[]"(Theme.battle1,Theme.battle5));
							}else if(sacrificeTheme||audio.currentTheme==Theme.sacrifice){
								auto theme=sacrificeTheme?Theme.sacrifice:Theme.normal;
								audio.switchTheme(theme);
								audio.setNextTheme(theme);
							}else audio.setNextTheme(Theme.normal);
						}
					}
				}
				/+if(options.testLag){
					if(controller.network){
						if(controller.network.isHost&&controller.network.playing){
							static bool delayed=false;
							if(!delayed){
								delayed=true;
								import core.thread;
								Thread.sleep(1.seconds);
								eventManager.update();
								eventManager.update();
							}
						}
					}
				}+/
			}//else state.step();
			// state.commit();
			updateCameraTarget();
			if(camera.target){
				auto targetFacing=state.current.movingObjectById!((obj)=>obj.creatureState.facing, function float(){ assert(0); })(camera.target);
				updateCameraPosition(dt,targetFacing!=camera.lastTargetFacing,mouse.dragging||mouse.rotating);
				camera.lastTargetFacing=targetFacing;
			}
		}
		foreach(sac;sacs.data){
			static totalTime=Duration.zero;
			totalTime+=dt;
			auto frame=(totalTime.total!"hnsecs"*1e-7)*animFPS;
			import animations;
			// if(sac.numFrames(cast(AnimationState)0)) sac.setFrame(cast(AnimationState)0,cast(size_t)(frame%sac.numFrames(cast(AnimationState)0))); // TODO: fix
		}
		if(audio&&state) audio.update(dt,fpview.viewMatrix,state.current);
		updateCursor(dt);
		super.onUpdate(dt);
	}
	bool mouseTargetValid(Target target){
		if(mouse.status!=MouseStatus.icon||mouse.dragging) return true;
		if(!state) return false;
		import spells:SpelFlags;
		enum orderSpelFlags=SpelFlags.targetWizards|SpelFlags.targetCreatures|SpelFlags.targetCorpses|SpelFlags.targetStructures|SpelFlags.targetGround|AdditionalSpelFlags.targetSacrificed;
		auto otarget=OrderTarget(target);
		final switch(mouse.icon){
			case MouseIcon.guard: return isApplicable(orderSpelFlags,otarget.summarize(renderSide,state.current));
			case MouseIcon.attack: return isApplicable(orderSpelFlags,otarget.summarize(renderSide,state.current));
			case MouseIcon.move: return isApplicable(orderSpelFlags,otarget.summarize(renderSide,state.current));
			case MouseIcon.spell: return !!state.current.spellStatus!false(camera.target,mouse.spell,otarget).among(SpellStatus.ready,SpellStatus.mustBeNearBuilding,SpellStatus.mustBeNearEnemyAltar,SpellStatus.mustBeConnectedToConversion);
			case MouseIcon.ability: return state.current.abilityStatus!false(renderSide,mouse.spell,otarget)==SpellStatus.ready;
		}
	}
	void initializeMouse(){
		DagonBackend.hideMouse();
		mouse.x=width/2;
		mouse.y=height/2;
		fpview.oldMouseX=cast(int)mouse.x;
		fpview.oldMouseY=cast(int)mouse.y;
		eventManager.setMouse(cast(int)mouse.x, cast(int)mouse.y);
	}
	Target computeMouseTarget(){
		if(mouse.menuMode) return renderer.formTarget;
		if(mouse.onSpellbook) return renderer.spellbookTarget;
		if(mouse.onSelectionRoster) return renderer.selectionRosterTarget;
		if(mouse.onMinimap) return renderer.minimapTarget;
		auto information=gbuffer.getInformation();
		if(!state) return Target.init;
		auto cur=state.current;
		if(information.x==1){
			Vector3f position=2560.0f*information.yz;
			if(!cur.isOnGround(position)) return Target.init;
			position.z=cur.getGroundHeight(position);
			return Target(TargetType.terrain,0,position,TargetLocation.scene);
		}else if(information.x==2){
			auto id=(cast(int)information.y)<<16|cast(int)information.z;
			if(!state.current.isValidTarget(id,TargetType.creature)&&!state.current.isValidTarget(id,TargetType.building)) return Target.init;
			static Target handle(B,T)(T obj,int renderSide,ObjectState!B state){
				enum isMoving=is(T==MovingObject!B);
				static if(isMoving) enum type=TargetType.creature;
				else enum type=TargetType.building;
				return Target(type,obj.id,obj.position,TargetLocation.scene);
			}
			return cur.objectById!handle(id,renderSide,cur);
		}else if(information.x==3){
			auto id=(cast(int)information.y)<<16|cast(int)information.z;
			if(!cur.isValidTarget(id,TargetType.soul)) return Target.init;
			return Target(TargetType.soul,id,cur.soulById!((soul)=>soul.position,function Vector3f(){ assert(0); })(id),TargetLocation.scene);
		}else return Target.init;
	}
	void updateMouseTarget(){
		if(mouse.menuMode){
			if(mouse.status==MouseStatus.xmenu) mouse.status=MouseStatus.standard;
			if(mouse.target.type==TargetType.formElement){
				auto formIndex=mouse.target.formIndex;
				auto elementIndex=mouse.target.elementIndex;
				if(formIndex>=forms.length||elementIndex>=forms[formIndex].elements.length) mouse.target=Target.init;
			}else mouse.target=Target.init;
		}
		auto target=mouse.status==MouseStatus.xmenu?mouse.target:computeMouseTarget();
		if(!mouse.menuMode){
			if(target.location==TargetLocation.scene)
				if(target.id!=0&&(!state||!state.current.isValidTarget(target.id,target.type)))
					target=Target.init;
		}
		auto targetValid=mouseTargetValid(target);
		static immutable importantTargets=[TargetType.creature,TargetType.soul];
		if(mouse.cachedTarget.id!=0&&!state.current.isValidTarget(mouse.cachedTarget.id,mouse.cachedTarget.type)) mouse.cachedTarget=Target.init;
		if(target.location.among(TargetLocation.scene,TargetLocation.minimap)){
			if(!importantTargets.canFind(target.type)&&!(target.location==TargetLocation.minimap&&target.type==TargetType.building)){
				auto delta=mouse.cachedTarget.location!=TargetLocation.minimap?mouse.targetCacheDelta:mouse.minimapTargetCacheDelta;
				if(mouse.cachedTarget.type!=TargetType.none){
					if((mouse.inHitbox || abs(mouse.cachedTargetX-mouse.x)<delta &&
					    abs(mouse.cachedTargetY-mouse.y)<delta)&&
					   mouse.cachedTargetFrame+(mouse.inHitbox?2:1)*mouse.targetCacheDuration>state.current.frame){
						target=mouse.cachedTarget;
						targetValid=mouseTargetValid(target);
					}else mouse.cachedTarget=Target.init;
				}
			}else if(targetValid){
				mouse.cachedTarget=target;
				mouse.cachedTargetX=mouse.x;
				mouse.cachedTargetY=mouse.y;
				mouse.cachedTargetFrame=state.current.frame;
			}
		}
		static bool targetsEquiv(ref Target a,ref Target b){
			return (a.type==b.type||
			        a.type.among(TargetType.soulStat, TargetType.manaStat, TargetType.healthStat)
			        && b.type.among(TargetType.soulStat, TargetType.manaStat, TargetType.healthStat))
				&& a.id==b.id;
		}
		if(state) mouse.frame=state.current.frame;
		if(!targetsEquiv(mouse.target, target))
			mouse.targetUpdateFrame=mouse.frame;
		mouse.target=target;
		if(mouse.target.type==TargetType.spell)
			mouse.targetSpell=renderer.spellbookTargetSpell;
		if(mouse.target.type==TargetType.ability)
			mouse.targetSpell=renderer.selectionRosterTargetAbility;
		mouse.targetValid=targetValid;
		auto otarget=OrderTarget(target);
		if(target.type!=TargetType.none && targetValid && target.location==TargetLocation.scene){
			assert(!!state);
			auto summary=summarize!true(otarget,renderSide,state.current);
			with(Cursor)
				mouse.showFrame=targetValid && target.location==TargetLocation.scene &&
					!(summary&TargetFlags.corpse) &&
					((mouse.status.among(MouseStatus.standard,MouseStatus.rectangleSelect)&&!mouse.dragging &&
					  summary&(TargetFlags.soul|TargetFlags.creature|TargetFlags.wizard)) ||
					 (mouse.status==MouseStatus.icon&&!mouse.dragging&&!!target.type.among(TargetType.creature,TargetType.building,TargetType.soul)));
		}else mouse.showFrame=false;

	}
	void animateTarget(Target target){
		switch(target.type){
			case TargetType.none: return;
			case TargetType.terrain: animateManalith(target.position, renderSide, state.current); break;
			case TargetType.creature, TargetType.building: animateManafount(target.position, state.current); break;
			case TargetType.soul: animateManahoar(target.position, renderSide, 30.0f, state.current); break;
			default: assert(target.location!=TargetLocation.scene); break;
		}
	}
	void addMouseSparkle(){
		auto size=options.cursorSize;
		float scale=size==-1?32*info.hudScaling:size;
		import std.random:uniform;
		auto offset=scale*Vector2f(uniform(-0.25f,0.25f),uniform(-0.25f,0.25f));
		info.mouseSparkles~=RenderInfo!DagonBackend.MouseSparkle(mouse.x+offset.x,mouse.y+offset.y);
	}
	void updateMouseSparkles(){
		for(int i=0;i<info.mouseSparkles.length;){
			if(++info.mouseSparkles[i].frame>=SacCursor!DagonBackend.numSparkleFrames){
				swap(info.mouseSparkles[i],info.mouseSparkles[$-1]);
				info.mouseSparkles.length=info.mouseSparkles.length-1;
			}else i++;
		}
	}
	void updateCursor(Duration dt){
		updateMouseSparkles();
		updateMouseTarget();
		auto otarget=OrderTarget(mouse.target);
		if(mouse.dragging) mouse.cursor=Cursor.drag;
		else if(!state) mouse.cursor=Cursor.normal;
		else final switch(mouse.status){
			case MouseStatus.standard:
				mouse.cursor=otarget.cursor(renderSide,false,state.current);
				break;
			case MouseStatus.xmenu:
				mouse.cursor=Cursor.normal;
				if(eventManager.mouseRelX||eventManager.mouseRelY){
					import std.random:uniform;
					if(uniform(0,2)==0)
						addMouseSparkle();
				}
				if(options.xmenu) updateXmenu();
				break;
			case MouseStatus.rectangleSelect:
				mouse.cursor=Cursor.rectangleSelect;
				break;
			case MouseStatus.icon:
				if(mouse.icon==MouseIcon.spell&&!renderer.spellbookVisible(state.current,info)){
					mouse.status=MouseStatus.standard;
					if(audio) audio.playSound("kabI");
					goto case MouseStatus.standard;
				}
				mouse.cursor=otarget.cursor(renderSide,true,state.current);
				break;
		}
	}
	override void startGBufferInformationDownload(){
		if(mouse.onMinimap) return;
		static int i=0;
		if(options.printFps && ((++i)%=2)==0) writeln(eventManager.fps);
		mouse.x=eventManager.mouseX/screenScaling;
		mouse.y=eventManager.mouseY/screenScaling;
		mouse.x=max(0,min(mouse.x,width-1));
		mouse.y=max(0,min(mouse.y,height-1));
		auto x=cast(int)(mouse.x+0.5f), y=cast(int)(height-1-mouse.y+0.5f);
		x=max(0,min(x,width-1));
		y=max(0,min(y,height-1));
		gbuffer.startInformationDownload(x,y);
	}

	bool displacementDirty=false;
	private bool hasDisplacement(){
		return state.current.obj.opaqueObjects.effects.testDisplacements.length!=0||
			state.current.obj.opaqueObjects.effects.eruptCastings.length!=0||
			state.current.obj.opaqueObjects.effects.erupts.length!=0||
			state.current.obj.opaqueObjects.effects.quakes.length!=0;
	}
	override bool needTerrainDisplacement(){
		return state&&(displacementDirty||hasDisplacement());
	}
	override void displaceTerrain(){
		if(!state) return;
		bindTestDisplacement();
		foreach(ref td;state.current.obj.opaqueObjects.effects.testDisplacements){
			float time=float(td.frame)/updateFPS;
			testDisplacement(time);
		}
		unbindTestDisplacement();
		bindEruptDisplacement();
		foreach(ref ec;state.current.obj.opaqueObjects.effects.eruptCastings){
			float time=float(ec.erupt.frame)/updateFPS;
			eruptDisplacement(ec.erupt.position.x,ec.erupt.position.y,time);
		}
		foreach(ref e;state.current.obj.opaqueObjects.effects.erupts){
			float time=float(e.frame)/updateFPS;
			eruptDisplacement(e.position.x,e.position.y,time);
		}
		unbindEruptDisplacement();
		bindQuakeDisplacement();
		foreach(ref e;state.current.obj.opaqueObjects.effects.quakes){
			float time=float(e.frame)/updateFPS;
			quakeDisplacement(e.position.x,e.position.y,time);
		}
		unbindQuakeDisplacement();
		displacementDirty=hasDisplacement();
	}

	AudioBackend!DagonBackend audio;
	void initializeAudio(){
		audio=New!(AudioBackend!DagonBackend)(options.volume,options.musicVolume,options.soundVolume);
		audio.switchTheme(Theme.normal);
	}
	~this(){
		if(audio){
			Delete(audio);
			audio=null;
		}
	}
}

class SacApplication: SceneApplication{
	SacScene scene;
	this(Options options){
		auto width=cast(int)(options.width*options.scale);
		auto height=cast(int)(options.height*options.scale);
		super(width, height, options.detectResolution, options.resizableWindow, options.enableFullscreen, "SacEngine", []);
		if(options.detectResolution||options.width==0||options.height==0){
			options.width=this.width;
			options.height=this.height;
		}
		scene = new SacScene(sceneManager, options);
		scene.load();
	}
	override void onUpdate(Duration dt){
		scene.update(dt);
	}
	override void onRender(){
		scene.render();
	}
}

struct DagonBackend{
static:
	SacApplication app;
	@property SacScene scene(){
		if(!app) return null;
		return app.scene;
	}
	@property GameState!DagonBackend state(){
		if(!app) return null;
		if(!app.scene) return null;
		return app.scene.state;
	}
	@property Controller!DagonBackend controller(){
		if(!app) return null;
		if(!app.scene) return null;
		return app.scene.controller;
	}
	@property Network!DagonBackend network(){
		if(!app) return null;
		if(!app.scene) return null;
		if(!app.scene.controller) return null;
		return app.scene.controller.network;
	}
	void initialize(Options options){
		enforce(!app,"DagonBackend already initialized"); // TODO: fix?
		app = new SacApplication(options);
		enforce(!!scene,"Scene missing");
		app.scene.initialize(options);
	}
	void addLogicCallback(bool delegate() dg){
		scene.addLogicCallback(dg);
	}
	void setState(GameState!DagonBackend state){
		scene.setState(state);
	}
	void setSlot(int slot){
		scene.renderSlot=slot;
	}
	void focusCamera(int id,bool reset=true){
		scene.focusCamera(id,reset);
	}
	void setController(Controller!DagonBackend controller){
		scene.setController(controller);
	}
	void addObject(SacObject!DagonBackend obj,Vector3f position,Quaternionf rotation){
		scene.addObject(obj,position,rotation);
	}
	bool processEvents(){
		app.eventManager.update();
		app.processEvents();
		return app.eventManager.running;
	}
	void run(){
		if(!app) return;
		if(!app.scene) return;
		app.scene.start();
		app.run();
	}
	void pause(){ if(app&&app.scene) app.scene.pause(); }
	void unpause(){ if(app&&app.scene) app.scene.unpause(); }
	void clearSidechannelMessages(){ if(app.scene) app.scene.info.activeChatMessages.clearSidechannelMessages(); }
	~this(){ Delete(app); }

	void grabFocus(){ SDL_RaiseWindow(app.window); }
	void captureMouse(){ SDL_SetWindowGrab(app.window, SDL_TRUE); }
	bool isMouseCaptured(){ return !!SDL_GetWindowGrab(app.window); }
	void releaseMouse(){ SDL_SetWindowGrab(app.window, SDL_FALSE); }
	void showMouse(){ SDL_ShowCursor(SDL_DISABLE); }
	void hideMouse(){ SDL_ShowCursor(SDL_DISABLE); }
	int[2] screenResolution(){
		SDL_DisplayMode dm;
		SDL_GetCurrentDisplayMode(0,&dm);
		return [dm.w,dm.h];
	}
	int[2] globalMousePosition(){
		int[2] r;
		SDL_GetGlobalMouseState(&r[0],&r[1]);
		return r;
	}

	alias RenderContext=RenderingContext*;

	Matrix4f getModelViewProjectionMatrix(Vector3f position,Quaternionf rotation){ // TODO: compute this in the renderer?
		auto modelMatrix=translationMatrix(position)*rotation.toMatrix4x4;
		auto modelViewMatrix=scene.rc3d.viewMatrix*modelMatrix;
		auto modelViewProjectionMatrix=scene.rc3d.projectionMatrix*modelViewMatrix;
		return modelViewProjectionMatrix;
	}
	Matrix4f getSpriteModelViewProjectionMatrix(Vector3f position){
		auto modelViewMatrix=scene.rc3d.viewMatrix*translationMatrix(position)*scene.rc3d.invViewRotationMatrix;
		auto modelViewProjectionMatrix=scene.rc3d.projectionMatrix*modelViewMatrix;
		return modelViewProjectionMatrix;
	}

	alias Texture=.Texture;
	alias Material=.GenericMaterial;
	alias MaterialBackend=.GenericMaterialBackend;
	alias Mesh=.Mesh;
	alias Mesh2D=.Mesh2D;
	alias BoneMesh=.BoneMesh;
	alias TerrainMesh=.TerrainMesh;
	alias MinimapMesh=.Mesh2D;

	Texture makeTexture(SuperImage i,bool mirroredRepeat=true){
		auto repeat=mirroredRepeat?GL_MIRRORED_REPEAT:GL_REPEAT;
		auto texture=New!Texture(null); // TODO: set owner
		texture.image=i;
		texture.createFromImage(texture.image,true,repeat);
		return texture;
	}

	Mesh makeMesh(size_t numVertices,size_t numFaces){
		auto m=new Mesh(null); // TODO: set owner
		m.vertices=New!(Vector3f[])(numVertices);
		m.normals=New!(Vector3f[])(numVertices);
		m.texcoords=New!(Vector2f[])(numVertices);
		m.indices=New!(uint[3][])(numFaces);
		return m;
	}
	void finalizeMesh(Mesh mesh){
		mesh.dataReady=true;
		mesh.prepareVAO();
	}
	BoneMesh makeBoneMesh(size_t numVertices, size_t numFaces){
		auto m=new BoneMesh(null); // TODO: set owner
		foreach(j;0..3){
			m.vertices[j]=New!(Vector3f[])(numVertices);
			m.vertices[j][]=Vector3f(0,0,0);
		}
		m.normals=New!(Vector3f[])(numVertices);
		m.texcoords=New!(Vector2f[])(numVertices);
		m.boneIndices=New!(uint[3][])(numVertices);
		m.weights=New!(Vector3f[])(numVertices);
		m.weights[]=Vector3f(0,0,0);
		m.indices=New!(uint[3][])(numFaces);
		return m;
	}
	void finalizeBoneMesh(BoneMesh mesh){
		mesh.dataReady=true;
		mesh.prepareVAO();
	}
	TerrainMesh makeTerrainMesh(size_t numVertices, size_t numFaces){
		auto m=new TerrainMesh(null); // TODO: set owner
		m.vertices=New!(Vector3f[])(numVertices);
		m.normals=New!(Vector3f[])(numVertices);
		m.texcoords=New!(Vector2f[])(numVertices);
		m.coords=New!(Vector2f[])(numVertices);
		m.indices=New!(uint[3][])(numFaces);
		return m;
	}
	void finalizeTerrainMesh(TerrainMesh mesh){
		mesh.dataReady=true;
		mesh.prepareVAO();
	}
	Mesh2D makeMesh2D(size_t numVertices,size_t numFaces){
		auto m=new MinimapMesh(null); // TODO: set owner
		m.vertices=New!(Vector2f[])(numVertices);
		m.texcoords=New!(Vector2f[])(numVertices);
		m.indices=New!(uint[3][])(numFaces);
		return m;
	}
	void finalizeMesh2D(Mesh2D mesh){
		mesh.dataReady=true;
		mesh.prepareVAO();
	}
	MinimapMesh makeMinimapMesh(size_t numVertices, size_t numFaces){
		return makeMesh2D(numVertices,numFaces);
	}
	void finalizeMinimapMesh(MinimapMesh mesh){
		return finalizeMesh2D(mesh);
	}

	alias Quad=ShapeQuad;
	Quad makeQuad(){ return New!ShapeQuad(scene.assetManager); }
	alias CreatureFrame=ShapeSacCreatureFrame;
	CreatureFrame makeCreatureFrame(){ return New!ShapeSacCreatureFrame(scene.assetManager); }
	alias SubQuad=ShapeSubQuad;
	SubQuad makeSubQuad(float left,float top,float right,float bottom){
		return New!ShapeSubQuad(scene.assetManager,left,top,right,bottom);
	}
	alias StatsFrame=ShapeSacStatsFrame;
	StatsFrame makeStatsFrame(){ return New!ShapeSacStatsFrame(scene.assetManager); }
	alias Cooldown=ShapeCooldown;
	Cooldown makeCooldown(){ return New!ShapeCooldown(scene.assetManager); }

	alias Font=FreeTypeFont;
	Font loadFont(int pointSize,string filename){
		import file=std.file;
		if(!file.exists(filename)) return null;
		auto result=new FreeTypeFont(pointSize,null);
		result.createFromFile(filename);
		result.prepareVAO();
		result.preloadASCII();
		return result;
	}

	@property environment(){ return scene.environment; } // TODO: get rid of this?
	@property shadowMap(){ return scene.shadowMap; }     // TODO: get rid of this?

	@property GeometryPassBackend defaultMaterialBackend(){ return scene.defaultMaterialBackend; }
	@property ShadelessBackend shadelessMaterialBackend(){ return scene.shadelessMaterialBackend; }
	@property ShadelessMorphBackend shadelessMorphMaterialBackend(){ return scene.shadelessMorphMaterialBackend; }

	@property BoneBackend boneMaterialBackend(){ return scene.boneMaterialBackend; }
	@property ShadelessBoneBackend shadelessBoneMaterialBackend(){ return scene.shadelessBoneMaterialBackend; }
	@property BoneShadowBackend boneShadowBackend(){ return scene.shadowMap.bsb; }

	@property TerrainBackend2 terrainMaterialBackend(){ return scene.terrainMaterialBackend; }
	@property TerrainShadowBackend terrainShadowBackend(){ return scene.shadowMap.tsb; }

	@property BuildingSummonBackend1 buildingSummonMaterialBackend1(){ return scene.buildingSummonMaterialBackend1; }
	@property BuildingSummonBackend2 buildingSummonMaterialBackend2(){ return scene.buildingSummonMaterialBackend2; }
	@property SacSkyBackend sacSkyMaterialBackend(){ return scene.sacSkyMaterialBackend; }
	@property SacSunBackend sacSunMaterialBackend(){ return scene.sacSunMaterialBackend; }
	@property SkyBackend skyMaterialBackend(){ return scene.skyMaterialBackend; }


	@property HUDMaterialBackend hudMaterialBackend(){ return scene.hudMaterialBackend; }
	@property HUDMaterialBackend2 hudMaterialBackend2(){ return scene.hudMaterialBackend2; }
	@property ColorHUDMaterialBackend colorHUDMaterialBackend(){ return scene.colorHUDMaterialBackend; }
	@property ColorHUDMaterialBackend2 colorHUDMaterialBackend2(){ return scene.colorHUDMaterialBackend2; }
	@property MinimapMaterialBackend minimapMaterialBackend(){ return scene.minimapMaterialBackend; }
	@property CooldownMaterialBackend cooldownMaterialBackend(){ return scene.cooldownMaterialBackend; }

	Material makeMaterial(MaterialBackend backend){ return scene.createMaterial(backend); }

	@property Material shadowMaterial(){ return scene.shadowMap.sm; }

	void scissor(int x,int y,int width,int height){
		glScissor(x,y,width,height);
	}

	void enableWireframe(){
		glPolygonMode(GL_FRONT_AND_BACK,GL_LINE);
		glDisable(GL_CULL_FACE);
	}
	void disableWireframe(){
		glPolygonMode(GL_FRONT_AND_BACK,GL_FILL);
		glEnable(GL_CULL_FACE);
	}

	void enableDepthMask(){
		glDepthMask(GL_TRUE); // TODO: avoid setting this twice?
	}
	void disableDepthMask(){
		glDepthMask(GL_FALSE);
	}

	void enableCulling(){
		glEnable(GL_CULL_FACE);
	}
	void disableCulling(){
		glDisable(GL_CULL_FACE);
	}

	void enableTransparency(){
		glEnablei(GL_BLEND, 0);
		glEnablei(GL_BLEND, 1);
		if(glBlendFunci){
			glBlendFunci(0, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
			glBlendFunci(1, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
		}else glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
	}

	void enableAdditive(){
		glEnablei(GL_BLEND, 0);
		glEnablei(GL_BLEND, 1);
		if(glBlendFunci){
			glBlendFunci(0, GL_SRC_ALPHA, GL_ONE);
			glBlendFunci(1, GL_SRC_ALPHA, GL_ONE);
		}else glBlendFunc(GL_SRC_ALPHA, GL_ONE);
	}

	@property blending(GenericMaterial material){ return ("blending" in material.inputs).asInteger; }
	static struct Blending{
		enum Opaque=.Opaque;
		enum Transparent=.Transparent;
		enum Additive=.Additive;
	}
	Material[] createMaterials(SacObject!DagonBackend sobj,SacObject!DagonBackend.MaterialConfig config){
		GenericMaterial[] materials;
		foreach(i;0..sobj.numParts){
			GenericMaterial mat;
			if(i==config.sunBeamPart){
				mat=makeMaterial(gpuSkinning&&sobj.isSaxs?scene.shadelessBoneMaterialBackend:scene.shadelessMaterialBackend);
				mat.depthWrite=false;
				mat.blending=Additive;
				mat.energy=4.0f;
			}else if(i==config.locustWingPart){
				mat=makeMaterial(gpuSkinning&&sobj.isSaxs?scene.shadelessBoneMaterialBackend:scene.shadelessMaterialBackend);
				mat.depthWrite=false;
				mat.blending=Additive;
				mat.energy=20.0f;
			}else if((config.transparentShinyParts>>i)&1){
				mat=makeMaterial(gpuSkinning&&sobj.isSaxs?scene.shadelessBoneMaterialBackend:scene.shadelessMaterialBackend);
				mat.depthWrite=false;
				mat.blending=Transparent;
				mat.transparency=0.5f;
				mat.energy=20.0f;
			}else{
				mat=makeMaterial(gpuSkinning&&sobj.isSaxs?scene.boneMaterialBackend:scene.defaultMaterialBackend);
			}
			auto diffuse=sobj.isSaxs?sobj.saxsi.saxs.bodyParts[i].texture:sobj.textures[i];
			if(diffuse !is null) mat.diffuse=diffuse;
			mat.specular=sobj.isSaxs?Color4f(1,1,1,1):Color4f(0,0,0,1);
			mat.roughness=1.0f;
			mat.metallic=0.5f;
			if(i==config.shinyPart){
				mat.emission=diffuse;
				mat.energy=0.5f;
			}
			materials~=mat;
		}
		return materials;
	}

	Material[] createTransparentMaterials(SacObject!DagonBackend sobj){
		GenericMaterial[] materials;
		foreach(i;0..sobj.numParts){
			if(("blending" in sobj.materials[i].inputs).asInteger==Transparent){
				materials~=sobj.materials[i];
				continue;
			}
			auto mat=makeMaterial(gpuSkinning&&sobj.isSaxs?scene.shadelessBoneMaterialBackend:scene.shadelessMaterialBackend);
			mat.depthWrite=false;
			mat.blending=Transparent;
			auto diffuse=sobj.isSaxs?sobj.saxsi.saxs.bodyParts[i].texture:sobj.textures[i];
			if(diffuse !is null) mat.diffuse=diffuse;
			mat.specular=sobj.isSaxs?Color4f(1,1,1,1):Color4f(0,0,0,1);
			mat.roughness=1.0f;
			mat.metallic=0.5f;
			materials~=mat;
		}
		return materials;
	}

	Material[] createShadowMaterials(SacObject!DagonBackend sobj){
		GenericMaterial[] materials;
		materials=new GenericMaterial[](sobj.materials.length);
		foreach(i,mat;sobj.materials){
			auto blending=("blending" in mat.inputs).asInteger;
			if(blending!=Additive){
				auto shadowMat=makeMaterial(gpuSkinning&&sobj.isSaxs?scene.shadowMap.bsb:scene.shadowMap.sb); // TODO: use shadowMap.sm if no alpha channel
				if(auto diffuse="diffuse" in mat.inputs)
					if(diffuse.texture)
						shadowMat.diffuse=diffuse.texture;
				materials[i]=shadowMat;
			}
		}
		return materials;
	}

	Material createMaterial(SacMap!DagonBackend map){
		auto mat=makeMaterial(scene.terrainMaterialBackend);
		auto specu=0.1f*map.envi.landscapeSpecularity;
		mat.specular=Color4f(specu*map.envi.specularityRed/255.0f,specu*map.envi.specularityGreen/255.0f,specu*map.envi.specularityBlue/255.0f);
		//mat.roughness=1.0f-map.envi.landscapeGlossiness;
		mat.roughness=1.0f;
		mat.metallic=0.1f;
		mat.energy=0.05;
		if(map.tileset==Tileset.james) mat.detailFactor=0.0f;
		return mat;
	}

	Material createMaterial(SacSoul!DagonBackend soul){
		auto mat=makeMaterial(scene.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=Transparent;
		mat.energy=20.0f;
		mat.diffuse=soul.texture;
		return mat;
	}
	Material createMaterial(SacGreenSoul!DagonBackend soul){
		auto mat=makeMaterial(scene.shadelessMaterialBackend);
		mat.depthWrite=false;
		mat.blending=Transparent;
		mat.energy=20.0f;
		mat.diffuse=soul.texture;
		return mat;
	}

	Material createMaterial(SacParticle!DagonBackend particle){
		final switch(particle.type) with(ParticleType){
			case manafount, manalith, manahoar, shrine, firy, fire, fireball, cold, explosion, explosion2, speedUp, heal, scarabHit, relativeHeal, ghostTransition, ghost, lightningCasting, chainLightningCasting, needle, freeze, etherealFormSpark, shard, flurryShard, redVortexDroplet, blueVortexDroplet, spark, styxSpark, rend, castPersephone, castPersephone2, castPyro, castJames, castStratos, castCharnel, castCharnel2, breathOfLife, wrathCasting, wrathExplosion1, wrathExplosion2, wrathParticle, rainbowParticle, rainOfFrogsCasting, frogExplosion, gnomeHit, warmongerHit, steam, ashParticle, smoke, dirt, dust, splat, rock, webDebris, oil, poison, relativePoison, swarmHit, slime, hoverBlood, blood, locustBlood, locustDebris:
				auto mat=makeMaterial(scene.shadelessMaterialBackend);
				mat.depthWrite=false;
				mat.blending=particle.type.among(styxSpark,rend,ashParticle,smoke,dirt,dust,splat,rock,oil,poison,relativePoison,swarmHit,slime,hoverBlood,blood,locustBlood)?Transparent:Additive;
				if(particle.type==dust) mat.alpha=0.25f;
				mat.energy=particle.energy;
				mat.diffuse=particle.texture;
				mat.color=particle.color;
				return mat;
		}
	}

	std.typecons.Tuple!(Material[],Material[],Material,Material) createMaterials(SacCursor!DagonBackend sacCursor){
		auto materials=new Material[](sacCursor.textures.length);
		foreach(i;0..materials.length){
			auto mat=makeMaterial(scene.hudMaterialBackend);
			mat.blending=Transparent;
			mat.diffuse=sacCursor.textures[i];
			materials[i]=mat;
		}
		auto iconMaterials=new Material[](sacCursor.iconTextures.length);
		foreach(i;0..iconMaterials.length){
			auto mat=makeMaterial(scene.hudMaterialBackend);
			mat.blending=Transparent;
			mat.diffuse=sacCursor.iconTextures[i];
			iconMaterials[i]=mat;
		}
		auto mat=makeMaterial(scene.hudMaterialBackend);
		mat.blending=Transparent;
		mat.diffuse=sacCursor.invalidTargetIconTexture;
		auto invalidTargetIconMaterial=mat;
		mat=makeMaterial(scene.hudMaterialBackend2);
		mat.blending=Additive;
		mat.diffuse=sacCursor.sparkleTexture;
		mat.energy=20.0f;
		auto sparkleMaterial=mat;
		return tuple(materials,iconMaterials,invalidTargetIconMaterial,sparkleMaterial);
	}

	Material[] createMaterials(SacHud!DagonBackend sacHud){
		auto materials=new Material[](sacHud.textures.length);
		foreach(i;0..materials.length){
			bool spellReady=i==SacHud!DagonBackend.spellReadyIndex;
			auto mat=makeMaterial(spellReady?scene.hudMaterialBackend2:scene.colorHUDMaterialBackend);
			mat.blending=spellReady?Additive:Transparent;
			mat.diffuse=sacHud.textures[i];
			materials[i]=mat;
		}
		return materials;
	}

	Material createMaterial(SacCommandCone!DagonBackend sacCommandCone){
		auto material=makeMaterial(scene.shadelessMaterialBackend);
		material.depthWrite=false;
		material.blending=Additive;
		material.energy=1.0f;
		//material.diffuse=sacCommandCone.texture;
		//material.diffuse=makeTexture(makeOnePixelImage(Color4f(1.0f,1.0f,1.0f)));
		return material;
	}

	//uint ticks(){ return SDL_GetTicks(); }
	MonoTime time(){ return MonoTime.currTime(); }

	enum GL_GPU_MEM_INFO_TOTAL_AVAILABLE_MEM_NVX=0x9048;
	enum GL_GPU_MEM_INFO_CURRENT_AVAILABLE_MEM_NVX=0x9049;

	GLint getTotalGPUMemory(){
		GLint total_mem_kb = 0;
		glGetIntegerv(GL_GPU_MEM_INFO_TOTAL_AVAILABLE_MEM_NVX,
		              &total_mem_kb);
		return total_mem_kb;
	}

	GLint getAvailableGPUMemory(){
		GLint cur_avail_mem_kb = 0;
		glGetIntegerv(GL_GPU_MEM_INFO_CURRENT_AVAILABLE_MEM_NVX,
		              &cur_avail_mem_kb);
		return cur_avail_mem_kb;
	}


	enum hasAudio=true;
	@property AudioBackend!DagonBackend audio(){
		return scene.audio;
	}
	void loopingSoundSetup(StaticObject!DagonBackend object){
		if(audio) audio.loopingSoundSetup(object);
	}
	void deleteLoopingSounds(){
		if(audio) audio.deleteLoopingSounds();
	}
	void updateAudioAfterRollback(){
		if(audio&&scene.state) audio.updateAudioAfterRollback(scene.state.current);
	}
	void queueDialogSound(int side,char[4] sound,DialogPriority priority){
		if(!audio||side!=-1&&side!=scene.renderSide) return;
		audio.queueDialogSound(sound,priority);
	}
	int getSoundDuration(char[4] sound){
		return AudioBackend!DagonBackend.getDuration(sound);
	}
	void playSound(int side,char[4] sound,float gain=1.0f){
		if(!audio||side!=-1&&side!=scene.renderSide) return;
		audio.playSound(sound,gain);
	}
	void playSpellbookSound(int side,SpellbookSoundFlags flags,char[4] sound,float gain=1.0f){
		if(!audio||side!=-1&&side!=scene.renderSide) return;
		final switch(scene.spellbookTab){
			case SpellType.creature: if(flags&SpellbookSoundFlags.creatureTab) break; return;
			case SpellType.spell: if(flags&SpellbookSoundFlags.spellTab) break; return;
			case SpellType.structure: if(flags&SpellbookSoundFlags.structureTab) break; return;
		}
		audio.playSound(sound,gain);
	}
	void playSoundAt(char[4] sound,Vector3f position,float gain=1.0f){
		if(!audio) return;
		audio.playSoundAt(sound,position,gain);
	}
	void playSoundAt(char[4] sound,int id,float gain=1.0f){
		if(!audio) return;
		audio.playSoundAt(sound,id,gain);
	}
	void stopSoundsAt(int id){
		if(!audio) return;
		audio.stopSoundsAt(id);
	}
}

// TODO: get rid of code duplication here?
class ShapeSacCreatureFrame: Owner, Drawable{
	Vector2f[20] vertices;
	float[20] alpha;
	uint[3][16] indices;

	GLuint vao = 0;
	GLuint vbo = 0;
	GLuint abo = 0;
	GLuint eao = 0;

	this(Owner o){
		super(o);

		enum size=0.1f;
		enum border=0.5f*size;
		enum gap=0.0f;
		enum left=-border,right=1.0f+border;
		enum bottom=1.0f+border,top=-border;
		vertices[0]=Vector2f(left+gap,top);
		vertices[1]=Vector2f(left+gap+size,top);
		vertices[2]=Vector2f(left+gap+size,top-size);
		vertices[3]=Vector2f(right,top);
		vertices[4]=Vector2f(left+gap+size,top+size);

		vertices[5]=Vector2f(left,top+gap);
		vertices[6]=Vector2f(left+size,top+gap+size);
		vertices[7]=Vector2f(left,top+gap+size);
		vertices[8]=Vector2f(left-size,top+gap+size);
		vertices[9]=Vector2f(left,bottom-gap);

		enum largeAlpha=1.0f;
		enum smallAlpha=0.0f;

		alpha[0]=smallAlpha;
		alpha[1]=largeAlpha;
		alpha[2]=smallAlpha;
		alpha[3]=smallAlpha;
		alpha[4]=smallAlpha;

		alpha[5]=smallAlpha;
		alpha[6]=smallAlpha;
		alpha[7]=largeAlpha;
		alpha[8]=smallAlpha;
		alpha[9]=smallAlpha;

		indices[0]=[0,1,2];
		indices[1]=[1,3,2];
		indices[2]=[0,4,1];
		indices[3]=[4,3,1];

		indices[4]=[5,6,7];
		indices[5]=[8,5,7];
		indices[6]=[7,9,6];
		indices[7]=[8,9,7];

		foreach(i;10..20){
			vertices[i]=Vector2f(1.0f,1.0f)-vertices[i-10];
			alpha[i]=alpha[i-10];
		}
		foreach(i;8..16){
			indices[i]=indices[i-8][]+10;
			import std.algorithm: swap;
			swap(indices[i][1],indices[i][2]);
		}

		glGenBuffers(1, &vbo);
		glBindBuffer(GL_ARRAY_BUFFER, vbo);
		glBufferData(GL_ARRAY_BUFFER, vertices.length * float.sizeof * 2, vertices.ptr, GL_STATIC_DRAW);

		glGenBuffers(1, &abo);
		glBindBuffer(GL_ARRAY_BUFFER, abo);
		glBufferData(GL_ARRAY_BUFFER, alpha.length * float.sizeof, alpha.ptr, GL_STATIC_DRAW);

		glGenBuffers(1, &eao);
		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, eao);
		glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.length * uint.sizeof * 3, indices.ptr, GL_STATIC_DRAW);

		glGenVertexArrays(1, &vao);
		glBindVertexArray(vao);
		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, eao);

		glEnableVertexAttribArray(0);
		glBindBuffer(GL_ARRAY_BUFFER, vbo);
		glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, null);

		glEnableVertexAttribArray(1);
		glBindBuffer(GL_ARRAY_BUFFER, abo);
		glVertexAttribPointer(1, 1, GL_FLOAT, GL_FALSE, 0, null);

		glBindVertexArray(0);
	}

	~this(){
		glDeleteVertexArrays(1, &vao);
		glDeleteBuffers(1, &vbo);
		glDeleteBuffers(1, &abo);
		glDeleteBuffers(1, &eao);
	}

	void update(Duration dt){}

	void render(RenderingContext* rc){
		glDepthMask(0);
		glBindVertexArray(vao);
		glDrawElements(GL_TRIANGLES, cast(uint)indices.length * 3, GL_UNSIGNED_INT, cast(void*)0);
		glBindVertexArray(0);
		glDepthMask(1);
	}
}

class ShapeSubQuad: Owner, Drawable{
	Vector2f[4] vertices;
	Vector2f[4] texcoords;
	uint[3][2] indices;

	GLuint vao = 0;
	GLuint vbo = 0;
	GLuint tbo = 0;
	GLuint eao = 0;

	this(Owner o,float left,float top,float right,float bottom){
		super(o);

		vertices[0] = Vector2f(0, 1);
		vertices[1] = Vector2f(0, 0);
		vertices[2] = Vector2f(1, 0);
		vertices[3] = Vector2f(1, 1);

		texcoords[0] = Vector2f(left, bottom);
		texcoords[1] = Vector2f(left, top);
		texcoords[2] = Vector2f(right, top);
		texcoords[3] = Vector2f(right, bottom);

		indices[0][0] = 0;
		indices[0][1] = 2;
		indices[0][2] = 1;

		indices[1][0] = 0;
		indices[1][1] = 3;
		indices[1][2] = 2;

		glGenBuffers(1, &vbo);
		glBindBuffer(GL_ARRAY_BUFFER, vbo);
		glBufferData(GL_ARRAY_BUFFER, vertices.length * float.sizeof * 2, vertices.ptr, GL_STATIC_DRAW);

		glGenBuffers(1, &tbo);
		glBindBuffer(GL_ARRAY_BUFFER, tbo);
		glBufferData(GL_ARRAY_BUFFER, texcoords.length * float.sizeof * 2, texcoords.ptr, GL_STATIC_DRAW);

		glGenBuffers(1, &eao);
		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, eao);
		glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.length * uint.sizeof * 3, indices.ptr, GL_STATIC_DRAW);

		glGenVertexArrays(1, &vao);
		glBindVertexArray(vao);
		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, eao);

		glEnableVertexAttribArray(0);
		glBindBuffer(GL_ARRAY_BUFFER, vbo);
		glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, null);

		glEnableVertexAttribArray(1);
		glBindBuffer(GL_ARRAY_BUFFER, tbo);
		glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 0, null);

		glBindVertexArray(0);
	}

	~this(){
		glDeleteVertexArrays(1, &vao);
		glDeleteBuffers(1, &vbo);
		glDeleteBuffers(1, &tbo);
		glDeleteBuffers(1, &eao);
	}

	void update(Duration dt){ }

	void render(RenderingContext* rc){
		glDepthMask(0);
		glBindVertexArray(vao);
		glDrawElements(GL_TRIANGLES, cast(uint)indices.length * 3, GL_UNSIGNED_INT, cast(void*)0);
		glBindVertexArray(0);
		glDepthMask(1);
	}
}

class ShapeSacStatsFrame: Owner, Drawable{
	Vector2f[8] vertices;
	Vector2f[8] texcoords;
	uint[3][4] indices;

	GLuint vao = 0;
	GLuint vbo = 0;
	GLuint tbo = 0;
	GLuint eao = 0;

	this(Owner o){
		super(o);

		vertices[0] = Vector2f(0, 0.5);
		vertices[1] = Vector2f(0, 0);
		vertices[2] = Vector2f(1, 0);
		vertices[3] = Vector2f(1, 0.5);

		vertices[4] = Vector2f(0, 1);
		vertices[5] = Vector2f(0, 0.5);
		vertices[6] = Vector2f(1, 0.5);
		vertices[7] = Vector2f(1, 1);

		texcoords[0] = Vector2f(0.5, 0.25-1.0/128);
		texcoords[1] = Vector2f(0.5, 0);
		texcoords[2] = Vector2f(0.75-1.0/128, 0);
		texcoords[3] = Vector2f(0.75-1.0/128, 0.25-1.0/128);

		texcoords[4] = Vector2f(0.5, 1.0/128);
		texcoords[5] = Vector2f(0.5, 0.25-0.5/128);
		texcoords[6] = Vector2f(0.75-1.0/128, 0.25-0.5/128);
		texcoords[7] = Vector2f(0.75-1.0/128, 1.0/128);

		indices[0][0] = 0;
		indices[0][1] = 2;
		indices[0][2] = 1;

		indices[1][0] = 0;
		indices[1][1] = 3;
		indices[1][2] = 2;

		indices[2][0] = 4;
		indices[2][1] = 6;
		indices[2][2] = 5;

		indices[3][0] = 4;
		indices[3][1] = 7;
		indices[3][2] = 6;

		glGenBuffers(1, &vbo);
		glBindBuffer(GL_ARRAY_BUFFER, vbo);
		glBufferData(GL_ARRAY_BUFFER, vertices.length * float.sizeof * 2, vertices.ptr, GL_STATIC_DRAW);

		glGenBuffers(1, &tbo);
		glBindBuffer(GL_ARRAY_BUFFER, tbo);
		glBufferData(GL_ARRAY_BUFFER, texcoords.length * float.sizeof * 2, texcoords.ptr, GL_STATIC_DRAW);

		glGenBuffers(1, &eao);
		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, eao);
		glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.length * uint.sizeof * 3, indices.ptr, GL_STATIC_DRAW);

		glGenVertexArrays(1, &vao);
		glBindVertexArray(vao);
		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, eao);

		glEnableVertexAttribArray(0);
		glBindBuffer(GL_ARRAY_BUFFER, vbo);
		glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, null);

		glEnableVertexAttribArray(1);
		glBindBuffer(GL_ARRAY_BUFFER, tbo);
		glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 0, null);

		glBindVertexArray(0);
	}

	~this(){
		glDeleteVertexArrays(1, &vao);
		glDeleteBuffers(1, &vbo);
		glDeleteBuffers(1, &tbo);
		glDeleteBuffers(1, &eao);
	}

	void update(Duration dt){ }

	void render(RenderingContext* rc){
		glDepthMask(0);
		glBindVertexArray(vao);
		glDrawElements(GL_TRIANGLES, cast(uint)indices.length * 3, GL_UNSIGNED_INT, cast(void*)0);
		glBindVertexArray(0);
		glDepthMask(1);
	}
}

class ShapeCooldown: Owner, Drawable{
	Vector2f[6] vertices;
	float[6] index;
	uint[3][4] indices;

	GLuint vao = 0;
	GLuint vbo = 0;
	GLuint vio = 0;
	GLuint eao = 0;

	this(Owner o){
		super(o);
		auto unit = sqrt(0.5f);
		vertices[0] = Vector2f(0, 0);
		vertices[1] = Vector2f(0, -unit);
		vertices[2] = Vector2f(unit, 0);
		vertices[3] = Vector2f(0, unit);
		vertices[4] = Vector2f(-unit, 0);
		vertices[5] = vertices[1];

		index=[0,1,2,3,4,5];

		indices[0] = [0,2,1];
		indices[1] = [0,3,2];
		indices[2] = [0,4,3];
		indices[3] = [0,5,4];

		glGenBuffers(1, &vbo);
		glBindBuffer(GL_ARRAY_BUFFER, vbo);
		glBufferData(GL_ARRAY_BUFFER, vertices.length * float.sizeof * 2, vertices.ptr, GL_STATIC_DRAW);

		glGenBuffers(1, &vio);
		glBindBuffer(GL_ARRAY_BUFFER, vio);
		glBufferData(GL_ARRAY_BUFFER, index.length * int.sizeof, index.ptr, GL_STATIC_DRAW);

		glGenBuffers(1, &eao);
		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, eao);
		glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.length * uint.sizeof * 3, indices.ptr, GL_STATIC_DRAW);

		glGenVertexArrays(1, &vao);
		glBindVertexArray(vao);
		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, eao);

		glEnableVertexAttribArray(0);
		glBindBuffer(GL_ARRAY_BUFFER, vbo);
		glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, null);

		glEnableVertexAttribArray(1);
		glBindBuffer(GL_ARRAY_BUFFER, vio);
		glVertexAttribPointer(1, 1, GL_FLOAT, GL_FALSE, 0, null);

		glBindVertexArray(0);
	}

	~this(){
		glDeleteVertexArrays(1, &vao);
		glDeleteBuffers(1, &vbo);
		glDeleteBuffers(1, &vio);
		glDeleteBuffers(1, &eao);
	}

	void update(Duration dt){ }

	void render(RenderingContext* rc){
		glDepthMask(0);
		glBindVertexArray(vao);
		glDrawElements(GL_TRIANGLES, cast(uint)indices.length * 3, GL_UNSIGNED_INT, cast(void*)0);
		glBindVertexArray(0);
		glDepthMask(1);
	}
}
