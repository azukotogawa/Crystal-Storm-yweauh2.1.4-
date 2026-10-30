class_name WorldFeatureTypes
extends RefCounted

enum FeatureKind {
	NONE,
	TOWN,
	TOWN_BUILDING,
	TREE,
	GRASS_PATCH,
	BUSH,
	ANIMAL_SPAWN,
	RUIN,
	POI,
	VEIN,
	ENCOUNTER,
}

enum AnimalKind {
	DEER,
	BOAR,
	RABBIT,
	BIRD,
	FOX,
	GOAT,
	DUCK,
	SHEEP,
	WOLF,
	HERON,
}

const ANIMAL_DISPLAY := {
	AnimalKind.DEER: "Deer",
	AnimalKind.BOAR: "Boar",
	AnimalKind.RABBIT: "Rabbit",
	AnimalKind.BIRD: "Bird",
	AnimalKind.FOX: "Fox",
	AnimalKind.GOAT: "Goat",
	AnimalKind.DUCK: "Duck",
	AnimalKind.SHEEP: "Sheep",
	AnimalKind.WOLF: "Wolf",
	AnimalKind.HERON: "Heron",
}