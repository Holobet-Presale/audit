// SPDX-License-Identifier: MIT
// File: @openzeppelin/contracts/GSN/Context.sol

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";


interface IStrategy {
    function vault() external view returns (address);

    function want() external view returns (IERC20);

    function beforeDeposit() external;

    function deposit() external;

    function withdraw(uint256) external;

    function balanceOf() external view returns (uint256);


    function panic() external;

    function pause() external;

    function unpause() external;

    function paused() external view returns (bool);

    function pendingReward() external view returns (uint256);
}

/**
 * @dev Implementation of a vault to deposit funds for yield optimizing.
 * This is the contract that receives funds and that users interface with.
 * The yield optimizing strategy itself is implemented in a separate 'Strategy.sol' contract.
 */
contract HBTVault is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    event OnDeposit(uint256 amount, address user);
    event onWithdraw(uint256 amount, address user);
    event onTokenGetStuck(address token, uint256 amount);

    IStrategy public immutable strategy;
    mapping(address => bool) private depositWhitelist;

    constructor(
        IStrategy _strategy,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        strategy = _strategy;
    }

    function want() public view returns (IERC20) {
        return IERC20(strategy.want());
    }

    function manageDepositWhitelist(address user, bool isAdd) public onlyOwner {
        depositWhitelist[user] = isAdd;
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        require(recipient != address(this), "!Use deposit function");
        return super.transfer(recipient, amount);
    }

    /**
     * @dev It calculates the total underlying value of {token} held by the system.
     * It takes into account the vault contract balance, the strategy contract balance
     *  and the balance deployed in other contracts as part of the strategy.
     */
    function balance() public view returns (uint256) {
        return
            want().balanceOf(address(this)).add(
                IStrategy(strategy).balanceOf()
            );
    }

  

    /**
     * @dev Custom logic in here for how much the vault allows to be borrowed.
     * We return 100% of tokens for now. Under certain conditions we might
     * want to keep some of the system funds at hand in the vault, instead
     * of putting them to work.
     */
    function available() public view returns (uint256) {
        return want().balanceOf(address(this));
    }

    /**
     * @dev Function for various UIs to display the current value of one of our yield tokens.
     * Returns an uint256 with 18 decimals of how much underlying asset one vault share represents.
     */
    function getPricePerFullShare() public view returns (uint256) {
        return
            totalSupply() == 0 ? 1e18 : balance().mul(1e18).div(totalSupply());
    }

    /**
     * @dev A helper function to call deposit() with all the sender's funds.
     */
    function depositAll() external {
        deposit(want().balanceOf(msg.sender));
    }

    /**
     * @dev The entrypoint of funds into the system. People deposit with this function
     * into the vault. The vault is then in charge of sending funds into the strategy.
     */
    function deposit(uint256 _amount) public nonReentrant {
        require(_amount > 0, "amount should be more than zero");
        require(depositWhitelist[msg.sender], "Cannot deposit");
        strategy.beforeDeposit();
        uint256 _pool = balance();
        want().safeTransferFrom(msg.sender, address(this), _amount);

        earn(_amount);
        uint256 _after = balance();
        _amount = _after.sub(_pool); // Additional check for deflationary tokens
        uint256 shares = 0;
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(totalSupply())).div(_pool);
        }
        _mint(msg.sender, shares);

        emit OnDeposit(_amount, msg.sender);
    }

    /**
     * @dev Function to send funds into the strategy and put them to work. It's primarily called
     * by the vault's deposit() function.
     */
    function earn(uint256 _amount) public {
        want().safeTransfer(address(strategy), _amount);
        strategy.deposit();
    }

    /**
     * @dev A helper function to call withdraw() with all the sender's funds.
     */
    function withdrawAll() external {
        withdraw(balanceOf(msg.sender));
    }

    /**
     * @dev Function to exit the system. The vault will withdraw the required tokens
     * from the strategy and pay up the token holder. A proportional number of IOU
     * tokens are burned in the process.
     */
    function withdraw(uint256 _shares) public {
        uint256 r = (balance().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);

        uint256 b = want().balanceOf(address(this));
        if (b < r) {
          
            uint256 _withdraw = r.sub(b);
            strategy.withdraw(_withdraw);
            uint256 _after = want().balanceOf(address(this));
            r = _after;
        }

        uint256 withdrawAmount = r;

       
        want().safeTransfer(msg.sender, withdrawAmount);

        emit onWithdraw(withdrawAmount, msg.sender);
    }

    function inCaseTokensGetStuck(address _token) external onlyOwner {
        require(_token != address(want()), "!token");
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
        emit onTokenGetStuck(_token, amount);
    }
}
