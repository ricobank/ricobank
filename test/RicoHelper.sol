// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.15;

import '../src/mixin/math.sol';
import { BalancerFlower } from '../src/flow.sol';
import { Feedbase } from '../lib/feedbase/src/Feedbase.sol';
import { GemFab } from '../lib/gemfab/src/gem.sol';
import { GemFabLike } from '../src/ball.sol';
import { Ball } from '../src/ball.sol';
import { GemLike } from '../src/abi.sol';
import { Vat } from '../src/vat.sol';
import { Vow } from '../src/vow.sol';

interface WethLike is GemLike {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

abstract contract RicoSetUp is Math {
    address constant public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    bytes32 constant public gilk = "gold";
    bytes32 constant public rilk = "ruby";
    bytes32 constant public gtag = "goldusd";
    bytes32 constant public rtag = "rubyusd";
    uint256 constant public init_mint = 10000;
    address public immutable self = address(this);

    BalancerFlower public flow;
    GemFabLike public gemfab;
    Ball     public ball;
    Feedbase public feed;
    GemLike  public gold;
    GemLike  public ruby;
    GemLike  public rico;
    GemLike  public risk;
    Vat      public vat;
    Vow      public vow;
    address  public arico;
    address  public arisk;
    address  public agold;
    address  public aruby;
    address  public avat;

    function make_bank() public {
        feed = new Feedbase();
        gemfab = GemFabLike(address(new GemFab()));
        ball = new Ball(gemfab, address(feed));

        rico = GemLike(address(ball.rico()));
        risk = GemLike(address(ball.risk()));
        vat  = Vat(address(ball.vat()));
        vow  = Vow(payable(address(ball.vow())));
        flow = ball.flow();

        avat  = address(vat);
        arico = address(rico);
        arisk = address(risk);

        rico.approve(avat, type(uint256).max);
    }

    function init_gold() public {
        gold = GemLike(address(gemfab.build(bytes32("Gold"), bytes32("GOLD"))));
        gold.mint(self, init_mint * WAD);
        gold.approve(avat, type(uint256).max);
        vat.init(gilk, address(gold), self, gtag);
        vat.filk(gilk, bytes32('chop'), RAD);
        vat.filk(gilk, bytes32("line"), init_mint * 10 * RAD);
        vat.filk(gilk, bytes32('duty'), 1000000001546067052200000000);  // 5%
        feed.push(gtag, bytes32(RAY), block.timestamp + 1000);
        vat.list(address(gold), true);
        agold = address(gold);
        vow.grant(agold);
    }

    function init_ruby() public {
        ruby = GemLike(address(gemfab.build(bytes32("Ruby"), bytes32("RUBY"))));
        ruby.mint(self, init_mint * WAD);
        ruby.approve(avat, type(uint256).max);
        vat.init(rilk, address(ruby), self, rtag);
        vat.filk(rilk, bytes32('chop'), RAD);
        vat.filk(rilk, bytes32("line"), init_mint * 10 * RAD);
        vat.filk(rilk, bytes32('duty'), 1000000001546067052200000000);  // 5%
        feed.push(rtag, bytes32(RAY), block.timestamp + 1000);
        vat.list(address(ruby), true);
        aruby = address(ruby);
        vow.grant(aruby);
    }
}
