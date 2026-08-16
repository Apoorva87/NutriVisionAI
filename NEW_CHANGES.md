# NEW_CHANGES

## Overall Product Direction

The app should feel simpler, calmer, and more polished without throwing away the functionality that already works well.

The main product change is:

- keep the tab name simple as `Log`
- merge the current `Scan` and `Log` intent into one cleaner experience inside that tab
- preserve the current working search flow
- preserve the current working AI lookup flow
- preserve the current grocery suggestion behavior
- improve how these things are presented so users need fewer clicks and less decision-making

This should feel like a refinement of the existing app, not a brand new product.

## Visual Direction

New UI should stay close to what is already implemented.

That means:

- keep the current dark theme
- keep the rounded card language
- keep the purple accent style
- keep the clean, premium, slightly glowy look that already exists
- avoid introducing a totally different visual system just because a screen is new

The app should feel consistent from old screens to new screens.

## The `Log` Tab

The tab should remain short and simple.

Preferred name:

- `Log`

Not preferred:

- `Add Food`

Inside `Log`, the user should immediately understand three things they can do:

1. `Scan`
2. `Search`
3. `Ask AI`

These should not feel like three separate worlds. They are three ways to add food into the same in-progress meal.

## What `Scan` Should Mean

`Scan` should be the strongest, most obvious action inside the `Log` tab.

When the user taps `Scan`, the camera should elegantly support both:

- taking a normal food picture
- scanning a barcode on a packaged item

The user should not feel like they have to choose between "camera mode" and "barcode mode" before opening the camera.

Instead, the scanning screen should imply:

- barcode scanning is live and available
- meal-photo capture is also available
- both are part of the same scanning experience

The scanning screen should feel smart and minimal.

Good behavior:

- if a barcode is recognized, the app surfaces that naturally
- if the user taps the shutter, the normal meal image flow runs
- the camera screen communicates both abilities in an elegant, low-friction way

## What `Search` Should Mean

`Search` should stay simple.

The user should be able to:

- type
- speak

And then the app should start showing likely matches below as they go.

This should continue using the current search behavior and current data sources. The main change is presentation and ease of use, not changing the underlying functionality.

Expected behavior:

- fuzzy results appear live
- likely matches show below the input
- the UI feels fast and lightweight
- voice and typing both feed the same query experience

This should feel like:

- quick
- compact
- forgiving
- low-click

## What `Ask AI` Should Mean

The current AI lookup behavior is good and should not be reinvented.

The main change should be the entry experience.

The easiest way to begin `Ask AI` should be:

- tap and speak

Then:

- the speech is transcribed into English
- the transcript is cleaned up so it focuses on food items, quantities, and sizes
- normal conversational filler is reduced
- the cleaned-up food description is passed into the existing AI macro estimation flow

Important product principle:

- do not change the core AI estimation behavior if the current result quality is already good enough

This should feel like the current AI feature, just more natural to start.

## Shared Meal Draft Behavior

No matter how the user adds food:

- scan
- search
- AI lookup

Everything should collect into one meal draft.

That draft should feel easy to understand at a glance.

The user should always be able to tell:

- how many items are currently in the draft
- what the current calorie total is
- what was just added
- how to review or save the draft

The draft UI should stay compact and not take over the whole screen unless the user explicitly opens it.

## Grocery List: Product Goal

The grocery page should become much stronger without becoming visually noisy.

The most important direction here is:

- compact UI
- strong AI suggestions
- multi-store price awareness
- low friction
- persistent decisions

The grocery screen should feel like a smart shopping assistant, not just a static checklist.

## Grocery List: What Must Be Preserved

The current AI grocery suggestion behavior is valuable and should remain.

That means the grocery list should still feel like it understands:

- what the user has been eating
- the preferences or cuisine prompt the user gives
- weekly grocery needs derived from those habits or suggestions

This should remain a core part of the page, not an afterthought.

## Grocery List: Compact UI Direction

The grocery page should be information-dense but still calm.

It should not feel cluttered even when prices from multiple vendors are shown.

The desired feel is:

- compact rows
- easy scanning
- store comparison without visual overload
- subtle use of hierarchy

A good compact grocery row should show:

- item name
- quantity
- optional context or hint
- 2-3 store price choices in a compact form

The store comparison should be easy to read without requiring huge labels everywhere.

Preferred UI treatment:

- use store symbols or compact brand markers in the compare strip when possible
- avoid long repeated retailer names if they make the row feel bulky

## Grocery List: Vendor Price Compare Behavior

The grocery screen should be able to pull prices from different sources and show them in a way that feels actionable.

The compare view should not just display prices passively.

It should allow the user to make a store choice per item naturally.

Desired behavior:

- each item can show compact prices from multiple stores
- tapping a store price means "I want to get this item from this store"
- the chosen price becomes a store assignment for that item

This should feel lightweight and obvious.

## Grocery List: Store Buckets

When the user taps prices for different stores, the app should build store-specific buckets in the background.

Example:

- yogurt assigned to one store
- spinach assigned to another store
- bars assigned to a third store

Then the app should remember those assignments.

This matters because the grocery experience should feel cumulative.

The user should not have to redo store choices every time they come back.

The app should remember:

- which store the user selected for each item
- the current mix of stores in the plan
- which items are still unassigned

## Grocery List: Export Behavior

Exports should operate on store buckets, not just the full raw list.

Desired behavior:

- if the user selected several items for Store A, exporting Store A should only export those items
- if the user selected a different set for Store B, exporting Store B should export only those items
- the app should still allow exporting or sharing the full generic grocery checklist too

The user should feel like:

- "I have already organized this trip"
- "the app remembers my store choices"
- "I can send each store exactly what belongs there"

## Grocery List: Background Intelligence

The grocery list should feel smart because some work happens quietly in the background.

From the user's perspective, this means:

- vendor matches appear without blocking the whole screen
- prices can refresh quietly
- the app can remember previous matches
- users do not start from zero every time they open the grocery list

The UI should communicate this gently.

Good examples:

- show that prices were refreshed recently
- show whether information is fresh enough to trust
- avoid forcing the user to manually redo vendor lookups each session

The app should feel like it is helping continuously, not waiting for the user to push every step manually.

## Grocery List: Freshness and Trust

Because prices change, the UI should communicate freshness in a compact way.

The user should be able to understand:

- whether prices are recent
- whether a vendor match is still reliable
- whether an item needs a refresh or still looks good

This should be subtle, not alarming.

The goal is trust, not noise.

## Grocery List: Good UX Qualities

The grocery page should feel:

- compact
- smart
- persistent
- calm
- useful even before every item has a perfect vendor match

It should not feel:

- crowded
- over-engineered
- dependent on constant user micromanagement
- reset-heavy

## What Should Not Happen

The redesign should avoid:

- changing existing working AI lookup behavior unnecessarily
- changing existing working DB search behavior unnecessarily
- introducing a totally different visual style for new screens
- making users choose too many modes before they even start
- making grocery price compare look like a spreadsheet
- forcing vendor lookup to happen only in the foreground
- making store export feel brittle or one-shot

## Grocery List: Confirmed Design Decisions

### Stores
- V1 targets three stores: Whole Foods, Sprouts, Trader Joe's
- Store lineup should be extensible for adding more later

### Price Data Source
- Real prices only — no AI-generated price estimates
- Web search via self-hosted SearXNG server
- Search strategy TBD (store-scoped web search vs site-specific vs hybrid)
- SearXNG base URL to be configured later

### Price Lookup Behavior
- Lazy + cached: prices load automatically when grocery view appears
- Only fetch for items without fresh cached prices (e.g., <24h old)
- Async requests — prices trickle in as results arrive
- Manual refresh button available for forcing new lookups
- Persistent vendor match cache with freshness metadata

### Store Assignment
- Inline price chips per item row (e.g., `WF $4.99` `SP $3.79` `TJ $3.49`)
- Tapping a store price assigns that item to that store's bucket
- Selected chip gets highlight treatment
- Assignments persist across app restarts

### Export
- No export functionality — the list lives in the app only
- No deep linking to store apps
- No Apple Reminders integration

### What Still Needs Design
- Exact SearXNG search query strategy (pending server URL)
- Price chip visual treatment and loading states
- Freshness indicators for cached prices
- Cart row layout with price chips integrated
- Interaction between AI suggestions and price lookup

## Desired Final Feeling

When the user uses the new app flow, it should feel like:

- `Log` is simple and obvious
- `Scan` is elegant and smart
- `Search` is fast and forgiving
- `Ask AI` is natural to start with voice
- grocery is compact, intelligent, and increasingly personalized over time

The biggest success condition is not just that features exist.

It is that the app feels pleasant, reduces friction, and quietly remembers helpful context so the user can move faster with less effort.
