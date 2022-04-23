// SPDX-License-Identifier: MIT
pragma solidity =0.8.9;

import "./VoltzUSDC.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


interface IAAVE {
    function deposit(address asset,
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


contract JointVaultStrategy {

    // Conversion Rate
    uint public crate;

    // USDC Token
    IERC20 underlyingToken   = IERC20(0xe22da380ee6B445bb8273C81944ADEB6E8450422);
    
    // aUSDC Token
    IERC20 variableRateToken = IERC20(0xe12AFeC5aa12Cf614678f9bFeeB98cA9Bb95b5B0);

    // Aave Lending Pool
    IAAVE AAVE = IAAVE(0xE0fBa4Fc209b4948668006B2bE61711b7f465bAe);

    // ERC-20 Token
    VoltzUSDC token;
    IERC20 jvUSDC;
    
    constructor() { 
        token = new VoltzUSDC("Joint Voltz USDC", "jvUSDC"); 
        jvUSDC = IERC20(address(token));
        crate = 100; // initialize conversion rate
    }


    /**
   * @dev Deposits USDC the Vault
   * @param amount The amount of tokens getting deposited
   */
    function deposit(uint256 amount) public {
        require(underlyingToken.allowance(msg.sender, address(this)) >= amount, "Not enough allowance;");
        bool success = underlyingToken.transferFrom(msg.sender,address(this), amount);        
        require(success);
        success = underlyingToken.approve(address(AAVE), amount);
        require(success);
        uint256 finalAmount = amount / crate * 100;
        uint aave_t0 = variableRateToken.balanceOf(address(this));
        AAVE.deposit(address(underlyingToken), finalAmount, address(this), 0);
        uint aave_t1 = variableRateToken.balanceOf(address(this));
        require(aave_t1 - aave_t0 == amount, "Aave deposit failed;");
        uint mintamount = amount * 10**12;
        token.adminMint(msg.sender, mintamount);      
    }

    function totalAmountJVUsdc() public view returns (uint256){
        return token.totalSupply();      
    }
    function thisContractBalanceAUsdc() public view returns (uint256){
        return variableRateToken.balanceOf(address(this));      
    }

    function setCRate() public { // restriction needed
        uint tcb = thisContractBalanceAUsdc();
        uint tav = totalAmountJVUsdc();
        crate =  tcb/tav * 100;      
    }

    function withdraw(uint256 amount) public {
        uint burnamount = amount * 10**12;
        require(jvUSDC.allowance(msg.sender, address(this)) >= amount, "Not enough allowance;");
        bool success = jvUSDC.transferFrom(msg.sender, address(this), burnamount);
        require(success);
        token.adminBurn(address(this), burnamount);
        uint256 finalAmount = crate * amount / 100;        
        uint256 wa = AAVE.withdraw(address(underlyingToken), finalAmount, address(this));
        require(wa == finalAmount, "Not enough collateral;");
        success = underlyingToken.transfer(msg.sender, finalAmount);
        require(success);      
    }

    function getback() public {
        bool success = underlyingToken.transfer(msg.sender, underlyingToken.balanceOf(address(this)));
        require(success);
    }

    fallback() external {
        if (msg.sender == address(token)) {
            revert("No known function targeted;");
        }
    }
}
