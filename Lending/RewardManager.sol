
//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IHBTLendingStaking {
    function userInfo(address)
        external
        view
        returns (uint256 amount, bool hasTakenLoan);
}

contract RewardManager is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable REWARDTOKEN;
    mapping(address => uint256) public rewards;
    IHBTLendingStaking public immutable stakingContract;
    address public immutable lendingManager;

    event onRewardTopUp(address user, uint256 amount);
    event onRewardPaid(uint256 amount);
    event onRewardConfiscated(address user, uint256 amount);

    constructor(
        IERC20 _REWARDTOKEN,
        IHBTLendingStaking _stakingContract,
        address _lendingManager
    ) {
        REWARDTOKEN = _REWARDTOKEN;
        require(address(_stakingContract) != address(0) && _lendingManager != address(0));
        stakingContract = _stakingContract;
        lendingManager = _lendingManager;
    }

    function topUpRewards(address user, uint256 amount) public onlyOwner {
        REWARDTOKEN.safeTransferFrom(msg.sender, address(this), amount);
        rewards[user] += amount;
        emit onRewardTopUp(user, amount);
    }

    function withdrawRewards() public {
        uint256 rewardAmount = rewards[msg.sender];
        require(rewardAmount > 0, "ZERO Rewards");
        (, bool hasTakenLoan) = stakingContract.userInfo(msg.sender);
        require(!hasTakenLoan, "Please Clear Loan First");
        rewards[msg.sender] = 0;
        REWARDTOKEN.safeTransfer(msg.sender, rewardAmount);
        emit onRewardPaid(rewardAmount);
    }

    function confiscateRewards(address user) public {
        require(msg.sender == lendingManager, "not authorized");
        uint256 rewardAmount = rewards[user];
        rewards[user] = 0;
        REWARDTOKEN.safeTransfer(owner(), rewardAmount);

        emit onRewardConfiscated(user, rewardAmount);
    }



    function withdrawStuckTokens(IERC20 token) public  onlyOwner{
        token.safeTransfer(msg.sender, token.balanceOf(address(this)));
    }
}
