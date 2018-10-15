module nttData;

immutable struct CreatureData{
	char[4] tag;
	string name; // TODO: internationalization
	string model;
	string stance;
	float scaling=2e-3;
}

CreatureData abomination={
	tag: "ctug",
	name: "Abomination",
	model: "saxs_r8/sxr8.WAD!/gutc.FLDR/gutc.SAXC/gutc.SXMD",
	stance: "saxs_r8/sxr8.WAD!/gutc.FLDR/GCst.SXSK",
	scaling: 2e-3,
};

CreatureData astaroth={
	tag: "RAMH",
	name: "Astaroth",
	model: "saxshero/hero.WAD!/ban2.FLDR/ban2.SAXC/ban2.SXMD",
	stance: "saxs_r1/sxr1.WAD!/dzzy.FLDR/DZst.SXSK",
	scaling: 2e-3,
};

CreatureData basilisk={
	tag: "guls",
	name: "Basilisk",
	model: "saxs_r6/sxr6.WAD!/slug.FLDR/eslg.SAXC/eslg.SXMD",
	stance: "saxs_r6/sxr6.WAD!/slug.FLDR/SLst.SXSK",
	scaling: 1e-3,
};

CreatureData blight={
	tag: "kacd",
	name: "Blight",
	model: "saxs_r7/sxr7.WAD!/ckto.FLDR/dcak.SAXC/dcak.SXMD",
	stance: "saxs_r7/sxr7.WAD!/ckto.FLDR/CKst.SXSK",
	scaling: 1e-3,
};

CreatureData bombard={
	tag: "wlcf",
	name: "Bombard",
	model: "saxs_r8/sxr8.WAD!/claw.FLDR/fclw.SAXC/fclw.SXMD",
	stance: "saxs_r8/sxr8.WAD!/claw.FLDR/CPsf.SXSK",
	scaling: 2e-3,
};

CreatureData boulderdash={
	tag: "llab",
	name: "Boulderdash",
	model: "saxs_r4/sxr4.WAD!/ball.FLDR/bale.SAXC/bale.SXMD",
	stance: "saxs_r4/sxr4.WAD!/ball.FLDR/BMst.SXSK",
	scaling: 2e-3,
};

CreatureData brainiac={
	tag: "bobs",
	name: "Brainiac",
	model: "saxs_r3/sxr3.WAD!/sbob.FLDR/sbob.SAXC/sbob.SXMD",
	stance: "saxs_r3/sxr3.WAD!/sbob.FLDR/SBst.SXSK",
	scaling: 1e-3,
};

CreatureData cog={
	tag: "zidf",
	name: "Cog",
	model: "saxs_r1/sxr1.WAD!/dzzy.FLDR/fdzy.SAXC/fdzy.SXMD",
	stance: "saxs_r1/sxr1.WAD!/dzzy.FLDR/DZst.SXSK",
	scaling: 1e-3,
};

CreatureData deadeye={
	tag: "plfd",
	name: "Deadeye",
	model: "saxs_r4/sxr4.WAD!/flop.FLDR/dflp.SAXC/dflp.SXMD",
	stance: "saxs_r4/sxr4.WAD!/flop.FLDR/FGst.SXSK",
	scaling: 1e-3,
};

CreatureData dragon={
	tag: "grdg",
	name: "Dragon",
	model: "saxs_r11/sr11.WAD!/drag.FLDR/drag.SAXC/drag.SXMD",
	stance: "saxs_r11/sr11.WAD!/drag.FLDR/DGst.SXSK",
	scaling: 4e-3,
};

CreatureData dragonHatchling={
	tag: "rdbO",
	name: "Dragon Hatchling",
	model: "saxshero/hero.WAD!/baby.FLDR/baby.SAXC/baby.SXMD",
	stance: "saxs_r11/sr11.WAD!/drag.FLDR/DGst.SXSK",
	scaling: 1e-3,
};

CreatureData druid={
	tag: "nmuh",
	name: "Druid",
	model: "saxs_r1/sxr1.WAD!/humn.FLDR/humn.SAXC/humn.SXMD",
	stance: "saxs_r1/sxr1.WAD!/humn.FLDR/HUst.SXSK",
	scaling: 1e-3,
};

CreatureData earthfling={
	tag: "palk",
	name: "Earthfling",
	model: "saxs_r2/sxr2.WAD!/klap.FLDR/eklp.SAXC/eklp.SXMD",
	stance: "saxs_r2/sxr2.WAD!/klap.FLDR/KLst.SXSK",
	scaling: 1e-3,
};

CreatureData ent={
	tag: "mtsl",
	name: "Ent",
	model: "saxs_r10/sr10.WAD!/stmp.FLDR/stmp.SAXC/stmp.SXMD",
	stance: "saxs_r10/sr10.WAD!/stmp.FLDR/STst.SXSK",
	scaling: 2e-3,
};

CreatureData faestus1={
	tag: "ehtH",
	name: "Faestus",
	model: "saxshero/hero.WAD!/thes.FLDR/thes.SAXC/thes.SXMD",
	stance: "saxs_r4/sxr4.WAD!/flop.FLDR/FGst.SXSK",
	scaling: 2e-3,
};

CreatureData faestus2={
	tag: "EHTH",
	name: "Faestus",
	model: "saxshero/hero.WAD!/the2.FLDR/the2.SAXC/the2.SXMD",
	stance: "saxs_r4/sxr4.WAD!/flop.FLDR/FGst.SXSK",
	scaling: 2e-3,
};

CreatureData fallen={
	tag: "dplk",
	name: "Fallen",
	model: "saxs_r2/sxr2.WAD!/klap.FLDR/dklp.SAXC/dklp.SXMD",
	stance: "saxs_r2/sxr2.WAD!/klap.FLDR/KLst.SXSK",
	scaling: 1e-3,
};

CreatureData familiar={
	tag: "imaf",
	name: "Familiar",
	model: "saxs_r3/sxr3.WAD!/bugz.FLDR/FAmr.SAXC/FAmr.SXMD",
	stance: "saxs_r3/sxr3.WAD!/bugz.FLDR/FAho.SXSK", // TODO: ok?
	scaling: 1e-3,
};

CreatureData farmer={
	tag: "zepe",
	name: "Farmer",
	model: "saxs_odd/sxod.WAD!/peas.FLDR/epez.SAXC/epez.SXMD",
	stance: "saxs_odd/sxod.WAD!/peas.FLDR/PEst.SXSK",
	scaling: 1e-3,
};

CreatureData firefist={
	tag: "lrtf",
	name: "Firefist",
	model: "saxs_r5/sxr5.WAD!/trol.FLDR/ftrl.SAXC/ftrl.SXMD",
	stance: "saxs_r5/sxr5.WAD!/trol.FLDR/TRst.SXSK",
	scaling: 2e-3,
};

CreatureData flameminion={
	tag: "fplk",
	name: "Earthfling",
	model: "saxs_r2/sxr2.WAD!/klap.FLDR/fklp.SAXC/fklp.SXMD",
	stance: "saxs_r2/sxr2.WAD!/klap.FLDR/KLst.SXSK",
	scaling: 1e-3,
};

CreatureData flummox={
	tag: "wlce",
	name: "Flummox",
	model: "saxs_r8/sxr8.WAD!/claw.FLDR/eclw.SAXC/eclw.SXMD",
	stance: "saxs_r8/sxr8.WAD!/claw.FLDR/CPst.SXSK",
	scaling: 1.5e-3,
};

CreatureData flurry={
	tag: "wlca",
	name: "Flurry",
	model: "saxs_r8/sxr8.WAD!/claw.FLDR/aclw.SAXC/aclw.SXMD",
	stance: "saxs_r8/sxr8.WAD!/claw.FLDR/CPst.SXSK",
	scaling: 1.5e-3,
};

CreatureData frostwolf={ // TODO: this is screwed up, why?
	tag: "lbog",
	name: "Frostwolf",
	model: "saxs_r1/sxr1.WAD!/gobl.FLDR/gobl.SAXC/gobl.SXMD",
	stance: "saxs_r1/sxr1.WAD!/gobl.FLDR/GBst.SXSK",
	scaling: 1e-3,
};

CreatureData gammel={
	tag: "magH",
	name: "Gammel",
	model: "saxshero/hero.WAD!/gamm.FLDR/gamm.SAXC/gamm.SXMD",
	stance: "saxs_r7/sxr7.WAD!/ckto.FLDR/CKst.SXSK",
	scaling: 1.5e-3,
};

CreatureData gangrel={
	tag: "ramH",
	name: "Gangrel",
	model: "saxshero/hero.WAD!/bane.FLDR/bane.SAXC/bane.SXMD",
	stance: "saxs_r1/sxr1.WAD!/dzzy.FLDR/DZst.SXSK",
	scaling: 2e-3,
};

CreatureData gargoyle={
	tag: "sohe",
	name: "Gargoyle",
	model: "saxs_r3/sxr3.WAD!/hsbt.FLDR/ehbt.SAXC/ehbt.SXMD",
	stance: "saxs_r3/sxr3.WAD!/hsbt.FLDR/HBst.SXSK",
	scaling: 1e-3,
};

CreatureData ghost={
	tag: "tshg",
	name: "Ghost",
	model: "saxs_odd/sxod.WAD!/peas.FLDR/peas.SAXC/peas.SXMD",
	stance: "saxs_odd/sxod.WAD!/peas.FLDR/PEst.SXSK",
	scaling: 1e-3,
};

CreatureData gnome={
	tag: "plfl",
	name: "Gnome",
	model: "saxs_r4/sxr4.WAD!/flop.FLDR/lflp.SAXC/lflp.SXMD",
	stance: "saxs_r4/sxr4.WAD!/flop.FLDR/FGst.SXSK",
	scaling: 1e-3,
};

CreatureData gremlin={
	tag: "lrps",
	name: "Gremlin",
	model: "saxs_r7/sxr7.WAD!/sprg.FLDR/sprl.SAXC/sprl.SXMD",
	stance: "saxs_r7/sxr7.WAD!/sprg.FLDR/SPst.SXSK",
	scaling: 1e-3,
};

CreatureData hellmouth={
	tag: "nomd",
	name: "Hellmouth",
	model: "saxs_r11/sr11.WAD!/dmon.FLDR/ddmn.SAXC/ddmn.SXMD",
	stance: "saxs_r11/sr11.WAD!/dmon.FLDR/DMst.SXSK",
	scaling: 3e-3,
};

CreatureData ikarus={
	tag: "kace",
	name: "Ikarus",
	model: "saxs_r7/sxr7.WAD!/ckto.FLDR/ecak.SAXC/ecak.SXMD",
	stance: "saxs_r7/sxr7.WAD!/ckto.FLDR/CKst.SXSK",
	scaling: 1e-3,
};

CreatureData jabberocky={
	tag: "mtse",
	name: "Jabberocky",
	model: "saxs_r10/sr10.WAD!/estm.FLDR/estm.SAXC/estm.SXMD",
	stance: "saxs_r10/sr10.WAD!/estm.FLDR/ESst.SXSK",
	scaling: 2e-3,
};

CreatureData locust={
	tag: "pazb",
	name: "Locust",
	model: "saxs_r3/sxr3.WAD!/bugz.FLDR/bugz.SAXC/bugz.SXMD",
	stance: "saxs_r3/sxr3.WAD!/bugz.FLDR/BZst.SXSK",
	scaling: 1e-3,
};

CreatureData lordSurtur={
	tag: "uslH",
	name: "Lord Surtur",
	model: "saxshero/hero.WAD!/surt.FLDR/surt.SAXC/surt.SXMD",
	stance: "saxs_r1/sxr1.WAD!/humn.FLDR/HUst.SXSK",
	scaling: 2.5e-3,
};

CreatureData manahoar={
	tag: "oham",
	name: "Manahoar",
	model: "saxs_odd/sxod.WAD!/maho.FLDR/maho.SAXC/maho.SXMD",
	stance: "saxs_odd/sxod.WAD!/maho.FLDR/MAst.SXSK",
	scaling: 1e-3,
};

CreatureData mutant={
	tag: "cbab",
	name: "Mutant",
	model: "saxs_r8/sxr8.WAD!/gutc.FLDR/babc.SAXC/babc.SXMD",
	stance: "saxs_r8/sxr8.WAD!/gutc.FLDR/GCst.SXSK",
	scaling: 2e-3,
};

CreatureData necryl={
	tag: "glsd",
	name: "Necryl",
	model: "saxs_r6/sxr6.WAD!/slug.FLDR/dslg.SAXC/dslg.SXMD",
	stance: "saxs_r6/sxr6.WAD!/slug.FLDR/SLst.SXSK",
	scaling: 1e-3,
};

CreatureData netherfiend={
	tag: "crpd",
	name: "Netherfiend",
	model: "saxs_r10/sr10.WAD!/prcy.FLDR/prcy.SAXC/prcy.SXMD",
	stance: "saxs_r10/sr10.WAD!/prcy.FLDR/PCst.SXSK",
	scaling: 2e-3,
};

CreatureData peasant={
	tag: "saep",
	name: "Peasant",
	model: "saxs_odd/sxod.WAD!/peas.FLDR/peas.SAXC/peas.SXMD",
	stance: "saxs_odd/sxod.WAD!/peas.FLDR/PEst.SXSK",
	scaling: 1e-3,
};

CreatureData phoenix={
	tag: "grdr",
	name: "Phoenix",
	model: "saxs_r11/sr11.WAD!/fdrg.FLDR/fdrg.SAXC/fdrg.SXMD",
	stance: "saxs_r11/sr11.WAD!/fdrg.FLDR/DFst.SXSK",
	scaling: 4e-3,
};

CreatureData pyrodactyl={
	tag: "kacf",
	name: "Pyrodactyl",
	model: "saxs_r7/sxr7.WAD!/ckto.FLDR/fcak.SAXC/fcak.SXMD",
	stance: "saxs_r7/sxr7.WAD!/ckto.FLDR/CKst.SXSK",
	scaling: 1e-3,
};

CreatureData pyromaniac={
	tag: "plff",
	name: "Pyromaniac",
	model: "saxs_r4/sxr4.WAD!/flop.FLDR/fflp.SAXC/fflp.SXMD",
	stance: "saxs_r4/sxr4.WAD!/flop.FLDR/FGst.SXSK",
	scaling: 1e-3,
};

CreatureData ranger={
	tag: "amuh",
	name: "Ranger",
	model: "saxs_r2/sxr2.WAD!/huma.FLDR/huma.SAXC/huma.SXMD",
	stance: "saxs_r2/sxr2.WAD!/huma.FLDR/HAst.SXSK",
	scaling: 1e-3,
};

CreatureData rhinok={
	tag: "gard",
	name: "Rhinok",
	model: "saxs_r11/sr11.WAD!/dmon.FLDR/edmn.SAXC/edmn.SXMD",
	stance: "saxs_r11/sr11.WAD!/dmon.FLDR/Eds1.SXSK", // TODO: what is Eds2 exactly?
	scaling: 3e-3,
};

CreatureData sacDoctor={
	tag: "dcas",
	name: "Sac Doctor",
	model: "saxs_odd/sxod.WAD!/sacd.FLDR/sacd.SAXC/sacd.SXMD",
	stance: "saxs_odd/sxod.WAD!/sacd.FLDR/SDst.SXSK",
	scaling: 2e-3,
};

CreatureData saraBella={
	tag: "pezH",
	name: "Sara Bella",
	model: "saxshero/hero.WAD!/sara.FLDR/sara.SAXC/sara.SXMD",
	stance: "saxs_r3/sxr3.WAD!/sbob.FLDR/SBst.SXSK",
	scaling: 2e-3,
};

CreatureData scarab={
	tag: "cara",
	name: "Scarab",
	model: "saxs_r6/sxr6.WAD!/bugs.FLDR/bugl.SAXC/bugl.SXMD",
	stance: "saxs_r6/sxr6.WAD!/bugs.FLDR/BGst.SXSK",
	scaling: 1e-3,
};

CreatureData scythe={
	tag: "dzid",
	name: "Scythe",
	model: "saxs_r1/sxr1.WAD!/dzzy.FLDR/ddiz.SAXC/ddiz.SXMD",
	stance: "saxs_r1/sxr1.WAD!/dzzy.FLDR/DZst.SXSK",
	scaling: 1e-3,
};

CreatureData seraph={
	tag: "grps",
	name: "Seraph",
	model: "saxs_r7/sxr7.WAD!/sprg.FLDR/sprg.SAXC/sprg.SXMD",
	stance: "saxs_r7/sxr7.WAD!/sprg.FLDR/SPst.SXSK",
	scaling: 1e-3,
};

CreatureData shrike={
	tag: "tbsh",
	name: "Shrike",
	model: "saxs_r3/sxr3.WAD!/hsbt.FLDR/lhbt.SAXC/lhbt.SXMD",
	stance: "saxs_r3/sxr3.WAD!/hsbt.FLDR/HBst.SXSK",
	scaling: 1e-3,
};

CreatureData silverback={
	tag: "grdb",
	name: "Silverback",
	model: "saxs_r11/sr11.WAD!/adrg.FLDR/adrg.SAXC/adrg.SXMD",
	stance: "saxs_r11/sr11.WAD!/adrg.FLDR/ADst.SXSK",
	scaling: 3e-3,
};

CreatureData sirocco={
	tag: "risH",
	name: "Sirocco",
	model: "saxshero/hero.WAD!/sirc.FLDR/sirc.SAXC/sirc.SXMD",
	stance: "saxs_r11/sr11.WAD!/drag.FLDR/DGst.SXSK",
	scaling: 5e-3,
};

CreatureData slave={
	tag: "zepf",
	name: "Slave",
	model: "saxs_odd/sxod.WAD!/peas.FLDR/fpez.SAXC/fpez.SXMD",
	stance: "saxs_odd/sxod.WAD!/peas.FLDR/PEst.SXSK",
	scaling: 1e-3,
};

CreatureData snowman={
	tag: "zepa",
	name: "Snowman",
	model: "saxs_odd/sxod.WAD!/peas.FLDR/apez.SAXC/apez.SXMD",
	stance: "saxs_odd/sxod.WAD!/peas.FLDR/PEst.SXSK",
	scaling: 1e-3,	
};

CreatureData spitfire={
	tag: "sohf",
	name: "Spitfire",
	model: "saxs_r3/sxr3.WAD!/hsbt.FLDR/fhbt.SAXC/fhbt.SXMD",
	stance: "saxs_r3/sxr3.WAD!/hsbt.FLDR/HBst.SXSK",
	scaling: 1e-3,
};

CreatureData squall={
	tag: "alab",
	name: "Squall",
	model: "saxs_r4/sxr4.WAD!/ball.FLDR/bala.SAXC/bala.SXMD",
	stance: "saxs_r4/sxr4.WAD!/ball.FLDR/BMst.SXSK",
	scaling: 1.5e-3,

};

CreatureData stormGiant={
	tag: "rgos",
	name: "Storm Giant",
	model: "/home/tgehr/games/sac/SacrificeH/tools/3d/source/extracted/saxs_r1/sxr1.WAD!/humn.FLDR/sogr.SAXC/sogr.SXMD",
	stance: "/home/tgehr/games/sac/SacrificeH/tools/3d/source/extracted/saxs_r1/sxr1.WAD!/humn.FLDR/HUst.SXSK",
	scaling: 2e-3,
};

CreatureData styx={
	tag: "nugd",
	name: "Styx",
	model: "/home/tgehr/games/sac/SacrificeH/tools/3d/source/extracted/saxs_r9/sxr9.WAD!/gunh.FLDR/gund.SAXC/gund.SXMD",
	stance: "/home/tgehr/games/sac/SacrificeH/tools/3d/source/extracted/saxs_r9/sxr9.WAD!/gunh.FLDR/GUst.SXSK",
	scaling: 2e-3,
};

CreatureData sylph={
	tag: "ahcr",
	name: "Sylph",
	model: "/home/tgehr/games/sac/SacrificeH/tools/3d/source/extracted/saxs_r2/sxr2.WAD!/huma.FLDR/AArc.SAXC/AArc.SXMD",
	stance: "/home/tgehr/games/sac/SacrificeH/tools/3d/source/extracted/saxs_r2/sxr2.WAD!/huma.FLDR/HAst.SXSK",
	scaling: 1e-3,
};

CreatureData taurock={
	tag: "raeb",
	name: "Taurock",
	model: "/home/tgehr/games/sac/SacrificeH/tools/3d/source/extracted/saxs_r5/sxr5.WAD!/bear.FLDR/eber.SAXC/eber.SXMD",
	stance: "/home/tgehr/games/sac/SacrificeH/tools/3d/source/extracted/saxs_r5/sxr5.WAD!/bear.FLDR/BEst.SXSK",
	scaling: 2e-3,
};

CreatureData thestor={
	tag: "eafH",
	name: "Thestor",
	model: "/home/tgehr/games/sac/SacrificeH/tools/3d/source/extracted/saxshero/hero.WAD!/faes.FLDR/faez.SAXC/faez.SXMD",
	stance: "saxs_r4/sxr4.WAD!/flop.FLDR/FGst.SXSK",
	scaling: 2e-3,
};

CreatureData tickferno={
	tag: "craf",
	name: "Tickferno",
	model: "saxs_r6/sxr6.WAD!/bugs.FLDR/bugf.SAXC/bugf.SXMD",
	stance: "saxs_r6/sxr6.WAD!/bugs.FLDR/BGst.SXSK",
	scaling: 1e-3,

};

CreatureData toldor={
	tag: "oohH",
	name: "Toldor",
	model: "/home/tgehr/games/sac/SacrificeH/tools/3d/source/extracted/saxshero/hero.WAD!/hoom.FLDR/hoom.SAXC/hoom.SXMD",
	stance: "saxs_r10/sr10.WAD!/stmp.FLDR/STst.SXSK",
	scaling: 3e-3,
};

CreatureData trogg={
	tag: "ycro",
	name: "Trogg",
	model: "/home/tgehr/games/sac/SacrificeH/tools/3d/source/extracted/saxs_r1/sxr1.WAD!/humn.FLDR/eorc.SAXC/eorc.SXMD",
	stance: "/home/tgehr/games/sac/SacrificeH/tools/3d/source/extracted/saxs_r1/sxr1.WAD!/humn.FLDR/HUst.SXSK",
	scaling: 1e-3,
};

CreatureData troll={
	tag: "lort",
	name: "Troll",
	model: "saxs_r5/sxr5.WAD!/trol.FLDR/ltrl.SAXC/ltrl.SXMD",
	stance: "saxs_r5/sxr5.WAD!/trol.FLDR/TRst.SXSK",
	scaling: 2e-3,
};

CreatureData vortick={
	tag: "craa",
	name: "Vortick",
	model: "/home/tgehr/games/sac/SacrificeH/tools/3d/source/extracted/saxs_r6/sxr6.WAD!/buga.FLDR/buga.SAXC/buga.SXMD",
	stance: "/home/tgehr/games/sac/SacrificeH/tools/3d/source/extracted/saxs_r6/sxr6.WAD!/buga.FLDR/BAst.SXSK",
	scaling: 1e-3,
};

CreatureData warmonger={
	tag: "nugf",
	name: "Warmonger",
	model: "/home/tgehr/games/sac/SacrificeH/tools/3d/source/extracted/saxs_r9/sxr9.WAD!/gunh.FLDR/gunf.SAXC/gunf.SXMD",
	stance: "/home/tgehr/games/sac/SacrificeH/tools/3d/source/extracted/saxs_r9/sxr9.WAD!/gunh.FLDR/GUst.SXSK",
	scaling: 2e-3,
};

CreatureData yeti={
	tag: "ycrp",
	name: "Yeti",
	model: "saxs_r10/sr10.WAD!/prcy.FLDR/aprc.SAXC/aprc.SXMD",
	stance: "saxs_r10/sr10.WAD!/prcy.FLDR/PCst.SXSK",
	scaling: 2e-3,
};

CreatureData zombie={
	tag: "zepd",
	name: "Zombie",
	model: "saxs_odd/sxod.WAD!/peas.FLDR/dpez.SAXC/dpez.SXMD",
	stance: "saxs_odd/sxod.WAD!/peas.FLDR/PEst.SXSK",
	scaling: 1e-3,		
};

CreatureData zyzyx={
	tag: "tnem",
	name: "Zyzyx",
	model: "saxs_r3/sxr3.WAD!/bugz.FLDR/FAmr.SAXC/FAmr.SXMD",
	stance: "saxs_r3/sxr3.WAD!/bugz.FLDR/FAho.SXSK", // TODO: ok?
	scaling: 1e-3,

};

CreatureData* creatureDataByTag(char[4] tag){
Lswitch: switch(tag){
		static foreach(dataName;__traits(allMembers, nttData)){
			static if(is(typeof(mixin(`nttData.`~dataName))==CreatureData)){
				static if(mixin(`nttData.`~dataName).tag!=(char[4]).init)
				case mixin(`nttData.`~dataName).tag:{
					if(!mixin(`nttData.`~dataName).name)
						return null;
					else return &mixin(`nttData.`~dataName);
				}
			}
		}
		default:
			import std.stdio;
			//stderr.writeln("WARNING: unknown tag '",tag,"'");
			writeln(tag);
			return null;
	}
}
