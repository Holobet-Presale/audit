
// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

pragma solidity ^0.8.15;

interface IReferralManager {
    function recordReferral(address _user, address _referrer) external;

    function getReferrer(address _user) external view returns (address);

    function recordComission(address user, uint256 amount) external;
}

// File: contracts/Presale.sol

pragma solidity ^0.8.15;

interface IVault is IERC20 {
    function deposit(uint256 _amount) external;

    function withdraw(uint256 _amount) external;

    function getPricePerFullShare() external view returns (uint256);
}

contract HBTPresale is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 public immutable USDC;
    IERC20 public immutable HBT;

    IReferralManager public referralManager;

    struct PresaleInfo {
        uint256 totalHBTBought;
        uint256 totalUSDCPaid;
        uint256 totalHBTClaimed;
        uint256 totalVaultReceiptAmount;
        uint256 claimedTrenches;
        uint256 nextClaimTime;
        uint256 totalRewardClaimed;
    }

    mapping(address => PresaleInfo) public purchaseInfo;

    IVault public vault;
    uint256 public immutable cliffTime;
    uint256 public totalTokenSold;
    uint256 public totalUSDCRaised;
    uint256 public immutable maxTrenches;
    uint256 public constant REFERRAL_COMISSION = 25; //2.5%
    uint256 public constant BONUS = 25; //2.5%

    uint256 constant ONE_DAY = 1 days;
    uint256 public constant ONE_MONTH = 30 * ONE_DAY;

    uint256 public tokenPrice;
    bool public isParticipationOpen;
    uint256 constant MAX_INT =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    uint256 public presaleEndTime;

    event onClaim(uint256 hbtAmount, uint256 hbtReward);
    event onParticipate(
        uint256 hbtAmount,
        uint256 usdcAmount,
        address referrer
    );

    event onRewardClaim(uint256 hbtReward);

    constructor(
        IERC20 _USDC,
        IERC20 _HBT,
        uint256 _tokenPrice,
        uint256 _cliffTime,
        uint256 _maxTrenches
    ) {
        USDC = _USDC;
        HBT = _HBT;
        tokenPrice = _tokenPrice;
        cliffTime = _cliffTime;
        maxTrenches = _maxTrenches;
    }

    function setVault(IVault _vault) public onlyOwner {
        require(address(vault) == address(0), "vault already set");
        vault = _vault;
        HBT.safeApprove(address(_vault), MAX_INT);
    }

    function changeTokenPrice(uint256 newPrice) public onlyOwner {
        tokenPrice = newPrice;
    }

    function finishParticipations() public onlyOwner {
        require(presaleEndTime == 0, "Presale already finished");
        presaleEndTime = block.timestamp;
    }

    function baseTime() public view returns (uint256) {
        return presaleEndTime + cliffTime;
    }

    function setReferralManager(IReferralManager _referralManager)
        public
        onlyOwner
    {
        referralManager = _referralManager;

        HBT.safeApprove(address(referralManager), MAX_INT);
    }

    function flipParticipationStatus() public onlyOwner {
        isParticipationOpen = !isParticipationOpen;
    }

    function participate(uint256 usdcAmount, address referralAddress) public {
        require(isParticipationOpen, "Participation is not opened");
        require(presaleEndTime == 0, "Participation Closed");
        USDC.safeTransferFrom(msg.sender, address(this), usdcAmount);

        purchaseInfo[msg.sender].totalUSDCPaid += usdcAmount;

        address finalReferral = referralManager.getReferrer(msg.sender);
        if (finalReferral == address(0)) {
            if (referralAddress == address(0)) {
                referralAddress = owner();
            }
            referralManager.recordReferral(msg.sender, referralAddress);
            finalReferral = referralAddress;
        }

        uint256 hbtAmount = usdcToHBT(usdcAmount);

        uint256 referralComissionAmount = (hbtAmount.mul(REFERRAL_COMISSION))
            .div(1000);

        referralManager.recordComission(finalReferral, referralComissionAmount);

        uint256 bonus = (hbtAmount.mul(BONUS)).div(1000);
        uint256 finalHBTAmountAfterBonus = hbtAmount.add(bonus);
        purchaseInfo[msg.sender].totalHBTBought += finalHBTAmountAfterBonus;

        uint256 preVaultReceipt = vault.balanceOf(address(this));
        vault.deposit(finalHBTAmountAfterBonus);
        uint256 finalVaultReceiptBalance = vault.balanceOf(address(this)).sub(
            preVaultReceipt
        );
        purchaseInfo[msg.sender]
            .totalVaultReceiptAmount += finalVaultReceiptBalance;
        totalTokenSold += finalHBTAmountAfterBonus;
        totalUSDCRaised += usdcAmount;
        emit onParticipate(hbtAmount, usdcAmount, finalReferral);
    }

    function usdcToHBT(uint256 usdcAmount) public view returns (uint256) {
        return (usdcAmount * 1e18) / tokenPrice;
    }

    function withdrawToken(IERC20 _token) public onlyOwner {
        require(
            address(_token) != address(vault),
            "Cannot withdraw receipt tokens"
        );
        _token.safeTransfer(msg.sender, _token.balanceOf(address(this)));
    }

  

    function getPendingReward(address user) public view returns (uint256) {
        if (purchaseInfo[user].totalVaultReceiptAmount == 0) {
            return 0;
        }

        uint256 receiptOwned = purchaseInfo[user].totalVaultReceiptAmount;

        uint256 vestedInHBT = purchaseInfo[user].totalHBTBought.sub(
            purchaseInfo[user].totalHBTClaimed
        );

        uint256 stakedFinalBalance = (receiptOwned *
            vault.getPricePerFullShare()).div(1e18);

        if (stakedFinalBalance < vestedInHBT) {
            return 0;
        }
        return stakedFinalBalance.sub(vestedInHBT);
    }

    function claim() public {
        require(presaleEndTime > 0, "Withdraw not enabled");
        require(baseTime() < block.timestamp, "cliff period not passed");
        require(
            purchaseInfo[msg.sender].nextClaimTime < block.timestamp,
            "Time not passed"
        );
        require(
            purchaseInfo[msg.sender].claimedTrenches < maxTrenches,
            "Exceeds Max Trenches"
        );

        uint256 totalVestedAmount = purchaseInfo[msg.sender].totalHBTBought;

        uint256 remainingVestedAmount = totalVestedAmount.sub(
            purchaseInfo[msg.sender].totalHBTClaimed
        );

        uint256 timePassed = block.timestamp.sub(presaleEndTime);

        uint256 claimableTrenches = timePassed.div(ONE_MONTH);

        if (claimableTrenches > maxTrenches) {
            claimableTrenches = maxTrenches;
        }

        claimableTrenches = claimableTrenches.sub(
            purchaseInfo[msg.sender].claimedTrenches
        );

        uint256 tokensToClaim = (totalVestedAmount.mul(claimableTrenches)).div(maxTrenches);
        purchaseInfo[msg.sender].nextClaimTime =
            block.timestamp +
            ONE_MONTH -
            (timePassed % ONE_MONTH);
        purchaseInfo[msg.sender].claimedTrenches += claimableTrenches;

        uint256 totalReceipts = purchaseInfo[msg.sender]
            .totalVaultReceiptAmount;

        uint256 preHBTBal = HBT.balanceOf(address(this));
        vault.withdraw(totalReceipts);
        uint256 finalHBTBal = HBT.balanceOf(address(this)).sub(preHBTBal);
        uint256 rewardProfit = 0;
        if (finalHBTBal > remainingVestedAmount) {
            rewardProfit = finalHBTBal.sub(remainingVestedAmount);
        }

        uint256 reStakeAmount = 0;

        if (purchaseInfo[msg.sender].claimedTrenches < maxTrenches) {
            reStakeAmount = finalHBTBal.sub(tokensToClaim).sub(rewardProfit);
        }

        if (reStakeAmount > 0) {
            uint256 preReceipt = vault.balanceOf(address(this));
            vault.deposit(reStakeAmount);
            uint256 finalReceipt = vault.balanceOf(address(this)).sub(
                preReceipt
            );
            purchaseInfo[msg.sender].totalVaultReceiptAmount = finalReceipt;
        } else {
            purchaseInfo[msg.sender].totalVaultReceiptAmount = 0;
        }

        purchaseInfo[msg.sender].totalHBTClaimed += tokensToClaim;
        purchaseInfo[msg.sender].totalRewardClaimed += rewardProfit;
        HBT.safeTransfer(msg.sender, tokensToClaim + rewardProfit);
        emit onClaim(tokensToClaim, rewardProfit);
    }

    function harvestReward() public {
        uint256 preHBTBalance = HBT.balanceOf(address(this));
        uint256 totalVaultReceiptAmount = purchaseInfo[msg.sender]
            .totalVaultReceiptAmount;
        vault.withdraw(totalVaultReceiptAmount);
        uint256 finalHBTBalance = HBT.balanceOf(address(this)) - preHBTBalance;
        uint256 totalVestedAmount = purchaseInfo[msg.sender].totalHBTBought;
        uint256 remainingVestedAmount = totalVestedAmount -
            purchaseInfo[msg.sender].totalHBTClaimed;
        uint256 rewards = finalHBTBalance - remainingVestedAmount;

        uint256 reStakeAmount = finalHBTBalance - rewards;
        if (reStakeAmount > 0) {
            uint256 preReceipt = vault.balanceOf(address(this));
            vault.deposit(reStakeAmount);
            uint256 finalReceipt = vault.balanceOf(address(this)) - preReceipt;
            purchaseInfo[msg.sender].totalVaultReceiptAmount = finalReceipt;
        } else {
            purchaseInfo[msg.sender].totalVaultReceiptAmount = 0;
        }

        purchaseInfo[msg.sender].totalRewardClaimed += rewards;

        HBT.safeTransfer(msg.sender, rewards);
        emit onRewardClaim(rewards);
    }
}
