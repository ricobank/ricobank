// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import { Swapper, UniSetUp } from "../test/UniHelper.sol";

import { Ball, GemFabLike } from '../src/ball.sol';
import { INonfungiblePositionManager, IUniswapV3Pool } from '../src/TEMPinterface.sol';
import { Gem, GemFab } from '../lib/gemfab/src/gem.sol';
import { Feedbase } from '../lib/feedbase/src/Feedbase.sol';
import { Divider } from '../lib/feedbase/src/combinators/Divider.sol';
import { Medianizer } from '../lib/feedbase/src/Medianizer.sol';
import { UniswapV3Adapter } from "../lib/feedbase/src/adapters/UniswapV3Adapter.sol";
import { BalSetUp } from "./RicoHelper.sol";
import { UniSwapper } from '../src/swap2.sol';
import { Vat } from '../src/vat.sol';
import { Math } from '../src/mixin/math.sol';
import { WethLike } from '../test/RicoHelper.sol';

contract BallTest is Test, BalSetUp, UniSetUp, Math {
    bytes32 internal constant WILK = "weth";
    uint8   public immutable EXACT_IN  = 0;
    uint8   public immutable EXACT_OUT = 1;
    address internal constant BUSD = 0x4Fabb145d64652a948d72533023f6E7A623C7C53;
    address internal constant PSM  = 0xF977814e90dA44bFA03b6295A0616a897441aceC;
    // TODO these should have dashes
    bytes32 internal constant WTAG = "wethusd";
    bytes32 internal constant WRTAG = "wethrico";
    bytes32 internal constant RTAG = "ricousd";
    Swapper swap;
    uint256 constant public BANKYEAR = (365 * 24 + 6) * 3600;
    address rico;

    function setUp() public {
    }

    function test_ball() public {
        address aweth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        uint gas = gasleft();
        GemFabLike gf = GemFabLike(address(new GemFab()));
        Feedbase fb = new Feedbase();
        // todo par arg
        Ball ball = new Ball(
            gf, address(fb), aweth, BAL_W_P_F, BAL_VAULT
        );
        skip(BANKYEAR);
        uint usedgas     = gas - gasleft();
        uint expectedgas = 25271853;
        if (usedgas < expectedgas) {
            console.log("ball saved %s gas", expectedgas - usedgas);
        }
        if (usedgas > expectedgas) {
            console.log("ball gas increase by", usedgas - expectedgas);
        }

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

        Vat vat = ball.vat();
        uint wethamt = WAD;
        address me   = address(this);
        WethLike(WETH).deposit{value: wethamt}();
        uint par = vat.par(); // init_sqrtpar ^ 2
        // try to frob 1 weth for at least $1k...shouldn't work because no look
        int dart = int(par * wethamt * 1000 / RAY);
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(WILK, me, int(wethamt), dart);

        UniswapV3Adapter adapt = ball.adapt();
        Divider divider = ball.divider();
        (,,address _mdn,,,,,,,,,) = vat.ilks(WILK);
        Medianizer mdn = Medianizer(_mdn);
 
        adapt.look(WTAG);
        adapt.look(RTAG);
        divider.poke(WRTAG);
        mdn.poke(WRTAG);

        Gem(WETH).approve(address(vat), type(uint).max);
        vat.frob(WILK, me, int(wethamt), dart);
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(WILK, me, 0, dart);
    }
}
