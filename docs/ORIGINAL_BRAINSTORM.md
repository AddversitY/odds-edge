# Recovered Odds Edge brainstorming reference

Source: https://chatgpt.com/share/6ad44e23-5178-83ea-8863-63936a2fd474
Read from the rendered shared conversation on October 18, 2026. This document
summarizes the actual analytical-platform, niche and monetization replies now
accessible through that link. It is not a verbatim archive or a claim that image
attachments and interactive prototypes were imported.

## Product identity

A customizable sports betting research laboratory. Users investigate evidence,
change model assumptions, test scenarios, compare market prices and objectively
review forecasts. The emphasis is transparency, customization and verification,
rather than selling picks or asking users to trust unexplained probabilities.

## Platform experience

Windows: a complete analytical workstation with multiple charts, customizable
panels and detailed tables. iOS: the same analytical depth organized into
touch-friendly tabs and expandable views. Shared Flutter foundations do not
mean identical layouts or reduced research functionality on mobile.

## Five foundational capabilities

1. **Deep Statistical Explorer:** team/player history, opponent strength,
   situational splits, advanced metrics, usage, efficiency and trends. Date-range
   controls and direct player/team comparisons.
2. **Advanced Simulation Engine:** repeated simulations under assumptions about
   injuries, environment, pace and player usage, with uncertainty ranges and
   sensitivity analysis. Results require defensible sport-specific models.
3. **Sportsbook Odds Laboratory:** multi-book comparison, no-vig probabilities,
   historical movement and model-versus-market investigation.
4. **Parlay Correlation Analyzer:** joint outcomes from correlation-aware models;
   no blind multiplication of dependent leg probabilities. This is distinct from
   arbitrage and is not removed by postponing arbitrage.
5. **Transparent AI Research Assistant:** questions answered with source data,
   charts and reproducible calculations. AI explanations must not invent inputs
   or present unsupported estimates as validated forecasts.

## Differentiation and Proof Lab

The original conversation proposed an integrated research cycle: formulate a
theory, test it against past events, freeze a forward prediction and evaluate it
after the outcome. Suggested flagship components:

- **Historical Replay Lab:** point-in-time statistics, injuries and sportsbook
  prices, with strict no-hindsight controls. Today's lines and later knowledge
  cannot fill missing historical records.
- **Edge Reliability Analyzer:** test whether an apparent edge survives reasonable
  changes in assumptions; report sample sizes, calibration, uncertainty, price
  freshness and model disagreement. Distinguish fragile conclusions from robust
  evidence rather than highlighting a baseline EV alone.
- **Game Script Simulator:** coherent game-level scenarios connect changes such
  as early leads or player absences to downstream volume, scoring and props.
  Arbitrarily adding independent slider effects is only an explanatory demo.
- **Prediction Autopsy:** retain all forecasts, not just placed bets. Compare
  original assumptions with actual plays/usage/participation and use calibration
  to distinguish systematic errors from ordinary outcome randomness.
- **Market Truth Detector:** assess quote age, source corroboration, accessibility,
  exact line/rule identity and movement to identify misleading apparent value.

**Proof Lab** was the proposed umbrella and signature research report, combining
these tools. The strongest proposed initial combination was Historical Replay,
Edge Reliability and Prediction Autopsy. These were opportunities to validate,
not verified claims that no competitor offers similar functionality.

## Facts versus assumptions

Keep sourced historical facts immutable. Store user overrides separately with
versioned models, feature snapshots, probabilities and quote timestamps. Explain
what changed and its impact. A computed EV is mathematically conditional on its
probability input; it is not proof that the probability is accurate. Numerical
examples in the original chat were invented demonstrations.

## Original development and commercial proposals

The earlier conversation suggested starting with NFL moneylines, spreads and
totals, saving custom models/research and adding more complex props later.
Flutter was proposed for the application and Python for statistical computation.
The current prototype's odds service is Dart; Python statistical services remain
an architectural proposal, not an already implemented backend.

Monetization centered on analytical tools rather than picks. Free, Pro and Elite
were proposed, with illustrative monthly prices of $0, $19.99 and $49.99. Those
prices and feature allocations were not validated commitments. Suggested future
foundations included accounts, saved research, feature entitlements and metering
expensive simulations, with no real payments activated before product validation.
Revenue examples were arithmetic scenarios, not forecasts. Competitor, provider,
platform and agent-product claims in the chat must be independently checked
before reuse as current facts.

## Later user direction takes precedence

- The published goal is broad multi-sport coverage, including college football,
  tennis and combat sports. NFL is the first prototype, not the entire product.
- Initial costs must stay low; no $300–$400/month feed commitment is authorized.
- The owner explicitly wants to return to this analytical vision and omit
  arbitrage from the initial phase. Preserve parlay correlation as a separate
  analytical capability and live comparison as a core architectural requirement.
- No provider purchase, vendor outreach, publishing, account connection or
  installation is authorized merely because an old assistant reply recommended it.

See `PRODUCT_PLAN.md` for the current implementation sequence and safeguards.
