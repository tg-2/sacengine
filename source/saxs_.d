// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

module saxs_;
import util;
import std.string, std.exception;

struct SAXSReferencePoint { // 4 optional attachment points that follow animated bones
							// hand position, weapon attachment, or spell origin etc
	short boneIndex; // which bone has that point.
	ushort flags; // I dont know what they do yet but it seems the first flag is if the offset will be enabled or not
	float[3] offset; // [0.0f ,0.0f, 0.0f] Vector 3 float for the offset from the bone.
}
struct SAXSLimbRecord { //Rendering settings for each limb if it will be transparent or not etc
align(1):
	ubyte flags; // here the first bit means if it will use trans or not. TODO: there are 2 more bits but im not sure what they do yet 
	ubyte zero; // nothing it leaves space but it puts a 0 there.
	uint chromaKey; // 0x040404 the color used for transparency (if you make this pink all the pink pixels will be trans) like quake does it. 
}
struct SAXS{
	float scaling; // contols the scale of the model 1.0 is 100% size
	float rootAdjustUnscaled; // TODO: rootAdjustUnscaled * scaling i think this is used to offset the height of where the model is placed but im not sure 
	
	float vertexQuality; // these two are for LOD as i understand, The higher the value, the fewer vertices and rings the model uses. 1.0 2.0 3.0 and so on...
	float ringQuality; //  and for both of these -1.0 means full model no LOD. thats how sacrifice uses them.
	
	ubyte[8] unwritten; // dont know what these bytes are, they dont do anything and the dll does not use them, possibly they just leave space in between.
	
	SAXSReferencePoint[4] referencePoints; // up to 4 of these points
	SAXSLimbRecord[16] limbs; // and up to 16 of these effects
	bool[40] hitboxBones; // what bones will contribute to frustrum culling but im not sure if they are for spell collisions etc
}
static assert(SAXSReferencePoint.sizeof == 16);
static assert(SAXSReferencePoint.offset.offsetof == 4);
static assert(SAXSLimbRecord.sizeof == 6);
static assert(SAXSLimbRecord.chromaKey.offsetof == 2);
static assert(SAXS.rootAdjustUnscaled.offsetof == 4);
static assert(SAXS.vertexQuality.offsetof == 8);
static assert(SAXS.ringQuality.offsetof == 12);
static assert(SAXS.referencePoints.offsetof ==0x18);
static assert(SAXS.limbs.offsetof == 0x58);
static assert(SAXS.hitboxBones.offsetof == 0xB8);
static assert(SAXS.sizeof==224);

SAXS parseSAXS(ubyte[] data){
	enforce(data.length>=SAXS.sizeof);
	return *cast(SAXS*)data.ptr;
}

SAXS loadSAXS(string filename){
	enforce(filename.endsWith(".SAXS"));
	return parseSAXS(readFile(filename));
}

