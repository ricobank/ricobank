// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.9;

interface GemLike {
    function transfer(address dst, uint256 wad) external;
    function mint(address dst, uint256 wad) external;
}

interface BPoolLike {
    function swap_exactAmountIn(address intok, uint amt, address outtok) external;
}

contract PoolFlapper {
    BPoolLike pool;
    address RICO;
    address RISK;
    function flap(uint wad) external {
    }
}
