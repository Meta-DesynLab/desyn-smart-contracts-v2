// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.12;

import "./TToken.sol";

contract TTokenFactory {
    mapping(string=>TToken) tokens;
    function get(string calldata name) external view returns (TToken) {
        return tokens[name];
    }
    function build(string calldata name, string calldata symbol, uint8 decimals) external returns (TToken) {
        tokens[name] = new TToken(name, symbol, decimals);
        return tokens[name];
    }
}
