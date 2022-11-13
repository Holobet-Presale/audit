//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract HBTMasterChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;




    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 totalTokensLocked; // totalTokensLocked in pool
    }

    PoolInfo public poolInfo;

    mapping(address => UserInfo) public userInfo;
    uint256 public immutable startBlock;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);


    constructor(
        IERC20 _hbt,
        uint256 _startBlock
    ) {
        startBlock = block.number;
     
        add(1000, _hbt);
    }

    function add(
        uint256 _allocPoint,
        IERC20 _lpToken
       
    ) internal {
      
        uint256 lastRewardBlock = block.number > startBlock
            ? block.number
            : startBlock;
        poolInfo = PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            totalTokensLocked: 0
        });
    }

  

    function deposit(uint256 _amount) public  {
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[msg.sender];
      

    
        if (_amount > 0) {
            uint256 preAmount = pool.lpToken.balanceOf(address(this)); // deflationary check
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            _amount = pool.lpToken.balanceOf(address(this)).sub(preAmount);
            pool.totalTokensLocked = pool.totalTokensLocked.add(_amount);
            user.amount = user.amount.add(_amount);
        }

       
        emit Deposit(msg.sender, _amount);
    }

  
    // Withdraw LP tokens from .
    function withdraw(uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
       
      

        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.totalTokensLocked = pool.totalTokensLocked.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
    
        emit Withdraw(msg.sender, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw() public nonReentrant {
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
      
        pool.totalTokensLocked = pool.totalTokensLocked.sub(amount);
        pool.lpToken.safeTransfer(address(msg.sender), amount);

        emit EmergencyWithdraw(msg.sender, amount);
    }

   
}
