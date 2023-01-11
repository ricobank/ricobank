// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { Ball, GemFabLike } from '../src/ball.sol';
import { Gem, GemFab } from '../lib/gemfab/src/gem.sol';
import { Feedbase } from '../lib/feedbase/src/Feedbase.sol';
import { BalSetUp } from "./RicoHelper.sol";

contract BallTest is Test, BalSetUp {
    function setUp() public {}

    function test_ball() public {
        address aweth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        GemFabLike gf = GemFabLike(address(new GemFab()));
        Feedbase fb = new Feedbase();
        Ball ball = new Ball(
            gf, address(fb), aweth, address(this),
            BAL_W_P_F, BAL_VAULT
        );
        require(address(0) != address(ball));
    }
}
