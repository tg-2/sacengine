struct Animations{
	char[4] stance1;
	char[4][4] idle;
	char[4] tumble;
	char[4] run;
	char[4] falling;  // only for flying creatures
	char[4] hitFloor; // only for flying creatures
	char[4] knocked2Floor; // only for walking creatures
	char[4] getUp;         // only for walking creatures
	char[4][3] attack;
	char[4] damageFront;
	char[4] damageRight;
	char[4] damageBack;
	char[4] damageLeft;
	char[4] damageTop;
	char[4][3] death;
	char[4][2] shoot;
	char[4] run2; // TODO: what is this actually?
	char[4] thrash;
	char[4] spellcastStart; // wizards only
	char[4] spellcast; // wizards only
	char[4] spellcastEnd; // wizards only
	char[4] runSpellcastStart; // wizards only
	char[4] runSpellcast; // wizards only
	char[4] runSpellcastEnd; // wizards only
	char[4] takeoff;
	char[4] fly;
	char[4] land;
	char[4] flyDamage;
	char[4] flyDeath;
	char[4] flyAttack;
	char[4] hover;
	char[4][3] unknown33; // unused?
	char[4] carried;
	char[4] fling;
	char[4] notify;
	char[4] stance2;
	char[4] rise;
	char[4] corpse;
	char[4] float_;
	char[4] float2Thrash;
	char[4] sorrow;
	char[4] doubletake;
	char[4] ambivalence;
	char[4] disgust;
	char[4] bow;
	char[4] laugh;
	char[4] disoriented;
	char[4] corpseRise; // wizards only
	char[4] floatStatic; // wizards only
	char[4] floatMove; // wizards only
	char[4] float2Stance; // wizards only
	char[4] talk;
	char[4][2] unknown35; // unused?	
}
