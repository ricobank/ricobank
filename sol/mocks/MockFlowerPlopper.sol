// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021 the bank

pragma solidity 0.8.9;

import 'hardhat/console.sol';

import '../flow.sol';

contract MockFlowerPlopper is Math, BalancerSwapper, Flipper
{
    address public RICO;
    address public vow;

    function flip(bytes32 ilk, address urn, address gem, uint ink, uint bill) external {
        trade(gem, RICO, SwapKind.GIVEN_OUT, bill);
        uint refund = GemLike(gem).balanceOf(address(this));
        GemLike(gem).transfer(vow, refund);
        Plopper(vow).plop(ilk, urn, refund);
    }

    function trade(address tokIn, address tokOut, SwapKind kind, uint amt) internal {
        SingleSwap memory ss = SingleSwap({
        poolId: pools[tokIn][tokOut],
        kind: kind,
        assetIn: IAsset(tokIn),
        assetOut: IAsset(tokOut),
        amount: amt,
        userData: ""
        });
        FundManagement memory fm = FundManagement({
        sender: address(this),
        fromInternalBalance: false,
        recipient: payable(vow),
        toInternalBalance: false
        });
        bvault.swap(ss, fm, type(uint256).max, block.timestamp);
    }

    function approve_gem(address gem) external {
        GemLike(gem).approve(address(bvault), type(uint256).max);
        GemLike(gem).approve(vow, type(uint256).max);
    }

    function file(bytes32 key, address val) external {
        ward();
        if (key == "rico") {RICO = val;
        } else if (key == "vow") {vow = val;
        } else {revert("ERR_FILE_KEY");}
    }
}
