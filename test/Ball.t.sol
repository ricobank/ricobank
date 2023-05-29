pragma solidity 0.8.19;

import "forge-std/Test.sol";
import { UniSetUp, PoolArgs, Asset } from "../test/UniHelper.sol";

import { Ball } from '../src/ball.sol';
import { INonfungiblePositionManager } from './Univ3Interface.sol';
import { Gem, GemFab } from '../lib/gemfab/src/gem.sol';
import { Feedbase } from '../lib/feedbase/src/Feedbase.sol';
import { Divider } from '../lib/feedbase/src/combinators/Divider.sol';
import { Medianizer } from '../lib/feedbase/src/Medianizer.sol';
import { UniswapV3Adapter } from "../lib/feedbase/src/adapters/UniswapV3Adapter.sol";
import { Vat } from '../src/vat.sol';
import { Math } from '../src/mixin/math.sol';
import { WethLike } from '../test/RicoHelper.sol';
import {ChainlinkAdapter} from "../lib/feedbase/src/adapters/ChainlinkAdapter.sol";
import {TWAP} from "../lib/feedbase/src/combinators/TWAP.sol";
import {Progression} from "../lib/feedbase/src/combinators/Progression.sol";
import { Vow } from "../src/vow.sol";
import { ERC20Hook } from '../src/hook/ERC20hook.sol';
import { Vox } from "../src/vox.sol";

contract BallTest is Test, UniSetUp, Math {
    bytes32 internal constant WILK = "weth";
    uint8   public immutable EXACT_IN  = 0;
    uint8   public immutable EXACT_OUT = 1;
    address internal constant DAI   = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address internal constant WETH  = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant WETH_DAI_POOL  = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;
    bytes32 internal constant WETH_ILK = "weth";
    bytes32 internal constant WETH_DAI_TAG = "weth:dai";
    bytes32 internal constant WETH_RICO_TAG = "weth:rico";
    bytes32 internal constant RICO_DAI_TAG = "rico:dai";
    bytes32 internal constant DAI_RICO_TAG = "dai:rico";
    bytes32 internal constant XAU_USD_TAG = "xau:usd";
    bytes32 internal constant DAI_USD_TAG = "dai:usd";
    bytes32 internal constant RICO_XAU_TAG = "rico:xau";
    bytes32 internal constant REF_RICO_TAG = "ref:rico";
    bytes32 internal constant RICO_REF_TAG = "rico:ref";
    bytes32 constant public RICO_RISK_TAG  = "rico:risk";
    bytes32 constant public RISK_RICO_TAG  = "risk:rico";
    ChainlinkAdapter cladapt;
    UniswapV3Adapter uniadapt;
    Divider divider;
    Medianizer mdn;
    Feedbase fb;
    GemFab gf;
    address me;
    INonfungiblePositionManager npfm = INonfungiblePositionManager(
        0xC36442b4a4522E871399CD717aBDD847Ab11FE88
    );
    address COMPOUND_CDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;

    uint256 constant public BANKYEAR = (365 * 24 + 6) * 3600;
    address rico;
    address risk;
    address ricodai;
    address ricorisk;
    uint24  constant public RICO_FEE = 500;
    uint24  constant public RISK_FEE = 3000;
    uint160 constant public risk_price = 2 ** 96;
    uint256 constant INIT_SQRTPAR = RAY * 2;
    uint256 constant INIT_PAR = (INIT_SQRTPAR ** 2) / RAY;
    uint256 constant wethricoprice = 1500 * RAY * RAY / INIT_PAR;
    uint256 constant wethamt = WAD;
    int256  constant dart = int(wethamt * wethricoprice / INIT_PAR);
    bytes32[] ilks;
    uint DEV_FUND_RISK = 1000000 * WAD;
    uint DUST = 90 * RAD;

    ERC20Hook hook;
    Vat vat;
    Vow vow;
    Vox vox;

    receive () payable external {}

    function advance_chainlink() internal {
        // chainlink adapter advances from chainlink time
        // prank ttl to uint max
        (bytes32 v,) = fb.pull(address(cladapt), XAU_USD_TAG);
        vm.prank(address(cladapt));
        fb.push(XAU_USD_TAG, v, type(uint).max);
        (v,) = fb.pull(address(cladapt), DAI_USD_TAG);
        vm.prank(address(cladapt));
        fb.push(DAI_USD_TAG, v, type(uint).max);
    }

    function _ink(bytes32 i, address u) view internal returns (uint) {
        (,,,,,,,,address ihook) = vat.ilks(i);
        return ERC20Hook(ihook).inks(i, u);
    }

    function look_poke() internal {
        advance_chainlink();
        uniadapt.look(WETH_DAI_TAG);
        uniadapt.look(RICO_DAI_TAG);
        uniadapt.look(RICO_RISK_TAG);


        mdn.poke(WETH_RICO_TAG);
        mdn.poke(RICO_REF_TAG);
        mdn.poke(RICO_RISK_TAG);
        mdn.poke(RISK_RICO_TAG);
    }

    function make_uniwrapper() internal returns (address deployed) {
        bytes memory args = abi.encode('');
        bytes memory bytecode = abi.encodePacked(vm.getCode(
            "../lib/feedbase/artifacts/src/adapters/UniWrapper.sol:UniWrapper"
        ), args);
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
    }

    function setUp() public {
        me = address(this);
        gf = new GemFab();
        fb = new Feedbase();
        rico = address(gf.build(bytes32("Rico"), bytes32("RICO")));
        risk = address(gf.build(bytes32("Rico Riskshare"), bytes32("RISK")));
        uint160 sqrtparx96 = uint160(INIT_SQRTPAR * (2 ** 96) / RAY);
        ricodai = create_pool(rico, DAI, 500, sqrtparx96);
        ricorisk = create_pool(rico, risk, RISK_FEE, risk_price);

        Ball.IlkParams[] memory ips = new Ball.IlkParams[](1);
        ilks = new bytes32[](1);
        ilks[0] = WETH_ILK;
        assertEq(ilks.length, 1);
        ips[0] = Ball.IlkParams(
            'weth',
            WETH,
            WETH_DAI_POOL,
            RAY, // chop
            DUST, // dust
            1000000001546067052200000000, // fee
            100000 * RAD, // line
            RAY, // liqr
            20000, // ttl
            1 // range
        );

        address uniwrapper = make_uniwrapper();
        Ball.UniParams memory ups = Ball.UniParams(
            0xC36442b4a4522E871399CD717aBDD847Ab11FE88,
            ':uninft',
            1000000001546067052200000000,
            RAY,
            8,
            uniwrapper
        );

        Ball.BallArgs memory bargs = Ball.BallArgs(
            address(fb),
            rico,
            risk,
            ricodai,
            ricorisk,
            router,
            uniwrapper,
            INIT_PAR,
            100000 * WAD,
            20000, // ricodai
            BANKYEAR * 100,
            BANKYEAR, // daiusd
            BANKYEAR, // xauusd
            Vow.Ramp(WAD, WAD, block.timestamp, 1),
            0x6B175474E89094C44Da98b954EedeAC495271d0F,
            0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9,
            0x214eD9Da11D2fbe465a6fc601a91E62EbEc1a0D6
        );

        uint gas = gasleft();
        Ball ball = new Ball(bargs);
        ball.makeilk(ips[0]);
        ball.makeuni(ups);
        ball.approve(me);

        uint usedgas     = gas - gasleft();
        uint expectedgas = 19923011;
        if (usedgas < expectedgas) {
            console.log("ball saved %s gas...currently %s", expectedgas - usedgas, usedgas);
        }
        if (usedgas > expectedgas) {
            console.log("ball gas increase by %s...currently %s", usedgas - expectedgas, usedgas);
        }

        Gem(rico).ward(address(ball.vat()), true);
        Gem(risk).ward(address(ball.vow()), true);

        vat = ball.vat();
        cladapt = ball.cladapt();
        uniadapt = ball.uniadapt();
        divider = ball.divider();
        mdn = ball.mdn();

        skip(40000);
        cladapt.look(XAU_USD_TAG);
        cladapt.look(DAI_USD_TAG);
        uniadapt.look(WETH_DAI_TAG);
        look_poke();
        skip(BANKYEAR / 2);

        hook = ball.hook();
        vm.prank(VAULT);
        Gem(DAI).transfer(address(this), 500 * WAD);
        Gem(WETH).approve(address(hook), type(uint).max);
        WethLike(WETH).deposit{value: wethamt * 100}();
        // try to frob 1 weth for at least $1k...shouldn't work because no look
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(WETH_ILK, me, abi.encodePacked(wethamt), dart);

        cladapt.look(XAU_USD_TAG);
        cladapt.look(DAI_USD_TAG);
        uniadapt.look(WETH_DAI_TAG);

        look_poke();

        vow = ball.vow();
        vox = ball.vox();

        Gem(risk).mint(address(this), DEV_FUND_RISK);
        Gem(rico).approve(address(hook), type(uint256).max);
        Gem(risk).approve(address(hook), type(uint256).max);
    }

    modifier _flap_after_ {
        _;
        uint vow_risk_before = Gem(risk).balanceOf(address(vow));
        Gem(risk).mint(me, 10000 * WAD);
        vow.keep(ilks);
        uint vow_risk_after = Gem(risk).balanceOf(address(vow));
        assertGt(vow_risk_after, vow_risk_before);
    }

    modifier _flop_after_ {
        _;
        vm.expectCall(risk, abi.encodePacked(Gem(risk).mint.selector));
        vow.keep(ilks);
    }

    modifier _balanced_after_ {
        _;
        // should not be any auctions
        uint me_risk_1 = Gem(risk).balanceOf(me);
        uint me_rico_1 = Gem(rico).balanceOf(me);

        vow.keep(ilks);

        uint me_risk_2 = Gem(risk).balanceOf(me);
        uint me_rico_2 = Gem(rico).balanceOf(me);

        assertEq(me_risk_1, me_risk_2);
        assertEq(me_rico_1, me_rico_2);
    }

    function test_basic() public {
        (bytes32 price, uint ttl) = fb.pull(address(mdn), RICO_REF_TAG);
        uint vox_price = rmul(uint(price), vox.amp());
        assertGt(uint(vox_price), INIT_PAR * 99 / 100);
        assertLt(uint(vox_price), INIT_PAR * 100 / 99);
        (price, ttl) = fb.pull(address(mdn), WETH_RICO_TAG);
        // ether price about 1600 rn
        assertGt(uint(price) / RAY, 1000 * RAY / INIT_PAR);
        assertLt(uint(price) / RAY, 2000 * RAY / INIT_PAR);
    }

    function test_ball() public {
        vat.frob(WETH_ILK, me, abi.encodePacked(wethamt), dart);
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(WETH_ILK, me, abi.encodePacked(int(0)), dart);
    }

    function test_fee_bail_flop() public _flop_after_ {
        vat.frob(WETH_ILK, me, abi.encodePacked(wethamt), dart);
        vm.expectRevert(Vow.ErrSafeBail.selector);
        vow.bail(WETH_ILK, me);
        skip(BANKYEAR * 100);
        // revert bc feed data old
        vm.expectRevert(Vow.ErrSafeBail.selector);
        vow.bail(WETH_ILK, me);
        look_poke();
        vow.keep(ilks);
        uint meweth = WethLike(WETH).balanceOf(me);
        Gem(rico).mint(me, 1000000 * WAD);
        vow.bail(WETH_ILK, me);
        assertGt(WethLike(WETH).balanceOf(me), meweth);
    }


    function test_ball_flap() public _flap_after_ {
        vat.frob(WETH_ILK, me, abi.encodePacked(wethamt), dart);
        vm.expectRevert(Vow.ErrSafeBail.selector);
        vow.bail(WETH_ILK, me);
        skip(BANKYEAR * 100);
    }

    // user pays down the urn first, then try to flap
    function test_ball_pay_flap_1() public {
        vat.frob(WETH_ILK, me, abi.encodePacked(wethamt), dart);
        vm.expectRevert(Vow.ErrSafeBail.selector);
        vow.bail(WETH_ILK, me);
        skip(BANKYEAR * 100); advance_chainlink(); look_poke();

        uint artleft = vat.urns(WETH_ILK, me);
        uint inkleft = _ink(WETH_ILK, me);

        (,uint rack,,uint dust,,,,,) = vat.ilks(WETH_ILK);
        vat.frob(WETH_ILK, me, abi.encodePacked(int(0)), -int((artleft * rack - dust) / rack));
        uint artleftafter = vat.urns(WETH_ILK, me);
        uint inkleftafter = _ink(WETH_ILK, me);
        assertEq(inkleftafter, inkleft);
        assertEq(artleftafter, dust / rack);

        uint self_risk_1 = Gem(risk).balanceOf(me);
        vow.keep(ilks);
        uint self_risk_2 = Gem(risk).balanceOf(me);
        assertLt(self_risk_2, self_risk_1);
    }

    function test_ball_pay_flap_success() public  _balanced_after_ {
        vat.frob(WETH_ILK, me, abi.encodePacked(wethamt), dart);
        vm.expectRevert(Vow.ErrSafeBail.selector);
        vow.bail(WETH_ILK, me);
        skip(BANKYEAR * 100); look_poke();

        uint artleft = vat.urns(WETH_ILK, me);
        uint inkleft = _ink(WETH_ILK, me);
        vow.keep(ilks); // drips
        Gem(rico).mint(me, artleft * 1000);
        (,uint rack,,uint dust,,,,,) = vat.ilks(WETH_ILK);
        vat.frob(WETH_ILK, me, abi.encodePacked(int(0)), -int((artleft * rack - dust) / rack));
        uint artleftafter = vat.urns(WETH_ILK, me);
        uint inkleftafter = _ink(WETH_ILK, me);
        assertEq(inkleftafter, inkleft);
        assertGt(artleftafter, dust / rack * 999 / 1000);
        assertLt(artleftafter, dust / rack * 1000 / 999);
        // balanced now because already kept
    }

}
