// Branded-character guard for the story-turn output gate (PRD §8.6 "real
// people and brands"). The rubric already forbids branded characters, but the
// model doesn't always follow it: the eval saw "Mickey Mouse" survive the gate
// in most reruns of one case. This deterministic list catches the characters
// kids (and parents) name most often; the rubric still covers everything else.

const BRANDED_CHARACTERS = [
  "mickey mouse", "minnie mouse", "donald duck", "elsa", "olaf", "moana", "simba",
  "buzz lightyear", "lightning mcqueen", "winnie the pooh", "spider-man", "spiderman", "batman",
  "superman", "wonder woman", "incredible hulk", "iron man", "spongebob", "patrick star", "peppa pig",
  "paw patrol", "bluey", "cocomelon", "pikachu", "pokemon", "pokémon", "super mario", "luigi",
  "sonic the hedgehog", "barbie", "elmo", "cookie monster", "barney", "dora the explorer",
  "thomas the tank engine", "hello kitty", "minions", "shrek", "harry potter", "grogu",
  "baby yoda", "darth vader", "hogwarts", "disney", "marvel", "lego", "roblox", "minecraft", "fortnite",
];

const escape = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&").replace(/ /g, "\\s+");
const PATTERNS = BRANDED_CHARACTERS.map((name) => ({
  name,
  pattern: new RegExp(`(?<![\\p{L}\\p{N}])${escape(name)}(?![\\p{L}\\p{N}])`, "iu"),
}));

/**
 * The branded characters named in `text`, in list order (lowercase). The
 * kid's own first name is never one: a child may really be called Elsa.
 */
export function brandedCharactersIn(text: string, kidFirstName = ""): string[] {
  const kid = kidFirstName.trim().toLowerCase();
  return PATTERNS.filter(({ name, pattern }) => name !== kid && pattern.test(text)).map(({ name }) => name);
}

/** True when any of the texts names a branded character other than the kid's own name. */
export function namesBrandedCharacter(texts: string[], kidFirstName = ""): boolean {
  return texts.some((text) => brandedCharactersIn(text, kidFirstName).length > 0);
}
