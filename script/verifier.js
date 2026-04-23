#!/usr/bin/env node
/*
 * Openwealth demo — offchain verifier.
 *
 * Watches `DepositObserved(address,uint256,bytes32)` on VerificationRelay (Sepolia).
 * On match, either calls `confirmOrder(clientWallet, amount)` (APPROVE mode)
 * or `rejectDeposit(from, reason)` (REJECT mode). Mode is chosen per-run via env.
 *
 * Usage:
 *   MODE=approve  CLIENT_WALLET=0x... node script/verifier.js
 *   MODE=reject   REASON="UNKNOWN_SENDER" node script/verifier.js
 *
 * Required env:
 *   SEPOLIA_RPC, PRIVATE_KEY, RELAY_ADDRESS
 *   MODE = "approve" | "reject"
 *   CLIENT_WALLET (for approve)
 *   REASON        (for reject, optional; defaults to "REJECTED_BY_VERIFIER")
 *   FROM_BLOCK    (optional; default = "latest" - 1)
 *   POLL_MS       (optional; default = 4000)
 *   ONE_SHOT      (optional; if "1" exits after first handled deposit)
 */

const { ethers } = require("ethers");

const RELAY_ABI = [
  "event DepositObserved(address from, uint256 amount, bytes32 ethTxHash)",
  "event OrderVerified(address clientWallet, uint256 amount)",
  "event OrderRejected(address from, string reason)",
  "function confirmOrder(address clientWallet, uint256 amount) external",
  "function rejectDeposit(address from, string reason) external",
];

function required(name) {
  const v = process.env[name];
  if (!v) throw new Error(`Missing env ${name}`);
  return v;
}

async function main() {
  const rpc = required("SEPOLIA_RPC");
  const pk = required("PRIVATE_KEY");
  const relayAddr = required("RELAY_ADDRESS");
  const mode = (process.env.MODE || "approve").toLowerCase();
  const pollMs = Number(process.env.POLL_MS || 4000);
  const oneShot = process.env.ONE_SHOT === "1";

  const provider = new ethers.JsonRpcProvider(rpc);
  const wallet = new ethers.Wallet(pk, provider);
  const relay = new ethers.Contract(relayAddr, RELAY_ABI, wallet);

  const latest = await provider.getBlockNumber();
  let fromBlock = process.env.FROM_BLOCK
    ? Number(process.env.FROM_BLOCK)
    : Math.max(0, latest - 1);

  console.log(`[verifier] mode=${mode}  relay=${relayAddr}  startBlock=${fromBlock}`);
  console.log(`[verifier] signer=${wallet.address}`);

  const topic = relay.interface.getEvent("DepositObserved").topicHash;
  const seen = new Set();

  async function handleLog(log) {
    const key = `${log.transactionHash}:${log.index}`;
    if (seen.has(key)) return;
    seen.add(key);

    const parsed = relay.interface.parseLog(log);
    const { from, amount, ethTxHash } = parsed.args;
    console.log(
      `[verifier] DepositObserved: from=${from} amount=${amount.toString()} ethTxHash=${ethTxHash}`
    );
    console.log(`           sepolia tx: ${log.transactionHash}  block=${log.blockNumber}`);

    let tx;
    if (mode === "approve") {
      const clientWallet = required("CLIENT_WALLET");
      console.log(`[verifier] APPROVING → confirmOrder(${clientWallet}, ${amount.toString()})`);
      tx = await relay.confirmOrder(clientWallet, amount);
    } else if (mode === "reject") {
      const reason = process.env.REASON || "REJECTED_BY_VERIFIER";
      console.log(`[verifier] REJECTING → rejectDeposit(${from}, "${reason}")`);
      tx = await relay.rejectDeposit(from, reason);
    } else {
      throw new Error(`unknown MODE=${mode}`);
    }
    console.log(`[verifier] sent ${tx.hash}`);
    const rcpt = await tx.wait();
    console.log(`[verifier] mined block=${rcpt.blockNumber}`);

    if (oneShot) {
      console.log("[verifier] ONE_SHOT — exiting.");
      process.exit(0);
    }
  }

  while (true) {
    try {
      const head = await provider.getBlockNumber();
      if (head >= fromBlock) {
        const logs = await provider.getLogs({
          address: relayAddr,
          topics: [topic],
          fromBlock,
          toBlock: head,
        });
        for (const log of logs) await handleLog(log);
        fromBlock = head + 1;
      }
    } catch (e) {
      console.error(`[verifier] poll error: ${e.message}`);
    }
    await new Promise((r) => setTimeout(r, pollMs));
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
