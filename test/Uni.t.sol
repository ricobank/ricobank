// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { Gem, GemFab } from '../lib/gemfab/src/gem.sol';
import { Math } from "../src/mixin/math.sol";
import { Asset, PoolArgs, Swapper, UniSetUp } from './UniHelper.sol';
import { WethLike } from "./RicoHelper.sol";



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
    GemFab gemfab;
    address[] addr2;
    uint24[] fees1;

    function setUp() public {
        gemfab = new GemFab();
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
        addr2 = new address[](2);
        fees1 = new uint24 [](1);
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

    function test_join(Gem token0, Gem token1) private {
        swap.approveGem(address(token0), ROUTER);
        swap.approveGem(address(token1), ROUTER);
        addr2 = new address[](2);
        fees1 = new uint24 [](1);
        addr2[0] = address(token0);
        addr2[1] = address(token1);
        fees1[0] = 500;
        bytes memory fore;
        bytes memory rear;
        (fore, rear) = create_path(addr2, fees1);
        swap.setPath(address(token0), address(token1), fore, rear);


        uint amt0 = WAD;
        uint amt1 = 4 * WAD;
        uint24 fee = 500;
        uint160 sqrtPriceX96 = x96(2);
        uint160 sqrtSpreadX96 = x96div(x96(101), x96(100));
        uint160 low = x96div(sqrtPriceX96, sqrtSpreadX96);
        uint160 high = x96mul(sqrtPriceX96, sqrtSpreadX96);
        assertLt(low, high);

        token0.mint(address(this), amt0);
        token1.mint(address(this), amt1);
        create_and_join_pool(PoolArgs(
            Asset(address(token0), amt0),
            Asset(address(token1), amt1),
            fee,
            sqrtPriceX96,
            low,
            high,
            10 // whatever, we know it's 10
        ));

        token0.mint(address(swap), WAD * 1000);
        token1.mint(address(swap), WAD * 1000);
        uint tok1before = token1.balanceOf(address(swap));
        uint tok0before = token0.balanceOf(address(swap));
        uint res = swap.swap(address(token0), address(token1), address(swap), EXACT_IN, WAD, 0);
        assertLt(token0.balanceOf(address(swap)), tok0before);
        assertGt(token1.balanceOf(address(swap)), tok1before);
        assert(swap.SWAP_ERR() != res);
    }

    function test_join_forward() public {
        Gem token0 = gemfab.build("TOK0", "token 0");
        Gem token1 = gemfab.build("TOK1", "token 1");
        do {
            token1 = gemfab.build("TOK1", "token 1");
        } while (token0 > token1);
        test_join(token0, token1);
    }

    function test_join_reverse() public {
        Gem token0 = gemfab.build("TOK0", "token 0");
        Gem token1;
        do {
            token1 = gemfab.build("TOK1", "token 1");
        } while (token0 < token1);
        test_join(token0, token1);
    }
}
