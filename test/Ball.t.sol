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
import { UniSwapper } from '../src/swap.sol';
import { Vat } from '../src/vat.sol';
import { Math } from '../src/mixin/math.sol';
import { WethLike } from '../test/RicoHelper.sol';
import {ChainlinkAdapter} from "../lib/feedbase/src/adapters/ChainlinkAdapter.sol";
import {TWAP} from "../lib/feedbase/src/combinators/TWAP.sol";
import {Progression} from "../lib/feedbase/src/combinators/Progression.sol";
import { Vow } from "../src/vow.sol";
import {UniFlower} from '../src/flow.sol';

contract BallTest is Test, UniSetUp, Math {
    bytes32 internal constant WILK = "weth";
    uint8   public immutable EXACT_IN  = 0;
    uint8   public immutable EXACT_OUT = 1;
    address internal constant DAI   = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address internal constant WETH  = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant WETH_DAI_POOL  = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;
    // TODO these should have dashes
    bytes32 internal constant WETH_ILK = "weth";
    bytes32 internal constant WETH_DAI_TAG = "wethdai";
    bytes32 internal constant WETH_RICO_TAG = "wethrico";
    bytes32 internal constant RICO_DAI_TAG = "ricodai";
    bytes32 internal constant DAI_RICO_TAG = "dairico";
    bytes32 internal constant XAU_USD_TAG = "xauusd";
    bytes32 internal constant XAU_DAI_TAG = "xauusd";
    bytes32 internal constant DAI_USD_TAG = "daiusd";
    bytes32 internal constant XAU_RICO_TAG = "xaurico";
    bytes32 internal constant REF_RICO_TAG = "refrico";
    bytes32 internal constant RICO_REF_TAG = "ricoref";
    ChainlinkAdapter cladapt;
    UniswapV3Adapter adapt;
    Divider divider;
    Progression progression;
    TWAP twap;
    Medianizer mdn;
    Feedbase fb;
    GemFabLike gf;
    address me;
    INonfungiblePositionManager npfm = INonfungiblePositionManager(
        0xC36442b4a4522E871399CD717aBDD847Ab11FE88
    );
    address COMPOUND_CDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;

    Swapper swap;
    uint256 constant public BANKYEAR = (365 * 24 + 6) * 3600;
    address rico;
    uint constant INIT_SQRTPAR = RAY * 2;
    uint constant INIT_PAR = (INIT_SQRTPAR ** 2) / RAY;
    uint constant wethricoprice = 1500 * RAY * RAY / INIT_PAR;
    uint constant wethamt = WAD;
    int constant dart = int(wethamt * wethricoprice / INIT_PAR);

    Vat vat;
    Vow vow;
    UniFlower flow;

    function setUp() public {
        address aweth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        uint gas = gasleft();
        gf = GemFabLike(address(new GemFab()));
        fb = new Feedbase();

        bytes32[] memory ilks = new bytes32[](1);
        ilks[0] = WILK;
        address[] memory gems = new address[](1);
        gems[0] = WETH;
        address[] memory pools = new address[](1);
        pools[0] = WETH_DAI_POOL;
        Ball ball = new Ball(Ball.BallArgs(
            address(gf), address(fb), aweth, factory, router, INIT_SQRTPAR, ilks, gems, pools
        ));
        skip(BANKYEAR / 2);
        uint usedgas     = gas - gasleft();
        uint expectedgas = 27299482;
        if (usedgas < expectedgas) {
            console.log("ball saved %s gas...currently %s", expectedgas - usedgas, usedgas);
        }
        if (usedgas > expectedgas) {
            console.log("ball gas increase by %s...currently %s", usedgas - expectedgas, usedgas);
        }

        swap = new Swapper();
        rico = ball.rico();
        swap.approveGem(DAI, router);
        swap.approveGem(rico, router);
        swap.setSwapRouter(router);
        // Create a path to swap UNI for WETH in a single hop
        address [] memory addr2 = new address[](2);
        uint24  [] memory fees1 = new uint24 [](1);
        addr2[0] = DAI;
        addr2[1] = ball.rico();
        fees1[0] = 500;
        bytes memory fore;
        bytes memory rear;
        (fore, rear) = create_path(addr2, fees1);
        swap.setPath(DAI, rico, fore, rear);

        vm.prank(VAULT);
        Gem(DAI).transfer(address(this), 500 * WAD);

        Gem(DAI).transfer(address(swap), 300 * WAD);
        uint res = swap.swap(DAI, rico, address(swap), EXACT_IN, 300 * WAD, 1);
        // pool has no liquidity
        assert(swap.SWAP_ERR() == res);

        vat = ball.vat();
        Gem(WETH).approve(address(vat), type(uint).max);
        me   = address(this);
        WethLike(WETH).deposit{value: wethamt * 100}();
        // try to frob 1 weth for at least $1k...shouldn't work because no look
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(WETH_ILK, me, int(wethamt), dart);

        adapt = ball.adapt();
        divider = ball.divider();
        (,,address _mdn,,,,,,,,,) = vat.ilks(WETH_ILK);
        mdn = Medianizer(_mdn);
 
        cladapt = ball.cladapt();
        twap = ball.twap();
        progression = ball.progression();

        cladapt.look(XAU_USD_TAG);
        cladapt.look(DAI_USD_TAG);
        {
            // chainlink adapter advances from chainlink time
            // prank ttl to uint max
            (bytes32 v,) = fb.pull(address(cladapt), XAU_USD_TAG);
            vm.prank(address(cladapt));
            fb.push(XAU_USD_TAG, v, type(uint).max);
            (v,) = fb.pull(address(cladapt), DAI_USD_TAG);
            vm.prank(address(cladapt));
            fb.push(DAI_USD_TAG, v, type(uint).max);
        }

        look_poke();

        vow = ball.vow();

        bool reverse = rico > DAI;
        uint daiamt = 10000 * WAD;
        vm.prank(COMPOUND_CDAI);
        Gem(DAI).transfer(address(this), daiamt * 10);
        Gem(rico).mint(address(this), daiamt * RAY / INIT_SQRTPAR);
        Gem(DAI).approve(address(nfpm), type(uint).max);
        Gem(rico).approve(address(nfpm), type(uint).max);
        if (reverse) {
            int24 tick = getTickAtSqrtRatio(uint160(RAY ** 2 / INIT_SQRTPAR * 2 ** 96 / RAY));
            tick = tick / 10 * 10;
            nfpm.mint(INonfungiblePositionManager.MintParams(
                DAI, rico,
                500,
                tick - 10,
                tick + 10,
                daiamt,
                daiamt * RAY / INIT_SQRTPAR,
                0,
                0,
                address(this),
                type(uint).max
            ));
                
        } else {
            int24 tick = getTickAtSqrtRatio(uint160(INIT_SQRTPAR * 2 ** 96 / RAY));
            tick = tick / 10 * 10;
            nfpm.mint(INonfungiblePositionManager.MintParams(
                rico, DAI,
                500,
                tick - 10,
                tick + 10,
                daiamt * RAY / INIT_SQRTPAR,
                daiamt,
                0,
                0,
                address(this),
                type(uint).max
            ));
        }

        flow = ball.flow();
    }

    function look_poke() internal {
        adapt.look(WETH_DAI_TAG);
        adapt.look(RICO_DAI_TAG);

        divider.poke(WETH_RICO_TAG);
        divider.poke(DAI_RICO_TAG);
        divider.poke(XAU_DAI_TAG);
        divider.poke(XAU_RICO_TAG);

        twap.poke(XAU_RICO_TAG);
        progression.poke(REF_RICO_TAG);
        divider.poke(RICO_REF_TAG);

        mdn.poke(WETH_RICO_TAG);
        mdn.poke(RICO_REF_TAG);
    }

    function test_basic() public {
        (bytes32 price, uint ttl) = fb.pull(address(mdn), RICO_REF_TAG);
        assertEq(uint(price) / RAY, INIT_PAR / RAY);
        (price, ttl) = fb.pull(address(mdn), WETH_RICO_TAG);
        // ether price about 1600 rn
        assertGt(uint(price) / RAY, 1000 * RAY / INIT_PAR);
        assertLt(uint(price) / RAY, 2000 * RAY / INIT_PAR);
    }

    function test_ball() public {
        vat.frob(WETH_ILK, me, int(wethamt), dart);
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(WETH_ILK, me, 0, dart);
    }

    function test_fee_bail() public {
        vat.frob(WETH_ILK, me, int(wethamt), dart);
        vm.expectRevert(Vow.ErrSafeBail.selector);
        vow.bail(WETH_ILK, me);
        skip(BANKYEAR * 100);
        // revert bc feed data old
        vm.expectRevert(Vow.ErrSafeBail.selector);
        vow.bail(WETH_ILK, me);
        look_poke();
        uint aid = vow.bail(WETH_ILK, me);
        flow.glug(aid);
    }
}
