// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.12;

// Needed to handle structures externally
pragma experimental ABIEncoderV2;

// Imports

import "../interfaces/IBFactory.sol";
import "./PCToken.sol";
import "../utils/DesynReentrancyGuard.sol";
import "../utils/DesynOwnable.sol";

// Interfaces

// Libraries
import { RightsManager } from "../libraries/RightsManager.sol";
import "../libraries/SmartPoolManager.sol";
import "../libraries/SafeApprove.sol";

// Contracts

/**
 * @author Desyn Labs
 * @title Smart Pool with customizable features
 * @notice PCToken is the "Desyn Smart Pool" token (transferred upon finalization)
 * @dev Rights are defined as follows (index values into the array)
 * Note that functions called on bPool and bFactory may look like internal calls,
 *   but since they are contracts accessed through an interface, they are really external.
 * To make this explicit, we could write "IBPool(address(bPool)).function()" everywhere,
 *   instead of "bPool.function()".
 */
contract ConfigurableRightsPool is PCToken, DesynOwnable, DesynReentrancyGuard {
    using DesynSafeMath for uint;
    using SafeApprove for IERC20;

    enum Etypes { OPENED, CLOSED }
    enum Period { HALF, ONE, TWO }

    // Type declarations

    struct PoolParams {
        // Desyn Pool Token (representing shares of the pool)
        string poolTokenSymbol;
        string poolTokenName;
        // Tokens inside the Pool
        address[] constituentTokens;
        uint[] tokenBalances;
        uint[] tokenWeights;
        uint swapFee;
        uint managerFee;
        uint redeemFee;
        uint issueFee;
        Etypes etype;
    }

    // State variables

    IBFactory public bFactory;
    IBPool public bPool;

    // Struct holding the rights configuration
    RightsManager.Rights public rights;

    // This is for adding a new (currently unbound) token to the pool
    // It's a two-step process: commitAddToken(), then applyAddToken()
    SmartPoolManager.NewTokenParams public newToken;

    SmartPoolManager.Status public etfStatus;

    // Fee is initialized on creation, and can be changed if permission is set
    // Only needed for temporary storage between construction and createPool
    // Thereafter, the swap fee should always be read from the underlying pool
    uint private _initialSwapFee;

    // Store the list of tokens in the pool, and balances
    // NOTE that the token list is *only* used to store the pool tokens between
    //   construction and createPool - thereafter, use the underlying BPool's list
    //   (avoids synchronization issues)
    address[] private _initialTokens;
    uint[] private _initialBalances;
    uint[] private _initialWeights;

    // Enforce a mandatory wait time between updates
    // This is also the wait time between committing and applying a new token
    uint public addTokenTimeLockInBlocks;

    // Whitelist of LPs (if configured)
    mapping(address => bool) private _liquidityProviderWhitelist;

    // Cap on the pool size (i.e., # of tokens minted when joining)
    // Limits the risk of experimental pools; failsafe/backup for fixed-size pools
    uint public bspCap;
    uint public managerFee;
    uint public redeemFee;
    uint public issueFee;
    uint public startClaimFeeTime;
    uint public claimPeriod = 60*60*24*30;
    address public managerOwner = 0xc312309d21211e1b8Be0DdA746508157B4b2a9f3;
    address public vault_Address = 0xF10473e8edEe939d1b79d71CFC985Da54edD0364;

    Etypes public etype;

    // Event declarations

    // Anonymous logger event - can only be filtered by contract address

    event LogCall(
        bytes4  indexed sig,
        address indexed caller,
        bytes data
    ) anonymous;

    event LogJoin(
        address indexed caller,
        address indexed tokenIn,
        uint tokenAmountIn
    );
    event LogExit(
        address indexed caller,
        address indexed tokenOut,
        uint tokenAmountOut
    );

    event CapChanged(
        address indexed caller,
        uint oldCap,
        uint newCap
    );
    
    event NewTokenCommitted(
        address indexed token,
        address indexed pool,
        address indexed caller
    );

    event SetManagerFee(
        uint indexed managerFee,
        uint indexed issueFee,
        uint indexed redeemFee
    );
    // Modifiers

       modifier managerFeeOwner() {
        require(managerOwner == msg.sender, "Ownable: caller is not the manager");
        _;
    }

    // Modifiers

    modifier logs() {
        emit LogCall(msg.sig, msg.sender, msg.data);
        _;
    }

    // Mark functions that require delegation to the underlying Pool
    modifier needsBPool() {
        require(address(bPool) != address(0), "ERR_NOT_CREATED");
        _;
    }

    modifier lockUnderlyingPool() {
        // Turn off swapping on the underlying pool during joins
        // Otherwise tokens with callbacks would enable attacks involving simultaneous swaps and joins
        bool origSwapState = bPool.isPublicSwap();
        bPool.setPublicSwap(false);
        _;
        bPool.setPublicSwap(origSwapState);
    }

    // Default values for these variables (used only in updateWeightsGradually), set in the constructor
    // Pools without permission to update weights cannot use them anyway, and should call
    //   the default createPool() function.
    // To override these defaults, pass them into the overloaded createPool()
    uint public constant DEFAULT_ADD_TOKEN_TIME_LOCK_IN_BLOCKS = 0;

    // Function declarations

    /**
     * @notice Construct a new Configurable Rights Pool (wrapper around BPool)
     * @dev _initialTokens and _swapFee are only used for temporary storage between construction
     *      and create pool, and should not be used thereafter! _initialTokens is destroyed in
     *      createPool to prevent this, and _swapFee is kept in sync (defensively), but
     *      should never be used except in this constructor and createPool()
     * @param factoryAddress - the BPoolFactory used to create the underlying pool
     * @param poolParams - struct containing pool parameters
     * @param rightsStruct - Set of permissions we are assigning to this smart pool
     */
    constructor(
        address factoryAddress,
        PoolParams memory poolParams,
        RightsManager.Rights memory rightsStruct

    )
        public
        PCToken(poolParams.poolTokenSymbol, poolParams.poolTokenName)
    {
        // We don't have a pool yet; check now or it will fail later (in order of likelihood to fail)
        // (and be unrecoverable if they don't have permission set to change it)
        // Most likely to fail, so check first
        require(poolParams.swapFee >= DesynConstants.MIN_FEE, "ERR_INVALID_SWAP_FEE");
        require(poolParams.swapFee <= DesynConstants.MAX_FEE, "ERR_INVALID_SWAP_FEE");
         require(poolParams.managerFee >= DesynConstants.MANAGER_MIN_FEE, "ERR_INVALID_SWAP_FEE");
        require(poolParams.managerFee <= DesynConstants.MANAGER_MAX_FEE, "ERR_INVALID_SWAP_FEE");
        startClaimFeeTime = block.timestamp;

        // Arrays must be parallel
        require(poolParams.tokenBalances.length == poolParams.constituentTokens.length, "ERR_START_BALANCES_MISMATCH");
        require(poolParams.tokenWeights.length == poolParams.constituentTokens.length, "ERR_START_WEIGHTS_MISMATCH");
        // Cannot have too many or too few - technically redundant, since BPool.bind() would fail later
        // But if we don't check now, we could have a useless contract with no way to create a pool

        require(poolParams.constituentTokens.length >= DesynConstants.MIN_ASSET_LIMIT, "ERR_TOO_FEW_TOKENS");
        require(poolParams.constituentTokens.length <= DesynConstants.MAX_ASSET_LIMIT, "ERR_TOO_MANY_TOKENS");
        // There are further possible checks (e.g., if they use the same token twice), but
        // we can let bind() catch things like that (i.e., not things that might reasonably work)

        SmartPoolManager.verifyTokenCompliance(poolParams.constituentTokens);

        bFactory = IBFactory(factoryAddress);
        rights = rightsStruct;
        _initialTokens = poolParams.constituentTokens;
        _initialBalances = poolParams.tokenBalances;
        _initialWeights = poolParams.tokenWeights;
        _initialSwapFee = poolParams.swapFee;
        managerFee = poolParams.managerFee;
        issueFee = poolParams.issueFee;
        redeemFee = poolParams.redeemFee;

        // These default block time parameters can be overridden in createPool
        addTokenTimeLockInBlocks = DEFAULT_ADD_TOKEN_TIME_LOCK_IN_BLOCKS;
        
        // By default, there is no cap (unlimited pool token minting)
        bspCap = DesynConstants.MAX_UINT;
        emit SetManagerFee(managerFee,issueFee,redeemFee);
         etype = poolParams.etype;
    }
  

    /**
     * @notice Set the swap fee on the underlying pool
     * @dev Keep the local version and core in sync (see below)
     *      bPool is a contract interface; function calls on it are external
     * @param swapFee in Wei
     */
    function setSwapFee(uint swapFee)
        external
        logs
        lock
        onlyOwner
        needsBPool
        virtual
    {
        require(rights.canChangeSwapFee, "ERR_NOT_CONFIGURABLE_SWAP_FEE");

        // Underlying pool will check against min/max fee
        bPool.setSwapFee(swapFee);
    }

    /**
     * @notice Getter for the publicSwap field on the underlying pool
     * @dev viewLock, because setPublicSwap is lock
     *      bPool is a contract interface; function calls on it are external
     * @return Current value of isPublicSwap
     */
    function isPublicSwap()
        external
        view
        viewlock
        needsBPool
        virtual
        returns (bool)
    {
        return bPool.isPublicSwap();
    }

    /**
     * @notice Set the cap (max # of pool tokens)
     * @dev _bspCap defaults in the constructor to unlimited
     *      Can set to 0 (or anywhere below the current supply), to halt new investment
     *      Prevent setting it before creating a pool, since createPool sets to intialSupply
     *      (it does this to avoid an unlimited cap window between construction and createPool)
     *      Therefore setting it before then has no effect, so should not be allowed
     * @param newCap - new value of the cap
     */
    function setCap(uint newCap)
        external
        logs
        lock
        needsBPool
        onlyOwner
    {
        require(rights.canChangeCap, "ERR_CANNOT_CHANGE_CAP");

        emit CapChanged(msg.sender, bspCap, newCap);

        bspCap = newCap;
    }

    /**
     * @notice Set the public swap flag on the underlying pool
     * @dev If this smart pool has canPauseSwapping enabled, we can turn publicSwap off if it's already on
     *      Note that if they turn swapping off - but then finalize the pool - finalizing will turn the
     *      swapping back on. They're not supposed to finalize the underlying pool... would defeat the
     *      smart pool functions. (Only the owner can finalize the pool - which is this contract -
     *      so there is no risk from outside.)
     *
     *      bPool is a contract interface; function calls on it are external
     * @param publicSwap new value of the swap
     */
    function setPublicSwap(bool publicSwap)
        external
        logs
        lock
        onlyOwner
        needsBPool
        virtual
    {
        require(rights.canPauseSwapping, "ERR_NOT_PAUSABLE_SWAP");

        bPool.setPublicSwap(publicSwap);
    }


    function claimManagerFee()
        external
        logs
        lock
        managerFeeOwner
        needsBPool
        virtual
    {
        require(DesynSafeMath.bsub(block.timestamp, startClaimFeeTime) >= claimPeriod,"The collection cycle is not reached");
       uint time = DesynSafeMath.bsub(block.timestamp, startClaimFeeTime)/claimPeriod;
       address[] memory poolTokens = bPool.getCurrentTokens();
       uint[] memory tokensAmount = new uint[](poolTokens.length);
        bool returnValue;
        for (uint i = 0; i < poolTokens.length; i++) {
            address t = poolTokens[i];
            uint tokenBalance = bPool.getBalance(t);
            uint tokenAmountOut = DesynSafeMath.bmul(tokenBalance,managerFee*time/12);
            _pushUnderlying(t, address(this), tokenAmountOut);
           returnValue = IERC20(t).safeApprove(vault_Address, tokenAmountOut);
           tokensAmount[i] = tokenAmountOut;
        }       
        IVault(vault_Address).depositManagerToken(poolTokens,tokensAmount);
        startClaimFeeTime = startClaimFeeTime + time*claimPeriod;
    }


    /**
     * @notice Create a new Smart Pool
     * @dev Delegates to internal function
     * @param initialSupply starting token balance
     */
    function createPool(uint initialSupply)
        external
        onlyOwner
        logs
        lock
        virtual
    {
        createPoolInternal(initialSupply);
    }

    /**
     * @notice Create a new Smart Pool
     * @dev Delegates to internal function
     * @param initialSupply starting token balance
     * @param closurePeriod the etf closure period
     */
    function createPool(uint initialSupply, uint collectPeriod, Period closurePeriod)
        external
        onlyOwner
        logs
        lock
        virtual
    {
        if(etype == Etypes.CLOSED) {
            require(collectPeriod <= DesynConstants.MAX_COLLECT_PERIOD, "ERR_EXCEEDS_FUND_RAISING_PERIOD");
    
            uint period;
            uint collectEndTime = block.timestamp + collectPeriod;
            if (closurePeriod == Period.HALF) {
                period = 180 days;
            } else if (closurePeriod == Period.ONE) {
                period = 365 days;
            } else {
                period = 730 days;
            }
            
            uint closureEndTime = collectEndTime + period;
            etfStatus = SmartPoolManager.Status(collectPeriod, collectEndTime, period, closureEndTime);
        }

        createPoolInternal(initialSupply);
    }

    function rebalance(
        address tokenA,
        address tokenB,
        uint deltaWeight,
        uint minAmountOut
    )
        external
        logs
        lock
        onlyOwner
        needsBPool
        virtual
    {
        if (etype == Etypes.CLOSED) {
            require(block.timestamp > etfStatus.collectEndTime && block.timestamp < etfStatus.closureEndTime, "ERR_NOT_REBALANCE_PERIOD");
        }

        require(rights.canChangeWeights, "ERR_NOT_CONFIGURABLE_WEIGHTS");
        require(tokenA != tokenB, "ERR_TOKENS_SAME");

        require(bFactory.isTokenWhitelisted(tokenB), "ERR_TOKEN_NOT_IN_WHITELIST");

        // We don't want people to set weights manually if there's a block-based update in progress
        bool bools = IVault(vault_Address).getManagerClaimBool(address(this));
        if(bools){
            IVault(vault_Address).managerClaim(address(this));
        }  

        if (!bPool.isBound(tokenB)) {
            bool returnValue = IERC20(tokenB).safeApprove(address(bPool), DesynConstants.MAX_UINT);
            require(returnValue, "ERR_ERC20_FALSE");
        }

        // Delegate to library to save space
        SmartPoolManager.rebalance(IConfigurableRightsPool(address(this)), bPool, tokenA, tokenB, deltaWeight, minAmountOut);
    }

    /**
     * @notice Schedule (commit) a token to be added; must call applyAddToken after a fixed
     *         number of blocks to actually add the token
     *
     * @dev The purpose of this two-stage commit is to give warning of a potentially dangerous
     *      operation. A malicious pool operator could add a large amount of a low-value token,
     *      then drain the pool through price manipulation. Of course, there are many
     *      legitimate purposes, such as adding additional collateral tokens.
     *
     * @param token - the token to be added
     * @param balance - how much to be added
     * @param denormalizedWeight - the desired token weight
     */
    function commitAddToken(
        address token,
        uint balance,
        uint denormalizedWeight
    )
        external
        logs
        lock
        onlyOwner
        needsBPool
        virtual
    {
        require(rights.canAddRemoveTokens, "ERR_CANNOT_ADD_REMOVE_TOKENS");

        // Can't do this while a progressive update is happening
        bool bools = IVault(vault_Address).getManagerClaimBool(address(this));
        if(bools){
        IVault(vault_Address).managerClaim(address(this));
        }     

        SmartPoolManager.verifyTokenCompliance(token);

        emit NewTokenCommitted(token, address(this), msg.sender);

        // Delegate to library to save space
        SmartPoolManager.commitAddToken(
            bPool,
            token,
            balance,
            denormalizedWeight,
            newToken
        );
    }

    /**
     * @notice Add the token previously committed (in commitAddToken) to the pool
     */
    function applyAddToken()
        external
        logs
        lock
        onlyOwner
        needsBPool
        virtual
    {
        require(rights.canAddRemoveTokens, "ERR_CANNOT_ADD_REMOVE_TOKENS");

        // Delegate to library to save space
        SmartPoolManager.applyAddToken(
            IConfigurableRightsPool(address(this)),
            bPool,
            addTokenTimeLockInBlocks,
            newToken
        );
    }

    /**
     * @notice Join a pool
     * @dev Emits a LogJoin event (for each token)
     *      bPool is a contract interface; function calls on it are external
     * @param poolAmountOut - number of pool tokens to receive
     * @param maxAmountsIn - Max amount of asset tokens to spend
     */
    function joinPool(uint poolAmountOut, uint[] calldata maxAmountsIn)
        external
        logs
        lock
        needsBPool
        lockUnderlyingPool
    {
        require(!rights.canWhitelistLPs || _liquidityProviderWhitelist[msg.sender],
                "ERR_NOT_ON_WHITELIST");

        if (etype == Etypes.CLOSED) {
            require(block.timestamp <= etfStatus.collectEndTime, "ERR_COLLECT_PERIOD_FINISHED!");
        }
        // Delegate to library to save space

        // Library computes actualAmountsIn, and does many validations
        // Cannot call the push/pull/min from an external library for
        // any of these pool functions. Since msg.sender can be anybody,
        // they must be internal
        uint[] memory actualAmountsIn = SmartPoolManager.joinPool(
                                            IConfigurableRightsPool(address(this)),
                                            bPool,
                                            poolAmountOut,
                                            maxAmountsIn
                                        );

        // After createPool, token list is maintained in the underlying BPool
        address[] memory poolTokens = bPool.getCurrentTokens();
        uint[] memory tokensAmount = new uint[](poolTokens.length);
        for (uint i = 0; i < poolTokens.length; i++) {
            address t = poolTokens[i];
            uint tokenAmountIn = actualAmountsIn[i];
            emit LogJoin(msg.sender, t, tokenAmountIn);
            uint tokenAmountInNew = DesynSafeMath.bmul(tokenAmountIn,issueFee);
            _pullUnderlying(t, msg.sender, DesynSafeMath.bsub(tokenAmountIn,tokenAmountInNew));
            if(issueFee != 0){
            bool xfer = IERC20(t).transferFrom(msg.sender, address(this), tokenAmountInNew);
            bool returnValue = IERC20(t).safeApprove(vault_Address, tokenAmountInNew);
            require(xfer&&returnValue, "ERR_ERC20_FALSE");
            tokensAmount[i] = tokenAmountInNew;
            }       
        }
        if(issueFee != 0){
             IVault(vault_Address).depositIssueRedeemToken(poolTokens,tokensAmount);
        } 
        uint poolAmountOutNew = DesynSafeMath.bsub(poolAmountOut,DesynSafeMath.bmul(poolAmountOut,issueFee));
        _mintPoolShare(poolAmountOutNew);
        _pushPoolShare(msg.sender, poolAmountOutNew);
    }

    /**
     * @notice Exit a pool - redeem pool tokens for underlying assets
     * @dev Emits a LogExit event for each token
     *      bPool is a contract interface; function calls on it are external
     * @param poolAmountIn - amount of pool tokens to redeem
     * @param minAmountsOut - minimum amount of asset tokens to receive
     */
    function exitPool(uint poolAmountIn, uint[] calldata minAmountsOut)
        external
        logs
        lock
        needsBPool
        lockUnderlyingPool
    {
        // Delegate to library to save space
        if (etype == Etypes.CLOSED) {
            require(block.timestamp >= etfStatus.closureEndTime || block.timestamp <= etfStatus.collectEndTime, "ERR_CLOSURE_TIME_NOT_ARRIVED!");
        }

        // Library computes actualAmountsOut, and does many validations
        // Also computes the exitFee and pAiAfterExitFee
        (uint pAiAfterExitFee,
         uint[] memory actualAmountsOut) = SmartPoolManager.exitPool(
                                               IConfigurableRightsPool(address(this)),
                                               bPool,
                                               poolAmountIn,
                                               minAmountsOut
                                           );
        _pullPoolShare(msg.sender, poolAmountIn);
        _burnPoolShare(pAiAfterExitFee);

        // After createPool, token list is maintained in the underlying BPool
        address[] memory poolTokens = bPool.getCurrentTokens();
        uint[] memory tokensAmount = new uint[](poolTokens.length);
        for (uint i = 0; i < poolTokens.length; i++) {
            address t = poolTokens[i];
            uint tokenAmountOut = actualAmountsOut[i];
            uint tokenAmountOutNew = DesynSafeMath.bmul(tokenAmountOut,redeemFee);
            emit LogExit(msg.sender, t, DesynSafeMath.bsub(tokenAmountOut,tokenAmountOutNew));
            _pushUnderlying(t, msg.sender, DesynSafeMath.bsub(tokenAmountOut,tokenAmountOutNew));
            if(redeemFee != 0){
            _pushUnderlying(t, address(this), tokenAmountOutNew);
            bool returnValue = IERC20(t).safeApprove(vault_Address, tokenAmountOutNew);
            require(returnValue, "ERR_ERC20_APPROVE_FALSE");
            tokensAmount[i] = tokenAmountOutNew;
            }
        }
           if(redeemFee != 0){
             IVault(vault_Address).depositIssueRedeemToken(poolTokens,tokensAmount);
        } 
    }


    /**
     * @notice Add to the whitelist of liquidity providers (if enabled)
     * @param provider - address of the liquidity provider
     */
    function whitelistLiquidityProvider(address provider)
        external
        onlyOwner
        lock
        logs
    {
        require(rights.canWhitelistLPs, "ERR_CANNOT_WHITELIST_LPS");
        require(provider != address(0), "ERR_INVALID_ADDRESS");

        _liquidityProviderWhitelist[provider] = true;
    }

    /**
     * @notice Remove from the whitelist of liquidity providers (if enabled)
     * @param provider - address of the liquidity provider
     */
    function removeWhitelistedLiquidityProvider(address provider)
        external
        onlyOwner
        lock
        logs
    {
        require(rights.canWhitelistLPs, "ERR_CANNOT_WHITELIST_LPS");
        require(_liquidityProviderWhitelist[provider], "ERR_LP_NOT_WHITELISTED");
        require(provider != address(0), "ERR_INVALID_ADDRESS");

        _liquidityProviderWhitelist[provider] = false;
    }

    /**
     * @notice Check if an address is a liquidity provider
     * @dev If the whitelist feature is not enabled, anyone can provide liquidity (assuming finalized)
     * @return boolean value indicating whether the address can join a pool
     */
    function canProvideLiquidity(address provider)
        external
        view
        returns(bool)
    {
        if (rights.canWhitelistLPs) {
            return _liquidityProviderWhitelist[provider];
        }
        else {
            // Probably don't strictly need this (could just return true)
            // But the null address can't provide funds
            return provider != address(0);
        }
    }

    /**
     * @notice Getter for specific permissions
     * @dev value of the enum is just the 0-based index in the enumeration
     *      For instance canPauseSwapping is 0; canChangeWeights is 2
     * @return token boolean true if we have the given permission
    */
    function hasPermission(RightsManager.Permissions permission)
        external
        view
        virtual
        returns(bool)
    {
        return RightsManager.hasPermission(rights, permission);
    }

    /**
     * @notice Get the denormalized weight of a token
     * @dev viewlock to prevent calling if it's being updated
     * @return token weight
     */
    function getDenormalizedWeight(address token)
        external
        view
        viewlock
        needsBPool
        returns (uint)
    {
        return bPool.getDenormalizedWeight(token);
    }

    /**
     * @notice Getter for the RightsManager contract
     * @dev Convenience function to get the address of the RightsManager library (so clients can check version)
     * @return address of the RightsManager library
    */
    function getRightsManagerVersion() external pure returns (address) {
        return address(RightsManager);
    }

    /**
     * @notice Getter for the DesynSafeMath contract
     * @dev Convenience function to get the address of the DesynSafeMath library (so clients can check version)
     * @return address of the DesynSafeMath library
    */
    function getDesynSafeMathVersion() external pure returns (address) {
        return address(DesynSafeMath);
    }

    /**
     * @notice Getter for the SmartPoolManager contract
     * @dev Convenience function to get the address of the SmartPoolManager library (so clients can check version)
     * @return address of the SmartPoolManager library
    */
    function getSmartPoolManagerVersion() external pure returns (address) {
        return address(SmartPoolManager);
    }

    // Public functions

    // "Public" versions that can safely be called from SmartPoolManager
    // Allows only the contract itself to call them (not the controller or any external account)

    function mintPoolShareFromLib(uint amount) public {
        require (msg.sender == address(this), "ERR_NOT_CONTROLLER");

        _mint(amount);
    }

    function pushPoolShareFromLib(address to, uint amount) public {
        require (msg.sender == address(this), "ERR_NOT_CONTROLLER");

        _push(to, amount);
    }

    function pullPoolShareFromLib(address from, uint amount) public  {
        require (msg.sender == address(this), "ERR_NOT_CONTROLLER");

        _pull(from, amount);
    }

    function burnPoolShareFromLib(uint amount) public  {
        require (msg.sender == address(this), "ERR_NOT_CONTROLLER");

        _burn(amount);
    }

    // Internal functions

    // Lint wants the function to have a leading underscore too
    /* solhint-disable private-vars-leading-underscore */

    /**
     * @notice Create a new Smart Pool
     * @dev Initialize the swap fee to the value provided in the CRP constructor
     *      Can be changed if the canChangeSwapFee permission is enabled
     * @param initialSupply starting token balance
     */
    function createPoolInternal(uint initialSupply) internal {
        require(address(bPool) == address(0), "ERR_IS_CREATED");
        require(initialSupply >= DesynConstants.MIN_POOL_SUPPLY, "ERR_INIT_SUPPLY_MIN");
        require(initialSupply <= DesynConstants.MAX_POOL_SUPPLY, "ERR_INIT_SUPPLY_MAX");

        // If the controller can change the cap, initialize it to the initial supply
        // Defensive programming, so that there is no gap between creating the pool
        // (initialized to unlimited in the constructor), and setting the cap,
        // which they will presumably do if they have this right.
        if (rights.canChangeCap) {
            bspCap = initialSupply;
        }

        // There is technically reentrancy here, since we're making external calls and
        // then transferring tokens. However, the external calls are all to the underlying BPool

        // To the extent possible, modify state variables before calling functions
        _mintPoolShare(initialSupply);
        _pushPoolShare(msg.sender, initialSupply);

        // Deploy new BPool (bFactory and bPool are interfaces; all calls are external)
        
        bPool = bFactory.newLiquidityPool();

        // EXIT_FEE must always be zero, or ConfigurableRightsPool._pushUnderlying will fail
        require(bPool.EXIT_FEE() == 0, "ERR_NONZERO_EXIT_FEE");
        require(DesynConstants.EXIT_FEE == 0, "ERR_NONZERO_EXIT_FEE");

        for (uint i = 0; i < _initialTokens.length; i++) {
            address t = _initialTokens[i];
            uint bal = _initialBalances[i];
            uint denorm = _initialWeights[i];

            require(bFactory.isTokenWhitelisted(t), "ERR_TOKEN_NOT_IN_WHITELIST");

            bool returnValue = IERC20(t).transferFrom(msg.sender, address(this), bal);
            require(returnValue, "ERR_ERC20_FALSE");

            returnValue = IERC20(t).safeApprove(address(bPool), DesynConstants.MAX_UINT);
            require(returnValue, "ERR_ERC20_FALSE");

            bPool.bind(t, bal, denorm);
        }

        while (_initialTokens.length > 0) {
            // Modifying state variable after external calls here,
            // but not essential, so not dangerous
            _initialTokens.pop();
        }

        // Set fee to the initial value set in the constructor
        // Hereafter, read the swapFee from the underlying pool, not the local state variable
        bPool.setSwapFee(_initialSwapFee);
        bPool.setPublicSwap(false);

        // "destroy" the temporary swap fee (like _initialTokens above) in case a subclass tries to use it
        _initialSwapFee = 0;
    }

    /* solhint-enable private-vars-leading-underscore */

    // Rebind BPool and pull tokens from address
    // bPool is a contract interface; function calls on it are external
    function _pullUnderlying(address erc20, address from, uint amount) internal needsBPool {
        // Gets current Balance of token i, Bi, and weight of token i, Wi, from BPool.
        uint tokenBalance = bPool.getBalance(erc20);
        uint tokenWeight = bPool.getDenormalizedWeight(erc20);

        bool xfer = IERC20(erc20).transferFrom(from, address(this), amount);
        require(xfer, "ERR_ERC20_FALSE");
        bPool.rebind(erc20, DesynSafeMath.badd(tokenBalance, amount), tokenWeight);
    }

    // Rebind BPool and push tokens to address
    // bPool is a contract interface; function calls on it are external
    function _pushUnderlying(address erc20, address to, uint amount) internal needsBPool {
        // Gets current Balance of token i, Bi, and weight of token i, Wi, from BPool.
        uint tokenBalance = bPool.getBalance(erc20);
        uint tokenWeight = bPool.getDenormalizedWeight(erc20);
        bPool.rebind(erc20, DesynSafeMath.bsub(tokenBalance, amount), tokenWeight);

        bool xfer = IERC20(erc20).transfer(to, amount);
        require(xfer, "ERR_ERC20_FALSE");
    }

    // Wrappers around corresponding core functions

    // 
    function _mint(uint amount) internal override {
        super._mint(amount);
        require(varTotalSupply <= bspCap, "ERR_CAP_LIMIT_REACHED");
    }

    function _mintPoolShare(uint amount) internal {
        _mint(amount);
    }

    function _pushPoolShare(address to, uint amount) internal {
        _push(to, amount);
    }

    function _pullPoolShare(address from, uint amount) internal  {
        _pull(from, amount);
    }

    function _burnPoolShare(uint amount) internal  {
        _burn(amount);
    }
}
