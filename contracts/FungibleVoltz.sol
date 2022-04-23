pragma solidity =0.8.9;

import "./interfaces/IPeriphery.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IMarginEngine.sol";
import "./interfaces/IERC20Minimal.sol";
import "./interfaces/rate_oracles/IRateOracle.sol";
import "hardhat/console.sol";

contract FungibleVoltz {
    uint160 MIN_SQRT_RATIO = 2503036416286949174936592462;
    uint160 MAX_SQRT_RATIO = 2507794810551837817144115957740;

    IERC20Minimal underlying;
    IFactory factory;
    IPeriphery periphery;
    IMarginEngine marginEngine;

    constructor(address _underlying, address _factory, address _periphery, address _marginEngine) {
        underlying = IERC20Minimal(_underlying);
        factory = IFactory(_factory);
        periphery = IPeriphery(_periphery);
        marginEngine = IMarginEngine(_marginEngine);
    }

    function hasBalance() public view returns (bool) {
        return underlying.balanceOf(address(this)) > 0;
    }

    // function mint() public {
    //     underlying.approve(address(periphery), 10 * 1e18);

    //     console.log(address(periphery));

    //     periphery.mintOrBurn(IPeriphery.MintOrBurnParams({
    //         marginEngine: marginEngine,
    //         tickLower: 0,
    //         tickUpper: 1200,
    //         notional: 10 * 1e18,
    //         isMint: true,
    //         marginDelta: 10 * 1e18
    //     }));
    // }

    function execute() public {
        underlying.approve(address(periphery), 10 * 1e18);
        
        if (periphery.getCurrentTick(marginEngine) < 0) {
            console.log("-", uint24(-periphery.getCurrentTick(marginEngine)));
        } else {
            console.log(uint24(periphery.getCurrentTick(marginEngine)));
        }

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
}
