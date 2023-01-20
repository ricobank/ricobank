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

contract Ball {
    error ErrGFHash();
    error ErrFBHash();

    bytes32 internal constant WILK = "weth";
    bytes32 internal constant WTAG = "wethusd";
    uint256 internal constant HALF = 5 * 10**17;
    uint256 internal constant FEE  = 3 * 10**15;
    uint256 internal constant RAY  = 10 ** 27;
    uint256 internal constant RAD  = 10 ** 45;
    address public rico;
    address public risk;
    BalancerFlower public flow;
    Vat public vat;
    Vow public vow;
    Vox public vox;

    bytes32 public immutable gemFabHash = 0x3d4566ab42065aeb1aa89c121b828f7cce52f908859617efe6f5c85247df2b3b;
    bytes32 public immutable feedbaseHash = 0x444a69f35a859778fe48a0d50c8c24a3d891d8e7287c6db0df0d17f9fcb9c71b;

    constructor(GemFabLike gemfab, address feedbase, address weth, address wethsrc, address poolfab, address bal_vault) {
//        bytes32 codeHash;
//        assembly { codeHash := extcodehash(gemfab) }
//        if (gemFabHash != codeHash) revert ErrGFHash();
//        assembly { codeHash := extcodehash(feedbase) }
//        if (feedbaseHash != codeHash) revert ErrFBHash();

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
        vat.init(WILK, weth, wethsrc, WTAG);
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
        GemLike(risk).ward(address(this), false);

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
        address risk_pool = WeightedPoolFactoryLike(poolfab).create(
            '50 RICO 50 RISK', 'B-50RICO-50RISK', risk_tokens, weights, FEE, roll);
        address weth_pool = WeightedPoolFactoryLike(poolfab).create(
            '50 RICO 50 WETH', 'B-50RICO-50WETH', weth_tokens, weights, FEE, roll);
        bytes32 risk_pool_id = Pool(risk_pool).getPoolId();
        bytes32 weth_pool_id = Pool(weth_pool).getPoolId();
        flow.setPool(rico, risk, risk_pool_id);
        flow.setPool(risk, rico, risk_pool_id);
        flow.setPool(weth, rico, weth_pool_id);
        flow.setVault(bal_vault);
        vow.grant(rico);
        vow.grant(risk);
        vow.grant(weth);

        flow.give(roll);
        vow.give(roll);
        vox.give(roll);
        vat.give(roll);
    }
}
