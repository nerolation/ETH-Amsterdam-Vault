pragma solidity =0.8.9;

import "./interfaces/IPeriphery.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IMarginEngine.sol";
import "./interfaces/fcms/IFCM.sol";
import "./interfaces/rate_oracles/IRateOracle.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

interface IAAVE {
    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);
}

contract VoltzUSDC is ERC20, Ownable {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function adminMint(address to, uint amount) external onlyOwner {
        _mint(to, amount);
    }

    function adminBurn(address from, uint amount) external onlyOwner {
        _burn(from, amount);
    }
}

contract JointVaultStrategy {
    //
    // Constants
    //

    uint160 MIN_SQRT_RATIO = 2503036416286949174936592462;
    uint160 MAX_SQRT_RATIO = 2507794810551837817144115957740;

    //
    // Token contracts
    //

    IERC20 public variableRateToken; // AUSDC
    IERC20 public underlyingToken; // USDC
    IERC20 public JVUSDC; // JVUSDC
    VoltzUSDC public token; // JVUSDC ERC instantiation

    //
    // Aave contracts
    //
    IAAVE AAVE;

    //
    // Voltz contracts
    //

    IFactory factory;
    IPeriphery periphery;
    IMarginEngine marginEngine;
    IFCM fcm;

    //
    // Logic variables
    //

    CollectionWindow public collectionWindow;
    uint256 public termEnd; // unix timestamp in seconds
    uint public crate; // Conversion rate

    //
    // Structs
    //

    struct CollectionWindow {
        uint256 start; // unix timestamp in seconds
        uint256 end; // unix timestamp in seconds
    }

    //
    // Modifiers
    //

    modifier isInCollectionWindow() {
        require(collectionWindowSet(), "Collection window not set");
        require(inCollectionWindow(), "Collection window not open");
        _;
    }

    modifier isNotInCollectionWindow() {
        require(collectionWindowSet(), "Collection window not set");
        require(!inCollectionWindow(), "Collection window open");
        _;
    }

    modifier canExecute() {
        require(isAfterCollectionWindow(), "Collection round has not finished");
        _;
    }

    modifier canSettle() {
        require(isAfterEndTerm(), "Not past term end");
        _;
    }

    constructor(
        address _variableRateToken,
        address _underlyingToken,
        address _factory,
        address _fcm,
        address _marginEngine,
        address _aave,
        CollectionWindow memory _collectionWindow
    ) {
        // Token contracts
        variableRateToken = IERC20(_variableRateToken);
        underlyingToken = IERC20(_underlyingToken);

        // Deploy JVUSDC token
        token = new VoltzUSDC("Joint Voltz USDC", "jvUSDC"); 
        JVUSDC = IERC20(address(token));

        // Voltz contracts
        factory = IFactory(_factory);
        periphery = IPeriphery(factory.periphery());
        fcm = IFCM(_fcm);
        marginEngine = IMarginEngine(_marginEngine);

        // Aave contracts
        AAVE = IAAVE(_aave);

        // Set initial collection window
        collectionWindow = _collectionWindow;

        // initialize conversion rate
        crate = 100; 
    }

    //
    // Modifier helpers
    //

    function collectionWindowSet() internal returns (bool) {
        return collectionWindow.start != 0 && collectionWindow.end != 0;
    }

    function inCollectionWindow() internal returns (bool) {
        return block.timestamp >= collectionWindow.start && block.timestamp < collectionWindow.end;
    }

    function isAfterCollectionWindow() internal returns (bool) {
        // TODO: Also ensure that it's before the start of the next collection window
        return block.timestamp > collectionWindow.end;
    }

    function isAfterEndTerm() internal returns (bool) {
        return block.timestamp >= termEnd;
    }

    //
    // Data functions
    //

    // Returns factor in 2 decimal format to handle sub 1 numbers.
    function conversionFactor() public view returns (uint256) {
        require(JVUSDC.totalSupply() != 0, "JVUSDC totalSupply is zero");

        return (
            variableRateToken.balanceOf(address(this)) * 100
            / JVUSDC.totalSupply()
        );
    }

    //
    // Strategy functions
    //

    function execute() public canExecute {
        variableRateToken.approve(address(fcm), 10 * 1e18);

        fcm.initiateFullyCollateralisedFixedTakerSwap(10 * 1e18, MAX_SQRT_RATIO - 1);

        termEnd = marginEngine.termEndTimestampWad() / 1e18;
    }

    function settle() public canSettle {
        fcm.settleTrader();
    }

    //
    // User functions
    //

    function deposit(uint256 amount) public isInCollectionWindow {
        require(underlyingToken.allowance(msg.sender, address(this)) >= amount, "Not enough allowance");

        bool success = underlyingToken.transferFrom(msg.sender, address(this), amount);        
        require(success);

        success = underlyingToken.approve(address(AAVE), amount);
        require(success);

        uint256 finalAmount = amount / crate * 100;
        AAVE.deposit(address(underlyingToken), finalAmount, address(this), 0);

        token.adminMint(msg.sender, amount);      
    }

    function withdraw(uint256 amount) public isInCollectionWindow {
        require(JVUSDC.allowance(msg.sender, address(this)) > 0, "No allowance");
        bool success = JVUSDC.transferFrom(msg.sender, address(this), amount);
        require(success);
        token.adminBurn(address(this), amount);
        uint256 finalAmount = crate * amount / 100;

        uint256 wa = AAVE.withdraw(address(underlyingToken), finalAmount, address(this));
        require(wa == finalAmount, "Not enough collateral");

        success = underlyingToken.transfer(msg.sender, finalAmount);
        require(success);      
    }

    function contractBalanceUsdc() public view returns (uint256){
        return underlyingToken.balanceOf(address(this));      
    }

    function contractBalanceAUsdc() public view returns (uint256){
        return variableRateToken.balanceOf(address(this));      
    }

    fallback() external {
        if (msg.sender == address(token)) {
            revert("No known function targeted");
        }
    }
}
