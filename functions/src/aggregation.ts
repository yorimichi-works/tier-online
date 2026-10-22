export const ranks = ["ss", "s", "a", "b", "c", "d"] as const;
export type Rank = (typeof ranks)[number];
export type Placements = Partial<Record<Rank, string[]>>;

export const scores: Record<Rank, number> = {
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

export interface IncrementalAggregate extends Aggregate {
  itemIds: string[];
}

function emptyCounts(): Record<Rank, number> {
  return Object.fromEntries(ranks.map((rank) => [rank, 0])) as Record<Rank, number>;
}

function normalizedPlacements(placements: Placements): Map<string, Rank> {
  const result = new Map<string, Rank>();
  // aggregateTier と同じく、高いTierを優先する。壊れた入力で同じitemが
  // 複数rankに入っていても、差分集計と従来集計の結果を一致させる。
  for (const rank of ranks) {
    for (const itemId of placements[rank] ?? []) {
      if (!result.has(itemId)) result.set(itemId, rank);
    }
  }
  return result;
}

function rankForAverage(average: number): Rank {
  return ranks.reduce((best, candidate) =>
    Math.abs(scores[candidate] - average) < Math.abs(scores[best] - average)
      ? candidate
      : best,
  );
}

function normalizeCounts(value: unknown): Record<Rank, number> {
  const source = value && typeof value === "object" ? value as Record<string, unknown> : {};
  return Object.fromEntries(ranks.map((rank) => [
    rank,
    typeof source[rank] === "number" && Number.isFinite(source[rank]) ?
      Math.max(0, source[rank] as number) : 0,
  ])) as Record<Rank, number>;
}

/// Firestoreに保存された集計値を、差分更新用の正規形へ変換する。
export function incrementalAggregateFrom(
  itemIds: string[],
  data: Partial<Aggregate> | undefined,
): IncrementalAggregate {
  const distributions: Record<string, Record<Rank, number>> = {};
  const rawDistributions = data?.distributions ?? {};
  for (const itemId of itemIds) {
    distributions[itemId] = normalizeCounts(rawDistributions[itemId]);
  }
  const result: IncrementalAggregate = {
    itemIds: [...itemIds],
    participants: Math.max(0, data?.participants ?? 0),
    community: {},
    distributions,
    disagreement: {},
  };
  // 既存分布からrank・分散を作り直すため、古い/部分的な表示値を引き継がない。
  return recomputeDerivedFields(result);
}

function recomputeDerivedFields(aggregate: IncrementalAggregate): IncrementalAggregate {
  const community: Record<string, Rank> = {};
  const disagreement: Record<string, number> = {};
  for (const itemId of aggregate.itemIds) {
    const counts = aggregate.distributions[itemId] ?? emptyCounts();
    const count = ranks.reduce((sum, rank) => sum + counts[rank], 0);
    if (count === 0) continue;
    const sum = ranks.reduce((total, rank) => total + scores[rank] * counts[rank], 0);
    const sumSquares = ranks.reduce(
      (total, rank) => total + scores[rank] * scores[rank] * counts[rank],
      0,
    );
    const average = sum / count;
    community[itemId] = rankForAverage(average);
    disagreement[itemId] = Math.max(0, sumSquares / count - average * average);
  }
  return {...aggregate, community, disagreement};
}

function recomputeItemDerivedFields(
  community: Record<string, Rank>,
  disagreement: Record<string, number>,
  itemId: string,
  counts: Record<Rank, number>,
): void {
  const count = ranks.reduce((sum, rank) => sum + counts[rank], 0);
  if (count === 0) {
    delete community[itemId];
    delete disagreement[itemId];
    return;
  }
  const sum = ranks.reduce((total, rank) => total + scores[rank] * counts[rank], 0);
  const sumSquares = ranks.reduce(
    (total, rank) => total + scores[rank] * scores[rank] * counts[rank],
    0,
  );
  const average = sum / count;
  community[itemId] = rankForAverage(average);
  disagreement[itemId] = Math.max(0, sumSquares / count - average * average);
}

/// submissionの作成・更新・削除を、全submissionを読み直さずに集計へ反映する。
/// 入力を変更せず新しい値を返すため、Firestore transaction内でも安全に使える。
export function applySubmissionDelta(
  aggregate: IncrementalAggregate,
  before: Placements | undefined,
  after: Placements | undefined,
): IncrementalAggregate {
  const allowed = new Set(aggregate.itemIds);
  const previous = before ? normalizedPlacements(before) : new Map<string, Rank>();
  const next = after ? normalizedPlacements(after) : new Map<string, Rank>();
  const distributions = {...aggregate.distributions};
  const community = {...aggregate.community};
  const disagreement = {...aggregate.disagreement};
  const changedItemIds = new Set<string>();
  for (const itemId of new Set([...previous.keys(), ...next.keys()])) {
    if (!allowed.has(itemId)) continue;
    const oldRank = previous.get(itemId);
    const newRank = next.get(itemId);
    if (oldRank === newRank) continue;
    const counts = {...(aggregate.distributions[itemId] ?? emptyCounts())};
    if (oldRank != null) {
      counts[oldRank] = Math.max(0, counts[oldRank] - 1);
    }
    if (newRank != null) counts[newRank] += 1;
    distributions[itemId] = counts;
    changedItemIds.add(itemId);
  }
  for (const itemId of changedItemIds) {
    recomputeItemDerivedFields(
      community,
      disagreement,
      itemId,
      distributions[itemId],
    );
  }
  const participants = Math.max(
    0,
    aggregate.participants + Number(after != null) - Number(before != null),
  );
  return {...aggregate, participants, distributions, community, disagreement};
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
