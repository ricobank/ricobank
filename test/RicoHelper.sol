// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.15;

import { Feedbase } from '../lib/feedbase/src/Feedbase.sol';
import { GemFab } from '../lib/gemfab/src/gem.sol';
import { GemFabLike } from '../src/ball.sol';
import { Ball } from '../src/ball.sol';
import { GemLike } from '../src/abi.sol';

interface WethLike is GemLike {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

abstract contract RicoSetUp {
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function make_bank() public returns(Ball) {
        Feedbase feedbase = new Feedbase();
        GemFab gemfab = new GemFab();
        Ball ball = new Ball(GemFabLike(address(gemfab)), address(feedbase));
        return ball;
    }
}
