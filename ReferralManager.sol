// SPDX-License-Identifier: MIT


pragma solidity ^0.8.0;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
// File: contracts/ReferralManager.sol

pragma solidity ^0.8.15;



contract HBTReferral is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable HBT;

    bool public referralComissionClaimEnabled;
    mapping(address => bool) public operators;
    mapping(address => address) public referrers; // user address => referrer address
    mapping(address => uint256) public referralsCount; // referrer address => referrals count

    mapping(address => uint256) public referralComission;
    event ReferralRecorded(address indexed user, address indexed referrer);
    event OperatorUpdated(address indexed operator, bool indexed status);

    event ReferralComissionRecorded(address user, uint256 amount);
    event onComissionPaid(uint256 amount);

    constructor(IERC20 _HBT) {
        HBT = _HBT;
    }

    modifier onlyOperator() {
        require(operators[msg.sender], "Operator: caller is not the operator");
        _;
    }

    function flipReferralComissionClaimEnabled() public onlyOperator {
        referralComissionClaimEnabled = !referralComissionClaimEnabled;
    }

    function recordReferral(address _user, address _referrer)
        public
        onlyOperator
    {
        if (
            _user != address(0) &&
            _referrer != address(0) &&
            _user != _referrer &&
            referrers[_user] == address(0)
        ) {
            referrers[_user] = _referrer;
            referralsCount[_referrer] += 1;
            emit ReferralRecorded(_user, _referrer);
        }
    }

    function recordComission(address user, uint256 amount) public onlyOperator {
        HBT.safeTransferFrom(msg.sender, address(this), amount);
        referralComission[user] += amount;
        emit ReferralComissionRecorded(user, amount);
    }

    function claimReferralComission() public {
        require(referralComissionClaimEnabled, "Claim not enabled");
        require(referralComission[msg.sender] > 0, "No comission");
        uint256 amount = referralComission[msg.sender];
        referralComission[msg.sender] = 0;
        HBT.safeTransfer(msg.sender, amount);
        emit onComissionPaid(amount);
    }

    // Get the referrer address that referred the user
    function getReferrer(address _user) public view returns (address) {
        return referrers[_user];
    }

    // Update the status of the operator
    function updateOperator(address _operator, bool _status)
        external
        onlyOwner
    {
        operators[_operator] = _status;
        emit OperatorUpdated(_operator, _status);
    }
}
