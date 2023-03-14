// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.19;

import { ISwapRouter } from './TEMPinterface.sol';
import './mixin/ward.sol';

abstract contract UniSwapper is Ward {
    struct Path {
        bytes fore;
        bytes rear;
    }
    enum SwapKind {EXACT_IN, EXACT_OUT}
    // tokIn -> kind -> Path
    mapping(address tokIn => mapping(address tokOut => Path)) public paths;

    uint256 public constant SWAP_ERR = type(uint256).max;

    ISwapRouter public router;

    function setPath(address tokIn, address tokOut, bytes calldata fore, bytes calldata rear)
      _ward_ external {
        Path storage path = paths[tokIn][tokOut];
        path.fore = fore;
        path.rear = rear;
    }

    function setSwapRouter(address r)
      _ward_ external {
        router = ISwapRouter(r);
    }

    function _swap(address tokIn, address tokOut, address receiver, SwapKind kind, uint amt, uint limit)
            internal returns (uint256 result) {
        if (kind == SwapKind.EXACT_IN) {
            ISwapRouter.ExactInputParams memory params =
                ISwapRouter.ExactInputParams({
                    path : paths[tokIn][tokOut].fore,
                    recipient : receiver,
                    deadline : block.timestamp,
                    amountIn : amt,
                    amountOutMinimum : limit
                });
            try router.exactInput(params) returns (uint res) {
                result = res;
            } catch {
                result = SWAP_ERR;
            }
        } else {
            ISwapRouter.ExactOutputParams memory params =
                ISwapRouter.ExactOutputParams({
                    path: paths[tokIn][tokOut].rear,
                    recipient: receiver,
                    deadline: block.timestamp,
                    amountOut: amt,
                    amountInMaximum: limit
                });

            try router.exactOutput(params) returns (uint res) {
                result = res;
            } catch {
                result = SWAP_ERR;
            }
        }
    }
}
