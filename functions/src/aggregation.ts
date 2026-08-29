export const ranks = ["ss", "s", "a", "b", "c", "d"] as const;
export type Rank = (typeof ranks)[number];
export type Placements = Partial<Record<Rank, string[]>>;

const scores: Record<Rank, number> = {
  ss: 6,
  s: 5,
  a: 4,
  b: 3,
  c: 2,
  d: 1,
};

export interface Aggregate {
  participants: number;
  community: Record<string, Rank>;
  distributions: Record<string, Record<Rank, number>>;
  disagreement: Record<string, number>;
}

export function aggregateTier(
  itemIds: string[],
  submissions: Placements[],
): Aggregate {
  const community: Record<string, Rank> = {};
  const distributions: Record<string, Record<Rank, number>> = {};
  const disagreement: Record<string, number> = {};

  for (const itemId of itemIds) {
    const counts = Object.fromEntries(ranks.map((rank) => [rank, 0])) as
      Record<Rank, number>;
    const itemScores: number[] = [];
    for (const placement of submissions) {
      const rank = ranks.find((candidate) =>
        placement[candidate]?.includes(itemId),
      );
      if (rank === undefined) continue;
      counts[rank] += 1;
      itemScores.push(scores[rank]);
    }
    distributions[itemId] = counts;
    if (itemScores.length === 0) continue;
    const average = itemScores.reduce((sum, value) => sum + value, 0) /
      itemScores.length;
    community[itemId] = ranks.reduce((best, candidate) =>
      Math.abs(scores[candidate] - average) < Math.abs(scores[best] - average)
        ? candidate
        : best,
    );
    disagreement[itemId] = itemScores.reduce(
      (sum, value) => sum + Math.pow(value - average, 2),
      0,
    ) / itemScores.length;
  }

  return {
    participants: submissions.length,
    community,
    distributions,
    disagreement,
  };
}
