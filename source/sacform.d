import std.exception, std.algorithm;
import dlib.math;

import form,txtr;
import nttData;

struct SacFormText{
	Vector3f position;
	string text;
}

enum FormTexture{
	formBackground,
	formBorder,
	formPart1,
	formPart2,
}

struct SacFormPart(B){
	B.Mesh2D mesh;
	FormTexture texture;
}

struct SacFormElement(B){
	SacFormPart!B[] parts;
	//string text;
	//bool bigText;
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

auto makeForm(B)(int width,int height,bool title,bool border){
	auto offset=Vector2f(0.0f,0.0f);
	auto backOffset=offset;
	auto backSize=Vector2f(width,height);
	if(title){
		backOffset.y+=16;
		backSize.y-=16;
	}
	if(border){
		backOffset+=Vector2f(8.0f,8.0f);
		backSize-=Vector2f(16.0f,16.0f);
	}
	SacFormPart!B[] parts;
	auto back=makeQuad!B(backOffset,backSize,Vector2f(0.0f,0.0f),(1.0f/32.0f)*backSize,false,false);
	parts~=SacFormPart!B(back,FormTexture.formBackground);

	if(border){
		auto cornerOffset=offset;
		auto topCornerOffset=cornerOffset;
		if(title) topCornerOffset.y+=16;

		auto cornerSize=Vector2f(32.0f,32.0f);
		auto cornerTexOff=Vector2f(0.5f+(0.5f/64.0f),(0.5f/64.0f));
		auto cornerTexSize=Vector2f(0.5f-1.0f/64.0f,0.5f-1.0f/64.0f);


		auto outerEdgeSize=Vector2f(16.0f,16.0f);
		auto outerEdgeTexOff=Vector2f(0.5f/32.0f,0.5f+(0.5f/32.0f));
		auto outerEdgeTexSize=Vector2f(0.5f-1.0f/32.0f,0.5f-1.0f/32.0f);

		auto innerEdgeSize=Vector2f(16.0f,16.0f);
		auto innerEdgeTexOff=Vector2f(0.5f+0.5f/32.0f,0.5f+(0.5f/32.0f));
		auto innerEdgeTexSize=Vector2f(0.5f-1.0f/32.0f,0.5f-1.0f/32.0f);

		auto horizontalBorderSize=Vector2f(width-2.0f*(cornerSize.x+outerEdgeSize.x+innerEdgeSize.x),16.0f);
		auto verticalBorderSize=Vector2f(16.0f,height-2.0f*(cornerSize.y+outerEdgeSize.y+innerEdgeSize.y));
		if(title) verticalBorderSize.y-=16.0f;

		if(horizontalBorderSize.x>0.0f){
			auto topBorder=makeQuad!B(topCornerOffset+Vector2f(cornerSize.x+outerEdgeSize.x+innerEdgeSize.x,0.0f),horizontalBorderSize,Vector2f(0.0f,0.0f),(1.0f/16.0f)*horizontalBorderSize,false,true);
			parts~=SacFormPart!B(topBorder,FormTexture.formBorder);

			auto bottomBorder=makeQuad!B(cornerOffset+Vector2f(cornerSize.x+outerEdgeSize.x+innerEdgeSize.x,height-horizontalBorderSize.y),horizontalBorderSize,Vector2f(0.0f,0.0f),(1.0f/16.0f)*horizontalBorderSize,false,false);
			parts~=SacFormPart!B(bottomBorder,FormTexture.formBorder);
		}

		if(verticalBorderSize.y>0.0f){
			auto leftBorder=makeQuad!B(topCornerOffset+Vector2f(0.0f,cornerSize.y+outerEdgeSize.y+innerEdgeSize.y),verticalBorderSize,Vector2f(0.0f,0.0f),(1.0f/16.0f)*verticalBorderSize,true,false,true);
			parts~=SacFormPart!B(leftBorder,FormTexture.formBorder);

			auto rightBorder=makeQuad!B(topCornerOffset+Vector2f(width-verticalBorderSize.x,cornerSize.y+outerEdgeSize.y+innerEdgeSize.y),verticalBorderSize,Vector2f(0.0f,0.0f),(1.0f/16.0f)*verticalBorderSize,false,false,true);
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


		auto rightTopInnerEdge=makeQuad!B(topCornerOffset+Vector2f(width-outerEdgeSize.x,cornerSize.y+outerEdgeSize.y),outerEdgeSize,innerEdgeTexOff,innerEdgeTexSize,true,false);
		parts~=SacFormPart!B(rightTopInnerEdge,FormTexture.formPart2);

		auto rightTopOuterEdge=makeQuad!B(topCornerOffset+Vector2f(width-outerEdgeSize.x,cornerSize.y),outerEdgeSize,outerEdgeTexOff,outerEdgeTexSize,true,false);
		parts~=SacFormPart!B(rightTopOuterEdge,FormTexture.formPart2);


		auto topRightInnerEdge=makeQuad!B(topCornerOffset+Vector2f(width-cornerSize.x-outerEdgeSize.x-innerEdgeSize.x,0.0f),outerEdgeSize,innerEdgeTexOff,innerEdgeTexSize,true,false,true);
		parts~=SacFormPart!B(topRightInnerEdge,FormTexture.formPart2);

		auto topRightOuterEdge=makeQuad!B(topCornerOffset+Vector2f(width-cornerSize.x-outerEdgeSize.x,0.0f),outerEdgeSize,outerEdgeTexOff,outerEdgeTexSize,true,false,true);
		parts~=SacFormPart!B(topRightOuterEdge,FormTexture.formPart2);

		auto leftBottomInnerEdge=makeQuad!B(cornerOffset+Vector2f(0.0f,height-cornerSize.y-outerEdgeSize.y-innerEdgeSize.y),outerEdgeSize,innerEdgeTexOff,innerEdgeTexSize,false,true);
		parts~=SacFormPart!B(leftBottomInnerEdge,FormTexture.formPart2);

		auto leftBottomOuterEdge=makeQuad!B(cornerOffset+Vector2f(0.0f,height-cornerSize.y-outerEdgeSize.y),outerEdgeSize,outerEdgeTexOff,outerEdgeTexSize,false,true);
		parts~=SacFormPart!B(leftBottomOuterEdge,FormTexture.formPart2);

		auto bottomLeftInnerEdge=makeQuad!B(cornerOffset+Vector2f(cornerSize.x+outerEdgeSize.x,height-innerEdgeSize.y),outerEdgeSize,innerEdgeTexOff,innerEdgeTexSize,false,true,true);
		parts~=SacFormPart!B(bottomLeftInnerEdge,FormTexture.formPart2);

		auto bottomLeftOuterEdge=makeQuad!B(cornerOffset+Vector2f(cornerSize.x,height-outerEdgeSize.y),outerEdgeSize,outerEdgeTexOff,outerEdgeTexSize,false,true,true);
		parts~=SacFormPart!B(bottomLeftOuterEdge,FormTexture.formPart2);


		auto rightBottomInnerEdge=makeQuad!B(cornerOffset+Vector2f(width-outerEdgeSize.x,height-cornerSize.x-outerEdgeSize.x-innerEdgeSize.y),outerEdgeSize,innerEdgeTexOff,innerEdgeTexSize,true,true);
		parts~=SacFormPart!B(rightBottomInnerEdge,FormTexture.formPart2);

		auto rightBottomOuterEdge=makeQuad!B(cornerOffset+Vector2f(width-outerEdgeSize.x,height-cornerSize.y-outerEdgeSize.y),outerEdgeSize,outerEdgeTexOff,outerEdgeTexSize,true,true);
		parts~=SacFormPart!B(rightBottomOuterEdge,FormTexture.formPart2);


		auto bottomRightInnerEdge=makeQuad!B(cornerOffset+Vector2f(width-cornerSize.x-outerEdgeSize.x-innerEdgeSize.x,height-innerEdgeSize.y),outerEdgeSize,innerEdgeTexOff,innerEdgeTexSize,true,true,true);
		parts~=SacFormPart!B(bottomRightInnerEdge,FormTexture.formPart2);

		auto bottomRightOuterEdge=makeQuad!B(cornerOffset+Vector2f(width-cornerSize.x-outerEdgeSize.y,height-outerEdgeSize.y),outerEdgeSize,outerEdgeTexOff,outerEdgeTexSize,true,true,true);
		parts~=SacFormPart!B(bottomRightOuterEdge,FormTexture.formPart2);


		auto topLeft=makeQuad!B(topCornerOffset,cornerSize,cornerTexOff,cornerTexSize,false,false);
		parts~=SacFormPart!B(topLeft,FormTexture.formPart1);

		auto topRight=makeQuad!B(topCornerOffset+Vector2f(width-cornerSize.x,0.0f),cornerSize,cornerTexOff,cornerTexSize,true,false);
		parts~=SacFormPart!B(topRight,FormTexture.formPart1);

		auto bottomLeft=makeQuad!B(cornerOffset+Vector2f(0.0f,height-cornerSize.y),cornerSize,cornerTexOff,cornerTexSize,false,true);
		parts~=SacFormPart!B(bottomLeft,FormTexture.formPart1);
		auto bottomRight=makeQuad!B(cornerOffset+Vector2f(width-cornerSize.x,height-cornerSize.y),cornerSize,cornerTexOff,cornerTexSize,true,true);
		parts~=SacFormPart!B(bottomRight,FormTexture.formPart1);
	}
	return SacFormElement!B(parts);
}

auto makeSacFormElement(B)(Vector2f globalOffset,Element element){
	switch(element.type) with(ElementType){
		case button:
			break;
		case form:
			break;
		case picture:
			break;
		case slider:
			break;
		case scrollbox:
			break;
		case textbox:
			break;
		case checkbox:
			break;
		case text:
			break;
		case dropdown:
			break;
		case canvas:
			break;
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
		FormTexture.formPart1: "extracted/interfac/ifac.WAD!/form.FLDR/FMp1.TXTR",
		FormTexture.formPart2: "extracted/interfac/ifac.WAD!/form.FLDR/FMp2.TXTR",
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

	private this(char[4] tag){
		form=tag in forms;
		enforce(!!form);
		auto title=!!(form.flags&FormFlags.title);
		auto border=!!(form.flags&FormFlags.border);
		sacElements~=makeForm!B(width,height,title,border);
		auto globalOffset=Vector2f(0.0f,0.0f);
		if(title) globalOffset.y+=16;
		if(border) globalOffset+=Vector2f(16.0f,16.0f);
		foreach(ref e;form.elements){
			sacElements~=makeSacFormElement!B(globalOffset,e);
		}
	}

	static SacForm!B[char[4]] sacForms;
	static SacForm!B get(char[4] tag){
		if(auto r=tag in sacForms) return *r;
		return sacForms[tag]=new SacForm!B(tag);
	}
}
