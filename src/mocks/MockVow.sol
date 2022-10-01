// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.15;

import '../vow.sol';

contract MockVow is Vow {
        receive() external payable {}
}
