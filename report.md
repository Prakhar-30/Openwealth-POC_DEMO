# Openwealth × Reactive Network — Demo POC Run Report

This report documents a full live test of the Openwealth reactive pipeline on testnet, covering:

1. **Happy path** — USDC deposit → offchain verifier approves → token mint on destination chain → reconciliation back to the relay.
2. **Rejection path** — USDC deposit → offchain verifier rejects → no mint, only a reconciliation-failure event.

Every step below includes the on-chain transaction or block link so the flow can be independently verified.

---

## 1. Networks and contracts

| Role | Chain | Chain ID | Address |
|---|---|---|---|
| USDC (origin token) | Sepolia | 11155111 | [`0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8`](https://sepolia.etherscan.io/address/0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8) |
| Deposit wallet (EOA) | Sepolia | 11155111 | [`0xcD46C4C833725bC46b8aA4136BCdd35b615b5BC5`](https://sepolia.etherscan.io/address/0xcD46C4C833725bC46b8aA4136BCdd35b615b5BC5) |
| `VerificationRelay` | Sepolia | 11155111 | [`0x77B770620231839B6309e09ceD726456A96b07A7`](https://sepolia.etherscan.io/address/0x77B770620231839B6309e09ceD726456A96b07A7) |
| `OpenwealthToken` (Minter CC) | Base Sepolia | 84532 | [`0xE44D3F0ED40C04AaD3858eC34870B02b496c6Aaf`](https://sepolia.basescan.org/address/0xE44D3F0ED40C04AaD3858eC34870B02b496c6Aaf) |
| `OpenwealthRSC` (Reactive) | Reactive Lasna | 5318007 | [`0xd29025E3D14bef990e82d5385b27A97f0b97bf4b`](https://lasna.reactscan.net/address/0x49abe186a9b24f73e34ccae3d179299440c352ac/25139) |

Deployer / RVM ID: `0x49aBE186a9B24F73E34cCAe3D179299440c352aC`

Reactive contract dashboard (all RVM transactions for this RSC): [lasna.reactscan.net/…/contract/0xd29025…bf4b?screen=transactions](https://lasna.reactscan.net/address/0x49abe186a9b24f73e34ccae3d179299440c352ac/contract/0xd29025e3d14bef990e82d5385b27a97f0b97bf4b?screen=transactions)

### Deployment transactions

| Contract | Chain | Deploy tx |
|---|---|---|
| `OpenwealthToken` | Base Sepolia | [`0x7331e29d47a65ec9d9de9dd352f0410a564d0053da0a1e3a53ee37f114cf775e`](https://sepolia.basescan.org/tx/0x7331e29d47a65ec9d9de9dd352f0410a564d0053da0a1e3a53ee37f114cf775e) |
| `VerificationRelay` | Sepolia | [`0xb92b77f5d5feee68df190c06cd01e09985c09f210d3b39f55f42b806372933e1`](https://sepolia.etherscan.io/tx/0xb92b77f5d5feee68df190c06cd01e09985c09f210d3b39f55f42b806372933e1) |
| `OpenwealthRSC` | Lasna | [RVM tx #25139](https://lasna.reactscan.net/address/0x49abe186a9b24f73e34ccae3d179299440c352ac/25139) |

The RSC was deployed with `--value 5 ether` to prefund callback delivery. Its constructor issued three `service.subscribe` calls:

1. USDC `Transfer` on Sepolia, topic_2 filtered to the deposit wallet.
2. `OrderVerified` on the VerificationRelay (Sepolia).
3. `Minted` on `OpenwealthToken` (Base Sepolia).

---

## 2. Happy path — approved deposit

Client wallet (mint recipient on Base Sepolia): `0x49aBE186a9B24F73E34cCAe3D179299440c352aC`
Deposit amount: `1.000000 USDC` (1 000 000 with 6 decimals).

### Step 1 — Client deposit (Sepolia)

`transfer(depositWallet, 1_000_000)` on USDC.

- Sepolia block **10 717 816**
- Tx: [`0xbec5a2d902f2699c0095482fb8fe7516baac666fb691f80d816c38790794f94f`](https://sepolia.etherscan.io/tx/0xbec5a2d902f2699c0095482fb8fe7516baac666fb691f80d816c38790794f94f)

### Step 2 — RSC detects the deposit (Lasna)

The reactive contract's `react()` matched the Transfer (to = deposit wallet) and emitted `Callback` targeting `VerificationRelay.notifyDeposit(...)` on Sepolia.

- RVM tx **#25142** — [Reactscan RVM view](https://lasna.reactscan.net/address/0x49abe186a9b24f73e34ccae3d179299440c352ac/25142)

### Step 3 — `notifyDeposit` callback lands on Sepolia → `DepositObserved`

- Sepolia block **10 717 818**
- Tx: [`0xcfbdfb9255c59f00435672de3518cd4af6e81c1b2b2fec483e07645a2e5ad368`](https://sepolia.etherscan.io/tx/0xcfbdfb9255c59f00435672de3518cd4af6e81c1b2b2fec483e07645a2e5ad368)
- `from = 0x49aBE1…352aC`, `amount = 1 000 000`, `ethTxHash = 0xbec5a2…4f94f`

### Step 4 — Offchain verifier approves → `confirmOrder`

The offchain verifier (`script/verifier.js`, mode `approve`) picked up the `DepositObserved` log, matched it against its "DB" (simulated), and called `confirmOrder(clientWallet, amount)`.

- Sepolia block **10 717 819**
- Tx: [`0xa9ef6c96516dbca87a72616b9cd96c89abe3fb9005abcfa1f280c0de376f59cb`](https://sepolia.etherscan.io/tx/0xa9ef6c96516dbca87a72616b9cd96c89abe3fb9005abcfa1f280c0de376f59cb)
- Emits `OrderVerified(clientWallet=0x49aBE1…352aC, amount=1 000 000)`

### Step 5 — RSC detects `OrderVerified` (Lasna)

The RSC matched the `OrderVerified` event on the relay and emitted a `Callback` targeting `OpenwealthToken.mint(...)` on Base Sepolia.

- RVM tx **#25143** — [Reactscan RVM view](https://lasna.reactscan.net/address/0x49abe186a9b24f73e34ccae3d179299440c352ac/25143)

### Step 6 — `mint` callback lands on Base Sepolia → `Minted`

- Base Sepolia block **40 598 874**
- Tx: [`0x683e3f122bd537e3774fa2c8639220327c5b8f8df7b5c68c05d700dc3f2d850b`](https://sepolia.basescan.org/tx/0x683e3f122bd537e3774fa2c8639220327c5b8f8df7b5c68c05d700dc3f2d850b)
- Emits `Transfer(0x0, clientWallet, 1 000 000)` + `Minted(clientWallet, 1 000 000)`

Post-mint state on Base Sepolia:

- `OpenwealthToken.totalSupply() = 1 000 000`
- `balanceOf(0x49aBE1…352aC) = 1 000 000`

### Step 7 — RSC detects `Minted` (Lasna)

The RSC matched the `Minted` event on the token and emitted a `Callback` targeting `VerificationRelay.notifyMinted(...)` on Sepolia.

- RVM tx **#25144** — [Reactscan RVM view](https://lasna.reactscan.net/address/0x49abe186a9b24f73e34ccae3d179299440c352ac/25144)

### Step 8 — `notifyMinted` callback lands on Sepolia → `MintReconciled`

Reconciliation event for Openwealth's accounting. Flow ends here.

- Sepolia block **10 717 822**
- Tx: [`0x0cbd5c0e34a8f81a0008f4b4ead301b16885d144a0faeda7c293e11971a17a6e`](https://sepolia.etherscan.io/tx/0x0cbd5c0e34a8f81a0008f4b4ead301b16885d144a0faeda7c293e11971a17a6e)
- Emits `MintReconciled(clientWallet=0x49aBE1…352aC, amount=1 000 000)`

### Happy-path summary

```
Sepolia 10 717 816   deposit (USDC transfer)
        │
        ▼
Lasna   RVM #25142   RSC.react → Callback(notifyDeposit)
        │
        ▼
Sepolia 10 717 818   DepositObserved                        ← from RN callback proxy
        │
        ▼  (offchain verifier matches, approves)
Sepolia 10 717 819   OrderVerified                          ← confirmOrder
        │
        ▼
Lasna   RVM #25143   RSC.react → Callback(mint)
        │
        ▼
Base S. 40 598 874   Transfer(0x0→client) + Minted          ← from RN callback proxy
        │
        ▼
Lasna   RVM #25144   RSC.react → Callback(notifyMinted)
        │
        ▼
Sepolia 10 717 822   MintReconciled                         ← from RN callback proxy
```

Total wall-clock time from deposit to reconciliation: **≈ 72 seconds**.

---

## 3. Rejection path — rejected deposit

Deposit amount: `0.500000 USDC`.

### Step 1 — Client deposit (Sepolia)

`transfer(depositWallet, 500_000)` on USDC.

- Sepolia block **10 717 857**
- Tx: [`0xecdb6ff358cc9541e8eae76e624e8e8eb24c3f987d50ab565b611bec28cd4faa`](https://sepolia.etherscan.io/tx/0xecdb6ff358cc9541e8eae76e624e8e8eb24c3f987d50ab565b611bec28cd4faa)

### Step 2 — RSC detects the deposit (Lasna)

- RVM tx **#25147** — [Reactscan RVM view](https://lasna.reactscan.net/address/0x49abe186a9b24f73e34ccae3d179299440c352ac/25147)

### Step 3 — `notifyDeposit` callback lands on Sepolia → `DepositObserved`

- Sepolia block **10 717 858**
- Tx: [`0x860d12a890602ecbfeaee2c4c05497842ddaab3a68ad3510845c05472dff71ef`](https://sepolia.etherscan.io/tx/0x860d12a890602ecbfeaee2c4c05497842ddaab3a68ad3510845c05472dff71ef)

### Step 4 — Offchain verifier rejects → `rejectDeposit`

The offchain verifier (`script/verifier.js`, mode `reject`, reason `UNKNOWN_SENDER`) picked up the `DepositObserved` log and called `rejectDeposit(from, reason)`.

- Sepolia block **10 717 859**
- Tx: [`0xb3ad9d3e3c8aafae2eaecefa208829e7beadf883f28d259c52d796f230c3eb77`](https://sepolia.etherscan.io/tx/0xb3ad9d3e3c8aafae2eaecefa208829e7beadf883f28d259c52d796f230c3eb77)
- Emits `OrderRejected(from=0x49aBE1…352aC, reason="UNKNOWN_SENDER")`

### Step 5 — Flow ends

The RSC does **not** subscribe to `OrderRejected`, so no further callback is issued. Base Sepolia token state is unchanged:

- `totalSupply()` stays at `1 000 000` (carried over from the happy path)
- `balanceOf(clientWallet)` stays at `1 000 000`

No mint tx on Base Sepolia in the rejection window.

### Rejection-path summary

```
Sepolia 10 717 857   deposit (USDC transfer)
        │
        ▼
Lasna   RVM #25147   RSC.react → Callback(notifyDeposit)
        │
        ▼
Sepolia 10 717 858   DepositObserved                        ← from RN callback proxy
        │
        ▼  (offchain verifier rejects)
Sepolia 10 717 859   OrderRejected("UNKNOWN_SENDER")        ← rejectDeposit
        │
        ▼
      (flow terminates — no RSC subscription on OrderRejected, no mint)
```

In a production flow Openwealth would manually refund the deposit wallet upon seeing `OrderRejected`.

---

## 4. Verification checklist

| Check | Result |
|---|---|
| USDC `Transfer` → RSC subscription fires exactly once per deposit | ✓ both runs |
| `DepositObserved` carries correct `from`, `amount`, `ethTxHash` | ✓ |
| `OrderVerified` → RSC subscription fires only on approval | ✓ |
| `mint` is executed on Base Sepolia only for approved deposit | ✓ (only 1 mint, not 2) |
| `Minted` → RSC subscription fires and closes the loop | ✓ |
| `MintReconciled` emitted with matching `clientWallet` and `amount` | ✓ |
| Rejected deposit does **not** trigger any mint | ✓ (balance unchanged) |
| End-to-end latency per approved cycle | ≈ 72 s |
| End-to-end latency per rejected cycle | ≈ 36 s |
