// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.15;

import '../src/mixin/math.sol';
import { Feedbase } from '../lib/feedbase/src/Feedbase.sol';
import { GemFab } from '../lib/gemfab/src/gem.sol';
import { GemFabLike } from '../src/ball.sol';
import { Ball } from '../src/ball.sol';
import { DockLike } from '../src/abi.sol';
import { GemLike } from '../src/abi.sol';
import { VatLike } from '../src/abi.sol';

interface WethLike is GemLike {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

abstract contract RicoSetUp is Math {
    address constant public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    bytes32 constant public gilk = "gold";
    bytes32 constant public rilk = "ruby";
    uint256 constant public init_mint = 10000;
    address public immutable self = address(this);

    Ball public ball;
    DockLike public dock;
    GemFabLike public gemfab;
    GemLike public gold;
    GemLike public ruby;
    GemLike public rico;
    GemLike public risk;
    VatLike public vat;
    address public adock;
    address public arico;
    address public agold;

    address public avat;

    function make_bank() public {
        Feedbase feedbase = new Feedbase();
        gemfab = GemFabLike(address(new GemFab()));
        ball = new Ball(gemfab, address(feedbase));

        dock = DockLike(address(ball.dock()));
        rico = GemLike(address(ball.rico()));
        risk = GemLike(address(ball.risk()));
        vat  = VatLike(address(ball.vat()));

        avat  = address(vat);
        adock = address(dock);
        arico = address(rico);

        dock.bind_joy(address(vat), address(rico), true);
    }

    function init_gold() public {
        gold = GemLike(address(gemfab.build(bytes32("Gold"), bytes32("GOLD"))));
        gold.mint(self, init_mint * WAD);
        gold.approve(address(dock), type(uint256).max);
        vat.init(gilk, address(gold));
        vat.filk(gilk, bytes32("line"), init_mint * 10 * RAD);
        vat.plot(gilk, RAY);
        dock.bind_gem(avat, gilk, address(gold));
        dock.list(address(gold), true);
        agold = address(gold);
    }

    function init_ruby() public {
        ruby = GemLike(address(gemfab.build(bytes32("Ruby"), bytes32("RUBY"))));
        ruby.mint(self, init_mint * WAD);
        ruby.approve(address(dock), type(uint256).max);
        vat.init(rilk, address(ruby));
        vat.filk(rilk, bytes32("line"), init_mint * 10 * RAD);
        vat.plot(rilk, RAY);
        dock.bind_gem(avat, rilk, address(ruby));
        dock.list(address(ruby), true);
    }
}
