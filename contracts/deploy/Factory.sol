// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is disstributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.6.12;

// Builds new LiquidityPools, logging their addresses and providing `isLiquidityPool(address) -> (bool)`

import "../base/LiquidityPool.sol";

contract Factory is BBronze {
    event LOG_NEW_POOL(
        address indexed caller,
        address indexed pool
    );

    event LOG_BLABS(
        address indexed caller,
        address indexed blabs
    );

    event LOG_ROUTER(
        address indexed caller,
        address indexed router
    );

    mapping(address=>bool) private _isLiquidityPool;

    function isLiquidityPool(address b)
        external view returns (bool)
    {
        return _isLiquidityPool[b];
    }

    function newLiquidityPool()
        external
        returns (LiquidityPool)
    {
        LiquidityPool lpool = new LiquidityPool();
        _isLiquidityPool[address(lpool)] = true;
        emit LOG_NEW_POOL(msg.sender, address(lpool));
        lpool.setController(msg.sender);
        return lpool;
    }

    address private _blabs;
    address private _swapRouter;
    address private _managerOwner;
    constructor() public {
        _blabs = msg.sender;
    }



    function getBLabs()
        external view
        returns (address)
    {
        return _blabs;
    }

    function setBLabs(address b)
        external
    {
        require(msg.sender == _blabs, "ERR_NOT_BLABS");
        emit LOG_BLABS(msg.sender, b);
        _blabs = b;
    }

    function getSwapRouter()
        external view
        returns (address)
    {
        return _swapRouter;
    }

    function setSwapRouter(address router)
        external
    {
        require(msg.sender == _blabs, "ERR_NOT_BLABS");
        emit LOG_ROUTER(msg.sender, router);
        _swapRouter = router;
    }

    function collect(IERC20 token)
        external 
    {
        require(msg.sender == _blabs, "ERR_NOT_BLABS");
        uint collected = token.balanceOf(address(this));
        bool xfer = token.transfer(_blabs, collected);
        require(xfer, "ERR_ERC20_FAILED");
    }
}