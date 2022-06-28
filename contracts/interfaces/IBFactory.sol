// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.12;

interface IBPool {
    function rebind(address token, uint balance, uint denorm) external;
    function rebindSmart(
        address tokenA, 
        address tokenB,
        uint deltaWeight, 
        uint deltaBalance, 
        bool isSoldout,
        uint minAmountOut
    ) external;
    function setSwapFee(uint swapFee) external;
    function setUnirouter(address unirouter_) external;
    function setPublicSwap(bool publicSwap) external;
    function bind(address token, uint balance, uint denorm) external;
    function unbind(address token) external;
    function unbindPure(address token) external;
    function gulp(address token) external;
    function isBound(address token) external view returns(bool);
    function getBalance(address token) external view returns (uint);
    function totalSupply() external view returns (uint);
    function getSwapFee() external view returns (uint);
    function isPublicSwap() external view returns (bool);
    function getDenormalizedWeight(address token) external view returns (uint);
    function getTotalDenormalizedWeight() external view returns (uint);
    // solhint-disable-next-line func-name-mixedcase
    function EXIT_FEE() external view returns (uint);
 
    function calcPoolOutGivenSingleIn(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint poolSupply,
        uint totalWeight,
        uint tokenAmountIn,
        uint swapFee
    )
        external pure
        returns (uint poolAmountOut);

    function calcSingleInGivenPoolOut(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint poolSupply,
        uint totalWeight,
        uint poolAmountOut,
        uint swapFee
    )
        external pure
        returns (uint tokenAmountIn);

    function calcSingleOutGivenPoolIn(
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint poolSupply,
        uint totalWeight,
        uint poolAmountIn,
        uint swapFee
    )
        external pure
        returns (uint tokenAmountOut);

    function calcPoolInGivenSingleOut(
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint poolSupply,
        uint totalWeight,
        uint tokenAmountOut,
        uint swapFee
    )
        external pure
        returns (uint poolAmountIn);

    function getCurrentTokens()
        external view
        returns (address[] memory tokens);
}

interface IBFactory {
    function newLiquidityPool() external returns (IBPool);
    function setBLabs(address b) external;
    function collect(IBPool pool) external;
    function isBPool(address b) external view returns (bool);
    function getBLabs() external view returns (address);
    function getSwapRouter() external view returns (address);
    function getVaultAddress() external view returns (address);
    function getManagerOwner() external view returns (address);

}
interface IVault {
    function depositManagerToken(address[] calldata poolTokens,uint[] calldata tokensAmount) external;
    function depositIssueRedeemToken(address[] calldata poolTokens,uint[] calldata tokensAmount) external;
    function managerClaim(address pool) external;
    function getManagerClaimBool(address pool) external view returns(bool);
}

