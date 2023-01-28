// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import { UniSetUp } from "../test/UniHelper.sol";

import { Ball, GemFabLike } from '../src/ball.sol';
import { INonfungiblePositionManager, IUniswapV3Pool } from '../src/TEMPinterface.sol';
import { Gem, GemFab } from '../lib/gemfab/src/gem.sol';
import { Feedbase } from '../lib/feedbase/src/Feedbase.sol';
import { BalSetUp } from "./RicoHelper.sol";
import { UniSwapper } from '../src/swap2.sol';

contract Swapper is UniSwapper {
    function swap(address tokIn, address tokOut, address receiver, uint8 kind, uint amt, uint limit)
            public returns (uint256 result) {
        result = _swap(tokIn, tokOut, receiver, SwapKind(kind), amt, limit);
    }

    function approveGem(address gem, address target) external {
        Gem(gem).approve(target, type(uint256).max);
    }
}


contract BallTest is Test, BalSetUp, UniSetUp {
    uint8   public immutable EXACT_IN  = 0;
    uint8   public immutable EXACT_OUT = 1;
    address internal constant BUSD = 0x4Fabb145d64652a948d72533023f6E7A623C7C53;
    address internal constant PSM  = 0xF977814e90dA44bFA03b6295A0616a897441aceC;
    uint256 internal constant WAD  = 10 ** 18;
    Swapper swap;
    address rico;

    function setUp() public {
    }

    function test_ball() public {
        address aweth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        GemFabLike gf = GemFabLike(address(new GemFab()));
        Feedbase fb = new Feedbase();

        Ball ball = new Ball(
            gf, address(fb), aweth, address(this),
            BAL_W_P_F, BAL_VAULT
        );

        swap = new Swapper();
        rico = ball.rico();
        swap.approveGem(BUSD, ROUTER);
        swap.approveGem(rico, ROUTER);
        swap.setSwapRouter(ROUTER);
        // Create a path to swap UNI for WETH in a single hop
        address [] memory addr2 = new address[](2);
        uint24  [] memory fees1 = new uint24 [](1);
        addr2[0] = BUSD;
        addr2[1] = ball.rico();
        fees1[0] = 500;
        bytes memory fore;
        bytes memory rear;

        (fore, rear) = create_path(addr2, fees1);
        swap.setPath(BUSD, rico, fore, rear);

        vm.prank(PSM);
        Gem(BUSD).transfer(address(this), 500 * WAD);

        Gem(BUSD).transfer(address(swap), 300 * WAD);
        uint res = swap.swap(BUSD, rico, address(swap), EXACT_IN, 300 * WAD, 1);
        // pool has no liquidity
        assert(swap.SWAP_ERR() == res);
    }
}
