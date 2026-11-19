// Local cosmetic meshes for the original wizard models.
module christmas_hat;

import saxs : Saxs, BodyPart, Position, Vertex;
import dlib.math : Vector2f, Vector3f;
import dlib.image.color : Color4f;
import std.math : cos, sin, PI;
import util : makeOnePixelImage;

void addCharlotteHat(B)(ref Saxs!B model){
	// The original model's bone 23 carries the head and hair. Coordinates are
	// in that bone's local space, so the hat follows every existing animation.
	enum headBone=23;
	if(model.bones.length!=25) return; // do not guess on a replacement model
	addHat!B(model,headBone,Vector3f(0,-0.10f,0.18f),1.0f);
}

void addEldredHat(B)(ref Saxs!B model){
	// In the original hero model, bone 11 carries Eldred's head.
	if(model.bones.length!=32) return;
	addHat!B(model,11,Vector3f(0,0.05f,0.13f),0.80f);
}

void addSorchaHat(B)(ref Saxs!B model){
	// Original Sorcha (gret): bone 13 carries the head.
	if(model.bones.length!=32 || model.bodyParts.length!=9) return;
	addHat!B(model,13,Vector3f(0,0.01f,0.18f),0.78f);
}

void addButaHat(B)(ref Saxs!B model){
	// Original Ambassador Buta: bone 14 carries the head.
	if(model.bones.length!=30 || model.bodyParts.length!=9) return;
	addHat!B(model,14,Vector3f(0,0.08f,0.09f),1.15f);
}

void addHachimenHats(B)(ref Saxs!B model){
	// Hachimen has two independently animated heads.
	if(model.bones.length!=26 || model.bodyParts.length!=12) return;
	addHat!B(model,7,Vector3f(0,0.02f,0.16f),0.95f);
	addHat!B(model,15,Vector3f(0,0.02f,0.16f),0.95f);
}

private void addHat(B)(ref Saxs!B model,int headBone,Vector3f base,float scale){
	enum segments=20;
	struct Ring { float x, y, z, rx, ry; }
	void addPart(Ring[] rings, Color4f color){
		BodyPart!B part;
		part.texture=B.makeTexture(makeOnePixelImage(color),false);
		foreach(ring; rings){
			foreach(i; 0..segments){
				auto angle=cast(float)(2.0*PI*i/segments);
				auto c=cos(angle), s=sin(angle);
				auto offset=base+scale*(Vector3f(ring.x+ring.rx*c,ring.y+ring.ry*s,ring.z)-Vector3f(0,-0.10f,0.18f));
				auto normal=Vector3f(c,s,0.3f).normalized();
				auto index=cast(int)model.positions.length;
				model.positions~=Position(headBone,offset,1.0f,normal);
				part.vertices~=Vertex([index],Vector2f(0.5f,0.5f));
			}
		}
		foreach(r; 0..rings.length-1) foreach(i; 0..segments){
			auto a=cast(uint)(r*segments+i), b=cast(uint)(r*segments+(i+1)%segments);
			auto c=a+segments, d=b+segments;
			part.faces~=[a,b,d];
			part.faces~=[a,d,c];
		}
		model.bodyParts~=part;
	}
	// White fur trim, a bent red crown and a white pompom.
	addPart([Ring(0,-0.10f,0.18f,0.16f,0.19f),
	         Ring(0,-0.10f,0.25f,0.16f,0.19f)],Color4f(0.95f,0.95f,0.92f,1));
	addPart([Ring(0,-0.10f,0.245f,0.15f,0.18f),
	         Ring(0,-0.10f,0.34f,0.12f,0.14f),
	         Ring(0.03f,-0.10f,0.44f,0.08f,0.10f),
	         Ring(0.11f,-0.10f,0.49f,0.045f,0.055f),
	         Ring(0.17f,-0.10f,0.46f,0.025f,0.03f)],Color4f(0.8f,0.015f,0.025f,1));
	addPart([Ring(0.18f,-0.10f,0.40f,0.008f,0.008f),
	         Ring(0.18f,-0.10f,0.42f,0.05f,0.05f),
	         Ring(0.18f,-0.10f,0.46f,0.065f,0.065f),
	         Ring(0.18f,-0.10f,0.50f,0.05f,0.05f),
	         Ring(0.18f,-0.10f,0.52f,0.008f,0.008f)],Color4f(0.95f,0.95f,0.92f,1));
}
