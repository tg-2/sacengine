struct CreatureStats{
	int flags;
	float health;
	float mana;
	int souls;
	float maxHealth;
	float regeneration;
	float drain;
	float maxMana;	
	float runningSpeed;
	float flyingSpeed;
	float rangedAccuracy;
	float meleeResistance;
	float directSpellResistance;
	float splashSpellResistance;
	float directRangedResistance;
	float splashRangedResistance;
	Effects effects;
}
struct Effects{
	int speedUp=0;
	int speedUpFrame=-1;
}

import std.math: PI;
@property float rotationSpeed(ref CreatureStats stats,bool isFlying){ // in radians per second
	if(isFlying) return 0.5f*cast(float)PI;
	return cast(float)PI;
}
@property float pitchingSpeed(ref CreatureStats stats){ // in radians per second
	return 0.125f*cast(float)PI;
}
@property float pitchLowerLimit(ref CreatureStats stats){
	return -0.25f*cast(float)PI;
}
@property float pitchUpperLimit(ref CreatureStats stats){
	return 0.25f*cast(float)PI;
}
@property float movementSpeed(ref CreatureStats stats,bool isFlying){ // in meters per second
	auto effectFactor=(5.0f/3.0f)^^stats.effects.speedUp;
	return (isFlying?stats.flyingSpeed:stats.runningSpeed)*effectFactor;
}
@property float maxDownwardSpeedFactor(ref CreatureStats stats){
	return 2.0f;
}
@property float upwardFlyingSpeedFactor(ref CreatureStats stats){
	return 0.5f;
}
@property float downwardFlyingSpeedFactor(ref CreatureStats stats){
	return 2.0f;
}
@property float fallingAcceleration(ref CreatureStats stats){
	return 30.0f;
}
@property float landingSpeed(ref CreatureStats stats){
	return 0.5f*stats.movementSpeed(true);
}
@property float downwardHoverSpeed(ref CreatureStats stats){
	return 3.0f;
}
@property float flyingHeight(ref CreatureStats stats){
	return 4.0f;
}

@property float takeoffSpeed(ref CreatureStats stats){
	return stats.movementSpeed(true);
}
@property float collisionFixupSpeed(ref CreatureStats stats){
	return 5.0f;
}

@property float reviveTime(ref CreatureStats stats){
	return 5.0f;
}
@property float reviveHeight(ref CreatureStats stats){
	return 2.0f;
}
