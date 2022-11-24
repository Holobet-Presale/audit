// SPDX-License-Identifier: MIT



import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

pragma solidity ^0.8.0;

contract PriceBacking is Ownable {
    using SafeERC20 for IERC20;
    IERC20 public immutable HBT;
    IERC20 public immutable USDC;

    bool public isEnabled;
    address[] public burnAddresses;
    mapping(address => bool) public burnAddressesMap;

    address public constant DEAD_ADDRESS =
        0x000000000000000000000000000000000000dEaD;

    event onConvert(uint256 hbtAmount, uint256 usdcAmount);

    constructor(
        IERC20 _HBT,
        IERC20 _USDC,
        address teamAllocationAddress
    ) {
        HBT = _HBT;
        USDC = _USDC;

        addBurnAddress(teamAllocationAddress);
        addBurnAddress(DEAD_ADDRESS);
    }

    function flipEnabled() public onlyOwner {
        isEnabled = !isEnabled;
    }

    function addBurnAddress(address addr) internal {
        require(!burnAddressesMap[addr], "Already Added");
        burnAddresses.push(addr);
        burnAddressesMap[addr] = true;
    }

    function getCirculationSupply() public view returns (uint256) {
        uint256 totalSupply = HBT.totalSupply();
        uint256 burnAddressesBalance = 0;
        for (uint256 i = 0; i < burnAddresses.length; i++) {
            burnAddressesBalance += HBT.balanceOf(burnAddresses[i]);
        }
        return totalSupply - burnAddressesBalance;
    }

    function HBTToUSDCRate() public view returns (uint256) {
        uint256 HBTCirculation = getCirculationSupply();
        uint256 USDCBalance = USDC.balanceOf(address(this));
        return ((USDCBalance) * 1e6) / (HBTCirculation/1e12);
    }

    function HBTToUSDC(uint256 hbtAmount) public view returns (uint256) {
        uint256 rate = HBTToUSDCRate();
        return ((rate*hbtAmount)/1e12)/1e6;
    }

    function convert(uint256 hbtAmount) public {
        require(isEnabled, "convert not enabled");
        uint256 preBalance = HBT.balanceOf(address(this));
        HBT.safeTransferFrom(msg.sender, address(this), hbtAmount);
        hbtAmount = HBT.balanceOf(address(this))-preBalance;
        uint256 usdcAmount = HBTToUSDC(hbtAmount);
        HBT.safeTransfer(DEAD_ADDRESS, hbtAmount);
        USDC.safeTransfer(msg.sender, usdcAmount);
        emit onConvert(hbtAmount, usdcAmount);
    }


    function withdrawHBT()  public onlyOwner{
        HBT.safeTransfer(msg.sender, HBT.balanceOf(address(this)) );
    }

}
