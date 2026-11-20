# NEAR Hackathon submission: draft

Deadline: 14 Nov 2026 23:59 UTC (Sat 15 Nov, 5:29 am IST). Submit once; fixes
go through the request-changes page afterwards.

Two independent entries. Each README names the other.

## Entry 1: Glyf × NEAR

| Field | Value |
|---|---|
| Project name | Glyf × NEAR: NEAR Intents in every chat |
| Team lead | Arpit Singh Bhatia |
| Email | arpitx35@gmail.com |
| Team size | Solo |
| Tracks | Unstoppable DeFi · Real-World Money · Privacy & Private AI · AI Security & Defense · Agent Economy · Social Money · Open Innovation |
| NEAR payout account | **owed by Arpit** |
| Repository | https://github.com/The-x-35/glyf/tree/near-hackathon (the NEAR work is the diff from tag `near-baseline`, linked in docs/NEAR.md) |
| Demo post | **owed by Arpit** (X post below) |

Description (at most 2,000 characters):

> Glyf is an AI keyboard for iPhone and Android. With NEAR Intents, money moves where people already talk: type "swap 20 usdc on base to sol" or "send 5 usdc to alice.near" in any chat, and the keyboard shows a live NEAR Intents quote (you pay, you get, about 30 seconds). Tap to deposit from MetaMask or Phantom. Glyf never holds a key.
>
> What we built for NEAR:
> - Swaps across 30+ chains typed in plain words: Solana ↔ EVM, and Bitcoin, Zcash, NEAR, TON, Tron and others as a destination.
> - Pay anyone exactly what they want, in their chain and coin (EXACT_OUTPUT): .near names, NEAR accounts, Bitcoin addresses. You pay from USDC on Base, or SOL.
> - Origins Glyf can't sign for (BTC, ZEC, …) get a deposit address, a QR code and live tracking.
> - Guard checks every send before it's signed:
>   - address poisoning (a lookalike of someone you paid before)
>   - a .near account that doesn't exist
>   - recipient format vs. destination chain
>   - new recipients and daily spend limits
> - Private AI on NEAR AI Cloud: one switch sends Glyf's writing and answers to NEAR AI's TEE models, with verifiable receipts.
> - The AI suggestion strip offers NEAR payments from the conversation ("pay Sam back $22.50"). Split-bill pay links let each friend pay from whatever chain they hold.
> - The pot: a Sputnik DAO is the group's shared pot. Friends pay into it from any chain, and "pay the caterer $120 from the pot" becomes a proposal the group votes on in Trezu.
> - Earn: "put $50 to work" moves idle USDC or SOL into a yield vault (Morpho, Kamino) through NEAR Intents, and "take it out" brings it back.
> - Three wallets side by side, picked by the chain you pay from: MetaMask (EVM), Phantom (Solana), HOT (NEAR).
>
> Hackathon work: branch near-hackathon, diff from tag near-baseline. Try it keyless: `cd server && npm i && npm run near:quote -- "swap 20 usdc on base to sol"`. Steps and tests in docs/NEAR.md.
>
> Also entered by the same author: the NEAR investment thesis (link).

## Entry 2: NEAR investment thesis

| Field | Value |
|---|---|
| Project name | (from the thesis repo) |
| Tracks | Investment Thesis |
| Repository | **to publish with Arpit's OK** |
| Demo post | **owed by Arpit** (dashboard screenshots) |

## X post, entry 1 (Arpit posts it with the demo video)

> Built at NEAR HACKATHON: Glyf × NEAR 🟢
>
> Your keyboard now speaks NEAR Intents. Type "swap 20 usdc on base to sol" or "send 5 usdc to alice.near" in any chat → live quote → sign in your own wallet → it lands in ~30s.
>
> Guard catches poisoned addresses, and AI runs privately on NEAR AI Cloud.
>
> @NEARProtocol #NEARHackathon
> github.com/The-x-35/glyf/tree/near-hackathon

## Demo video shot list (about 90 seconds, iPhone)

1. Messages, a chat with a friend: "dinner was $90 for the four of us" → "$22.50 each" chip → Request → the pay link is sent.
2. Type "swap 20 usdc on base to sol" → chip "Swap 20 USDC → SOL · Base → Solana · NEAR Intents" → panel with the live quote and ~32 s.
3. Tap → Glyf app → MetaMask signs the deposit → "Swapping on NEAR Intents" → "Swapped", with the explorer link.
4. Type "send 5 usdc to alice.near" → quote with the exact amount out.
5. Paste a poisoned lookalike address → Guard blocks it: "Looks like 0xAb12…9fE0 you paid before, but it isn't".
6. Profile › Keyboard › Private AI on NEAR → rewrite a message → the NEAR AI receipt.
