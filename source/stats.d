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
	int numSpeedUps=0;
	float speedUp=1.0f;
	int speedUpUpdateFrame=-1;
	int speedUpFrame=-1;
	int stunCooldown=0;
	int rangedCooldown=0;
	int abilityCooldown=0;
	int carrying=0;
	bool appearing=false;
	bool disappearing=false;
	bool stealth=false;
	bool lifeShield=false;
	int numDesecrations=0;
}
import dlib.math.portable: pi;
@property float rotationSpeed(ref CreatureStats stats,bool isFlying){ // in radians per second
	if(isFlying) return 0.5f*pi!float;
	return pi!float;
}
@property float pitchingSpeed(ref CreatureStats stats){ // in radians per second
	return 0.125f*pi!float;
}
@property float pitchLowerLimit(ref CreatureStats stats){
	return -0.25f*pi!float;
}
@property float pitchUpperLimit(ref CreatureStats stats){
	return 0.25f*pi!float;
}
@property float movementSpeed(ref CreatureStats stats,bool isFlying){ // in meters per second
	auto effectFactor=stats.effects.speedUp;
	return (isFlying?stats.flyingSpeed:stats.runningSpeed)*effectFactor;
}
@property float movementAcceleration(ref CreatureStats stats,bool isFlying){
	auto effectFactor=stats.effects.speedUp;
	return (isFlying?20.0f:75.0f)*effectFactor;
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
@property float upwardHoverSpeed(ref CreatureStats stats){
	return 3.0f;
}
@property float flyingHeight(ref CreatureStats stats){
	return 4.5f;
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
