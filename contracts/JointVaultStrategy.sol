pragma solidity =0.8.9;

import "./voltz/interfaces/IPeriphery.sol";
import "./voltz/interfaces/IFactory.sol";
import "./voltz/interfaces/IMarginEngine.sol";
import "./voltz/interfaces/fcms/IFCM.sol";
import "./voltz/interfaces/IAAVE.sol";
import "./JointVaultUSDC.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract JointVaultStrategy is Ownable {
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
        cRate = 1e18; 
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

    // Returns factor in 5 decimal format to handle sub 1 numbers.
    // TODO: remove hardcoded decimals
    function conversionFactor() internal returns (uint256) {
        require(JVUSDC.totalSupply() != 0, "JVUSDC totalSupply is zero");

        return (
            // twelve decimals for aUSDC / jVUSDC decimal different + 18 from ctoken decimals
            variableRateToken.balanceOf(address(this)) * 10 ** 30
            / JVUSDC.totalSupply()
        );
    }
 
    // @notice Update conversion rate 
    function updateCRate() internal { // restriction needed
        cRate = conversionFactor();
    }

    //
    // Strategy functions
    //

    // @notice Interact with Voltz 
    function execute() public canExecute {
        variableRateToken.approve(address(fcm), variableRateToken.balanceOf(address(this)));

        fcm.initiateFullyCollateralisedFixedTakerSwap(variableRateToken.balanceOf(address(this)), MAX_SQRT_RATIO - 1);

        termEnd = marginEngine.termEndTimestampWad() / 1e18;
    }

    // @notice Update window in which 
    // @param  Amount of USDC to withdraw from AAVE
    function updateCollectionWindow() public {
        collectionWindow.start = termEnd;
        collectionWindow.end = termEnd + 86400; // termEnd + 1 day
    }
    
    // @notice Settle Strategie 
    function settle() public canSettle {
        // Get AUSDC and USDC from Voltz position
        fcm.settleTrader();

        // Convert USDC to AUSDC
        uint256 underlyingTokenBalance = underlyingToken.balanceOf(address(this));

        underlyingToken.approve(address(AAVE), underlyingTokenBalance);
        AAVE.deposit(address(underlyingToken), underlyingTokenBalance, address(this), 0);

        // Update cRate
        updateCRate();

        // Update the collection window
        updateCollectionWindow();
    }

    // TODO: Do not require custodian
    function setMarginEngine(address _marginEngine) public onlyOwner {
        marginEngine = IMarginEngine(_marginEngine);
    }

    //
    // User functions
    //
    
    // @notice Initiate deposit to AAVE Lending Pool and receive jvUSDC
    // @param  Amount of USDC to deposit to AAVE
    // TODO: remove hardcoded decimals
    function deposit(uint256 amount) public isInCollectionWindow {
        underlyingToken.transferFrom(msg.sender, address(this), amount);
 
        // Convert different denominations (6 <- 18)
        uint mintAmount = amount * 1e12;

        // Approve AAve to spend the underlying token
        underlyingToken.approve(address(AAVE), mintAmount);

        // Calculate deposit rate
        uint256 finalAmount = amount / cRate * 1e18;

        // Deposit to Aave
        uint aave_t0 = variableRateToken.balanceOf(address(this));
        AAVE.deposit(address(underlyingToken), amount, address(this), 0);
        uint aave_t1 = variableRateToken.balanceOf(address(this));
        require(aave_t1 - aave_t0 == amount, "Aave deposit failed;");

        JVUSDC.adminMint(msg.sender, mintAmount);      
    }

    // @notice Initiate withdraw from AAVE Lending Pool and pay back jvUSDC
    // @param  Amount of yvUSDC to redeem as USDC
    // TODO: remove hardcoded decimals
    function withdraw(uint256 amount) public isInCollectionWindow {
        // Convert different denominations (6 -> 18)
        uint256 withdrawAmount = cRate * amount / 1e30;

        // Pull jvUSDC tokens from user
        JVUSDC.transferFrom(msg.sender, address(this), amount);

        // Burn jvUSDC tokens from this contract
        JVUSDC.adminBurn(address(this), amount);

        // Update payout amount
        uint256 wa = AAVE.withdraw(address(underlyingToken), withdrawAmount, address(this));
        require(wa == withdrawAmount, "Not enough collateral;");

        // Transfer USDC back to the user
        underlyingToken.transfer(msg.sender, withdrawAmount);
    }

    // @notice Receive this contracts USDC balance
    function contractBalanceUsdc() public view returns (uint256){
        return underlyingToken.balanceOf(address(this));      
    }

    // @notice Receive this contracts aUSDC balance
    function contractBalanceAUsdc() public view returns (uint256){
        return variableRateToken.balanceOf(address(this));      
    }

    // @notice Fallback that ignores calls from jvUSDC
    // @notice Calls from jvUSDC happen when user deposits
    fallback() external {
        if (msg.sender == address(JVUSDC)) {
            revert("No known function targeted");
        }
    }
}
