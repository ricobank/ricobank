/// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.19;

contract Lock {
    uint256 private constant LOCKED = 1;
    uint256 private constant UNLOCKED = 2;
    uint256 private _LOCK_STATUS = 2; // UNLOCKED

    error ErrLock();

    modifier _lock_ {
        if (_LOCK_STATUS != UNLOCKED) revert ErrLock();
        _LOCK_STATUS = LOCKED;
        _;
        _LOCK_STATUS = UNLOCKED;
    }
}
