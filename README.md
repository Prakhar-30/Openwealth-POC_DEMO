# Openwealth × Reactive Network — Demo POC

A minimal, end-to-end demo of the Openwealth deposit → mint pipeline wired through the [Reactive Network](https://reactive.network/). One reactive smart contract on Lasna bridges two EVM chains and a small off-chain verifier stands in for Openwealth's order-management backend.

> **Demo build — not production.** All access control is intentionally removed to keep the surface small. The live flows executed against Sepolia, Base Sepolia, and Reactive Lasna Testnet are documented in [`report.md`](./report.md).

---

## Flow at a glance

```
  ┌────────────┐     USDC Transfer      ┌─────────────────────┐
  │ Investor   │ ─────────────────────► │ Deposit wallet (EOA)│   (Sepolia)
  └────────────┘                        └──────────┬──────────┘
                                                   │
                                   Transfer event  ▼
                                        ┌───────────────────────┐
                                        │  OpenwealthRSC  (RSC) │   (Lasna)
                                        └──────────┬────────────┘
                                                   │ callback
                                                   ▼
                                        ┌───────────────────────┐
                                        │  VerificationRelay    │   (Sepolia)
                                        │   emits DepositObserved│
                                        └──────────┬────────────┘
                                                   │
                      (off-chain verifier polls, decides approve / reject)
                                                   │
                          ┌────────────────────────┴─────────────────────────┐
                          │ approve: confirmOrder                            │
                          │     → OrderVerified → RSC → mint on Base Sepolia │
                          │     → Minted        → RSC → notifyMinted         │
                          │     → MintReconciled on relay                    │
                          │ reject:  rejectDeposit → OrderRejected (flow end)│
                          └──────────────────────────────────────────────────┘
```

One RSC, three subscriptions, three callbacks. No on-chain order data, no cross-chain relayer to operate.

---

## Repository layout

```
src/
  OpenwealthRSC.sol        Reactive Smart Contract (Lasna)
  VerificationRelay.sol    Callback contract for deposit + reconciliation (Sepolia)
  OpenwealthToken.sol      Demo ERC-20 minter (Base Sepolia)
script/
  verifier.js              Off-chain verifier simulating Openwealth's backend
deployments.json           Addresses, chain IDs, deploy tx hashes
report.md                  Live test run — both approval and rejection cycles
foundry.toml               Foundry config + RPC aliases
```

---

## Contracts

| Contract | Chain | Purpose |
|---|---|---|
| `OpenwealthRSC` | Reactive Lasna (5318007) | Subscribes to USDC `Transfer` (to = deposit wallet), relay `OrderVerified`, and token `Minted`. Dispatches the three callbacks that drive the flow. |
| `VerificationRelay` | Sepolia (11155111) | Thin event bridge. Emits `DepositObserved` / `OrderVerified` / `OrderRejected` / `MintReconciled`. No state, no access control. |
| `OpenwealthToken` | Base Sepolia (84532) | Minimal ERC-20-ish token with a public `mint(address,address,uint256)` callback entry point. |

Event signatures used for subscriptions:

- `Transfer(address,address,uint256)` on USDC — filtered by `topic_2 = depositWallet`
- `OrderVerified(address,uint256)` on the relay
- `Minted(address,uint256)` on the token

---

## Prerequisites

- [Foundry](https://book.getfoundry.sh/) (`forge`, `cast`) — 1.5 or newer
- Node.js 18+ for `script/verifier.js`
- Funded EOA on Sepolia, Base Sepolia, and Reactive Lasna (the same EOA is the RSC owner / RVM ID)
- Some test USDC on Sepolia (uses `0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8`)

---

## Build

```shell
forge build
```

## Deploy

Order: callback contracts first, RSC last (so it knows both addresses).

```shell
# 1. Token on Base Sepolia
forge create src/OpenwealthToken.sol:OpenwealthToken \
  --broadcast \
  --rpc-url $BASE_SEPOLIA_RPC \
  --private-key $PRIVATE_KEY \
  --value 0.02ether \
  --constructor-args 0xa6eA49Ed671B8a4dfCDd34E36b7a75Ac79B8A5a6   # Base Sepolia callback proxy

# 2. Relay on Sepolia
forge create src/VerificationRelay.sol:VerificationRelay \
  --broadcast \
  --rpc-url $SEPOLIA_RPC \
  --private-key $PRIVATE_KEY \
  --value 0.02ether \
  --constructor-args 0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA   # Sepolia callback proxy

# 3. RSC on Lasna (fund with enough lREACT for callback delivery)
forge create src/OpenwealthRSC.sol:OpenwealthRSC \
  --broadcast \
  --rpc-url https://lasna-rpc.rnk.dev/ \
  --private-key $PRIVATE_KEY \
  --value 5ether \
  --constructor-args \
    0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8 \  # USDC on Sepolia
    0xcD46C4C833725bC46b8aA4136BCdd35b615b5BC5 \  # deposit wallet
    <RELAY_ADDR> \
    <TOKEN_ADDR>
```

The RSC's constructor registers all three subscriptions in a single deploy tx. Verify the RSC is active on [Reactscan](https://lasna.reactscan.net/).

---

## Running the demo

### 1. Run the off-chain verifier

```shell
# Approve every deposit it sees
SEPOLIA_RPC=$SEPOLIA_RPC \
PRIVATE_KEY=$PRIVATE_KEY \
RELAY_ADDRESS=<RELAY_ADDR> \
MODE=approve \
CLIENT_WALLET=0xYourBaseSepoliaWallet \
ONE_SHOT=1 \
node script/verifier.js
```

Swap `MODE=reject` (with optional `REASON=...`) to simulate the rejection branch.

`ONE_SHOT=1` makes the verifier exit after handling the first `DepositObserved`. Drop it to leave the verifier running.

### 2. Trigger a deposit

```shell
cast send 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8 \
  "transfer(address,uint256)" 0xcD46C4C833725bC46b8aA4136BCdd35b615b5BC5 1000000 \
  --rpc-url $SEPOLIA_RPC --private-key $PRIVATE_KEY
```

### 3. Watch

- Relay events on Sepolia: `cast logs --address <RELAY_ADDR> --rpc-url $SEPOLIA_RPC`
- Mint + `Minted` on Base Sepolia: `cast logs --address <TOKEN_ADDR> --rpc-url $BASE_SEPOLIA_RPC`
- RVM reacts on Lasna: the RSC's [Reactscan dashboard](https://lasna.reactscan.net/)

Happy path takes ≈ 70 s end-to-end; rejection path ≈ 35 s.

---

## Live test run

See [`report.md`](./report.md) for a full transcript of both cycles with every transaction hash and Reactscan RVM-tx link.

---

## Notes on the demo vs. the full POC

This repo intentionally strips the design in the main POC doc down to the smallest thing that proves the loop works:

- **No `depositId` correlation layer** — the relay just passes `(from, amount, ethTxHash)` straight through.
- **No access control** — `VerificationRelay`, `OpenwealthToken`, and the RSC's callback sinks are wide open so anyone can drive the demo.
- **No retries / failure bookkeeping** — mint failures, backend timeouts, and duplicates are out of scope.
- **`VerificationRelay` lives on Sepolia** — same chain as the deposit, keeps the verifier's RPC config simple. Nothing in the RSC prevents moving it to Base Sepolia.

These are the knobs to tighten before production; the architecture and event shapes stay the same.
