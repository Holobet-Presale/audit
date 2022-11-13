// File: @openzeppelin/contracts/token/ERC20/IERC20.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";






interface IRewardPool {
    function harvest() external;
}

contract HolobetToken is ERC20, Ownable {
    mapping(address => bool) public ammPairs;
    mapping(address => bool) public salesTaxWhitelist;

    uint256 public constant STAKING_REWARD_FEE = 10; //1%;
    uint256 public constant MARKETING_FEE = 10; //1%;
    uint256 public constant PRICE_BACKING_FEE = 30; //3%;
    uint256 public constant MAX_SUPPLY = 1000000000 * 1e18;

    address public rewardPool;
    address public marketingAddress;
    address public priceBackingAddress;

    bool public rewardTriggerEnabled;
    bool public isTaxEnabled;


    constructor(
        address _marketingAddress,
        address _priceBackingAddress
    ) ERC20("HoloBet", "HBT") {
        require(_marketingAddress != address(0) && _priceBackingAddress != address(0),"Please Enter Valid Address");
        marketingAddress = _marketingAddress;
        priceBackingAddress = _priceBackingAddress;
        _mint(msg.sender, MAX_SUPPLY);


    }

    function flipTaxStatus() public onlyOwner{
        isTaxEnabled = !isTaxEnabled;
    }
   

    function flipRewardTriggerEnabled() public onlyOwner  {
        rewardTriggerEnabled = !rewardTriggerEnabled;
        if(rewardTriggerEnabled){
            _notifyRewardPool();
        }
    }

    function setRewardPool(address newAddress) public onlyOwner {
        require(newAddress != address(0),"Please Enter Valid Address");
        rewardPool = newAddress;
    }

    function setMarketingAddress(address newAddress) public onlyOwner {
        require(newAddress != address(0),"Please Enter Valid Address");
        marketingAddress = newAddress;
    }

    function setPriceBackingAddress(address newAddress) public onlyOwner {
        require(newAddress != address(0),"Please Enter Valid Address");
        priceBackingAddress = newAddress;
    }

    function manageAMMPairs(address pair, bool isAdd) public onlyOwner {
        require(pair != address(0),"Please Enter Valid Address");
        ammPairs[pair] = isAdd;
    }

    function manageSalesTaxWhitelist(address addr, bool isAdd)
        public
        onlyOwner
    {
        salesTaxWhitelist[addr] = isAdd;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        bool isTaxable = ammPairs[to] && !salesTaxWhitelist[from] && isTaxEnabled;
        if (isTaxable) {

            uint256  stakingRewardFee = amount * STAKING_REWARD_FEE/1000;
            uint256  marketingFee = amount * MARKETING_FEE/1000;
            uint256  priceBackingFee = amount * PRICE_BACKING_FEE/1000;
            takeRewardFee(from,stakingRewardFee);

            super._transfer(from, marketingAddress, marketingFee);
            super._transfer(from, priceBackingAddress, priceBackingFee);
            super._transfer(from, to, amount-(stakingRewardFee+marketingFee+priceBackingFee));
        } else {
            super._transfer(from, to, amount);
        }
    }


    function takeRewardFee(address from, uint256 amount) internal {
        super._transfer(from, address(this), amount);

        if(rewardTriggerEnabled && rewardPool !=address(0)){
            _notifyRewardPool();
        }
    }


    function notifyRewardPool() public {
        require(msg.sender == owner(),"not allowed");
        _notifyRewardPool();
    }  


     function _notifyRewardPool() internal {
        uint256 amount = balanceOf(address(this));
        super._transfer( address(this), rewardPool, amount);
        IRewardPool(rewardPool).harvest();
    }   

}
