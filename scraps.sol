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

  // function executeMargin() public {
  //     variableRateToken.approve(address(periphery), 10 * 1e18);
  //     
  //     periphery.swap(IPeriphery.SwapPeripheryParams({
  //         marginEngine: marginEngine,
  //         isFT: true,
  //         notional: 10 * 1e18,
  //         sqrtPriceLimitX96: MAX_SQRT_RATIO - 1,
  //         tickLower: -6000,
  //         tickUpper: 0,
  //         marginDelta: 1 * 1e18
  //     }));
  // }
