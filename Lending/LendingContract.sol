//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";



interface IHBTLendingStaking {
    function userInfo(address)
        external
        view
        returns (uint256 amount, bool hasTakenLoan);

    function manageLoan(address user, bool hasTakenLoan) external;

    function isStakingEnabled() external view returns (bool isEnabled);

    function confiscateStaking(address _user) external;
}

interface IXHBT is IERC20 {
    function mint(address user, uint256 amount) external;

    function burn(uint256 amount) external;
}

interface IRewardManager {
    function confiscateRewards(address user) external;
}


library DSMath {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }

    function min(uint x, uint y) internal pure returns (uint z) {
        return x <= y ? x : y;
    }
    function max(uint x, uint y) internal pure returns (uint z) {
        return x >= y ? x : y;
    }
    function imin(int x, int y) internal pure returns (int z) {
        return x <= y ? x : y;
    }
    function imax(int x, int y) internal pure returns (int z) {
        return x >= y ? x : y;
    }

    uint constant WAD = 10 ** 18;
    uint constant RAY = 10 ** 27;

    //rounds to zero if x*y < WAD / 2
    function wmul(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, y), WAD / 2) / WAD;
    }
    //rounds to zero if x*y < WAD / 2
    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, y), RAY / 2) / RAY;
    }
    //rounds to zero if x*y < WAD / 2
    function wdiv(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, WAD), y / 2) / y;
    }
    //rounds to zero if x*y < RAY / 2
    function rdiv(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, RAY), y / 2) / y;
    }

    // This famous algorithm is called "exponentiation by squaring"
    // and calculates x^n with x as fixed-point and n as regular unsigned.
    //
    // It's O(log n), instead of O(n) for naive repeated multiplication.
    //
    // These facts are why it works:
    //
    //  If n is even, then x^n = (x^2)^(n/2).
    //  If n is odd,  then x^n = x * x^(n-1),
    //   and applying the equation for even x gives
    //    x^n = x * (x^2)^((n-1) / 2).
    //
    //  Also, EVM division is flooring and
    //    floor[(n-1) / 2] = floor[n / 2].
    //
    function rpow(uint x, uint n) internal pure returns (uint z) {
        z = n % 2 != 0 ? x : RAY;

        for (n /= 2; n != 0; n /= 2) {
            x = rmul(x, x);

            if (n % 2 != 0) {
                z = rmul(z, x);
            }
        }
    }
}

contract HBTLending is Ownable {
    using SafeERC20 for IERC20;
    IHBTLendingStaking public immutable stakingContract;

    struct Loan {
        uint256 amount;
        uint256 loanTime;
        uint256 interestFreeDays;
        uint256 interestRate;
        uint256 confiscationDeadLine;
    }

    IXHBT public immutable xHBT;
    IERC20 public immutable HBT;

    mapping(address => Loan) public loans;

    IRewardManager public REWARDMANAGER;

    uint256 public constant ONE_DAY = 1 days;
    uint256 public interestFreeDays = ONE_DAY * 21;
    uint256 public confiscationDeadline = ONE_DAY * 366;

    // interest rate in  wei i.e 1% annualy = 1e18
    uint256 public interestRateAnnually;

    event onTakeLoan(
        uint256 amount,
        uint256 interestFreeDays,
        uint256 interestRate,
        uint256 confiscationDeadLine
    );
    event onLoanReset(uint256 amount);
    event onLoanConfiscated(address user);
    event onBalancexHBT(address user, uint256 amount);

    constructor(
        IXHBT _xHBT,
        IERC20 _HBT,
        IHBTLendingStaking _stakingContract,
        uint256 _interestRateAnnually
    ) {
        xHBT = _xHBT;
        HBT = _HBT;
        stakingContract = _stakingContract;
        setInterestRateAnnually(_interestRateAnnually);
    }

    function setInterestRateAnnually(uint256 newRate) public onlyOwner {
        require(newRate <= 50 ether, "Cannot set more than 50%");
        interestRateAnnually = newRate;
    }

    function setInterestFreeDays(uint256 newDuration) public onlyOwner {
        interestFreeDays = newDuration;
    }

    function setConfiscationDays(uint256 newDuration) public onlyOwner {
        require(
            newDuration >= 180 * ONE_DAY,
            "can set duration less than 6 months"
        );
        confiscationDeadline = newDuration;
    }

    function setRewardManager(IRewardManager _REWARDMANAGER) public onlyOwner {
        require(address(REWARDMANAGER) == address(0), "Already Set");
        REWARDMANAGER = _REWARDMANAGER;
    }

    function takeLoan() external {
        require(canTakeLoan(), "Loan is disabled");
        (uint256 amount, bool hasTakenLoan) = stakingContract.userInfo(
            msg.sender
        );
        require(!hasTakenLoan, "Loan has already taken");
        require(amount > 0, "Please Stake First");
        stakingContract.manageLoan(msg.sender, true);
        loans[msg.sender] = Loan({
            amount: amount,
            loanTime: block.timestamp,
            interestFreeDays: interestFreeDays,
            interestRate: interestRateAnnually,
            confiscationDeadLine: confiscationDeadline
        });
        xHBT.mint(msg.sender, amount);
        emit onTakeLoan(
            amount,
            interestFreeDays,
            interestRateAnnually,
            confiscationDeadline
        );
    }

    function resetLoan(address user) internal {
        Loan storage loan = loans[user];
        emit onLoanReset(loan.amount);
        loan.amount = 0;
        loan.confiscationDeadLine = 0;
        loan.interestFreeDays = 0;
        loan.interestRate = 0;
        loan.loanTime = 0;
        stakingContract.manageLoan(user, false);
    }

    function getUserInterest(address user,uint256 maxAmount) public view returns (uint256) {
        uint256 interestAmount = 0;
        Loan storage loan = loans[user];
        bool isInterestFree = (loan.loanTime + loan.interestFreeDays) >
            block.timestamp;
        if (loan.amount > 0 && !isInterestFree) {
            uint256 daysPassed = ((block.timestamp -
                loan.loanTime -
                loan.interestFreeDays) / ONE_DAY);
            
            interestAmount = accrueInterest(loan.amount,loan.interestRate,daysPassed);
        }

        if(interestAmount> maxAmount){
            return maxAmount;
        }
        
        return interestAmount;
    }

    function canTakeLoan() public view returns (bool) {
        return !stakingContract.isStakingEnabled();
    }

    function HBTToXHBTDeficit(address addr) public view returns (uint256) {
        Loan storage loan = loans[addr];

        uint256 deficit = 0;
        uint256 xHBTBalance = xHBT.balanceOf(addr);
        if (loan.amount > xHBTBalance) {
            deficit = loan.amount - xHBTBalance;
        }
        return deficit;
    }

    function balanceDeficitxHBT(address account, uint256 amount) internal {
        if (amount > 0) {
            HBT.safeTransferFrom(account, address(this), amount);
            emit onBalancexHBT(account, amount);
        }
    }

    function repayLoan() external {
        Loan storage loan = loans[msg.sender];
        (uint256 stakedAmount, bool hasTakenLoan) = stakingContract.userInfo(
            msg.sender
        );
        require(hasTakenLoan, "Dont have any loan");

        uint256 HBTToxHBTDeficit = HBTToXHBTDeficit(msg.sender);
        if (HBTToxHBTDeficit > 0) {
            balanceDeficitxHBT(msg.sender, HBTToxHBTDeficit);
        }

        xHBT.transferFrom(
            msg.sender,
            address(this),
            loan.amount - HBTToxHBTDeficit
        );
        xHBT.burn(loan.amount - HBTToxHBTDeficit);

        uint256 interestAmount = getUserInterest(msg.sender,stakedAmount);
        if (interestAmount > 0) {
            HBT.safeTransferFrom(msg.sender, address(this), interestAmount);
        }

        resetLoan(msg.sender);
    }

    function withdrawAllTokens(IERC20 token) external onlyOwner {
        token.safeTransfer(msg.sender, token.balanceOf(address(this)));
    }

    function confiscateLoan(address user) public onlyOwner {
        Loan storage loan = loans[user];
        require(loan.amount > 0, "Dont have any loan");
        require(
            loan.loanTime + loan.confiscationDeadLine < block.timestamp,
            "Confiscation period not reached"
        );
        stakingContract.confiscateStaking(user);
        REWARDMANAGER.confiscateRewards(user);
        resetLoan(user);
        emit onLoanConfiscated(user);
    }

    function confiscateLoans(address[] memory users) public onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            confiscateLoan(users[i]);
        }
    }







    function wadToRay(uint _wad) internal pure returns (uint) {
        return DSMath.mul(_wad, 10 ** 9);
    }

    // Go from wei to ray (10**27)
    function weiToRay(uint _wei) internal pure returns (uint) {
        return DSMath.mul(_wei, 10 ** 27);
    } 


    function yearlyRateToRay(uint _rateWad) internal pure returns (uint) {
        return DSMath.add(wadToRay(1 ether), DSMath.rdiv(wadToRay(_rateWad), weiToRay(365*1 days)));
    }


     function accrueInterest(uint256 _principal, uint256 interestRate, uint256 daysPassed) internal pure returns (uint) {
        uint256 finalRate = interestRate/100;
        uint256 ageInSeconds = daysPassed* 1 days;
        uint256 rate = yearlyRateToRay(finalRate);
        return DSMath.rmul(_principal, DSMath.rpow(rate, ageInSeconds))-_principal;
    }
}
