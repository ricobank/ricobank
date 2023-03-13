// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.18;
import 'forge-std/Test.sol';

import '../src/mixin/math.sol';
import { UniFlower } from '../src/flow.sol';
import { Feedbase } from '../lib/feedbase/src/Feedbase.sol';
import { Divider } from '../lib/feedbase/src/combinators/Divider.sol';
import { Medianizer } from '../lib/feedbase/src/Medianizer.sol';
import { GemFab, Gem } from '../lib/gemfab/src/gem.sol';
import { GemFabLike } from '../src/ball.sol';
import { Ball } from '../src/ball.sol';
import { Vat } from '../src/vat.sol';
import { Vow } from '../src/vow.sol';
import { Vox } from '../src/vox.sol';
import {ERC20Hook} from '../src/hook/ERC20hook.sol';

import { UniSetUp } from "./UniHelper.sol";

interface WethLike {
    function deposit() external payable;
    function approve(address, uint) external;
    function allowance(address, address) external returns (uint);
    function balanceOf(address) external returns (uint);
}

contract GemUsr {
    Vat vat;
    constructor(Vat _vat) {
        vat  = _vat;
    }
    function approve(address gem, address usr, uint amt) public {
        Gem(gem).approve(usr, amt);
    }
    function frob(bytes32 ilk, address usr, int dink, int dart) public {
        vat.frob(ilk, usr, dink, dart);
    }
    function transfer(address gem, address dst, uint amt) public {
        Gem(gem).transfer(dst, amt);
    }
}

abstract contract RicoSetUp is UniSetUp, Math, Test {
    address constant public DAI   = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant public WETH  = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant public WETH_DAI_POOL  = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;
    address constant public VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    bytes32 constant public dilk = "dai";
    bytes32 constant public gilk = "gold";
    bytes32 constant public wilk = "weth";
    bytes32 constant public rilk = "ruby";
    bytes32 constant public dutag = "daiusd";
    bytes32 constant public grtag = "goldrico";
    bytes32 constant public wrtag = "wethrico";

    bytes32 constant public rtag = "ricousd";
    uint256 constant public init_mint = 10000;
    uint256 constant public BANKYEAR = (365 * 24 + 6) * 3600;
    address public immutable azero = address(0);
    address public immutable self = address(this);

    UniFlower public flow;
    GemFabLike public gemfab;
    Ball     public ball;
    Feedbase public feed;
    Gem      public dai;
    Gem      public gold;
    Gem      public ruby;
    Gem      public rico;
    Gem      public risk;
    Vat      public vat;
    Vow      public vow;
    Vox      public vox;
    ERC20Hook public hook;
    address  public arico;
    address  public arisk;
    address  public agold;
    address  public aruby;
    address  public avat;
    address  public avow;
    address  public avox;
    address  public ahook;
    Medianizer mdn;
    Divider divider;

    function rico_mint(uint amt, bool bail) internal {
        GemUsr usr = new GemUsr(vat);
        (bytes32 v, uint t) = feedpull(grtag);
        feedpush(grtag, bytes32(RAY), type(uint).max);
        gold.mint(address(usr), amt);
        usr.approve(agold, address(hook), amt);
        usr.frob(gilk, address(usr), int(amt), int(amt));
        feedpush(grtag, bytes32(0), type(uint).max);
        if (bail) vow.bail(gilk, address(usr));
        usr.transfer(arico, self, amt);
        feedpush(grtag, v, t);
    }

    function check_gas(uint gas, uint expectedgas) internal view {
        uint usedgas     = gas - gasleft();
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
        divider.poke(tag);
        mdn.poke(tag);
    }

    function make_feed(bytes32 tag) internal {
        address[] memory sources = new address[](2);
        bytes32[] memory tags = new bytes32[](2);
        sources[0] = address(this); tags[0] = bytes32(tag);
        sources[1] = address(this); tags[1] = bytes32("ONE");
        divider.setConfig(tag, Divider.Config(sources, tags));
    }

    function make_bank() public {
        feed = new Feedbase();
        gemfab = GemFabLike(address(new GemFab()));

        Ball.IlkParams[] memory ips = new Ball.IlkParams[](1);
        ips[0] = Ball.IlkParams(
            'weth',
            WETH,
            WETH_DAI_POOL,
            RAD, // chop
            90 * RAD, // dust
            1000000001546067052200000000, // fee
            100000 * RAD, // line
            RAY, // liqr
            UniFlower.Ramp(WAD / 1000, WAD, block.timestamp, 1, WAD / 100),
            20000, // ttl
            BANKYEAR / 4 // range
        );
        UniFlower.Ramp memory stdramp = UniFlower.Ramp(
            WAD, WAD, block.timestamp, 1, WAD / 100
        );
        Ball.BallArgs memory bargs = Ball.BallArgs(
            address(gemfab),
            address(feed),
            WETH,
            factory,
            router,
            self,
            RAY,
            100000 * RAD,
            20000, // ricodai
            BANKYEAR / 4,
            BANKYEAR, // daiusd
            BANKYEAR, // xauusd
            10000, // twap
            BANKYEAR,
            block.timestamp, // prog
            block.timestamp + BANKYEAR * 10,
            BANKYEAR / 12,
            stdramp,
            stdramp,
            stdramp
        );
        ball = new Ball(bargs, ips);


        rico = Gem(ball.rico());
        risk = Gem(ball.risk());
        vat  = Vat(address(ball.vat()));
        vow  = Vow(address(ball.vow()));
        vox  = Vox(address(ball.vox()));
        flow = ball.flow();
        hook = ball.hook();

        avat  = address(vat);
        avow  = address(vow);
        avox  = address(vox);
        arico = address(rico);
        arisk = address(risk);
        ahook = address(hook);

        rico.approve(avat, type(uint256).max);

        (,,address fsrc,,,,,,,,) = vat.ilks(wilk);
        mdn = Medianizer(fsrc);
        divider = ball.divider();
        
        feed.push(bytes32("ONE"), bytes32(RAY), type(uint).max);
        make_feed(rtag);
        make_feed(wrtag);
        make_feed(grtag);
    }

    function init_dai() public {
        dai = Gem(DAI);
        vm.prank(VAULT);
        dai.transfer(address(this), 10000 * WAD);
        dai.approve(address(hook), type(uint256).max);
        vat.init(dilk, self, dutag);
        hook.link(dilk, address(dai));
        hook.grant(address(dai));
        vat.filk(dilk, 'hook', uint(bytes32(bytes20(address(hook)))));
        vat.filk(dilk, bytes32('chop'), RAD);
        vat.filk(dilk, bytes32('line'), init_mint * 10 * RAD);
        vat.filk(dilk, bytes32('fee'),  1000000001546067052200000000);  // 5%
        // feedpush(dutag, bytes32(RAY), block.timestamp + 1000);
        hook.list(DAI, true);
        vow.grant(DAI);
    }

    function init_gold() public {
        gold = Gem(address(gemfab.build(bytes32("Gold"), bytes32("GOLD"))));
        gold.mint(self, init_mint * WAD);
        gold.approve(address(hook), type(uint256).max);
        vat.init(gilk, self, grtag);
        hook.link(gilk, address(gold));
        hook.grant(address(gold));
        vat.filk(gilk, 'hook', uint(bytes32(bytes20(address(hook)))));
        // todo fix other chops, should be rays
        vat.filk(gilk, bytes32('chop'), RAY);
        vat.filk(gilk, bytes32('line'), init_mint * 10 * RAD);
        vat.filk(gilk, bytes32('fee'),  1000000001546067052200000000);  // 5%
        feedpush(grtag, bytes32(RAY), block.timestamp + 1000);
        hook.list(address(gold), true);
        agold = address(gold);
        vow.grant(agold);
    }

    function init_ruby() public {
        ruby = Gem(address(gemfab.build(bytes32("Ruby"), bytes32("RUBY"))));
        ruby.mint(self, init_mint * WAD);
        ruby.approve(address(hook), type(uint256).max);
        vat.init(rilk, self, rtag);
        hook.link(rilk, address(ruby));
        hook.grant(address(ruby));
        vat.filk(rilk, 'hook', uint(bytes32(bytes20(address(hook)))));
        vat.filk(rilk, bytes32('chop'), RAD);
        vat.filk(rilk, bytes32('line'), init_mint * 10 * RAD);
        vat.filk(rilk, bytes32('fee'),  1000000001546067052200000000);  // 5%
        feedpush(rtag, bytes32(RAY), block.timestamp + 1000);
        hook.list(address(ruby), true);
        aruby = address(ruby);
        vow.grant(aruby);
    }

    function curb(address g, uint vel, uint rel, uint bel, uint cel, uint del) internal {
        vow.pair(g, 'vel', vel);
        vow.pair(g, 'rel', rel);
        vow.pair(g, 'bel', bel);
        vow.pair(g, 'cel', cel);
        vow.pair(g, 'del', del);
    }
}
