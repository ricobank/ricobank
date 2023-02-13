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
import {TWAP} from "../lib/feedbase/src/combinators/TWAP.sol";
import {Progression} from "../lib/feedbase/src/combinators/Progression.sol";
import {ChainlinkAdapter} from "../lib/feedbase/src/adapters/ChainlinkAdapter.sol";
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
    error ErrGFHash();
    error ErrFBHash();

    bytes32 internal constant RICO_DAI_TAG = "ricodai";
    bytes32 internal constant DAI_RICO_TAG = "dairico";
    bytes32 internal constant XAU_USD_TAG = "xauusd";
    bytes32 internal constant XAU_DAI_TAG = "xauusd";
    bytes32 internal constant DAI_USD_TAG = "daiusd";
    bytes32 internal constant XAU_RICO_TAG = "xaurico";
    bytes32 internal constant REF_RICO_TAG = "refrico";
    bytes32 internal constant RICO_REF_TAG = "ricoref";
    bytes32 internal constant RTAG = "ricousd";
    uint256 internal constant BANKYEAR = ((365 * 24) + 6) * 3600;
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


    bytes32 risk_pool_id;
    address risk_pool;

    IUniswapV3Pool public ricodai;
    IUniswapV3Pool public ricorisk;

    Medianizer mdn;
    UniswapV3Adapter public adapt;
    Divider public divider;
    ChainlinkAdapter public cladapt;
    Progression public progression;
    TWAP public twap;

    address constant DAI_USD_AGG = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address constant XAU_USD_AGG = 0x214eD9Da11D2fbe465a6fc601a91E62EbEc1a0D6;

    struct BallArgs {
        address gemfab;
        address feedbase;
        address weth;
        address factory;
        address router;
        uint    sqrtpar;
        bytes32[] ilks;
        address[] gems;
        address[] pools;
    }

    constructor(BallArgs memory args) payable {
        router = args.router;
        factory = args.factory;
        require(args.ilks.length == args.gems.length, "ilks and gems don't match");
        require(args.ilks.length == args.pools.length, "ilks and pools don't match");
        address roll = msg.sender;
        flow = new UniFlower();

        rico = address(GemFabLike(args.gemfab).build(bytes32("Rico"), bytes32("RICO")));
        risk = address(GemFabLike(args.gemfab).build(bytes32("Rico Riskshare"), bytes32("RISK")));

        vow = new Vow();
        vox = new Vox();
        vat = new Vat();

        vat.prod(args.sqrtpar ** 2 / RAY);

        vow.link('flow', address(flow));
        vow.link('vat',  address(vat));
        vow.link('RICO', rico);
        vow.link('RISK', risk);

        vox.link('fb',  args.feedbase);
        vox.link('tip', roll);
        vox.link('vat', address(vat));

        vat.file('ceil',  100000e45);
        vat.link('feeds', args.feedbase);
        vat.link('rico',  address(rico));

        vow.pair(address(risk), 'vel', 1e18);
        vow.pair(address(risk), 'rel', 1e12);
        vow.pair(address(risk), 'bel', 0);
        vow.pair(address(risk), 'cel', 600);
        //vow.pair(address(risk), 'del', 1);
        vow.ward(address(flow), true);

        vat.ward(address(vow),  true);
        vat.ward(address(vox),  true);

        mdn = new Medianizer(args.feedbase);
        uint160 sqrtparx96 = uint160(args.sqrtpar * (2 ** 96) / RAY);
        ricodai = create_pool(PoolArgs(
            Asset(rico, 0), Asset(DAI, 0), 500, sqrtparx96, 0, 0, 0
        ));
 
        adapt = new UniswapV3Adapter(Feedbase(args.feedbase));
        divider = new Divider(args.feedbase, RAY);
        flow.setSwapRouter(args.router);
        for (uint i = 0; i < args.ilks.length; i++) {
            bytes32 ilk = args.ilks[i];
            address gem = args.gems[i];
            address pool = args.pools[i];
            vat.init(ilk, gem, address(mdn), concat(ilk, 'rico'));
            // TODO ilk config values, do we need them in arguments?
            vat.filk(ilk, 'chop', RAD);
            vat.filk(ilk, 'dust', 90 * RAD);
            vat.filk(ilk, 'fee',  1000000001546067052200000000);  // 5%
            vat.filk(ilk, 'line', 100000 * RAD);
            vat.filk(ilk, 'liqr', RAY);
            vat.list(gem, true);
            vow.grant(gem);

            address [] memory addr3 = new address[](3);
            uint24  [] memory fees2 = new uint24 [](2);
            addr3[0] = gem;
            addr3[1] = DAI;
            addr3[2] = rico;
            fees2[0] = 3000;
            fees2[1] = 500;
            (bytes memory f, bytes memory r) = create_path(addr3, fees2);
            flow.setPath(gem, rico, f, r);
            vow.pair(gem, "vel", WAD / 1000);
            vow.pair(gem, "rel", WAD);
            vow.pair(gem, "bel", block.timestamp);
            vow.pair(gem, "cel", 1);
            vow.pair(gem, "del", WAD / 100);

            // quarter day twap range, 1hr ttl
            adapt.setConfig(
                concat(ilk, 'dai'),
                UniswapV3Adapter.Config(pool, 20000, BANKYEAR / 4, true)
            );

            address[] memory ss = new address[](2);
            bytes32[] memory ts = new bytes32[](2);
            ss[0] = address(adapt); ts[0] = concat(ilk, 'dai');
            ss[1] = address(adapt); ts[1] = RICO_DAI_TAG;
            divider.setConfig(concat(ilk, 'rico'), Divider.Config(ss, ts));
            vow.grant(gem);
        }

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
        // todo ramp config
        vow.pair(risk, "vel", WAD);
        vow.pair(risk, "rel", WAD);
        vow.pair(risk, "bel", block.timestamp);
        vow.pair(risk, "cel", 1);
        vow.pair(risk, "del", WAD / 100);
        vow.pair(address(0), "vel", WAD);
        vow.pair(address(0), "rel", WAD);
        vow.pair(address(0), "bel", block.timestamp);
        vow.pair(address(0), "cel", 1);
        vow.pair(address(0), "del", WAD / 100);

        flow.setPath(rico, risk, rear, fore);
        vow.pair(rico, "vel", WAD);
        vow.pair(rico, "rel", WAD);
        vow.pair(rico, "bel", block.timestamp);
        vow.pair(rico, "cel", 1);
        vow.pair(rico, "del", WAD / 100);

        vow.grant(rico);
        vow.grant(risk);

        flow.give(roll);
        vow.give(roll);
        vat.give(roll);

        ricorisk = create_pool(PoolArgs(
            Asset(rico, 0), Asset(risk, 0), RISK_FEE, risk_price, 0, 0, 0
        ));

        adapt.setConfig(
            RICO_DAI_TAG,
            UniswapV3Adapter.Config(address(ricodai), 20000, BANKYEAR / 4, DAI < rico)
        );
        adapt.ward(roll, true);
        adapt.ward(address(this), false);

        // dai/rico = 1 / (rico/dai)
        address[] memory sources = new address[](2);
        bytes32[] memory tags    = new bytes32[](2);
        Feedbase(args.feedbase).push(bytes32("ONE"), bytes32(RAY), type(uint).max);
        sources[0] = address(this); tags[0] = bytes32("ONE");
        sources[1] = address(adapt); tags[1] = RICO_DAI_TAG;
        divider.setConfig(DAI_RICO_TAG, Divider.Config(sources, tags));

        //                         rico/dai        dai/rico
        // Rico/Dai AMM -------------|-------inv------|
        // XAU/USD CL -- divider-->divider-->twap-->prog-->inv-->RICO/REF
        // DAI/USD CL ----|
        cladapt = new ChainlinkAdapter(args.feedbase);
        cladapt.setConfig(XAU_USD_TAG, ChainlinkAdapter.Config(XAU_USD_AGG, BANKYEAR, RAY));
        cladapt.setConfig(DAI_USD_TAG, ChainlinkAdapter.Config(DAI_USD_AGG, BANKYEAR, RAY));
        sources[0] = address(cladapt); tags[0] = XAU_USD_TAG;
        sources[1] = address(cladapt); tags[1] = DAI_USD_TAG;
        divider.setConfig(XAU_DAI_TAG, Divider.Config(sources, tags));
        sources[0] = address(divider); tags[0] = XAU_DAI_TAG;
        sources[1] = address(adapt); tags[1] = RICO_DAI_TAG;
        divider.setConfig(XAU_RICO_TAG, Divider.Config(sources, tags));

        twap = new TWAP(args.feedbase);
        twap.setConfig(XAU_RICO_TAG, TWAP.Config(address(divider), 10000, BANKYEAR));
        
        progression = new Progression(Feedbase(args.feedbase));
        progression.setConfig(REF_RICO_TAG, Progression.Config(
            address(divider), DAI_RICO_TAG,
            address(twap),    XAU_RICO_TAG,
            // TODO discuss whether 10y is appropriate, decide on period
            block.timestamp,  block.timestamp + BANKYEAR * 10, BANKYEAR / 12
        ));

        sources[0] = address(this); tags[0] = bytes32("ONE");
        sources[1] = address(progression); tags[1] = REF_RICO_TAG;
        divider.setConfig(RICO_REF_TAG, Divider.Config(sources, tags));

        divider.ward(roll, true);
        divider.ward(address(this), false);

        // median([(ddai / dweth) / (ddai / drico)]) == drico / dweth
        sources = new address[](1);
        sources[0] = address(divider);
        mdn.setSources(sources);
        mdn.setOwner(roll);

        // vox needs rico-dai
        vox.link('tip', address(mdn));
        vox.file('tag', RICO_REF_TAG);
        vox.give(roll);
    }

    function concat(bytes32 a, bytes32 b) internal pure returns (bytes32 res) {
        uint i;
        while (true) {
            if (a[i] == 0) break;
            unchecked{ i++; }
        }
        res = a | (b >> (i << 3));
    }
}
