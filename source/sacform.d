import std.exception, std.algorithm, std.conv: to;
import std.range: iota,chain;
import dlib.math;
import util;
import form,txtr,sacfont,nttData;


enum FormTexture{
	formBackground,
	formBorder,
	formTitlebar,
	formPart1,
	formPart2,
	formPart3,
	formPart4,
	formPart5,
	formPart6,
	blueButtonBackground,
	buttonBackground,
	entryboxBackground,
	textboxBackground,
	textboxBorder,
	sliderBackground,
	progressbar,
}

struct SacFormPart(B){
	B.Mesh2D[2] mesh; // [inactive, active]
	B.Texture texture;

	this(B.Mesh2D mesh,FormTexture texture){
		this(mesh,mesh,texture);
	}
	this(B.Mesh2D inactiveMesh,B.Mesh2D activeMesh,FormTexture texture){
		this(inactiveMesh,activeMesh,SacForm!B.getTexture(texture));
	}
	this(B.Mesh2D mesh,B.Texture texture){
		this(mesh,mesh,texture);
	}
	this(B.Mesh2D inactiveMesh,B.Mesh2D activeMesh,B.Texture texture){
		this.mesh=[inactiveMesh,activeMesh];
		this.texture=texture;
	}
}


enum FormFont{
	standard,
	smallTitle,
	largeTitle,
}

FormFont titleFont(bool isLarge){
	return isLarge?FormFont.largeTitle:FormFont.smallTitle;}

FontType formFontType(FormFont which){
	final switch(which) with(FormFont){
		case standard: return FontType.fnwt;
		case smallTitle: return FontType.fn08;
		case largeTitle: return FontType.fn12;
	}
}
FontType titleFontType(bool isLarge){
	return formFontType(titleFont(isLarge));
}

SacFont!B formSacFont(B)(FormFont which){
	return SacFont!B.get(formFontType(which));
}
SacFont!B titleSacFont(B)(bool isLarge){
	return SacFont!B.get(titleFontType(isLarge));
}

struct SacFormText{
	string text;
	Vector2f position;
	FormFont font;
}

string formTextFromTag(char[4] tag){
	if(tag=="\0\0\0\0") return null;
	return formTexts.get(tag,"");
}

string mouseoverTextFromTag(char[4] tag){
	if(tag=="\0\0\0\0") return null;
	return mouseoverTexts.get(tag,formTexts.get(tag,""));
}

struct SubSacForm(B){
	Vector2f offset;
	SacForm!B form;
}

struct SacFormElement(B){
	ElementType type;
	char[4] id;
	Vector2f offset;
	Vector2f size;
	SacFormPart!B[] parts;
	SacFormText[] texts;
	string mouseoverText;
	int formIndex=-1;
	SubSacForm!B[] subForms;
}


B.Mesh2D makeQuad(B)(Vector2f offset,Vector2f size,Vector2f texOffset,Vector2f texSize,bool flippedX,bool flippedY,bool swapCoords=false){
	auto mesh=B.makeMesh2D(4,2);
	mesh.vertices[0]=Vector2f(offset.x,offset.y+size.y);
	mesh.vertices[1]=Vector2f(offset.x,offset.y);
	mesh.vertices[2]=Vector2f(offset.x+size.x,offset.y);
	mesh.vertices[3]=Vector2f(offset.x+size.x,offset.y+size.y,0.0f);
	mesh.texcoords[0]=Vector2f(flippedX?texSize.x:0.0f, flippedY?0.0f:texSize.y);
	mesh.texcoords[1]=Vector2f(flippedX?texSize.x:0.0f, flippedY?texSize.y:0.0f);
	mesh.texcoords[2]=Vector2f(flippedX?0.0f:texSize.x, flippedY?texSize.y:0.0f);
	mesh.texcoords[3]=Vector2f(flippedX?0.0f:texSize.x, flippedY?0.0f:texSize.y);
	if(swapCoords) foreach(ref coord;mesh.texcoords) swap(coord.x,coord.y);
	foreach(ref coord;mesh.texcoords) coord+=texOffset;
	mesh.indices[0]=[0,2,1];
	mesh.indices[1]=[0,3,2];
	B.finalizeMesh2D(mesh);
	return mesh;
}

auto makeForm(B)(Vector2f offset,char[4] id,Vector2f size,string title,bool largeTitle,bool background,bool border){
	SacFormPart!B[] parts;
	auto backOffset=offset;
	auto backSize=size;
	if(title){
		backOffset.y+=16;
		backSize.y-=16;
	}
	if(border){
		backOffset+=Vector2f(8.0f,8.0f);
		backSize-=Vector2f(16.0f,16.0f);
	}
	if(background){
		auto back=makeQuad!B(backOffset,backSize,Vector2f(0.0f,0.0f),(1.0f/32.0f)*backSize,false,false);
		parts~=SacFormPart!B(back,FormTexture.formBackground);
	}

	if(border){
		auto cornerOffset=offset;
		auto topCornerOffset=cornerOffset;
		if(title) topCornerOffset.y+=16;

		auto cornerSize=Vector2f(32.0f,32.0f);
		auto cornerTexOffInactive=Vector2f(0.5f/64.0f,0.5f/64.0f);
		auto cornerTexOffActive=Vector2f(0.5f+0.5f/64.0f,0.5f/64.0f);
		auto cornerTexSize=Vector2f(0.5f-1.0f/64.0f,0.5f-1.0f/64.0f);


		auto outerEdgeSize=Vector2f(16.0f,16.0f);
		auto outerEdgeTexOff=Vector2f(0.5f/32.0f,0.5f+(0.5f/32.0f));
		auto outerEdgeTexSize=Vector2f(0.5f-1.0f/32.0f,0.5f-1.0f/32.0f);

		auto innerEdgeSize=Vector2f(16.0f,16.0f);
		auto innerEdgeTexOff=Vector2f(0.5f+0.5f/32.0f,0.5f+(0.5f/32.0f));
		auto innerEdgeTexSize=Vector2f(0.5f-1.0f/32.0f,0.5f-1.0f/32.0f);

		auto horizontalBorderSize=Vector2f(size.x-2.0f*(cornerSize.x+outerEdgeSize.x+innerEdgeSize.x),16.0f);
		auto verticalBorderSize=Vector2f(16.0f,size.y-2.0f*(cornerSize.y+outerEdgeSize.y+innerEdgeSize.y));
		if(title) verticalBorderSize.y-=16.0f;

		if(horizontalBorderSize.x>0.0f){
			auto horizontalBorderTexOff=(1.0f/16.0f)*Vector2f(0.5f,0.5f);
			auto horizontalBorderTexSize=(1.0f/16.0f)*(horizontalBorderSize-Vector2f(1.0f,1.0f));

			auto topBorder=makeQuad!B(topCornerOffset+Vector2f(cornerSize.x+outerEdgeSize.x+innerEdgeSize.x,0.0f),horizontalBorderSize,horizontalBorderTexOff,horizontalBorderTexSize,false,true);
			parts~=SacFormPart!B(topBorder,FormTexture.formBorder);

			auto bottomBorder=makeQuad!B(cornerOffset+Vector2f(cornerSize.x+outerEdgeSize.x+innerEdgeSize.x,size.y-horizontalBorderSize.y),horizontalBorderSize,horizontalBorderTexOff,horizontalBorderTexSize,false,false);
			parts~=SacFormPart!B(bottomBorder,FormTexture.formBorder);
		}

		if(verticalBorderSize.y>0.0f){
			auto verticalBorderTexOff=(1.0f/16.0f)*Vector2f(0.5f,0.5f);
			auto verticalBorderTexSize=(1.0f/16.0f)*(verticalBorderSize-Vector2f(1.0f,1.0f));

			auto leftBorder=makeQuad!B(topCornerOffset+Vector2f(0.0f,cornerSize.y+outerEdgeSize.y+innerEdgeSize.y),verticalBorderSize,verticalBorderTexOff,verticalBorderTexSize,true,false,true);
			parts~=SacFormPart!B(leftBorder,FormTexture.formBorder);

			auto rightBorder=makeQuad!B(topCornerOffset+Vector2f(size.x-verticalBorderSize.x,cornerSize.y+outerEdgeSize.y+innerEdgeSize.y),verticalBorderSize,verticalBorderTexOff,verticalBorderTexSize,false,false,true);
			parts~=SacFormPart!B(rightBorder,FormTexture.formBorder);
		}

		auto leftTopInnerEdge=makeQuad!B(topCornerOffset+Vector2f(0.0f,cornerSize.y+outerEdgeSize.y),outerEdgeSize,innerEdgeTexOff,innerEdgeTexSize,false,false);
		parts~=SacFormPart!B(leftTopInnerEdge,FormTexture.formPart2);
		auto leftTopOuterEdge=makeQuad!B(topCornerOffset+Vector2f(0.0f,cornerSize.y),outerEdgeSize,outerEdgeTexOff,outerEdgeTexSize,false,false);
		parts~=SacFormPart!B(leftTopOuterEdge,FormTexture.formPart2);
		auto topLeftInnerEdge=makeQuad!B(topCornerOffset+Vector2f(cornerSize.x+outerEdgeSize.x,0.0f),outerEdgeSize,innerEdgeTexOff,innerEdgeTexSize,false,false,true);
		parts~=SacFormPart!B(topLeftInnerEdge,FormTexture.formPart2);
		auto topLeftOuterEdge=makeQuad!B(topCornerOffset+Vector2f(cornerSize.x,0.0f),outerEdgeSize,outerEdgeTexOff,outerEdgeTexSize,false,false,true);
		parts~=SacFormPart!B(topLeftOuterEdge,FormTexture.formPart2);
		auto rightTopInnerEdge=makeQuad!B(topCornerOffset+Vector2f(size.x-outerEdgeSize.x,cornerSize.y+outerEdgeSize.y),outerEdgeSize,innerEdgeTexOff,innerEdgeTexSize,true,false);
		parts~=SacFormPart!B(rightTopInnerEdge,FormTexture.formPart2);
		auto rightTopOuterEdge=makeQuad!B(topCornerOffset+Vector2f(size.x-outerEdgeSize.x,cornerSize.y),outerEdgeSize,outerEdgeTexOff,outerEdgeTexSize,true,false);
		parts~=SacFormPart!B(rightTopOuterEdge,FormTexture.formPart2);
		auto topRightInnerEdge=makeQuad!B(topCornerOffset+Vector2f(size.x-cornerSize.x-outerEdgeSize.x-innerEdgeSize.x,0.0f),outerEdgeSize,innerEdgeTexOff,innerEdgeTexSize,true,false,true);
		parts~=SacFormPart!B(topRightInnerEdge,FormTexture.formPart2);
		auto topRightOuterEdge=makeQuad!B(topCornerOffset+Vector2f(size.x-cornerSize.x-outerEdgeSize.x,0.0f),outerEdgeSize,outerEdgeTexOff,outerEdgeTexSize,true,false,true);
		parts~=SacFormPart!B(topRightOuterEdge,FormTexture.formPart2);
		auto leftBottomInnerEdge=makeQuad!B(cornerOffset+Vector2f(0.0f,size.y-cornerSize.y-outerEdgeSize.y-innerEdgeSize.y),outerEdgeSize,innerEdgeTexOff,innerEdgeTexSize,false,true);
		parts~=SacFormPart!B(leftBottomInnerEdge,FormTexture.formPart2);
		auto leftBottomOuterEdge=makeQuad!B(cornerOffset+Vector2f(0.0f,size.y-cornerSize.y-outerEdgeSize.y),outerEdgeSize,outerEdgeTexOff,outerEdgeTexSize,false,true);
		parts~=SacFormPart!B(leftBottomOuterEdge,FormTexture.formPart2);
		auto bottomLeftInnerEdge=makeQuad!B(cornerOffset+Vector2f(cornerSize.x+outerEdgeSize.x,size.y-innerEdgeSize.y),outerEdgeSize,innerEdgeTexOff,innerEdgeTexSize,false,true,true);
		parts~=SacFormPart!B(bottomLeftInnerEdge,FormTexture.formPart2);
		auto bottomLeftOuterEdge=makeQuad!B(cornerOffset+Vector2f(cornerSize.x,size.y-outerEdgeSize.y),outerEdgeSize,outerEdgeTexOff,outerEdgeTexSize,false,true,true);
		parts~=SacFormPart!B(bottomLeftOuterEdge,FormTexture.formPart2);
		auto rightBottomInnerEdge=makeQuad!B(cornerOffset+Vector2f(size.x-outerEdgeSize.x,size.y-cornerSize.x-outerEdgeSize.x-innerEdgeSize.y),outerEdgeSize,innerEdgeTexOff,innerEdgeTexSize,true,true);
		parts~=SacFormPart!B(rightBottomInnerEdge,FormTexture.formPart2);
		auto rightBottomOuterEdge=makeQuad!B(cornerOffset+Vector2f(size.x-outerEdgeSize.x,size.y-cornerSize.y-outerEdgeSize.y),outerEdgeSize,outerEdgeTexOff,outerEdgeTexSize,true,true);
		parts~=SacFormPart!B(rightBottomOuterEdge,FormTexture.formPart2);
		auto bottomRightInnerEdge=makeQuad!B(cornerOffset+Vector2f(size.x-cornerSize.x-outerEdgeSize.x-innerEdgeSize.x,size.y-innerEdgeSize.y),outerEdgeSize,innerEdgeTexOff,innerEdgeTexSize,true,true,true);
		parts~=SacFormPart!B(bottomRightInnerEdge,FormTexture.formPart2);
		auto bottomRightOuterEdge=makeQuad!B(cornerOffset+Vector2f(size.x-cornerSize.x-outerEdgeSize.y,size.y-outerEdgeSize.y),outerEdgeSize,outerEdgeTexOff,outerEdgeTexSize,true,true,true);
		parts~=SacFormPart!B(bottomRightOuterEdge,FormTexture.formPart2);

		auto topLeftInactive=makeQuad!B(topCornerOffset,cornerSize,cornerTexOffInactive,cornerTexSize,false,false);
		auto topLeftActive=makeQuad!B(topCornerOffset,cornerSize,cornerTexOffActive,cornerTexSize,false,false);
		parts~=SacFormPart!B(topLeftInactive,topLeftActive,FormTexture.formPart1);

		auto topRightInactive=makeQuad!B(topCornerOffset+Vector2f(size.x-cornerSize.x,0.0f),cornerSize,cornerTexOffInactive,cornerTexSize,true,false);
		auto topRightActive=makeQuad!B(topCornerOffset+Vector2f(size.x-cornerSize.x,0.0f),cornerSize,cornerTexOffActive,cornerTexSize,true,false);
		parts~=SacFormPart!B(topRightInactive,topRightActive,FormTexture.formPart1);

		auto bottomLeftInactive=makeQuad!B(cornerOffset+Vector2f(0.0f,size.y-cornerSize.y),cornerSize,cornerTexOffInactive,cornerTexSize,false,true);
		auto bottomLeftActive=makeQuad!B(cornerOffset+Vector2f(0.0f,size.y-cornerSize.y),cornerSize,cornerTexOffActive,cornerTexSize,false,true);
		parts~=SacFormPart!B(bottomLeftInactive,bottomLeftActive,FormTexture.formPart1);

		auto bottomRightInactive=makeQuad!B(cornerOffset+Vector2f(size.x-cornerSize.x,size.y-cornerSize.y),cornerSize,cornerTexOffInactive,cornerTexSize,true,true);
		auto bottomRightActive=makeQuad!B(cornerOffset+Vector2f(size.x-cornerSize.x,size.y-cornerSize.y),cornerSize,cornerTexOffActive,cornerTexSize,true,true);
		parts~=SacFormPart!B(bottomRightInactive,bottomRightActive,FormTexture.formPart1);
	}
	SacFormText[] texts;
	if(title){
		auto titleOffset=offset;
		auto cornerSize=Vector2f(32.0f,32.0f);
		auto cornerTexOffInactive=Vector2f((0.5f/64.0f),0.5f+(0.5f/64.0f));
		auto cornerTexOffActive=Vector2f(0.5f+(0.5f/64.0f),0.5f+(0.5f/64.0f));
		auto cornerTexSize=Vector2f(0.5f-1.0f/64.0f,0.5f-1.0f/64.0f);

		auto cornerLeftInactive=makeQuad!B(titleOffset,cornerSize,cornerTexOffInactive,cornerTexSize,false,false);
		auto cornerLeftActive=makeQuad!B(titleOffset,cornerSize,cornerTexOffActive,cornerTexSize,false,false);
		parts~=SacFormPart!B(cornerLeftInactive,cornerLeftActive,FormTexture.formPart1);

		auto cornerRightInactive=makeQuad!B(titleOffset+Vector2f(size.x-cornerSize.x,0.0f),cornerSize,cornerTexOffInactive,cornerTexSize,true,false);
		auto cornerRightActive=makeQuad!B(titleOffset+Vector2f(size.x-cornerSize.x,0.0f),cornerSize,cornerTexOffActive,cornerTexSize,true,false);
		parts~=SacFormPart!B(cornerRightInactive,cornerRightActive,FormTexture.formPart1);

		auto titlebarSize=Vector2f(size.x-2.0f*cornerSize.x,32.0f);
		auto titlebarTexOff=(1.0f/32.0f)*Vector2f(0.5f,0.5f);
		auto titlebarTexSize=(1.0f/32.0f)*(titlebarSize-Vector2f(1.0f,1.0f));
		auto titlebar=makeQuad!B(titleOffset+Vector2f(cornerSize.x,0.0f),titlebarSize,titlebarTexOff,titlebarTexSize,false,false);
		parts~=SacFormPart!B(titlebar,FormTexture.formTitlebar);

		auto font=titleSacFont!B(largeTitle);
		auto settings=FormatSettings();
		auto titleSize=font.getSize(title,settings);
		auto position=titleOffset+Vector2f(0.5f*(size.x-titleSize.x),7);
		texts~=SacFormText(title,position,titleFont(largeTitle));
	}
	string mouseoverText=null;
	int formIndex=-1;
	return SacFormElement!B(ElementType.form,id,offset,size,parts,texts,mouseoverText,formIndex);
}

auto makeBasicElement(B)(ElementType type,Vector2f offset,char[4] id,Vector2f size,string text,bool largeText,string mouseoverText,int formIndex)in{
	assert(type==ElementType.button||type==ElementType.entrybox||type==ElementType.checkbox||type==ElementType.slider||type==ElementType.dropdown);
}do{
	SacFormPart!B[] parts;
	auto cornerSize=Vector2f(16.0f,size.y);
	auto cornerTexOffInactive=Vector2f(0.5f/32.0f,0.5f/32.0f);
	auto cornerTexOffActive=Vector2f(0.5f+0.5f/32.0f,0.5f/32.0f);
	auto cornerTexSize=Vector2f(0.5f-1.0f/32.0f,0.5f-1.0f/32.0f);

	auto cornerTexture=type==ElementType.slider?FormTexture.formPart5:FormTexture.formPart2;

	auto cornerLeftInactive=makeQuad!B(offset,cornerSize,cornerTexOffInactive,cornerTexSize,false,false);
	auto cornerLeftActive=makeQuad!B(offset,cornerSize,cornerTexOffActive,cornerTexSize,false,false);
	parts~=SacFormPart!B(cornerLeftInactive,cornerLeftActive,cornerTexture);

	auto cornerRightInactive=makeQuad!B(offset+Vector2f(size.x-cornerSize.x,0.0f),cornerSize,cornerTexOffInactive,cornerTexSize,true,false);
	auto cornerRightActive=makeQuad!B(offset+Vector2f(size.x-cornerSize.x,0.0f),cornerSize,cornerTexOffActive,cornerTexSize,true,false);
	parts~=SacFormPart!B(cornerRightInactive,cornerRightActive,cornerTexture);

	auto barOffset=offset;
	auto barSize=Vector2f(size.x-2.0f*cornerSize.x,size.y);
	auto checkSize=Vector2f(16.0f,size.y);

	if(type==ElementType.checkbox){
		barOffset.x+=checkSize.x;
		barSize.x-=checkSize.x;
	}else if(type==ElementType.dropdown){
		barSize.x-=cornerSize.x;
	}

	auto barTexOff=(1.0f/16.0f)*Vector2f(0.5f,0.5f);
	auto barTexSize=(1.0f/16.0f)*(barSize-Vector2f(1.0f,1.0f));
	auto barTexture=type==ElementType.entrybox||type==ElementType.dropdown?FormTexture.entryboxBackground:type==ElementType.slider?FormTexture.sliderBackground:FormTexture.buttonBackground;
	auto bar=makeQuad!B(barOffset+Vector2f(cornerSize.x,0.0f),barSize,barTexOff,barTexSize,false,false);
	parts~=SacFormPart!B(bar,barTexture);

	if(type==ElementType.checkbox){
		auto checkOffset=offset+Vector2f(cornerSize.x,0.0f);
		auto checkTexOffInactive=Vector2f(0.5f/32.0f,0.5f/32.0f);
		auto checkTexOffActive=Vector2f(0.5f+0.5f/32.0f,0.5f/32.0f);
		auto checkTexSize=Vector2f(0.5f-1.0f/32.0f,0.5f-1.0f/32.0f);

		auto checkInactive=makeQuad!B(checkOffset,checkSize,checkTexOffInactive,checkTexSize,false,false);
		auto checkActive=makeQuad!B(checkOffset,checkSize,checkTexOffActive,checkTexSize,false,false);
		parts~=SacFormPart!B(checkInactive,checkActive,FormTexture.formPart4);
	}else if(type==ElementType.slider){
		auto sliderOffset=offset+Vector2f(cornerSize.x,0.0f);
		auto sliderSize=Vector2f(16.0f,16.0f);
		auto sliderTexOff=Vector2f(0.5f/32.0f,0.5f+0.5f/32.0f);
		auto sliderTexSize=Vector2f(0.5f-1.0f/32.0f,0.5f-1.0f/32.0f);

		auto slider=makeQuad!B(sliderOffset,sliderSize,sliderTexOff,sliderTexSize,false,false); // TODO: this should be moveable
		parts~=SacFormPart!B(slider,FormTexture.formPart5);
	}else if(type==ElementType.dropdown){
		auto arrowOffset=offset+Vector2f(size.x-2*cornerSize.x,0.0f);

		auto arrowInactive=makeQuad!B(arrowOffset,cornerSize,cornerTexOffInactive,cornerTexSize,true,true,true);
		auto arrowActive=makeQuad!B(arrowOffset,cornerSize,cornerTexOffActive,cornerTexSize,true,true,true);
		parts~=SacFormPart!B(arrowInactive,arrowActive,FormTexture.formPart5);
	}

	SacFormText[] texts;
	if(type!=ElementType.entrybox&&type!=ElementType.slider){
		auto font=titleSacFont!B(largeText);
		Vector2f position;
		if(type!=ElementType.checkbox){
			auto settings=FormatSettings();
			auto textSize=font.getSize(text,settings);
			position=offset+Vector2f(0.5f*(size.x-textSize.x),1.0f);
		}else{
			position=offset+Vector2f(cornerSize.x+checkSize.x+4.0f,1.0f);
		}
		texts~=SacFormText(text,position,titleFont(largeText));
	}
	return SacFormElement!B(type,id,offset,size,parts,texts,mouseoverText,formIndex);
}

auto makeButton(B)(Vector2f offset,char[4] id,Vector2f size,string text,bool largeText,string mouseoverText,int formIndex){
	return makeBasicElement!B(ElementType.button,offset,id,size,text,largeText,mouseoverText,formIndex);
}
auto makeEntrybox(B)(Vector2f offset,char[4] id,Vector2f size,string text,bool largeText,string mouseoverText,int formIndex){
	return makeBasicElement!B(ElementType.entrybox,offset,id,size,text,largeText,mouseoverText,formIndex);
}
auto makeCheckbox(B)(Vector2f offset,char[4] id,Vector2f size,string text,bool largeText,string mouseoverText,int formIndex){
	return makeBasicElement!B(ElementType.checkbox,offset,id,size,text,largeText,mouseoverText,formIndex);
}
auto makeSlider(B)(Vector2f offset,char[4] id,Vector2f size,string mouseoverText,int formIndex){
	return makeBasicElement!B(ElementType.slider,offset,id,size,null,false,mouseoverText,formIndex);
}
auto makeDropdown(B)(Vector2f offset,char[4] id,Vector2f size,string text,bool largeText,string mouseoverText,int formIndex){
	return makeBasicElement!B(ElementType.dropdown,offset,id,size,text,largeText,mouseoverText,formIndex);
}

auto makeSubSacForm(B)(Vector2f offset,char[4] id,Vector2f size,SacForm!B subForm,string mouseoverText,int formIndex){
	// TODO: does size matter?
	return SacFormElement!B(ElementType.form,id,offset,size,[],[],mouseoverText,formIndex,[SubSacForm!B(offset,subForm)]);
}

auto formPicturePath(Element element){
	auto tag=element.picture=="\0\0\0\0"?element.pictureOrForm:element.picture;
	return formIcons.get(tag,formTxtrs.get(tag,null));
}
auto makePicture(B)(Vector2f offset,char[4] id,Vector2f size,B.Texture texture,string mouseoverText,int formIndex){
	SacFormPart!B[] parts;
	auto picture=makeQuad!B(offset,size,Vector2f(0.0f,0.0f),Vector2f(1.0f,1.0f),false,false);
	parts~=SacFormPart!B(picture,texture);
	SacFormText[] texts;
	return SacFormElement!B(ElementType.picture,id,offset,size,parts,texts,mouseoverText,formIndex);
}

auto makeTextbox(B)(Vector2f offset,char[4] id,Vector2f size,string title,bool largeTitle,bool border,bool scrollbar,string mouseoverText,int formIndex){
	SacFormPart!B[] parts;
	auto backOffset=offset;
	auto backSize=size;
	if(title){
		backOffset.y+=8.0f;
		backSize.y-=8.0f;
	}
	if(border){
		backOffset+=Vector2f(8.0f,8.0f);
		backSize-=Vector2f(16.0f,16.0f);
	}
	auto back=makeQuad!B(backOffset,backSize,Vector2f(0.0f,0.0f),(1.0f/32.0f)*backSize,false,false);
	parts~=SacFormPart!B(back,FormTexture.textboxBackground);

	if(border){
		auto cornerOffset=offset;
		auto topCornerOffset=cornerOffset;
		if(title) topCornerOffset.y+=8.0f;

		auto cornerSize=Vector2f(8.0f,8.0f);
		auto cornerTexOffInactive=Vector2f(0.5f/32.0f,0.5f+0.5f/32.0f);
		auto cornerTexOffActive=Vector2f(0.25f+0.5f/32.0f,0.5f+0.5f/32.0f);
		auto cornerTexSize=Vector2f(0.25f-1.0f/32.0f,0.25f-1.0f/32.0f);

		auto horizontalBorderSize=Vector2f(size.x-2.0f*cornerSize.x,8.0f);
		auto verticalBorderSize=Vector2f(8.0f,size.y-2.0f*cornerSize.y);
		if(title) verticalBorderSize.y-=8.0f;

		if(horizontalBorderSize.x>0.0f){
			auto horizontalBorderTexOff=(1.0f/8.0f)*Vector2f(0.5f,0.5f);
			auto horizontalBorderTexSize=(1.0f/8.0f)*(horizontalBorderSize-Vector2f(1.0f,1.0f));

			auto topBorder=makeQuad!B(topCornerOffset+Vector2f(cornerSize.x,0.0f),horizontalBorderSize,horizontalBorderTexOff,horizontalBorderTexSize,false,true);
			parts~=SacFormPart!B(topBorder,FormTexture.textboxBorder);

			auto bottomBorder=makeQuad!B(cornerOffset+Vector2f(cornerSize.x,size.y-horizontalBorderSize.y),horizontalBorderSize,horizontalBorderTexOff,horizontalBorderTexSize,false,false);
			parts~=SacFormPart!B(bottomBorder,FormTexture.textboxBorder);
		}

		if(verticalBorderSize.y>0.0f){
			auto verticalBorderTexOff=(1.0f/8.0f)*Vector2f(0.5f,0.5f);
			auto verticalBorderTexSize=(1.0f/8.0f)*(verticalBorderSize-Vector2f(1.0f,1.0f));

			auto leftBorder=makeQuad!B(topCornerOffset+Vector2f(0.0f,cornerSize.y),verticalBorderSize,verticalBorderTexOff,verticalBorderTexSize,true,false,true);
			parts~=SacFormPart!B(leftBorder,FormTexture.textboxBorder);

			auto rightBorder=makeQuad!B(topCornerOffset+Vector2f(size.x-verticalBorderSize.x,cornerSize.y),verticalBorderSize,verticalBorderTexOff,verticalBorderTexSize,false,false,true);
			parts~=SacFormPart!B(rightBorder,FormTexture.textboxBorder);
		}

		auto topLeftInactive=makeQuad!B(topCornerOffset,cornerSize,cornerTexOffInactive,cornerTexSize,false,true);
		auto topLeftActive=makeQuad!B(topCornerOffset,cornerSize,cornerTexOffActive,cornerTexSize,false,true);
		parts~=SacFormPart!B(topLeftInactive,topLeftActive,FormTexture.formPart3);

		auto topRightInactive=makeQuad!B(topCornerOffset+Vector2f(size.x-cornerSize.x,0.0f),cornerSize,cornerTexOffInactive,cornerTexSize,true,true);
		auto topRightActive=makeQuad!B(topCornerOffset+Vector2f(size.x-cornerSize.x,0.0f),cornerSize,cornerTexOffActive,cornerTexSize,true,true);
		parts~=SacFormPart!B(topRightInactive,topRightActive,FormTexture.formPart3);

		auto bottomLeftInactive=makeQuad!B(cornerOffset+Vector2f(0.0f,size.y-cornerSize.y),cornerSize,cornerTexOffInactive,cornerTexSize,false,false);
		auto bottomLeftActive=makeQuad!B(cornerOffset+Vector2f(0.0f,size.y-cornerSize.y),cornerSize,cornerTexOffActive,cornerTexSize,false,false);
		parts~=SacFormPart!B(bottomLeftInactive,bottomLeftActive,FormTexture.formPart3);

		auto bottomRightInactive=makeQuad!B(cornerOffset+Vector2f(size.x-cornerSize.x,size.y-cornerSize.y),cornerSize,cornerTexOffInactive,cornerTexSize,true,false);
		auto bottomRightActive=makeQuad!B(cornerOffset+Vector2f(size.x-cornerSize.x,size.y-cornerSize.y),cornerSize,cornerTexOffActive,cornerTexSize,true,false);
		parts~=SacFormPart!B(bottomRightInactive,bottomRightActive,FormTexture.formPart3);
	}
	if(scrollbar){
		auto arrowSize=Vector2f(16.0f,16.0f);
		auto arrowTexOffInactive=Vector2f(0.5f/32.0f,0.5f/32.0f);
		auto arrowTexOffActive=Vector2f(0.5f+0.5f/32.0f,0.5f/32.0f);
		auto arrowTexSize=Vector2f(0.5f-1.0f/32.0f,0.5f-1.0f/32.0f);

		auto scrollbarOffset=backOffset+Vector2f(backSize.x-arrowSize.x,0.0f);
		auto topArrowOffset=scrollbarOffset;
		auto bottomArrowOffset=topArrowOffset+Vector2f(0.0f,backSize.y-arrowSize.y);

		auto sliderBackgroundOffset=scrollbarOffset+Vector2f(0.0f,arrowSize.y);
		auto sliderBackgroundSize=Vector2f(16.0f,backSize.y-2.0f*arrowSize.y);
		auto sliderBackgroundTexOff=(1.0f/16.0f)*Vector2f(0.5f,0.5f);
		auto sliderBackgroundTexSize=(1.0f/16.0f)*(sliderBackgroundSize-Vector2f(1.0f,1.0f));

		auto sliderBackground=makeQuad!B(sliderBackgroundOffset,sliderBackgroundSize,sliderBackgroundTexOff,sliderBackgroundTexSize,true,false,true);
		parts~=SacFormPart!B(sliderBackground,FormTexture.sliderBackground);

		auto topArrowInactive=makeQuad!B(scrollbarOffset,arrowSize,arrowTexOffInactive,arrowTexSize,true,false,true);
		auto topArrowActive=makeQuad!B(scrollbarOffset,arrowSize,arrowTexOffActive,arrowTexSize,true,false,true);
		parts~=SacFormPart!B(topArrowInactive,topArrowActive,FormTexture.formPart5);

		auto bottomArrowInactive=makeQuad!B(bottomArrowOffset,arrowSize,arrowTexOffInactive,arrowTexSize,true,true,true);
		auto bottomArrowActive=makeQuad!B(bottomArrowOffset,arrowSize,arrowTexOffActive,arrowTexSize,true,true,true);
		parts~=SacFormPart!B(bottomArrowInactive,bottomArrowActive,FormTexture.formPart5);

		auto sliderOffset=scrollbarOffset+Vector2f(0.0f,arrowSize.y); // TODO: this should be moveable
		auto sliderSize=Vector2f(16.0f,16.0f);
		auto sliderTexOff=Vector2f(0.5f/32.0f,0.5f+0.5f/32.0f);
		auto sliderTexSize=Vector2f(0.5f-1.0f/32.0f,0.5f-1.0f/32.0f);
		auto slider=makeQuad!B(sliderOffset,sliderSize,sliderTexOff,sliderTexSize,true,false,true);
		parts~=SacFormPart!B(slider,FormTexture.formPart5);
	}
	SacFormText[] texts;
	if(title){
		auto titleOffset=offset;
		auto cornerSize=Vector2f(16.0f,16.0f);
		auto cornerTexOffInactive=Vector2f(0.5f/32.0f,0.5f/32.0f);
		auto cornerTexOffActive=Vector2f(0.5f+0.5f/32.0f,0.5f/32.0f);
		auto cornerTexSize=Vector2f(0.5f-1.0f/32.0f,0.5f-1.0f/32.0f);

		auto cornerLeftInactive=makeQuad!B(titleOffset,cornerSize,cornerTexOffInactive,cornerTexSize,false,false);
		auto cornerLeftActive=makeQuad!B(titleOffset,cornerSize,cornerTexOffActive,cornerTexSize,false,false);
		parts~=SacFormPart!B(cornerLeftInactive,cornerLeftActive,FormTexture.formPart3);

		auto cornerRightInactive=makeQuad!B(titleOffset+Vector2f(size.x-cornerSize.x,0.0f),cornerSize,cornerTexOffInactive,cornerTexSize,true,false);
		auto cornerRightActive=makeQuad!B(titleOffset+Vector2f(size.x-cornerSize.x,0.0f),cornerSize,cornerTexOffActive,cornerTexSize,true,false);
		parts~=SacFormPart!B(cornerRightInactive,cornerRightActive,FormTexture.formPart3);

		auto titlebarSize=Vector2f(size.x-2.0f*cornerSize.x,16.0f);
		auto titlebarTexOff=(1.0f/16.0f)*Vector2f(0.5f,0.5f);
		auto titlebarTexSize=(1.0f/16.0f)*(titlebarSize-Vector2f(1.0f,1.0f));
		auto titlebar=makeQuad!B(titleOffset+Vector2f(cornerSize.x,0.0f),titlebarSize,titlebarTexOff,titlebarTexSize,false,false);
		parts~=SacFormPart!B(titlebar,FormTexture.buttonBackground);

		auto font=titleSacFont!B(largeTitle);
		auto settings=FormatSettings();
		auto titleSize=font.getSize(title,settings);
		auto position=titleOffset+Vector2f(0.5f*(size.x-titleSize.x),1);
		texts~=SacFormText(title,position,titleFont(largeTitle));
	}

	return SacFormElement!B(ElementType.textbox,id,offset,size,parts,texts,mouseoverText,formIndex);
}

auto makeText(B)(Vector2f offset,char[4] id,Vector2f size,string text,FormFont formFont,bool centerX,bool centerY,string mouseoverText,int formIndex){
	SacFormPart!B[] parts;
	SacFormText[] texts;
	auto font=formSacFont!B(formFont);
	auto settings=FormatSettings();
	auto textSize=font.getSize(text,settings);
	auto textOffset=offset;
	if(centerX) textOffset.x=offset.x+0.5f*(size.x-textSize.x);
	if(centerY) textOffset.y=offset.y+0.5f*(size.y-textSize.y);
	texts~=SacFormText(text,textOffset,formFont); // TODO: this offset is not fully accurate, but it is not so clear why
	return SacFormElement!B(ElementType.text,id,offset,size,parts,texts,mouseoverText,formIndex);
}

auto makeSacFormElement(B)(Vector2f globalOffset,Vector2f backgroundSize,Element element,int formIndex){
	auto centerX=!!(element.flags&ElementFlags.centerHorizontally);
	auto centerY=!!(element.flags&ElementFlags.centerVertically);
	enum center=q{
		if(centerX) offset.x=0.5f*(backgroundSize.x-size.x);
		if(centerY) offset.y=0.5f*(backgroundSize.y-size.y);
	};
	switch(element.type) with(ElementType){
		case button:
			auto offset=globalOffset+Vector2f(element.left,element.top);
			auto size=Vector2f(element.width,16.0f);
			mixin(center);
			auto text=formTextFromTag(element.text);
			auto largeText=!!(element.flags&ElementFlags.largeText);
			auto mouseoverText=mouseoverTextFromTag(element.mouseover);
			return makeButton!B(offset,element.id,size,text,largeText,mouseoverText,formIndex);
		case form:
			auto offset=globalOffset+Vector2f(element.left,element.top);
			auto size=Vector2f(element.width,element.height);
			mixin(center);
			auto form=SacForm!B.get(element.pictureOrForm);
			auto mouseoverText=mouseoverTextFromTag(element.mouseover);
			return makeSubSacForm!B(offset,element.id,size,form,mouseoverText,formIndex);
		case picture:
			auto offset=globalOffset+Vector2f(element.left,element.top);
			auto size=Vector2f(element.width,element.height);
			mixin(center);
			auto filename=formPicturePath(element);
			auto mouseoverText=mouseoverTextFromTag(element.mouseover);
			if(filename){
				auto texture=B.makeTexture(loadTXTR(filename));
				return makePicture!B(offset,element.id,size,texture,mouseoverText,formIndex);
			}else{
				// TODO: fix
				auto texture=SacForm!B.getTexture(FormTexture.textboxBackground);
				return makePicture!B(offset,element.id,size,texture,mouseoverText,formIndex);
			}
		case slider:
			auto offset=globalOffset+Vector2f(element.left,element.top);
			auto size=Vector2f(element.width,element.height);
			mixin(center);
			auto mouseoverText=mouseoverTextFromTag(element.mouseover);
			return makeSlider!B(offset,element.id,size,mouseoverText,formIndex);
		case textbox:
			auto offset=globalOffset+Vector2f(element.left,element.top);
			auto size=Vector2f(element.width,element.height);
			mixin(center);
			auto title=formTextFromTag(element.text);
			auto largeTitle=!!(element.flags&ElementFlags.largeText);
			//auto border=!!(element.flags&ElementFlags.border);
			auto border=true;
			auto scrollbar=!(element.flags&ElementFlags.noScrollbar);
			auto mouseoverText=mouseoverTextFromTag(element.mouseover);
			return makeTextbox!B(offset,element.id,size,title,largeTitle,border,scrollbar,mouseoverText,formIndex);
		case entrybox:
			auto offset=globalOffset+Vector2f(element.left,element.top);
			auto size=Vector2f(element.width,16.0f);
			mixin(center);
			auto text=formTextFromTag(element.text);
			auto largeText=!!(element.flags&ElementFlags.largeText);
			auto mouseoverText=mouseoverTextFromTag(element.mouseover);
			return makeEntrybox!B(offset,element.id,size,text,largeText,mouseoverText,formIndex);
		case checkbox:
			auto offset=globalOffset+Vector2f(element.left,element.top);
			auto size=Vector2f(element.width,16.0f);
			mixin(center);
			auto text=formTextFromTag(element.text);
			auto largeText=!!(element.flags&ElementFlags.largeText);
			auto mouseoverText=mouseoverTextFromTag(element.mouseover);
			return makeCheckbox!B(offset,element.id,size,text,largeText,mouseoverText,formIndex);
		case text:
			import std.stdio;
			auto offset=globalOffset+Vector2f(element.left,element.top);
			auto size=Vector2f(element.width,element.height);
			mixin(center);
			auto text=formTextFromTag(element.text);
			//auto whiteText=!!(element.flags&ElementFlags.whiteText); // TODO: does this do anything for basic text?
			auto largerText=!!(element.flags&ElementFlags.largerText);
			enforce(!largerText,"TODO");
			auto largeText=!!(element.flags&ElementFlags.largeText);
			auto font=largeText?FormFont.largeTitle:FormFont.standard;
			auto mouseoverText=mouseoverTextFromTag(element.mouseover);
			return makeText!B(offset,element.id,size,text,font,true,true,mouseoverText,formIndex);
		case dropdown:
			auto offset=globalOffset+Vector2f(element.left,element.top);
			auto size=Vector2f(element.width,16.0f);
			mixin(center);
			auto text=formTextFromTag(element.text);
			auto largeText=!!(element.flags&ElementFlags.largeText);
			auto mouseoverText=mouseoverTextFromTag(element.mouseover);
			return makeDropdown!B(offset,element.id,size,text,largeText,mouseoverText,formIndex);
		case canvas:
			auto offset=globalOffset+Vector2f(element.left,element.top);
			auto size=Vector2f(element.width,element.height);
			mixin(center);
			auto title=formTextFromTag(element.text);
			if(!title) title=""; // e.g., ziws
			auto largeTitle=!!(element.flags&ElementFlags.largeText);
			//auto border=!!(element.flags&ElementFlags.border);
			auto border=true;
			//auto scrollbar=!(element.flags&ElementFlags.noScrollbar);
			auto scrollbar=false;
			auto mouseoverText=mouseoverTextFromTag(element.mouseover);
			auto canvas=makeTextbox!B(offset,element.id,size,title,largeTitle,border,scrollbar,mouseoverText,formIndex);
			canvas.type=ElementType.canvas;
			return canvas;
		case progressbar:
			break;
		default:
			enforce(0, "TODO");
			assert(0);
	}
	import std.stdio;
	writeln("TODO: ",element);
	return SacFormElement!B();
}

final class SacForm(B){
	static immutable string[] formTexturePaths=[
		FormTexture.formBackground: "extracted/interfac/ifac.WAD!/form.FLDR/FMbg.TXTR",
		FormTexture.formBorder: "extracted/interfac/ifac.WAD!/form.FLDR/FMbo.TXTR",
		FormTexture.formTitlebar: "extracted/interfac/ifac.WAD!/form.FLDR/FMtb.TXTR",
		FormTexture.formPart1: "extracted/interfac/ifac.WAD!/form.FLDR/FMp1.TXTR",
		FormTexture.formPart2: "extracted/interfac/ifac.WAD!/form.FLDR/FMp2.TXTR",
		FormTexture.formPart3: "extracted/interfac/ifac.WAD!/form.FLDR/FMp3.TXTR",
		FormTexture.formPart4: "extracted/interfac/ifac.WAD!/form.FLDR/FMp4.TXTR",
		FormTexture.formPart5: "extracted/interfac/ifac.WAD!/form.FLDR/FMp5.TXTR",
		FormTexture.formPart6: "extracted/interfac/ifac.WAD!/form.FLDR/FMp5.TXTR",
		FormTexture.blueButtonBackground: "extracted/interfac/ifac.WAD!/form.FLDR/FBbb.TXTR",
		FormTexture.buttonBackground: "extracted/interfac/ifac.WAD!/form.FLDR/FBbg.TXTR",
		FormTexture.entryboxBackground: "extracted/interfac/ifac.WAD!/form.FLDR/FEbg.TXTR",
		FormTexture.textboxBackground: "extracted/interfac/ifac.WAD!/form.FLDR/FLbg.TXTR",
		FormTexture.textboxBorder: "extracted/interfac/ifac.WAD!/form.FLDR/FLbo.TXTR",
		FormTexture.sliderBackground: "extracted/interfac/ifac.WAD!/form.FLDR/FSbg.TXTR",
		FormTexture.progressbar: "extracted/interfac/ifac.WAD!/form.FLDR/FMsb.TXTR",
	];
	static B.Texture[FormTexture.max+1] textures;
	static B.Texture getTexture(FormTexture formTexture){
		if(textures[formTexture]) return textures[formTexture];
		return textures[formTexture]=B.makeTexture(loadTXTR(formTexturePaths[formTexture]),false);
	}

	char[4] tag;
	immutable(Form)* form;
	SacFormElement!B[] sacElements;

	uint width(){ return form.width; }
	uint height(){ return form.height; }

	char[4] default_(){ return form.default_; }
	char[4] escape(){ return form.escape; }

	string mouseoverText(){ return null; }
	bool returnIsOk(){ return tag=="thci"||tag=="thco"; } // TODO: is there some flag for this?

	bool isChatForm(){ return tag=="thci"||tag=="thco"; }

	private this(char[4] tag){
		this.tag=tag;
		form=tag in forms;
		enforce(!!form);
		auto title=!!(form.flags&FormFlags.title)?formTextFromTag(form.title):null;
		auto background=!!(form.flags&FormFlags.background1);
		auto border=!!(form.flags&FormFlags.border);
		auto offset=Vector2f(0.0f,0.0f);
		auto size=Vector2f(width,height);
		sacElements~=makeForm!B(offset,form.id,size,title,true,background,border);
		auto globalOffset=Vector2f(0.0f,0.0f);
		if(title) globalOffset.y+=16;
		if(border) globalOffset+=Vector2f(16.0f,16.0f);
		foreach(i,ref e;form.elements){
			sacElements~=makeSacFormElement!B(globalOffset,size,e,to!int(i));
		}
	}

	static SacForm!B[char[4]] sacForms;
	static SacForm!B get(char[4] tag){
		if(auto r=tag in sacForms) return *r;
		return sacForms[tag]=new SacForm!B(tag);
	}
}

struct ElementState{
	ElementType type;
	char[4] id;
	string mouseoverText;
	int numChildren=0;
	int parent=-1;
	int sacFormIndex=-1;
	bool enabled=true;
	bool visible=true;
	bool checked=false;
	enum maxTextInputLength=194;
	int textInputWidth;
	Array!char textInput;
	int textCursor;
	int textStart=0;
	int textEnd=0;
}

bool activate(ref ElementState element){
	if(!element.enabled) return false;
	final switch(element.type) with(ElementType){
		case unknown0: return false;
		case button: element.checked=true; return true;
		case form: return false;
		case picture: return false;
		case slider: return false;
		case textbox: return false;
		case entrybox: return false;
		case checkbox: element.checked^=1; return true;
		case text: return false;
		case dropdown: return false;
		case canvas: return false;
		case progressbar: return false;
	}
}

void fitTextStart(B)(ref ElementState element,bool expand=true){
	// TODO: faster algorithm?
	auto font=formSacFont!B(FormFont.standard);
	auto smallData=expand?element.textInput.data[0..element.textEnd]:element.textInput.data[element.textStart..element.textEnd];
	int curWidth=0;
	while(curWidth<=element.textInputWidth){
		element.textStart=to!int(smallData.ptr+smallData.length-element.textInput.data.ptr);
		if(!smallData.length) break;
		import std.utf,std.typecons;
		dchar c=smallData.decodeBack!(Yes.useReplacementDchar);
		curWidth+=font.getCharWidth(c);
	}
}

void fitTextEnd(B)(ref ElementState element,bool expand=true){
	// TODO: faster algorithm?
	auto font=formSacFont!B(FormFont.standard);
	auto smallData=expand?element.textInput.data[element.textStart..$]:element.textInput.data[element.textStart..element.textEnd];
	int curWidth=0;
	while(curWidth<=element.textInputWidth){
		element.textEnd=to!int(smallData.ptr-element.textInput.data.ptr);
		if(!smallData.length) break;
		import std.utf,std.typecons;
		dchar c=smallData.decodeFront!(Yes.useReplacementDchar);
		curWidth+=font.getCharWidth(c);
	}
}

bool moveLeft(B)(ref ElementState element){
	if(element.textCursor<=0) return false;
	import std.utf:strideBack;
	element.textCursor-=element.textInput.data[].strideBack(element.textCursor);
	auto left=element.textCursor;
	if(left<element.textStart){
		element.textStart=left;
		element.fitTextEnd!B(false);
	}
	return true;
}
bool moveRight(B)(ref ElementState element){
	if(element.textCursor>=element.textInput.length) return false;
	import std.utf:stride;
	element.textCursor+=element.textInput.data[].stride(element.textCursor);
	auto right=min(element.textInput.length,element.textCursor+1);
	if(element.textEnd<right){
		element.textEnd=max(element.textEnd,right);
		element.fitTextStart!B(false);
	}
	return true;
}

bool enterDchar(B)(ref ElementState element,dchar d){
	import std.uni:isWhite;
	if(isWhite(d)&&d!=' ') return false;
	import std.utf:encode;
	char[4] buf;
	auto numCodeUnits=encode(buf,d);
	if(element.textInput.length+numCodeUnits>element.maxTextInputLength)
		return false;
	foreach(c;buf[0..numCodeUnits]) element.textInput~=c;
	import std.algorithm;
	bringToFront(element.textInput.data[element.textCursor..$-numCodeUnits],element.textInput.data[$-numCodeUnits..$]); // TODO: faster algorithm?
	element.moveRight!B();
	element.fitTextEnd!B();
	return true;
}

bool deleteDchar(B)(ref ElementState element){
	if(element.textCursor<=0) return false;
	import std.utf:strideBack;
	auto numCodeUnits=element.textInput.data[].strideBack(element.textCursor);
	import std.algorithm:bringToFront;
	bringToFront(element.textInput.data[element.textCursor-numCodeUnits..element.textCursor],element.textInput.data[element.textCursor..$]);
	element.textInput.length=element.textInput.length-numCodeUnits;
	element.textEnd=min(element.textEnd,to!int(element.textInput.length));
	element.textStart=min(element.textStart,element.textEnd);
	element.textCursor-=numCodeUnits;
	element.textStart=min(element.textStart,element.textCursor);
	element.fitTextEnd!B();
	return true;
}
bool deleteDcharForward(B)(ref ElementState element){
	if(element.textCursor>=element.textInput.length) return false;
	import std.utf:stride;
	element.textCursor+=element.textInput.data[].stride(element.textCursor);
	return element.deleteDchar!B();
}

struct SacFormState(B){
	SacForm!B sacForm;
	Array!ElementState elements;
	int activeIndex;
	int defaultIndex=-1;
	int escapeIndex=-1;
	int okIndex=-1;

	ref activeElement(){ return elements[activeIndex]; }
	@property bool returnIsOk(){ return sacForm.returnIsOk; }
}

bool activeOk(B)(ref SacFormState!B form){
	if(form.okIndex<0||form.okIndex>=form.elements.length) return false;
	form.activeIndex=form.okIndex;
	return true;
}
bool activeDefault(B)(ref SacFormState!B form){
	if(form.defaultIndex<0||form.defaultIndex>=form.elements.length) return false;
	form.activeIndex=form.defaultIndex;
	return true;
}
bool activeEscape(B)(ref SacFormState!B form){
	if(form.escapeIndex<0||form.escapeIndex>=form.elements.length) return false;
	form.activeIndex=form.escapeIndex;
	return true;
}

void focusType(B)(ref SacFormState!B form,ElementType type){
	if(form.elements[form.activeIndex].type==type) return;
	foreach(i;chain(iota(form.activeIndex+1,to!int(form.elements.length)),iota(0,form.activeIndex))){
		if(form.elements[i].type==type){
			form.activeIndex=i;
			break;
		}
	}
}
bool isTabbable(ElementType type){
	final switch(type) with(ElementType){
		case unknown0,form,picture,text,canvas,progressbar:
			return false;
		case button,slider,textbox,entrybox,checkbox,dropdown:
			return true;
	}
}
void tabActive(B)(ref SacFormState!B form){
	foreach(i;chain(iota(form.activeIndex+1,to!int(form.elements.length)),iota(0,form.activeIndex))){
		if(form.elements[i].type.isTabbable){
			form.activeIndex=i;
			break;
		}
	}
}

SacFormState!B sacFormInstance(B)(char[4] tag){
	return sacFormInstance(SacForm!B.get(tag));
}

SacFormState!B sacFormInstance(B)(SacForm!B form){
	Array!ElementState elements;
	int activeIndex=0;
	int defaultIndex=-1;
	int escapeIndex=-1;
	int okIndex=-1;
	void addForm(SacForm!B currentForm,int parent,int parentSacFormIndex){
		int current=to!int(elements.length);
		elements~=ElementState(ElementType.form,currentForm.tag,currentForm.mouseoverText,0,parent,parentSacFormIndex); // TODO: enabled, visible?
		foreach(sacFormIndex,ref sacElement;currentForm.sacElements){
			if(sacFormIndex==0) continue; // form itself is always first sacElement
			if(sacElement.type!=ElementType.form){
				enforce(sacElement.subForms.length==0);
				if(sacElement.id==currentForm.default_){
					defaultIndex=to!int(elements.length);
					activeIndex=defaultIndex;
				}
				if(sacElement.id==currentForm.escape){
					escapeIndex=to!int(elements.length);
				}
				if(sacElement.id=="__ko"||sacElement.id=="dnes"){
					okIndex=to!int(elements.length);
				}
				auto flags=currentForm.form.elements[sacElement.formIndex].flags;
				auto enabled=!(flags&ElementFlags.disabled);
				auto visible=!(flags&ElementFlags.hidden);
				elements~=ElementState(sacElement.type,sacElement.id,sacElement.mouseoverText,0,parent,to!int(sacFormIndex),enabled,visible);
				if(sacElement.type==ElementType.entrybox){
					elements[$-1].textInputWidth=max(0,cast(int)(sacElement.size.x+0.5f)-40);
				}
			}else{
				enforce(sacElement.subForms.length==1);
				addForm(sacElement.subForms[0].form,current,to!int(sacFormIndex));
			}
		}
		elements[current].numChildren=to!int(elements.length)-(current+1);
	}
	addForm(form,-1,-1);
	return SacFormState!B(form,move(elements),activeIndex,defaultIndex,escapeIndex,okIndex);
}
