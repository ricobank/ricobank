/// SPDX-License-Identifier: AGPL-3.0

// The cannonball is the canonical deployment sequence
// implemented as one big contract. You can diff more
// efficient deployment sequences against the result of
// this one.

pragma solidity 0.8.17;

import {Vat} from './vat.sol';
import {Vow} from './vow.sol';
import {Vox} from './vox.sol';
import {UniFlower} from './flow.sol';
import {Feedbase} from "../lib/feedbase/src/Feedbase.sol";
import {Divider} from "../lib/feedbase/src/combinators/Divider.sol";
import {UniswapV3Adapter} from "../lib/feedbase/src/adapters/UniswapV3Adapter.sol";
import {Medianizer} from "../lib/feedbase/src/Medianizer.sol";
import {Math} from '../src/mixin/math.sol';
import { Asset, UniSetUp, PoolArgs } from "../test/UniHelper.sol";
import { IUniswapV3Pool } from "../src/TEMPinterface.sol";

interface GemFabLike {
    function build(
        bytes32 name,
        bytes32 symbol
    ) payable external returns (GemLike);
}

interface GemLike {
    function ward(address usr,
        bool authed
    ) payable external;
}

contract Ball is Math, UniSetUp {
    bytes32 internal constant WILK = "weth";
    bytes32 internal constant WTAG = "wethusd";
    bytes32 internal constant WRTAG = "wethrico";
    bytes32 internal constant RTAG = "ricousd";
    uint160 internal constant init_sqrtparx96 = 2 ** 96;
    uint160 internal constant risk_price = 2 ** 96;
    uint24  internal constant RICO_FEE = 500;
    uint24  internal constant RISK_FEE = 3000;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public rico;
    address public risk;
    UniFlower public flow;
    Vat public vat;
    Vow public vow;
    Vox public vox;

    IUniswapV3Pool public ricodai;
    IUniswapV3Pool public ricorisk;

    Medianizer mdn;
    UniswapV3Adapter public adapt;
    Divider public divider;

    constructor(GemFabLike gemfab, address feedbase, address weth, address _factory, address _router) payable {
        factory = _factory;  // todo remove test helper usage in ball and fix ball gas consumption
        router  = _router;

        address roll = msg.sender;
        flow = new UniFlower();

        rico = address(gemfab.build(bytes32("Rico"), bytes32("RICO")));
        risk = address(gemfab.build(bytes32("Rico Riskshare"), bytes32("RISK")));

        vow = new Vow();
        vox = new Vox();
        vat = new Vat();

        vow.link('flow', address(flow));
        vow.link('vat',  address(vat));
        vow.link('RICO', rico);
        vow.link('RISK', risk);

        vox.link('fb',  feedbase);
        vox.link('tip', roll);
        vox.link('vat', address(vat));

        vat.file('ceil',  100000e45);
        vat.link('feeds', feedbase);
        vat.link('rico',  address(rico));

        vow.pair(address(risk), 'vel', 1e18);
        vow.pair(address(risk), 'rel', 1e12);
        vow.pair(address(risk), 'bel', 0);
        vow.pair(address(risk), 'cel', 600);
        //vow.pair(address(risk), 'del', 1);
        vow.ward(address(flow), true);

        vat.ward(address(vow),  true);
        vat.ward(address(vox),  true);

        mdn = new Medianizer(feedbase);
        vat.init(WILK, weth, address(mdn), WRTAG);
        // TODO select weth ilk values
        vat.filk(WILK, 'chop', RAD);
        vat.filk(WILK, 'dust', 90 * RAD);
        vat.filk(WILK, 'fee',  1000000001546067052200000000);  // 5%
        vat.filk(WILK, 'line', 100000 * RAD);
        vat.filk(WILK, 'liqr', RAY);
        vat.list(weth, true);
        vow.grant(weth);

        GemLike(rico).ward(address(vat), true);
        GemLike(risk).ward(address(vow), true);

        // gem doesn't have give right now
        GemLike(rico).ward(roll, true);
        GemLike(rico).ward(address(this), false);
        GemLike(risk).ward(roll, true);
        // don't unward for risk yet...need to create pool

        // todo move out of ball for gas, either calc gemfab create address or split ball into parts if too big
        address [] memory addr2 = new address[](2);
        uint24  [] memory fees1 = new uint24 [](1);
        bytes memory fore;
        bytes memory rear;
        addr2[0] = risk;
        addr2[1] = rico;
        fees1[0] = RISK_FEE;
        (fore, rear) = create_path(addr2, fees1);
        flow.setPath(risk, rico, fore, rear);

        flow.setPath(rico, risk, rear, fore);

        address [] memory addr3 = new address[](3);
        uint24  [] memory fees2 = new uint24 [](2);
        addr3[0] = weth;
        addr3[1] = DAI;
        addr3[2] = rico;
        fees2[0] = 3000;
        fees2[1] = 500;
        (fore, rear) = create_path(addr3, fees2);
        flow.setPath(weth, rico, fore, rear);

        flow.setSwapRouter(router);

        vow.grant(rico);
        vow.grant(risk);
        vow.grant(weth);

        flow.give(roll);
        vow.give(roll);
        vat.give(roll);

        ricodai = create_pool(PoolArgs(
            Asset(rico, 0), Asset(DAI, 0), RICO_FEE, init_sqrtparx96, 0, 0, 0
        ));
        ricorisk = create_pool(PoolArgs(
            Asset(rico, 0), Asset(risk, 0), RISK_FEE, risk_price, 0, 0, 0
        ));

        adapt = new UniswapV3Adapter(Feedbase(feedbase));
        address ethdaipooladdr = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;
        // quarter day twap range, 1hr ttl
        adapt.setConfig(
            WTAG,
            UniswapV3Adapter.Config(ethdaipooladdr, 20000, 3600, true)
        );
        adapt.setConfig(
            RTAG,
            UniswapV3Adapter.Config(address(ricodai), 20000, 3600, DAI < rico)
        );
        adapt.ward(roll, true);
        adapt.ward(address(this), false);

        divider = new Divider(feedbase, RAY);
        address[] memory sources = new address[](2);
        bytes32[] memory tags    = new bytes32[](2);
        sources[0] = address(adapt); tags[0] = WTAG;
        sources[1] = address(adapt); tags[1] = RTAG;
        divider.setConfig(WRTAG, Divider.Config(sources, tags));

        // TODO - this is hack, dividing by one until medianizer has proper Config
        sources[0] = address(adapt); tags[0] = RTAG;
        sources[1] = address(this); tags[1] = bytes32("ONE");
        divider.setConfig(RTAG, Divider.Config(sources, tags));
        Feedbase(feedbase).push(bytes32("ONE"), bytes32(RAY), type(uint).max);
        divider.ward(roll, true);
        divider.ward(address(this), false);

        // median([(ddai / dweth) / (ddai / drico)]) == drico / dweth
        sources = new address[](1);
        sources[0] = address(divider);
        mdn.setSources(sources);
        mdn.setOwner(roll);

        // vox needs rico-dai
        vox.link('tip', address(mdn));
        vox.file('tag', RTAG);
        vox.give(roll);
    }
}
