pragma solidity =0.8.9;

import "./interfaces/IPeriphery.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IMarginEngine.sol";
import "./interfaces/fcms/IFCM.sol";
import "./interfaces/IAAVE.sol";
import "./JointVaultUSDC.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "hardhat/console.sol";

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
    JointVaultUSDC public JVUSDC; // JVUSDC ERC instantiation

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
    uint public cRate; // Conversion rate

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
        JVUSDC = new JointVaultUSDC("Joint Vault USDC", "jvUSDC"); 

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
        cRate = 100; 
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
            variableRateToken.balanceOf(address(this)) * 100 * 10 ** 12
            / JVUSDC.totalSupply()
        );
    }

    function updateCRate() internal { // restriction needed
        cRate = conversionFactor();
    }

    //
    // Strategy functions
    //

    function execute() public canExecute {
        variableRateToken.approve(address(fcm), variableRateToken.balanceOf(address(this)));

        fcm.initiateFullyCollateralisedFixedTakerSwap(variableRateToken.balanceOf(address(this)), MAX_SQRT_RATIO - 1);

        termEnd = marginEngine.termEndTimestampWad() / 1e18;
    }

    function updateCollectionWindow() public {
        collectionWindow.start = termEnd;
        collectionWindow.end = termEnd + 86400; // termEnd + 1 day
    }

    function settle() public canSettle {
        // get AUSDC and USDC from Voltz position
        fcm.settleTrader();

        // Update cRate
        updateCRate();
        
        // Convert USDC to AUSDC
        // AAVE.deposit(address(underlyingToken), variableRateToken.balanceOf(address(this)), address(this), 0);

        updateCollectionWindow();
    }

    //
    // User functions
    //
    
    // @notice Initiate deposit to AAVE Lending Pool and receive jvUSDC
    // @param  Amount of USDC to deposit to AAVE
    function deposit(uint256 amount) public isInCollectionWindow {
        require(underlyingToken.allowance(msg.sender, address(this)) >= amount, "Not enough allowance;");
        
        
        bool success = underlyingToken.transferFrom(msg.sender, address(this), amount);        
        require(success);

        success = underlyingToken.approve(address(AAVE), amount);
        require(success);

        uint256 finalAmount = amount / cRate * 100;

        uint aave_t0 = variableRateToken.balanceOf(address(this));
        AAVE.deposit(address(underlyingToken), finalAmount, address(this), 0);

        uint aave_t1 = variableRateToken.balanceOf(address(this));
        require(aave_t1 - aave_t0 == amount, "Aave deposit failed;");

        uint mintAmount = amount * 10 ** 12;
        JVUSDC.adminMint(msg.sender, mintAmount);      
    }
    
    // @notice Initiate withdraw from AAVE Lending Pool and pay back jvUSDC
    // @param  Amount of USDC to withdraw from AAVE
    function withdraw(uint256 amount) public isInCollectionWindow {
        uint burnAmount = amount * 10 ** 12;
       
        require(JVUSDC.allowance(msg.sender, address(this)) >= amount, "Not enough allowance;");

        bool success = JVUSDC.transferFrom(msg.sender, address(this), burnAmount);
        require(success);
        
        // Burn jvUSDC tokens from this contract
        JVUSDC.adminBurn(address(this), burnAmount);
        
        // Update payout amount
        uint256 finalAmount = cRate * amount / 100;        
        uint256 wa = AAVE.withdraw(address(underlyingToken), finalAmount, address(this));
        require(wa == finalAmount, "Not enough collateral;");

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
        if (msg.sender == address(JVUSDC)) {
            revert("No known function targeted");
        }
    }
}
