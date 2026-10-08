# HomerContinuations

The Continuations page.

## Design notes

- **Continuations** (`HomerContinuationsReducer`, from `continuations/page.tsx`): the pending continuations, plus the ones that failed to fire (shown only when there are any — agents report crashes through continuations, so a lost one is a report nobody gets). Both lists come from one cancellable loop every 30 s, the console's cadence. Cancel is offered for PENDING only and is not checked against the user's grants: the console doesn't, and the API's continuation has no `owner` to check (the server applies `canControl`). A cancel always refetches, as the console does on settle; a 409 or 404 reads as "can no longer be cancelled", since the list was stale. A card's run numbers are links in one `AttributedString`, so the sentence wraps as text; they use a private `homer-process:<id>` scheme that the card's `openURL` action turns into `processTapped`
