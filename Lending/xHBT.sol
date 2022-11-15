//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract xHBTToken is ERC20("xHBT", "xHBT"), Ownable {
    mapping(address => bool) public minters;
    mapping(address => bool) public transferWhitelist;

    function mint(address user, uint256 amount) public {
        require(minters[msg.sender], "address not minter");
        _mint(user, amount);
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }

    function manageMinters(address addr, bool isAdd) public onlyOwner {
        minters[addr] = isAdd;
    }

    function manageTransferWhitelist(address addr, bool isAdd)
        public
        onlyOwner
    {
        transferWhitelist[addr] = isAdd;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        require(
            transferWhitelist[from] || transferWhitelist[to],
            "Cannot Transfer to non whitelist address"
        );
        super._transfer(from, to, amount);
    }
}
