// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import "reactive-lib/src/interfaces/IReactive.sol";
import "reactive-lib/src/abstract-base/AbstractPausableReactive.sol";

/// @title OpenwealthRSC — Reactive Smart Contract on Lasna for the Openwealth demo.
/// @notice Bridges Sepolia USDC deposits and Base Sepolia token mints via the VerificationRelay on Sepolia.
contract OpenwealthRSC is IReactive, AbstractPausableReactive {

    uint256 private constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 private constant BASE_SEPOLIA_CHAIN_ID = 84532;

    // keccak256("Transfer(address,address,uint256)")
    uint256 private constant TRANSFER_TOPIC_0 =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;
    // keccak256("OrderVerified(address,uint256)")
    uint256 private constant ORDER_VERIFIED_TOPIC_0 =
        0x513ba840b32abce7d9cd387c1f2025f089356b30b9d11e0b015aafab9c664a1e;
    // keccak256("Minted(address,uint256)")
    uint256 private constant MINTED_TOPIC_0 =
        0x30385c845b448a36257a6a1716e6ad2e1bc2cbe333cde1e69fe849ad6511adfe;

    uint64 private constant CALLBACK_GAS_LIMIT = 1_000_000;

    address public immutable usdc;              // USDC on Sepolia
    address public immutable depositWallet;     // Openwealth deposit EOA on Sepolia
    address public immutable verificationRelay; // Sepolia
    address public immutable openwealthToken;   // Base Sepolia

    constructor(
        address _usdc,
        address _depositWallet,
        address _verificationRelay,
        address _openwealthToken
    ) payable {
        owner = msg.sender;
        usdc = _usdc;
        depositWallet = _depositWallet;
        verificationRelay = _verificationRelay;
        openwealthToken = _openwealthToken;

        if (!vm) {
            // 1. USDC Transfer on Sepolia, filtered on "to = depositWallet" (topic_2).
            service.subscribe(
                SEPOLIA_CHAIN_ID,
                _usdc,
                TRANSFER_TOPIC_0,
                REACTIVE_IGNORE,
                uint256(uint160(_depositWallet)),
                REACTIVE_IGNORE
            );
            // 2. OrderVerified on VerificationRelay (Sepolia).
            service.subscribe(
                SEPOLIA_CHAIN_ID,
                _verificationRelay,
                ORDER_VERIFIED_TOPIC_0,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
            // 3. Minted on OpenwealthToken (Base Sepolia).
            service.subscribe(
                BASE_SEPOLIA_CHAIN_ID,
                _openwealthToken,
                MINTED_TOPIC_0,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
        }
    }

    function react(LogRecord calldata log) external vmOnly {
        // Leg 1: USDC Transfer (to = depositWallet) → notifyDeposit
        if (log.topic_0 == TRANSFER_TOPIC_0 && log._contract == usdc) {
            address from = address(uint160(log.topic_1));
            uint256 amount = abi.decode(log.data, (uint256));
            emit Callback(
                SEPOLIA_CHAIN_ID,
                verificationRelay,
                CALLBACK_GAS_LIMIT,
                abi.encodeWithSignature(
                    "notifyDeposit(address,address,uint256,bytes32)",
                    address(0),
                    from,
                    amount,
                    bytes32(log.tx_hash)
                )
            );
            return;
        }
        // Leg 2: OrderVerified on relay → mint on Base Sepolia
        if (log.topic_0 == ORDER_VERIFIED_TOPIC_0 && log._contract == verificationRelay) {
            (address clientWallet, uint256 amount) = abi.decode(log.data, (address, uint256));
            emit Callback(
                BASE_SEPOLIA_CHAIN_ID,
                openwealthToken,
                CALLBACK_GAS_LIMIT,
                abi.encodeWithSignature(
                    "mint(address,address,uint256)",
                    address(0),
                    clientWallet,
                    amount
                )
            );
            return;
        }
        // Leg 3: Minted on token → notifyMinted on relay
        if (log.topic_0 == MINTED_TOPIC_0 && log._contract == openwealthToken) {
            address to = address(uint160(log.topic_1));
            uint256 amount = abi.decode(log.data, (uint256));
            emit Callback(
                SEPOLIA_CHAIN_ID,
                verificationRelay,
                CALLBACK_GAS_LIMIT,
                abi.encodeWithSignature(
                    "notifyMinted(address,address,uint256)",
                    address(0),
                    to,
                    amount
                )
            );
            return;
        }
    }

    function getPausableSubscriptions()
        internal
        view
        override
        returns (Subscription[] memory)
    {
        Subscription[] memory subs = new Subscription[](3);
        subs[0] = Subscription(
            SEPOLIA_CHAIN_ID,
            usdc,
            TRANSFER_TOPIC_0,
            REACTIVE_IGNORE,
            uint256(uint160(depositWallet)),
            REACTIVE_IGNORE
        );
        subs[1] = Subscription(
            SEPOLIA_CHAIN_ID,
            verificationRelay,
            ORDER_VERIFIED_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        subs[2] = Subscription(
            BASE_SEPOLIA_CHAIN_ID,
            openwealthToken,
            MINTED_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        return subs;
    }
}
