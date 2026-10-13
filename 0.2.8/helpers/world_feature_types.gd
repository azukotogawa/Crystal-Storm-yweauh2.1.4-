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
}

enum AnimalKind {
	DEER,
	BOAR,
	RABBIT,
	BIRD,
}

const ANIMAL_DISPLAY := {
	AnimalKind.DEER: "Deer",
	AnimalKind.BOAR: "Boar",
	AnimalKind.RABBIT: "Rabbit",
	AnimalKind.BIRD: "Bird",
}