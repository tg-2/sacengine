// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

import util;
import std.stdio;
import std.random;
import std.conv, std.algorithm, std.string, std.exception, std.path;
import std.array;
import std.typecons: tuple, Tuple;
import sxtx;

struct BoneData{
	float[3] pos;
	ushort parent;
	ushort unused0; // setting all those fields to 0 does not affect the ingame rendering
	float[3][8] hitbox;
	float[7] unused1; // setting all those fields to 0 does not affect the ingame rendering
}
static assert(BoneData.sizeof==140);

struct BodyPartHeader{
	ubyte numRings;
	ubyte additionalRingEntries;
	ushort numExplicitFaces;
	ubyte[16] unknown0;
	uint flags;
	uint explicitFaceOffset;
	uint stripsOffset;
	ubyte[4] unknown1;
}
static assert(BodyPartHeader.sizeof==36);

enum BodyPartFlags: uint{
	CLOSE_TOP=1, // make triangles from first vertex to all other vertices, facing up
	CLOSE_BOT=2, // make triangles from first vertex to all other vertices, facing down
	HAS_SEAM=0x80,
	SEAM_STARTS_RING_ZERO=0x100,
	SEAM_STARTS_NONZERO_RING=0x200,
}

struct RingHeader{
	ubyte numEntries; // number of RingEntries
	ubyte unknown;
	ushort texture; // this is some sort of offset into the texture data (multiplying by 2 duplicates textures).
	uint offset; // offset of first data byte of first TriangleStrip
}
static assert(RingHeader.sizeof==8);

struct Ring{
	RingHeader* header;
	alias header this;
	RingEntry[] entries;
	string toString(){
		return text("Ring(",*header,", ",entries,")");
	}
}

struct RingEntry{
	ushort[3] indices;
	ubyte textureU;
	ubyte textureV;
	ushort unknown1;
}
static assert(RingEntry.sizeof==10);

struct StripHeader{
	ubyte[2] unknown0;
	ushort numStrips;
	ubyte[4] unknown1;
}
static assert(StripHeader.sizeof==8);

static struct SeamEntry{
	ushort bodyPart;
	ushort ring;
	ushort vertex;
	ubyte textureU; 
	ubyte textureV;
}
static assert(SeamEntry.sizeof==8);

struct BodyPart{
	BodyPartHeader* header;
	alias header this;
	uint[] offsets;
	Ring[] rings;
	ushort[3][] explicitFaces;
	StripHeader* stripHeader;
	SeamEntry[] strips;
	string toString(){
		return text("BodyPart(",*header,", ",rings,")");
	}
}

struct Position{
	short[3] pos;
	short bone;
	ushort weight;
	short[3] normal;
}
static assert(Position.sizeof==16);

struct Model{
	float zfactor;
	BoneData[] bones;
	BodyPart[] bodyParts;
	Position[] positions;
}

Model parseSXMD(ubyte[] data){
	uint numBodyParts=data[0];
	float zfactor=*cast(float*)data[8..12].ptr;
	uint numBones=*cast(uint*)data[28..32].ptr-1;
	uint boneOffset=*cast(uint*)data[32..36].ptr+140;
	uint vertexOffset=*cast(uint*)data[36..40].ptr;
	auto bones=cast(BoneData[])data[boneOffset..boneOffset+numBones*BoneData.sizeof];
	BodyPart[] bodyParts;
	uint numPositions=0;
	for(int k=0;k<numBodyParts;k++){
		uint offset=*cast(uint*)data[40+4*k..44+4*k].ptr;
		auto header=cast(BodyPartHeader*)&data[offset];
		//writeln(header.numRings," ",header.unknown0);
		assert(offset<data.length);
		Ring[] edata;
		auto offsets=cast(uint[])data[offset+BodyPartHeader.sizeof..offset+BodyPartHeader.sizeof+uint.sizeof*header.numRings];
		foreach(i,off;offsets){
			auto ringHeader=cast(RingHeader*)&data[off];
			auto entries=cast(RingEntry[])data[ringHeader.offset..ringHeader.offset+(ringHeader.numEntries+256*header.additionalRingEntries)*RingEntry.sizeof];
			foreach(ref entry;entries){
				foreach(index;entry.indices){
					if(index!=ushort.max&&index>=numPositions) numPositions=index+1;
				}
			}
			edata~=Ring(ringHeader,entries);
		}
		ushort[3][] explicitFaces=[];
		if(header.numExplicitFaces>0)
			explicitFaces=cast(ushort[3][])data[header.explicitFaceOffset..header.explicitFaceOffset+(ushort[3]).sizeof*header.numExplicitFaces];
		StripHeader* stripHeader;
		SeamEntry[] strips;
		if(header.stripsOffset){
			stripHeader=cast(StripHeader*)data[header.stripsOffset..header.stripsOffset+StripHeader.sizeof];
			strips=cast(SeamEntry[])data[header.stripsOffset+StripHeader.sizeof..header.stripsOffset+StripHeader.sizeof+SeamEntry.sizeof*stripHeader.numStrips];
		}
		bodyParts~=BodyPart(header,offsets,edata,explicitFaces,stripHeader,strips);
	}
	auto positions=cast(Position[])data[vertexOffset..vertexOffset+Position.sizeof*numPositions];
	auto remainingDataOffset=vertexOffset+Position.sizeof*numPositions;
	return Model(zfactor,bones,bodyParts,positions);
}
// when I refer to something as RETAIL I mean how the original engine does it or has it.
struct RetailRingVertex {
	ushort flags;
	ubyte u;
	bool active;
}

uint[3][] buildRetailRingFaces(const RetailRingVertex[] oldRing,
		const RetailRingVertex[] newRing, ushort oldPostFlags = 0,
		ushort newPostFlags = 0) {
	import std.algorithm : count;
	auto oldActiveCount = oldRing.count!(v => v.active);
	auto newActiveCount = newRing.count!(v => v.active);
	uint[3][] outFaces;
	if (!oldActiveCount || !newActiveCount) return outFaces;
	enum uint oldBase = 0;
	uint newBase = cast(uint)oldActiveCount + 1;
	size_t oldCursor, newCursor;
	uint oldOrdinal, newOrdinal;
	int oldIndex = -1, newIndex = -1, previous = -1;
	bool havePrevious, oldWrapped, newWrapped;
	bool fetchedNew = true;
	bool specialOld() { return (oldRing[oldCursor].flags & 0x60) != 0; }
	bool specialNew() { return (newRing[newCursor].flags & 0x60) != 0; }
	bool nextOldSpecial() {
		auto raw = oldCursor + 1;
		auto flags = raw < oldRing.length ? oldRing[raw].flags : oldPostFlags;
		return (flags & 0x60) != 0;
	}
	bool nextNewSpecial() {
		auto raw = newCursor + 1;
		auto flags = raw < newRing.length ? newRing[raw].flags : newPostFlags;
		return (flags & 0x60) != 0;
	}
	void fetchOld() {
		while (!oldRing[oldCursor].active) {
			if (++oldCursor == oldRing.length) {
				oldCursor = 0;
				oldWrapped = true;
			}
		}
		oldIndex = cast(int)(oldBase + oldOrdinal++);
		fetchedNew = false;
	}
	void fetchNew() {
		while (!newRing[newCursor].active) {
			if (++newCursor == newRing.length) {
				newCursor = 0;
				newWrapped = true;
			}
		}
		newIndex = cast(int)(newBase + newOrdinal++);
		fetchedNew = true;
	}
	for (;;) {
		if (oldIndex < 0) fetchOld();
		if (newIndex < 0) fetchNew();
		if (havePrevious) {
			outFaces ~= fetchedNew
				? [cast(uint)previous, cast(uint)oldIndex, cast(uint)newIndex]
				: [cast(uint)newIndex, cast(uint)previous, cast(uint)oldIndex];
		}
		bool consumeOld = ((oldRing[oldCursor].u < newRing[newCursor].u) || newWrapped)
			&& !oldWrapped;
		bool oldSpecial = specialOld();
		bool newSpecial = specialNew();
		if (oldSpecial && consumeOld && nextNewSpecial()) consumeOld = false;
		else if (!oldSpecial && newSpecial && !consumeOld && nextOldSpecial()) consumeOld = true;
		if (consumeOld) {
			previous = oldIndex;
			havePrevious = true;
			oldIndex = -1;
			if (++oldCursor == oldRing.length) {
				if (newWrapped) {
					outFaces ~= [cast(uint)newIndex, cast(uint)previous, oldBase + oldOrdinal];
					return outFaces;
				}
				oldCursor = 0;
				oldIndex = cast(int)(oldBase + oldOrdinal);
				oldOrdinal = 0;
				fetchedNew = !fetchedNew;
				oldWrapped = true;
			}
		} else {
			previous = newIndex;
			havePrevious = true;
			newIndex = -1;
			if (++newCursor == newRing.length) {
				if (oldWrapped) {
					outFaces ~= [cast(uint)previous, cast(uint)oldIndex, newBase + newOrdinal];
					return outFaces;
				}
				newCursor = 0;
				newIndex = cast(int)(newBase + newOrdinal);
				newOrdinal = 0;
				fetchedNew = !fetchedNew;
				newWrapped = true;
			}
		}
		if (oldWrapped && newWrapped) return outFaces;
	}
}

struct SeamRecord {
	ushort bodyPart, ring, vertex;
	ubyte u, v;
}
struct SeamVertex {
	ushort[3] indices;
	ubyte u, v;
	bool active = true;
}
struct SeamRing {
	SeamVertex[] vertices;
	bool active = true;
	ubyte selectorFlags;
}
struct SeamBody {
	SeamRing[] rings;
	SeamRecord[] records;
	uint flags;
	ubyte otherPart, wrapU;
}
struct SeamOutputVertex {
	ushort[3] indices;
	float u, v;
}
struct SeamMesh {
	SeamOutputVertex[] vertices;
	uint[3][] faces;
}

void prepareSeam(ref SeamBody body, size_t owner) {
	if (!(body.flags & 0x80) || !body.records.length) return;
	foreach(a, record; body.records) {
		if (record.bodyPart != owner || record.u != 0) continue;
		body.records = body.records[a..$] ~ body.records[0..a];
		body.flags |= body.records[0].ring == 0 ? 0x100 : 0x200;
		return;
	}
}

int advanceRetailRing(uint actorFlags, int lodStep, ref SeamBody body,
		int selector, int boundarySelector) {
	if (actorFlags & 0x100) return selector + lodStep;
	int result = selector + lodStep;
	int scan = (selector >> 16) + 1;
	int target = result >> 16;
	int boundary = cast(short)(boundarySelector >> 16);
	while (scan < target && scan < boundary) {
		if (body.rings[scan].selectorFlags & 1) {
			result = scan << 16;
			target = scan;
		} else {
			body.rings[scan].selectorFlags &= cast(ubyte)~2;
		}
		++scan;
	}
	return result;
}

int[] selectRetailRings(ref SeamBody body, uint actorFlags = 0x1410,
		int lodStep = 0x10000) {
	int ringCount = cast(int)body.rings.length;
	int boundarySelector = ringCount << 16;
	int selector;
	if ((body.flags & 0x80) && (actorFlags & 0x1400) == 0x1400) {
		if (body.flags & 0x100) {
			selector = advanceRetailRing(actorFlags, lodStep, body, 0,
				boundarySelector);
		} else if (body.flags & 0x200) {
			int candidate = boundarySelector - lodStep;
			boundarySelector = candidate >= 0x20000
				? candidate : ringCount << 16;
		}
	}
	int[] result;
	for (;;) {
		if (selector >= boundarySelector) {
			if (boundarySelector != ringCount << 16) break;
			if (((selector - lodStep) >> 16) == ringCount - 1) break;
			selector = (ringCount - 1) << 16;
		}
		result ~= selector >> 16;
		selector = advanceRetailRing(actorFlags, lodStep, body, selector,
			boundarySelector);
	}
	return result;
}

SeamMesh buildRetailSeam(SeamBody[] bodies, size_t owner, int firstRing,
		int lastRing) {
	auto body = bodies[owner];
	auto records = body.records;
	SeamMesh result;
	if (!records.length) return result;
	bool boundary = (body.flags & 0x80) != 0;
	int selectedRing = (body.flags & 0x100) ? firstRing : lastRing;
	if (boundary && selectedRing >= body.rings.length) return result;
	size_t a, b;
	bool wrappedA, wrappedB, haveA, haveB, havePrevious;
	uint currentA, currentB, previous;
	bool scan(ref size_t cursor, ref bool wrapped, bool isOwner,
			out SeamVertex vertex) {
		bool crossed;
		for (;;) {
			auto r = records[cursor];
			size_t part = isOwner ? owner : body.otherPart;
			if (r.bodyPart == part) {
				size_t ring = isOwner && boundary ? selectedRing : r.ring;
				auto source = bodies[part].rings[ring];
				if (source.active && source.vertices[r.vertex].active) {
					vertex = source.vertices[r.vertex];
					return true;
				}
			}
			if (++cursor == records.length) {
				cursor = 0;
				wrapped = true;
				if (crossed) return false;
				crossed = true;
			}
		}
	}
	for (;;) {
		if (!haveA) {
			SeamVertex source;
			if (!scan(a, wrappedA, true, source)) return result;
			currentA = cast(uint)result.vertices.length;
			result.vertices ~= SeamOutputVertex(source.indices,
				(wrappedA ? body.wrapU : source.u) / 256.0f, source.v / 256.0f);
			haveA = true;
		}
		if (!haveB) {
			SeamVertex source;
			if (!scan(b, wrappedB, false, source)) return result;
			currentB = cast(uint)result.vertices.length;
			auto r = records[b];
			auto v = boundary
				? bodies[owner].rings[records[a].ring].vertices[records[a].vertex].v
				: r.v;
			result.vertices ~= SeamOutputVertex(source.indices,
				(wrappedB ? body.wrapU : r.u) / 256.0f, v / 256.0f);
			haveB = true;
		}
		if (havePrevious) {
			result.faces ~= [currentA, previous, currentB];
			if (wrappedA && wrappedB) return result;
		}
		if ((a < b && !wrappedA) || wrappedB) {
			previous = currentA;
			haveA = false;
			if (++a == records.length) {
				a = 0;
				wrappedA = true;
			}
		} else {
			previous = currentB;
			haveB = false;
			if (++b == records.length) {
				b = 0;
				wrappedB = true;
			}
		}
		havePrevious = true;
	}
}

private ubyte retailInteger(real value) {
	return cast(ubyte)cast(uint)value;
}

void prepareRetailUVs(ref Model model, const uint[] textureWidths,
		const uint[] textureHeights) {
	assert(textureWidths.length == model.bodyParts.length);
	assert(textureHeights.length == model.bodyParts.length);
	foreach (bodyIndex, ref body; model.bodyParts) {
		const uint atlasX = 0;
		const uint atlasY = 0;
		const uint regionWidth = 256;
		const uint regionHeight = 256;
		const uint loadedHeight = textureHeights[bodyIndex];
		foreach (ringIndex, ref ring; body.rings) {
			if (body.numExplicitFaces != 0) {
				const real vScale = 1.0L /
					((cast(real)loadedHeight - 1.0L) /
					cast(real)regionHeight + cast(real)(cast(double)0.001));
				foreach (ref entry; ring.entries) {
					entry.textureU = cast(ubyte)(
						(cast(uint)entry.textureU * regionWidth) / 256 + atlasX);
					entry.textureV = retailInteger(
						cast(real)entry.textureV * vScale + atlasY);
				}
			} else {
				uint row;
				if (ringIndex + 1 == body.rings.length) {
					row = regionHeight - 1;
				} else {
					row = ((regionHeight - 1) *
						(cast(uint)ring.texture + 1) + 8192) / 16384;
				}
				const ubyte v = cast(ubyte)(row + atlasY);
				foreach (ref entry; ring.entries) {
					entry.textureU = cast(ubyte)(
						(cast(uint)entry.textureU * regionWidth) / 256 + atlasX);
					entry.textureV = v;
				}
			}
			ring.texture = cast(ushort)(atlasX + regionWidth);
		}
		if (body.stripHeader !is null) {
			body.stripHeader.unknown0[1] = cast(ubyte)(atlasX + regionWidth - 1);
			foreach (ref entry; body.strips) {
				entry.textureU = cast(ubyte)(
					(cast(uint)entry.textureU * regionWidth) / 256 + atlasX);
				entry.textureV = cast(ubyte)(
					(cast(uint)entry.textureV * regionWidth) / 256 + atlasY);
			}
		}
	}
}

uint[3][] buildRetailCap(uint actorFlags, uint bodyFlags, bool first,
		uint base, uint emittedCount) {
	uint[3][] faces;
	if (!(actorFlags & 0x402) || !(actorFlags & 0x800) ||
			!(bodyFlags & (first ? 1u : 2u)) || emittedCount < 3)
		return faces;
	foreach (uint k; 1 .. emittedCount - 1)
		faces ~= first ? [base, base+k+1, base+k]
			: [base, base+k, base+k+1];
	return faces;
}

uint[] selectRetailVertices(ref ushort[] flags, int vertexStep,
		bool hasExplicitFaces, uint actorFlags = 0x1c10) {
	assert(vertexStep > 0);
	int end = cast(int)flags.length << 16;
	int step = hasExplicitFaces ? 0x10000 : vertexStep;
	if (end / step < 3) step = end / 3 + 1;
	uint[] result;
	int selector;
	while (selector < end) {
		int current = selector >> 16;
		flags[current] |= 0x100;
		result ~= cast(uint)current;
		int next = selector + step;
		int skippedFixed = selector + 0x10000;
		for (int skipped = current + 1;
				skipped < (next >> 16) && skippedFixed < end;
				++skipped, skippedFixed += 0x10000) {
			if (!(actorFlags & 0x4000) && (flags[skipped] & 0x80)) {
				flags[skipped] |= 0x100;
				result ~= cast(uint)skipped;
			} else {
				flags[skipped] &= cast(ushort)0xfeff;
			}
		}
		selector = next;
	}
	return result;
}
