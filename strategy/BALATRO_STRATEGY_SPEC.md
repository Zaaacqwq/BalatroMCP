# Balatro Strategy Spec

Version: 1

Purpose:

- Give an LLM a stable, reusable Balatro strategy without fine-tuning.
- Prefer high win rate and consistency over flashy high-roll lines.

## 1. Facts The Agent Should Treat As Ground Truth

These are factual gameplay anchors taken from the wiki and used to shape the strategy:

- Jokers are central to the game plan and players usually start with 5 Joker slots.
- A run progresses through Antes; each Ante contains a Small Blind, Big Blind, and Boss Blind.
- A standard run is won by beating the finisher blind at Ante 8.
- Small and Big Blinds can be skipped for Tags; Boss Blinds must be played.
- The shop appears after defeating a blind and normally offers 2 random cards, 2 booster packs, and 1 voucher.
- Shop rerolls start at $5, go up by $1 each reroll, and reset on the next shop.
- Booster packs come in Arcana, Buffoon, Celestial, Spectral, and Standard categories.
- Planet cards level up poker hands.
- Tarot and Spectral cards modify deck composition, card quality, and resources.
- Stakes stack cumulatively, so higher stakes inherit lower-stake penalties.

## 2. Primary Objective

The primary objective is to maximize win rate for normal runs.

Decision priority:

1. Survive the current blind.
2. Preserve or improve future blind consistency.
3. Grow economy when survival margin exists.
4. Increase late-run ceiling only when it does not significantly reduce current survival.

## 3. Strategic Identity

The agent should not play like a gambler by default.

Default identity:

- Stable
- Economy-aware
- Synergy-first
- Conservative with rerolls
- Will pivot only when the new line is clearly stronger than the current one

## 4. Core Heuristics

### 4.1 Survival First

If the current blind looks dangerous, the agent should prefer immediate score over long-term greed.

Danger signals:

- Current scoring line barely clears the blind.
- Current hand quality is poor and remaining hands are low.
- Boss blind directly attacks the current build.
- Current build depends on fragile conditions not yet set up.

When danger is high:

- Buy immediate score.
- Level the hand type already being played.
- Avoid speculative economy pickups.
- Avoid greed rerolls.
- Avoid skipping blinds unless the tag payoff is exceptional and the blind is already trivial.

### 4.2 Build Around a Scoring Line

The agent should usually commit to one main scoring line at a time:

- high card
- pair
- two pair
- three of a kind
- straight
- flush
- full house
- four of a kind
- straight flush
- secret hands if clearly enabled

Preferred progression:

- Early game: commit to the easiest reliable line supported by current deck and jokers.
- Mid game: improve the same line with planets, deck fixing, and joker synergy.
- Late game: only pivot if a new joker package or deck transformation clearly dominates.

### 4.3 Joker-Centric Planning

Treat jokers as the core of the build.

Joker priority order:

1. Jokers that make the current line win now.
2. Jokers that multiply existing value.
3. Jokers that improve consistency or deck control.
4. Economy jokers that do not weaken current survival.
5. Speculative jokers only if there is board space and pivot value is real.

Preferred joker balance:

- 1 immediate score enabler
- 1 scaling or multiplicative payoff
- 1 consistency or deck-fixing tool
- 1 economy card if safe
- 1 flex slot

General joker rules:

- Avoid buying isolated goodstuff that does not fit the current line.
- Prefer multiplying an already-good line over splitting into two weak lines.
- Sell low-impact jokers once a stronger synergy package is online.
- Be cautious with temporary/perishable/rental obligations on high stakes.

### 4.4 Economy Rules

Money exists to increase win rate, not to sit unused forever.

Economy rules:

- Protect enough money to avoid being forced into bad shops.
- Buy strong tempo if the current blind curve is threatening.
- Reroll only when the current shop is weak relative to the build and there is enough surplus money.
- Do not reroll aggressively in early shops without economy support.
- Prefer guaranteed value over chasing rare perfect hits.

### 4.5 Deck Manipulation

The agent should value deck quality more than deck size alone.

Good deck changes:

- Remove cards that dilute the primary hand type.
- Increase rank and suit concentration when building straights, flushes, pairs, or full houses.
- Add enhanced/sealed/editioned cards only if they support the current line.
- Use Tarot and Spectral effects to create a more consistent scoring deck, not random novelty.

Avoid:

- Random card additions with no synergy.
- Weak deck-thinning that breaks current hand assembly.
- Transformations that reduce short-term consistency unless the run is already secure.

## 5. Phase Rules

### 5.1 Blind Selection

Default:

- Play Small Blind if the deck needs money, setup, or safety.
- Skip Small or Big Blind only when the tag value clearly exceeds the lost rewards and the upcoming fight remains safe.
- Do not skip into a dangerous Boss Blind without a strong reason.

### 5.2 In-Round Play

For each hand:

1. Estimate whether the blind can be beaten with remaining hands.
2. If yes, prefer the lowest-risk line that gets there.
3. If no, maximize expected score this hand while preserving one backup line if possible.

Discard policy:

- Discard to improve consistency toward the current line.
- Avoid vanity discards when already on pace to win.
- Value discards more on decks or stakes where hand count is constrained and hand quality matters more.

Play policy:

- Prefer reliable scoring over fragile high-roll assemblies.
- Use consumables before the hand only when they clearly increase expected value now or unlock an important future threshold.

Card selection policy inside a chosen hand type:

- Do not stop at choosing the hand class; also optimize the exact cards played.
- When multiple card sets produce the same poker hand, prefer the set that preserves future hand quality.
- Do not assume a hand must contain 5 played cards; Balatro allows playing 1 to 5 cards.
- First identify the smallest legal card set that forms the intended scoring hand.
- Then decide whether to add extra cards into the remaining slots as a controlled refresh of bad cards.
- For pair, two pair, three of a kind, and four of a kind, prefer the smallest scoring core first, then fill any extra slots only with cards that are low future value.
- Preserve high cards, overcards, strong straight connectors, strong flush cards, and other likely future keeps unless there is a concrete reason to spend them now.
- Treat extra non-scoring cards as disposable refresh candidates, not as automatic inclusions.
- Good extra cards to throw in are low-value offsuit junk, broken connectors, duplicate dead weight, or cards the current build is actively trying to cycle out.
- If there are no clearly disposable extras, prefer the minimum-card version of the hand rather than adding random side cards.
- Only spend high-value side cards when one of these is true:
  - they are required to form the hand
  - they are required to beat the blind this hand
  - joker, enhancement, seal, edition, or boss mechanics specifically reward those exact cards
- If two plays have similar immediate score, prefer the one that keeps the next hand's pair/straight/flush potential higher.
- Avoid attaching Ace/King/Queen/Jack or premium connectors to a weak pair line by default when lower-value throwaway cards can occupy those slots instead.

### 5.3 Shop Phase

Buy order:

1. Immediate survival joker or card improvement.
2. Multiplicative scaling for an already-working line.
3. High-value voucher that fits the build.
4. Planet cards for the main hand type.
5. Tarot or Spectral effects that improve deck quality.
6. Reroll only if none of the above are good and money permits.

### 5.4 Pack Choice

Default pack value order depends on the build:

- Buffoon when joker quality is the main bottleneck.
- Celestial when the main hand is identified and worth leveling.
- Arcana when deck editing or enhancements are highly valuable.
- Standard when the run needs specific playing-card quality or suit/rank concentration.
- Spectral when the deck can absorb risk and the payoff is high.

## 6. Consumable Rules

### 6.1 Planet Cards

Planets are premium when the run already knows its main hand type.

Use planet cards aggressively when:

- One hand type is clearly dominant.
- The deck consistently produces that hand.
- Joker synergy rewards that hand.

Use less aggressively when:

- The run has not stabilized on a main line.
- The hand type is unreliable.

### 6.2 Tarot Cards

Tarot cards are for deck shaping, enhancement, money bursts, and tactical setup.

Use Tarot to:

- Improve card quality in the main line.
- Remove weak cards.
- Concentrate ranks and suits.
- Create jokers or money only when it supports current needs.

Avoid using Tarot in ways that:

- Spread the deck in multiple incompatible directions.
- Create a flashy card that the current line does not use.

### 6.3 Spectral Cards

Spectral cards usually have bigger upside and bigger downside.

Use Spectral cards when:

- The run needs a decisive power spike.
- The current deck can absorb the drawback.
- The effect strongly supports the chosen line.

Avoid them when:

- The blind is already unstable.
- The drawback harms consistency more than the upside helps.

## 7. Voucher Rules

Voucher policy:

- Buy vouchers that improve the current run's consistency, economy, or access to relevant resources.
- Value merchant/overstock-style acceleration highly when the run can exploit it.
- Be selective with vouchers that give long-run upside but little immediate help on dangerous runs.

Because vouchers are paired:

- Buying a useful initial voucher can unlock stronger future value.
- Do not buy weak prerequisite vouchers unless the downstream value is likely to matter.

## 8. Stake Adjustments

### White to Green

- Play fundamentally strong lines.
- Moderate greed is acceptable.
- Economy and setup retain high value.

### Black Stake

- Eternal jokers appear more often.
- Avoid short-lived or easily replaceable filler purchases.
- Be more careful before buying a joker that could become dead weight.

### Blue Stake

- With fewer discards, consistency matters more.
- Prefer lines that can be assembled without excessive digging.
- Increase the value of hand quality, deck shaping, and direct-score jokers.

### Purple Stake

- Faster score scaling reduces time to stabilize.
- Buy tempo sooner.
- Reroll less for luxury upgrades.

### Orange Stake

- Perishable risk reduces the value of slow-burn setup pieces.
- Favor immediate and medium-horizon value over slow scaling.

### Gold Stake

- Rental pressure makes bad purchases much more punishing.
- Every buy should justify its carrying cost or sale timing.
- Prioritize cheap, efficient, high-impact pieces and maintain cash discipline.

## 9. Deck-Specific Strategic Adjustments

See `deck_profiles.yaml` for the concise machine-readable version.

High-level guidance:

- Red Deck: use the extra discard to support consistency-driven lines.
- Blue Deck: use extra hand count to play safer and preserve discards.
- Yellow Deck: leverage the extra $10 into early power or economy compounding.
- Green Deck: preserve spare hands and discards because they convert directly to cash.
- Black Deck: the extra joker slot encourages stronger synergy packages, but the lower hand count punishes slow setup.
- Magic Deck: treat consumable play as part of the core plan from the start.
- Nebula Deck: favor a clearly identified main hand because Telescope improves planet access value.
- Ghost Deck: respect the higher access to Spectral effects but do not over-gamble.
- Abandoned Deck: face-card synergies are off; pair/straight/consistency lines improve.
- Checkered Deck: flush lines become much more reliable.
- Zodiac Deck: exploit its strong starting shop/voucher acceleration.
- Painted Deck: use the larger hand size to assemble stronger hands, but value joker slots more carefully.
- Anaglyph Deck: plan around future Double Tag payoff when skips are safe.
- Plasma Deck: evaluate scoring lines with chip/mult balance in mind, not normal intuition.
- Erratic Deck: identify concentration patterns quickly and commit to what the deck actually supports.

## 10. Decision Scoring Template

Every candidate action should be scored across four axes:

- survival_value
- synergy_value
- economy_value
- risk_penalty

The agent should prefer the action with the best total:

`total = survival_value + synergy_value + economy_value - risk_penalty`

Interpretation:

- survival_value: how much this action improves odds of beating the current blind
- synergy_value: how much this action strengthens the current build direction
- economy_value: how much this action preserves or improves future purchasing power
- risk_penalty: how likely this action is to strand the run, create dead pieces, or force bad future turns

## 11. Hard Rules

- Never choose an illegal action.
- Never buy a card only because it is generically famous or strong; it must fit the current run.
- Do not reroll below a safe cash floor unless the current shop is actively failing the run.
- Do not pivot the entire build without at least one strong enabling reason.
- If the boss blind attacks the current build, adapt immediately even if that lowers long-term ceiling.
- If a win is already secure, reduce unnecessary variance.

## 12. What The Agent Should Output

At each turn, the agent should produce:

1. Current plan state:
   - survival
   - stabilize
   - econ
   - pivot
   - high_roll
2. Chosen action
3. Short reason tied to this strategy spec

## 13. Portability Guidance

This strategy is meant to be external memory, not model memory.

Use this instead of fine-tuning when possible:

- store it in the repo
- inject only relevant fragments at inference time
- keep versioned updates
- share the same strategy across Codex, Claude, Copilot, and other MCP clients

Fine-tuning is not the recommended first step here because:

- the policy changes often
- the game contains many local exceptions
- deck/stake/shop context is easier to handle with retrieval than with fixed weights

## Sources

- Balatro Wiki main page: https://balatrogame.fandom.com/wiki/Balatro_Wiki
- Jokers: https://balatrogame.fandom.com/wiki/Jokers
- Decks: https://balatrogame.fandom.com/wiki/Decks
- Poker Hands: https://balatrogame.fandom.com/wiki/Poker_Hands
- Card Modifiers: https://balatrogame.fandom.com/wiki/Card_Modifiers
- The Shop: https://balatrogame.fandom.com/wiki/The_Shop
- Stakes: https://balatrogame.fandom.com/wiki/Stakes
- Blinds and Antes: https://balatrogame.fandom.com/wiki/Blinds_and_Antes
- Tags: https://balatrogame.fandom.com/wiki/Tags
- Tarot Cards: https://balatrogame.fandom.com/wiki/Tarot_Cards
- Planet Cards: https://balatrogame.fandom.com/wiki/Planet_Cards
- Spectral Cards: https://balatrogame.fandom.com/wiki/Spectral_Cards
- Vouchers: https://balatrogame.fandom.com/wiki/Vouchers
- Booster Packs: https://balatrogame.fandom.com/wiki/Booster_Packs
