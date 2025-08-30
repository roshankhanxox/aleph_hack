// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockUSDC
 * @dev A simple mock USDC token for testing remittance contract
 */
contract MockUSDC is ERC20 {
    
    /**
     * @dev Constructor creates mock USDC with 6 decimals (like real USDC)
     */
    constructor() ERC20("Mock USD Coin", "USDC") {
        // Mint 1 million USDC to contract deployer for testing
        _mint(msg.sender, 1000000 * 10**6); // 1M USDC with 6 decimals
    }

    /**
     * @dev Override decimals to match real USDC (6 decimals)
     */
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /**
     * @dev Mint more tokens for testing (anyone can call this)
     * @param _to Address to mint tokens to
     * @param _amount Amount to mint (in smallest units)
     */
    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }

    /**
     * @dev Easy function to get 1000 USDC for testing
     */
    function getFreeUSDC() external {
        _mint(msg.sender, 1000 * 10**6); // 1000 USDC
    }
}