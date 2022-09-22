pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract USDC is ERC20("USDC", "USDC") {
    using SafeERC20 for IERC20;

    constructor() {
     _mint(msg.sender, 1000000000000*1e18);

    }

 function decimals() public view virtual override returns (uint8) {
        return 6;
    }
  

    function mintFor(address user, uint256 amount) public {
        _mint(user, amount);
    }

  
}
