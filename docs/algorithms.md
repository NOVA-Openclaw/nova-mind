# Analysis Algorithms

## Overview

The NOVA Relationships system employs sophisticated algorithms to analyze entity data and extract meaningful patterns. These algorithms enable intelligent context weighting, behavioral prediction, and relationship strength assessment.

## Core Algorithm Categories

### 1. Confidence Scoring

Confidence scoring determines the reliability of entity data based on multiple factors:

#### Data Quality Assessment
```typescript
interface DataQuality {
  source_reliability: number;    // 0.0-1.0: How reliable is the data source?
  verification_status: number;   // 0.0-1.0: Has the data been verified?
  consistency_score: number;     // 0.0-1.0: How consistent across sources?
  completeness_ratio: number;    // 0.0-1.0: How complete is the data?
}

function calculateDataQuality(fact: EntityFact): number {
  const weights = {
    source_reliability: 0.3,
    verification_status: 0.3,
    consistency_score: 0.2,
    completeness_ratio: 0.2
  };
  
  return Object.entries(weights).reduce((score, [key, weight]) => {
    return score + (fact[key] || 0) * weight;
  }, 0);
}
```

#### Temporal Decay
```typescript
function calculateTemporalDecay(
  timestamp: Date, 
  decayRate: number = 0.1,
  maxAge: number = 365 * 24 * 60 * 60 * 1000 // 1 year in ms
): number {
  const age = Date.now() - timestamp.getTime();
  const normalizedAge = age / maxAge;
  
  // Exponential decay: newer data has higher confidence
  return Math.exp(-decayRate * normalizedAge);
}
```

#### Cross-Reference Validation
```typescript
function calculateConsistencyScore(facts: EntityFact[]): number {
  const factsByKey = groupBy(facts, 'key');
  
  return Object.values(factsByKey).reduce((totalScore, factGroup) => {
    if (factGroup.length === 1) return totalScore + 1.0;
    
    // Multiple values for same fact - check consistency
    const uniqueValues = new Set(factGroup.map(f => f.value));
    const agreementRatio = 1.0 / uniqueValues.size;
    
    return totalScore + agreementRatio;
  }, 0) / Object.keys(factsByKey).length;
}
```

#### Overall Confidence Score
```typescript
function calculateConfidenceScore(fact: EntityFact): number {
  const quality = calculateDataQuality(fact);
  const temporal = calculateTemporalDecay(fact.created_at);
  const consistency = fact.consistency_score || 1.0;
  
  // Weighted combination
  const weights = { quality: 0.5, temporal: 0.3, consistency: 0.2 };
  
  return (
    quality * weights.quality +
    temporal * weights.temporal +
    consistency * weights.consistency
  );
}
```

### 2. Frequency Analysis

Frequency analysis identifies patterns in entity interactions and behaviors:

#### Interaction Frequency
```typescript
interface InteractionPattern {
  total_interactions: number;
  daily_average: number;
  weekly_pattern: number[];      // 7 values for each day of week
  hourly_pattern: number[];      // 24 values for each hour
  seasonal_variance: number;     // How much does frequency vary?
  response_time_avg: number;     // Average response time in minutes
}

function analyzeInteractionFrequency(
  interactions: Interaction[],
  timeWindow: number = 30 * 24 * 60 * 60 * 1000 // 30 days
): InteractionPattern {
  const recent = interactions.filter(
    i => Date.now() - i.timestamp.getTime() < timeWindow
  );
  
  const dailyAverage = recent.length / (timeWindow / (24 * 60 * 60 * 1000));
  
  // Analyze weekly patterns (Monday = 0, Sunday = 6)
  const weeklyPattern = Array(7).fill(0);
  recent.forEach(interaction => {
    const dayOfWeek = interaction.timestamp.getDay();
    weeklyPattern[dayOfWeek]++;
  });
  
  // Analyze hourly patterns
  const hourlyPattern = Array(24).fill(0);
  recent.forEach(interaction => {
    const hour = interaction.timestamp.getHours();
    hourlyPattern[hour]++;
  });
  
  return {
    total_interactions: recent.length,
    daily_average: dailyAverage,
    weekly_pattern: weeklyPattern,
    hourly_pattern: hourlyPattern,
    seasonal_variance: calculateVariance(weeklyPattern),
    response_time_avg: calculateAverageResponseTime(recent)
  };
}
```

#### Topic Preference Analysis
```typescript
function analyzeTopicPreferences(
  interactions: Interaction[]
): Map<string, TopicScore> {
  const topicCounts = new Map<string, number>();
  const topicEngagement = new Map<string, number[]>();
  
  interactions.forEach(interaction => {
    const topics = extractTopics(interaction.content);
    const engagement = calculateEngagement(interaction);
    
    topics.forEach(topic => {
      topicCounts.set(topic, (topicCounts.get(topic) || 0) + 1);
      
      if (!topicEngagement.has(topic)) {
        topicEngagement.set(topic, []);
      }
      topicEngagement.get(topic)!.push(engagement);
    });
  });
  
  const topicScores = new Map<string, TopicScore>();
  
  topicCounts.forEach((count, topic) => {
    const engagements = topicEngagement.get(topic)!;
    const avgEngagement = engagements.reduce((a, b) => a + b, 0) / engagements.length;
    
    topicScores.set(topic, {
      frequency: count,
      engagement: avgEngagement,
      consistency: calculateConsistency(engagements),
      recentTrend: calculateRecentTrend(topic, interactions)
    });
  });
  
  return topicScores;
}
```

### 3. Longitudinal Patterns

Longitudinal analysis tracks how entities change over time:

#### Behavioral Evolution
```typescript
interface BehavioralTrend {
  trait: string;
  historical_values: TimeSeriesPoint[];
  trend_direction: 'increasing' | 'decreasing' | 'stable' | 'cyclical';
  trend_strength: number;        // 0.0-1.0: How strong is the trend?
  change_points: Date[];         // When did significant changes occur?
  prediction_confidence: number; // How confident are we in predictions?
}

function analyzeBehavioralEvolution(
  entityId: number,
  trait: string,
  timeWindow: number = 180 * 24 * 60 * 60 * 1000 // 180 days
): BehavioralTrend {
  const historicalData = getHistoricalFacts(entityId, trait, timeWindow);
  const timeSeries = historicalData.map(fact => ({
    timestamp: fact.created_at,
    value: parseFloat(fact.value)
  }));
  
  // Sort by timestamp
  timeSeries.sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime());
  
  // Calculate trend using linear regression
  const trend = calculateLinearTrend(timeSeries);
  
  // Detect change points using sliding window variance
  const changePoints = detectChangePoints(timeSeries);
  
  // Classify trend direction
  const trendDirection = classifyTrendDirection(trend.slope, trend.confidence);
  
  return {
    trait,
    historical_values: timeSeries,
    trend_direction: trendDirection,
    trend_strength: Math.abs(trend.slope),
    change_points: changePoints,
    prediction_confidence: trend.confidence
  };
}
```

#### Seasonal Pattern Detection
```typescript
function detectSeasonalPatterns(
  timeSeries: TimeSeriesPoint[],
  periods: number[] = [7, 30, 365] // days, weekly, monthly, yearly
): SeasonalPattern[] {
  return periods.map(period => {
    const periodMs = period * 24 * 60 * 60 * 1000;
    const cycles = Math.floor(
      (timeSeries[timeSeries.length - 1].timestamp.getTime() - 
       timeSeries[0].timestamp.getTime()) / periodMs
    );
    
    if (cycles < 2) {
      return { period, strength: 0, confidence: 0 };
    }
    
    // Analyze autocorrelation at period intervals
    const autocorr = calculateAutocorrelation(timeSeries, period);
    const strength = Math.abs(autocorr);
    const confidence = calculateSeasonalConfidence(timeSeries, period);
    
    return {
      period,
      strength,
      confidence,
      phase: calculatePhase(timeSeries, period),
      amplitude: calculateAmplitude(timeSeries, period)
    };
  });
}
```

### 4. Entity Associations

Entity association algorithms identify and score relationships between entities:

#### Direct Relationship Strength
```typescript
function calculateRelationshipStrength(
  entityA: number,
  entityB: number
): RelationshipScore {
  const interactions = getInteractionsBetween(entityA, entityB);
  const mutualContacts = getMutualContacts(entityA, entityB);
  const sharedTopics = getSharedTopicInterests(entityA, entityB);
  
  // Interaction-based scoring
  const interactionScore = calculateInteractionScore(interactions);
  
  // Network-based scoring (mutual connections)
  const networkScore = mutualContacts.length / 10.0; // Normalize
  
  // Content-based scoring (shared interests)
  const contentScore = calculateContentSimilarity(entityA, entityB);
  
  // Temporal consistency (regular interactions over time)
  const consistencyScore = calculateInteractionConsistency(interactions);
  
  // Combined relationship strength
  const weights = {
    interaction: 0.4,
    network: 0.2,
    content: 0.2,
    consistency: 0.2
  };
  
  const overallStrength = 
    interactionScore * weights.interaction +
    networkScore * weights.network +
    contentScore * weights.content +
    consistencyScore * weights.consistency;
  
  return {
    strength: Math.min(overallStrength, 1.0),
    interaction_frequency: interactions.length,
    mutual_connections: mutualContacts.length,
    shared_interests: sharedTopics.length,
    consistency: consistencyScore,
    last_interaction: getLastInteraction(interactions)?.timestamp
  };
}
```

#### Transitive Relationship Discovery
```typescript
function discoverTransitiveRelationships(
  entityId: number,
  maxDegrees: number = 3,
  minStrength: number = 0.3
): TransitiveRelationship[] {
  const discovered: TransitiveRelationship[] = [];
  const visited = new Set<number>();
  const queue = [{ entity: entityId, path: [], distance: 0 }];
  
  while (queue.length > 0) {
    const { entity, path, distance } = queue.shift()!;
    
    if (distance > maxDegrees || visited.has(entity)) continue;
    visited.add(entity);
    
    const directRelations = getDirectRelationships(entity, minStrength);
    
    directRelations.forEach(relation => {
      if (!visited.has(relation.target_entity)) {
        const newPath = [...path, relation];
        const pathStrength = calculatePathStrength(newPath);
        
        if (pathStrength >= minStrength) {
          discovered.push({
            source_entity: entityId,
            target_entity: relation.target_entity,
            path: newPath,
            distance: distance + 1,
            strength: pathStrength,
            confidence: calculatePathConfidence(newPath)
          });
          
          queue.push({
            entity: relation.target_entity,
            path: newPath,
            distance: distance + 1
          });
        }
      }
    });
  }
  
  return discovered.sort((a, b) => b.strength - a.strength);
}
```

### 5. Dynamic Mood Schema

The dynamic mood schema adapts responses based on entity state and context:

#### Contextual Mood Detection
```typescript
interface MoodContext {
  recent_interactions: Interaction[];
  interaction_sentiment: number;    // -1.0 to 1.0
  response_time_pattern: number;    // Deviation from normal
  topic_engagement: number;         // Current topic interest level
  stress_indicators: string[];      // Detected stress signals
  preferred_style: CommunicationStyle;
}

function detectCurrentMood(
  entityId: number,
  recentWindow: number = 24 * 60 * 60 * 1000 // 24 hours
): MoodContext {
  const recent = getRecentInteractions(entityId, recentWindow);
  const baseline = getBaselineMetrics(entityId);
  
  const sentiment = calculateAverageSentiment(recent);
  const responsePattern = analyzeResponseTimeDeviation(recent, baseline);
  const engagement = calculateCurrentEngagement(recent);
  const stressIndicators = detectStressSignals(recent);
  const preferredStyle = inferPreferredStyle(recent, baseline);
  
  return {
    recent_interactions: recent,
    interaction_sentiment: sentiment,
    response_time_pattern: responsePattern,
    topic_engagement: engagement,
    stress_indicators: stressIndicators,
    preferred_style: preferredStyle
  };
}
```

#### Adaptive Response Selection
```typescript
function selectResponseStyle(
  moodContext: MoodContext,
  entityProfile: EntityProfile
): ResponseConfiguration {
  const baseStyle = entityProfile.communication_style || 'balanced';
  
  // Adapt based on current mood
  let adaptedStyle = baseStyle;
  let urgencyLevel = 'normal';
  let emotionalTone = 'neutral';
  
  // Stress indicators suggest need for empathy
  if (moodContext.stress_indicators.length > 0) {
    emotionalTone = 'supportive';
    adaptedStyle = makeStyleMoreGentle(adaptedStyle);
  }
  
  // Low engagement suggests need for brevity
  if (moodContext.topic_engagement < 0.3) {
    adaptedStyle = makeStyleMoreConcise(adaptedStyle);
  }
  
  // Negative sentiment suggests careful approach
  if (moodContext.interaction_sentiment < -0.3) {
    emotionalTone = 'careful';
    urgencyLevel = 'low';
  }
  
  // Fast response pattern suggests high engagement
  if (moodContext.response_time_pattern < -0.5) {
    urgencyLevel = 'high';
    adaptedStyle = makeStyleMoreDetailed(adaptedStyle);
  }
  
  return {
    communication_style: adaptedStyle,
    emotional_tone: emotionalTone,
    urgency_level: urgencyLevel,
    context_sensitivity: calculateContextSensitivity(moodContext),
    personalization_level: calculatePersonalizationLevel(moodContext, entityProfile)
  };
}
```

#### Mood History Tracking
```typescript
function trackMoodEvolution(
  entityId: number,
  timeWindow: number = 30 * 24 * 60 * 60 * 1000 // 30 days
): MoodEvolution {
  const moodHistory: MoodSnapshot[] = [];
  const windowSize = 24 * 60 * 60 * 1000; // Daily snapshots
  
  for (let t = Date.now() - timeWindow; t < Date.now(); t += windowSize) {
    const mood = detectMoodAtTime(entityId, new Date(t));
    moodHistory.push({
      timestamp: new Date(t),
      sentiment: mood.interaction_sentiment,
      engagement: mood.topic_engagement,
      stress_level: mood.stress_indicators.length,
      response_speed: mood.response_time_pattern
    });
  }
  
  return {
    timeline: moodHistory,
    sentiment_trend: calculateTrend(moodHistory.map(m => m.sentiment)),
    engagement_trend: calculateTrend(moodHistory.map(m => m.engagement)),
    stress_pattern: analyzeStressPattern(moodHistory),
    stability_score: calculateMoodStability(moodHistory),
    prediction: predictFutureMood(moodHistory)
  };
}
```

## Integration and Usage

### Context Weighting Integration
```typescript
function calculateContextWeight(
  entityFact: EntityFact,
  currentContext: InteractionContext
): number {
  const confidence = calculateConfidenceScore(entityFact);
  const relevance = calculateRelevance(entityFact, currentContext);
  const recency = calculateTemporalDecay(entityFact.created_at);
  
  // Token cost consideration
  const factLength = entityFact.value.length;
  const costPenalty = factLength > 100 ? 0.8 : 1.0;
  
  return confidence * relevance * recency * costPenalty;
}
```

### Real-time Analysis Pipeline
```typescript
class AnalysisPipeline {
  async processNewInteraction(interaction: Interaction): Promise<AnalysisResult> {
    // Run algorithms in parallel
    const [confidence, frequency, mood, associations] = await Promise.all([
      this.updateConfidenceScores(interaction),
      this.analyzeFrequencyPatterns(interaction),
      this.updateMoodAnalysis(interaction),
      this.discoverNewAssociations(interaction)
    ]);
    
    // Update entity profiles
    await this.updateEntityProfile(interaction.entity_id, {
      confidence_updates: confidence,
      frequency_patterns: frequency,
      current_mood: mood,
      new_associations: associations
    });
    
    return {
      updated_facts: confidence.updated_facts,
      pattern_changes: frequency.significant_changes,
      mood_shift: mood.mood_change_detected,
      new_relationships: associations.filter(a => a.confidence > 0.8)
    };
  }
}
```

---

*These algorithms form the analytical foundation of the NOVA Relationships system, enabling intelligent entity understanding and context-aware interactions. They work together to create a comprehensive picture of entity behavior, relationships, and preferences.*