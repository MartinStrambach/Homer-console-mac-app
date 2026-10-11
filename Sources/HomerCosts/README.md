# HomerCosts

The Costs page (admins only).

## Design notes

- **Costs** (`HomerCostsReducer`, admins only) runs three loops, so a month change restarts only one: the rolling-window snapshot every 5 s (`useCosts`' `refetchInterval`), and the month's and all-time ledgers every 30 s — the console only marks those stale after 30 s and re-reads them on mount or window focus, which a page left open never gets. `monthlyLoaded` carries the month it asked for and is dropped once another is picked. With no month picked the request has no `month` and the server answers with the current UTC month, so the page moves to the next month by itself, with no date logic in the app. While a picked month loads, the previous one stays on screen dimmed (the console's `keepPreviousData`). Usage bars follow `CostUsageBar`: green, yellow from 80 % of the cap, red at it; percentages round half up like `toFixed(0)`. The per-agent table lists agents that have spent or have a cap, so a capped agent with no spend shows at $0
- **The page's layout.** Stat tiles head it: the last minute against its cap, the last day (the per-agent spends summed), the month shown and all time. The per-agent table lists the agents nearest their cap first, then the uncapped ones by spend (`byNearestCap`) — the console sorts by name; what needs a look comes first. The global bar ticks 80 %, where it turns yellow. The month's and all-time ledgers list the biggest spender first, each row with its share of the total as a bar, and sit side by side from 900 pt of content width
