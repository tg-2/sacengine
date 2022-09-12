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
				if(type==FontType.fnwt) rightMost=4;
				else if(type==FontType.fn12) rightMost=6;
				else rightMost=1;
			}
			letter.width=rightMost+1;
			letter.height=letterHeight-1;
			letter.mesh=B.makeSubQuad(float(u-widthSlack)/width,float(v+0.5f)/height,float(u+letter.width+widthSlack)/width,float(v+letterHeight-0.5f)/height);
		}
		if(type==FontType.fndb){
			widthSlack=0.5f;
			lineHeight=8; // TODO: ok?
		}else if(type==FontType.fnwt){
			// widthSlack?
			lineHeight=11;
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

Vector2f getSize(B)(SacFont!B font,scope const(char)[] text,FormatSettings settings){ // TODO: get rid of code duplication
	with(font) with(settings){
		float cX=0.0f, cY=0.0f;
		auto ptext=text;
		size_t writePos=0;
		float width=0.0f;
		void lineBreak(){
			cY+=scale*font.lineHeight;
			cX=0.0f;
			if(text[writePos].among(' ','\n')) writePos++;
		}
		for(;;){
			if(!ptext.length||ptext[0].among(' ','\n')){
				auto cur=text.length-ptext.length;
				auto word=text[writePos..cur];
				auto spaceWordWidth=scale*font.getTextWidth(text[writePos..cur]);
				if(cX+spaceWordWidth>maxWidth) lineBreak();
				cX+=scale*font.getTextWidth(text[writePos..cur]);
				writePos=cur;
				width=max(width,cX);
				if(ptext.length&&ptext[0]=='\n') lineBreak();
			}
			if(!ptext.length) break;
			ptext=ptext[1..$];
		}
		return Vector2f(width,cY+scale*font.lineHeight);
	}
}

void write(alias draw,B)(SacFont!B font,scope const(char)[] text,float left,float top,FormatSettings settings){
	if(!text.length) return;
	with(font) with(settings){
		float cX=left, cY=top;
		auto ptext=text;
		size_t writePos=0;
		void lineBreak(){
			cY+=scale*font.lineHeight;
			cX=left;
			if(text[writePos].among(' ','\n')) writePos++;
		}
		for(;;){
			if(!ptext.length||ptext[0].among(' ','\n')){
				auto cur=text.length-ptext.length;
				auto word=text[writePos..cur];
				auto spaceWordWidth=scale*font.getTextWidth(text[writePos..cur]);
				if(cX+spaceWordWidth>maxWidth) lineBreak();
				cX+=font.rawWrite!draw(text[writePos..cur],cX,cY,scale);
				writePos=cur;
				if(ptext.length&&ptext[0]=='\n') lineBreak();
			}
			if(!ptext.length) break;
			ptext=ptext[1..$];
		}
	}
}
