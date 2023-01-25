// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { Gem } from '../lib/gemfab/src/gem.sol';
import { Math } from "../src/mixin/math.sol";
import { UniSetUp } from './UniHelper.sol';
import { UniSwapper } from '../src/swap2.sol';
import { WethLike } from "./RicoHelper.sol";

contract Swapper is UniSwapper {
    function swap(address tokIn, address tokOut, address receiver, uint8 kind, uint amt, uint limit)
            public returns (uint256 result) {
        result = _swap(tokIn, tokOut, receiver, SwapKind(kind), amt, limit);
    }

    function approveGem(address gem, address target) external {
        Gem(gem).approve(target, type(uint256).max);
    }
}

///@notice unit test of UniSwapper only, excludes use of ricobank and pool creation
contract UniTest is Test, UniSetUp, Math {
    address public immutable self   = address(this);
    address public immutable GATE   = 0xa3A7B6F88361F48403514059F1F16C8E78d60EeC;
    address public immutable BAL    = 0xba100000625a3754423978a60c9317c58a424e3D;
    address public immutable CRV    = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public immutable UNI    = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    uint256 public immutable lump   = 10000 * WAD;
    uint256 public immutable chip   = 100 * WAD;
    uint8   public immutable EXACT_IN  = 0;
    uint8   public immutable EXACT_OUT = 1;
    WethLike weth = WethLike(WETH);
    Swapper swap;

    function setUp() public {
        swap = new Swapper();
        swap.approveGem(BAL, ROUTER);
        swap.approveGem(CRV, ROUTER);
        swap.approveGem(UNI, ROUTER);
        swap.approveGem(WETH, ROUTER);

        swap.setSwapRouter(ROUTER);

        vm.prank(GATE);
        Gem(BAL).transfer(address(swap), lump);
        vm.prank(GATE);
        Gem(CRV).transfer(address(swap), lump);
        vm.prank(GATE);
        Gem(UNI).transfer(address(swap), lump);
        weth.deposit{value: lump}();
        Gem(WETH).transfer(address(swap), lump);

        // Create a path to swap UNI for WETH in a single hop
        address [] memory addr2 = new address[](2);
        uint24  [] memory fees1 = new uint24 [](1);
        addr2[0] = UNI;
        addr2[1] = WETH;
        fees1[0] = 500;
        bytes memory fore;
        bytes memory rear;
        (fore, rear) = create_path(addr2, fees1);
        swap.setPath(UNI, WETH, fore, rear);

        // Set a path to swap BAL for UNI via WETH
        address [] memory addr3 = new address[](3);
        uint24  [] memory fees2 = new uint24 [](2);
        addr3[0] = BAL;
        addr3[1] = WETH;
        addr3[2] = UNI;
        fees2[0] = 3000;
        fees2[1] = 500;
        (fore, rear) = create_path(addr3, fees2);
        swap.setPath(BAL, UNI, fore, rear);
    }

    function test_single_hop_exact_in() public {
        uint256 uni1 = Gem(UNI).balanceOf(address(swap));
        uint256 weth1 = Gem(WETH).balanceOf(address(swap));

        swap.swap(UNI, WETH, address(swap), EXACT_IN, chip, 0);

        uint256 weth2 = Gem(WETH).balanceOf(address(swap));
        uint256 uni2 = Gem(UNI).balanceOf(address(swap));

        assertGt(weth2, weth1);
        assertLt(uni2, uni1);
    }

    function test_single_hop_exact_out() public {
        uint256 uni1 = Gem(UNI).balanceOf(address(swap));
        uint256 weth1 = Gem(WETH).balanceOf(address(swap));

        swap.swap(UNI, WETH, address(swap), EXACT_OUT, WAD / 10, type(uint256).max);

        uint256 weth2 = Gem(WETH).balanceOf(address(swap));
        uint256 uni2 = Gem(UNI).balanceOf(address(swap));

        assertGt(weth2, weth1);
        assertLt(uni2, uni1);
    }

    function test_multi_hop_exact_in() public {
        uint256 bal1 = Gem(BAL).balanceOf(address(swap));
        uint256 uni1 = Gem(UNI).balanceOf(address(swap));

        swap.swap(BAL, UNI, address(swap), EXACT_IN, chip, 0);

        uint256 bal2 = Gem(BAL).balanceOf(address(swap));
        uint256 uni2 = Gem(UNI).balanceOf(address(swap));

        assertGt(uni2, uni1);
        assertLt(bal2, bal1);
    }

    function test_multi_hop_exact_out() public {
        uint256 bal1 = Gem(BAL).balanceOf(address(swap));
        uint256 uni1 = Gem(UNI).balanceOf(address(swap));

        swap.swap(BAL, UNI, address(swap), EXACT_OUT, chip, type(uint256).max);

        uint256 bal2 = Gem(BAL).balanceOf(address(swap));
        uint256 uni2 = Gem(UNI).balanceOf(address(swap));

        assertGt(uni2, uni1);
        assertLt(bal2, bal1);
    }
}
