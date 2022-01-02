/// SPDX-License-Identifier: AGPL-3.0-or-later

contract Lock {
    uint256 private immutable LOCKED = 1;
    uint256 private immutable UNLOCKED = 2;
    uint256 private _LOCK_STATUS = 2; // UNLOCKED

    error ErrMutex();

    modifier locks() {
        if (_LOCK_STATUS != UNLOCKED) revert ErrMutex();
        _LOCK_STATUS = LOCKED;
        _;
        _LOCK_STATUS = UNLOCKED;
    }
}
