// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import "reactive-lib/src/abstract-base/AbstractCallback.sol";

/// @title OpenwealthToken — Minter CC on Base Sepolia (demo)
/// @notice Minimal ERC20-like token minted via RSC callback. No access control in the demo.
contract OpenwealthToken is AbstractCallback {

    string public constant name = "Openwealth Demo Token";
    string public constant symbol = "OWD";
    uint8  public constant decimals = 6;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Minted(address indexed to, uint256 amount);

    constructor(address _callbackSender) payable AbstractCallback(_callbackSender) {}

    /// @notice Called by the RSC (via Base Sepolia callback proxy) to mint tokens to the client.
    function mint(address /* rvm_sender */, address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
        emit Minted(to, amount);
    }
}
