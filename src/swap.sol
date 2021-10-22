// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.9;

import './mixin/ward.sol';

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

interface BalancerV2VaultLike is BalancerV2Types {
    function swap(
        SingleSwap calldata singleSwap,
        FundManagement calldata funds,
        uint256 limit,
        uint256 deadline
    ) external returns (uint256);
}

abstract contract BalancerSwapper is BalancerV2Types, Ward {

    BalancerV2VaultLike public bvault;
    // tokIn -> tokOut -> poolID
    mapping(address=>mapping(address=>bytes32)) public pools;

    function setPool(address a, address b, bytes32 id) external {
        ward();
        pools[a][b] = id;
    }

    function setVault(address v) external {
        ward();
        bvault = BalancerV2VaultLike(v);
    }

    function _swap(address tokIn, address sender, uint amt, address tokOut, address receiver) internal {
        SingleSwap memory ss = SingleSwap({
            poolId: pools[tokIn][tokOut],
            kind: SwapKind.GIVEN_IN,
            assetIn: IAsset(tokIn),
            assetOut: IAsset(tokOut),
            amount: amt,
            userData: ""
        });
        FundManagement memory fm = FundManagement({
            sender: sender,
            fromInternalBalance: false,
            recipient: payable(receiver),
            toInternalBalance: false
        });
        bvault.swap(ss, fm, 0, block.timestamp);
    }

}

