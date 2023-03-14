/// SPDX-License-Identifier: AGPL-3.0

// The cannonball is the canonical deployment sequence
// implemented as one big contract. You can diff more
// efficient deployment sequences against the result of
// this one.

pragma solidity 0.8.19;

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
import {Pool} from '../src/mixin/pool.sol';
import { IUniswapV3Pool } from "../src/TEMPinterface.sol";
import {ERC20Hook} from './hook/ERC20hook.sol';

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

contract Ball is Math, Pool {
    error ErrGFHash();
    error ErrFBHash();

    bytes32 internal constant RICO_DAI_TAG = "ricodai";
    bytes32 internal constant DAI_RICO_TAG = "dairico";
    bytes32 internal constant USD_RICO_TAG = "usdrico";
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
    ERC20Hook public hook;

    IUniswapV3Pool public ricodai;
    IUniswapV3Pool public ricorisk;

    Medianizer public mdn;
    UniswapV3Adapter public adapt;
    Divider public divider;
    ChainlinkAdapter public cladapt;
    Progression public progression;
    TWAP public twap;
   
    address constant DAI_USD_AGG = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address constant XAU_USD_AGG = 0x214eD9Da11D2fbe465a6fc601a91E62EbEc1a0D6;
    struct IlkParams {
        bytes32 ilk;
        address gem;
        address pool;
        uint    chop;
        uint    dust;
        uint    fee;
        uint    line;
        uint    liqr;
        UniFlower.Ramp ramp;
        uint    ttl;
        uint    range;
    }

    struct BallArgs {
        address gemfab;
        address feedbase;
        address weth;
        address factory;
        address router;
        address roll;
        uint    sqrtpar;
        uint    ceil;
        uint    ricodairange;
        uint    ricodaittl;
        uint    daiusdttl;
        uint    xauusdttl;
        uint    twaprange;
        uint    twapttl;
        uint    progstart;
        uint    progend;
        uint    progperiod;
        UniFlower.Ramp ricoramp;
        UniFlower.Ramp riskramp;
        UniFlower.Ramp mintramp;
    }

    constructor(
        BallArgs    memory args,
        IlkParams[] memory ilks
    ) payable {
        address roll = args.roll;
        flow = new UniFlower();

        rico = address(GemFabLike(args.gemfab).build(bytes32("Rico"), bytes32("RICO")));
        risk = address(GemFabLike(args.gemfab).build(bytes32("Rico Riskshare"), bytes32("RISK")));

        vow = new Vow();
        vox = new Vox();
        vat = new Vat();

        hook = new ERC20Hook(address(vat), address(flow), rico);

        vat.prod(args.sqrtpar ** 2 / RAY);

        vow.link('flow', address(flow));
        vow.link('vat',  address(vat));
        vow.link('RICO', rico);
        vow.link('RISK', risk);

        vox.link('fb',  args.feedbase);
        vox.link('tip', roll);
        vox.link('vat', address(vat));

        vat.file('ceil',  args.ceil);
        vat.link('feeds', args.feedbase);
        vat.link('rico',  address(rico));

        vow.ward(address(flow), true);

        vat.ward(address(vow),  true);
        vat.ward(address(vox),  true);

        hook.ward(address(flow), true); // flowback
        hook.ward(address(vat), true);  // grabhook, frobhook

        mdn = new Medianizer(args.feedbase);

        uint160 sqrtparx96 = uint160(args.sqrtpar * (2 ** 96) / RAY);
        ricodai = create_pool(args.factory, rico, DAI, 500, sqrtparx96);

        adapt = new UniswapV3Adapter(Feedbase(args.feedbase));
        divider = new Divider(args.feedbase, RAY);
        twap = new TWAP(args.feedbase);
        flow.setSwapRouter(args.router);
        for (uint i = 0; i < ilks.length; i++) {
            IlkParams memory ilkparams = ilks[i];
            bytes32 ilk = ilkparams.ilk;
            address gem = ilkparams.gem;
            address pool = ilkparams.pool;
            vat.init(ilk, address(hook), address(mdn), concat(ilk, 'rico'));
            hook.link(ilk, gem);
            hook.grant(gem);
            vat.filk(ilk, 'chop', ilkparams.chop);
            vat.filk(ilk, 'dust', ilkparams.dust);
            vat.filk(ilk, 'fee',  ilkparams.fee);  // 5%
            vat.filk(ilk, 'line', ilkparams.line);
            vat.filk(ilk, 'liqr', ilkparams.liqr);
            hook.list(gem, true);
            vow.grant(gem);

            bytes memory f;
            bytes memory r;
            if (gem == DAI) {
                address [] memory a2 = new address[](2);
                uint24  [] memory f1 = new uint24 [](1);
                a2[0] = DAI;
                a2[1] = rico;
                f1[0] = RICO_FEE;
                (f, r) = create_path(a2, f1);
                // dai/rico feed created later
            } else {
                // To avoid STD
                {
                    address [] memory addr3 = new address[](3);
                    uint24  [] memory fees2 = new uint24 [](2);
                    addr3[0] = gem;
                    addr3[1] = DAI;
                    addr3[2] = rico;
                    fees2[0] = IUniswapV3Pool(pool).fee();
                    fees2[1] = RICO_FEE;
                    (f, r) = create_path(addr3, fees2);
                }

                adapt.setConfig(
                    concat(ilk, 'dai'),
                    UniswapV3Adapter.Config(pool, ilkparams.ttl, ilkparams.range, gem > DAI)
                );

                // TODO: Check what to use for range, ttl
                twap.setConfig(concat(ilk, 'dai'), TWAP.Config(address(adapt), args.twaprange, args.twapttl));
                address[] memory ss = new address[](2);
                bytes32[] memory ts = new bytes32[](2);
                ss[0] = address(twap); ts[0] = concat(ilk, 'dai');
                ss[1] = address(adapt); ts[1] = RICO_DAI_TAG;
                divider.setConfig(concat(ilk, 'rico'), Divider.Config(ss, ts));
            }

            flow.setPath(gem, rico, f, r);
            vow.pair(gem, "vel", ilkparams.ramp.vel);
            vow.pair(gem, "rel", ilkparams.ramp.rel);
            vow.pair(gem, "bel", ilkparams.ramp.bel);
            vow.pair(gem, "cel", ilkparams.ramp.cel);
            vow.pair(gem, "del", ilkparams.ramp.del);
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
        vow.pair(risk, "vel", args.riskramp.vel);
        vow.pair(risk, "rel", args.riskramp.rel);
        vow.pair(risk, "bel", args.riskramp.bel);
        vow.pair(risk, "cel", args.riskramp.cel);
        vow.pair(risk, "del", args.riskramp.del);
        vow.pair(address(0), "vel", args.mintramp.vel);
        vow.pair(address(0), "rel", args.mintramp.rel);
        vow.pair(address(0), "bel", args.mintramp.bel);
        vow.pair(address(0), "cel", args.mintramp.cel);
        vow.pair(address(0), "del", args.mintramp.del);

        flow.setPath(rico, risk, rear, fore);
        vow.pair(rico, "vel", args.ricoramp.vel);
        vow.pair(rico, "rel", args.ricoramp.rel);
        vow.pair(rico, "bel", args.ricoramp.bel);
        vow.pair(rico, "cel", args.ricoramp.cel);
        vow.pair(rico, "del", args.ricoramp.del);

        vow.grant(rico);
        vow.grant(risk);

        flow.give(roll);
        vow.give(roll);
        vat.give(roll);
        hook.give(roll);

        ricorisk = create_pool(args.factory, rico, risk, RISK_FEE, risk_price);
        // |------------------------->divider--------->twap------>| (usd/rico)
        // |                              |                       |
        // |                             inv                      |
        // |                              |                       |
        // |                         rico/dai                     |
        // |   Rico/Dai AMM ------------->|                       |
        // --- DAI/USD CL -- divider---->divider------>twap---->prog-->inv-->RICO/REF
        //     XAU/USD CL ----|                   ^
        //                                  (xau/rico)
        adapt.setConfig(
            RICO_DAI_TAG,
            UniswapV3Adapter.Config(address(ricodai), args.ricodairange, args.ricodaittl, DAI < rico)
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

        cladapt = new ChainlinkAdapter(args.feedbase);
        cladapt.setConfig(XAU_USD_TAG, ChainlinkAdapter.Config(XAU_USD_AGG, args.xauusdttl, RAY));
        cladapt.setConfig(DAI_USD_TAG, ChainlinkAdapter.Config(DAI_USD_AGG, args.daiusdttl, RAY));
        sources[0] = address(cladapt); tags[0] = XAU_USD_TAG;
        sources[1] = address(cladapt); tags[1] = DAI_USD_TAG;
        divider.setConfig(XAU_DAI_TAG, Divider.Config(sources, tags));
        sources[0] = address(divider); tags[0] = XAU_DAI_TAG;
        sources[1] = address(adapt); tags[1] = RICO_DAI_TAG;
        divider.setConfig(XAU_RICO_TAG, Divider.Config(sources, tags));
        sources[0] = address(divider); tags[0] = DAI_RICO_TAG;
        sources[1] = address(cladapt); tags[1] = DAI_USD_TAG;
        divider.setConfig(USD_RICO_TAG, Divider.Config(sources, tags));

        twap.setConfig(XAU_RICO_TAG, TWAP.Config(address(divider), args.twaprange, args.twapttl));
        twap.setConfig(USD_RICO_TAG, TWAP.Config(address(divider), args.twaprange, args.twapttl));
        
        progression = new Progression(Feedbase(args.feedbase));
        progression.setConfig(REF_RICO_TAG, Progression.Config(
            address(twap), USD_RICO_TAG,
            address(twap), XAU_RICO_TAG,
            // TODO discuss whether 10y is appropriate, decide on period
            args.progstart, args.progend, args.progperiod
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
