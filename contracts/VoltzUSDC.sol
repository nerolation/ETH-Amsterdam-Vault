pragma solidity =0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract VoltzUSDC is ERC20, Ownable {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function adminMint(address to, uint amount) external onlyOwner {
        _mint(to, amount);
    }

    function adminBurn(address from, uint amount) external onlyOwner {
        _burn(from, amount);
    }
}
