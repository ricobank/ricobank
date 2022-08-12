import { Feedbase } from 'feedbase/Feedbase.sol';
import { Gem, GemFab } from 'gemfab/gem.sol';

import { GemFabLike } from 'src/ball.sol';
import { Ball } from 'src/ball.sol';

contract SetUp {
    function setUp() public {
        Feedbase feedbase = new Feedbase();
        GemFab gemfab = new GemFab();
        Ball ball = new Ball(GemFabLike(address(gemfab)), address(feedbase));
    }
}