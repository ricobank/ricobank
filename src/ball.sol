/// SPDX-License-Identifier: AGPL-3.0

// The cannonball is the canonical deployment sequence
// implemented as one big contract. You can diff more
// efficient deployment sequences against the result of
// this one.

pragma solidity 0.8.17;

import {Vat} from './vat.sol';
import {Vow} from './vow.sol';
import {Vox} from './vox.sol';
import {BalancerFlower} from './flow.sol';
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

interface WeightedPoolFactoryLike {
    function create(
        string memory name,
        string memory symbol,
        address[] memory tokens,
        uint256[] memory weights,
        uint256 swapFeePercentage,
        address owner
    ) external returns (address);
}

interface Pool {
    function getPoolId() external view returns (bytes32);
}

contract Ball is Math, UniSetUp {
    error ErrGFHash();
    error ErrFBHash();

    bytes32 internal constant WILK = "weth";
    bytes32 internal constant WTAG = "wethusd";
    bytes32 internal constant WRTAG = "wethrico";
    bytes32 internal constant RTAG = "ricousd";
    uint256 internal constant HALF = 5 * 10**17;
    uint256 internal constant FEE  = 3 * 10**15;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public rico;
    address public risk;
    BalancerFlower public flow;
    Vat public vat;
    Vow public vow;
    Vox public vox;

    IUniswapV3Pool public ricoref;
    IUniswapV3Pool public riskrico;
    uint160 constant init_sqrtparx96 = 2 ** 96;

    bytes32 risk_pool_id;
    bytes32 weth_pool_id;
    address risk_pool;
    address weth_pool;

    Medianizer mdn;
    UniswapV3Adapter public adapt;
    Divider public divider;

    constructor(GemFabLike gemfab, address feedbase, address weth, address poolfab, address bal_vault) payable {
        address roll = msg.sender;
        flow = new BalancerFlower();

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

        address[] memory risk_tokens  = new address[](2);
        address[] memory weth_tokens  = new address[](2);
        uint256[] memory weights = new uint256[](2);
        if (rico < risk) {
            risk_tokens[0] = rico;
            risk_tokens[1] = risk;
        } else {
            risk_tokens[0] = risk;
            risk_tokens[1] = rico;
        }
        if (rico < weth) {
            weth_tokens[0] = rico;
            weth_tokens[1] = weth;
        } else {
            weth_tokens[0] = weth;
            weth_tokens[1] = rico;
        }
        weights[0] = HALF;
        weights[1] = HALF;
        risk_pool = WeightedPoolFactoryLike(poolfab).create(
            '50 RICO 50 RISK', 'B-50RICO-50RISK', risk_tokens, weights, FEE, roll);
        weth_pool = WeightedPoolFactoryLike(poolfab).create(
            '50 RICO 50 WETH', 'B-50RICO-50WETH', weth_tokens, weights, FEE, roll);
        risk_pool_id = Pool(risk_pool).getPoolId();
        weth_pool_id = Pool(weth_pool).getPoolId();
        flow.setPool(rico, risk, risk_pool_id);
        flow.setPool(risk, rico, risk_pool_id);
        flow.setPool(weth, rico, weth_pool_id);
        flow.setVault(bal_vault);
        vow.grant(rico);
        vow.grant(risk);
        vow.grant(weth);

        flow.give(roll);
        vow.give(roll);
        vat.give(roll);

        ricoref = create_pool(PoolArgs(
            Asset(rico, 0), Asset(DAI, 0), 500, init_sqrtparx96, 0, 0, 0
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
            UniswapV3Adapter.Config(address(ricoref), 20000, 3600, DAI < rico)
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
