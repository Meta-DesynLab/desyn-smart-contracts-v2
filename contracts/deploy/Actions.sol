// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.12;

pragma experimental ABIEncoderV2;
import { RightsManager } from "../libraries/RightsManager.sol";

abstract contract ERC20 {
    function approve(address spender, uint amount) external virtual returns (bool);
    function transfer(address dst, uint amt) external virtual returns (bool);
    function transferFrom(address sender, address recipient, uint amount) external virtual returns (bool);
    function balanceOf(address whom) external view virtual returns (uint);
    function allowance(address, address) external view virtual returns (uint);
}

abstract contract DesynOwnable {
    function setController(address controller) external virtual;
}

abstract contract AbstractPool is ERC20, DesynOwnable {
    function setSwapFee(uint swapFee) external virtual;
    function setPublicSwap(bool public_) external virtual;
    
    function joinPool(uint poolAmountOut, uint[] calldata maxAmountsIn) external virtual;
}

abstract contract LiquidityPoolActions is AbstractPool {
    function finalize() external virtual;
    function bind(address token, uint balance, uint denorm) external virtual;
    function rebind(address token, uint balance, uint denorm) external virtual;
    function unbind(address token) external virtual;
    function isBound(address t) external view virtual returns (bool);
    function getCurrentTokens() external view virtual returns (address[] memory);
    function getFinalTokens() external view virtual returns(address[] memory);
    function getBalance(address token) external view virtual returns (uint);
}

abstract contract FactoryActions {
    function newLiquidityPool() external virtual returns (LiquidityPoolActions);
}

abstract contract IConfigurableRightsPool is AbstractPool {
    enum Etypes { OPENED, CLOSED }
    enum Period { HALF, ONE, TWO }

    struct PoolParams {
        string poolTokenSymbol;
        string poolTokenName;
        address[] constituentTokens;
        uint[] tokenBalances;
        uint[] tokenWeights;
        uint swapFee;
        uint managerFee;
        uint redeemFee;
        uint issueFee;
        Etypes etype;
    }

    struct CrpParams {
        uint initialSupply;
        uint collectPeriod;
        Period period;
    }

    function createPool(
        uint initialSupply, uint collectPeriod, Period period
    ) external virtual;
    function createPool(uint initialSupply) external virtual;
    function setCap(uint newCap) external virtual;
    function rebalance(address tokenA, address tokenB, uint deltaWeight, uint minAmountOut) external virtual;
    function commitAddToken(address token, uint balance, uint denormalizedWeight) external virtual;
    function applyAddToken() external virtual;
    function whitelistLiquidityProvider(address provider) external virtual;
    function removeWhitelistedLiquidityProvider(address provider) external virtual;
    function bPool() external view virtual returns (LiquidityPoolActions);
}

abstract contract ICRPFactory {
    function newCrp(
        address factoryAddress,
        IConfigurableRightsPool.PoolParams calldata params,
        RightsManager.Rights calldata rights
    ) external virtual returns (IConfigurableRightsPool);
}

/********************************** WARNING **********************************/
//                                                                           //
// This contract is only meant to be used in conjunction with ds-proxy.      //
// Calling this contract directly will lead to loss of funds.                //
//                                                                           //
/********************************** WARNING **********************************/

contract Actions {

    // --- Pool Creation ---

    function create(
        FactoryActions factory,
        address[] calldata tokens,
        uint[] calldata balances,
        uint[] calldata weights,
        uint swapFee,
        bool finalize
    ) external returns (LiquidityPoolActions pool) {
        require(tokens.length == balances.length, "ERR_LENGTH_MISMATCH");
        require(tokens.length == weights.length, "ERR_LENGTH_MISMATCH");

        pool = factory.newLiquidityPool();
        pool.setSwapFee(swapFee);

        for (uint i = 0; i < tokens.length; i++) {
            ERC20 token = ERC20(tokens[i]);
            require(token.transferFrom(msg.sender, address(this), balances[i]), "ERR_TRANSFER_FAILED");
            _safeApprove(token, address(pool), balances[i]);
            pool.bind(tokens[i], balances[i], weights[i]);
        }

        if (finalize) {
            pool.finalize();
            require(pool.transfer(msg.sender, pool.balanceOf(address(this))), "ERR_TRANSFER_FAILED");
        } else {
            pool.setPublicSwap(true);
        }
    }
    
    function createSmartPool(
        ICRPFactory factory,
        FactoryActions coreFactory,
        IConfigurableRightsPool.PoolParams calldata poolParams,
        IConfigurableRightsPool.CrpParams calldata crpParams,
        RightsManager.Rights calldata rights
    ) external returns (IConfigurableRightsPool crp) {
        require(
            poolParams.constituentTokens.length == poolParams.tokenBalances.length,
            "ERR_LENGTH_MISMATCH"
        );
        require(
            poolParams.constituentTokens.length == poolParams.tokenWeights.length,
            "ERR_LENGTH_MISMATCH"
        );

        crp = factory.newCrp(
            address(coreFactory),
            poolParams,
            rights
        );
        
        for (uint i = 0; i < poolParams.constituentTokens.length; i++) {
            ERC20 token = ERC20(poolParams.constituentTokens[i]);
            require(
                token.transferFrom(msg.sender, address(this), poolParams.tokenBalances[i]),
                "ERR_TRANSFER_FAILED"
            );
            _safeApprove(token, address(crp), poolParams.tokenBalances[i]);
        }
        
        crp.createPool(
            crpParams.initialSupply,
            crpParams.collectPeriod,
            crpParams.period
        );
        require(crp.transfer(msg.sender, crpParams.initialSupply), "ERR_TRANSFER_FAILED");
        // DSProxy instance keeps pool ownership to enable management
    }
    
    // --- Joins ---
    
    function joinPool(
        LiquidityPoolActions pool,
        uint poolAmountOut,
        uint[] calldata maxAmountsIn
    ) external {
        address[] memory tokens = pool.getFinalTokens();
        _join(pool, tokens, poolAmountOut, maxAmountsIn);
    }
    
    function joinSmartPool(
        IConfigurableRightsPool pool,
        uint poolAmountOut,
        uint[] calldata maxAmountsIn
    ) external {
        address[] memory tokens = pool.bPool().getCurrentTokens();
        _join(pool, tokens, poolAmountOut, maxAmountsIn);
    }
    
    // --- Pool management (common) ---
    
    function setPublicSwap(AbstractPool pool, bool publicSwap) external {
        pool.setPublicSwap(publicSwap);
    }

    function setSwapFee(AbstractPool pool, uint newFee) external {
        pool.setSwapFee(newFee);
    }

    function setController(AbstractPool pool, address newController) external {
        pool.setController(newController);
    }
    
    // --- Private pool management ---

    function setTokens(
        LiquidityPoolActions pool,
        address[] calldata tokens,
        uint[] calldata balances,
        uint[] calldata denorms
    ) external {
        require(tokens.length == balances.length, "ERR_LENGTH_MISMATCH");
        require(tokens.length == denorms.length, "ERR_LENGTH_MISMATCH");

        for (uint i = 0; i < tokens.length; i++) {
            ERC20 token = ERC20(tokens[i]);
            if (pool.isBound(tokens[i])) {
                if (balances[i] > pool.getBalance(tokens[i])) {
                    require(
                        token.transferFrom(msg.sender, address(this), balances[i] - pool.getBalance(tokens[i])),
                        "ERR_TRANSFER_FAILED"
                    );
                    _safeApprove(token, address(pool), balances[i] - pool.getBalance(tokens[i]));
                }
                if (balances[i] > 10**6) {
                    pool.rebind(tokens[i], balances[i], denorms[i]);
                } else {
                    pool.unbind(tokens[i]);
                }

            } else {
                require(token.transferFrom(msg.sender, address(this), balances[i]), "ERR_TRANSFER_FAILED");
                _safeApprove(token, address(pool), balances[i]);
                pool.bind(tokens[i], balances[i], denorms[i]);
            }

            if (token.balanceOf(address(this)) > 0) {
                require(token.transfer(msg.sender, token.balanceOf(address(this))), "ERR_TRANSFER_FAILED");
            }

        }
    }

    function finalize(LiquidityPoolActions pool) external {
        pool.finalize();
        require(pool.transfer(msg.sender, pool.balanceOf(address(this))), "ERR_TRANSFER_FAILED");
    }
    
    // --- Smart pool management ---

    function rebalance(
        IConfigurableRightsPool crp,
        address tokenA,
        address tokenB,
        uint deltaWeight,
        uint minAmountOut
    ) external {
        crp.rebalance(tokenA, tokenB, deltaWeight, minAmountOut);
    }

    function setCap(
        IConfigurableRightsPool crp,
        uint newCap
    ) external {
        crp.setCap(newCap);
    }

    function commitAddToken(
        IConfigurableRightsPool crp,
        ERC20 token,
        uint balance,
        uint denormalizedWeight
    ) external {
        crp.commitAddToken(address(token), balance, denormalizedWeight);
    }

    function applyAddToken(
        IConfigurableRightsPool crp,
        ERC20 token,
        uint tokenAmountIn
    ) external {
        require(token.transferFrom(msg.sender, address(this), tokenAmountIn), "ERR_TRANSFER_FAILED");
        _safeApprove(token, address(crp), tokenAmountIn);
        crp.applyAddToken();
        require(crp.transfer(msg.sender, crp.balanceOf(address(this))), "ERR_TRANSFER_FAILED");
    }

    function whitelistLiquidityProvider(
        IConfigurableRightsPool crp,
        address provider
    ) external {
        crp.whitelistLiquidityProvider(provider);
    }

    function removeWhitelistedLiquidityProvider(
        IConfigurableRightsPool crp,
        address provider
    ) external {
        crp.removeWhitelistedLiquidityProvider(provider);
    }
    
    // --- Internals ---
    
    function _safeApprove(ERC20 token, address spender, uint amount) internal {
        if (token.allowance(address(this), spender) > 0) {
            token.approve(spender, 0);
        }
        token.approve(spender, amount);
    }
    
    function _join(
        AbstractPool pool,
        address[] memory tokens,
        uint poolAmountOut,
        uint[] memory maxAmountsIn
    ) internal {
        require(maxAmountsIn.length == tokens.length, "ERR_LENGTH_MISMATCH");

        for (uint i = 0; i < tokens.length; i++) {
            ERC20 token = ERC20(tokens[i]);
            require(token.transferFrom(msg.sender, address(this), maxAmountsIn[i]), "ERR_TRANSFER_FAILED");
            _safeApprove(token, address(pool), maxAmountsIn[i]);
        }
        pool.joinPool(poolAmountOut, maxAmountsIn);
        for (uint i = 0; i < tokens.length; i++) {
            ERC20 token = ERC20(tokens[i]);
            if (token.balanceOf(address(this)) > 0) {
                require(token.transfer(msg.sender, token.balanceOf(address(this))), "ERR_TRANSFER_FAILED");
            }
        }
        require(pool.transfer(msg.sender, pool.balanceOf(address(this))), "ERR_TRANSFER_FAILED");
    }
}