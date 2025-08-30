// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/utils/Nonces.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RemittanceRewards is ERC20, ERC20Burnable, ERC20Pausable, Ownable, ERC20Permit, ERC20Votes {
    
    // Minter role for the SimpleRemittance contract
    mapping(address => bool) public minters;
    
    // Events
    event MinterAdded(address indexed minter);
    event MinterRemoved(address indexed minter);
    
    // Custom errors
    error NotAuthorizedMinter();

    constructor(address recipient, address initialOwner)
        ERC20("RemittanceRewards", "RMR")
        Ownable(initialOwner)
        ERC20Permit("RemittanceRewards")
    {
        _mint(recipient, 1000000 * 10 ** decimals());
    }

    /**
     * @dev Modifier to check if caller is authorized minter
     */
    modifier onlyMinter() {
        if (!minters[msg.sender] && msg.sender != owner()) {
            revert NotAuthorizedMinter();
        }
        _;
    }

    /**
     * @dev Add a minter (typically the SimpleRemittance contract)
     * @param _minter Address to give minting permission
     */
    function addMinter(address _minter) external onlyOwner {
        require(_minter != address(0), "Invalid minter address");
        minters[_minter] = true;
        emit MinterAdded(_minter);
    }

    /**
     * @dev Remove a minter
     * @param _minter Address to remove minting permission
     */
    function removeMinter(address _minter) external onlyOwner {
        minters[_minter] = false;
        emit MinterRemoved(_minter);
    }

    /**
     * @dev Check if address is authorized minter
     * @param _address Address to check
     * @return Whether the address can mint tokens
     */
    function isMinter(address _address) external view returns (bool) {
        return minters[_address] || _address == owner();
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @dev Mint tokens - can be called by owner or authorized minters
     * @param to Address to mint tokens to
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) public onlyMinter {
        _mint(to, amount);
    }

    // The following functions are overrides required by Solidity.

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Pausable, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}