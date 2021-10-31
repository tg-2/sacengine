// copyright © tg
// distributed under the terms of the gplv3 license
// https://www.gnu.org/licenses/gpl-3.0.txt

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
	int yellCooldown=0;
	int carrying=0;
	bool appearing=false;
	bool disappearing=false;
	bool stealth=false;
	bool lifeShield=false;
	int numDesecrations=0;
	bool isGuardian=false;
	int poisonDamage=0;
	int infectionCooldown=0;
	int numManaBlocks=0;
	bool petrified=false;
	bool skinOfStone=false;
	bool etherealForm=false;
	bool fireform=false;
	bool protectiveSwarm=false;
	bool airShield=false;
	int ignitionTime=-2;
	int buzzTime=-2;
	int antiGravityTime=-2;
	bool frozen=false;
	bool ringsOfFire=false;
	int numSlimes=0;
	int numVines=0;
	int numBlightMites=0;
	int lightningChargeFrames=0;
	float devourRegenerationIncrement; // TODO: is this neeeded?
	@property bool slimed(){ return numSlimes!=0; }
	@property bool vined(){ return numVines!=0; }
	@property bool regenerationBlocked(){ return poisonDamage!=0||immobilized||ringsOfFire||slimed||vined; }
	@property bool manaBlocked(){ return numManaBlocks!=0; }
	@property bool ccProtected(){
		return lifeShield||skinOfStone||etherealForm||fireform||protectiveSwarm||airShield
			||petrified||frozen||ringsOfFire||slimed||vined;
	}
	@property bool stoneEffect(){ return petrified||skinOfStone; }
	@property bool immobilized(){ return petrified||frozen; }
	@property bool fixed(){ return vined; }
	@property bool healBlocked(){ return petrified||frozen||ringsOfFire||slimed||vined; } // TODO: add remaining effects
	@property bool shieldBlocked(){ return ringsOfFire||slimed||vined; }
	@property bool lightningCharged(){ return lightningChargeFrames!=0; }
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
	auto effectFactor=stats.effects.speedUp*0.25f^^stats.effects.numSlimes*0.8f^^stats.effects.numBlightMites*(stats.effects.lightningCharged?4.0f/3.0f:1.0f); // TODO: probably slowdowns should be interpolated too
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
	return 15.0f;
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
