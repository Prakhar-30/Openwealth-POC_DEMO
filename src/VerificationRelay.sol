// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import "reactive-lib/src/abstract-base/AbstractCallback.sol";

/// @title VerificationRelay — Openwealth demo
/// @notice Thin bridge between Reactive Smart Contract and Openwealth's backend.
///         Deployed on Sepolia. No access control in this demo build.
contract VerificationRelay is AbstractCallback {

    event DepositObserved(address from, uint256 amount, bytes32 ethTxHash);
    event OrderVerified(address clientWallet, uint256 amount);
    event OrderRejected(address from, string reason);
    event MintReconciled(address clientWallet, uint256 amount);

    constructor(address _callbackSender) payable AbstractCallback(_callbackSender) {}

    /// @notice Called by the RSC (via Sepolia callback proxy) when USDC Transfer hits the deposit wallet.
    function notifyDeposit(
        address /* rvm_sender */,
        address from,
        uint256 amount,
        bytes32 ethTxHash
    ) external {
        emit DepositObserved(from, amount, ethTxHash);
    }

    /// @notice Called by Openwealth's offchain verifier after DB match + compliance approval.
    function confirmOrder(address clientWallet, uint256 amount) external {
        emit OrderVerified(clientWallet, amount);
    }

    /// @notice Called by Openwealth's offchain verifier when match/compliance fails.
    function rejectDeposit(address from, string calldata reason) external {
        emit OrderRejected(from, reason);
    }

    /// @notice Called by the RSC after mint succeeds on destination chain.
    function notifyMinted(
        address /* rvm_sender */,
        address clientWallet,
        uint256 amount
    ) external {
        emit MintReconciled(clientWallet, amount);
    }
}
