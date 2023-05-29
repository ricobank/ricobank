// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.19;
import 'forge-std/Test.sol';

import '../src/mixin/math.sol';
import { Feedbase } from '../lib/feedbase/src/Feedbase.sol';
import { Divider } from '../lib/feedbase/src/combinators/Divider.sol';
import { Medianizer } from '../lib/feedbase/src/Medianizer.sol';
import { GemFab, Gem } from '../lib/gemfab/src/gem.sol';
import { Ball } from '../src/ball.sol';
import { Vat } from '../src/vat.sol';
import { Vow } from '../src/vow.sol';
import { Vox } from '../src/vox.sol';
import { ERC20Hook } from '../src/hook/ERC20hook.sol';
import { UniNFTHook } from '../src/hook/nfpm/UniV3NFTHook.sol';
import { UniSetUp } from "./UniHelper.sol";

interface WethLike {
    function deposit() external payable;
    function approve(address, uint) external;
    function allowance(address, address) external returns (uint);
    function balanceOf(address) external returns (uint);
}


contract Guy {
    Vat vat;
    Vow vow;
    constructor(address _vat, address _vow) {
        vat  = Vat(_vat);
        vow = Vow(_vow);
    }
    function approve(address gem, address dst, uint amt) public {
        Gem(gem).approve(dst, amt);
    }
    function frob(bytes32 ilk, address usr, bytes calldata dink, int dart) public {
        vat.frob(ilk, usr, dink, dart);
    }
    function transfer(address gem, address dst, uint amt) public {
        Gem(gem).transfer(dst, amt);
    }
    function bail(bytes32 i, address u) public {
        vow.bail(i, u);
    }
    function keep(bytes32[] calldata ilks) public {
        vow.keep(ilks);
    }
}

abstract contract RicoSetUp is UniSetUp, Math, Test {
    address constant public DAI  = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant public WETH_DAI_POOL = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;
    bytes32 constant public WETH_RICO_TAG = "weth:rico";
    bytes32 constant public RICO_RISK_TAG = "rico:risk";
    bytes32 constant public RISK_RICO_TAG = "risk:rico";

    address constant public VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    bytes32 constant public dilk  = "dai";
    bytes32 constant public gilk  = "gold";
    bytes32 constant public wilk  = "weth";
    bytes32 constant public rilk  = "ruby";
    bytes32 constant public uilk  = ":uninft";
    bytes32 constant public dutag = "dai:usd";
    bytes32 constant public grtag = "gold:rico";
    bytes32 constant public wrtag = "weth:rico";
    bytes32 constant public drtag = "dai:rico";

    bytes32 constant public rtag       = "rico:usd";
    uint160 constant public risk_price = 2 ** 96;
    uint24  constant public RICO_FEE   = 500;
    uint24  constant public RISK_FEE   = 3000;
    uint256 constant public HOOK_ROOM  = 8;
    uint256 constant public init_mint  = 10000;
    uint256 constant public BANKYEAR   = (365 * 24 + 6) * 3600;
    uint256 constant public no_rush    = WAD;
    address public immutable azero     = address(0);
    address payable public immutable self = payable(address(this));

    ERC20Hook   public hook;
    UniNFTHook  public nfthook;
    Medianizer  public mdn;
    Ball     public ball;
    Divider  public divider;
    Feedbase public feed;
    Gem      public dai;
    Gem      public gold;
    Gem      public ruby;
    Gem      public rico;
    Gem      public risk;
    GemFab   public gemfab;
    Vat      public vat;
    Vow      public vow;
    Vox      public vox;
    address  public ricodai;
    address  public ricorisk;
    address  public arico;
    address  public arisk;
    address  public agold;
    address  public aruby;
    address  public avat;
    address  public avow;
    address  public avox;
    address  public ahook;
    address  public uniwrapper;

    Guy _bob;
    Guy guy;

    receive () external payable {}

    function rico_mint(uint amt, bool bail) internal {
        uint start_gold = gold.balanceOf(self);
        _bob = new Guy(avat, avow);
        (bytes32 v, uint t) = feedpull(grtag);
        feedpush(grtag, bytes32(RAY * 10000), type(uint).max);
        gold.mint(address(_bob), amt);
        _bob.approve(agold, address(hook), amt);
        _bob.frob(gilk, address(_bob), abi.encodePacked(amt), int(amt));
        feedpush(grtag, bytes32(0), type(uint).max);
        if (bail) vow.bail(gilk, address(_bob));
        _bob.transfer(arico, self, amt);
        feedpush(grtag, v, t);
        uint end_gold = gold.balanceOf(self);
        gold.burn(self, end_gold - start_gold);
    }

    function _ink(bytes32 ilk, address usr) internal view returns (uint) {
        (,,,,,,,,address h) = vat.ilks(ilk);
        return ERC20Hook(h).inks(ilk, usr);
    }

    function _art(bytes32 ilk, address usr) internal view returns (uint art) {
        art = vat.urns(ilk, usr);
    }

    function check_gas(uint gas, uint expectedgas) internal view {
        uint usedgas = gas - gasleft();
        if (usedgas < expectedgas) {
            console.log("saved %s gas...currently %s", expectedgas - usedgas, usedgas);
        }
        if (usedgas > expectedgas) {
            console.log("gas increase by %s...currently %s", usedgas - expectedgas, usedgas);
        }
    }

    function feedpull(bytes32 tag) internal view returns (bytes32, uint) {
        return feed.pull(address(mdn), tag);
    }

    function feedpush(bytes32 tag, bytes32 val, uint ttl) internal {
        feed.push(tag, val, ttl);
        mdn.poke(tag);
    }

    function make_feed(bytes32 tag) internal {
        address[] memory sources = new address[](2);
        bytes32[] memory tags = new bytes32[](2);
        sources[0] = address(this); tags[0] = bytes32(tag);
        sources[1] = address(this); tags[1] = bytes32("ONE");
        divider.setConfig(tag, Divider.Config(sources, tags));
        // todo quorum?
        Medianizer.Config memory mdnconf =
            Medianizer.Config(new address[](1), new bytes32[](1), 0);
        mdnconf.srcs[0] = address(divider);
        mdnconf.tags[0] = tag;
        mdn.setConfig(tag, mdnconf);
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

    function make_bank() public {
        feed   = new Feedbase();
        gemfab = new GemFab();
        rico  = gemfab.build(bytes32("Rico"), bytes32("RICO"));
        risk  = gemfab.build(bytes32("Rico Riskshare"), bytes32("RISK"));
        arico = address(rico);
        arisk = address(risk);
        uint160 sqrtparx96 = uint160(2 ** 96);
        ricodai  = create_pool(arico, DAI, 500, sqrtparx96);
        ricorisk = create_pool(arico, arisk, RISK_FEE, risk_price);

        uniwrapper = make_uniwrapper();

        Ball.IlkParams[] memory ips = new Ball.IlkParams[](1);
        ips[0] = Ball.IlkParams(
            'weth',
            WETH,
            WETH_DAI_POOL,
            RAY, // chop
            90 * RAD, // dust
            1000000001546067052200000000, // fee
            100000 * RAD, // line
            RAY, // liqr
            20000, // ttl
            BANKYEAR / 4 // range
        );
        Ball.UniParams memory ups = Ball.UniParams(
            0xC36442b4a4522E871399CD717aBDD847Ab11FE88,
            ':uninft',
            1000000001546067052200000000,
            RAY,
            HOOK_ROOM,
            uniwrapper
        );
        Ball.BallArgs memory bargs = Ball.BallArgs(
            address(feed),
            arico,
            arisk,
            ricodai,
            ricorisk,
            router,
            uniwrapper,
            RAY,
            100000 * WAD,
            20000, // ricodai
            BANKYEAR / 4,
            BANKYEAR, // daiusd
            BANKYEAR, // xauusd
            Vow.Ramp(WAD, WAD, block.timestamp, 1),
            0x6B175474E89094C44Da98b954EedeAC495271d0F,
            0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9,
            0x214eD9Da11D2fbe465a6fc601a91E62EbEc1a0D6
        );

        ball = new Ball(bargs);
        ball.makeilk(ips[0]);
        ball.makeuni(ups);
        ball.approve(self);

        ////////// these are outside ball, but must be part of real deploy process, unless warding ball first w create2
        Gem(rico).ward(address(ball.vat()), true);
        Gem(risk).ward(address(ball.vow()), true);
        // Gem(rico).ward(address(self), false);
        // Gem(risk).ward(address(self), false);
        //////////

        vat  = Vat(address(ball.vat()));
        vow  = Vow(address(ball.vow()));
        vox  = Vox(address(ball.vox()));
        hook = ball.hook();
        nfthook = ball.nfthook();
        mdn  = ball.mdn();
        divider = ball.divider();

        avat  = address(vat);
        avow  = address(vow);
        avox  = address(vox);
        ahook = address(hook);

        rico.approve(avat, type(uint256).max);
        rico.approve(ahook, type(uint256).max);

        feed.push(bytes32("ONE"), bytes32(RAY), type(uint).max);
        make_feed(rtag);
        make_feed(wrtag);
        make_feed(grtag);
        make_feed(RISK_RICO_TAG);
        make_feed(RICO_RISK_TAG);

        feedpush(RISK_RICO_TAG, bytes32(RAY), block.timestamp + 1000);
        feedpush(RICO_RISK_TAG, bytes32(RAY), block.timestamp + 1000);
    }

    function init_dai() public {
        dai = Gem(DAI);
        vm.prank(VAULT);
        dai.transfer(address(this), 10000 * WAD);
        dai.approve(address(hook), type(uint256).max);
        vat.init(dilk, address(hook));
        hook.wire(dilk, address(dai), self, drtag);
        vat.filk(dilk, 'hook', uint(bytes32(bytes20(address(hook)))));
        vat.filk(dilk, bytes32('chop'), RAD);
        vat.filk(dilk, bytes32('line'), init_mint * 10 * RAD);
        vat.filk(dilk, bytes32('fee'),  1000000001546067052200000000);  // 5%
        // feedpush(dutag, bytes32(RAY), block.timestamp + 1000);
        hook.list(DAI, true);
        make_feed(drtag);
    }

    function init_gold() public {
        gold = Gem(address(gemfab.build(bytes32("Gold"), bytes32("GOLD"))));
        gold.mint(self, init_mint * WAD);
        gold.approve(address(hook), type(uint256).max);
        vat.init(gilk, address(hook));
        hook.wire(gilk, address(gold), self, grtag);
        vat.filk(gilk, 'hook', uint(bytes32(bytes20(address(hook)))));
        // todo fix other chops, should be rays
        vat.filk(gilk, bytes32('chop'), RAY);
        vat.filk(gilk, bytes32('line'), init_mint * 10 * RAD);
        vat.filk(gilk, bytes32('fee'),  1000000001546067052200000000);  // 5%
        feedpush(grtag, bytes32(RAY), block.timestamp + 1000);
        agold = address(gold);
        hook.list(agold, true);
    }

    function init_ruby() public {
        ruby = Gem(address(gemfab.build(bytes32("Ruby"), bytes32("RUBY"))));
        ruby.mint(self, init_mint * WAD);
        ruby.approve(address(hook), type(uint256).max);
        vat.init(rilk, address(hook));
        hook.wire(rilk, address(ruby), self, rtag);
        vat.filk(rilk, 'hook', uint(bytes32(bytes20(address(hook)))));
        vat.filk(rilk, bytes32('chop'), RAD);
        vat.filk(rilk, bytes32('line'), init_mint * 10 * RAD);
        vat.filk(rilk, bytes32('fee'),  1000000001546067052200000000);  // 5%
        feedpush(rtag, bytes32(RAY), block.timestamp + 1000);
        hook.list(address(ruby), true);
        aruby = address(ruby);
    }

    function prepguyrico(uint amt, bool bail) internal {
        rico_mint(amt, bail);
        rico.transfer(address(guy), amt);
        guy.approve(arico, ahook, UINT256_MAX);
    }

    function assertClose(uint v1, uint v2, uint rel) internal {
        uint abs = v1 / rel;
        assertGt(v1 + abs, v2);
        assertLt(v1 - abs, v2);
    }

}
