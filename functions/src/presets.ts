import {SupportedLocale} from "./internationalization";

export const GENERIC_PRESET_TOPIC_IDS = [
  "starter-generic-onigiri-fillings", "starter-generic-pizza-toppings",
  "starter-generic-sushi-toppings", "starter-generic-ice-cream-flavors",
  "starter-generic-snack-types", "starter-generic-drink-types",
  "starter-generic-hot-pot", "starter-generic-egg-dishes",
  "starter-generic-sandwiches", "starter-generic-world-cuisines",
  "starter-generic-countries-and-regions",
  "starter-generic-popular-animals", "starter-generic-pets",
  "starter-generic-dog-breeds", "starter-generic-cat-breeds",
  "starter-generic-sea-creatures", "starter-generic-birds",
  "starter-generic-dinosaurs", "starter-generic-game-genres",
  "starter-generic-board-games", "starter-generic-card-games",
  "starter-generic-party-games", "starter-generic-playground-games",
  "starter-generic-gaming-devices", "starter-generic-game-mechanics",
  "starter-generic-movie-genres", "starter-generic-anime-genres",
  "starter-generic-music-genres", "starter-generic-instruments",
  "starter-generic-book-genres", "starter-generic-tv-genres",
  "starter-generic-story-heroes", "starter-generic-sports",
  "starter-generic-ball-sports", "starter-generic-winter-sports",
  "starter-generic-water-sports", "starter-generic-martial-arts",
  "starter-generic-workouts", "starter-generic-hobbies",
  "starter-generic-school-subjects", "starter-generic-stationery",
  "starter-generic-housework", "starter-generic-travel-styles",
  "starter-generic-transportation", "starter-generic-weather",
  "starter-generic-seasons", "starter-generic-smartphone-features",
  "starter-generic-social-features", "starter-generic-home-appliances",
  "starter-generic-emoji-reactions", "starter-generic-colors",
] as const;

const PRESET_IDS = new Set<string>(GENERIC_PRESET_TOPIC_IDS);

export const isGenericPresetTopic = (topicId: string): boolean =>
  PRESET_IDS.has(topicId) || topicId.startsWith("preset-");

export const genericPresetMeta = (locale: SupportedLocale): {
  title: string; description: string;
} => ({
  ja: {
    title: "公式Tierプリセット | tier表オンライン",
    description: "すぐに参加できる、みんなで決める公式Tierプリセットです。",
  },
  ko: {
    title: "공식 티어 프리셋 | 티어표 온라인",
    description: "바로 참여할 수 있는 공식 커뮤니티 티어 프리셋입니다.",
  },
  en: {
    title: "Official Tier Preset | Tier Online",
    description: "An official community tier preset ready for you to rank.",
  },
  "zh-tw": {
    title: "官方 Tier 預設 | Tier 表線上版",
    description: "可立即參加排名的官方社群 Tier 預設。",
  },
  "pt-br": {
    title: "Preset oficial | Tier Online",
    description: "Um preset oficial da comunidade pronto para você classificar.",
  },
}[locale]);
