// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import '../src/mixin/math.sol';
import { BalancerFlower } from '../src/flow.sol';
import { Feedbase } from '../lib/feedbase/src/Feedbase.sol';
import { Medianizer } from '../lib/feedbase/src/Medianizer.sol';
import { GemFab, Gem } from '../lib/gemfab/src/gem.sol';
import { GemFabLike } from '../src/ball.sol';
import { Ball } from '../src/ball.sol';
import { Vat } from '../src/vat.sol';
import { Vow } from '../src/vow.sol';
import { Vox } from '../src/vox.sol';

import { BalSetUp } from "./BalHelper.sol";
import { UniSetUp } from "./UniHelper.sol";

interface WethLike {
    function deposit() external payable;
    function approve(address, uint) external;
    function allowance(address, address) external returns (uint);
    function balanceOf(address) external returns (uint);
}

abstract contract RicoSetUp is BalSetUp, Math {
    address constant public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    bytes32 constant public gilk = "gold";
    bytes32 constant public wilk = "weth";
    bytes32 constant public rilk = "ruby";
    bytes32 constant public gtag = "goldusd";
    bytes32 constant public wtag = "wethusd";
    bytes32 constant public rtag = "rubyusd";
    uint256 constant public init_mint = 10000;
    uint256 constant public BANKYEAR = (365 * 24 + 6) * 3600;
    address public immutable azero = address(0);
    address public immutable self = address(this);

    BalancerFlower public flow;
    GemFabLike public gemfab;
    Ball     public ball;
    Feedbase public feed;
    Gem      public gold;
    Gem      public ruby;
    Gem      public rico;
    Gem      public risk;
    Vat      public vat;
    Vow      public vow;
    Vox      public vox;
    address  public arico;
    address  public arisk;
    address  public agold;
    address  public aruby;
    address  public avat;
    address  public avow;
    address  public avox;
    Medianizer mdn;

    function make_bank() public {
        make_bank(self);
    }

    function feedpush(bytes32 tag, bytes32 val, uint ttl) internal {
        feed.push(tag, val, ttl);
        mdn.poke(tag);
    }

    function make_bank(address wethsrc) public {
        feed = new Feedbase();
        gemfab = GemFabLike(address(new GemFab()));

        ball = new Ball(gemfab, address(feed), WETH, wethsrc, BAL_W_P_F, BAL_VAULT);

        rico = Gem(ball.rico());
        risk = Gem(ball.risk());
        vat  = Vat(address(ball.vat()));
        vow  = Vow(address(ball.vow()));
        vox  = Vox(address(ball.vox()));
        flow = ball.flow();

        avat  = address(vat);
        avow  = address(vow);
        avox  = address(vox);
        arico = address(rico);
        arisk = address(risk);

        rico.approve(avat, type(uint256).max);

        (,,address fsrc,,,,,,,,,) = vat.ilks(wilk);
        mdn = Medianizer(fsrc);
    }

    function init_gold() public {
        gold = Gem(address(gemfab.build(bytes32("Gold"), bytes32("GOLD"))));
        gold.mint(self, init_mint * WAD);
        gold.approve(avat, type(uint256).max);
        vat.init(gilk, address(gold), self, gtag);
        vat.filk(gilk, bytes32('chop'), RAD);
        vat.filk(gilk, bytes32('line'), init_mint * 10 * RAD);
        vat.filk(gilk, bytes32('fee'),  1000000001546067052200000000);  // 5%
        feedpush(gtag, bytes32(RAY), block.timestamp + 1000);
        vat.list(address(gold), true);
        agold = address(gold);
        vow.grant(agold);
    }

    function init_ruby() public {
        ruby = Gem(address(gemfab.build(bytes32("Ruby"), bytes32("RUBY"))));
        ruby.mint(self, init_mint * WAD);
        ruby.approve(avat, type(uint256).max);
        vat.init(rilk, address(ruby), self, rtag);
        vat.filk(rilk, bytes32('chop'), RAD);
        vat.filk(rilk, bytes32('line'), init_mint * 10 * RAD);
        vat.filk(rilk, bytes32('fee'),  1000000001546067052200000000);  // 5%
        feedpush(rtag, bytes32(RAY), block.timestamp + 1000);
        vat.list(address(ruby), true);
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
