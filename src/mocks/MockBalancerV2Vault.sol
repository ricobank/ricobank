// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021 the bank

pragma solidity 0.8.15;

interface IAsset {}
interface BalancerV2Types {
    enum SwapKind { GIVEN_IN, GIVEN_OUT }
    struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        IAsset assetIn;
        IAsset assetOut;
        uint256 amount;
        bytes userData;
    }
    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }
}

interface IERC20 {
    function transferFrom(address, address, uint256) external;
    function transfer(address, uint256) external;
    function balanceOf(address) external returns (uint256);
}

import '../mixin/math.sol';
import '../mixin/ward.sol';
import 'hardhat/console.sol';
import {GemLike} from '../abi.sol';
contract MockBalancerV2Vault is Ward, Math, BalancerV2Types {
    // in -> out -> amtOut/amtIn (wad)
    mapping(address=>mapping(address=>uint256)) public prices;
    function swap(
        SingleSwap calldata singleSwap,
        FundManagement calldata funds,
        uint256 limit,
        uint256 deadline
    ) external returns (uint256 amtOut) {
        require(singleSwap.kind == SwapKind.GIVEN_IN, '1');
        require(!funds.fromInternalBalance, '2');
        require(!funds.toInternalBalance, '3');
        require(singleSwap.amount > 0, '4');
        require(block.timestamp <= deadline, '5');
        require(funds.sender == msg.sender, '6');
        require(limit == 0, '7');

        address addrIn  = address(singleSwap.assetIn);
        address addrOut = address(singleSwap.assetOut);
        uint256 balIn   = IERC20(addrIn).balanceOf(address(this));
        uint256 balOut  = IERC20(addrOut).balanceOf(address(this));
        uint256 price   = prices[addrIn][addrOut];
        require( price != 0, '8' );

        amtOut          = wmul(singleSwap.amount, price);
        IERC20(addrIn).transferFrom(funds.sender, address(this), singleSwap.amount);
        IERC20(addrOut).transfer(funds.recipient, amtOut);
    }

    function setPrice(address addrIn, address addrOut, uint256 wad) external _ward_ {
        prices[addrIn][addrOut] = wad;
    }
}
