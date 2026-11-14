# Product review — 14 November 2026

## Recommendation

**Owner clarification:** Personal bet history, entering placed bets, grading
outcomes and a record-centered experience are not wanted. The automatic
observation journal built earlier in this session has been removed, as have
the Bets tab, My bets tool, save-to-bet-log actions and the prominent Home
report link. Existing stored files are preserved. Model validation stays in
secondary methodology views; it does not require users to track anything.

Build the clearest NFL price-research experience: find a player or game,
understand the price, inspect the evidence, and compare alternatives. The next major milestone should be that complete
phone experience. A new ensemble model and a more elaborate parlay simulator
should follow a clear, dependable core journey.

Simplicity means presenting the next useful decision first, with depth one
tap away. It does not mean deleting the existing math and research tools.

## Scope and evidence

Reviewed official product/help pages, public product previews, repository
implementation and rendered 390px app screenshots. No paid account, private
competitor dashboard, sportsbook account or proprietary model was accessed.
Vendor claims about returns, accuracy, speed and coverage are not independently
verified. This is a product comparison, not a profitability ranking.

There are multiple live products called OddsEdge. The two independently
identified below are both included; neither is silently assumed to be the
owner's exact intended competitor. That overlap is also a practical reason
to choose a more distinctive product identity before public distribution.

## Competitive lessons

| Product and primary evidence | Useful pattern | Our version and limits |
| --- | --- | --- |
| [Outlier Prop Finder](https://help.outlier.bet/en/articles/6711738-research-player-propositions-with-outlier-s-prop-finder) and [public product](https://www.outlier.bet/) | Scan a filterable prop feed, then open a richer evidence page. Public previews combine history, matchup context, line movement and both supporting/opposing arguments. | Keep one legible price card and one consistent detail destination. Put deeper evidence behind named sections, with an obvious way back to the same list/filter. Our stored NFL snapshots do not match its advertised real-time, multi-sport coverage. |
| [PropsBot product](https://propsbot.ai/) and [confidence definition](https://propsbot.ai/glossary/confidence-score/) | Distinguishes model agreement from price edge; surfaces a public performance-ledger entry point. | Keep win estimate, price break-even and evidence quality distinct. Keep validation sample counts in secondary methodology views. Do not invent an AI confidence percentage: PropsBot itself says its score is not the chance of a win. Do not build a user betting ledger or imply that internal validation is an audited public record. |
| [Props.Cash](https://props.cash/) and [its September product update](https://propsdotcash.beehiiv.com/p/the-props-cash-website-just-got-a-brand-new-look) | Charts, contextual filters, search, saved filters and team/matchup pages make deeper research approachable. | Preserve the existing chart and player history, add a coherent evidence view and reusable filter presets. Any historical filter must show its sample size and remain distinct from a forecast. Do not add live progress bars without a reliable live-score source. |
| [OddsJam EV tool](https://oddsjam.com/betting-tools/positive-ev) | Clear job: compare a price, inspect the opportunity and track the outcome. | Make exact-selection book comparison immediate and show snapshot freshness beside the price. Existing free cached data can support comparison, not advertised real-time execution parity. Bet tracking is not part of our product direction. |
| [OddsEdge.ai](https://oddsedge.ai/) | Focused arbitrage-opportunity and calculator workflow. | Borrow the narrow task focus. Retain execution/rules caveats; do not adopt its homepage's unconditional profit language. |
| [OddsEdge sportsbook scanner](https://www.oddsedgebet.com/) | Consensus fair-price comparison, market detail and line-movement positioning. | Show fair market chance as context, distinct from our model estimate and the price's break-even chance. Its public preview had zero loaded edges when reviewed; that is not evidence about its private coverage or results. |

The competitors' strongest shared idea is an efficient research journey.
Their promotional win language and large feature inventories are not a
design specification for this app.

## Assessment of our app

**Strong foundations.** The code already has precise selection matching,
price provenance, demo labels, no-vig math, local storage, historical player
evidence, injury context, usage projections, a price ladder and expandable
reasoning. The game model report honestly shows losses and refuses to call
an insufficient sample an edge. Personal betting journals are not part of the intended experience.

**The main problem is hierarchy.** Before this pass, five primary tabs exposed
Home, Games, Props, Parlays and Bets. Bets is now removed, while Home still
repeats Games and adds Value,
Trending and “Don't.” More leads into several older research/tool paths.
There are useful tools, but too many overlapping starting points.

**Cards are useful but compete for attention.** A prop card can show an
action word, two probability values, a points gap, three historical windows,
a sparkline and matchup copy before opening its detail. This is substantial
information for an experienced user; it needs a quieter initial hierarchy
for a new user. The next main card should answer “what is this price?” and
“why investigate?” before presenting every supporting statistic.

**Language needs one consistent contract.** “Bet” can sound like a command,
especially when the model's past profit test does not establish an edge.
Replace that presentation in a later wording pass with a descriptive price
assessment, while keeping model estimates distinct from demonstrated accuracy.
“Trending” should explain whether it means recent historical clear rates or
popular activity; this app currently has the former, not a popularity feed.
“Don't” is too ambiguous for navigation. Model chance, observed hit rate,
market no-vig and price break-even must never be interchangeable.

**Data readiness must be visible.** Loading player evidence previously
looked like missing chances and Skip verdicts. That is now an explicit
loading state. Missing data after a failed load remains an honest
unavailable state. Sample quotes can describe synthetic matchups that do
not reflect a player's actual team; the example badge must remain visible.

**Responsiveness is part of the design.** Pricing alternatives repeatedly
recomputed the same player windows and projections across a board. This
pass shares those computations within each pricing pass, without keeping
results across changed inputs. Verdict parity is covered by a regression
test. This reduces duplicate work; a measured web frame-time/startup
benchmark remains outstanding. Browser inspection of the built app hit
repeated timeouts, so full interactive web behavior is not signed off by
the successful compile or widget screenshots.

## Implemented in this pass

- A project-local Flutter 3.47.7 / Dart 3.13.5 setup with repeatable Windows
  setup and Flutter wrapper scripts; no global PATH dependency.
- Removed personal bet-tracking entry points and the new record interface.
  Research and price comparison remain the focus.
- Cool graphite surfaces, soft blue interactive controls, neutral white
  text, and restrained mint/amber/coral status colors. Sans typography for
  interface headings and figures; the serif wordmark stays distinctive.
- Explicit theme divider colors, avoiding the visually harsh default
  separators in the previous rendering.
- Player-data loading presentation and per-pass pricing reuse.
- Today / Research / Tools navigation; Props/Games switch inside Research.
  Visited research views preserve search, filters and list position.
- Search by player, team or stat, remembered prop filters, unavailable-filter
  handling and a clear reset when the current criteria have no matches.
- Price-first prop details: model estimate versus the posted price's
  break-even chance, source age, support/caution summary, and expandable
  Performance, Matchup/availability, Prices and Model/math sections.
- Review / Thin margin / Pass replace the directive Bet / Lean / Skip
  presentation. Existing enum identities and pricing thresholds are unchanged.
- Portable phone screenshots under `build/review` instead of a former
  developer's machine-specific output directory.

Opaque text/status tokens on the three background surfaces all exceed
4.5:1 contrast (21 pairs); primary-button text is 8.95:1. This is a token
check, not a complete accessibility audit of alpha overlays, charts,
focus, semantics, screen readers or platform settings.

Validation of the final implemented pass: Flutter analysis has no issues;
all 260 Flutter tests and all 38 Python model tests pass. Windows and web
release builds pass. The optional screenshot workflow passes and renders
Home, Games, Props, prop detail and the existing parlay slip. Images are local
QA artifacts under `build/review`, not evidence of profitable predictions.

## Visual direction

| Role | Token | Use |
| --- | --- | --- |
| Background | `#0C1017` | Quiet canvas |
| Card | `#151C25` | Content grouping |
| Raised surface | `#202A37` | Inputs and secondary grouping |
| Primary text | `#F3F6FA` | Main content |
| Secondary text | `#BAC6D6` | Supporting evidence |
| Interaction | `#A8C7FA` | Selected navigation and primary controls |
| Positive / caution / negative | `#69D7B0` / `#F1C27A` / `#FF918A` | Labeled assessments and charts |

This is a design hypothesis about clarity and tone, not a claim that a
specific color scientifically increases retention. Keep hierarchy, spacing,
recognizable controls and feedback consistent. Avoid ornamental glass or
gradients over numerical content. Add a matching light appearance as its
own designed and tested variant, not an automatic color inversion.

[Apple's design principles](https://developer.apple.com/design/human-interface-guidelines/design-principles/)
support clear hierarchy, agency and purpose. Its [layout guidance](https://developer.apple.com/design/human-interface-guidelines/layout)
explicitly recommends progressive disclosure, and its [color guidance](https://developer.apple.com/design/human-interface-guidelines/color)
supports consistent semantic colors and non-color alternatives.

## The next complete product milestone

Navigation, prop disclosures and preference continuity below are now
implemented. The remaining work is a full accessibility/performance audit,
more evidence usability testing, and a deliberately designed light appearance.
Bookmarks and a continue-research entry remain optional, not a bet journal.

1. **Consolidate navigation.** Three destinations: Today, Research and Tools.
   Research contains Props/Games as a local switch; calculators and deeper
   model explanations sit behind clear secondary links. No Bets or Record
   destination. A parlay is a research comparison, not a personal outcome log.
   Preserve old data formats while replacing entry points.
2. **Finish one excellent prop detail.** Price and freshness first; a small
   recent-history chart; three visible evidence sections: Performance,
   Matchup and Price. Put assumptions, model limitations and math beneath
   them. Show both supporting and opposing evidence. Returning restores
   the user's list position and filters.
3. **Make continuity useful.** Saved filters, bookmarked research and a
   “Continue research” entry, if useful. Make returning faster through saved
   preferences and relevant evidence, without asking users to log bets or
   enter outcomes.
4. **Prove the experience.** Validate at 390×844 and enlarged text, with
   reduced motion and keyboard/screen-reader navigation. Measure search to
   useful detail and ability to identify example/stale data. Check frame
   times and first useful content on web and Windows before calling it smooth.

Only then prioritize empirical correlated-parlay simulation with its
walk-forward joint calibration. Keep the proposed ensemble model separate
and subject to the existing adoption rules. More model complexity will not
repair confusing navigation or stale inputs.

## Responsible engagement

Optimize for finishing a useful research task and understanding the evidence.
Use clear saved-state feedback, persistent preferences, respectful motion
and user-controlled research preferences. Do not optimize time spent,
number of bets, or frequency of checking prices. No streak rewards, loss
recovery prompts, countdown pressure, confetti, or manufactured urgency.

Alerts should eventually be opt-in, tied to a saved research condition,
deduplicated and rate-limited, with quiet hours and a clear off switch.
They require an appropriate data/deployment plan first; none were enabled.

No signups, purchases, paid feeds, public deployment or additional live-odds
credits were used for this review. The current differentiator is transparent
NFL research and price comparison; real-time multi-sport parity remains outside the
current free-snapshot architecture.
