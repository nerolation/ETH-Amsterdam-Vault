pragma solidity =0.8.9;

import "./interfaces/IPeriphery.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IMarginEngine.sol";
import "./interfaces/IERC20Minimal.sol";
import "./interfaces/fcms/IFCM.sol";
import "./interfaces/rate_oracles/IRateOracle.sol";
import "hardhat/console.sol";

contract FungibleVoltz {
    // Constants
    uint160 MIN_SQRT_RATIO = 2503036416286949174936592462;
    uint160 MAX_SQRT_RATIO = 2507794810551837817144115957740;

    // Token contracts
    IERC20Minimal variableRateToken; // AUSDC
    IERC20Minimal fixedRateToken; // USDC
    IERC20Minimal fungibleToken; // vUSDC

    // Voltz contracts
    IFactory factory;
    IPeriphery periphery;
    IMarginEngine marginEngine;
    IFCM fcm;

    // Logic variables
    CollectionWindow collectionWindow;

    // Structs
    struct CollectionWindow {
        uint256 start; // unix timestamp in seconds
        uint256 end; // unix timestamp in seconds
    }

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

    constructor(
        address _variableRateToken,
        address _fixedRateToken,
        address _fungibleToken,
        address _factory,
        address _fcm,
        address _marginEngine,
        CollectionWindow memory _collectionWindow
    ) {
        // Token contracts
        variableRateToken = IERC20Minimal(_variableRateToken);
        fixedRateToken = IERC20Minimal(_fixedRateToken);
        fungibleToken = IERC20Minimal(_fungibleToken);

        // Voltz contracts
        factory = IFactory(_factory);
        periphery = IPeriphery(factory.periphery());
        fcm = IFCM(_fcm);
        marginEngine = IMarginEngine(_marginEngine);

        // Set initial collection window
        collectionWindow = _collectionWindow; 
    }

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

    function execute() public canExecute {
        variableRateToken.approve(address(fcm), 10 * 1e18);

        fcm.initiateFullyCollateralisedFixedTakerSwap(10 * 1e18, MAX_SQRT_RATIO - 1);
    }

    function settle() public {
        fcm.settleTrader();
    }

    // Returns factor in wei format to handle sub 1 numbers. TODO: Consider floating point arithmetic.
    function conversionFactor() public view returns (uint256) {
        if (fungibleToken.balanceOf(address(this)) == 0) {
            return 0;
        }

        return (
            (variableRateToken.balanceOf(address(this)) + fixedRateToken.balanceOf(address(this))) * (10 ** fungibleToken.decimals())
            / fungibleToken.balanceOf(address(this))
        );
    }

    function deposit() public isInCollectionWindow {
        // TODO
    }

    function withdraw() public isInCollectionWindow {
        // TODO
    }
}
