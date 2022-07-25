// SPDX-License-Identifier: GPL-3.0-or-later
library SafeMath {

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }


    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

library Address {

    function isContract(address account) internal view returns (bool) {
        // According to EIP-1052, 0x0 is the value returned for not-yet created accounts
        // and 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470 is returned
        // for accounts without code, i.e. `keccak256('')`
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly { codehash := extcodehash(account) }
        return (codehash != accountHash && codehash != 0x0);
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }


    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
      return functionCall(target, data, "Address: low-level call failed");
    }

    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        return _functionCallWithValue(target, data, 0, errorMessage);
    }

    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        return _functionCallWithValue(target, data, value, errorMessage);
    }

    function _functionCallWithValue(address target, bytes memory data, uint256 weiValue, string memory errorMessage) private returns (bytes memory) {
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{ value: weiValue }(data);
        if (success) {
            return returndata;
        } else {
            
            if (returndata.length > 0) {
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}



pragma solidity 0.6.12;
import "../interfaces/IERC20.sol";
import "../utils/DesynOwnable.sol";
// Contracts
pragma experimental ABIEncoderV2;

interface ICRPPool {
    function getController() external view returns (address);
}

interface IToken{
    function decimals() external view returns(uint);
}

interface IDSProxy {
    function owner() external view returns (address);
}
/**
 * @author Desyn Labs
 * @title Vault managerFee 
*/
contract Vault is DesynOwnable{
     using SafeMath for uint256;
    using Address for address;

     struct claimTokenInfo{
      address token;
      uint256 decimals;
      uint256 amount;
  }

    event ManagerRatio(
        address indexed caller,
        uint indexed amount
    );

    event IssueRedeemRatio(
        address indexed caller,
        uint indexed amount
    );

   struct claimRecordInfo{
       uint time;
       claimTokenInfo[] tokens;
   }


    mapping(address => address) public pool_manager;
    mapping(address => address[]) public pool_manager_tokenList;
    mapping(address => uint[]) public pool_manager_tokenAmount;
    mapping(address => address[]) public pool_issue_redeem_tokenList;
    mapping(address => uint[]) public pool_issue_redeem_tokenAmount;
    mapping(address => bool) public pool_manager_isClaim;
    mapping(address => bool) public black_list;
    //history record
    mapping(address => uint) public record_number;
    mapping(address => mapping(uint => claimRecordInfo)) public record_List;
    uint public total_ratio = 100;
    uint public manager_ratio = 20;
    uint public issue_redeem_ratio = 20;
    constructor () public {
    }

 receive() external payable {

  	}

    function depositManagerToken(address[] calldata poolTokens,uint[] calldata tokensAmount) public {
        require(poolTokens.length == tokensAmount.length,"Token list length is not eequalqu");
        if(pool_manager[msg.sender] == address(0)){
            address manager_address =  ICRPPool(msg.sender).getController();
            pool_manager[msg.sender] = manager_address;
        }
        address[] memory _pool_tokenList = pool_manager_tokenList[msg.sender];
        uint[] memory _pool_tokenAmount = pool_manager_tokenAmount[msg.sender];
        (address[] memory new_pool_tokenList,uint[] memory new_pool_tokenAmount) =   communaldepositToken(poolTokens,tokensAmount,msg.sender,_pool_tokenList,_pool_tokenAmount);
         pool_manager_tokenList[msg.sender]  = new_pool_tokenList;
         if(pool_issue_redeem_tokenList[msg.sender].length != 0){
             pool_issue_redeem_tokenList[msg.sender]  = new_pool_tokenList;
         }
         pool_manager_tokenAmount[msg.sender] = new_pool_tokenAmount;
         pool_manager_isClaim[msg.sender] = true;
    }

    function depositIssueRedeemToken(address[] calldata poolTokens,uint[] calldata tokensAmount) public {
        require(poolTokens.length == tokensAmount.length,"Token list length is not eequalqu");
        if(pool_manager[msg.sender] == address(0)){
            address manager_address =  ICRPPool(msg.sender).getController();
            pool_manager[msg.sender] = manager_address;
        }
         address[] memory _pool_tokenList = pool_issue_redeem_tokenList[msg.sender];
        uint[] memory _pool_tokenAmount = pool_issue_redeem_tokenAmount[msg.sender];
        (address[] memory new_pool_tokenList,uint[] memory new_pool_tokenAmount) =   communaldepositToken(poolTokens,tokensAmount,msg.sender,_pool_tokenList,_pool_tokenAmount);
         pool_issue_redeem_tokenList[msg.sender]  = new_pool_tokenList;
         if(pool_manager_tokenList[msg.sender].length != 0){
            pool_manager_tokenList[msg.sender]  = new_pool_tokenList;
         }        
         pool_issue_redeem_tokenAmount[msg.sender] = new_pool_tokenAmount;
         pool_manager_isClaim[msg.sender] = true;
    }

    function communaldepositToken(address[] calldata poolTokens,uint[] calldata tokensAmount,address poolAdr,address[] memory _pool_tokenList,uint[] memory _pool_tokenAmount) internal returns(address[] memory new_pool_tokenList,uint[] memory new_pool_tokenAmount){
        //old
        //new
        new_pool_tokenList = new address[](poolTokens.length);
        new_pool_tokenAmount = new uint[](poolTokens.length);
        if((_pool_tokenList.length == _pool_tokenAmount.length && _pool_tokenList.length == 0)||!pool_manager_isClaim[poolAdr]){
        for(uint i = 0;i <poolTokens.length;i++){
              address t = poolTokens[i];
            uint tokenBalance = tokensAmount[i];
            IERC20(t).transferFrom(msg.sender, address(this), tokenBalance);
          new_pool_tokenList[i] = poolTokens[i];
            new_pool_tokenAmount[i] = tokensAmount[i];
        }
        }else{
              for(uint k = 0;k<poolTokens.length;k++){
                  if(_pool_tokenList[k] == poolTokens[k]){
                       address t = poolTokens[k];
                    uint tokenBalance = tokensAmount[k];
            IERC20(t).transferFrom(msg.sender, address(this), tokenBalance);
            new_pool_tokenList[k] = poolTokens[k];
            new_pool_tokenAmount[k] = _pool_tokenAmount[k].add(tokenBalance);
                  }
              }
        }
                return(new_pool_tokenList,new_pool_tokenAmount);
    }

    function poolManagerTokenList(address pool) public view returns(address[] memory tokens){
        return pool_manager_tokenList[pool];
    }

    function poolManagerTokenAmount(address pool) public  view returns(uint[] memory tokenAmount){
        return pool_manager_tokenAmount[pool];
    }

       function poolIssueRedeemTokenList(address pool) public view returns(address[] memory tokens){
        return pool_issue_redeem_tokenList[pool];
    }

    function poolIssueRedeemTokenAmount(address pool) public  view returns(uint[] memory tokenAmount){
        return pool_issue_redeem_tokenAmount[pool];
    }

    function getManagerClaimBool(address pool) public view returns(bool bools){
        bools = pool_manager_isClaim[pool];
    }
    function setBlackList(address user,bool bools) public onlyOwner{
        black_list[user] = bools;
    }
    function adminClaimToken(address token, address user,uint amount) public onlyOwner{
        IERC20(token).transfer(user, amount);
    }
    function getBNB() public payable onlyOwner{
       msg.sender.transfer(address(this).balance);
    }

    function setManagerRatio(uint amount) public onlyOwner{
        require(amount <= total_ratio,"Maximum limit exceeded");
        manager_ratio = amount;
        emit ManagerRatio(msg.sender, amount);
    }
      function setIssueRedeemRatio(uint amount) public onlyOwner{
        require(amount <= total_ratio,"Maximum limit exceeded");
        issue_redeem_ratio = amount;
        emit IssueRedeemRatio(msg.sender, amount);
    }

    function managerClaim(address pool) public {
        address manager_address =  ICRPPool(pool).getController();
         address[] memory _pool_manager_tokenList = pool_manager_tokenList[pool].length != 0 ? pool_manager_tokenList[pool] : pool_issue_redeem_tokenList[pool];
        require(!black_list[manager_address],"The pool manager is not claimed");
        require(pool_manager[pool] == manager_address,"claim is not manager");
        require(_pool_manager_tokenList.length > 0,"The pool is not manager fee");
        require(pool_manager_isClaim[pool], "The pool manager is claim");
        pool_manager_isClaim[pool] = false;
        uint[] memory _pool_manager_tokenAmount = pool_manager_tokenAmount[pool];
        uint[] memory  _pool_issue_redeem_tokenAmount = pool_issue_redeem_tokenAmount[pool];
         bool boolOne = _pool_manager_tokenAmount.length == 0 ? false : true;
         bool boolTwo = _pool_issue_redeem_tokenAmount.length == 0 ? false : true;
         //record
         claimRecordInfo storage recordInfo;
         delete recordInfo.time;
         delete recordInfo.tokens;
         recordInfo.time = block.timestamp;
        for( uint i = 0;i < _pool_manager_tokenList.length;i++){
            uint balance;
            claimTokenInfo memory tokenInfo;
            //manager fee
            if(boolOne){
                uint balanceOne = _pool_manager_tokenAmount[i].mul(manager_ratio).div(total_ratio);
                balance = balance.add(balanceOne);
            }
        if(boolTwo){
                uint balanceTwo = _pool_issue_redeem_tokenAmount[i].mul(issue_redeem_ratio).div(total_ratio);
                 balance = balance.add(balanceTwo);
        }  
            address t = _pool_manager_tokenList[i];
            if(manager_address.isContract()){
               manager_address =  IDSProxy(manager_address).owner();
            }
            tokenInfo.token = t;
            tokenInfo.amount = balance;
            tokenInfo.decimals = IToken(t).decimals();
            recordInfo.tokens.push(tokenInfo);
            IERC20(t).transfer(manager_address, balance);
        }
        
        record_number[pool] = record_number[pool].add(1);
        record_List[pool][record_number[pool]] = recordInfo;
        pool_manager_tokenAmount[pool] = new uint[](0);
        pool_issue_redeem_tokenAmount[pool] = new uint[](0);
        pool_manager_tokenList[pool] = new address[](0);
        pool_issue_redeem_tokenList[pool] = new address[](0);
    }

    function managerClaimRecordList(address pool) public view returns(claimRecordInfo[] memory claimRecordInfos){
            uint num = record_number[pool];
            claimRecordInfo[] memory records = new claimRecordInfo[](num);
            for(uint i = 1;i < num + 1; i++){
                claimRecordInfo memory record;
                  record = record_List[pool][i];
                records[i.sub(1)] = record; 
            }
            return records;
    }

      function managerClaimList(address pool) public view returns(claimTokenInfo[] memory claimTokenInfos){
          address[] memory _pool_manager_tokenList = pool_manager_tokenList[pool].length != 0 ? pool_manager_tokenList[pool] : pool_issue_redeem_tokenList[pool];
           uint[] memory _pool_manager_tokenAmount = pool_manager_tokenAmount[pool];
        uint[] memory  _pool_issue_redeem_tokenAmount = pool_issue_redeem_tokenAmount[pool];
        claimTokenInfo[] memory infos = new claimTokenInfo[](_pool_manager_tokenList.length);
         bool boolOne = _pool_manager_tokenAmount.length == 0 ? false : true;
         bool boolTwo = _pool_issue_redeem_tokenAmount.length == 0 ? false : true;
        for(uint i = 0;i < _pool_manager_tokenList.length;i++){
            claimTokenInfo memory tokenInfo;
            tokenInfo.token = _pool_manager_tokenList[i];
            uint balance;
            if(boolOne){
                 uint balanceOne = _pool_manager_tokenAmount[i].mul(manager_ratio).div(total_ratio);
                 balance = balance.add(balanceOne);
            }
           if(boolTwo){
                uint balanceTwo = _pool_issue_redeem_tokenAmount[i].mul(issue_redeem_ratio).div(total_ratio);
                balance = balance.add(balanceTwo);
           }
            tokenInfo.amount = balance;
            tokenInfo.decimals = IToken( _pool_manager_tokenList[i]).decimals();
            infos[i] = tokenInfo;
        }
        return infos;

    }
}
