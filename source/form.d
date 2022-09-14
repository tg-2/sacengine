// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import util;
import std.exception, std.string;

enum ElementType{
	unknown0=0,
	button=1,
	form=2,
	picture=3,
	slider=4,
	textbox=5,
	entrybox=6,
	checkbox=7,
	text=10,
	dropdown=11,
	canvas=12,
	progressbar=13,
}

enum FormFlags{
	unknown6=1<<6,
	background0=1<<7,
	title=1<<8,
	border=1<<9,
	background1=1<<10,
	centerVertically=1<<12,
	centerHorizontally=1<<13,
}

enum ElementFlags{
	centerHorizontally=1<<1,
	centerVertically=1<<2,
	hidden=1<<3,
	noScrollbar=1<<5,
	disabled=1<<8,
	whiteText=1<<9,
	largerText=1<<10,
	largeText=1<<11,
	unknown14=1<<14,
	unknown15=1<<15,
	unknown16=1<<16,
	unnknown17=1<<17,
	unnknown20=1<<20,
}

struct FormHeader{
	align(1):
	char[4] id;
	char[4] title;
	int unknown0;
	int unknown1;
	int width;
	int height;
	int unknown2;
	char[4] default_;
	char[4] escape;
	int unknown3;
	int flags;
	ubyte unknown4;
	ubyte numElements;
	ushort unknown5;
	ubyte unknown6;
}
static assert(FormHeader.sizeof==49);

struct Element{
	ElementType type;
	char[4] id;
	char[4] text;
	char[4] mouseover;
	int top;
	int left;
	uint width;
	uint height;
	char[4] pictureOrForm; // id of default picture or id of form
	char[4] picture;
	uint unknown9;
	uint unknown10;
	uint flags;
	uint unknown12;
	char[4] unknown13; // next menu?
	uint unknown14;
	uint unknown15;
	char[4] unknown16;
	char[4] unknown17;
	char[4] unknown18;
	char[4] unknown19;
	char[4] unknown20;
}
static assert(Element.sizeof==88);

struct Form{
	FormHeader *header;
	alias header this;
	Element[] elements;
}

Form parseForm(ubyte[] data){
	enforce(data.length>=FormHeader.sizeof);
	auto header=cast(FormHeader*)data.ptr;
	enforce(data.length==FormHeader.sizeof+header.numElements*Element.sizeof);
	auto elements=cast(Element[])data[FormHeader.sizeof..$];
	return Form(header,elements);
}

Form loadForm(string filename){
	enforce(filename.endsWith(".FORM"));
	auto data=readFile(filename);
	return parseForm(data);
}
