// IMP-25: the SF Symbols a page's choice tile may show. The model picks from
// this list only (story_path_schema.ts puts it in the strict JSON schema as
// an enum); anything else is mapped to DEFAULT_CHOICE_SYMBOL rather than
// failing the page. Child-friendly pictures: animals, weather, places and
// objects. Includes every symbol setup_tiles.json uses (setup_tiles_test.ts
// checks), so a choice can reuse a setup tile's picture.

export const CHOICE_SYMBOLS = [
  // animals and characters
  "figure.child", "lizard.fill", "hare.fill", "cat.fill", "dog.fill", "bird.fill", "fish.fill",
  "tortoise.fill", "teddybear.fill", "pawprint.fill", "ladybug.fill", "ant.fill", "shield.fill",
  "gearshape.fill", "crown.fill",
  // places
  "tree.fill", "beach.umbrella.fill", "moon.stars.fill", "drop.fill", "building.columns.fill",
  "leaf.fill", "house.fill", "carrot.fill", "water.waves", "mountain.2.fill", "leaf.circle.fill",
  "building.2.fill", "tent.fill",
  // weather and sky
  "sun.max.fill", "cloud.fill", "cloud.rain.fill", "snowflake", "wind", "rainbow", "star.fill",
  "moon.zzz.fill", "sparkles",
  // objects and actions
  "questionmark.circle.fill", "fork.knife", "hand.raised.fill", "arrow.up.circle.fill",
  "person.2.fill", "wrench.and.screwdriver.fill", "gift.fill", "speaker.wave.3.fill",
  "flag.checkered", "heart.fill", "balloon.fill", "music.note", "key.fill", "map.fill",
  "magnifyingglass", "book.fill", "paintbrush.fill", "bicycle", "car.fill", "airplane",
  "sailboat.fill", "umbrella.fill", "bell.fill", "hands.clap.fill", "face.smiling",
] as const;

export type ChoiceSymbol = (typeof CHOICE_SYMBOLS)[number];

/** Shown when the model names a symbol that isn't on the list. */
export const DEFAULT_CHOICE_SYMBOL: ChoiceSymbol = "sparkles";

const SYMBOL_SET: ReadonlySet<string> = new Set(CHOICE_SYMBOLS);

export function isChoiceSymbol(symbol: string): symbol is ChoiceSymbol {
  return SYMBOL_SET.has(symbol);
}

/** The symbol itself when allow-listed (after trimming), else the default. */
export function toChoiceSymbol(symbol: string): ChoiceSymbol {
  const trimmed = symbol.trim();
  return isChoiceSymbol(trimmed) ? trimmed : DEFAULT_CHOICE_SYMBOL;
}
