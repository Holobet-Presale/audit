// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

interface IMasterChef {



    
  
    function userInfo(address)
        external
        view
        returns (uint256 amount);

   
    function deposit(uint256 _amount) external;


    function withdraw(uint256 _amount) external;

    function emergencyWithdraw() external;


}

contract StratManager is Ownable, Pausable {
    address public keeper;
    address public vault;

    constructor(address _keeper, address _vault) {
        require(_keeper != address(0),"Please Enter Valid Address");

        keeper = _keeper;
        vault = _vault;
    }

    // checks that caller is either owner or keeper.
    modifier onlyManager() {
        require(msg.sender == owner() || msg.sender == keeper, "!manager");
        _;
    }

    /**
     * @dev Updates address of the strat keeper.
     * @param _keeper new keeper address.
     */
    function setKeeper(address _keeper) external onlyManager {
        require(_keeper != address(0),"Please Enter Valid Address");

        keeper = _keeper;
    }

    function setVault(address _vault) external onlyOwner {
        require(vault == address(0), "Cannot modify vault");
        vault = _vault;
    }
}

contract HBTVaultStrategy is StratManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public immutable want;

    // Third party contracts
    address public immutable masterchef;

    uint256 constant MAX_INT =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

   
    event OnDeposit(uint256 amount);
    event onWithdraw(uint256 amount);
    event onPanic();

    constructor(
        address _want,
        address _masterChef
    ) StratManager(msg.sender, address(0)) {
        require(_masterChef != address(0),"Please Enter Valid Address");
        require(_want != address(0),"Please Enter Valid Address");

        masterchef = _masterChef;
        want = _want;
        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IMasterChef(masterchef).deposit(wantBal);
        }

        emit OnDeposit(wantBal);
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IMasterChef(masterchef).withdraw(_amount.sub(wantBal));
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        IERC20(want).safeTransfer(vault, wantBal);
        emit onWithdraw(wantBal);
    }

  

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        return  IMasterChef(masterchef).userInfo(address(this));
    }
    
    // pauses deposits and withdraws all funds from third party systems.
    function panic() external onlyManager {
        pause();
        IMasterChef(masterchef).emergencyWithdraw();
        emit onPanic();
    }

    function pause() public onlyManager {
        _pause();

        _removeAllowances();
    }

    function unpause() external onlyManager {
        _unpause();

        _giveAllowances();

        deposit();
    }

    function _giveAllowances() internal {
        IERC20(want).safeApprove(masterchef, MAX_INT);
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(masterchef, 0);
    }
}
