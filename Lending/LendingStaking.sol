//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract HBTLendingStaking is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;
        bool hasTakenLoan;
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 totalTokensLocked; // totalTokensLocked in pool
    }

    PoolInfo public poolInfo;
    address public lendingManager;

    bool public isStakingEnabled;

    mapping(address => UserInfo) public userInfo;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event onConfiscateStaking(address indexed user, uint256 amount);

    constructor(IERC20 _hbt) {
        poolInfo = PoolInfo({lpToken: _hbt, totalTokensLocked: 0});
    }

    function setLendingManager(address newAddress) public onlyOwner {
        require(newAddress != address(0), "Please Enter Valid Address");
        lendingManager = newAddress;
    }

    function deposit(uint256 _amount) public {
        require(isStakingEnabled, "Staking Not Enabled");
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[msg.sender];
        require(
            !user.hasTakenLoan,
            "Cannot stake more before clearing the loan"
        );

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

    function manageLoan(address user, bool hasTakenLoan) public {
        require(msg.sender == lendingManager, "not authorized");
        UserInfo storage _user = userInfo[user];
        _user.hasTakenLoan = hasTakenLoan;
    }

    function flipDepositStatus() public onlyOwner {
        isStakingEnabled = !isStakingEnabled;
    }

    function withdraw(uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[msg.sender];
        require(!user.hasTakenLoan, "Please Clear The Loan First");
        require(user.amount >= _amount, "withdraw: not good");
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.totalTokensLocked = pool.totalTokensLocked.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }

        emit Withdraw(msg.sender, _amount);
    }

    function confiscateStaking(address _user) public nonReentrant {
        require(msg.sender == lendingManager, "not authorized");

        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[_user];
        uint256 amount = user.amount;
        if (amount > 0) {
            user.amount = 0;
            pool.totalTokensLocked = pool.totalTokensLocked.sub(amount);
            pool.lpToken.safeTransfer(address(lendingManager), amount);
        }

        emit onConfiscateStaking(_user, amount);
    }
}
