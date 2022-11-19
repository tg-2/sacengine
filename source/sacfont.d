import std.stdio, std.conv, std.encoding, std.algorithm, std.exception, std.string, std.utf;
import dlib.image,dlib.image.color,dlib.math;
import txtr,util;

enum FontType{
	fn08,
	fn10,
	fn12,
	fndb,
	fnwt,
	ft12,
}


auto byLatin1(R)(R r){ return r.byDchar.map!(c=>c>=0x100?'?':c); }

class SacFont(B){
	B.Texture texture;
	struct Letter{
		int width;
		int height;
		B.SubQuad mesh;
	}
	Letter[256] letters;
	float widthSlack=1.0f;
	int lineHeight=16;
	this(FontType type){
		auto image=loadTXTR(text("extracted/main/MAIN.WAD!/font.FLDR/",type,".TXTR"));
		texture=B.makeTexture(image,false);
		const width=image.width, height=image.height, channels=image.channels, data=image.data;
		enforce(width%16==0 && height%16==0 && channels==4);
		const letterWidth=image.width/16, letterHeight=image.height/16;
		foreach(k,ref letter;letters){
			int u=(cast(int)k%16)*letterWidth, v=(cast(int)k/16)*letterHeight;
			int rightMost=0;
			foreach(i;u..u+letterWidth){
				foreach(j;v..v+letterHeight){
					auto alpha=data[channels*(i+width*j)+3];
					if(alpha!=0) rightMost=max(rightMost,i-u);
				}
			}
			if(k==' '){
				if(type==FontType.fnwt||type==FontType.fn08) rightMost=3;
				else if(type==FontType.fn10) rightMost=5;
				else if(type==FontType.fn12||type==FontType.ft12) rightMost=6;
				else rightMost=1;
			}
			letter.width=rightMost+1;
			letter.height=letterHeight;
			letter.mesh=B.makeSubQuad(float(u-widthSlack)/width,float(v)/height,float(u+letter.width+widthSlack)/width,float(v+letterHeight)/height);
		}
		if(type==FontType.fndb){
			widthSlack=0.5f;
			lineHeight=8; // TODO: ok?
		}else if(type==FontType.fnwt){
			// widthSlack?
			lineHeight=11;
		}else if(type==FontType.fn10){
			lineHeight=14; // TODO: correct?
		}
	}
	static SacFont!B[FontType.max+1] fonts;
	static SacFont!B get(FontType type){
		if(!fonts[type]) fonts[type]=new SacFont!B(type);
		return fonts[type];
	}
}

float rawWrite(alias draw,B,R)(SacFont!B font,R text,float left,float top,float scale){
	with(font){
		float cursor=0.0f;
		foreach(dchar c;text){
			if(c>=0x100) c='?';
			draw(letters[c].mesh,left+cursor-widthSlack,top,scale*(letters[c].width+2.0f*widthSlack),scale*(letters[c].height));
			cursor+=scale*(letters[c].width+1);
		}
		return cursor;
	}
}

enum FlowType{
	left,
}
struct FormatSettings{
	auto flowType=FlowType.left;
	auto scale=1.0f;
	auto maxWidth=float.infinity;
}

int getCharWidth(B)(SacFont!B font,dchar c){
	with(font){
		if(c>=0x100) return font.getCharWidth('?');
		return letters[c].width+1;
	}
}
int getTextWidth(B)(SacFont!B font,scope const(char)[] text){
	with(font){
		int r=0;
		foreach(i,dchar c;text)
			r+=font.getCharWidth(c);
		return r;
	}
}

auto writeImpl(alias draw=void,B)(SacFont!B font,scope const(char)[] text,float left,float top,FormatSettings settings){
	with(font) with(settings){
		if(!text.length){
			static if(is(draw==void)) return Vector2f(0.0f,scale*font.lineHeight);
			else return;
		}
		float cX=left, cY=top;
		size_t writePos=0;
		static if(is(draw==void)) float width=0.0f;
		void write(scope const(char)[] text){
			static if(!is(draw==void)) cX+=font.rawWrite!draw(text,cX,cY,scale);
			else cX+=scale*font.getTextWidth(text);
		}
		void lineBreak(){
			cY+=scale*font.lineHeight;
			cX=left;
			if(text[writePos].among(' ','\n')) writePos++;
		}
		for(auto ptext=text;;){
			if(!ptext.length||ptext[0].among(' ','\n')){
				auto cur=text.length-ptext.length;
				auto word=text[writePos..cur];
				auto spaceWordWidth=scale*font.getTextWidth(text[writePos..cur]);
				if(cX+spaceWordWidth>left+maxWidth) lineBreak();
				write(text[writePos..cur]);
				writePos=cur;
				static if(is(draw==void)) width=max(width,cX);
				if(ptext.length&&ptext[0]=='\n') lineBreak();
			}
			if(!ptext.length) break;
			ptext=ptext[1..$];
		}
		static if(is(draw==void)) return Vector2f(width,cY+scale*font.lineHeight);
	}
}

Vector2f getSize(B)(SacFont!B font,scope const(char)[] text,FormatSettings settings){
	return writeImpl!void(font,text,0.0f,0.0f,settings);
}

void write(alias draw,B)(SacFont!B font,scope const(char)[] text,float left,float top,FormatSettings settings){
	static assert(!is(draw==void));
	writeImpl!draw(font,text,left,top,settings);
}
