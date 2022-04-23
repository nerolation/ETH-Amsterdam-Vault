pragma solidity =0.8.9;

import "./interfaces/IPeriphery.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IMarginEngine.sol";
import "./interfaces/IERC20Minimal.sol";
import "./interfaces/fcms/IFCM.sol";
import "./interfaces/rate_oracles/IRateOracle.sol";
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

    IERC20Minimal variableRateToken; // AUSDC
    IERC20Minimal underlyingToken; // USDC
    IERC20Minimal jvUSDC; // jvUSDC

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

    CollectionWindow collectionWindow;
    uint256 termEnd; // unix timestamp in seconds

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
        address _jvUSDC,
        address _factory,
        address _fcm,
        address _marginEngine,
        CollectionWindow memory _collectionWindow
    ) {
        // Token contracts
        variableRateToken = IERC20Minimal(_variableRateToken);
        underlyingToken = IERC20Minimal(_underlyingToken);
        jvUSDC = IERC20Minimal(_jvUSDC);

        // Voltz contracts
        factory = IFactory(_factory);
        periphery = IPeriphery(factory.periphery());
        fcm = IFCM(_fcm);
        marginEngine = IMarginEngine(_marginEngine);

        // Set initial collection window
        collectionWindow = _collectionWindow; 
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
        if (jvUSDC.balanceOf(address(this)) == 0) {
            return 0;
        }

        return (
            (variableRateToken.balanceOf(address(this)) + underlyingToken.balanceOf(address(this))) * 100
            / jvUSDC.balanceOf(address(this))
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

    function deposit() public isInCollectionWindow {
        // TODO
    }

    function withdraw() public isInCollectionWindow {
        // TODO
    }
}
