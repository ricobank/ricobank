/// SPDX-License-Identifier: AGPL-3.0

// Direct read access for any storage slot

pragma solidity 0.8.15;

contract Slot {
    function _slot(bytes32 arg) internal pure returns (bytes32 ret) {
        assembly {
	    ret := mload(arg)
	}
    }
    function slot(bytes32 arg) external pure returns (bytes32 ret) {
        return _slot(arg);
    }
}
