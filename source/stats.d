struct CreatureStats{
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
}

@property float rotationSpeed(ref CreatureStats stats){ // in radians per second
	import std.math: PI;
	return PI;
}
@property float movementSpeed(ref CreatureStats stats,bool isFlying){ // in meters per second
	return (isFlying?stats.flyingSpeed:stats.runningSpeed)*0.01f;
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
	return 0.5f;
}
@property float landingSpeed(ref CreatureStats stats){
	return 0.5f*stats.movementSpeed(true);
}
@property float downwardHoverSpeed(ref CreatureStats stats){
	return 0.25f*stats.landingSpeed;
}
@property float flyingHeight(ref CreatureStats stats){
	return 3.0f;
}

@property float takeoffSpeed(ref CreatureStats stats){
	return stats.movementSpeed(true);
}
@property float collisionFixupSpeed(ref CreatureStats stats){
	return 5.0f;
}
