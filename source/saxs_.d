// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

module saxs_;
import util;
import std.string, std.exception;

struct SAXSReferencePoint { // optional attachment points that follow animated bones,
							// e.g. hand position, weapon attachment, or spell origin
	short boneIndex; // index of the bone this point is attached to
	ushort flags; // TODO: semantics not fully known; the first flag appears to enable the offset
	float[3] offset; // offset from the bone
}
struct SAXSLimbRecord { // per-limb rendering settings (transparency etc.)
align(1):
	ubyte flags; // bit 0: use transparency. TODO: meaning of the remaining bits unknown
	ubyte zero; // padding, always zero
	uint chromaKey; // color key used for transparency (e.g. 0x040404); pixels of this color become transparent, Quake-style
}
struct SAXS{
	float scaling; // controls the scale of the model; 1.0 is 100% size
	float rootAdjustUnscaled; // TODO: unconfirmed; rootAdjustUnscaled * scaling appears to offset the height where the model is placed

	float vertexQuality; // LOD control: higher values use fewer vertices and rings (1.0, 2.0, 3.0, ...)
	float ringQuality; // for both quality values, -1.0 means full model with no LOD; this is how retail Sacrifice uses them

	ubyte[8] unwritten; // unknown; unused by the retail DLL, possibly reserved padding

	SAXSReferencePoint[4] referencePoints; // up to 4 of these points
	SAXSLimbRecord[16] limbs; // and up to 16 of these records
	bool[40] hitboxBones; // which bones contribute to frustum culling; possibly also used for spell collisions
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

