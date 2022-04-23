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

    constructor(
        address _variableRateToken,
        address _fixedRateToken,
        address _fungibleToken,
        address _factory,
        address _fcm,
        address _marginEngine
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
    }

    function executeMargin() public {
        variableRateToken.approve(address(periphery), 10 * 1e18);
        
        periphery.swap(IPeriphery.SwapPeripheryParams({
            marginEngine: marginEngine,
            isFT: true,
            notional: 10 * 1e18,
            sqrtPriceLimitX96: MAX_SQRT_RATIO - 1,
            tickLower: -6000,
            tickUpper: 0,
            marginDelta: 1 * 1e18
        }));
    }

    function execute() public {
        variableRateToken.approve(address(fcm), 10 * 1e18);

        fcm.initiateFullyCollateralisedFixedTakerSwap(10 * 1e18, MAX_SQRT_RATIO - 1);
    }

    function settle() public {
        fcm.settleTrader();
    }

    function shareValue() public view returns (uint256) {
        return (variableRateToken.balanceOf(address(this)) + fixedRateToken.balanceOf(address(this))) / fungibleToken.balanceOf(address(this));
    }
}
